import XCTest
@testable import MiGestorKMPMac

/// Escenas de la proyección: qué se ve en cada momento del torneo y que nunca salgan nombres.
final class TournamentProjectionModelTests: XCTestCase {
    private typealias Fixtures = TournamentTreeFixtures

    /// Nombres que no se parecen a «Equipo N»: si alguno aparece en la proyección, se nota.
    private func names(_ count: Int) -> [TournamentPlanTeam] {
        (1...count).map { TournamentPlanTeam(id: "alumno-\($0)", name: "Lucía y Hugo \($0)", studentIDs: ["est-\($0)"]) }
    }

    private func placement(teams: Int, venues: Int) throws -> TournamentPlan {
        var plan = TournamentPlan(
            name: "Torneo de prueba", format: .leaguePlacement, teams: names(teams),
            venueCount: venues, matchDurationMinutes: 8, transitionMinutes: 2
        )
        plan.totalTimeMinutes = 300
        plan.persistSchedule(try plan.generatedRounds())
        return plan
    }

    private func makePlan(_ format: TournamentFormat, teams: Int, venues: Int = 2, groups: Int = 0) throws -> TournamentPlan {
        var plan = TournamentPlan(
            name: "Torneo de prueba", format: format, teams: names(teams),
            groupCount: groups, qualifiedTeamsPerGroup: 2, venueCount: venues
        )
        plan.persistSchedule(try plan.generatedRounds())
        return plan
    }

    private func leagueFirstRoundSize(_ plan: TournamentPlan) -> Int {
        plan.savedSchedule.first(where: { $0.stage != .knockout })?.matches.count ?? 0
    }

    private func kinds(_ model: TournamentProjectionModel) -> [TournamentProjectionScene.Kind] {
        model.scenes.map(\.kind)
    }

    // MARK: Escenas por fase

    func testSinCalendarioMuestraUnMensaje() {
        let plan = TournamentPlan(name: "Vacío", format: .roundRobin, teams: names(4))
        let model = TournamentProjectionModel.make(plan: plan)
        XCTAssertEqual(model.stage, .empty)
        XCTAssertEqual(kinds(model), [.empty])
        XCTAssertTrue(model.footer.isEmpty)
    }

    func testSinEmpezarEnseñaLaPrimeraRonda() throws {
        let plan = try placement(teams: 12, venues: 6)
        let model = TournamentProjectionModel.make(plan: plan)
        XCTAssertEqual(model.stage, .notStarted)
        XCTAssertEqual(kinds(model), [.notStarted])
        guard case .notStarted(let upNext) = model.scenes[0] else { return XCTFail("escena inesperada") }
        XCTAssertEqual(upNext.header.title, "Prepárate")
        XCTAssertEqual(upNext.matches.count, leagueFirstRoundSize(plan))
        XCTAssertTrue(upNext.matches.allSatisfy { !$0.isPlayed })
        XCTAssertEqual(model.footer.map(\.state), [.current, .upcoming, .upcoming])
        XCTAssertEqual(model.footer.map(\.title), ["1 · Liguilla", "2 · Cuadro", "Podio"])
    }

    func testLiguillaEnJuegoRotaPistasYClasificacion() throws {
        var plan = try placement(teams: 12, venues: 6)
        let size = leagueFirstRoundSize(plan)
        Fixtures.playLeague(&plan, limit: size + 1)
        let model = TournamentProjectionModel.make(plan: plan)
        XCTAssertEqual(model.stage, .leagueInPlay)
        XCTAssertEqual(kinds(model), [.round, .standings])
        guard case .round(let round) = model.scenes[0] else { return XCTFail("escena inesperada") }
        XCTAssertEqual(round.header.title, "Ahora en juego")
        XCTAssertTrue(round.header.kicker.contains("Ronda 2 de"), round.header.kicker)
        XCTAssertEqual(round.playedCount, 1)
        // Un partido con marcador se ve como «Equipo N · Pista P».
        let played = try XCTUnwrap(round.matches.first(where: \.isPlayed))
        XCTAssertTrue(played.markerText.hasPrefix("Equipo "))
        XCTAssertTrue(played.markerText.contains("· Pista"))
    }

