import CoreGraphics
import Foundation
import XCTest
@testable import MiGestorKMPMac

final class PlannerClassKitTests: XCTestCase {
    func testInputKeepsPlanTasksAndSkipsCollections() {
        let input = makeInput()

        XCTAssertEqual(input.tasks.map(\.title), ["Split-Step Traffic Lights", "Net Drop Circuit", "Pair closure"])
        XCTAssertEqual(input.tasks.map(\.minutes), [6, 24, 5])
        XCTAssertEqual(input.tasks.map(\.isMainMoment), [false, true, false])
    }

    func testLongDetailIsShortenedForTheOnDeviceModel() {
        let long = String(repeating: "word ", count: 600)
        let shortened = PlannerClassKitInput.shortened(long)

        XCTAssertLessThanOrEqual(shortened.count, PlannerClassKitInput.maxDetailLength + 1)
        XCTAssertTrue(shortened.hasSuffix("…"))
    }

    func testCoachingIsTrimmedAndNeverAsksDoYouUnderstand() {
        let coaching = PlannerClassKitNormalizer.coaching(
            show: "  Demo con un alumno. ",
            say: ["1. A lifts short.", "- B plays a soft drop.", "B touches the cone.", "Six good drops, then swap.", "a lifts short."],
            rule: ["• El drop solo cuenta antes de la línea.", ""],
            checks: [("Do you understand?", "Yes"), ("Where does it land?", "Before the line"), ("", "x")],
            cue: "Soft touch.",
            card: PlannerClassKitCard(title: "Net drop circuit", steps: ["A lifts short.", "", "B drops."], points: "Before the line.", swap: "6 drops.", cue: "soft touch")
        )

        XCTAssertEqual(coaching.show, "Demo con un alumno.")
        XCTAssertEqual(coaching.say, ["A lifts short.", "B plays a soft drop.", "B touches the cone."])
        XCTAssertEqual(coaching.rule, ["El drop solo cuenta antes de la línea."])
        XCTAssertEqual(coaching.checks.map(\.question), ["Where does it land?"])
        XCTAssertEqual(coaching.card?.title, "NET DROP CIRCUIT")
        XCTAssertEqual(coaching.card?.steps, ["A lifts short.", "B drops."])
        XCTAssertEqual(coaching.card?.cue, "SOFT TOUCH")
    }

    func testBoardWordsAreThreeUppercaseWords() {
        let header = PlannerClassKitNormalizer.header(
            boardWords: ["soft · net", "back", "drop"],
            sessionCue: "Soft touch.",
            cueGesture: "Mano abierta",
            closingQuestion: "Clear or drop?",
            closingSentence: "I play a drop when ______ (at the back)."
        )

        XCTAssertEqual(header.boardWords, ["SOFT", "NET", "BACK"])
    }

    func testCardsComeOnlyFromMainTasks() {
        var kit = PlannerClassKit(input: makeInput())
        let card = PlannerClassKitCard(title: "CARD", steps: ["Step"], points: "", swap: "", cue: "")
        for index in kit.tasks.indices {
            kit.tasks[index].coaching = PlannerClassKitCoaching(show: "", say: [], rule: [], checks: [], cue: "", card: card)
        }

        XCTAssertEqual(kit.cards.count, 1)
    }

    func testPDFWithoutAIHasTheGuideAndNoCards() throws {
        let kit = PlannerClassKit(input: makeInput())
        XCTAssertFalse(kit.hasCoaching)

        let data = try XCTUnwrap(PlannerClassKitPDFRenderer.render(kit: kit))
        let document = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        XCTAssertGreaterThanOrEqual(document.numberOfPages, 1)
    }

    func testPDFPutsEachCardOnItsOwnPage() throws {
        let withoutCards = try pageCount(PlannerClassKit(input: makeInput()))
        var kit = PlannerClassKit(input: makeInput())
        let mainIndex = try XCTUnwrap(kit.tasks.firstIndex { $0.source.isMainMoment })
        kit.tasks[mainIndex].coaching = PlannerClassKitCoaching(
            show: "Demo.",
            say: ["A lifts short."],
            rule: [],
            checks: [],
            cue: "Soft touch.",
            card: PlannerClassKitCard(title: "NET DROP", steps: ["A lifts short."], points: "1", swap: "6", cue: "SOFT TOUCH")
        )

        XCTAssertEqual(try pageCount(kit), withoutCards + 1)
    }

    // MARK: Helpers

    private func pageCount(_ kit: PlannerClassKit) throws -> Int {
        let data = try XCTUnwrap(PlannerClassKitPDFRenderer.render(kit: kit))
        return try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!)).numberOfPages
    }

    private func makeInput() -> PlannerClassKitInput {
        let steps = [
            step("w", phase: "Warm-up", title: "Split-Step Traffic Lights", minutes: 6),
            step("m", phase: "Main task", title: "Net Drop Circuit", minutes: 24, isMain: true),
            step("r", phase: "Recogida", title: "Recogida de volantes", minutes: nil, isCollection: true),
            step("c", phase: "Closure", title: "Pair closure", minutes: 5)
        ]
        let block = PlannerSessionReviewBlock(id: "U04", label: "U04", totalMinutes: 35, precededByBreak: false, steps: steps)
        return PlannerClassKitInput(
            title: "U04 · Drop shot and net play",
            meta: "1º BAC B · Sesión 4",
            objective: "Play soft drops close to the net.",
            setup: ["Pistas 1-4: un cono en cada calle."],
            blocks: [block],
            clilCues: ["Soft touch."]
        )
    }

    private func step(_ key: String, phase: String, title: String, minutes: Int?, isMain: Bool = false, isCollection: Bool = false) -> PlannerSessionReviewStep {
        PlannerSessionReviewStep(
            activityKey: key,
            minutes: minutes,
            startOffsetMinutes: nil,
            phase: phase,
            title: title,
            detail: "A lifts short. B plays a soft drop and touches the cone.",
            clil: nil,
            isMain: isMain,
            isCollection: isCollection,
            extras: []
        )
    }
}
