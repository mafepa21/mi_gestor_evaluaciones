import PDFKit
import XCTest
import MiGestorKit
@testable import MiGestorKMPMac

/// Guardado en bloque con alumnos inventados: nunca con alumnado real.
final class GradeReportBatchExporterTests: XCTestCase {
    private var parent: URL!

    override func setUpWithError() throws {
        parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("notas-lote-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: parent)
    }

    private func report(id: Int64, first: String, last: String = "Prueba", grade: Double = 7) -> StudentGradeReport {
        StudentGradeReport(
            studentId: id,
            studentName: "\(first) \(last)",
            firstName: first,
            email: nil,
            finalGrade: KotlinDouble(value: grade),
            finalLevel: GradeLevel.companion.of(score: grade),
            instruments: [
                GradeReportInstrument(columnId: "a", title: "Examen", value: grade, weight: 1, weightPercent: 100,
                                      level: GradeLevel.companion.of(score: grade), criterionCodes: []),
            ],
            rubrics: [],
            pendingTitles: []
        )
    }

    private let context = StudentGradeReportPDFRenderer.Context(
        className: "2º ESO Prueba",
        subjectName: "Educación Física",
        periodName: "1ª Evaluación"
    )

    private func items(_ reports: [StudentGradeReport]) -> [GradeReportBatchExporter.Item] {
        reports.map { .init(report: $0, narrative: AppleFoundationGradeReportService.templateNarrative(for: $0)) }
    }

    func testFolderNameJoinsPeriodAndClassWithoutSlashes() {
        XCTAssertEqual(GradeReportBatchExporter.folderName(periodName: "1ª Evaluación", className: "2º ESO B"), "Notas 1ª Evaluación · 2º ESO B")
        XCTAssertEqual(GradeReportBatchExporter.folderName(periodName: "1/2", className: "A:B"), "Notas 1-2 · A-B")
        XCTAssertEqual(GradeReportBatchExporter.folderName(periodName: " ", className: ""), "Notas")
    }

    func testSavesOnePDFPerStudentInANewFolder() throws {
        let result = try GradeReportBatchExporter.export(
            items: items([report(id: 1, first: "Lucía"), report(id: 2, first: "Hugo", grade: 5.5)]),
            context: context,
            into: parent
        )

        XCTAssertEqual(result.folder.lastPathComponent, "Notas 1ª Evaluación · 2º ESO Prueba")
        XCTAssertEqual(result.savedFiles.map(\.lastPathComponent).sorted(), [
            "Notas_1a_Evaluacion_Hugo_Prueba.pdf",
            "Notas_1a_Evaluacion_Lucia_Prueba.pdf",
        ])
        XCTAssertTrue(result.failedNames.isEmpty)
        for url in result.savedFiles {
            let document = try XCTUnwrap(PDFDocument(url: url))
            XCTAssertTrue(document.string?.contains("NOTA PROVISIONAL") == true)
        }
    }

    func testNeverOverwritesAnExistingFolder() throws {
        let first = try GradeReportBatchExporter.export(items: items([report(id: 1, first: "Lucía")]), context: context, into: parent)
        let second = try GradeReportBatchExporter.export(items: items([report(id: 1, first: "Lucía")]), context: context, into: parent)

        XCTAssertNotEqual(first.folder, second.folder)
        XCTAssertEqual(second.folder.lastPathComponent, "Notas 1ª Evaluación · 2º ESO Prueba 2")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.savedFiles[0].path))
    }

    func testStudentsWithTheSameNameGetNumberedFiles() throws {
        let result = try GradeReportBatchExporter.export(
            items: items([report(id: 1, first: "Ana"), report(id: 2, first: "Ana")]),
            context: context,
            into: parent
        )

        XCTAssertEqual(result.savedFiles.map(\.lastPathComponent), [
            "Notas_1a_Evaluacion_Ana_Prueba.pdf",
            "Notas_1a_Evaluacion_Ana_Prueba 2.pdf",
        ])
    }

    func testSavedPDFIsTheSameAsTheMailAttachment() throws {
        let student = report(id: 1, first: "Lucía")
        let narrative = AppleFoundationGradeReportService.templateNarrative(for: student)
        let result = try GradeReportBatchExporter.export(items: [.init(report: student, narrative: narrative)], context: context, into: parent)
        let mailURL = try XCTUnwrap(StudentGradeReportPDFRenderer.writeTemporaryFile(report: student, narrative: narrative, context: context))

        let saved = try XCTUnwrap(PDFDocument(url: result.savedFiles[0])?.string)
        let mail = try XCTUnwrap(PDFDocument(url: mailURL)?.string)
        XCTAssertEqual(saved, mail)
    }
}
