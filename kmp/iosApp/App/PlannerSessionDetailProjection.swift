import Foundation
import MiGestorKit

/// Presentación docente de un plan importado.
///
/// Los planes históricos guardan el desarrollo como líneas de texto porque el payload de
/// SQLDelight es deliberadamente opaco. Esta proyección deshace el formato que usa el
/// importador (`tiempo · fase · actividad (Profesorado: …; Alumnado: …; Evidencia: …)`) sin
/// exigir una migración y mantiene un fallback legible para planes antiguos.
struct PlannerSessionDetailProjection {
    let objective: String
    let criteria: [String]
    let materials: [String]
    let basicKnowledge: [String]
    let evidence: [String]
    let adaptations: [String]
    let organisation: String
    let coreKnowledge: String
    let assessment: String
    let guidingQuestions: [String]
    let closure: String
    let activities: [LearningSituationSessionActivityDraft]
    let timeline: [PlannerSessionTimelineBlock]
    let supportSections: [PlannerSessionSupportSection]
    let clilChunks: LearningSituationCLILChunksDraft?
    let activityCount: Int
    // Repaso rápido: se calculan una sola vez al construir la proyección.
    let reviewObjective: String
    let setupBullets: [String]
    let attentionNotes: [String]
    /// Montaje y atención completos, por si `setupBullets`/`attentionNotes` recortaron algo.
    let setupAll: [String]
    let attentionAll: [String]
    let guideBlocks: [PlannerSessionReviewBlock]

    init(plan: LearningSituationSessionPlan) {
        let payload = Self.decodePayload(plan.developmentJson)
        let rawActivities = PlannerSessionPlanPayloadNormalizer.activities(from: payload)
        let rawSections = PlannerSessionPlanPayloadNormalizer.sections(from: payload)

        // Los documentos narrativos (p. ej. 1º BAC) incluyen el bloque de chunks CLIL como texto dentro
        // de la última fase numerada, sin sección propia. Se extraen de cualquier línea y se retiran
        // del texto de actividades/secciones para que se muestren solo en su tarjeta.
        let chunkSectionsText = rawSections
            .filter { section in
                let title = Self.normalized(section.title)
                return title.contains("chunk") || title.contains("clil") || title.contains("bilingue")
            }
            .flatMap(\.lines)
            .joined(separator: "\n")
        let anyLineText = (rawSections.flatMap(\.lines) + rawActivities.map(\.teacherActions)).joined(separator: "\n")
        let embeddedChunks = payload.clilChunks.flatMap { $0.isEmpty ? nil : $0 }
            ?? LearningSituationSessionDevelopmentPayload.parseCLILChunks(from: chunkSectionsText)
            ?? LearningSituationSessionDevelopmentPayload.parseCLILChunks(from: anyLineText)
        let stripsChunkLines = embeddedChunks != nil
        let normalizedActivities: [LearningSituationSessionActivityDraft] = stripsChunkLines
            ? rawActivities.map { activity in
                var copy = activity
                copy.teacherActions = Self.strippingChunkLines(from: activity.teacherActions)
                return copy
            }
            : rawActivities
        let sections: [LearningSituationSessionSectionDraft] = stripsChunkLines
            ? rawSections.map { section in
                LearningSituationSessionSectionDraft(
                    title: section.title,
                    lines: section.lines.map(Self.strippingChunkLines).filter { !$0.isEmpty }
                )
            }
            : rawSections
        let timelineSections = sections.filter(Self.isTimelineSection)
        let timeline = timelineSections.map(PlannerSessionTimelineBlock.init)

        let sectionEvidence = sections
            .filter(Self.isEvidenceSection)
            .flatMap { section in
                section.lines.isEmpty ? [section.title] : section.lines
            }

        let stepEvidence = timeline
            .flatMap(\.steps)
            .compactMap(\.evidence)

        let materialParts = Self.materialParts(plan.material)
        self.objective = Self.cleaned(plan.objective)
        self.criteria = Self.decodeStrings(plan.criteriaJson)
        self.materials = materialParts.materials
        self.basicKnowledge = Self.unique(materialParts.basicKnowledge + Self.splitList(payload.coreKnowledge))
        self.evidence = Self.unique(sectionEvidence + stepEvidence + Self.splitList(payload.assessment))
        self.adaptations = Self.decodeStrings(plan.adaptationsJson)
        self.organisation = Self.cleaned(payload.organisation)
        self.coreKnowledge = Self.cleaned(payload.coreKnowledge)
        self.assessment = Self.cleaned(payload.assessment)
        self.guidingQuestions = Self.unique(payload.guidingQuestions.map(Self.cleaned).filter { !$0.isEmpty })
        self.closure = Self.cleaned(stripsChunkLines ? Self.strippingChunkLines(from: payload.closure) : payload.closure)
        self.activities = normalizedActivities
        self.timeline = timeline
        self.supportSections = sections
            .filter { !Self.isTimelineSection($0) && !Self.isEvidenceSection($0) }
            .compactMap(PlannerSessionSupportSection.init)

        self.clilChunks = embeddedChunks

        self.activityCount = normalizedActivities.isEmpty
            ? timeline.reduce(0) { $0 + $1.steps.count }
            : normalizedActivities.count

        let review = PlannerSessionReviewBuilder(
            objective: self.objective,
            organisation: self.organisation,
            adaptations: self.adaptations,
            activities: normalizedActivities
        )
        self.reviewObjective = review.objective
        self.setupAll = review.setupAll
        self.setupBullets = review.setupBullets
        self.attentionAll = review.attentionAll
        self.attentionNotes = review.attentionNotes
        self.guideBlocks = review.blocks
    }

