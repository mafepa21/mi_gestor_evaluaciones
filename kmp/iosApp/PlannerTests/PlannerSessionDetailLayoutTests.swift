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

    func testWideReviewStartsAtWideThreshold() {
        let threshold = PlannerSessionDetailLayoutPolicy.wideMinimumWidth

        XCTAssertFalse(PlannerSessionDetailLayoutPolicy.usesWideReview(for: threshold - 1))
        XCTAssertTrue(PlannerSessionDetailLayoutPolicy.usesWideReview(for: threshold))
    }

    func testLongSessionBlocksGoSideBySideOnlyWhenBothFit() {
        XCTAssertEqual(PlannerSessionDetailLayoutPolicy.guideColumnCount(blockCount: 2, guideWidth: 1_000), 2)
        XCTAssertEqual(PlannerSessionDetailLayoutPolicy.guideColumnCount(blockCount: 2, guideWidth: 800), 1)
        XCTAssertEqual(PlannerSessionDetailLayoutPolicy.guideColumnCount(blockCount: 2, guideWidth: 840), 2)
        XCTAssertEqual(PlannerSessionDetailLayoutPolicy.guideColumnCount(blockCount: 1, guideWidth: 1_400), 1)
        XCTAssertEqual(PlannerSessionDetailLayoutPolicy.guideColumnCount(blockCount: 3, guideWidth: 1_400), 1)
    }

    func testSessionTypeLabelKeepsLongAndShortOperationallyDistinct() {
        XCTAssertEqual(PlannerSessionDetailSessionType.label(for: "Bloque largo"), "LONG")
        XCTAssertEqual(PlannerSessionDetailSessionType.label(for: "SHORT"), "SHORT")
        XCTAssertEqual(PlannerSessionDetailSessionType.label(for: "Simple y Doble"), "LONG / SHORT")
    }
}
