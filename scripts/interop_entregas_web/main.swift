// Verificación de interoperabilidad del importador de entregas web.
//
//   swiftc -O kmp/iosApp/AppleShared/WebSubmissionImportService.swift \
//          scripts/interop_entregas_web/main.swift -o /tmp/interop && /tmp/interop
//
// O más corto:  scripts/interop_entregas_web/verificar.sh
//
// QUÉ PRUEBA Y POR QUÉ IMPORTA
//
// El navegador cifra con @noble (JavaScript) y la app descifra con CryptoKit
// (Swift). Son dos implementaciones distintas del mismo formato, y basta un
// detalle para que una no entienda a la otra: el orden de los bytes del HKDF, el
// relleno del base64url, si la etiqueta Poly1305 va pegada al criptograma, cómo
// se serializa un decimal al canonicalizar para la firma. Todos esos fallos son
// silenciosos hasta que un alumno entrega y no se puede abrir.
//
// `interop-v1.json` es el patrón de referencia que produce el repo de la PWA con
// `npm run fixture`. Es adversario a propósito: lleva un decimal en el manifiesto
// (donde JSON.stringify da "250" y Swift tiende a dar "250.0"), comillas, barra
// invertida y salto de línea en un título, y acentos en una respuesta.
//
// No se hace como test de XCTest porque en `main` no existe todavía ningún
// objetivo de pruebas de Swift, y añadirlo aquí chocaría con `develop`, que ya lo
// trae. Esto verifica lo mismo sin tocar el sistema de compilación.

import Foundation

// MARK: - Andamio de comprobaciones

var pasadas = 0
var fallos = 0

func comprobar(_ nombre: String, _ condicion: Bool, _ detalle: String = "") {
    if condicion {
        pasadas += 1
        print("  ok    \(nombre)")
    } else {
        fallos += 1
        print("  FALLA \(nombre)\(detalle.isEmpty ? "" : " -> \(detalle)")")
    }
}

func comprobarLanza(_ nombre: String, _ bloque: () throws -> Void) {
    do {
        try bloque()
        fallos += 1
        print("  FALLA \(nombre) -> no lanzó y debía lanzar")
    } catch {
        pasadas += 1
        print("  ok    \(nombre)")
    }
}

// MARK: - Carga del fixture

struct Fixture: Decodable {
    let algoritmo: String
    let infoHkdf: String
    let recipientPrivateKey: String
    let manifest: WebFormManifest
    let envelope: WebSubmissionEnvelope
    let expectedPayload: WebSubmissionPayload
}

let raizRepo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let rutaFixture = raizRepo
    .appendingPathComponent("kmp/iosApp/PlannerTests/Recursos/interop-v1.json")

guard let datosFixture = try? Data(contentsOf: rutaFixture) else {
    print("No encuentro el fixture en \(rutaFixture.path)")
    print("Genéralo en el repo de la PWA con: npm run fixture")
    exit(1)
}

let fixture: Fixture
do {
    fixture = try JSONDecoder().decode(Fixture.self, from: datosFixture)
} catch {
    print("El fixture no se puede leer con los modelos del contrato: \(error)")
    exit(1)
}

// El manifiesto se vuelve a necesitar en bruto: la firma se verifica sobre los
// bytes canonicalizados del JSON, no sobre el modelo ya decodificado.
let arbolFixture = try JSONSerialization.jsonObject(with: datosFixture) as! [String: Any]
let manifiestoBruto = try JSONSerialization.data(
    withJSONObject: arbolFixture["manifest"] as! [String: Any]
)

print("\nFixture")
print("  algoritmo: \(fixture.algoritmo)")
comprobar(
    "el separador de dominio del HKDF coincide con el de la PWA",
    fixture.infoHkdf == WebSubmissionCrypto.hkdfInfo,
    "fixture=\(fixture.infoHkdf) app=\(WebSubmissionCrypto.hkdfInfo)"
)
comprobar("el manifiesto trae los cinco tipos", Set(fixture.manifest.items.map(\.type)).count == 5)

// MARK: - 1. base64url

print("\nbase64url")
comprobar(
    "el nonce mide 12 bytes",
    Data(base64URLEncoded: fixture.envelope.nonce)?.count == 12
)
comprobar(
    "la clave efímera mide 32 bytes",
    Data(base64URLEncoded: fixture.envelope.ephemeralPublicKey)?.count == 32
)
comprobar(
    "ida y vuelta sin relleno",
    Data([0xfb, 0xff, 0x00, 0x10]).base64URLEncodedString == "-_8AEA"
        && Data(base64URLEncoded: "-_8AEA") == Data([0xfb, 0xff, 0x00, 0x10])
)

// MARK: - 2. Canonicalización y firma del manifiesto