    /// Etiqueta de bloque/segmento de una sesión LONG (`U01 · Título`). No repite la clave si el título ya la lleva.
    static func segmentLabel(for activity: LearningSituationSessionActivityDraft) -> String? {
        let key = activity.segmentKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = activity.segmentTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // El título del segmento ya suele empezar por la clave (`U01`): no se repite («U01 · U01»).
        if !title.isEmpty, key.isEmpty || title.lowercased().hasPrefix(key.lowercased()) || title.caseInsensitiveCompare(key) == .orderedSame {
            return title
        }
        let label = [key, title].filter { !$0.isEmpty }.joined(separator: " · ")
        return label.isEmpty ? nil : label
    }

    var hasTeacherBrief: Bool {
        !objective.isEmpty || !criteria.isEmpty || !evidence.isEmpty || !materials.isEmpty || !basicKnowledge.isEmpty
    }

    /// Quita de un texto multilínea el encabezado del bloque de chunks CLIL y sus líneas etiquetadas
    /// (Teacher Cues / Student Interaction / Debrief o su equivalente en castellano).
    static func strippingChunkLines(from text: String) -> String {
        let labelPattern = #"^(?:pautas de accion docente|teacher cues|comunicacion en juego|student interaction|feedback y reflexion|debrief)\b"#
        let headingPattern = #"^(?:chunks?\s+linguisticos?|language\s+chunks)\b"#
        return text
            .components(separatedBy: .newlines)
            .filter { line in
                let value = normalized(line)
                    .replacingOccurrences(of: #"^[\s\-\u2022*#]+"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: "*", with: "")
                return value.range(of: labelPattern, options: .regularExpression) == nil
                    && value.range(of: headingPattern, options: .regularExpression) == nil
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodePayload(_ json: String) -> LearningSituationSessionDevelopmentPayload {
        if let payload = LearningSituationSessionDevelopmentPayload.decode(from: json) {
            return payload
        }
        return LearningSituationSessionDevelopmentPayload(schema: "legacy", schemaVersion: 1, sections: [], activities: [])
    }

    private static func decodeStrings(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return unique(values.map(cleaned).filter { !$0.isEmpty })
    }

    private static func materialParts(_ material: String) -> (materials: [String], basicKnowledge: [String]) {
        let cleanedMaterial = cleaned(material)
        guard !cleanedMaterial.isEmpty else { return ([], []) }

        let marker = "— Saberes básicos:"
        let split = cleanedMaterial.range(of: marker, options: [.caseInsensitive, .diacriticInsensitive])
        let materialText: String
        let knowledgeText: String
        if let split {
            materialText = String(cleanedMaterial[..<split.lowerBound])
            knowledgeText = String(cleanedMaterial[split.upperBound...])
        } else {
            materialText = cleanedMaterial
            knowledgeText = ""
        }

        return (
            splitList(materialText),
            splitList(knowledgeText)
        )
    }

    private static func splitList(_ value: String) -> [String] {
        unique(value
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map(cleaned)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty })
    }

    private static func isEvidenceSection(_ section: LearningSituationSessionSectionDraft) -> Bool {
        let title = normalized(section.title)
        return title.hasPrefix("evidencia") || title.hasPrefix("evidence") ||
            title.hasPrefix("evaluacion") || title.hasPrefix("assessment")
    }

    private static func isTimelineSection(_ section: LearningSituationSessionSectionDraft) -> Bool {
        let title = normalized(section.title)
        if title.hasPrefix("adaptacion") || title.hasPrefix("adaptation") || isEvidenceSection(section) {
            return false
        }
        if title.hasPrefix("block ") || title.hasPrefix("bloque ") ||
            title.hasPrefix("break") || title.hasPrefix("descanso") ||
            title.contains("variante prepara") || title.contains("variante consolida") ||
            title.contains("prepara") || title.contains("consolida") {
            return true
        }
        return section.lines.contains { line in
            Self.parseStep(line).timeLabel != nil
        }
    }

    static func parseStep(_ rawLine: String) -> PlannerSessionTimelineStep {
        var line = cleaned(rawLine)
        var teacherRole: String?
        var studentRole: String?
        var evidence: String?

        if let open = line.lastIndex(of: "("), line.hasSuffix(")") {
            let suffix = String(line[line.index(after: open)..<line.index(before: line.endIndex)])
            if suffix.localizedCaseInsensitiveContains("profesor") ||
                suffix.localizedCaseInsensitiveContains("teacher") ||
                suffix.localizedCaseInsensitiveContains("alumn") ||
                suffix.localizedCaseInsensitiveContains("student") ||
                suffix.localizedCaseInsensitiveContains("evidencia") ||
                suffix.localizedCaseInsensitiveContains("evidence") {
                line = cleaned(String(line[..<open]))
                let labels = parseLabels(suffix)
                teacherRole = labels.teacher
                studentRole = labels.student
                evidence = labels.evidence
            }
        }

        let components = line
            .components(separatedBy: " · ")
            .map(cleaned)
            .filter { !$0.isEmpty }

        guard !components.isEmpty else {
            return PlannerSessionTimelineStep(timeLabel: nil, phase: nil, activity: "", teacherRole: teacherRole, studentRole: studentRole, evidence: evidence)
        }

        let timeLabel: String?
        var content = components
        if looksLikeTime(components[0]) {
            timeLabel = components[0]
            content.removeFirst()
        } else {
            timeLabel = nil
        }

        let phase = content.count >= 2 ? content.removeFirst() : nil
        let activity = content.joined(separator: " · ")
        return PlannerSessionTimelineStep(
            timeLabel: timeLabel,
            phase: phase,
            activity: activity.isEmpty ? (phase ?? components[0]) : activity,
            teacherRole: teacherRole,
            studentRole: studentRole,
            evidence: evidence
        )
    }

    private static func parseLabels(_ suffix: String) -> (teacher: String?, student: String?, evidence: String?) {
        let pattern = #"(?i)(Profesorado|Teacher(?: role)?|Docente|Alumnado|Student(?: role)?|Evidencia|Evidence)\s*:\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let fullRange = Range(NSRange(location: 0, length: suffix.utf16.count), in: suffix) else {
            return (nil, nil, nil)
        }

        let matches = regex.matches(in: suffix, range: NSRange(fullRange, in: suffix))
        var teacher: String?
        var student: String?
        var evidence: String?
        for (index, match) in matches.enumerated() {
            guard let labelRange = Range(match.range(at: 1), in: suffix) else { continue }
            let valueStart = Range(match.range, in: suffix)?.upperBound ?? suffix.index(after: labelRange.upperBound)
            let valueEnd: String.Index
            if index + 1 < matches.count, let nextRange = Range(matches[index + 1].range, in: suffix) {
                valueEnd = suffix.index(before: nextRange.lowerBound)
            } else {
                valueEnd = suffix.endIndex
            }
            let value = cleaned(String(suffix[valueStart..<valueEnd]).trimmingCharacters(in: CharacterSet(charactersIn: "; ")))
            guard !value.isEmpty else { continue }
            let label = normalized(String(suffix[labelRange]))
            if label.contains("profesor") || label.contains("teacher") || label.contains("docente") {
                teacher = value
            } else if label.contains("alumn") || label.contains("student") {
                student = value
            } else if label.contains("evidencia") || label.contains("evidence") {
                evidence = value
            }
        }
        return (teacher, student, evidence)
    }

    private static func looksLikeTime(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{1,3}\s*(?:['’′]|min)?(?:\s*[-–—]\s*[0-9]{1,3}\s*(?:['’′]|min)?)?$"#, options: .regularExpression) != nil
    }

