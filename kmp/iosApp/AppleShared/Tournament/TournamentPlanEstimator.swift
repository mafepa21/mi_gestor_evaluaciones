import Foundation

struct TournamentPlanEstimate: Equatable {
    let roundCount: Int
    let matchCount: Int
    let estimatedDurationMinutes: Int

    var durationText: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        let seconds = TimeInterval(estimatedDurationMinutes * 60)
        return formatter.string(from: seconds) ?? "\(estimatedDurationMinutes) min"
    }
}

enum TournamentPlanEstimator {
    static func estimate(
        format: TournamentFormat,
        teamCount: Int,
        groupCount: Int,
        qualifiedTeamsPerGroup: Int,
        venueCount: Int,
        matchDurationMinutes: Int,
        transitionMinutes: Int
    ) -> TournamentPlanEstimate? {
        guard teamCount >= 2, venueCount >= 1 else { return nil }

        let roundDuration = max(1, matchDurationMinutes + transitionMinutes)
        let teamNames = TournamentPlan.defaultTeamNames(count: teamCount)
        let resolvedGroupCount = format == .groupStageKnockout ? max(1, groupCount) : nil
        let resolvedQualified = clampedQualifiedTeams(
            format: format,
            teamCount: teamCount,
            groupCount: resolvedGroupCount ?? 0,
            qualifiedTeamsPerGroup: qualifiedTeamsPerGroup
        )

        guard let rounds = try? TournamentScheduleGenerator.generate(
            format: format,
            teamNames: teamNames,
            venueCount: venueCount,
            groupCount: resolvedGroupCount,
            qualifiedTeamsPerGroup: resolvedQualified
        ) else {
            return nil
        }

        let matches = rounds.flatMap(\.matches).count
        guard matches > 0, !rounds.isEmpty else { return nil }

        return TournamentPlanEstimate(
            roundCount: rounds.count,
            matchCount: matches,
            estimatedDurationMinutes: rounds.count * roundDuration
        )
    }

    private static func clampedQualifiedTeams(
        format: TournamentFormat,
        teamCount: Int,
        groupCount: Int,
        qualifiedTeamsPerGroup: Int
    ) -> Int {
        guard format == .groupStageKnockout, groupCount > 0 else {
            return qualifiedTeamsPerGroup
        }

        let minimum = GroupStageConfiguration.minimumQualifiedTeamsPerGroup(
            groupCount: groupCount,
            teamCount: teamCount
        )
        let maximum = GroupStageConfiguration.maximumQualifiedTeamsPerGroup(
            groupCount: groupCount,
            teamCount: teamCount
        )
        return min(max(qualifiedTeamsPerGroup, minimum), maximum)
    }
}
