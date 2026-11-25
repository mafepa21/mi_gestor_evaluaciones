import Foundation
import MiGestorKit
import XCTest
@testable import MiGestorKMPMac

/// Exportar a Educamos: emparejamiento automático de columnas y SA, transposición 1-4 → 0-10 y nota final.
final class EducamosEvaluationMatchingTests: XCTestCase {
    private var zeroTrace: AuditTrace {
        let zero = Instant.companion.fromEpochMilliseconds(epochMilliseconds: 0)
        return AuditTrace(authorUserId: nil, createdAt: zero, updatedAt: zero, associatedGroupId: nil, deviceId: nil, syncVersion: 0)
    }

    private func tab(_ id: String, _ title: String, parent: String? = nil, order: Int32 = 0) -> NotebookTab {
        NotebookTab(
            id: id,
            title: title,
            description: nil,
            order: order,
            parentTabId: parent,
            fixedColumnWidth: nil,
            trace: zeroTrace,
            weight: nil
        )
    }

    private func column(
        id: String,
        title: String,
        type: NotebookColumnType = .numeric,
        instrument: NotebookInstrumentKind = .custom,
        inputKind: NotebookCellInputKind = .numeric010,
        scaleKind: NotebookScaleKind = .tenPoint,
        tabIds: [String] = ["hockey"],
        evaluationId: Int64? = nil,
        weight: Double = 1.0,
        counts: Bool = true
    ) -> NotebookColumnDefinition {
        NotebookColumnDefinition(
            id: id,
            title: title,
            type: type,
            categoryKind: .evaluation,
            instrumentKind: instrument,
            inputKind: inputKind,
            evaluationId: evaluationId.map { KotlinLong(value: $0) },
            rubricId: nil,
            formula: nil,
            weight: weight,
            dateEpochMs: nil,
            unitOrSituation: nil,
            competencyCriteriaIds: [],
            scaleKind: scaleKind,
            tabIds: tabIds,
            sessions: [],
            sharedAcrossTabs: false,
            colorHex: nil,
            iconName: nil,
            order: 0,
            widthDp: 120,
            categoryId: nil,
            ordinalLevels: [],
            availableIcons: [],
            countsTowardAverage: counts,
            isPinned: false,
            isHidden: false,
            visibility: .visible,
            isLocked: false,
            isTemplate: false,
            emptyCellPolicy: .excludeFromAverage,
            trace: zeroTrace
        )
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
        XCTAssertEqual(EducamosSATabMatcher.propose(shortName: "Hock", tabs: tabs)?.id, "hockey")
        XCTAssertEqual(EducamosSATabMatcher.propose(shortName: "Ultim", tabs: tabs)?.id, "ultimate")
        XCTAssertEqual(EducamosSATabMatcher.propose(shortName: "SA4 Salto", tabs: tabs)?.id, "salto")
        XCTAssertNil(EducamosSATabMatcher.propose(shortName: "1.ª Evaluación", tabs: tabs))
        XCTAssertNil(EducamosSATabMatcher.propose(shortName: "SA9 Natación", tabs: tabs))
        XCTAssertFalse(EducamosSATabMatcher.candidateTabs(tabs).contains { $0.id == "ev1" || $0.id == "ev2" })
        XCTAssertEqual(EducamosSATabMatcher.displayTitle(tabs[1], tabs: tabs), "Hockey (1.ª Evaluación)")
        XCTAssertEqual(EducamosSATabMatcher.displayTitle(tabs[5], tabs: tabs), "Asistencia")
    }

    func testBilingualAndFullDescriptionSAMatching() {
        let bilingualTabs = [
            tab("ev1", "1.ª Evaluación"),
            tab("balonmano", "SA1: Balonmano", parent: "ev1"),
            tab("badminton", "SA2: Bádminton", parent: "ev1", order: 1)
        ]
        XCTAssertEqual(
            EducamosSATabMatcher.propose(shortName: "Hand", fullName: "Balonmano", tabs: bilingualTabs)?.id,
            "balonmano"
        )
        XCTAssertEqual(
            EducamosSATabMatcher.propose(shortName: "Hand", tabs: bilingualTabs)?.id,
            "balonmano"
        )
        XCTAssertEqual(
            EducamosSATabMatcher.propose(shortName: "BAd", fullName: "Badminton", tabs: bilingualTabs)?.id,
            "badminton"
        )
    }

