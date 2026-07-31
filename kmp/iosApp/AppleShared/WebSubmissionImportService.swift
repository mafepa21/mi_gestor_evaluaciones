import Foundation
import CryptoKit

/// Importación de entregas del alumnado hechas desde la PWA (repo `entregas-alumnado`).
///
/// Diseño: `plan_entregas_web_alumnado_2026-07-29.md`.
/// Contrato: `contrato/manifiesto.schema.json` y `contrato/entrega.schema.json` del repo de la PWA.
///
/// Este servicio hace SIETE cosas y ninguna más:
///   1. Verifica la firma del manifiesto.
///   2. Descifra el sobre.
///   3. Comprueba que la entrega es de ese formulario.
///   4. Traduce alias -> alumno y `webItemId` -> `notebook_instrument_items.id`.
///   5. Valida cada respuesta contra el TIPO que declara el manifiesto.
///   6. Descarta duplicados por `submissionId`.
///   7. Devuelve un borrador para previsualizar.
///
/// Lo que deliberadamente NO hace: escribir en la base de datos. Eso es de
/// `NotebookInstrumentsRepository.saveResponses`, que es quien resume el estado de
/// la celda, escribe `display_value`, deriva y guarda la nota, invalida la caché de
/// la hoja y avisa a la interfaz. Un `INSERT` directo en
/// `notebook_instrument_responses` se salta esos cinco pasos y deja la respuesta
/// guardada pero sin nota y sin refrescar el Cuaderno.
///
/// Tampoco calcula notas a partir de lo que manda el navegador: la entrega solo
/// lleva respuestas, y cualquier campo de nota que apareciera se ignora.

// MARK: - Modelos del contrato

enum WebManifestItemType: String, Codable {
    case check = "CHECK"
    case text = "TEXT"
    case number = "NUMBER"
    case scale1To4 = "SCALE_1_4"
    case choice = "CHOICE"
}

struct WebManifestSection: Codable {
    let sectionId: String
    let title: String
    let help: String?
}

struct WebManifestItem: Codable {
    let webItemId: String
    let type: WebManifestItemType
    let title: String
    let required: Bool
    let sectionId: String?
    let helpText: String?
    let options: [String]?
    let min: Double?
    let max: Double?
    let maxLength: Int?
    let scaleLabels: [String]?
}

struct WebFormManifest: Codable {
    let schemaVersion: Int
    let formInstanceId: String
    let title: String
    let subtitle: String?
    let locale: String
    let sections: [WebManifestSection]?
    let items: [WebManifestItem]
    let recipientKey: String
    let publisherKey: String?
    let signature: String?
    let expiresAt: String
    /// Correo al que el alumnado manda su entrega. Solo lo usa la web.
    let deliveryEmail: String?
}

struct WebSubmissionEnvelope: Codable {
    let schemaVersion: Int
    let submissionId: String
    let formInstanceId: String
    let participantAlias: String
    let encryptedPayload: String
    let ephemeralPublicKey: String
    let nonce: String
    let clientSubmittedAt: String
}

/// Una respuesta tal y como viaja. Exactamente uno de los tres valores viene
/// puesto; el esquema de la PWA lo garantiza y aquí se vuelve a comprobar, porque
/// no nos fiamos de que el fichero venga de nuestra propia PWA.
struct WebAnswer: Codable {
    let webItemId: String
    let bool: Bool?
    let number: Double?
    let text: String?
}

struct WebSubmissionPayload: Codable {
    let schemaVersion: Int
    let formInstanceId: String
    let answers: [WebAnswer]
}

// MARK: - Errores

