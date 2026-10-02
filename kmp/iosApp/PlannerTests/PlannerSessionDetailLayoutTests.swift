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

    func testSessionTypeLabelKeepsLongAndShortOperationallyDistinct() {
        XCTAssertEqual(PlannerSessionDetailSessionType.label(for: "Bloque largo"), "LONG")
        XCTAssertEqual(PlannerSessionDetailSessionType.label(for: "SHORT"), "SHORT")
        XCTAssertEqual(PlannerSessionDetailSessionType.label(for: "Simple y Doble"), "LONG / SHORT")
    }
}
