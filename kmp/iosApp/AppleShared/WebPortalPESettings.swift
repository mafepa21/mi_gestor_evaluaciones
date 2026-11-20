import Foundation

/// Qué datos de Educación Física y asistencia deja ver el docente en el portal (fase 3C).
///
/// Vive solo en este equipo: `Documentos/EntregasWeb/portal/ef-visible.json`.
/// No viaja por Sync LAN: solo publica el Mac que tiene las llaves. Todo empieza apagado.
struct WebPortalGroupPESettings: Codable, Equatable {
    /// Pruebas físicas visibles (`PhysicalTestDefinition.id -> Bool`).
    var pruebas: [String: Bool] = [:]
    /// Pruebas que ya pasaron la confirmación inicial.
    var pruebasConfirmadas: [String] = []
    /// Mostrar resumen de asistencia (contadores y fechas recientes, sin notas privadas).
    var asistencia: Bool = false
    /// Ya pasó la confirmación inicial de asistencia.
    var asistenciaConfirmada: Bool = false

    func isTestVisible(testId: String) -> Bool { pruebas[testId] == true }

    func needsTestConfirmation(testId: String) -> Bool { !pruebasConfirmadas.contains(testId) }

    var visibleTestIds: Set<String> { Set(pruebas.filter { $0.value }.map(\.key)) }

    var hasAnythingActive: Bool { asistencia || pruebas.values.contains(true) }
}

/// Estado persistido de grupos que llegaron a publicar bloques de EF/asistencia (`ef-publicado.json`).
struct WebPortalPEPublishedState: Codable, Equatable {
    var conEF: [Int64] = []
    var pendientes: [Int64] = []

    static func url(besides settingsURL: URL) -> URL {
        settingsURL.deletingLastPathComponent().appendingPathComponent("ef-publicado.json")
    }

    static func load(fileURL: URL) -> WebPortalPEPublishedState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(WebPortalPEPublishedState.self, from: data) else {
            return WebPortalPEPublishedState()
        }
        return state
    }

    func save(fileURL: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? encoder.encode(self) { try? data.write(to: fileURL, options: [.atomic]) }
    }
}

struct WebPortalPESettings: Equatable {
    private(set) var groups: [Int64: WebPortalGroupPESettings] = [:]

    subscript(classId: Int64) -> WebPortalGroupPESettings {
        get { groups[classId] ?? WebPortalGroupPESettings() }
        set { groups[classId] = newValue }
    }

    var activeClassIds: Set<Int64> {
        Set(groups.filter { $0.value.hasAnythingActive }.map(\.key))
    }

    static func standardURL() -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documents
            .appendingPathComponent("EntregasWeb", isDirectory: true)
            .appendingPathComponent("portal", isDirectory: true)
            .appendingPathComponent("ef-visible.json")
    }

    static func load(fileURL: URL) -> WebPortalPESettings {
        guard let data = try? Data(contentsOf: fileURL),
              let raw = try? JSONDecoder().decode([String: WebPortalGroupPESettings].self, from: data) else {
            return WebPortalPESettings()
        }
        var settings = WebPortalPESettings()
        for (key, value) in raw {
            if let classId = Int64(key) { settings.groups[classId] = value }
        }
        return settings
    }

    private static let lock = NSLock()

    @discardableResult
    static func mutate(
        fileURL: URL,
        _ change: (inout WebPortalPESettings) -> Void
    ) throws -> WebPortalPESettings {
        lock.lock()
        defer { lock.unlock() }
        var settings = load(fileURL: fileURL)
        change(&settings)
        let raw = Dictionary(uniqueKeysWithValues: settings.groups.map { (String($0.key), $0.value) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(raw).write(to: fileURL, options: [.atomic])
        return settings
    }
}
