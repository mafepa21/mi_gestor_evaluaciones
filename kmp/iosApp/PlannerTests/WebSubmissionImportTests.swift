import Foundation
import XCTest
@testable import MiGestorKMPMac

#if DEBUG
final class WebSubmissionImportTests: XCTestCase {
    private var manifest: WebFormManifest {
        // swiftlint:disable:next force_try
        try! JSONDecoder().decode(
            WebFormManifest.self,
            from: Data(WebSubmissionFixture.manifestJSON.utf8)
        )
    }

    private var snapshot: WebSubmissionSnapshot {
        let items = Dictionary(uniqueKeysWithValues: manifest.items.map {
            ($0.webItemId, "item-\($0.webItemId)")
        })
        return WebSubmissionSnapshot(
            formInstanceId: WebSubmissionFixture.formInstanceId,
            classId: 7,
            columnId: "column-fixture",
            privateKeyRef: WebSubmissionKeychain.reference(for: WebSubmissionFixture.formInstanceId),
            revoked: false,
            expiresAtEpochMs: 4_000_000_000_000,
            title: manifest.title,
            studentIdByAlias: [WebSubmissionFixture.participantAlias: 42],
            itemIdByWebItemId: items,
            studentNames: [42: "Ana Ferrer"],
            importedAtBySubmissionId: [:],
            roster: [WebRosterEntry(id: 42, name: "Ana Ferrer")]
        )
    }

    private func snapshot(importedAtBySubmissionId: [String: Int64]) -> WebSubmissionSnapshot {
        let base = snapshot
        return WebSubmissionSnapshot(
            formInstanceId: base.formInstanceId,
            classId: base.classId,
            columnId: base.columnId,
            privateKeyRef: base.privateKeyRef,
            revoked: base.revoked,
            expiresAtEpochMs: base.expiresAtEpochMs,
            title: base.title,
            studentIdByAlias: base.studentIdByAlias,
            itemIdByWebItemId: base.itemIdByWebItemId,
            studentNames: base.studentNames,
            importedAtBySubmissionId: importedAtBySubmissionId,
            roster: base.roster
        )
    }

    override func setUp() {
        super.setUp()
        let key = Data(base64URLEncoded: WebSubmissionFixture.recipientPrivateKeyBase64URL) ?? Data()
        XCTAssertTrue(
            WebSubmissionKeychain.save(
                privateKey: key,
                reference: WebSubmissionKeychain.reference(for: WebSubmissionFixture.formInstanceId)
            )
        )
    }

    override func tearDown() {
        WebSubmissionKeychain.delete(
            reference: WebSubmissionKeychain.reference(for: WebSubmissionFixture.formInstanceId)
        )
        super.tearDown()
    }

    func testRoutesKnownFormAndRejectsUnknownFormInMixedBatch() {
        let service = WebSubmissionImportService(
            resolver: WebSubmissionSnapshotResolver(snapshots: [snapshot.formInstanceId: snapshot])
        )
        let file = (name: "entrega.mgsub", data: Data(WebSubmissionFixture.envelopeJSON.utf8))

        let preview = service.preview(
            files: [file],
            manifests: [manifest.formInstanceId: manifest],
            manifestJSONByFormInstanceId: [manifest.formInstanceId: Data(WebSubmissionFixture.manifestJSON.utf8)]
        )

        XCTAssertEqual(preview.drafts.count, 1)
        XCTAssertEqual(preview.drafts.first?.formInstanceId, WebSubmissionFixture.formInstanceId)
        XCTAssertTrue(preview.rejections.isEmpty)

        let unknown = service.preview(files: [file], manifests: [:])
        XCTAssertTrue(unknown.drafts.isEmpty)
        XCTAssertEqual(unknown.rejections.count, 1)
        XCTAssertTrue(unknown.rejections[0].reason.contains("formulario registrado"))
    }

    func testDuplicateSubmissionInSameBatchIsRejectedWithoutOverwriting() {
        let service = WebSubmissionImportService(
            resolver: WebSubmissionSnapshotResolver(snapshot: snapshot)
        )
        let file = (name: "entrega.mgsub", data: Data(WebSubmissionFixture.envelopeJSON.utf8))

        let preview = service.preview(
            files: [file, (name: "copia-entrega.mgsub", data: file.data)],
            manifests: [manifest.formInstanceId: manifest]
        )

        XCTAssertEqual(preview.drafts.count, 1)
        XCTAssertEqual(preview.rejections.count, 1)
        XCTAssertTrue(preview.rejections[0].reason.contains("dos veces"))
    }

    func testAlreadyImportedSubmissionIsSeparatedFromRejections() {
        let service = WebSubmissionImportService(
            resolver: WebSubmissionSnapshotResolver(
                snapshot: snapshot(importedAtBySubmissionId: [WebSubmissionFixture.submissionId: 1_754_000_000_000])
            )
        )
        let file = (name: "entrega.mgsub", data: Data(WebSubmissionFixture.envelopeJSON.utf8))

        let preview = service.preview(
            files: [file],
            manifests: [manifest.formInstanceId: manifest]
        )

        XCTAssertTrue(preview.drafts.isEmpty)
        XCTAssertTrue(preview.rejections.isEmpty)
        XCTAssertEqual(preview.alreadyImported.count, 1)
    }

    func testRejectsInvalidManifestSignatureBeforeImporting() {
        let service = WebSubmissionImportService(
            resolver: WebSubmissionSnapshotResolver(snapshot: snapshot)
        )
        let invalidManifest = Data(
            WebSubmissionFixture.manifestJSON
                .replacingOccurrences(of: "zpg_", with: "bad_")
                .utf8
        )
        let file = (name: "entrega.mgsub", data: Data(WebSubmissionFixture.envelopeJSON.utf8))

        let preview = service.preview(
            files: [file],
            manifests: [manifest.formInstanceId: manifest],
            manifestJSONByFormInstanceId: [manifest.formInstanceId: invalidManifest]
        )

        XCTAssertTrue(preview.drafts.isEmpty)
        XCTAssertEqual(preview.rejections.count, 1)
        XCTAssertTrue(preview.rejections[0].reason.contains("firma"))
    }

    func testTypeValidationRejectsInvalidAnswerType() {
        let item = WebManifestItem(
            webItemId: "scale",
            type: .scale1To4,
            title: "Escala",
            required: true,
            sectionId: nil,
            helpText: nil,
            options: nil,
            min: nil,
            max: nil,
            maxLength: nil,
            scaleLabels: nil
        )
        let answer = WebAnswer(webItemId: "scale", bool: nil, number: 5, text: nil)

        XCTAssertEqual(
            WebSubmissionImportService.typeMismatchReason(item: item, answer: answer),
            "la escala va de 1 a 4 y llegó 5"
        )
    }
}
#endif
