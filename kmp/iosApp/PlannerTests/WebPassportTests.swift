import XCTest
@testable import MiGestorKMPMac

/// Pasaporte por paradas: reparto en paradas, junta de envíos y vista del docente.
final class WebPassportTests: XCTestCase {
    // MARK: - Paradas a partir de los títulos

    func testAgrupaApartadosSeguidosConElMismoPrefijo() {
        let reparto = WebPassportSections.split(
            titles: [
                "Parada 1 · Mi mejor reto",
                "Parada 1 · Lo que más me cuesta",
                "Parada 2 · Nuestro mejor rally",
                "Parada 3 · Un error corregido",
            ],
            fallbackTitle: "Pasaporte"
        )
        XCTAssertEqual(reparto.stops.map(\.title), ["Parada 1", "Parada 2", "Parada 3"])
        XCTAssertEqual(reparto.stops.map(\.sectionId), ["p1", "p2", "p3"])
        XCTAssertEqual(reparto.stops[0].itemIndexes, [0, 1])
        XCTAssertEqual(reparto.itemTitles, ["Mi mejor reto", "Lo que más me cuesta", "Nuestro mejor rally", "Un error corregido"])
    }

    func testSiAlgunApartadoNoTienePrefijoTodoVaEnUnaParada() {
        let reparto = WebPassportSections.split(
            titles: ["Parada 1 · Mi mejor reto", "Una cosa que quiero mejorar"],
            fallbackTitle: "Mi pasaporte"
        )
        XCTAssertEqual(reparto.stops.count, 1)
        XCTAssertEqual(reparto.stops[0].title, "Mi pasaporte")
        XCTAssertEqual(reparto.stops[0].itemIndexes, [0, 1])
        XCTAssertEqual(reparto.itemTitles, ["Parada 1 · Mi mejor reto", "Una cosa que quiero mejorar"])
    }

    func testSinApartadosNoHayParadas() {
        XCTAssertTrue(WebPassportSections.split(titles: [], fallbackTitle: "X").stops.isEmpty)
    }

    // MARK: - Juntar envíos

    private func respuesta(_ item: String, texto: String) -> WebResolvedAnswer {
        WebResolvedAnswer(itemId: item, webItemId: "w\(item)", title: "T\(item)", type: .text, textValue: texto, boolValue: nil, numberValue: nil)
    }

