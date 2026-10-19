import SwiftUI
import MiGestorKit

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Instrumentos con criterios (rúbricas y plantillas estructuradas)

/// `level`: el criterio se valora con un nivel (rúbrica o ítem 1-4). `check`: ítem de lista de cotejo (Sí / No).
enum CourtVoiceCriterionKind: String, Codable, Hashable, Sendable {
    case level
    case check
}

struct CourtVoiceCriterionLevel: Codable, Hashable, Sendable, Identifiable {
    /// `levelId` de la rúbrica, "1"..."4" en ítems 1-4, o "si"/"no" en listas de cotejo.
    let id: String
    let name: String
    let points: Double
    let detail: String?

    static let checkYes = CourtVoiceCriterionLevel(id: "si", name: "Sí", points: 1, detail: nil)
    static let checkNo = CourtVoiceCriterionLevel(id: "no", name: "No", points: 0, detail: nil)
}

struct CourtVoiceCriterionDescriptor: Codable, Hashable, Sendable, Identifiable {
    /// `criterionId` de la rúbrica o `itemId` de la plantilla.
    let id: String
    let title: String
    let kind: CourtVoiceCriterionKind
    let weight: Double
    /// Ordenados de menor a mayor puntuación.
    let levels: [CourtVoiceCriterionLevel]
}

enum CourtVoiceInstrumentSource: Codable, Hashable, Sendable {
    case rubric(evaluationId: Int64, rubricId: Int64)
    case template
}

struct CourtVoiceInstrumentDescriptor: Codable, Hashable, Sendable, Identifiable {
    var id: String { columnId }
    let columnId: String
    let title: String
    let source: CourtVoiceInstrumentSource
    let criteria: [CourtVoiceCriterionDescriptor]
}

/// Propuesta para un criterio dentro de una acción. `evidence == nil` significa que el docente no lo mencionó:
/// se muestra plegado y nunca se valora salvo que el docente elija un nivel.
struct CourtVoiceCriterionProposal: Codable, Hashable, Sendable, Identifiable {
    var id: String { criterion.id }
    let criterion: CourtVoiceCriterionDescriptor
    var evidence: String?
    var suggestedLevelId: String?
    var chosenLevelId: String?

    var isMentioned: Bool { evidence != nil }
    var suggestedLevel: CourtVoiceCriterionLevel? { criterion.levels.first { $0.id == suggestedLevelId } }
    var chosenLevel: CourtVoiceCriterionLevel? { criterion.levels.first { $0.id == chosenLevelId } }
}

extension Array where Element == CourtVoiceCriterionProposal {
    var hasChosenLevel: Bool { contains { $0.chosenLevelId != nil } }

    /// Misma regla que `RubricDetail.calculateScore`: solo cuentan los criterios valorados.
    var previewScore: Double? {
        var total = 0.0
        var weightUsed = 0.0
        for proposal in self where proposal.criterion.kind == .level {
            guard let level = proposal.chosenLevel else { continue }
            let maxPoints = Swift.max(1.0, proposal.criterion.levels.map(\.points).max() ?? 1.0)
            let weight = proposal.criterion.weight > 0 ? proposal.criterion.weight : 1.0
            total += Swift.min(1.0, Swift.max(0.0, level.points / maxPoints)) * weight
            weightUsed += weight
        }
        guard weightUsed > 0 else { return nil }
        return (total / weightUsed * 1000).rounded() / 100
    }
}

// MARK: - Emparejamiento por reglas (red de seguridad sin Apple Intelligence)

enum CourtVoiceCriteriaMatcher {

    /// Palabras que no identifican un criterio: artículos, conectores, el contexto de la clase y los adjetivos de valoración.
    private static let stopwords: Set<String> = [
        "para", "pero", "como", "cuando", "donde", "porque", "aunque", "tambien", "ademas", "esta", "este", "estos", "estas",
        "todo", "toda", "todos", "todas", "muy", "bien", "mal", "hoy", "pista", "clase", "sesion", "alumno", "alumna",
        "hace", "hacer", "tiene", "tener", "siempre", "nunca", "poco", "mucho", "bastante", "algo", "veces", "sobre",
        "entre", "desde", "hasta", "segun", "durante", "adecuado", "adecuada", "adecuados", "adecuadas", "correcto",
        "correcta", "correctos", "correctas", "excelente", "genial", "perfecto", "perfecta", "regular", "flojo", "floja",
        "buena", "bueno", "buenos", "buenas", "solo", "sola", "ella", "ellos"
    ]