enum WebSubmissionImportError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case notJSON(String)
    case manifestNotSigned
    case manifestSignatureInvalid
    case manifestExpired(String)
    case wrongForm(expected: String, got: String)
    case decryptionFailed
    case badKeyLength(field: String, expected: Int, got: Int)
    case payloadFormMismatch
    case unknownItem(String)
    case duplicatedItem(String)
    case typeMismatch(webItemId: String, detail: String)
    case unknownAlias(String)
    case noAnswers

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let v):
            return "La entrega usa la versión \(v) del formato y esta app entiende la 1."
        case .notJSON(let detalle):
            return "El fichero no es una entrega legible: \(detalle)"
        case .manifestNotSigned:
            return "El formulario no viene firmado, así que no se puede comprobar que sea el original."
        case .manifestSignatureInvalid:
            return "La firma del formulario no corresponde a su contenido: alguien lo ha modificado."
        case .manifestExpired(let cuando):
            return "El formulario dejó de aceptar entregas el \(cuando)."
        case .wrongForm(let esperado, let recibido):
            return "La entrega es de otro formulario (\(recibido)); este es \(esperado)."
        case .decryptionFailed:
            return "No se puede descifrar. O la clave no es la de este formulario, o el fichero ha sido manipulado."
        case .badKeyLength(let campo, let esperado, let recibido):
            return "\(campo) debería medir \(esperado) bytes y mide \(recibido)."
        case .payloadFormMismatch:
            return "El formulario que dice el interior del sobre no coincide con el de fuera."
        case .unknownItem(let id):
            return "La respuesta \(id) no existe en este formulario."
        case .duplicatedItem(let id):
            return "La respuesta \(id) viene dos veces."
        case .typeMismatch(let id, let detalle):
            return "La respuesta \(id) no encaja con su tipo: \(detalle)"
        case .unknownAlias(let alias):
            return "El código \(alias.prefix(6))… no está asignado a ningún alumno o alumna de este formulario."
        case .noAnswers:
            return "La entrega no trae ninguna respuesta."
        }
    }
}

// MARK: - Criptografía

/// X25519 efímero -> HKDF-SHA256 -> ChaCha20-Poly1305 (RFC 8439).
///
/// Todo con CryptoKit, sin dependencias nuevas. El formato lo fija el repo de la
/// PWA y hay un fixture (`interop-v1.json`) con un patrón de referencia: si el
/// test de interoperabilidad deja de pasar, es que una de las dos partes ha
/// cambiado el formato sin avisar a la otra.
enum WebSubmissionCrypto {
    /// Separador de dominio del HKDF. Tiene que ser byte a byte el mismo que en
    /// `src/cripto.mjs` de la PWA.
    static let hkdfInfo = "entregas-alumnado/v1/x25519-chacha20poly1305"

    static let prefijoX25519 = "x25519:"
    static let prefijoEd25519 = "ed25519:"

    /// Datos autenticados del sobre. Atan el criptograma a este formulario, esta
    /// entrega y este alias: cambiar cualquiera de los tres hace que el descifrado
    /// falle, en vez de aceptar una entrega recolocada o atribuida a otra persona.
    static func additionalData(for envelope: WebSubmissionEnvelope) -> Data {
        Data("v1|\(envelope.formInstanceId)|\(envelope.submissionId)|\(envelope.participantAlias)".utf8)
    }

