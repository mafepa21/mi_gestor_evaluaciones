import Foundation

struct KnockoutBracketStage: Identifiable {
    let id: Int
    let title: String
    let matches: [ScheduledMatch]
}

struct KnockoutBracketResolver {
    static func allMatches(in rounds: [ScheduledRound]) -> [ScheduledMatch] {
        rounds.filter { $0.stage == .knockout || !rounds.contains(where: { $0.stage == .knockout }) }
            .flatMap(\.matches)
    }

    static func stages(in rounds: [ScheduledRound]) -> [KnockoutBracketStage] {
        let matches = allMatches(in: rounds)
        guard !matches.isEmpty else { return [] }

        var stageByMatchID: [UUID: Int] = [:]
        var matchesByStage: [[ScheduledMatch]] = []

        for match in matches {
            let parentStages = [match.homeTeam, match.awayTeam].compactMap { participant -> Int? in
                guard let number = bracketMatchNumber(from: participant) else { return nil }
                guard matches.indices.contains(number - 1) else { return nil }
                return stageByMatchID[matches[number - 1].id]
            }

            let stageIndex = (parentStages.max() ?? -1) + 1
            while matchesByStage.count <= stageIndex {
                matchesByStage.append([])
            }

            matchesByStage[stageIndex].append(match)
            stageByMatchID[match.id] = stageIndex
        }

        let finalStageIndex = matchesByStage.count - 1
        return matchesByStage.enumerated().map { index, matches in
            KnockoutBracketStage(
                id: index,
                title: stageTitle(index: index, finalStageIndex: finalStageIndex),
                matches: matches
            )
        }
    }

    static func parentMatchIDs(
        for match: ScheduledMatch,
        in rounds: [ScheduledRound]
    ) -> [UUID] {
        let matches = allMatches(in: rounds)

        return [match.homeTeam, match.awayTeam].compactMap { participant in
            guard let number = bracketMatchNumber(from: participant),
                  matches.indices.contains(number - 1)
            else {
                return nil
            }

            return matches[number - 1].id
        }
    }

    static func nextStageIndex(
        rounds: [ScheduledRound],
        results: [KnockoutMatchResult]
    ) -> Int {
        let bracketStages = stages(in: rounds)

        return bracketStages.first(where: { stage in
            stage.matches.contains { match in
                !results.contains { $0.matchID == match.id && $0.isDecisive }
            }
        })?.id ?? max(bracketStages.count - 1, 0)
    }

    static func resolvedParticipant(
        _ participant: String,
        rounds: [ScheduledRound],
        results: [KnockoutMatchResult],
        groupResults: [MatchResult] = [],
        teamNames: [String] = [],
        groupCount: Int = 0
    ) -> String {
        if let qualifier = qualifier(from: participant), !teamNames.isEmpty {
            let resolvedGroupCount = groupCount > 0
                ? groupCount
                : GroupStageConfiguration.defaultGroupCount(for: teamNames.count)
            let groups = GroupStageConfiguration.groups(
                teamNames: teamNames,
                groupCount: resolvedGroupCount
            )

            if let groupIndex = qualifier.groupIndex,
               groups.indices.contains(groupIndex) {
                let standings = StandingsCalculator.calculate(
                    teamNames: groups[groupIndex],
                    results: groupResults
                )
                if let qualifiedTeam = standings.dropFirst(qualifier.position - 1).first?.teamName {
                    return qualifiedTeam
                }
            } else if qualifier.groupIndex == nil,
                      let qualifiedTeam = StandingsCalculator.calculate(
                          teamNames: teamNames,
                          results: groupResults
                      ).dropFirst(qualifier.position - 1).first?.teamName {
                return qualifiedTeam
            }
        }

        guard let matchNumber = bracketMatchNumber(from: participant) else {
            return participant
        }

        let matches = allMatches(in: rounds)
        guard matches.indices.contains(matchNumber - 1) else {
            return participant
        }

        let referencedMatch = matches[matchNumber - 1]
        guard let result = results.first(where: { $0.matchID == referencedMatch.id }),
              let winner = result.winner
        else {
            return participant
        }

        return winner
    }

    static func nextRoundIndex(
        rounds: [ScheduledRound],
        results: [KnockoutMatchResult]
    ) -> Int {
        for (index, round) in rounds.enumerated() {
            if round.matches.contains(where: { match in
                !results.contains(where: { $0.matchID == match.id && $0.isDecisive })
            }) {
                return index
            }
        }

        return max(rounds.count - 1, 0)
    }

    static func isFinished(
        rounds: [ScheduledRound],
        results: [KnockoutMatchResult]
    ) -> Bool {
        !rounds.isEmpty && allMatches(in: rounds).allSatisfy { match in
            results.contains(where: { $0.matchID == match.id && $0.isDecisive })
        }
    }

    static func champion(
        rounds: [ScheduledRound],
        results: [KnockoutMatchResult]
    ) -> String? {
        guard let finalMatch = allMatches(in: rounds).last,
              let finalResult = results.first(where: { $0.matchID == finalMatch.id })
        else {
            return nil
        }

        return finalResult.winner
    }

    private static func bracketMatchNumber(from participant: String) -> Int? {
        let normalized = participant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.hasPrefix("Ganador P") else { return nil }
        return Int(normalized.dropFirst("Ganador P".count))
    }

    private static func qualifier(
        from participant: String
    ) -> (position: Int, groupIndex: Int?)? {
        let normalized = participant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.hasPrefix("Clasificado ") else { return nil }

        let components = normalized.split(separator: " ")
        guard components.count >= 2,
              let position = Int(components[1])
        else {
            return nil
        }

        guard components.count >= 4,
              components[2] == "Grupo",
              let groupLetter = components[3].first
        else {
            return (position, nil)
        }

        let groupIndex = Int(groupLetter.asciiValue ?? 65) - 65
        return (position, groupIndex)
    }

    private static func stageTitle(index: Int, finalStageIndex: Int) -> String {
        switch finalStageIndex - index {
        case 0:
            "Final"
        case 1:
            "Semifinales"
        case 2:
            "Cuartos de final"
        case 3:
            "Octavos de final"
        case 4:
            "Dieciseisavos"
        default:
            "Ronda \(index + 1)"
        }
    }
}
