import XCTest
@testable import MiGestorKMPMac

/// Portal del alumnado: criptografía (vectores del contrato), almacén local,
/// contenido del tablón y flujo de invitar / cerrar con un servidor simulado.
final class WebPortalCryptoTests: XCTestCase {
    private let portalId = "AAECAwQFBgcICQoLDA0ODw"
    private let kTablon = Data(0x20...0x3F)
    private let nonce = Data(0x01...0x0C)

    func testVectoresDelContratoParaElCodigoDeAlta() throws {
        let claves = try WebPortalCrypto.deriveInvite(code: "K7M2XQ9PAB")
        XCTAssertEqual(WebPortalCrypto.hex(claves.raiz), "5341cfb433a99250df6fe0dca7ac8909fadb5fb7ee014315cac2bbebf75d8f23")
        XCTAssertEqual(claves.inviteId, "YTOXSxGhb28QvWd_4KCZrQ")
        XCTAssertEqual(claves.pruebaAlta, "3SGev2wOvjQby57XgPETsvYLhhuzkyr65NwuHRR_AWk")
        XCTAssertEqual(WebPortalCrypto.hex(claves.kAlta), "f995fde3d9ba93d812beba36a7e8e18788a0f18941d1e4fa6fd61b4a766aa893")
        XCTAssertEqual(claves.inviteIdHash, WebPortalCrypto.sha256Hex("YTOXSxGhb28QvWd_4KCZrQ"))
        XCTAssertEqual(claves.pruebaHash.count, 64)
    }

    func testSobresDeLaWebSeAbrenYSeReproducen() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Recursos/portal-v1.json")
        let raiz = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let entradas = try XCTUnwrap(raiz["entradas"] as? [String: Any])
        let sobres = try XCTUnwrap(raiz["sobres"] as? [String: Any])
        let tablon = Data(try XCTUnwrap(entradas["tablonJson"] as? String).utf8)
        let claves = try WebPortalCrypto.deriveInvite(code: "K7M2XQ9PAB")
        let alta = try WebPortalCrypto.Envelope(jsonObject: try XCTUnwrap(sobres["sobreAlta"] as? [String: Any]))
        let web = try WebPortalCrypto.Envelope(jsonObject: try XCTUnwrap(sobres["tablon"] as? [String: Any]))
        XCTAssertEqual(try WebPortalCrypto.seal(kTablon, key: claves.kAlta, context: .alta(portalId: portalId), nonce: nonce), alta)
        XCTAssertEqual(try WebPortalCrypto.seal(tablon, key: kTablon, context: .tablon(portalId: portalId, version: 1_763_491_200_000), nonce: nonce), web)
        XCTAssertEqual(try WebPortalCrypto.open(web, key: kTablon, context: .tablon(portalId: portalId, version: 1_763_491_200_000)), tablon)
    }

    func testCodigoGeneradoUsaSoloElAlfabetoSinAmbiguos() throws {
        for _ in 0..<50 {
            let code = try WebPortalCrypto.generateCode()
            XCTAssertEqual(code.count, 10)
            XCTAssertTrue(code.allSatisfy { WebPortalCrypto.codeAlphabet.contains($0) })
            XCTAssertNil(code.firstIndex(where: { "01IO".contains($0) }))
        }
        XCTAssertEqual(WebPortalCrypto.codeAlphabet.count, 32)
    }

    func testNormalizarCodigoEscrito() {
        XCTAssertEqual(WebPortalCrypto.normalizeCode(" k7m2x-q9pab "), "K7M2XQ9PAB")
        XCTAssertNil(WebPortalCrypto.normalizeCode("K7M2XQ9PA"))
        XCTAssertNil(WebPortalCrypto.normalizeCode("K7M2XQ9PA1"))
        XCTAssertNil(WebPortalCrypto.normalizeCode("K7M2XQ9PAO"))
        XCTAssertEqual(WebPortalCrypto.displayCode("K7M2XQ9PAB"), "K7M2X-Q9PAB")
    }

    func testSobreAbreSoloConSuContexto() throws {
        let sobre = try WebPortalCrypto.seal(Data("hola".utf8), key: kTablon, context: .tablon(portalId: portalId, version: 7), nonce: nonce)
        XCTAssertEqual(try WebPortalCrypto.open(sobre, key: kTablon, context: .tablon(portalId: portalId, version: 7)), Data("hola".utf8))
        XCTAssertThrowsError(try WebPortalCrypto.open(sobre, key: kTablon, context: .tablon(portalId: portalId, version: 8)))
        XCTAssertThrowsError(try WebPortalCrypto.open(sobre, key: kTablon, context: .tablon(portalId: "otro", version: 7)))
        XCTAssertThrowsError(try WebPortalCrypto.open(sobre, key: kTablon, context: .alta(portalId: portalId)))
        XCTAssertThrowsError(try WebPortalCrypto.open(sobre, key: Data(repeating: 1, count: 32), context: .tablon(portalId: portalId, version: 7)))
    }

    func testSobreConNonceFijoEsDeterministaYSerializaComoLaWeb() throws {
        let a = try WebPortalCrypto.seal(kTablon, key: kTablon, context: .alta(portalId: portalId), nonce: nonce)
        let b = try WebPortalCrypto.seal(kTablon, key: kTablon, context: .alta(portalId: portalId), nonce: nonce)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.nonce, WebPortalCrypto.base64URL(nonce))
        XCTAssertTrue(a.jsonString.hasPrefix("{\"v\":1,\"nonce\":\""))
        // cifrado (32 B) + etiqueta (16 B)
        XCTAssertEqual(WebPortalCrypto.fromBase64URL(a.ct)?.count, 48)
    }
}

