import XCTest
@testable import MiGestorKMPMac

/// Canal en directo de torneos: estado, reloj con desfase, marcadores provisionales, política de
/// la ventana del Mac y lectura de las respuestas del helper. Sin red.
final class TournamentLiveStateTests: XCTestCase {
    private typealias Fixtures = TournamentTreeFixtures

    private func names(_ count: Int) -> [TournamentPlanTeam] {
        (1...count).map { TournamentPlanTeam(id: "alumno-\($0)", name: "Lucía y Hugo \($0)", studentIDs: ["est-\($0)"]) }
    }

    private func leaguePlan(teams: Int = 6, venues: Int = 3) throws -> TournamentPlan {
        var plan = TournamentPlan(name: "Liga de prueba", format: .roundRobin, teams: names(teams), venueCount: venues)
        plan.persistSchedule(try plan.generatedRounds())
        return plan
    }

    private func state(
        session: String = "s1",
        tournament: String = "t1",
        seq: Int64 = 1,
        sentAtMs: Int64 = 1_000_000,
        receivedAtMs: Int64? = 1_000_000,
        status: TournamentLiveStatus = .running,
        roundNumber: Int? = nil,
        timer: TournamentLiveTimer? = nil,
        scene: TournamentLiveScene = .auto,
        scores: [String: [Int]] = [:]
    ) -> TournamentLiveState {
        TournamentLiveState(
            sessionId: session, tournamentId: tournament, seq: seq, sentAtMs: sentAtMs,
            receivedAtMs: receivedAtMs, status: status, roundNumber: roundNumber,
            timer: timer, scene: scene, scores: scores
        )
    }

    // MARK: Codable

    func testCodableIdaYVuelta() throws {
        let original = state(
            roundNumber: 2,
            timer: TournamentLiveTimer(endAtMs: 61_000, pausedRemainingS: nil, totalS: 60),
            scene: .courts,
            scores: [UUID().uuidString: [3, 2]]
        )
        let decoded = try XCTUnwrap(TournamentLiveState.decode(try original.encoded()))
        XCTAssertEqual(decoded, original)
    }

