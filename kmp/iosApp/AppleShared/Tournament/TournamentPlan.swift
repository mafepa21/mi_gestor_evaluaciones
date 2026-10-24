import Foundation

enum TournamentFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case roundRobin
    case knockout
    case groupStageKnockout
    case rotation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .roundRobin:
            "Liga"
        case .knockout:
            "Eliminatoria"
        case .groupStageKnockout:
            "Liguilla + eliminatorias"
        case .rotation:
            "Rotaciones"
        }
    }

    var description: String {
        switch self {
        case .roundRobin:
            "Todos juegan varias rondas contra distintos rivales."
        case .knockout:
            "Cada partido elimina a un equipo hasta llegar a la final."
        case .groupStageKnockout:
            "Se forman grupos, los mejores pasan y se cruzan en un cuadro eliminatorio."
        case .rotation:
            "Rondas rápidas para repartir equipos y pistas."
        }
    }

    var includesKnockoutPhase: Bool {
        self == .knockout || self == .groupStageKnockout
    }

}

enum TournamentPlanStatus: String, Codable, Sendable {
    case draft
    case scheduled
    case live
    case finished

    var title: String {
        switch self {
        case .draft:
            "Borrador"
        case .scheduled:
            "Planificado"
        case .live:
            "En curso"
        case .finished:
            "Finalizado"
        }
    }

    var colorName: String {
        switch self {
        case .draft:
            "secondary"
        case .scheduled:
            "indigo"
        case .live:
            "green"
        case .finished:
            "orange"
        }
    }
}

/// Equipo de un torneo. En la Situación de Aprendizaje, `id` es el id del grupo de trabajo
/// (texto, para no atar el motor al tipo numérico de KMP) y `studentIDs` los alumnos que lo forman.
struct TournamentPlanTeam: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var name: String
    var studentIDs: [String]

    init(id: String = UUID().uuidString, name: String, studentIDs: [String] = []) {
        self.id = id
        self.name = name
        self.studentIDs = studentIDs
    }
}

/// Torneo como valor puro (sin SwiftData): configuración, equipos, calendario y resultados.
/// Los equipos se identifican por nombre en calendario y resultados, así que los nombres
/// deben ser únicos dentro del plan.
struct TournamentPlan: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var name: String
    var startDate: Date
    var format: TournamentFormat
    var teams: [TournamentPlanTeam]
    var groupCount: Int
    var qualifiedTeamsPerGroup: Int
    var venueCount: Int
    var matchDurationMinutes: Int
    var transitionMinutes: Int
    var status: TournamentPlanStatus
    /// Calendario generado. Se rellena con `persistSchedule`.
    var savedSchedule: [ScheduledRound] = []
    /// Resultados de liga / liguilla. Se rellenan con `persistResults`.
    var savedResults: [MatchResult] = []
    /// Resultados de eliminatoria. Se rellenan con `persistKnockoutResults`.
    var savedKnockoutResults: [KnockoutMatchResult] = []
    /// Datos que solo tienen los torneos migrados del módulo antiguo de EF. Se conservan al guardar.
    var legacyExtras: TournamentLegacyExtras?
    /// Formulario de inscripción por entregas web, si el torneo lo usa.
    var registration: TournamentRegistration?

    init(
        id: UUID = UUID(),
        name: String,
        startDate: Date = Date(),
        format: TournamentFormat = .roundRobin,
        teams: [TournamentPlanTeam],
        groupCount: Int = 0,
        qualifiedTeamsPerGroup: Int = 2,
        venueCount: Int = 2,
        matchDurationMinutes: Int = 8,
        transitionMinutes: Int = 2,
        status: TournamentPlanStatus = .draft
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.format = format
        self.teams = teams
        self.groupCount = format == .groupStageKnockout
            ? (groupCount > 0
                ? groupCount
                : GroupStageConfiguration.defaultGroupCount(for: teams.count))
            : 0
        self.qualifiedTeamsPerGroup = qualifiedTeamsPerGroup
        self.venueCount = venueCount
        self.matchDurationMinutes = matchDurationMinutes
        self.transitionMinutes = transitionMinutes
        self.status = status
    }

    /// Crea un torneo con equipos genéricos "Equipo 1…N" (igual que el original).
    init(
        name: String,
        startDate: Date = Date(),
        format: TournamentFormat = .roundRobin,
        teamCount: Int = 8,
        groupCount: Int = 0,
        qualifiedTeamsPerGroup: Int = 2,
        venueCount: Int = 2,
        matchDurationMinutes: Int = 8,
        transitionMinutes: Int = 2,
        status: TournamentPlanStatus = .draft
    ) {
        self.init(
            name: name,
            startDate: startDate,
            format: format,
            teams: Self.defaultTeamNames(count: teamCount).map { TournamentPlanTeam(name: $0) },
            groupCount: groupCount,
            qualifiedTeamsPerGroup: qualifiedTeamsPerGroup,
            venueCount: venueCount,
            matchDurationMinutes: matchDurationMinutes,
            transitionMinutes: transitionMinutes,
            status: status
        )
    }

    var teamNames: [String] { teams.map(\.name) }

    var teamCount: Int { teams.count }

    var roundDurationMinutes: Int {
        matchDurationMinutes + transitionMinutes
    }

    static func defaultTeamNames(count: Int) -> [String] {
        guard count > 0 else { return [] }
        return (1...count).map { "Equipo \($0)" }
    }

    /// Nombres de equipo repetidos (rompen calendario y clasificación, que se basan en el nombre).
    var duplicatedTeamNames: [String] {
        var seen = Set<String>()
        var duplicated: [String] = []
        for name in teamNames where !seen.insert(name).inserted && !duplicated.contains(name) {
            duplicated.append(name)
        }
        return duplicated
    }
}
