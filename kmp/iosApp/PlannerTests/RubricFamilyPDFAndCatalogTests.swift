import XCTest
@testable import MiGestorKMPMac
import MiGestorKit

final class RubricFamilyPDFAndCatalogTests: XCTestCase {

    func testRubricTemplateCatalogIntegrity() {
        let templates = RubricTemplateCatalog.templates
        XCTAssertGreaterThanOrEqual(templates.count, 8, "Debe haber al menos 8 plantillas oficiales en el catálogo")

        var seenIds = Set<String>()
        for template in templates {
            XCTAssertFalse(template.id.isEmpty, "El ID de la plantilla no debe estar vacío")
            XCTAssertFalse(seenIds.contains(template.id), "Los IDs de plantillas deben ser únicos: \(template.id)")
            seenIds.insert(template.id)

            XCTAssertFalse(template.title.isEmpty, "El título de la plantilla no debe estar vacío")
            XCTAssertFalse(template.description.isEmpty, "La descripción no debe estar vacía")
            XCTAssertGreaterThanOrEqual(template.criteria.count, 3, "Cada plantilla debe tener al menos 3 criterios")

            for criterion in template.criteria {
                XCTAssertFalse(criterion.name.isEmpty, "El nombre del criterio no debe estar vacío")
                XCTAssertGreaterThan(criterion.weight, 0.0, "El peso del criterio debe ser mayor a 0")
                XCTAssertEqual(criterion.levels.count, 4, "Cada criterio debe tener exactamente 4 niveles LOMLOE")

                for (idx, level) in criterion.levels.enumerated() {
                    XCTAssertEqual(level.order, idx + 1, "El orden del nivel debe coincidir con su posición (1 a 4)")
                    XCTAssertEqual(level.points, idx + 1, "Los puntos del nivel deben coincidir con su orden (1 a 4)")
                    XCTAssertFalse(level.description.isEmpty, "La descripción del nivel no debe estar vacía")
                    XCTAssertTrue(level.name.contains("Nivel \(idx + 1)"), "El nombre debe identificar el Nivel \(idx + 1)")
                }
            }
        }
    }

    func testRubricTemplateCategoryFilters() {
        let templates = RubricTemplateCatalog.templates

        let physicalTemplates = templates.filter { $0.category == .physicalCondition }
        XCTAssertFalse(physicalTemplates.isEmpty)
        XCTAssertTrue(physicalTemplates.contains { $0.id.contains("calentamiento") })

        let sportsTemplates = templates.filter { $0.category == .sportsAndGames }
        XCTAssertFalse(sportsTemplates.isEmpty)
        XCTAssertTrue(sportsTemplates.contains { $0.id.contains("invasion") })

        let expressionTemplates = templates.filter { $0.category == .bodyExpression }
        XCTAssertFalse(expressionTemplates.isEmpty)

        let outdoorTemplates = templates.filter { $0.category == .outdoorNature }
        XCTAssertFalse(outdoorTemplates.isEmpty)

        let transversalTemplates = templates.filter { $0.category == .transversal }
        XCTAssertFalse(transversalTemplates.isEmpty)
        XCTAssertTrue(transversalTemplates.contains { $0.id.contains("coevaluacion") })
    }

    func testQualitativeGradeLOMLOEScale() {
        XCTAssertEqual(RubricFamilyReportPDFRenderer.qualitativeGrade(for: 10.0).text, "SOBRESALIENTE")
        XCTAssertEqual(RubricFamilyReportPDFRenderer.qualitativeGrade(for: 9.0).text, "SOBRESALIENTE")
        XCTAssertEqual(RubricFamilyReportPDFRenderer.qualitativeGrade(for: 8.5).text, "NOTABLE")
        XCTAssertEqual(RubricFamilyReportPDFRenderer.qualitativeGrade(for: 7.0).text, "NOTABLE")
        XCTAssertEqual(RubricFamilyReportPDFRenderer.qualitativeGrade(for: 6.5).text, "BIEN")
        XCTAssertEqual(RubricFamilyReportPDFRenderer.qualitativeGrade(for: 6.0).text, "BIEN")
        XCTAssertEqual(RubricFamilyReportPDFRenderer.qualitativeGrade(for: 5.5).text, "SUFICIENTE")
        XCTAssertEqual(RubricFamilyReportPDFRenderer.qualitativeGrade(for: 5.0).text, "SUFICIENTE")
        XCTAssertEqual(RubricFamilyReportPDFRenderer.qualitativeGrade(for: 4.9).text, "INSUFICIENTE")
        XCTAssertEqual(RubricFamilyReportPDFRenderer.qualitativeGrade(for: 1.0).text, "INSUFICIENTE")
        XCTAssertEqual(RubricFamilyReportPDFRenderer.qualitativeGrade(for: 0.0).text, "INSUFICIENTE")
    }

