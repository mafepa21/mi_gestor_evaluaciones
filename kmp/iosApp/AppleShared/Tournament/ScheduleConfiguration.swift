import Foundation

struct ScheduleConfiguration: Equatable, Hashable, Codable, Sendable {
    var format: TournamentFormat
    var groupCount: Int = 0
    var qualifiedTeamsPerGroup: Int = 2
    var venueCount: Int
    var matchDurationMinutes: Int
    var transitionMinutes: Int
}

extension TournamentPlan {
    var scheduleConfiguration: ScheduleConfiguration {
        ScheduleConfiguration(
            format: format,
            groupCount: groupCount,
            qualifiedTeamsPerGroup: qualifiedTeamsPerGroup,
            venueCount: venueCount,
            matchDurationMinutes: matchDurationMinutes,
            transitionMinutes: transitionMinutes
        )
    }

    mutating func applyScheduleConfiguration(_ configuration: ScheduleConfiguration) {
        format = configuration.format
        if configuration.format == .groupStageKnockout {
            let resolvedGroupCount = GroupStageConfiguration.option(
                for: configuration.groupCount,
                teamCount: teamCount
            )?.groupCount ?? GroupStageConfiguration.defaultGroupCount(for: teamCount)
            let minimumQualified = GroupStageConfiguration.minimumQualifiedTeamsPerGroup(
                groupCount: resolvedGroupCount,
                teamCount: teamCount
            )
            let maximumQualified = GroupStageConfiguration.maximumQualifiedTeamsPerGroup(
                groupCount: resolvedGroupCount,
                teamCount: teamCount
            )

            groupCount = resolvedGroupCount
            qualifiedTeamsPerGroup = min(
                max(configuration.qualifiedTeamsPerGroup, minimumQualified),
                max(minimumQualified, maximumQualified)
            )
        } else {
            groupCount = 0
            qualifiedTeamsPerGroup = configuration.qualifiedTeamsPerGroup
        }
        venueCount = configuration.venueCount
        matchDurationMinutes = configuration.matchDurationMinutes
        transitionMinutes = configuration.transitionMinutes
        savedSchedule = []
        savedResults = []
        savedKnockoutResults = []
        status = .draft
    }
}
