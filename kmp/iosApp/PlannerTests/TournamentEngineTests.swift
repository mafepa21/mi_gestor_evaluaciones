import XCTest
@testable import MiGestorKMPMac

final class TournamentTests: XCTestCase {
    func testNewTournamentGeneratesTeamsAndStoresConfiguration() {
        var tournament = TournamentPlan(
            name: "Liga de prueba",
            format: .roundRobin,
            teamCount: 6,
            venueCount: 3,
            matchDurationMinutes: 10,
            transitionMinutes: 2
        )

        XCTAssertEqual(tournament.name, "Liga de prueba")
        XCTAssertEqual(tournament.format, .roundRobin)
        XCTAssertEqual(tournament.teamCount, 6)
        XCTAssertEqual(tournament.teamNames, [
            "Equipo 1", "Equipo 2", "Equipo 3",
            "Equipo 4", "Equipo 5", "Equipo 6"
        ])
        XCTAssertEqual(tournament.venueCount, 3)
        XCTAssertEqual(tournament.roundDurationMinutes, 12)
        XCTAssertEqual(tournament.status, .draft)
    }

    func testEmptyTeamCountProducesNoTeams() {
        XCTAssertTrue(TournamentPlan.defaultTeamNames(count: 0).isEmpty)
        XCTAssertTrue(TournamentPlan.defaultTeamNames(count: -1).isEmpty)
    }

    func testFormatTitlesAreUserFacing() {
        XCTAssertEqual(TournamentFormat.roundRobin.title, "Liga")
        XCTAssertEqual(TournamentFormat.knockout.title, "Eliminatoria")
        XCTAssertEqual(TournamentFormat.groupStageKnockout.title, "Liguilla + eliminatorias")
        XCTAssertEqual(TournamentFormat.rotation.title, "Rotaciones")
    }

    func testGroupStageKnockoutGeneratesLeagueAndFinalBracket() throws {
        let teamNames = TournamentPlan.defaultTeamNames(count: 8)
        let rounds = try TournamentScheduleGenerator.generate(
            format: .groupStageKnockout,
            teamNames: teamNames,
            venueCount: 2
        )

        let groupRounds = rounds.filter { $0.stage == .groupStage }
        let knockoutRounds = rounds.filter { $0.stage == .knockout }
        let result = ScheduleValidator.validate(
            format: .groupStageKnockout,
            teamNames: teamNames,
            venueCount: 2,
            rounds: rounds
        )

        XCTAssertEqual(groupRounds.flatMap(\.matches).count, 12)
        XCTAssertEqual(knockoutRounds.flatMap(\.matches).count, 3)
        XCTAssertEqual(groupRounds.count, 6)
        XCTAssertEqual(knockoutRounds.count, 2)
        XCTAssertEqual(
            KnockoutBracketResolver.stages(in: rounds).map(\.title),
            ["Semifinales", "Final"]
        )
        XCTAssertTrue(result.isValid)
    }

    func testGroupStageReassignsVenuesAcrossGroups() throws {
        let teamNames = TournamentPlan.defaultTeamNames(count: 8)
        let rounds = try TournamentScheduleGenerator.generate(
            format: .groupStageKnockout,
            teamNames: teamNames,
            venueCount: 4
        )

        let groupRounds = rounds.filter { $0.stage == .groupStage }
        let result = ScheduleValidator.validate(
            format: .groupStageKnockout,
            teamNames: teamNames,
            venueCount: 4,
            rounds: rounds
        )

        XCTAssertTrue(groupRounds.allSatisfy { round in
            Set(round.matches.map(\.venueNumber)).count == round.matches.count
        })
        XCTAssertTrue(result.isValid)
    }

    func testGroupStageKeepsTeamWorkloadsBalanced() throws {
        let teamNames = TournamentPlan.defaultTeamNames(count: 8)
        let rounds = try TournamentScheduleGenerator.generate(
            format: .groupStageKnockout,
            teamNames: teamNames,
            venueCount: 2
        )
        var matchCounts = Dictionary(uniqueKeysWithValues: teamNames.map { ($0, 0) })

        for round in rounds where round.stage == .groupStage {
            for match in round.matches {
                matchCounts[match.homeTeam, default: 0] += 1
                matchCounts[match.awayTeam, default: 0] += 1
            }

            let workloadRange = (matchCounts.values.max() ?? 0) - (matchCounts.values.min() ?? 0)
            XCTAssertLessThanOrEqual(workloadRange, 1, "La ronda (round.number) desequilibra los partidos")
        }
    }

