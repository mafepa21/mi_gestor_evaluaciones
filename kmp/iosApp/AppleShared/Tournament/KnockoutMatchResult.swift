import Foundation

struct KnockoutMatchResult: Identifiable, Hashable, Codable {
    let matchID: UUID
    let homeTeam: String
    let awayTeam: String
    let homeScore: Int
    let awayScore: Int

    var id: UUID { matchID }

    var winner: String? {
        if homeScore == awayScore { return nil }
        return homeScore > awayScore ? homeTeam : awayTeam
    }

    var isDecisive: Bool {
        homeScore != awayScore
    }

    init(
        matchID: UUID,
        homeTeam: String,
        awayTeam: String,
        homeScore: Int,
        awayScore: Int
    ) {
        self.matchID = matchID
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
        self.homeScore = homeScore
        self.awayScore = awayScore
    }
}
