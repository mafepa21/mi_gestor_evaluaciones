import CoreGraphics
import XCTest
@testable import MiGestorKMPMac

final class PlannerSessionDetailLayoutTests: XCTestCase {
    func testLayoutPolicyUsesCompactBelowRegularThreshold() {
        let width = PlannerSessionDetailLayoutPolicy.regularMinimumWidth - 1

        XCTAssertEqual(PlannerSessionDetailLayoutPolicy.layout(for: width), .compact)
    }

    func testLayoutPolicyUsesRegularAtThresholdAndAbove() {
        let threshold = PlannerSessionDetailLayoutPolicy.regularMinimumWidth

        XCTAssertEqual(PlannerSessionDetailLayoutPolicy.layout(for: threshold), .regular)
        XCTAssertEqual(PlannerSessionDetailLayoutPolicy.layout(for: threshold + 240), .regular)
    }

    func testNavigatorFallsBackToFirstActivityForUnknownSelection() {
        let navigator = PlannerSessionActivityNavigator(
            activityKeys: ["W01-L-01", "W01-L-02"],
            selectedKey: "missing"
        )

        XCTAssertEqual(navigator.selectedKey, "W01-L-01")
        XCTAssertEqual(navigator.selectedIndex, 0)
        XCTAssertFalse(navigator.canMovePrevious)
        XCTAssertTrue(navigator.canMoveNext)
    }

    func testNavigatorHandlesEmptyAndSingleActivityWithoutLeavingBounds() {
        var empty = PlannerSessionActivityNavigator(activityKeys: [])
        empty.movePrevious()
        empty.moveNext()

        XCTAssertNil(empty.selectedKey)
        XCTAssertNil(empty.selectedIndex)
        XCTAssertFalse(empty.canMovePrevious)
        XCTAssertFalse(empty.canMoveNext)

        var single = PlannerSessionActivityNavigator(activityKeys: ["W01-S-01"])
        single.movePrevious()
        single.moveNext()

        XCTAssertEqual(single.selectedKey, "W01-S-01")
        XCTAssertFalse(single.canMovePrevious)
        XCTAssertFalse(single.canMoveNext)
    }

    func testNavigatorMovesSelectsAndStopsAtBothBoundaries() {
        var navigator = PlannerSessionActivityNavigator(
            activityKeys: ["W01-L-01", "W01-L-02", "W01-L-03"]
        )

        navigator.movePrevious()
        XCTAssertEqual(navigator.selectedKey, "W01-L-01")

        navigator.select("W01-L-02")
        XCTAssertEqual(navigator.selectedIndex, 1)
        navigator.moveNext()
        navigator.moveNext()

        XCTAssertEqual(navigator.selectedKey, "W01-L-03")
        XCTAssertTrue(navigator.canMovePrevious)
        XCTAssertFalse(navigator.canMoveNext)

        navigator.select("unknown")
        XCTAssertEqual(navigator.selectedKey, "W01-L-03")
    }

    func testSessionTypeLabelKeepsLongAndShortOperationallyDistinct() {
        XCTAssertEqual(PlannerSessionDetailSessionType.label(for: "Bloque largo"), "LONG")
        XCTAssertEqual(PlannerSessionDetailSessionType.label(for: "SHORT"), "SHORT")
        XCTAssertEqual(PlannerSessionDetailSessionType.label(for: "Simple y Doble"), "LONG / SHORT")
    }
}
