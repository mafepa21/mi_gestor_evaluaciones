import Foundation
import MiGestorKit
import XCTest
@testable import MiGestorKMPMac

/// Recorre la lectura real de datos (base de datos de pruebas) y comprueba el texto final.
/// Todo el alumnado es inventado.
@MainActor
final class BulletinBaseBridgeTests: XCTestCase {
    func testBuildsAnonymousReportFromStoredData() async throws {
        let bridge = KmpBridge()
        let container = bridge.container
        let now = Date()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let suffix = String(nowMs)

        let classId = try await container.classesRepository.saveClass(
            id: nil, name: "Grupo prueba boletín \(suffix)", course: 2, description: nil,
            centerId: nil, academicYearId: nil, stageCycleId: nil, subjectId: nil,
            updatedAtEpochMs: 0, deviceId: nil, syncVersion: 0
        ).int64Value
        func addStudent(_ first: String, _ last: String) async throws -> Int64 {
            let id = try await container.studentsRepository.saveStudent(
                id: nil, firstName: first, lastName: last, email: "\(first.lowercased())@example.com",
                photoPath: nil, isInjured: false, sex: .unspecified, sexSource: .unknown, birthDate: nil,
                updatedAtEpochMs: 0, deviceId: nil, syncVersion: 0
            ).int64Value
            try await container.classesRepository.addStudentToClass(classId: classId, studentId: id)
            return id
        }
        let olivia = try await addStudent("Olivia", "Inventada Ruiz")
        let bruno = try await addStudent("Bruno", "Ficticio Paz")

        // Asistencia de Olivia: 5 días, uno ausente con nota que nombra a Bruno.
        for day in 0..<5 {
            _ = try await container.attendanceRepository.saveAttendance(
                id: nil, studentId: olivia, classId: classId,
                dateEpochMs: nowMs - Int64(day) * 3_600_000,
                status: day == 0 ? "AUSENTE" : "PRESENTE",
                note: day == 0 ? "Se quedó con Bruno en la biblioteca" : "",
                hasIncident: false, followUpRequired: false, sessionId: nil,
                updatedAtEpochMs: 0, deviceId: nil, syncVersion: 0
            )
        }

        // Una columna evaluable y otra de datos brutos (no cuenta para la media).
        let instant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        let trace = AuditTrace(authorUserId: nil, createdAt: instant, updatedAt: instant,
                               associatedGroupId: KotlinLong(value: classId), deviceId: nil, syncVersion: 0)
        func column(_ id: String, _ title: String, counts: Bool) -> NotebookColumnDefinition {
            NotebookColumnDefinition(
                id: id, title: title, type: .numeric, categoryKind: .evaluation, instrumentKind: .custom,
                inputKind: .numeric010, evaluationId: nil, rubricId: nil, formula: nil, weight: 1,
                dateEpochMs: KotlinLong(value: nowMs), unitOrSituation: nil, competencyCriteriaIds: [],
                scaleKind: .custom, tabIds: [], sessions: [], sharedAcrossTabs: false, colorHex: nil,
                iconName: nil, order: -1, widthDp: 120, categoryId: nil, ordinalLevels: [],
                availableIcons: [], countsTowardAverage: counts, isPinned: false, isHidden: false,
                visibility: .visible, isLocked: false, isTemplate: false,
                emptyCellPolicy: .excludeFromAverage, trace: trace
            )
        }
        let evaluable = "col_boletin_eval_\(suffix)"
        let raw = "col_boletin_bruto_\(suffix)"
        try await container.notebookConfigRepository.saveColumn(classId: classId, column: column(evaluable, "Circuito", counts: true))
        try await container.notebookConfigRepository.saveColumn(classId: classId, column: column(raw, "Metros Cooper", counts: false))
        _ = try await container.notebookRepository.saveGrade(classId: classId, studentId: olivia, columnId: evaluable, evaluationId: nil, value: KotlinDouble(value: 8.5))
        _ = try await container.notebookRepository.saveGrade(classId: classId, studentId: olivia, columnId: raw, evaluationId: nil, value: KotlinDouble(value: 2300))

        _ = try await container.incidentsRepository.saveIncident(
            id: nil, classId: classId, studentId: KotlinLong(value: bruno),
            title: "Discusión", detail: "Discute con Olivia Inventada Ruiz. Teléfono 600 111 222",
            severity: "low", dateEpochMs: nowMs, authorUserId: nil,
            updatedAtEpochMs: 0, deviceId: nil, syncVersion: 0
        )

        let report = try await bridge.buildBulletinBaseReport(
            classId: classId,
            termLabel: "1er Trimestre",
            period: (now.addingTimeInterval(-86_400 * 2), now.addingTimeInterval(86_400))
        )

        XCTAssertEqual(report.studentCount, 2)
        XCTAssertEqual(report.evaluableColumnCount, 1, "Los datos brutos no son columna evaluable")
        let folded = BulletinBaseTextScrubber.fold(report.text)
        for forbidden in ["olivia", "bruno", "inventada", "ficticio", "ruiz", "example.com", "600 111 222", "2300"] {
            XCTAssertFalse(folded.contains(forbidden), "Se cuela «\(forbidden)»:\n\(report.text)")
        }
        let codeByName = Dictionary(uniqueKeysWithValues: report.key.map { ($0.studentName, $0.code) })
        let oliviaCode = try XCTUnwrap(codeByName["Olivia Inventada Ruiz"])
        let brunoCode = try XCTUnwrap(codeByName["Bruno Ficticio Paz"])
        XCTAssertTrue(report.text.contains("Asistencia: 80 % presente · 1 falta · 0 retrasos"), report.text)
        XCTAssertTrue(report.text.contains("Notas: media 8,5 (1 nota)"), report.text)
        XCTAssertTrue(report.text.contains("Se quedó con \(brunoCode) en la biblioteca"), report.text)
        XCTAssertTrue(report.text.contains("Discusión: Discute con \(oliviaCode). Teléfono [teléfono]"), report.text)

        try? await container.classesRepository.deleteClass(classId: classId)
    }
}
