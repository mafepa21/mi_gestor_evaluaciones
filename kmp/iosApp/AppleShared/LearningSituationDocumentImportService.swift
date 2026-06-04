import Foundation
import CryptoKit
import ZIPFoundation

struct LearningSituationImportDraft: Identifiable, Codable {
    let id: UUID
    var title: String
    var stageLabel: String
    var courseLabel: String
    var subjectLabel: String
    var termLabel: String
    var centerLabel: String
    var sessionCount: Int
    var challenge: String
    var finalProduct: String
    var justification: String
    var competencies: [String]
    var criteria: [LearningSituationCriterionDraft]
    var knowledge: [String]
    var methodology: [String]
    var inclusionMeasures: [String]
    var evaluationItems: [LearningSituationEvaluationDraft]
    var warnings: [String]
    var selectedClassIds: Set<Int64> = []
    let sourceURL: URL
    let sourceFileName: String
    let sha256: String
    let sizeBytes: Int64

    init(
        title: String,
        stageLabel: String,
        courseLabel: String,
        subjectLabel: String,
        termLabel: String,
        centerLabel: String,
        sessionCount: Int,
        challenge: String,
        finalProduct: String,
        justification: String,
        competencies: [String],
        criteria: [LearningSituationCriterionDraft],
        knowledge: [String],
        methodology: [String],
        inclusionMeasures: [String],
        evaluationItems: [LearningSituationEvaluationDraft],
        warnings: [String],
        sourceURL: URL,
        sourceFileName: String,
        sha256: String,
        sizeBytes: Int64
    ) {
        self.id = UUID()
        self.title = title
        self.stageLabel = stageLabel
        self.courseLabel = courseLabel
        self.subjectLabel = subjectLabel
        self.termLabel = termLabel
        self.centerLabel = centerLabel
        self.sessionCount = sessionCount
        self.challenge = challenge
        self.finalProduct = finalProduct
        self.justification = justification
        self.competencies = competencies
        self.criteria = criteria
        self.knowledge = knowledge
        self.methodology = methodology
        self.inclusionMeasures = inclusionMeasures
        self.evaluationItems = evaluationItems
        self.warnings = warnings
        self.sourceURL = sourceURL
        self.sourceFileName = sourceFileName
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
    }

    var payloadJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

struct LearningSituationCriterionDraft: Identifiable, Codable {
    let id: UUID
    var criterion: String
    var evidence: String

    init(criterion: String, evidence: String = "") {
        self.id = UUID()
        self.criterion = criterion
        self.evidence = evidence
    }
}

struct LearningSituationEvaluationDraft: Identifiable, Codable {
    let id: UUID
    var title: String
    var criterionLabel: String
    var weightPercent: Double?
    var rubricId: Int64?
    var isSelected: Bool = false

    init(title: String, criterionLabel: String, weightPercent: Double?) {
        self.id = UUID()
        self.title = title
        self.criterionLabel = criterionLabel
        self.weightPercent = weightPercent
        self.rubricId = nil
    }
}

struct LearningSituationSessionSectionDraft: Identifiable, Codable {
    let id: UUID
    var title: String
    var lines: [String]

    init(title: String, lines: [String]) {
        self.id = UUID()
        self.title = title
        self.lines = lines
    }
}

struct LearningSituationSessionPlanDraft: Identifiable, Codable {
    let id: UUID
    var sessionNumber: Int
    var sourceLabel: String
    var title: String
    var sessionType: String
    var effectiveMinutes: Int
    var objective: String
    var criteria: [String]
    var material: String
    var development: [LearningSituationSessionSectionDraft]
    var adaptations: [String]

    init(
        sessionNumber: Int,
        sourceLabel: String,
        title: String,
        sessionType: String,
        effectiveMinutes: Int,
        objective: String,
        criteria: [String],
        material: String,
        development: [LearningSituationSessionSectionDraft],
        adaptations: [String]
    ) {
        self.id = UUID()
        self.sessionNumber = sessionNumber
        self.sourceLabel = sourceLabel
        self.title = title
        self.sessionType = sessionType
        self.effectiveMinutes = effectiveMinutes
        self.objective = objective
        self.criteria = criteria
        self.material = material
        self.development = development
        self.adaptations = adaptations
    }

