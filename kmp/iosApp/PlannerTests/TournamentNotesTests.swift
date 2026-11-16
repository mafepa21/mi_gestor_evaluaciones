import XCTest
@testable import MiGestorKMPMac

final class TournamentNotesTests: XCTestCase {
    private func makePlan() -> TournamentPlan {
        TournamentPlan(
            name: "Liga de prueba",
            teams: [
                TournamentPlanTeam(id: "1", name: "Rojo", studentIDs: ["10", "11"]),
                TournamentPlanTeam(id: "2", name: "Azul", studentIDs: ["12"])
            ]
        )
    }

    func testNotesSurviveSavingAndLoading() throws {
        var plan = makePlan()
        let note = TournamentNote(
            kind: .resultConflict,
            text: "Rojo dice 5-3 y Azul dice 4-4",
            createdAt: Date(timeIntervalSince1970: 1_000),
            roundNumber: 1,
            venueNumber: 2,
            teams: ["Rojo", "Azul"],
            incidentIds: [7, 8]
        )
        plan.addNote(note)

        let restored = try TournamentPlan(columns: plan.columns())

        XCTAssertEqual(restored.notes, [note])
    }

    func testPlanSavedWithoutNotesLoadsWithoutNotes() throws {
        let plan = makePlan()
        let columns = try plan.columns()

        XCTAssertFalse(columns.configJSON.contains("notes"), "Sin notas no se escribe la clave")
        XCTAssertNil(try TournamentPlan(columns: columns).notes)
    }

    func testConflictIsFoundByRoundAndVenue() {
        var plan = makePlan()
        plan.addNote(TournamentNote(kind: .match, text: "Muy igualado", roundNumber: 1, venueNumber: 1))
        plan.addNote(TournamentNote(kind: .resultConflict, text: "No hay acuerdo", roundNumber: 1, venueNumber: 2))
        plan.addNote(TournamentNote(kind: .student, text: "Juega muy bien", roundNumber: 1, venueNumber: 1, studentID: "10"))

        XCTAssertFalse(plan.hasResultConflict(roundNumber: 1, venueNumber: 1))
        XCTAssertTrue(plan.hasResultConflict(roundNumber: 1, venueNumber: 2))
        XCTAssertEqual(plan.notes(roundNumber: 1, venueNumber: 1).map(\.text), ["Muy igualado"], "Las notas de alumno no son del partido")
        XCTAssertEqual(plan.notes(studentID: "10").map(\.text), ["Juega muy bien"])
    }

    func testNotesAreGroupedByRoundWithLooseOnesLast() {
        var plan = makePlan()
        plan.addNote(TournamentNote(kind: .student, text: "Sin ronda", createdAt: Date(timeIntervalSince1970: 1), studentID: "10"))
        plan.addNote(TournamentNote(kind: .match, text: "R2", createdAt: Date(timeIntervalSince1970: 2), roundNumber: 2, venueNumber: 1))
        plan.addNote(TournamentNote(kind: .match, text: "R1", createdAt: Date(timeIntervalSince1970: 3), roundNumber: 1, venueNumber: 1))

        XCTAssertEqual(plan.notesByRound.map(\.roundNumber), [1, 2, nil])
    }

    func testIncidentIdsAreStoredAndRemovingLastNoteClearsList() {
        var plan = makePlan()
        let note = TournamentNote(kind: .match, text: "Nota", roundNumber: 1, venueNumber: 1)
        plan.addNote(note)
        plan.setIncidentIds([3, 4], forNote: note.id)
        XCTAssertEqual(plan.noteList.first?.incidentIds, [3, 4])

        plan.removeNote(id: note.id)
        XCTAssertNil(plan.notes)
    }

    func testIncidentDetailCarriesContext() {
        let conflict = TournamentNote(kind: .resultConflict, text: "No hay acuerdo", roundNumber: 1, venueNumber: 2, teams: ["Rojo", "Azul"])
        XCTAssertEqual(conflict.incidentDetail, "Conflicto por el resultado (Ronda 1 · Pista 2 · Rojo contra Azul): No hay acuerdo")
        XCTAssertEqual(conflict.incidentSeverity, "medium")

        let student = TournamentNote(kind: .student, text: "Juega muy bien", studentID: "10")
        XCTAssertEqual(student.incidentDetail, "Juega muy bien")
        XCTAssertEqual(student.incidentSeverity, "low")
    }
}
