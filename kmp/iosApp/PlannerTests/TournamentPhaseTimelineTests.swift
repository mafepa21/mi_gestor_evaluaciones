import XCTest
@testable import MiGestorKMPMac

/// Fases del torneo y su progreso.
final class TournamentPhaseTimelineTests: XCTestCase {
    private typealias Fixtures = TournamentTreeFixtures

    func testLiguillaMasPuestosSinEmpezar() throws {
        for (teams, venues) in [(7, 3), (12, 6), (16, 8), (24, 8)] {
            let plan = try Fixtures.placementPlan(teams: teams, venues: venues)
            let timeline = TournamentPhaseTimeline.make(plan: plan)
            XCTAssertEqual(timeline.phases.map(\.kind), [.league, .bracket, .podium], "\(teams) parejas")
            XCTAssertEqual(timeline.currentKind, .league)
            XCTAssertEqual(timeline.phases.map(\.state), [.current, .upcoming, .upcoming])
            XCTAssertFalse(timeline.hasStarted)
            XCTAssertEqual(timeline.leaguePlayed, 0)
            XCTAssertGreaterThan(timeline.leagueTotal, 0)
            XCTAssertTrue(timeline.phases[0].detail.hasPrefix("Sin empezar"))
            XCTAssertEqual(timeline.phases[1].detail, "Se abre al acabar la liguilla")
            XCTAssertEqual(timeline.phases.map(\.number), [1, 2, 3])
            XCTAssertEqual(timeline.phases[0].title, "Fase 1 · Liguilla")
            XCTAssertEqual(timeline.phases[0].progress, 0)
        }
    }

    func testLiguillaAMedias() throws {
        var plan = try Fixtures.placementPlan(teams: 12, venues: 6)
        let total = TournamentPhaseTimeline.make(plan: plan).leagueTotal
        Fixtures.playLeague(&plan, limit: total / 2)
        let timeline = TournamentPhaseTimeline.make(plan: plan)
        XCTAssertEqual(timeline.currentKind, .league)
        XCTAssertEqual(timeline.leaguePlayed, total / 2)
        XCTAssertTrue(timeline.hasStarted)
        XCTAssertEqual(timeline.phases[0].progress, Double(total / 2) / Double(total), accuracy: 1e-9)
        XCTAssertTrue(timeline.phases[0].detail.hasPrefix("Ronda "), timeline.phases[0].detail)
        XCTAssertNotNil(timeline.currentRound)
        XCTAssertEqual(timeline.phases[1].state, .upcoming)
    }

    func testCuadroSinEmpezarYAMedias() throws {
        var plan = try Fixtures.placementPlan(teams: 16, venues: 8)
        Fixtures.playLeague(&plan)
        var timeline = TournamentPhaseTimeline.make(plan: plan)
        XCTAssertEqual(timeline.currentKind, .bracket)
        XCTAssertEqual(timeline.phases.map(\.state), [.done, .current, .upcoming])
        XCTAssertTrue(timeline.phases[0].detail.hasPrefix("Terminada"))
        XCTAssertTrue(timeline.phases[1].detail.hasPrefix("Sin empezar"))
        XCTAssertEqual(timeline.currentRound, 1)

        Fixtures.playBracket(&plan, limit: 10)
        timeline = TournamentPhaseTimeline.make(plan: plan)
        XCTAssertEqual(timeline.currentKind, .bracket)
        XCTAssertEqual(timeline.bracketPlayed, 10)
        XCTAssertTrue(timeline.phases[1].detail.hasPrefix("Ronda 2 de 4 · 10 de "), timeline.phases[1].detail)
        XCTAssertEqual(timeline.currentRound, 2)
        XCTAssertEqual(timeline.currentRoundCount, 4)
        XCTAssertGreaterThan(timeline.phases[1].progress, 0)
        XCTAssertLessThan(timeline.phases[1].progress, 1)
    }

    func testCerrarLaLiguillaAntesDeTiempoAbreElCuadro() throws {
        var plan = try Fixtures.placementPlan(teams: 12, venues: 6)
        Fixtures.playLeague(&plan, limit: 6)
        plan.closeLeagueEarly()
        let timeline = TournamentPhaseTimeline.make(plan: plan)
        XCTAssertEqual(timeline.currentKind, .bracket)
        XCTAssertEqual(timeline.leagueTotal, 6, "Los partidos descartados ya no cuentan")
        XCTAssertTrue(timeline.phases[0].isDone)
    }

