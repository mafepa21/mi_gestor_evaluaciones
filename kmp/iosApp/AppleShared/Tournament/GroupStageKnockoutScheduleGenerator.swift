import Foundation

struct GroupStageKnockoutScheduleGenerator {
    static func generate(
        teamNames: [String],
        venueCount: Int,
        groupCount: Int? = nil,
        qualifiedTeamsPerGroup: Int = 2
    ) throws -> [ScheduledRound] {
        guard teamNames.count >= 2 else {
            throw ScheduleGenerationError.notEnoughTeams
        }
        guard venueCount > 0 else {
            throw ScheduleGenerationError.noVenues
        }

        let resolvedGroupCount = groupCount
            ?? GroupStageConfiguration.defaultGroupCount(for: teamNames.count)
        guard let groupOption = GroupStageConfiguration.option(
            for: resolvedGroupCount,
            teamCount: teamNames.count
        ) else {
            throw ScheduleGenerationError.invalidGroupConfiguration
        }

        let minimumQualified = GroupStageConfiguration.minimumQualifiedTeamsPerGroup(
            groupCount: resolvedGroupCount,
            teamCount: teamNames.count
        )
        guard qualifiedTeamsPerGroup >= minimumQualified,
              qualifiedTeamsPerGroup <= groupOption.minimumGroupSize
        else {
            throw ScheduleGenerationError.invalidGroupConfiguration
        }

        let groups = GroupStageConfiguration.groups(
            teamNames: teamNames,
            groupCount: resolvedGroupCount
        )
        let groupRounds = try generateGroupRounds(
            groups: groups,
            teamNames: teamNames,
            venueCount: venueCount
        )
        let qualifiedParticipants = GroupStageConfiguration.qualifiedParticipantNames(
            groupCount: resolvedGroupCount,
            teamsPerGroup: qualifiedTeamsPerGroup
        )
        let knockoutRounds = try KnockoutScheduleGenerator.generate(
            teamNames: qualifiedParticipants,
            venueCount: venueCount
        ).map { round in
            ScheduledRound(
                id: round.id,
                number: round.number + groupRounds.count,
                matches: round.matches,
                stage: .knockout
            )
        }

        return groupRounds + knockoutRounds
    }

    private static func generateGroupRounds(
        groups: [[String]],
        teamNames: [String],
        venueCount: Int
    ) throws -> [ScheduledRound] {
        var matches: [ScheduledMatch] = []

        for group in groups {
            let groupRounds = try RoundRobinScheduleGenerator.generate(
                teamNames: group,
                venueCount: max(group.count, 1)
            )
            matches.append(contentsOf: groupRounds.flatMap(\.matches))
        }

        return BalancedScheduleGenerator.generate(
            matches: matches,
            teamNames: teamNames,
            venueCount: venueCount,
            stage: .groupStage
        )
    }
}
