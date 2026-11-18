// Comprobador de interoperabilidad del portal del alumnado (Swift <-> web).
//
// Se compila con el `WebPortalCrypto.swift` real de la app (ver `verificar.sh`):
//
//   swiftc -O kmp/iosApp/AppleShared/WebPortalCrypto.swift \
//          scripts/interop_entregas_web/portal/main.swift -o $TMPDIR/interop_portal
//   $TMPDIR/interop_portal [fixture.json] [salida.json]
//
// Comprueba los vectores del contrato (sección 4). Si hay fixture de la web
// (`portal-v1.json`, de `npm run fixture`), también que Swift abre los sobres de la
// web y produce el mismo `ct` con nonce fijo. Al final escribe `salida.json` con
// un sobreAlta y un tablón cifrados por Swift para que la web los abra después.
import Foundation
import CryptoKit

var fallos = 0
func comprobar(_ ok: Bool, _ texto: String) {
    print("  \(ok ? "ok   " : "FALLA") \(texto)")
    if !ok { fallos += 1 }
}

let codigo = "K7M2XQ9PAB"
let portalId = "AAECAwQFBgcICQoLDA0ODw"
let kTablon = Data(0x20...0x3F)
let nonce = Data(0x01...0x0C)
let version: Int64 = 1_763_491_200_000

