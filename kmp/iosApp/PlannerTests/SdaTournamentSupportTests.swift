import XCTest
@testable import MiGestorKMPMac

/// Lógica de las pantallas de torneos de la SdA: equipos desde grupos, resultados,
/// eliminatorias dependientes y conversión registro <-> plan.
final class SdaTournamentSupportTests: XCTestCase {
    private func group(_ id: Int64, _ name: String, students: [Int64], classId: Int64 = 1) -> TournamentWorkGroupTeam {
        TournamentWorkGroupTeam(
            groupId: id,
            classId: classId,
            tabId: "tab",
            name: name,
            members: students.map { TournamentTeamMember(studentId: $0, fullName: "Alumno \($0)") }
        )
    }

    private func makePlan(
        format: TournamentFormat,
        teams: Int,
        venues: Int = 2,
        groupCount: Int = 0
    ) throws -> TournamentPlan {
        var plan = TournamentPlan(
            name: "Prueba",
            format: format,
            teamCount: teams,
            groupCount: groupCount,
            venueCount: venues
        )
        let rounds = try TournamentScheduleGenerator.generate(
            format: plan.format,
            teamNames: plan.teamNames,
            venueCount: plan.venueCount,
            groupCount: format == .groupStageKnockout ? plan.groupCount : nil,
            qualifiedTeamsPerGroup: plan.qualifiedTeamsPerGroup
        )
        plan.persistSchedule(rounds)
        return plan
    }

    func testUniqueNamesDisambiguatesRepeatedAndBlankNames() {
        XCTAssertEqual(
            SdaTournamentTeams.uniqueNames(["Linces", "Linces", "Orcas", "Linces", " "]),
            ["Linces", "Linces (2)", "Orcas", "Linces (3)", "Grupo sin nombre"]
        )
    }

    func testPlanTeamsKeepGroupIdAndSortedStudents() {
        let teams = SdaTournamentTeams.planTeams(from: [group(7, "Halcones", students: [9, 3])])
        XCTAssertEqual(teams.first?.id, "7")
        XCTAssertEqual(teams.first?.studentIDs, ["3", "9"])
    }

    func testRecordRoundTripKeepsPlanAndIdentity() throws {
        let plan = try makePlan(format: .roundRobin, teams: 4)
        let record = try TournamentRecord(plan: plan, learningSituationId: 5, classId: 2, tabId: "t")
        XCTAssertEqual(record.id, plan.id.uuidString)
        let decoded = try record.plan()
        XCTAssertEqual(decoded.savedSchedule, plan.savedSchedule)
        XCTAssertEqual(decoded.teams, plan.teams)
        XCTAssertEqual(decoded.status, .scheduled)
    }

    func testLeagueScoreReplaceAndClear() throws {
        var plan = try makePlan(format: .roundRobin, teams: 4)
        let slot = try XCTUnwrap(plan.slots.first)
        plan.setScore(for: slot, home: 2, away: 1)
        XCTAssertEqual(plan.status, .live)
        XCTAssertEqual(plan.savedResults.count, 1)
        plan.setScore(for: slot, home: 0, away: 3)
        XCTAssertEqual(plan.savedResults.count, 1, "Corregir un resultado no duplica el partido")
        XCTAssertEqual(plan.result(for: slot)?.awayScore, 3)
        XCTAssertEqual(plan.completedMatchCount, 1)
        plan.clearScore(for: slot)
        XCTAssertTrue(plan.savedResults.isEmpty)
    }

    func testKnockoutChangingWinnerPrunesDependentResults() throws {
        var plan = try makePlan(format: .knockout, teams: 4, venues: 2)
        let semis = plan.slots.filter { $0.roundNumber == 1 }
        XCTAssertEqual(semis.count, 2)
        plan.setScore(for: semis[0], home: 3, away: 1)
        plan.setScore(for: semis[1], home: 2, away: 0)
        let finalSlot = try XCTUnwrap(plan.slots.first { $0.roundNumber == 2 })
        XCTAssertTrue(plan.canScore(finalSlot), "La final ya tiene a sus dos equipos")
        plan.setScore(for: finalSlot, home: 1, away: 0)
        XCTAssertEqual(plan.champion, finalSlot.match.homeTeam)

        // Cambia el ganador de la primera semifinal: la final deja de ser válida.
        plan.setScore(for: semis[0], home: 0, away: 1)
        XCTAssertTrue(plan.savedKnockoutResults.allSatisfy { $0.matchID != finalSlot.id })
        XCTAssertNil(plan.champion)
    }

    func testKnockoutPlaceholdersCannotBeScored() throws {
        let plan = try makePlan(format: .knockout, teams: 4)
        let finalSlot = try XCTUnwrap(plan.slots.first { $0.roundNumber == 2 })
        XCTAssertFalse(plan.canScore(finalSlot))
    }

