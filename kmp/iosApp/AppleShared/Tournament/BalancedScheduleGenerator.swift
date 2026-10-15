import Foundation

/// Distributes matches into physical rounds while keeping team workloads as even as possible.
/// A team is never scheduled twice in the same round, and teams with fewer matches are
/// preferred before teams that are already ahead in the schedule.
struct BalancedScheduleGenerator {
    static func generate(
        matches: [ScheduledMatch],
        teamNames: [String],
        venueCount: Int,
        stage: ScheduledRoundStage
    ) -> [ScheduledRound] {
        guard venueCount > 0, !matches.isEmpty else { return [] }

        let orderedTeams = uniqueTeams(from: teamNames, matches: matches)
        let teamOrder = Dictionary(
            uniqueKeysWithValues: orderedTeams.enumerated().map { ($1, $0) }
        )
        var pending = matches
        var matchCounts = Dictionary(
            uniqueKeysWithValues: orderedTeams.map { ($0, 0) }
        )
        var lastRoundByTeam = Dictionary(
            uniqueKeysWithValues: orderedTeams.map { ($0, 0) }
        )
        var rounds: [ScheduledRound] = []

        while !pending.isEmpty {
            var selectedMatches: [ScheduledMatch] = []
            var teamsInRound = Set<String>()

            while selectedMatches.count < venueCount {
                guard let candidateIndex = selectCandidate(
                    from: pending,
                    teamNames: orderedTeams,
                    teamOrder: teamOrder,
                    matchCounts: matchCounts,
                    lastRoundByTeam: lastRoundByTeam,
                    teamsInRound: teamsInRound
                ) else {
                    break
                }

                let match = pending.remove(at: candidateIndex)
                selectedMatches.append(match)
                teamsInRound.insert(match.homeTeam)
                teamsInRound.insert(match.awayTeam)
            }

            guard !selectedMatches.isEmpty else {
                break
            }

            let roundNumber = rounds.count + 1
            let scheduledMatches = selectedMatches.enumerated().map { index, match in
                ScheduledMatch(
                    id: match.id,
                    homeTeam: match.homeTeam,
                    awayTeam: match.awayTeam,
                    venueNumber: index + 1
                )
            }

            rounds.append(
                ScheduledRound(
                    number: roundNumber,
                    matches: scheduledMatches,
                    stage: stage
                )
            )

            for match in selectedMatches {
                matchCounts[match.homeTeam, default: 0] += 1
                matchCounts[match.awayTeam, default: 0] += 1
                lastRoundByTeam[match.homeTeam] = roundNumber
                lastRoundByTeam[match.awayTeam] = roundNumber
            }
        }

        return rounds
    }

    private static func selectCandidate(
        from pending: [ScheduledMatch],
        teamNames: [String],
        teamOrder: [String: Int],
        matchCounts: [String: Int],
        lastRoundByTeam: [String: Int],
        teamsInRound: Set<String>
    ) -> Int? {
        let priorityTeams = teamNames.sorted { lhs, rhs in
            let lhsCount = matchCounts[lhs, default: 0]
            let rhsCount = matchCounts[rhs, default: 0]
            if lhsCount != rhsCount { return lhsCount < rhsCount }

            let lhsLastRound = lastRoundByTeam[lhs, default: 0]
            let rhsLastRound = lastRoundByTeam[rhs, default: 0]
            if lhsLastRound != rhsLastRound { return lhsLastRound < rhsLastRound }

            return teamOrder[lhs, default: .max] < teamOrder[rhs, default: .max]
        }

        for team in priorityTeams where !teamsInRound.contains(team) {
            let candidateIndices = pending.indices.filter { index in
                let match = pending[index]
                guard match.homeTeam == team || match.awayTeam == team else {
                    return false
                }

                return !teamsInRound.contains(match.homeTeam)
                    && !teamsInRound.contains(match.awayTeam)
            }

            if let candidateIndex = candidateIndices.min(by: { lhs, rhs in
                candidateScore(
                    for: pending[lhs],
                    targetTeam: team,
                    matchCounts: matchCounts,
                    teamOrder: teamOrder,
                    originalIndex: lhs
                ) < candidateScore(
                    for: pending[rhs],
                    targetTeam: team,
                    matchCounts: matchCounts,
                    teamOrder: teamOrder,
                    originalIndex: rhs
                )
            }) {
                return candidateIndex
            }
        }

        return nil
    }

    private static func candidateScore(
        for match: ScheduledMatch,
        targetTeam: String,
        matchCounts: [String: Int],
        teamOrder: [String: Int],
        originalIndex: Int
    ) -> (Int, Int, Int, Int, Int) {
        let opponent = match.homeTeam == targetTeam ? match.awayTeam : match.homeTeam
        let targetCount = matchCounts[targetTeam, default: 0]
        let opponentCount = matchCounts[opponent, default: 0]

        return (
            max(targetCount, opponentCount),
            targetCount + opponentCount,
            opponentCount,
            teamOrder[opponent, default: .max],
            originalIndex
        )
    }

    private static func uniqueTeams(
        from teamNames: [String],
        matches: [ScheduledMatch]
    ) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for team in teamNames + matches.flatMap({ [$0.homeTeam, $0.awayTeam] }) {
            if seen.insert(team).inserted {
                ordered.append(team)
            }
        }

        return ordered
    }
}
