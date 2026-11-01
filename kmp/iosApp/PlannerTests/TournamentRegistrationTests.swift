import XCTest
@testable import MiGestorKMPMac

/// Inscripción a torneos por formulario web: nombres de la lista, parejas e importación.
final class TournamentRegistrationTests: XCTestCase {
    /// Generador fijo para que el emparejamiento al azar sea repetible.
    private struct FixedGenerator: RandomNumberGenerator {
        var state: UInt64 = 42
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private func entry(_ id: String, _ partner: String? = nil, participates: Bool = true, team: String? = nil) -> TournamentRegistrationEntry {
        TournamentRegistrationEntry(studentId: id, participates: participates, partnerStudentId: partner, teamName: team)
    }

    private func pair(_ entries: [TournamentRegistrationEntry], roster: [String]) -> TournamentPairingResult {
        var generator = FixedGenerator()
        return TournamentPairing.pair(entries: entries, rosterIds: roster, using: &generator)
    }

    // MARK: Nombres

    func testNombreYPrimerApellido() {
        let labels = TournamentRegistrationNames.optionLabels(for: [("1", "Lucía", "Martín Pérez")])
        XCTAssertEqual(labels["1"], "Lucía Martín")
    }

    func testRepetidosLlevanInicialDelSegundoApellido() {
        let labels = TournamentRegistrationNames.optionLabels(for: [
            ("1", "Ana", "García López"),
            ("2", "Ana", "García Ruiz"),
            ("3", "Bruno", "García López"),
        ])
        XCTAssertEqual(labels["1"], "Ana García L.")
        XCTAssertEqual(labels["2"], "Ana García R.")
        XCTAssertEqual(labels["3"], "Bruno García")
    }

    func testNombresCompletosIgualesSiguenSiendoDistintos() {
        let labels = TournamentRegistrationNames.optionLabels(for: [("1", "Ana", "Gil"), ("2", "Ana", "Gil")])
        XCTAssertEqual(Set(labels.values).count, 2)
    }

    // MARK: Parejas

    func testParejaMutuaSeRespeta() {
        let result = pair([entry("1", "2", team: "Rayos"), entry("2", "1")], roster: ["1", "2"])
        XCTAssertEqual(result.pairs.count, 1)
        XCTAssertTrue(result.pairs[0].isMutual)
        XCTAssertEqual(result.pairs[0].teamName, "Rayos")
        XCTAssertNil(result.leftOver)
    }

    func testEleccionNoMutuaQuedaSueltaYSeEmparejaConOtro() {
        // 1 elige a 2, pero 2 elige a 3 y 3 a 2: 2 y 3 juntos; 1 y 4 los junta la app.
        let result = pair([entry("1", "2"), entry("2", "3"), entry("3", "2"), entry("4")], roster: ["1", "2", "3", "4"])
        XCTAssertEqual(result.pairs.count, 2)
        let mutual = result.pairs.first(where: \.isMutual)
        XCTAssertEqual(Set([mutual?.first, mutual?.second]), Set(["2", "3"]))
        let assigned = result.pairs.first { !$0.isMutual }
        XCTAssertEqual(Set([assigned?.first, assigned?.second]), Set(["1", "4"]))
    }

    func testImparDejaUnoSinPareja() {
        let result = pair([entry("1"), entry("2"), entry("3")], roster: ["1", "2", "3"])
        XCTAssertEqual(result.pairs.count, 1)
        XCTAssertNotNil(result.leftOver)
    }

    func testSinRespuestaYNoParticipanSeSeparan() {
        let result = pair([entry("1", "2"), entry("2", "1"), entry("3", participates: false)], roster: ["1", "2", "3", "4"])
        XCTAssertEqual(result.pairs.count, 1)
        XCTAssertEqual(result.declined, ["3"])
        XCTAssertEqual(result.notResponded, ["4"])
    }

    func testElegidoQueNoParticipaNoCuenta() {
        let result = pair([entry("1", "2"), entry("2", "1", participates: false), entry("3")], roster: ["1", "2", "3"])
        XCTAssertEqual(result.pairs.count, 1)
        XCTAssertFalse(result.pairs[0].isMutual)
    }

    func testAlumnadoDeOtroCursoSeIgnora() {
        let result = pair([entry("1", "9"), entry("9", "1")], roster: ["1", "2"])
        XCTAssertTrue(result.pairs.isEmpty)
        XCTAssertEqual(result.leftOver, "1")
        XCTAssertEqual(result.notResponded, ["2"])
    }

