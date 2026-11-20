import XCTest
@testable import MiGestorKMPMac

@MainActor
final class WebPortalTournamentsTests: XCTestCase {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("portal-torneos-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func sampleLeaguePlan(status: TournamentPlanStatus = .live, withResults: Bool = true) throws -> TournamentPlan {
        let teams = [
            TournamentPlanTeam(id: "t1", name: "Ana y Carlos", studentIDs: ["101", "102"]),
            TournamentPlanTeam(id: "t2", name: "Lucía y Marcos", studentIDs: ["103", "104"]),
            TournamentPlanTeam(id: "t3", name: "Sofía y Leo", studentIDs: ["105", "106"]),
            TournamentPlanTeam(id: "t4", name: "Elena y Hugo", studentIDs: ["107", "108"]),
        ]
        var plan = TournamentPlan(
            id: UUID(),
            name: "Torneo de Bádminton",
            startDate: Date(timeIntervalSince1970: 1_763_600_000),
            format: .roundRobin,
            teams: teams,
            groupCount: 0,
            qualifiedTeamsPerGroup: 2,
            venueCount: 2,
            matchDurationMinutes: 8,
            transitionMinutes: 2,
            status: status
        )
        plan.notes = [TournamentNote(
            kind: .resultConflict,
            text: "Discusión privada sobre un punto",
            roundNumber: 1,
            venueNumber: 1,
            teams: ["Ana y Carlos", "Lucía y Marcos"]
        )]
        plan.persistSchedule(try plan.generatedRounds())
        if withResults, let firstRound = plan.savedSchedule.first, let firstMatch = firstRound.matches.first {
            plan.savedResults = [
                MatchResult(
                    matchID: firstMatch.id,
                    homeTeam: firstMatch.homeTeam,
                    awayTeam: firstMatch.awayTeam,
                    homeScore: 15,
                    awayScore: 11
                )
            ]
        }
        return plan
    }

    // MARK: - Ajustes locales

    func testSettingsTodoApagadoPorDefectoYGuardaYRelee() throws {
        let dir = try tempDir()
        let url = dir.appendingPathComponent("torneos-visibles.json")

        let initial = WebPortalTournamentSettings.load(fileURL: url)
        XCTAssertTrue(initial.activeClassIds.isEmpty)
        XCTAssertFalse(initial[5].isVisible(tournamentId: "abc"))
        XCTAssertFalse(initial[5].showsNames(tournamentId: "abc"))
        XCTAssertTrue(initial[5].needsConfirmation(tournamentId: "abc"))
        XCTAssertTrue(initial[5].needsNamesConfirmation(tournamentId: "abc"))

        try WebPortalTournamentSettings.mutate(fileURL: url) { settings in
            settings[5].torneos["abc"] = WebPortalTournamentVisibility(visible: true, mostrarNombres: false)
            settings[5].confirmados.append("abc")
        }

        let reloaded = WebPortalTournamentSettings.load(fileURL: url)
        XCTAssertEqual(reloaded.activeClassIds, [5])
        XCTAssertTrue(reloaded[5].isVisible(tournamentId: "abc"))
        XCTAssertFalse(reloaded[5].showsNames(tournamentId: "abc"))
        XCTAssertFalse(reloaded[5].needsConfirmation(tournamentId: "abc"))
        XCTAssertTrue(reloaded[5].needsNamesConfirmation(tournamentId: "abc"))
    }

    // MARK: - Privacidad y bloque JSON

    func testBloqueSinNombresNoFiltraNombresNiIncidencias() throws {
        let plan = try sampleLeaguePlan()
        let entry = WebPortalTournaments.tournamentEntry(
            id: plan.id.uuidString,
            plan: plan,
            groupName: "2º ESO B",
            studentId: 105, // Equipo 3 (Sofía y Leo)
            showNames: false
        )
        let block = try XCTUnwrap(WebPortalTournaments.torneosBlock(entries: [entry]))
        let data = try JSONSerialization.data(withJSONObject: block, options: [.sortedKeys])
        let jsonText = String(decoding: data, as: UTF8.self)

        // Ningún nombre de equipo, nombre de alumno ni nota de incidencia aparece en claro.
        for forbidden in ["Ana", "Carlos", "Lucía", "Marcos", "Sofía", "Leo", "Elena", "Hugo", "Discusión", "105", "101"] {
            XCTAssertFalse(jsonText.contains(forbidden), "No debe aparecer «\(forbidden)» sin nombres activados")
        }

        let miEquipo = try XCTUnwrap(entry["miEquipo"] as? [String: Any])
        XCTAssertEqual(miEquipo["numero"] as? Int, 3)
        XCTAssertEqual(miEquipo["etiqueta"] as? String, "Equipo 3")

        // Debe tener próximo partido asignado para Equipo 3.
        let prox = try XCTUnwrap(entry["proximoPartido"] as? [String: Any])
        let local = prox["local"] as? String ?? ""
        let visitante = prox["visitante"] as? String ?? ""
        XCTAssertTrue(local == "Equipo 3" || visitante == "Equipo 3")
    }

