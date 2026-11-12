import CoreGraphics
import CoreText
import Foundation
import MiGestorKit

/// Guion de clase de una sesión: lo que el docente dice, muestra y comprueba, sacado de
/// las líneas etiquetadas («Muestra:», «Di:», «Comprueba:», «Regla:», «Corrección:»,
/// «Seguridad:», «Pizarra:») del texto docente de cada actividad.
struct PlannerSessionClassScript: Equatable {
    /// Etiquetas encontradas en el texto de una actividad.
    struct Labels: Equatable {
        struct Check: Equatable {
            let question: String
            let answer: String?
        }

        var show: String?
        var say: [String] = []
        var checks: [Check] = []
        var rules: [String] = []
        var corrections: [String] = []
        var safety: [String] = []
        var board: String?

        /// Hay algo que contar en el guion (la pizarra es de la sesión, no de la actividad).
        var hasActivityContent: Bool {
            show != nil || !say.isEmpty || !checks.isEmpty || !rules.isEmpty || !corrections.isEmpty || !safety.isEmpty
        }
    }

    struct Activity: Equatable {
        let title: String
        let minutes: Int?
        let labels: Labels
    }

    /// Palabras clave de la sesión (primera «Pizarra:» que aparezca).
    var board: String?
    var activities: [Activity] = []

    static let empty = PlannerSessionClassScript()

    var isEmpty: Bool { board == nil && activities.isEmpty }

    /// Entrada pura: título, minutos y texto docente crudo de cada actividad, en orden.
    init(activities source: [(title: String, minutes: Int?, teacherText: String)] = []) {
        var board: String?
        var activities: [Activity] = []
        for item in source {
            let labels = Self.labels(in: item.teacherText)
            if board == nil { board = labels.board }
            if labels.hasActivityContent {
                activities.append(Activity(title: item.title, minutes: item.minutes, labels: labels))
            }
        }
        self.board = board
        self.activities = activities
    }

    private static let labelPattern = try! NSRegularExpression(
        pattern: #"^(muestra|d[ií]|comprueba|regla|correcci[oó]n|seguridad|pizarra)\s*:\s*(.*)$"#,
        options: [.caseInsensitive]
    )

