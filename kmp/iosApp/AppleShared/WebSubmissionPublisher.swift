import Foundation
import CryptoKit

/// Publicación de formularios: la otra mitad del circuito de entregas del alumnado.
///
/// Convierte una plantilla de instrumento del Cuaderno en un manifiesto firmado que
/// la PWA puede pintar, más un enlace personal por alumno.
///
/// Lo que NUNCA sale de aquí hacia el manifiesto:
///
///  - `studentId`, `classId`, `columnId` ni el `id` de `notebook_instrument_items`.
///    Los `webItemId` se generan aleatorios y la única traducción vive en
///    `web_item_map`, en el Mac.
///  - Nombres del alumnado. El enlace lleva un alias de 128 bits y nada más.
///
/// Y una cosa que sí sale, con cuidado: la clave **pública** de cifrado. La privada
/// se queda en el llavero, así que aunque alguien se haga con el manifiesto no
/// puede leer ninguna respuesta.
enum WebSubmissionPublisher {

    // MARK: - Resultado

    struct PublishedForm {
        let formInstanceId: String
        /// El manifiesto firmado, listo para subir a la web.
        let manifestJSON: String
        let recipientPublicKey: String
        let publisherPublicKey: String
        /// Clave privada X25519. Va al llavero y no a la base de datos.
        let recipientPrivateKey: Data
        let expiresAtEpochMs: Int64
        /// `webItemId` -> `notebook_instrument_items.id`, para guardar en el mapa.
        let itemMap: [(webItemId: String, itemId: String, itemType: WebManifestItemType)]
        /// Un alias por alumno.
        let aliases: [(alias: String, studentId: Int64)]
        /// Enlaces personales, en el orden del alumnado que se pasó.
        let links: [(studentId: Int64, studentName: String, url: String)]
    }

    struct ItemToPublish {
        let itemId: String
        let title: String
        let type: WebManifestItemType
        let required: Bool
        let options: [String]
        let helpText: String?
        let scaleLabels: [String]?
        let sectionId: String?
    }

    struct SectionToPublish {
        let sectionId: String
        let title: String
        let help: String?
    }

    struct StudentToPublish {
        let id: Int64
        let name: String
    }

    enum PublishError: LocalizedError {
        case noItems
        case noStudents
        case choiceWithoutOptions(String)
        case signingFailed

        var errorDescription: String? {
            switch self {
            case .noItems:
                return "El instrumento no tiene ningún apartado que publicar."
            case .noStudents:
                return "El grupo no tiene alumnado al que dar enlaces."
            case .choiceWithoutOptions(let titulo):
                return "El apartado «\(titulo)» es de elección pero no tiene opciones."
            case .signingFailed:
                return "No se pudo firmar el manifiesto."
            }
        }
    }

    // MARK: - Publicar

