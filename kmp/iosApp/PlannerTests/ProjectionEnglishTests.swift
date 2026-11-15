import XCTest
@testable import MiGestorKMPMac

/// Toda la proyección del Mac se ve en inglés: ninguna cadena lleva palabras españolas típicas
/// y los huecos del cuadro se traducen con ordinales correctos.
final class ProjectionEnglishTests: XCTestCase {
    private typealias Fixtures = TournamentTreeFixtures

    /// Palabras españolas que no deben verse nunca en la proyección.
    private static let spanishWords = [
        "Equipo", "Pista", "contra", "Ronda", "Liguilla", "Cuadro", "Podio", "Descanso", "Prepárate",
        "Clasificación", "Gana", "Pierde", "Ganador", "Perdedor", "Campeones", "pausa", "Tiempo",
        "Grupo", "Puestos", "Fase", "conexión", "Descansa",
    ]

    private func teams(_ count: Int) -> [TournamentPlanTeam] {
        (1...count).map { TournamentPlanTeam(id: "alumno-\($0)", name: "Lucía y Hugo \($0)", studentIDs: ["est-\($0)"]) }
    }

    private func plan(_ format: TournamentFormat, teams count: Int, venues: Int = 2, groups: Int = 0) throws -> TournamentPlan {
        var plan = TournamentPlan(
            name: "Torneo de prueba", format: format, teams: teams(count),
            groupCount: groups, qualifiedTeamsPerGroup: 2, venueCount: venues,
            matchDurationMinutes: 8, transitionMinutes: 2
        )
        if format == .leaguePlacement { plan.totalTimeMinutes = 300 }
        plan.persistSchedule(try plan.generatedRounds())
        return plan
    }

    /// Planes en todos los momentos: sin empezar, en juego, descanso, fin de fase y terminado.
    private func plans() throws -> [TournamentPlan] {
        var result: [TournamentPlan] = []
        var league = try plan(.roundRobin, teams: 5)
        result.append(league)
        Fixtures.playLeague(&league, limit: 3)
        result.append(league)
        Fixtures.playLeague(&league)
        result.append(league)

        var placement = try plan(.leaguePlacement, teams: 12, venues: 6)
        result.append(placement)
        let first = placement.savedSchedule.first(where: { $0.stage != .knockout })?.matches.count ?? 0
        Fixtures.playLeague(&placement, limit: first)
        result.append(placement)
        Fixtures.playLeague(&placement, limit: first + 2)
        result.append(placement)
        Fixtures.playLeague(&placement)
        result.append(placement)
        Fixtures.playBracket(&placement, limit: 3)
        result.append(placement)
        Fixtures.playBracket(&placement)
        result.append(placement)

        var big = try plan(.leaguePlacement, teams: 24, venues: 8)
        Fixtures.playLeague(&big)
        Fixtures.playBracket(&big, limit: 1)
        result.append(big)

        var groups = try plan(.groupStageKnockout, teams: 8, groups: 2)
        result.append(groups)
        Fixtures.playLeague(&groups, limit: 2)
        result.append(groups)
        Fixtures.playLeague(&groups)
        result.append(groups)
        Fixtures.playBracket(&groups, limit: 1)
        result.append(groups)
        Fixtures.playBracket(&groups)
        result.append(groups)

        var knockout = try plan(.knockout, teams: 8)
        result.append(knockout)
        Fixtures.playBracket(&knockout, limit: 1)
        result.append(knockout)
        Fixtures.playBracket(&knockout, limit: 2)
        result.append(knockout)
        Fixtures.playBracket(&knockout)
        result.append(knockout)

        // Sin calendario.
        result.append(TournamentPlan(name: "Vacío", format: .roundRobin, teams: teams(4)))
        return result
    }

    private func assertEnglish(_ texts: [String], _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(texts.isEmpty, context, file: file, line: line)
        for text in texts {
            for word in Self.spanishWords {
                XCTAssertFalse(text.contains(word), "«\(text)» lleva «\(word)» en \(context)", file: file, line: line)
            }
        }
    }

    func testNingunaCadenaDeLaProyeccionLlevaPalabrasEspanolas() throws {
        for (index, plan) in try plans().enumerated() {
            let model = TournamentProjectionModel.make(plan: plan)
            assertEnglish(model.allTexts, "plan \(index) \(model.stage)")
            // Con los nombres encendidos solo cambian los equipos, el resto sigue en inglés.
            let named = TournamentProjectionModel.make(plan: plan, hints: ProjectionLiveHints(showNames: true))
            assertEnglish(named.allTexts, "plan \(index) con nombres")
            for scene in TournamentLiveScene.allCases {
                let hinted = TournamentProjectionModel.make(plan: plan, hints: ProjectionLiveHints(roundNumber: 2, scene: scene))
                assertEnglish(hinted.allTexts, "plan \(index) escena \(scene)")
            }
        }
    }