    private func almacen() -> WebPassportStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasaporte-\(UUID().uuidString).json")
        return WebPassportStore(fileURL: url)
    }

    private let secciones = ["wa": "p1", "wb": "p1", "wc": "p2"]

    func testUnEnvioPosteriorConservaLoQueNoTrae() {
        var store = almacen()
        store.merge(studentId: 7, clientSubmittedAt: "2026-10-28T10:00:00.000Z",
                    answers: [respuesta("a", texto: "uno")], sectionIdByWebItemId: secciones)
        store.merge(studentId: 7, clientSubmittedAt: "2026-11-04T10:00:00.000Z",
                    answers: [respuesta("c", texto: "tres")], sectionIdByWebItemId: secciones)

        XCTAssertEqual(store.mergedAnswers(for: 7).map(\.itemId), ["a", "c"])
        let registro = store.record(for: 7)
        XCTAssertEqual(registro?.sectionChangedAt["p1"], "2026-10-28T10:00:00.000Z")
        XCTAssertEqual(registro?.sectionChangedAt["p2"], "2026-11-04T10:00:00.000Z")
        XCTAssertEqual(registro?.lastSubmittedAt, "2026-11-04T10:00:00.000Z")
    }

    func testUnaRespuestaNuevaSustituyeALaAnterior() {
        var store = almacen()
        store.merge(studentId: 7, clientSubmittedAt: "2026-10-28T10:00:00.000Z",
                    answers: [respuesta("a", texto: "antes")], sectionIdByWebItemId: secciones)
        store.merge(studentId: 7, clientSubmittedAt: "2026-11-04T10:00:00.000Z",
                    answers: [respuesta("a", texto: "ahora")], sectionIdByWebItemId: secciones)
        XCTAssertEqual(store.mergedAnswers(for: 7).first?.textValue, "ahora")
        XCTAssertEqual(store.record(for: 7)?.sectionChangedAt["p1"], "2026-11-04T10:00:00.000Z")
    }

    func testUnEnvioAntiguoQueLlegaTardeNoPisaElNuevo() {
        var store = almacen()
        store.merge(studentId: 7, clientSubmittedAt: "2026-11-04T10:00:00.000Z",
                    answers: [respuesta("a", texto: "ahora")], sectionIdByWebItemId: secciones)
        store.merge(studentId: 7, clientSubmittedAt: "2026-10-28T10:00:00.000Z",
                    answers: [respuesta("a", texto: "antes")], sectionIdByWebItemId: secciones)
        XCTAssertEqual(store.mergedAnswers(for: 7).first?.textValue, "ahora")
    }

    func testReenviarLoMismoNoMarcaLaParadaComoCambiada() {
        var store = almacen()
        store.merge(studentId: 7, clientSubmittedAt: "2026-10-28T10:00:00.000Z",
                    answers: [respuesta("a", texto: "uno")], sectionIdByWebItemId: secciones)
        store.merge(studentId: 7, clientSubmittedAt: "2026-11-04T10:00:00.000Z",
                    answers: [respuesta("a", texto: "uno"), respuesta("c", texto: "tres")], sectionIdByWebItemId: secciones)
        XCTAssertEqual(store.record(for: 7)?.sectionChangedAt["p1"], "2026-10-28T10:00:00.000Z")
    }

    func testGuardaYVuelveALeer() throws {
        var store = almacen()
        store.merge(studentId: 7, clientSubmittedAt: "2026-10-28T10:00:00.000Z",
                    answers: [respuesta("a", texto: "uno")], sectionIdByWebItemId: secciones)
        try store.save()
        defer { try? FileManager.default.removeItem(at: store.fileURL) }
        let leido = WebPassportStore(fileURL: store.fileURL)
        XCTAssertEqual(leido.mergedAnswers(for: 7), store.mergedAnswers(for: 7))
    }

    // MARK: - Vista del docente

    private func manifiesto() throws -> WebFormManifest {
        let json = """
        {"schemaVersion":1,"mode":"passport","formInstanceId":"11111111-2222-4333-8444-555555555555",
         "title":"Pasaporte","locale":"es","recipientKey":"x","expiresAt":"2027-06-30T23:59:59Z",
         "sections":[{"sectionId":"p1","title":"Parada 1"},{"sectionId":"p2","title":"Parada 2"}],
         "items":[{"webItemId":"wa","type":"TEXT","title":"A","required":false,"sectionId":"p1"},
                  {"webItemId":"wb","type":"TEXT","title":"B","required":false,"sectionId":"p1"},
                  {"webItemId":"wc","type":"TEXT","title":"C","required":false,"sectionId":"p2"}]}
        """
        return try JSONDecoder().decode(WebFormManifest.self, from: Data(json.utf8))
    }

    func testEstadoDeCadaParadaYMarcaDeVisto() throws {
        var store = almacen()
        store.merge(studentId: 7, clientSubmittedAt: "2026-10-28T10:00:00.000Z",
                    answers: [respuesta("b", texto: "dos"), respuesta("a", texto: "uno")], sectionIdByWebItemId: secciones)
        let roster = [WebRosterEntry(id: 7, name: "Prueba, Alba"), WebRosterEntry(id: 8, name: "Prueba, Bruno")]

        var vista = WebPassportProgress.build(
            formInstanceId: "f", title: "Pasaporte", groupName: "1º BAC", manifest: try manifiesto(),
            roster: roster, store: store
        )
        XCTAssertEqual(vista.stops.map(\.title), ["Parada 1", "Parada 2"])
        XCTAssertEqual(vista.rows[0].statuses, [.updated(at: "2026-10-28T10:00:00.000Z"), .empty])
        XCTAssertEqual(vista.rows[1].statuses, [.empty, .empty])
        XCTAssertEqual(vista.sentCount(stopIndex: 0), 1)
        XCTAssertEqual(vista.startedCount, 1)
        // Las respuestas salen en el orden del formulario, no en el de llegada.
        XCTAssertEqual(vista.rows[0].answersBySection["p1"]?.map(\.value), ["uno", "dos"])

        store.markSeen(studentId: 7)
        vista = WebPassportProgress.build(
            formInstanceId: "f", title: "Pasaporte", groupName: "1º BAC", manifest: try manifiesto(),
            roster: roster, store: store
        )
        XCTAssertEqual(vista.rows[0].statuses[0], .sent(at: "2026-10-28T10:00:00.000Z"))
    }

    // MARK: - Publicar

    func testElManifiestoDelPasaporteLlevaModoYParadas() throws {
        let publicado = try WebSubmissionPublisher.publish(
            title: "Pasaporte",
            subtitle: nil,
            locale: "es",
            sections: [WebSubmissionPublisher.SectionToPublish(sectionId: "p1", title: "Parada 1", help: nil)],
            items: [
                WebSubmissionPublisher.ItemToPublish(
                    itemId: "i1", title: "Mi mejor reto", type: .text, required: false,
                    options: [], helpText: nil, scaleLabels: nil, sectionId: "p1"
                ),
            ],
            students: [WebSubmissionPublisher.StudentToPublish(id: 1, name: "Prueba")],
            baseURL: "https://example.test",
            deliveryEmail: nil,
            expiresAtEpochMs: 1_900_000_000_000,
            mode: "passport"
        )
        let manifiesto = try JSONDecoder().decode(WebFormManifest.self, from: Data(publicado.manifestJSON.utf8))
        XCTAssertEqual(manifiesto.mode, "passport")
        XCTAssertEqual(manifiesto.sections?.map(\.sectionId), ["p1"])
        XCTAssertEqual(manifiesto.items.first?.sectionId, "p1")
        XCTAssertEqual(manifiesto.items.first?.required, false)
    }
}
