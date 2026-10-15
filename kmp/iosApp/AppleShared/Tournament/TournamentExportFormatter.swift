import Foundation

enum TournamentExportFormatter {
    static func scheduleText(
        tournament: TournamentPlan,
        rounds: [ScheduledRound]
    ) -> String {
        var lines = header(for: tournament)
        lines.append("Calendario")
        lines.append("")

        for round in rounds {
            let date = tournament.startDate.addingTimeInterval(
                TimeInterval((round.number - 1) * tournament.roundDurationMinutes * 60)
            )
            lines.append("Ronda \(round.number) · \(date.formatted(date: .omitted, time: .shortened))")
            for match in round.matches {
                lines.append("  Pista \(match.venueNumber): \(match.homeTeam) vs \(match.awayTeam)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    static func roundRobinResultsText(
        tournament: TournamentPlan,
        results: [MatchResult]
    ) -> String {
        var lines = header(for: tournament)
        lines.append("Resultados")
        lines.append("")

        for result in results {
            lines.append("\(result.homeTeam) \(result.homeScore)–\(result.awayScore) \(result.awayTeam)")
        }

        lines.append("")
        lines.append(contentsOf: standingsLines(
            tournamentName: tournament.name,
            standings: StandingsCalculator.calculate(
                teamNames: tournament.teamNames,
                results: results
            )
        ))
        return lines.joined(separator: "\n")
    }

    static func knockoutResultsText(
        tournament: TournamentPlan,
        rounds: [ScheduledRound],
        results: [KnockoutMatchResult]
    ) -> String {
        var lines = header(for: tournament)
        lines.append("Resultados de eliminación")
        lines.append("")

        let roundByMatchID = Dictionary(
            uniqueKeysWithValues: rounds.flatMap { round in
                round.matches.map { ($0.id, round.number) }
            }
        )

        for result in results {
            let roundNumber = roundByMatchID[result.matchID].map(String.init) ?? "?"
            let winner = result.winner.map { " · Gana \($0)" } ?? " · Desempate pendiente"
            lines.append(
                "Ronda \(roundNumber): \(result.homeTeam) \(result.homeScore)–\(result.awayScore) \(result.awayTeam)\(winner)"
            )
        }

        if let champion = KnockoutBracketResolver.champion(rounds: rounds, results: results) {
            lines.append("")
            lines.append("Campeón: \(champion)")
        }

        return lines.joined(separator: "\n")
    }

    static func standingsText(
        tournamentName: String,
        standings: [Standing]
    ) -> String {
        standingsLines(tournamentName: tournamentName, standings: standings)
            .joined(separator: "\n")
    }

    private static func header(for tournament: TournamentPlan) -> [String] {
        [
            "CUADERNO VIVO · TORNEO",
            tournament.name,
            tournament.startDate.formatted(date: .complete, time: .shortened),
            "Formato: \(tournament.format.title)",
            ""
        ]
    }

    private static func standingsLines(
        tournamentName: String,
        standings: [Standing]
    ) -> [String] {
        var lines = [
            "Clasificación · \(tournamentName)",
            ""
        ]

        for (index, standing) in standings.enumerated() {
            lines.append(
                "\(index + 1). \(standing.teamName) · \(standing.points) pts · PJ \(standing.played) · V \(standing.wins) · E \(standing.draws) · D \(standing.losses)"
            )
        }

        return lines
    }
}