    func testLaProyeccionEnDirectoEstaEnIngles() throws {
        let plan = try plan(.roundRobin, teams: 6, venues: 3)
        let round = plan.slots.filter { $0.roundNumber == 1 }
        let state = TournamentLiveState(
            sessionId: "s", tournamentId: "t1", seq: 1, sentAtMs: 1_000_000, receivedAtMs: 1_000_000,
            status: .paused, roundNumber: 1,
            timer: TournamentLiveTimer(endAtMs: nil, pausedRemainingS: 30, totalS: 480),
            showNames: true,
            scores: Dictionary(uniqueKeysWithValues: round.map { ($0.id.uuidString, [2, 1]) })
        )
        for stale in [false, true] {
            let live = TournamentLiveProjection(tournamentID: "t1", state: state, clock: TournamentLiveClock(), isStale: stale)
            let model = TournamentProjectionModel.make(plan: live.plan(overlaying: plan), hints: live.hints)
            assertEnglish(model.allTexts, "directo (viejo: \(stale))")
        }
        assertEnglish(ProjectionLiveTexts.fixedTexts, "textos fijos del directo")
        XCTAssertEqual(ProjectionLiveTexts.timeUp, "Time!")
        XCTAssertEqual(ProjectionLiveTexts.paused, "Paused")
        assertEnglish(
            [ProjectionStrings.loading, ProjectionStrings.tournamentNotFound, ProjectionStrings.placeLabel(1), ProjectionStrings.matchLabel(2)],
            "mensajes de la ventana"
        )
    }

    func testLosHuecosSeVenEnInglesEnElCuadro() throws {
        var knockout = try plan(.knockout, teams: 8)
        Fixtures.playBracket(&knockout, limit: 1)
        let texts = TournamentProjectionModel.make(plan: knockout).allTexts
        XCTAssertTrue(texts.contains { $0.hasPrefix("Winner M") }, "falta un hueco «Winner M» en \(texts)")
        XCTAssertTrue(texts.contains("Quarterfinals") || texts.contains("Semifinals"), "\(texts)")
        XCTAssertTrue(texts.contains { $0.contains("Team ") })

        let groups = try plan(.groupStageKnockout, teams: 8, groups: 2)
        let layout = try XCTUnwrap(BracketTreeLayout.make(plan: groups))
        let labels = ProjectionTeamLabels(plan: groups)
        let slots = layout.nodes.flatMap { [$0.home.label, $0.away.label] }.map { labels.label(name: $0) }
        XCTAssertTrue(slots.contains("1st Group A") || slots.contains("2nd Group B"), "\(slots)")
    }

    func testTraduccionDeHuecosYOrdinales() {
        let cases = [
            ("Gana P5", "Winner M5"), ("Pierde P5", "Loser M5"), ("Ganador P3", "Winner M3"), ("Perdedor P3", "Loser M3"),
            ("3º liguilla", "3rd group stage"), ("1º Grupo A", "1st Group A"), ("Clasificado 2 Grupo B", "2nd Group B"),
            ("Clasificado 4", "4th group stage"), ("12º liguilla", "12th group stage"),
        ]
        for (spanish, english) in cases {
            XCTAssertEqual(ProjectionStrings.placeholder(spanish), english)
            XCTAssertTrue(ProjectionTeamLabels.isSlotPlaceholder(spanish), spanish)
        }
        let ordinals = [1: "1st", 2: "2nd", 3: "3rd", 4: "4th", 10: "10th", 11: "11th", 12: "12th", 13: "13th",
                        14: "14th", 21: "21st", 22: "22nd", 23: "23rd", 101: "101st", 111: "111th", 112: "112th"]
        for (number, text) in ordinals { XCTAssertEqual(ProjectionStrings.ordinal(number), text) }
    }

    func testGlosarioDeFasesYTextos() {
        XCTAssertEqual(ProjectionStrings.footerTitle("Fase 1 · Liguilla"), "1 · Group stage")
        XCTAssertEqual(ProjectionStrings.footerTitle("Fase 1 · Grupos"), "1 · Groups")
        XCTAssertEqual(ProjectionStrings.footerTitle("Fase 2 · Cuartos de final"), "2 · Quarterfinals")
        XCTAssertEqual(ProjectionStrings.footerBracket(number: 2, isPlacement: true), "2 · Bracket")
        XCTAssertEqual(ProjectionStrings.phaseTitle("Fase 1 · Liguilla"), "Phase 1 · Group stage")
        XCTAssertEqual(ProjectionStrings.phaseTitle("Liga"), "League")
        for (spanish, english) in [("Final", "Final"), ("Semifinales", "Semifinals"), ("Cuartos de final", "Quarterfinals"),
                                   ("Octavos de final", "Round of 16"), ("Ronda 3", "Round 3")] {
            XCTAssertEqual(ProjectionStrings.stage(spanish), english)
        }
        XCTAssertEqual(ProjectionStrings.round(3, of: 7), "Round 3 of 7")
        XCTAssertEqual(ProjectionStrings.resting(["Team 3"]), "Resting: Team 3")
        XCTAssertEqual(ProjectionStrings.resting(["Team 3", "Team 5"]), "Resting: Team 3, Team 5")
        XCTAssertEqual(ProjectionStrings.resting((1...7).map { "Team \($0)" }), "7 teams resting")
        XCTAssertNil(ProjectionStrings.resting([]))
        XCTAssertEqual(ProjectionStrings.destination(winner: "sigue por 1–4", loser: "sigue por 5–8"), "Win: places 1–4 · Lose: places 5–8")
        XCTAssertEqual(ProjectionStrings.destination(winner: "puesto 1º", loser: "puesto 2º"), "Win: 1st place · Lose: 2nd place")
        XCTAssertEqual(ProjectionStrings.placesCaption(1...4), "Places 1–4")
        XCTAssertEqual(ProjectionStrings.columnSubtitle("2 grupos de 4 puestos"), "2 groups of 4 places")
        XCTAssertEqual(ProjectionStrings.groupName("Grupo A"), "Group A")
        XCTAssertEqual(
            ProjectionLiveTexts.offlineNotice(atMs: 1_700_000_000_000, timeZone: TimeZone(secondsFromGMT: 0)!),
            "iPad disconnected · last update 22:13"
        )
    }
}