final class WebPortalStoreTests: XCTestCase {
    private var directory: URL!
    private var service: String!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("portal-\(UUID().uuidString)")
        service = "com.migestor.portal.tests.\(UUID().uuidString)"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private var fileURL: URL { directory.appendingPathComponent("portal/alumnos.json") }

    func testGuardaYRelee() throws {
        var store = WebPortalStore(fileURL: fileURL, keychainService: service)
        store.set(WebPortalEntry(portalId: "AAA", estadoConocido: "pendiente", invitadoEl: 5, ultimaVersion: nil), for: 42)
        try store.save()
        let otra = WebPortalStore(fileURL: fileURL, keychainService: service)
        XCTAssertEqual(otra[42]?.portalId, "AAA")
        XCTAssertEqual(otra.studentId(forPortalId: "AAA"), 42)
        XCTAssertNil(otra[7])
    }

    func testMutarNoPisaLoEscritoPorOtro() throws {
        try WebPortalStore.mutate(fileURL: fileURL, keychainService: service) {
            $0.set(WebPortalEntry(portalId: "A", estadoConocido: "pendiente", invitadoEl: nil, ultimaVersion: nil), for: 1)
        }
        try WebPortalStore.mutate(fileURL: fileURL, keychainService: service) {
            $0.set(WebPortalEntry(portalId: "B", estadoConocido: "pendiente", invitadoEl: nil, ultimaVersion: nil), for: 2)
        }
        let store = WebPortalStore(fileURL: fileURL, keychainService: service)
        XCTAssertEqual(store.entries.count, 2)
    }

    func testFicheroNoContieneNombresNiClaves() throws {
        var store = WebPortalStore(fileURL: fileURL, keychainService: service)
        store.set(WebPortalEntry(portalId: "PORTAL", estadoConocido: "activada", invitadoEl: 1, ultimaVersion: 2), for: 9)
        try store.save()
        let texto = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(texto.contains("PORTAL"))
        XCTAssertFalse(texto.lowercased().contains("ktablon"))
    }

    func testLlaveDeTablonEnElLlavero() throws {
        let store = WebPortalStore(fileURL: fileURL, keychainService: service)
        let key = try WebPortalCrypto.newTablonKey()
        defer { store.deleteTablonKey(portalId: "P1") }
        guard store.saveTablonKey(key, portalId: "P1") else {
            throw XCTSkip("El llavero no está disponible en este entorno de pruebas.")
        }
        XCTAssertEqual(store.tablonKey(portalId: "P1"), key)
        XCTAssertNil(store.tablonKey(portalId: "P2"))
        XCTAssertFalse(store.saveTablonKey(Data(count: 5), portalId: "P3"))
        store.deleteTablonKey(portalId: "P1")
        XCTAssertNil(store.tablonKey(portalId: "P1"))
    }

