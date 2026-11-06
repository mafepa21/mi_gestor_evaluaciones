import XCTest
@testable import MiGestorKMPMac

/// Modalidad «Liguilla + puestos»: cálculo de tiempos, sugerencias, liguilla, cuadro y tabla final.
final class PlacementTournamentTests: XCTestCase {
    private struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state ^ (state >> 29)
        }
    }

    private func input(
        teams: Int, match: Int = 8, total: Int, venues: Int = 8, rounds: Int? = nil
    ) -> PlacementPlanInput {
        PlacementPlanInput(
            teamCount: teams, matchMinutes: match, transitionMinutes: 2,
            totalMinutes: total, venueCount: venues, placementRounds: rounds
        )
    }

    private func plan(teams: Int, total: Int, venues: Int = 8, rounds: Int? = nil) throws -> TournamentPlan {
        var plan = TournamentPlan(
            name: "Prueba", format: .leaguePlacement,
            teams: (1...teams).map { TournamentPlanTeam(name: "Pareja \($0)") },
            venueCount: venues, matchDurationMinutes: 8, transitionMinutes: 2
        )
        plan.totalTimeMinutes = total
        plan.placementRounds = rounds
        plan.persistSchedule(try plan.generatedRounds())
        return plan
    }

    /// Juega la liguilla y el cuadro con resultados al azar usando el flujo real.
    private func play(_ plan: inout TournamentPlan, using generator: inout Generator) {
        for slot in plan.slots where slot.stage == .groupStage {
            plan.setScore(for: slot, home: Int.random(in: 0...21, using: &generator), away: Int.random(in: 0...21, using: &generator))
        }
        while let slot = plan.slots.first(where: { $0.stage == .knockout && !plan.hasResult($0) }) {
            let homeWins = Bool.random(using: &generator)
            plan.setScore(for: slot, home: homeWins ? 15 : 10, away: homeWins ? 10 : 15)
        }
    }

    // MARK: Cálculo

    func testVeinticuatroParejasEnUnaHoraNoCabeYSugiereCambios() throws {
        let value = input(teams: 24, total: 60)
        let calculation = try XCTUnwrap(PlacementPlanner.calculate(value))
        XCTAssertFalse(calculation.fits)
        XCTAssertEqual(calculation.placementMatches, 52)
        XCTAssertEqual(calculation.minimumLeagueRounds, 3)
        XCTAssertGreaterThan(calculation.neededMinutes, 60)
        let titles = PlacementPlanner.suggestions(for: value).map(\.title)
        XCTAssertTrue(titles.contains { $0.hasPrefix("Ampliar a") })
        XCTAssertTrue(titles.contains("Cuadro de 2 rondas"), "\(titles)")
    }

    func testConTiempoDeSobraLaLiguillaOcupaLoQueQueda() throws {
        let calculation = try XCTUnwrap(PlacementPlanner.calculate(input(teams: 24, total: 140)))
        XCTAssertTrue(calculation.fits)
        XCTAssertEqual(calculation.leagueRounds * 10 + calculation.placementBatches * 10 - 2, calculation.neededMinutes)
        XCTAssertLessThanOrEqual(calculation.neededMinutes, 140)
        XCTAssertEqual(calculation.leagueMatches, calculation.leagueRounds * 8)
    }

    func testTodaSugerenciaHaceQueQuepa() {
        for teams in 4...40 {
            for match in [4, 6, 8, 12] {
                for total in [20, 45, 60, 90, 120] {
                    for venues in [2, 4, 8] {
                        let value = input(teams: teams, match: match, total: total, venues: venues)
                        guard let calculation = PlacementPlanner.calculate(value) else {
                            XCTFail("Sin cálculo: \(value)"); continue
                        }
                        let suggestions = PlacementPlanner.suggestions(for: value)
                        if calculation.fits {
                            XCTAssertTrue(suggestions.isEmpty)
                            XCTAssertLessThanOrEqual(calculation.neededMinutes, total, "\(value)")
                        } else {
                            XCTAssertFalse(suggestions.isEmpty, "\(value)")
                            for suggestion in suggestions {
                                var changed = value
                                changed.apply(suggestion.change)
                                XCTAssertEqual(PlacementPlanner.calculate(changed)?.fits, true, "\(value) \(suggestion.title)")
                            }
                        }
                    }
                }
            }
        }
    }

    func testMenosDeCuatroParejasNoSeCalcula() {
        XCTAssertNil(PlacementPlanner.calculate(input(teams: 3, total: 60)))
    }

    func testNoCabeNoCreaCalendario() {
        var plan = TournamentPlan(
            name: "Prueba", format: .leaguePlacement,
            teams: (1...24).map { TournamentPlanTeam(name: "Pareja \($0)") },
            venueCount: 8, matchDurationMinutes: 8, transitionMinutes: 2
        )
        plan.totalTimeMinutes = 60
        XCTAssertThrowsError(try plan.generatedRounds())
    }

    // MARK: Liguilla

    func testLiguillaRepartoJustoConCualquierNumeroDeParejas() {
        for teams in 4...40 {
            for venues in [2, 4, 8, 12] {
                for roundCount in [2, 3, 6, 10] {
                    let rounds = PlacementLeagueScheduler.rounds(teamCount: teams, venueCount: venues, roundCount: roundCount)
                    XCTAssertEqual(rounds.count, roundCount)
                    var played = Array(repeating: 0, count: teams)
                    var rested = Array(repeating: 0, count: teams)
                    for round in rounds {
                        let everyone = round.pairs.flatMap { $0 } + round.resting
                        XCTAssertEqual(everyone.sorted(), Array(0..<teams), "Una pareja dos veces en la misma tanda")
                        XCTAssertEqual(round.pairs.count, min(venues, teams / 2))
                        round.pairs.flatMap { $0 }.forEach { played[$0] += 1 }
                        round.resting.forEach { rested[$0] += 1 }
                    }
                    XCTAssertLessThanOrEqual(played.max()! - played.min()!, 1, "partidos \(teams)/\(venues)/\(roundCount)")
                    XCTAssertLessThanOrEqual(rested.max()! - rested.min()!, 1, "descansos \(teams)/\(venues)/\(roundCount)")
                }
            }
        }
    }

    func testDiecisieteParejasNadieRepiteDescansoNiRival() {
        let rounds = PlacementLeagueScheduler.rounds(teamCount: 17, venueCount: 8, roundCount: 6)
        let resting = rounds.flatMap(\.resting)
        XCTAssertEqual(resting.count, 6)
        XCTAssertEqual(Set(resting).count, 6)
        let meetings = rounds.flatMap(\.pairs).map { Set($0) }
        XCTAssertEqual(Set(meetings).count, meetings.count)
    }

    // MARK: Cuadro

    func testCuadroDeVeinticuatroSeParteComoSePidio() {
        let bracket = PlacementBracket(teamCount: 24, maxRounds: nil)
        XCTAssertEqual(bracket.matches.count, 52)
        XCTAssertEqual(bracket.roundCount, 5)
        func ranges(_ round: Int) -> [ClosedRange<Int>] {
            Array(Set(bracket.matches.filter { $0.round == round }.map(\.positions)))
                .sorted { $0.lowerBound < $1.lowerBound }
        }
        XCTAssertEqual(ranges(1), [1...24])
        XCTAssertEqual(ranges(2), [1...12, 13...24])
        XCTAssertEqual(ranges(3), [1...6, 7...12, 13...18, 19...24])
        XCTAssertEqual(ranges(4).first, 1...3)
        let first = bracket.matches.filter { $0.round == 1 }
        XCTAssertEqual(first.first?.home, .seed(1))
        XCTAssertEqual(first.first?.away, .seed(24))
        XCTAssertEqual(first.last?.home, .seed(12))
        XCTAssertEqual(first.last?.away, .seed(13))
    }

    func testNingunaParejaJuegaDosVecesEnLaMismaTanda() throws {
        for teams in [8, 17, 24, 25, 32] {
            var plan = try plan(teams: teams, total: 300)
            var generator = Generator(state: UInt64(teams))
            play(&plan, using: &generator)
            for round in plan.savedSchedule {
                let names = plan.slots.filter { $0.roundNumber == round.number }.flatMap(\.teamNames)
                XCTAssertEqual(names.count, Set(names).count, "Tanda \(round.number) con \(teams) parejas")
            }
        }
    }

    func testCadaPuestoSaleUnaSolaVez() throws {
        for teams in [4, 5, 6, 7, 8, 9, 11, 12, 13, 15, 16, 17, 18, 19, 21, 23, 24, 25, 27, 32, 33, 40] {
            for seed in 1...2 {
                var plan = try plan(teams: teams, total: 400)
                var generator = Generator(state: UInt64(teams * 1000 + seed))
                play(&plan, using: &generator)
                let table = try XCTUnwrap(plan.placementFinalTable, "\(teams) parejas")
                XCTAssertEqual(table.map(\.position), Array(1...teams))
                XCTAssertEqual(Set(table.map(\.teamName)).count, teams)
                XCTAssertTrue(table.allSatisfy { plan.teamNames.contains($0.teamName) })
            }
        }
    }

    func testCuadroCortoDecideLaLiguillaDentroDelGrupo() throws {
        var plan = try plan(teams: 24, total: 60, rounds: 2)
        var generator = Generator(state: 7)
        play(&plan, using: &generator)
        let table = try XCTUnwrap(plan.placementFinalTable)
        XCTAssertEqual(table.map(\.position), Array(1...24))
        for start in stride(from: 0, to: 24, by: 6) {
            let group = table[start..<(start + 6)].map(\.leaguePosition)
            XCTAssertEqual(group, group.sorted())
        }
    }

    func testDiecisieteParejasTodasEntranYJuegan() throws {
        for seed in 1...20 {
            var plan = try plan(teams: 17, total: 180)
            var generator = Generator(state: UInt64(seed))
            play(&plan, using: &generator)
            var counts = Dictionary(uniqueKeysWithValues: plan.teamNames.map { ($0, 0) })
            for slot in plan.slots where slot.stage == .knockout {
                slot.teamNames.forEach { counts[$0, default: 0] += 1 }
            }
            XCTAssertEqual(counts.count, 17)
            XCTAssertGreaterThanOrEqual(counts.values.min()!, 3)
            XCTAssertLessThanOrEqual(counts.values.max()!, 5)
        }
    }

    // MARK: Flujo

    func testElCuadroEsperaALaLiguilla() throws {
        var plan = try plan(teams: 8, total: 90)
        let knockout = try XCTUnwrap(plan.slots.first { $0.stage == .knockout })
        XCTAssertFalse(plan.canScore(knockout))
        XCTAssertTrue(plan.displayTeams(for: knockout).home.hasPrefix("Puesto "))
        plan.setScore(for: knockout, home: 2, away: 1)
        XCTAssertTrue(plan.savedKnockoutResults.isEmpty)
    }

    func testPasarAlCuadroConPartidosSinJugar() throws {
        var plan = try plan(teams: 8, total: 120)
        let league = plan.slots.filter { $0.stage == .groupStage }
        plan.closeLeagueEarly()
        XCTAssertNil(plan.leagueClosedEarly, "Sin ningún resultado no se puede cerrar")
        plan.setScore(for: league[0], home: 15, away: 3)
        plan.closeLeagueEarly()
        XCTAssertEqual(plan.leagueClosedEarly, true)
        XCTAssertFalse(plan.canScore(league[1]), "La liguilla cerrada no admite resultados")
        let knockoutCount = plan.savedSchedule.filter { $0.stage == .knockout }.flatMap(\.matches).count
        XCTAssertEqual(plan.totalMatchCount, knockoutCount + 1, "Los partidos descartados no cuentan en el progreso")
        let knockout = try XCTUnwrap(plan.slots.first { $0.stage == .knockout })
        XCTAssertTrue(plan.canScore(knockout))
        plan.reopenLeague()
        XCTAssertNil(plan.leagueClosedEarly)
    }

    func testCorregirUnResultadoBorraLoQueDependiaDeEl() throws {
        var plan = try plan(teams: 8, total: 120)
        for slot in plan.slots where slot.stage == .groupStage {
            plan.setScore(for: slot, home: 15, away: 10)
        }
        let opening = plan.slots.filter { $0.stage == .knockout && plan.canScore($0) }
        for slot in opening {
            plan.setScore(for: slot, home: 15, away: 10)
        }
        let first = try XCTUnwrap(opening.first)
        let dependent = try XCTUnwrap(plan.slots.first { slot in
            slot.stage == .knockout && slot.teamNames.contains(first.match.homeTeam) && slot.id != first.id
        })
        XCTAssertTrue(plan.canScore(dependent))
        plan.setScore(for: dependent, home: 15, away: 10)
        XCTAssertTrue(plan.savedKnockoutResults.contains { $0.matchID == dependent.id })

        // Cambia el ganador del primer partido: lo que dependía de él ya no vale.
        let current = try XCTUnwrap(plan.slots.first { $0.id == first.id })
        plan.setScore(for: current, home: 10, away: 15)
        XCTAssertFalse(plan.savedKnockoutResults.contains { $0.matchID == dependent.id })
        let updated = try XCTUnwrap(plan.slots.first { $0.id == dependent.id })
        XCTAssertTrue(updated.teamNames.contains(first.match.awayTeam))
    }

    func testCorregirLaLiguillaReajustaElCuadro() throws {
        var plan = try plan(teams: 4, total: 120)
        for slot in plan.slots where slot.stage == .groupStage {
            plan.setScore(for: slot, home: 15, away: 10)
        }
        let first = try XCTUnwrap(plan.slots.first { $0.stage == .knockout })
        plan.setScore(for: first, home: 15, away: 10)
        // Dar la vuelta a todos los marcadores de liguilla cambia el orden y por tanto los cruces.
        for slot in plan.slots where slot.stage == .groupStage {
            plan.setScore(for: slot, home: 0, away: 21)
        }
        let changed = try XCTUnwrap(plan.slots.first { $0.id == first.id })
        if changed.teamNames != first.teamNames {
            XCTAssertFalse(plan.savedKnockoutResults.contains { $0.matchID == first.id })
        }
    }

    func testRendimientoConVeinticuatroParejas() throws {
        var plan = try plan(teams: 24, total: 200)
        var generator = Generator(state: 3)
        let start = Date()
        play(&plan, using: &generator)
        // Son 100 partidos largos: cada anotación debe ser casi instantánea.
        XCTAssertLessThan(Date().timeIntervalSince(start) / Double(plan.totalMatchCount), 0.05)
    }

    func testEmpatarEnElCuadroNoCuentaComoResuelto() throws {
        var plan = try plan(teams: 4, total: 120)
        for slot in plan.slots where slot.stage == .groupStage {
            plan.setScore(for: slot, home: 15, away: 15)
        }
        XCTAssertEqual(plan.pendingLeagueMatchCount, 0, "En liguilla el empate vale")
        let slot = try XCTUnwrap(plan.slots.first { $0.stage == .knockout })
        plan.setScore(for: slot, home: 10, away: 10)
        XCTAssertNil(plan.placementFinalTable)
    }

    func testPorcentajeDeVictoriasNoCastigaAQuienDescansa() {
        let rows = PlacementStandings.rank(
            teamNames: ["A", "B", "C"],
            results: [
                MatchResult(homeTeam: "A", awayTeam: "C", homeScore: 15, awayScore: 10),
                MatchResult(homeTeam: "B", awayTeam: "C", homeScore: 15, awayScore: 10),
                MatchResult(homeTeam: "B", awayTeam: "C", homeScore: 10, awayScore: 15)
            ]
        )
        XCTAssertEqual(rows.first?.teamName, "A", "A gana 1 de 1; B gana 1 de 2")
    }

    func testSeGuardaYSeRecuperaLaConfiguracion() throws {
        var original = try plan(teams: 8, total: 120, rounds: 2)
        original.leagueClosedEarly = true
        let restored = try TournamentPlan(columns: try original.columns())
        XCTAssertEqual(restored.format, .leaguePlacement)
        XCTAssertEqual(restored.totalTimeMinutes, 120)
        XCTAssertEqual(restored.placementRounds, 2)
        XCTAssertEqual(restored.leagueClosedEarly, true)
    }

    func testOtrosFormatosNoGuardanCamposNuevos() throws {
        let plan = TournamentPlan(name: "Liga", format: .roundRobin, teamCount: 4)
        let json = try plan.configJSON()
        XCTAssertFalse(json.contains("totalTimeMinutes"))
        XCTAssertFalse(json.contains("placementRounds"))
    }
}