    /// Genera claves nuevas, construye el manifiesto, lo firma y devuelve todo lo
    /// necesario para guardarlo y repartirlo.
    ///
    /// Las claves se generan **por formulario**, no una vez para toda la app: así
    /// una clave comprometida solo afecta a un formulario, y revocar es tan simple
    /// como dejar de aceptar ese `formInstanceId`.
    static func publish(
        title: String,
        subtitle: String?,
        locale: String,
        sections: [SectionToPublish],
        items: [ItemToPublish],
        students: [StudentToPublish],
        baseURL: String,
        expiresAtEpochMs: Int64,
        formInstanceId: String = UUID().uuidString
    ) throws -> PublishedForm {
        guard !items.isEmpty else { throw PublishError.noItems }
        guard !students.isEmpty else { throw PublishError.noStudents }

        let cifrado = Curve25519.KeyAgreement.PrivateKey()
        let firma = Curve25519.Signing.PrivateKey()
        let recipientKey = WebSubmissionCrypto.prefijoX25519
            + cifrado.publicKey.rawRepresentation.base64URLEncodedString
        let publisherKey = WebSubmissionCrypto.prefijoEd25519
            + firma.publicKey.rawRepresentation.base64URLEncodedString

        // `webItemId` aleatorio y opaco. Podría derivarse de la clave del ítem
        // (`chkp_1`, `obs_s1_i2`), que sería más fácil de depurar, pero eso
        // publicaría la estructura interna del instrumento. La traducción vive en
        // `web_item_map` y en ningún otro sitio.
        var itemMap: [(webItemId: String, itemId: String, itemType: WebManifestItemType)] = []
        var itemsJSON: [[String: Any]] = []

        for item in items {
            if item.type == .choice, item.options.count < 2 {
                throw PublishError.choiceWithoutOptions(item.title)
            }
            let webItemId = "i" + Data(UUID().uuidString.utf8).base64URLEncodedString.prefix(20)
            itemMap.append((webItemId: webItemId, itemId: item.itemId, itemType: item.type))

            var json: [String: Any] = [
                "webItemId": webItemId,
                "type": item.type.rawValue,
                "title": item.title,
                "required": item.required,
            ]
            if let sectionId = item.sectionId { json["sectionId"] = sectionId }
            if let helpText = item.helpText, !helpText.isEmpty { json["helpText"] = helpText }
            // Cada extra solo se pone en el tipo que lo admite: el esquema del
            // contrato rechaza, por ejemplo, `options` en un TEXT.
            switch item.type {
            case .choice:
                json["options"] = item.options
            case .scale1To4:
                if let labels = item.scaleLabels, labels.count == 4 { json["scaleLabels"] = labels }
            case .check, .text, .number:
                break
            }
            itemsJSON.append(json)
        }

        var manifiesto: [String: Any] = [
            "schemaVersion": 1,
            "formInstanceId": formInstanceId,
            "title": title,
            "locale": locale,
            "items": itemsJSON,
            "recipientKey": recipientKey,
            "publisherKey": publisherKey,
            "expiresAt": iso8601(expiresAtEpochMs),
        ]
        if let subtitle, !subtitle.isEmpty { manifiesto["subtitle"] = subtitle }
        if !sections.isEmpty {
            manifiesto["sections"] = sections.map { seccion -> [String: Any] in
                var json: [String: Any] = ["sectionId": seccion.sectionId, "title": seccion.title]
                if let help = seccion.help, !help.isEmpty { json["help"] = help }
                return json
            }
        }

        // Se firma la forma canónica, la misma que verifica la PWA. Después se
        // añade `signature`, que la canonicalización excluye por definición.
        let canonico = Data(JSONCanonicalizer.canonicalize(manifiesto).utf8)
        guard let firmaBytes = try? firma.signature(for: canonico) else {
            throw PublishError.signingFailed
        }
        manifiesto["signature"] = firmaBytes.base64URLEncodedString

        // Se serializa ordenado para que el fichero sea estable y legible en un
        // diff; la firma ya está calculada sobre la forma canónica, así que el
        // formato de este JSON no la afecta.
        let datos = try JSONSerialization.data(
            withJSONObject: manifiesto,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let manifestJSON = String(decoding: datos, as: UTF8.self)

        var aliases: [(alias: String, studentId: Int64)] = []
        var links: [(studentId: Int64, studentName: String, url: String)] = []
        var usados = Set<String>()
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL

        for alumno in students {
            var alias: String
            repeat { alias = randomAlias() } while usados.contains(alias)
            usados.insert(alias)
            aliases.append((alias: alias, studentId: alumno.id))
            // El alias va en el FRAGMENTO: el navegador no lo envía al servidor, así
            // que ningún registro de acceso ve nunca quién es quién.
            links.append((
                studentId: alumno.id,
                studentName: alumno.name,
                url: "\(base)/#a=\(alias)"
            ))
        }

        return PublishedForm(
            formInstanceId: formInstanceId,
            manifestJSON: manifestJSON,
            recipientPublicKey: recipientKey,
            publisherPublicKey: publisherKey,
            recipientPrivateKey: cifrado.rawRepresentation,
            expiresAtEpochMs: expiresAtEpochMs,
            itemMap: itemMap,
            aliases: aliases,
            links: links
        )
    }

    // MARK: - Exportación para el docente

    /// Texto para repartir: un alumno y su enlace por línea.
    static func linksText(for form: PublishedForm, title: String) -> String {
        let ancho = form.links.map(\.studentName.count).max() ?? 0
        var lineas = [
            title,
            "Formulario: \(form.formInstanceId)",
            "",
            "Reparte cada enlace SOLO a su destinatario.",
            "El código va detrás del # y por eso nunca llega al servidor.",
            "",
        ]
        for enlace in form.links {
            lineas.append(
                enlace.studentName.padding(toLength: max(ancho, enlace.studentName.count), withPad: " ", startingAt: 0)
                    + "  " + enlace.url
            )
        }
        return lineas.joined(separator: "\n") + "\n"
    }

    // MARK: - Utilidades

    private static func randomAlias() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString
    }

    private static func iso8601(_ epochMs: Int64) -> String {
        let formato = ISO8601DateFormatter()
        formato.timeZone = TimeZone(identifier: "UTC")
        formato.formatOptions = [.withInternetDateTime]
        return formato.string(from: Date(timeIntervalSince1970: Double(epochMs) / 1000))
    }
}
