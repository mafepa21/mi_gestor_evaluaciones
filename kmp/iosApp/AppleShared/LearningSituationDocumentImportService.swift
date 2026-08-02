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
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unreadableDocument: return "No se ha podido leer el documento Word."
        case .missingDocumentBody: return "El documento no contiene texto reconocible."
        case .timedOut: return "La lectura del documento ha tardado demasiado. Inténtalo de nuevo."
        }
    }
}

struct LearningSituationDocumentImportFailure: Identifiable {
    let id: UUID
    let fileName: String
    let message: String

    init(fileName: String, message: String) {
        self.id = UUID()
        self.fileName = fileName
        self.message = message
    }
}

struct LearningSituationDocumentImportBatch {
    let drafts: [LearningSituationImportDraft]
    let failures: [LearningSituationDocumentImportFailure]
}

struct LearningSituationDocumentImportService {
    func preview(from url: URL) throws -> LearningSituationImportDraft {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let paragraphs = try readParagraphs(from: data).filter { !$0.isEmpty }
        guard !paragraphs.isEmpty else { throw LearningSituationImportError.missingDocumentBody }
        // C1/C3: algunas SA (p.ej. SA 3, SA 5) ponen la ficha técnica y los criterios de
        // evaluación en tablas ("Campo | Dato", "Criterio | Enunciado oficial | Rol en la SA")
        // en vez de párrafos "Etiqueta: valor". `readParagraphs` ya aplana el texto de las
        // celdas dentro de `paragraphs` (sin colon, así que `metadataValue`/`criterionDrafts`
        // no los reconocían); se leen también como bloques para poder emparejar fila a fila.
        let tables: [[[String]]] = (try? wordDocumentBlocks(from: data))?.compactMap { block in
            if case .table(let rows) = block { return rows } else { return nil }
        } ?? []

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

        // C2: "Pregunta guía:" (SA 5) y "Reto inicial" (SA 4b, SA 6) son sinónimos reales de
        // "Pregunta Motriz"/"Driving question" que no estaban en la lista.
        let challenge = textFollowingHeading(["Pregunta Motriz", "Driving question", "Pregunta guía", "Pregunta guia", "Reto inicial"], paragraphs: paragraphs)
        let finalProduct = textFollowingHeading(["Producto Final", "Final product"], paragraphs: paragraphs)
        let criteriaFromParagraphs = criterionDrafts(from: paragraphs)
        let criteriaFromTables = criterionDraftsFromTables(tables)
        let criteria = criteriaFromParagraphs.isEmpty ? criteriaFromTables : criteriaFromParagraphs

        // C4: la forma valenciana "Criteri 1.1 Diseño del plan - 40%: …" (SA 1) no contenía
        // ninguna de las palabras del filtro ("criterio"/"criterion"/"total"/"ce "/"ce.") y
        // ninguna ponderación se detectaba. Se añade "criteri" y se aceptan también los
        // párrafos con "%" que caen bajo un encabezado de "Sistema de evaluación"/"Evaluación
        // (resumen)", aunque no lleven ninguna de esas palabras clave.
        let evaluationHeadingIndexes = paragraphs.indices.filter {
            let value = normalized(paragraphs[$0])
            return value.contains("sistema de evaluacion") || value.contains("evaluacion (resumen)") || value.contains("evaluacion resumen")
        }
        let evaluationSectionIndexes: Set<Int> = Set(evaluationHeadingIndexes.flatMap { start -> [Int] in
            Array((start + 1)..<min(start + 15, paragraphs.count))
        })
        let evaluationItems = paragraphs.indices
            .filter { index in
                let paragraph = paragraphs[index]
                let clean = paragraph.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                guard clean.contains("%") else { return false }
                if clean.contains("criterio") ||
                    clean.contains("criteri ") ||
                    clean.contains("criterion") ||
                    clean.contains("total") ||
                    clean.contains("ce ") ||
                    clean.contains("ce.") ||
                    clean.range(of: "\\bce\\s*\\d", options: .regularExpression) != nil {
                    return true
                }
                return evaluationSectionIndexes.contains(index)
            }
            .map { evaluationDraft(from: paragraphs[$0]) }

        // C1: la ficha técnica en tabla ("Campo | Dato") no lleva ":" en cada celda, así que
        // `metadataValue` (que exige un ":" en el párrafo) se quedaba siempre vacío para SA 3.
        // Se intenta primero el párrafo con ":" y, si no hay nada, se busca fila a fila en las
        // tablas por coincidencia de la etiqueta de la primera celda.
        func metadata(_ patterns: [String]) -> String {
            let fromParagraphs = metadataValue(forPatterns: patterns, in: paragraphs)
            if !fromParagraphs.isEmpty { return fromParagraphs }
            return metadataValueFromTables(patterns, tables: tables)
        }
        let stage = metadata(["etapa", "stage"])
        let course = metadata(["curso", "grade"])
        let subject = metadata(["materia", "subject"])
        // C2: "Evaluación: 2ª evaluación" (SA 4b) es el trimestre en la práctica; se añade
        // "evaluacion" a los sinónimos de trimestre.
        let term = metadata(["trimestre", "term", "evaluacion"])
        let center = metadata(["centro de referencia", "centro", "center", "context", "contexto"])
        let duration = metadata(["temporalizacion", "temporalización", "time allocation", "duration", "duracion", "duración"])

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
            // C2: "2. Justificación y pregunta guía" (SA 5) no matcheaba con ningún sinónimo — la
            // lista solo tenía la forma inglesa "justification".
            justification: sectionText(afterHeadings: ["JUSTIFICACIÓN Y RETO", "CLIL justification and driving question", "justification", "Justificación"], untilHeadings: ["Pregunta Motriz", "Driving question", "CLIL 4Cs", "4Cs"], paragraphs: paragraphs).first ?? "",
            competencies: paragraphs.filter {
                let clean = cleanBulletPrefix($0)
                if clean.hasPrefix("CE.") ||
                    clean.range(of: "^ce[.\\s\\d]", options: [.regularExpression, .caseInsensitive]) != nil {
                    return true
                }
                // C3: excluye el encabezado de sección "Competencias específicas" (sin código ni
                // contenido propio), que antes se colaba solo por contener la palabra
                // "competencia".
                guard clean.localizedCaseInsensitiveContains("competencia") else { return false }
                return clean.contains(":") || !criterionCodesInText(clean).isEmpty
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

    /// Previsualiza todos los documentos seleccionados y conserva los resultados válidos aunque
    /// uno de los archivos no pueda leerse. El orden de `drafts` y `failures` sigue el orden de
    /// selección del usuario dentro de cada colección.
    func preview(from urls: [URL]) -> LearningSituationDocumentImportBatch {
        var drafts: [LearningSituationImportDraft] = []
        var failures: [LearningSituationDocumentImportFailure] = []

        for url in urls {
            do {
                drafts.append(try preview(from: url))
            } catch {
                failures.append(
                    LearningSituationDocumentImportFailure(
                        fileName: url.lastPathComponent,
                        message: error.localizedDescription
                    )
                )
            }
        }

        return LearningSituationDocumentImportBatch(drafts: drafts, failures: failures)
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
        while result.hasPrefix("•") || result.hasPrefix("-") || result.hasPrefix("*") || result.hasPrefix("◦") || result.hasPrefix("▪") || result.hasPrefix("#") {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    /// Vocabulario de títulos de sección reutilizado por las distintas plantillas de SA. Sirve
    /// para detectar el final de una sección aunque el documento no use el sinónimo exacto que se
    /// le pasó como `untilHeadings` a `sectionText` (p.ej. una SA que titula "5. Producto final
    /// (resumen)" en vez de "METODOLOGÍA"): sin este corte genérico, `sectionText` seguía leyendo
    /// hasta el final del documento y volcaba el resto de secciones (metodología, medidas DUA,
    /// tabla de secuenciación) dentro del bloque anterior.
    private static let knownSectionHeadings: Set<String> = [
        "saberes basicos", "saberes basicos implicados", "metodologia",
        "atencion a la diversidad", "medidas dua", "producto final",
        "secuenciacion", "documento fuente", "competencias especificas",
        "criterios de evaluacion", "criterios y evidencias", "sistema de evaluacion",
        "justificacion", "justificacion y reto", "pregunta motriz", "reto inicial"
    ]

    /// Encabezado de sección "genérico": línea con símbolo Markdown literal ("#", típico de
    /// documentos generados a partir de Markdown), numeración de sección de primer nivel
    /// ("5. Producto final...") o coincidencia exacta con `knownSectionHeadings`.
    private func isGenericSectionHeading(_ paragraph: String) -> Bool {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("#") { return true }
        if trimmed.range(of: #"^\d+\.\s+[A-ZÁÉÍÓÚÑ¿]"#, options: .regularExpression) != nil { return true }
        return Self.knownSectionHeadings.contains(normalized(trimmed))
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

    /// C1: variante de `metadataValue` para la ficha técnica en tabla ("Campo | Dato"), donde el
    /// texto de cada celda no lleva ":" y `metadataValue` (que lo exige) nunca encuentra nada.
    private func metadataValueFromTables(_ patterns: [String], tables: [[[String]]]) -> String {
        let normalizedPatterns = patterns.map { normalized($0) }
        for table in tables {
            for row in table {
                guard row.count >= 2, let first = row.first, !first.isEmpty else { continue }
                let normalizedLabel = normalized(first)
                guard normalizedPatterns.contains(where: { normalizedLabel.contains($0) }) else { continue }
                let value = row.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }
        return ""
    }

    /// C3: criterios de evaluación en tabla ("Criterio | Enunciado oficial... | Rol en la SA",
    /// SA 3 y SA 5). Se detecta por la cabecera de la primera columna y se normaliza el código a
    /// "CE X.X" igual que en el resto de importadores.
    private func criterionDraftsFromTables(_ tables: [[[String]]]) -> [LearningSituationCriterionDraft] {
        var results: [LearningSituationCriterionDraft] = []
        for table in tables {
            guard let header = table.first, let firstHeader = header.first else { continue }
            let normalizedHeader = normalized(firstHeader)
            guard normalizedHeader.contains("criterio") || normalizedHeader.contains("criteri") else { continue }
            for row in table.dropFirst() {
                guard let firstCell = row.first else { continue }
                let codes = criterionCodesInText(firstCell)
                guard !codes.isEmpty else { continue }
                let evidence = row.count > 1 ? row[1] : ""
                for code in codes {
                    results.append(LearningSituationCriterionDraft(criterion: code, evidence: evidence))
                }
            }
        }
        return results
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
            if normalizedEndHeadings.contains(where: { normText.contains($0) }) { return false }
            return !isGenericSectionHeading(text)
        })
        .map(cleanBulletPrefix)
        .filter { !$0.isEmpty && !$0.localizedCaseInsensitiveContains("descriptores operativos") }
    }

    private func criterionDrafts(from paragraphs: [String]) -> [LearningSituationCriterionDraft] {
        var results: [LearningSituationCriterionDraft] = []
        for (index, paragraph) in paragraphs.enumerated() {
            let cleanPara = cleanBulletPrefix(paragraph)
            guard cleanPara.localizedCaseInsensitiveContains("criterio") || cleanPara.localizedCaseInsensitiveContains("criterion") else { continue }
            // C3: `criterionDrafts` metía como criterio el propio encabezado de sección
            // ("Criterios de evaluación y evidencias") porque solo miraba si el párrafo
            // contenía la palabra "criterio". Se descarta cuando no hay ni código de criterio
            // (p.ej. "1.2") ni contenido tras ":" — un encabezado no trae ninguna de las dos.
            let hasCriterionCode = !criterionCodesInText(cleanPara).isEmpty
            let hasColonContent = cleanPara.firstIndex(of: ":").map { colon in
                !String(cleanPara[cleanPara.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } ?? false
            guard hasCriterionCode || hasColonContent else { continue }

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
        return candidates.map(cleanBulletPrefix)
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

/// Resultado intermedio compartido por los dos parsers de sesión (formato A de párrafos y
/// formato B de tablas), antes de expandirlo a `LearningSituationSessionPlanDraft` por cada
/// número de sesión que declare el encabezado (p.ej. "Sesiones 3 y 5").
private struct ParsedSessionPlan {
    let title: String
    let sessionType: String
    let effectiveMinutes: Int
    let objective: String
    let criteria: [String]
    let material: String
    let development: [LearningSituationSessionSectionDraft]
    let adaptations: [String]
}

struct LearningSituationSessionSequenceDocumentImportService {
    /// B2/B3: el número de sesión debe ir seguido de un separador explícito (".", "-", "—",
    /// "–", ":", opcionalmente detrás de una anotación entre paréntesis como "(NEW)") o no
    /// llevar nada más. Sin este requisito, un párrafo de prosa como "Session 3 finishes the
    /// panel and starts planning the final event." (00d - Cierre de Curso) matcheaba igual que
    /// un encabezado real y generaba una sesión 3 fantasma duplicada.
    private static let headerPattern = try! NSRegularExpression(
        pattern: #"^(?:SESI|SESSI)(?:ÓN|ON|ONES|ONS)?\s+([0-9]+)(?:\s+(?:y|and|\&)\s+([0-9]+))?(?:\s*\([^)]*\))?(?:\s*[.:\-–—]\s*(.*))?$"#,
        options: [.caseInsensitive]
    )

    func preview(from url: URL) throws -> LearningSituationSessionSequenceImportDraft {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let blocks = try wordDocumentBlocks(from: data)
        return try preview(blocks: blocks, data: data, url: url)
    }

    /// Separado de `preview(from:)` para poder ejercitar el parser con los bloques ya
    /// extraídos (documentos de prueba) sin pasar por la descompresión del `.docx`.
    func preview(blocks: [WordDocumentBlock], data: Data, url: URL) throws -> LearningSituationSessionSequenceImportDraft {
        guard !blocks.isEmpty else { throw LearningSituationImportError.missingDocumentBody }

        // `defaultMinutesByType` (B6) sigue operando sobre el texto plano de todo el documento
        // (incluido el de dentro de tablas), que es donde suele ir la frase introductoria
        // "Simple sessions are designed for 30 effective minutes.".
        let allParagraphTexts = blocks.flatMap { block -> [String] in
            switch block {
            case .paragraph(let text): return [text]
            case .table(let rows): return rows.flatMap { $0 }
            }
        }
        let defaultMinutes = defaultMinutesByType(in: allParagraphTexts)

        // B7: formato semanal (`sesiones_por_semana.docx`). La unidad de planificación es la
        // SEMANA, con un BLOQUE LARGO (90′) y un BLOQUE CORTO (30′) en vez de "SESIÓN N con
        // versión simple y doble". Se detecta antes que el formato de sesión: si el documento
        // trae encabezados de semana, se usa esta ruta.
        if let weekly = try weeklyPreview(blocks: blocks, data: data, url: url) {
            return weekly
        }

        struct HeaderMatch {
            let blockIndex: Int
            let header: String
            let numbers: [Int]
            let restAfterSeparator: String?
        }
        var headerMatches: [HeaderMatch] = []
        for (index, block) in blocks.enumerated() {
            guard case .paragraph(let text) = block else { continue }
            guard let match = Self.headerPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let firstRange = Range(match.range(at: 1), in: text),
                  let firstNumber = Int(text[firstRange]) else { continue }
            var numbers = [firstNumber]
            if match.range(at: 2).location != NSNotFound,
               let secondRange = Range(match.range(at: 2), in: text),
               let secondNumber = Int(text[secondRange]) {
                numbers.append(secondNumber)
            }
            let rest: String?
            if match.range(at: 3).location != NSNotFound, let restRange = Range(match.range(at: 3), in: text) {
                rest = String(text[restRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                rest = nil
            }
            headerMatches.append(HeaderMatch(blockIndex: index, header: text, numbers: numbers, restAfterSeparator: rest))
        }

        var plans: [LearningSituationSessionPlanDraft] = []
        for (position, match) in headerMatches.enumerated() {
            let endBlockIndex = position + 1 < headerMatches.count ? headerMatches[position + 1].blockIndex : blocks.count
            let bodyBlocks = Array(blocks[(match.blockIndex + 1)..<endBlockIndex])
            let containsTable = bodyBlocks.contains { if case .table = $0 { return true } else { return false } }
            let parsed: ParsedSessionPlan
            if containsTable {
                // B1: formato de tabla (todas las carpetas salvo SA 1).
                parsed = parsePlanFromBlocks(header: match.header, restAfterSeparator: match.restAfterSeparator, body: bodyBlocks, defaultMinutes: defaultMinutes)
            } else {
                // Formato A (SA 1): párrafos con etiquetas ("Objetivo:", "Criterios:"...). No se
                // toca la lógica existente para no degradarlo.
                let bodyParagraphs = bodyBlocks.compactMap { block -> String? in
                    if case .paragraph(let text) = block { return text.isEmpty ? nil : text }
                    return nil
                }
                parsed = parsePlanLegacy(header: match.header, body: bodyParagraphs, defaultMinutes: defaultMinutes)
            }
            plans.append(contentsOf: match.numbers.map {
                LearningSituationSessionPlanDraft(
                    sessionNumber: $0,
                    sourceLabel: match.header,
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
        let missingTitleCount = plans.filter { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        if missingTitleCount > 0 {
            warnings.append("\(missingTitleCount) sesiones no tienen título reconocido.")
        }
        let missingObjectiveCount = plans.filter { $0.objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        if missingObjectiveCount > 0 {
            warnings.append("\(missingObjectiveCount) sesiones no tienen objetivo reconocido.")
        }
        let missingDevelopmentCount = plans.filter { $0.development.isEmpty }.count
        if missingDevelopmentCount > 0 {
            warnings.append("\(missingDevelopmentCount) sesiones no tienen desarrollo reconocido.")
        }
        let inferredMinutesCount = plans.filter { $0.effectiveMinutes > 0 && integerMatch(in: $0.sourceLabel, pattern: #"([0-9]+)\s*(?:minutos|minutes|min|')"#) == nil }.count
        if inferredMinutesCount > 0 {
            warnings.append("\(inferredMinutesCount) sesiones usan minutos inferidos por tipo o desarrollo.")
        }
        // B5: aviso explícito por sesión con versión simple y doble, ya que se toma la duración
        // de la versión simple como referencia en vez de sumar los tramos de ambas.
        for plan in plans where plan.sessionType == "Simple y Doble" {
            warnings.append("La sesión \(plan.sessionNumber) define versión simple y doble; se han tomado \(plan.effectiveMinutes)′. Ajusta el tipo si este grupo tiene sesión doble.")
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

    // MARK: - B7: formato semanal (BLOQUE LARGO / BLOQUE CORTO)

    /// Encabezado de semana: "SEMANA 3 — Classification Tournament (23 y 26 de abril)".
    /// Se exige el mismo separador explícito que en el encabezado de sesión para no confundir
    /// una frase de prosa ("La semana 3 cierra el diseño...") con un encabezado real.
    private static let weekHeaderPattern = try! NSRegularExpression(
        pattern: #"^(?:SEMANA|SETMANA|WEEK)\s+([0-9]+)(?:\s*[.:\-–—]\s*(.*))?$"#,
        options: [.caseInsensitive]
    )

    private enum WeekBlockKind {
        case long
        case short
    }

    /// "BLOQUE LARGO (90′ útiles — dos bloques de 45′...)" / "BLOQUE CORTO (30′ útiles)",
    /// con sus equivalentes en inglés. Devuelve el tipo de bloque y los minutos declarados.
    private func weekBlockHeading(_ paragraph: String) -> (kind: WeekBlockKind, minutes: Int?)? {
        guard paragraph.split(separator: " ").count <= 20 else { return nil }
        let value = normalized(paragraph)
        let kind: WeekBlockKind
        if value.hasPrefix("bloque largo") || value.hasPrefix("long block") {
            kind = .long
        } else if value.hasPrefix("bloque corto") || value.hasPrefix("short block") {
            kind = .short
        } else {
            return nil
        }
        return (kind, integerMatch(in: paragraph, pattern: #"([0-9]+)\s*(?:['’′]|minutos?|minutes?|min)"#))
    }

    /// Tabla del bloque corto: una sola tabla con dos columnas de variante
    /// ("Variante PREPARA (cae antes del largo…)" / "Variante CONSOLIDA (…)").
    private func variantColumnIndexes(_ header: [String]) -> [(index: Int, title: String)] {
        header.enumerated().compactMap { index, raw in
            let value = normalized(raw)
            guard value.contains("prepara") || value.contains("consolida") || value.contains("variante") || value.contains("variant") else {
                return nil
            }
            return (index, raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Convierte la tabla de dos variantes en una sección de desarrollo por variante,
    /// conservando la franja de tiempo y la fase de cada fila.
    private func variantSections(_ rows: [[String]]) -> [LearningSituationSessionSectionDraft] {
        guard let header = rows.first else { return [] }
        let variants = variantColumnIndexes(header)
        guard variants.count >= 2 else { return [] }
        let normalizedHeader = header.map(normalized)
        let timeIndex = normalizedHeader.firstIndex { $0.contains("time") || $0.contains("hora") || $0.contains("tiempo") }
        let phaseIndex = normalizedHeader.firstIndex { $0.contains("phase") || $0.contains("fase") }
        return variants.map { variant in
            let lines = rows.dropFirst().compactMap { row -> String? in
                guard variant.index < row.count else { return nil }
                let content = row[variant.index].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty, content != "—", content != "-" else { return nil }
                let prefix = [timeIndex, phaseIndex]
                    .compactMap { index -> String? in
                        guard let index, index < row.count else { return nil }
                        let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                        return value.isEmpty ? nil : value
                    }
                    .joined(separator: " · ")
                return prefix.isEmpty ? content : "\(prefix) · \(content)"
            }
            return LearningSituationSessionSectionDraft(title: variant.title, lines: lines)
        }
    }

    /// Encabezado de desarrollo dentro de una semana: "Block 1 (45′)", "Break (15′) — …",
    /// "Bloque 2". No se reutiliza `isDevelopmentHeading` (formato de sesión) porque este
    /// acepta cualquier párrafo que contenga un rango numérico, y en el formato semanal hay
    /// prosa con rangos ("3-4 comisiones", "limited throws per possession (3-5)") que acabaría
    /// convertida en secciones vacías.
    private func isWeekDevelopmentHeading(_ paragraph: String) -> Bool {
        guard paragraph.split(separator: " ").count <= 14 || normalized(paragraph).hasPrefix("break") ||
            normalized(paragraph).hasPrefix("descanso") else { return false }
        let value = normalized(paragraph)
        return value.hasPrefix("block ") || value.hasPrefix("bloque ") ||
            value.hasPrefix("break") || value.hasPrefix("descanso")
    }

    /// Encabezados de cierre del documento (posteriores a la última semana): la tabla resumen
    /// de momentos de evaluación de la SA no pertenece a la Semana N.
    private func isDocumentTailHeading(_ paragraph: String) -> Bool {
        guard paragraph.split(separator: " ").count <= 10 else { return false }
        let value = normalized(paragraph)
        return (value.contains("resumen") && value.contains("momentos")) ||
            (value.contains("summary") && value.contains("assessment"))
    }

    /// Resultado de leer una semana del documento.
    private struct ParsedWeek {
        let number: Int
        let header: String
        let title: String
        let objective: String
        let criteria: [String]
        let material: String
        let longSections: [LearningSituationSessionSectionDraft]
        let longMinutes: Int?
        let shortSections: [LearningSituationSessionSectionDraft]
        let shortMinutes: Int?
        let sharedSections: [LearningSituationSessionSectionDraft]
        let adaptations: [String]
    }

    /// Devuelve `nil` si el documento no está en formato semanal (para que `preview` siga con
    /// el formato de sesión de siempre).
    private func weeklyPreview(blocks: [WordDocumentBlock], data: Data, url: URL) throws -> LearningSituationSessionSequenceImportDraft? {
        var weekHeaders: [(blockIndex: Int, header: String, number: Int, title: String)] = []
        for (index, block) in blocks.enumerated() {
            guard case .paragraph(let text) = block else { continue }
            guard let match = Self.weekHeaderPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let numberRange = Range(match.range(at: 1), in: text),
                  let number = Int(text[numberRange]) else { continue }
            var title = ""
            if match.range(at: 2).location != NSNotFound, let titleRange = Range(match.range(at: 2), in: text) {
                title = String(text[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            weekHeaders.append((index, text, number, title))
        }
        guard !weekHeaders.isEmpty else { return nil }

        var weeks: [ParsedWeek] = []
        for (position, header) in weekHeaders.enumerated() {
            let end = position + 1 < weekHeaders.count ? weekHeaders[position + 1].blockIndex : blocks.count
            weeks.append(parseWeek(
                number: header.number,
                header: header.header,
                title: header.title,
                body: Array(blocks[(header.blockIndex + 1)..<end])
            ))
        }

        var plans: [LearningSituationSessionPlanDraft] = []
        var warnings: [String] = []
        for week in weeks {
            let baseTitle = week.title.isEmpty ? "Semana \(week.number)" : week.title
            let longMinutes = week.longMinutes ?? 90
            let shortMinutes = week.shortMinutes ?? 30
            if week.longSections.isEmpty {
                warnings.append("La semana \(week.number) no tiene BLOQUE LARGO reconocido.")
            }
            if week.shortSections.isEmpty {
                warnings.append("La semana \(week.number) no tiene BLOQUE CORTO reconocido.")
            }
            plans.append(LearningSituationSessionPlanDraft(
                sessionNumber: week.number * 2 - 1,
                sourceLabel: "\(week.header) · BLOQUE LARGO (\(longMinutes)′)",
                title: "\(baseTitle) — Bloque largo",
                sessionType: "Bloque largo",
                effectiveMinutes: longMinutes,
                objective: week.objective,
                criteria: week.criteria,
                material: week.material,
                development: week.longSections + week.sharedSections,
                adaptations: week.adaptations
            ))
            plans.append(LearningSituationSessionPlanDraft(
                sessionNumber: week.number * 2,
                sourceLabel: "\(week.header) · BLOQUE CORTO (\(shortMinutes)′)",
                title: "\(baseTitle) — Bloque corto",
                sessionType: "Bloque corto",
                effectiveMinutes: shortMinutes,
                objective: week.objective,
                criteria: week.criteria,
                material: week.material,
                development: week.shortSections + week.sharedSections,
                adaptations: week.adaptations
            ))
        }

        // El documento es el mismo para los dos grupos: lo que cambia es el orden dentro de la
        // semana (el bloque largo cae en el día de sesión doble del grupo). La app todavía no
        // ubica las sesiones automáticamente contra el horario, así que se avisa en vez de
        // decidir por el docente.
        warnings.append("Formato semanal: cada semana se importa como dos sesiones (bloque largo de 90′ y bloque corto de 30′). Al ubicarlas, el bloque largo va en el día de sesión doble del grupo y el corto en el simple; el orden dentro de la semana cambia entre grupos.")
        let missingObjective = plans.filter { $0.objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        if missingObjective > 0 {
            warnings.append("\(missingObjective) bloques no tienen objetivo reconocido.")
        }
        let missingDevelopment = plans.filter { $0.development.isEmpty }.count
        if missingDevelopment > 0 {
            warnings.append("\(missingDevelopment) bloques no tienen desarrollo reconocido.")
        }
        let numbers = weeks.map(\.number).sorted()
        if let maximum = numbers.max(), numbers != Array(1...maximum) {
            warnings.append("La numeración de las semanas no es consecutiva.")
        }

        return LearningSituationSessionSequenceImportDraft(
            plans: plans.sorted { $0.sessionNumber < $1.sessionNumber },
            warnings: warnings,
            sourceURL: url,
            sourceFileName: url.lastPathComponent,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            sizeBytes: Int64(data.count)
        )
    }

    private func parseWeek(number: Int, header: String, title: String, body: [WordDocumentBlock]) -> ParsedWeek {
        var objective = ""
        var material = ""
        var saberes = ""
        var criteriaRaw = ""
        var evidence = ""
        var fichaTitle = ""

        var longSections: [LearningSituationSessionSectionDraft] = []
        var shortSections: [LearningSituationSessionSectionDraft] = []
        var sharedSections: [LearningSituationSessionSectionDraft] = []
        var adaptations: [String] = []

        // Destino actual: antes del primer "BLOQUE …" y después de la última tabla del bloque
        // corto, el contenido pertenece a la semana entera (preguntas guía, variantes de
        // dificultad, adaptaciones) y se copia en los dos bloques.
        var target: WeekBlockKind?
        var reachedFinalSections = false
        var reachedDocumentTail = false
        var currentTitle: String?
        var currentLines: [String] = []
        var currentIsAdaptations = false
        var longMinutes: Int?
        var shortMinutes: Int?
        var pendingLabel: FichaField?

        func assign(_ field: FichaField, _ rawValue: String) {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            switch field {
            case .title: if fichaTitle.isEmpty { fichaTitle = value }
            case .objective: if objective.isEmpty { objective = value }
            case .criteria: criteriaRaw = criteriaRaw.isEmpty ? value : "\(criteriaRaw), \(value)"
            case .material: if material.isEmpty { material = value }
            case .saberes: if saberes.isEmpty { saberes = value }
            case .evidence: if evidence.isEmpty { evidence = value }
            case .organisation, .date: break
            }
        }

        func flushSection() {
            defer {
                currentTitle = nil
                currentLines = []
                currentIsAdaptations = false
            }
            guard let sectionTitle = currentTitle else { return }
            if currentIsAdaptations {
                adaptations.append(contentsOf: currentLines)
                return
            }
            let section = LearningSituationSessionSectionDraft(title: sectionTitle, lines: currentLines)
            if reachedFinalSections || target == nil {
                sharedSections.append(section)
            } else if target == .long {
                longSections.append(section)
            } else {
                shortSections.append(section)
            }
        }

        func startSection(_ sectionTitle: String, isAdaptations: Bool = false) {
            flushSection()
            currentTitle = sectionTitle
            currentLines = []
            currentIsAdaptations = isAdaptations
        }

        func appendLine(_ line: String) {
            if currentTitle == nil {
                switch target {
                case .some(.long): currentTitle = "Bloque largo"
                case .some(.short): currentTitle = "Bloque corto"
                case .none: currentTitle = "Notas de la semana"
                }
                currentLines = []
            }
            currentLines.append(line)
        }

        for block in body {
            switch block {
            case .paragraph(let rawText):
                let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                if isDocumentTailHeading(text) { reachedDocumentTail = true }
                if reachedDocumentTail { continue }
                if let waiting = pendingLabel {
                    assign(waiting, text)
                    pendingLabel = nil
                    continue
                }
                if let blockHeading = weekBlockHeading(text) {
                    flushSection()
                    reachedFinalSections = false
                    target = blockHeading.kind
                    switch blockHeading.kind {
                    case .long: longMinutes = blockHeading.minutes
                    case .short: shortMinutes = blockHeading.minutes
                    }
                    continue
                }
                if let field = fichaLabelOnly(text) {
                    pendingLabel = field
                    continue
                }
                if let (field, value) = fichaColonPair(text) {
                    assign(field, value)
                    continue
                }
                if let final = finalSectionHeading(text) {
                    reachedFinalSections = true
                    switch final {
                    case .development(let sectionTitle):
                        startSection(sectionTitle)
                    case .adaptations:
                        startSection("Adaptaciones", isAdaptations: true)
                    }
                    continue
                }
                if isWeekDevelopmentHeading(text) {
                    startSection(text)
                    continue
                }
                appendLine(text)
            case .table(let rawRows):
                if reachedDocumentTail { continue }
                let rows = rawRows.map { row in row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
                    .filter { row in row.contains { !$0.isEmpty } }
                guard !rows.isEmpty else { continue }
                if let tableHeader = rows.first, !variantColumnIndexes(tableHeader).isEmpty {
                    flushSection()
                    let sections = variantSections(rows)
                    if sections.isEmpty {
                        for row in rows.dropFirst() { appendLine(row.joined(separator: " · ")) }
                    } else if target == .long {
                        longSections.append(contentsOf: sections)
                    } else {
                        shortSections.append(contentsOf: sections)
                    }
                    continue
                }
                if isTimeTable(rows) {
                    for line in timeTableLines(rows) { appendLine(line) }
                    continue
                }
                if let tableHeader = rows.first, tableHeader.count >= 2 {
                    let dataRows = tableHeader.first.flatMap(fichaField(forLabel:)) != nil ? rows : Array(rows.dropFirst())
                    var matchedAny = false
                    for row in dataRows {
                        guard row.count >= 2, let field = fichaField(forLabel: row[0]) else { continue }
                        assign(field, row.dropFirst().joined(separator: " "))
                        matchedAny = true
                    }
                    if !matchedAny {
                        for row in rows.dropFirst() { appendLine(row.joined(separator: " · ")) }
                    }
                    continue
                }
                for row in rows.dropFirst() { appendLine(row.joined(separator: " · ")) }
            }
        }
        flushSection()

        if !evidence.isEmpty {
            sharedSections.insert(LearningSituationSessionSectionDraft(title: "Evaluación", lines: [evidence]), at: 0)
        }
        if !saberes.isEmpty {
            material = material.isEmpty ? saberes : "\(material) — Saberes básicos: \(saberes)"
        }

        return ParsedWeek(
            number: number,
            header: header,
            title: fichaTitle.isEmpty ? title : fichaTitle,
            objective: objective,
            criteria: criterionCodes(in: criteriaRaw),
            material: material,
            longSections: longSections,
            longMinutes: longMinutes,
            shortSections: shortSections,
            shortMinutes: shortMinutes,
            sharedSections: sharedSections,
            adaptations: adaptations
        )
    }

    /// Formato A (solo SA 1, párrafos con etiquetas "Objetivo:", "Criterios:", "Material:",
    /// "Evidencia:", "Bloque N (45'):"). Sin cambios de comportamiento respecto al parser
    /// original: el soporte de tablas del bloque B no debe degradarlo.
    private func parsePlanLegacy(header: String, body: [String], defaultMinutes: [String: Int]) -> ParsedSessionPlan {
        let headerParts = sessionTypeAndTitle(from: header)
        let titleFromBody = value(afterLabels: ["Título", "Title"], in: body)
            .trimmingCharacters(in: CharacterSet(charactersIn: "“”\""))
        let title = titleFromBody.isEmpty ? headerParts.title : titleFromBody
        let objective = value(afterLabels: ["Objetivo", "Objetivos", "Objective", "Objectives"], in: body)
        // B4: "Criterios: Criteri 1.1, Criteri 1.2, Criteri 3.2 (se trabajan, no se corrigen
        // todavía)." (SA 1) se partía por comas y producía criterios falsos ("Criteri 3.2 (se
        // trabajan", "no se corrigen todavía)"). Se extraen los códigos con una expresión
        // regular y se descarta el texto entre paréntesis y cualquier separador.
        let criteriaRawValue = value(afterLabels: ["Criterio de evaluación", "Criterios de evaluación", "Criterio", "Criterios", "Criterion", "Criteria"], in: body)
        let criteria = criterionCodes(in: criteriaRawValue)
        let material = value(afterLabels: ["Material", "Materials", "Materiales"], in: body)
        let evidence = value(afterLabels: ["Evidencia", "Evidencias", "Evidence"], in: body)
        let type = headerParts.type
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
        if !evidence.isEmpty {
            development.insert(.init(title: "Evidencia", lines: [evidence]), at: 0)
        }
        let adaptations = adaptationIndex.map { Array(body.dropFirst($0 + 1)) } ?? []
        let minutes = integerMatch(in: header, pattern: #"([0-9]+)\s*(?:minutos|minutes|min|')"#)
            ?? defaultMinutes[normalized(type)]
            ?? inferredMinutes(from: development)
        return ParsedSessionPlan(
            title: title, sessionType: type, effectiveMinutes: minutes, objective: objective,
            criteria: criteria, material: material, development: development, adaptations: adaptations
        )
    }

    // MARK: - B1/B5/B6: formato de tabla (resto de carpetas)

    /// Etiquetas reconocidas en la "ficha" de sesión, tanto si vienen como fila de una tabla
    /// `etiqueta | valor` (p.ej. "Item | Detail") como si vienen como dos párrafos consecutivos
    /// (etiqueta sola, seguida del contenido en el párrafo siguiente — SA 3, SA 4 y SA 6).
    private enum FichaField {
        case title, objective, criteria, material, saberes, organisation, evidence, date
    }

    private func fichaField(forLabel rawLabel: String) -> FichaField? {
        let label = normalized(rawLabel.trimmingCharacters(in: CharacterSet(charactersIn: " :\t")))
        switch label {
        case "titulo", "title":
            return .title
        case "objetivo", "objetivos", "objetivo especifico", "objetivo principal",
             "objective", "objectives", "specific objective", "main objective":
            return .objective
        case "criterio", "criterios", "criterio de evaluacion", "criterios de evaluacion",
             "criterios de evaluacion trabajados", "criterios de evaluacion abordados",
             "criterion", "criteria", "criteria worked", "evaluation criteria addressed",
             "assessment focus":
            return .criteria
        case "material", "materiales", "material necesario", "materials", "materials needed",
             "required materials":
            return .material
        case "saberes basicos", "saberes basicos trabajados", "saberes basicos worked",
             "basic knowledge addressed", "core knowledge addressed":
            return .saberes
        case "organizacion del grupo", "group organisation", "student grouping":
            return .organisation
        case "evidencia", "evidencias", "evidence",
             // Formato semanal: la ficha de la semana declara en "Assessment"/"Evaluación" qué
             // instrumento se recoge y en qué bloque.
             "assessment", "evaluacion", "evaluation":
            return .evidence
        case "fecha", "date":
            return .date
        default:
            return nil
        }
    }

    /// Detecta un párrafo que ES una etiqueta de ficha (nada más: "Specific objective",
    /// "Objetivo específico"...), para esperar el contenido en el párrafo siguiente.
    private func fichaLabelOnly(_ paragraph: String) -> FichaField? {
        guard paragraph.split(separator: " ").count <= 6 else { return nil }
        return fichaField(forLabel: paragraph)
    }

    /// Detecta el patrón "Etiqueta: valor" en un único párrafo (formato A y también presente en
    /// algunos documentos de formato B).
    private func fichaColonPair(_ paragraph: String) -> (FichaField, String)? {
        guard let colonIndex = paragraph.firstIndex(of: ":") else { return nil }
        let label = String(paragraph[..<colonIndex])
        guard label.split(separator: " ").count <= 6, let field = fichaField(forLabel: label) else { return nil }
        let value = String(paragraph[paragraph.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (field, value)
    }

    /// B5: marcador de que arranca una versión "Simple"/"Doble" de la sesión ("SIMPLE version
    /// (30' effective)...", "Timed development — 90' version (Double session...)"). No se
    /// duplica la sesión: cada versión se vuelca como una sección de desarrollo separada.
    private func isVersionHeading(_ paragraph: String) -> Bool {
        guard paragraph.count < 200 else { return false }
        let value = normalized(paragraph)
        // "Simple session adaptation (30' useful)" (SA 6) marca el cierre de cada sesión con el
        // encaje a sesión simple, no una adaptación de inclusión/NEAE: se reconoce como versión
        // antes que como sección de "Adaptaciones" (ver `finalSectionHeading`, comprobado
        // después en el orden de bloques).
        let hasVersionWord = value.contains("version") || value.contains("session adaptation") || value.contains("adaptacion de la sesion")
        guard hasVersionWord else { return false }
        return value.contains("simple") || value.contains("doble") || value.contains("double")
    }

    private func versionSectionTitle(isDouble: Bool, raw: String) -> String {
        isDouble ? "Versión doble (90′)" : "Versión simple (30′)"
    }

    /// Encabezados intermedios sin contenido propio (p.ej. "Time development"/"Desarrollo
    /// temporal" justo antes de la tabla horaria o de los marcadores de versión): se ignoran en
    /// vez de abrir una sección de desarrollo ruidosa con una sola línea.
    private func isIgnorableSectionIntro(_ paragraph: String) -> Bool {
        guard paragraph.split(separator: " ").count <= 6 else { return false }
        let value = normalized(paragraph)
        return value == "time development" || value == "timed development" ||
            value == "desarrollo temporal" || value == "desarrollo de la sesion" ||
            value == "desarrollo de la sesión" || value == "session development"
    }

    private enum FinalSection {
        case development(title: String)
        case adaptations
    }

    /// Secciones finales del formato B que se conservan (B1): como sección de desarrollo con
    /// su propio título, o como adaptaciones cuando corresponde.
    private func finalSectionHeading(_ paragraph: String) -> FinalSection? {
        guard paragraph.split(separator: " ").count <= 6 else { return nil }
        let value = normalized(paragraph)
        // Los documentos alternan singular/plural ("Preguntas guía" vs "Guiding question"), así
        // que se comprueban las dos palabras clave por separado en vez de la frase completa.
        if value.contains("adaptation") || value.contains("adaptacion") {
            return .adaptations
        }
        if value.contains("guiding question") || (value.contains("pregunta") && value.contains("guia")) || value.contains("pregunta orientativa") {
            return .development(title: "Preguntas orientativas")
        }
        if value.contains("difficulty variant") || (value.contains("variante") && value.contains("dificultad")) {
            return .development(title: "Variantes de dificultad")
        }
        if (value.contains("evidence") && value.contains("collect")) || (value.contains("evidencia") && value.contains("recogid")) {
            return .development(title: "Evidencia recogida")
        }
        if (value.contains("assessment") && value.contains("instrument")) || (value.contains("instrumento") && value.contains("evaluacion")) {
            return .development(title: "Instrumento de evaluación")
        }
        if value.contains("closure") || value.contains("cierre") {
            return .development(title: "Cierre")
        }
        return nil
    }

    private func isTimeTable(_ rows: [[String]]) -> Bool {
        guard let header = rows.first, let first = header.first else { return false }
        let value = normalized(first)
        return value == "time" || value == "hora" || value == "horario" || value == "tiempo"
    }

    /// B1: convierte una tabla horaria (Time | Phase | Activity | Teacher role | Student role |
    /// Evidence, con sinónimos en español) en líneas legibles de desarrollo.
    private func timeTableLines(_ rows: [[String]]) -> [String] {
        guard let header = rows.first else { return [] }
        let normalizedHeader = header.map(normalized)
        func columnIndex(_ candidates: [String]) -> Int? {
            normalizedHeader.firstIndex { column in candidates.contains { column.contains($0) } }
        }
        let timeIndex = columnIndex(["time", "hora", "tiempo"])
        let phaseIndex = columnIndex(["phase", "fase"])
        let activityIndex = columnIndex(["activity", "actividad"])
        let teacherIndex = columnIndex(["teacher", "profesor", "docente"])
        let studentIndex = columnIndex(["student", "alumno"])
        let evidenceIndex = columnIndex(["evidence", "evidencia"])
        func cell(_ row: [String], _ index: Int?) -> String? {
            guard let index, index < row.count else { return nil }
            let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty || value == "—" || value == "-" ? nil : value
        }
        return rows.dropFirst().compactMap { row -> String? in
            guard row.contains(where: { !$0.isEmpty }) else { return nil }
            let time = cell(row, timeIndex)
            let phase = cell(row, phaseIndex)
            let activity = cell(row, activityIndex)
            let teacher = cell(row, teacherIndex)
            let student = cell(row, studentIndex)
            let evidence = cell(row, evidenceIndex)
            var head = [time, phase, activity].compactMap { $0 }.joined(separator: " · ")
            if head.isEmpty { head = row.joined(separator: " · ") }
            var extras: [String] = []
            if let teacher { extras.append("Profesorado: \(teacher)") }
            if let student { extras.append("Alumnado: \(student)") }
            if let evidence { extras.append("Evidencia: \(evidence)") }
            return extras.isEmpty ? head : "\(head) (\(extras.joined(separator: "; ")))"
        }
    }

    /// B4: extrae todos los códigos de criterio de un texto ("Criteri 1.1, Criteri 1.2, Criteri
    /// 3.2 (se trabajan, no se corrigen todavía).", "2.1", "Criterion 3.2 (CE3)"...) y los
    /// normaliza siempre a "CE X.X", sin duplicados. Antes se troceaba por comas, lo que partía
    /// el texto entre paréntesis en criterios falsos.
    private func criterionCodes(in text: String) -> [String] {
        criterionCodesInText(text)
    }

    private func parsePlanFromBlocks(
        header: String,
        restAfterSeparator: String?,
        body: [WordDocumentBlock],
        defaultMinutes: [String: Int]
    ) -> ParsedSessionPlan {
        var titleFromFicha = ""
        var objective = ""
        var material = ""
        var saberes = ""
        var criteriaRaw = ""
        var evidenceFromFicha = ""

        var development: [LearningSituationSessionSectionDraft] = []
        var adaptations: [String] = []
        var currentSectionTitle: String?
        var currentLines: [String] = []
        var currentIsAdaptations = false
        var pendingLabel: FichaField?
        var sawSimple = false
        var sawDouble = false

        func assign(_ field: FichaField, _ value: String) {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            switch field {
            case .title: if titleFromFicha.isEmpty { titleFromFicha = value }
            case .objective: if objective.isEmpty { objective = value }
            case .criteria: criteriaRaw = criteriaRaw.isEmpty ? value : "\(criteriaRaw), \(value)"
            case .material: if material.isEmpty { material = value }
            case .saberes: if saberes.isEmpty { saberes = value }
            case .organisation: break // informativo, no tiene campo propio en el modelo actual
            case .evidence: if evidenceFromFicha.isEmpty { evidenceFromFicha = value }
            case .date: break
            }
        }

        func flushSection() {
            defer {
                currentSectionTitle = nil
                currentLines = []
                currentIsAdaptations = false
            }
            guard let title = currentSectionTitle else { return }
            if currentIsAdaptations {
                adaptations.append(contentsOf: currentLines)
            } else {
                development.append(.init(title: title, lines: currentLines))
            }
        }

        func appendLine(_ line: String) {
            if currentSectionTitle == nil {
                currentSectionTitle = "Desarrollo"
                currentLines = []
            }
            currentLines.append(line)
        }

        for block in body {
            switch block {
            case .paragraph(let rawText):
                let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                if let labelWaitingForValue = pendingLabel {
                    assign(labelWaitingForValue, text)
                    pendingLabel = nil
                    continue
                }
                if let field = fichaLabelOnly(text) {
                    pendingLabel = field
                    continue
                }
                if let (field, value) = fichaColonPair(text) {
                    assign(field, value)
                    continue
                }
                if isIgnorableSectionIntro(text) {
                    continue
                }
                if isVersionHeading(text) {
                    flushSection()
                    let isDouble = normalized(text).contains("doble") || normalized(text).contains("double")
                    sawDouble = sawDouble || isDouble
                    sawSimple = sawSimple || !isDouble
                    currentSectionTitle = versionSectionTitle(isDouble: isDouble, raw: text)
                    currentLines = []
                    continue
                }
                if let final = finalSectionHeading(text) {
                    flushSection()
                    switch final {
                    case .development(let sectionTitle):
                        currentSectionTitle = sectionTitle
                        currentIsAdaptations = false
                    case .adaptations:
                        currentSectionTitle = "Adaptaciones"
                        currentIsAdaptations = true
                    }
                    currentLines = []
                    continue
                }
                appendLine(text)
            case .table(let rawRows):
                let rows = rawRows.map { row in row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
                    .filter { row in row.contains { !$0.isEmpty } }
                guard !rows.isEmpty else { continue }
                if isTimeTable(rows) {
                    for line in timeTableLines(rows) { appendLine(line) }
                } else if let header = rows.first, header.count >= 2 {
                    // Tabla "ficha" etiqueta|valor (p.ej. "Item | Detail" + filas "Specific
                    // objective | ..."). Si la primera columna no trae etiquetas reconocidas,
                    // se trata como tabla genérica y se vuelca como líneas de desarrollo.
                    let dataRows = header.first.flatMap(fichaField(forLabel:)) != nil ? rows : Array(rows.dropFirst())
                    var matchedAny = false
                    for row in dataRows {
                        guard row.count >= 2, let field = fichaField(forLabel: row[0]) else { continue }
                        assign(field, row.dropFirst().joined(separator: " "))
                        matchedAny = true
                    }
                    if !matchedAny {
                        for row in rows.dropFirst() { appendLine(row.joined(separator: " · ")) }
                    }
                } else {
                    for row in rows.dropFirst() { appendLine(row.joined(separator: " · ")) }
                }
            }
        }
        flushSection()

        if !evidenceFromFicha.isEmpty {
            development.insert(.init(title: "Evidencia", lines: [evidenceFromFicha]), at: 0)
        }
        if !saberes.isEmpty {
            material = material.isEmpty ? saberes : "\(material) — Saberes básicos: \(saberes)"
        }

        let headerParts = sessionTypeAndTitle(from: header)
        let restTitle = restAfterSeparator.map(cleanRestTitle) ?? ""
        let title = !titleFromFicha.isEmpty ? titleFromFicha : (!restTitle.isEmpty ? restTitle : headerParts.title)

        // B5: `sessionType` refleja las versiones realmente presentes en el documento.
        let sessionType: String
        if sawSimple && sawDouble {
            sessionType = "Simple y Doble"
        } else if sawDouble {
            sessionType = "Doble"
        } else if sawSimple {
            sessionType = "Simple"
        } else {
            sessionType = headerParts.type
        }

        // B5: si hay versión simple y doble, se toma la duración de la simple como referencia
        // (con aviso explícito) en vez de sumar los minutos de ambas.
        let minutesKey = sawSimple ? "Simple" : (sawDouble ? "Doble" : sessionType)
        var minutes = integerMatch(in: header, pattern: #"([0-9]+)\s*(?:minutos|minutes|min|')"#)
            ?? defaultMinutes[normalized(minutesKey)]
            ?? 0
        if minutes == 0 {
            minutes = inferredMinutes(from: development)
        }

        let criteria = criterionCodes(in: criteriaRaw)
        return ParsedSessionPlan(
            title: title, sessionType: sessionType, effectiveMinutes: minutes, objective: objective,
            criteria: criteria, material: material, development: development, adaptations: adaptations
        )
    }

    /// B2: recorta el prefijo de tipo ("Simple:"/"Double:"/"Doble:", con plural opcional) y las
    /// anotaciones tipo "(NEW)"/"(nueva)" del texto que sigue al separador del encabezado.
    private func cleanRestTitle(_ rest: String) -> String {
        rest
            .replacingOccurrences(of: #"^\s*\([^)]*\)\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^(Simples?|Doubles?|Dobles?)\s*[:\-–—]?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func value(afterLabels labels: [String], in paragraphs: [String]) -> String {
        let normalizedLabels = labels.map { normalized($0) }
        for paragraph in paragraphs {
            let normPara = normalized(paragraph)
            for label in normalizedLabels {
                if normPara.range(of: "\\b\(NSRegularExpression.escapedPattern(for: label))s?\\b", options: .regularExpression) != nil {
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
               item.hasPrefix("break ") ||
               item.hasPrefix("descanso ") ||
               item.hasPrefix("desarrollo de la sesion") ||
               item.hasPrefix("desarrollo de la sesión") ||
               item.hasPrefix("session development") ||
               item.hasPrefix("development of the session") ||
               item.contains("descanso reglamentario") ||
               item.contains("regulatory rest") ||
               timeRangeMinutes(in: paragraph) != nil
    }

    private func integerMatch(in text: String, pattern: String) -> Int? {
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let match = regex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        return match.flatMap { Range($0.range(at: 1), in: text) }.flatMap { Int(text[$0]) }
    }

    private func sessionTypeAndTitle(from header: String) -> (type: String, title: String) {
        let normalizedHeader = normalized(header)
        let type: String
        if normalizedHeader.contains("double") || normalizedHeader.contains("doble") {
            type = "Doble"
        } else {
            type = "Simple"
        }
        // B2: el separador tras el número también puede ser "." (no solo "-:–—"), el tipo puede
        // ir en plural ("Sesiones 3 y 5 - Dobles: ..."), y puede haber una anotación entre
        // paréntesis tipo "(NEW)"/"(nueva)" que no debe colarse en el título.
        let pattern = #"^(?:SESI|SESSI)(?:ÓN|ON|ONES|ONS)?\s+[0-9]+(?:\s+(?:y|and|\&)\s+[0-9]+)?\s*(?:\([^)]*\)\s*)?(?:[.:\-–—]\s*)?(?:(?:Simples?|Doubles?|Dobles?)\s*[.:\-–—]?\s*)?(?:\([^)]*\)\s*)?(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
              let titleRange = Range(match.range(at: 1), in: header) else {
            return (type, "")
        }
        let title = String(header[titleRange])
            .replacingOccurrences(of: #"^(Simples?|Doubles?|Dobles?)\s*[.:\-–—]?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^\([^)]*\)\s*[-–—:]?\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (type, title)
    }

    // B6: los documentos reales dicen "30 effective minutes", "30' effective", "(30’ útiles)" o
    // "90' useful" — no siempre llevan la palabra "minutos/minutes/min" pegada al número, y
    // usan comilla tipográfica ('’'/'′') en vez de la palabra. Se acepta cualquiera de las dos
    // marcas: un apóstrofo (con la palabra effective/useful/efectivos/útiles opcional detrás) o
    // la palabra "efectivos/útiles" seguida de "minutos/minutes/min".
    private static let minutesMarkerFragment = #"(?:['’′](?:\s*(?:effective|useful|efectivos?|útiles?))?|(?:effective|useful|efectivos?|útiles?)?\s*(?:minutos?|minutes?|min))"#

    private func defaultMinutesByType(in paragraphs: [String]) -> [String: Int] {
        var result: [String: Int] = [:]
        for paragraph in paragraphs {
            let normalizedParagraph = normalized(paragraph)
            if normalizedParagraph.contains("simple"),
               let minutes = integerMatch(in: paragraph, pattern: #"Simple[^0-9]{0,80}([0-9]+)\s*"# + Self.minutesMarkerFragment) {
                result[normalized("Simple")] = minutes
            }
            if (normalizedParagraph.contains("double") || normalizedParagraph.contains("doble")),
               let minutes = integerMatch(in: paragraph, pattern: #"(?:Double|Doble)[^0-9]{0,80}([0-9]+)\s*"# + Self.minutesMarkerFragment) {
                result[normalized("Doble")] = minutes
            }
        }
        return result
    }

    private func inferredMinutes(from development: [LearningSituationSessionSectionDraft]) -> Int {
        let total = development
            .compactMap { timeRangeMinutes(in: $0.title) }
            .reduce(0, +)
        return total
    }

    private func timeRangeMinutes(in text: String) -> Int? {
        let pattern = #"([0-9]{1,3})\s*(?:'|’|min)?\s*[-–—]\s*([0-9]{1,3})\s*(?:'|’|min)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let startRange = Range(match.range(at: 1), in: text),
              let endRange = Range(match.range(at: 2), in: text),
              let start = Int(text[startRange]),
              let end = Int(text[endRange]),
              end > start else {
            return nil
        }
        return end - start
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
