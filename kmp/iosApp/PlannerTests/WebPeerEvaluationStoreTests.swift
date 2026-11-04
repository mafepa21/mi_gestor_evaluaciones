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

    // MARK: Pareja elegida: cada partido cuenta aparte

    func testCadaPartidoCuentaAparteYCorregirLoSustituye() {
        var almacen = WebPeerEvaluationStore(fileURL: fichero())
        almacen.record(evaluatorAlias: "A", targetStudentId: 7, round: 1, clientSubmittedAt: "2026-11-02T10:00:00Z", answers: [nota(2)])
        almacen.record(evaluatorAlias: "A", targetStudentId: 7, round: 2, clientSubmittedAt: "2026-11-03T10:00:00Z", answers: [nota(4)])
        // Corregir el partido 2: sustituye, no suma.
        almacen.record(evaluatorAlias: "A", targetStudentId: 7, round: 2, clientSubmittedAt: "2026-11-03T12:00:00Z", answers: [nota(3)])
        let respuestas = almacen.evaluations(for: 7).flatMap(\.answers)
        XCTAssertEqual(respuestas.map(\.numberValue), [2, 3])
        XCTAssertEqual(WebAnswerCombiner.combine(respuestas)?.number, 2.5)
    }

    func testUnFicheroDeAntesSinPartidoSigueCasandoConElPartido1() throws {
        let url = fichero()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let antiguo = """
        {"A|7":{"evaluatorAlias":"A","targetStudentId":7,"clientSubmittedAt":"2026-10-01T10:00:00Z","answers":[{"itemId":"i1","webItemId":"w1","title":"Nota","type":"SCALE_1_4","numberValue":1}]}}
        """
        try Data(antiguo.utf8).write(to: url)
        var almacen = WebPeerEvaluationStore(fileURL: url)
        XCTAssertEqual(almacen.allEvaluations.first?.round, 1)
        almacen.record(evaluatorAlias: "A", targetStudentId: 7, clientSubmittedAt: "2026-10-02T10:00:00Z", answers: [nota(4)])
        XCTAssertEqual(almacen.evaluations(for: 7).map { $0.answers.first?.numberValue }, [4])
    }

    func testLaEntregaSinPartidoEsElPartido1() throws {
        let sin = try JSONDecoder().decode(WebSubmissionPayload.self, from: Data(#"{"schemaVersion":2,"formInstanceId":"f","targets":[]}"#.utf8))
        let con = try JSONDecoder().decode(WebSubmissionPayload.self, from: Data(#"{"schemaVersion":2,"formInstanceId":"f","targets":[],"round":3}"#.utf8))
        XCTAssertNil(sin.round)
        XCTAssertEqual(con.round, 3)
    }

    // MARK: Resultados y correo

    private func manifiesto() throws -> WebFormManifest {
        try JSONDecoder().decode(WebFormManifest.self, from: Data("""
        {"schemaVersion":2,"formInstanceId":"f","title":"Tactics","locale":"en","recipientKey":"x","expiresAt":"2027-01-01T00:00:00Z","mode":"peer",
         "items":[{"webItemId":"w1","type":"SCALE_1_4","title":"Shot placement","required":true},
                  {"webItemId":"w2","type":"SCALE_1_4","title":"Back to base","required":true}]}
        """.utf8))
    }

    private func respuesta(_ web: String, _ valor: Double) -> WebResolvedAnswer {
        WebResolvedAnswer(itemId: web, webItemId: web, title: web, type: .scale1To4, textValue: nil, boolValue: nil, numberValue: valor)
    }

    func testResultadosSinAutoevaluacionYConParejasQueNoCasan() throws {
        let ev = { (de: String, a: Int64, ronda: Int, v1: Double, v2: Double) in
            WebPeerEvaluationStore.Evaluation(evaluatorAlias: de, targetStudentId: a, round: ronda, clientSubmittedAt: "x",
                                              answers: [self.respuesta("w1", v1), self.respuesta("w2", v2)])
        }
        let resultados = WebPeerResults.build(
            title: "Tactics", groupName: "1º BAC",
            manifest: try manifiesto(),
            roster: [.init(id: 1, name: "Alex M.", email: "alex@centro.test"),
                     .init(id: 2, name: "Bea R.", email: nil),
                     .init(id: 3, name: "Carlos P.", email: "carlos@centro.test")],
            evaluations: [ev("aB", 1, 1, 3, 2), ev("aB", 1, 2, 4, 3), ev("aA", 2, 1, 2, 2), ev("aA", 1, 1, 1, 1), ev("aC", 2, 1, 3, 3)],
            studentIdByAlias: ["aA": 1, "aB": 2, "aC": 3]
        )
        let alex = try XCTUnwrap(resultados.rows.first { $0.studentId == 1 })
        // La autoevaluación de Alex (aA -> 1) no cuenta: solo los dos partidos de Bea.
        XCTAssertEqual(alex.evaluationCount, 2)
        XCTAssertEqual(alex.averages, [3.5, 2.5])
        XCTAssertEqual(resultados.evaluationCount, 4)
        XCTAssertEqual(resultados.studentsWhoSent, 3)
        // Carlos evaluó a Bea, pero Bea nunca evaluó a Carlos.
        XCTAssertEqual(resultados.mismatches.map(\.evaluatorName), ["Carlos P."])
        XCTAssertEqual(resultados.mismatches.first?.targetHasNotSent, false)

        let plan = WebPeerResultsMail.plan(results: resultados, selected: [1, 2, 3], signature: "Mario")
        XCTAssertEqual(plan.messages.map(\.studentId), [1])
        XCTAssertEqual(Set(plan.skipped.map(\.studentId)), [2, 3])
        let cuerpo = try XCTUnwrap(plan.messages.first?.body)
        XCTAssertTrue(cuerpo.contains("2 matches"))
        XCTAssertTrue(cuerpo.contains("Shot placement: 3.5"))
        XCTAssertTrue(cuerpo.contains("Next goal: back to base"))
        // Nunca nombra a quien evaluó.
        XCTAssertFalse(cuerpo.contains("Bea"))
    }
}
