import PDFKit
import XCTest
import MiGestorKit
@testable import MiGestorKMPMac

/// Informe de notas con datos inventados: nunca con alumnado real.
final class StudentGradeReportPDFRendererTests: XCTestCase {
    private func instrument(_ id: String, _ title: String, value: Double, weight: Double, codes: [String] = []) -> GradeReportInstrument {
        GradeReportInstrument(
            columnId: id,
            title: title,
            value: value,
            weight: weight,
            weightPercent: weight,
            level: GradeLevel.companion.of(score: value),
            criterionCodes: codes
        )
    }

    private func sampleReport(email: String? = "lucia.prueba@example.test") -> StudentGradeReport {
        StudentGradeReport(
            studentId: 1,
            studentName: "Lucía Prueba",
            firstName: "Lucía",
            email: email,
            finalGrade: KotlinDouble(value: 7.5),
            finalLevel: GradeLevel.notable,
            instruments: [
                instrument("a", "Prueba escrita UD1", value: 6.5, weight: 30, codes: ["CE 1.2", "CE 1.3"]),
                instrument("b", "Rúbrica · Expresión corporal", value: 8, weight: 25, codes: ["CE 2.1"]),
                instrument("c", "Prueba física · Resistencia", value: 7, weight: 20),
                instrument("d", "Cuaderno de clase", value: 9, weight: 15),
                instrument("e", "Actitud diaria", value: 8, weight: 10),
            ],
            rubrics: [
                GradeReportRubric(columnId: "b", title: "Rúbrica · Expresión corporal", criteria: [
                    GradeReportRubricCriterion(criterionId: 1, name: "Comunica con el cuerpo", levelName: "Logrado", levelPosition: 3, levelCount: 4, levelDescription: "Usa gestos con intención y el mensaje se entiende."),
                    GradeReportRubricCriterion(criterionId: 2, name: "Trabajo en grupo", levelName: "Excelente", levelPosition: 4, levelCount: 4, levelDescription: nil),
                ]),
            ],
            pendingTitles: []
        )
    }

    private let context = StudentGradeReportPDFRenderer.Context(
        className: "2º ESO Prueba",
        subjectName: "Educación Física",
        periodName: "1ª Evaluación"
    )

    func testRendersA4WithProvisionalHeaderAndKeyData() throws {
        let report = sampleReport()
        let narrative = AppleFoundationGradeReportService.templateNarrative(for: report)
        let body = StudentGradeReportPDFRenderer.buildAttributedReport(report: report, narrative: narrative, context: context)
        let data = try XCTUnwrap(StudentGradeReportPDFRenderer.renderPDF(attributedBody: body, headerText: "NOTA PROVISIONAL · LUCÍA PRUEBA"))
        let document = try XCTUnwrap(PDFDocument(data: data))

        XCTAssertGreaterThanOrEqual(document.pageCount, 1)
        let box = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertEqual(box.width, 595)
        XCTAssertEqual(box.height, 842)

        let text = try XCTUnwrap(document.string)
        for expected in ["NOTA PROVISIONAL", "Lucía Prueba", "7,5", "Notable", "Prueba escrita UD1", "30 %", "CE 1.2, CE 1.3",
                         "Comunica con el cuerpo", "Logrado", "CÓMO SE CALCULA", "LO QUE HACES BIEN", "LO QUE PUEDES MEJORAR",
                         "provisionales"] {
            XCTAssertTrue(text.contains(expected), "Falta «\(expected)» en el PDF")
        }
        for index in 0..<document.pageCount {
            XCTAssertTrue(document.page(at: index)?.string?.contains("NOTA PROVISIONAL") == true, "Página \(index + 1) sin aviso")
        }

        if let output = ProcessInfo.processInfo.environment["GRADE_REPORT_SAMPLE"] {
            try data.write(to: URL(fileURLWithPath: output))
        }
    }

    func testCalculationTextMatchesFinalGrade() {
        let text = GradeReportFormat.calculation(for: sampleReport())
        XCTAssertEqual(text, "Cada instrumento cuenta según su peso. 6,5 × 30 % + 8,0 × 25 % + 7,0 × 20 % + 9,0 × 15 % + 8,0 × 10 % = 7,5.")
    }

    func testTemplateNarrativeUsesBestAndWeakestInstrument() {
        let narrative = AppleFoundationGradeReportService.templateNarrative(for: sampleReport())
        XCTAssertFalse(narrative.isAI)
        XCTAssertTrue(narrative.strengths.contains("Cuaderno de clase (9,0)"))
        XCTAssertTrue(narrative.strengths.contains("«Trabajo en grupo»"))
        XCTAssertTrue(narrative.improvements.contains("Prueba escrita UD1 (6,5)"))
    }

    func testFileNameHasNoAccentsOrSpaces() {
        XCTAssertEqual(
            StudentGradeReportPDFRenderer.fileName(for: sampleReport(), periodName: "1ª Evaluación"),
            "Notas_1a_Evaluacion_Lucia_Prueba.pdf"
        )
    }

    func testPercentFormat() {
        XCTAssertEqual(GradeReportFormat.percent(30), "30 %")
        XCTAssertEqual(GradeReportFormat.percent(33.333), "33,3 %")
    }
}
