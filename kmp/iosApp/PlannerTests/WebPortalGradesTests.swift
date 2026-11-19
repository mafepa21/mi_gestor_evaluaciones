import Foundation
import XCTest
import MiGestorKit
@testable import MiGestorKMPMac

/// Portal fase 2, «Mis notas»: filtro de columnas, media, JSON 4.1, cola de 10 minutos,
/// resumen sin duplicados y ajustes locales.
@MainActor
final class WebPortalGradesTests: XCTestCase {

    // MARK: Ayudas para construir el Cuaderno

    private var utc: Foundation.TimeZone { Foundation.TimeZone(identifier: "UTC")! }
    private var trace: AuditTrace {
        let now = Instant.companion.fromEpochMilliseconds(epochMilliseconds: 0)
        return AuditTrace(authorUserId: nil, createdAt: now, updatedAt: now, associatedGroupId: nil, deviceId: nil, syncVersion: 0)
    }

    private func column(
        id: String,
        title: String,
        evaluationId: Int64,
        weight: Double = 1,
        type: NotebookColumnType = .numeric,
        instrument: NotebookInstrumentKind = .task,
        tabIds: [String] = ["t1"],
        shared: Bool = false,
        counts: Bool = true,
        hidden: Bool = false,
        dateMs: Int64? = nil
    ) -> NotebookColumnDefinition {
        NotebookColumnDefinition(
            id: id, title: title, type: type, categoryKind: .evaluation, instrumentKind: instrument,
            inputKind: .numeric010, evaluationId: KotlinLong(value: evaluationId), rubricId: nil, formula: nil,
            weight: weight, dateEpochMs: dateMs.map { KotlinLong(value: $0) }, unitOrSituation: nil,
            competencyCriteriaIds: [], scaleKind: .tenPoint, tabIds: tabIds, sessions: [], sharedAcrossTabs: shared,
            colorHex: nil, iconName: nil, order: 0, widthDp: 120, categoryId: nil, ordinalLevels: [],
            availableIcons: [], countsTowardAverage: counts, isPinned: false, isHidden: hidden,
            visibility: hidden ? .hidden : .visible, isLocked: false, isTemplate: false,
            emptyCellPolicy: .excludeFromAverage, trace: trace
        )
    }

    private func row(student id: Int64, grades: [Int64: Double]) -> NotebookRow {
        let student = Student(
            id: id, firstName: "Alumno\(id)", lastName: "Prueba", email: nil, photoPath: nil, isInjured: false,
            sex: .unspecified, sexSource: .unknown, birthDate: nil, trace: trace
        )
        return NotebookRow(
            student: student,
            cells: grades.sorted { $0.key < $1.key }.map { NotebookCell(evaluationId: $0.key, value: KotlinDouble(value: $0.value)) },
            weightedAverage: nil, averageExplanation: nil, persistedCells: [], persistedGrades: []
        )
    }

    private func sheet(tabs: [String], columns: [NotebookColumnDefinition], rows: [NotebookRow]) -> NotebookSheet {
        NotebookSheet(
            classId: 7,
            tabs: tabs.map { NotebookTab(id: $0, title: $0, description: nil, order: 0, parentTabId: nil, fixedColumnWidth: nil, trace: trace) },
            columns: columns, columnCategories: [], rows: rows, workGroups: [], workGroupMembers: [], insights: []
        )
    }

    private func reports(_ scope: WebPortalGrades.Scope) -> [StudentGradeReport] {
        // Lo mismo que hace «Enviar notas al alumnado» con las columnas y filas de la pestaña activa.
        BuildStudentGradeReportsUseCase().build(
            columns: scope.allColumns, rows: scope.rows,
            rubricsByColumn: [:], assessmentsByColumn: [:], criterionCodes: [:]
        )
    }