    func testDescansoEntreRondasEnseñaLaSiguiente() throws {
        var plan = try placement(teams: 12, venues: 6)
        Fixtures.playLeague(&plan, limit: leagueFirstRoundSize(plan))
        let model = TournamentProjectionModel.make(plan: plan)
        XCTAssertEqual(model.stage, .rest)
        XCTAssertEqual(kinds(model), [.upNext, .standings])
        guard case .upNext(let upNext) = model.scenes[0] else { return XCTFail("escena inesperada") }
        XCTAssertEqual(upNext.header.kicker, "Descanso · Prepárate")
        XCTAssertTrue(upNext.header.title.contains("Ronda 2 de"), upNext.header.title)
    }

    func testFinDeLiguillaAnunciaElCuadro() throws {
        var plan = try placement(teams: 12, venues: 6)
        Fixtures.playLeague(&plan)
        let model = TournamentProjectionModel.make(plan: plan)
        XCTAssertEqual(model.stage, .leagueEnded)
        XCTAssertEqual(kinds(model), [.phaseEnd, .standings])
        guard case .phaseEnd(let end) = model.scenes[0] else { return XCTFail("escena inesperada") }
        XCTAssertEqual(end.header.kicker, "Fin de la fase 1")
        XCTAssertFalse(end.matches.isEmpty)
        XCTAssertNotNil(end.note)
        XCTAssertEqual(model.footer.map(\.state), [.done, .current, .upcoming])
    }

    func testCuadroEnJuegoDiceAQueLlevaGanarOPerder() throws {
        var plan = try placement(teams: 16, venues: 8)
        Fixtures.playLeague(&plan)
        Fixtures.playBracket(&plan, limit: 2)
        let model = TournamentProjectionModel.make(plan: plan)
        XCTAssertEqual(model.stage, .bracketInPlay)
        XCTAssertEqual(kinds(model), [.round, .bracket])
        guard case .round(let round) = model.scenes[0] else { return XCTFail("escena inesperada") }
        XCTAssertEqual(round.playedCount, 2)
        XCTAssertTrue(round.matches.allSatisfy { $0.destination?.hasPrefix("Gana:") == true })
        XCTAssertTrue(round.matches.allSatisfy { $0.caption?.hasPrefix("Puestos") == true })
        XCTAssertEqual(model.footer.map(\.state), [.done, .current, .upcoming])
    }

    func testTerminadoEnseñaElPodio() throws {
        var plan = try placement(teams: 8, venues: 4)
        Fixtures.playLeague(&plan)
        Fixtures.playBracket(&plan)
        let model = TournamentProjectionModel.make(plan: plan)
        XCTAssertEqual(model.stage, .finished)
        XCTAssertEqual(kinds(model), [.podium])
        guard case .podium(let podium) = model.scenes[0] else { return XCTFail("escena inesperada") }
        XCTAssertEqual(podium.places.map(\.position), [1, 2, 3])
        XCTAssertEqual(podium.others.map(\.position), Array(4...8))
        XCTAssertEqual(model.footer.last?.state, .current)
    }

    func testLigaSencillaTerminaConPodio() throws {
        var plan = try makePlan(.roundRobin, teams: 4)
        Fixtures.playLeague(&plan)
        let model = TournamentProjectionModel.make(plan: plan)
        XCTAssertEqual(model.stage, .finished)
        guard case .podium(let podium) = model.scenes[0] else { return XCTFail("escena inesperada") }
        XCTAssertEqual(podium.places.count, 3)
    }