    func testEstadoMuestraSinCorreoSoloSiNoHayCuenta() {
        let entry = WebPortalEntry(portalId: "A", estadoConocido: "pendiente", invitadoEl: nil, ultimaVersion: nil)
        XCTAssertEqual(WebPortalAccountStatus.resolve(hasEmail: false, entry: nil, server: nil), .sinCorreo)
        XCTAssertEqual(WebPortalAccountStatus.resolve(hasEmail: true, entry: nil, server: nil), .sinInvitar)
        XCTAssertEqual(WebPortalAccountStatus.resolve(hasEmail: false, entry: entry, server: .cuenta(invitacion: .ninguna)), .activada)
        XCTAssertEqual(WebPortalAccountStatus.resolve(hasEmail: true, entry: entry, server: .invitacionCaducada), .caducado)
        XCTAssertEqual(WebPortalAccountStatus.resolve(hasEmail: true, entry: entry, server: .invitacionPendiente), .pendiente)
        XCTAssertEqual(WebPortalAccountStatus.resolve(hasEmail: true, entry: entry, server: .ninguna), .sinCuenta)
        XCTAssertEqual(WebPortalAccountStatus.resolve(hasEmail: false, entry: entry, server: .invitacionPendiente), .pendiente)
        XCTAssertEqual(WebPortalAccountStatus.resolve(hasEmail: false, entry: entry, server: .invitacionCaducada), .caducado)
        XCTAssertEqual(WebPortalAccountStatus.resolve(hasEmail: false, entry: entry, server: .ninguna), .sinCorreo)
        // Sin red se usa el último estado conocido.
        XCTAssertEqual(WebPortalAccountStatus.resolve(hasEmail: true, entry: entry, server: nil), .pendiente)
    }
}

final class WebPortalPublisherTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_763_491_200)

    private func form(_ title: String, mode: String = "self", days: Double = 3, url: String? = "https://ejemplo.test/#f=1&a=2", done: Bool = false) -> WebPortalFormEntry {
        WebPortalFormEntry(title: title, context: "2º ESO B", mode: mode, expiresAt: now.addingTimeInterval(days * 86_400), url: url, done: done)
    }

    private func board(_ forms: [WebPortalFormEntry]) throws -> [String: Any] {
        let data = try WebPortalPublisher.buildBoard(portalId: "AAECAwQFBgcICQoLDA0ODw", forms: forms, now: now)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTablonSepararPendientesYHechos() throws {
        let json = try board([
            form("Autoevaluación"),
            form("Inscripción", done: true),
            form("Pasaporte", mode: "passport", days: 5, done: true),
            form("Caducada", days: -1),
            form("Sin https", url: "http://ejemplo.test/#f=1"),
        ])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        let pendientes = try XCTUnwrap(json["pendientes"] as? [[String: Any]])
        XCTAssertEqual(pendientes.map { $0["titulo"] as? String }, ["Autoevaluación", "Pasaporte"], "el pasaporte sigue pendiente aunque tenga envíos")
        XCTAssertEqual(pendientes.first?["tipo"] as? String, "autoevaluacion")
        XCTAssertEqual(pendientes.first?["contexto"] as? String, "2º ESO B")
        XCTAssertEqual(pendientes.first?["plazo"] as? String, "2025-11-21T18:40:00Z")
        let hechos = try XCTUnwrap(json["hechos"] as? [[String: String]])
        XCTAssertEqual(hechos, [["titulo": "Inscripción"]])
    }

    func testTipoPorModo() {
        XCTAssertEqual(WebPortalPublisher.boardType(mode: "peer"), "coevaluacion")
        XCTAssertEqual(WebPortalPublisher.boardType(mode: "passport"), "pasaporte")
        XCTAssertEqual(WebPortalPublisher.boardType(mode: "self"), "autoevaluacion")
    }

    func testAliasEstableYSinNombreReal() {
        let a = WebPortalPublisher.alias(for: "AAECAwQFBgcICQoLDA0ODw")
        XCTAssertEqual(a, WebPortalPublisher.alias(for: "AAECAwQFBgcICQoLDA0ODw"))
        XCTAssertNotNil(a.range(of: "^[a-z]+_[a-z]+$", options: .regularExpression))
    }

    func testVersionSiempreSube() {
        let ms = Int64(now.timeIntervalSince1970 * 1000)
        XCTAssertEqual(WebPortalPublisher.nextVersion(last: nil, now: now), ms)
        XCTAssertEqual(WebPortalPublisher.nextVersion(last: ms, now: now), ms + 1)
        XCTAssertEqual(WebPortalPublisher.nextVersion(last: ms + 500, now: now), ms + 501)
    }
}

