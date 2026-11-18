import Foundation
import CryptoKit
import CommonCrypto
import Security

/// Criptografía del portal del alumnado (contrato `contrato_portal_v1_2026-11-18.md`).
///
/// Solo depende de Foundation, CryptoKit, CommonCrypto y Security, para poder
/// compilarse suelto en `scripts/interop_entregas_web/portal/main.swift` y
/// comprobar los mismos vectores que la web.
///
/// Qué hace cada pieza:
///  - **Código de alta**: 10 caracteres al azar. De él salen tres cosas distintas
///    (identificador, prueba y llave de alta) con PBKDF2 + HKDF.
///  - **Sobres**: ChaCha20-Poly1305 con un dato autenticado (AAD) que ata el sobre
///    a su portal, a su tipo y, en el tablón, a su versión.
enum WebPortalCrypto {
    // MARK: - Constantes del contrato

    /// Sin 0, 1, I ni O. 32 caracteres: cada byte aleatorio se reduce con `& 0x1F`.
    static let codeAlphabet = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
    static let codeLength = 10
    static let pbkdf2Iterations = 600_000
    static let pbkdf2Salt = "entregas-alumnado/v1/portal/alta"
    static let hkdfInfoPrefix = "entregas-alumnado/v1/portal/alta/"

    enum CryptoError: Error, Equatable {
        case randomFailure
        case keyDerivationFailure
        case badKeyLength
        case badEnvelope
        case decryptionFailure
    }

    // MARK: - Base64url sin relleno

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func fromBase64URL(_ text: String) -> Data? {
        var base = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard !base.contains("=") else { return nil }
        base += String(repeating: "=", count: (4 - base.count % 4) % 4)
        return Data(base64Encoded: base)
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(_ text: String) -> String {
        hex(Data(SHA256.hash(data: Data(text.utf8))))
    }

    // MARK: - Aleatorio

    static func randomBytes(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw CryptoError.randomFailure
        }
        return Data(bytes)
    }

    /// 16 bytes en base64url: 22 caracteres.
    static func newPortalId() throws -> String { base64URL(try randomBytes(16)) }

    /// 32 bytes: la llave que cifra el tablón de un alumno.
    static func newTablonKey() throws -> Data { try randomBytes(32) }

    // MARK: - Código de alta

    /// Código de 10 caracteres, sin guion. Cada carácter sale de `byte & 0x1F`.
    static func generateCode() throws -> String {
        let bytes = try randomBytes(codeLength)
        return String(bytes.map { codeAlphabet[Int($0 & 0x1F)] })
    }

    /// `XXXXX-XXXXX`, como se enseña al alumno.
    static func displayCode(_ code: String) -> String {
        guard code.count == codeLength else { return code }
        return "\(code.prefix(5))-\(code.suffix(5))"
    }

    /// Mayúsculas, sin guiones ni espacios. `nil` si no son 10 caracteres válidos:
    /// el error es genérico y no se llama al servidor.
    static func normalizeCode(_ text: String) -> String? {
        let limpio = text.uppercased().filter { $0 != "-" && !$0.isWhitespace }
        guard limpio.count == codeLength, limpio.allSatisfy({ codeAlphabet.contains($0) }) else { return nil }
        return limpio
    }

    struct InviteKeys: Equatable {
        /// PBKDF2 del código.
        let raiz: Data
        /// 16 B en base64url.
        let inviteId: String
        /// 32 B en base64url.
        let pruebaAlta: String
        /// 32 B. Cifra el `sobreAlta`.
        let kAlta: Data

        var inviteIdHash: String { WebPortalCrypto.sha256Hex(inviteId) }
        var pruebaHash: String { WebPortalCrypto.sha256Hex(pruebaAlta) }
    }

