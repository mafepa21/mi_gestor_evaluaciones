import Foundation

enum ScheduleIssueSeverity: String, Hashable {
    case error
    case warning

    var title: String {
        switch self {
        case .error:
            "Conflicto"
        case .warning:
            "Aviso"
        }
    }
}

struct ScheduleValidationIssue: Identifiable, Hashable {
    let id: String
    let severity: ScheduleIssueSeverity
    let message: String
}

struct ScheduleValidationResult: Hashable {
    let issues: [ScheduleValidationIssue]

    var errors: [ScheduleValidationIssue] {
        issues.filter { $0.severity == .error }
    }

    var warnings: [ScheduleValidationIssue] {
        issues.filter { $0.severity == .warning }
    }

    var isValid: Bool {
        errors.isEmpty
    }
}

struct ScheduleValidator {
    static func validate(
        format: TournamentFormat = .roundRobin,
        teamNames: [String],
        venueCount: Int,
        rounds: [ScheduledRound]
    ) -> ScheduleValidationResult {
        var issues: [ScheduleValidationIssue] = []
        let normalizedTeams = teamNames.map(normalize)
        let nonEmptyTeams = normalizedTeams.filter { !$0.isEmpty }
        let knownTeams = Set(nonEmptyTeams)

        if nonEmptyTeams.count < 2 {
            issues.append(
                ScheduleValidationIssue(
                    id: "teams.minimum",
                    severity: .error,
                    message: "Necesitas al menos dos equipos con nombre."
                )
            )
        }

        if normalizedTeams.contains(where: \.isEmpty) {
            issues.append(
                ScheduleValidationIssue(
                    id: "teams.empty",
                    severity: .error,
                    message: "Todos los equipos deben tener un nombre."
                )
            )
        }

        let duplicateTeams = Dictionary(grouping: nonEmptyTeams, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys
            .sorted()

        if !duplicateTeams.isEmpty {
            issues.append(
                ScheduleValidationIssue(
                    id: "teams.duplicates",
                    severity: .error,
                    message: "Hay nombres de equipo repetidos: \(duplicateTeams.joined(separator: ", "))."
                )
            )
        }

        if venueCount < 1 {
            issues.append(
                ScheduleValidationIssue(
                    id: "venues.minimum",
                    severity: .error,
                    message: "Necesitas al menos una pista o zona disponible."
                )
            )
        }

        if rounds.isEmpty {
            issues.append(
                ScheduleValidationIssue(
                    id: "rounds.empty",
                    severity: .error,
                    message: "El calendario no contiene ninguna ronda."
                )
            )
        }

        var playedPairs = Set<String>()

        for round in rounds {
            var teamsInRound = Set<String>()
            var venuesInRound = Set<Int>()

            for match in round.matches {
                let homeTeam = normalize(match.homeTeam)
                let awayTeam = normalize(match.awayTeam)
                let pair = [homeTeam, awayTeam].sorted().joined(separator: "::")

                if homeTeam.isEmpty || awayTeam.isEmpty {
                    issues.append(
                        issue(
                            id: "round-\(round.number)-match-\(match.id)-teams-empty",
                            severity: .error,
                            message: "La ronda \(round.number) contiene un partido sin dos equipos."
                        )
                    )
                }

                if homeTeam == awayTeam {
                    issues.append(
                        issue(
                            id: "round-\(round.number)-match-\(match.id)-self-match",
                            severity: .error,
                            message: "La ronda \(round.number) contiene un autoenfrentamiento."
                        )
                    )
                }

                for team in [homeTeam, awayTeam] where !team.isEmpty {
                    let isKnockoutPlaceholder = isKnockoutRound(
                        format: format,
                        round: round
                    ) && isBracketPlaceholder(team)
                    if !knownTeams.contains(team) && !isKnockoutPlaceholder {
                        issues.append(
                            issue(
                                id: "round-\(round.number)-match-\(match.id)-unknown-\(team)",
                                severity: .error,
                                message: "El equipo \(team) aparece en la ronda \(round.number), pero no está configurado."
                            )
                        )
                    }

                    if !teamsInRound.insert(team).inserted {
                        issues.append(
                            issue(
                                id: "round-\(round.number)-team-\(team)",
                                severity: .error,
                                message: "El equipo \(team) juega más de un partido en la ronda \(round.number)."
                            )
                        )
                    }
                }

                if match.venueNumber < 1 || match.venueNumber > venueCount {
                    issues.append(
                        issue(
                            id: "round-\(round.number)-match-\(match.id)-venue-range",
                            severity: .error,
                            message: "El partido de la ronda \(round.number) usa una pista fuera del rango configurado."
                        )
                    )
                }

                if !venuesInRound.insert(match.venueNumber).inserted {
                    issues.append(
                        issue(
                            id: "round-\(round.number)-venue-\(match.venueNumber)",
                            severity: .error,
                            message: "La pista \(match.venueNumber) tiene más de un partido en la ronda \(round.number)."
                        )
                    )
                }

                if !isKnockoutRound(format: format, round: round),
                   !homeTeam.isEmpty,
                   !awayTeam.isEmpty,
                   homeTeam != awayTeam {
                    if !playedPairs.insert(pair).inserted {
                        issues.append(
                            issue(
                                id: "pair-\(pair)",
                                severity: .warning,
                                message: "El enfrentamiento \(homeTeam) vs \(awayTeam) se repite en el calendario."
                            )
                        )
                    }
                }
            }
        }

        return ScheduleValidationResult(issues: issues)
    }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func isBracketPlaceholder(_ name: String) -> Bool {
        name.hasPrefix("ganador p")
            || name.hasPrefix("clasificado ")
    }

    private static func isKnockoutRound(
        format: TournamentFormat,
        round: ScheduledRound
    ) -> Bool {
        format == .knockout || (
            format == .groupStageKnockout && round.stage == .knockout
        )
    }

    private static func issue(
        id: String,
        severity: ScheduleIssueSeverity,
        message: String
    ) -> ScheduleValidationIssue {
        ScheduleValidationIssue(id: id, severity: severity, message: message)
    }
}