    func testGroupStageKnockoutUsesStandingsToResolveSemifinals() throws {
        let teamNames = ["A", "B", "C", "D", "E", "F", "G", "H"]
        var tournament = TournamentPlan(
            name: "Mundial de prueba",
            format: .groupStageKnockout,
            teamCount: teamNames.count,
            venueCount: 2
        )
        tournament.replaceTeamNames(teamNames)

        let rounds = try TournamentScheduleGenerator.generate(
            format: .groupStageKnockout,
            teamNames: teamNames,
            venueCount: 2
        )
        let groupMatches = rounds
            .filter { $0.stage == .groupStage }
            .flatMap(\.matches)
        let groupResults = groupMatches.map { match in
            let homeRank = teamNames.firstIndex(of: match.homeTeam)!
            let awayRank = teamNames.firstIndex(of: match.awayTeam)!
            return MatchResult(
                matchID: match.id,
                homeTeam: match.homeTeam,
                awayTeam: match.awayTeam,
                homeScore: homeRank < awayRank ? 1 : 0,
                awayScore: homeRank < awayRank ? 0 : 1
            )
        }

        tournament.persistSchedule(rounds)
        tournament.persistResults(groupResults)

        let firstKnockoutMatch = try XCTUnwrap(
            rounds.first(where: { $0.stage == .knockout })?.matches.first
        )
        let resolvedHome = KnockoutBracketResolver.resolvedParticipant(
            firstKnockoutMatch.homeTeam,
            rounds: rounds,
            results: [],
            groupResults: groupResults,
            teamNames: teamNames
        )
        let resolvedAway = KnockoutBracketResolver.resolvedParticipant(
            firstKnockoutMatch.awayTeam,
            rounds: rounds,
            results: [],
            groupResults: groupResults,
            teamNames: teamNames
        )

        XCTAssertEqual(resolvedHome, "A")
        XCTAssertEqual(resolvedAway, "F")

        let metrics = ScheduleAnalytics.metrics(tournament: tournament, rounds: rounds)
        XCTAssertEqual(metrics.totalMatches, 15)
        XCTAssertEqual(metrics.completedMatches, 12)
    }

    func testGroupStageOptionsPreferGroupsOfFourAndOfferAlternatives() {
        let defaultOption = GroupStageConfiguration.options(for: 8).first
        XCTAssertEqual(defaultOption?.groupCount, 2)
        XCTAssertEqual(defaultOption?.groupSizes, [4, 4])
        XCTAssertEqual(GroupStageConfiguration.defaultGroupCount(for: 8), 2)

        let sixTeamOptions = GroupStageConfiguration.options(for: 6)
        XCTAssertTrue(sixTeamOptions.contains { $0.groupSizes == [3, 3] })
        XCTAssertTrue(sixTeamOptions.contains { $0.groupSizes == [2, 2, 2] })
        XCTAssertEqual(GroupStageConfiguration.defaultGroupCount(for: 6), 2)
    }

    func testGroupStageKnockoutUsesConfiguredClassifiedTeamsPerGroup() throws {
        let teamNames = TournamentPlan.defaultTeamNames(count: 8)
        let rounds = try TournamentScheduleGenerator.generate(
            format: .groupStageKnockout,
            teamNames: teamNames,
            venueCount: 2,
            groupCount: 2,
            qualifiedTeamsPerGroup: 1
        )

        let knockoutMatches = rounds
            .filter { $0.stage == .knockout }
            .flatMap(\.matches)
        let result = ScheduleValidator.validate(
            format: .groupStageKnockout,
            teamNames: teamNames,
            venueCount: 2,
            rounds: rounds
        )

        XCTAssertEqual(knockoutMatches.count, 1)
        XCTAssertEqual(KnockoutBracketResolver.stages(in: rounds).map(\.title), ["Final"])
        XCTAssertTrue(knockoutMatches.allSatisfy {
            $0.homeTeam.contains("Grupo") && $0.awayTeam.contains("Grupo")
        })
        XCTAssertTrue(result.isValid)
    }

    func testGroupConfigurationIsStoredAndApplied() {
        var tournament = TournamentPlan(
            name: "Configuración de grupos",
            format: .groupStageKnockout,
            teamCount: 8,
            groupCount: 2,
            qualifiedTeamsPerGroup: 1
        )

        XCTAssertEqual(tournament.groupCount, 2)
        XCTAssertEqual(tournament.qualifiedTeamsPerGroup, 1)

        tournament.applyScheduleConfiguration(
            ScheduleConfiguration(
                format: .groupStageKnockout,
                groupCount: 4,
                qualifiedTeamsPerGroup: 2,
                venueCount: 2,
                matchDurationMinutes: 8,
                transitionMinutes: 2
            )
        )

        XCTAssertEqual(tournament.groupCount, 4)
        XCTAssertEqual(tournament.qualifiedTeamsPerGroup, 2)
    }