    /// Familias de palabras del vocabulario de Educación Física que deben contar como la misma idea.
    private static let synonymGroups: [[String]] = [
        ["desplaz", "muev", "mover", "coloca", "posicion", "llega", "corre", "recorr"],
        ["golpe", "golpeo", "raqueta", "remate", "saque", "clear", "dejad"],
        ["tecni", "ejecu", "gesto"],
        ["decisi", "decid", "tacti", "elige", "eleg", "estrateg", "lee el juego"],
        ["respet", "limpi", "fair", "deportiv", "compañer", "companer", "norma", "regla"],
        ["calent", "activac"],
        ["recog", "material", "orden"],
        ["esfuerz", "intens", "empeñ", "empen", "implica"],
        ["cooper", "colabor", "equipo", "ayuda"],
        ["autoconc", "reflexi", "autoeval"],
        ["feedback", "retroal", "comenta", "empati"],
        ["etic", "valor", "competi"]
    ]

    private enum Tone: Double {
        case top = 1.0
        case good = 0.67
        case partial = 0.33
        case low = 0.0
    }

    private static let partialPhrases = ["a veces", "le cuesta", "irregular", "mejorable", "en desarrollo", "regular", "todavia", "a medias", "justo"]
    private static let lowPhrases = ["muy mal", "fatal", "no sabe", "no consigue", "insuficiente", "muy flojo", "nada bien", "mal"]
    private static let negationWords: Set<String> = ["no", "nunca", "tampoco"]
    private static let topPhrases = ["muy bien", "excelente", "perfect", "genial", "domina", "sobresal", "impecable", "brillante", "fenomenal", "de diez"]
    private static let goodPhrases = ["bien", "adecuad", "correct", "bastante", "notable", "buen", "solid", "segur"]

    // MARK: Entrada pública

    /// Devuelve una propuesta por cada criterio del instrumento. Solo los mencionados llevan evidencia y nivel sugerido.
    static func match(text: String, instrument: CourtVoiceInstrumentDescriptor) -> [CourtVoiceCriterionProposal] {
        let clauses = splitClauses(text)
        let clauseKeys = clauses.map { keys(of: $0) }
        let textKeys = Set(clauseKeys.flatMap { $0 })
        let criterionKeys = instrument.criteria.map { keys(of: $0.title) }

        var documentFrequency: [String: Int] = [:]
        for set in criterionKeys {
            for key in set { documentFrequency[key, default: 0] += 1 }
        }

        return instrument.criteria.enumerated().map { index, criterion in
            let own = criterionKeys[index]
            let matched = own.intersection(textKeys)
            let score = matched.reduce(0.0) { $0 + 1.0 / Double(documentFrequency[$1] ?? 1) }
            guard score >= 0.5 else {
                return CourtVoiceCriterionProposal(criterion: criterion)
            }
            let evidenceClauses = clauses.indices.filter { !clauseKeys[$0].intersection(own).isEmpty }.map { clauses[$0] }
            let evidence = evidenceClauses.joined(separator: " … ")
            let suggested = suggestLevel(for: criterion, clause: evidence)
            return CourtVoiceCriterionProposal(
                criterion: criterion,
                evidence: evidence,
                suggestedLevelId: suggested?.id,
                chosenLevelId: suggested?.id
            )
        }
    }

