import XCTest
@testable import MiGestorKMPMac

/// Piezas de prueba compartidas por las pruebas del árbol y de las fases.
enum TournamentTreeFixtures {
    static func placementPlan(teams: Int, venues: Int, total: Int = 300) throws -> TournamentPlan {
        var plan = TournamentPlan(
            name: "Prueba", format: .leaguePlacement,
            teams: (1...teams).map { TournamentPlanTeam(id: "t\($0)", name: "Pareja \($0)") },
            venueCount: venues, matchDurationMinutes: 8, transitionMinutes: 2
        )
        plan.totalTimeMinutes = total
        plan.persistSchedule(try plan.generatedRounds())
        return plan
    }

    static func knockoutPlan(teams: Int) throws -> TournamentPlan {
        var plan = TournamentPlan(
            name: "Eliminatoria", format: .knockout,
            teams: (1...teams).map { TournamentPlanTeam(id: "t\($0)", name: "Equipo \($0)") },
            venueCount: 2
        )
        plan.persistSchedule(try plan.generatedRounds())
        return plan
    }

    static func groupsPlan(teams: Int, groups: Int) throws -> TournamentPlan {
        var plan = TournamentPlan(
            name: "Grupos", format: .groupStageKnockout,
            teams: (1...teams).map { TournamentPlanTeam(id: "t\($0)", name: "Equipo \($0)") },
            groupCount: groups, qualifiedTeamsPerGroup: 2, venueCount: 2
        )
        plan.persistSchedule(try plan.generatedRounds())
        return plan
    }

    /// Juega los partidos de liguilla o grupos que digan `limit` (todos si es `nil`). Gana siempre el local por dos.
    static func playLeague(_ plan: inout TournamentPlan, limit: Int? = nil) {
        var count = 0
        for slot in plan.slots where slot.stage != .knockout {
            if let limit, count >= limit { return }
            plan.setScore(for: slot, home: 12 + count % 3, away: 10)
            count += 1
        }
    }

    /// Juega partidos del cuadro, gana el local, hasta `limit` (todos si es `nil`).
    static func playBracket(_ plan: inout TournamentPlan, limit: Int? = nil) {
        var count = 0
        while let slot = plan.slots.first(where: { $0.stage == .knockout && plan.canScore($0) && !plan.hasResult($0) }) {
            if let limit, count >= limit { return }
            plan.setScore(for: slot, home: 15, away: 10)
            count += 1
        }
    }
}

final class BracketTreeLayoutTests: XCTestCase {
    private typealias Fixtures = TournamentTreeFixtures

    // MARK: Estructura con 7, 12, 16 y 24 parejas

