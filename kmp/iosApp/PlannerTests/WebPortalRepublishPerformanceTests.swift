import XCTest
import Security
@testable import MiGestorKMPMac

/// Rendimiento de `republishPortalBoards` en el hilo principal.
///
/// Escenario con datos INVENTADOS: 6 grupos × 30 alumnos (180), 20 tareas web activas,
/// 3 columnas visibles por grupo y torneos activos. Montar el escenario completo exige un
/// contenedor de Kotlin con base de datos; en su lugar se mide cada tramo síncrono por separado
/// con entradas sintéticas del mismo tamaño (fichero de alumnos, llavero, ficheros de enlaces y
/// bloques de notas/torneos/EF de 180 alumnos). El tiempo de cada tramo es el reloj de pared de
/// la ejecución síncrona en el hilo principal (el XCTest `@MainActor` corre ahí): es el tiempo
/// que el hilo principal queda bloqueado.
@MainActor
final class WebPortalRepublishPerformanceTests: XCTestCase {
    private static let groups = 6
    private static let studentsPerGroup = 30
    private static let tasks = 20
    private static let budgetMs = 16.0
    private static let runs = 7

    private var cleanup: [URL] = []

    override func tearDown() {
        for url in cleanup { try? FileManager.default.removeItem(at: url) }
        cleanup = []
        super.tearDown()
    }

    // MARK: Entradas sintéticas

    private var studentIds: [Int64] { (1...Int64(Self.groups * Self.studentsPerGroup)).map { $0 } }

    private func makeStoreFile() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("rend-portal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        cleanup.append(folder)
        let url = folder.appendingPathComponent("alumnos.json")
        var store = WebPortalStore(fileURL: url, keychainService: "com.migestor.rendimiento-prueba")
        for id in studentIds {
            store.set(WebPortalEntry(portalId: "portal-inventado-\(id)-AAAAAAAAAAAAAAAAAAAAAA", estadoConocido: "activa", invitadoEl: 1_760_000_000_000, ultimaVersion: 1_760_000_000_000 + id), for: id)
        }
        try store.save()
        return url
    }

    private func notasBlock(_ id: Int64) -> [String: Any] {
        let actividades = (1...3).map { n -> [String: Any] in
            ["titulo": "Actividad inventada \(n)", "nivel": "Notable", "nota": 7.5, "comentario": "Comentario de prueba número \(n) para el alumno \(id)"]
        }
        return [
            "provisional": true, "actualizado": "2026-11-21T10:00:00Z",
            "materias": [["grupo": "Grupo \(id / 30)", "materia": "Educación Física", "actividades": actividades, "media": ["valor": 7.4, "nivel": "Notable"]]],
        ]
    }

    private func torneosBlock(_ id: Int64) -> [String: Any] {
        let standings = (1...6).map { ["posicion": $0, "equipo": "Equipo \($0)", "puntos": 12 - $0, "pj": 5, "pg": 3, "pe": 1, "pp": 1] as [String: Any] }
        let rondas = (1...5).map { r in
            ["ronda": r, "partidos": (1...3).map { ["local": "Equipo \($0)", "visitante": "Equipo \($0 + 3)", "marcador": "2-1"] as [String: Any] }] as [String: Any]
        }
        return ["actualizado": "2026-11-21T10:00:00Z", "lista": [["titulo": "Torneo inventado", "estado": "enCurso", "clasificacion": standings, "rondas": rondas, "miEquipo": "Equipo \(id % 6 + 1)"] as [String: Any]]]
    }

    private func peBlocks() -> WebPortalPEBlocks {
        var blocks = WebPortalPEBlocks()
        for id in studentIds {
            blocks.known.insert(id)
            blocks.fisica[id] = ["actualizado": "2026-11-21T10:00:00Z", "lista": (1...4).map { ["prueba": "Prueba \($0)", "valores": [10, 11, 12, 13], "unidad": "rep"] as [String: Any] }]
            blocks.asistencia[id] = ["actualizado": "2026-11-21T10:00:00Z", "porcentaje": 92, "faltas": 3]
        }
        return blocks
    }

    private func gradeBlocks() -> WebPortalGradeBlocks {
        var blocks = WebPortalGradeBlocks()
        for id in studentIds { blocks.known.insert(id); blocks.notas[id] = notasBlock(id) }
        return blocks
    }

    private func tournamentBlocks() -> WebPortalTournamentBlocks {
        var blocks = WebPortalTournamentBlocks()
        for id in studentIds { blocks.known.insert(id); blocks.torneos[id] = torneosBlock(id) }
        return blocks
    }

