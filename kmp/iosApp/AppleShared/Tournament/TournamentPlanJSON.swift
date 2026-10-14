import Foundation

/// Configuración serializable del torneo (columna `config_json`).
struct TournamentPlanConfigSnapshot: Equatable, Codable, Sendable {
    var format: TournamentFormat
    var startDate: Date
    var groupCount: Int
    var qualifiedTeamsPerGroup: Int
    var venueCount: Int
    var matchDurationMinutes: Int
    var transitionMinutes: Int
    var status: TournamentPlanStatus
    /// Solo en torneos migrados del módulo antiguo de EF; los demás la omiten.
    var legacyExtras: TournamentLegacyExtras?
}

/// Las cinco columnas JSON de `learning_situation_tournaments` más id y nombre.
/// Todas son texto JSON; una columna vacía se interpreta como "sin datos".
struct TournamentPlanColumns: Equatable, Sendable {
    var id: String
    var name: String
    var configJSON: String
    var teamSnapshotJSON: String
    var scheduleJSON: String
    var resultsJSON: String
    var knockoutResultsJSON: String
}

enum TournamentPlanJSON {
    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    /// Devuelve `fallback` si el texto está vacío o es `null`; lanza si hay contenido pero es inválido
    /// (para no pisar datos reales con valores por defecto al volver a guardar).
    static func decode<T: Decodable>(_ type: T.Type, from json: String, fallback: T) throws -> T {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "null" else { return fallback }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(T.self, from: Data(trimmed.utf8))
    }
}

extension TournamentPlan {
    var configSnapshot: TournamentPlanConfigSnapshot {
        TournamentPlanConfigSnapshot(
            format: format,
            startDate: startDate,
            groupCount: groupCount,
            qualifiedTeamsPerGroup: qualifiedTeamsPerGroup,
            venueCount: venueCount,
            matchDurationMinutes: matchDurationMinutes,
            transitionMinutes: transitionMinutes,
            status: status,
            legacyExtras: legacyExtras
        )
    }

    func configJSON() throws -> String { try TournamentPlanJSON.encode(configSnapshot) }
    func teamSnapshotJSON() throws -> String { try TournamentPlanJSON.encode(teams) }
    func scheduleJSON() throws -> String { try TournamentPlanJSON.encode(savedSchedule) }
    func resultsJSON() throws -> String { try TournamentPlanJSON.encode(savedResults) }
    func knockoutResultsJSON() throws -> String { try TournamentPlanJSON.encode(savedKnockoutResults) }

    /// Todas las columnas listas para guardar en SQLDelight.
    func columns() throws -> TournamentPlanColumns {
        TournamentPlanColumns(
            id: id.uuidString,
            name: name,
            configJSON: try configJSON(),
            teamSnapshotJSON: try teamSnapshotJSON(),
            scheduleJSON: try scheduleJSON(),
            resultsJSON: try resultsJSON(),
            knockoutResultsJSON: try knockoutResultsJSON()
        )
    }

    /// Reconstruye el plan desde las columnas. Lanza si el id no es un UUID o algún JSON no vacío es inválido.
    init(columns: TournamentPlanColumns) throws {
        guard let uuid = UUID(uuidString: columns.id) else {
            throw TournamentPlanDecodingError.invalidID(columns.id)
        }
        let defaults = TournamentPlanConfigSnapshot(
            format: .roundRobin,
            startDate: Date(timeIntervalSince1970: 0),
            groupCount: 0,
            qualifiedTeamsPerGroup: 2,
            venueCount: 2,
            matchDurationMinutes: 8,
            transitionMinutes: 2,
            status: .draft
        )
        let config = try TournamentPlanJSON.decode(
            TournamentPlanConfigSnapshot.self, from: columns.configJSON, fallback: defaults
        )
        let teams = try TournamentPlanJSON.decode(
            [TournamentPlanTeam].self, from: columns.teamSnapshotJSON, fallback: []
        )
        self.init(
            id: uuid,
            name: columns.name,
            startDate: config.startDate,
            format: config.format,
            teams: teams,
            groupCount: config.groupCount,
            qualifiedTeamsPerGroup: config.qualifiedTeamsPerGroup,
            venueCount: config.venueCount,
            matchDurationMinutes: config.matchDurationMinutes,
            transitionMinutes: config.transitionMinutes,
            status: config.status
        )
        // El init normaliza groupCount; se respeta el valor guardado tal cual.
        self.groupCount = config.groupCount
        self.legacyExtras = config.legacyExtras
        self.savedSchedule = try TournamentPlanJSON.decode([ScheduledRound].self, from: columns.scheduleJSON, fallback: [])
        self.savedResults = try TournamentPlanJSON.decode([MatchResult].self, from: columns.resultsJSON, fallback: [])
        self.savedKnockoutResults = try TournamentPlanJSON.decode(
            [KnockoutMatchResult].self, from: columns.knockoutResultsJSON, fallback: []
        )
    }
}

enum TournamentPlanDecodingError: Error, Equatable {
    case invalidID(String)
}