    func testEstructuraDelCuadroDePuestos() throws {
        for (teams, venues) in [(7, 3), (12, 6), (16, 8), (24, 8)] {
            let plan = try Fixtures.placementPlan(teams: teams, venues: venues)
            let layout = try XCTUnwrap(BracketTreeLayout.make(plan: plan), "\(teams) parejas")
            let bracket = plan.placementBracket

            XCTAssertEqual(layout.nodes.count, bracket.matches.count, "\(teams) parejas")
            XCTAssertEqual(layout.columns.count, bracket.roundCount, "\(teams) parejas")
            XCTAssertEqual(Set(layout.nodes.map(\.number)), Set(1...bracket.matches.count), "\(teams) parejas")
            XCTAssertEqual(layout.columns.map(\.title), (1...bracket.roundCount).map { "Ronda \($0)" })
            XCTAssertTrue(layout.isPlacement)

            // Cada partido manda a quien gana y a quien pierde a un solo sitio.
            for node in layout.nodes {
                let outgoing = layout.edges.filter { $0.from == node.id }
                XCTAssertEqual(outgoing.filter { $0.kind == .winner }.count, 1, "P\(node.number) de \(teams)")
                XCTAssertEqual(outgoing.filter { $0.kind == .loser }.count, 1, "P\(node.number) de \(teams)")
            }
            // Los puestos finales cubren todos los puestos sin repetir.
            XCTAssertEqual(layout.leaves.reduce(0) { $0 + $1.slotCount }, teams, "\(teams) parejas")
            let covered = layout.leaves.flatMap { Array($0.positions) }.sorted()
            XCTAssertEqual(covered, Array(1...teams), "\(teams) parejas")
            // Alturas sin solaparse dentro de una columna.
            for column in layout.columns {
                let ys = layout.nodes.filter { $0.column == column.id }.map(\.yRow).sorted()
                for (a, b) in zip(ys, ys.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, 1 - 1e-9) }
            }
        }
    }

    func testGruposImparesPasanDirectoYSeMarcan() throws {
        for (teams, venues) in [(7, 3), (12, 6), (24, 8)] {
            let plan = try Fixtures.placementPlan(teams: teams, venues: venues)
            let layout = try XCTUnwrap(BracketTreeLayout.make(plan: plan))
            let direct = layout.nodes.flatMap { [$0.home, $0.away] }.filter(\.isDirectPass)
            XCTAssertFalse(plan.placementBracket.byes.isEmpty, "\(teams) parejas")
            XCTAssertEqual(direct.count, plan.placementBracket.byes.count, "\(teams) parejas: un pase directo por cada hueco")
        }
        let even = try Fixtures.placementPlan(teams: 16, venues: 8)
        let layout = try XCTUnwrap(BracketTreeLayout.make(plan: even))
        XCTAssertTrue(layout.nodes.flatMap { [$0.home, $0.away] }.allSatisfy { !$0.isDirectPass })
    }

    // MARK: Huecos y estados

    func testAntesDeCerrarLaLiguillaSeVenHuecosYNadaEnJuego() throws {
        let plan = try Fixtures.placementPlan(teams: 12, venues: 6)
        let layout = try XCTUnwrap(BracketTreeLayout.make(plan: plan))
        XCTAssertFalse(layout.isOpen)
        XCTAssertNil(layout.currentColumn)
        XCTAssertTrue(layout.nodes.allSatisfy { $0.status == .pending })
        let first = layout.nodes.filter { $0.column == 0 }
        XCTAssertTrue(first.allSatisfy { $0.home.label.hasSuffix("º liguilla") && !$0.home.isResolved })
        let second = layout.nodes.filter { $0.column == 1 }
        XCTAssertTrue(second.allSatisfy { $0.home.label.hasPrefix("Gana P") || $0.home.label.hasPrefix("Pierde P") })
    }

    func testConLaLiguillaCerradaLaPrimeraRondaEstaEnJuegoConNombres() throws {
        var plan = try Fixtures.placementPlan(teams: 12, venues: 6)
        Fixtures.playLeague(&plan)
        let layout = try XCTUnwrap(BracketTreeLayout.make(plan: plan))
        XCTAssertTrue(layout.isOpen)
        XCTAssertEqual(layout.currentColumn, 0)
        XCTAssertEqual(layout.columns[0].state, .current)
        XCTAssertEqual(layout.columns[0].headerText, "Ronda 1 · en juego")
        let first = layout.nodes.filter { $0.column == 0 }
        XCTAssertTrue(first.allSatisfy { $0.status == .inPlay && $0.home.isResolved && $0.away.isResolved })
        XCTAssertTrue(layout.nodes.filter { $0.column > 0 }.allSatisfy { $0.status == .pending })
    }

    func testMarcadorYGanadorEnUnPartidoJugado() throws {
        var plan = try Fixtures.placementPlan(teams: 8, venues: 4)
        Fixtures.playLeague(&plan)
        Fixtures.playBracket(&plan, limit: 1)
        let layout = try XCTUnwrap(BracketTreeLayout.make(plan: plan))
        let played = try XCTUnwrap(layout.nodes.first { $0.status == .played })
        XCTAssertEqual(played.home.score, 15)
        XCTAssertEqual(played.away.score, 10)
        XCTAssertTrue(played.home.isWinner)
        XCTAssertFalse(played.away.isWinner)
        XCTAssertEqual(played.winnerTeamName, played.home.teamName)
        XCTAssertEqual(played.loserTeamName, played.away.teamName)
        XCTAssertEqual(layout.playedCount, 1)
    }

    func testTextoDeDestinoDelCuadroDePuestos() throws {
        let plan = try Fixtures.placementPlan(teams: 8, venues: 4)
        let layout = try XCTUnwrap(BracketTreeLayout.make(plan: plan))
        let first = try XCTUnwrap(layout.nodes.first)
        XCTAssertEqual(first.positions, 1...8)
        XCTAssertEqual(first.destinationText, "Gana: sigue por 1–4 · Pierde: sigue por 5–8")
        let last = try XCTUnwrap(layout.nodes.last { $0.column == layout.columns.count - 1 })
        XCTAssertTrue(last.destinationText.hasPrefix("Gana: puesto "))
    }

    // MARK: Camino de una pareja

    func testCaminoDeUnaParejaEnElCuadroDePuestos() throws {
        var plan = try Fixtures.placementPlan(teams: 16, venues: 8)
        Fixtures.playLeague(&plan)
        Fixtures.playBracket(&plan, limit: 8) // toda la primera ronda
        let layout = try XCTUnwrap(BracketTreeLayout.make(plan: plan))
        let match = try XCTUnwrap(layout.nodes.first { $0.status == .played && $0.column == 0 })
        let winnerID = try XCTUnwrap(match.home.teamID)
        let loserID = try XCTUnwrap(match.away.teamID)

        let up = try XCTUnwrap(layout.path(for: winnerID))
        XCTAssertNotNil(up.leagueText)
        XCTAssertEqual(up.steps.first?.outcome, .won)
        XCTAssertEqual(up.steps.first?.ownScore, 15)
        XCTAssertEqual(up.steps.first?.opponentScore, 10)
        XCTAssertTrue(up.highlightedNodeIDs.contains(match.id))
        let upEdge = try XCTUnwrap(layout.edges.first { $0.from == match.id && $0.kind == .winner })
        let downEdge = try XCTUnwrap(layout.edges.first { $0.from == match.id && $0.kind == .loser })
        XCTAssertTrue(up.highlightedEdgeIDs.contains(upEdge.id))
        XCTAssertFalse(up.highlightedEdgeIDs.contains(downEdge.id))
        // Su siguiente partido ya está en el camino: la ronda 2 toca jugarla.
        XCTAssertEqual(up.steps.count, 2)
        XCTAssertEqual(up.steps.last?.outcome, .playing)
        XCTAssertNil(up.finalPosition)
        XCTAssertTrue(up.summaryText.contains("gana 15–10"))

        let down = try XCTUnwrap(layout.path(for: loserID))
        XCTAssertEqual(down.steps.first?.outcome, .lost)
        XCTAssertTrue(down.highlightedEdgeIDs.contains(downEdge.id))
        XCTAssertFalse(down.highlightedEdgeIDs.contains(upEdge.id))
        XCTAssertTrue(down.summaryText.contains("pierde 10–15"))
        XCTAssertNil(layout.path(for: "no-existe"))
    }

    func testCaminoDeUnaParejaConUnPartidoEnJuegoDiceAdondeLleva() throws {
        var plan = try Fixtures.placementPlan(teams: 8, venues: 4)
        Fixtures.playLeague(&plan)
        let layout = try XCTUnwrap(BracketTreeLayout.make(plan: plan))
        let match = try XCTUnwrap(layout.nodes.first { $0.status == .inPlay })
        let path = try XCTUnwrap(layout.path(for: try XCTUnwrap(match.home.teamID)))
        XCTAssertEqual(path.steps.first?.outcome, .playing)
        XCTAssertTrue(path.steps.first?.text.contains("Gana: sigue por 1–4") ?? false)
    }

    func testTorneoTerminadoTodasLasParejasTienenPuestoFinalDistinto() throws {
        for (teams, venues) in [(7, 3), (12, 6), (16, 8), (24, 8)] {
            var plan = try Fixtures.placementPlan(teams: teams, venues: venues)
            Fixtures.playLeague(&plan)
            Fixtures.playBracket(&plan)
            let layout = try XCTUnwrap(BracketTreeLayout.make(plan: plan))
            XCTAssertTrue(layout.nodes.allSatisfy { $0.status == .played }, "\(teams) parejas")
            XCTAssertNil(layout.currentColumn)
            XCTAssertTrue(layout.leaves.allSatisfy(\.isComplete), "\(teams) parejas")
            let table = try XCTUnwrap(plan.placementFinalTable, "\(teams) parejas")
            var positions: Set<Int> = []
            for team in plan.teams {
                let path = try XCTUnwrap(layout.path(for: team.id))
                let expected = try XCTUnwrap(table.first { $0.teamName == team.name }?.position)
                XCTAssertEqual(path.finalPosition, expected, "\(team.name) de \(teams)")
                positions.insert(try XCTUnwrap(path.finalPosition))
                XCTAssertFalse(path.steps.isEmpty)
                XCTAssertTrue(path.steps.allSatisfy { $0.outcome == .won || $0.outcome == .lost })
            }
            XCTAssertEqual(positions, Set(1...teams), "\(teams) parejas")
        }
    }

    // MARK: Eliminatoria

    func testEliminatoriaDeOchoEquipos() throws {
        let plan = try Fixtures.knockoutPlan(teams: 8)
        let layout = try XCTUnwrap(BracketTreeLayout.make(plan: plan))
        XCTAssertFalse(layout.isPlacement)
        XCTAssertEqual(layout.columns.map(\.title), ["Cuartos de final", "Semifinales", "Final"])
        XCTAssertEqual(layout.columns.map { $0.nodeIDs.count }, [4, 2, 1])
        XCTAssertEqual(layout.finalColumnTitle, "Podio")
        XCTAssertEqual(layout.leaves.map(\.id), [1, 2])
        XCTAssertTrue(layout.nodes.allSatisfy { $0.positions == nil })
        // Solo suben los ganadores: 4 + 2 hacia nodos, 1 hacia el campeón, y 1 perdedor de la final al subcampeón.
        XCTAssertEqual(layout.edges.filter { $0.kind == .winner }.count, 7)
        XCTAssertEqual(layout.edges.filter { $0.kind == .loser }.count, 1)
        XCTAssertEqual(layout.nodes.first?.destinationText, "Gana: pasa a Semifinales · Pierde: queda eliminado")
        XCTAssertEqual(layout.nodes.last?.destinationText, "Gana: campeón · Pierde: subcampeón")
        XCTAssertTrue(layout.isOpen)
        XCTAssertEqual(layout.currentColumn, 0)
        // La semifinal queda centrada entre sus dos cuartos.
        let semi = try XCTUnwrap(layout.nodes.first { $0.column == 1 })
        let parents = layout.edges.compactMap { edge -> Double? in
            guard case .node(let id, _) = edge.target, id == semi.id else { return nil }
            return layout.node(edge.from)?.yRow
        }
        XCTAssertEqual(parents.count, 2)
        XCTAssertEqual(semi.yRow, parents.reduce(0, +) / 2, accuracy: 1e-9)
    }

    func testEliminatoriaDeSeisEquiposTieneUnSaltoDeColumna() throws {
        let plan = try Fixtures.knockoutPlan(teams: 6)
        let layout = try XCTUnwrap(BracketTreeLayout.make(plan: plan))
        XCTAssertEqual(layout.nodes.count, 5)
        XCTAssertEqual(layout.columns.map { $0.nodeIDs.count }, [3, 1, 1])
        // El ganador de un partido de la primera columna llega directo a la tercera.
        let jump = layout.edges.contains { edge in
            guard case .node(let id, _) = edge.target,
                  let from = layout.node(edge.from), let to = layout.node(id) else { return false }
            return to.column - from.column == 2
        }
        XCTAssertTrue(jump)
    }

    func testEliminatoriaTerminadaYCaminoDelCampeon() throws {
        var plan = try Fixtures.knockoutPlan(teams: 8)
        Fixtures.playBracket(&plan)
        let layout = try XCTUnwrap(BracketTreeLayout.make(plan: plan))
        XCTAssertTrue(layout.nodes.allSatisfy { $0.status == .played })
        XCTAssertEqual(layout.leaves.first?.teamNames, [plan.champion ?? "?"])
        let champion = try XCTUnwrap(plan.teams.first { $0.name == plan.champion })
        let path = try XCTUnwrap(layout.path(for: champion.id))
        XCTAssertEqual(path.steps.count, 3)
        XCTAssertTrue(path.steps.allSatisfy { $0.outcome == .won })
        XCTAssertEqual(path.finalPosition, 1)
        XCTAssertNil(path.leagueText)
        // Quien cae en cuartos se queda sin más pasos.
        let loser = try XCTUnwrap(layout.nodes.first?.loserTeamName)
        let loserTeam = try XCTUnwrap(plan.teams.first { $0.name == loser })
        let loserPath = try XCTUnwrap(layout.path(for: loserTeam.id))
        XCTAssertEqual(loserPath.steps.count, 1)
        XCTAssertEqual(loserPath.steps.first?.outcome, .lost)
        XCTAssertNil(loserPath.finalPosition)
    }

    func testLiguillaMasEliminatoriasAbreElCuadroAlTerminarLosGrupos() throws {
        var plan = try Fixtures.groupsPlan(teams: 8, groups: 2)
        var layout = try XCTUnwrap(BracketTreeLayout.make(plan: plan))
        XCTAssertFalse(layout.isOpen)
        XCTAssertTrue(layout.nodes.filter { $0.column == 0 }.allSatisfy { !$0.home.isResolved && $0.home.label.contains("Grupo") })
        Fixtures.playLeague(&plan)
        layout = try XCTUnwrap(BracketTreeLayout.make(plan: plan))
        XCTAssertTrue(layout.isOpen)
        XCTAssertTrue(layout.nodes.filter { $0.column == 0 }.allSatisfy { $0.home.isResolved && $0.status == .inPlay })
        let team = try XCTUnwrap(layout.nodes.first?.home.teamID)
        XCTAssertTrue(layout.path(for: team)?.leagueText?.contains("Grupo") ?? false)
    }

    func testFormatosSinCuadroNoTienenArbol() throws {
        var plan = TournamentPlan(name: "Liga", format: .roundRobin, teamCount: 6, venueCount: 2)
        plan.persistSchedule(try plan.generatedRounds())
        XCTAssertNil(BracketTreeLayout.make(plan: plan))
        let empty = TournamentPlan(name: "Vacío", format: .knockout, teamCount: 8)
        XCTAssertNil(BracketTreeLayout.make(plan: empty))
    }
}