    func testTorneoTerminadoEstaEnElPodio() throws {
        for (teams, venues) in [(7, 3), (24, 8)] {
            var plan = try Fixtures.placementPlan(teams: teams, venues: venues)
            Fixtures.playLeague(&plan)
            Fixtures.playBracket(&plan)
            let timeline = TournamentPhaseTimeline.make(plan: plan)
            XCTAssertEqual(timeline.currentKind, .podium, "\(teams) parejas")
            XCTAssertEqual(timeline.phases.map(\.state), [.done, .done, .current])
            XCTAssertEqual(timeline.bracketPlayed, timeline.bracketTotal)
            XCTAssertEqual(timeline.phases[2].detail, "Clasificación final")
            XCTAssertEqual(timeline.phases[2].progress, 0, "El podio no es una fase con barra")
        }
    }

    func testEliminatoriaDeOchoYSeisEquiposUsaLasRondasComoFases() throws {
        var plan = try Fixtures.knockoutPlan(teams: 8)
        var timeline = TournamentPhaseTimeline.make(plan: plan)
        XCTAssertEqual(timeline.phases.map(\.kind), [.round(1), .round(2), .round(3), .podium])
        XCTAssertEqual(timeline.phases.map(\.title), [
            "Fase 1 · Cuartos de final", "Fase 2 · Semifinales", "Fase 3 · Final", "Podio"
        ])
        XCTAssertEqual(timeline.currentKind, .round(1))
        XCTAssertEqual(timeline.bracketTotal, 7)

        Fixtures.playBracket(&plan, limit: 4)
        timeline = TournamentPhaseTimeline.make(plan: plan)
        XCTAssertEqual(timeline.currentKind, .round(2))
        XCTAssertEqual(timeline.phases.map(\.state), [.done, .current, .upcoming, .upcoming])

        Fixtures.playBracket(&plan)
        timeline = TournamentPhaseTimeline.make(plan: plan)
        XCTAssertEqual(timeline.currentKind, .podium)
        XCTAssertEqual(timeline.phases.map(\.state), [.done, .done, .done, .current])

        let six = TournamentPhaseTimeline.make(plan: try Fixtures.knockoutPlan(teams: 6))
        XCTAssertEqual(six.phases.map(\.kind), [.round(1), .round(2), .round(3), .podium])
    }

    func testLiguillaMasEliminatoriasTieneGruposCuadroYPodio() throws {
        var plan = try Fixtures.groupsPlan(teams: 8, groups: 2)
        var timeline = TournamentPhaseTimeline.make(plan: plan)
        XCTAssertEqual(timeline.phases.map(\.kind), [.league, .bracket, .podium])
        XCTAssertEqual(timeline.phases[0].title, "Fase 1 · Grupos")
        XCTAssertEqual(timeline.phases[1].detail, "Se abre al acabar los grupos")
        Fixtures.playLeague(&plan)
        timeline = TournamentPhaseTimeline.make(plan: plan)
        XCTAssertEqual(timeline.currentKind, .bracket)
        Fixtures.playBracket(&plan)
        XCTAssertEqual(TournamentPhaseTimeline.make(plan: plan).currentKind, .podium)
    }

    func testLigaYRotacionesSoloTienenLigaYClasificacionFinal() throws {
        for format in [TournamentFormat.roundRobin, .rotation] {
            var plan = TournamentPlan(name: "Liga", format: format, teamCount: 6, venueCount: 2)
            plan.persistSchedule(try plan.generatedRounds())
            var timeline = TournamentPhaseTimeline.make(plan: plan)
            XCTAssertEqual(timeline.phases.map(\.kind), [.league, .podium])
            XCTAssertEqual(timeline.phases[1].title, "Clasificación final")
            XCTAssertEqual(timeline.currentKind, .league)
            XCTAssertEqual(timeline.bracketTotal, 0)
            if format == .roundRobin {
                Fixtures.playLeague(&plan)
                timeline = TournamentPhaseTimeline.make(plan: plan)
                XCTAssertEqual(timeline.currentKind, .podium)
                XCTAssertTrue(timeline.phases[0].isDone)
            }
        }
    }
}
