import Foundation
import XCTest
@testable import MiGestorKMPMac

/// «Cerrar evaluación»: trimestre de la pestaña, estado de los pasos, recordatorios y fichas.
/// Datos inventados.
final class EvaluationClosingFlowTests: XCTestCase {
    func testTermFromTabTitle() {
        XCTAssertEqual(EvaluationClosingTerm.from(tabTitle: "1.ª Eval"), .first)
        XCTAssertEqual(EvaluationClosingTerm.from(tabTitle: "2ª evaluación"), .second)
        XCTAssertEqual(EvaluationClosingTerm.from(tabTitle: "Tercer trimestre"), .third)
        XCTAssertEqual(EvaluationClosingTerm.from(tabTitle: "Segunda evaluación"), .second)
        XCTAssertNil(EvaluationClosingTerm.from(tabTitle: "Recuperación"))
        XCTAssertNil(EvaluationClosingTerm.from(tabTitle: nil))
        // Los textos coinciden con Informes para compartir «Tu valoración» y el informe anónimo.
        XCTAssertEqual(EvaluationClosingTerm.first.rawValue, "1er Trimestre")
    }

    func testCurrentTermByMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        func date(_ month: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: month, day: 15))! }
        XCTAssertEqual(EvaluationClosingTerm.current(at: date(11), calendar: calendar), .first)
        XCTAssertEqual(EvaluationClosingTerm.current(at: date(2), calendar: calendar), .second)
        XCTAssertEqual(EvaluationClosingTerm.current(at: date(5), calendar: calendar), .third)
    }

    func testStepStatesAlwaysCarryText() {
        XCTAssertEqual(EvaluationClosingSteps.notes(issueCount: 0, hasCountingColumns: true), .done("Listo"))
        XCTAssertEqual(EvaluationClosingSteps.notes(issueCount: 3, hasCountingColumns: true), .attention("3 avisos"))
        XCTAssertEqual(EvaluationClosingSteps.notes(issueCount: 0, hasCountingColumns: false), .pending("Sin columnas que cuenten"))
        XCTAssertEqual(EvaluationClosingSteps.comments(withComment: 24, total: 30), .attention("6 sin comentario"))
        XCTAssertEqual(EvaluationClosingSteps.comments(withComment: 30, total: 30), .done("Listo"))
        var record = EvaluationClosingRecord()
        XCTAssertEqual(EvaluationClosingSteps.excel(record), .pending("Pendiente"))
        record.exportDate = Date()
        record.uploadedDate = Date()
        XCTAssertEqual(EvaluationClosingSteps.excel(record), .done("Generado"))
        XCTAssertEqual(EvaluationClosingSteps.upload(record), .done("Subido"))
    }

    func testRecordIsStoredPerClassAndTab() throws {
        let suite = "evaluation-closing-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var record = EvaluationClosingRecord()
        record.exportSummary = "60 notas y 30 comentarios"
        record.uploadedDate = Date(timeIntervalSince1970: 1_000)
        EvaluationClosingStore.save(record, classId: 7, tabId: "T1", defaults: defaults)
        XCTAssertEqual(EvaluationClosingStore.load(classId: 7, tabId: "T1", defaults: defaults), record)
        XCTAssertEqual(EvaluationClosingStore.load(classId: 7, tabId: "T2", defaults: defaults), EvaluationClosingRecord())
    }

    func testChipsComeFirstFromWhatIsAlreadyRecorded() {
        var input = BulletinBaseStudentInput(studentId: 1, firstName: "Nora", lastName: "Ejemplo")
        input.stamps = [
            BulletinBaseStampCount(title: "Cooperación", count: 3),
            BulletinBaseStampCount(title: "Entrega pendiente", count: 1)
        ]
        input.criterionLevels = [
            BulletinBaseCriterionLevel(criterion: "Resistencia", level: "Avanzado", descriptor: nil, ratio: 1.0),
            BulletinBaseCriterionLevel(criterion: "Velocidad, salida", level: "En progreso", descriptor: nil, ratio: 0.25)
        ]
        input.attendance = BulletinBaseAttendance(present: 8, noMaterial: 2)

        let chips = QuickNoteCatalog.chips(for: input)
        let strength = chips[.strength] ?? []
        let improve = chips[.improve] ?? []
        XCTAssertEqual(strength.first, QuickNoteChip(group: .strength, text: "Cooperación", source: "sello ×3"))
        XCTAssertTrue(strength.contains(QuickNoteChip(group: .strength, text: "Resistencia: avanzado", source: "rúbrica")))
        XCTAssertEqual(improve.first?.text, "Entrega pendiente")
        // Las comas se quitan para no romper el formato de la valoración.
        XCTAssertTrue(improve.contains { $0.text == "Velocidad salida: en progreso" })
        XCTAssertTrue(improve.contains(QuickNoteChip(group: .improve, text: "Traer el material de clase", source: "2 días sin material")))
        // Las frases fijas siempre están, sin repetir.
        XCTAssertTrue((chips[.guidance] ?? []).contains { $0.text == "Mantener la constancia" })
        XCTAssertEqual((chips[.guidance] ?? []).filter { $0.text == "Revisar la agenda del material" }.count, 1)
        // Sin datos del alumno, solo las frases fijas.
        XCTAssertEqual(QuickNoteCatalog.chips(for: nil)[.strength]?.allSatisfy { $0.source == nil }, true)
    }

    func testComposerRoundTrip() {
        let selected: [QuickNoteGroup: [String]] = [
            .strength: ["Cooperación", "Constancia"],
            .guidance: ["Mantener la constancia"]
        ]
        let note = QuickNoteComposer.compose(selected: selected, freeText: "  Mejoró mucho en noviembre.  ")
        XCTAssertEqual(note, "Fortaleza: Cooperación, Constancia. Orientación: Mantener la constancia.\nMejoró mucho en noviembre.")
        let parts = QuickNoteComposer.decompose(note)
        XCTAssertEqual(parts.selected, selected)
        XCTAssertEqual(parts.freeText, "Mejoró mucho en noviembre.")
        // Una valoración escrita a mano queda entera como texto libre.
        let manual = QuickNoteComposer.decompose("Buen trimestre. A seguir así.")
        XCTAssertTrue(manual.selected.isEmpty)
        XCTAssertEqual(manual.freeText, "Buen trimestre. A seguir así.")
        XCTAssertEqual(QuickNoteComposer.compose(selected: [:], freeText: ""), "")
    }
}
