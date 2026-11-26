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
    /// Activada, Pendiente y Caducado mandan sobre «Sin correo» si hay entrada local.
    static func resolve(hasEmail: Bool, entry: WebPortalEntry?, server: WebPortalServerState?) -> WebPortalAccountStatus {
        let status: WebPortalAccountStatus
        if let server {
            status = from(server: server)
        } else if let entry {
            status = WebPortalAccountStatus(rawValue: entry.estadoConocido) ?? .desconocido
        } else {
            return hasEmail ? .sinInvitar : .sinCorreo
        }
        switch status {
        case .activada, .pendiente, .caducado: return status
        default: return hasEmail ? status : .sinCorreo
        }
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

    // MARK: - K_tablon en la bóveda (protegida por clave única en el Llavero)

    private func tablonAccount(portalId: String) -> String {
        "tablon-\(portalId)"
    }

    @discardableResult
    func saveTablonKey(_ key: Data, portalId: String) -> Bool {
        guard key.count == 32 else { return false }
        return AppSecretVault.shared.saveData(key, service: keychainService, account: tablonAccount(portalId: portalId))
    }

    func tablonKey(portalId: String) -> Data? {
        guard let datos = AppSecretVault.shared.loadData(service: keychainService, account: tablonAccount(portalId: portalId)),
              datos.count == 32 else { return nil }
        return datos
    }

    @discardableResult
    func deleteTablonKey(portalId: String) -> Bool {
        AppSecretVault.shared.delete(service: keychainService, account: tablonAccount(portalId: portalId))
    }

    // MARK: Llave pendiente
    // Al reinvitar a quien ya tiene cuenta, la llave nueva espera aquí hasta que
    // canjee el código. Mientras, se sigue publicando con la actual.

    private func pendingAccount(portalId: String) -> String {
        "tablon-pend-\(portalId)"
    }

    @discardableResult
    func savePendingKey(_ key: Data, portalId: String) -> Bool {
        guard key.count == 32 else { return false }
        return AppSecretVault.shared.saveData(key, service: keychainService, account: pendingAccount(portalId: portalId))
    }

    func pendingKey(portalId: String) -> Data? {
        guard let datos = AppSecretVault.shared.loadData(service: keychainService, account: pendingAccount(portalId: portalId)),
              datos.count == 32 else { return nil }
        return datos
    }

    @discardableResult
    func deletePendingKey(portalId: String) -> Bool {
        AppSecretVault.shared.delete(service: keychainService, account: pendingAccount(portalId: portalId))
    }

    /// La pendiente pasa a ser la llave con la que se publica.
    @discardableResult
    func promotePendingKey(portalId: String) -> Bool {
        guard let key = pendingKey(portalId: portalId), saveTablonKey(key, portalId: portalId) else { return false }
        deletePendingKey(portalId: portalId)
        return true
    }
}