print("\nCanonicalización y firma")
// Este es el caso que caza el desalineamiento de decimales: si Swift escribiera
// "250.0" donde JavaScript escribe "250", la firma no verificaría.
comprobar(
    "un entero se canonicaliza sin parte decimal",
    JSONCanonicalizer.canonicalize(["a": NSNumber(value: 250.0)]) == "{\"a\":250}",
    JSONCanonicalizer.canonicalize(["a": NSNumber(value: 250.0)])
)
comprobar(
    "un decimal conserva la parte decimal",
    JSONCanonicalizer.canonicalize(["a": NSNumber(value: 0.5)]) == "{\"a\":0.5}",
    JSONCanonicalizer.canonicalize(["a": NSNumber(value: 0.5)])
)
comprobar(
    "las claves se ordenan",
    JSONCanonicalizer.canonicalize(["b": 1, "a": 2] as [String: Any]) == "{\"a\":2,\"b\":1}"
)
comprobar(
    "el campo signature se excluye en cualquier nivel",
    JSONCanonicalizer.canonicalize(["a": 1, "signature": "x"] as [String: Any])
        == JSONCanonicalizer.canonicalize(["a": 1] as [String: Any])
)
comprobar(
    "los escapes son los de JSON.stringify",
    JSONCanonicalizer.canonicalize("con \"comillas\", barra \\ y salto\nlínea")
        == "\"con \\\"comillas\\\", barra \\\\ y salto\\nlínea\"",
    JSONCanonicalizer.canonicalize("con \"comillas\", barra \\ y salto\nlínea")
)
comprobar(
    "los acentos NO se escapan",
    JSONCanonicalizer.canonicalize("canción") == "\"canción\""
)

// La prueba de fuego: la firma que puso JavaScript la valida Swift.
do {
    try WebSubmissionCrypto.verifyManifestSignature(rawManifestJSON: manifiestoBruto)
    pasadas += 1
    print("  ok    la firma Ed25519 del manifiesto de la PWA verifica en CryptoKit")
} catch {
    fallos += 1
    print("  FALLA la firma Ed25519 del manifiesto de la PWA verifica en CryptoKit -> \(error)")
}

// Y el ataque que más daño hace: cambiar la clave de cifrado por la del atacante.
comprobarLanza("sustituir recipientKey invalida la firma") {
    var manipulado = arbolFixture["manifest"] as! [String: Any]
    manipulado["recipientKey"] = "x25519:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    let datos = try JSONSerialization.data(withJSONObject: manipulado)
    try WebSubmissionCrypto.verifyManifestSignature(rawManifestJSON: datos)
}
comprobarLanza("quitar la firma se rechaza") {
    var manipulado = arbolFixture["manifest"] as! [String: Any]
    manipulado.removeValue(forKey: "signature")
    let datos = try JSONSerialization.data(withJSONObject: manipulado)
    try WebSubmissionCrypto.verifyManifestSignature(rawManifestJSON: datos)
}

// MARK: - 3. Descifrado

print("\nDescifrado")
guard let privada = Data(base64URLEncoded: fixture.recipientPrivateKey) else {
    print("  FALLA la clave privada del fixture no es base64url")
    exit(1)
}

do {
    let carga = try WebSubmissionCrypto.decrypt(
        envelope: fixture.envelope,
        recipientPrivateKeyRaw: privada
    )
    pasadas += 1
    print("  ok    CryptoKit descifra el sobre que cifró el navegador")

    comprobar("el formInstanceId de dentro coincide", carga.formInstanceId == fixture.envelope.formInstanceId)
    comprobar("llegan las cinco respuestas", carga.answers.count == fixture.expectedPayload.answers.count)

    let porId = Dictionary(carga.answers.map { ($0.webItemId, $0) }, uniquingKeysWith: { a, _ in a })
    let esperadas = Dictionary(
        fixture.expectedPayload.answers.map { ($0.webItemId, $0) },
        uniquingKeysWith: { a, _ in a }
    )

    comprobar("CHECK llega como sí/no", porId["f_check"]?.bool == true)
    comprobar(
        "TEXT llega con los acentos intactos",
        porId["f_text"]?.text == esperadas["f_text"]?.text,
        porId["f_text"]?.text ?? "nada"
    )
    comprobar(
        "NUMBER conserva el decimal",
        porId["f_number"]?.number == 42.5,
        "\(porId["f_number"]?.number ?? -1)"
    )
    comprobar("SCALE_1_4 llega como entero de 1 a 4", porId["f_scale"]?.number == 3)
    comprobar("CHOICE llega con una de las opciones", porId["f_choice"]?.text == "timing")
} catch {
    fallos += 1
    print("  FALLA CryptoKit descifra el sobre que cifró el navegador -> \(error)")
}

// MARK: - 4. Manipular el sobre tiene que romper el descifrado

print("\nManipulación del sobre")