    func testRoundRobinGeneratesEveryPairOnceForEvenTeamCount() throws {
        let rounds = try RoundRobinScheduleGenerator.generate(
            teamNames: ["A", "B", "C", "D"],
            venueCount: 2
        )

        let pairs = rounds.flatMap(\.matches).map { match in
            Set([match.homeTeam, match.awayTeam])
        }

        XCTAssertEqual(rounds.count, 3)
        XCTAssertEqual(pairs.count, 6)
        XCTAssertEqual(Set(pairs).count, 6)
        XCTAssertTrue(rounds.allSatisfy { round in
            Set(round.matches.map(\.venueNumber)).count == round.matches.count
        })
    }

    func testRoundRobinAddsByeForOddTeamCount() throws {
        let rounds = try RoundRobinScheduleGenerator.generate(
            teamNames: ["A", "B", "C", "D", "E"],
            venueCount: 2
        )

        let matches = rounds.flatMap(\.matches)

        XCTAssertEqual(rounds.count, 5)
        XCTAssertEqual(matches.count, 10)
        XCTAssertFalse(matches.contains { $0.homeTeam == "__bye__" || $0.awayTeam == "__bye__" })
    }

    func testRoundRobinSplitsLogicalRoundsWhenVenuesAreLimited() throws {
        let teamNames = TournamentPlan.defaultTeamNames(count: 8)
        let rounds = try RoundRobinScheduleGenerator.generate(
            teamNames: teamNames,
            venueCount: 2
        )

        let result = ScheduleValidator.validate(
            teamNames: teamNames,
            venueCount: 2,
            rounds: rounds
        )

        XCTAssertEqual(rounds.count, 14)
        XCTAssertEqual(rounds.flatMap(\.matches).count, 28)
        XCTAssertTrue(rounds.allSatisfy { $0.matches.count <= 2 })
        XCTAssertTrue(result.isValid)
    }

    func testRoundRobinDoesNotRepeatBeforeEveryTeamHasPlayed() throws {
        let teamNames = TournamentPlan.defaultTeamNames(count: 8)
        let rounds = try RoundRobinScheduleGenerator.generate(
            teamNames: teamNames,
            venueCount: 2
        )
        var matchCounts = Dictionary(uniqueKeysWithValues: teamNames.map { ($0, 0) })

        for round in rounds {
            let teamsInRound = round.matches.flatMap { [$0.homeTeam, $0.awayTeam] }
            XCTAssertEqual(Set(teamsInRound).count, teamsInRound.count)

            for match in round.matches {
                matchCounts[match.homeTeam, default: 0] += 1
                matchCounts[match.awayTeam, default: 0] += 1
            }

            let workloadRange = (matchCounts.values.max() ?? 0) - (matchCounts.values.min() ?? 0)
            XCTAssertLessThanOrEqual(workloadRange, 1, "La ronda (round.number) repite antes de equilibrar equipos")
        }
    }

    func testKnockoutGeneratesByesAndNMinusOneMatches() throws {
        let teamNames = ["A", "B", "C", "D", "E"]
        let rounds = try TournamentScheduleGenerator.generate(
            format: .knockout,
            teamNames: teamNames,
            venueCount: 2
        )

        let result = ScheduleValidator.validate(
            format: .knockout,
            teamNames: teamNames,
            venueCount: 2,
            rounds: rounds
        )

        XCTAssertEqual(rounds.flatMap(\.matches).count, teamNames.count - 1)
        XCTAssertTrue(rounds.flatMap(\.matches).contains { $0.homeTeam.hasPrefix("Ganador") || $0.awayTeam.hasPrefix("Ganador") })
        XCTAssertTrue(result.isValid)
    }

    func testKnockoutStopsAfterFinalForDifferentTeamCounts() throws {
        for teamCount in 2...8 {
            let teamNames = (1...teamCount).map { "Equipo \($0)" }
            let rounds = try TournamentScheduleGenerator.generate(
                format: .knockout,
                teamNames: teamNames,
                venueCount: 2
            )

            XCTAssertEqual(
                rounds.flatMap(\.matches).count,
                teamCount - 1,
                "El cuadro de \(teamCount) equipos debe terminar en la final"
            )
            XCTAssertFalse(rounds.isEmpty)
        }
    }

    func testRotationGeneratesDeterministicRoundsForOddTeamCount() throws {
        let teamNames = ["A", "B", "C", "D", "E"]
        let rounds = try TournamentScheduleGenerator.generate(
            format: .rotation,
            teamNames: teamNames,
            venueCount: 2
        )

        let result = ScheduleValidator.validate(
            format: .rotation,
            teamNames: teamNames,
            venueCount: 2,
            rounds: rounds
        )

        XCTAssertEqual(rounds.flatMap(\.matches).count, 10)
        XCTAssertTrue(result.isValid)
    }

