import CoreGraphics
import XCTest
@testable import MiGestorKMPMac

/// Reglas de proyección de la junta: formato de la Media, filtro, resumen local.
final class JuntaProjectionTests: XCTestCase {
    private func row(
        _ id: Int64,
        average: Double?,
        other: Int = 0,
        reviewed: Bool = false
    ) -> JuntaStudentRowUI {
        JuntaStudentRowUI(
            studentId: id, firstName: "Alumno", lastName: "Prueba \(id)",
            average: average, absencePercent: 12, absenceCount: 3,
            supportLevel: nil, incidentCount: 0,
            otherFailedCount: other, agreement: "", isReviewed: reviewed, isFrozen: false
        )
    }

    func testMediaUnDecimalConComa() {
        XCTAssertEqual(JuntaFormat.average(6.8), "6,8")
        XCTAssertEqual(JuntaFormat.average(5.0), "5,0")
        XCTAssertEqual(JuntaFormat.average(nil), "–")
    }

    func testMediaCercaDeCincoNuncaSeLeeCinco() {
        XCTAssertEqual(JuntaFormat.average(4.96), "4,96")
        XCTAssertEqual(JuntaFormat.average(4.95), "4,95")
        XCTAssertEqual(JuntaFormat.average(4.999), "4,99")
        XCTAssertEqual(JuntaFormat.average(4.94), "4,9")
    }

    func testTotalSumaOtrasYLaPropiaSiSuspende() {
        XCTAssertEqual(row(1, average: 4.2, other: 2).totalFailed, 3)
        XCTAssertEqual(row(2, average: 4.99, other: 0).totalFailed, 1)
        XCTAssertEqual(row(3, average: 5.0, other: 1).totalFailed, 1)
        XCTAssertEqual(row(4, average: nil, other: 1).totalFailed, 1)
    }

    func testResumenYFiltros() {
        let rows = [
            row(1, average: 6.8, reviewed: true),
            row(2, average: 4.2, other: 2),
            row(3, average: 7.5, other: 1),
            row(4, average: 5.0),
        ]
        let summary = JuntaRules.summary(of: rows)
        XCTAssertEqual(summary.studentCount, 4)
        XCTAssertEqual(summary.passAllCount, 2)
        XCTAssertEqual(summary.oneOrTwoFailedCount, 1)
        XCTAssertEqual(summary.threeOrMoreFailedCount, 1)
        XCTAssertEqual(summary.passedOwnSubjectCount, 3)
        XCTAssertEqual(summary.reviewedCount, 1)
        XCTAssertEqual(JuntaFormat.headline(summary), "2 de 4 aprueban todo")
        XCTAssertEqual(rows.filter(JuntaFilter.failing.matches).map(\.studentId), [2, 3])
        XCTAssertEqual(rows.filter(JuntaFilter.unreviewed.matches).map(\.studentId), [2, 3, 4])
    }

    func testSiguienteAlumno() {
        let rows = [row(1, average: 6), row(2, average: 6), row(3, average: 6)]
        XCTAssertEqual(JuntaRules.nextStudentId(after: 1, in: rows), 2)
        XCTAssertNil(JuntaRules.nextStudentId(after: 3, in: rows))
        XCTAssertEqual(JuntaRules.nextStudentId(after: nil, in: rows), 1)
    }

    func testFechaIsoYTexto() {
        XCTAssertEqual(JuntaFormat.longDate("2026-12-15"), "15 de diciembre de 2026")
        XCTAssertEqual(JuntaFormat.dayMonth("2026-12-15"), "15 de diciembre")
        XCTAssertEqual(JuntaFormat.isoDate(JuntaFormat.parseDate("2026-12-15")!), "2026-12-15")
    }

    // MARK: Acta

    private func board(closed: Bool = true) -> JuntaBoardUI {
        var ana = row(1, average: 6.8)
        ana.agreement = ""
        var luis = JuntaStudentRowUI(
            studentId: 2, firstName: "Luis", lastName: "Gil", average: 4.2, absencePercent: 12, absenceCount: 3,
            supportLevel: .iii, incidentCount: 2, otherFailedCount: 2,
            agreement: "Plan de refuerzo en Matemáticas.", isReviewed: true, isFrozen: closed
        )
        luis.agreement = "Plan de refuerzo en Matemáticas."
        let lucia = row(3, average: 7.5, other: 1)
        let students = [ana, luis, lucia]
        let session = JuntaSessionUI(
            id: "s1", classId: 1, kind: .first, label: "1ª evaluación", dateIso: "2026-12-15",
            attendees: "Equipo docente", generalAgreements: "Reforzar hábitos.",
            isClosed: closed, closedAtEpochMs: nil, plannerEvaluationPeriodId: nil
        )
        return JuntaBoardUI(session: session, students: students, summary: JuntaRules.summary(of: students))
    }

    func testActaSoloIncluyeAlumnadoConAcuerdoOSuspensasYSoloElNivel() {
        let content = JuntaActaContent(board: board(), groupName: "2º ESO B")
        XCTAssertEqual(content.students.map(\.name), ["Luis Gil", "Alumno Prueba 3"])
        XCTAssertEqual(content.students.first?.level, "Nivel III")
        XCTAssertEqual(content.students.first?.failed, 3)
        XCTAssertEqual(content.students.last?.level, "–")
        XCTAssertEqual(content.dateText, "15 de diciembre de 2026")
        XCTAssertTrue(content.isFrozen)
    }

    func testActaSeRenderizaComoPDFDeUnaOMasPaginas() throws {
        let content = JuntaActaContent(board: board(), groupName: "2º ESO B")
        let data = try XCTUnwrap(JuntaActaPDFRenderer.render(content))
        let document = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        XCTAssertGreaterThanOrEqual(document.numberOfPages, 1)
        if let output = ProcessInfo.processInfo.environment["JUNTA_ACTA_SAMPLE"] {
            try data.write(to: URL(fileURLWithPath: output))
        }

        // Un grupo grande pagina la tabla sin perder filas.
        let many = (1...120).map { row(Int64($0), average: 3.0, other: 1) }
        var big = board()
        big.students = many
        big.summary = JuntaRules.summary(of: many)
        let bigData = try XCTUnwrap(JuntaActaPDFRenderer.render(JuntaActaContent(board: big, groupName: "Grupo grande")))
        let bigDocument = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: bigData as CFData)!))
        XCTAssertGreaterThan(bigDocument.numberOfPages, 1)
    }
}
