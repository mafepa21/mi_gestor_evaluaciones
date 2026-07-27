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
    /// Cuando el campo procede de una rejilla "sesión × indicador" (`obs_s<N>_i<M>`),
    /// esta clave permite a la capa de materialización/agregación reconocer a qué
    /// sesión e indicador pertenece cada respuesta 1-4. `nil` para campos genéricos.
    var key: String? = nil
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
        // A4: una vez alcanzada la sección "Nota para quien importe" (metainstrucciones para
        // quien procese el documento, no para docentes/alumnado) se ignora el resto del
        // documento: sin esta bandera, párrafos posteriores como una explicación de la
        // fórmula seguían evaluándose y podían machacar `gradingFormula` con una nota interna.
        var reachedImporterNotes = false

        func flushCurrent() {
            guard let heading = currentHeading else { return }
            let (instrument, extraWarnings) = makeInstrument(from: heading, tables: pendingTables, paragraphs: pendingParagraphs)
            if let instrument {
                instruments.append(instrument)
            } else {
                warnings.append("No se ha podido interpretar \(heading.title).")
            }
            warnings.append(contentsOf: extraWarnings)
            pendingTables = []
            pendingParagraphs = []
        }

        for block in blocks {
            if reachedImporterNotes { continue }
            switch block {
            case .paragraph(let text):
                let cleanText = clean(text)
                guard !cleanText.isEmpty else { continue }
                if isDocumentTitle(cleanText) {
                    continue
                } else if isImporterNoteSection(cleanText) {
                    flushCurrent()
                    currentHeading = nil
                    reachedImporterNotes = true
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
        // A8(a): antes, este aviso solo se emitía si no había fórmula de calificación, pero
        // todos los documentos reales la llevan, así que nunca saltaba. Ahora se emite siempre
        // que la suma se desvíe de 100, tenga o no fórmula.
        let weightedTotal = instruments.compactMap(\.weightPercent).reduce(0, +)
        if weightedTotal > 0, abs(weightedTotal - 100) > 0.5 {
            warnings.append("La suma de ponderaciones detectada es \(formatPercent(weightedTotal)); revisa el reparto antes de crear columnas.")
        }
        // A8(b): verificación cruzada entre los términos "Texto (NN%)" de la fórmula de
        // calificación y los instrumentos realmente detectados.
        if let gradingFormula {
            warnings.append(contentsOf: unmatchedGradingFormulaWarnings(gradingFormula, instruments: instruments))
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
        try wordDocumentBlocks(from: data)
    }

    private func makeInstrument(from heading: ParsedInstrumentHeading, tables: [[[String]]], paragraphs: [String]) -> (AssessmentInstrumentDraft?, [String]) {
        let normalizedTitle = normalized(heading.title)
        let nonEmptyTables = tables
            .map { $0.map { row in row.map(clean) }.filter { row in row.contains { !$0.isEmpty } } }
            .filter { !$0.isEmpty }
        let kind = inferKind(title: normalizedTitle, tables: nonEmptyTables)
        let rubric = makeRubric(kind: kind, tables: nonEmptyTables)
        let (checklistItems, consumedParagraphs1) = makeChecklistItemsCollectingConsumption(kind: kind, tables: nonEmptyTables, paragraphs: paragraphs)
        let observationFields = makeObservationFields(kind: kind, tables: nonEmptyTables)
        let (quizQuestions, consumedParagraphs2) = makeQuizQuestionsCollectingConsumption(kind: kind, tables: nonEmptyTables, paragraphs: paragraphs)

        // A7: si la rejilla tiene peso y ninguna de sus columnas trae ya una escala explícita
        // "1-4", pero la última cabecera es claramente una columna de nota (nota/note/mark/
        // score), se asume escala 1-4 y se avisa para que el docente lo revise.
        var extraWarnings: [String] = []
        var effectiveObservationFields = observationFields
        if kind == .observationGrid, (heading.weightPercent ?? 0) > 0, !hasObservationScale1To4(observationFields) {
            if lastHeaderLooksLikeNoteColumn(nonEmptyTables) {
                effectiveObservationFields = observationFields.map { field in
                    var copy = field
                    if copy.scaleLabel == nil || !normalized(copy.scaleLabel!).contains("1") {
                        copy.scaleLabel = "1-4"
                    }
                    return copy
                }
                extraWarnings.append("Se asume escala 1-4 en «\(heading.title)»; revísalo si el documento usa otra escala.")
            }
        }

        let selectedByDefault = (heading.weightPercent ?? 0) > 0
        let scoreStrategy = defaultScoreStrategy(
            kind: kind,
            weightPercent: heading.weightPercent,
            checklistItems: checklistItems,
            observationFields: effectiveObservationFields
        )
        // A6: `.checklistProportional` refleja que el documento SÍ pondera la checklist, y desde
        // el soporte de nota proporcional (`ítems marcados / total × 10`, derivada en
        // `NotebookInstrumentsRepositorySqlDelight.saveResponses`) la columna materializada sí
        // suma a la media. `countsTowardAverage` sigue alineado con lo que la materialización
        // real puede calcular hoy (mismo criterio que `canMaterializeAverage` en KmpBridge.swift).
        let materializesAverageAutomatically: Bool
        switch scoreStrategy {
        case .numeric0To10, .rubric, .checklistAllOrNothing, .observationScale1To4,
             .quizPercentCorrect, .checklistProportional:
            materializesAverageAutomatically = true
        case .none:
            materializesAverageAutomatically = false
        }
        let countsTowardAverage = materializesAverageAutomatically && (heading.weightPercent ?? 0) > 0

        if rubric == nil, checklistItems.isEmpty, effectiveObservationFields.isEmpty, quizQuestions.isEmpty {
            return (nil, extraWarnings)
        }

        // A5: los párrafos que no se han consumido como ítems de checklist ni como preguntas de
        // quiz llevan a menudo información real (momento de recogida, escala, criterio de
        // agregación...) que la guía de autoría promete conservar como nota del instrumento.
        let consumed = consumedParagraphs1.union(consumedParagraphs2)
        let narrativeNotes = paragraphs.enumerated()
            .filter { !consumed.contains($0.offset) }
            .map(\.element)
        var noteText: String?
        if countsTowardAverage {
            var parts: [String] = []
            if scoreStrategy == .checklistProportional {
                let weightText = heading.weightPercent.map(formatPercent) ?? "peso detectado"
                parts.append("Checklist ponderada (\(weightText)): la nota se calcula como ítems marcados ÷ ítems totales × 10.")
            }
            parts.append(contentsOf: narrativeNotes)
            noteText = parts.isEmpty ? nil : parts.joined(separator: "\n")
        } else {
            var parts: [String] = ["Auxiliar o sin puntuación computable detectada"]
            parts.append(contentsOf: narrativeNotes)
            noteText = parts.joined(separator: "\n")
        }

        return (AssessmentInstrumentDraft(
            title: heading.title,
            kind: kind,
            criterionLabel: heading.criterionLabel,
            weightPercent: heading.weightPercent,
            isSelected: selectedByDefault,
            countsTowardAverage: countsTowardAverage,
            scoreStrategy: scoreStrategy,
            rubric: rubric,
            checklistItems: checklistItems,
            observationFields: effectiveObservationFields,
            quizQuestions: quizQuestions,
            note: noteText
        ), extraWarnings)
    }

    private func lastHeaderLooksLikeNoteColumn(_ tables: [[[String]]]) -> Bool {
        tables.contains { table in
            guard let header = table.first, let last = header.last, !last.isEmpty else { return false }
            let value = normalized(last)
            return value.contains("nota") || value.contains("note") || value.contains("mark") || value.contains("score")
        }
    }

    private func defaultScoreStrategy(
        kind: AssessmentInstrumentKind,
        weightPercent: Double?,
        checklistItems: [ChecklistItemDraft],
        observationFields: [ObservationFieldDraft]
    ) -> AssessmentInstrumentScoreStrategy {
        guard (weightPercent ?? 0) > 0 else { return .none }
        switch kind {
        case .rubric:
            return .rubric
        case .observationGrid:
            return hasObservationScale1To4(observationFields) ? .observationScale1To4 : .none
        case .checklist:
            // A6: si la checklist tiene ítems y el documento le asigna peso, es computable de
            // forma proporcional (número de ítems marcados / total). `submissionChecklist` y
            // `teacherObservation` siguen sin puntuar: son requisito de entrega y registro de
            // apoyo, y en los documentos reales nunca llevan "%".
            return checklistItems.isEmpty ? .none : .checklistProportional
        case .submissionChecklist:
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

    /// A5: además de los ítems, devuelve los índices de `paragraphs` que se han consumido
    /// (los que sí aportaron algún ítem de checklist), para que el resto pueda conservarse
    /// como nota narrativa del instrumento.
    private func makeChecklistItemsCollectingConsumption(kind: AssessmentInstrumentKind, tables: [[[String]]], paragraphs: [String]) -> ([ChecklistItemDraft], Set<Int>) {
        guard kind == .checklist || kind == .submissionChecklist else { return ([], []) }
        let tableItems = tables.flatMap { table in
            let rows = table.dropFirst().isEmpty ? table : Array(table.dropFirst())
            return rows.compactMap { row -> ChecklistItemDraft? in
                guard let title = row.first(where: { !$0.isEmpty }) else { return nil }
                return ChecklistItemDraft(title: title, required: true)
            }
        }
        var items = tableItems
        var consumed: Set<Int> = []
        for (index, paragraph) in paragraphs.enumerated() {
            let extracted = checklistItems(from: paragraph)
            guard !extracted.isEmpty else { continue }
            items.append(contentsOf: extracted)
            consumed.insert(index)
        }
        return (items, consumed)
    }

    /// A5: variante de `makeQuizQuestions` que además informa qué párrafos se han consumido.
    private func makeQuizQuestionsCollectingConsumption(kind: AssessmentInstrumentKind, tables: [[[String]]], paragraphs: [String]) -> ([QuizQuestionDraft], Set<Int>) {
        guard kind == .quizQuestions else { return ([], []) }
        let tableQuestions = tables.flatMap { table -> [QuizQuestionDraft] in
            let rows = table.dropFirst().isEmpty ? table : Array(table.dropFirst())
            return rows.compactMap { row -> QuizQuestionDraft? in
                guard let text = row.first(where: { !$0.isEmpty }) else { return nil }
                let options = Array(row.dropFirst()).map(clean).filter { !$0.isEmpty }
                return QuizQuestionDraft(questionText: text, options: options)
            }
        }
        var questions = tableQuestions
        var consumed: Set<Int> = []
        for (index, paragraph) in paragraphs.enumerated() {
            guard let question = quizQuestion(from: paragraph) else { continue }
            questions.append(question)
            consumed.insert(index)
        }
        return (questions, consumed)
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
            options = slashOptions.options
            text = slashOptions.questionText
        }
        return QuizQuestionDraft(questionText: text, options: options)
    }

    /// A9: la pregunta y sus opciones separadas por " / " no siempre van precedidas de "?"
    /// (p.ej. "Una bebida con mucha cafeína... puede afectar a: sueño / FC / hidratación /
    /// todas."). Si hay "?", se corta ahí como antes; si no, se usa el último ":" del texto
    /// como punto de corte entre pregunta y opciones.
    private func optionsFromSlashList(_ text: String) -> (questionText: String, options: [String])? {
        let cutRange: Range<String.Index>?
        if let questionMarkRange = text.range(of: "?", options: .backwards) {
            cutRange = questionMarkRange
        } else if let colonRange = text.range(of: ":", options: .backwards) {
            cutRange = colonRange
        } else {
            cutRange = nil
        }
        guard let cutRange else { return nil }
        let tail = String(text[cutRange.upperBound...])
        guard tail.contains(" / ") else { return nil }
        let parts = tail
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .components(separatedBy: " / ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count > 1 else { return nil }
        let questionText = String(text[..<cutRange.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (questionText, parts)
    }

    private func makeObservationFields(kind: AssessmentInstrumentKind, tables: [[[String]]]) -> [ObservationFieldDraft] {
        guard kind == .teacherObservation || kind == .observationGrid else { return [] }
        return tables.flatMap { table -> [ObservationFieldDraft] in
            if let sessionFields = sessionIndicatorObservationFields(from: table) {
                return sessionFields
            }
            let header = table.first ?? []
            let scale = header.dropFirst().filter { !$0.isEmpty }.joined(separator: " / ")
            let fieldTitles = observationFieldTitles(from: table)
            return fieldTitles.map { title in
                ObservationFieldDraft(title: title, scaleLabel: scale.isEmpty ? nil : scale)
            }
        }
    }

    /// Detecta la forma "Alumno/a | Momento | indicador1 | ... | indicadorN | Nota (1-4)"
    /// (una fila por sesión de observación fija) y genera un campo por sesión×indicador
    /// en vez de un campo genérico por columna, para poder rellenar cada sesión con sus
    /// indicadores 1-4 de forma independiente. Devuelve `nil` si la tabla no tiene esa forma.
    private func sessionIndicatorObservationFields(from table: [[String]]) -> [ObservationFieldDraft]? {
        guard let header = table.first, header.count >= 4 else { return nil }
        let normalizedHeader = header.map(normalized)
        guard let firstHeader = normalizedHeader.first,
              firstHeader.contains("alumno") || firstHeader.contains("student"),
              normalizedHeader.count > 1,
              normalizedHeader[1].contains("momento") || normalizedHeader[1].contains("moment") else {
            return nil
        }

        var indicatorEnd = header.count
        if let lastHeader = normalizedHeader.last,
           lastHeader.contains("nota") || lastHeader.contains("mark") || lastHeader.contains("score") {
            indicatorEnd -= 1
        }
        let indicatorRange = 2..<indicatorEnd
        guard !indicatorRange.isEmpty else { return nil }
        let indicatorTitles = indicatorRange.map { clean(header[$0]) }

        let dataRows = table.dropFirst().filter { row in
            row.count > 1 && !row[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !dataRows.isEmpty else { return nil }

        var fields: [ObservationFieldDraft] = []
        for (sessionIndex, row) in dataRows.enumerated() {
            let sessionLabel = clean(row[1])
            for (indicatorOffset, columnIndex) in indicatorRange.enumerated() {
                guard columnIndex < row.count else { continue }
                let indicatorTitle = indicatorTitles[indicatorOffset]
                fields.append(ObservationFieldDraft(
                    title: "\(sessionLabel) · \(indicatorTitle)",
                    scaleLabel: "1-4",
                    key: "obs_s\(sessionIndex)_i\(indicatorOffset)"
                ))
            }
        }
        return fields
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
        let withoutNumber = cleanText
            .replacingOccurrences(of: #"^\s*\d+[\.\)]\s*"#, with: "", options: .regularExpression)
        let weight = firstDouble(in: withoutNumber, pattern: #"([0-9]+(?:[.,][0-9]+)?)\s*%"#)

        // A3: antes solo se recortaba UN "- CE X.X" y UN "- NN%", así que un encabezado con
        // varios criterios ("- CE 1.2 y 1.4 (proceso) - 35%") dejaba el título contaminado
        // ("...y 1.4 (proceso)") y perdía todos los códigos menos el primero. Ahora se corta en
        // el primer separador que introduce metadatos y se extraen todos los códigos de la cola.
        let metadataBoundary = withoutNumber.range(
            of: #"\s[-–—]\s*(?:CE\s*\d|Criteri[oa]?\s*\d|\d+(?:[.,]\d+)?\s*%)"#,
            options: [.regularExpression, .caseInsensitive]
        )
        let title: String
        let criterion: String?
        if let boundary = metadataBoundary {
            title = String(withoutNumber[..<boundary.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = String(withoutNumber[boundary.lowerBound...])
            let tailWithoutWeight = tail.replacingOccurrences(
                of: #"[-–—]?\s*[0-9]+(?:[.,][0-9]+)?\s*%"#,
                with: "",
                options: .regularExpression
            )
            let codes = allCriterionCodes(in: tailWithoutWeight)
            criterion = codes.isEmpty ? nil : codes.joined(separator: " · ")
        } else {
            title = withoutNumber.trimmingCharacters(in: CharacterSet(charactersIn: " -–—\t\n\r"))
            let codes = allCriterionCodes(in: withoutNumber)
            criterion = codes.isEmpty ? nil : codes.joined(separator: " · ")
        }
        let finalTitle = title.isEmpty ? cleanText : title
        return ParsedInstrumentHeading(title: finalTitle, criterionLabel: criterion, weightPercent: weight)
    }

    /// Extrae todos los códigos de criterio de un fragmento de texto (con o sin prefijo
    /// "CE"/"Criterio"/"Criteri") y los normaliza siempre a la forma "CE X.X", sin duplicados.
    private func allCriterionCodes(in text: String) -> [String] {
        criterionCodesInText(text)
    }

    /// A8(b): compara los términos "Texto (NN%)" de la fórmula de calificación final con los
    /// títulos de los instrumentos detectados y avisa de los que no encuentran pareja.
    private func unmatchedGradingFormulaWarnings(_ gradingFormula: String, instruments: [AssessmentInstrumentDraft]) -> [String] {
        let rhs: Substring
        if let equalsRange = gradingFormula.range(of: "=") {
            rhs = gradingFormula[equalsRange.upperBound...]
        } else {
            rhs = Substring(gradingFormula)
        }
        let termPattern = try? NSRegularExpression(pattern: #"^(.*?)\s*\(\s*[0-9]+(?:[.,][0-9]+)?\s*%\s*\)\s*$"#)
        let normalizedInstrumentTitles = instruments.map { normalized($0.title) }
        var warnings: [String] = []
        for rawTerm in rhs.components(separatedBy: "+") {
            let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            let nsTerm = term as NSString
            guard let match = termPattern?.firstMatch(in: term, range: NSRange(location: 0, length: nsTerm.length)),
                  let titleRange = Range(match.range(at: 1), in: term) else { continue }
            let termTitle = String(term[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !termTitle.isEmpty else { continue }
            let normalizedTermTitle = normalized(termTitle)
            let matches = normalizedInstrumentTitles.contains { instrumentTitle in
                instrumentTitle.contains(normalizedTermTitle) || normalizedTermTitle.contains(instrumentTitle)
            }
            if !matches {
                warnings.append("La fórmula menciona «\(termTitle)» pero no se ha detectado ningún instrumento con ese nombre.")
            }
        }
        return warnings
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
        // A1: los puntos decimales ("CE 2.1") y los porcentajes ("40%") no son puntuación de
        // prosa; sin neutralizarlos antes, cualquier encabezado sin numerar con un criterio
        // decimal ("Rúbrica... - CE 2.1 - 40%") se descartaba por el "." de "2.1".
        let neutralized = text
            .replacingOccurrences(of: #"\d+[.,]\d+"#, with: "0", options: .regularExpression)
            .replacingOccurrences(of: #"\d+\s*%"#, with: "0", options: .regularExpression)
        let interior = neutralized.hasSuffix(".") || neutralized.hasSuffix(":") ? String(neutralized.dropLast()) : neutralized
        return !interior.contains(where: { ".!?".contains($0) })
    }

    private func isNumberedInstrumentHeading(_ text: String) -> Bool {
        guard text.range(of: #"^\s*\d+[\.\)]\s+"#, options: .regularExpression) != nil else { return false }
        let value = normalized(text)
        if instrumentHeadingKeywords.contains(where: { value.contains($0) }) {
            return true
        }
        // A2: un párrafo numerado que además lleve "NN%" y/o "CE X.X" es un encabezado de
        // instrumento aunque su título no use ninguna palabra clave conocida (p.ej.
        // "4. Mini-portafolio de datos y reflexión - CE 3.3 - 15%").
        let hasWeight = text.range(of: #"[0-9]+(?:[.,][0-9]+)?\s*%"#, options: .regularExpression) != nil
        let hasCriterion = text.range(of: #"CE\s*\d+(?:\.\d+)?"#, options: [.regularExpression, .caseInsensitive]) != nil
        return hasWeight || hasCriterion
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
            "coevaluacion", "producto final", "tarea competencial",
            "cuestionario", "test", "portafolio", "mini-portafolio", "informe",
            "proyecto", "diario", "registro"
        ].map(normalized)
    }
}

/// Compartido entre los tres importadores de documentos de Situaciones de Aprendizaje: extrae
/// todos los códigos de criterio de un texto ("CE 1.2", "Criteri 1.1", "Criterio 3.2 (CE3)",
/// "2.1" a secas...) y los normaliza siempre a la forma "CE X.X", sin duplicados y descartando
/// el resto del texto (incluido el contenido entre paréntesis).
func criterionCodesInText(_ text: String) -> [String] {
    guard let regex = try? NSRegularExpression(
        pattern: #"(?:CE|Criteri[oa]?|Criterion)?\s*([0-9]+\.[0-9]+)"#,
        options: [.caseInsensitive]
    ) else { return [] }
    let nsText = text as NSString
    var seen = Set<String>()
    var results: [String] = []
    regex.enumerateMatches(in: text, range: NSRange(location: 0, length: nsText.length)) { match, _, _ in
        guard let match, let range = Range(match.range(at: 1), in: text) else { return }
        let code = "CE \(text[range])"
        if seen.insert(code).inserted { results.append(code) }
    }
    return results
}

/// Compartido entre los tres importadores de documentos de Situaciones de Aprendizaje
/// (instrumentos, programación y secuencia de sesiones): descomprime `word/document.xml`
/// y lo vuelca en bloques de párrafo/tabla en orden de aparición.
func wordDocumentBlocks(from data: Data) throws -> [WordDocumentBlock] {
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

private struct ParsedInstrumentHeading {
    let title: String
    let criterionLabel: String?
    let weightPercent: Double?
}

enum WordDocumentBlock {
    case paragraph(String)
    case table([[String]])
}

final class WordDocumentTableReader: NSObject, XMLParserDelegate {
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