    func testGroupStageKnockoutOpensOnlyAfterGroupsFinish() throws {
        var plan = try makePlan(format: .groupStageKnockout, teams: 8, venues: 4, groupCount: 2)
        let knockout = plan.slots.filter { $0.stage == .knockout }
        XCTAssertFalse(knockout.isEmpty)
        XCTAssertFalse(plan.groupStageIsComplete)
        XCTAssertTrue(knockout.allSatisfy { !plan.canScore($0) })
        for slot in plan.slots where slot.stage == .groupStage {
            plan.setScore(for: slot, home: 1, away: 0)
        }
        XCTAssertTrue(plan.groupStageIsComplete)
        let firstKnockout = try XCTUnwrap(plan.slots.first { $0.stage == .knockout })
        XCTAssertTrue(plan.canScore(firstKnockout))
        XCTAssertEqual(plan.groupStandings.count, 2)
    }

    func testChangedGroupsAreDetectedAndTeamsRefreshed() throws {
        let original = [group(1, "Halcones", students: [1, 2]), group(2, "Linces", students: [3]), group(3, "Orcas", students: [4])]
        var plan = TournamentPlan(
            name: "Liga",
            teams: SdaTournamentTeams.planTeams(from: original),
            venueCount: 1
        )
        let rounds = try TournamentScheduleGenerator.generate(format: .roundRobin, teamNames: plan.teamNames, venueCount: 1)
        plan.persistSchedule(rounds)
        XCTAssertFalse(SdaTournamentTeams.hasChanged(snapshot: plan.teams, current: original))

        // Un grupo nuevo no cuenta: puede haberse dejado fuera a propósito.
        XCTAssertFalse(SdaTournamentTeams.hasChanged(snapshot: plan.teams, current: original + [group(9, "Pumas", students: [8])]))

        let edited = [group(1, "Halcones", students: [1, 2, 5]), group(2, "Linces", students: [3]), group(3, "Orcas", students: [4])]
        XCTAssertTrue(SdaTournamentTeams.hasChanged(snapshot: plan.teams, current: edited))
        let renamed = [group(1, "Halcones", students: [1, 2]), group(2, "Linces rojos", students: [3]), group(3, "Orcas", students: [4])]
        XCTAssertTrue(SdaTournamentTeams.hasChanged(snapshot: plan.teams, current: renamed))
        let deleted = [group(1, "Halcones", students: [1, 2]), group(3, "Orcas", students: [4])]
        XCTAssertTrue(SdaTournamentTeams.hasChanged(snapshot: plan.teams, current: deleted))

        plan.setScore(for: try XCTUnwrap(plan.slots.first), home: 1, away: 0)
        try plan.updateTeams(from: edited)
        XCTAssertTrue(plan.savedResults.isEmpty, "Actualizar borra los resultados")
        XCTAssertEqual(plan.savedSchedule.flatMap(\.matches).count, 3)
        XCTAssertEqual(plan.status, .scheduled)
        XCTAssertFalse(SdaTournamentTeams.hasChanged(snapshot: plan.teams, current: edited))
    }

    func testUpdateTeamsWithTooFewGroupsThrowsAndKeepsPlan() throws {
        let original = [group(1, "A", students: [1]), group(2, "B", students: [2])]
        var plan = TournamentPlan(name: "Liga", teams: SdaTournamentTeams.planTeams(from: original), venueCount: 1)
        plan.persistSchedule(try TournamentScheduleGenerator.generate(format: .roundRobin, teamNames: plan.teamNames, venueCount: 1))
        let before = plan
        XCTAssertThrowsError(try plan.updateTeams(from: [original[0]]))
        XCTAssertEqual(plan, before)
    }

    func testExportTextIncludesScheduleAndResults() throws {
        var plan = try makePlan(format: .roundRobin, teams: 4)
        plan.setScore(for: try XCTUnwrap(plan.slots.first), home: 2, away: 1)
        let text = plan.exportText
        XCTAssertTrue(text.contains("Calendario"))
        XCTAssertTrue(text.contains("Resultados"))
        XCTAssertTrue(text.contains("Clasificación"))
    }

    func testTypicalSessionMinutesUsesMostCommonDuration() {
        XCTAssertEqual(
            sdaTypicalSessionMinutes(startEndTimes: [("08:00", "08:55"), ("09:00", "09:55"), ("10:00", "11:00")]),
            55
        )
        XCTAssertNil(sdaTypicalSessionMinutes(startEndTimes: []))
        XCTAssertNil(sdaTypicalSessionMinutes(startEndTimes: [("09:00", "08:00")]))
    }
}
