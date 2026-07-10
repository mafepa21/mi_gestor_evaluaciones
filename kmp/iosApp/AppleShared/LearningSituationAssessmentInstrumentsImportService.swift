import Foundation
import CryptoKit
import ZIPFoundation

struct LearningSituationAssessmentImportDraft: Identifiable, Codable {
    let id: UUID
    var sourceFileName: String
    var instruments: [AssessmentInstrumentDraft]
    var gradingFormula: String?
    var warnings: [String]
    let sourceURL: URL
    let sha256: String
    let sizeBytes: Int64

    init(
        sourceFileName: String,
        instruments: [AssessmentInstrumentDraft],
        gradingFormula: String?,
        warnings: [String],
        sourceURL: URL,
        sha256: String,
        sizeBytes: Int64
    ) {
        self.id = UUID()
        self.sourceFileName = sourceFileName
        self.instruments = instruments
        self.gradingFormula = gradingFormula
        self.warnings = warnings
        self.sourceURL = sourceURL
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
    }
}

struct AssessmentInstrumentDraft: Identifiable, Codable {
    let id: UUID
    var title: String
    var kind: AssessmentInstrumentKind
    var criterionLabel: String?
    var weightPercent: Double?
    var isSelected: Bool
    var countsTowardAverage: Bool
    var scoreStrategy: AssessmentInstrumentScoreStrategy
    var emptyCellPolicy: AssessmentInstrumentEmptyCellPolicy
    var rubric: RubricDraft?
    var checklistItems: [ChecklistItemDraft]
    var observationFields: [ObservationFieldDraft]
    var quizQuestions: [QuizQuestionDraft]
    var note: String?

    init(
        title: String,
        kind: AssessmentInstrumentKind,
        criterionLabel: String?,
        weightPercent: Double?,
        isSelected: Bool,
        countsTowardAverage: Bool,
        scoreStrategy: AssessmentInstrumentScoreStrategy,
        emptyCellPolicy: AssessmentInstrumentEmptyCellPolicy = .excludeFromAverage,
        rubric: RubricDraft?,
        checklistItems: [ChecklistItemDraft] = [],
        observationFields: [ObservationFieldDraft] = [],
        quizQuestions: [QuizQuestionDraft] = [],
        note: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.kind = kind
        self.criterionLabel = criterionLabel
        self.weightPercent = weightPercent
        self.isSelected = isSelected
        self.countsTowardAverage = countsTowardAverage
        self.scoreStrategy = scoreStrategy
        self.emptyCellPolicy = emptyCellPolicy
        self.rubric = rubric
        self.checklistItems = checklistItems
        self.observationFields = observationFields
        self.quizQuestions = quizQuestions
        self.note = note
    }
}

enum AssessmentInstrumentKind: String, Codable, CaseIterable {
    case rubric
    case observationGrid
    case checklist
    case teacherObservation
    case submissionChecklist
    case quizQuestions

    var label: String {
        switch self {
        case .rubric: return "Rubrica"
        case .observationGrid: return "Observacion"
        case .checklist: return "Checklist"
        case .teacherObservation: return "Observacion docente"
        case .submissionChecklist: return "Checklist final"
        case .quizQuestions: return "Quiz"
        }
    }
}

enum AssessmentInstrumentScoreStrategy: String, Codable, CaseIterable {
    case none
    case numeric0To10
    case rubric
    case checklistAllOrNothing
    case checklistProportional
    case observationScale1To4
    case quizPercentCorrect

    var label: String {
        switch self {
        case .none: return "Auxiliar"
        case .numeric0To10: return "Nota 0-10"
        case .rubric: return "Rúbrica"
        case .checklistAllOrNothing: return "Checklist todo/nada"
        case .checklistProportional: return "Checklist proporcional"
        case .observationScale1To4: return "Observación 1-4"
        case .quizPercentCorrect: return "Quiz % aciertos"
        }
    }
}

