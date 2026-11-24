import Foundation
import CoreGraphics
import CoreText
import SwiftUI
import MiGestorKit

/// PDF del informe de notas de un alumno (A4, CoreText). Sirve en iPad y en Mac.
/// Lleva «Nota provisional» en la cabecera de todas las páginas.
enum StudentGradeReportPDFRenderer {
    static let pageSize = CGSize(width: 595, height: 842)
    static let margin: CGFloat = 48

    struct Context {
        var className: String
        var subjectName: String
        var periodName: String
        var date: Date = Date()
        var deadlineText: String?
    }

    // MARK: - Documento

    static func buildAttributedReport(
        report: StudentGradeReport,
        narrative: GradeReportNarrative,
        context: Context
    ) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let contentWidth = pageSize.width - margin * 2

        func font(_ size: CGFloat, bold: Bool = false) -> CTFont {
            CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
        }
        func paragraph(spacingBefore: CGFloat = 0, spacingAfter: CGFloat = 4, tabs: [NSTextTab] = [], alignment: NSTextAlignment = .left) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.alignment = alignment
            style.paragraphSpacingBefore = spacingBefore
            style.paragraphSpacing = spacingAfter
            style.lineSpacing = 2
            style.tabStops = tabs
            return style
        }
        let ink = CGColor(gray: 0.1, alpha: 1)
        let secondary = CGColor(gray: 0.4, alpha: 1)
        let accent = CGColor(red: 0.0, green: 0.36, blue: 0.75, alpha: 1)

        func append(_ text: String, size: CGFloat, bold: Bool = false, color: CGColor? = nil, style: NSParagraphStyle) {
            out.append(NSAttributedString(string: text, attributes: [
                .font: font(size, bold: bold),
                .foregroundColor: color ?? ink,
                .paragraphStyle: style,
            ]))
        }
        func sectionTitle(_ text: String) {
            append("\(text.uppercased())\n", size: 9.5, bold: true, color: secondary, style: paragraph(spacingBefore: 18, spacingAfter: 6))
        }

        // Cabecera: nombre y nota final.
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "es_ES")
        dateFormatter.dateFormat = "d 'de' MMMM 'de' yyyy"

        let headTabs = [NSTextTab(textAlignment: .right, location: contentWidth, options: [:])]
        append(report.studentName, size: 20, bold: true, style: paragraph(spacingAfter: 2, tabs: headTabs))
        if let final = report.finalGrade?.doubleValue {
            append("\t\(GradeReportFormat.grade(final))", size: 30, bold: true, style: paragraph(spacingAfter: 2, tabs: headTabs))
        }
        append("\n", size: 8, style: paragraph(spacingAfter: 0))
        let meta = [context.className, context.subjectName].filter { !$0.isEmpty }.joined(separator: " · ")
        append(meta, size: 10.5, color: secondary, style: paragraph(spacingAfter: 0, tabs: headTabs))
        if let level = report.finalLevel {
            append("\t\(level.label)", size: 12, bold: true, color: accent, style: paragraph(spacingAfter: 0, tabs: headTabs))
        }
        append("\n", size: 8, style: paragraph(spacingAfter: 0))
        let period = [context.periodName, dateFormatter.string(from: context.date)].filter { !$0.isEmpty }.joined(separator: " · ")
        append("\(period)\n", size: 10.5, color: secondary, style: paragraph(spacingAfter: 8))

        // Instrumentos.
        sectionTitle("Tus instrumentos")
        let tableTabs = [
            NSTextTab(textAlignment: .right, location: contentWidth - 170, options: [:]),
            NSTextTab(textAlignment: .right, location: contentWidth - 110, options: [:]),
            NSTextTab(textAlignment: .right, location: contentWidth, options: [:]),
        ]
        append("Instrumento\tPeso\tNota\tNivel\n", size: 9, bold: true, color: secondary, style: paragraph(spacingAfter: 4, tabs: tableTabs))
        for instrument in report.instruments {
            let title = instrument.title.count > 48 ? String(instrument.title.prefix(47)) + "…" : instrument.title
            append(
                "\(title)\t\(GradeReportFormat.percent(instrument.weightPercent))\t\(GradeReportFormat.grade(instrument.value))\t\(instrument.level.label)\n",
                size: 11,
                style: paragraph(spacingAfter: instrument.criterionCodes.isEmpty ? 6 : 0, tabs: tableTabs)
            )
            if !instrument.criterionCodes.isEmpty {
                append("\(instrument.criterionCodes.joined(separator: ", "))\n", size: 9, color: secondary, style: paragraph(spacingAfter: 6))
            }
        }
        if !report.pendingTitles.isEmpty {
            append("Aún sin nota: \(report.pendingTitles.joined(separator: ", ")).\n", size: 9.5, color: secondary, style: paragraph(spacingBefore: 2))
        }

        // Rúbricas: nivel real de cada criterio y su descriptor.
        for rubric in report.rubrics {
            sectionTitle("Tu rúbrica: \(rubric.title)")
            let critTabs = [NSTextTab(textAlignment: .right, location: contentWidth, options: [:])]
            for criterion in rubric.criteria {
                let dots = String(repeating: "●", count: Int(criterion.levelPosition))
                    + String(repeating: "○", count: max(0, Int(criterion.levelCount - criterion.levelPosition)))
                append("\(criterion.name)\t\(criterion.levelName)  \(dots)\n", size: 11, bold: true, style: paragraph(spacingBefore: 4, spacingAfter: 2, tabs: critTabs))
                if let description = criterion.levelDescription {
                    append("\(description)\n", size: 10, color: secondary, style: paragraph(spacingAfter: 6))
                }
            }
        }

        // Cálculo explicado (texto fijo de la app).
        if let calculation = GradeReportFormat.calculation(for: report) {
            sectionTitle("Cómo se calcula tu nota")
            append("\(calculation)\n", size: 11, style: paragraph())
        }

        // Textos redactados.
        let origin = narrative.isAI ? "Redactado con ayuda de la IA de Apple y revisado por tu profesor." : nil
        sectionTitle("Lo que haces bien")
        append("\(narrative.strengths)\n", size: 11, style: paragraph())
        sectionTitle("Lo que puedes mejorar")
        append("\(narrative.improvements)\n", size: 11, style: paragraph())

        // Pie.
        var foot = "Estas notas son provisionales. La nota oficial es la que se publique en la plataforma educativa del centro."
        if let deadline = context.deadlineText, !deadline.isEmpty {
            foot += " Si ves un error, responde al correo \(deadline)."
        } else {
            foot += " Si ves un error, responde al correo."
        }
        if let origin { foot += " \(origin)" }
        append("\(foot)\n", size: 9, color: secondary, style: paragraph(spacingBefore: 28))

        return out
    }

    // MARK: - Render

    static func renderPDF(attributedBody: NSAttributedString, headerText: String) -> Data? {
        let data = CFDataCreateMutable(nil, 0)!
        guard let consumer = CGDataConsumer(data: data) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        // Deja sitio arriba para la cabecera «Nota provisional».
        let headerHeight: CGFloat = 24
        let textRect = CGRect(
            x: margin,
            y: margin,
            width: pageSize.width - margin * 2,
            height: pageSize.height - margin * 2 - headerHeight
        )
        let path = CGPath(rect: textRect, transform: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedBody as CFAttributedString)
        let header = NSAttributedString(string: headerText, attributes: [
            .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 8.5, nil),
            .foregroundColor: CGColor(red: 0.72, green: 0.38, blue: 0.0, alpha: 1),
        ])
        let headerLine = CTLineCreateWithAttributedString(header as CFAttributedString)

        var location = 0
        var pageCount = 0
        while location < attributedBody.length && pageCount < 20 {
            context.beginPDFPage(nil)
            context.textPosition = CGPoint(x: margin, y: pageSize.height - margin + 4)
            CTLineDraw(headerLine, context)

            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(location, 0), path, nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()
            if visible.length <= 0 { break }
            location += visible.length
            pageCount += 1
        }
        context.closePDF()
        return data as Data
    }

    /// Nombre de archivo sin espacios ni barras: «Notas_Lucia_Martin.pdf».
    static func fileName(for report: StudentGradeReport, periodName: String) -> String {
        func clean(_ text: String) -> String {
            text.replacingOccurrences(of: "ª", with: "a")
                .replacingOccurrences(of: "º", with: "o")
                .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "es_ES"))
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: "_")
        }
        let period = clean(periodName)
        return "Notas_\(period.isEmpty ? "" : period + "_")\(clean(report.studentName)).pdf"
    }

    /// El PDF completo de un alumno. Lo usan el correo y el guardado en bloque: así son idénticos.
    static func pdfData(
        report: StudentGradeReport,
        narrative: GradeReportNarrative,
        context: Context
    ) -> Data? {
        let body = buildAttributedReport(report: report, narrative: narrative, context: context)
        return renderPDF(attributedBody: body, headerText: "NOTA PROVISIONAL · \(report.studentName.uppercased())")
    }

    /// Escribe el PDF en una carpeta temporal propia y devuelve su URL.
    static func writeTemporaryFile(
        report: StudentGradeReport,
        narrative: GradeReportNarrative,
        context: Context
    ) -> URL? {
        guard let data = pdfData(report: report, narrative: narrative, context: context) else {
            return nil
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("InformesNotas", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(fileName(for: report, periodName: context.periodName))
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