    func testBloqueConNombresMuestraNombresPeroNuncaIncidenciasNiIds() throws {
        let plan = try sampleLeaguePlan()
        let entry = WebPortalTournaments.tournamentEntry(
            id: plan.id.uuidString,
            plan: plan,
            groupName: "2º ESO B",
            studentId: 105,
            showNames: true
        )
        let miEquipo = try XCTUnwrap(entry["miEquipo"] as? [String: Any])
        XCTAssertEqual(miEquipo["etiqueta"] as? String, "Sofía y Leo")

        let data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
        let jsonText = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(jsonText.contains("Discusión"))
        XCTAssertFalse(jsonText.contains("105"))
    }

    func testAlumnoSinEquipoNoTieneMiEquipoPeroVeElTorneo() throws {
        let plan = try sampleLeaguePlan()
        let entry = WebPortalTournaments.tournamentEntry(
            id: plan.id.uuidString,
            plan: plan,
            groupName: "2º ESO B",
            studentId: 999,
            showNames: false
        )
        XCTAssertNil(entry["miEquipo"])
        XCTAssertNil(entry["proximoPartido"])
        let clasificacion = entry["clasificacion"] as? [[String: Any]] ?? []
        XCTAssertFalse(clasificacion.isEmpty)
        let rondas = entry["rondas"] as? [[String: Any]] ?? []
        XCTAssertFalse(rondas.isEmpty)
    }

    func testTodosLosFormatosConstruyenBloqueValido() throws {
        let teams = (1...8).map { i in
            TournamentPlanTeam(id: "t\(i)", name: "Nombre Secreto \(i)", studentIDs: ["\(200 + i)"])
        }
        for format in TournamentFormat.allCases {
            var plan = TournamentPlan(
                id: UUID(),
                name: "Torneo \(format.title)",
                startDate: Date(timeIntervalSince1970: 1_763_600_000),
                format: format,
                teams: teams,
                groupCount: format == .groupStageKnockout ? 2 : 0,
                qualifiedTeamsPerGroup: 2,
                venueCount: 2,
                matchDurationMinutes: 8,
                transitionMinutes: 2,
                status: .scheduled
            )
            if format == .leaguePlacement {
                plan.totalTimeMinutes = 180
            }
            plan.persistSchedule(try plan.generatedRounds())
            let entry = WebPortalTournaments.tournamentEntry(
                id: plan.id.uuidString,
                plan: plan,
                groupName: "3º ESO A",
                studentId: 201,
                showNames: false
            )
            XCTAssertEqual(entry["formato"] as? String, WebPortalTournaments.formatKey(format))
            XCTAssertNotNil(entry["miEquipo"], "Debe identificar miEquipo en \(format)")
            let data = try? JSONSerialization.data(withJSONObject: entry)
            let text = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            XCTAssertFalse(text.contains("Nombre Secreto"), "Sin nombres no puede filtrarse en \(format)")
        }
    }

    func testTorneoFinalizadoIncluyePodio() throws {
        var plan = try sampleLeaguePlan(status: .finished, withResults: false)
        // Rellenar todos los partidos de liga con victorias claras para t1 > t2 > t3 > t4.
        var results: [MatchResult] = []
        for round in plan.savedSchedule {
            for match in round.matches {
                let homeIdx = plan.teams.firstIndex { $0.name == match.homeTeam } ?? 0
                let awayIdx = plan.teams.firstIndex { $0.name == match.awayTeam } ?? 0
                let homeWins = homeIdx < awayIdx
                results.append(MatchResult(
                    matchID: match.id,
                    homeTeam: match.homeTeam,
                    awayTeam: match.awayTeam,
                    homeScore: homeWins ? 15 : 8,
                    awayScore: homeWins ? 8 : 15
                ))
            }
        }
        plan.savedResults = results
        let entry = WebPortalTournaments.tournamentEntry(
            id: plan.id.uuidString,
            plan: plan,
            groupName: "2º ESO B",
            studentId: 103, // Equipo 2
            showNames: false
        )
        XCTAssertEqual(entry["estado"] as? String, "finalizado")
        let podio = try XCTUnwrap(entry["podio"] as? [[String: Any]])
        XCTAssertEqual(podio.count, 3)
        XCTAssertEqual(podio[0]["equipo"] as? String, "Equipo 1")
        XCTAssertEqual(podio[1]["equipo"] as? String, "Equipo 2")
        XCTAssertEqual(podio[1]["esMio"] as? Bool, true)
    }