    static func decrypt(
        envelope: WebSubmissionEnvelope,
        recipientPrivateKeyRaw: Data
    ) throws -> WebSubmissionPayload {
        guard recipientPrivateKeyRaw.count == 32 else {
            throw WebSubmissionImportError.badKeyLength(
                field: "La clave privada",
                expected: 32,
                got: recipientPrivateKeyRaw.count
            )
        }
        guard let ephemeral = Data(base64URLEncoded: envelope.ephemeralPublicKey),
              ephemeral.count == 32 else {
            throw WebSubmissionImportError.badKeyLength(
                field: "La clave efímera",
                expected: 32,
                got: Data(base64URLEncoded: envelope.ephemeralPublicKey)?.count ?? 0
            )
        }
        guard let nonceBytes = Data(base64URLEncoded: envelope.nonce), nonceBytes.count == 12 else {
            throw WebSubmissionImportError.badKeyLength(
                field: "El nonce",
                expected: 12,
                got: Data(base64URLEncoded: envelope.nonce)?.count ?? 0
            )
        }
        guard let sealed = Data(base64URLEncoded: envelope.encryptedPayload), sealed.count > 16 else {
            throw WebSubmissionImportError.decryptionFailed
        }

        do {
            let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: recipientPrivateKeyRaw)
            let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeral)
            let shared = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
            // Salt vacío: HKDF lo trata como un bloque de ceros del tamaño del
            // hash, que es lo mismo que hace @noble cuando no se le pasa salt.
            let key = shared.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: Data(),
                sharedInfo: Data(hkdfInfo.utf8),
                outputByteCount: 32
            )
            // @noble concatena criptograma y etiqueta; CryptoKit los quiere
            // separados, y la etiqueta de Poly1305 son los últimos 16 bytes.
            let cortePorLaEtiqueta = sealed.count - 16
            let box = try ChaChaPoly.SealedBox(
                nonce: try ChaChaPoly.Nonce(data: nonceBytes),
                ciphertext: sealed.prefix(cortePorLaEtiqueta),
                tag: sealed.suffix(16)
            )
            let claro = try ChaChaPoly.open(box, using: key, authenticating: additionalData(for: envelope))
            return try JSONDecoder().decode(WebSubmissionPayload.self, from: claro)
        } catch let error as WebSubmissionImportError {
            throw error
        } catch {
            throw WebSubmissionImportError.decryptionFailed
        }
    }

    /// Verifica la firma Ed25519 del manifiesto.
    ///
    /// Sin esto, cualquiera que pueda servir el manifiesto puede sustituir
    /// `recipientKey` por una clave suya y quedarse con todas las respuestas en
    /// claro. Es el ataque que más daño hace de todo el circuito.
    static func verifyManifestSignature(rawManifestJSON: Data) throws {
        guard let arbol = try? JSONSerialization.jsonObject(with: rawManifestJSON),
              let objeto = arbol as? [String: Any] else {
            throw WebSubmissionImportError.notJSON("el manifiesto no es un objeto JSON")
        }
        guard let firmaTexto = objeto["signature"] as? String,
              let firma = Data(base64URLEncoded: firmaTexto) else {
            throw WebSubmissionImportError.manifestNotSigned
        }
        guard let publisher = objeto["publisherKey"] as? String,
              publisher.hasPrefix(prefijoEd25519),
              let publicaRaw = Data(base64URLEncoded: String(publisher.dropFirst(prefijoEd25519.count))),
              publicaRaw.count == 32 else {
            throw WebSubmissionImportError.manifestNotSigned
        }
        let canonico = Data(JSONCanonicalizer.canonicalize(objeto).utf8)
        do {
            let publica = try Curve25519.Signing.PublicKey(rawRepresentation: publicaRaw)
            guard publica.isValidSignature(firma, for: canonico) else {
                throw WebSubmissionImportError.manifestSignatureInvalid
            }
        } catch let error as WebSubmissionImportError {
            throw error
        } catch {
            throw WebSubmissionImportError.manifestSignatureInvalid
        }
    }
}

// MARK: - Canonicalización JSON

/// Serialización canónica compatible con `canonicalizar()` de `src/cripto.mjs`.
///
/// Las dos partes tienen que producir EXACTAMENTE los mismos bytes o la firma no
/// verifica. Los tres sitios donde JavaScript y Swift se desalinean con más
/// facilidad, y qué se hace con cada uno:
///
///   - **Orden de las claves.** Se ordenan. `Array.sort()` de JS compara por
///     unidades UTF-16; para claves ASCII, que es todo lo que usa el contrato,
///     coincide con el orden de Swift.
///   - **Enteros contra decimales.** `JSON.stringify(250)` da `"250"`, no
///     `"250.0"`. Aquí se detecta si el número es entero y se escribe sin parte
///     decimal. El fixture de interoperabilidad incluye un decimal a propósito
///     para que esto quede probado y no supuesto.
///   - **Escapado de cadenas.** `JSON.stringify` escapa comillas, barra
///     invertida y controles, y deja el resto de UTF-8 tal cual: no escapa
///     tildes ni la ñ. Se replica eso.
///
/// El campo `signature` se excluye en cualquier nivel, igual que en la PWA.
enum JSONCanonicalizer {
    static func canonicalize(_ valor: Any) -> String {
        switch valor {
        case is NSNull:
            return "null"
        case let numero as NSNumber:
            return canonicalizeNumber(numero)
        case let texto as String:
            return escape(texto)
        case let lista as [Any]:
            return "[" + lista.map(canonicalize).joined(separator: ",") + "]"
        case let objeto as [String: Any]:
            let claves = objeto.keys.filter { $0 != "signature" }.sorted()
            let partes = claves.map { clave in
                escape(clave) + ":" + canonicalize(objeto[clave] as Any)
            }
            return "{" + partes.joined(separator: ",") + "}"
        default:
            return "null"
        }
    }

