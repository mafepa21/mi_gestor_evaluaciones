import Foundation
import CoreGraphics
import CoreText
import SwiftUI
import MiGestorKit

/// Renderizador de informes individuales de rúbricas para familias y alumnado usando CoreText + CoreGraphics.
/// 100% nativo y multiplataforma (iPadOS y macOS Native sin dependencias de UI).
enum RubricFamilyReportPDFRenderer {
    /// A4 vertical a 72 dpi (595 x 842 pt).
    static let pageSize = CGSize(width: 595, height: 842)
    static let margin: CGFloat = 42

    struct CriterionEvaluationItem {
        let criterionName: String
        let weight: Double
        let selectedLevelOrder: Int
        let selectedLevelName: String
        let selectedLevelPoints: Int
        let selectedLevelDescription: String
    }

    struct RenderOptions {
        var schoolName: String = "Centro Educativo"
        var departmentName: String = "Departamento de Educación Física"
        var studentName: String
        var className: String
        var rubricTitle: String
        var score: Double
        var evaluationDate: Date = Date()
        var teacherName: String = "Profesorado de Educación Física"
        var teacherFeedback: String = ""
        var proposalsForImprovement: String = ""
    }

    /// Obtiene la etiqueta y color cualitativo oficial LOMLOE según la puntuación.
    static func qualitativeGrade(for score: Double) -> (text: String, color: CGColor) {
        if score >= 9.0 {
            return ("SOBRESALIENTE", CGColor(red: 0.1, green: 0.55, blue: 0.25, alpha: 1.0))
        } else if score >= 7.0 {
            return ("NOTABLE", CGColor(red: 0.05, green: 0.45, blue: 0.65, alpha: 1.0))
        } else if score >= 6.0 {
            return ("BIEN", CGColor(red: 0.15, green: 0.35, blue: 0.75, alpha: 1.0))
        } else if score >= 5.0 {
            return ("SUFICIENTE", CGColor(red: 0.75, green: 0.45, blue: 0.05, alpha: 1.0))
        } else {
            return ("INSUFICIENTE", CGColor(red: 0.75, green: 0.15, blue: 0.15, alpha: 1.0))
        }
    }

