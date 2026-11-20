import Foundation

/// Resumen seguro (sin secretos) de las llaves del portal presentes en un equipo o copia cifrada.
public struct WebPortalBackupVaultSummary: Equatable, Sendable {
    public let accountCount: Int
    public let keyCount: Int
    public let hasAccountKey: Bool

    public init(accountCount: Int, keyCount: Int, hasAccountKey: Bool) {
        self.accountCount = accountCount
        self.keyCount = keyCount
        self.hasAccountKey = hasAccountKey
    }

    public var isEmpty: Bool {
        accountCount == 0 && keyCount == 0 && !hasAccountKey
    }

    public var subtitle: String {
        var parts: [String] = []
        if accountCount > 0 {
            parts.append("\(accountCount) \(accountCount == 1 ? "cuenta" : "cuentas")")
        } else if keyCount > 0 {
            parts.append("\(keyCount) \(keyCount == 1 ? "llave" : "llaves")")
        }
        if hasAccountKey {
            parts.append("clave del buzón")
        }
        return parts.isEmpty ? "Sin llaves del portal" : parts.joined(separator: " y ")
    }
}

/// Bóveda de llaves y configuración del Portal del alumnado para copias portables CIFRADAS (`.migestorbackupx`).
///
/// Reglas de seguridad:
///  - Solo se empaqueta en el ZIP temporal justo antes de cifrar con PBKDF2 + AES-256-GCM.
///  - NUNCA se guarda en texto claro dentro de copias locales `.migestorbackup`.
///  - Al importar una copia `.migestorbackupx`, se lee en memoria y se elimina inmediatamente
///    del staging antes de mover la copia al historial local.
///  - Las copias legacy `.migestorbackup` nunca la exportan ni la aceptan al importar.
public struct WebPortalBackupVault: Codable, Equatable, Sendable {
    public static let archiveEntryName = "portal-vault.json"
    public static let currentVersion = 1

    public struct KeyEntry: Codable, Equatable, Sendable {
        public let portalId: String
        public let tablonKeyBase64: String?
        public let pendingKeyBase64: String?

        public init(portalId: String, tablonKeyBase64: String?, pendingKeyBase64: String?) {
            self.portalId = portalId
            self.tablonKeyBase64 = tablonKeyBase64
            self.pendingKeyBase64 = pendingKeyBase64
        }
    }

    public let version: Int
    public let alumnosJSON: Data?
    public let notasVisiblesJSON: Data?
    public let torneosVisiblesJSON: Data?
    public let efVisibleJSON: Data?
    public let keys: [KeyEntry]
    public let accountKey: String?

    public init(
        version: Int = WebPortalBackupVault.currentVersion,
        alumnosJSON: Data?,
        notasVisiblesJSON: Data?,
        torneosVisiblesJSON: Data?,
        efVisibleJSON: Data? = nil,
        keys: [KeyEntry],
        accountKey: String?
    ) {
        self.version = version
        self.alumnosJSON = alumnosJSON
        self.notasVisiblesJSON = notasVisiblesJSON
        self.torneosVisiblesJSON = torneosVisiblesJSON
        self.efVisibleJSON = efVisibleJSON
        self.keys = keys
        self.accountKey = accountKey
    }

    public var summary: WebPortalBackupVaultSummary {
        let accounts: Int = {
            guard let alumnosJSON,
                  let decoded = try? JSONDecoder().decode([String: WebPortalEntry].self, from: alumnosJSON) else {
                return keys.count
            }
            return decoded.count
        }()
        let keyCount = keys.filter { $0.tablonKeyBase64 != nil || $0.pendingKeyBase64 != nil }.count
        return WebPortalBackupVaultSummary(
            accountCount: accounts,
            keyCount: keyCount,
            hasAccountKey: accountKey?.isEmpty == false
        )
    }

    public static func defaultPortalDirectory(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("EntregasWeb/portal", isDirectory: true)
    }

    /// Resumen del estado actual del portal en este equipo (sin exponer ningún secreto).
    public static func currentSummary(
        portalDirectory: URL? = nil,
        keychainService: String? = nil,
        readAccountKey: (() -> String?)? = nil
    ) -> WebPortalBackupVaultSummary {
        guard let vault = capture(
            portalDirectory: portalDirectory,
            keychainService: keychainService,
            readAccountKey: readAccountKey
        ) else {
            return WebPortalBackupVaultSummary(accountCount: 0, keyCount: 0, hasAccountKey: false)
        }
        return vault.summary
    }