/// Servidor simulado del portal.
final class WebPortalFakeServer: URLProtocol {
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
        let (code, data) = Self.handler?(request, body) ?? (200, Data("{}".utf8))
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class WebPortalFlowTests: XCTestCase {
    private var directory: URL!
    private var service: String!
    private var client: WebPortalClient!
    private let iterations = 1_000

    private var storeURL: URL { directory.appendingPathComponent("portal/alumnos.json") }

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("portal-\(UUID().uuidString)")
        service = "com.migestor.portal.tests.\(UUID().uuidString)"
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WebPortalFakeServer.self]
        client = WebPortalClient(url: "https://ejemplo.test/buzon/portal.php", session: URLSession(configuration: config))
        WebPortalFakeServer.requests = []
        WebPortalFakeServer.handler = nil
    }

    override func tearDown() {
        let store = WebPortalStore(fileURL: storeURL, keychainService: service)
        for entry in store.entries.values { store.deleteTablonKey(portalId: entry.portalId) }
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func json(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    func testInvitarCreaEntradaYLlaveYNoEnviaElCodigo() async throws {
        WebPortalFakeServer.handler = { _, _ in (200, Data("{\"caduca\":1764000000}".utf8)) }
        let result = try await WebPortalInviter.invite(
            studentIds: [1, 2], storeURL: storeURL, keychainService: service,
            client: client, accountKey: "cuenta-prueba", iterations: iterations
        )
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].code.count, 10)
        XCTAssertEqual(result[0].expires, Date(timeIntervalSince1970: 1_764_000_000))
        let (request, body) = try XCTUnwrap(WebPortalFakeServer.requests.first)
        XCTAssertEqual(request.url?.query, "accion=invitar")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer cuenta-prueba")
        let text = String(decoding: body, as: UTF8.self)
        for invitation in result { XCTAssertFalse(text.contains(invitation.code), "el código no viaja al servidor") }
        let items = try XCTUnwrap(json(body)["invitaciones"] as? [[String: Any]])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual((items[0]["inviteIdHash"] as? String)?.count, 64)

        // El sobreAlta abre con la llave derivada del código y trae K_tablon.
        let keys = try WebPortalCrypto.deriveInvite(code: result[0].code, iterations: iterations)
        let sobre = try WebPortalCrypto.Envelope(jsonObject: try XCTUnwrap(items[0]["sobreAlta"] as? [String: Any]))
        let kTablon = try WebPortalCrypto.open(sobre, key: keys.kAlta, context: .alta(portalId: result[0].portalId))
        let store = WebPortalStore(fileURL: storeURL, keychainService: service)
        guard let guardada = store.tablonKey(portalId: result[0].portalId) else {
            throw XCTSkip("El llavero no está disponible en este entorno de pruebas.")
        }
        XCTAssertEqual(guardada, kTablon)
        XCTAssertEqual(store[1]?.estadoConocido, "pendiente")
    }

    func testSiElServidorFallaNoQuedaNadaEnLocal() async throws {
        WebPortalFakeServer.handler = { _, _ in (500, Data()) }
        do {
            _ = try await WebPortalInviter.invite(
                studentIds: [1], storeURL: storeURL, keychainService: service,
                client: client, accountKey: "k", iterations: iterations
            )
            XCTFail("tenía que fallar")
        } catch {
            XCTAssertEqual(error as? WebSubmissionInbox.InboxError, .server(500))
        }
        XCTAssertTrue(WebPortalStore(fileURL: storeURL, keychainService: service).entries.isEmpty)
    }

    func testReinvitarConservaPortalIdYRotaLaLlave() async throws {
        WebPortalFakeServer.handler = { _, _ in (200, Data("{}".utf8)) }
        let first = try await WebPortalInviter.invite(
            studentIds: [1], storeURL: storeURL, keychainService: service, client: client, accountKey: "k", iterations: iterations
        )
        let store = WebPortalStore(fileURL: storeURL, keychainService: service)
        let oldKey = store.tablonKey(portalId: first[0].portalId)
        let second = try await WebPortalInviter.invite(
            studentIds: [1], storeURL: storeURL, keychainService: service, client: client, accountKey: "k", iterations: iterations
        )
        XCTAssertEqual(second[0].portalId, first[0].portalId)
        XCTAssertTrue(second[0].wasReinvite)
        XCTAssertNotEqual(second[0].code, first[0].code)
        if let oldKey {
            XCTAssertNotEqual(store.tablonKey(portalId: first[0].portalId), oldKey)
        }
    }

    func testCerrarBorraEntradaYLlave() async throws {
        WebPortalFakeServer.handler = { _, _ in (200, Data("{\"cerradas\":1}".utf8)) }
        let invited = try await WebPortalInviter.invite(
            studentIds: [1], storeURL: storeURL, keychainService: service, client: client, accountKey: "k", iterations: iterations
        )
        try await WebPortalInviter.close(studentIds: [1], storeURL: storeURL, keychainService: service, client: client, accountKey: "k")
        let store = WebPortalStore(fileURL: storeURL, keychainService: service)
        XCTAssertNil(store[1])
        XCTAssertNil(store.tablonKey(portalId: invited[0].portalId))
        XCTAssertEqual(WebPortalFakeServer.requests.last?.request.url?.query, "accion=cerrar")
    }

    func testEstadoTraduceLaRespuestaDelServidor() async throws {
        WebPortalFakeServer.handler = { _, _ in
            (200, Data("""
            {"estados":{"a":{"cuenta":true,"invitacion":"ninguna"},"b":{"cuenta":false,"invitacion":"pendiente"},
            "c":{"cuenta":false,"invitacion":"caducada"},"d":{"cuenta":false,"invitacion":"ninguna"},"e":{"cuenta":true,"invitacion":"pendiente"}}}
            """.utf8))
        }
        let states = try await client.state(portalIds: ["a", "b", "c", "d", "e"], accountKey: "k")
        XCTAssertEqual(states["a"], .cuenta(invitacion: .ninguna))
        XCTAssertEqual(states["b"], .invitacionPendiente)
        XCTAssertEqual(states["c"], .invitacionCaducada)
        XCTAssertEqual(states["d"], .ninguna)
        XCTAssertEqual(states["e"], .cuenta(invitacion: .pendiente))
    }

    func testPublicarCifraElTablonYGuardaLaVersion() async throws {
        WebPortalFakeServer.handler = { request, body in
            if request.url?.query == "accion=invitar" { return (200, Data("{}".utf8)) }
            let ids = (self.json(body)["tablones"] as? [[String: Any]])?.compactMap { $0["portalId"] as? String } ?? []
            let results = ids.map { "{\"portalId\":\"\($0)\",\"ok\":true}" }.joined(separator: ",")
            return (200, Data("{\"resultados\":[\(results)]}".utf8))
        }
        let invited = try await WebPortalInviter.invite(
            studentIds: [1], storeURL: storeURL, keychainService: service, client: client, accountKey: "k", iterations: iterations
        )
        let store = WebPortalStore(fileURL: storeURL, keychainService: service)
        guard let key = store.tablonKey(portalId: invited[0].portalId) else {
            throw XCTSkip("El llavero no está disponible en este entorno de pruebas.")
        }
        let now = Date(timeIntervalSince1970: 1_763_491_200)
        let form = WebPortalFormEntry(title: "Autoevaluación", context: "2º ESO B", mode: "self",
                                      expiresAt: now.addingTimeInterval(86_400), url: "https://ejemplo.test/#f=1&a=2", done: false)
        let outcome = await WebPortalPublisher.publish(
            inputs: [.init(studentId: 1, forms: [form]), .init(studentId: 99, forms: [form])],
            storeURL: storeURL, keychainService: service, client: client, accountKey: "k", now: now
        )
        XCTAssertEqual(outcome.published, 1, "el alumno sin portal se salta")
        let (_, body) = try XCTUnwrap(WebPortalFakeServer.requests.last)
        let item = try XCTUnwrap((json(body)["tablones"] as? [[String: Any]])?.first)
        let version = try XCTUnwrap(item["version"] as? Int64)
        let sobre = try WebPortalCrypto.Envelope(jsonObject: try XCTUnwrap(item["sobre"] as? [String: Any]))
        let abierto = try WebPortalCrypto.open(sobre, key: key, context: .tablon(portalId: invited[0].portalId, version: version))
        XCTAssertTrue(String(decoding: abierto, as: UTF8.self).contains("Autoevaluación"))
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("Autoevaluación"), "el título no viaja en claro")
        XCTAssertEqual(WebPortalStore(fileURL: storeURL, keychainService: service)[1]?.ultimaVersion, version)
    }

    // MARK: Rotación diferida de K_tablon

    private func markActive(_ studentId: Int64) throws {
        try WebPortalStore.mutate(fileURL: storeURL, keychainService: service) {
            guard var e = $0[studentId] else { return }
            e.estadoConocido = "activada"
            $0.set(e, for: studentId)
        }
    }

    func testReinvitarConCuentaActivaDejaLaLlaveEnPendiente() async throws {
        WebPortalFakeServer.handler = { _, _ in (200, Data("{}".utf8)) }
        let first = try await WebPortalInviter.invite(
            studentIds: [1], storeURL: storeURL, keychainService: service, client: client, accountKey: "k", iterations: iterations
        )
        let id = first[0].portalId
        let store = WebPortalStore(fileURL: storeURL, keychainService: service)
        guard let current = store.tablonKey(portalId: id) else { throw XCTSkip("Sin llavero en este entorno.") }
        try markActive(1)
        _ = try await WebPortalInviter.invite(
            studentIds: [1], storeURL: storeURL, keychainService: service, client: client, accountKey: "k", iterations: iterations
        )
        XCTAssertEqual(store.tablonKey(portalId: id), current, "se sigue publicando con la llave actual")
        let pending = try XCTUnwrap(store.pendingKey(portalId: id))
        XCTAssertNotEqual(pending, current)
        XCTAssertEqual(WebPortalStore(fileURL: storeURL, keychainService: service)[1]?.estadoConocido, "activada")

        // Aún sin canjear: no se toca nada.
        XCTAssertTrue(WebPortalInviter.resolvePending(states: [id: .cuenta(invitacion: .pendiente)], storeURL: storeURL, keychainService: service).isEmpty)
        XCTAssertEqual(store.tablonKey(portalId: id), current)
        // Canjeó: la pendiente es la llave.
        XCTAssertEqual(WebPortalInviter.resolvePending(states: [id: .cuenta(invitacion: .ninguna)], storeURL: storeURL, keychainService: service), [1])
        XCTAssertEqual(store.tablonKey(portalId: id), pending)
        XCTAssertNil(store.pendingKey(portalId: id))
    }

    func testPendienteSeDescartaSiCaducaYSiElServidorFalla() async throws {
        WebPortalFakeServer.handler = { _, _ in (200, Data("{}".utf8)) }
        let first = try await WebPortalInviter.invite(
            studentIds: [1], storeURL: storeURL, keychainService: service, client: client, accountKey: "k", iterations: iterations
        )
        let id = first[0].portalId
        let store = WebPortalStore(fileURL: storeURL, keychainService: service)
        guard let current = store.tablonKey(portalId: id) else { throw XCTSkip("Sin llavero en este entorno.") }
        try markActive(1)

        // Servidor falla: no queda pendiente.
        WebPortalFakeServer.handler = { _, _ in (500, Data()) }
        do {
            _ = try await WebPortalInviter.invite(studentIds: [1], storeURL: storeURL, keychainService: service, client: client, accountKey: "k", iterations: iterations)
            XCTFail("tenía que fallar")
        } catch {}
        XCTAssertNil(store.pendingKey(portalId: id))
        XCTAssertEqual(store.tablonKey(portalId: id), current)

        // Caduca: se descarta.
        WebPortalFakeServer.handler = { _, _ in (200, Data("{}".utf8)) }
        _ = try await WebPortalInviter.invite(studentIds: [1], storeURL: storeURL, keychainService: service, client: client, accountKey: "k", iterations: iterations)
        XCTAssertNotNil(store.pendingKey(portalId: id))
        WebPortalInviter.resolvePending(states: [id: .cuenta(invitacion: .caducada)], storeURL: storeURL, keychainService: service)
        XCTAssertNil(store.pendingKey(portalId: id))
        XCTAssertEqual(store.tablonKey(portalId: id), current)
    }

    func testElPublicadorPromueveLaPendienteSiYaCanjeo() async throws {
        WebPortalFakeServer.handler = { _, _ in (200, Data("{}".utf8)) }
        let first = try await WebPortalInviter.invite(
            studentIds: [1], storeURL: storeURL, keychainService: service, client: client, accountKey: "k", iterations: iterations
        )
        let id = first[0].portalId
        let store = WebPortalStore(fileURL: storeURL, keychainService: service)
        guard store.tablonKey(portalId: id) != nil else { throw XCTSkip("Sin llavero en este entorno.") }
        try markActive(1)
        _ = try await WebPortalInviter.invite(studentIds: [1], storeURL: storeURL, keychainService: service, client: client, accountKey: "k", iterations: iterations)
        let pending = try XCTUnwrap(store.pendingKey(portalId: id))

        WebPortalFakeServer.handler = { request, body in
            if request.url?.query == "accion=estado" {
                return (200, Data("{\"estados\":{\"\(id)\":{\"cuenta\":true,\"invitacion\":\"ninguna\"}}}".utf8))
            }
            return (200, Data("{\"resultados\":[{\"portalId\":\"\(id)\",\"ok\":true}]}".utf8))
        }
        let now = Date(timeIntervalSince1970: 1_763_491_200)
        _ = await WebPortalPublisher.publish(inputs: [.init(studentId: 1, forms: [])], storeURL: storeURL, keychainService: service, client: client, accountKey: "k", now: now)
        XCTAssertEqual(store.tablonKey(portalId: id), pending)
        let (_, body) = try XCTUnwrap(WebPortalFakeServer.requests.last)
        let item = try XCTUnwrap((json(body)["tablones"] as? [[String: Any]])?.first)
        let sobre = try WebPortalCrypto.Envelope(jsonObject: try XCTUnwrap(item["sobre"] as? [String: Any]))
        XCTAssertNoThrow(try WebPortalCrypto.open(sobre, key: pending, context: .tablon(portalId: id, version: try XCTUnwrap(item["version"] as? Int64))))
    }

    func testRechazaServidorSinHttps() async {
        let inseguro = WebPortalClient(url: "http://ejemplo.test/buzon/portal.php", session: client.session)
        do {
            _ = try await inseguro.state(portalIds: ["a"], accountKey: "k")
            XCTFail("tenía que rechazar http")
        } catch {
            XCTAssertEqual(error as? WebSubmissionInbox.InboxError, .network)
        }
        XCTAssertTrue(WebPortalFakeServer.requests.isEmpty)
    }
}

