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

    let tablonJSON = Data("{\"schemaVersion\":1,\"alias\":\"tigre_azul\",\"actualizado\":\"2026-11-18T18:40:00Z\",\"pendientes\":[],\"hechos\":[]}".utf8)
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

    // Fixture de la web (opcional hasta que exista `npm run fixture`).
    print("Fixture de la web")
    if let datos = FileManager.default.contents(atPath: rutaFixture),
       let raiz = try JSONSerialization.jsonObject(with: datos) as? [String: Any] {
        comprobar(true, "fixture leído: \(rutaFixture)")
        func sobre(_ clave: String) -> WebPortalCrypto.Envelope? {
            if let obj = raiz[clave] as? [String: Any] { return try? WebPortalCrypto.Envelope(jsonObject: obj) }
            if let t = raiz[clave] as? String, let d = t.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { return try? WebPortalCrypto.Envelope(jsonObject: obj) }
            return nil
        }
        if let webAlta = sobre("sobreAlta") {
            comprobar(webAlta == sobreAlta, "mismo sobreAlta (nonce fijo) que la web")
            comprobar((try? WebPortalCrypto.open(webAlta, key: claves.kAlta, context: .alta(portalId: portalId))) == kTablon, "Swift abre el sobreAlta de la web")
        } else { comprobar(false, "el fixture no trae `sobreAlta`") }
        if let webTablon = sobre("sobreTablon") ?? sobre("tablon") {
            let abierto = try? WebPortalCrypto.open(webTablon, key: kTablon, context: .tablon(portalId: portalId, version: version))
            comprobar(abierto != nil, "Swift abre el tablón de la web")
            if let abierto {
                let propio = try WebPortalCrypto.seal(abierto, key: kTablon, context: .tablon(portalId: portalId, version: version), nonce: nonce)
                comprobar(propio == webTablon, "mismo tablón cifrado (nonce fijo) que la web")
            }
        } else { comprobar(false, "el fixture no trae el tablón cifrado") }
    } else {
        print("  OMITIDO: no hay fixture en \(rutaFixture) (genera `npm run fixture` en entregas-alumnado y cópialo)")
    }

    // Salida para que la web abra lo cifrado por Swift.
    let salida: [String: Any] = [
        "codigo": codigo,
        "portalId": portalId,
        "version": version,
        "kTablonHex": WebPortalCrypto.hex(kTablon),
        "nonceHex": WebPortalCrypto.hex(nonce),
        "inviteId": claves.inviteId,
        "pruebaAlta": claves.pruebaAlta,
        "sobreAlta": sobreAlta.jsonObject,
        "tablonJson": String(decoding: tablonJSON, as: UTF8.self),
        "sobreTablon": sobreTablon.jsonObject,
    ]
    try JSONSerialization.data(withJSONObject: salida, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: rutaSalida))
    print("Escrito \(rutaSalida)")
} catch {
    comprobar(false, "error inesperado: \(error)")
}

print(fallos == 0 ? "\nTodo en verde." : "\n\(fallos) comprobaciones fallan.")
exit(fallos == 0 ? 0 : 1)
