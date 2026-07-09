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
        case .quizQuestions: return "Quiz / Test"
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
        case .quizPercentCorrect: return "Porcentaje de aciertos"
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

struct QuizQuestionDraft: Codable {
    var questionText: String
    var questionType: QuizQuestionType
    var options: [String]
    var correctAnswer: String?
}

enum QuizQuestionType: String, Codable {
    case multipleChoice
    case trueFalse
    case fillInTheBlank
    case openEnded
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
    var quizQuestions: [QuizQuestionDraft]
    var observationFields: [ObservationFieldDraft]
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
        quizQuestions: [QuizQuestionDraft] = [],
        observationFields: [ObservationFieldDraft] = [],
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
        self.quizQuestions = quizQuestions
        self.observationFields = observationFields
        self.note = note
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
    var indicatorTitles: [String] = []
}

extension AssessmentInstrumentDraft {
    var hasStructuredObservationIndicators: Bool {
        observationFields.contains { !$0.indicatorTitles.isEmpty }
    }
}

struct LearningSituationAssessmentInstrumentsImportService {
    func preview(from url: URL) throws -> LearningSituationAssessmentImportDraft {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
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
                } else if isImporterMetaNote(cleanText) {
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
        let quizQuestions = kind == .quizQuestions ? makeQuizQuestions(paragraphs: paragraphs) : []
        let observationFields = makeObservationFields(kind: kind, tables: nonEmptyTables)

        // Un parrafo que aporta contenido estructurado (item de checklist o pregunta de
        // quiz) no se duplica como nota; si tenia texto de contexto antes del primer
        // marcador, ese fragmento se conserva igualmente como anotacion.
        let annotations: [String] = paragraphs.compactMap { paragraph -> String? in
            let cleanPara = clean(paragraph)
            guard !cleanPara.isEmpty else { return nil }
            if kind == .checklist || kind == .submissionChecklist,
               !parseChecklistItems(from: paragraph).isEmpty {
                let preamble = checklistPreamble(from: paragraph)
                return preamble.isEmpty ? nil : preamble
            }
            if kind == .quizQuestions, quizQuestion(from: paragraph) != nil {
                return nil
            }
            return cleanPara
        }

        let note = annotations.isEmpty ? nil : annotations.joined(separator: "\n")
        
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
            quizQuestions: quizQuestions,
            observationFields: observationFields,
            note: note
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

    private func makeQuizQuestions(paragraphs: [String]) -> [QuizQuestionDraft] {
        paragraphs.compactMap(quizQuestion(from:))
    }

    private func slashOptions(in text: String) -> (questionText: String, options: [String])? {
        let optionsPattern = #"([A-Za-z0-9\sáéíóúÁÉÍÓÚñÑ]+(?:\s*/\s*[A-Za-z0-9\sáéíóúÁÉÍÓÚñÑ]+)+)"#
        guard let regex = try? NSRegularExpression(pattern: optionsPattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let optionsText = String(text[range])
        let options = optionsText.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard options.count > 1 else { return nil }
        let questionText = text.replacingOccurrences(of: optionsText, with: "").trimmingCharacters(in: CharacterSet(charactersIn: " :.\t\n\r"))
        return (questionText.isEmpty ? text : questionText, options)
    }

    private func quizQuestion(from paragraph: String) -> QuizQuestionDraft? {
        let cleanPara = clean(paragraph)
        guard !cleanPara.isEmpty else { return nil }

        if cleanPara.hasPrefix("- [ ]") || cleanPara.hasPrefix("[ ]") || cleanPara.hasPrefix("-") || cleanPara.hasPrefix("•") {
            return nil
        }

        let hasQuestionMark = cleanPara.contains("?") || cleanPara.contains("¿")
        let hasFillInBlank = cleanPara.contains("____")
        let hasTrueFalse = normalized(cleanPara).contains("verdadero o falso") || normalized(cleanPara).contains("true or false")
        let slash = slashOptions(in: cleanPara)

        guard hasQuestionMark || hasFillInBlank || hasTrueFalse || slash != nil else { return nil }

        if hasTrueFalse {
            return QuizQuestionDraft(
                questionText: cleanPara,
                questionType: .trueFalse,
                options: ["Verdadero", "Falso"],
                correctAnswer: nil
            )
        } else if hasFillInBlank {
            return QuizQuestionDraft(
                questionText: cleanPara,
                questionType: .fillInTheBlank,
                options: [],
                correctAnswer: nil
            )
        } else if let slash {
            return QuizQuestionDraft(
                questionText: slash.questionText,
                questionType: .multipleChoice,
                options: slash.options,
                correctAnswer: nil
            )
        }

        return QuizQuestionDraft(
            questionText: cleanPara,
            questionType: .openEnded,
            options: [],
            correctAnswer: nil
        )
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
        let paragraphItems = paragraphs.flatMap(parseChecklistItems(from:))
        return tableItems + paragraphItems
    }

    private func makeObservationFields(kind: AssessmentInstrumentKind, tables: [[[String]]]) -> [ObservationFieldDraft] {
        guard kind == .teacherObservation || kind == .observationGrid else { return [] }
        return tables.flatMap { table -> [ObservationFieldDraft] in
            let header = table.first ?? []
            let scale = header.dropFirst().filter { !$0.isEmpty }.joined(separator: " / ")
            let fieldTitles = observationFieldTitles(from: table)
            let indicatorTitles = observationIndicatorTitles(from: table)
            return fieldTitles.map { title in
                ObservationFieldDraft(
                    title: title,
                    scaleLabel: scale.isEmpty ? nil : scale,
                    indicatorTitles: indicatorTitles
                )
            }
        }
    }

    // Solo aporta indicadores cuando `observationFieldTitles` resolvio en modo
    // "fila = titulo" (cabecera sin "student"/"exercise", ej. "Alumno/a"). En ese
    // caso las columnas de indicador reales son todas las que no sean: la columna
    // usada como titulo de fila (la que aporta el primer valor no vacio de cada
    // fila, normalmente "Momento") ni ninguna cuyo nombre normalizado contenga
    // "nota" (la columna de nota final de fila, no un indicador evaluable).
    private func observationIndicatorTitles(from table: [[String]]) -> [String] {
        guard let header = table.first else { return [] }
        let firstHeader = normalized(header.first ?? "")
        guard !(firstHeader.contains("student") || firstHeader.contains("exercise")) else { return [] }
        let rows = table.dropFirst().isEmpty ? table : Array(table.dropFirst())
        var excludedIndices = Set(rows.compactMap { row in
            row.firstIndex(where: { !$0.isEmpty })
        })
        excludedIndices.insert(0) // primera columna: alumno/a, nunca es indicador
        return header.enumerated().filter { index, column in
            let cleanColumn = clean(column)
            guard !cleanColumn.isEmpty else { return false }
            guard !excludedIndices.contains(index) else { return false }
            return !normalized(cleanColumn).contains("nota")
        }.map { clean($0.element) }
    }

    private func inferKind(title: String, tables: [[[String]]]) -> AssessmentInstrumentKind {
        if title.contains("submission") || title.contains("entrega") || title.contains("final checklist") || title.contains("producto final") {
            return .submissionChecklist
        }
        if title.contains("quiz") || title.contains("test") || title.contains("cuestionario") {
            if tables.isEmpty {
                return .quizQuestions
            }
            return .checklist
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
        // Un titulo sin numerar es corto (p.ej. "Checklist final de entrega - Sesion 10").
        // Sin este limite de longitud, cualquier parrafo narrativo que mencione de pasada
        // una palabra clave ("instrumento", "checklist", "coevaluacion"...) se confundiria
        // con un encabezado nuevo y rompería el agrupamiento de tablas/anotaciones.
        let isExplicitUnnumberedHeading = cleanText.count <= 70
            && instrumentHeadingKeywords.contains { normalizedText.contains($0) }
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

    private func checklistPreamble(from paragraph: String) -> String {
        let cleanText = clean(paragraph)
        guard let regex = try? NSRegularExpression(pattern: #"(?:-\s*)?\[\s?\]"#),
              let firstMatch = regex.firstMatch(in: cleanText, range: NSRange(cleanText.startIndex..., in: cleanText)),
              let markerRange = Range(firstMatch.range, in: cleanText) else {
            return ""
        }
        return clean(String(cleanText[cleanText.startIndex..<markerRange.lowerBound]))
    }

    private func parseChecklistItems(from paragraph: String) -> [ChecklistItemDraft] {
        let cleanText = clean(paragraph)
        guard !cleanText.isEmpty else { return [] }

        // Extrae solo el texto que sigue a cada marcador "- [ ] "/"[ ] ", ignorando
        // cualquier frase de contexto que preceda al primer marcador en el parrafo.
        let markerItemPattern = #"(?:-\s*)?\[\s?\]\s*(.+?)(?=\s*(?:-\s*)?\[\s?\]|$)"#
        if let regex = try? NSRegularExpression(pattern: markerItemPattern) {
            let range = NSRange(cleanText.startIndex..., in: cleanText)
            let matches = regex.matches(in: cleanText, range: range)
            let items = matches.compactMap { match -> ChecklistItemDraft? in
                guard let itemRange = Range(match.range(at: 1), in: cleanText) else { return nil }
                let title = clean(String(cleanText[itemRange]))
                guard !title.isEmpty, !normalized(title).hasPrefix("tick before") else { return nil }
                return ChecklistItemDraft(title: title, required: true)
            }
            if !items.isEmpty { return items }
        }

        if cleanText.hasPrefix("-") || cleanText.hasPrefix("•") || cleanText.hasPrefix("*") {
            var itemText = cleanText
            while itemText.hasPrefix("-") || itemText.hasPrefix("•") || itemText.hasPrefix("*") {
                itemText.removeFirst()
                itemText = itemText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !itemText.isEmpty {
                return [ChecklistItemDraft(title: itemText, required: true)]
            }
        }
        
        if cleanText.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) != nil && cleanText.count < 120 {
            return [ChecklistItemDraft(title: cleanText, required: true)]
        }
        
        return []
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

    private func isImporterMetaNote(_ text: String) -> Bool {
        let value = normalized(text)
        return value.contains("nota para quien importe") ||
            value.contains("nota para el importador") ||
            value.contains("note for whoever imports")
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