    private func allOn(_ columns: [NotebookColumnDefinition], media: Bool = false) -> WebPortalGroupGradeSettings {
        var settings = WebPortalGroupGradeSettings()
        settings.media = media
        for column in columns { settings.columnas[column.id] = true }
        return settings
    }

    private func block(_ scope: WebPortalGrades.Scope, settings: WebPortalGroupGradeSettings, studentIndex: Int = 0) -> [String: Any]? {
        let context = WebPortalGrades.context(classId: 7, groupName: "2º ESO B", subject: "Educación Física", scope: scope)
        return WebPortalGrades.notasBlock(report: reports(scope)[studentIndex], context: context, settings: settings, now: Date(timeIntervalSince1970: 1_763_577_600), timeZone: utc)
    }

    private func titles(_ block: [String: Any]?) -> [String] {
        let materias = block?["materias"] as? [[String: Any]] ?? []
        return materias.flatMap { ($0["actividades"] as? [[String: Any]] ?? []).compactMap { $0["titulo"] as? String } }
    }

    // MARK: Filtro de columnas

    func testOcultasQueNoCuentanYApagadasNuncaSalen() {
        let visible = column(id: "a", title: "Visible encendida", evaluationId: 1, weight: 2)
        let apagada = column(id: "b", title: "Cuenta pero apagada", evaluationId: 2)
        let oculta = column(id: "c", title: "Oculta encendida", evaluationId: 3, hidden: true)
        let noCuenta = column(id: "d", title: "No cuenta encendida", evaluationId: 4, counts: false)
        let texto = column(id: "e", title: "Texto encendida", evaluationId: 5, type: .text)
        let columns = [visible, apagada, oculta, noCuenta, texto]
        let data = sheet(tabs: ["t1"], columns: columns.map { $0 }, rows: [row(student: 1, grades: [1: 8, 2: 6, 3: 9, 4: 3, 5: 4])])
        let scope = WebPortalGrades.scope(sheet: data, preferredTabId: nil)

        var settings = allOn(columns)
        settings.columnas["b"] = false

        XCTAssertEqual(titles(block(scope, settings: settings)), ["Visible encendida"])

        // La lista de la hoja tampoco ofrece la oculta ni la que no cuenta.
        let overview = WebPortalGrades.overview(classId: 7, scope: scope)
        XCTAssertEqual(overview.columns.map(\.id), ["a", "b"])
    }

    func testTodoApagadoDeEntradaNoPublicaNada() {
        let col = column(id: "a", title: "Nota", evaluationId: 1)
        let scope = WebPortalGrades.scope(sheet: sheet(tabs: ["t1"], columns: [col], rows: [row(student: 1, grades: [1: 8])]), preferredTabId: nil)

        XCTAssertNil(block(scope, settings: WebPortalGroupGradeSettings()))
        XCTAssertFalse(WebPortalGroupGradeSettings().hasActiveColumns)
    }

    // MARK: Media

    func testMediaIgualALaDelPDFParaLaMismaPestana() throws {
        let enT1 = column(id: "a", title: "Solo en t1", evaluationId: 1, weight: 3, tabIds: ["t1"])
        let enT2 = column(id: "b", title: "Solo en t2", evaluationId: 2, weight: 1, tabIds: ["t2"])
        let compartida = column(id: "s", title: "Compartida", evaluationId: 3, weight: 1, tabIds: [], shared: true)
        let columns = [enT1, enT2, compartida]
        let data = sheet(tabs: ["t1", "t2"], columns: columns, rows: [row(student: 1, grades: [1: 8, 2: 2, 3: 4])])
        let settings = allOn(columns, media: true)

        // t1: (8*3 + 4*1) / 4 = 7.0. t2: (2*1 + 4*1) / 2 = 3.0.
        for (tab, expected) in [("t1", 7.0), ("t2", 3.0)] {
            let scope = WebPortalGrades.scope(sheet: data, preferredTabId: tab)
            let pdf = try XCTUnwrap(reports(scope)[0].finalGrade).doubleValue
            let materia = try XCTUnwrap((block(scope, settings: settings)?["materias"] as? [[String: Any]])?.first)
            let media = try XCTUnwrap(materia["media"] as? [String: Any])
            XCTAssertEqual(try XCTUnwrap(media["valor"] as? Double), pdf, accuracy: 0.000_001, "portal y PDF, pestaña \(tab)")
            XCTAssertEqual(pdf, expected, accuracy: 0.000_001, "pestaña \(tab)")
        }
        // Sin pestaña recordada, la primera. Una desconocida también cae en la primera.
        XCTAssertEqual(WebPortalGrades.scope(sheet: data, preferredTabId: nil).tabId, "t1")
        XCTAssertEqual(WebPortalGrades.scope(sheet: data, preferredTabId: "borrada").tabId, "t1")
    }

