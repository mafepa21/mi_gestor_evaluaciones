import Foundation

struct MatchResult: Identifiable, Hashable, Codable {
    let id: UUID
    let matchID: UUID?
    let homeTeam: String
    let awayTeam: String
    let homeScore: Int
    let awayScore: Int

    init(
        id: UUID = UUID(),
        matchID: UUID? = nil,
        homeTeam: String,
        awayTeam: String,
        homeScore: Int,
        awayScore: Int
    ) {
        self.id = id
        self.matchID = matchID
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
        self.homeScore = homeScore
        self.awayScore = awayScore
    }
}

struct Standing: Identifiable, Hashable {
    let teamName: String
    var played = 0
    var wins = 0
    var draws = 0
    var losses = 0
    var points = 0

    var id: String { teamName }
}

struct StandingsCalculator {
    static func calculate(teamNames: [String], results: [MatchResult]) -> [Standing] {
        var standings = Dictionary(
            uniqueKeysWithValues: teamNames.map { ($0, Standing(teamName: $0)) }
        )

        for result in results {
            guard var home = standings[result.homeTeam], var away = standings[result.awayTeam] else {
                continue
            }

            home.played += 1
            away.played += 1

            if result.homeScore > result.awayScore {
                home.wins += 1
                home.points += 3
                away.losses += 1
            } else if result.homeScore < result.awayScore {
                away.wins += 1
                away.points += 3
                home.losses += 1
            } else {
                home.draws += 1
                away.draws += 1
                home.points += 1
                away.points += 1
            }

            standings[result.homeTeam] = home
            standings[result.awayTeam] = away
        }

        return standings.values.sorted {
            if $0.points != $1.points {
                return $0.points > $1.points
            }
            if $0.wins != $1.wins {
                return $0.wins > $1.wins
            }
            return $0.teamName.localizedStandardCompare($1.teamName) == .orderedAscending
        }
    }
}
