import Foundation

struct ScheduledMatchSlot: Identifiable, Hashable {
    let match: ScheduledMatch
    let stage: ScheduledRoundStage
    let roundNumber: Int
    let startDate: Date
    let endDate: Date
    let venueNumber: Int

    var id: UUID { match.id }

    var teamNames: [String] {
        [match.homeTeam, match.awayTeam]
    }
}

struct ScheduleMatchScore: Hashable {
    let homeScore: Int
    let awayScore: Int

    var scoreText: String {
        "\(homeScore)–\(awayScore)"
    }

    var isDraw: Bool {
        homeScore == awayScore
    }

    var winningSide: ScheduleMatchWinningSide? {
        if homeScore == awayScore { return nil }
        return homeScore > awayScore ? .home : .away
    }
}

enum ScheduleMatchWinningSide: Hashable {
    case home
    case away
}

struct TeamScheduleLoad: Identifiable, Hashable {
    let teamName: String
    let matchCount: Int
    let shortestRestMinutes: Int?

    var id: String { teamName }
}

struct ScheduleMetrics: Hashable {
    let totalMatches: Int
    let completedMatches: Int
    let roundCount: Int
    let venueCount: Int
    let projectedEndDate: Date?
    let programmedOccupancyPercentage: Int
    let shortestRestMinutes: Int?
    let averageRestMinutes: Int?
    let teamLoads: [TeamScheduleLoad]

    var completionFraction: Double {
        guard totalMatches > 0 else { return 0 }
        return Double(completedMatches) / Double(totalMatches)
    }

    var remainingMatches: Int {
        max(totalMatches - completedMatches, 0)
    }
}

enum ScheduleAnalytics {
    static func slots(
        tournament: TournamentPlan,
        rounds: [ScheduledRound]
    ) -> [ScheduledMatchSlot] {
        let roundDuration = TimeInterval(tournament.roundDurationMinutes * 60)
        let matchDuration = TimeInterval(tournament.matchDurationMinutes * 60)

        return rounds.flatMap { round in
            let startDate = tournament.startDate.addingTimeInterval(
                TimeInterval(max(round.number - 1, 0)) * roundDuration
            )

            return round.matches.map { match in
                let match = resolvedMatch(
                    match,
                    tournament: tournament,
                    rounds: rounds
                )

                return ScheduledMatchSlot(
                    match: match,
                    stage: round.stage,
                    roundNumber: round.number,
                    startDate: startDate,
                    endDate: startDate.addingTimeInterval(matchDuration),
                    venueNumber: match.venueNumber
                )
            }
        }
        .sorted {
            if $0.startDate != $1.startDate {
                return $0.startDate < $1.startDate
            }
            return $0.venueNumber < $1.venueNumber
        }
    }

    private static func resolvedMatch(
        _ match: ScheduledMatch,
        tournament: TournamentPlan,
        rounds: [ScheduledRound]
    ) -> ScheduledMatch {
        guard isKnockoutMatch(match: match, tournament: tournament, rounds: rounds) else {
            return match
        }

        let results = tournament.savedKnockoutResults
        return ScheduledMatch(
            id: match.id,
            homeTeam: KnockoutBracketResolver.resolvedParticipant(
                match.homeTeam,
                rounds: rounds,
                results: results,
                groupResults: tournament.savedResults,
                teamNames: tournament.teamNames,
                groupCount: tournament.groupCount
            ),
            awayTeam: KnockoutBracketResolver.resolvedParticipant(
                match.awayTeam,
                rounds: rounds,
                results: results,
                groupResults: tournament.savedResults,
                teamNames: tournament.teamNames,
                groupCount: tournament.groupCount
            ),
            venueNumber: match.venueNumber
        )
    }

    static func metrics(
        tournament: TournamentPlan,
        rounds: [ScheduledRound]
    ) -> ScheduleMetrics {
        let slots = slots(tournament: tournament, rounds: rounds)
        let completedIDs = completedMatchIDs(tournament: tournament, slots: slots)
        let teamLoads = makeTeamLoads(tournament: tournament, slots: slots)
        let restValues = teamLoads.compactMap(\.shortestRestMinutes)
        let capacity = max(rounds.count * max(tournament.venueCount, 1), 1)

        return ScheduleMetrics(
            totalMatches: slots.count,
            completedMatches: slots.filter { completedIDs.contains($0.id) }.count,
            roundCount: rounds.count,
            venueCount: tournament.venueCount,
            projectedEndDate: slots.map(\.endDate).max(),
            programmedOccupancyPercentage: min(100, Int((Double(slots.count) / Double(capacity) * 100).rounded())),
            shortestRestMinutes: restValues.min(),
            averageRestMinutes: restValues.isEmpty ? nil : Int(Double(restValues.reduce(0, +)) / Double(restValues.count)),
            teamLoads: teamLoads
        )
    }