    /// Instrumento cuyos criterios encajan mejor con la frase. Exige al menos un criterio mencionado.
    static func bestInstrument(
        text: String,
        instruments: [CourtVoiceInstrumentDescriptor]
    ) -> (instrument: CourtVoiceInstrumentDescriptor, proposals: [CourtVoiceCriterionProposal])? {
        var best: (CourtVoiceInstrumentDescriptor, [CourtVoiceCriterionProposal], Int)?
        for instrument in instruments {
            let proposals = match(text: text, instrument: instrument)
            let mentioned = proposals.filter(\.isMentioned).count
            guard mentioned > 0 else { continue }
            if best == nil || mentioned > best!.2 {
                best = (instrument, proposals, mentioned)
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// Añade criterios a las acciones de la bandeja: evaluaciones con instrumento de criterios y observaciones que encajan.
    static func attachSuggestions(
        to draft: CourtVoiceCaptureDraft,
        instruments: [String: CourtVoiceInstrumentDescriptor]
    ) -> CourtVoiceCaptureDraft {
        guard !instruments.isEmpty else { return draft }
        var updated = draft
        let ordered = instruments.values.sorted { $0.title < $1.title }
        for index in updated.actions.indices {
            var action = updated.actions[index]
            let text = evidenceText(for: action)
            switch action.kind {
            case .quickEvaluation:
                let wasReady = action.isReadyToApply
                if let columnId = action.columnId, let instrument = instruments[columnId] {
                    action.criterionProposals = match(text: text, instrument: instrument)
                    action.criteriaColumnId = columnId
                } else if action.columnId == nil, let best = bestInstrument(text: text, instruments: ordered) {
                    action.columnId = best.instrument.columnId
                    action.columnTitle = best.instrument.title
                    action.criterionProposals = best.proposals
                    action.criteriaColumnId = best.instrument.columnId
                    action.resolutionReason = "Instrumento sugerido por los criterios mencionados"
                }
                if !wasReady && action.isReadyToApply {
                    action.isSelected = action.confidence >= 0.75
                }
            case .observation:
                if let best = bestInstrument(text: text, instruments: ordered) {
                    action.criterionProposals = best.proposals
                    action.criteriaColumnId = best.instrument.columnId
                    action.criteriaColumnTitle = best.instrument.title
                }
            case .attendance, .injury:
                break
            }
            updated.actions[index] = action
        }
        return updated
    }

    static func evidenceText(for action: CourtVoiceProposedAction) -> String {
        let excerpt = action.sourceExcerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = action.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if excerpt.isEmpty { return note }
        if note.isEmpty || normalized(excerpt).contains(normalized(note)) { return excerpt }
        return "\(excerpt). \(note)"
    }

    // MARK: Nivel sugerido

    static func suggestLevel(for criterion: CourtVoiceCriterionDescriptor, clause: String) -> CourtVoiceCriterionLevel? {
        let text = normalized(clause)
        let words = wordList(text)
        let isNegated = words.contains { negationWords.contains($0) }

        switch criterion.kind {
        case .check:
            if isNegated || tone(of: text, words: words) == .low { return .checkNo }
            return .checkYes
        case .level:
            let levels = criterion.levels
            guard !levels.isEmpty else { return nil }
            // 1. Nivel nombrado ("logrado", "avanzado").
            if let named = levels.first(where: { level in
                let name = normalized(level.name)
                return name.count >= 4 && text.contains(name)
            }) {
                return named
            }
            // 2. Nivel dictado con número ("un 3", "nivel 2").
            if let number = explicitLevelNumber(in: words), number >= 1, number <= levels.count {
                return levels[number - 1]
            }
            // 3. Tono de la frase. Sin tono, no se propone nada: lo decide el docente.
            guard let tone = isNegated ? .low : tone(of: text, words: words) else { return nil }
            let index = Int((Double(levels.count - 1) * tone.rawValue).rounded())
            return levels[Swift.min(levels.count - 1, Swift.max(0, index))]
        }
    }

    private static func tone(of text: String, words: [String]) -> Tone? {
        if partialPhrases.contains(where: { text.contains($0) }) { return .partial }
        if lowPhrases.contains(where: { phrase in phrase.contains(" ") ? text.contains(phrase) : words.contains(phrase) }) { return .low }
        if topPhrases.contains(where: { text.contains($0) }) { return .top }
        if goodPhrases.contains(where: { phrase in words.contains { $0.hasPrefix(phrase) } }) { return .good }
        return nil
    }

    private static func explicitLevelNumber(in words: [String]) -> Int? {
        for (index, word) in words.enumerated() {
            guard let value = Int(word), index > 0 else { continue }
            if ["un", "una", "nivel", "con"].contains(words[index - 1]) { return value }
        }
        return nil
    }

    // MARK: Texto

    static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES")).lowercased()
    }

    private static func wordList(_ normalizedText: String) -> [String] {
        normalizedText.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// Divide en cláusulas por puntuación y conectores, conservando el texto original para mostrarlo como evidencia.
    static func splitClauses(_ text: String) -> [String] {
        var clauses: [String] = []
        let pieces = text.components(separatedBy: CharacterSet(charactersIn: ",.;:!?\n"))
        let connectors = [" y ", " pero ", " aunque ", " además ", " ademas ", " e "]
        for piece in pieces {
            var parts = [piece]
            for connector in connectors {
                parts = parts.flatMap { $0.components(separatedBy: connector) }
            }
            clauses.append(contentsOf: parts)
        }
        return clauses
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Claves de significado: familia de sinónimos o raíz de 5 letras de cada palabra con contenido.
    static func keys(of text: String) -> Set<String> {
        let normalizedText = normalized(text)
        var result = Set<String>()
        for (groupIndex, group) in synonymGroups.enumerated() where group.contains(where: { $0.contains(" ") && normalizedText.contains($0) }) {
            result.insert("g\(groupIndex)")
        }
        for word in wordList(normalizedText) where word.count >= 4 && !stopwords.contains(word) {
            if let groupIndex = synonymGroups.firstIndex(where: { group in group.contains { !$0.contains(" ") && word.hasPrefix($0) } }) {
                result.insert("g\(groupIndex)")
            } else {
                result.insert(String(word.prefix(5)))
            }
        }
        return result
    }
}

// MARK: - Refinado con Apple Intelligence (en el dispositivo)

@MainActor
enum CourtVoiceCriteriaModelRefiner {

    static var isAvailable: Bool {
        AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available
    }

    /// Pide al modelo qué criterios se mencionan y con qué nivel. Solo se aceptan ids y niveles que existen;
    /// el resto se descarta. Los criterios que ya detectaron las reglas se conservan.
    static func refine(
        text: String,
        proposals: [CourtVoiceCriterionProposal]
    ) async -> [CourtVoiceCriterionProposal] {
        #if canImport(FoundationModels)
        guard isAvailable, !proposals.isEmpty else { return proposals }
        if #available(iOS 26.0, macOS 26.0, *) {
            let catalog = proposals.map { proposal in
                let levels = proposal.criterion.levels.map(\.name).joined(separator: " / ")
                return "- id \(proposal.criterion.id): \(proposal.criterion.title) [niveles: \(levels)]"
            }.joined(separator: "\n")
            let prompt = """
            Frase del profesor sobre un alumno: «\(text)»
            Criterios del instrumento:
            \(catalog)
            Devuelve solo los criterios a los que la frase se refiere de verdad. Para cada uno, el nivel que mejor describe lo dicho,
            copiado exactamente de su lista de niveles, o vacío si la frase no indica nivel. No incluyas criterios no mencionados.
            """
            do {
                let session = LanguageModelSession(instructions: "Ayudas a un profesor de Educación Física a evaluar con rúbricas. No inventas valoraciones que no se hayan dicho.")
                let response = try await session.respond(
                    to: prompt,
                    generating: GeneratedCriteriaMatches.self,
                    includeSchemaInPrompt: true,
                    options: AppleFoundationModelSupport.generationOptions(temperature: 0.0)
                )
                return merge(response.content.matches.map { (criterionId: $0.criterionId, levelName: $0.levelName, evidence: $0.evidence) }, into: proposals)
            } catch {
                AppleFoundationModelSupport.recordRuntimeFailure(error)
                return proposals
            }
        }
        #endif
        return proposals
    }

    /// Une la respuesta del modelo con las propuestas. Nunca cambia un nivel que el docente ya tocó.
    static func merge(
        _ matches: [(criterionId: String, levelName: String?, evidence: String)],
        into proposals: [CourtVoiceCriterionProposal]
    ) -> [CourtVoiceCriterionProposal] {
        var result = proposals
        for match in matches {
            guard let index = result.firstIndex(where: { $0.criterion.id == match.criterionId.trimmingCharacters(in: .whitespaces) }) else { continue }
            var proposal = result[index]
            let teacherTouched = proposal.chosenLevelId != proposal.suggestedLevelId
            if proposal.evidence == nil {
                let evidence = match.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
                proposal.evidence = evidence.isEmpty ? "Detectado por Apple Intelligence" : evidence
            }
            if let name = match.levelName.map(CourtVoiceCriteriaMatcher.normalized),
               let level = proposal.criterion.levels.first(where: { CourtVoiceCriteriaMatcher.normalized($0.name) == name }),
               !teacherTouched {
                proposal.suggestedLevelId = level.id
                proposal.chosenLevelId = level.id
            }
            result[index] = proposal
        }
        return result
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedCriterionMatch {
    @Guide(description: "Id exacto del criterio, copiado de la lista")
    let criterionId: String
    @Guide(description: "Nombre exacto del nivel, copiado de la lista del criterio; nil si la frase no indica nivel")
    let levelName: String?
    @Guide(description: "Fragmento literal de la frase que se refiere a este criterio")
    let evidence: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedCriteriaMatches {
    let matches: [GeneratedCriterionMatch]
}
#endif

// MARK: - Carga de instrumentos de la clase

@MainActor
enum CourtVoiceInstrumentLoader {
    /// Lee criterios de rúbricas y plantillas estructuradas de las columnas visibles. No escribe nada.
    static func load(
        bridge: KmpBridge,
        classId: Int64,
        columns: [NotebookColumnDefinition]
    ) async -> [String: CourtVoiceInstrumentDescriptor] {
        let evaluations = (try? await bridge.container.evaluationsRepository.listClassEvaluations(classId: classId)) ?? []
        var rubricByEvaluation: [Int64: Int64] = [:]
        for evaluation in evaluations {
            if let rubricId = evaluation.rubricId?.int64Value { rubricByEvaluation[evaluation.id] = rubricId }
        }

        var result: [String: CourtVoiceInstrumentDescriptor] = [:]
        for column in columns {
            let evaluationId = column.evaluationId?.int64Value
            if let evaluationId,
               let rubricId = column.rubricId?.int64Value ?? rubricByEvaluation[evaluationId],
               let detail = try? await bridge.container.rubricsRepository.getRubricDetail(rubricId: rubricId) {
                let criteria = detail.criteria
                    .sorted { $0.criterion.order < $1.criterion.order }
                    .map { entry in
                        CourtVoiceCriterionDescriptor(
                            id: String(entry.criterion.id),
                            title: entry.criterion.description_,
                            kind: .level,
                            weight: entry.criterion.weight,
                            levels: entry.levels
                                .map { level in
                                    CourtVoiceCriterionLevel(
                                        id: String(level.id),
                                        name: level.name,
                                        points: Double(level.points > 0 ? level.points : level.order),
                                        detail: level.description_?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                                    )
                                }
                                .sorted { $0.points < $1.points }
                        )
                    }
                if !criteria.isEmpty {
                    result[column.id] = CourtVoiceInstrumentDescriptor(
                        columnId: column.id,
                        title: column.title,
                        source: .rubric(evaluationId: evaluationId, rubricId: rubricId),
                        criteria: criteria
                    )
                }
                continue
            }

            guard column.inputKind.isStructuredInstrument,
                  let detail = try? await bridge.container.notebookInstrumentsRepository.getTemplateForColumn(columnId: column.id) else {
                continue
            }
            let criteria: [CourtVoiceCriterionDescriptor] = detail.items
                .sorted { $0.order < $1.order }
                .compactMap { item in
                    switch item.type {
                    case .check:
                        return CourtVoiceCriterionDescriptor(id: item.id, title: item.title, kind: .check, weight: 1, levels: [.checkNo, .checkYes])
                    case .scale14:
                        let levels = (1...4).map { value in
                            CourtVoiceCriterionLevel(
                                id: String(value),
                                name: item.options.count == 4 ? item.options[value - 1] : String(value),
                                points: Double(value),
                                detail: nil
                            )
                        }
                        return CourtVoiceCriterionDescriptor(id: item.id, title: item.title, kind: .level, weight: 1, levels: levels)
                    default:
                        return nil
                    }
                }
            if !criteria.isEmpty {
                result[column.id] = CourtVoiceInstrumentDescriptor(columnId: column.id, title: column.title, source: .template, criteria: criteria)
            }
        }
        return result
    }
}

// MARK: - Editor de criterios en la bandeja (HIG: un control segmentado por criterio)

struct CourtVoiceCriteriaEditor: View {
    let proposals: [CourtVoiceCriterionProposal]
    let isLoading: Bool
    let onChoose: (_ criterionId: String, _ levelId: String?) -> Void

    @State private var showsUnmentioned = false

    private var mentioned: [CourtVoiceCriterionProposal] { proposals.filter { $0.isMentioned || $0.chosenLevelId != nil } }
    private var unmentioned: [CourtVoiceCriterionProposal] { proposals.filter { !$0.isMentioned && $0.chosenLevelId == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                ProgressView("Buscando criterios")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if mentioned.isEmpty && !isLoading {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No encuentro a qué criterio te refieres").font(.subheadline.weight(.semibold))
                        Text("Elige el nivel en los criterios que quieras valorar.").font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement(children: .combine)
            }

            ForEach(Array(mentioned.enumerated()), id: \.element.id) { offset, proposal in
                CourtVoiceCriterionRow(number: offset + 1, proposal: proposal, onChoose: onChoose)
            }

            if !unmentioned.isEmpty {
                DisclosureGroup(isExpanded: Binding(
                    get: { showsUnmentioned || mentioned.isEmpty },
                    set: { showsUnmentioned = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(unmentioned) { proposal in
                            CourtVoiceCriterionRow(number: nil, proposal: proposal, onChoose: onChoose)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text(unmentioned.count == 1 ? "1 criterio sin mencionar · sin valorar" : "\(unmentioned.count) criterios sin mencionar · sin valorar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            footer
        }
    }

    @ViewBuilder
    private var footer: some View {
        let valued = proposals.filter { $0.chosenLevelId != nil }
        if !valued.isEmpty {
            HStack {
                Text("\(valued.count) de \(proposals.count) · los demás no cuentan")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                if let score = proposals.previewScore {
                    Text("Nota \(IosFormatting.decimal(from: score))")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                } else {
                    let yes = valued.filter { $0.chosenLevelId == CourtVoiceCriterionLevel.checkYes.id }.count
                    Text("\(yes) de \(valued.count) logrados")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            }
        }
    }
}

private struct CourtVoiceCriterionRow: View {
    let number: Int?
    let proposal: CourtVoiceCriterionProposal
    let onChoose: (_ criterionId: String, _ levelId: String?) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var criterion: CourtVoiceCriterionDescriptor { proposal.criterion }

    /// Lista de cotejo: Sí, No y Sin marcar. Rúbrica: niveles de menor a mayor.
    private var options: [CourtVoiceCriterionLevel] {
        criterion.kind == .check ? [.checkYes, .checkNo] : criterion.levels
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let number {
                    Text("\(number)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(EvaluationDesign.accent, in: Circle())
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(criterion.title)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let evidence = proposal.evidence, !evidence.isEmpty {
                        Text("Por «\(evidence)»")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            levelPicker

            if let detail = proposal.chosenLevel?.detail {
                Text("\(proposal.chosenLevel?.name ?? ""): \(detail)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if let suggested = proposal.suggestedLevel {
                    Label("Sugerido: \(suggested.name)", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)
                    if proposal.chosenLevelId != suggested.id {
                        Button("Volver a la sugerencia") { onChoose(criterion.id, suggested.id) }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.borderless)
                    }
                }
                Spacer(minLength: 0)
                if criterion.kind == .level, proposal.chosenLevelId != nil {
                    Button("Sin valorar") { onChoose(criterion.id, nil) }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(criterion.title)
    }

    @ViewBuilder
    private var levelPicker: some View {
        let selection = Binding<String?>(
            get: { proposal.chosenLevelId },
            set: { onChoose(criterion.id, $0) }
        )
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(pickerOptions, id: \.id) { option in
                    Button {
                        onChoose(criterion.id, option.levelId)
                    } label: {
                        HStack {
                            Text(option.label)
                            Spacer()
                            if proposal.chosenLevelId == option.levelId {
                                Image(systemName: "checkmark").foregroundStyle(EvaluationDesign.accent)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(proposal.chosenLevelId == option.levelId ? .isSelected : [])
                }
            }
        } else {
            Picker(criterion.title, selection: selection) {
                ForEach(pickerOptions, id: \.id) { option in
                    if let symbol = option.symbol {
                        Label(option.label, systemImage: symbol).tag(option.levelId)
                    } else {
                        Text(option.label).tag(option.levelId)
                    }
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityValue(accessibilityValue)
        }
    }

    private struct PickerOption {
        let id: String
        let levelId: String?
        let label: String
        let symbol: String?
    }

    private var pickerOptions: [PickerOption] {
        if criterion.kind == .check {
            return [
                PickerOption(id: "si", levelId: "si", label: "Sí", symbol: "checkmark"),
                PickerOption(id: "no", levelId: "no", label: "No", symbol: "xmark"),
                PickerOption(id: "none", levelId: nil, label: "Sin marcar", symbol: nil)
            ]
        }
        return options.map { PickerOption(id: $0.id, levelId: $0.id, label: $0.name, symbol: nil) }
    }

    private var accessibilityValue: String {
        guard let chosen = proposal.chosenLevel else {
            return criterion.kind == .check ? "Sin marcar" : "Sin valorar"
        }
        var value = chosen.name
        if criterion.kind == .level, let index = criterion.levels.firstIndex(of: chosen) {
            value += ", \(index + 1) de \(criterion.levels.count)"
        }
        if chosen.id == proposal.suggestedLevelId { value += ", sugerido" }
        return value
    }
}