    func testGruposMuestranUnaTablaPorGrupo() throws {
        var plan = try makePlan(.groupStageKnockout, teams: 8, groups: 2)
        Fixtures.playLeague(&plan, limit: 2)
        let model = TournamentProjectionModel.make(plan: plan)
        guard case .standings(let standings) = model.scenes.last else { return XCTFail("falta la clasificación") }
        XCTAssertEqual(standings.tables.count, 2)
        XCTAssertEqual(standings.tables.map(\.title), ["Grupo A", "Grupo B"])
        XCTAssertEqual(standings.header.title, "Clasificación por grupos")
    }

    func testEliminatoriaEnJuegoYDescanso() throws {
        var plan = try makePlan(.knockout, teams: 8)
        Fixtures.playBracket(&plan, limit: 4)
        let model = TournamentProjectionModel.make(plan: plan)
        // Cuartos completos y sin resultados en semifinales: descanso.
        XCTAssertEqual(model.stage, .rest)
        XCTAssertEqual(model.scenes.first?.kind, .upNext)
        XCTAssertEqual(model.scenes.last?.kind, .bracket)
    }

    // MARK: Rotación y mitades

    func testRotacionDaLaVueltaYDura15Segundos() throws {
        var plan = try placement(teams: 12, venues: 6)
        Fixtures.playLeague(&plan, limit: leagueFirstRoundSize(plan) + 1)
        let model = TournamentProjectionModel.make(plan: plan)
        XCTAssertEqual(TournamentProjectionModel.rotationSeconds, 15)
        XCTAssertEqual(model.scene(at: 0).kind, .round)
        XCTAssertEqual(model.scene(at: 1).kind, .standings)
        XCTAssertEqual(model.scene(at: 2).kind, .round)
        XCTAssertEqual(model.scene(at: -1).kind, .standings)
    }

    func testCuadroEnteroConOchoPartidosPorRonda() throws {
        var plan = try placement(teams: 16, venues: 8)
        Fixtures.playLeague(&plan)
        Fixtures.playBracket(&plan, limit: 1)
        let model = TournamentProjectionModel.make(plan: plan)
        let brackets = model.scenes.compactMap { scene -> ProjectionBracket? in
            if case .bracket(let value) = scene { return value }
            return nil
        }
        XCTAssertEqual(brackets.map(\.part), [.whole])
    }

    func testCuadroEnDosMitadesConMasDeOchoPartidosPorRonda() throws {
        var plan = try placement(teams: 24, venues: 8)
        Fixtures.playLeague(&plan)
        Fixtures.playBracket(&plan, limit: 1)
        let model = TournamentProjectionModel.make(plan: plan)
        XCTAssertEqual(kinds(model), [.round, .bracket, .bracket])
        let parts = model.scenes.compactMap { scene -> ProjectionBracket? in
            if case .bracket(let value) = scene { return value }
            return nil
        }
        XCTAssertEqual(parts.map(\.part), [.first, .second])
        XCTAssertEqual(parts[0].header.title, "Cuadro · puestos 1 a 12")
        XCTAssertEqual(parts[1].header.title, "Cuadro · puestos 13 a 24")
        // Cada mitad lleva sus partidos, sin repetirse.
        let firstIDs = Set(parts[0].nodes.map(\.id))
        let secondIDs = Set(parts[1].nodes.map(\.id))
        XCTAssertTrue(firstIDs.isDisjoint(with: secondIDs))
        XCTAssertFalse(firstIDs.isEmpty)
        XCTAssertFalse(secondIDs.isEmpty)
        // Las líneas solo unen partidos que se dibujan en esa mitad.
        for part in parts {
            let ids = Set(part.nodes.map(\.id))
            for edge in part.edges {
                XCTAssertTrue(ids.contains(edge.from))
                if case .node(let target, _) = edge.target { XCTAssertTrue(ids.contains(target)) }
            }
        }
        XCTAssertNotEqual(parts[0].id, parts[1].id)
    }

    // MARK: Sin nombres