    func testMediaSoloConInterruptor() throws {
        let col = column(id: "a", title: "Nota", evaluationId: 1)
        let scope = WebPortalGrades.scope(sheet: sheet(tabs: ["t1"], columns: [col], rows: [row(student: 1, grades: [1: 7.4])]), preferredTabId: nil)

        let sin = try XCTUnwrap(block(scope, settings: allOn([col], media: false)))
        XCTAssertNil((sin["materias"] as? [[String: Any]])?.first?["media"])

        let con = try XCTUnwrap(block(scope, settings: allOn([col], media: true)))
        let media = try XCTUnwrap((con["materias"] as? [[String: Any]])?.first?["media"] as? [String: Any])
        XCTAssertEqual(media["valor"] as? Double, 7.4)
        XCTAssertEqual(media["nivel"] as? String, "Notable")
    }

    // MARK: JSON 4.1

    func testJsonDelBloqueNotasCoincideConElContrato() throws {
        let rubrica = GradeReportRubric(columnId: "a", title: "Bádminton · Rúbrica de juego", criteria: [
            GradeReportRubricCriterion(criterionId: 1, name: "Golpeo de fondo", levelName: "Bueno", levelPosition: 3, levelCount: 4, levelDescription: "Golpea con control."),
            GradeReportRubricCriterion(criterionId: 2, name: "Colocación", levelName: "Regular", levelPosition: 2, levelCount: 4, levelDescription: nil),
        ])
        let instrument = GradeReportInstrument(columnId: "a", title: "Bádminton · Rúbrica de juego", value: 8.0, weight: 1, weightPercent: 100, level: .notable, criterionCodes: [])
        let report = StudentGradeReport(
            studentId: 1, studentName: "Alumno1 Prueba", firstName: "Alumno1", email: nil,
            finalGrade: KotlinDouble(value: 7.4), finalLevel: .notable,
            instruments: [instrument], rubrics: [rubrica], pendingTitles: []
        )
        // 12 de noviembre de 2026, mediodía UTC.
        let context = WebPortalGradeContext(classId: 7, groupName: "2º ESO B", subject: "Educación Física", columns: [
            "a": WebPortalGradeColumnMeta(id: "a", tipo: "rubrica", dateEpochMs: 1_794_484_800_000),
        ])
        var settings = WebPortalGroupGradeSettings()
        settings.columnas["a"] = true
        settings.media = true
        let notas = try XCTUnwrap(WebPortalGrades.notasBlock(
            report: report, context: context, settings: settings, now: Date(timeIntervalSince1970: 1_763_577_600), timeZone: utc
        ))

        // Va dentro del tablón v1 y sobrevive a la serialización.
        let data = try WebPortalPublisher.buildBoard(portalId: "AAECAwQFBgcICQoLDA0ODw", forms: [], notas: notas, now: Date(timeIntervalSince1970: 1_763_577_600))
        let board = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(board["schemaVersion"] as? Int, 1)
        let json = try XCTUnwrap(board["notas"] as? [String: Any])
        XCTAssertEqual(json["provisional"] as? Bool, true)
        XCTAssertEqual(json["actualizado"] as? String, "2025-11-19T18:40:00Z")
        let materia = try XCTUnwrap((json["materias"] as? [[String: Any]])?.first)
        XCTAssertEqual(materia["materia"] as? String, "Educación Física")
        XCTAssertEqual(materia["grupo"] as? String, "2º ESO B")
        XCTAssertEqual(materia["media"] as? [String: AnyHashable], ["valor": 7.4, "nivel": "Notable"])
        let actividad = try XCTUnwrap((materia["actividades"] as? [[String: Any]])?.first)
        XCTAssertEqual(actividad["titulo"] as? String, "Bádminton · Rúbrica de juego")
        XCTAssertEqual(actividad["fecha"] as? String, "2026-11-12")
        XCTAssertEqual(actividad["tipo"] as? String, "rubrica")
        XCTAssertEqual(actividad["valor"] as? Double, 8.0)
        XCTAssertEqual(actividad["nivel"] as? String, "Notable")
        let criterios = try XCTUnwrap(actividad["rubrica"] as? [[String: Any]])
        XCTAssertEqual(criterios.count, 2)
        XCTAssertEqual(criterios[0]["criterio"] as? String, "Golpeo de fondo")
        XCTAssertEqual(criterios[0]["nivel"] as? String, "Bueno")
        XCTAssertEqual(criterios[0]["posicion"] as? Int, 3)
        XCTAssertEqual(criterios[0]["de"] as? Int, 4)
        XCTAssertEqual(criterios[0]["descripcion"] as? String, "Golpea con control.")
        XCTAssertNil(criterios[1]["descripcion"], "sin descriptor no hay clave")

        // Sin notas, el tablón queda como en la fase 1.
        let plain = try WebPortalPublisher.buildBoard(portalId: "AAECAwQFBgcICQoLDA0ODw", forms: [])
        XCTAssertNil((try JSONSerialization.jsonObject(with: plain) as? [String: Any])?["notas"])
    }

