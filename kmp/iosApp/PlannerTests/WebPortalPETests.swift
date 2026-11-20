import Foundation
import XCTest
@testable import MiGestorKMPMac

final class WebPortalPETests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("migestor-pe-portal-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
    }

    func testSettingsTodoApagadoPorDefectoYPersiste() throws {
        let url = tempDir.appendingPathComponent("ef-visible.json")
        let initial = WebPortalPESettings.load(fileURL: url)
        XCTAssertFalse(initial[10].hasAnythingActive)
        XCTAssertFalse(initial[10].asistencia)
        XCTAssertTrue(initial[10].needsTestConfirmation(testId: "t1"))

        try WebPortalPESettings.mutate(fileURL: url) { settings in
            settings[10].pruebas["t1"] = true
            settings[10].pruebasConfirmadas.append("t1")
            settings[10].asistencia = true
            settings[10].asistenciaConfirmada = true
        }
        let reloaded = WebPortalPESettings.load(fileURL: url)
        XCTAssertTrue(reloaded[10].isTestVisible(testId: "t1"))
        XCTAssertFalse(reloaded[10].needsTestConfirmation(testId: "t1"))
        XCTAssertTrue(reloaded[10].asistencia)
        XCTAssertEqual(reloaded.activeClassIds, [10])
    }

    func testFisicaBlockCalculaMejoraSegunHigherIsBetter() throws {
        let defs: [String: WebPortalPE.TestMeta] = [
            "1000m": .init(id: "1000m", name: "Test 1000m", capacityLabel: "Resistencia", unit: "s", higherIsBetter: false),
            "salto": .init(id: "salto", name: "Salto horizontal", capacityLabel: "Fuerza", unit: "cm", higherIsBetter: true),
        ]
        let records: [WebPortalPE.TestRecord] = [
            .init(testId: "1000m", rawValue: 272, rawText: "4:32", score: 7.2, observedAtEpochMs: 1_759_000_000_000),
            .init(testId: "1000m", rawValue: 255, rawText: "4:15", score: 8.5, observedAtEpochMs: 1_763_000_000_000),
            .init(testId: "salto", rawValue: 204, rawText: "2,04 m", score: 7.8, observedAtEpochMs: 1_759_000_000_000),
            .init(testId: "salto", rawValue: 218, rawText: "2,18 m", score: 8.8, observedAtEpochMs: 1_763_000_000_000),
        ]

        // Solo 1000m encendido -> salto NO aparece.
        let block = try XCTUnwrap(WebPortalPE.fisicaBlock(
            definitions: defs,
            records: records,
            visibleTestIds: ["1000m", "salto"]
        ))
        let pruebas = try XCTUnwrap(block["pruebas"] as? [[String: Any]])
        XCTAssertEqual(pruebas.count, 2)

        let run = try XCTUnwrap(pruebas.first { ($0["id"] as? String) == "1000m" })
        XCTAssertEqual(run["mejora"] as? Bool, true)
        XCTAssertEqual((run["actual"] as? [String: Any])?["marca"] as? String, "4:15")
        XCTAssertEqual((run["anterior"] as? [String: Any])?["marca"] as? String, "4:32")

        let jump = try XCTUnwrap(pruebas.first { ($0["id"] as? String) == "salto" })
        XCTAssertEqual(jump["mejora"] as? Bool, true)
        XCTAssertEqual(jump["diferencia"] as? String, "+14 cm")

        // Con visibleTestIds vacío -> nil
        XCTAssertNil(WebPortalPE.fisicaBlock(definitions: defs, records: records, visibleTestIds: []))
    }

    func testAsistenciaBlockSoloExportaContadoresYFechasSinNotasPrivadas() throws {
        let items: [WebPortalPE.AttendanceItem] = [
            .init(dateEpochMs: 1_760_000_000_000, status: "PRESENT"),
            .init(dateEpochMs: 1_761_000_000_000, status: "ABSENT"),
            .init(dateEpochMs: 1_762_000_000_000, status: "LATE"),
            .init(dateEpochMs: 1_763_000_000_000, status: "JUSTIFICADA"),
            .init(dateEpochMs: 1_764_000_000_000, status: "NO_KIT"),
        ]
        let block = try XCTUnwrap(WebPortalPE.asistenciaBlock(records: items))
        let resumen = try XCTUnwrap(block["resumen"] as? [String: Int])
        XCTAssertEqual(resumen["faltas"], 1)
        XCTAssertEqual(resumen["retrasos"], 1)
        XCTAssertEqual(resumen["justificadas"], 1)
        XCTAssertEqual(resumen["sinEquipacion"], 1)

        let recientes = try XCTUnwrap(block["recientes"] as? [[String: Any]])
        XCTAssertEqual(recientes.count, 4)
        // Solo `fecha` y `tipo`: nunca notas ni incidencias.
        for item in recientes {
            XCTAssertEqual(Set(item.keys), Set(["fecha", "tipo"]))
        }
    }

    func testBuildBoardYPreviewIncluyenFisicaYAsistencia() throws {
        let fisica: [String: Any] = [
            "actualizado": "2026-11-20T12:00:00Z",
            "pruebas": [[
                "id": "1000m",
                "nombre": "Test 1000m",
                "capacidad": "Resistencia",
                "actual": ["marca": "4:15", "nota": 8.5],
                "anterior": ["marca": "4:32"],
                "diferencia": "−17 s",
                "mejora": true,
            ]],
        ]
        let asistencia: [String: Any] = [
            "actualizado": "2026-11-20T12:00:00Z",
            "resumen": ["faltas": 2, "retrasos": 1, "justificadas": 0, "sinEquipacion": 1],
            "recientes": [["fecha": "2026-11-14", "tipo": "retraso"]],
        ]

        let board = try WebPortalPublisher.buildBoard(
            portalId: "pid-ef",
            forms: [],
            fisica: fisica,
            asistencia: asistencia
        )
        let preview = WebPortalStudentPreviewData.parse(
            boardData: board,
            studentName: "Ana",
            groupName: "2º ESO B",
            accountStatus: .activada
        )
        XCTAssertFalse(preview.isCompletelyEmpty)
        XCTAssertTrue(preview.hasPEData)
        XCTAssertEqual(preview.physicalTests.count, 1)
        XCTAssertEqual(preview.physicalTests.first?.currentMark, "4:15")
        XCTAssertEqual(preview.attendance?.absences, 2)
        XCTAssertEqual(preview.attendance?.noKit, 1)
    }

    @MainActor
    func testViewModelConfirmacionesYRetiradaInmediata() async {
        let url = tempDir.appendingPathComponent("ef-vm.json")
        var calls: [(Int64, Bool)] = []
        let row = WebPortalPETestRow(id: "t1", name: "1000m", capacityLabel: "Resistencia", recordedStudents: 25, totalStudents: 30, assignmentCount: 2)
        let vm = WebPortalPEViewModel(
            settingsURL: url,
            canEdit: true,
            loadOverview: { classId in
                WebPortalPEOverview(classId: classId, studentCount: 30, tests: [row], hasAttendanceRecords: true)
            },
            changed: { classId, immediately in calls.append((classId, immediately)) }
        )

        await vm.load(classId: 7)
        vm.requestTest(row, on: true)
        XCTAssertEqual(vm.pendingConfirmation, .showTest(row))
        vm.confirmPending()
        XCTAssertTrue(vm.isTestOn(row))
        XCTAssertEqual(calls.last?.1, false) // Encender espera 10 min

        vm.requestTest(row, on: false)
        XCTAssertFalse(vm.isTestOn(row))
        XCTAssertEqual(calls.last?.1, true)  // Apagar retira al momento

        vm.requestAttendance(on: true)
        XCTAssertEqual(vm.pendingConfirmation, .showAttendance)
        vm.confirmPending()
        XCTAssertTrue(vm.settings.asistencia)
        vm.requestAttendance(on: false)
        XCTAssertFalse(vm.settings.asistencia)
        XCTAssertEqual(calls.last?.1, true)

        vm.requestPassport(on: true)
        XCTAssertEqual(vm.pendingConfirmation, .showPassport)
        vm.confirmPending()
        XCTAssertTrue(vm.settings.pasaporte)
        vm.requestPassport(on: false)
        XCTAssertFalse(vm.settings.pasaporte)
        XCTAssertEqual(calls.last?.1, true)
    }

    func testPasaporteBlockYPreviewIncluyenSellosEHistorico() throws {
        let pasaporte = try XCTUnwrap(WebPortalPE.pasaporteBlock(entries: [
            .init(title: "Pasaporte · Balonmano", stops: [
                .init(title: "Punto de partida", done: true),
                .init(title: "Ataque en equipo", done: true),
                .init(title: "Reflexión final", done: false),
            ]),
        ]))
        let notas: [String: Any] = [
            "provisional": true,
            "materias": [[
                "grupo": "2º ESO B",
                "actividades": [],
                "historico": [
                    ["titulo": "1.ª Evaluación", "media": ["valor": 7.8, "nivel": "Notable"]],
                ],
            ]],
        ]
        let board = try WebPortalPublisher.buildBoard(
            portalId: "pid-3d",
            forms: [],
            notas: notas,
            pasaporte: pasaporte
        )
        let preview = WebPortalStudentPreviewData.parse(
            boardData: board,
            studentName: "Ana",
            groupName: "2º ESO B",
            accountStatus: .activada
        )
        XCTAssertFalse(preview.isCompletelyEmpty)
        XCTAssertTrue(preview.hasPEData)
        XCTAssertEqual(preview.passports.first?.completed, 2)
        XCTAssertEqual(preview.passports.first?.total, 3)
        XCTAssertEqual(preview.gradeSubjects.first?.historical.first?.title, "1.ª Evaluación")
        XCTAssertEqual(preview.gradeSubjects.first?.historical.first?.valueText, "7,8")
    }
}
