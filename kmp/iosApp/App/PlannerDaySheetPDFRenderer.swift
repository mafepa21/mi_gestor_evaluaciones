import CoreGraphics
import CoreText
import Foundation
import MiGestorKit

/// Esquema corto de una sesión para la hoja del día.
struct PlannerDaySheetEntry: Equatable {
    struct Step: Equatable {
        let minutes: Int?
        let title: String
    }

    let time: String
    let group: String
    let title: String
    let objective: String
    let steps: [Step]
    let materials: [String]
    let attention: [String]

    static let maxSteps = 14
    static let maxListItems = 4

    /// Usa el guion del plan si existe; si no, el texto libre de la sesión.
    init(session: PlanningSession, plan: LearningSituationSessionPlan?, timeLabel: String) {
        self.time = timeLabel
        self.group = session.groupName
        let unit = session.teachingUnitName.trimmingCharacters(in: .whitespacesAndNewlines)
        let planTitle = plan?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.title = planTitle.isEmpty ? (unit.isEmpty ? "Sesión sin título" : unit) : planTitle

        guard let plan else {
            self.objective = session.objectives.trimmingCharacters(in: .whitespacesAndNewlines)
            self.steps = session.activities
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(Self.maxSteps)
                .map { Step(minutes: nil, title: $0) }
            self.materials = []
            self.attention = []
            return
        }

        let projection = PlannerSessionDetailProjection(plan: plan)
        self.objective = projection.reviewObjective
        self.steps = projection.guideBlocks
            .flatMap(\.steps)
            .filter { !$0.isCollection }
            .prefix(Self.maxSteps)
            .map { Step(minutes: $0.minutes, title: $0.title) }
        let materials = projection.materials.isEmpty ? projection.setupBullets : projection.materials
        self.materials = Array(materials.prefix(Self.maxListItems))
        self.attention = Array(projection.attentionNotes.prefix(Self.maxListItems))
    }

    init(time: String, group: String, title: String, objective: String, steps: [Step], materials: [String], attention: [String]) {
        self.time = time
        self.group = group
        self.title = title
        self.objective = objective
        self.steps = steps
        self.materials = materials
        self.attention = attention
    }
}

/// Hoja A3 apaisada con tres sesiones por página, para imprimir y llevar a clase.
/// Core Text + Core Graphics puro, igual que `PlannerReportPDFRenderer`.
enum PlannerDaySheetPDFRenderer {
    /// A3 apaisado a 72 dpi.
    static let pageSize = CGSize(width: 1191, height: 842)
    static let columnsPerPage = 3
    static let margin: CGFloat = 24
    static let gutter: CGFloat = 16
    static let notesHeight: CGFloat = 120

    /// Reparte las sesiones en páginas de tres.
    static func pages(for entries: [PlannerDaySheetEntry]) -> [[PlannerDaySheetEntry]] {
        stride(from: 0, to: entries.count, by: columnsPerPage).map {
            Array(entries[$0..<min($0 + columnsPerPage, entries.count)])
        }
    }

    static func columnRect(index: Int) -> CGRect {
        let width = (pageSize.width - margin * 2 - gutter * CGFloat(columnsPerPage - 1)) / CGFloat(columnsPerPage)
        return CGRect(
            x: margin + CGFloat(index) * (width + gutter),
            y: margin,
            width: width,
            height: pageSize.height - margin * 2 - 22
        )
    }