    func testKnockoutResolverPropagatesWinnerToNextMatch() throws {
        let rounds = try TournamentScheduleGenerator.generate(
            format: .knockout,
            teamNames: ["A", "B", "C", "D", "E"],
            venueCount: 2
        )
        let matches = KnockoutBracketResolver.allMatches(in: rounds)
        let firstMatch = matches[0]
        let nextMatch = matches[2]
        let firstResult = KnockoutMatchResult(
            matchID: firstMatch.id,
            homeTeam: firstMatch.homeTeam,
            awayTeam: firstMatch.awayTeam,
            homeScore: 2,
            awayScore: 0
        )

        XCTAssertEqual(
            KnockoutBracketResolver.resolvedParticipant(
                nextMatch.homeTeam,
                rounds: rounds,
                results: [firstResult]
            ),
            "A"
        )
    }

    func testKnockoutResolverGroupsMatchesIntoVisualStages() throws {
        let rounds = try TournamentScheduleGenerator.generate(
            format: .knockout,
            teamNames: TournamentPlan.defaultTeamNames(count: 8),
            venueCount: 2
        )

        let stages = KnockoutBracketResolver.stages(in: rounds)

        XCTAssertEqual(stages.map(\.title), ["Cuartos de final", "Semifinales", "Final"])
        XCTAssertEqual(stages.map { $0.matches.count }, [4, 2, 1])
        XCTAssertEqual(stages.flatMap(\.matches).count, 7)
    }

    func testKnockoutResolverExposesParentsAndNextStage() throws {
        let rounds = try TournamentScheduleGenerator.generate(
            format: .knockout,
            teamNames: TournamentPlan.defaultTeamNames(count: 8),
            venueCount: 2
        )
        let stages = KnockoutBracketResolver.stages(in: rounds)
        let semifinal = try XCTUnwrap(stages[1].matches.first)

        XCTAssertEqual(
            Set(KnockoutBracketResolver.parentMatchIDs(for: semifinal, in: rounds)),
            Set(stages[0].matches.prefix(2).map(\.id))
        )
        XCTAssertEqual(
            KnockoutBracketResolver.nextStageIndex(rounds: rounds, results: []),
            0
        )

        let firstRoundResults = stages[0].matches.map {
            KnockoutMatchResult(
                matchID: $0.id,
                homeTeam: $0.homeTeam,
                awayTeam: $0.awayTeam,
                homeScore: 1,
                awayScore: 0
            )
        }

        XCTAssertEqual(
            KnockoutBracketResolver.nextStageIndex(
                rounds: rounds,
                results: firstRoundResults
            ),
            1
        )
    }

    func testTournamentPersistsKnockoutResults() throws {
        var tournament = TournamentPlan(name: "Eliminatoria", format: .knockout, teamCount: 4)
        let rounds = try TournamentScheduleGenerator.generate(
            format: .knockout,
            teamNames: tournament.teamNames,
            venueCount: tournament.venueCount
        )
        let match = try XCTUnwrap(KnockoutBracketResolver.allMatches(in: rounds).first)
        let result = KnockoutMatchResult(
            matchID: match.id,
            homeTeam: match.homeTeam,
            awayTeam: match.awayTeam,
            homeScore: 1,
            awayScore: 0
        )

        tournament.persistKnockoutResults([result])

        XCTAssertEqual(tournament.savedKnockoutResults, [result])
        XCTAssertEqual(tournament.savedKnockoutResults.first?.winner, match.homeTeam)
    }

    func testStandingsAwardThreePointsForWinAndOneForDraw() {
        let results = [
            MatchResult(homeTeam: "A", awayTeam: "B", homeScore: 3, awayScore: 1),
            MatchResult(homeTeam: "B", awayTeam: "C", homeScore: 2, awayScore: 2)
        ]

        let standings = StandingsCalculator.calculate(
            teamNames: ["A", "B", "C"],
            results: results
        )

        XCTAssertEqual(standings[0].teamName, "A")
        XCTAssertEqual(standings[0].points, 3)
        XCTAssertEqual(standings[1].teamName, "B")
        XCTAssertEqual(standings[1].points, 1)
        XCTAssertEqual(standings[2].teamName, "C")
        XCTAssertEqual(standings[2].points, 1)
        XCTAssertEqual(standings[2].draws, 1)
    }

