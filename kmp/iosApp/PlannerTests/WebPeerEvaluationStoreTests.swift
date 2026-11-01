import XCTest
@testable import MiGestorKMPMac

/// Coevaluación por buzón: las evaluaciones llegan en tandas y la media debe incluirlas todas.
final class WebPeerEvaluationStoreTests: XCTestCase {
    private func nota(_ valor: Double) -> WebResolvedAnswer {
        WebResolvedAnswer(itemId: "i1", webItemId: "w1", title: "Nota", type: .scale1To4,
                          textValue: nil, boolValue: nil, numberValue: valor)
    }

    private func fichero() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("coevaluaciones.json")
    }

    func testLaMediaIncluyeLasEvaluacionesDeTandasAnteriores() throws {
        let url = fichero()
        var primera = WebPeerEvaluationStore(fileURL: url)
        primera.record(evaluatorAlias: "A", targetStudentId: 7, clientSubmittedAt: "2026-10-24T10:00:00Z", answers: [nota(2)])
        primera.record(evaluatorAlias: "B", targetStudentId: 7, clientSubmittedAt: "2026-10-24T10:01:00Z", answers: [nota(4)])
        try primera.save()

        // Segunda recogida, más tarde: se vuelve a leer del disco.
        var segunda = WebPeerEvaluationStore(fileURL: url)
        segunda.record(evaluatorAlias: "C", targetStudentId: 7, clientSubmittedAt: "2026-10-24T11:00:00Z", answers: [nota(3)])
        let respuestas = segunda.evaluations(for: 7).flatMap(\.answers)
        XCTAssertEqual(respuestas.count, 3)
        XCTAssertEqual(WebAnswerCombiner.combine(respuestas)?.number, 3)
    }

    func testUnReenvioSustituyeAlAnteriorYNoVotaDosVeces() {
        var almacen = WebPeerEvaluationStore(fileURL: fichero())
        almacen.record(evaluatorAlias: "A", targetStudentId: 7, clientSubmittedAt: "2026-10-24T10:00:00Z", answers: [nota(1)])
        almacen.record(evaluatorAlias: "A", targetStudentId: 7, clientSubmittedAt: "2026-10-24T12:00:00Z", answers: [nota(4)])
        // Una copia antigua que llega tarde no pisa la nueva.
        almacen.record(evaluatorAlias: "A", targetStudentId: 7, clientSubmittedAt: "2026-10-24T11:00:00Z", answers: [nota(2)])
        let respuestas = almacen.evaluations(for: 7).flatMap(\.answers)
        XCTAssertEqual(respuestas.map(\.numberValue), [4])
    }

    func testSoloCuentanLasEvaluacionesDeEseAlumno() {
        var almacen = WebPeerEvaluationStore(fileURL: fichero())
        almacen.record(evaluatorAlias: "A", targetStudentId: 7, clientSubmittedAt: "x", answers: [nota(1)])
        almacen.record(evaluatorAlias: "A", targetStudentId: 8, clientSubmittedAt: "x", answers: [nota(4)])
        XCTAssertEqual(almacen.evaluations(for: 7).count, 1)
    }

    func testCombinador() {
        let si = WebResolvedAnswer(itemId: "c", webItemId: "c", title: "", type: .check, textValue: nil, boolValue: true, numberValue: nil)
        let no = WebResolvedAnswer(itemId: "c", webItemId: "c", title: "", type: .check, textValue: nil, boolValue: false, numberValue: nil)
        XCTAssertEqual(WebAnswerCombiner.combine([si, si, no])?.bool, true)
        XCTAssertEqual(WebAnswerCombiner.combine([si, no])?.bool, false)
        XCTAssertEqual(WebAnswerCombiner.combine([nota(2), nota(3)])?.text, "2.50")
        let texto = { (t: String) in WebResolvedAnswer(itemId: "t", webItemId: "t", title: "", type: .text, textValue: t, boolValue: nil, numberValue: nil) }
        XCTAssertEqual(WebAnswerCombiner.combine([texto("Bien"), texto(" "), texto("Mejor")])?.text, "Bien\nMejor")
        XCTAssertNil(WebAnswerCombiner.combine([]))
    }

    // MARK: Reparto de lo recogido del buzón

    private func borrador(_ submissionId: String, studentId: Int64?) -> WebSubmissionDraft {
        WebSubmissionDraft(
            submissionId: submissionId, formInstanceId: "F", alias: "A", studentId: studentId, studentName: nil,
            classId: 1, columnId: "col", clientSubmittedAt: "x", answers: [nota(3)],
            requiredTotal: 1, requiredAnswered: 1, missingRequiredTitles: [],
            targetAlias: submissionId.contains("#") ? "T" : nil, isPeerEvaluation: submissionId.contains("#")
        )
    }

    func testRepartoImportaLoQueTieneDuenoYBorraSoloEnviosCompletos() {
        var vista = WebSubmissionImportPreview()
        vista.drafts = [
            borrador("s1", studentId: 1),
            borrador("s2#t1", studentId: 2),
            borrador("s2#t2", studentId: 3),
            borrador("s3#t1", studentId: 2),
            borrador("s3#t2", studentId: nil),
        ]
        let reparto = WebSubmissionInboxTriage.triage(vista)
        XCTAssertEqual(reparto.decisions.count, 4)
        XCTAssertEqual(reparto.deletable, ["s1", "s2"])
        XCTAssertEqual(reparto.pending, 1)
    }
}
