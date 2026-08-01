import XCTest
@testable import MiGestorKMPMac

final class WebSubmissionSharingTests: XCTestCase {
    func testReadsPrivateLinksByAliasAndKeepsDuplicateNamesDistinct() throws {
        let formInstanceId = "form-links-test"
        let folder = try XCTUnwrap(WebSubmissionPrivateLinksStore.folderURL(for: formInstanceId))
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: folder) }

        let text = """
        Formulario de prueba
        Formulario: \(formInstanceId)

        Ana García  https://entregas.example/#f=\(formInstanceId)&a=alias-a
        Ana García  https://entregas.example/#f=\(formInstanceId)&a=alias-b
        """
        try Data(text.utf8).write(
            to: folder.appendingPathComponent("enlaces-alumnado.txt"),
            options: [.atomic]
        )

        let snapshot = WebSubmissionSnapshot(
            formInstanceId: formInstanceId,
            classId: 1,
            columnId: "column",
            privateKeyRef: "",
            revoked: false,
            expiresAtEpochMs: 4_000_000_000_000,
            title: "Formulario",
            studentIdByAlias: ["alias-a": 42, "alias-b": 43],
            itemIdByWebItemId: [:],
            studentNames: [42: "Ana García", 43: "Ana García"],
            importedAtBySubmissionId: [:],
            roster: []
        )

        let links = WebSubmissionPrivateLinksStore.readLinks(
            formInstanceId: formInstanceId,
            snapshot: snapshot,
            students: []
        )

        XCTAssertEqual(links.map(\.studentId), [42, 43])
        XCTAssertEqual(links.map { $0.url.fragment }, ["f=\(formInstanceId)&a=alias-a", "f=\(formInstanceId)&a=alias-b"])
    }

    func testBuildsIndividualMailtoWithEncodedSubjectAndBody() throws {
        let url = try XCTUnwrap(
            WebSubmissionMailComposer.mailtoURL(
                recipient: " alumno@example.com ",
                subject: "Entrega · SA 1",
                body: "Hola, Ana\nhttps://entregas.example/#f=form&a=alias"
            )
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "mailto")
        XCTAssertEqual(components.path, "alumno@example.com")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "subject" })?.value, "Entrega · SA 1")
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "body" })?.value,
            "Hola, Ana\nhttps://entregas.example/#f=form&a=alias"
        )
    }
}