    func testTournamentPersistsScheduleAndResults() throws {
        var tournament = TournamentPlan(
            name: "Torneo persistente",
            format: .roundRobin,
            teamCount: 4,
            venueCount: 2
        )
        let rounds = try RoundRobinScheduleGenerator.generate(
            teamNames: tournament.teamNames,
            venueCount: tournament.venueCount
        )
        let results = [
            MatchResult(homeTeam: "Equipo 1", awayTeam: "Equipo 4", homeScore: 2, awayScore: 1)
        ]

        tournament.persistSchedule(rounds)
        tournament.persistResults(results)

        XCTAssertEqual(tournament.savedSchedule, rounds)
        XCTAssertEqual(tournament.savedResults, results)
        XCTAssertEqual(tournament.status, .scheduled)
    }

    func testScheduleValidatorAcceptsGeneratedCalendar() throws {
        let teamNames = ["A", "B", "C", "D"]
        let rounds = try RoundRobinScheduleGenerator.generate(
            teamNames: teamNames,
            venueCount: 2
        )

        let result = ScheduleValidator.validate(
            teamNames: teamNames,
            venueCount: 2,
            rounds: rounds
        )

        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testScheduleValidatorRejectsVenueConflict() {
        let teamNames = ["A", "B", "C", "D"]
        let rounds = [
            ScheduledRound(
                number: 1,
                matches: [
                    ScheduledMatch(homeTeam: "A", awayTeam: "B", venueNumber: 1),
                    ScheduledMatch(homeTeam: "C", awayTeam: "D", venueNumber: 1)
                ]
            )
        ]

        let result = ScheduleValidator.validate(
            teamNames: teamNames,
            venueCount: 1,
            rounds: rounds
        )

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { $0.message.contains("pista 1") })
    }

    func testScheduleAnalyticsBuildsSlotsAndMetrics() throws {
        let startDate = Date(timeIntervalSince1970: 1_000_000)
        var tournament = TournamentPlan(
            name: "Analítica",
            startDate: startDate,
            teamCount: 4,
            venueCount: 2,
            matchDurationMinutes: 8,
            transitionMinutes: 2
        )
        let rounds = try RoundRobinScheduleGenerator.generate(
            teamNames: tournament.teamNames,
            venueCount: tournament.venueCount
        )

        let slots = ScheduleAnalytics.slots(tournament: tournament, rounds: rounds)
        let metrics = ScheduleAnalytics.metrics(tournament: tournament, rounds: rounds)

        XCTAssertEqual(slots.count, 6)
        XCTAssertEqual(slots.first?.startDate, startDate)
        XCTAssertEqual(slots.first?.endDate, startDate.addingTimeInterval(8 * 60))
        XCTAssertEqual(metrics.roundCount, 3)
        XCTAssertEqual(metrics.totalMatches, 6)
        XCTAssertEqual(metrics.programmedOccupancyPercentage, 100)
        XCTAssertEqual(metrics.shortestRestMinutes, 2)
        XCTAssertEqual(metrics.averageRestMinutes, 2)
        XCTAssertEqual(metrics.projectedEndDate, startDate.addingTimeInterval(28 * 60))
    }

    func testScheduleAnalyticsTracksCompletedMatchByID() throws {
        var tournament = TournamentPlan(
            name: "Progreso",
            teamCount: 4,
            venueCount: 2
        )
        let rounds = try RoundRobinScheduleGenerator.generate(
            teamNames: tournament.teamNames,
            venueCount: tournament.venueCount
        )
        let firstMatch = try XCTUnwrap(rounds.first?.matches.first)

        tournament.persistSchedule(rounds)
        tournament.persistResults([
            MatchResult(
                matchID: firstMatch.id,
                homeTeam: firstMatch.homeTeam,
                awayTeam: firstMatch.awayTeam,
                homeScore: 2,
                awayScore: 1
            )
        ])

        let metrics = ScheduleAnalytics.metrics(tournament: tournament, rounds: rounds)
        let nextSlot = ScheduleAnalytics.nextSlot(tournament: tournament, rounds: rounds)
        let firstSlot = try XCTUnwrap(ScheduleAnalytics.slots(tournament: tournament, rounds: rounds).first)

        XCTAssertEqual(metrics.completedMatches, 1)
        XCTAssertEqual(metrics.remainingMatches, 5)
        XCTAssertNotEqual(nextSlot?.id, firstMatch.id)
        XCTAssertEqual(
            ScheduleAnalytics.result(for: firstSlot, tournament: tournament),
            ScheduleMatchScore(homeScore: 2, awayScore: 1)
        )
    }

