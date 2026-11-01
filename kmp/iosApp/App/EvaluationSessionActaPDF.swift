import CoreGraphics
import CoreText
import Foundation

/// Contenido del acta de la junta, ya preparado para dibujar. Separado del
/// dibujo para poder probarlo sin PDF.
///
/// Nunca lleva datos clínicos: de las medidas de apoyo solo viaja el nivel
/// («Nivel III» / «Nivel IV») y las notas de seguimiento no entran.
struct JuntaActaContent: Equatable {
    struct StudentLine: Equatable {
        let name: String
        let failed: Int
        let level: String
        let agreement: String
    }

    let title: String
    let groupName: String
    let evaluationLabel: String
    let dateText: String
    let attendees: String
    let summaryLines: [String]
    let generalAgreements: String
    let students: [StudentLine]
    /// `true` si las cifras son las congeladas al cerrar; si no, son las de hoy.
    let isFrozen: Bool

    init(board: JuntaBoardUI, groupName: String) {
        let summary = board.summary
        title = "Acta de la sesión de evaluación"
        self.groupName = groupName
        evaluationLabel = board.session.label
        dateText = JuntaFormat.longDate(board.session.dateIso)
        attendees = board.session.attendees.trimmingCharacters(in: .whitespacesAndNewlines)
        summaryLines = [
            "Aprueban todo \(summary.passAllCount) de \(summary.studentCount) alumnos. "
                + "Con 1 o 2 suspensas: \(summary.oneOrTwoFailedCount). "
                + "Con 3 o más: \(summary.threeOrMoreFailedCount).",
            JuntaFormat.ownSubjectLine(summary).replacingOccurrences(of: "En mi materia aprueban", with: "En la materia propia aprueban")
        ]
        generalAgreements = board.session.generalAgreements.trimmingCharacters(in: .whitespacesAndNewlines)
        students = board.students
            .filter { !$0.agreement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.totalFailed > 0 }
            .map {
                StudentLine(
                    name: $0.fullName,
                    failed: $0.totalFailed,
                    level: $0.supportLevel.map(\.displayName) ?? "–",
                    agreement: $0.agreement.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        isFrozen = board.session.isClosed
    }
}

/// Dibuja el acta de la junta en A4 con Core Text + Core Graphics, igual que
/// `PlannerReportPDFRenderer` y `PlannerDaySheetPDFRenderer`: sin AppKit ni
/// UIKit, así que sirve igual en iPad, iPhone y Mac. La tabla de alumnado se
/// pagina sola y repite su cabecera en cada hoja.
enum JuntaActaPDFRenderer {
    static let pageSize = PlannerReportPDFRenderer.pageSize
    static let margin = PlannerReportPDFRenderer.margin

    private static let contentWidth = pageSize.width - margin * 2
    private static let footerReserve: CGFloat = 28
    /// Anchos de columna de la tabla: Alumno, Susp., Medida, Acuerdo.
    private static let columns: [CGFloat] = [130, 42, 72, contentWidth - 130 - 42 - 72]

    static func render(_ content: JuntaActaContent) -> Data? {
        let data = CFDataCreateMutable(nil, 0)!
        guard let consumer = CGDataConsumer(data: data) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        var page = Page(context: context)
        page.begin()

        page.paragraph(content.title, size: 20, bold: true)
        page.space(4)
        page.paragraph("\(content.groupName) · \(content.evaluationLabel) · \(content.dateText)", size: 11, gray: 0.35)
        if !content.attendees.isEmpty {
            page.space(2)
            page.paragraph("Asistentes: \(content.attendees)", size: 11, gray: 0.35)
        }
        if !content.isFrozen {
            page.space(2)
            page.paragraph("Borrador: la junta sigue abierta y las cifras son las de hoy.", size: 10, gray: 0.45)
        }

        page.heading("Resumen")
        content.summaryLines.forEach { page.paragraph($0, size: 11) }

        page.heading("Acuerdos generales")
        page.paragraph(content.generalAgreements.isEmpty ? "Sin acuerdos generales." : content.generalAgreements, size: 11)

        page.heading("Acuerdos por alumno")
        if content.students.isEmpty {
            page.paragraph("Ningún alumno con acuerdo ni suspensas.", size: 11)
        } else {
            page.tableHeader()
            for line in content.students {
                page.tableRow(line)
            }
        }

        page.signatures()
        page.finish()
        context.closePDF()
        return data as Data
    }

    static func writeToTemporaryFile(_ content: JuntaActaContent, suggestedName: String) -> URL? {
        guard let data = render(content) else { return nil }
        let safeName = suggestedName
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName.isEmpty ? "acta-junta" : safeName)-\(UUID().uuidString.prefix(8))")
            .appendingPathExtension("pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: Página

    private struct Page {
        let context: CGContext
        /// Distancia desde el borde superior de la hoja hasta donde toca escribir.
        var top: CGFloat = margin
        var number = 0

        init(context: CGContext) { self.context = context }

        private var bottomLimit: CGFloat { pageSize.height - margin - footerReserve }

        mutating func begin() {
            context.beginPDFPage(nil)
            number += 1
            top = margin
        }

        mutating func newPage(repeatingTable: Bool = false) {
            finish()
            begin()
            if repeatingTable { tableHeader() }
        }

        func finish() {
            let footer = NSAttributedString(
                string: "Documento generado por MiGestor · Página \(number)",
                attributes: attributes(size: 8.5, gray: 0.5)
            )
            draw(footer, x: margin, top: pageSize.height - margin - 10, width: contentWidth, height: 12)
            context.endPDFPage()
        }

        mutating func space(_ points: CGFloat) { top += points }

        mutating func heading(_ text: String) {
            if top + 60 > bottomLimit { newPage() }
            space(16)
            paragraph(text, size: 13, bold: true)
            space(3)
        }

        mutating func paragraph(_ text: String, size: CGFloat, bold: Bool = false, gray: CGFloat = 0.1) {
            let attributed = NSAttributedString(string: text, attributes: attributes(size: size, bold: bold, gray: gray))
            let height = measure(attributed, width: contentWidth)
            if top + height > bottomLimit { newPage() }
            draw(attributed, x: margin, top: top, width: contentWidth, height: height)
            top += height + 3
        }

        mutating func tableHeader() {
            let titles = ["Alumno", "Susp.", "Medida", "Acuerdo"]
            var x = margin
            for (index, title) in titles.enumerated() {
                draw(
                    NSAttributedString(string: title, attributes: attributes(size: 9.5, bold: true, gray: 0.35)),
                    x: x, top: top, width: columns[index] - 6, height: 13
                )
                x += columns[index]
            }
            top += 16
            rule(at: top)
            top += 5
        }

        mutating func tableRow(_ line: JuntaActaContent.StudentLine) {
            let cells = [
                line.name,
                "\(line.failed)",
                line.level,
                line.agreement.isEmpty ? "–" : line.agreement
            ].enumerated().map { index, text in
                NSAttributedString(string: text, attributes: attributes(size: 10.5, bold: index == 0, gray: 0.1))
            }
            let heights = cells.enumerated().map { measure($0.element, width: columns[$0.offset] - 6) }
            let rowHeight = heights.max() ?? 13
            if top + rowHeight > bottomLimit { newPage(repeatingTable: true) }
            var x = margin
            for (index, cell) in cells.enumerated() {
                draw(cell, x: x, top: top, width: columns[index] - 6, height: heights[index])
                x += columns[index]
            }
            top += rowHeight + 6
            rule(at: top - 3, gray: 0.88)
        }

        mutating func signatures() {
            if top + 110 > bottomLimit { newPage() }
            top += 40
            let half = (contentWidth - 40) / 2
            for (index, caption) in ["El/la tutor/a", "Fecha y firma"].enumerated() {
                let x = margin + CGFloat(index) * (half + 40)
                rule(at: top + 34, x: x, width: half, gray: 0.3)
                draw(
                    NSAttributedString(string: caption, attributes: attributes(size: 9.5, gray: 0.35)),
                    x: x, top: top + 38, width: half, height: 13
                )
            }
            top += 56
        }

        // MARK: Dibujo

        private func rule(at top: CGFloat, x: CGFloat = margin, width: CGFloat = contentWidth, gray: CGFloat = 0.6) {
            context.setStrokeColor(CGColor(gray: gray, alpha: 1))
            context.setLineWidth(0.5)
            let y = pageSize.height - top
            context.move(to: CGPoint(x: x, y: y))
            context.addLine(to: CGPoint(x: x + width, y: y))
            context.strokePath()
        }

        private func measure(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
            let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
            let size = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter, CFRangeMake(0, 0), nil,
                CGSize(width: width, height: .greatestFiniteMagnitude), nil
            )
            return ceil(size.height)
        }

        private func draw(_ text: NSAttributedString, x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) {
            let rect = CGRect(x: x, y: pageSize.height - top - height, width: width, height: height + 2)
            let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), CGPath(rect: rect, transform: nil), nil)
            CTFrameDraw(frame, context)
        }
    }

    private static func attributes(size: CGFloat, bold: Bool = false, gray: CGFloat = 0) -> [NSAttributedString.Key: Any] {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        return [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: gray, alpha: 1)
        ]
    }
}
