import Foundation
import MiGestorKit
import XCTest
@testable import MiGestorKMPMac

/// Exportar a Educamos con pestañas de evaluación: SA ↔ pestaña, nota final y nota parcial.
final class EducamosEvaluationMatchingTests: XCTestCase {
    private func tab(_ id: String, _ title: String, parent: String? = nil, order: Int32 = 0) -> NotebookTab {
        let zero = Instant.companion.fromEpochMilliseconds(epochMilliseconds: 0)
        return NotebookTab(id: id, title: title, description: nil, order: order, parentTabId: parent, fixedColumnWidth: nil,
                           trace: AuditTrace(authorUserId: nil, createdAt: zero, updatedAt: zero, associatedGroupId: nil, deviceId: nil, syncVersion: 0),
                           weight: nil)
    }

    private lazy var tabs = [
        tab("ev1", "1.ª Evaluación"),
        tab("hockey", "Hockey", parent: "ev1"),
        tab("ultimate", "Ultimate", parent: "ev1", order: 1),
        tab("ev2", "2.ª Evaluación", order: 1),
        tab("salto", "Salto", parent: "ev2"),
        tab("asistencia", "Asistencia", order: 2)
    ]

    func testNormalizesEducamosPrefixes() {
        XCTAssertEqual(EducamosSATabMatcher.normalizedName("SA2 Hockey"), "hockey")
        XCTAssertEqual(EducamosSATabMatcher.normalizedName("S.A. 3: Disco volador"), "disco volador")
        XCTAssertEqual(EducamosSATabMatcher.normalizedName("SA - Atletismo"), "atletismo")
        // Sin número ni signo detrás, «Sa» es parte del nombre.
        XCTAssertEqual(EducamosSATabMatcher.normalizedName("Salto"), "salto")
    }

    func testProposesBlocksAndNeverAnEvaluation() {
        XCTAssertEqual(EducamosSATabMatcher.propose(shortName: "SA2 Hockey", tabs: tabs)?.id, "hockey")
        XCTAssertEqual(EducamosSATabMatcher.propose(shortName: "Ultim", tabs: tabs)?.id, "ultimate")
        XCTAssertEqual(EducamosSATabMatcher.propose(shortName: "SA4 Salto", tabs: tabs)?.id, "salto")
        XCTAssertNil(EducamosSATabMatcher.propose(shortName: "1.ª Evaluación", tabs: tabs))
        XCTAssertNil(EducamosSATabMatcher.propose(shortName: "SA9 Natación", tabs: tabs))
        XCTAssertFalse(EducamosSATabMatcher.candidateTabs(tabs).contains { $0.id == "ev1" || $0.id == "ev2" })
        XCTAssertEqual(EducamosSATabMatcher.displayTitle(tabs[1], tabs: tabs), "Hockey (1.ª Evaluación)")
        XCTAssertEqual(EducamosSATabMatcher.displayTitle(tabs[5], tabs: tabs), "Asistencia")
    }

    func testFinalGradeComesFromTheExcelEvaluation() {
        // El Excel es de la 1.ª evaluación aunque el Cuaderno esté abierto en un bloque de la 2.ª.
        XCTAssertEqual(EducamosFinalGradeSource.evaluationTabId(tabs: tabs, excelEvaluation: "1ª Evaluación", activeTabId: "salto"), "ev1")
        XCTAssertEqual(EducamosFinalGradeSource.evaluationTabId(tabs: tabs, excelEvaluation: "Segunda evaluación", activeTabId: nil), "ev2")
        // Sin trimestre reconocible: la evaluación de la pestaña abierta.
        XCTAssertEqual(EducamosFinalGradeSource.evaluationTabId(tabs: tabs, excelEvaluation: "Final", activeTabId: "ultimate"), "ev1")
        XCTAssertNil(EducamosFinalGradeSource.evaluationTabId(tabs: tabs, excelEvaluation: "Final", activeTabId: "asistencia"))
    }

    func testPartialPolicyDefaultsToEmptyAndIsRememberedPerGroup() throws {
        let suite = "educamos-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(EducamosPartialGradePolicy.load(classId: 7, defaults: defaults), .leaveEmpty)
        EducamosPartialGradePolicy.exportPartial.save(classId: 7, defaults: defaults)
        XCTAssertEqual(EducamosPartialGradePolicy.load(classId: 7, defaults: defaults), .exportPartial)
        XCTAssertEqual(EducamosPartialGradePolicy.load(classId: 8, defaults: defaults), .leaveEmpty)
    }
}