    func testScheduleAnalyticsResolvesLegacyResultWithoutMatchID() throws {
        var tournament = TournamentPlan(name: "Resultado legado", teamCount: 4, venueCount: 2)
        let rounds = try RoundRobinScheduleGenerator.generate(
            teamNames: tournament.teamNames,
            venueCount: tournament.venueCount
        )
        let slot = try XCTUnwrap(ScheduleAnalytics.slots(tournament: tournament, rounds: rounds).first)

        tournament.persistResults([
            MatchResult(
                homeTeam: slot.match.homeTeam,
                awayTeam: slot.match.awayTeam,
                homeScore: 0,
                awayScore: 0
            )
        ])

        XCTAssertEqual(
            ScheduleAnalytics.result(for: slot, tournament: tournament),
            ScheduleMatchScore(homeScore: 0, awayScore: 0)
        )
    }

    func testScheduleAnalyticsResolvesKnockoutResultForSlot() throws {
        var tournament = TournamentPlan(name: "Eliminatoria", format: .knockout, teamCount: 4, venueCount: 2)
        let rounds = try TournamentScheduleGenerator.generate(
            format: .knockout,
            teamNames: tournament.teamNames,
            venueCount: tournament.venueCount
        )
        let slot = try XCTUnwrap(ScheduleAnalytics.slots(tournament: tournament, rounds: rounds).first)

        tournament.persistKnockoutResults([
            KnockoutMatchResult(
                matchID: slot.id,
                homeTeam: slot.match.homeTeam,
                awayTeam: slot.match.awayTeam,
                homeScore: 3,
                awayScore: 2
            )
        ])

        XCTAssertEqual(
            ScheduleAnalytics.result(for: slot, tournament: tournament),
            ScheduleMatchScore(homeScore: 3, awayScore: 2)
        )
    }

    func testScheduleAnalyticsPropagatesKnockoutWinnersToNextRound() throws {
        var tournament = TournamentPlan(
            name: "Ganadores",
            format: .knockout,
            teamCount: 4,
            venueCount: 2
        )
        let rounds = try TournamentScheduleGenerator.generate(
            format: .knockout,
            teamNames: tournament.teamNames,
            venueCount: tournament.venueCount
        )
        let matches = KnockoutBracketResolver.allMatches(in: rounds)
        let firstMatch = try XCTUnwrap(matches.first)
        let secondMatch = try XCTUnwrap(matches.dropFirst().first)
        let nextMatch = try XCTUnwrap(matches.dropFirst(2).first)

        tournament.persistKnockoutResults([
            KnockoutMatchResult(
                matchID: firstMatch.id,
                homeTeam: firstMatch.homeTeam,
                awayTeam: firstMatch.awayTeam,
                homeScore: 3,
                awayScore: 1
            ),
            KnockoutMatchResult(
                matchID: secondMatch.id,
                homeTeam: secondMatch.homeTeam,
                awayTeam: secondMatch.awayTeam,
                homeScore: 0,
                awayScore: 2
            )
        ])

        let nextSlot = try XCTUnwrap(
            ScheduleAnalytics.slots(tournament: tournament, rounds: rounds)
                .first { $0.id == nextMatch.id }
        )

        XCTAssertEqual(nextSlot.match.homeTeam, firstMatch.homeTeam)
        XCTAssertEqual(nextSlot.match.awayTeam, secondMatch.awayTeam)
        XCTAssertFalse(nextSlot.teamNames.contains { $0.hasPrefix("Ganador P") })
    }

    func testTimelineLayoutUsesRealDurationAtEveryZoom() throws {
        var tournament = TournamentPlan(
            name: "Gantt denso",
            startDate: Date(timeIntervalSince1970: 1_000_000),
            teamCount: 4,
            venueCount: 2,
            matchDurationMinutes: 8,
            transitionMinutes: 2
        )
        let rounds = try RoundRobinScheduleGenerator.generate(
            teamNames: tournament.teamNames,
            venueCount: tournament.venueCount
        )
        let slots = ScheduleAnalytics.slots(tournament: tournament, rounds: rounds)
        let zooms: [(hourWidth: Double, markerMinutes: Int, matchWidth: Double, transitionWidth: Double)] = [
            (630, 30, 84, 21),
            (840, 15, 112, 28),
            (1_344, 5, 179.2, 44.8)
        ]

        for zoom in zooms {
            let layout = ScheduleTimelineLayout.make(
                slots: slots,
                startDate: tournament.startDate,
                zoomHourWidth: zoom.hourWidth,
                markerMinutes: zoom.markerMinutes
            )
            let venueSlots = slots.filter { $0.venueNumber == 1 }.sorted { $0.startDate < $1.startDate }
            let frames = venueSlots.compactMap(layout.block(for:))
            let firstFrame = try XCTUnwrap(frames.first)

            XCTAssertEqual(firstFrame.width, zoom.matchWidth, accuracy: 0.01)
            let firstX = firstFrame.x
            let secondX = try XCTUnwrap(frames.dropFirst().first).x
            XCTAssertEqual(
                secondX - firstX,
                zoom.matchWidth + zoom.transitionWidth,
                accuracy: 0.01
            )
        }
    }

