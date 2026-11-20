import Foundation
import OSLog
import MiGestorKit

/// Construye y publica el tablón «Para hacer» de cada alumno (ticket 4.4).
///
/// El tablón viaja cifrado con `K_tablon`: el servidor solo ve un sobre, su tamaño
/// y cuándo cambia. Aquí se decide qué entra:
///  - **pendientes**: formularios activos del alumno que aún no se han importado.
///  - **hechos**: los ya importados. Lo decide la app; el móvil no marca nada.
///  - El pasaporte (varias paradas) nunca pasa a «hecho»: queda pendiente hasta que caduca,
///    aunque ya tenga envíos.

/// Un formulario visto desde un alumno.
struct WebPortalFormEntry: Equatable {
    let title: String
    /// Grupo, p. ej. «2º ESO B».
    let context: String
    /// `self`, `peer` o `passport`.
    let mode: String
    let expiresAt: Date
    /// Enlace personal de siempre (`#f=…&a=…`). Sin https no se publica.
    let url: String?
    let done: Bool
}

enum WebPortalPublisher {
    static let log = Logger(subsystem: "com.migestor.entregas-web", category: "portal")
    /// Tope del servidor por tablón.
    static let maxBoardBytes = 256 * 1024
    static let batchSize = 50

    // MARK: - Contenido

    static func boardType(mode: String) -> String {
        switch mode {
        case "peer": return "coevaluacion"
        case "passport": return "pasaporte"
        default: return "autoevaluacion"
        }
    }