    /// 20 tareas, cada una con su `enlaces-alumnado.txt` de 30 alumnos.
    private func makeTasks() throws -> [(id: String, snapshot: WebSubmissionSnapshot)] {
        try (0..<Self.tasks).map { index in
            let formId = "zz-rendimiento-\(UUID().uuidString)"
            let folder = try XCTUnwrap(WebSubmissionPrivateLinksStore.folderURL(for: formId))
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            cleanup.append(folder)
            let group = index % Self.groups
            var aliases: [String: Int64] = [:]
            var names: [Int64: String] = [:]
            var lines = ["Formulario inventado \(index)", "Formulario: \(formId)", ""]
            for n in 0..<Self.studentsPerGroup {
                let studentId = Int64(group * Self.studentsPerGroup + n + 1)
                let alias = "alias-\(index)-\(n)"
                aliases[alias] = studentId
                names[studentId] = "Alumno Inventado \(studentId)"
                lines.append("Alumno Inventado \(studentId)  https://entregas.example/#f=\(formId)&a=\(alias)")
            }
            try Data(lines.joined(separator: "\n").utf8).write(to: folder.appendingPathComponent("enlaces-alumnado.txt"), options: [.atomic])
            let snapshot = WebSubmissionSnapshot(
                formInstanceId: formId, classId: Int64(group + 1), columnId: "col", privateKeyRef: "", revoked: false,
                expiresAtEpochMs: 4_000_000_000_000, title: "Tarea \(index)", studentIdByAlias: aliases,
                itemIdByWebItemId: [:], studentNames: names, importedAtBySubmissionId: [:], roster: []
            )
            return (formId, snapshot)
        }
    }

    // MARK: Medida

    private struct Sample { let name: String; let medianMs: Double; let maxMs: Double }

    private func sample(_ name: String, _ body: () -> Void) -> Sample {
        body() // calentamiento (cachés de disco y de formatos)
        var times: [Double] = []
        for _ in 0..<Self.runs {
            let start = DispatchTime.now()
            body()
            times.append(PerfLog.elapsedMs(since: start))
        }
        times.sort()
        return Sample(name: name, medianMs: times[times.count / 2], maxMs: times.last ?? 0)
    }

