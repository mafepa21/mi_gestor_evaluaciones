import Foundation
import CryptoKit
import Security

/// Resultado al leer la clave maestra de la bóveda en el Llavero del sistema.
enum AppSecretVaultKeychainReadResult: Equatable {
    case found(Data)
    case notFound
    case denied(OSStatus)
    case error(OSStatus)
}

/// Acceso al Llavero inyectable para pruebas unitarias aisladas del Llavero real.
protocol AppSecretVaultKeychainBackend {
    func loadMasterKey(service: String, account: String) -> AppSecretVaultKeychainReadResult
    func saveMasterKey(_ key: Data, service: String, account: String, label: String) -> Bool
    func deleteMasterKey(service: String, account: String) -> Bool
    func loadLegacyItem(service: String, account: String) -> Data?
    func deleteLegacyItem(service: String, account: String) -> Bool
}

struct SystemAppSecretVaultKeychainBackend: AppSecretVaultKeychainBackend {
    func loadMasterKey(service: String, account: String) -> AppSecretVaultKeychainReadResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, data.count == 32 else {
                return .error(errSecDecode)
            }
            return .found(data)
        case errSecItemNotFound:
            return .notFound
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed:
            return .denied(status)
        default:
            return .error(status)
        }
    }

    func saveMasterKey(_ key: Data, service: String, account: String, label: String) -> Bool {
        guard key.count == 32 else { return false }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: label,
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    func deleteMasterKey(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    func loadLegacyItem(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return data
    }

    func deleteLegacyItem(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}

/// Bóveda cifrada local protegida por **una sola clave maestra** en el Llavero.
///
/// Motivo:
/// En macOS con firma ad hoc (`codesign --sign -`), cada versión nueva de la app
/// cambia de firma binaria y macOS solicita la contraseña del Llavero una vez por
/// cada ítem individual. Al guardar todos los secretos de la app (portal del alumnado,
/// formularios web, buzón y sync iOS) en un único fichero cifrado con AES-256-GCM y
/// una sola clave maestra en el Llavero:
/// - Al instalar una versión nueva solo aparece **un único diálogo** del Llavero.
/// - Si el usuario acepta («Permitir siempre» o «Permitir»), la bóveda queda
///   desbloqueada en memoria para toda la sesión sin más avisos.
/// - Si el usuario deniega, la bóveda queda bloqueada sin insistir con más diálogos
///   hasta que decida volver a desbloquearla explícitamente (`retryUnlock()`).
/// - Las claves existentes del Llavero antiguo se migran automáticamente al leerse
///   por primera vez y se eliminan del Llavero antiguo una vez persistidas.
final class AppSecretVault {
    static let shared = AppSecretVault()

    static let defaultMasterKeyService = "com.migestor.vault"
    static let defaultMasterKeyAccount = "master-key"
    static let defaultMasterKeyLabel = "Cuaderno Vivo (Bóveda de claves)"

    private struct Payload: Codable {
        var version: Int = 1
        /// `service -> [account: base64(secret)]`
        var items: [String: [String: String]] = [:]
    }

    private let lock = NSLock()
    private let vaultURL: URL
    private let masterKeyService: String
    private let masterKeyAccount: String
    private let masterKeyLabel: String
    private let backend: AppSecretVaultKeychainBackend
    private let fileManager: FileManager

    private var cachedMasterKey: SymmetricKey?
    private var cachedPayload: Payload?
    private var lockedByDenial = false

    init(
        vaultURL: URL? = nil,
        masterKeyService: String = AppSecretVault.defaultMasterKeyService,
        masterKeyAccount: String = AppSecretVault.defaultMasterKeyAccount,
        masterKeyLabel: String = AppSecretVault.defaultMasterKeyLabel,
        backend: AppSecretVaultKeychainBackend = SystemAppSecretVaultKeychainBackend(),
        fileManager: FileManager = .default
    ) {
        self.vaultURL = vaultURL ?? Self.defaultVaultURL(fileManager: fileManager)
        self.masterKeyService = masterKeyService
        self.masterKeyAccount = masterKeyAccount
        self.masterKeyLabel = masterKeyLabel
        self.backend = backend
        self.fileManager = fileManager
    }

    static func defaultVaultURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("MiGestor", isDirectory: true)
            .appendingPathComponent("secret-vault.enc")
    }

    /// Indica si la bóveda ya está desbloqueada en memoria en esta sesión.
    var isUnlocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cachedMasterKey != nil && cachedPayload != nil
    }

    /// Indica si el usuario denegó el acceso a la clave maestra en esta sesión.
    var isLockedByUserDenial: Bool {
        lock.lock()
        defer { lock.unlock() }
        return lockedByDenial
    }

    /// Permite reintentar el desbloqueo si el usuario lo denegó anteriormente.
    @discardableResult
    func retryUnlock() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        lockedByDenial = false
        return ensureUnlockedLocked(createIfMissing: false)
    }

    /// Borra la caché en memoria (útil para tests o bloqueo manual).
    func lockInMemory() {
        lock.lock()
        defer { lock.unlock() }
        cachedMasterKey = nil
        cachedPayload = nil
    }

    // MARK: - Lectura / Escritura / Borrado

    func loadData(service: String, account: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        if lockedByDenial {
            return nil
        }

        if ensureUnlockedLocked(createIfMissing: false),
           let encoded = cachedPayload?.items[service]?[account],
           let data = Data(base64Encoded: encoded) {
            return data
        }

        // Si el usuario acaba de denegar la bóveda, respetamos su decisión sin
        // lanzar nuevos diálogos del Llavero antiguo.
        if lockedByDenial {
            return nil
        }

        // Migración perezosa desde el Llavero clásico: si el secreto aún vivía ahí,
        // se copia a la bóveda cifrada y se borra la entrada antigua para no volver
        // a pedir contraseña en futuras actualizaciones.
        guard let legacyData = backend.loadLegacyItem(service: service, account: account) else {
            return nil
        }

        if storeInVaultLocked(legacyData, service: service, account: account) {
            _ = backend.deleteLegacyItem(service: service, account: account)
        }
        return legacyData
    }

    func loadString(service: String, account: String) -> String? {
        guard let data = loadData(service: service, account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func saveData(_ data: Data, service: String, account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard storeInVaultLocked(data, service: service, account: account) else {
            return false
        }
        _ = backend.deleteLegacyItem(service: service, account: account)
        return true
    }

    @discardableResult
    func saveString(_ value: String, service: String, account: String) -> Bool {
        saveData(Data(value.utf8), service: service, account: account)
    }

    @discardableResult
    func delete(service: String, account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        var removedFromVault = false
        if !lockedByDenial, ensureUnlockedLocked(createIfMissing: false) {
            if var serviceItems = cachedPayload?.items[service],
               serviceItems.removeValue(forKey: account) != nil {
                let previous = cachedPayload
                if serviceItems.isEmpty {
                    cachedPayload?.items.removeValue(forKey: service)
                } else {
                    cachedPayload?.items[service] = serviceItems
                }
                if persistLocked() {
                    removedFromVault = true
                } else {
                    cachedPayload = previous
                }
            }
        }

        let removedFromLegacy = backend.deleteLegacyItem(service: service, account: account)
        return removedFromVault || removedFromLegacy
    }

    // MARK: - Internos (siempre bajo `lock`)

    private func storeInVaultLocked(_ data: Data, service: String, account: String) -> Bool {
        guard ensureUnlockedLocked(createIfMissing: true) else {
            return false
        }
        let previous = cachedPayload
        var payload = cachedPayload ?? Payload()
        var serviceItems = payload.items[service] ?? [:]
        serviceItems[account] = data.base64EncodedString()
        payload.items[service] = serviceItems
        cachedPayload = payload

        if persistLocked() {
            return true
        }
        cachedPayload = previous
        return false
    }

    private func ensureUnlockedLocked(createIfMissing: Bool) -> Bool {
        if cachedMasterKey != nil && cachedPayload != nil {
            return true
        }
        if lockedByDenial {
            return false
        }

        let vaultFileExists = fileManager.fileExists(atPath: vaultURL.path)

        switch backend.loadMasterKey(service: masterKeyService, account: masterKeyAccount) {
        case .found(let keyData):
            let key = SymmetricKey(data: keyData)
            if vaultFileExists {
                guard let payload = readAndDecryptPayloadLocked(using: key) else {
                    return false
                }
                cachedMasterKey = key
                cachedPayload = payload
                return true
            } else {
                cachedMasterKey = key
                cachedPayload = Payload()
                return true
            }

        case .notFound:
            // Nunca sobrescribir un fichero de bóveda existente si falta su clave maestra.
            if vaultFileExists || !createIfMissing {
                return false
            }
            guard let newKeyData = Self.generateRandomKey(count: 32),
                  backend.saveMasterKey(
                    newKeyData,
                    service: masterKeyService,
                    account: masterKeyAccount,
                    label: masterKeyLabel
                  ) else {
                return false
            }
            cachedMasterKey = SymmetricKey(data: newKeyData)
            cachedPayload = Payload()
            return true

        case .denied:
            lockedByDenial = true
            return false

        case .error:
            return false
        }
    }

    private func readAndDecryptPayloadLocked(using key: SymmetricKey) -> Payload? {
        guard let combined = try? Data(contentsOf: vaultURL),
              let sealedBox = try? AES.GCM.SealedBox(combined: combined),
              let plaintext = try? AES.GCM.open(sealedBox, using: key),
              let payload = try? JSONDecoder().decode(Payload.self, from: plaintext) else {
            return nil
        }
        return payload
    }

    private func persistLocked() -> Bool {
        guard let key = cachedMasterKey, let payload = cachedPayload else {
            return false
        }
        do {
            try fileManager.createDirectory(
                at: vaultURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let plaintext = try encoder.encode(payload)
            let sealed = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealed.combined else { return false }
            #if os(iOS)
            try combined.write(to: vaultURL, options: [.atomic, .completeFileProtection])
            #else
            try combined.write(to: vaultURL, options: [.atomic])
            #endif
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: vaultURL.path)
            return true
        } catch {
            return false
        }
    }

    private static func generateRandomKey(count: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            return nil
        }
        return Data(bytes)
    }
}
