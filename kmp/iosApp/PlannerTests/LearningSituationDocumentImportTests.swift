import Foundation
import XCTest
@testable import MiGestorKMPMac

final class LearningSituationDocumentImportTests: XCTestCase {
    func testBatchPreviewKeepsEveryUnreadableFileAsAnIndependentFailure() {
        let urls = [
            URL(fileURLWithPath: "/tmp/primera-situacion.docx"),
            URL(fileURLWithPath: "/tmp/segunda-situacion.docx")
        ]

        let batch = LearningSituationDocumentImportService().preview(from: urls)

        XCTAssertTrue(batch.drafts.isEmpty)
        XCTAssertEqual(batch.failures.map(\.fileName), [
            "primera-situacion.docx",
            "segunda-situacion.docx"
        ])
        XCTAssertEqual(batch.failures.count, urls.count)
    }
}