    /// Apodo estable derivado del `portalId`. No es el nombre del alumno.
    static func alias(for portalId: String) -> String {
        let animals = ["tigre", "lince", "nutria", "halcon", "delfin", "zorro", "lobo", "oso"]
        let colors = ["azul", "verde", "rojo", "naranja", "violeta", "dorado", "plata", "turquesa"]
        let bytes = Array(WebPortalCrypto.fromBase64URL(portalId) ?? Data(portalId.utf8))
        let a = bytes.first.map { Int($0) } ?? 0
        let b = bytes.dropFirst().first.map { Int($0) } ?? 0
        return "\(animals[a % animals.count])_\(colors[b % colors.count])"
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// JSON del tablón v1. Las claves desconocidas las ignora la web.
    /// `notas` (fase 2), `torneos` (fase 3B), `fisica` y `asistencia` (fase 3C) son opcionales.
    static func buildBoard(
        portalId: String,
        forms: [WebPortalFormEntry],
        notas: [String: Any]? = nil,
        torneos: [String: Any]? = nil,
        fisica: [String: Any]? = nil,
        asistencia: [String: Any]? = nil,
        now: Date = Date()
    ) throws -> Data {
        let pending = forms
            .filter { ($0.mode == "passport" || !$0.done) && $0.expiresAt > now }
            .compactMap { form -> [String: Any]? in
                guard let url = form.url, url.hasPrefix("https://") else { return nil }
                return [
                    "titulo": form.title,
                    "contexto": form.context,
                    "tipo": boardType(mode: form.mode),
                    "plazo": isoString(form.expiresAt),
                    "url": url,
                ]
            }
            .sorted { ($0["plazo"] as? String ?? "") < ($1["plazo"] as? String ?? "") }
        let done = forms
            .filter { $0.done && $0.mode != "passport" }
            .map { ["titulo": $0.title] }
        var board: [String: Any] = [
            "schemaVersion": 1,
            "alias": alias(for: portalId),
            "actualizado": isoString(now),
            "pendientes": pending,
            "hechos": done,
        ]
        if let notas { board["notas"] = notas }
        if let torneos { board["torneos"] = torneos }
        if let fisica { board["fisica"] = fisica }
        if let asistencia { board["asistencia"] = asistencia }
        return try JSONSerialization.data(withJSONObject: board, options: [.sortedKeys])
    }

    /// Siempre mayor que la anterior, aunque el reloj vaya atrasado.
    static func nextVersion(last: Int64?, now: Date) -> Int64 {
        max(Int64(now.timeIntervalSince1970 * 1000), (last ?? 0) + 1)
    }

    // MARK: - Publicar

    struct Input {
        let studentId: Int64
        let forms: [WebPortalFormEntry]
        /// Bloque «Mis notas» ya filtrado por los interruptores. `nil`: sin notas.
        var notas: [String: Any]?
        /// Bloque «Torneos» ya filtrado por los interruptores. `nil`: sin torneos.
        var torneos: [String: Any]?
        /// Bloque «Mi EF» (pruebas físicas) filtrado por los interruptores.
        var fisica: [String: Any]? = nil
        /// Bloque «Asistencia» filtrado por el interruptor.
        var asistencia: [String: Any]? = nil
    }

    struct Outcome: Equatable {
        var published = 0
        var failed = 0
        /// Alumnos cuyo tablón aceptó el servidor.
        var publishedStudentIds: [Int64] = []
        /// El servidor ya no conoce a estos alumnos (cuenta cerrada desde otro sitio).
        var unknownStudentIds: [Int64] = []
        /// Tablones que pasan del tope de tamaño.
        var tooLargeStudentIds: [Int64] = []

        /// Fallos que merece la pena reintentar: ni demasiado grande ni cuenta cerrada.
        var retryableFailures: Int { max(0, failed - tooLargeStudentIds.count - unknownStudentIds.count) }
    }

    /// Cifra y sube los tablones. Mezcla grupos en el mismo lote. Un alumno sin
    /// entrada local o sin `K_tablon` en este dispositivo se salta.
    @discardableResult
    static func publish(
        inputs: [Input],
        storeURL: URL,
        keychainService: String = WebPortalStore.defaultKeychainService,
        client: WebPortalClient,
        accountKey: String,
        now: Date = Date()
    ) async -> Outcome {
        var outcome = Outcome()
        let store = WebPortalStore(fileURL: storeURL, keychainService: keychainService)

        // Quien tiene una llave pendiente (reinvitado con cuenta activa) pregunta antes al
        // servidor: si ya canjeó, la pendiente pasa a ser la llave; si caducó, se descarta.
        let pendingPortalIds = store.entries.values.map(\.portalId).filter { store.pendingKey(portalId: $0) != nil }
        if !pendingPortalIds.isEmpty,
           let states = try? await client.state(portalIds: pendingPortalIds, accountKey: accountKey) {
            WebPortalInviter.resolvePending(states: states, storeURL: storeURL, keychainService: keychainService)
        }

        var boards: [(studentId: Int64, board: WebPortalClient.Board)] = []
        for input in inputs {
            guard let entry = store[input.studentId],
                  let key = store.tablonKey(portalId: entry.portalId) else { continue }
            let version = nextVersion(last: entry.ultimaVersion, now: now)
            do {
                let json = try buildBoard(
                    portalId: entry.portalId,
                    forms: input.forms,
                    notas: input.notas,
                    torneos: input.torneos,
                    fisica: input.fisica,
                    asistencia: input.asistencia,
                    now: now
                )
                guard json.count <= maxBoardBytes else {
                    outcome.failed += 1
                    outcome.tooLargeStudentIds.append(input.studentId)
                    continue
                }
                let sobre = try WebPortalCrypto.seal(json, key: key, context: .tablon(portalId: entry.portalId, version: version))
                boards.append((input.studentId, WebPortalClient.Board(portalId: entry.portalId, version: version, sobre: sobre)))
            } catch {
                outcome.failed += 1
            }
        }

        for start in stride(from: 0, to: boards.count, by: batchSize) {
            let batch = Array(boards[start..<min(start + batchSize, boards.count)])
            do {
                let results = try await client.publish(batch.map(\.board), accountKey: accountKey)
                var accepted: [Int64: Int64] = [:]
                for item in batch {
                    guard let result = results.first(where: { $0.portalId == item.board.portalId }) else {
                        outcome.failed += 1
                        continue
                    }
                    if result.ok {
                        accepted[item.studentId] = item.board.version
                        outcome.published += 1
                        outcome.publishedStudentIds.append(item.studentId)
                    } else {
                        outcome.failed += 1
                        if result.reason == "desconocido" { outcome.unknownStudentIds.append(item.studentId) }
                    }
                }
                _ = try? WebPortalStore.mutate(fileURL: storeURL, keychainService: keychainService) { store in
                    for (studentId, version) in accepted {
                        guard var entry = store[studentId] else { continue }
                        entry.ultimaVersion = version
                        store.set(entry, for: studentId)
                    }
                }
            } catch {
                outcome.failed += batch.count
                log.error("Publicar tablones: \(error.localizedDescription, privacy: .public)")
            }
        }
        return outcome
    }
}

/// Resultado de una publicación de «Mis notas» para decidir si se reintenta.
struct WebPortalGradesPublishStatus: Equatable {
    /// Algo falló y tiene sentido volver a intentarlo (red, servidor, grupo sin leer).
    var retry = false
    /// Algún tablón pasa del tope de 256 KB: no se reintenta, se avisa en la hoja.
    var tooLarge = false
}

// MARK: - Cola

/// Las publicaciones en segundo plano van de una en una: dos a la vez se pisarían
/// la versión del tablón.
@MainActor
final class WebPortalPublishQueue {
    static let shared = WebPortalPublishQueue()
    private var tail: Task<Void, Never>?