enum AssessmentInstrumentEmptyCellPolicy: String, Codable, CaseIterable {
    case excludeFromAverage
    case countAsZero

    var label: String {
        switch self {
        case .excludeFromAverage: return "Vacías excluidas"
        case .countAsZero: return "Vacías como 0"
        }
    }
}

struct RubricDraft: Codable {
    var levels: [RubricLevelDraft]
    var criteria: [RubricCriterionDraft]
}

struct RubricLevelDraft: Codable {
    var label: String
    var points: Int
}

struct RubricCriterionDraft: Codable {
    var title: String
    var descriptors: [String]
    var weight: Double
}

struct ChecklistItemDraft: Codable {
    var title: String
    var required: Bool
}

struct ObservationFieldDraft: Codable {
    var title: String
    var scaleLabel: String?
}

struct QuizQuestionDraft: Codable {
    var questionText: String
    var options: [String]
}

struct LearningSituationAssessmentInstrumentsImportService {
    func preview(from url: URL) throws -> LearningSituationAssessmentImportDraft {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return try preview(from: url, data: data)
    }

    /// Variante que recibe los bytes ya leídos: permite separar el acceso al recurso con
    /// alcance de seguridad (rápido, hazlo en el hilo que ya tiene la autorización de
    /// NSOpenPanel/.fileImporter) del parseo XML en sí (CPU-bound, seguro de despachar
    /// a background sin volver a tocar la URL ni el security scope).
    func preview(from url: URL, data: Data) throws -> LearningSituationAssessmentImportDraft {
        let blocks = try readBlocks(from: data)
        guard !blocks.isEmpty else { throw LearningSituationImportError.missingDocumentBody }

        var warnings: [String] = []
        var instruments: [AssessmentInstrumentDraft] = []
        var currentHeading: ParsedInstrumentHeading?
        var pendingTables: [[[String]]] = []
        var pendingParagraphs: [String] = []
        var gradingFormula: String?

        func flushCurrent() {
            guard let heading = currentHeading else { return }
            if let instrument = makeInstrument(from: heading, tables: pendingTables, paragraphs: pendingParagraphs) {
                instruments.append(instrument)
            } else {
                warnings.append("No se ha podido interpretar \(heading.title).")
            }
            pendingTables = []
            pendingParagraphs = []
        }

        for block in blocks {
            switch block {
            case .paragraph(let text):
                let cleanText = clean(text)
                guard !cleanText.isEmpty else { continue }
                if isDocumentTitle(cleanText) {
                    continue
                } else if isImporterNoteSection(cleanText) {
                    flushCurrent()
                    currentHeading = nil
                } else if isGradingLine(cleanText) {
                    gradingFormula = cleanText
                } else if let heading = parseHeading(cleanText) {
                    flushCurrent()
                    currentHeading = heading
                } else if currentHeading != nil {
                    pendingParagraphs.append(cleanText)
                }
            case .table(let rows):
                if currentHeading == nil {
                    if let heading = headingFromTable(rows) {
                        currentHeading = heading
                    }
                } else {
                    pendingTables.append(rows)
                }
            }
        }
        flushCurrent()

        if instruments.isEmpty {
            warnings.append("No se han detectado instrumentos evaluativos en tablas DOCX.")
        }
        let weightedTotal = instruments.compactMap(\.weightPercent).reduce(0, +)
        if weightedTotal > 0, abs(weightedTotal - 100) > 0.5, gradingFormula == nil {
            warnings.append("La suma de ponderaciones detectada es \(formatPercent(weightedTotal)); revisa el reparto antes de crear columnas.")
        }

        return LearningSituationAssessmentImportDraft(
            sourceFileName: url.lastPathComponent,
            instruments: instruments,
            gradingFormula: gradingFormula,
            warnings: warnings,
            sourceURL: url,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            sizeBytes: Int64(data.count)
        )
    }