    static func render(entries: [PlannerDaySheetEntry], dayLabel: String) -> Data? {
        guard !entries.isEmpty else { return nil }
        let data = CFDataCreateMutable(nil, 0)!
        guard let consumer = CGDataConsumer(data: data) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        let allPages = pages(for: entries)
        for (pageIndex, page) in allPages.enumerated() {
            context.beginPDFPage(nil)
            let pageTitle = allPages.count > 1 ? "\(dayLabel) · hoja \(pageIndex + 1) de \(allPages.count)" : dayLabel
            drawText(
                NSAttributedString(string: pageTitle, attributes: attributes(size: 10, bold: true, gray: 0.35)),
                in: CGRect(x: margin, y: pageSize.height - margin - 14, width: pageSize.width - margin * 2, height: 16),
                context: context
            )
            for (index, entry) in page.enumerated() {
                drawColumn(entry, in: columnRect(index: index), context: context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    static func writeToTemporaryFile(entries: [PlannerDaySheetEntry], dayLabel: String, suggestedName: String) -> URL? {
        guard let data = render(entries: entries, dayLabel: dayLabel) else { return nil }
        let safeName = suggestedName.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName)-\(UUID().uuidString.prefix(8))")
            .appendingPathExtension("pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: Dibujo

    private static func drawColumn(_ entry: PlannerDaySheetEntry, in rect: CGRect, context: CGContext) {
        let padding: CGFloat = 12
        context.saveGState()
        context.setStrokeColor(gray: 0.6, alpha: 1)
        context.setLineWidth(0.8)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.strokePath()

        // Cabecera: hora · grupo y título.
        let headerHeight: CGFloat = 92
        let headerRect = CGRect(x: rect.minX, y: rect.maxY - headerHeight, width: rect.width, height: headerHeight)
        context.setFillColor(gray: 0.92, alpha: 1)
        context.addPath(CGPath(roundedRect: headerRect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.fillPath()
        context.restoreGState()

        let header = NSMutableAttributedString(
            string: [entry.time, entry.group].filter { !$0.isEmpty }.joined(separator: " · ") + "\n",
            attributes: attributes(size: 12, bold: true, gray: 0.3)
        )
        header.append(NSAttributedString(string: entry.title, attributes: attributes(size: 18, bold: true)))
        drawText(header, in: headerRect.insetBy(dx: padding, dy: 8), context: context)

        // Notas a mano abajo.
        let notesRect = CGRect(x: rect.minX + padding, y: rect.minY + padding, width: rect.width - padding * 2, height: notesHeight)
        drawText(
            NSAttributedString(string: "Notas", attributes: attributes(size: 10, bold: true, gray: 0.35)),
            in: CGRect(x: notesRect.minX, y: notesRect.maxY - 14, width: notesRect.width, height: 14),
            context: context
        )
        context.saveGState()
        context.setStrokeColor(gray: 0.75, alpha: 1)
        context.setLineWidth(0.5)
        var lineY = notesRect.maxY - 30
        while lineY >= notesRect.minY {
            context.move(to: CGPoint(x: notesRect.minX, y: lineY))
            context.addLine(to: CGPoint(x: notesRect.maxX, y: lineY))
            lineY -= 22
        }
        context.strokePath()
        context.restoreGState()

        let bodyRect = CGRect(
            x: rect.minX + padding,
            y: notesRect.maxY + 10,
            width: rect.width - padding * 2,
            height: headerRect.minY - notesRect.maxY - 10 - 10
        )
        let fitted = drawText(body(for: entry), in: bodyRect, context: context)
        if !fitted {
            drawText(
                NSAttributedString(string: "…", attributes: attributes(size: 12, bold: true, gray: 0.35)),
                in: CGRect(x: bodyRect.maxX - 12, y: bodyRect.minY - 8, width: 12, height: 16),
                context: context
            )
        }
    }

    static func body(for entry: PlannerDaySheetEntry) -> NSAttributedString {
        let text = NSMutableAttributedString()
        func section(_ title: String) {
            if text.length > 0 { text.append(NSAttributedString(string: "\n", attributes: attributes(size: 8))) }
            text.append(NSAttributedString(string: title.uppercased() + "\n", attributes: attributes(size: 10.5, bold: true, gray: 0.35)))
        }
        func line(_ value: String, bold: Bool = false) {
            text.append(NSAttributedString(string: value + "\n", attributes: attributes(size: 13, bold: bold)))
        }

        if !entry.objective.isEmpty {
            section("Objetivo")
            line(entry.objective)
        }
        if !entry.steps.isEmpty {
            let total = entry.steps.compactMap(\.minutes).reduce(0, +)
            section(total > 0 ? "Pasos · \(total) min" : "Pasos")
            for step in entry.steps {
                let prefix = step.minutes.map { "\($0)′  " } ?? "•  "
                let row = NSMutableAttributedString(string: prefix, attributes: attributes(size: 13, bold: true))
                row.append(NSAttributedString(string: step.title + "\n", attributes: attributes(size: 13)))
                text.append(row)
            }
        }
        if !entry.materials.isEmpty {
            section("Material")
            entry.materials.forEach { line("•  " + $0) }
        }
        if !entry.attention.isEmpty {
            section("Atención")
            entry.attention.forEach { line("!  " + $0) }
        }
        if text.length == 0 {
            line("Sin guion planificado.")
        }
        return text
    }

    /// Dibuja el texto en el rectángulo. Devuelve `false` si no cupo entero.
    @discardableResult
    private static func drawText(_ text: NSAttributedString, in rect: CGRect, context: CGContext) -> Bool {
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), CGPath(rect: rect, transform: nil), nil)
        CTFrameDraw(frame, context)
        return CTFrameGetVisibleStringRange(frame).length >= text.length
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