    func testTimelineLayoutDoesNotForceAFalseMinimumWidthForShortMatches() throws {
        var tournament = TournamentPlan(
            name: "Gantt compacto",
            startDate: Date(timeIntervalSince1970: 1_000_000),
            teamCount: 4,
            venueCount: 2,
            matchDurationMinutes: 2,
            transitionMinutes: 1
        )
        let rounds = try RoundRobinScheduleGenerator.generate(
            teamNames: tournament.teamNames,
            venueCount: tournament.venueCount
        )
        let slots = ScheduleAnalytics.slots(tournament: tournament, rounds: rounds)
        let layout = ScheduleTimelineLayout.make(
            slots: slots,
            startDate: tournament.startDate,
            zoomHourWidth: 480,
            markerMinutes: 15
        )

        let firstSlot = try XCTUnwrap(slots.first)
        let first = try XCTUnwrap(layout.block(for: firstSlot))
        XCTAssertEqual(first.width, 16, accuracy: 0.01)
        XCTAssertLessThan(first.width, 112)

        for venue in 1...tournament.venueCount {
            let venueSlots = slots.filter { $0.venueNumber == venue }.sorted { $0.startDate < $1.startDate }
            let frames = venueSlots.compactMap(layout.block(for:))

            for pair in zip(frames, frames.dropFirst()) {
                XCTAssertGreaterThanOrEqual(
                    pair.1.x,
                    pair.0.x + pair.0.width + ScheduleTimelineLayout.minimumGap
                )
            }
        }
    }

    func testTimelineLayoutCanReserveReadableWidthForMapCards() throws {
        var tournament = TournamentPlan(
            name: "Mapa legible",
            startDate: Date(timeIntervalSince1970: 1_000_000),
            teamCount: 4,
            venueCount: 2,
            matchDurationMinutes: 8,
            transitionMinutes: 2
        )
        let rounds = try RoundRobinScheduleGenerator.generate(
            teamNames: tournament.teamNames,
            venueCount: tournament.venueCount
        )
        let slots = ScheduleAnalytics.slots(tournament: tournament, rounds: rounds)
        let layout = ScheduleTimelineLayout.make(
            slots: slots,
            startDate: tournament.startDate,
            zoomHourWidth: 360,
            markerMinutes: 15,
            readableColumnWidth: 148
        )

        let venueSlots = slots.filter { $0.venueNumber == 1 }.sorted { $0.startDate < $1.startDate }
        let frames = venueSlots.compactMap(layout.block(for:))
        let firstFrame = try XCTUnwrap(frames.first)

        XCTAssertEqual(firstFrame.width, 148, accuracy: 0.01)
        XCTAssertEqual(
            try XCTUnwrap(frames.dropFirst().first).x - firstFrame.x,
            152,
            accuracy: 0.01
        )
        XCTAssertEqual(layout.markerSpacing, 152, accuracy: 0.01)

        for pair in zip(frames, frames.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                pair.1.x,
                pair.0.x + pair.0.width + ScheduleTimelineLayout.minimumGap
            )
        }
    }

    func testApplyingScheduleConfigurationClearsScheduleAndResults() throws {
        var tournament = TournamentPlan(name: "Recalcular", teamCount: 4)
        let rounds = try RoundRobinScheduleGenerator.generate(
            teamNames: tournament.teamNames,
            venueCount: tournament.venueCount
        )
        tournament.persistSchedule(rounds)
        tournament.persistResults([
            MatchResult(homeTeam: "Equipo 1", awayTeam: "Equipo 4", homeScore: 1, awayScore: 0)
        ])

        tournament.applyScheduleConfiguration(
            ScheduleConfiguration(
                format: .rotation,
                venueCount: 3,
                matchDurationMinutes: 12,
                transitionMinutes: 3
            )
        )

        XCTAssertEqual(tournament.format, .rotation)
        XCTAssertEqual(tournament.venueCount, 3)
        XCTAssertEqual(tournament.roundDurationMinutes, 15)
        XCTAssertTrue(tournament.savedSchedule.isEmpty)
        XCTAssertTrue(tournament.savedResults.isEmpty)
        XCTAssertEqual(tournament.status, .draft)
    }

    func testReplacingTeamsResetsGeneratedData() throws {
        var tournament = TournamentPlan(name: "Torneo editable", teamCount: 4)
        let rounds = try RoundRobinScheduleGenerator.generate(
            teamNames: tournament.teamNames,
            venueCount: tournament.venueCount
        )
        tournament.persistSchedule(rounds)
        tournament.persistResults([
            MatchResult(homeTeam: "Equipo 1", awayTeam: "Equipo 4", homeScore: 1, awayScore: 0)
        ])

        tournament.replaceTeamNames(["Rojo", "Azul", "Verde", "Amarillo"])

        XCTAssertEqual(tournament.teamNames, ["Rojo", "Azul", "Verde", "Amarillo"])
        XCTAssertTrue(tournament.savedSchedule.isEmpty)
        XCTAssertTrue(tournament.savedResults.isEmpty)
        XCTAssertEqual(tournament.status, .draft)
    }

    func testScheduleExportContainsTournamentRoundsAndVenues() throws {
        var tournament = TournamentPlan(name: "Liga exportable", teamCount: 4, venueCount: 2)
        let rounds = try RoundRobinScheduleGenerator.generate(
            teamNames: tournament.teamNames,
            venueCount: tournament.venueCount
        )

        let export = TournamentExportFormatter.scheduleText(
            tournament: tournament,
            rounds: rounds
        )

        XCTAssertTrue(export.contains("Liga exportable"))
        XCTAssertTrue(export.contains("Ronda 1"))
        XCTAssertTrue(export.contains("Pista 1"))
        XCTAssertTrue(export.contains("Equipo 1"))
    }

    func testKnockoutExportContainsChampion() throws {
        var tournament = TournamentPlan(name: "Copa exportable", format: .knockout, teamCount: 2)
        let rounds = try TournamentScheduleGenerator.generate(
            format: .knockout,
            teamNames: tournament.teamNames,
            venueCount: tournament.venueCount
        )
        let match = try XCTUnwrap(KnockoutBracketResolver.allMatches(in: rounds).first)
        let results = [
            KnockoutMatchResult(
                matchID: match.id,
                homeTeam: match.homeTeam,
                awayTeam: match.awayTeam,
                homeScore: 3,
                awayScore: 1
            )
        ]

        let export = TournamentExportFormatter.knockoutResultsText(
            tournament: tournament,
            rounds: rounds,
            results: results
        )

        XCTAssertTrue(export.contains("Campeón: \(match.homeTeam)"))
    }
}