let args = CommandLine.arguments
let rutaFixture = args.count > 1 ? args[1] : "kmp/iosApp/PlannerTests/Recursos/portal-v1.json"
let rutaSalida = args.count > 2 ? args[2] : (ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp") + "/portal-swift.json"

print("Código y derivación")
do {
    comprobar(WebPortalCrypto.normalizeCode("k7m2x-q9pab") == codigo, "normaliza minúsculas, guion y espacios")
    comprobar(WebPortalCrypto.normalizeCode("K7M2XQ9PA") == nil, "rechaza longitud incorrecta")
    comprobar(WebPortalCrypto.normalizeCode("K7M2XQ9PA0") == nil, "rechaza el carácter 0")
    comprobar(WebPortalCrypto.displayCode(codigo) == "K7M2X-Q9PAB", "se muestra XXXXX-XXXXX")
    let generado = try WebPortalCrypto.generateCode()
    comprobar(WebPortalCrypto.normalizeCode(generado) == generado, "el código generado es válido (\(generado.count) caracteres)")

    let claves = try WebPortalCrypto.deriveInvite(code: codigo)
    comprobar(WebPortalCrypto.hex(claves.raiz) == "5341cfb433a99250df6fe0dca7ac8909fadb5fb7ee014315cac2bbebf75d8f23", "raíz PBKDF2")
    comprobar(claves.inviteId == "YTOXSxGhb28QvWd_4KCZrQ", "inviteId")
    comprobar(claves.pruebaAlta == "3SGev2wOvjQby57XgPETsvYLhhuzkyr65NwuHRR_AWk", "pruebaAlta")
    comprobar(WebPortalCrypto.hex(claves.kAlta) == "f995fde3d9ba93d812beba36a7e8e18788a0f18941d1e4fa6fd61b4a766aa893", "kAlta")
    comprobar(claves.inviteIdHash == WebPortalCrypto.sha256Hex(claves.inviteId) && claves.inviteIdHash.count == 64, "inviteIdHash = SHA-256 hex del texto b64u")
    comprobar(claves.pruebaHash == WebPortalCrypto.sha256Hex(claves.pruebaAlta) && claves.pruebaHash.count == 64, "pruebaHash = SHA-256 hex del texto b64u")

    print("Sobres")
    let sobreAlta = try WebPortalCrypto.seal(kTablon, key: claves.kAlta, context: .alta(portalId: portalId), nonce: nonce)
    comprobar(try WebPortalCrypto.open(sobreAlta, key: claves.kAlta, context: .alta(portalId: portalId)) == kTablon, "sobreAlta: ida y vuelta")
    comprobar(sobreAlta.nonce == WebPortalCrypto.base64URL(nonce), "el nonce fijo viaja en el sobre")
    let otroNonce = try WebPortalCrypto.seal(kTablon, key: claves.kAlta, context: .alta(portalId: portalId))
    comprobar(otroNonce.nonce != sobreAlta.nonce, "sin nonce fijo se usa uno al azar")

    // Fixture de la web: el tablón son los bytes literales de `entradas.tablonJson`.
    let fixture = FileManager.default.contents(atPath: rutaFixture)
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    let tablonTexto = (fixture?["entradas"] as? [String: Any])?["tablonJson"] as? String
        ?? "{\"schemaVersion\":1,\"alias\":\"tigre_azul\",\"actualizado\":\"2026-11-18T18:40:00Z\",\"pendientes\":[],\"hechos\":[]}"
    let tablonJSON = Data(tablonTexto.utf8)
    let sobreTablon = try WebPortalCrypto.seal(tablonJSON, key: kTablon, context: .tablon(portalId: portalId, version: version), nonce: nonce)
    comprobar(try WebPortalCrypto.open(sobreTablon, key: kTablon, context: .tablon(portalId: portalId, version: version)) == tablonJSON, "tablón: ida y vuelta")

    func falla(_ cuerpo: () throws -> Data) -> Bool { (try? cuerpo()) == nil }
    comprobar(falla { try WebPortalCrypto.open(sobreTablon, key: kTablon, context: .tablon(portalId: portalId, version: version + 1)) }, "el tablón no abre con otra version")
    comprobar(falla { try WebPortalCrypto.open(sobreTablon, key: kTablon, context: .tablon(portalId: "AAAAAAAAAAAAAAAAAAAAAA", version: version)) }, "el tablón no abre con otro portalId")
    comprobar(falla { try WebPortalCrypto.open(sobreAlta, key: claves.kAlta, context: .cuenta(portalId: portalId)) }, "el sobreAlta no abre con AAD de cuenta")
    comprobar(falla { try WebPortalCrypto.open(sobreAlta, key: kTablon, context: .alta(portalId: portalId)) }, "el sobreAlta no abre con otra llave")
    var roto = Array(WebPortalCrypto.fromBase64URL(sobreAlta.ct)!)
    roto[0] ^= 1
    let rotoSobre = WebPortalCrypto.Envelope(nonce: sobreAlta.nonce, ct: WebPortalCrypto.base64URL(Data(roto)))
    comprobar(falla { try WebPortalCrypto.open(rotoSobre, key: claves.kAlta, context: .alta(portalId: portalId)) }, "un bit cambiado en ct se detecta")

    print("Fixture de la web")
    if let fixture {
        let esperados = fixture["esperados"] as? [String: Any] ?? [:]
        let sobres = fixture["sobres"] as? [String: Any] ?? [:]
        comprobar(true, "fixture leído: \(rutaFixture)")
        comprobar(claves.inviteIdHash == esperados["inviteIdHash"] as? String, "inviteIdHash coincide con la web")
        comprobar(claves.pruebaHash == esperados["pruebaHash"] as? String, "pruebaHash coincide con la web")
        comprobar(WebPortalCrypto.hex(Data(SHA256.hash(data: tablonJSON))) == esperados["tablonSha256"] as? String, "SHA-256 del tablón literal coincide")
        for (nombre, propio, contexto, llave) in [
            ("sobreAlta", sobreAlta, WebPortalCrypto.Context.alta(portalId: portalId), claves.kAlta),
            ("tablon", sobreTablon, WebPortalCrypto.Context.tablon(portalId: portalId, version: version), kTablon),
        ] {
            guard let obj = sobres[nombre] as? [String: Any], let web = try? WebPortalCrypto.Envelope(jsonObject: obj) else {
                comprobar(false, "el fixture no trae `sobres.\(nombre)`"); continue
            }
            comprobar(propio == web, "\(nombre): mismo ct con nonce fijo que la web")
            comprobar((try? WebPortalCrypto.open(web, key: llave, context: contexto)) != nil, "Swift abre el \(nombre) de la web")
        }
        if let obj = sobres["sobreCuenta"] as? [String: Any], let web = try? WebPortalCrypto.Envelope(jsonObject: obj) {
            comprobar((try? WebPortalCrypto.open(web, key: Data(hexString: "115303a3e8c4fd4dfcf19302a4bd1a012c5b35a1832a8fc56e9c9f085fecffa2"), context: .cuenta(portalId: portalId))) == kTablon, "Swift abre el sobreCuenta de la web")
        }
    } else {
        print("  OMITIDO: no hay fixture en \(rutaFixture)")
    }

    // Salida para que la web abra lo cifrado por Swift.
    let salida: [String: Any] = [
        "codigo": codigo,
        "portalId": portalId,
        "version": String(version),
        "kTablonHex": WebPortalCrypto.hex(kTablon),
        "nonceHex": WebPortalCrypto.hex(nonce),
        "inviteId": claves.inviteId,
        "pruebaAlta": claves.pruebaAlta,
        "sobreAlta": sobreAlta.jsonObject,
        "tablonJson": String(decoding: tablonJSON, as: UTF8.self),
        "tablon": sobreTablon.jsonObject,
    ]
    try JSONSerialization.data(withJSONObject: salida, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: rutaSalida))
    print("Escrito \(rutaSalida)")
} catch {
    comprobar(false, "error inesperado: \(error)")
}

print(fallos == 0 ? "\nTodo en verde." : "\n\(fallos) comprobaciones fallan.")
exit(fallos == 0 ? 0 : 1)

extension Data {
    init(hexString: String) {
        var bytes = [UInt8]()
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            bytes.append(UInt8(hexString[index..<next], radix: 16) ?? 0)
            index = next
        }
        self.init(bytes)
    }
}