    func testNingunaCadenaLlevaNombresDeEquipoNiDeAlumno() throws {
        var plans: [TournamentPlan] = []
        // Todos los momentos del cuadro de puestos.
        var progress = try placement(teams: 12, venues: 6)
        plans.append(progress)
        Fixtures.playLeague(&progress, limit: leagueFirstRoundSize(progress))
        plans.append(progress)
        Fixtures.playLeague(&progress, limit: leagueFirstRoundSize(progress) + 2)
        plans.append(progress)
        Fixtures.playLeague(&progress)
        plans.append(progress)
        Fixtures.playBracket(&progress, limit: 3)
        plans.append(progress)
        Fixtures.playBracket(&progress)
        plans.append(progress)
        // Mitades, liga, grupos y eliminatoria.
        var big = try placement(teams: 24, venues: 8)
        Fixtures.playLeague(&big)
        Fixtures.playBracket(&big, limit: 1)
        plans.append(big)
        var league = try makePlan(.roundRobin, teams: 5)
        Fixtures.playLeague(&league, limit: 3)
        plans.append(league)
        var groups = try makePlan(.groupStageKnockout, teams: 8, groups: 2)
        Fixtures.playLeague(&groups)
        plans.append(groups)
        var knockout = try makePlan(.knockout, teams: 8)
        Fixtures.playBracket(&knockout, limit: 2)
        plans.append(knockout)
        Fixtures.playBracket(&knockout)
        plans.append(knockout)

        for plan in plans {
            let model = TournamentProjectionModel.make(plan: plan)
            let forbidden = plan.teams.flatMap { [$0.name, $0.id] + $0.studentIDs } + ["Lucía", "Hugo"]
            for text in model.allTexts {
                for word in forbidden {
                    XCTAssertFalse(text.contains(word), "«\(text)» lleva «\(word)» en \(model.stage)")
                }
            }
            XCTAssertFalse(model.allTexts.isEmpty)
        }
    }

    func testElNumeroDeEquipoEsFijoSegunPlanTeams() throws {
        var plan = try placement(teams: 8, venues: 4)
        let labels = ProjectionTeamLabels(plan: plan)
        XCTAssertEqual(labels.label(name: "Lucía y Hugo 3"), "Equipo 3")
        XCTAssertEqual(labels.label(id: "alumno-8"), "Equipo 8")
        // Jugar no cambia los números.
        Fixtures.playLeague(&plan, limit: 3)
        XCTAssertEqual(ProjectionTeamLabels(plan: plan), labels)
        let model = TournamentProjectionModel.make(plan: plan)
        guard case .round(let round) = model.scenes[0] else { return XCTFail("escena inesperada") }
        let slot = try XCTUnwrap(plan.slots.first(where: { $0.id == round.matches.first?.id }))
        let home = try XCTUnwrap(plan.teams.firstIndex { $0.name == slot.match.homeTeam })
        XCTAssertEqual(round.matches.first?.home, "Equipo \(home + 1)")
    }
    func testUnNombreDesconocidoNuncaLlegaALaProyeccion() throws {
        let labels = ProjectionTeamLabels(plan: try placement(teams: 8, venues: 4))
        // Nombre que no está en el plan (p. ej. de una edición anterior): no se proyecta.
        XCTAssertEqual(labels.label(name: "Marta y Leo"), ProjectionTeamLabels.unknownTeam)
        XCTAssertEqual(labels.label(name: "Andrés y Pablo 2"), ProjectionTeamLabels.unknownTeam)
        // Los huecos del cuadro sí pasan tal cual.
        for slot in ["Gana P5", "Pierde P12", "Ganador P3", "Perdedor P1", "Clasificado 2 Grupo B", "Clasificado 3", "3º liguilla", "1º Grupo A"] {
            XCTAssertEqual(labels.label(name: slot), slot)
        }
    }
}

private extension ProjectionBracket {
    var id: String { "\(part)" }
}
