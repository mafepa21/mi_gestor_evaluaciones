import Foundation
import Security

/// Lo que la app recuerda del portal del alumnado, solo en este dispositivo.
///
///  - `Documentos/EntregasWeb/portal/alumnos.json`: `studentId → entrada`. Es el
///    único sitio donde un `portalId` se une a un alumno. Como `coevaluaciones.json`,
///    no viaja por Sync LAN.
///  - Llavero: `K_tablon` de cada portal. Quien no la tiene no puede publicar.
struct WebPortalEntry: Codable, Equatable {
    var portalId: String
    /// Último estado que dijo el servidor (`WebPortalAccountStatus.rawValue`).
    var estadoConocido: String
    /// Milisegundos desde 1970 de la última invitación.
    var invitadoEl: Int64?
    /// Última `version` publicada. La siguiente siempre es mayor.
    var ultimaVersion: Int64?
}

/// Estado de la cuenta de un alumno tal como se enseña en la hoja.
enum WebPortalAccountStatus: String, Equatable {
    /// Aún no se le ha invitado.
    case sinInvitar
    /// Local: no hay correo utilizable ni cuenta activada.
    case sinCorreo
    case pendiente
    case caducado
    case activada
    /// Se invitó y el servidor ya no sabe de él (cerrada).
    case sinCuenta
    /// Aún no se ha preguntado al servidor.
    case desconocido

    var label: String {
        switch self {
        case .sinInvitar: return "Sin invitar"
        case .sinCorreo: return "Sin correo"
        case .pendiente: return "Pendiente"
        case .caducado: return "Código caducado"
        case .activada: return "Activada"
        case .sinCuenta: return "Sin cuenta"
        case .desconocido: return "Comprobando…"
        }
    }

    /// Traduce lo que dice el servidor (contrato, sección 3).
    static func from(server: WebPortalServerState) -> WebPortalAccountStatus {
        switch server {
        case .cuenta: return .activada
        case .invitacionPendiente: return .pendiente
        case .invitacionCaducada: return .caducado
        case .ninguna: return .sinCuenta
        }
    }

    /// Cruza lo local (entrada y correo) con lo que dijo el servidor.
    /// «Sin correo» solo se muestra si tampoco hay cuenta activada.
    static func resolve(hasEmail: Bool, entry: WebPortalEntry?, server: WebPortalServerState?) -> WebPortalAccountStatus {
        if let server {
            let status = from(server: server)
            if status == .activada { return .activada }
            if !hasEmail { return .sinCorreo }
            return status
        }
        guard let entry else { return hasEmail ? .sinInvitar : .sinCorreo }
        let known = WebPortalAccountStatus(rawValue: entry.estadoConocido) ?? .desconocido
        if known == .activada { return .activada }
        if !hasEmail { return .sinCorreo }
        return known
    }
}

struct WebPortalStore {
    let fileURL: URL
    let keychainService: String
    private(set) var entries: [Int64: WebPortalEntry] = [:]

    static let defaultKeychainService = "com.migestor.portal"

    init(fileURL: URL, keychainService: String = WebPortalStore.defaultKeychainService) {
        self.fileURL = fileURL
        self.keychainService = keychainService
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([String: WebPortalEntry].self, from: data) {
            for (key, entry) in stored {
                if let id = Int64(key) { entries[id] = entry }
            }
        }
    }

    /// `Documentos/EntregasWeb/portal/alumnos.json`.
    static func standard() -> WebPortalStore? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return WebPortalStore(fileURL: documents
            .appendingPathComponent("EntregasWeb", isDirectory: true)
            .appendingPathComponent("portal", isDirectory: true)
            .appendingPathComponent("alumnos.json"))
    }

    subscript(studentId: Int64) -> WebPortalEntry? { entries[studentId] }

    mutating func set(_ entry: WebPortalEntry, for studentId: Int64) { entries[studentId] = entry }

    mutating func remove(studentId: Int64) { entries[studentId] = nil }

    func studentId(forPortalId portalId: String) -> Int64? {
        entries.first { $0.value.portalId == portalId }?.key
    }

    func save() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let plain = Dictionary(uniqueKeysWithValues: entries.map { (String($0.key), $0.value) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(plain).write(to: fileURL, options: [.atomic, .completeFileProtection])
        // Relaciona alumno con portal: solo para el dueño del dispositivo.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Relee el fichero, aplica el cambio y lo guarda, todo seguido y sin esperas.
    /// Así una publicación en segundo plano no pisa lo que la hoja acaba de escribir.
    @discardableResult
    static func mutate(
        fileURL: URL,
        keychainService: String = defaultKeychainService,
        _ body: (inout WebPortalStore) -> Void
    ) throws -> WebPortalStore {
        var store = WebPortalStore(fileURL: fileURL, keychainService: keychainService)
        body(&store)
        try store.save()
        return store
    }

    // MARK: - K_tablon en el llavero

    private func keychainBase(portalId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "tablon-\(portalId)",
        ]
    }

    @discardableResult
    func saveTablonKey(_ key: Data, portalId: String) -> Bool {
        guard key.count == 32 else { return false }
        let base = keychainBase(portalId: portalId)
        SecItemDelete(base as CFDictionary)
        var nuevo = base
        nuevo[kSecValueData as String] = key
        // Sin iCloud y solo con el dispositivo desbloqueado, como el resto de claves.
        nuevo[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(nuevo as CFDictionary, nil) == errSecSuccess
    }

    func tablonKey(portalId: String) -> Data? {
        var consulta = keychainBase(portalId: portalId)
        consulta[kSecReturnData as String] = true
        consulta[kSecMatchLimit as String] = kSecMatchLimitOne
        var resultado: CFTypeRef?
        guard SecItemCopyMatching(consulta as CFDictionary, &resultado) == errSecSuccess,
              let datos = resultado as? Data, datos.count == 32 else { return nil }
        return datos
    }

    @discardableResult
    func deleteTablonKey(portalId: String) -> Bool {
        SecItemDelete(keychainBase(portalId: portalId) as CFDictionary) == errSecSuccess
    }
}