    static func pbkdf2(password: String, salt: String, iterations: Int, length: Int = 32) throws -> Data {
        var derived = [UInt8](repeating: 0, count: length)
        let pass = Array(password.utf8)
        let saltBytes = Array(salt.utf8)
        let status = pass.withUnsafeBufferPointer { passPtr in
            saltBytes.withUnsafeBufferPointer { saltPtr in
                passPtr.baseAddress!.withMemoryRebound(to: Int8.self, capacity: pass.count) { p in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        p, pass.count,
                        saltPtr.baseAddress, saltBytes.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        &derived, length
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoError.keyDerivationFailure }
        return Data(derived)
    }

    static func hkdf(_ ikm: Data, info: String, length: Int) -> Data {
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: Data(),
            info: Data(info.utf8),
            outputByteCount: length
        )
        return key.withUnsafeBytes { Data($0) }
    }

    /// `code` ya normalizado (10 caracteres). `iterations` solo se baja en pruebas.
    static func deriveInvite(code: String, iterations: Int = pbkdf2Iterations) throws -> InviteKeys {
        let raiz = try pbkdf2(password: code, salt: pbkdf2Salt, iterations: iterations)
        return InviteKeys(
            raiz: raiz,
            inviteId: base64URL(hkdf(raiz, info: hkdfInfoPrefix + "id", length: 16)),
            pruebaAlta: base64URL(hkdf(raiz, info: hkdfInfoPrefix + "prueba", length: 32)),
            kAlta: hkdf(raiz, info: hkdfInfoPrefix + "llave", length: 32)
        )
    }

    // MARK: - Sobres

    /// Dato autenticado de cada sobre (UTF-8).
    enum Context {
        case alta(portalId: String)
        case cuenta(portalId: String)
        case tablon(portalId: String, version: Int64)

        var aad: Data {
            switch self {
            case .alta(let id): return Data("portal-v1|alta|\(id)".utf8)
            case .cuenta(let id): return Data("portal-v1|cuenta|\(id)".utf8)
            case .tablon(let id, let version): return Data("portal-v1|tablon|\(id)|\(version)".utf8)
            }
        }
    }

    /// `{"v":1,"nonce":b64u,"ct":b64u(cifrado‖etiqueta)}`.
    struct Envelope: Codable, Equatable {
        let v: Int
        let nonce: String
        let ct: String

        /// Mismo orden de claves que la web, y estable.
        var jsonString: String { "{\"v\":\(v),\"nonce\":\"\(nonce)\",\"ct\":\"\(ct)\"}" }
        var jsonData: Data { Data(jsonString.utf8) }
        var jsonObject: [String: Any] { ["v": v, "nonce": nonce, "ct": ct] }

        init(v: Int = 1, nonce: String, ct: String) {
            self.v = v
            self.nonce = nonce
            self.ct = ct
        }

        init(jsonObject: [String: Any]) throws {
            guard let v = jsonObject["v"] as? Int,
                  let nonce = jsonObject["nonce"] as? String,
                  let ct = jsonObject["ct"] as? String else { throw CryptoError.badEnvelope }
            self.init(v: v, nonce: nonce, ct: ct)
        }
    }

    /// `nonce` fijo solo para vectores de prueba; en uso real se deja en `nil`.
    static func seal(_ plaintext: Data, key: Data, context: Context, nonce: Data? = nil) throws -> Envelope {
        guard key.count == 32 else { throw CryptoError.badKeyLength }
        let nonceBytes = try nonce ?? randomBytes(12)
        guard nonceBytes.count == 12 else { throw CryptoError.badKeyLength }
        let box = try ChaChaPoly.seal(
            plaintext,
            using: SymmetricKey(data: key),
            nonce: try ChaChaPoly.Nonce(data: nonceBytes),
            authenticating: context.aad
        )
        return Envelope(nonce: base64URL(nonceBytes), ct: base64URL(box.ciphertext + box.tag))
    }

    static func open(_ envelope: Envelope, key: Data, context: Context) throws -> Data {
        guard key.count == 32 else { throw CryptoError.badKeyLength }
        guard envelope.v == 1,
              let nonceBytes = fromBase64URL(envelope.nonce), nonceBytes.count == 12,
              let ct = fromBase64URL(envelope.ct), ct.count >= 16 else { throw CryptoError.badEnvelope }
        do {
            let box = try ChaChaPoly.SealedBox(
                nonce: try ChaChaPoly.Nonce(data: nonceBytes),
                ciphertext: ct.dropLast(16),
                tag: ct.suffix(16)
            )
            return try ChaChaPoly.open(box, using: SymmetricKey(data: key), authenticating: context.aad)
        } catch {
            throw CryptoError.decryptionFailure
        }
    }
}