    private func readBlocks(from data: Data) throws -> [WordDocumentBlock] {
        let archive = try Archive(data: data, accessMode: .read, pathEncoding: nil)
        guard let entry = archive["word/document.xml"] else {
            throw LearningSituationImportError.unreadableDocument
        }
        var xmlData = Data()
        _ = try archive.extract(entry) { xmlData.append($0) }
        let reader = WordDocumentTableReader()
        guard reader.parse(data: xmlData) else { throw LearningSituationImportError.unreadableDocument }
        return reader.blocks
    }

    private func makeInstrument(from heading: ParsedInstrumentHeading, tables: [[[String]]], paragraphs: [String]) -> AssessmentInstrumentDraft? {
        let normalizedTitle = normalized(heading.title)
        let nonEmptyTables = tables
            .map { $0.map { row in row.map(clean) }.filter { row in row.contains { !$0.isEmpty } } }
            .filter { !$0.isEmpty }
        let kind = inferKind(title: normalizedTitle, tables: nonEmptyTables)
        let rubric = makeRubric(kind: kind, tables: nonEmptyTables)
        let checklistItems = makeChecklistItems(kind: kind, tables: nonEmptyTables, paragraphs: paragraphs)
        let observationFields = makeObservationFields(kind: kind, tables: nonEmptyTables)
        let quizQuestions = makeQuizQuestions(kind: kind, tables: nonEmptyTables, paragraphs: paragraphs)
        let selectedByDefault = (heading.weightPercent ?? 0) > 0
        let scoreStrategy = defaultScoreStrategy(
            kind: kind,
            weightPercent: heading.weightPercent,
            observationFields: observationFields
        )
        let countsTowardAverage = scoreStrategy != .none && (heading.weightPercent ?? 0) > 0

        if rubric == nil, checklistItems.isEmpty, observationFields.isEmpty, quizQuestions.isEmpty {
            return nil
        }
        return AssessmentInstrumentDraft(
            title: heading.title,
            kind: kind,
            criterionLabel: heading.criterionLabel,
            weightPercent: heading.weightPercent,
            isSelected: selectedByDefault,
            countsTowardAverage: countsTowardAverage,
            scoreStrategy: scoreStrategy,
            rubric: rubric,
            checklistItems: checklistItems,
            observationFields: observationFields,
            quizQuestions: quizQuestions,
            note: countsTowardAverage ? nil : "Auxiliar o sin puntuación computable detectada"
        )
    }

    private func defaultScoreStrategy(
        kind: AssessmentInstrumentKind,
        weightPercent: Double?,
        observationFields: [ObservationFieldDraft]
    ) -> AssessmentInstrumentScoreStrategy {
        guard (weightPercent ?? 0) > 0 else { return .none }
        switch kind {
        case .rubric:
            return .rubric
        case .observationGrid:
            return hasObservationScale1To4(observationFields) ? .observationScale1To4 : .none
        case .checklist, .submissionChecklist:
            return .none
        case .teacherObservation:
            return .none
        case .quizQuestions:
            return .quizPercentCorrect
        }
    }

    private func hasObservationScale1To4(_ fields: [ObservationFieldDraft]) -> Bool {
        fields.contains { field in
            guard let scale = field.scaleLabel else { return false }
            let value = normalized(scale)
            return value.contains("1") && value.contains("4")
        }
    }

