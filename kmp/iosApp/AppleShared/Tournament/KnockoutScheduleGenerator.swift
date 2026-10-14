import Foundation

struct KnockoutScheduleGenerator {
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

        let bracketSize = nextPowerOfTwo(greaterThanOrEqualTo: teamNames.count)
        var participants = teamNames + Array(repeating: nil as String?, count: bracketSize - teamNames.count)
        var rounds: [ScheduledRound] = []
        var matchNumber = 1

        while participants.count > 1 {
            var nextParticipants: [String?] = []
            var matches: [ScheduledMatch] = []

            for pairStart in stride(from: 0, to: participants.count, by: 2) {
                let home = participants[pairStart]
                let away = participants[pairStart + 1]

                switch (home, away) {
                case let (team?, nil), let (nil, team?):
                    nextParticipants.append(team)
                case let (home?, away?):
                    matches.append(
                        ScheduledMatch(
                            homeTeam: home,
                            awayTeam: away,
                            venueNumber: (matches.count % venueCount) + 1
                        )
                    )
                    nextParticipants.append("Ganador P\(matchNumber)")
                    matchNumber += 1
                case (nil, nil):
                    break
                }
            }

            if nextParticipants.count > 1 && nextParticipants.count.isMultiple(of: 2) == false {
                nextParticipants.append(nil)
            }

            rounds.append(
                contentsOf: ScheduleRoundBuilder.split(
                    matches: matches,
                    venueCount: venueCount,
                    startingNumber: rounds.count + 1,
                    stage: .knockout
                )
            )
            participants = nextParticipants
        }

        return rounds
    }

    private static func nextPowerOfTwo(greaterThanOrEqualTo value: Int) -> Int {
        var result = 1
        while result < value {
            result *= 2
        }
        return result
    }
}
