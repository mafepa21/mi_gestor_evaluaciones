import XCTest
@testable import MiGestorKMPMac

/// Mapeo puro del módulo antiguo de torneos de EF al motor nuevo (sin bridge ni base de datos).
final class LegacyTournamentMigratorTests: XCTestCase {
    private func team(_ name: String, students: [Int64] = [], color: String = "#1E88E5") -> LegacyTournamentTeam {
        LegacyTournamentTeam(id: UUID(), name: name, colorHex: color, studentIds: students)
    }

    private func match(
        phase: String, round: Int, home: String, away: String,
        homeTeam: LegacyTournamentTeam? = nil, awayTeam: LegacyTournamentTeam? = nil,
        score: (Int, Int) = (0, 0), court: String = "", session: Int64? = nil
    ) -> LegacyTournamentMatch {
        LegacyTournamentMatch(
            id: UUID(), phase: phase, round: round, homeLabel: home, awayLabel: away,
            homeTeamId: homeTeam?.id, awayTeamId: awayTeam?.id,
            homeScore: score.0, awayScore: score.1, court: court, linkedSessionId: session
        )
    }

    private func state(
        template: LegacyTournamentTemplate, status: LegacyTournamentStatus = .draft,
        teams: [LegacyTournamentTeam], matches: [LegacyTournamentMatch]
    ) -> LegacyTournamentState {
        LegacyTournamentState(
            id: UUID(), classId: 7, name: "Torneo de baloncesto", sport: "Baloncesto",
            template: template, status: status, pointsWin: 3, pointsDraw: 1, pointsLoss: 0,
            tieBreaker: "Diferencia de tantos", teams: teams, matches: matches,
            studentProfiles: [LegacyTournamentStudentProfile(id: 10, level: "Fuerte", incompatibleStudentIds: [11])],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testLeagueMapsTeamsRoundsVenuesAndResults() throws {
        let a = team("Rojos", students: [1, 2], color: "#E53935")
        let b = team("Rojos", students: [3])           // nombre repetido
        let c = team("  ")                              // nombre vacío
        let m1 = match(phase: "Liga", round: 1, home: "Rojos", away: "Rojos", homeTeam: a, awayTeam: b, score: (4, 2), court: "Pista 2", session: 55)
        let m2 = match(phase: "Liga", round: 2, home: "Rojos", away: "", homeTeam: a, awayTeam: c)
        let legacy = state(template: .roundRobin, status: .active, teams: [a, b, c], matches: [m1, m2])

        let mapping = LegacyTournamentMapper.map(legacy)
        let plan = mapping.plan

        XCTAssertEqual(plan.id, legacy.id)
        XCTAssertEqual(plan.format, .roundRobin)
        XCTAssertEqual(plan.status, .live)
        XCTAssertEqual(plan.teams.map(\.id), [a.id.uuidString, b.id.uuidString, c.id.uuidString])
        XCTAssertEqual(plan.teams.map(\.name), ["Rojos", "Rojos (2)", "Equipo 3"])
        XCTAssertEqual(plan.teams[0].studentIDs, ["1", "2"])
        XCTAssertTrue(plan.duplicatedTeamNames.isEmpty)
        XCTAssertEqual(mapping.renamedTeams.count, 2)

        XCTAssertEqual(plan.savedSchedule.map(\.number), [1, 2])
        XCTAssertEqual(plan.savedSchedule.map(\.stage), [.league, .league])
        XCTAssertEqual(plan.savedSchedule[0].matches[0].homeTeam, "Rojos")
        XCTAssertEqual(plan.savedSchedule[0].matches[0].awayTeam, "Rojos (2)")
        XCTAssertEqual(plan.savedSchedule[0].matches[0].venueNumber, 2)
        XCTAssertEqual(plan.savedSchedule[1].matches[0].venueNumber, 1)
        XCTAssertEqual(plan.venueCount, 2)

        // Solo el partido con tantos anotados cuenta como jugado.
        XCTAssertEqual(plan.savedResults.count, 1)
        XCTAssertEqual(plan.savedResults[0].matchID, m1.id)
        XCTAssertEqual(plan.savedResults[0].homeTeam, "Rojos")
        XCTAssertEqual(plan.savedResults[0].awayTeam, "Rojos (2)")
        XCTAssertEqual(plan.savedResults[0].homeScore, 4)
        XCTAssertEqual(plan.savedResults[0].awayScore, 2)
        XCTAssertTrue(plan.savedKnockoutResults.isEmpty)

        let extras = try XCTUnwrap(plan.legacyExtras)
        XCTAssertEqual(extras.sport, "Baloncesto")
        XCTAssertEqual([extras.pointsWin, extras.pointsDraw, extras.pointsLoss], [3, 1, 0])
        XCTAssertEqual(extras.tieBreaker, "Diferencia de tantos")
        XCTAssertEqual(extras.teamColorHexByTeamID[a.id.uuidString], "#E53935")
        XCTAssertEqual(extras.linkedSessionIDByMatchID[m1.id.uuidString], 55)
        XCTAssertEqual(extras.studentProfiles.first?.incompatibleStudentIDs, ["11"])
    }

    func testRecordIsCourseOnlyUsesLegacyIdAndRoundTripsThroughColumns() throws {
        let a = team("Azules"), b = team("Verdes")
        let m = match(phase: "Liga", round: 1, home: "Azules", away: "Verdes", homeTeam: a, awayTeam: b, score: (1, 3))
        let legacy = state(template: .roundRobin, status: .closed, teams: [a, b], matches: [m])

        let record = try LegacyTournamentMapper.record(for: LegacyTournamentMapper.map(legacy))

        XCTAssertEqual(record.id, legacy.id.uuidString)
        XCTAssertNil(record.learningSituationId)
        XCTAssertEqual(record.classId, 7)
        XCTAssertEqual(record.format, "roundRobin")
        XCTAssertEqual(record.status, "finished")
        XCTAssertEqual(record.createdAt, legacy.createdAt)

        // El motor lee lo migrado, incluidos los extras opcionales.
        let rebuilt = try TournamentPlan(
            columns: TournamentPlanColumns(
                id: record.id, name: record.name, configJSON: record.configJSON,
                teamSnapshotJSON: record.teamSnapshotJSON, scheduleJSON: record.scheduleJSON,
                resultsJSON: record.resultsJSON, knockoutResultsJSON: record.knockoutResultsJSON
            )
        )
        XCTAssertEqual(rebuilt, LegacyTournamentMapper.map(legacy).plan)
        XCTAssertEqual(rebuilt.legacyExtras?.sport, "Baloncesto")

        // Migrar dos veces da exactamente el mismo registro (mismo id, mismo contenido de equipos y marcadores).
        let again = try LegacyTournamentMapper.record(for: LegacyTournamentMapper.map(legacy))
        XCTAssertEqual(again.id, record.id)
        XCTAssertEqual(again.teamSnapshotJSON, record.teamSnapshotJSON)
        XCTAssertEqual(again.resultsJSON, record.resultsJSON)
        XCTAssertEqual(again.scheduleJSON, record.scheduleJSON)
        XCTAssertEqual(again.configJSON, record.configJSON)
    }

    func testPlansWithoutLegacyExtrasKeepDecodingAsBefore() throws {
        let plan = TournamentPlan(name: "Nuevo", teamCount: 4)
        XCTAssertNil(plan.legacyExtras)
        let json = try plan.configJSON()
        XCTAssertFalse(json.contains("legacyExtras"))
    }

    func testKnockoutDropsByeAndResolvesFinalFromScoredSemis() {
        let a = team("A"), b = team("B"), c = team("C"), d = team("D")
        let m1 = match(phase: "Eliminatoria", round: 1, home: "A", away: "B", homeTeam: a, awayTeam: b, score: (3, 1))
        let m2 = match(phase: "Eliminatoria", round: 2, home: "C", away: "D", homeTeam: c, awayTeam: d, score: (0, 2))
        let final = match(phase: "Final", round: 3, home: "Ganador A", away: "Ganador C", score: (2, 1))
        let bye = match(phase: "Eliminatoria", round: 9, home: "E", away: "BYE", homeTeam: a)
        let legacy = state(template: .knockout, teams: [a, b, c, d], matches: [m1, m2, final, bye])

        let mapping = LegacyTournamentMapper.map(legacy)
        let plan = mapping.plan

        XCTAssertEqual(plan.format, .knockout)
        XCTAssertEqual(mapping.droppedByeMatches, 1)
        XCTAssertEqual(plan.savedSchedule.count, 3)
        XCTAssertTrue(plan.savedSchedule.allSatisfy { $0.stage == .knockout })
        XCTAssertEqual(plan.savedSchedule[2].matches[0].homeTeam, "Ganador P1")
        XCTAssertEqual(plan.savedSchedule[2].matches[0].awayTeam, "Ganador P2")

        XCTAssertEqual(plan.savedKnockoutResults.count, 3)
        let finalResult = plan.savedKnockoutResults.first { $0.matchID == final.id }
        XCTAssertEqual(finalResult?.homeTeam, "A")
        XCTAssertEqual(finalResult?.awayTeam, "D")  // C perdió 0-2: pasa D
        XCTAssertEqual(finalResult?.winner, "A")
        XCTAssertEqual(mapping.droppedResults, 0)
    }

    func testGroupsAndKnockoutTranslatesBracketPlaceholders() {
        let t1 = team("T1"), t2 = team("T2"), t3 = team("T3"), t4 = team("T4")
        let ga = match(phase: "Grupo A", round: 1, home: "T1", away: "T2", homeTeam: t1, awayTeam: t2, score: (2, 0))
        let gb = match(phase: "Grupo B", round: 1, home: "T3", away: "T4", homeTeam: t3, awayTeam: t4)
        let sf1 = match(phase: "Semifinal", round: 1, home: "1A", away: "2B")
        let sf2 = match(phase: "Semifinal", round: 2, home: "1B", away: "2A")
        let final = match(phase: "Final", round: 3, home: "Ganador SF1", away: "Ganador SF2")
        let legacy = state(template: .groupsAndKnockout, status: .draft, teams: [t1, t2, t3, t4], matches: [ga, gb, sf1, sf2, final])

        let mapping = LegacyTournamentMapper.map(legacy)
        let plan = mapping.plan

        XCTAssertEqual(plan.format, .groupStageKnockout)
        XCTAssertEqual(plan.groupCount, 2)
        XCTAssertEqual(plan.status, .scheduled)
        XCTAssertEqual(plan.savedSchedule.map(\.stage), [.groupStage, .groupStage, .knockout, .knockout, .knockout])
        XCTAssertEqual(plan.savedSchedule.map(\.number), [1, 2, 3, 4, 5])
        XCTAssertEqual(plan.savedSchedule[2].matches[0].homeTeam, "Clasificado 1 Grupo A")
        XCTAssertEqual(plan.savedSchedule[2].matches[0].awayTeam, "Clasificado 2 Grupo B")
        XCTAssertEqual(plan.savedSchedule[3].matches[0].homeTeam, "Clasificado 1 Grupo B")
        XCTAssertEqual(plan.savedSchedule[4].matches[0].homeTeam, "Ganador P1")
        XCTAssertEqual(plan.savedSchedule[4].matches[0].awayTeam, "Ganador P2")
        XCTAssertEqual(plan.savedResults.map(\.matchID), [ga.id])
    }

    func testMatchesShareARoundWhenPhaseAndRoundCoincide() {
        let a = team("A"), b = team("B"), c = team("C"), d = team("D")
        let m1 = match(phase: "Liga", round: 1, home: "A", away: "B", homeTeam: a, awayTeam: b, court: "1")
        let m2 = match(phase: "Liga", round: 1, home: "C", away: "D", homeTeam: c, awayTeam: d, court: "Pista 2")
        let m3 = match(phase: "Liga", round: 2, home: "A", away: "C", homeTeam: a, awayTeam: c)
        let plan = LegacyTournamentMapper.map(
            state(template: .roundRobin, teams: [a, b, c, d], matches: [m1, m2, m3])
        ).plan
        XCTAssertEqual(plan.savedSchedule.map { $0.matches.count }, [2, 1])
        XCTAssertEqual(plan.savedSchedule[0].matches.map(\.venueNumber), [1, 2])
        XCTAssertEqual(plan.venueCount, 2)
    }

    func testVenueNumberParsing() {
        XCTAssertEqual(LegacyTournamentMapper.venueNumber(from: "Pista 3"), 3)
        XCTAssertEqual(LegacyTournamentMapper.venueNumber(from: "2"), 2)
        XCTAssertEqual(LegacyTournamentMapper.venueNumber(from: "Pista 12 norte 4"), 12)
        XCTAssertEqual(LegacyTournamentMapper.venueNumber(from: ""), 1)
        XCTAssertEqual(LegacyTournamentMapper.venueNumber(from: "Pabellón"), 1)
        XCTAssertEqual(LegacyTournamentMapper.venueNumber(from: "Pista 0"), 1)
    }

    func testStoreDecodesOldJSONAndSkipsCorruptItems() throws {
        let a = team("A"), b = team("B")
        let good = state(template: .roundRobin, teams: [a, b], matches: [
            match(phase: "Liga", round: 1, home: "A", away: "B", homeTeam: a, awayTeam: b)
        ])
        let goodData = try JSONEncoder().encode(good)
        let goodObject = try JSONSerialization.jsonObject(with: goodData)
        let payload = try JSONSerialization.data(withJSONObject: [goodObject, ["id": "no-es-un-torneo"]])

        let loaded = LegacyTournamentStore.decode(payload)

        XCTAssertEqual(loaded.tournaments.map(\.id), [good.id])
        XCTAssertEqual(loaded.undecodableCount, 1)
        XCTAssertEqual(loaded.tournaments.first?.template, .roundRobin)
        XCTAssertEqual(LegacyTournamentStore.decode(Data("basura".utf8)).tournaments.count, 0)
    }

    func testOldTemplateAndStatusRawValuesAreTheOnesPersistedByTheOldModule() {
        XCTAssertEqual(LegacyTournamentTemplate(rawValue: "Round-robin"), .roundRobin)
        XCTAssertEqual(LegacyTournamentTemplate(rawValue: "Eliminatoria"), .knockout)
        XCTAssertEqual(LegacyTournamentTemplate(rawValue: "Fase de grupos + eliminatoria"), .groupsAndKnockout)
        XCTAssertEqual(LegacyTournamentStatus(rawValue: "Borrador"), .draft)
        XCTAssertEqual(LegacyTournamentStatus(rawValue: "Activo"), .active)
        XCTAssertEqual(LegacyTournamentStatus(rawValue: "Cerrado"), .closed)
        XCTAssertEqual(LegacyTournamentStatus(rawValue: "Archivado"), .archived)
    }
}