    func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await work()
        }
    }
}

// MARK: - Enganche con el puente

extension KmpBridge {
    /// Una sola llamada desde publicar e importar. No bloquea ni lanza: sin cuentas de
    /// portal, o sin buzón en este dispositivo, no hace nada.
    /// `formInstanceIds == nil` republica todos los tablones.
    func schedulePortalRepublish(formInstanceIds: Set<String>?) {
        guard let store = WebPortalStore.standard(), !store.entries.isEmpty else { return }
        WebPortalPublishQueue.shared.enqueue { [weak self] in
            await self?.republishPortalBoards(formInstanceIds: formInstanceIds)
        }
    }

    /// `gradeClassIds`: grupos cuyas notas han cambiado (se suman a los que tienen columnas
    /// encendidas, esperan publicación o ya publicaron notas). Solo se suben los alumnos cuyo
    /// bloque `notas` cambió de verdad.
    /// `onlyGrades`: publicación solo por notas. Los pendientes de cada alumno afectado se
    /// calculan con todas sus instancias, de cualquier grupo.
    /// Un grupo que no se pudo leer publica a su alumnado sin notas (apagar siempre retira).
    @discardableResult
    func republishPortalBoards(
        formInstanceIds: Set<String>?,
        gradeClassIds: Set<Int64> = [],
        tournamentClassIds: Set<Int64> = [],
        peClassIds: Set<Int64> = [],
        onlyGrades: Bool = false,
        onlyDynamicBlocks: Bool = false
    ) async -> WebPortalGradesPublishStatus {
        var status = WebPortalGradesPublishStatus()
        guard let store = WebPortalStore.standard(),
              !store.entries.isEmpty,
              let accountKey = WebSubmissionInbox.accountKey else { return status }
        let baseURL = UserDefaults.standard.string(forKey: "webSubmissions.baseURL") ?? "https://projectosef.alwaysdata.net"
        let ahora = Date()
        let ahoraMs = Int64(ahora.timeIntervalSince1970 * 1000)

        guard let instancias = try? await container.webSubmissionsRepository.listAllFormInstances() else {
            status.retry = true
            return status
        }

        // Notas, torneos y EF vigentes (lectura suspend en `@MainActor`; cálculos en segundo plano).
        let gradeBlocks = await portalGradeBlocks(extraClassIds: gradeClassIds)
        let tournamentBlocks = await portalTournamentBlocks(extraClassIds: tournamentClassIds)
        let peBlocks = await portalPEBlocks(extraClassIds: peClassIds)
        let watcher = WebPortalGradesWatcher.shared
        let tournamentWatcher = WebPortalTournamentsWatcher.shared
        let peWatcher = WebPortalPEWatcher.shared
        func notas(for studentId: Int64) -> [String: Any]? { gradeBlocks.notas(for: studentId) }
        func torneos(for studentId: Int64) -> [String: Any]? { tournamentBlocks.torneos(for: studentId) }
        func fisica(for studentId: Int64) -> [String: Any]? { peBlocks.fisica(for: studentId) }
        func asistencia(for studentId: Int64) -> [String: Any]? { peBlocks.asistencia(for: studentId) }

        var dynamicTargets = Set<Int64>()
        for (studentId, _) in store.entries {
            if gradeBlocks.known.contains(studentId),
               watcher.summary.hasChanged(studentId: studentId, notas: gradeBlocks.notas[studentId]) {
                dynamicTargets.insert(studentId)
            }
            if tournamentBlocks.known.contains(studentId),
               tournamentWatcher.summary.hasChanged(studentId: studentId, torneos: tournamentBlocks.torneos[studentId]) {
                dynamicTargets.insert(studentId)
            }
            if peBlocks.known.contains(studentId),
               peWatcher.summary.hasChanged(studentId: studentId, fisica: peBlocks.fisica[studentId], asistencia: peBlocks.asistencia[studentId]) {
                dynamicTargets.insert(studentId)
            }
        }

        let skipUnrelatedForms = onlyGrades || onlyDynamicBlocks
        var formsByStudent: [Int64: [WebPortalFormEntry]] = [:]
        var affected = Set<Int64>()
        for instancia in instancias where !instancia.revoked && !instancia.archived && instancia.expiresAtEpochMs > ahoraMs {
            let alumnado = (try? await container.classesRepository.listStudentsInClass(classId: instancia.classId)) ?? []
            if skipUnrelatedForms, Set(alumnado.map(\.id)).isDisjoint(with: dynamicTargets) { continue }
            guard let snapshot = await loadWebSubmissionSnapshot(formInstanceId: instancia.formInstanceId) else { continue }
            let links = WebSubmissionPrivateLinksStore.readLinks(
                formInstanceId: instancia.formInstanceId,
                snapshot: snapshot,
                students: alumnado
            )
            let ledger = (try? await container.webSubmissionsRepository.listLedgerForForm(formInstanceId: instancia.formInstanceId)) ?? []
            let doneStudents = Set(ledger.filter { $0.status == "IMPORTED" }.compactMap { entry in entry.alias.flatMap { snapshot.studentIdByAlias[$0] } })
            let groupName = classes.first(where: { $0.id == instancia.classId })?.name ?? ""
            for link in links {
                formsByStudent[link.studentId, default: []].append(WebPortalFormEntry(
                    title: instancia.title,
                    context: groupName,
                    mode: instancia.mode,
                    expiresAt: Date(timeIntervalSince1970: Double(instancia.expiresAtEpochMs) / 1000),
                    url: link.url.absoluteString,
                    done: doneStudents.contains(link.studentId)
                ))
                if formInstanceIds?.contains(instancia.formInstanceId) == true { affected.insert(link.studentId) }
            }
        }

        var targets = formInstanceIds == nil ? Set(store.entries.keys) : affected.intersection(store.entries.keys)
        targets.formUnion(dynamicTargets)
        guard let storeURL = WebPortalStore.standard()?.fileURL else { return status }
        let outcome = await WebPortalPublisher.publish(
            inputs: targets.sorted().map {
                WebPortalPublisher.Input(
                    studentId: $0,
                    forms: formsByStudent[$0] ?? [],
                    notas: notas(for: $0),
                    torneos: torneos(for: $0),
                    fisica: fisica(for: $0),
                    asistencia: asistencia(for: $0)
                )
            },
            storeURL: storeURL,
            client: WebPortalClient(url: WebPortalClient.url(baseURL: baseURL)),
            accountKey: accountKey,
            now: ahora
        )
        for studentId in outcome.publishedStudentIds {
            watcher.summary.record(studentId: studentId, notas: notas(for: studentId))
            tournamentWatcher.summary.record(studentId: studentId, torneos: torneos(for: studentId))
            peWatcher.summary.record(studentId: studentId, fisica: fisica(for: studentId), asistencia: asistencia(for: studentId))
        }
        if outcome.published + outcome.failed > 0 {
            WebPortalPublisher.log.notice("Portal: \(outcome.published) tablones publicados, \(outcome.failed) con error")
        }
        // Demasiado grande y alumnos cerrados no se arreglan reintentando.
        status.retry = outcome.retryableFailures > 0 || !gradeBlocks.failedClassIds.isEmpty || !tournamentBlocks.failedClassIds.isEmpty || !peBlocks.failedClassIds.isEmpty
        status.tooLarge = !outcome.tooLargeStudentIds.isEmpty
        watcher.updatePublishedState(
            withNotes: gradeBlocks.classIdsWithNotes,
            readClassIds: gradeBlocks.readClassIds,
            complete: !status.retry && !status.tooLarge
        )
        tournamentWatcher.updatePublishedState(
            withTournaments: tournamentBlocks.classIdsWithTournaments,
            readClassIds: tournamentBlocks.readClassIds,
            complete: !status.retry && !status.tooLarge
        )
        peWatcher.updatePublishedState(
            withPE: peBlocks.classIdsWithPE,
            readClassIds: peBlocks.readClassIds,
            complete: !status.retry && !status.tooLarge
        )
        return status
    }
}