    private static func canonicalizeNumber(_ numero: NSNumber) -> String {
        // JSONSerialization devuelve los booleanos como NSNumber, así que hay que
        // distinguirlos antes de tratarlos como números.
        if CFGetTypeID(numero) == CFBooleanGetTypeID() {
            return numero.boolValue ? "true" : "false"
        }
        let doble = numero.doubleValue
        if doble.rounded() == doble, abs(doble) < 9_007_199_254_740_992 {
            return String(Int64(doble))
        }
        // La descripción de Double en Swift es la representación más corta que
        // vuelve al mismo valor, igual que el `Number.prototype.toString` de JS.
        return String(doble)
    }

    private static func escape(_ texto: String) -> String {
        var salida = "\""
        for escalar in texto.unicodeScalars {
            switch escalar {
            case "\"": salida += "\\\""
            case "\\": salida += "\\\\"
            case "\n": salida += "\\n"
            case "\r": salida += "\\r"
            case "\t": salida += "\\t"
            case "\u{08}": salida += "\\b"
            case "\u{0C}": salida += "\\f"
            default:
                if escalar.value < 0x20 {
                    salida += String(format: "\\u%04x", escalar.value)
                } else {
                    salida.unicodeScalars.append(escalar)
                }
            }
        }
        return salida + "\""
    }
}

// MARK: - base64url

extension Data {
    init?(base64URLEncoded texto: String) {
        var base64 = texto.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let resto = base64.count % 4
        if resto > 0 { base64 += String(repeating: "=", count: 4 - resto) }
        guard let datos = Data(base64Encoded: base64) else { return nil }
        self = datos
    }

    var base64URLEncodedString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Borrador de importación

/// Una respuesta ya traducida a lo que entiende la app.
struct WebResolvedAnswer {
    let itemId: String
    let webItemId: String
    let title: String
    let type: WebManifestItemType
    let textValue: String?
    let boolValue: Bool?
    let numberValue: Double?
}

/// Resultado de examinar UNA entrega. Es lo que se previsualiza; no se ha escrito
/// nada todavía.
struct WebSubmissionDraft: Identifiable {
    let id = UUID()
    let submissionId: String
    let formInstanceId: String
    let alias: String
    let studentId: Int64?
    let studentName: String?
    let classId: Int64
    let columnId: String
    let clientSubmittedAt: String
    let answers: [WebResolvedAnswer]
    let requiredTotal: Int
    let requiredAnswered: Int
    let missingRequiredTitles: [String]

    /// Si no se ha podido resolver a quién pertenece, el docente tiene que
    /// asignarlo a mano antes de importar.
    var needsManualAssignment: Bool { studentId == nil }
}

/// Una entrega que no se importa, con el motivo en lenguaje llano.
struct WebSubmissionRejection: Identifiable {
    let id = UUID()
    let fileName: String
    let reason: String
}

/// Una entrega que ya se importó antes y por tanto se ignora.
struct WebSubmissionAlreadyImported: Identifiable {
    let id = UUID()
    let fileName: String
    let submissionId: String
    let importedAtEpochMs: Int64
}

struct WebSubmissionImportPreview {
    var drafts: [WebSubmissionDraft] = []
    var rejections: [WebSubmissionRejection] = []
    var alreadyImported: [WebSubmissionAlreadyImported] = []

