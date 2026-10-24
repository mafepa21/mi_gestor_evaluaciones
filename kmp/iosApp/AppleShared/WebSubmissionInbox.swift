import Foundation
import CryptoKit
import Security

/// Buzón de entregas (`buzon/buzon.php` del repo `entregas-alumnado`).
///
/// La web deposita allí el sobre cifrado y la app lo recoge sola, sin pasar por el
/// correo. El buzón no puede leer nada: la clave privada sigue en el llavero.
///
/// Tres claves, todas creadas aquí:
///  - **cuenta**: una por instalación, en el llavero. Registra formularios nuevos.
///    En el servidor solo está su huella (`cuenta.hash`).
///  - **depósito**: una por formulario, va en el enlace del alumno (`b=`).
///  - **lectura**: una por formulario, en el llavero. Recoge y borra.
enum WebSubmissionInbox {
    /// Ruta del buzón en la misma web que los formularios.
    static let path = "/buzon/buzon.php"

    static func url(baseURL: String) -> String {
        (baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL) + path
    }

    /// 32 bytes aleatorios en base64url: 43 caracteres, lo que espera la web.
    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString
    }

    static func fingerprint(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Claves en el llavero

    private static let service = "com.migestor.buzon"
    private static let accountKeyName = "cuenta"

    static func readTokenName(formInstanceId: String) -> String { "lectura-\(formInstanceId)" }

    static func saveToken(_ token: String, name: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
        ]
        SecItemDelete(base as CFDictionary)
        var nuevo = base
        nuevo[kSecValueData as String] = Data(token.utf8)
        nuevo[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(nuevo as CFDictionary, nil) == errSecSuccess
    }

    static func loadToken(name: String) -> String? {
        let consulta: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var resultado: CFTypeRef?
        guard SecItemCopyMatching(consulta as CFDictionary, &resultado) == errSecSuccess,
              let datos = resultado as? Data else { return nil }
        return String(data: datos, encoding: .utf8)
    }

    static var accountKey: String? { loadToken(name: accountKeyName) }

    /// Crea la clave de cuenta si no existe y devuelve su huella para el servidor.
    static func ensureAccountKey() -> String? {
        if let existing = accountKey { return fingerprint(existing) }
        let token = randomToken()
        return saveToken(token, name: accountKeyName) ? fingerprint(token) : nil
    }

    // MARK: - Errores

    enum InboxError: LocalizedError, Equatable {
        case noAccountKey
        case unauthorized
        case server(Int)
        case network

        var errorDescription: String? {
            switch self {
            case .noAccountKey: return "Falta activar el buzón en este dispositivo."
            case .unauthorized: return "El buzón no reconoce la clave de este dispositivo."
            case .server(let code): return "El buzón respondió con un error (\(code))."
            case .network: return "No se pudo conectar con el buzón."
            }
        }
    }
}

/// Llamadas al buzón. `URLSession` inyectable para probarlo sin red.
struct WebSubmissionInboxClient {
    let url: String
    var session: URLSession = .shared

    struct Collected {
        /// Sobre tal cual llegó, listo para `WebSubmissionImportService`.
        let data: Data
        let alias: String
        let submissionId: String
    }

    func register(
        formInstanceId: String,
        accountKey: String,
        depositToken: String,
        readToken: String,
        expiresAt: Date,
        aliases: [String]
    ) async throws {
        _ = try await post(
            action: "registrar",
            headers: ["Authorization": "Bearer \(accountKey)"],
            body: [
                "formInstanceId": formInstanceId,
                "depositHash": WebSubmissionInbox.fingerprint(depositToken),
                "readHash": WebSubmissionInbox.fingerprint(readToken),
                "expiresAt": Int(expiresAt.timeIntervalSince1970),
                "aliasHashes": aliases.map(WebSubmissionInbox.fingerprint),
            ]
        )
    }

    func collect(formInstanceId: String, readToken: String) async throws -> [Collected] {
        let data = try await post(
            action: "recoger",
            headers: ["X-Buzon-Token": readToken],
            body: ["formInstanceId": formInstanceId]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["entregas"] as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let alias = entry["participantAlias"] as? String,
                  let submissionId = entry["submissionId"] as? String,
                  let raw = try? JSONSerialization.data(withJSONObject: entry) else { return nil }
            return Collected(data: raw, alias: alias, submissionId: submissionId)
        }
    }

    /// Borra del servidor lo ya importado. Si el alumno reenvió entretanto, el buzón lo conserva.
    func delete(formInstanceId: String, readToken: String, entries: [(alias: String, submissionId: String)]) async throws {
        guard !entries.isEmpty else { return }
        _ = try await post(
            action: "borrar",
            headers: ["X-Buzon-Token": readToken],
            body: [
                "formInstanceId": formInstanceId,
                "entregas": entries.map { ["alias": $0.alias, "submissionId": $0.submissionId] },
            ]
        )
    }

    private func post(action: String, headers: [String: String], body: [String: Any]) async throws -> Data {
        guard let endpoint = URL(string: "\(url)?accion=\(action)") else { throw WebSubmissionInbox.InboxError.network }
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WebSubmissionInbox.InboxError.network
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw WebSubmissionInbox.InboxError.unauthorized }
        guard (200..<300).contains(code) else { throw WebSubmissionInbox.InboxError.server(code) }
        return data
    }
}
