import Foundation

struct TournamentScheduleGenerator {
    static func generate(
        format: TournamentFormat,
        teamNames: [String],
        venueCount: Int,
        groupCount: Int? = nil,
        qualifiedTeamsPerGroup: Int = 2
    ) throws -> [ScheduledRound] {
        switch format {
        case .roundRobin:
            try RoundRobinScheduleGenerator.generate(
                teamNames: teamNames,
                venueCount: venueCount
            )
        case .knockout:
            try KnockoutScheduleGenerator.generate(
                teamNames: teamNames,
                venueCount: venueCount
            )
        case .groupStageKnockout:
            try GroupStageKnockoutScheduleGenerator.generate(
                teamNames: teamNames,
                venueCount: venueCount,
                groupCount: groupCount,
                qualifiedTeamsPerGroup: qualifiedTeamsPerGroup
            )
        case .rotation:
            try RotationScheduleGenerator.generate(
                teamNames: teamNames,
                venueCount: venueCount
            )
        }
    }
}
