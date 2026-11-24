import Foundation
import MiGestorKit
import XCTest
@testable import MiGestorKMPMac

/// Pestaña de evaluación (pesos, nombres) y valorar más rápido (por ficha, copiar, fichas propias).
/// Datos inventados.
@MainActor
final class EvaluationTabQuickNotesTests: XCTestCase {
    private func tab(_ id: String, _ title: String, parent: String? = nil, weight: Double? = nil, order: Int32 = 0) -> NotebookTab {
        let trace = AuditTrace(authorUserId: nil, createdAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: 0),
                               updatedAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: 0),
                               associatedGroupId: nil, deviceId: nil, syncVersion: 0)
        return NotebookTab(id: id, title: title, description: nil, order: order, parentTabId: parent,
                           fixedColumnWidth: nil, trace: trace, weight: weight.map { KotlinDouble(value: $0) })
    }

    func testWeightTextParsesCommaAndRange() {
        XCTAssertEqual(NotebookWeightText.parse("60"), 60)
        XCTAssertEqual(NotebookWeightText.parse("33,3"), 33.3)
        XCTAssertEqual(NotebookWeightText.parse(" 33.3 "), 33.3)
        XCTAssertNil(NotebookWeightText.parse(""))
        XCTAssertNil(NotebookWeightText.parse("120"))
        XCTAssertNil(NotebookWeightText.parse("-5"))
        XCTAssertEqual(NotebookWeightText.format(60), "60")
        XCTAssertEqual(NotebookWeightText.format(100.0 / 3), "33,3")
    }

    func testEvaluationOptionsKeepExistingAndOfferMissing() {
        let tabs = [
            tab("ev1", "1.ª Evaluación"),
            tab("hockey", "Hockey", parent: "ev1", weight: 60),
            tab("asistencia", "Asistencia", order: 1)
        ]
        let options = NotebookEvaluationNaming.options(tabs: tabs)
        XCTAssertEqual(options.map(\.title), ["1.ª Evaluación", "2.ª Evaluación", "3.ª Evaluación", "Ninguna (pestaña suelta)"])
        XCTAssertEqual(options.first?.placement, .existing("ev1"))
        XCTAssertEqual(options[1].placement, .new("2.ª Evaluación"))
        XCTAssertEqual(options.last?.placement, .loose)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let november = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24))!
        XCTAssertEqual(NotebookEvaluationNaming.defaultPlacement(tabs: tabs, date: november), .existing("ev1"))
    }

    func testBlockWeightsFromKotlin() {
        let blocks = [tab("hockey", "Hockey", parent: "ev1", weight: 60), tab("ultimate", "Ultimate", parent: "ev1", weight: 40)]
        let percents = NotebookEvaluation.shared.weightPercents(blocks: blocks)
        XCTAssertEqual(percents["hockey"]?.doubleValue, 60)
        XCTAssertEqual(percents["ultimate"]?.doubleValue, 40)
        XCTAssertEqual(NotebookTabSyncMerge.weight(NSNumber(value: 60.0))?.doubleValue, 60)
        XCTAssertNil(NotebookTabSyncMerge.weight(NSNull()))
    }

    func testOwnChipsGoAfterRecordedAndBeforeFixed() {
        var input = BulletinBaseStudentInput(studentId: 1, firstName: "Nora", lastName: "Ejemplo")
        input.stamps = [BulletinBaseStampCount(title: "Cooperación", count: 2)]
        let chips = QuickNoteCatalog.chips(for: input, custom: [.strength: [(id: "f1", text: "Liderazgo, en el juego.")]])
        let strength = chips[.strength] ?? []
        XCTAssertEqual(strength.first?.text, "Cooperación")
        XCTAssertEqual(strength[1], QuickNoteChip(group: .strength, text: "Liderazgo en el juego", source: nil, phraseId: "f1"))
        XCTAssertEqual(strength[2].text, "Actitud positiva")
    }

    func testGroupChipAddsAndRemovesWithoutTouchingTheRest() async throws {
        let bridge = KmpBridge()
        let container = bridge.container
        let suffix = String(Int64(Date().timeIntervalSince1970 * 1000))
        // Sin cifras: una etiqueta con 1, 2 o 3 se convertiría en T1, T2 o T3 y se mezclaría.
        let letters = String(UUID().uuidString.filter(\.isLetter).prefix(8))
        let term = "Prueba fichas \(letters)"
        let classId = try await container.classesRepository.saveClass(
            id: nil, name: "Grupo prueba fichas \(suffix)", course: 2, description: nil,
            centerId: nil, academicYearId: nil, stageCycleId: nil, subjectId: nil,
            updatedAtEpochMs: 0, deviceId: nil, syncVersion: 0
        ).int64Value
        func addStudent(_ first: String) async throws -> Int64 {
            let id = try await container.studentsRepository.saveStudent(
                id: nil, firstName: first, lastName: "Inventado", email: nil,
                photoPath: nil, isInjured: false, sex: .unspecified, sexSource: .unknown, birthDate: nil,
                updatedAtEpochMs: 0, deviceId: nil, syncVersion: 0
            ).int64Value
            try await container.classesRepository.addStudentToClass(classId: classId, studentId: id)
            return id
        }
        let ana = try await addStudent("Ana")
        let luis = try await addStudent("Luis")
        _ = try await bridge.saveTeacherTermNote(studentId: ana, classId: classId, termLabel: term, text: "Fortaleza: Constancia.\nMejoró mucho.")
        _ = try await bridge.saveTeacherTermNote(studentId: luis, classId: classId, termLabel: term, text: "Fortaleza: Cooperación.")

        let changed = try await bridge.applyQuickNoteChip(
            classId: classId, termLabel: term, group: .strength, text: "Cooperación",
            selectedStudentIds: [ana], allStudentIds: [ana, luis]
        )
        XCTAssertEqual(changed, 2)
        let notes = try await bridge.teacherTermNotes(classId: classId, termLabel: term)
        XCTAssertEqual(notes[ana], "Fortaleza: Constancia, Cooperación.\nMejoró mucho.")
        XCTAssertEqual(notes[luis] ?? "", "")

        // Copiar al trimestre siguiente: no pisa a quien ya tiene, y se puede deshacer.
        let next = "Prueba copia \(letters)"
        _ = try await bridge.saveTeacherTermNote(studentId: luis, classId: classId, termLabel: next, text: "Ya escrita")
        _ = try await bridge.saveTeacherTermNote(studentId: luis, classId: classId, termLabel: term, text: "Fortaleza: Esfuerzo.")
        let undo = try await bridge.copyTeacherTermNotes(classId: classId, fromTerm: term, toTerm: next, studentIds: [ana, luis], replaceExisting: false)
        XCTAssertEqual(undo.map(\.studentId), [ana])
        var copied = try await bridge.teacherTermNotes(classId: classId, termLabel: next)
        XCTAssertEqual(copied[ana], "Fortaleza: Constancia, Cooperación.\nMejoró mucho.")
        XCTAssertEqual(copied[luis], "Ya escrita")
        try await bridge.restoreTeacherTermNotes(classId: classId, termLabel: next, previous: undo)
        copied = try await bridge.teacherTermNotes(classId: classId, termLabel: next)
        XCTAssertEqual(copied[ana] ?? "", "")
    }

    func testOwnPhraseSoftDelete() async throws {
        let bridge = KmpBridge()
        let text = "Ficha de prueba \(UUID().uuidString.prefix(6))"
        let saved = try await bridge.saveQuickNotePhrase(group: .guidance, text: text)
        let phrase = try XCTUnwrap(saved)
        var all = await bridge.quickNotePhrases()
        XCTAssertTrue((all[.guidance] ?? []).contains { $0.id == phrase.id })
        try await bridge.deleteQuickNotePhrase(phrase)
        all = await bridge.quickNotePhrases()
        XCTAssertFalse((all[.guidance] ?? []).contains { $0.id == phrase.id })
        let stored = try await bridge.container.quickNotePhraseRepository.get(id: phrase.id)
        XCTAssertEqual(stored?.isDeleted, true)
    }
}