    func testAutoMatchesColumnsWithinSAAndDoesNotStealFromUnmatchedSA() {
        let elements: [EducamosSMElement] = [
            // SA1 Béisbol (no existe en este Cuaderno)
            EducamosSMElement(columnIndex: 6, columnLetter: "G", shortName: "AUT", uuid: "u1", tipoColumna: 14, parentSAColumnLetter: "J"),
            EducamosSMElement(columnIndex: 7, columnLetter: "H", shortName: "CM", uuid: "u2", tipoColumna: 14, parentSAColumnLetter: "J"),
            EducamosSMElement(columnIndex: 8, columnLetter: "I", shortName: "TG", uuid: "u3", tipoColumna: 14, parentSAColumnLetter: "J"),
            EducamosSMElement(columnIndex: 9, columnLetter: "J", shortName: "Beis", uuid: "u4", tipoColumna: 15),
            // SA2 Hockey (sí existe en el Cuaderno)
            EducamosSMElement(columnIndex: 10, columnLetter: "K", shortName: "Seg", uuid: "u5", tipoColumna: 14, parentSAColumnLetter: "O"),
            EducamosSMElement(columnIndex: 11, columnLetter: "L", shortName: "C.M.", uuid: "u6", tipoColumna: 14, parentSAColumnLetter: "O"),
            EducamosSMElement(columnIndex: 12, columnLetter: "M", shortName: "T-T", uuid: "u7", tipoColumna: 14, parentSAColumnLetter: "O"),
            EducamosSMElement(columnIndex: 13, columnLetter: "N", shortName: "A.H", uuid: "u8", tipoColumna: 14, parentSAColumnLetter: "O"),
            EducamosSMElement(columnIndex: 14, columnLetter: "O", shortName: "Hock", uuid: "u9", tipoColumna: 15),
            EducamosSMElement(columnIndex: 15, columnLetter: "P", shortName: "Nota", uuid: nil, tipoColumna: 1)
        ]

        let columns: [NotebookColumnDefinition] = [
            column(
                id: "col_seg",
                title: "Rejilla Transversal de Seguridad con Implemento, Fair Play y Roles",
                type: .numeric,
                instrument: .dailyWork,
                inputKind: .structuredObservation,
                scaleKind: .fourLevel,
                tabIds: ["hockey"]
            ),
            column(
                id: "col_cm",
                title: "Rúbrica visual de técnica · Hockey",
                type: .rubric,
                instrument: .rubric,
                inputKind: .rubric,
                scaleKind: .tenPoint,
                tabIds: ["hockey"]
            ),
            column(
                id: "col_tt",
                title: "Rúbrica de Análisis Táctico en Mini-Liga y Valoración Crítica del Deporte",
                type: .rubric,
                instrument: .rubric,
                inputKind: .rubric,
                scaleKind: .tenPoint,
                tabIds: ["hockey"]
            ),
            column(
                id: "col_aut",
                title: "Autoevaluación",
                type: .text,
                instrument: .selfAssessment,
                inputKind: .structuredForm,
                scaleKind: .custom,
                tabIds: ["hockey"]
            )
        ]

        let resolved = EducamosColumnMatcher.matchElements(
            elements: elements,
            tabs: tabs,
            columns: columns,
            savedMapping: [:],
            excelEvaluation: "PRIMERA EVALUACIÓN",
            activeTabId: "hockey"
        )
        let byLetter = Dictionary(uniqueKeysWithValues: resolved.map { ($0.element.columnLetter, $0) })

        // Beis no está en el Cuaderno, así que sus columnas no roban la Autoevaluación ni las rúbricas de Hockey
        XCTAssertNil(byLetter["J"]?.appTab)
        XCTAssertNil(byLetter["G"]?.appColumn)
        XCTAssertNil(byLetter["H"]?.appColumn)
        XCTAssertNil(byLetter["I"]?.appColumn)

        // Hockey empareja su pestaña y sus 4 instrumentos 1 a 1 sin duplicados
        XCTAssertEqual(byLetter["O"]?.appTab?.id, "hockey")
        XCTAssertEqual(byLetter["K"]?.appColumn?.id, "col_seg")
        XCTAssertEqual(byLetter["L"]?.appColumn?.id, "col_cm")
        XCTAssertEqual(byLetter["M"]?.appColumn?.id, "col_tt")
        XCTAssertEqual(byLetter["N"]?.appColumn?.id, "col_aut")
    }

    func testTransposesTransversalObservationGridAndSelfAssessmentFromFourToTen() {
        let rejilla = column(
            id: "col_seg",
            title: "Rejilla Transversal de Seguridad",
            type: .numeric,
            instrument: .dailyWork,
            inputKind: .structuredObservation,
            scaleKind: .fourLevel
        )
        let autoeval = column(
            id: "col_aut",
            title: "Autoevaluación",
            type: .text,
            instrument: .selfAssessment,
            inputKind: .structuredForm,
            scaleKind: .custom
        )
        let checklist = column(
            id: "col_chk",
            title: "Checklist ponderada",
            type: .numeric,
            instrument: .checklist,
            inputKind: .structuredChecklist,
            scaleKind: .tenPoint
        )

        // En el Cuaderno (NotebookStructuredGrade) se transpone 1-4 -> 0-10 automáticamente
        XCTAssertEqual(NotebookStructuredGrade(value: 4.0, column: rejilla).value, 10.0, accuracy: 0.001)
        XCTAssertEqual(NotebookStructuredGrade(value: 3.0, column: rejilla).value, 20.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(NotebookStructuredGrade(value: 2.5, column: rejilla).value, 5.0, accuracy: 0.001)
        XCTAssertEqual(NotebookStructuredGrade(value: 1.0, column: rejilla).value, 0.0, accuracy: 0.001)
        XCTAssertEqual(NotebookStructuredGrade(value: 4.0, column: rejilla).scaleText, "/ 10")

        // En la exportación a Educamos (EducamosGradeExtractor) también sale sobre 10
        XCTAssertEqual(EducamosGradeExtractor.gradeOutOfTen(row: nil, column: rejilla, numericText: "4") ?? -1, 10.0, accuracy: 0.001)
        XCTAssertEqual(EducamosGradeExtractor.gradeOutOfTen(row: nil, column: rejilla, numericText: "3,4") ?? -1, 8.0, accuracy: 0.001)
        XCTAssertEqual(EducamosGradeExtractor.gradeOutOfTen(row: nil, column: autoeval, numericText: "3,5") ?? -1, 25.0 / 3.0, accuracy: 0.001)

        // Una checklist proporcional que ya nace sobre 10 (p. ej. 2,5 / 10) NO se reescala como nivel 1-4
        XCTAssertEqual(EducamosGradeExtractor.gradeOutOfTen(row: nil, column: checklist, numericText: "2,5") ?? -1, 2.5, accuracy: 0.001)
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