#if os(macOS)
import AppKit
import SwiftUI

/// Regresión: abrir «Portal del alumnado» cerraba la app en macOS. La hoja pedía
/// más alto que la ventana principal (900x450) y AppKit entraba en un bucle de
/// Update Constraints que acababa en NSGenericException.
@MainActor
final class WebPortalSheetLayoutTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("portal-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private let students = [
        WebPortalStudent(id: 1, firstName: "Aitana", lastName: "Prueba Ruiz", email: "aitana.prueba@centro.example"),
        WebPortalStudent(id: 2, firstName: "Bruno", lastName: "Ficticio Gil", email: "bruno.ficticio@centro.example"),
        WebPortalStudent(id: 3, firstName: "Dani", lastName: "Ejemplo Mora", email: nil),
    ]

    private func makeModel(failing: Bool) throws -> WebPortalViewModel {
        let url = directory.appendingPathComponent("portal/alumnos.json")
        if failing {
            // Con una entrada local y un servidor que falla la hoja muestra el banner de error.
            try WebPortalStore.mutate(fileURL: url) {
                $0.set(WebPortalEntry(portalId: "AAECAwQFBgcICQoLDA0ODw", estadoConocido: "pendiente", invitadoEl: nil, ultimaVersion: nil), for: 1)
            }
        }
        let model = WebPortalViewModel(baseURL: "https://ejemplo.test", storeURL: url, republish: {})
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WebPortalFakeServer.self]
        WebPortalFakeServer.handler = { _, _ in (500, Data()) }
        model.session = URLSession(configuration: config)
        return model
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Mete la hoja en una ventana de 900x450 y fuerza varias pasadas de layout.
    /// Muchas columnas que cuentan: la lista de «Notas visibles» es la más alta de la hoja.
    private static let manyColumns = WebPortalGradeOverview(
        classId: 1,
        studentCount: 24,
        columns: (1...14).map {
            WebPortalGradeColumnRow(id: "c\($0)", title: "Columna de prueba número \($0)", typeLabel: "Rúbrica", weightPercent: 7, withGrade: 20, total: 24)
        }
    )

    private func present(
        failing: Bool,
        asSheet: Bool,
        section: WebPortalSheet.PortalSection = .cuentas,
        overview: WebPortalGradeOverview? = nil
    ) async throws -> NSWindow {
        let model = try makeModel(failing: failing)
        let students = self.students
        let sheet = WebPortalSheet(
            groups: [.init(id: 1, name: "3 ESO A")],
            classId: 1,
            model: model,
            loadStudents: { _ in students },
            gradesSettingsURL: directory.appendingPathComponent("portal/notas-visibles.json"),
            loadGrades: { _, _ in overview },
            initialSection: section
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 450),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        if asSheet {
            struct Host: View {
                let sheet: WebPortalSheet
                @State private var shown = true
                var body: some View {
                    Color.clear.frame(width: 900, height: 450).sheet(isPresented: $shown) { sheet }
                }
            }
            window.contentViewController = NSHostingController(rootView: Host(sheet: sheet))
        } else {
            window.contentViewController = NSHostingController(rootView: sheet)
        }
        window.setContentSize(NSSize(width: 900, height: 450))
        window.makeKeyAndOrderFront(nil)
        for _ in 0..<8 {
            window.layoutIfNeeded()
            spin(0.15)
        }
        return window
    }

    func testHojaConErrorNoDesestabilizaLaVentana() async throws {
        let window = try await present(failing: true, asSheet: true)
        XCTAssertEqual(window.contentLayoutRect.height, 450, accuracy: 1, "la ventana principal no debe crecer")
        for sheet in window.sheets {
            XCTAssertLessThanOrEqual(sheet.frame.height, 450, "la hoja no puede ser más alta que su ventana")
        }
        window.orderOut(nil)
    }

    func testHojaCargadaNoDesestabilizaLaVentana() async throws {
        let window = try await present(failing: false, asSheet: true)
        XCTAssertEqual(window.contentLayoutRect.height, 450, accuracy: 1)
        for sheet in window.sheets {
            XCTAssertLessThanOrEqual(sheet.frame.height, 450, "la hoja no puede ser más alta que su ventana")
        }
        window.orderOut(nil)
    }

    func testPestanaNotasVisiblesNoDesestabilizaLaVentana() async throws {
        for overview in [Self.manyColumns, nil] {
            let window = try await present(failing: false, asSheet: true, section: .notas, overview: overview)
            XCTAssertEqual(window.contentLayoutRect.height, 450, accuracy: 1, "la ventana principal no debe crecer")
            for sheet in window.sheets {
                XCTAssertLessThanOrEqual(sheet.frame.height, 450, "la hoja no puede ser más alta que su ventana")
            }
            window.orderOut(nil)
        }
    }

    func testPestanaNotasVisiblesComoContenidoDeUnaVentanaPequena() async throws {
        let window = try await present(failing: true, asSheet: false, section: .notas, overview: Self.manyColumns)
        window.layoutIfNeeded()
        XCTAssertLessThanOrEqual(window.contentLayoutRect.height, 450.5, "la hoja no debe agrandar una ventana de 450")
        window.orderOut(nil)
    }

    func testHojaComoContenidoDeUnaVentanaPequena() async throws {
        let window = try await present(failing: true, asSheet: false)
        window.layoutIfNeeded()
        XCTAssertLessThanOrEqual(window.contentLayoutRect.height, 450.5, "la hoja no debe agrandar una ventana de 450")
        window.orderOut(nil)
    }

    func testTarjetaDeCodigoYVistaPreviaSeMidenSinBucle() throws {
        let card = WebPortalCodeCard(studentName: "Aitana Prueba Ruiz", code: "K7M2X-Q9PAB", link: "https://ejemplo.test/#portal/alta=K7M2XQ9PAB")
        let preview = WebPortalMailPreview(targets: students, baseURL: "https://ejemplo.test", onCancel: {}, onConfirm: {})
        for view in [AnyView(WebPortalCodeCardView(card: card)), AnyView(preview)] {
            let host = NSHostingController(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 450), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentViewController = host
            window.makeKeyAndOrderFront(nil)
            for _ in 0..<4 { window.layoutIfNeeded(); spin(0.1) }
            XCTAssertGreaterThan(host.view.fittingSize.height, 100)
            window.orderOut(nil)
        }
    }
}
#endif