    private func makeRubric(kind: AssessmentInstrumentKind, tables: [[[String]]]) -> RubricDraft? {
        guard kind == .rubric else { return nil }
        guard let table = tables.first(where: { $0.count >= 2 }) else { return nil }
        let header = table[0]
        let descriptorHeaders = Array(header.dropFirst()).filter { !$0.isEmpty }
        let levelLabels = descriptorHeaders.isEmpty ? ["1", "2", "3", "4"] : descriptorHeaders
        let levels = levelLabels.enumerated().map { index, label in
            RubricLevelDraft(label: label, points: index + 1)
        }
        let rows = table.dropFirst().filter { row in row.first?.isEmpty == false }
        guard !rows.isEmpty else { return nil }
        let rawWeights = rows.map { criterionWeight(from: $0) }
        let normalizedWeights = normalizedCriterionWeights(rawWeights, count: rows.count)
        let criteria = rows.enumerated().map { index, row in
            let descriptors = Array(row.dropFirst()).map(clean)
            return RubricCriterionDraft(
                title: criterionTitle(from: row.first ?? "Criterio"),
                descriptors: descriptors,
                weight: normalizedWeights[index]
            )
        }
        return RubricDraft(levels: levels, criteria: criteria)
    }

    private func criterionWeight(from row: [String]) -> Double? {
        guard let first = row.first else { return nil }
        if let percent = firstDouble(in: first, pattern: #"([0-9]+(?:[.,][0-9]+)?)\s*%"#) {
            return percent
        }
        if let points = firstDouble(in: first, pattern: #"([0-9]+(?:[.,][0-9]+)?)\s*(?:puntos?|pts?\.?)"#) {
            return points
        }
        if let decimal = firstDouble(in: first, pattern: #"\b(0[.,][0-9]+|1[.,]0+)\b"#) {
            return decimal
        }
        return nil
    }

    private func normalizedCriterionWeights(_ rawWeights: [Double?], count: Int) -> [Double] {
        guard count > 0 else { return [] }
        let equalWeight = 1.0 / Double(count)
        guard rawWeights.allSatisfy({ $0 != nil }) else {
            return Array(repeating: equalWeight, count: count)
        }
        let values = rawWeights.compactMap { $0 }
        let sum = values.reduce(0, +)
        guard sum > 0 else { return Array(repeating: equalWeight, count: count) }
        if sum > 1.5 {
            return values.map { $0 / sum }
        }
        return values.map { $0 / sum }
    }

