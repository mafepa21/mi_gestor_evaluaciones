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

    func testArchivedTasksStayOutOfActiveFilterAndAppearInArchiveFilter() {
        let task = WebSubmissionTaskInfo(
            formInstanceId: "form-archived",
            classId: 1,
            groupName: "3 ESO A",
            title: "SA 1",
            columnTitle: "Entrega",
            status: .active,
            isArchived: true,
            expiresAtEpochMs: 4_000_000_000_000,
            importedCount: 0,
            lastImportedAtEpochMs: nil
        )

        XCTAssertFalse(WebSubmissionTaskFilter.active.matches(task))
        XCTAssertTrue(WebSubmissionTaskFilter.all.matches(task))
        XCTAssertTrue(WebSubmissionTaskFilter.archived.matches(task))
    }

    // MARK: - Rúbrica visual

    func testElDibujoSoloViajaEnEscalasYConClaveConocida() throws {
        func item(_ id: String, _ tipo: WebManifestItemType, _ visual: String?) -> WebSubmissionPublisher.ItemToPublish {
            WebSubmissionPublisher.ItemToPublish(
                itemId: id, title: id, type: tipo, required: true,
                options: tipo == .choice ? ["a", "b"] : [], helpText: nil, scaleLabels: nil, sectionId: nil,
                visual: visual
            )
        }
        let publicado = try WebSubmissionPublisher.publish(
            title: "Coevaluación",
            subtitle: nil,
            locale: "en",
            sections: [],
            items: [
                item("saque", .scale1To4, "badminton.serve"),
                item("inventado", .scale1To4, "badminton.smash"),
                item("texto", .text, "badminton.serve"),
            ],
            students: [WebSubmissionPublisher.StudentToPublish(id: 1, name: "Prueba")],
            baseURL: "https://example.test",
            deliveryEmail: nil,
            expiresAtEpochMs: 1_900_000_000_000
        )
        let raiz = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(publicado.manifestJSON.utf8)) as? [String: Any])
        let items = try XCTUnwrap(raiz["items"] as? [[String: Any]])
        XCTAssertEqual(items[0]["visual"] as? String, "badminton.serve")
        XCTAssertNil(items[1]["visual"], "una clave que la web no conoce no se publica")
        XCTAssertNil(items[2]["visual"], "el contrato solo admite dibujos en escalas 1-4")
    }

    func testLasClavesDeDibujoTienenLaFormaDelContrato() {
        let forma = try! NSRegularExpression(pattern: "^[a-z0-9_]{1,32}\\.[a-z0-9_]{1,32}$")
        for opcion in WebRubricVisual.options {
            let rango = NSRange(opcion.key.startIndex..., in: opcion.key)
            XCTAssertNotNil(forma.firstMatch(in: opcion.key, range: rango), opcion.key)
        }
        XCTAssertEqual(Set(WebRubricVisual.options.map(\.key)).count, WebRubricVisual.options.count)
    }
}
