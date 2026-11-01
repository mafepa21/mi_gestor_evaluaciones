import XCTest
@testable import MiGestorKMPMac

/// Buzón de entregas: cliente HTTP (con un servidor simulado) y publicación con buzón.
final class WebSubmissionInboxTests: XCTestCase {
    /// Responde lo que diga `handler` y guarda cada petición.
    final class FakeServer: URLProtocol {
        nonisolated(unsafe) static var handler: ((URLRequest, Data) -> (Int, Data))?
        nonisolated(unsafe) static var requests: [(request: URLRequest, body: Data)] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let body = request.httpBody ?? request.httpBodyStream.map { stream in
                stream.open(); defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    if read <= 0 { break }
                    data.append(buffer, count: read)
                }
                return data
            } ?? Data()
            Self.requests.append((request, body))
            let (code, data) = Self.handler?(request, body) ?? (200, Data("{\"ok\":true}".utf8))
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private var session: URLSession!
    private var client: WebSubmissionInboxClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeServer.self]
        session = URLSession(configuration: config)
        FakeServer.requests = []
        FakeServer.handler = nil
        client = WebSubmissionInboxClient(url: "https://ejemplo.test/buzon/buzon.php", session: session)
    }

    private func json(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    // MARK: Claves

    func testClaveAleatoriaDe43Caracteres() {
        let token = WebSubmissionInbox.randomToken()
        XCTAssertEqual(token.count, 43)
        XCTAssertNil(token.range(of: "[^A-Za-z0-9_-]", options: .regularExpression))
        XCTAssertNotEqual(token, WebSubmissionInbox.randomToken())
    }

    func testHuellaEsSHA256EnHexadecimal() {
        // printf '%s' abc | sha256sum
        XCTAssertEqual(
            WebSubmissionInbox.fingerprint("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testURLDelBuzon() {
        XCTAssertEqual(WebSubmissionInbox.url(baseURL: "https://a.net/"), "https://a.net/buzon/buzon.php")
        XCTAssertEqual(WebSubmissionInbox.url(baseURL: "https://a.net"), "https://a.net/buzon/buzon.php")
    }

    // MARK: Cliente

    func testRegistrarMandaSoloHuellas() async throws {
        try await client.register(
            formInstanceId: "F1", accountKey: "cuenta", depositToken: "deposito", readToken: "lectura",
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000), aliases: ["a1", "a2"]
        )
        let sent = try XCTUnwrap(FakeServer.requests.first)
        XCTAssertEqual(sent.request.url?.query, "accion=registrar")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Authorization"), "Bearer cuenta")
        let body = json(sent.body)
        XCTAssertEqual(body["depositHash"] as? String, WebSubmissionInbox.fingerprint("deposito"))
        XCTAssertEqual(body["readHash"] as? String, WebSubmissionInbox.fingerprint("lectura"))
        XCTAssertEqual(body["aliasHashes"] as? [String], ["a1", "a2"].map(WebSubmissionInbox.fingerprint))
        XCTAssertEqual(body["expiresAt"] as? Int, 2_000_000_000)
        let texto = String(decoding: sent.body, as: UTF8.self)
        XCTAssertFalse(texto.contains("\"deposito\"") || texto.contains("\"lectura\""), "las claves no viajan en claro")
    }

    func testRecogerDevuelveLosSobres() async throws {
        FakeServer.handler = { _, _ in
            (200, Data(#"{"ok":true,"entregas":[{"participantAlias":"AL1","submissionId":"s1","formInstanceId":"F1"},{"submissionId":"sin-alias"}]}"#.utf8))
        }
        let result = try await client.collect(formInstanceId: "F1", readToken: "lectura")
        XCTAssertEqual(result.map(\.submissionId), ["s1"])
        XCTAssertEqual(result.first?.alias, "AL1")
        XCTAssertEqual(json(result[0].data)["formInstanceId"] as? String, "F1")
        XCTAssertEqual(FakeServer.requests.first?.request.value(forHTTPHeaderField: "X-Buzon-Token"), "lectura")
    }

    func testBorrarMandaAliasYEnvio() async throws {
        try await client.delete(formInstanceId: "F1", readToken: "lectura", entries: [("AL1", "s1")])
        let body = json(try XCTUnwrap(FakeServer.requests.first).body)
        XCTAssertEqual(body["entregas"] as? [[String: String]], [["alias": "AL1", "submissionId": "s1"]])
    }

    func testBorrarNadaNoLlamaAlServidor() async throws {
        try await client.delete(formInstanceId: "F1", readToken: "lectura", entries: [])
        XCTAssertTrue(FakeServer.requests.isEmpty)
    }

    func testErroresDelServidor() async {
        FakeServer.handler = { _, _ in (401, Data()) }
        do {
            _ = try await client.collect(formInstanceId: "F1", readToken: "mala")
            XCTFail("debía fallar")
        } catch {
            XCTAssertEqual(error as? WebSubmissionInbox.InboxError, .unauthorized)
        }
        FakeServer.handler = { _, _ in (500, Data()) }
        do {
            _ = try await client.collect(formInstanceId: "F1", readToken: "x")
            XCTFail("debía fallar")
        } catch {
            XCTAssertEqual(error as? WebSubmissionInbox.InboxError, .server(500))
        }
    }

    // MARK: Publicar con buzón

    private func publish(inbox: Bool) throws -> WebSubmissionPublisher.PublishedForm {
        try WebSubmissionPublisher.publish(
            title: "Inscripción", subtitle: nil, locale: "es", sections: [],
            items: [.init(itemId: "participa", title: "¿Participas?", type: .choice, required: true,
                          options: ["Sí", "No"], helpText: nil, scaleLabels: nil, sectionId: nil)],
            students: [.init(id: 1, name: "Ana Prueba")],
            baseURL: "https://ejemplo.test", deliveryEmail: nil,
            expiresAtEpochMs: 2_000_000_000_000,
            inboxPath: inbox ? WebSubmissionInbox.path : nil,
            depositToken: inbox ? "T".padding(toLength: 43, withPad: "T", startingAt: 0) : nil
        )
    }

    func testConBuzonElManifiestoLoLlevaFirmadoYElEnlaceLaClave() throws {
        let form = try publish(inbox: true)
        XCTAssertTrue(form.manifestJSON.contains("\"inbox\" : \"\\/buzon\\/buzon.php\"") || form.manifestJSON.contains("\"inbox\" : \"/buzon/buzon.php\""))
        XCTAssertNoThrow(try WebSubmissionCrypto.verifyManifestSignature(rawManifestJSON: Data(form.manifestJSON.utf8)))
        XCTAssertTrue(form.links[0].url.contains("&b=" + String(repeating: "T", count: 43)))
    }

    func testSinBuzonTodoComoAntes() throws {
        let form = try publish(inbox: false)
        XCTAssertFalse(form.manifestJSON.contains("inbox"))
        XCTAssertFalse(form.links[0].url.contains("&b="))
    }
}