    private func criterionTitle(from value: String) -> String {
        clean(value)
            .replacingOccurrences(of: #"\s*[\(\[]?\s*[0-9]+(?:[.,][0-9]+)?\s*%\s*[\)\]]?\s*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*[\(\[]?\s*[0-9]+(?:[.,][0-9]+)?\s*(?:puntos?|pts?\.?)\s*[\)\]]?\s*"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s*[\(\[]?\s*(?:0[.,][0-9]+|1[.,]0+)\s*[\)\]]?\s*"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—\t\n\r"))
    }

    private func makeChecklistItems(kind: AssessmentInstrumentKind, tables: [[[String]]], paragraphs: [String]) -> [ChecklistItemDraft] {
        guard kind == .checklist || kind == .submissionChecklist else { return [] }
        let tableItems = tables.flatMap { table in
            let rows = table.dropFirst().isEmpty ? table : Array(table.dropFirst())
            return rows.compactMap { row -> ChecklistItemDraft? in
                guard let title = row.first(where: { !$0.isEmpty }) else { return nil }
                return ChecklistItemDraft(title: title, required: true)
            }
        }
        let paragraphItems = paragraphs.flatMap(checklistItems(from:))
        return tableItems + paragraphItems
    }

    private func makeQuizQuestions(kind: AssessmentInstrumentKind, tables: [[[String]]], paragraphs: [String]) -> [QuizQuestionDraft] {
        guard kind == .quizQuestions else { return [] }
        let tableQuestions = tables.flatMap { table -> [QuizQuestionDraft] in
            let rows = table.dropFirst().isEmpty ? table : Array(table.dropFirst())
            return rows.compactMap { row -> QuizQuestionDraft? in
                guard let text = row.first(where: { !$0.isEmpty }) else { return nil }
                let options = Array(row.dropFirst()).map(clean).filter { !$0.isEmpty }
                return QuizQuestionDraft(questionText: text, options: options)
            }
        }
        let paragraphQuestions = paragraphs.compactMap(quizQuestion(from:))
        return tableQuestions + paragraphQuestions
    }

    private func quizQuestion(from paragraph: String) -> QuizQuestionDraft? {
        // Word numera estos párrafos vía su propio motor de listas (w:numPr): el texto
        // extraído del XML no incluye el "1. " literal, así que el prefijo numerado por sí
        // solo no basta para detectar todas las preguntas reales de una tabla/lista Word.
        let isNumbered = paragraph.range(of: #"^\s*\d+[\.\)]\s+"#, options: .regularExpression) != nil
        let isTrueFalse = normalized(paragraph).hasPrefix("verdadero o falso") || normalized(paragraph).hasPrefix("true or false")
        let looksLikeChoiceOrBlank = paragraph.contains(" / ") || paragraph.contains("___")
        guard isNumbered || paragraph.contains("?") || isTrueFalse || looksLikeChoiceOrBlank else { return nil }
        var text = paragraph.replacingOccurrences(of: #"^\s*\d+[\.\)]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var options: [String] = []
        if isTrueFalse {
            options = ["Verdadero", "Falso"]
        } else if let slashOptions = optionsFromSlashList(text) {
            options = slashOptions
            if let questionMarkRange = text.range(of: "?") {
                text = String(text[..<questionMarkRange.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return QuizQuestionDraft(questionText: text, options: options)
    }

    private func optionsFromSlashList(_ text: String) -> [String]? {
        guard let questionMarkRange = text.range(of: "?", options: .backwards) else { return nil }
        let tail = String(text[questionMarkRange.upperBound...])
        guard tail.contains(" / ") else { return nil }
        let parts = tail
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .components(separatedBy: " / ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.count > 1 ? parts : nil
    }

    private func makeObservationFields(kind: AssessmentInstrumentKind, tables: [[[String]]]) -> [ObservationFieldDraft] {
        guard kind == .teacherObservation || kind == .observationGrid else { return [] }
        return tables.flatMap { table in
            let header = table.first ?? []
            let scale = header.dropFirst().filter { !$0.isEmpty }.joined(separator: " / ")
            let fieldTitles = observationFieldTitles(from: table)
            return fieldTitles.map { title in
                ObservationFieldDraft(title: title, scaleLabel: scale.isEmpty ? nil : scale)
            }
        }
    }

    private func inferKind(title: String, tables: [[[String]]]) -> AssessmentInstrumentKind {
        if title.contains("submission") || title.contains("entrega") || title.contains("final checklist") || title.contains("producto final") {
            return .submissionChecklist
        }
        if title.contains("passport") ||
            title.contains("pasaporte") ||
            title.contains("checklist") ||
            title.contains("lista de cotejo") ||
            title.contains("lista de control") ||
            title.contains("autoevaluacion") ||
            title.contains("coevaluacion") {
            return .checklist
        }
        if title.contains("quiz") {
            return .quizQuestions
        }
        if title.contains("safety") || title.contains("adjustment") || title.contains("tarea competencial") {
            return .checklist
        }
        if title.contains("teacher") ||
            title.contains("docente") ||
            title.contains("registro anecdotico") ||
            title.contains("observacion docente") {
            return .teacherObservation
        }
        if title.contains("grid") ||
            title.contains("observ") ||
            title.contains("log") ||
            title.contains("record sheet") ||
            title.contains("diagnostic") ||
            title.contains("escala de valoracion") ||
            title.contains("diana de evaluacion") ||
            title.contains("observacion sistematica") ||
            tableHeaders(tables).contains(where: { $0.contains("student") || $0.contains("alumno") || $0.contains("exercise") }) {
            return .observationGrid
        }
        return .rubric
    }

    private func headingFromTable(_ rows: [[String]]) -> ParsedInstrumentHeading? {
        guard let first = rows.flatMap({ $0 }).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return nil
        }
        return parseHeading(first)
    }

    private func parseHeading(_ text: String) -> ParsedInstrumentHeading? {
        let cleanText = clean(text)
        let normalizedText = normalized(cleanText)
        let isExplicitUnnumberedHeading = looksLikeHeadingProse(cleanText) &&
            instrumentHeadingKeywords.contains { normalizedText.contains($0) }
        guard isNumberedInstrumentHeading(cleanText) || isExplicitUnnumberedHeading else {
            return nil
        }
        let weight = firstDouble(in: cleanText, pattern: #"([0-9]+(?:[.,][0-9]+)?)\s*%"#)
        let criterion = firstString(in: cleanText, pattern: #"(CE\s*\d+(?:\.\d+)?)"#)
        var title = cleanText
            .replacingOccurrences(of: #"^\s*\d+[\.\)]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*[-–—]\s*CE\s*\d+(?:\.\d+)?"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s*[-–—]\s*[0-9]+(?:[.,][0-9]+)?\s*%"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—\t\n\r"))
        if title.isEmpty { title = cleanText }
        return ParsedInstrumentHeading(title: title, criterionLabel: criterion, weightPercent: weight)
    }

    private func checklistItems(from paragraph: String) -> [ChecklistItemDraft] {
        let markerPattern = #"(?:^|\s)-\s*\[\s?\]\s*"#
        let normalizedMarkers = paragraph
            .replacingOccurrences(of: markerPattern, with: "|||CHECK_ITEM|||", options: .regularExpression)
            .replacingOccurrences(of: #"\[\s?\]\s*"#, with: "|||CHECK_ITEM|||", options: .regularExpression)
        let splitItems = normalizedMarkers
            .components(separatedBy: "|||CHECK_ITEM|||")
            .map(clean)
            .filter { !$0.isEmpty && !normalized($0).hasPrefix("tick before") }
        if splitItems.count > 1 {
            return splitItems.map { ChecklistItemDraft(title: $0, required: true) }
        }
        let labelStripped = paragraph
            .replacingOccurrences(of: #"^[^:]{1,40}:\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !labelStripped.isEmpty else { return [] }
        return [ChecklistItemDraft(title: labelStripped, required: true)]
    }

    private func observationFieldTitles(from table: [[String]]) -> [String] {
        guard let header = table.first else { return [] }
        let firstHeader = normalized(header.first ?? "")
        let usefulHeaderFields = header.dropFirst().map(clean).filter { !$0.isEmpty }
        if firstHeader.contains("student") || firstHeader.contains("exercise") {
            return usefulHeaderFields
        }
        let rows = table.dropFirst().isEmpty ? table : Array(table.dropFirst())
        return rows.compactMap { row in
            row.first(where: { !$0.isEmpty })
        }
    }

    private func isDocumentTitle(_ text: String) -> Bool {
        let value = normalized(text)
        return value.contains("assessment instruments") ||
            value.contains("instrumentos de evaluacion") ||
            value.contains("instrumentos de evaluación")
    }

    /// Marca el final del contenido evaluable: los párrafos de "notas para el importador"
    /// (metainstrucciones dirigidas a quien procese el documento, no a docentes/alumnado)
    /// no deben quedar enganchados como ítems del último instrumento/checklist detectado.
    private func isImporterNoteSection(_ text: String) -> Bool {
        normalized(text).contains("nota para quien importe")
    }

    private func isGradingLine(_ text: String) -> Bool {
        let value = normalized(text)
        return value == "grading model" ||
            value.contains("final sa grade") ||
            value.contains("modelo de calificacion") ||
            value.contains("modelo de calificación") ||
            value.contains("calificacion final") ||
            value.contains("calificación final")
    }

    /// Descarta párrafos de prosa (párrafos largos y/o con varias frases) para que no se
    /// confundan con un título de instrumento solo por contener una keyword suelta
    /// (p.ej. "Absorbe la antigua checklist de seguridad..." no es un heading).
    private func looksLikeHeadingProse(_ text: String) -> Bool {
        guard text.split(separator: " ").count <= 10 else { return false }
        let interior = text.hasSuffix(".") || text.hasSuffix(":") ? String(text.dropLast()) : text
        return !interior.contains(where: { ".!?".contains($0) })
    }

    private func isNumberedInstrumentHeading(_ text: String) -> Bool {
        guard text.range(of: #"^\s*\d+[\.\)]\s+"#, options: .regularExpression) != nil else { return false }
        let value = normalized(text)
        return instrumentHeadingKeywords.contains { value.contains($0) }
    }

    private func tableHeaders(_ tables: [[[String]]]) -> [String] {
        tables.flatMap { $0.first ?? [] }.map(normalized)
    }

    private func firstDouble(in text: String, pattern: String) -> Double? {
        firstString(in: text, pattern: pattern).flatMap {
            Double($0.replacingOccurrences(of: ",", with: "."))
        }
    }

    private func firstString(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private func formatPercent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private var instrumentHeadingKeywords: [String] {
        [
            "instrumento", "rubric", "rubrica", "grid", "rejilla", "checklist",
            "passport", "pasaporte", "quiz", "log", "record sheet", "diagnostic",
            "diagnostico", "adjustment", "observation", "observacion", "safety",
            "submission", "entrega", "lista de cotejo", "lista de control",
            "rubrica analitica", "escala de valoracion", "diana de evaluacion",
            "registro anecdotico", "observacion sistematica", "autoevaluacion",
            "coevaluacion", "producto final", "tarea competencial"
        ].map(normalized)
    }
}

private struct ParsedInstrumentHeading {
    let title: String
    let criterionLabel: String?
    let weightPercent: Double?
}

private enum WordDocumentBlock {
    case paragraph(String)
    case table([[String]])
}

private final class WordDocumentTableReader: NSObject, XMLParserDelegate {
    private(set) var blocks: [WordDocumentBlock] = []
    private var inParagraph = false
    private var inTable = false
    private var inRow = false
    private var inCell = false
    private var inText = false
    private var paragraphBuffer = ""
    private var cellBuffer = ""
    private var currentRow: [String] = []
    private var currentTable: [[String]] = []

    func parse(data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        if isElement(elementName, "tbl") {
            inTable = true
            currentTable = []
        } else if inTable && isElement(elementName, "tr") {
            inRow = true
            currentRow = []
        } else if inRow && isElement(elementName, "tc") {
            inCell = true
            cellBuffer = ""
        } else if isElement(elementName, "p") {
            inParagraph = true
            if !inCell { paragraphBuffer = "" }
        } else if inParagraph && isElement(elementName, "t") {
            inText = true
        } else if inParagraph && isElement(elementName, "tab") {
            append(" ")
        } else if inParagraph && isElement(elementName, "br") {
            append(" ")
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { append(string) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if isElement(elementName, "t") {
            inText = false
        } else if isElement(elementName, "p") {
            if !inCell {
                let value = clean(paragraphBuffer)
                if !value.isEmpty { blocks.append(.paragraph(value)) }
            }
            inParagraph = false
        } else if isElement(elementName, "tc") {
            currentRow.append(clean(cellBuffer))
            inCell = false
        } else if isElement(elementName, "tr") {
            currentTable.append(currentRow)
            inRow = false
        } else if isElement(elementName, "tbl") {
            let rows = currentTable.filter { row in row.contains { !$0.isEmpty } }
            if !rows.isEmpty { blocks.append(.table(rows)) }
            inTable = false
        }
    }

    private func append(_ string: String) {
        if inCell {
            cellBuffer += string
        } else {
            paragraphBuffer += string
        }
    }

    private func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isElement(_ elementName: String, _ localName: String) -> Bool {
        elementName == "w:\(localName)" || elementName.hasSuffix(":\(localName)") || elementName == localName
    }
}