    /// Quita viñetas, asteriscos de markdown y espacios; normaliza tildes sueltas (NFD).
    private static func cleanedLine(_ line: String) -> String {
        line.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: #"^[\s\-\u2022*#]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Etiqueta (en minúsculas y sin tilde) y texto de una línea, o `nil` si no lleva etiqueta.
    /// Solo la primera palabra cuenta: «Di:» sí, «Dibujo:» o «Dinámica:» no.
    static func labelAndText(of line: String) -> (label: String, text: String)? {
        let cleaned = cleanedLine(line)
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        guard let match = labelPattern.firstMatch(in: cleaned, range: range),
              let labelRange = Range(match.range(at: 1), in: cleaned),
              let textRange = Range(match.range(at: 2), in: cleaned) else { return nil }
        let label = cleaned[labelRange].lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
        return (label, cleaned[textRange].trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func labels(in teacherText: String) -> Labels {
        var result = Labels()
        for line in teacherText.components(separatedBy: .newlines) {
            guard let parsed = labelAndText(of: line), !parsed.text.isEmpty else { continue }
            let (label, text) = (parsed.label, parsed.text)
            switch label {
            case "muestra": if result.show == nil { result.show = text }
            case "di": result.say.append(text)
            case "comprueba":
                let parts = text.components(separatedBy: "→").count > 1
                    ? text.components(separatedBy: "→")
                    : text.components(separatedBy: "->")
                let question = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let answer = parts.dropFirst().joined(separator: "→").trimmingCharacters(in: .whitespacesAndNewlines)
                if !question.isEmpty {
                    result.checks.append(.init(question: question, answer: answer.isEmpty ? nil : answer))
                }
            case "regla": result.rules.append(text)
            case "correccion": result.corrections.append(text)
            case "seguridad": result.safety.append(text)
            case "pizarra": if result.board == nil { result.board = text }
            default: break
            }
        }
        return result
    }

    /// Quita del texto las líneas etiquetadas para no repetirlas en el resumen del paso.
    /// Sin etiquetas devuelve el texto tal cual.
    static func removingLabelLines(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        let kept = lines.filter { labelAndText(of: $0) == nil }
        guard kept.count != lines.count else { return text }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Esquema corto de una sesión para la hoja del día.
struct PlannerDaySheetEntry: Equatable {
    struct Step: Equatable {
        let minutes: Int?
        let title: String
        var detail: String = ""

        static let maxDetailLength = 170

        /// Primera parte del texto docente, en una o dos líneas.
        static func shortDetail(_ text: String) -> String {
            let flat = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard flat.count > maxDetailLength else { return flat }
            let cut = flat.prefix(maxDetailLength)
            let end = cut.lastIndex(of: " ") ?? cut.endIndex
            return String(cut[..<end]) + "…"
        }
    }

    let time: String
    let group: String
    let title: String
    let objective: String
    let steps: [Step]
    let materials: [String]
    let attention: [String]
    /// Guion de clase (vacío si ninguna actividad lleva etiquetas).
    var script: PlannerSessionClassScript = .empty

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
        let planSteps = projection.guideBlocks.flatMap(\.steps).filter { !$0.isCollection }
        // `reviewDetail` altera las líneas (viñetas, listas en línea): las etiquetas se leen del
        // texto docente crudo de la actividad, que se empareja por clave con el paso.
        var teacherTextByKey: [String: String] = [:]
        for activity in projection.activities where teacherTextByKey[activity.activityKey] == nil {
            teacherTextByKey[activity.activityKey] = activity.teacherActions
        }
        self.script = PlannerSessionClassScript(activities: planSteps.map {
            (title: $0.title, minutes: $0.minutes, teacherText: teacherTextByKey[$0.activityKey] ?? "")
        })
        self.steps = planSteps
            .prefix(Self.maxSteps)
            .map {
                Step(
                    minutes: $0.minutes,
                    title: $0.title,
                    detail: Step.shortDetail(PlannerSessionClassScript.removingLabelLines(from: $0.detail))
                )
            }
        let materials = Self.materialItems(plan.material)
        self.materials = Array((materials.isEmpty ? projection.setupBullets : materials).prefix(Self.maxListItems))
        self.attention = Array(projection.attentionNotes.prefix(Self.maxListItems))
    }

    /// Parte el material por líneas y «;», nunca por comas ni dentro de paréntesis,
    /// para que «Court group (12 pairs, 2 pairs per court)» quede entero.
    /// El visor usa `splitList` (por comas); aquí se respeta la frase completa.
    static func materialItems(_ material: String) -> [String] {
        var text = material
        if let marker = text.range(of: "— Saberes básicos:", options: [.caseInsensitive, .diacriticInsensitive]) {
            text = String(text[..<marker.lowerBound])
        }
        var items: [String] = []
        var current = ""
        var depth = 0
        func flush() {
            let item = current
                .replacingOccurrences(of: #"^[\s\-\u2022*]+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
            if !item.isEmpty && !items.contains(item) { items.append(item) }
            current = ""
        }
        for character in text {
            switch character {
            case "(", "[": depth += 1; current.append(character)
            case ")", "]": depth = max(depth - 1, 0); current.append(character)
            case _ where character == ";" || character.isNewline:
                if depth == 0 { flush() } else { current.append(character == ";" ? ";" : " ") }
            default: current.append(character)
            }
        }
        flush()
        return items
    }

    init(time: String, group: String, title: String, objective: String, steps: [Step], materials: [String], attention: [String], script: PlannerSessionClassScript = .empty) {
        self.script = script
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

    /// Páginas del guion de clase: solo las sesiones con guion, en el mismo orden.
    static func scriptPages(for entries: [PlannerDaySheetEntry]) -> [[PlannerDaySheetEntry]] {
        pages(for: entries.filter { !$0.script.isEmpty })
    }

    private static func drawPage(
        title: String,
        entries: [PlannerDaySheetEntry],
        context: CGContext,
        column: (PlannerDaySheetEntry, CGRect) -> Void
    ) {
        context.beginPDFPage(nil)
        drawText(
            NSAttributedString(string: title, attributes: attributes(size: 10, bold: true, gray: 0.35)),
            in: CGRect(x: margin, y: pageSize.height - margin - 14, width: pageSize.width - margin * 2, height: 16),
            context: context
        )
        for (index, entry) in entries.enumerated() {
            column(entry, columnRect(index: index))
        }
        context.endPDFPage()
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
            let pageTitle = allPages.count > 1 ? "\(dayLabel) · hoja \(pageIndex + 1) de \(allPages.count)" : dayLabel
            drawPage(title: pageTitle, entries: page, context: context) { drawColumn($0, in: $1, context: context) }
        }
        let scriptPages = scriptPages(for: entries)
        for (pageIndex, page) in scriptPages.enumerated() {
            let suffix = scriptPages.count > 1 ? " · hoja \(pageIndex + 1) de \(scriptPages.count)" : ""
            drawPage(title: "\(dayLabel) · guion de clase" + suffix, entries: page, context: context) {
                drawScriptColumn($0, in: $1, context: context)
            }
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

    /// Marco y cabecera de columna (hora · grupo, título). Devuelve el rectángulo de la cabecera.
    private static func drawColumnFrame(_ entry: PlannerDaySheetEntry, in rect: CGRect, padding: CGFloat, context: CGContext) -> CGRect {
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
        return headerRect
    }

    private static func drawOverflowMark(in bodyRect: CGRect, context: CGContext) {
        drawText(
            NSAttributedString(string: "…", attributes: attributes(size: 12, bold: true, gray: 0.35)),
            in: CGRect(x: bodyRect.maxX - 12, y: bodyRect.minY - 8, width: 12, height: 16),
            context: context
        )
    }

    private static func drawScriptColumn(_ entry: PlannerDaySheetEntry, in rect: CGRect, context: CGContext) {
        let padding: CGFloat = 12
        let headerRect = drawColumnFrame(entry, in: rect, padding: padding, context: context)
        let bodyRect = CGRect(
            x: rect.minX + padding,
            y: rect.minY + padding,
            width: rect.width - padding * 2,
            height: headerRect.minY - rect.minY - padding - 10
        )
        if !drawText(scriptBody(for: entry.script), in: bodyRect, context: context) {
            drawOverflowMark(in: bodyRect, context: context)
        }
    }

    private static func drawColumn(_ entry: PlannerDaySheetEntry, in rect: CGRect, context: CGContext) {
        let padding: CGFloat = 12
        let headerRect = drawColumnFrame(entry, in: rect, padding: padding, context: context)

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
        if !fitted { drawOverflowMark(in: bodyRect, context: context) }
    }

    /// Texto del guion: pizarra destacada y, por actividad, muestra, di, comprueba, regla,
    /// corrección y seguridad, con la etiqueta en gris pequeña.
    static func scriptBody(for script: PlannerSessionClassScript) -> NSAttributedString {
        let text = NSMutableAttributedString()
        func label(_ title: String) {
            text.append(NSAttributedString(string: title.uppercased() + "\n", attributes: labelAttributes))
        }
        func line(_ value: String, bold: Bool = false) {
            text.append(NSAttributedString(string: value + "\n", attributes: scriptTextAttributes(bold: bold)))
        }

        if let board = script.board {
            text.append(NSAttributedString(string: "PIZARRA\n", attributes: attributes(size: 10.5, bold: true, gray: 0.35)))
            text.append(NSAttributedString(string: board + "\n", attributes: attributes(size: 15, bold: true)))
        }
        for activity in script.activities {
            if text.length > 0 { text.append(NSAttributedString(string: "\n", attributes: attributes(size: 8))) }
            let prefix = activity.minutes.map { "\($0)′  " } ?? "•  "
            let row = NSMutableAttributedString(string: prefix, attributes: attributes(size: 13, bold: true))
            row.append(NSAttributedString(string: activity.title + "\n", attributes: attributes(size: 13, bold: true)))
            text.append(row)

            let labels = activity.labels
            if let show = labels.show {
                label("Muestra")
                line(show)
            }
            if !labels.say.isEmpty {
                label("Di")
                for (index, phrase) in labels.say.enumerated() {
                    line(labels.say.count > 1 ? "\(index + 1). " + phrase : phrase)
                }
            }
            if !labels.checks.isEmpty {
                label("Comprueba")
                for check in labels.checks {
                    let row = NSMutableAttributedString(string: check.question, attributes: scriptTextAttributes())
                    if let answer = check.answer {
                        row.append(NSAttributedString(string: " → ", attributes: scriptTextAttributes()))
                        row.append(NSAttributedString(string: answer, attributes: scriptTextAttributes(gray: 0.45)))
                    }
                    row.append(NSAttributedString(string: "\n", attributes: scriptTextAttributes()))
                    text.append(row)
                }
            }
            if !labels.rules.isEmpty {
                label("Regla")
                labels.rules.forEach { line($0) }
            }
            if !labels.corrections.isEmpty {
                label("Corrección")
                labels.corrections.forEach { line($0, bold: true) }
            }
            if !labels.safety.isEmpty {
                label("Seguridad")
                labels.safety.forEach { line($0) }
            }
        }
        return text
    }

    private static var labelAttributes: [NSAttributedString.Key: Any] {
        var result = attributes(size: 9, bold: true, gray: 0.5)
        result[NSAttributedString.Key(kCTParagraphStyleAttributeName as String)] = indentedStyle
        return result
    }

    private static func scriptTextAttributes(bold: Bool = false, gray: CGFloat = 0) -> [NSAttributedString.Key: Any] {
        var result = attributes(size: 12, bold: bold, gray: gray)
        result[NSAttributedString.Key(kCTParagraphStyleAttributeName as String)] = indentedStyle
        return result
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
                if !step.detail.isEmpty {
                    var detailAttributes = attributes(size: 11.5, gray: 0.3)
                    detailAttributes[NSAttributedString.Key(kCTParagraphStyleAttributeName as String)] = indentedStyle
                    row.append(NSAttributedString(string: step.detail + "\n", attributes: detailAttributes))
                }
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

    /// Sangría del detalle de cada paso, alineada con el título del paso.
    private static let indentedStyle: CTParagraphStyle = {
        var indent: CGFloat = 26
        var spacing: CGFloat = 3
        return withUnsafeBytes(of: &indent) { indentBytes in
            withUnsafeBytes(of: &spacing) { spacingBytes in
                let settings = [
                    CTParagraphStyleSetting(spec: .firstLineHeadIndent, valueSize: MemoryLayout<CGFloat>.size, value: indentBytes.baseAddress!),
                    CTParagraphStyleSetting(spec: .headIndent, valueSize: MemoryLayout<CGFloat>.size, value: indentBytes.baseAddress!),
                    CTParagraphStyleSetting(spec: .paragraphSpacing, valueSize: MemoryLayout<CGFloat>.size, value: spacingBytes.baseAddress!)
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
    }()

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