    var isEmpty: Bool { drafts.isEmpty && rejections.isEmpty && alreadyImported.isEmpty }
}

/// Lo que el servicio necesita saber de la base de datos, sin acoplarse a ella.
/// Con esto el examen de una entrega se puede probar sin montar SQLDelight.
protocol WebSubmissionContextResolver {
    /// Datos del formulario. `nil` si no está registrado en este dispositivo.
    func formInstance(formInstanceId: String) -> WebFormInstanceContext?
    /// alias -> alumno, dentro de ese formulario.
    func studentId(formInstanceId: String, alias: String) -> Int64?
    /// Nombre para mostrar en la previsualización.
    func studentName(studentId: Int64) -> String?
    /// `webItemId` -> `notebook_instrument_items.id`.
    func itemId(formInstanceId: String, webItemId: String) -> String?
    /// Momento en que se importó esa entrega, si ya se importó.
    func alreadyImportedAtEpochMs(submissionId: String) -> Int64?
    /// Clave privada X25519 del formulario, sacada del llavero.
    func recipientPrivateKey(privateKeyRef: String) -> Data?
}

struct WebFormInstanceContext {
    let formInstanceId: String
    let classId: Int64
    let columnId: String
    let privateKeyRef: String
    let revoked: Bool
    let expiresAtEpochMs: Int64
}

// MARK: - Servicio

struct WebSubmissionImportService {
    let resolver: WebSubmissionContextResolver
    /// Reloj inyectable: sin esto no se puede probar la caducidad sin esperar.
    var now: () -> Date = { Date() }

    static let supportedSchemaVersion = 1

    /// Examina varios ficheros `.mgsub` y devuelve qué se puede importar.
    /// No escribe nada.
    func preview(files: [(name: String, data: Data)], manifest: WebFormManifest) -> WebSubmissionImportPreview {
        var resultado = WebSubmissionImportPreview()
        for fichero in files {
            do {
                let borrador = try examine(data: fichero.data, manifest: manifest)
                resultado.drafts.append(borrador)
            } catch let yaEsta as YaImportada {
                resultado.alreadyImported.append(
                    WebSubmissionAlreadyImported(
                        fileName: fichero.name,
                        submissionId: yaEsta.submissionId,
                        importedAtEpochMs: yaEsta.importedAtEpochMs
                    )
                )
            } catch {
                resultado.rejections.append(
                    WebSubmissionRejection(
                        fileName: fichero.name,
                        reason: (error as? LocalizedError)?.errorDescription ?? "\(error)"
                    )
                )
            }
        }
        return resultado
    }

    /// Señal interna: no es un error del usuario, es que ya estaba importada.
    struct YaImportada: Error {
        let submissionId: String
        let importedAtEpochMs: Int64
    }