    var developmentSummary: String {
        development.map { section in
            ([section.title] + section.lines).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

struct LearningSituationSessionSequenceImportDraft: Identifiable, Codable {
    let id: UUID
    var plans: [LearningSituationSessionPlanDraft]
    var warnings: [String]
    let sourceURL: URL
    let sourceFileName: String
    let sha256: String
    let sizeBytes: Int64

    init(plans: [LearningSituationSessionPlanDraft], warnings: [String], sourceURL: URL, sourceFileName: String, sha256: String, sizeBytes: Int64) {
        self.id = UUID()
        self.plans = plans
        self.warnings = warnings
        self.sourceURL = sourceURL
        self.sourceFileName = sourceFileName
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
    }

    var payloadJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

enum LearningSituationImportError: LocalizedError {
    case unreadableDocument
    case missingDocumentBody

    var errorDescription: String? {
        switch self {
        case .unreadableDocument: return "No se ha podido leer el documento Word."
        case .missingDocumentBody: return "El documento no contiene texto reconocible."
        }
    }
}

struct LearningSituationDocumentImportService {
    func preview(from url: URL) throws -> LearningSituationImportDraft {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let paragraphs = try readParagraphs(from: data).filter { !$0.isEmpty }
        guard !paragraphs.isEmpty else { throw LearningSituationImportError.missingDocumentBody }

        var title = url.deletingPathExtension().lastPathComponent
        if let found = paragraphs.first(where: {
            let norm = normalized($0)
            return norm.contains("situacion de aprendizaje") ||
                   norm.hasPrefix("sa ") ||
                   norm.hasPrefix("sa:") ||
                   norm.range(of: "^sa\\s*\\d+", options: [.regularExpression, .caseInsensitive]) != nil
        }) {
            title = cleanBulletPrefix(found)
        } else if let first = paragraphs.first, first.count > 3, first.count < 150 {
            title = cleanBulletPrefix(first)
        }

        let challenge = textFollowingHeading(["Pregunta Motriz", "Driving question"], paragraphs: paragraphs)
        let finalProduct = textFollowingHeading(["Producto Final", "Final product"], paragraphs: paragraphs)
        let criteria = criterionDrafts(from: paragraphs)
        
        let evaluationItems = paragraphs
            .filter { paragraph in
                let clean = paragraph.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                guard clean.contains("%") else { return false }
                return clean.contains("criterio") ||
                       clean.contains("criterion") ||
                       clean.contains("total") ||
                       clean.contains("ce ") ||
                       clean.contains("ce.") ||
                       clean.range(of: "\\bce\\s*\\d", options: .regularExpression) != nil
            }
            .map { evaluationDraft(from: $0) }

        let stage = metadataValue(forPatterns: ["etapa", "stage"], in: paragraphs)
        let course = metadataValue(forPatterns: ["curso", "grade"], in: paragraphs)
        let subject = metadataValue(forPatterns: ["materia", "subject"], in: paragraphs)
        let term = metadataValue(forPatterns: ["trimestre", "term"], in: paragraphs)
        let center = metadataValue(forPatterns: ["centro de referencia", "centro", "center", "context", "contexto"], in: paragraphs)
        let duration = metadataValue(forPatterns: ["temporalizacion", "temporalización", "time allocation", "duration", "duracion", "duración"], in: paragraphs)

        var warnings: [String] = []
        if criteria.isEmpty { warnings.append("No se han reconocido criterios de evaluación.") }
        if evaluationItems.isEmpty { warnings.append("No se han reconocido ponderaciones de evaluación.") }
        if course.isEmpty { warnings.append("Revisa el curso antes de asociar grupos.") }

        return LearningSituationImportDraft(
            title: title,
            stageLabel: stage,
            courseLabel: course,
            subjectLabel: subject,
            termLabel: term,
            centerLabel: center,
            sessionCount: sessionCount(in: duration),
            challenge: challenge,
            finalProduct: finalProduct,
            justification: sectionText(afterHeadings: ["JUSTIFICACIÓN Y RETO", "CLIL justification and driving question", "justification"], untilHeadings: ["Pregunta Motriz", "Driving question", "CLIL 4Cs", "4Cs"], paragraphs: paragraphs).first ?? "",
            competencies: paragraphs.filter {
                let clean = cleanBulletPrefix($0)
                return clean.hasPrefix("CE.") || 
                       clean.range(of: "^ce[.\\s\\d]", options: [.regularExpression, .caseInsensitive]) != nil ||
                       clean.localizedCaseInsensitiveContains("competencia")
            },
            criteria: criteria,
            knowledge: sectionText(afterHeadings: ["Saberes Básicos Implicados", "Saberes Básicos", "Curricular alignment", "Specific competencies"], untilHeadings: ["METODOLOGÍA", "Methodology"], paragraphs: paragraphs),
            methodology: sectionText(afterHeadings: ["METODOLOGÍA Y ESTRATEGIAS ACTIVAS", "Methodology and scaffolding", "Methodology"], untilHeadings: ["ATENCIÓN A LA DIVERSIDAD", "Inclusion and UDL", "Inclusion"], paragraphs: paragraphs),
            inclusionMeasures: inclusionMeasures(from: paragraphs),
            evaluationItems: evaluationItems,
            warnings: warnings,
            sourceURL: url,
            sourceFileName: url.lastPathComponent,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            sizeBytes: Int64(data.count)
        )
    }

    private func readParagraphs(from data: Data) throws -> [String] {
        let archive = try Archive(data: data, accessMode: .read, pathEncoding: nil)
        guard let entry = archive["word/document.xml"] else {
            throw LearningSituationImportError.unreadableDocument
        }
        var xmlData = Data()
        _ = try archive.extract(entry) { xmlData.append($0) }
        let reader = WordParagraphReader()
        guard reader.parse(data: xmlData) else { throw LearningSituationImportError.unreadableDocument }
        return reader.paragraphs
    }

    private func cleanBulletPrefix(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasPrefix("•") || result.hasPrefix("-") || result.hasPrefix("*") || result.hasPrefix("◦") || result.hasPrefix("▪") {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private func metadataValue(forPatterns patterns: [String], in paragraphs: [String]) -> String {
        for paragraph in paragraphs {
            let normPara = normalized(paragraph)
            for pattern in patterns {
                let regexPattern = "\\b\(pattern)\\b[^:]*:"
                if let regex = try? NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive]),
                   regex.firstMatch(in: normPara, range: NSRange(normPara.startIndex..., in: normPara)) != nil {
                    if let colonIndex = paragraph.firstIndex(of: ":") {
                        return String(paragraph[paragraph.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }
        return ""
    }

    private func textFollowingHeading(_ headings: [String], paragraphs: [String]) -> String {
        for heading in headings {
            let normHeading = normalized(heading)
            for (index, paragraph) in paragraphs.enumerated() {
                let normPara = normalized(paragraph)
                if normPara.contains(normHeading) {
                    if let colonIndex = paragraph.firstIndex(of: ":") {
                        let content = String(paragraph[paragraph.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if content.count > 3 {
                            return content
                        }
                    }
                    if index + 1 < paragraphs.count {
                        return paragraphs[index + 1]
                    }
                }
            }
        }
        return ""
    }

    private func sectionText(afterHeadings startHeadings: [String], untilHeadings endHeadings: [String], paragraphs: [String]) -> [String] {
        var start: Int? = nil
        for heading in startHeadings {
            if let index = paragraphs.firstIndex(where: { normalized($0).contains(normalized(heading)) }) {
                start = index
                break
            }
        }
        guard let startIndex = start else { return [] }
        let tail = paragraphs.dropFirst(startIndex + 1)
        let normalizedEndHeadings = endHeadings.map { normalized($0) }
        return Array(tail.prefix { text in
            let normText = normalized(text)
            return !normalizedEndHeadings.contains(where: { normText.contains($0) })
        }).filter { !$0.localizedCaseInsensitiveContains("descriptores operativos") }
    }

    private func criterionDrafts(from paragraphs: [String]) -> [LearningSituationCriterionDraft] {
        var results: [LearningSituationCriterionDraft] = []
        for (index, paragraph) in paragraphs.enumerated() {
            let cleanPara = cleanBulletPrefix(paragraph)
            guard cleanPara.localizedCaseInsensitiveContains("criterio") || cleanPara.localizedCaseInsensitiveContains("criterion") else { continue }
            
            if index + 1 < paragraphs.count {
                let nextPara = cleanBulletPrefix(paragraphs[index + 1])
                if nextPara.localizedCaseInsensitiveContains("evidencia:") || nextPara.localizedCaseInsensitiveContains("evidence:") {
                    let evidenceLabel = nextPara.localizedCaseInsensitiveContains("evidencia:") ? "Evidencia:" : "Evidence:"
                    let expected = normalized(evidenceLabel)
                    var evidence = ""
                    if normalized(nextPara).hasPrefix(expected) {
                        let colon = nextPara.firstIndex(of: ":")
                        evidence = colon.map { String(nextPara[nextPara.index(after: $0)...]).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                    }
                    results.append(LearningSituationCriterionDraft(criterion: cleanPara, evidence: evidence))
                    continue
                }
            }
            
            if let colonIndex = cleanPara.firstIndex(of: ":") {
                let leftPart = String(cleanPara[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let rightPart = String(cleanPara[cleanPara.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                results.append(LearningSituationCriterionDraft(criterion: leftPart, evidence: rightPart))
            } else {
                results.append(LearningSituationCriterionDraft(criterion: cleanPara, evidence: ""))
            }
        }
        return results
    }

    private func evaluationDraft(from paragraph: String) -> LearningSituationEvaluationDraft {
        let cleanPara = cleanBulletPrefix(paragraph)
        let pattern = #"([0-9]+(?:[.,][0-9]+)?)\s*%"#
        let match = try? NSRegularExpression(pattern: pattern).firstMatch(in: cleanPara, range: NSRange(cleanPara.startIndex..., in: cleanPara))
        let weight = match.flatMap { Range($0.range(at: 1), in: cleanPara) }.flatMap { Double(cleanPara[$0].replacingOccurrences(of: ",", with: ".")) }
        let title = cleanPara.components(separatedBy: " - ").first ?? cleanPara
        
        var criterion = cleanPara.components(separatedBy: "(").dropFirst().first?.components(separatedBy: ")").first ?? ""
        if criterion.isEmpty {
            let critPattern = #"((?:CE|Criterio|Criterion)(?:\.[A-Z]+)*\s*\d+(?:\.\d+)*)"#
            if let critMatch = try? NSRegularExpression(pattern: critPattern, options: .caseInsensitive)
                .firstMatch(in: cleanPara, range: NSRange(cleanPara.startIndex..., in: cleanPara)),
               let critRange = Range(critMatch.range(at: 1), in: cleanPara) {
                criterion = String(cleanPara[critRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return LearningSituationEvaluationDraft(title: title, criterionLabel: criterion, weightPercent: weight)
    }

    private func inclusionMeasures(from paragraphs: [String]) -> [String] {
        let candidates = paragraphs.filter {
            let norm = normalized($0)
            return norm.contains("competencia motriz")
                || norm.contains("motor competence")
                || norm.contains("lesion temporal")
                || norm.contains("lesión temporal")
                || norm.contains("temporary injury")
                || norm.contains("dificultades de atencion")
                || norm.contains("dificultades de atención")
                || norm.contains("attention difficulties")
                || norm.contains("anxiety")
                || norm.contains("ansiedad")
                || norm.contains("graduacion de los ejercicios")
                || norm.contains("graduación de los ejercicios")
                || norm.contains("station levels")
                || norm.contains("rol de analista")
                || norm.contains("analyst role")
                || norm.contains("explicaciones en pista")
                || norm.contains("bilingual glossary")
        }
        return candidates
    }

    private func sessionCount(in text: String) -> Int {
        let match = try? NSRegularExpression(pattern: #"([0-9]+)\s+(?:sesi|sessi)"#, options: .caseInsensitive)
            .firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        return match.flatMap { Range($0.range(at: 1), in: text) }.flatMap { Int(text[$0]) } ?? 0
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}

struct LearningSituationSessionSequenceDocumentImportService {
    func preview(from url: URL) throws -> LearningSituationSessionSequenceImportDraft {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let paragraphs = try readParagraphs(from: data).filter { !$0.isEmpty }
        guard !paragraphs.isEmpty else { throw LearningSituationImportError.missingDocumentBody }

        let headerPattern = try NSRegularExpression(
            pattern: #"^(?:SESI|SESSI)(?:ÓN|ON|ONES|ONS)?\s+([0-9]+)(?:\s+(?:y|and|\&)\s+([0-9]+))?\s*(?:\((.+)\))?"#,
            options: [.caseInsensitive]
        )
        let headerIndexes = paragraphs.indices.filter {
            headerPattern.firstMatch(in: paragraphs[$0], range: NSRange(paragraphs[$0].startIndex..., in: paragraphs[$0])) != nil
        }
        var plans: [LearningSituationSessionPlanDraft] = []
        for (position, start) in headerIndexes.enumerated() {
            let end = position + 1 < headerIndexes.count ? headerIndexes[position + 1] : paragraphs.count
            let header = paragraphs[start]
            guard let match = headerPattern.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
                  let firstRange = Range(match.range(at: 1), in: header),
                  let firstNumber = Int(header[firstRange]) else { continue }
            var numbers = [firstNumber]
            if match.range(at: 2).location != NSNotFound,
               let secondRange = Range(match.range(at: 2), in: header),
               let secondNumber = Int(header[secondRange]) {
                numbers.append(secondNumber)
            }
            let body = Array(paragraphs[(start + 1)..<end])
            let parsed = parsePlan(header: header, body: body)
            plans.append(contentsOf: numbers.map {
                LearningSituationSessionPlanDraft(
                    sessionNumber: $0,
                    sourceLabel: header,
                    title: parsed.title,
                    sessionType: parsed.sessionType,
                    effectiveMinutes: parsed.effectiveMinutes,
                    objective: parsed.objective,
                    criteria: parsed.criteria,
                    material: parsed.material,
                    development: parsed.development,
                    adaptations: parsed.adaptations
                )
            })
        }
        plans.sort { $0.sessionNumber < $1.sessionNumber }
        var warnings: [String] = []
        if plans.isEmpty { warnings.append("No se han reconocido fichas de sesión.") }
        let numbers = plans.map(\.sessionNumber)
        if Set(numbers).count != numbers.count { warnings.append("Hay números de sesión repetidos.") }
        if let maximum = numbers.max(), numbers != Array(1...maximum) {
            warnings.append("La numeración de las sesiones no es consecutiva.")
        }
        if plans.contains(where: { $0.title.isEmpty || $0.objective.isEmpty }) {
            warnings.append("Revisa las sesiones sin título u objetivo reconocido.")
        }
        return LearningSituationSessionSequenceImportDraft(
            plans: plans,
            warnings: warnings,
            sourceURL: url,
            sourceFileName: url.lastPathComponent,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            sizeBytes: Int64(data.count)
        )
    }

    private func parsePlan(header: String, body: [String]) -> (
        title: String, sessionType: String, effectiveMinutes: Int, objective: String,
        criteria: [String], material: String, development: [LearningSituationSessionSectionDraft], adaptations: [String]
    ) {
        let title = value(afterLabels: ["Título", "Title"], in: body).trimmingCharacters(in: CharacterSet(charactersIn: "“”\""))
        let objective = value(afterLabels: ["Objetivo", "Objective"], in: body)
        let criteria = value(afterLabels: ["Criterio de evaluación", "Criterio", "Criterion", "Criteria"], in: body)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let material = value(afterLabels: ["Material", "Materials"], in: body)
        let normalizedHeader = header.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let type = normalizedHeader.contains("doble") ? "Doble" : "Simple"
        let minutes = integerMatch(in: header, pattern: #"([0-9]+)\s+minutos"#) ?? 0
        let adaptationIndex = body.firstIndex(where: {
            let norm = normalized($0)
            return norm.hasPrefix("adaptacion al contexto") || norm.hasPrefix("adaptación al contexto") || norm.hasPrefix("context adaptation")
        })
        let contentEnd = adaptationIndex ?? body.count
        let developmentStart = body.firstIndex(where: { isDevelopmentHeading($0) }) ?? contentEnd
        var development: [LearningSituationSessionSectionDraft] = []
        var currentTitle: String?
        var currentLines: [String] = []
        for paragraph in body[developmentStart..<contentEnd] {
            if isDevelopmentHeading(paragraph) {
                if let currentTitle { development.append(.init(title: currentTitle, lines: currentLines)) }
                currentTitle = paragraph
                currentLines = []
            } else {
                currentLines.append(paragraph)
            }
        }
        if let currentTitle { development.append(.init(title: currentTitle, lines: currentLines)) }
        let adaptations = adaptationIndex.map { Array(body.dropFirst($0 + 1)) } ?? []
        return (title, type, minutes, objective, criteria, material, development, adaptations)
    }

    private func readParagraphs(from data: Data) throws -> [String] {
        let archive = try Archive(data: data, accessMode: .read, pathEncoding: nil)
        guard let entry = archive["word/document.xml"] else { throw LearningSituationImportError.unreadableDocument }
        var xmlData = Data()
        _ = try archive.extract(entry) { xmlData.append($0) }
        let reader = WordParagraphReader()
        guard reader.parse(data: xmlData) else { throw LearningSituationImportError.unreadableDocument }
        return reader.paragraphs
    }

    private func value(afterLabels labels: [String], in paragraphs: [String]) -> String {
        let normalizedLabels = labels.map { normalized($0) }
        for paragraph in paragraphs {
            let normPara = normalized(paragraph)
            for label in normalizedLabels {
                if let range = normPara.range(of: "\\b\(NSRegularExpression.escapedPattern(for: label))\\b", options: .regularExpression) {
                    if let colonIndex = paragraph.firstIndex(of: ":") {
                        return String(paragraph[paragraph.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }
        return ""
    }

    private func isDevelopmentHeading(_ paragraph: String) -> Bool {
        let item = normalized(paragraph)
        return item.hasPrefix("bloque ") ||
               item.hasPrefix("block ") ||
               item.hasPrefix("desarrollo de la sesion") ||
               item.hasPrefix("desarrollo de la sesión") ||
               item.hasPrefix("session development") ||
               item.hasPrefix("development of the session") ||
               item.contains("descanso reglamentario") ||
               item.contains("regulatory rest")
    }

    private func integerMatch(in text: String, pattern: String) -> Int? {
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let match = regex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        return match.flatMap { Range($0.range(at: 1), in: text) }.flatMap { Int(text[$0]) }
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}

private final class WordParagraphReader: NSObject, XMLParserDelegate {
    private(set) var paragraphs: [String] = []
    private var inParagraph = false
    private var inText = false
    private var buffer = ""

    func parse(data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "w:p" || elementName.hasSuffix(":p") {
            inParagraph = true
            buffer = ""
        } else if inParagraph && (elementName == "w:t" || elementName.hasSuffix(":t")) {
            inText = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "w:t" || elementName.hasSuffix(":t") {
            inText = false
        } else if elementName == "w:p" || elementName.hasSuffix(":p") {
            let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { paragraphs.append(value) }
            inParagraph = false
        }
    }
}

struct LearningSituationDocumentStore {
    let directoryURL: URL

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        directoryURL = base.appendingPathComponent("LearningSituations", isDirectory: true)
    }

    func persistSourceDocument(from url: URL, sha256: String) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let destination = directoryURL.appendingPathComponent("\(sha256).docx")
        if manager.fileExists(atPath: destination.path) { return destination }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        try manager.copyItem(at: url, to: destination)
        return destination
    }
}