    func testSinFechaEnLaColumnaSeOmiteLaFecha() throws {
        let col = column(id: "a", title: "Nota", evaluationId: 1)
        let scope = WebPortalGrades.scope(sheet: sheet(tabs: ["t1"], columns: [col], rows: [row(student: 1, grades: [1: 8])]), preferredTabId: nil)
        let materia = try XCTUnwrap((block(scope, settings: allOn([col]))?["materias"] as? [[String: Any]])?.first)
        let actividad = try XCTUnwrap((materia["actividades"] as? [[String: Any]])?.first)
        XCTAssertNil(actividad["fecha"])
        XCTAssertEqual(actividad["tipo"] as? String, "nota")
    }

    // MARK: Cola de 10 minutos

    /// Reloj manual: `sleep` espera hasta que el test avanza el tiempo.
    @MainActor
    final class ManualClock {
        private(set) var now: TimeInterval = 0
        private var waiters: [(id: Int, deadline: TimeInterval, continuation: CheckedContinuation<Void, Error>)] = []
        private var nextId = 0
        var date: Date { Date(timeIntervalSince1970: 1_000_000 + now) }

        func sleep(_ seconds: TimeInterval) async throws {
            let id = nextId
            nextId += 1
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        waiters.append((id, now + seconds, continuation))
                    }
                }
            } onCancel: {
                Task { @MainActor in self.cancel(id) }
            }
        }

        private func cancel(_ id: Int) {
            guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
            waiters.remove(at: index).continuation.resume(throwing: CancellationError())
        }

        func advance(_ seconds: TimeInterval) async {
            await settle()
            now += seconds
            let due = waiters.filter { $0.deadline <= now }
            waiters.removeAll { $0.deadline <= now }
            for waiter in due { waiter.continuation.resume() }
            await settle()
        }

        func settle() async { for _ in 0..<30 { await Task.yield() } }
    }

    private func makeDebouncer(_ clock: ManualClock, fired: @escaping (Int64) -> Void) -> WebPortalGradesDebouncer {
        WebPortalGradesDebouncer(
            sleep: { try await clock.sleep($0) },
            now: { clock.date },
            fire: { fired($0) }
        )
    }

    func testLaEsperaPorDefectoSonDiezMinutos() {
        XCTAssertEqual(WebPortalGradesDebouncer.defaultDelay, 600)
    }

    func testPublicaDiezMinutosDespuesDelUltimoCambio() async {
        let clock = ManualClock()
        var fired: [Int64] = []
        let queue = makeDebouncer(clock) { fired.append($0) }

        queue.schedule(classId: 1)
        XCTAssertEqual(queue.dueDates[1], clock.date.addingTimeInterval(600))
        await clock.advance(599)
        XCTAssertEqual(fired, [], "a los 9:59 todavía no")

        // Otra nota a los 9:59: la espera empieza de nuevo.
        queue.schedule(classId: 1)
        await clock.advance(300)
        XCTAssertEqual(fired, [], "5 minutos después del último cambio, todavía no")
        await clock.advance(299)
        XCTAssertEqual(fired, [], "9:59 después del último cambio, todavía no")
        await clock.advance(1)
        XCTAssertEqual(fired, [1], "a los 10:00 del último cambio, una sola vez")
        XCTAssertTrue(queue.pendingClassIds.isEmpty)
        XCTAssertNil(queue.dueDates[1])

        await clock.advance(3_600)
        XCTAssertEqual(fired, [1], "no se repite sin otro cambio")
    }

    func testCadaGrupoTieneSuPropiaCola() async {
        let clock = ManualClock()
        var fired: [Int64] = []
        let queue = makeDebouncer(clock) { fired.append($0) }

        queue.schedule(classId: 1)
        await clock.advance(400)
        queue.schedule(classId: 2)
        XCTAssertEqual(queue.pendingClassIds, [1, 2])
        await clock.advance(200)
        XCTAssertEqual(fired, [1])
        await clock.advance(400)
        XCTAssertEqual(fired, [1, 2])
    }

    func testReintentarPublicaYaYQuitaLaEspera() async {
        let clock = ManualClock()
        var fired: [Int64] = []
        let queue = makeDebouncer(clock) { fired.append($0) }

        queue.schedule(classId: 3)
        queue.fireNow(classId: 3)
        await clock.settle()
        XCTAssertEqual(fired, [3])
        await clock.advance(700)
        XCTAssertEqual(fired, [3], "la espera cancelada no vuelve a disparar")
    }

    // MARK: Resumen sin duplicados

    func testResumenNoVuelveASubirLoQueNoCambio() {
        var summary = WebPortalGradesSummary()
        let first: [String: Any] = ["provisional": true, "actualizado": "2025-11-19T18:40:00Z", "materias": [["grupo": "2º ESO B", "actividades": [["titulo": "A", "valor": 8.0]]]]]
        var later = first
        later["actualizado"] = "2025-11-19T19:40:00Z"
        var corrected = first
        corrected["materias"] = [["grupo": "2º ESO B", "actividades": [["titulo": "A", "valor": 6.0]]]]

        XCTAssertFalse(summary.hasChanged(studentId: 1, notas: nil), "sin notas y sin nada publicado no es un cambio")
        XCTAssertTrue(summary.hasChanged(studentId: 1, notas: first))
        summary.record(studentId: 1, notas: first)
        XCTAssertFalse(summary.hasChanged(studentId: 1, notas: later), "solo cambió la fecha de actualización")
        XCTAssertTrue(summary.hasChanged(studentId: 1, notas: corrected), "otra nota sí se sube")
        XCTAssertTrue(summary.hasChanged(studentId: 1, notas: nil), "apagar lo ya visible también se sube")
        XCTAssertFalse(summary.hasChanged(studentId: 2, notas: nil), "otro alumno no se mezcla")

        summary.record(studentId: 1, notas: nil)
        XCTAssertFalse(summary.hasChanged(studentId: 1, notas: nil))
        XCTAssertNil(summary.lastNotas(studentId: 1))
    }

    // MARK: Ajustes locales

    func testAjustesTodoApagadoSiFaltaYSeGuardanPorGrupo() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notas-\(UUID().uuidString)/portal/notas-visibles.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }

        let empty = WebPortalGradeSettings.load(fileURL: url)
        XCTAssertFalse(empty[5].media)
        XCTAssertTrue(empty.activeClassIds.isEmpty)

        try WebPortalGradeSettings.mutate(fileURL: url) {
            $0[5].media = true
            $0[5].columnas["c1"] = true
            $0[5].confirmadas = ["c1"]
            $0[6].columnas["c9"] = false
        }
        let loaded = WebPortalGradeSettings.load(fileURL: url)
        XCTAssertTrue(loaded[5].media)
        XCTAssertTrue(loaded[5].isVisible(columnId: "c1"))
        XCTAssertFalse(loaded[5].needsConfirmation(columnId: "c1"))
        XCTAssertTrue(loaded[5].needsConfirmation(columnId: "c2"))
        XCTAssertEqual(loaded.activeClassIds, [5], "el grupo 6 solo tiene una columna apagada")

        // Formato del ticket 4.2.
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: [String: Any]])
        XCTAssertEqual(raw["5"]?["media"] as? Bool, true)
        XCTAssertEqual((raw["5"]?["columnas"] as? [String: Bool]), ["c1": true])
        XCTAssertEqual(raw["5"]?["confirmadas"] as? [String], ["c1"])
    }

    func testModeloPideConfirmarLaPrimeraVezYLuegoNo() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notas-\(UUID().uuidString)/notas-visibles.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var changes: [Int64] = []
        let overview = WebPortalGradeOverview(classId: 5, studentCount: 24, columns: [
            WebPortalGradeColumnRow(id: "c1", title: "Bádminton", typeLabel: "Rúbrica", weightPercent: 100, withGrade: 24, total: 24),
        ])
        let model = WebPortalGradesViewModel(settingsURL: url, canEdit: true, loadOverview: { _ in overview }, changed: { changes.append($0) })
        await model.load(classId: 5)
        let column = overview.columns[0]

        model.requestColumn(column, on: true)
        XCTAssertEqual(model.pendingConfirmation?.id, "c1", "la primera vez pide confirmación")
        XCTAssertFalse(model.isOn(column))
        model.cancelPending()
        XCTAssertFalse(model.isOn(column), "cancelar no enciende nada")
        XCTAssertTrue(changes.isEmpty)

        model.requestColumn(column, on: true)
        model.confirmPending()
        XCTAssertTrue(model.isOn(column))
        XCTAssertEqual(changes, [5])

        model.requestColumn(column, on: false)
        XCTAssertFalse(model.isOn(column), "apagar es inmediato")
        model.requestColumn(column, on: true)
        XCTAssertNil(model.pendingConfirmation, "ya confirmada: no vuelve a preguntar")
        XCTAssertTrue(model.isOn(column))
    }

    func testEnElIPadLosInterruptoresNoCambianNada() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notas-\(UUID().uuidString)/notas-visibles.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = WebPortalGradesViewModel(settingsURL: url, canEdit: false, loadOverview: { _ in nil }, changed: { _ in XCTFail("no debe avisar") })
        await model.load(classId: 5)
        let column = WebPortalGradeColumnRow(id: "c1", title: "X", typeLabel: "Nota", weightPercent: 100, withGrade: 1, total: 1)
        model.requestColumn(column, on: true)
        model.setMedia(true)
        XCTAssertNil(model.pendingConfirmation)
        XCTAssertFalse(model.settings.media)
        XCTAssertFalse(model.isOn(column))
    }
}