    private func report(_ samples: [Sample], title: String) {
        var lines = ["TABLA \(title) (ms en el hilo principal, \(Self.runs) pasadas)", "tramo | mediana | máximo"]
        for s in samples { lines.append("\(s.name) | \(String(format: "%.2f", s.medianMs)) | \(String(format: "%.2f", s.maxMs))") }
        print(lines.joined(separator: "\n"))
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: Pruebas

    func testCadaTramoSincronoCabeEnUnFotograma() throws {
        let storeURL = try makeStoreFile()
        let tasks = try makeTasks()
        let grades = gradeBlocks()
        let tournaments = tournamentBlocks()
        let pe = peBlocks()
        let gradeSummary = WebPortalGradesSummary()
        let tournamentSummary = WebPortalTournamentsSummary()
        let peSummary = WebPortalPESummary()

        // Llavero: un elemento de prueba propio; nunca se toca la clave real de la cuenta.
        let tokenName = "rendimiento-prueba-\(UUID().uuidString)"
        XCTAssertTrue(WebSubmissionInbox.saveToken(WebSubmissionInbox.randomToken(), name: tokenName))
        defer {
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.migestor.buzon", kSecAttrAccount as String: tokenName] as CFDictionary)
        }

        var samples: [Sample] = []
        samples.append(sample("almacén de alumnos (JSON, 180)") {
            _ = WebPortalStore(fileURL: storeURL, keychainService: "com.migestor.rendimiento-prueba")
        })
        samples.append(sample("llavero (clave de cuenta)") {
            _ = WebSubmissionInbox.loadToken(name: tokenName)
        })
        samples.append(sample("enlaces: 20 tareas × 30 alumnos") {
            for task in tasks {
                let links = WebPortalPublisher.readTaskLinks(formInstanceId: task.id, snapshot: task.snapshot, students: [])
                XCTAssertEqual(links.count, Self.studentsPerGroup)
            }
        })
        samples.append(sample("enlaces: una tarea (la peor)") {
            _ = WebPortalPublisher.readTaskLinks(formInstanceId: tasks[0].id, snapshot: tasks[0].snapshot, students: [])
        })
        samples.append(sample("huellas notas+torneos+EF (180)") {
            let changed = WebPortalPublisher.changedStudents(
                studentIds: self.studentIds, gradeBlocks: grades, gradeSummary: gradeSummary,
                tournamentBlocks: tournaments, tournamentSummary: tournamentSummary, peBlocks: pe, peSummary: peSummary
            )
            XCTAssertEqual(changed.count, self.studentIds.count)
        })
        samples.append(sample("registrar huellas tras publicar (180)") {
            var summary = WebPortalGradesSummary()
            var tSummary = WebPortalTournamentsSummary()
            let pSummary = WebPortalPESummary()
            for id in self.studentIds {
                summary.record(studentId: id, notas: grades.notas[id])
                tSummary.record(studentId: id, torneos: tournaments.torneos[id])
                pSummary.record(studentId: id, fisica: pe.fisica[id], asistencia: pe.asistencia[id], pasaporte: pe.pasaporte[id])
            }
        })
        report(samples, title: "coste síncrono de cada tramo")
        // Las huellas (comprobar y registrar) cuestan más de un fotograma: por eso van en segundo
        // plano y su límite se comprueba abajo con el latido del hilo principal.
        for s in samples where !s.name.contains("huellas") {
            XCTAssertLessThanOrEqual(s.medianMs, Self.budgetMs, "\(s.name) supera un fotograma")
        }
    }

    /// Latido: un hilo aparte pide cada ms al hilo principal que responda y anota lo que tarda.
    private final class Heartbeat {
        private(set) var maxLatencyMs = 0.0
        private var running = true
        private let lock = NSLock()
        private var thread: Thread?

        func start() {
            running = true
            maxLatencyMs = 0
            let t = Thread { [self] in
                while true {
                    lock.lock(); let go = running; lock.unlock()
                    if !go { return }
                    let start = DispatchTime.now()
                    let answered = DispatchSemaphore(value: 0)
                    DispatchQueue.main.async { answered.signal() }
                    answered.wait()
                    let ms = PerfLog.elapsedMs(since: start)
                    lock.lock(); maxLatencyMs = max(maxLatencyMs, ms); lock.unlock()
                    Thread.sleep(forTimeInterval: 0.001)
                }
            }
            thread = t
            t.start()
        }

        func stop() -> Double {
            lock.lock(); running = false; lock.unlock()
            Thread.sleep(forTimeInterval: 0.05)
            lock.lock(); defer { lock.unlock() }
            return maxLatencyMs
        }
    }

    func testLasHuellasEnSegundoPlanoNoBloqueanElHiloPrincipal() async throws {
        let grades = gradeBlocks()
        let tournaments = tournamentBlocks()
        let pe = peBlocks()
        let ids = studentIds
        let heartbeat = Heartbeat()

        // Control del instrumento: hecho en el hilo principal, el latido tiene que ver el bloqueo.
        heartbeat.start()
        try await Task.sleep(nanoseconds: 20_000_000)
        _ = WebPortalPublisher.changedStudents(
            studentIds: ids, gradeBlocks: grades, gradeSummary: WebPortalGradesSummary(),
            tournamentBlocks: tournaments, tournamentSummary: WebPortalTournamentsSummary(), peBlocks: pe, peSummary: WebPortalPESummary()
        )
        try await Task.sleep(nanoseconds: 20_000_000)
        let blockedMs = heartbeat.stop()

        // Igual que `republishPortalBoards`: comprobar y registrar en `Task.detached`.
        var worst = 0.0
        for _ in 0..<Self.runs {
            heartbeat.start()
            try await Task.sleep(nanoseconds: 20_000_000)
            let changed = await Task.detached(priority: .utility) {
                WebPortalPublisher.changedStudents(
                    studentIds: ids, gradeBlocks: grades, gradeSummary: WebPortalGradesSummary(),
                    tournamentBlocks: tournaments, tournamentSummary: WebPortalTournamentsSummary(), peBlocks: pe, peSummary: WebPortalPESummary()
                )
            }.value
            XCTAssertEqual(changed.count, ids.count)
            let recorded = await Task.detached(priority: .utility) { () -> (WebPortalGradesSummary, WebPortalTournamentsSummary) in
                var g = WebPortalGradesSummary()
                var t = WebPortalTournamentsSummary()
                WebPortalPublisher.recordPublished(
                    studentIds: ids, gradeBlocks: grades, gradeSummary: &g,
                    tournamentBlocks: tournaments, tournamentSummary: &t, peBlocks: pe, peSummary: WebPortalPESummary()
                )
                return (g, t)
            }.value
            // Lo registrado debe coincidir con lo que `hasChanged` espera: nada vuelve a cambiar.
            XCTAssertFalse(recorded.0.hasChanged(studentId: ids[0], notas: grades.notas[ids[0]]))
            XCTAssertFalse(recorded.1.hasChanged(studentId: ids[0], torneos: tournaments.torneos[ids[0]]))
            worst = max(worst, heartbeat.stop())
        }
        let text = "TABLA hilo principal durante huellas (latido, ms)\ncontrol en hilo principal | \(String(format: "%.2f", blockedMs))\nen segundo plano, peor de \(Self.runs) | \(String(format: "%.2f", worst))"
        print(text)
        add({ let a = XCTAttachment(string: text); a.lifetime = .keepAlways; return a }())
        XCTAssertGreaterThan(blockedMs, Self.budgetMs, "el latido debe detectar el bloqueo del control")
        XCTAssertLessThanOrEqual(worst, Self.budgetMs, "el hilo principal quedó bloqueado más de un fotograma")
    }
}
