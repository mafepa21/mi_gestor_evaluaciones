import Foundation

/// Ajustes locales de «Torneos» en el portal del alumnado (ticket fase 3B, 4.2).
///
/// Solo viven en el Mac que tiene las llaves del portal (`Documentos/EntregasWeb/portal/torneos-visibles.json`),
/// igual que `alumnos.json` y `notas-visibles.json`: no viajan por Sync LAN.
/// Todo empieza apagado si falta el fichero o la entrada.
struct WebPortalTournamentVisibility: Codable, Equatable {
    /// Si el torneo se publica en el portal del grupo.
    var visible: Bool = false
    /// Si se enseñan los nombres de equipo del plan en lugar de «Equipo 1, Equipo 2…».
    var mostrarNombres: Bool = false
}

struct WebPortalGroupTournamentSettings: Codable, Equatable {
    /// `<tournamentId>` → visibilidad y nombres de equipo.
    var torneos: [String: WebPortalTournamentVisibility] = [:]
    /// Torneos que ya pasaron el aviso «¿Mostrar este torneo en el portal?».
    var confirmados: [String] = []
    /// Torneos que ya pasaron el aviso «¿Mostrar los nombres de los equipos?».
    var nombresConfirmados: [String] = []

    func isVisible(tournamentId: String) -> Bool { torneos[tournamentId]?.visible == true }

    func showsNames(tournamentId: String) -> Bool {
        guard let item = torneos[tournamentId], item.visible else { return false }
        return item.mostrarNombres
    }

    func needsConfirmation(tournamentId: String) -> Bool { !confirmados.contains(tournamentId) }

    func needsNamesConfirmation(tournamentId: String) -> Bool { !nombresConfirmados.contains(tournamentId) }

    var hasActiveTournaments: Bool { torneos.values.contains { $0.visible } }

    var visibleTournamentIds: Set<String> { Set(torneos.filter { $0.value.visible }.map(\.key)) }
}

/// Qué grupos han publicado torneos y qué grupos esperan publicación
/// (`Documentos/EntregasWeb/portal/torneos-publicados.json`). Sirve para que, tras reiniciar,
/// un grupo que ya está apagado retire de verdad lo que el alumnado aún veía.
struct WebPortalTournamentsPublishedState: Codable, Equatable {
    var conTorneos: [Int64] = []
    var pendientes: [Int64] = []

    static func url(besides settingsURL: URL) -> URL {
        settingsURL.deletingLastPathComponent().appendingPathComponent("torneos-publicados.json")
    }

    static func load(fileURL: URL) -> WebPortalTournamentsPublishedState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(WebPortalTournamentsPublishedState.self, from: data) else {
            return WebPortalTournamentsPublishedState()
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

struct WebPortalTournamentSettings: Equatable {
    private(set) var groups: [Int64: WebPortalGroupTournamentSettings] = [:]

    subscript(classId: Int64) -> WebPortalGroupTournamentSettings {
        get { groups[classId] ?? WebPortalGroupTournamentSettings() }
        set { groups[classId] = newValue }
    }

    /// Grupos con algún torneo visible.
    var activeClassIds: Set<Int64> {
        Set(groups.filter { $0.value.hasActiveTournaments }.map(\.key))
    }

    static func standardURL() -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documents
            .appendingPathComponent("EntregasWeb", isDirectory: true)
            .appendingPathComponent("portal", isDirectory: true)
            .appendingPathComponent("torneos-visibles.json")
    }

    static func load(fileURL: URL) -> WebPortalTournamentSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let raw = try? JSONDecoder().decode([String: WebPortalGroupTournamentSettings].self, from: data) else {
            return WebPortalTournamentSettings()
        }
        var parsed: [Int64: WebPortalGroupTournamentSettings] = [:]
        for (key, value) in raw {
            if let id = Int64(key) { parsed[id] = value }
        }
        return WebPortalTournamentSettings(groups: parsed)
    }

    func save(fileURL: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let raw = Dictionary(uniqueKeysWithValues: groups.map { (String($0.key), $0.value) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(raw).write(to: fileURL, options: [.atomic])
    }

    /// Relee, aplica `body` y escribe atómicamente para no pisar otro cambio simultáneo.
    @discardableResult
    static func mutate(fileURL: URL, _ body: (inout WebPortalTournamentSettings) -> Void) throws -> WebPortalTournamentSettings {
        var current = load(fileURL: fileURL)
        body(&current)
        try current.save(fileURL: fileURL)
        return current
    }
}