    fileprivate static func blockTitle(_ title: String) -> (clean: String, duration: String?, kind: PlannerSessionTimelineBlock.Kind) {
        let normalizedTitle = normalized(title)
        let kind: PlannerSessionTimelineBlock.Kind = normalizedTitle.hasPrefix("break") || normalizedTitle.hasPrefix("descanso")
            ? .breakTime
            : (normalizedTitle.contains("prepara") ? .prepare : (normalizedTitle.contains("consolida") ? .consolidate : .activity))
        let duration = title.range(of: #"\([0-9]{1,3}\s*(?:['’′]|min)[^)]*\)"#, options: .regularExpression)
            .map { String(title[$0]).trimmingCharacters(in: CharacterSet(charactersIn: "()")) }
        let clean = title
            .replacingOccurrences(of: #"\s*\([0-9]{1,3}\s*(?:['’′]|min)[^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean.isEmpty ? title : clean, duration, kind)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert(normalized($0)).inserted }
    }

    private static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalized(_ value: String) -> String {
        cleaned(value).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}

/// Compatibilidad de lectura/escritura para planes que se guardaron antes de que el
/// importador tuviera un contrato tipado. La reparación es deliberadamente idempotente:
/// conserva actividades v2 válidas, convierte las líneas legacy a v2 y nunca expone un
/// identificador técnico como si fuera el título docente.
enum PlannerSessionPlanPayloadNormalizer {
    private static let activityIDPattern = try! NSRegularExpression(
        pattern: #"^W[0-9]{2}-[LS]-[0-9]{2}$"#,
        options: .caseInsensitive
    )

    static func activities(from payload: LearningSituationSessionDevelopmentPayload) -> [LearningSituationSessionActivityDraft] {
        let source = payload.activities.isEmpty
            ? PlannerSessionLegacyActivityProjection.executableActivities(from: payload.sections)
            : payload.activities
        let normalized = normalizedActivities(source)
        return NarrativeSessionActivityCompactor.compact(normalized, planVisuals: payload.visuals)
    }

    static func sections(from payload: LearningSituationSessionDevelopmentPayload) -> [LearningSituationSessionSectionDraft] {
        normalizedSections(from: payload, activities: activities(from: payload))
    }

    static func normalizedJSON(from json: String) -> String? {
        guard let payload = LearningSituationSessionDevelopmentPayload.decode(from: json) else { return nil }
        let normalizedActivities = activities(from: payload)
        let normalizedPayload = LearningSituationSessionDevelopmentPayload(
            schema: "session-plan-v2",
            schemaVersion: max(payload.schemaVersion, 2),
            organisation: payload.organisation,
            coreKnowledge: payload.coreKnowledge,
            assessment: payload.assessment,
            sections: normalizedSections(from: payload, activities: normalizedActivities),
            activities: normalizedActivities,
            guidingQuestions: payload.guidingQuestions,
            closure: payload.closure,
            visuals: payload.visuals,
            sequenceRoute: payload.sequenceRoute,
            sourceDocumentSHA256: payload.sourceDocumentSHA256
        )
        guard let data = try? JSONEncoder().encode(normalizedPayload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func normalizedActivities(_ source: [LearningSituationSessionActivityDraft]) -> [LearningSituationSessionActivityDraft] {
        var seenKeys = Set<String>()
        return source.enumerated().map { index, activity in
            var copy = activity
            let rawKey = activity.activityKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayKey: String
            if rawKey.isEmpty || rawKey.uppercased().hasPrefix("LEGACY-") {
                displayKey = "Actividad \(index + 1)"
            } else {
                displayKey = rawKey
            }
            let uniqueKey = seenKeys.insert(displayKey).inserted
                ? displayKey
                : "\(displayKey) \(index + 1)"
            copy.activityKey = uniqueKey

            let title = activity.activity.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty || title.uppercased().hasPrefix("LEGACY-") || matchesActivityIdentifier(title) {
                copy.activity = "Actividad \(index + 1)"
            }
            return copy
        }
    }

    private static func normalizedSections(
        from payload: LearningSituationSessionDevelopmentPayload,
        activities: [LearningSituationSessionActivityDraft]
    ) -> [LearningSituationSessionSectionDraft] {
        guard payload.activities.count > 1,
              payload.activities.allSatisfy(NarrativeSessionActivityCompactor.isNarrative),
              !activities.isEmpty else { return payload.sections }
        let breaks = payload.sections.filter(isNarrativeBreakSection)
        var result: [LearningSituationSessionSectionDraft] = []
        var previousSegment: String?
        var breakIndex = 0

        for activity in activities {
            let segment = narrativeSegmentIdentity(for: activity)
            if let segment,
               let previousSegment,
               segment != previousSegment,
               breakIndex < breaks.count {
                result.append(breaks[breakIndex])
                breakIndex += 1
            }
            result.append(narrativeTimelineSection(for: activity))
            if segment != nil { previousSegment = segment }
        }

        // A break at the end of a source block is still meaningful and must not be lost
        // merely because there is no following segment to trigger its insertion.
        result.append(contentsOf: breaks.dropFirst(breakIndex))
        return result
    }

    private static func narrativeTimelineSection(
        for activity: LearningSituationSessionActivityDraft
    ) -> LearningSituationSessionSectionDraft {
        let segment = [activity.segmentKey, activity.segmentTitle]
            .compactMap { value in value?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let title = [segment, activity.activity]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let duration = activity.plannedMinutes.map { "\($0) min" } ?? cleaned(activity.timeLabel)
        let content = [
            activity.teacherActions,
            activity.studentInstructions,
            activity.studentActions,
            activity.adaptations.isEmpty ? "" : "Adaptaciones: \(activity.adaptations)"
        ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let line = [duration, title, content.joined(separator: "\n")]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let sectionTitle = duration.isEmpty ? title : "\(title) (\(duration))"
        return LearningSituationSessionSectionDraft(
            title: sectionTitle,
            lines: line.isEmpty ? [] : [line]
        )
    }

    private static func isNarrativeBreakSection(_ section: LearningSituationSessionSectionDraft) -> Bool {
        let value = normalized(section.title)
        return value.hasPrefix("descanso") || value.hasPrefix("break") ||
            value.hasPrefix("pausa") || value.hasPrefix("rest")
    }

    private static func narrativeSegmentIdentity(
        for activity: LearningSituationSessionActivityDraft
    ) -> String? {
        if let segmentKey = activity.segmentKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !segmentKey.isEmpty {
            return normalized(segmentKey)
        }
        let range = NSRange(activity.activityKey.startIndex..., in: activity.activityKey)
        guard let regex = try? NSRegularExpression(pattern: #"\bU[0-9]{2,3}\b"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: activity.activityKey, range: range),
              let keyRange = Range(match.range, in: activity.activityKey) else { return nil }
        return normalized(String(activity.activityKey[keyRange]))
    }

    private static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalized(_ value: String) -> String {
        cleaned(value).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private static func matchesActivityIdentifier(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return activityIDPattern.firstMatch(in: value, range: range) != nil
    }
}

struct PlannerSessionTimelineBlock: Identifiable {
    enum Kind: Equatable {
        case activity
        case breakTime
        case prepare
        case consolidate
    }

    let id: String
    let title: String
    let durationLabel: String?
    let kind: Kind
    let steps: [PlannerSessionTimelineStep]

    init(section: LearningSituationSessionSectionDraft) {
        let title = PlannerSessionDetailProjection.blockTitle(section.title)
        self.id = section.id.uuidString
        self.title = title.clean
        self.durationLabel = title.duration
        self.kind = title.kind
        self.steps = section.lines
            .map(PlannerSessionDetailProjection.parseStep)
            .filter { !$0.activity.isEmpty }
    }
}

/// Projects v1 section/line payloads into executable rows only. Evidence, questions, closure
/// and adaptation prose remain contextual sections and must not appear as activities in QUICK VIEW.
enum PlannerSessionLegacyActivityProjection {
    static func executableActivities(from sections: [LearningSituationSessionSectionDraft]) -> [LearningSituationSessionActivityDraft] {
        let timelineSections = sections.enumerated().filter { _, section in
            let title = section.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            guard !title.contains("evidencia") && !title.contains("evidence") &&
                !title.contains("evaluacion") && !title.contains("assessment") &&
                !title.contains("pregunta") && !title.contains("guiding") &&
                !title.contains("cierre") && !title.contains("closure") &&
                !title.contains("adaptacion") && !title.contains("adaptation") else { return false }
            let hasTimedLine = section.lines.contains { PlannerSessionDetailProjection.parseStep($0).timeLabel != nil }
            return hasTimedLine
        }
        let activities = timelineSections.flatMap { sectionIndex, section in
            section.lines.enumerated().compactMap { lineIndex, line -> LearningSituationSessionActivityDraft? in
                let parsed = PlannerSessionDetailProjection.parseStep(line)
                let title = parsed.activity.trimmingCharacters(in: .whitespacesAndNewlines)
                guard parsed.timeLabel != nil, !title.isEmpty else { return nil }
                return LearningSituationSessionActivityDraft(
                    activityKey: "LEGACY-\(sectionIndex + 1)-\(lineIndex + 1)",
                    activityType: "legacy",
                    timeLabel: parsed.timeLabel ?? "",
                    phase: parsed.phase ?? section.title,
                    activity: title,
                    teacherActions: parsed.teacherRole ?? "",
                    studentActions: parsed.studentRole ?? "",
                    evidence: parsed.evidence ?? ""
                )
            }
        }
        return stableActivities(activities)
    }

    static func stableActivities(_ activities: [LearningSituationSessionActivityDraft]) -> [LearningSituationSessionActivityDraft] {
        var occurrences: [String: Int] = [:]
        return activities.enumerated().map { index, activity in
            var copy = activity
            let rawKey = activity.activityKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseKey = rawKey.isEmpty ? "LEGACY-\(index + 1)" : rawKey
            let occurrence = occurrences[baseKey, default: 0]
            occurrences[baseKey] = occurrence + 1
            copy.activityKey = occurrence == 0 ? baseKey : "\(baseKey)#\(occurrence + 1)"
            return copy
        }
    }
}

struct PlannerSessionTimelineStep: Identifiable {
    let id = UUID()
    let timeLabel: String?
    let phase: String?
    let activity: String
    let teacherRole: String?
    let studentRole: String?
    let evidence: String?
}

struct PlannerSessionSupportSection: Identifiable {
    let id: String
    let title: String
    let lines: [String]

    init?(section: LearningSituationSessionSectionDraft) {
        let lines = section.lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        self.id = section.id.uuidString
        self.title = section.title
        self.lines = lines
    }
}


// MARK: - Repaso rápido

/// Un paso del guion en el visor de repaso: una actividad (o su recogida) lista para pintar.
struct PlannerSessionReviewStep: Identifiable, Equatable {
    struct Extra: Equatable {
        let label: String
        let text: String
    }

    let activityKey: String
    let minutes: Int?
    /// Minuto de inicio acumulado en la sesión (sin contar el descanso). `nil` si no hay duración conocida.
    let startOffsetMinutes: Int?
    let phase: String
    let title: String
    let detail: String
    let clil: String?
    let isMain: Bool
    let isCollection: Bool
    /// Datos secundarios de la actividad (alumnado, evidencia, temporización…): salen al pulsar «Ver más».
    let extras: [Extra]

    var id: String { activityKey }

    /// `00:04` (horas:minutos desde el inicio de la sesión).
    static func offsetLabel(_ minutes: Int) -> String {
        String(format: "%02d:%02d", max(minutes, 0) / 60, max(minutes, 0) % 60)
    }
}

/// Un bloque del guion (una unidad `U01`, `U02`…). En una sesión LONG el segundo va tras el descanso legal.
struct PlannerSessionReviewBlock: Identifiable, Equatable {
    let id: String
    let label: String?
    let totalMinutes: Int
    let precededByBreak: Bool
    let steps: [PlannerSessionReviewStep]
}

struct PlannerSessionReviewBuilder {
    static let maxSetupBullets = 4
    static let maxSetupBulletLength = 80
    static let maxAttentionNotes = 3

    let objective: String
    let setupAll: [String]
    let setupBullets: [String]
    let attentionAll: [String]
    let attentionNotes: [String]
    let blocks: [PlannerSessionReviewBlock]

    init(
        objective planObjective: String,
        organisation: String,
        adaptations: [String],
        activities: [LearningSituationSessionActivityDraft]
    ) {
        let purposes = activities.map { PlannerSessionPresentationHelper.splitPurpose($0.purpose) }

        let objective = planObjective.trimmingCharacters(in: .whitespacesAndNewlines)
        self.objective = objective.isEmpty
            ? (purposes.map(\.objective).first { !$0.isEmpty } ?? "")
            : objective

        let setupSources = [organisation]
            + activities.flatMap { [$0.organisation, $0.setup] }
            + purposes.map(\.material)
        let setup = Self.unique(setupSources.flatMap { Self.fragments($0, splitSentences: true) })
        self.setupAll = setup
        self.setupBullets = setup.prefix(Self.maxSetupBullets).map { Self.shortened($0, to: Self.maxSetupBulletLength) }

        let attentionSources = adaptations
            + activities.map(\.adaptations)
            + purposes.map(\.attention)
        let attention = Self.unique(attentionSources.flatMap { Self.fragments($0, splitSentences: false) })
        self.attentionAll = attention
        self.attentionNotes = Array(attention.prefix(Self.maxAttentionNotes))

        self.blocks = Self.makeBlocks(from: activities)
    }

    // MARK: Bloques y pasos

    private static func makeBlocks(from activities: [LearningSituationSessionActivityDraft]) -> [PlannerSessionReviewBlock] {
        var groups: [(precededByBreak: Bool, activities: [LearningSituationSessionActivityDraft])] = []
        for (index, activity) in activities.enumerated() {
            if index == 0 {
                groups.append((false, [activity]))
            } else if startsNewBlock(previous: activities[index - 1], current: activity) {
                groups.append((true, [activity]))
            } else {
                groups[groups.count - 1].activities.append(activity)
            }
        }

        var cursor = 0
        return groups.enumerated().map { index, group in
            let steps = makeSteps(from: group.activities, cursor: &cursor)
            let label = group.activities.lazy.compactMap(PlannerSessionDetailProjection.segmentLabel(for:)).first
            return PlannerSessionReviewBlock(
                id: "\(index)-\(group.activities.first?.activityKey ?? "")",
                label: label,
                totalMinutes: steps.reduce(0) { $0 + ($1.minutes ?? 0) },
                precededByBreak: group.precededByBreak,
                steps: steps
            )
        }
    }

    /// Una sesión LONG lleva dos bloques; el descanso legal se sitúa donde cambia el segmento.
    private static func startsNewBlock(
        previous: LearningSituationSessionActivityDraft,
        current: LearningSituationSessionActivityDraft
    ) -> Bool {
        guard let previousKey = previous.segmentKey?.trimmingCharacters(in: .whitespacesAndNewlines), !previousKey.isEmpty,
              let currentKey = current.segmentKey?.trimmingCharacters(in: .whitespacesAndNewlines), !currentKey.isEmpty
        else { return false }
        return previousKey != currentKey
    }

    private static func makeSteps(
        from activities: [LearningSituationSessionActivityDraft],
        cursor: inout Int
    ) -> [PlannerSessionReviewStep] {
        var drafts: [(step: PlannerSessionReviewStep, moment: NarrativeSessionActivityCompactor.Moment?)] = []
        for (index, activity) in activities.enumerated() {
            let key = activity.activityKey.isEmpty ? "Actividad \(index + 1)" : activity.activityKey
            let title = PlannerSessionPresentationHelper.displayTitle(for: activity)
            let phase = activity.phase.trimmingCharacters(in: .whitespacesAndNewlines)
            let minutes = activity.plannedMinutes ?? minutes(fromTimeLabel: activity.timeLabel)
            let isCollection = isCollectionName(title) || isCollectionName(phase)
            let clil = PlannerSessionPresentationHelper.clilCallout(for: activity)

            var teacherText = activity.teacherActions
            if clil?.isEmpty == false {
                teacherText = PlannerSessionPresentationHelper.removingCLILConsigna(from: teacherText)
            }
            var collectionTitle: String?
            if !isCollection {
                let extracted = extractingCollection(from: teacherText)
                teacherText = extracted.text
                collectionTitle = extracted.collection
            }
            let studentText = [activity.studentInstructions, activity.studentActions]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let detail = teacherText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? studentText
                : teacherText.trimmingCharacters(in: .whitespacesAndNewlines)

            var startOffset: Int?
            if !isCollection, let minutes {
                startOffset = cursor
                cursor += minutes
            }
            let purpose = PlannerSessionPresentationHelper.splitPurpose(activity.purpose)
            let extras: [PlannerSessionReviewStep.Extra] = [
                ("Propósito", purpose.objective),
                ("Organización", [activity.organisation, activity.setup].filter { !$0.isEmpty }.joined(separator: "\n")),
                ("Material", activity.materials),
                ("Alumnado", detail == studentText ? "" : studentText),
                ("Temporización", activity.timingBreakdown),
                ("Evidencia", activity.evidence),
                ("Si el grupo va lento", activity.slowGroupPlan),
                ("Extensión si termina antes", activity.fastGroupExtension),
                ("Continuidad", [activity.prepares, activity.consolidates].filter { !$0.isEmpty }.joined(separator: "\n"))
            ].compactMap { label, text in
                let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : PlannerSessionReviewStep.Extra(label: label, text: value)
            }

            let moment = NarrativeSessionActivityCompactor.moment(for: phase.isEmpty ? activity.activity : phase)
            drafts.append((
                PlannerSessionReviewStep(
                    activityKey: key,
                    minutes: minutes,
                    startOffsetMinutes: startOffset,
                    phase: phase,
                    title: title,
                    detail: detail,
                    clil: clil,
                    isMain: false,
                    isCollection: isCollection,
                    extras: extras
                ),
                isCollection ? nil : moment
            ))
            if let collectionTitle {
                drafts.append((
                    PlannerSessionReviewStep(
                        activityKey: "\(key)#recogida",
                        minutes: nil,
                        startOffsetMinutes: nil,
                        phase: "Recogida",
                        title: collectionTitle,
                        detail: "",
                        clil: nil,
                        isMain: false,
                        isCollection: true,
                        extras: []
                    ),
                    nil
                ))
            }
        }

        // El paso principal es el de más minutos entre los del momento «principal».
        let mainIndex = drafts.indices
            .filter { drafts[$0].moment == .main }
            .max { (drafts[$0].step.minutes ?? 0) < (drafts[$1].step.minutes ?? 0) }
            .map { candidate -> Int in
                // `max` devuelve el último empate: se prefiere el primero.
                let best = drafts[candidate].step.minutes ?? 0
                return drafts.indices.first { drafts[$0].moment == .main && (drafts[$0].step.minutes ?? 0) == best } ?? candidate
            }
        return drafts.enumerated().map { index, entry in
            let step = entry.step
            guard index == mainIndex else { return step }
            return PlannerSessionReviewStep(
                activityKey: step.activityKey, minutes: step.minutes, startOffsetMinutes: step.startOffsetMinutes,
                phase: step.phase, title: step.title, detail: step.detail, clil: step.clil,
                isMain: true, isCollection: step.isCollection, extras: step.extras
            )
        }
    }

    private static func isCollectionName(_ value: String) -> Bool {
        normalized(value).hasPrefix("recogida")
    }

    /// Saca de un texto docente la línea «Recogida: …» para mostrarla como paso propio.
    private static func extractingCollection(from text: String) -> (text: String, collection: String?) {
        var collection: String?
        var kept: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let stripped = line
                .replacingOccurrences(of: #"^[\s\-\u2022*#]+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "*", with: "")
            if collection == nil, normalized(stripped).hasPrefix("recogida"),
               let colon = stripped.firstIndex(where: { $0 == ":" || $0 == "." }) {
                let rest = stripped[stripped.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
                collection = rest.isEmpty ? "Recoger el material" : rest
            } else {
                kept.append(line)
            }
        }
        return (kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), collection)
    }

    private static func minutes(fromTimeLabel label: String) -> Int? {
        let value = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = value.range(of: #"^([0-9]{1,3})\s*(?:['’′]|min)?\s*[-–—]\s*([0-9]{1,3})"#, options: .regularExpression) {
            let numbers = value[range].components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
            if numbers.count >= 2, numbers[1] > numbers[0] { return numbers[1] - numbers[0] }
            return nil
        }
        if let range = value.range(of: #"^[0-9]{1,3}(?=\s*(?:['’′]|min))"#, options: .regularExpression) {
            return Int(value[range])
        }
        return nil
    }

    // MARK: Texto

    /// Parte un texto en viñetas por salto de línea, `;` y (opcional) `. `.
    private static func fragments(_ text: String, splitSentences: Bool) -> [String] {
        var value = text.replacingOccurrences(of: ";", with: "\n")
        if splitSentences {
            value = value.replacingOccurrences(of: #"\.\s+"#, with: "\n", options: .regularExpression)
        }
        return value.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"^[\s\-\u2022*]+"#, with: "", options: .regularExpression) }
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))) }
            .filter { !$0.isEmpty }
    }

    private static func shortened(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))
        let cut = head.lastIndex(of: " ").map { String(head[..<$0]) } ?? head
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Quita duplicados. El prefijo de unidad («U10 · ») no cuenta: el mismo aviso
    /// repetido por unidad sale una sola vez.
    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert(normalized(withoutUnitPrefix($0))).inserted }
    }

    static func withoutUnitPrefix(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"^\s*[A-Za-z]{1,3}\d{1,3}\s*[·:\-–—]\s*"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