    func testValoresDesconocidosCaenEnPausaYAuto() throws {
        let json = """
        {"v":1,"sessionId":"s","tournamentId":"t","seq":0,"sentAtMs":1,"status":"volando","scene":"otra","scores":{}}
        """
        let decoded = try XCTUnwrap(TournamentLiveState.decode(Data(json.utf8)))
        XCTAssertEqual(decoded.status, .paused)
        XCTAssertEqual(decoded.scene, .auto)
        XCTAssertNil(TournamentLiveState.decode(Data(#"{"v":2,"sessionId":"s","tournamentId":"t","seq":0,"sentAtMs":1,"status":"running","scene":"auto","scores":{}}"#.utf8)))
    }

    func testElJSONCon64MarcadoresCabeEnElLimiteYNoLlevaNombres() throws {
        var scores: [String: [Int]] = [:]
        for _ in 0..<TournamentLiveState.maxScores { scores[UUID().uuidString] = [999, 999] }
        let data = try state(roundNumber: 3, timer: TournamentLiveTimer(endAtMs: 1, pausedRemainingS: 5, totalS: 600), scores: scores).encoded()
        XCTAssertLessThan(data.count, 16 * 1024)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("teamNames"))
        XCTAssertFalse(text.contains("names"))
    }

    // MARK: Reloj

    func testRelojConDesfaseDeNoventaSegundosEnAmbosSentidos() {
        let timer = TournamentLiveTimer(endAtMs: 1_060_000, pausedRemainingS: nil, totalS: 60)
        for skew: Int64 in [90_000, -90_000] {
            // El reloj del iPad difiere `skew` del del Mac: el helper ve received = sent + skew (latencia nula).
            var clock = TournamentLiveClock()
            let live = state(sentAtMs: 1_000_000, receivedAtMs: 1_000_000 + skew, timer: timer)
            clock.observe(live)
            XCTAssertEqual(clock.offsetMs, skew)
            // 10 s después (reloj del Mac) quedan unos 50 s.
            let nowMs = 1_000_000 + skew + 10_000
            XCTAssertEqual(clock.remainingSeconds(of: live, nowMs: nowMs), 50)
        }
    }

    func testElDesfaseEsElMinimoDeLasUltimasDoceMuestras() {
        var clock = TournamentLiveClock()
        // Una muestra muy rápida y luego doce más lentas: la rápida sale de la ventana.
        clock.observe(state(sentAtMs: 0, receivedAtMs: 10))
        XCTAssertEqual(clock.offsetMs, 10)
        for _ in 0..<12 { clock.observe(state(sentAtMs: 0, receivedAtMs: 500)) }
        XCTAssertEqual(clock.offsets.count, TournamentLiveClock.maxSamples)
        XCTAssertEqual(clock.offsetMs, 500)
        clock.observe(state(sentAtMs: 0, receivedAtMs: 80))
        XCTAssertEqual(clock.offsetMs, 80)
    }

    func testRelojEnPausaYAlLlegarACero() {
        let clock = TournamentLiveClock()
        let paused = state(status: .paused, timer: TournamentLiveTimer(endAtMs: nil, pausedRemainingS: 37, totalS: 480))
        XCTAssertEqual(clock.remainingSeconds(of: paused, nowMs: 5_000_000), 37)
        let notStarted = state(status: .paused, timer: TournamentLiveTimer(endAtMs: nil, pausedRemainingS: nil, totalS: 480))
        XCTAssertEqual(clock.remainingSeconds(of: notStarted, nowMs: 0), 480)
        let timeUp = state(status: .timeUp, timer: TournamentLiveTimer(endAtMs: nil, pausedRemainingS: 0, totalS: 480))
        XCTAssertEqual(clock.remainingSeconds(of: timeUp, nowMs: 0), 0)
        // Corriendo, pasado el fin: 0 (nunca negativo).
        let over = state(status: .running, timer: TournamentLiveTimer(endAtMs: 1_000, pausedRemainingS: nil, totalS: 10))
        XCTAssertEqual(clock.remainingSeconds(of: over, nowMs: 9_000), 0)
        XCTAssertNil(clock.remainingSeconds(of: state(timer: nil), nowMs: 0))
    }

    func testElRelojRedondeaHaciaArriba() {
        let clock = TournamentLiveClock()
        let live = state(status: .running, timer: TournamentLiveTimer(endAtMs: 10_001, pausedRemainingS: nil, totalS: 60))
        XCTAssertEqual(clock.remainingSeconds(of: live, nowMs: 0), 11)
        XCTAssertEqual(clock.remainingSeconds(of: live, nowMs: 1), 10)
    }

    // MARK: Frescura

    func testFrescuraDoceSegundosExactos() {
        XCTAssertFalse(TournamentLiveFreshness.isStale(receivedAtMs: 1_000, nowMs: 13_000))
        XCTAssertTrue(TournamentLiveFreshness.isStale(receivedAtMs: 1_000, nowMs: 13_001))
    }

    // MARK: Marcadores provisionales

    func testElOverlayNoMutaElPlanYAplicaElMarcador() throws {
        let plan = try leaguePlan()
        let original = plan
        let slot = try XCTUnwrap(plan.slots.first)
        let live = state(tournament: "t1", scores: [slot.id.uuidString: [7, 4]])
        let shown = TournamentLiveOverlay.apply(live, to: plan, tournamentID: "t1", isStale: false)
        XCTAssertEqual(plan, original)
        let shownSlot = try XCTUnwrap(shown.slots.first { $0.id == slot.id })
        XCTAssertEqual(shown.result(for: shownSlot)?.homeScore, 7)
        XCTAssertEqual(shown.result(for: shownSlot)?.awayScore, 4)
        XCTAssertTrue(plan.savedResults.isEmpty, "el marcador provisional nunca se guarda")
    }

    func testElOverlayIgnoraIdsDesconocidosYMalformados() throws {
        let plan = try leaguePlan()
        let live = state(scores: [UUID().uuidString: [1, 1], "no-es-uuid": [2, 2]])
        XCTAssertEqual(TournamentLiveOverlay.apply(live, to: plan, tournamentID: "t1", isStale: false), plan)
        let slot = try XCTUnwrap(plan.slots.first)
        let corto = state(scores: [slot.id.uuidString: [3]])
        XCTAssertEqual(TournamentLiveOverlay.apply(corto, to: plan, tournamentID: "t1", isStale: false), plan)
    }

    func testElOverlayNoSeAplicaConEstadoViejoDeOtroTorneoOCerrado() throws {
        let plan = try leaguePlan()
        let slot = try XCTUnwrap(plan.slots.first)
        let scores = [slot.id.uuidString: [5, 0]]
        XCTAssertEqual(TournamentLiveOverlay.apply(state(scores: scores), to: plan, tournamentID: "t1", isStale: true), plan)
        XCTAssertEqual(TournamentLiveOverlay.apply(state(tournament: "otro", scores: scores), to: plan, tournamentID: "t1", isStale: false), plan)
        let ended = state(status: .ended, scores: scores)
        XCTAssertEqual(TournamentLiveOverlay.apply(ended, to: plan, tournamentID: "t1", isStale: false), plan)
        // Solo la decisión de «torneo terminado» mira el de cierre.
        XCTAssertNotEqual(TournamentLiveOverlay.apply(ended, to: plan, tournamentID: "t1", isStale: false, allowEnded: true), plan)
    }

    // MARK: Proyección en directo

    func testLaProyeccionEnDirectoNoLlevaNombres() throws {
        var plan = try leaguePlan()
        let firstRound = plan.slots.filter { $0.roundNumber == 1 }
        let live = state(
            roundNumber: 1,
            timer: TournamentLiveTimer(endAtMs: 99_000, pausedRemainingS: nil, totalS: 480),
            scores: Dictionary(uniqueKeysWithValues: firstRound.map { ($0.id.uuidString, [2, 1]) })
        )
        for scene in TournamentLiveScene.allCases {
            var hinted = live
            hinted.scene = scene
            let projection = TournamentLiveProjection(tournamentID: "t1", state: hinted, clock: TournamentLiveClock(), isStale: false)
            let model = TournamentProjectionModel.make(plan: projection.plan(overlaying: plan), hints: projection.hints)
            let forbidden = plan.teams.flatMap { [$0.name, $0.id] + $0.studentIDs } + ["Lucía", "Hugo"]
            for text in model.allTexts + ProjectionLiveTexts.fixedTexts {
                for word in forbidden { XCTAssertFalse(text.contains(word), "«\(text)» lleva «\(word)»") }
            }
        }
        // Y el marcador provisional se ve en la ronda en juego.
        let projection = TournamentLiveProjection(tournamentID: "t1", state: live, clock: TournamentLiveClock(), isStale: false)
        let model = TournamentProjectionModel.make(plan: projection.plan(overlaying: plan), hints: projection.hints)
        guard case .round(let round) = model.scenes[0] else { return XCTFail("escena inesperada") }
        XCTAssertTrue(round.matches.allSatisfy { $0.homeScore == 2 && $0.awayScore == 1 })
        // El plan base no cambió.
        plan.status = .draft
        XCTAssertTrue(plan.savedResults.isEmpty)
    }

    func testLaRondaDelIPadSustituyeALaDeducida() throws {
        var plan = try leaguePlan()
        Fixtures.playLeague(&plan, limit: 1)
        let deduced = TournamentProjectionModel.make(plan: plan)
        guard case .round(let a) = deduced.scenes[0] else { return XCTFail("escena inesperada") }
        XCTAssertTrue(a.header.kicker.contains("Ronda 1 de"), a.header.kicker)
        let hinted = TournamentProjectionModel.make(plan: plan, hints: ProjectionLiveHints(roundNumber: 3, scene: .auto))
        guard let first = hinted.scenes.first else { return XCTFail("sin escenas") }
        XCTAssertTrue(first.header.title.contains("Ronda 3 de"), first.header.title)
        // Una ronda inexistente se ignora.
        let unknown = TournamentProjectionModel.make(plan: plan, hints: ProjectionLiveHints(roundNumber: 99, scene: .auto))
        XCTAssertEqual(unknown, deduced)
        XCTAssertEqual(TournamentProjectionModel.make(plan: plan, hints: nil), deduced)
    }

    func testLaEscenaForzadaFiltraYSiNoHayCoincidenciaVuelveLaRotacion() throws {
        var plan = try leaguePlan()
        Fixtures.playLeague(&plan, limit: 1)
        let all = TournamentProjectionModel.make(plan: plan)
        XCTAssertEqual(all.scenes.map(\.kind), [.round, .standings])
        let standings = TournamentProjectionModel.make(plan: plan, hints: ProjectionLiveHints(scene: .standings))
        XCTAssertEqual(standings.scenes.map(\.kind), [.standings])
        let courts = TournamentProjectionModel.make(plan: plan, hints: ProjectionLiveHints(scene: .courts))
        XCTAssertEqual(courts.scenes.map(\.kind), [.round])
        // Una liga no tiene cuadro: la escena vacía vuelve a la rotación automática.
        let bracket = TournamentProjectionModel.make(plan: plan, hints: ProjectionLiveHints(scene: .bracket))
        XCTAssertEqual(bracket.scenes, all.scenes)
        XCTAssertFalse(bracket.scenes.isEmpty)
    }

    func testLasPistasNoValenParaElEstadoDeCierreNiParaOtroTorneo() {
        let base = TournamentLiveProjection(tournamentID: "t1", state: state(roundNumber: 2, scene: .courts), clock: TournamentLiveClock(), isStale: false)
        XCTAssertEqual(base.hints, ProjectionLiveHints(roundNumber: 2, scene: .courts))
        var ended = base
        ended.state.status = .ended
        XCTAssertNil(ended.hints)
        var other = base
        other.state.tournamentId = "t2"
        XCTAssertNil(other.hints)
        XCTAssertFalse(other.showsClock)
        XCTAssertFalse(other.showsOfflineNotice)
    }

    func testElAvisoSinConexionSoloConLaSesionAbierta() {
        var live = TournamentLiveProjection(
            tournamentID: "t1",
            state: state(timer: TournamentLiveTimer(endAtMs: 5, pausedRemainingS: nil, totalS: 60)),
            clock: TournamentLiveClock(), isStale: true
        )
        XCTAssertTrue(live.showsOfflineNotice)
        XCTAssertTrue(live.showsClock, "con el iPad sin conexión el reloj sigue")
        live.state.status = .ended
        XCTAssertFalse(live.showsOfflineNotice)
        let notice = ProjectionLiveTexts.offlineNotice(atMs: 1_700_000_000_000, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(notice, "Sin conexión con el iPad · datos de las 22:13")
    }

    // MARK: Política de la ventana

    func testPodioSesentaSegundosEnUnaConstante() {
        XCTAssertEqual(TournamentLiveProjectionPolicy.podiumHoldSeconds, 60)
    }

    func testCuandoAbrirLaVentana() {
        let running = state(session: "a")
        XCTAssertTrue(TournamentLiveProjectionPolicy.shouldOpen(state: running, isStale: false, hasWindow: false, closedByHandSessions: []))
        XCTAssertFalse(TournamentLiveProjectionPolicy.shouldOpen(state: running, isStale: true, hasWindow: false, closedByHandSessions: []))
        XCTAssertFalse(TournamentLiveProjectionPolicy.shouldOpen(state: running, isStale: false, hasWindow: true, closedByHandSessions: []))
        XCTAssertFalse(TournamentLiveProjectionPolicy.shouldOpen(state: state(session: "a", status: .ended), isStale: false, hasWindow: false, closedByHandSessions: []))
        // La sesión que el docente cerró a mano no se reabre; una nueva sí.
        XCTAssertFalse(TournamentLiveProjectionPolicy.shouldOpen(state: running, isStale: false, hasWindow: false, closedByHandSessions: ["a"]))
        XCTAssertTrue(TournamentLiveProjectionPolicy.shouldOpen(state: state(session: "b"), isStale: false, hasWindow: false, closedByHandSessions: ["a"]))
    }

    func testCuandoCerrarLaVentana() {
        func action(auto: Bool, state: TournamentLiveState, finished: Bool = false) -> TournamentLiveWindowAction {
            TournamentLiveProjectionPolicy.windowAction(openedAutomatically: auto, windowTournamentID: "t1", state: state, tournamentFinished: finished)
        }
        // Torneo terminado: podio 60 s y luego se cierra.
        XCTAssertEqual(action(auto: true, state: state(status: .ended), finished: true), .closeAfter(60))
        // Sin terminar: se cierra al momento.
        XCTAssertEqual(action(auto: true, state: state(status: .ended), finished: false), .closeNow)
        // Una ventana abierta a mano nunca se cierra sola.
        XCTAssertEqual(action(auto: false, state: state(status: .ended), finished: true), .keepOpen)
        XCTAssertEqual(action(auto: false, state: state(tournament: "t2"), finished: false), .keepOpen)
        // Sesión nueva del mismo torneo durante el podio: manda la nueva (se mantiene).
        XCTAssertEqual(action(auto: true, state: state(session: "nueva", status: .running), finished: true), .keepOpen)
        // Otro torneo toma el canal: la ventana automática del anterior se cierra.
        XCTAssertEqual(action(auto: true, state: state(tournament: "t2"), finished: false), .closeNow)
        XCTAssertTrue(TournamentLiveProjectionPolicy.shouldClose(openedAutomatically: true, windowTournamentID: "t1", state: state(status: .ended), tournamentFinished: false))
        XCTAssertFalse(TournamentLiveProjectionPolicy.shouldClose(openedAutomatically: true, windowTournamentID: "t1", state: state(status: .ended), tournamentFinished: true))
    }

    // MARK: Respuestas del helper

    func testCodigosHTTPYConexion() {
        typealias O = TournamentLivePublishOutcome
        XCTAssertEqual(O.from(statusCode: 200, listeners: 1, error: nil), O(connection: .projecting, nextSendDelay: 5))
        XCTAssertEqual(O.from(statusCode: 200, listeners: 0, error: nil), O(connection: .noProjection, nextSendDelay: 5))
        XCTAssertEqual(O.from(statusCode: 200, listeners: nil, error: nil).connection, .noProjection)
        // Helper antiguo o contraseña distinta: sin proyección y reintento cada 30 s.
        XCTAssertEqual(O.from(statusCode: 404, listeners: nil, error: nil), O(connection: .noProjection, nextSendDelay: 30))
        XCTAssertEqual(O.from(statusCode: 401, listeners: nil, error: nil), O(connection: .noProjection, nextSendDelay: 30))
        XCTAssertEqual(O.from(statusCode: 413, listeners: nil, error: nil).connection, .noProjection)
        // Red caída: latido de 5 s.
        XCTAssertEqual(O.from(statusCode: nil, listeners: nil, error: URLError(.notConnectedToInternet)), O(connection: .noProjection, nextSendDelay: 5))
    }
}