    func testRubricFamilyReportPDFRendererGeneratesValidAttributedReportAndData() {
        let sampleItems = [
            RubricFamilyReportPDFRenderer.CriterionEvaluationItem(
                criterionName: "Fase de activación y movilidad articular",
                weight: 1.0,
                selectedLevelOrder: 4,
                selectedLevelName: "Nivel 4 (Excelente)",
                selectedLevelPoints: 4,
                selectedLevelDescription: "Dirige con soltura una rutina de movilidad dinámica adaptada a la actividad posterior."
            ),
            RubricFamilyReportPDFRenderer.CriterionEvaluationItem(
                criterionName: "Autonomía y actitud preventiva",
                weight: 1.0,
                selectedLevelOrder: 3,
                selectedLevelName: "Nivel 3 (Avanzado)",
                selectedLevelPoints: 3,
                selectedLevelDescription: "Actúa de forma autónoma con material adecuado y respetando el espacio del resto de compañeros."
            )
        ]

        let options = RubricFamilyReportPDFRenderer.RenderOptions(
            schoolName: "Colegio Sagrado Corazón",
            departmentName: "Departamento de Educación Física",
            studentName: "Laura García Navarro",
            className: "3º ESO B",
            rubricTitle: "Calentamiento General y Específico Autónomo",
            score: 8.8,
            evaluationDate: Date(timeIntervalSince1970: 1789000000),
            teacherName: "Mario Fernández",
            teacherFeedback: "Excelente predisposición motriz y liderazgo en la fase de movilidad.",
            proposalsForImprovement: "Continuar trabajando la constancia en los estiramientos dinámicos posteriores."
        )

        // 1. Construcción de NSAttributedString
        let attributedReport = RubricFamilyReportPDFRenderer.buildAttributedReport(
            criteriaItems: sampleItems,
            options: options
        )

        XCTAssertGreaterThan(attributedReport.length, 200)
        let stringContent = attributedReport.string

        XCTAssertTrue(stringContent.localizedCaseInsensitiveContains("Colegio Sagrado Corazón"))
        XCTAssertTrue(stringContent.contains("INFORME INDIVIDUAL DE EVALUACIÓN MEDIANTE RÚBRICA"))
        XCTAssertTrue(stringContent.contains("Laura García Navarro"))
        XCTAssertTrue(stringContent.contains("3º ESO B"))
        XCTAssertTrue(stringContent.contains("CALIFICACIÓN OBTENIDA: 8.8 / 10"))
        XCTAssertTrue(stringContent.contains("NOTABLE"))
        XCTAssertTrue(stringContent.contains("Fase de activación y movilidad articular"))
        XCTAssertTrue(stringContent.contains("Nivel 4 (Excelente)"))
        XCTAssertTrue(stringContent.contains("Excelente predisposición motriz"))
        XCTAssertTrue(stringContent.contains("Continuar trabajando la constancia"))
        XCTAssertTrue(stringContent.contains("Firma del profesor/a evaluador/a"))
        XCTAssertTrue(stringContent.contains("Recibido y conformidad de la familia"))

        // 2. Renderizado a Data PDF
        let pdfData = RubricFamilyReportPDFRenderer.renderPDF(attributedBody: attributedReport)
        XCTAssertNotNil(pdfData)
        XCTAssertGreaterThan(pdfData?.count ?? 0, 1000)

        // Firma mágica del estándar PDF (%PDF-)
        if let pdfData {
            let magic = String(decoding: pdfData.prefix(5), as: UTF8.self)
            XCTAssertTrue(magic.hasPrefix("%PDF"))
        }

        // 3. Exportación a archivo temporal
        let fileUrl = RubricFamilyReportPDFRenderer.writeToTemporaryFile(
            criteriaItems: sampleItems,
            options: options
        )
        XCTAssertNotNil(fileUrl)
        if let fileUrl {
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileUrl.path))
            try? FileManager.default.removeItem(at: fileUrl)
        }
    }
}