    func testEquiposConNombrePorDefectoYSinRepetidos() {
        let pairs: [TournamentPairingResult.Pair] = [
            .init(first: "1", second: "2", teamName: nil, isMutual: false),
            .init(first: "3", second: "4", teamName: "Rayos", isMutual: true),
            .init(first: "5", second: "6", teamName: "rayos", isMutual: true),
        ]
        let teams = TournamentPairing.teams(from: pairs, names: ["1": "Ana", "2": "Bruno"])
        XCTAssertEqual(teams.map(\.name), ["Ana y Bruno", "Rayos", "rayos 2"])
        XCTAssertEqual(teams[0].studentIDs, ["1", "2"])
    }

    // MARK: Respuestas

    private func registration(formId: String = "F1") -> TournamentRegistration {
        TournamentRegistration(
            formInstanceId: formId,
            privateKeyRef: "llavero://entregas-web/\(formId)",
            expiresAtEpochMs: 0,
            manifestJSON: "{}",
            studentIdByAlias: ["a1": "1", "a2": "2"],
            linkByStudentId: [:],
            itemIdByWebItemId: ["w1": "participa", "w2": "pareja", "w3": "equipo"],
            studentIdByPartnerOption: ["Ana Gil": "1", "Bruno Sol": "2"]
        )
    }

    private func answer(_ itemId: String, _ text: String) -> WebResolvedAnswer {
        WebResolvedAnswer(itemId: itemId, webItemId: "w", title: "", type: .choice, textValue: text, boolValue: nil, numberValue: nil)
    }

    private func draft(formId: String, student: Int64, answers: [WebResolvedAnswer], submission: String = UUID().uuidString) -> WebSubmissionDraft {
        WebSubmissionDraft(
            submissionId: submission, formInstanceId: formId, alias: "a\(student)", studentId: student,
            studentName: nil, classId: 1, columnId: "", clientSubmittedAt: "", answers: answers,
            requiredTotal: 2, requiredAnswered: 2, missingRequiredTitles: []
        )
    }

    func testRespuestaSeTraduce() {
        let result = registration().entry(studentId: 1, answers: [
            answer("participa", TournamentRegistration.yesOption),
            answer("pareja", "Bruno Sol"),
            answer("equipo", "  Rayos "),
        ])
        XCTAssertEqual(result, entry("1", "2", team: "Rayos"))
    }

    func testElegirseASiMismoEsSinPareja() {
        let result = registration().entry(studentId: 1, answers: [
            answer("participa", TournamentRegistration.yesOption),
            answer("pareja", "Ana Gil"),
        ])
        XCTAssertNil(result?.partnerStudentId)
    }

    func testOtroTorneoNoAbsorbeLasEntregas() {
        var torneo2 = registration(formId: "F2")
        let fromTorneo1 = draft(formId: "F1", student: 1, answers: [answer("participa", TournamentRegistration.yesOption)])
        XCTAssertEqual(torneo2.absorb([fromTorneo1]), 0)
        XCTAssertTrue(torneo2.entries.isEmpty)
    }

    func testImportarDosVecesNoDuplica() {
        var form = registration()
        let first = draft(formId: "F1", student: 1, answers: [answer("participa", TournamentRegistration.noOption)], submission: "s1")
        let second = draft(formId: "F1", student: 1, answers: [answer("participa", TournamentRegistration.yesOption)], submission: "s2")
        form.absorb([first])
        form.absorb([first, second])
        XCTAssertEqual(form.entries.count, 1)
        XCTAssertEqual(form.entries["1"]?.participates, true)
        XCTAssertEqual(form.importedSubmissionIds, ["s1", "s2"])
    }

    // MARK: Compatibilidad

    func testTorneoAntiguoSinInscripcionSeSigueLeyendo() throws {
        let plan = TournamentPlan(name: "Viejo", teamCount: 4)
        var columns = try plan.columns()
        XCTAssertFalse(columns.configJSON.contains("registration"))
        columns.configJSON = columns.configJSON.replacingOccurrences(of: "\"registration\":null,", with: "")
        XCTAssertNil(try TournamentPlan(columns: columns).registration)
    }

    func testInscripcionSobreviveAlGuardar() throws {
        var plan = TournamentPlan(name: "Futbolín 1º", teamCount: 2)
        var form = registration()
        form.entries["1"] = entry("1", "2")
        plan.registration = form
        XCTAssertEqual(try TournamentPlan(columns: plan.columns()).registration, form)
    }
}