    /// Examina UNA entrega. Lanza con el motivo si no se puede importar.
    func examine(data: Data, manifest: WebFormManifest) throws -> WebSubmissionDraft {
        let envelope: WebSubmissionEnvelope
        do {
            envelope = try JSONDecoder().decode(WebSubmissionEnvelope.self, from: data)
        } catch {
            throw WebSubmissionImportError.notJSON("le faltan campos o no es JSON")
        }

        guard envelope.schemaVersion == Self.supportedSchemaVersion else {
            throw WebSubmissionImportError.unsupportedSchemaVersion(envelope.schemaVersion)
        }

        // Duplicado antes de descifrar: es más barato y evita trabajo inútil.
        if let cuando = resolver.alreadyImportedAtEpochMs(submissionId: envelope.submissionId) {
            throw YaImportada(submissionId: envelope.submissionId, importedAtEpochMs: cuando)
        }

        guard envelope.formInstanceId == manifest.formInstanceId else {
            throw WebSubmissionImportError.wrongForm(
                expected: manifest.formInstanceId,
                got: envelope.formInstanceId
            )
        }

        guard let contexto = resolver.formInstance(formInstanceId: envelope.formInstanceId) else {
            throw WebSubmissionImportError.wrongForm(
                expected: manifest.formInstanceId,
                got: "\(envelope.formInstanceId) (no registrado en este dispositivo)"
            )
        }

        guard let privada = resolver.recipientPrivateKey(privateKeyRef: contexto.privateKeyRef) else {
            throw WebSubmissionImportError.decryptionFailed
        }

        let carga = try WebSubmissionCrypto.decrypt(envelope: envelope, recipientPrivateKeyRaw: privada)

        guard carga.schemaVersion == Self.supportedSchemaVersion else {
            throw WebSubmissionImportError.unsupportedSchemaVersion(carga.schemaVersion)
        }
        guard carga.formInstanceId == envelope.formInstanceId else {
            throw WebSubmissionImportError.payloadFormMismatch
        }
        guard !carga.answers.isEmpty else {
            throw WebSubmissionImportError.noAnswers
        }

        let porWebItemId = Dictionary(
            manifest.items.map { ($0.webItemId, $0) },
            uniquingKeysWith: { primero, _ in primero }
        )

        var resueltas: [WebResolvedAnswer] = []
        var vistos = Set<String>()
        for respuesta in carga.answers {
            guard !vistos.contains(respuesta.webItemId) else {
                throw WebSubmissionImportError.duplicatedItem(respuesta.webItemId)
            }
            vistos.insert(respuesta.webItemId)

            guard let item = porWebItemId[respuesta.webItemId] else {
                throw WebSubmissionImportError.unknownItem(respuesta.webItemId)
            }
            if let motivo = Self.typeMismatchReason(item: item, answer: respuesta) {
                throw WebSubmissionImportError.typeMismatch(
                    webItemId: respuesta.webItemId,
                    detail: motivo
                )
            }
            guard let itemId = resolver.itemId(
                formInstanceId: envelope.formInstanceId,
                webItemId: respuesta.webItemId
            ) else {
                throw WebSubmissionImportError.unknownItem(respuesta.webItemId)
            }

            resueltas.append(
                WebResolvedAnswer(
                    itemId: itemId,
                    webItemId: respuesta.webItemId,
                    title: item.title,
                    type: item.type,
                    textValue: respuesta.text,
                    boolValue: respuesta.bool,
                    numberValue: respuesta.number
                )
            )
        }

        // El alias sin resolver NO tumba la entrega: se marca para que el docente
        // la asigne a mano en la previsualización. Tirar una entrega buena porque
        // falta una fila de la tabla de alias sería perder trabajo del alumnado.
        let studentId = resolver.studentId(
            formInstanceId: envelope.formInstanceId,
            alias: envelope.participantAlias
        )

        let obligatorios = manifest.items.filter { $0.required }
        let sinResponder = obligatorios.filter { !vistos.contains($0.webItemId) }

        return WebSubmissionDraft(
            submissionId: envelope.submissionId,
            formInstanceId: envelope.formInstanceId,
            alias: envelope.participantAlias,
            studentId: studentId,
            studentName: studentId.flatMap { resolver.studentName(studentId: $0) },
            classId: contexto.classId,
            columnId: contexto.columnId,
            clientSubmittedAt: envelope.clientSubmittedAt,
            answers: resueltas,
            requiredTotal: obligatorios.count,
            requiredAnswered: obligatorios.count - sinResponder.count,
            missingRequiredTitles: sinResponder.map(\.title)
        )
    }

    /// Comprueba una respuesta contra el tipo que declara el manifiesto.
    /// Devuelve el motivo del rechazo, o `nil` si encaja.
    ///
    /// Un solo desajuste tumba la entrega entera, no solo ese ítem: media entrega
    /// importada es peor que ninguna, porque deja la celda a medias sin que nadie
    /// sepa qué falta.
    static func typeMismatchReason(item: WebManifestItem, answer: WebAnswer) -> String? {
        switch item.type {
        case .check:
            guard answer.bool != nil else { return "una casilla necesita un sí/no" }
            return nil
        case .text:
            guard let texto = answer.text else { return "un texto necesita texto" }
            if let maximo = item.maxLength, texto.count > maximo {
                return "tiene \(texto.count) caracteres y el máximo es \(maximo)"
            }
            return nil
        case .number:
            guard let numero = answer.number else { return "un número necesita un número" }
            guard numero.isFinite else { return "el número no es válido" }
            if let minimo = item.min, numero < minimo { return "es menor que el mínimo \(minimo)" }
            if let maximo = item.max, numero > maximo { return "es mayor que el máximo \(maximo)" }
            return nil
        case .scale1To4:
            guard let numero = answer.number else { return "una escala necesita un número" }
            guard numero.rounded() == numero else { return "la escala tiene que ser un número entero" }
            guard numero >= 1, numero <= 4 else { return "la escala va de 1 a 4 y llegó \(Int(numero))" }
            return nil
        case .choice:
            guard let texto = answer.text else { return "una elección necesita texto" }
            guard let opciones = item.options, opciones.contains(texto) else {
                return "\"\(texto)\" no está entre las opciones"
            }
            return nil
        }
    }
}
