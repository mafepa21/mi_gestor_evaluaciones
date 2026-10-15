import XCTest
@testable import MiGestorKMPMac

/// Lógica pura de la pantalla «Torneos»: agrupar por situación, resumen de fila y selector de situación.
final class SdaTournamentsOverviewTests: XCTestCase {
    private func makePlan(name: String, format: TournamentFormat = .roundRobin, teams: Int = 4) throws -> TournamentPlan {
        var plan = TournamentPlan(name: name, format: format, teamCount: teams, venueCount: 1)
        let rounds = try TournamentScheduleGenerator.generate(
            format: plan.format,
            teamNames: plan.teamNames,
            venueCount: plan.venueCount,
            groupCount: nil,
            qualifiedTeamsPerGroup: plan.qualifiedTeamsPerGroup
        )
        plan.persistSchedule(rounds)
        return plan
    }

    private func record(_ name: String, situation: Int64?, format: TournamentFormat = .roundRobin) throws -> TournamentRecord {
        try TournamentRecord(plan: makePlan(name: name, format: format), learningSituationId: situation, classId: 1, tabId: nil)
    }

    func testSummaryShowsFormatTeamsAndProgress() throws {
        var plan = try makePlan(name: "Liga")
        XCTAssertEqual(SdaTournamentsOverview.summary(of: plan), "Liga · 4 equipos · 0 de 6")
        let slot = try XCTUnwrap(plan.slots.first)
        plan.setScore(for: slot, home: 1, away: 0)
        XCTAssertEqual(SdaTournamentsOverview.summary(of: plan), "Liga · 4 equipos · 1 de 6")
    }

    func testSectionsFollowSituationOrderAndPutWithoutSituationLast() throws {
        let records = [
            try record("Copa", situation: 20),
            try record("Antiguo", situation: nil),
            try record("Torneo 1", situation: 10),
            try record("Torneo 2", situation: 10)
        ]
        let sections = SdaTournamentsOverview.sections(
            records: records,
            situations: [(id: 10, title: "SA 1 · Building Health"), (id: 20, title: "SA 2 · Bádminton"), (id: 30, title: "SA 3 · Vacía")]
        )
        XCTAssertEqual(sections.map(\.title), ["SA 1 · Building Health", "SA 2 · Bádminton", "Sin situación"])
        XCTAssertEqual(sections[0].items.map(\.name), ["Torneo 1", "Torneo 2"])
        XCTAssertNil(sections[2].situationId)
        XCTAssertEqual(sections[2].id, SdaTournamentListSection.withoutSituationId)
    }

    func testSituationMissingFromListStillShowsBeforeWithoutSituation() throws {
        let sections = SdaTournamentsOverview.sections(
            records: [try record("Huérfano", situation: 99), try record("Antiguo", situation: nil)],
            situations: []
        )
        XCTAssertEqual(sections.map(\.title), ["Situación", "Sin situación"])
    }

    func testNoRecordsMeansNoSections() {
        XCTAssertTrue(SdaTournamentsOverview.sections(records: [], situations: [(id: 1, title: "SA")]).isEmpty)
    }

    func testUnreadableRecordKeepsRowWithWarning() throws {
        var broken = try record("Roto", situation: nil)
        broken.scheduleJSON = "{no es json"
        let item = SdaTournamentsOverview.item(for: broken)
        XCTAssertNil(item.status)
        XCTAssertEqual(item.summary, SdaTournamentsOverview.unreadableSummary)
    }

    func testSituationChoicesNeedTwoGroups() {
        let choices = SdaTournamentsOverview.situationChoices(
            situations: [(id: 1, title: "SA 1"), (id: 2, title: "SA 2"), (id: 3, title: "SA 3")],
            groupCountBySituation: [1: 4, 2: 1]
        )
        XCTAssertEqual(choices.map(\.isAvailable), [true, false, false])
        XCTAssertEqual(choices.map(\.detailText), ["4 grupos", "1 grupo (hacen falta 2)", "Sin grupos"])
    }
}
