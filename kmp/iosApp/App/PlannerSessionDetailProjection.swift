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
    let timeline: [PlannerSessionTimelineBlock]
    let supportSections: [PlannerSessionSupportSection]
    let activityCount: Int

    init(plan: LearningSituationSessionPlan) {
        let sections = Self.decodeSections(plan.developmentJson)
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
        self.basicKnowledge = materialParts.basicKnowledge
        self.evidence = Self.unique(sectionEvidence + stepEvidence)
        self.adaptations = Self.decodeStrings(plan.adaptationsJson)
        self.timeline = timeline
        self.supportSections = sections
            .filter { !Self.isTimelineSection($0) && !Self.isEvidenceSection($0) }
            .compactMap(PlannerSessionSupportSection.init)
        self.activityCount = timeline.reduce(0) { $0 + $1.steps.count }
    }

    var hasTeacherBrief: Bool {
        !objective.isEmpty || !criteria.isEmpty || !evidence.isEmpty || !materials.isEmpty || !basicKnowledge.isEmpty
    }

    private static func decodeSections(_ json: String) -> [LearningSituationSessionSectionDraft] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([LearningSituationSessionSectionDraft].self, from: data)) ?? []
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
