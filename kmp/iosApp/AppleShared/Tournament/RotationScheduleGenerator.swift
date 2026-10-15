import Foundation

struct RotationScheduleGenerator {
    static func generate(
        teamNames: [String],
        venueCount: Int
    ) throws -> [ScheduledRound] {
        guard teamNames.count >= 2 else {
            throw ScheduleGenerationError.notEnoughTeams
        }
        guard venueCount > 0 else {
            throw ScheduleGenerationError.noVenues
        }

        var participants = teamNames
        if participants.count.isMultiple(of: 2) == false {
            participants.append("__bye__")
        }

        var rounds: [ScheduledRound] = []
        for _ in 0..<(participants.count - 1) {
            var matches: [ScheduledMatch] = []

            for pairStart in stride(from: 0, to: participants.count, by: 2) {
                let home = participants[pairStart]
                let away = participants[pairStart + 1]

                guard home != "__bye__", away != "__bye__" else { continue }

                matches.append(
                    ScheduledMatch(
                        homeTeam: home,
                        awayTeam: away,
                        venueNumber: (matches.count % venueCount) + 1
                    )
                )
            }

            rounds.append(
                contentsOf: ScheduleRoundBuilder.split(
                    matches: matches,
                    venueCount: venueCount,
                    startingNumber: rounds.count + 1
                )
            )

            let first = participants.removeFirst()
            participants.append(first)
        }

        return rounds
    }
}