    /// Construye el documento como `NSAttributedString` estructurado.
    static func buildAttributedReport(
        criteriaItems: [CriterionEvaluationItem],
        options: RenderOptions
    ) -> NSAttributedString {
        let fullString = NSMutableAttributedString()

        let pCenter = NSMutableParagraphStyle()
        pCenter.alignment = .center
        pCenter.paragraphSpacing = 3

        let pLeft = NSMutableParagraphStyle()
        pLeft.alignment = .left
        pLeft.paragraphSpacing = 4

        let pLeftSpaced = NSMutableParagraphStyle()
        pLeftSpaced.alignment = .left
        pLeftSpaced.paragraphSpacing = 6
        pLeftSpaced.paragraphSpacingBefore = 8

        // 1. Cabecera Institucional
        let schoolAttrs: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 11, nil),
            .foregroundColor: CGColor(gray: 0.35, alpha: 1.0),
            .paragraphStyle: pCenter
        ]
        fullString.append(NSAttributedString(string: "\(options.schoolName.uppercased())\n", attributes: schoolAttrs))

        let deptAttrs: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica" as CFString, 9.5, nil),
            .foregroundColor: CGColor(gray: 0.45, alpha: 1.0),
            .paragraphStyle: pCenter
        ]
        fullString.append(NSAttributedString(string: "\(options.departmentName.uppercased())\n\n", attributes: deptAttrs))

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 15, nil),
            .foregroundColor: CGColor(red: 0.1, green: 0.25, blue: 0.5, alpha: 1.0),
            .paragraphStyle: pCenter
        ]
        fullString.append(NSAttributedString(string: "INFORME INDIVIDUAL DE EVALUACIÓN MEDIANTE RÚBRICA\n", attributes: titleAttrs))

        let sepAttrs: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica" as CFString, 8, nil),
            .foregroundColor: CGColor(gray: 0.75, alpha: 1.0),
            .paragraphStyle: pCenter
        ]
        fullString.append(NSAttributedString(string: "_____________________________________________________________________________________\n\n", attributes: sepAttrs))

        // 2. Ficha de Datos del Alumno y Evaluación
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "es_ES")
        dateFormatter.dateFormat = "d 'de' MMMM 'de' yyyy"
        let dateStr = dateFormatter.string(from: options.evaluationDate)

        let metaLabelAttrs: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 9.5, nil),
            .foregroundColor: CGColor(gray: 0.2, alpha: 1.0),
            .paragraphStyle: pLeft
        ]
        let metaValAttrs: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica" as CFString, 9.5, nil),
            .foregroundColor: CGColor(gray: 0.25, alpha: 1.0),
            .paragraphStyle: pLeft
        ]

        let row1 = NSMutableAttributedString(string: "Alumno/a: ", attributes: metaLabelAttrs)
        row1.append(NSAttributedString(string: "\(options.studentName)       ", attributes: metaValAttrs))
        row1.append(NSAttributedString(string: "Curso/Grupo: ", attributes: metaLabelAttrs))
        row1.append(NSAttributedString(string: "\(options.className)\n", attributes: metaValAttrs))
        fullString.append(row1)

        let row2 = NSMutableAttributedString(string: "Rúbrica: ", attributes: metaLabelAttrs)
        row2.append(NSAttributedString(string: "\(options.rubricTitle)       ", attributes: metaValAttrs))
        row2.append(NSAttributedString(string: "Fecha: ", attributes: metaLabelAttrs))
        row2.append(NSAttributedString(string: "\(dateStr)\n", attributes: metaValAttrs))
        fullString.append(row2)

        let row3 = NSMutableAttributedString(string: "Docente evaluador: ", attributes: metaLabelAttrs)
        row3.append(NSAttributedString(string: "\(options.teacherName)\n\n", attributes: metaValAttrs))
        fullString.append(row3)

        // 3. Tarjeta de Calificación y Logro Global
        let grade = qualitativeGrade(for: options.score)
        let scoreText = String(format: "CALIFICACIÓN OBTENIDA: %.1f / 10   —   %@\n", options.score, grade.text)
        let scoreAttrs: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 13, nil),
            .foregroundColor: grade.color,
            .paragraphStyle: pCenter
        ]
        fullString.append(NSAttributedString(string: scoreText, attributes: scoreAttrs))

        let miniSepAttrs: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica" as CFString, 7, nil),
            .foregroundColor: CGColor(gray: 0.85, alpha: 1.0),
            .paragraphStyle: pCenter
        ]
        fullString.append(NSAttributedString(string: "------------------------------------------------------------------------------------------------------------------\n\n", attributes: miniSepAttrs))

        // 4. Desglose de Criterios y Descriptores del Nivel Alcanzado
        let secHeaderAttrs: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 11, nil),
            .foregroundColor: CGColor(red: 0.1, green: 0.25, blue: 0.5, alpha: 1.0),
            .paragraphStyle: pLeftSpaced
        ]
        fullString.append(NSAttributedString(string: "DESGLOSE DE CRITERIOS Y DESCRIPTORES ALCANZADOS:\n\n", attributes: secHeaderAttrs))

        for (index, item) in criteriaItems.enumerated() {
            let critHeader = NSMutableAttributedString()
            let critNumAttrs: [NSAttributedString.Key: Any] = [
                .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 10, nil),
                .foregroundColor: CGColor(gray: 0.15, alpha: 1.0),
                .paragraphStyle: pLeft
            ]
            critHeader.append(NSAttributedString(string: "\(index + 1). \(item.criterionName)", attributes: critNumAttrs))

            let weightAttrs: [NSAttributedString.Key: Any] = [
                .font: CTFontCreateWithName("Helvetica" as CFString, 9, nil),
                .foregroundColor: CGColor(gray: 0.45, alpha: 1.0),
                .paragraphStyle: pLeft
            ]
            critHeader.append(NSAttributedString(string: " (Peso: \(String(format: "%.1f", item.weight)))\n", attributes: weightAttrs))
            fullString.append(critHeader)

            // Nivel y Descriptor
            let levelHeaderAttrs: [NSAttributedString.Key: Any] = [
                .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 9.5, nil),
                .foregroundColor: CGColor(red: 0.15, green: 0.4, blue: 0.2, alpha: 1.0),
                .paragraphStyle: pLeft
            ]
            let levelHeader = NSAttributedString(
                string: "   ▸ Nivel Alcanzado: \(item.selectedLevelName) [\(item.selectedLevelPoints) pt(s)]\n",
                attributes: levelHeaderAttrs
            )
            fullString.append(levelHeader)

            let descAttrs: [NSAttributedString.Key: Any] = [
                .font: CTFontCreateWithName("Helvetica" as CFString, 9, nil),
                .foregroundColor: CGColor(gray: 0.3, alpha: 1.0),
                .paragraphStyle: pLeft
            ]
            let descString = NSAttributedString(string: "     \"\(item.selectedLevelDescription)\"\n\n", attributes: descAttrs)
            fullString.append(descString)
        }

        // 5. Observaciones del Docente y Recomendaciones Familiares
        if !options.teacherFeedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let obsHeaderAttrs: [NSAttributedString.Key: Any] = [
                .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 10, nil),
                .foregroundColor: CGColor(red: 0.1, green: 0.25, blue: 0.5, alpha: 1.0),
                .paragraphStyle: pLeftSpaced
            ]
            fullString.append(NSAttributedString(string: "OBSERVACIONES Y LOGROS OBSERVADOS:\n", attributes: obsHeaderAttrs))

            let obsAttrs: [NSAttributedString.Key: Any] = [
                .font: CTFontCreateWithName("Helvetica-Oblique" as CFString, 9.5, nil),
                .foregroundColor: CGColor(gray: 0.25, alpha: 1.0),
                .paragraphStyle: pLeft
            ]
            fullString.append(NSAttributedString(string: "\(options.teacherFeedback)\n\n", attributes: obsAttrs))
        }

        if !options.proposalsForImprovement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let propHeaderAttrs: [NSAttributedString.Key: Any] = [
                .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 10, nil),
                .foregroundColor: CGColor(red: 0.55, green: 0.3, blue: 0.05, alpha: 1.0),
                .paragraphStyle: pLeftSpaced
            ]
            fullString.append(NSAttributedString(string: "RECOMENDACIONES Y PROPUESTAS DE MEJORA:\n", attributes: propHeaderAttrs))

            let propAttrs: [NSAttributedString.Key: Any] = [
                .font: CTFontCreateWithName("Helvetica" as CFString, 9.5, nil),
                .foregroundColor: CGColor(gray: 0.25, alpha: 1.0),
                .paragraphStyle: pLeft
            ]
            fullString.append(NSAttributedString(string: "\(options.proposalsForImprovement)\n\n", attributes: propAttrs))
        }

        // 6. Cuadro de Firmas Oficiales
        let signSpacing = NSMutableParagraphStyle()
        signSpacing.alignment = .center
        signSpacing.paragraphSpacingBefore = 24

        let signLineAttrs: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica" as CFString, 9, nil),
            .foregroundColor: CGColor(gray: 0.4, alpha: 1.0),
            .paragraphStyle: signSpacing
        ]
        let signText = """
        __________________________________                   __________________________________
        Firma del profesor/a evaluador/a                      Recibido y conformidad de la familia
        """
        fullString.append(NSAttributedString(string: "\(signText)\n", attributes: signLineAttrs))

        return fullString
    }

    /// Renderiza el informe paginado en formato PDF.
    static func renderPDF(attributedBody: NSAttributedString) -> Data? {
        let data = CFDataCreateMutable(nil, 0)!
        guard let consumer = CGDataConsumer(data: data) else { return nil }

        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        let textRect = CGRect(
            x: margin,
            y: margin,
            width: pageSize.width - margin * 2,
            height: pageSize.height - margin * 2
        )
        let path = CGPath(rect: textRect, transform: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedBody as CFAttributedString)
        let totalLength = attributedBody.length

        var location = 0
        var pageCount = 0
        let maxPages = 50

        while location < totalLength && pageCount < maxPages {
            context.beginPDFPage(nil)

            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(location, 0), path, nil)
            CTFrameDraw(frame, context)

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()

            if visibleRange.length <= 0 {
                break
            }
            location += visibleRange.length
            pageCount += 1
        }

        context.closePDF()
        return data as Data
    }

    /// Genera el archivo PDF temporal y devuelve su URL para compartir.
    static func writeToTemporaryFile(
        criteriaItems: [CriterionEvaluationItem],
        options: RenderOptions
    ) -> URL? {
        let attributedReport = buildAttributedReport(criteriaItems: criteriaItems, options: options)
        guard let pdfData = renderPDF(attributedBody: attributedReport) else { return nil }

        let safeStudent = options.studentName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let fileName = "Informe_Rubrica_\(safeStudent)_\(UUID().uuidString.prefix(6)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try pdfData.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