    static func completedMatchIDs(
        tournament: TournamentPlan,
        slots: [ScheduledMatchSlot]
    ) -> Set<UUID> {
        let results = tournament.savedResults
        let resultIDs = Set(results.compactMap(\.matchID))
        let resultPairs = Set(results.map { pair(home: $0.homeTeam, away: $0.awayTeam) })
        let knockoutResultIDs = Set(tournament.savedKnockoutResults.map(\.matchID))

        return Set(
            slots.compactMap { slot in
                if isKnockoutMatch(slot: slot, tournament: tournament) {
                    return knockoutResultIDs.contains(slot.id) ? slot.id : nil
                }

                if resultIDs.contains(slot.id) || resultPairs.contains(pair(for: slot.match)) {
                    return slot.id
                }
                return nil
            }
        )
    }

    static func result(
        for slot: ScheduledMatchSlot,
        tournament: TournamentPlan
    ) -> ScheduleMatchScore? {
        if isKnockoutMatch(slot: slot, tournament: tournament) {
            guard let result = tournament.savedKnockoutResults.first(where: { $0.matchID == slot.id }) else {
                return nil
            }

            return ScheduleMatchScore(
                homeScore: result.homeScore,
                awayScore: result.awayScore
            )
        }

        let results = tournament.savedResults
        let result = results.first(where: { $0.matchID == slot.id })
            ?? results.first(where: {
                pair(home: $0.homeTeam, away: $0.awayTeam) == pair(for: slot.match)
            })

        guard let result else { return nil }

        return ScheduleMatchScore(
            homeScore: result.homeScore,
            awayScore: result.awayScore
        )
    }

    static func isCompleted(
        _ slot: ScheduledMatchSlot,
        tournament: TournamentPlan
    ) -> Bool {
        completedMatchIDs(tournament: tournament, slots: [slot]).contains(slot.id)
    }

    static func nextSlot(
        tournament: TournamentPlan,
        rounds: [ScheduledRound]
    ) -> ScheduledMatchSlot? {
        let allSlots = slots(tournament: tournament, rounds: rounds)
        let completedIDs = completedMatchIDs(tournament: tournament, slots: allSlots)
        return allSlots.first { !completedIDs.contains($0.id) }
    }

    private static func makeTeamLoads(
        tournament: TournamentPlan,
        slots: [ScheduledMatchSlot]
    ) -> [TeamScheduleLoad] {
        tournament.teamNames.map { teamName in
            let teamSlots = slots
                .filter { $0.teamNames.contains(teamName) }
                .sorted { $0.startDate < $1.startDate }

            let rests = zip(teamSlots, teamSlots.dropFirst()).map { previous, next in
                max(0, Int(next.startDate.timeIntervalSince(previous.endDate) / 60))
            }

            return TeamScheduleLoad(
                teamName: teamName,
                matchCount: teamSlots.count,
                shortestRestMinutes: rests.min()
            )
        }
    }

    private static func pair(for match: ScheduledMatch) -> String {
        pair(home: match.homeTeam, away: match.awayTeam)
    }

    private static func pair(home: String, away: String) -> String {
        [home, away].sorted().joined(separator: "::")
    }

    private static func isKnockoutMatch(
        match: ScheduledMatch,
        tournament: TournamentPlan,
        rounds: [ScheduledRound]
    ) -> Bool {
        guard tournament.format.includesKnockoutPhase else { return false }
        if tournament.format == .knockout { return true }

        return rounds.first(where: { $0.matches.contains(where: { $0.id == match.id }) })?.stage == .knockout
    }

    private static func isKnockoutMatch(
        slot: ScheduledMatchSlot,
        tournament: TournamentPlan
    ) -> Bool {
        tournament.format == .knockout || (
            tournament.format == .groupStageKnockout && slot.stage == .knockout
        )
    }
}