func sobreCon(
    alias: String? = nil,
    submissionId: String? = nil,
    formInstanceId: String? = nil,
    payload: String? = nil
) -> WebSubmissionEnvelope {
    WebSubmissionEnvelope(
        schemaVersion: fixture.envelope.schemaVersion,
        submissionId: submissionId ?? fixture.envelope.submissionId,
        formInstanceId: formInstanceId ?? fixture.envelope.formInstanceId,
        participantAlias: alias ?? fixture.envelope.participantAlias,
        encryptedPayload: payload ?? fixture.envelope.encryptedPayload,
        ephemeralPublicKey: fixture.envelope.ephemeralPublicKey,
        nonce: fixture.envelope.nonce,
        clientSubmittedAt: fixture.envelope.clientSubmittedAt
    )
}

comprobarLanza("atribuir la entrega a otro alias falla") {
    _ = try WebSubmissionCrypto.decrypt(
        envelope: sobreCon(alias: "AAAAAAAAAAAAAAAAAAAAAA"),
        recipientPrivateKeyRaw: privada
    )
}
comprobarLanza("recolocar la entrega en otro formulario falla") {
    _ = try WebSubmissionCrypto.decrypt(
        envelope: sobreCon(formInstanceId: "99999999-9999-4999-8999-999999999999"),
        recipientPrivateKeyRaw: privada
    )
}
comprobarLanza("cambiar el submissionId falla") {
    _ = try WebSubmissionCrypto.decrypt(
        envelope: sobreCon(submissionId: "99999999-9999-4999-8999-999999999999"),
        recipientPrivateKeyRaw: privada
    )
}
comprobarLanza("tocar un byte del criptograma falla") {
    var caracteres = Array(fixture.envelope.encryptedPayload)
    caracteres[7] = caracteres[7] == "A" ? "B" : "A"
    _ = try WebSubmissionCrypto.decrypt(
        envelope: sobreCon(payload: String(caracteres)),
        recipientPrivateKeyRaw: privada
    )
}
comprobarLanza("otra clave privada no puede abrirlo") {
    var otra = privada
    otra[0] = otra[0] ^ 0xff
    _ = try WebSubmissionCrypto.decrypt(envelope: fixture.envelope, recipientPrivateKeyRaw: otra)
}
comprobarLanza("una clave privada de longitud incorrecta se rechaza") {
    _ = try WebSubmissionCrypto.decrypt(
        envelope: fixture.envelope,
        recipientPrivateKeyRaw: Data(repeating: 0, count: 16)
    )
}

// MARK: - 5. Validación de tipos

print("\nValidación de tipos")
let porWebItemId = Dictionary(
    fixture.manifest.items.map { ($0.webItemId, $0) },
    uniquingKeysWith: { a, _ in a }
)

func motivo(_ webItemId: String, _ respuesta: WebAnswer) -> String? {
    WebSubmissionImportService.typeMismatchReason(item: porWebItemId[webItemId]!, answer: respuesta)
}

comprobar(
    "una escala de 5 se rechaza",
    motivo("f_scale", WebAnswer(webItemId: "f_scale", bool: nil, number: 5, text: nil)) != nil
)
comprobar(
    "una escala decimal se rechaza",
    motivo("f_scale", WebAnswer(webItemId: "f_scale", bool: nil, number: 2.5, text: nil)) != nil
)
comprobar(
    "una escala de 1 a 4 se acepta",
    motivo("f_scale", WebAnswer(webItemId: "f_scale", bool: nil, number: 4, text: nil)) == nil
)
comprobar(
    "una elección fuera de las opciones se rechaza",
    motivo("f_choice", WebAnswer(webItemId: "f_choice", bool: nil, number: nil, text: "otra cosa")) != nil
)
comprobar(
    "un número por debajo del mínimo se rechaza",
    motivo("f_number", WebAnswer(webItemId: "f_number", bool: nil, number: 0.1, text: nil)) != nil
)
comprobar(
    "un número por encima del máximo se rechaza",
    motivo("f_number", WebAnswer(webItemId: "f_number", bool: nil, number: 251, text: nil)) != nil
)
comprobar(
    "un texto en una casilla se rechaza",
    motivo("f_check", WebAnswer(webItemId: "f_check", bool: nil, number: nil, text: "sí")) != nil
)
comprobar(
    "un número en un texto se rechaza",
    motivo("f_text", WebAnswer(webItemId: "f_text", bool: nil, number: 3, text: nil)) != nil
)
comprobar(
    "un texto más largo que maxLength se rechaza",
    motivo(
        "f_text",
        WebAnswer(webItemId: "f_text", bool: nil, number: nil, text: String(repeating: "a", count: 500))
    ) != nil
)

// MARK: - 6. El servicio completo, con un resolutor de prueba

print("\nServicio completo")

