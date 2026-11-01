import Foundation
import XCTest
import MiGestorKit
@testable import MiGestorKMPMac

final class NotebookPhysicalTestColumnsTests: XCTestCase {
    func testPairsRawAndScoreColumnsOfSameTest() {
        let raw = column(id: "raw", title: "Test del km · Marca", inputKind: .time, category: "asig")
        let score = column(id: "score", title: "Test del km · Nota", inputKind: .numeric010, category: "asig", weight: 10, counts: true)
        let otherScore = column(id: "other", title: "Salto · Nota", inputKind: .numeric010, category: "asig")

        let pairs = NotebookPhysicalColumns.pairs(in: [raw, score, otherScore])

        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs.first?.raw.id, "raw")
        XCTAssertEqual(pairs.first?.score.id, "score")
        XCTAssertEqual(pairs.first?.kind, .time)
        XCTAssertEqual(pairs.first?.testName, "Test del km")
    }

    func testDoesNotPairAcrossCategories() {
        let raw = column(id: "raw", title: "Test del km · Marca", inputKind: .time, category: "a")
        let score = column(id: "score", title: "Test del km · Nota", inputKind: .numeric010, category: "b")

        XCTAssertTrue(NotebookPhysicalColumns.pairs(in: [raw, score]).isEmpty)
    }

    func testParsesMarks() {
        XCTAssertEqual(NotebookPhysicalMark.value(from: "04:32,50", kind: .time) ?? -1, 272.5, accuracy: 0.001)
        XCTAssertEqual(NotebookPhysicalMark.value(from: "4:32.5", kind: .time) ?? -1, 272.5, accuracy: 0.001)
        XCTAssertEqual(NotebookPhysicalMark.value(from: "12,3", kind: .time) ?? -1, 12.3, accuracy: 0.001)
        XCTAssertNil(NotebookPhysicalMark.value(from: "4:75", kind: .time))
        XCTAssertEqual(NotebookPhysicalMark.value(from: "1,92", kind: .distance) ?? -1, 1.92, accuracy: 0.001)
        XCTAssertNil(NotebookPhysicalMark.value(from: "12,5", kind: .repetitions))
        XCTAssertNil(NotebookPhysicalMark.value(from: "—", kind: .distance))
    }

    func testFormatsMarks() {
        XCTAssertEqual(NotebookPhysicalMark.timeText(seconds: 272.5), "04:32,50")
        XCTAssertEqual(NotebookPhysicalMark.compactTime("04:32,50"), "4:32,50")
        XCTAssertEqual(NotebookPhysicalMark.compactTime("00:04,70"), "0:04,70")
        XCTAssertEqual(NotebookPhysicalMark.decimalText(7.5), "7,5")
        XCTAssertEqual(NotebookPhysicalMark.decimalText(8), "8")
        XCTAssertEqual(NotebookPhysicalMark.storedText(from: "1.9", kind: .distance), "1,9")
        XCTAssertEqual(NotebookPhysicalMark.spokenTime("04:32,50"), "4 minutos 32,5 segundos")
    }

    func testRepairPlanFixesInvertedWeightsAndHidesDuplicates() {
        // Caso de la captura: Marca al 98 %, Nota «no cuenta» y columna de evaluación duplicada.
        let raw = column(id: "raw", title: "Test del km · Marca", inputKind: .time, category: "asig", weight: 98, counts: true)
        let score = column(id: "score", title: "Test del km · Nota", inputKind: .numeric010, category: "asig", weight: 0, counts: false)
        let duplicate = column(id: "eval_7", title: "Test del km", inputKind: .numeric010, instrument: .writtenTest, evaluationId: 7, weight: 1, counts: true)
        let unrelated = column(id: "eval_8", title: "Examen", inputKind: .numeric010, instrument: .writtenTest, evaluationId: 8, weight: 1, counts: true)

        let plan = NotebookPhysicalColumns.repairPlan(for: [raw, score, duplicate, unrelated])
        let byId = Dictionary(uniqueKeysWithValues: plan.map { ($0.column.id, $0) })

        XCTAssertEqual(plan.count, 3)
        XCTAssertEqual(byId["raw"]?.visibility, .hidden)
        XCTAssertEqual(byId["raw"]?.countsTowardAverage, false)
        XCTAssertEqual(byId["raw"]?.weight, 0)
        XCTAssertEqual(byId["score"]?.countsTowardAverage, true)
        XCTAssertEqual(byId["score"]?.weight, 10)
        XCTAssertEqual(byId["eval_7"]?.visibility, .hidden)
        XCTAssertEqual(byId["eval_7"]?.countsTowardAverage, false)
        XCTAssertNil(byId["eval_8"])
    }

    func testRepairPlanIsEmptyWhenAlreadyClean() {
        let raw = column(id: "raw", title: "Salto · Marca", inputKind: .distance, category: "asig", visibility: .hidden)
        let score = column(id: "score", title: "Salto · Nota", inputKind: .numeric010, category: "asig", weight: 10, counts: true)

        XCTAssertTrue(NotebookPhysicalColumns.repairPlan(for: [raw, score]).isEmpty)
    }

    func testRepairPlanKeepsTeacherChoiceToExcludeScore() {
        // Si la marca ya no cuenta, no se fuerza la nota: puede ser una prueba diagnóstica.
        let raw = column(id: "raw", title: "Salto · Marca", inputKind: .distance, category: "asig")
        let score = column(id: "score", title: "Salto · Nota", inputKind: .numeric010, category: "asig", weight: 0, counts: false)

        let plan = NotebookPhysicalColumns.repairPlan(for: [raw, score])

        XCTAssertEqual(plan.map(\.column.id), ["raw"])
    }

    private func column(
        id: String,
        title: String,
        inputKind: NotebookCellInputKind,
        instrument: NotebookInstrumentKind = .physicalTest,
        category: String? = nil,
        evaluationId: Int64? = nil,
        weight: Double = 0,
        counts: Bool = false,
        visibility: NotebookColumnVisibility = .visible
    ) -> NotebookColumnDefinition {
        let now = Instant.companion.fromEpochMilliseconds(epochMilliseconds: 0)
        return NotebookColumnDefinition(
            id: id,
            title: title,
            type: .numeric,
            categoryKind: instrument == .physicalTest ? .physicalEducation : .evaluation,
            instrumentKind: instrument,
            inputKind: inputKind,
            evaluationId: evaluationId.map { KotlinLong(value: $0) },
            rubricId: nil,
            formula: nil,
            weight: weight,
            dateEpochMs: nil,
            unitOrSituation: nil,
            competencyCriteriaIds: [],
            scaleKind: .tenPoint,
            tabIds: [],
            sessions: [],
            sharedAcrossTabs: false,
            colorHex: nil,
            iconName: nil,
            order: 0,
            widthDp: 120,
            categoryId: category,
            ordinalLevels: [],
            availableIcons: [],
            countsTowardAverage: counts,
            isPinned: false,
            isHidden: visibility != .visible,
            visibility: visibility,
            isLocked: false,
            isTemplate: false,
            emptyCellPolicy: .excludeFromAverage,
            trace: AuditTrace(
                authorUserId: nil,
                createdAt: now,
                updatedAt: now,
                associatedGroupId: nil,
                deviceId: nil,
                syncVersion: 0
            )
        )
    }
}
