import Foundation

/// Qué notas deja ver el docente en el portal del alumnado (ticket fase 2, 4.2).
///
/// Vive solo en este equipo: `Documentos/EntregasWeb/portal/notas-visibles.json`,
/// junto a `alumnos.json`. No viaja por Sync LAN (decisión 4.3): solo publica el Mac
/// que tiene las llaves. Todo está apagado mientras no se encienda a mano.
///
/// Formato: `{ "<classId>": { "media": false, "columnas": { "<columnId>": true }, "confirmadas": ["<columnId>"] } }`.
struct WebPortalGroupGradeSettings: Codable, Equatable {
    /// «Mostrar la media» del grupo.
    var media = false
    /// Interruptor de cada columna. Lo que falta está apagado.
    var columnas: [String: Bool] = [:]
    /// Columnas que ya pasaron el aviso «¿Mostrar esta nota al alumnado?».
    var confirmadas: [String] = []

    func isVisible(columnId: String) -> Bool { columnas[columnId] == true }

    func needsConfirmation(columnId: String) -> Bool { !confirmadas.contains(columnId) }

    /// Alguna columna encendida: solo estos grupos se vigilan.
    var hasActiveColumns: Bool { columnas.values.contains(true) }

    var visibleColumnIds: Set<String> { Set(columnas.filter { $0.value }.map(\.key)) }
}

struct WebPortalGradeSettings: Equatable {
    private(set) var groups: [Int64: WebPortalGroupGradeSettings] = [:]

    subscript(classId: Int64) -> WebPortalGroupGradeSettings {
        get { groups[classId] ?? WebPortalGroupGradeSettings() }
        set { groups[classId] = newValue }
    }

    var activeClassIds: Set<Int64> {
        Set(groups.filter { $0.value.hasActiveColumns }.map(\.key))
    }

    // MARK: Disco

    /// `Documentos/EntregasWeb/portal/notas-visibles.json`.
    static func standardURL() -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documents
            .appendingPathComponent("EntregasWeb", isDirectory: true)
            .appendingPathComponent("portal", isDirectory: true)
            .appendingPathComponent("notas-visibles.json")
    }

    /// Fichero ausente o ilegible: todo apagado.
    static func load(fileURL: URL) -> WebPortalGradeSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let raw = try? JSONDecoder().decode([String: WebPortalGroupGradeSettings].self, from: data) else {
            return WebPortalGradeSettings()
        }
        var settings = WebPortalGradeSettings()
        for (key, value) in raw {
            if let classId = Int64(key) { settings.groups[classId] = value }
        }
        return settings
    }

    private static let lock = NSLock()

    /// Lee, cambia y guarda de una vez (escritura atómica). Devuelve lo guardado.
    @discardableResult
    static func mutate(
        fileURL: URL,
        _ change: (inout WebPortalGradeSettings) -> Void
    ) throws -> WebPortalGradeSettings {
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
