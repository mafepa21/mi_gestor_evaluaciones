import CoreGraphics
import CoreText
import Foundation

/// Kit de clase en A4 vertical: el guion corre por las páginas que haga falta y
/// cada tarjeta de tarea va en su propia página, para imprimir y plastificar.
/// Core Text + Core Graphics puro, igual que `PlannerDaySheetPDFRenderer`.
enum PlannerClassKitPDFRenderer {
    /// A4 vertical a 72 dpi.
    static let pageSize = CGSize(width: 595, height: 842)
    static let margin: CGFloat = 40
    static let footerHeight: CGFloat = 20

    static func render(kit: PlannerClassKit) -> Data? {
        guard !kit.tasks.isEmpty else { return nil }
        let data = CFDataCreateMutable(nil, 0)!
        guard let consumer = CGDataConsumer(data: data) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        let footer = [kit.input.title, kit.input.meta].filter { !$0.isEmpty }.joined(separator: " · ")
        let text = body(for: kit)
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        let textRect = CGRect(
            x: margin,
            y: margin + footerHeight,
            width: pageSize.width - margin * 2,
            height: pageSize.height - margin * 2 - footerHeight
        )
        var location = 0
        var pageNumber = 1
        while location < text.length {
            context.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(location, 0), CGPath(rect: textRect, transform: nil), nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            drawFooter("\(footer) · \(pageNumber)", context: context)
            context.endPDFPage()
            // Sin avance (texto que no cabe ni en una página vacía): se corta para no quedar en bucle.
            guard visible.length > 0 else { break }
            location += visible.length
            pageNumber += 1
        }

        for card in kit.cards {
            context.beginPDFPage(nil)
            drawCard(card, context: context)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    static func writeToTemporaryFile(kit: PlannerClassKit) -> URL? {
        guard let data = render(kit: kit) else { return nil }
        let safeName = "kit-clase-\(kit.input.title)"
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
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

    // MARK: Texto del kit

    static func body(for kit: PlannerClassKit) -> NSAttributedString {
        let text = NSMutableAttributedString()
        func add(_ value: String, size: CGFloat, bold: Bool = false, gray: CGFloat = 0) {
            text.append(NSAttributedString(string: value + "\n", attributes: attributes(size: size, bold: bold, gray: gray)))
        }
        func heading(_ value: String) {
            add("", size: 6)
            add(value, size: 14, bold: true)
        }
        func label(_ value: String) {
            add(value.uppercased(), size: 8.5, bold: true, gray: 0.4)
        }

        add("Kit de clase", size: 10, bold: true, gray: 0.4)
        add(kit.input.title, size: 20, bold: true)
        if !kit.input.meta.isEmpty { add(kit.input.meta, size: 10.5, gray: 0.35) }
        if !kit.input.objective.isEmpty { add(kit.input.objective, size: 11) }

        if let header = kit.header {
            if !header.boardWords.isEmpty {
                heading("En la pizarra")
                add(header.boardWords.joined(separator: " · "), size: 18, bold: true)
            }
            if !header.sessionCue.isEmpty {
                label("Corrección de la sesión")
                add(header.cueGesture.isEmpty ? "“\(header.sessionCue)”" : "“\(header.sessionCue)” · \(header.cueGesture)", size: 11)
            }
        }

        if !kit.input.setup.isEmpty {
            heading("Montaje (5 minutos antes)")
            kit.input.setup.forEach { add("•  \($0)", size: 11) }
        }

        for (index, task) in kit.tasks.enumerated() {
            let source = task.source
            heading("Tarea \(index + 1) · \(source.title)" + (source.minutes.map { " · \($0) min" } ?? ""))
            guard let coaching = task.coaching else {
                if !source.detail.isEmpty { add(source.detail, size: 11) }
                continue
            }
            if !coaching.show.isEmpty {
                label("Muestra")
                add(coaching.show, size: 11)
            }
            if !coaching.say.isEmpty {
                label("Di")
                coaching.say.forEach { add("“\($0)”", size: 11.5, bold: true) }
            }
            if !coaching.rule.isEmpty {
                label("Regla que corrige")
                coaching.rule.forEach { add("•  \($0)", size: 11) }
            }
            if !coaching.checks.isEmpty {
                label("Comprueba")
                coaching.checks.forEach { add($0.answer.isEmpty ? "“\($0.question)”" : "“\($0.question)” → \($0.answer)", size: 11) }
            }
            if !coaching.cue.isEmpty {
                label("Corrección")
                add("“\(coaching.cue)”", size: 11, bold: true)
            }
        }

        if let header = kit.header, !header.closingQuestion.isEmpty {
            heading("Cierre por parejas")
            add("“\(header.closingQuestion)”", size: 11.5, bold: true)
            if !header.closingSentence.isEmpty { add(header.closingSentence, size: 11) }
        }

        heading("Cómo usar el kit")
        PlannerClassKitFixedContent.howToUse.forEach { add("•  \($0)", size: 10.5) }
        heading("Banco de frases fijas")
        PlannerClassKitFixedContent.phraseBank.forEach { phrase in
            let row = NSMutableAttributedString(string: phrase.phrase, attributes: attributes(size: 10.5, bold: true))
            row.append(NSAttributedString(string: "  \(phrase.gesture) · \(phrase.meaning)\n", attributes: attributes(size: 10.5, gray: 0.35)))
            text.append(row)
        }
        return text
    }

    // MARK: Dibujo

    private static func drawCard(_ card: PlannerClassKitCard, context: CGContext) {
        let rect = CGRect(origin: .zero, size: pageSize).insetBy(dx: margin, dy: margin)
        context.saveGState()
        context.setStrokeColor(gray: 0.5, alpha: 1)
        context.setLineWidth(1.5)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 16, cornerHeight: 16, transform: nil))
        context.strokePath()
        context.restoreGState()

        let text = NSMutableAttributedString()
        func add(_ value: String, size: CGFloat, bold: Bool = false, gray: CGFloat = 0) {
            text.append(NSAttributedString(string: value + "\n", attributes: attributes(size: size, bold: bold, gray: gray)))
        }
        add(card.title, size: 30, bold: true)
        add("", size: 14)
        for (index, step) in card.steps.enumerated() {
            add("\(index + 1). \(step)", size: 22)
            add("", size: 8)
        }
        if !card.points.isEmpty {
            add("", size: 10)
            add("POINTS", size: 14, bold: true, gray: 0.4)
            add(card.points, size: 20)
        }
        if !card.swap.isEmpty {
            add("", size: 10)
            add("SWAP", size: 14, bold: true, gray: 0.4)
            add(card.swap, size: 20)
        }
        if !card.cue.isEmpty {
            add("", size: 10)
            add("ONE CUE", size: 14, bold: true, gray: 0.4)
            add(card.cue, size: 28, bold: true)
        }
        let frame = CTFramesetterCreateFrame(
            CTFramesetterCreateWithAttributedString(text as CFAttributedString),
            CFRangeMake(0, 0),
            CGPath(rect: rect.insetBy(dx: 32, dy: 32), transform: nil),
            nil
        )
        CTFrameDraw(frame, context)
    }

    private static func drawFooter(_ value: String, context: CGContext) {
        let frame = CTFramesetterCreateFrame(
            CTFramesetterCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes(size: 8.5, gray: 0.5)) as CFAttributedString),
            CFRangeMake(0, 0),
            CGPath(rect: CGRect(x: margin, y: margin - 8, width: pageSize.width - margin * 2, height: 14), transform: nil),
            nil
        )
        CTFrameDraw(frame, context)
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
