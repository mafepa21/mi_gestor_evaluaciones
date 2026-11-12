import Foundation
import XCTest
@testable import MiGestorKMPMac

final class PlannerSessionActualEditTests: XCTestCase {
    func testInputSkipsCollections() {
        let input = makeInput()

        XCTAssertEqual(input.blocks.map(\.title), ["Calentamiento", "Rondo 4×2", "Partido reducido"])
    }

    func testModelSayingChangedWithSameTextIsUnchanged() {
        let planned = makeInput().blocks[0]
        let result = PlannerActualEditNormalizer.block(
            planned: planned, wasSkipped: false, changed: true,
            detail: "  movilidad articular y carrera continua suave ", minutes: 0, changeNote: "Nada"
        )

        XCTAssertEqual(result.status, .unchanged)
        XCTAssertEqual(result.detail, planned.detail)
        XCTAssertEqual(result.changeNote, "")
    }

    func testChangedTextAndMinutesAreKept() {
        let planned = makeInput().blocks[2]
        let result = PlannerActualEditNormalizer.block(
            planned: planned, wasSkipped: false, changed: true,
            detail: "Partido 4×4 con porterías pequeñas.", minutes: 30, changeNote: "Duró 10 minutos más."
        )

        XCTAssertEqual(result.status, .changed)
        XCTAssertEqual(result.minutes, 30)
        XCTAssertEqual(result.changeNote, "duró 10 minutos más")
    }

    func testImpossibleMinutesFallBackToPlan() {
        let planned = makeInput().blocks[2]
        let result = PlannerActualEditNormalizer.block(
            planned: planned, wasSkipped: false, changed: true,
            detail: "Partido 4×4 con porterías pequeñas.", minutes: 900, changeNote: ""
        )

        XCTAssertEqual(result.minutes, 20)
    }

    func testSkippedBlockLeavesActualTextAndGoesToAdaptations() {
        let input = makeInput()
        var edit = PlannerActualEdit(input: input)
        edit.apply(PlannerActualEditNormalizer.block(planned: input.blocks[1], wasSkipped: true, changed: false, detail: "", minutes: 0, changeNote: ""), to: input.blocks[1].id)
        edit.apply(PlannerActualEditNormalizer.block(planned: input.blocks[0], wasSkipped: false, changed: false, detail: "", minutes: 0, changeNote: ""), to: input.blocks[0].id)

        XCTAssertFalse(edit.actualJournalText.contains("Rondo"))
        XCTAssertTrue(edit.plannedJournalText.contains("• Rondo 4×2 (10 min): Grupos de 6, 4 pasan y 2 roban."))
        XCTAssertEqual(edit.adaptationsJournalText, "• Rondo 4×2: no se hizo.")
    }

    func testRevertRestoresPlanAndRemovesAdded() {
        let input = makeInput()
        var edit = PlannerActualEdit(input: input, status: .unchanged)
        edit.edit(input.blocks[0].id, detail: "Pilla-pilla con balón.")
        XCTAssertEqual(edit.blocks[0].status, .changed)

        edit.insert([PlannerActualEdit.Added(title: "Charla", minutes: 5, detail: "Juego limpio.", afterTitle: "")])
        XCTAssertEqual(edit.changeCount, 2)

        edit.revert(input.blocks[0].id)
        edit.revert(edit.blocks.last!.id)

        XCTAssertFalse(edit.hasChanges)
        XCTAssertEqual(edit.blocks.count, 3)
        XCTAssertEqual(edit.blocks[0].detail, input.blocks[0].detail)
    }

    func testEditingBackToPlanTextIsUnchanged() {
        let input = makeInput()
        var edit = PlannerActualEdit(input: input, status: .unchanged)
        edit.edit(input.blocks[0].id, detail: "Otra cosa")
        edit.edit(input.blocks[0].id, detail: input.blocks[0].detail + " ")

        XCTAssertEqual(edit.blocks[0].status, .unchanged)
    }

    func testAddedActivityGoesAfterNamedBlockOrAtTheEnd() {
        let input = makeInput()
        var edit = PlannerActualEdit(input: input, status: .unchanged)
        edit.insert([
            PlannerActualEdit.Added(title: "Charla", minutes: 5, detail: "", afterTitle: "rondo 4×2"),
            PlannerActualEdit.Added(title: "Estiramientos", minutes: nil, detail: "", afterTitle: "No existe"),
        ])

        XCTAssertEqual(edit.blocks.map(\.title), ["Calentamiento", "Rondo 4×2", "Charla", "Partido reducido", "Estiramientos"])
        XCTAssertTrue(edit.actualJournalText.contains("• Charla (5 min)"))
        XCTAssertTrue(edit.adaptationsJournalText.contains("• Charla: añadida."))
    }

    func testFailedBlockStaysAsPlan() {
        let input = makeInput()
        var edit = PlannerActualEdit(input: input)
        edit.markFailed(input.blocks[0].id)

        XCTAssertEqual(edit.blocks[0].status, .failed)
        XCTAssertEqual(edit.blocks[0].detail, input.blocks[0].detail)
        XCTAssertFalse(edit.hasChanges)
    }

    func testEmptyAddedTitleIsDropped() {
        XCTAssertNil(PlannerActualEditNormalizer.added(title: "  ", minutes: 5, detail: "x", afterTitle: ""))
        XCTAssertNil(PlannerActualEditNormalizer.added(title: "Charla", minutes: 0, detail: "", afterTitle: "")?.minutes)
    }

    // MARK: Datos inventados

    private func makeInput() -> PlannerActualEditInput {
        PlannerActualEditInput(title: "S04 · Juegos de invasión", meta: "Grupo de prueba", blocks: [
            PlannerSessionReviewBlock(id: "b1", label: nil, totalMinutes: 30, precededByBreak: false, steps: [
                step("a1", "Calentamiento", 10, "Movilidad articular y carrera continua suave."),
                step("a2", "Rondo 4×2", 10, "Grupos de 6, 4 pasan y 2 roban."),
                step("a3", "Recogida", nil, "Conos al carro.", isCollection: true),
            ]),
            PlannerSessionReviewBlock(id: "b2", label: nil, totalMinutes: 20, precededByBreak: false, steps: [
                step("a4", "Partido reducido", 20, "Partido 4×4."),
            ]),
        ])
    }

    private func step(_ key: String, _ title: String, _ minutes: Int?, _ detail: String, isCollection: Bool = false) -> PlannerSessionReviewStep {
        PlannerSessionReviewStep(
            activityKey: key, minutes: minutes, startOffsetMinutes: nil, phase: "", title: title,
            detail: detail, clil: nil, isMain: false, isCollection: isCollection, extras: []
        )
    }
}