    func testDigestIgnoraActualizadoYBuildBoardIncluyeTorneos() throws {
        let plan = try sampleLeaguePlan()
        let entry = WebPortalTournaments.tournamentEntry(
            id: plan.id.uuidString,
            plan: plan,
            groupName: "2º ESO B",
            studentId: 101,
            showNames: false
        )
        let b1 = WebPortalTournaments.torneosBlock(entries: [entry], now: Date(timeIntervalSince1970: 1_700_000_000))
        let b2 = WebPortalTournaments.torneosBlock(entries: [entry], now: Date(timeIntervalSince1970: 1_700_009_000))
        XCTAssertEqual(WebPortalTournaments.digest(of: b1), WebPortalTournaments.digest(of: b2))

        let boardData = try WebPortalPublisher.buildBoard(portalId: "AAECAwQFBgcICQoLDA0ODw", forms: [], torneos: b1)
        let parsed = try XCTUnwrap(try JSONSerialization.jsonObject(with: boardData) as? [String: Any])
        XCTAssertEqual(parsed["schemaVersion"] as? Int, 1)
        XCTAssertNotNil(parsed["torneos"])
    }

    // MARK: - ViewModel (confirmaciones, retirada inmediata e iPad)

    func testViewModelConfirmacionesYRetiradaInmediata() async throws {
        let dir = try tempDir()
        let url = dir.appendingPathComponent("torneos-visibles.json")
        let row = WebPortalTournamentRow(
            id: "tor-1",
            name: "Torneo de Bádminton",
            formatTitle: "Liguilla + puestos",
            status: .live,
            teamCount: 8,
            playedMatches: 6,
            totalMatches: 16,
            hasSchedule: true
        )
        var events: [(Int64, Bool)] = []
        let vm = WebPortalTournamentsViewModel(
            settingsURL: url,
            canEdit: true,
            loadOverview: { id in WebPortalTournamentOverview(classId: id, studentCount: 24, tournaments: [row]) },
            changed: { classId, immediately in events.append((classId, immediately)) }
        )
        await vm.load(classId: 7)
        XCTAssertFalse(vm.isVisible(row))

        // Primera vez encender pide confirmación (.showTournament).
        vm.requestVisible(row, on: true)
        XCTAssertEqual(vm.pendingConfirmation, .showTournament(row))
        XCTAssertFalse(vm.isVisible(row))
        vm.confirmPending()
        XCTAssertTrue(vm.isVisible(row))
        XCTAssertEqual(events.last?.0, 7)
        XCTAssertEqual(events.last?.1, false) // encender espera 2 min

        // Encender nombres de equipo pide confirmación específica (.showNames) y aplica al momento.
        vm.requestShowNames(row, on: true)
        XCTAssertEqual(vm.pendingConfirmation, .showNames(row))
        vm.confirmPending()
        XCTAssertTrue(vm.showsNames(row))
        XCTAssertEqual(events.last?.1, true)

        // Apagar torneo retira al momento y apaga mostrarNombres.
        vm.requestVisible(row, on: false)
        XCTAssertFalse(vm.isVisible(row))
        XCTAssertFalse(vm.showsNames(row))
        XCTAssertEqual(events.last?.1, true)
    }

    func testViewModelEnIPadEsSoloLectura() async throws {
        let dir = try tempDir()
        let url = dir.appendingPathComponent("torneos-visibles.json")
        let row = WebPortalTournamentRow(
            id: "tor-1",
            name: "Torneo",
            formatTitle: "Liga",
            status: .live,
            teamCount: 4,
            playedMatches: 1,
            totalMatches: 6,
            hasSchedule: true
        )
        var called = false
        let vm = WebPortalTournamentsViewModel(
            settingsURL: url,
            canEdit: false,
            loadOverview: { id in WebPortalTournamentOverview(classId: id, studentCount: 20, tournaments: [row]) },
            changed: { _, _ in called = true }
        )
        await vm.load(classId: 1)
        vm.requestVisible(row, on: true)
        XCTAssertNil(vm.pendingConfirmation)
        XCTAssertFalse(vm.isVisible(row))
        XCTAssertFalse(called)
    }

    // MARK: - Cola de 2 minutos y arranque tras reinicio

    func testWatcherUsaEsperaDeDosMinutosYRetiraAlArrancar() async throws {
        let dir = try tempDir()
        let debouncerStateURL = dir.appendingPathComponent("debouncer-state.json")
        let startupStateURL = dir.appendingPathComponent("torneos-publicados.json")
        WebPortalTournamentsPublishedState(conTorneos: [42], pendientes: []).save(fileURL: startupStateURL)

        var recordedWait: TimeInterval?
        var publishedClassIds: [Int64] = []
        let expectation = expectation(description: "startup publish")

        let debouncer = WebPortalGradesDebouncer(
            delay: WebPortalTournamentsWatcher.defaultDelay,
            sleep: { seconds in
                recordedWait = seconds
                try await Task.sleep(nanoseconds: 10_000_000_000)
            },
            fire: { _ in }
        )
        let watcher = WebPortalTournamentsWatcher(debouncer: debouncer, stateURL: debouncerStateURL)
        debouncer.schedule(classId: 99)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(recordedWait, 120)

        let startupWatcher = WebPortalTournamentsWatcher(stateURL: startupStateURL)
        startupWatcher.publish = { classId in
            publishedClassIds.append(classId)
            expectation.fulfill()
            return WebPortalGradesPublishStatus()
        }
        startupWatcher.runStartupPassOnce()
        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(publishedClassIds, [42])
        _ = watcher
    }
}