final class ResolutorDePrueba: WebSubmissionContextResolver {
    var privada: Data
    var aliasConocido: String?
    var yaImportadas: [String: Int64] = [:]

    init(privada: Data, aliasConocido: String?) {
        self.privada = privada
        self.aliasConocido = aliasConocido
    }

    func formInstance(formInstanceId: String) -> WebFormInstanceContext? {
        WebFormInstanceContext(
            formInstanceId: formInstanceId,
            classId: 7,
            columnId: "col-portafolio-sa2",
            privateKeyRef: "llavero://prueba",
            revoked: false,
            expiresAtEpochMs: 4_000_000_000_000
        )
    }
    func studentId(formInstanceId: String, alias: String) -> Int64? {
        alias == aliasConocido ? 42 : nil
    }
    func studentName(studentId: Int64) -> String? { studentId == 42 ? "Ana Ferrer" : nil }
    func itemId(formInstanceId: String, webItemId: String) -> String? { "item-\(webItemId)" }
    func alreadyImportedAtEpochMs(submissionId: String) -> Int64? { yaImportadas[submissionId] }
    func recipientPrivateKey(privateKeyRef: String) -> Data? { privada }
}

let sobreJSON = try JSONEncoder().encode(fixture.envelope)

let resolutor = ResolutorDePrueba(privada: privada, aliasConocido: fixture.envelope.participantAlias)
let servicio = WebSubmissionImportService(resolver: resolutor)

do {
    let borrador = try servicio.examine(data: sobreJSON, manifest: fixture.manifest)
    pasadas += 1
    print("  ok    el servicio examina la entrega completa")
    comprobar("resuelve el alias al alumno correcto", borrador.studentId == 42)
    comprobar("trae el nombre para previsualizar", borrador.studentName == "Ana Ferrer")
    comprobar("saca la clase y la columna del formulario", borrador.classId == 7 && borrador.columnId == "col-portafolio-sa2")
    comprobar("traduce los webItemId a ids reales", borrador.answers.allSatisfy { $0.itemId.hasPrefix("item-") })
    comprobar("cuenta los obligatorios", borrador.requiredAnswered == 5 && borrador.requiredTotal == 5)
    comprobar("no pide asignación manual", borrador.needsManualAssignment == false)
} catch {
    fallos += 1
    print("  FALLA el servicio examina la entrega completa -> \(error)")
}

// Un alias que no está en la tabla NO tumba la entrega: se marca para que el
// docente la asigne a mano. Tirar trabajo del alumnado por una fila que falta
// sería el peor comportamiento posible.
do {
    let sinAlias = ResolutorDePrueba(privada: privada, aliasConocido: nil)
    let borrador = try WebSubmissionImportService(resolver: sinAlias)
        .examine(data: sobreJSON, manifest: fixture.manifest)
    comprobar("un alias desconocido pide asignación manual, no se descarta", borrador.needsManualAssignment)
    pasadas += 1
    print("  ok    un alias desconocido no tumba la entrega")
} catch {
    fallos += 1
    print("  FALLA un alias desconocido no tumba la entrega -> \(error)")
}

// Idempotencia.
let resolutorConRegistro = ResolutorDePrueba(privada: privada, aliasConocido: fixture.envelope.participantAlias)
resolutorConRegistro.yaImportadas[fixture.envelope.submissionId] = 1_700_000_000_000
do {
    _ = try WebSubmissionImportService(resolver: resolutorConRegistro)
        .examine(data: sobreJSON, manifest: fixture.manifest)
    fallos += 1
    print("  FALLA una entrega ya importada se ignora -> no lanzó")
} catch is WebSubmissionImportService.YaImportada {
    pasadas += 1
    print("  ok    una entrega ya importada se ignora")
} catch {
    fallos += 1
    print("  FALLA una entrega ya importada se ignora -> lanzó otra cosa: \(error)")
}

// La previsualización de varios ficheros a la vez reparte en tres cubos.
let vistaPrevia = WebSubmissionImportService(resolver: resolutor).preview(
    files: [
        (name: "ana.mgsub", data: sobreJSON),
        (name: "roto.mgsub", data: Data("{ esto no es una entrega }".utf8)),
    ],
    manifest: fixture.manifest
)
comprobar("la previsualización acepta la buena", vistaPrevia.drafts.count == 1)
comprobar("la previsualización rechaza la rota con su motivo", vistaPrevia.rejections.count == 1)
comprobar(
    "el motivo del rechazo está en lenguaje llano",
    vistaPrevia.rejections.first?.reason.contains("no es una entrega legible") == true,
    vistaPrevia.rejections.first?.reason ?? "sin motivo"
)

// MARK: - Resultado

print("\n\(pasadas) pasadas, \(fallos) fallidas")
exit(fallos > 0 ? 1 : 0)