    /// Captura la configuración del portal y todas las llaves vigentes del Llavero.
    /// Devuelve `nil` si este equipo no tiene ninguna cuenta ni clave de buzón configurada.
    public static func capture(
        portalDirectory: URL? = nil,
        keychainService: String? = nil,
        readAccountKey: (() -> String?)? = nil,
        fileManager: FileManager = .default
    ) -> WebPortalBackupVault? {
        let resolvedService = keychainService ?? WebPortalStore.defaultKeychainService
        let accountKeyReader = readAccountKey ?? { WebSubmissionInbox.accountKey }

        guard let dir = portalDirectory ?? defaultPortalDirectory(fileManager: fileManager) else {
            if let accountKey = accountKeyReader(), !accountKey.isEmpty {
                return WebPortalBackupVault(
                    alumnosJSON: nil,
                    notasVisiblesJSON: nil,
                    torneosVisiblesJSON: nil,
                    keys: [],
                    accountKey: accountKey
                )
            }
            return nil
        }

        let alumnosURL = dir.appendingPathComponent("alumnos.json")
        let notasURL = dir.appendingPathComponent("notas-visibles.json")
        let torneosURL = dir.appendingPathComponent("torneos-visibles.json")
        let efURL = dir.appendingPathComponent("ef-visible.json")

        let alumnosJSON = try? Data(contentsOf: alumnosURL)
        let notasJSON = try? Data(contentsOf: notasURL)
        let torneosJSON = try? Data(contentsOf: torneosURL)
        let efJSON = try? Data(contentsOf: efURL)

        let store = WebPortalStore(fileURL: alumnosURL, keychainService: resolvedService)
        let portalIds = Array(Set(store.entries.values.map(\.portalId))).sorted()
        let keyEntries: [KeyEntry] = portalIds.compactMap { portalId in
            let tablon = store.tablonKey(portalId: portalId)?.base64EncodedString()
            let pending = store.pendingKey(portalId: portalId)?.base64EncodedString()
            guard tablon != nil || pending != nil else { return nil }
            return KeyEntry(portalId: portalId, tablonKeyBase64: tablon, pendingKeyBase64: pending)
        }

        let accountKey = accountKeyReader()
        let hasAnything = alumnosJSON != nil || notasJSON != nil || torneosJSON != nil || efJSON != nil
            || !keyEntries.isEmpty || (accountKey?.isEmpty == false)
        guard hasAnything else { return nil }

        return WebPortalBackupVault(
            alumnosJSON: alumnosJSON,
            notasVisiblesJSON: notasJSON,
            torneosVisiblesJSON: torneosJSON,
            efVisibleJSON: efJSON,
            keys: keyEntries,
            accountKey: accountKey
        )
    }

    public func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> WebPortalBackupVault {
        try JSONDecoder().decode(WebPortalBackupVault.self, from: data)
    }

    /// Lee `portal-vault.json` de un paquete recién extraído en staging y lo elimina SIEMPRE
    /// del disco antes de que el paquete entre en el historial local `.migestorbackup`.
    /// Solo devuelve la bóveda si proviene de una copia cifrada `.migestorbackupx`; en copias
    /// legacy sin cifrar se borra y se descarta.
    static func extractAndStrip(
        in stagedPackageURL: URL,
        format: ApplePortableBackupFormat,
        fileManager: FileManager = .default
    ) throws -> WebPortalBackupVault? {
        let stagedVaultURL = stagedPackageURL.appendingPathComponent(archiveEntryName)
        guard fileManager.fileExists(atPath: stagedVaultURL.path) else { return nil }
        var extracted: WebPortalBackupVault?
        if format == .encryptedV1, let raw = try? Data(contentsOf: stagedVaultURL) {
            extracted = try? decode(from: raw)
        }
        try fileManager.removeItem(at: stagedVaultURL)
        return extracted
    }

    /// Restaura los ficheros de configuración del portal (con permisos 0600) y las llaves al Llavero.
    /// Devuelve cuántas llaves de alumno se importaron correctamente.
    @discardableResult
    public func restore(
        to portalDirectory: URL? = nil,
        keychainService: String? = nil,
        writeAccountKey: ((String) -> Bool)? = nil,
        fileManager: FileManager = .default
    ) throws -> Int {
        let resolvedService = keychainService ?? WebPortalStore.defaultKeychainService
        let accountKeyWriter = writeAccountKey ?? { WebSubmissionInbox.restoreAccountKey($0) }
        guard let dir = portalDirectory ?? Self.defaultPortalDirectory(fileManager: fileManager) else {
            throw NSError(
                domain: "WebPortalBackupVault",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "No se pudo localizar la carpeta de documentos del portal."]
            )
        }
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        func writePrivate(_ data: Data?, filename: String) throws {
            guard let data else { return }
            let url = dir.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }

        try writePrivate(alumnosJSON, filename: "alumnos.json")
        try writePrivate(notasVisiblesJSON, filename: "notas-visibles.json")
        try writePrivate(torneosVisiblesJSON, filename: "torneos-visibles.json")
        try writePrivate(efVisibleJSON, filename: "ef-visible.json")

        let store = WebPortalStore(
            fileURL: dir.appendingPathComponent("alumnos.json"),
            keychainService: resolvedService
        )
        var restoredKeys = 0
        for entry in keys {
            if let b64 = entry.tablonKeyBase64, let raw = Data(base64Encoded: b64), raw.count == 32 {
                if store.saveTablonKey(raw, portalId: entry.portalId) {
                    restoredKeys += 1
                }
            }
            if let b64 = entry.pendingKeyBase64, let raw = Data(base64Encoded: b64), raw.count == 32 {
                _ = store.savePendingKey(raw, portalId: entry.portalId)
            }
        }
        if let accountKey, !accountKey.isEmpty {
            _ = accountKeyWriter(accountKey)
        }
        return restoredKeys
    }
}
