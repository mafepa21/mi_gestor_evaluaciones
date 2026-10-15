import Foundation

// Mutaciones del plan (sustituyen a los métodos `persist*` de SwiftData del original).
// Cada cambio que invalida el calendario reinicia resultados y estado, como en el original.
extension TournamentPlan {
    mutating func persistSchedule(_ rounds: [ScheduledRound]) {
        savedSchedule = rounds
        savedResults = []
        savedKnockoutResults = []
        status = .scheduled
    }

    mutating func persistResults(_ results: [MatchResult]) {
        savedResults = results
    }

    mutating func persistKnockoutResults(_ results: [KnockoutMatchResult]) {
        savedKnockoutResults = results
    }

    /// Sustituye los equipos conservando id y alumnos de los que mantienen el nombre.
    mutating func replaceTeamNames(_ names: [String]) {
        let existing = Dictionary(
            teams.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        replaceTeams(names.map { existing[$0] ?? TournamentPlanTeam(name: $0) })
    }

    /// Sustituye los equipos (p. ej. al volver a leer los grupos de trabajo) e invalida el calendario.
    mutating func replaceTeams(_ newTeams: [TournamentPlanTeam]) {
        teams = newTeams
        if format == .groupStageKnockout {
            let names = newTeams.map(\.name)
            let resolvedGroupCount = GroupStageConfiguration.option(
                for: groupCount,
                teamCount: names.count
            )?.groupCount ?? GroupStageConfiguration.defaultGroupCount(for: names.count)
            let minimumQualified = GroupStageConfiguration.minimumQualifiedTeamsPerGroup(
                groupCount: resolvedGroupCount,
                teamCount: names.count
            )
            let maximumQualified = GroupStageConfiguration.maximumQualifiedTeamsPerGroup(
                groupCount: resolvedGroupCount,
                teamCount: names.count
            )

            groupCount = resolvedGroupCount
            qualifiedTeamsPerGroup = min(
                max(qualifiedTeamsPerGroup, minimumQualified),
                max(minimumQualified, maximumQualified)
            )
        }
        savedSchedule = []
        savedResults = []
        savedKnockoutResults = []
        status = .draft
    }
}