// MARK: - Serialización JSON para SQLDelight (añadido en Cuaderno Vivo)

final class TournamentPlanJSONTests: XCTestCase {
    func testRoundTripConservaEquiposCalendarioYResultados() throws {
        var plan = TournamentPlan(
            name: "Copa SdA",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            format: .groupStageKnockout,
            teams: (1...8).map { TournamentPlanTeam(id: "g\($0)", name: "Eq \($0)", studentIDs: ["a\($0)", "b\($0)"]) },
            venueCount: 2
        )
        let rounds = try TournamentScheduleGenerator.generate(
            format: plan.format,
            teamNames: plan.teamNames,
            venueCount: plan.venueCount,
            groupCount: plan.groupCount,
            qualifiedTeamsPerGroup: plan.qualifiedTeamsPerGroup
        )
        plan.persistSchedule(rounds)
        let first = try XCTUnwrap(rounds.first?.matches.first)
        plan.persistResults([
            MatchResult(matchID: first.id, homeTeam: first.homeTeam, awayTeam: first.awayTeam, homeScore: 2, awayScore: 1)
        ])
        plan.persistKnockoutResults([
            KnockoutMatchResult(matchID: first.id, homeTeam: "A", awayTeam: "B", homeScore: 1, awayScore: 0)
        ])

        let restored = try TournamentPlan(columns: plan.columns())

        XCTAssertEqual(restored, plan)
        XCTAssertEqual(restored.teams.first?.studentIDs, ["a1", "b1"])
    }

    func testColumnasVaciasDanPlanSinDatos() throws {
        let plan = try TournamentPlan(columns: TournamentPlanColumns(
            id: UUID().uuidString, name: "Vacío",
            configJSON: "", teamSnapshotJSON: "", scheduleJSON: "", resultsJSON: "", knockoutResultsJSON: ""
        ))
        XCTAssertTrue(plan.teams.isEmpty)
        XCTAssertTrue(plan.savedSchedule.isEmpty)
        XCTAssertEqual(plan.status, .draft)
    }

    func testJSONCorruptoLanzaEnVezDeSilenciarlo() {
        let columns = TournamentPlanColumns(
            id: UUID().uuidString, name: "Roto",
            configJSON: "", teamSnapshotJSON: "", scheduleJSON: "{no es json", resultsJSON: "", knockoutResultsJSON: ""
        )
        XCTAssertThrowsError(try TournamentPlan(columns: columns))
    }
}
