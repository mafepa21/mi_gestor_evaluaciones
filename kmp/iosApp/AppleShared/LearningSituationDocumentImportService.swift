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
    /// Tablas del DOCX original que no encajan en ningún campo estructurado (p.ej. la
    /// secuenciación de sesiones "Sesión | Contenido | Criterio" o una tabla de adaptaciones
    /// "Barrera | Adaptación"). Se conservan como tabla para no aplanarlas en líneas sueltas.
    /// Opcional para poder decodificar situaciones guardadas antes de que existiera este campo.
    var documentTables: [LearningSituationTableDraft]?
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
        documentTables: [LearningSituationTableDraft] = [],
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
        self.documentTables = documentTables
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

/// Tabla del documento fuente que se conserva tal cual (cabecera + filas) en vez de aplanarla.
struct LearningSituationTableDraft: Identifiable, Codable {
    let id: UUID
    var title: String
    var header: [String]
    var rows: [[String]]

    init(title: String, header: [String], rows: [[String]]) {
        self.id = UUID()
        self.title = title
        self.header = header
        self.rows = rows
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

/// Una actividad ejecutable por el docente. Se mantiene separada de las secciones
/// narrativas para que la ficha de sesión pueda mostrar una secuencia accionable
/// sin perder la compatibilidad con documentos antiguos.
struct LearningSituationSessionActivityDraft: Identifiable, Codable {
    let id: UUID
    /// Stable identity from the planning document (for example W01-L-01). The UUID remains
    /// the SwiftUI identity for backwards compatibility, but joins between quick view and
    /// activity detail must use this key.
    var activityKey: String
    var activityType: String
    var plannedMinutes: Int?
    var timeLabel: String
    var phase: String
    var activity: String
    var purpose: String
    var organisation: String
    var setup: String
    var teacherActions: String
    var studentInstructions: String
    var studentActions: String
    var timingBreakdown: String
    var clilFocus: String
    var evidence: String
    var materials: String
    var adaptations: String
    var slowGroupPlan: String
    var fastGroupExtension: String

    init(
        activityKey: String = "",
        activityType: String = "core",
        plannedMinutes: Int? = nil,
        timeLabel: String,
        phase: String = "",
        activity: String,
        purpose: String = "",
        organisation: String = "",
        setup: String = "",
        teacherActions: String = "",
        studentInstructions: String = "",
        studentActions: String = "",
        timingBreakdown: String = "",
        clilFocus: String = "",
        evidence: String = "",
        materials: String = "",
        adaptations: String = "",
        slowGroupPlan: String = "",
        fastGroupExtension: String = ""
    ) {
        self.id = UUID()
        self.activityKey = activityKey
        self.activityType = activityType
        self.plannedMinutes = plannedMinutes
        self.timeLabel = timeLabel
        self.phase = phase
        self.activity = activity
        self.purpose = purpose
        self.organisation = organisation
        self.setup = setup
        self.teacherActions = teacherActions
        self.studentInstructions = studentInstructions
        self.studentActions = studentActions
        self.timingBreakdown = timingBreakdown
        self.clilFocus = clilFocus
        self.evidence = evidence
        self.materials = materials
        self.adaptations = adaptations
        self.slowGroupPlan = slowGroupPlan
        self.fastGroupExtension = fastGroupExtension
    }

    private enum CodingKeys: String, CodingKey {
        case id, activityKey, activityType, plannedMinutes, timeLabel, phase, activity,
             purpose, organisation, setup, teacherActions, studentInstructions, studentActions,
             timingBreakdown, clilFocus, evidence, materials, adaptations, slowGroupPlan,
             fastGroupExtension
        // session-plan-v2 keys. The legacy keys above remain accepted on decode.
        case v2Time = "time", v2Minutes = "minutes", v2Kind = "kind", v2Title = "title"
        case v2TeacherNarrative = "teacherNarrative", v2StudentOutput = "studentOutput"
        case v2Clil = "clil", v2Timing = "timing", v2IfSlow = "ifSlow", v2IfAhead = "ifAhead"
    }

    /// Encodes the stable, document-facing shape used by `session-plan-v2`. Keeping the
    /// Swift draft type means old callers and saved import previews do not need a migration.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let stableKey = activityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        try container.encode(stableKey.isEmpty ? id.uuidString : stableKey, forKey: .id)
        try container.encode(timeLabel, forKey: .v2Time)
        try container.encodeIfPresent(plannedMinutes, forKey: .v2Minutes)
        try container.encode(activityType, forKey: .v2Kind)
        try container.encode(activity, forKey: .v2Title)
        try container.encode(phase, forKey: .phase)
        try container.encode(purpose, forKey: .purpose)
        try container.encode(setup, forKey: .setup)
        try container.encode(teacherActions, forKey: .v2TeacherNarrative)
        try container.encode(studentInstructions, forKey: .studentInstructions)
        try container.encode(studentActions, forKey: .v2StudentOutput)
        try container.encode(organisation, forKey: .organisation)
        try container.encode(materials, forKey: .materials)
        try container.encode(evidence, forKey: .evidence)
        try container.encode(clilFocus, forKey: .v2Clil)
        try container.encode(timingBreakdown, forKey: .v2Timing)
        try container.encode(adaptations, forKey: .adaptations)
        try container.encode(slowGroupPlan, forKey: .v2IfSlow)
        try container.encode(fastGroupExtension, forKey: .v2IfAhead)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let encodedID = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        if let uuid = UUID(uuidString: encodedID) {
            self.id = uuid
            self.activityKey = try container.decodeIfPresent(String.self, forKey: .activityKey) ?? ""
        } else {
            self.id = UUID()
            self.activityKey = encodedID.isEmpty
                ? (try container.decodeIfPresent(String.self, forKey: .activityKey) ?? "")
                : encodedID
        }
        self.activityType = try container.decodeIfPresent(String.self, forKey: .v2Kind)
            ?? (try container.decodeIfPresent(String.self, forKey: .activityType)) ?? "core"
        self.plannedMinutes = try container.decodeIfPresent(Int.self, forKey: .v2Minutes)
            ?? (try container.decodeIfPresent(Int.self, forKey: .plannedMinutes))
        self.timeLabel = try container.decodeIfPresent(String.self, forKey: .v2Time)
            ?? (try container.decodeIfPresent(String.self, forKey: .timeLabel)) ?? ""
        self.phase = try container.decodeIfPresent(String.self, forKey: .phase) ?? ""
        self.activity = try container.decodeIfPresent(String.self, forKey: .v2Title)
            ?? (try container.decodeIfPresent(String.self, forKey: .activity)) ?? ""
        self.purpose = try container.decodeIfPresent(String.self, forKey: .purpose) ?? ""
        self.organisation = try container.decodeIfPresent(String.self, forKey: .organisation) ?? ""
        self.setup = try container.decodeIfPresent(String.self, forKey: .setup) ?? ""
        self.teacherActions = try container.decodeIfPresent(String.self, forKey: .v2TeacherNarrative)
            ?? (try container.decodeIfPresent(String.self, forKey: .teacherActions)) ?? ""
        self.studentInstructions = try container.decodeIfPresent(String.self, forKey: .studentInstructions) ?? ""
        self.studentActions = try container.decodeIfPresent(String.self, forKey: .v2StudentOutput)
            ?? (try container.decodeIfPresent(String.self, forKey: .studentActions)) ?? ""
        self.timingBreakdown = try container.decodeIfPresent(String.self, forKey: .v2Timing)
            ?? (try container.decodeIfPresent(String.self, forKey: .timingBreakdown)) ?? ""
        self.clilFocus = try container.decodeIfPresent(String.self, forKey: .v2Clil)
            ?? (try container.decodeIfPresent(String.self, forKey: .clilFocus)) ?? ""
        self.evidence = try container.decodeIfPresent(String.self, forKey: .evidence) ?? ""
        self.materials = try container.decodeIfPresent(String.self, forKey: .materials) ?? ""
        self.adaptations = try container.decodeIfPresent(String.self, forKey: .adaptations) ?? ""
        self.slowGroupPlan = try container.decodeIfPresent(String.self, forKey: .v2IfSlow)
            ?? (try container.decodeIfPresent(String.self, forKey: .slowGroupPlan)) ?? ""
        self.fastGroupExtension = try container.decodeIfPresent(String.self, forKey: .v2IfAhead)
            ?? (try container.decodeIfPresent(String.self, forKey: .fastGroupExtension)) ?? ""
    }
}

/// Payload versionado que vive en `developmentJson`. La forma antigua era un
/// array de secciones, por lo que el lector ofrece fallback para no romper planes
/// ya guardados.
struct LearningSituationSessionDevelopmentPayload: Codable {
    var schema: String
    var schemaVersion: Int
    var organisation: String
    var coreKnowledge: String
    var assessment: String
    var sections: [LearningSituationSessionSectionDraft]
    var activities: [LearningSituationSessionActivityDraft]
    var guidingQuestions: [String]
    var closure: String

    init(
        schema: String = "session-plan-v2",
        schemaVersion: Int = 2,
        organisation: String = "",
        coreKnowledge: String = "",
        assessment: String = "",
        sections: [LearningSituationSessionSectionDraft],
        activities: [LearningSituationSessionActivityDraft],
        guidingQuestions: [String] = [],
        closure: String = ""
    ) {
        self.schema = schema
        self.schemaVersion = schemaVersion
        self.organisation = organisation
        self.coreKnowledge = coreKnowledge
        self.assessment = assessment
        self.sections = sections
        self.activities = activities
        self.guidingQuestions = guidingQuestions
        self.closure = closure
    }

    private enum CodingKeys: String, CodingKey {
        case schema, schemaVersion, organisation, coreKnowledge, assessment
        case sections, activities, guidingQuestions, closure
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decodeIfPresent(String.self, forKey: .schema) ?? "legacy"
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        organisation = try container.decodeIfPresent(String.self, forKey: .organisation) ?? ""
        coreKnowledge = try container.decodeIfPresent(String.self, forKey: .coreKnowledge) ?? ""
        assessment = try container.decodeIfPresent(String.self, forKey: .assessment) ?? ""
        sections = try container.decodeIfPresent([LearningSituationSessionSectionDraft].self, forKey: .sections) ?? []
        activities = try container.decodeIfPresent([LearningSituationSessionActivityDraft].self, forKey: .activities) ?? []
        guidingQuestions = try container.decodeIfPresent([String].self, forKey: .guidingQuestions) ?? []
        closure = try container.decodeIfPresent(String.self, forKey: .closure) ?? ""
    }

    static func decode(from json: String) -> Self? {
        guard let data = json.data(using: .utf8) else { return nil }
        if let payload = try? JSONDecoder().decode(Self.self, from: data),
           payload.schema == "session-plan-v2" || payload.schemaVersion >= 2 ||
           !payload.sections.isEmpty || !payload.activities.isEmpty {
            return payload
        }
        guard let sections = try? JSONDecoder().decode([LearningSituationSessionSectionDraft].self, from: data) else {
            return nil
        }
        return Self(schema: "legacy", schemaVersion: 1, sections: sections, activities: [])
    }
}

enum LearningSituationWeeklyBlockRole: String, Codable, CaseIterable, Hashable {
    case long
    case short
}

enum LearningSituationWeeklySequenceRoute: String, Codable, CaseIterable, Hashable {
    case shortFirst
    case longFirst

    var displayName: String {
        switch self {
        case .shortFirst: return "SHORT primero"
        case .longFirst: return "LONG primero"
        }
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
    var activities: [LearningSituationSessionActivityDraft]
    var adaptations: [String]
    var organisation: String
    var coreKnowledge: String
    var assessment: String
    var guidingQuestions: [String]
    var closure: String
    var cycleIndex: Int?
    var weekKey: String?
    var blockRole: LearningSituationWeeklyBlockRole?
    var sequenceFormat: String?

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
        activities: [LearningSituationSessionActivityDraft] = [],
        adaptations: [String],
        organisation: String = "",
        coreKnowledge: String = "",
        assessment: String = "",
        guidingQuestions: [String] = [],
        closure: String = "",
        cycleIndex: Int? = nil,
        weekKey: String? = nil,
        blockRole: LearningSituationWeeklyBlockRole? = nil,
        sequenceFormat: String? = nil
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
        self.activities = activities
        self.adaptations = adaptations
        self.organisation = organisation
        self.coreKnowledge = coreKnowledge
        self.assessment = assessment
        self.guidingQuestions = guidingQuestions
        self.closure = closure
        self.cycleIndex = cycleIndex
        self.weekKey = weekKey
        self.blockRole = blockRole
        self.sequenceFormat = sequenceFormat
    }

    private enum CodingKeys: String, CodingKey {
        case id, sessionNumber, sourceLabel, title, sessionType, effectiveMinutes,
             objective, criteria, material, development, activities, adaptations,
             organisation, coreKnowledge, assessment, guidingQuestions, closure,
             cycleIndex, weekKey, blockRole, sequenceFormat
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        sessionNumber = try container.decode(Int.self, forKey: .sessionNumber)
        sourceLabel = try container.decode(String.self, forKey: .sourceLabel)
        title = try container.decode(String.self, forKey: .title)
        sessionType = try container.decode(String.self, forKey: .sessionType)
        effectiveMinutes = try container.decode(Int.self, forKey: .effectiveMinutes)
        objective = try container.decode(String.self, forKey: .objective)
        criteria = try container.decode([String].self, forKey: .criteria)
        material = try container.decode(String.self, forKey: .material)
        development = try container.decode([LearningSituationSessionSectionDraft].self, forKey: .development)
        activities = try container.decodeIfPresent([LearningSituationSessionActivityDraft].self, forKey: .activities) ?? []
        adaptations = try container.decode([String].self, forKey: .adaptations)
        organisation = try container.decodeIfPresent(String.self, forKey: .organisation) ?? ""
        coreKnowledge = try container.decodeIfPresent(String.self, forKey: .coreKnowledge) ?? ""
        assessment = try container.decodeIfPresent(String.self, forKey: .assessment) ?? ""
        guidingQuestions = try container.decodeIfPresent([String].self, forKey: .guidingQuestions) ?? []
        closure = try container.decodeIfPresent(String.self, forKey: .closure) ?? ""
        cycleIndex = try container.decodeIfPresent(Int.self, forKey: .cycleIndex)
        weekKey = try container.decodeIfPresent(String.self, forKey: .weekKey)
        blockRole = try container.decodeIfPresent(LearningSituationWeeklyBlockRole.self, forKey: .blockRole)
        sequenceFormat = try container.decodeIfPresent(String.self, forKey: .sequenceFormat)
    }

    var developmentSummary: String {
        let sectionSummary = development.map { section in
            ([section.title] + section.lines).joined(separator: "\n")
        }.joined(separator: "\n\n")
        let activitySummary = activities.map { activity in
            [
                [activity.timeLabel, activity.phase].filter { !$0.isEmpty }.joined(separator: " · "),
                activity.activity,
                activity.teacherActions.isEmpty ? nil : "Teacher: \(activity.teacherActions)",
                activity.studentActions.isEmpty ? nil : "Students: \(activity.studentActions)",
                activity.clilFocus.isEmpty ? nil : "CLIL: \(activity.clilFocus)",
                activity.evidence.isEmpty ? nil : "Evidence: \(activity.evidence)"
            ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        }.joined(separator: "\n\n")
        return [sectionSummary, activitySummary].filter { !$0.isEmpty }.joined(separator: "\n\n")
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
        // El lector distingue título real de Word (Heading 1/2/3) de párrafo normal y de tabla,
        // en vez de aplanar todo el documento a una única lista de "párrafos" (como hacía el
        // parser SAX anterior, que también convertía cada celda de tabla en un párrafo suelto y
        // volcaba el resto del documento dentro de la sección anterior cuando esta no encontraba
        // el sinónimo exacto de encabezado que esperaba).
        let blocks = try readStyledBlocks(from: data)
        let paragraphs: [String] = blocks.compactMap {
            switch $0 {
            case .heading(let text), .paragraph(let text): return text
            case .table: return nil
            }
        }.filter { !$0.isEmpty }
        guard !paragraphs.isEmpty else { throw LearningSituationImportError.missingDocumentBody }
        // Texto normalizado de los párrafos que SÍ son un título real de Word: permite a
        // `sectionText` parar en el siguiente encabezado del documento aunque no use ninguno de
        // los sinónimos concretos que se le pasan como `untilHeadings`.
        let headingTexts: Set<String> = Set(blocks.compactMap {
            if case .heading(let text) = $0 { return normalized(text) } else { return nil }
        })
        // C1/C3: algunas SA (p.ej. SA 3, SA 5) ponen la ficha técnica y los criterios de
        // evaluación en tablas ("Campo | Dato", "Criterio | Enunciado oficial | Rol en la SA")
        // en vez de párrafos "Etiqueta: valor"; se emparejan fila a fila en `metadataValueFromTables`
        // y `criterionDraftsFromTables`.
        let tables: [[[String]]] = blocks.compactMap {
            if case .table(let rows) = $0 { return rows } else { return nil }
        }
        // Tablas que no son la de criterios (esa ya se muestra estructurada) se conservan como
        // tabla, con el título del encabezado que las precede, para poder pintarlas como tabla en
        // vez de aplanarlas en líneas sueltas (p.ej. la secuenciación de sesiones o una tabla de
        // adaptaciones "Barrera | Adaptación").
        var documentTables: [LearningSituationTableDraft] = []
        var lastHeading = ""
        for block in blocks {
            switch block {
            case .heading(let text):
                lastHeading = text
            case .table(let rows):
                guard let header = rows.first, rows.count > 1 else { continue }
                let normalizedHeader = normalized(header.first ?? "")
                guard !normalizedHeader.contains("criterio"), !normalizedHeader.contains("criteri") else { continue }
                documentTables.append(LearningSituationTableDraft(
                    title: lastHeading.isEmpty ? "Tabla del documento" : lastHeading,
                    header: header,
                    rows: Array(rows.dropFirst())
                ))
            case .paragraph:
                continue
            }
        }

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
            justification: sectionText(afterHeadings: ["JUSTIFICACIÓN Y RETO", "CLIL justification and driving question", "justification", "Justificación"], untilHeadings: ["Pregunta Motriz", "Driving question", "CLIL 4Cs", "4Cs"], paragraphs: paragraphs, headingTexts: headingTexts).first ?? "",
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
            knowledge: sectionText(afterHeadings: ["Saberes Básicos Implicados", "Saberes Básicos", "Curricular alignment", "Specific competencies"], untilHeadings: ["METODOLOGÍA", "Methodology"], paragraphs: paragraphs, headingTexts: headingTexts),
            methodology: sectionText(afterHeadings: ["METODOLOGÍA Y ESTRATEGIAS ACTIVAS", "Fundamentación metodológica", "Methodology and scaffolding", "Methodology"], untilHeadings: ["ATENCIÓN A LA DIVERSIDAD", "Inclusion and UDL", "Inclusion"], paragraphs: paragraphs, headingTexts: headingTexts),
            inclusionMeasures: inclusionMeasures(from: paragraphs),
            evaluationItems: evaluationItems,
            warnings: warnings,
            documentTables: documentTables,
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

    private func readStyledBlocks(from data: Data) throws -> [ImportBlock] {
        let archive = try Archive(data: data, accessMode: .read, pathEncoding: nil)
        guard let entry = archive["word/document.xml"] else {
            throw LearningSituationImportError.unreadableDocument
        }
        var xmlData = Data()
        _ = try archive.extract(entry) { xmlData.append($0) }
        let reader = WordStyledParagraphReader()
        guard reader.parse(data: xmlData) else { throw LearningSituationImportError.unreadableDocument }
        return reader.blocks
    }

    private func cleanBulletPrefix(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasPrefix("•") || result.hasPrefix("-") || result.hasPrefix("*") || result.hasPrefix("◦") || result.hasPrefix("▪") || result.hasPrefix("#") {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    /// Encabezado de sección "genérico": un título real de Word (Heading 1/2/3, detectado por
    /// `headingTexts` a partir del estilo `w:pStyle` del párrafo) o, como red de seguridad para
    /// documentos sin estilos de título, una numeración de sección de primer nivel ("5. Producto
    /// final...") o un símbolo Markdown literal ("#"). Permite a `sectionText` parar en el
    /// siguiente encabezado del documento aunque no use ninguno de los sinónimos concretos que se
    /// le pasan como `untilHeadings`: sin este corte, una sección seguía leyendo hasta el final
    /// del documento y volcaba el resto de secciones (metodología, medidas DUA, tabla de
    /// secuenciación) dentro del bloque anterior.
    private func isGenericSectionHeading(_ paragraph: String, headingTexts: Set<String>) -> Bool {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if headingTexts.contains(normalized(trimmed)) { return true }
        if trimmed.hasPrefix("#") { return true }
        if trimmed.range(of: #"^\d+\.\s+[A-ZÁÉÍÓÚÑ¿]"#, options: .regularExpression) != nil { return true }
        return false
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

    private func sectionText(afterHeadings startHeadings: [String], untilHeadings endHeadings: [String], paragraphs: [String], headingTexts: Set<String>) -> [String] {
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
            return !isGenericSectionHeading(text, headingTexts: headingTexts)
        })
        .map(cleanBulletPrefix)
        .filter { !$0.isEmpty && !$0.localizedCaseInsensitiveContains("descriptores operativos") }
    }

    private func criterionDrafts(from paragraphs: [String]) -> [LearningSituationCriterionDraft] {
        var results: [LearningSituationCriterionDraft] = []
        for (index, paragraph) in paragraphs.enumerated() {
            let cleanPara = cleanBulletPrefix(paragraph)
            // C4b: "CE 2.1. ..." (SA Floorball y otras) usa solo la sigla, sin la palabra
            // "criterio"; se acepta también cuando trae un código de criterio y no es una
            // ponderación de evaluación (esas siempre llevan "%", como en "CE 2.2 Rúbrica...
            // - 40%: ...", que ya se recoge en `evaluationItems`).
            // El código debe abrir el párrafo ("CE 2.1. Participar..."): exigir solo un
            // decimal en cualquier parte del texto capturaba referencias incidentales como
            // "apartado 5.1".
            let hasBareCriterionCode = !cleanPara.contains("%") &&
                cleanPara.range(of: #"^CE\s*[0-9]+\.[0-9]+"#, options: [.regularExpression, .caseInsensitive]) != nil
            guard cleanPara.localizedCaseInsensitiveContains("criterio") || cleanPara.localizedCaseInsensitiveContains("criterion") || hasBareCriterionCode else { continue }
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
    let activities: [LearningSituationSessionActivityDraft]
    let adaptations: [String]
    let organisation: String
    let coreKnowledge: String
    let assessment: String
    let guidingQuestions: [String]
    let closure: String
}

struct LearningSituationSessionSequenceDocumentImportService {
    /// B2/B3: el número de sesión debe ir seguido de un separador explícito (".", "-", "—",
    /// "–", ":", opcionalmente detrás de una anotación entre paréntesis como "(NEW)") o no
    /// llevar nada más. Sin este requisito, un párrafo de prosa como "Session 3 finishes the
    /// panel and starts planning the final event." (00d - Cierre de Curso) matcheaba igual que
    /// un encabezado real y generaba una sesión 3 fantasma duplicada.
    private static let headerPattern = try! NSRegularExpression(
        pattern: #"^(?:SESSION|SESSIONS|SESI|SESSI)(?:ÓN|ON|ONES|ONS)?\s+([0-9]+)(?:\s+(?:y|and|\&)\s+([0-9]+))?(?:\s*\([^)]*\))?(?:\s*[.:\-–—]\s*(.*))?$"#,
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

        // Formato C (ficha + QUICK VIEW + ACTIVITY DETAILS) must win over the generic
        // paragraph/table parser. Its detail paragraphs are not session development and
        // flattening them would duplicate every activity in the legacy timeline.
        if isFormatC(blocks) {
            return parseFormatC(blocks: blocks, data: data, url: url)
        }

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
                    activities: parsed.activities,
                    adaptations: parsed.adaptations,
                    organisation: parsed.organisation,
                    coreKnowledge: parsed.coreKnowledge,
                    assessment: parsed.assessment,
                    guidingQuestions: parsed.guidingQuestions,
                    closure: parsed.closure
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

    // MARK: - C: ficha + QUICK VIEW + ACTIVITY DETAILS

    private func isFormatC(_ blocks: [WordDocumentBlock]) -> Bool {
        let hasQuickView = blocks.contains { block in
            guard case .paragraph(let value) = block else { return false }
            let text = normalized(value)
            return text == "quick view" || text == "vista rapida" || text.hasPrefix("quick view ")
        }
        let hasActivityTable = blocks.contains { block in
            guard case .table(let rows) = block, let header = rows.first else { return false }
            return header.contains { value in
                let text = normalized(value)
                return text.contains("activity id") || text.contains("id actividad") || text.contains("activity key")
            }
        }
        let hasSession = blocks.contains { block in
            guard case .paragraph(let value) = block else { return false }
            return Self.headerPattern.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
        }
        return hasQuickView && hasActivityTable && hasSession
    }

    private func parseFormatC(
        blocks: [WordDocumentBlock],
        data: Data,
        url: URL
    ) -> LearningSituationSessionSequenceImportDraft {
        struct Header {
            let index: Int
            let value: String
            let number: Int
        }

        var headers: [Header] = []
        for (index, block) in blocks.enumerated() {
            guard case .paragraph(let value) = block,
                  let match = Self.headerPattern.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                  let range = Range(match.range(at: 1), in: value),
                  let number = Int(value[range]) else { continue }
            headers.append(Header(index: index, value: value, number: number))
        }

        var plans: [LearningSituationSessionPlanDraft] = []
        var warnings: [String] = []
        var seenSessionNumbers = Set<Int>()
        for (position, header) in headers.enumerated() {
            guard seenSessionNumbers.insert(header.number).inserted else {
                warnings.append("Formato C: la sesión \(header.number) aparece repetida; se conserva la primera ficha y se omite la duplicada.")
                continue
            }
            let end = position + 1 < headers.count ? headers[position + 1].index : blocks.count
            let parsed = parseFormatCSession(header: header.value, body: Array(blocks[(header.index + 1)..<end]), warnings: &warnings)
            plans.append(LearningSituationSessionPlanDraft(
                sessionNumber: header.number,
                sourceLabel: header.value,
                title: parsed.title,
                sessionType: parsed.sessionType,
                effectiveMinutes: parsed.effectiveMinutes,
                objective: parsed.objective,
                criteria: parsed.criteria,
                material: parsed.material,
                development: parsed.development,
                activities: parsed.activities,
                adaptations: parsed.adaptations,
                organisation: parsed.organisation,
                coreKnowledge: parsed.coreKnowledge,
                assessment: parsed.assessment,
                guidingQuestions: parsed.guidingQuestions,
                closure: parsed.closure
            ))
        }

        plans.sort { $0.sessionNumber < $1.sessionNumber }
        if plans.isEmpty { warnings.append("Formato C detectado pero no se reconocieron sesiones.") }
        let numbers = plans.map(\.sessionNumber)
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
        return LearningSituationSessionSequenceImportDraft(
            plans: plans,
            warnings: warnings,
            sourceURL: url,
            sourceFileName: url.lastPathComponent,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            sizeBytes: Int64(data.count)
        )
    }

    private func parseFormatCSession(
        header: String,
        body: [WordDocumentBlock],
        warnings: inout [String]
    ) -> ParsedSessionPlan {
        var title = cleanRestTitle(sessionTypeAndTitle(from: header).title)
        var sessionType = sessionTypeAndTitle(from: header).type
        let minutes = integerMatch(in: header, pattern: #"([0-9]+)\s*(?:minutos|minutes|min|')"#) ?? 0
        var objective = ""
        var criteriaRaw = ""
        var material = ""
        var organisation = ""
        var coreKnowledge = ""
        var assessment = ""
        var activities: [LearningSituationSessionActivityDraft] = []
        var details: [String: [String: String]] = [:]
        var detailIDs: [String] = []
        var seenDetailIDs = Set<String>()
        var guidingQuestions: [String] = []
        var closureLines: [String] = []
        var section: String?
        var detailKey: String?
        var discardingDuplicateDetail = false
        var pendingFichaField: String?
        var pendingDetailField: String?
        var seenIDs = Set<String>()

        func field(_ raw: String) -> String? {
            switch normalized(raw).trimmingCharacters(in: CharacterSet(charactersIn: " :\t")) {
            case "titulo", "title": return "title"
            case "objetivo", "objetivo especifico", "objetivo principal", "objective", "specific objective", "main objective": return "objective"
            case "criterio", "criterios", "criterios trabajados", "criterios de evaluacion", "criteria", "criteria worked", "evaluation criteria addressed": return "criteria"
            case "material", "materiales", "materials", "materials needed", "required materials": return "material"
            case "organizacion del grupo", "organización del grupo", "group organisation", "student grouping": return "organisation"
            case "saberes basicos", "saberes basicos trabajados", "core knowledge addressed", "basic knowledge addressed": return "coreKnowledge"
            case "evaluacion", "evaluation", "assessment", "evidencia", "evidence": return "assessment"
            default: return nil
            }
        }

        func detailField(_ raw: String) -> String? {
            switch normalized(raw).trimmingCharacters(in: CharacterSet(charactersIn: " :\t")) {
            case "purpose", "proposito", "proposito de la actividad": return "purpose"
            case "organisation", "organization", "organizacion", "grouping": return "organisation"
            case "set-up", "setup", "preparation", "preparacion", "montaje": return "setup"
            case "teacher narrative", "teacher instructions", "teacher actions", "teacher script", "what the teacher says", "instrucciones del profesor", "acciones del docente", "narrativa del profesor": return "teacherActions"
            case "student instructions", "instructions for students", "learner narrative", "instrucciones para el alumnado", "consignas": return "studentInstructions"
            case "student output", "what students do", "student actions", "student narrative", "acciones del alumnado", "resultado del alumnado": return "studentActions"
            case "timing", "timing breakdown", "timing and transition", "transition cue", "transition", "desglose temporal", "transicion", "temporizacion y transiciones": return "timingBreakdown"
            case "clil", "clil focus", "clil language", "enfoque clil": return "clilFocus"
            case "materials", "materiales": return "materials"
            case "evidence", "evidencia": return "evidence"
            case "adaptations", "adaptaciones": return "adaptations"
            case "if the group is slow", "slow group plan", "si el grupo va lento": return "slowGroupPlan"
            case "if the group is ahead", "fast group extension", "si el grupo termina antes": return "fastGroupExtension"
            default: return nil
            }
        }

        func store(_ key: String, _ name: String, _ value: String) {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            // A repeated detail card is a warning condition, not permission to let the
            // later narrative silently replace the first one.
            if details[key]?[name] == nil {
                details[key, default: [:]][name] = value
            }
        }

        func assignFicha(_ name: String, _ value: String) {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            switch name {
            case "title": if title.isEmpty { title = value }
            case "objective": if objective.isEmpty { objective = value }
            case "criteria": criteriaRaw = criteriaRaw.isEmpty ? value : "\(criteriaRaw), \(value)"
            case "material": if material.isEmpty { material = value }
            case "organisation": if organisation.isEmpty { organisation = value }
            case "coreKnowledge": if coreKnowledge.isEmpty { coreKnowledge = value }
            case "assessment": if assessment.isEmpty { assessment = value }
            default: break
            }
        }

        for block in body {
            switch block {
            case .paragraph(let raw):
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let norm = normalized(text)
                if norm == "quick view" || norm == "vista rapida" { section = "quick"; detailKey = nil; pendingFichaField = nil; pendingDetailField = nil; discardingDuplicateDetail = false; continue }
                if norm == "activity details" || norm == "detalle de actividades" { section = "details"; detailKey = nil; pendingFichaField = nil; pendingDetailField = nil; discardingDuplicateDetail = false; continue }
                if norm == "guiding questions" || norm == "preguntas guia" || norm == "preguntas guía" { section = "guiding"; detailKey = nil; pendingFichaField = nil; pendingDetailField = nil; discardingDuplicateDetail = false; continue }
                if norm == "guiding questions and closure" || norm == "preguntas guia y cierre" || norm == "preguntas guía y cierre" { section = "guidingClosure"; detailKey = nil; pendingFichaField = nil; pendingDetailField = nil; discardingDuplicateDetail = false; continue }
                if norm == "closure" || norm == "cierre" { section = "closure"; detailKey = nil; pendingFichaField = nil; pendingDetailField = nil; discardingDuplicateDetail = false; continue }
                if let regex = try? NSRegularExpression(pattern: #"^ACTIVITY\s+([A-Z0-9][A-Z0-9_-]*)(?:\s*[—–-].*)?$"#, options: .caseInsensitive),
                   let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   let keyRange = Range(match.range(at: 1), in: text) {
                    let candidateKey = String(text[keyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if seenDetailIDs.insert(candidateKey).inserted {
                        detailKey = candidateKey
                        detailIDs.append(candidateKey)
                        discardingDuplicateDetail = false
                    } else {
                        detailKey = nil
                        discardingDuplicateDetail = true
                        warnings.append("\(header): Activity ID duplicado en ACTIVITY DETAILS (\(candidateKey)); se conserva la primera ficha.")
                    }
                    pendingFichaField = nil
                    pendingDetailField = nil
                    section = "details"
                    continue
                }
                if discardingDuplicateDetail { continue }
                if section == "guiding" {
                    let value = text.replacingOccurrences(of: #"^[-•]\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { guidingQuestions.append(value) }
                    continue
                }
                if section == "guidingClosure" {
                    let value = text.replacingOccurrences(of: #"^[-•]\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
                    if guidingQuestions.isEmpty { guidingQuestions.append(value) } else { closureLines.append(value) }
                    continue
                }
                if section == "closure" { closureLines.append(text); continue }

                // C documents sometimes put a ficha/detail label on its own line and the
                // value in the following paragraph. Keep that state explicitly, matching
                // the tolerant A/B parser instead of treating the label as prose.
                if let detailName = pendingDetailField, let detailKey {
                    store(detailKey, detailName, text)
                    pendingDetailField = nil
                    continue
                }
                if let fichaName = pendingFichaField {
                    assignFicha(fichaName, text)
                    pendingFichaField = nil
                    continue
                }
                if let separator = text.firstIndex(of: ":") {
                    let label = String(text[..<separator])
                    let value = String(text[text.index(after: separator)...])
                    if let detailKey, let detail = detailField(label) {
                        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            pendingDetailField = detail
                        } else {
                            store(detailKey, detail, value)
                        }
                        continue
                    }
                    if let ficha = field(label) {
                        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            pendingFichaField = ficha
                        } else {
                            assignFicha(ficha, value)
                        }
                        continue
                    }
                }
                if detailKey != nil, let detail = detailField(text) {
                    section = "details"
                    pendingDetailField = detail
                    continue
                }
                if let ficha = field(text) {
                    pendingFichaField = ficha
                    continue
                }
            case .table(let rawRows):
                if discardingDuplicateDetail { continue }
                let rows = rawRows.map { $0.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }.filter { $0.contains { !$0.isEmpty } }
                guard !rows.isEmpty else { continue }
                if isTimeTable(rows) && section == "quick" {
                    for activity in timeTableActivities(rows) {
                        let key = activity.activityKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !key.isEmpty else { continue }
                        if seenIDs.insert(key).inserted { activities.append(activity) }
                        else { warnings.append("\(header): Activity ID duplicado \(key); se conserva una sola fila.") }
                    }
                    continue
                }
                if let first = rows.first, first.count >= 2 {
                    let firstRowIsLabel = (detailKey != nil && detailField(first[0]) != nil) ||
                        (detailKey == nil && field(first[0]) != nil)
                    let dataRows = firstRowIsLabel ? rows : Array(rows.dropFirst())
                    for row in dataRows where row.count >= 2 {
                        if let detailKey, let detail = detailField(row[0]) { store(detailKey, detail, row.dropFirst().joined(separator: " ")); continue }
                        if let ficha = field(row[0]) { assignFicha(ficha, row.dropFirst().joined(separator: " ")) }
                    }
                }
            }
        }

        let mergedActivities = activities.map { activity -> LearningSituationSessionActivityDraft in
            guard let values = details[activity.activityKey] else { return activity }
            return LearningSituationSessionActivityDraft(
                activityKey: activity.activityKey, activityType: activity.activityType,
                plannedMinutes: activity.plannedMinutes, timeLabel: activity.timeLabel,
                phase: activity.phase, activity: activity.activity, purpose: values["purpose"] ?? activity.purpose,
                organisation: values["organisation"] ?? activity.organisation, setup: values["setup"] ?? activity.setup,
                teacherActions: values["teacherActions"] ?? activity.teacherActions,
                studentInstructions: values["studentInstructions"] ?? activity.studentInstructions,
                studentActions: values["studentActions"] ?? activity.studentActions,
                timingBreakdown: values["timingBreakdown"] ?? activity.timingBreakdown,
                clilFocus: values["clilFocus"] ?? activity.clilFocus, evidence: values["evidence"] ?? activity.evidence,
                materials: values["materials"] ?? activity.materials, adaptations: values["adaptations"] ?? activity.adaptations,
                slowGroupPlan: values["slowGroupPlan"] ?? activity.slowGroupPlan,
                fastGroupExtension: values["fastGroupExtension"] ?? activity.fastGroupExtension
            )
        }
        let quickIDs = Set(activities.map(\.activityKey))
        for id in detailIDs where !quickIDs.contains(id) {
            warnings.append("\(header): Activity ID \(id) aparece en ACTIVITY DETAILS pero no en QUICK VIEW; se conserva solo la fila QUICK VIEW.")
        }
        for id in quickIDs where !detailIDs.contains(id) {
            warnings.append("\(header): Activity ID \(id) no tiene ficha en ACTIVITY DETAILS; se conserva la fila QUICK VIEW.")
        }
        let expectedBlock = normalized(sessionType).contains("simple") || normalized(sessionType).contains("short") ? "-S-" : "-L-"
        for activity in mergedActivities where !activity.activityKey.contains(expectedBlock) {
            warnings.append("\(header): Activity ID \(activity.activityKey) no corresponde al bloque \(sessionType).")
        }
        sessionType = normalized(sessionType).contains("simple") || normalized(sessionType).contains("short") ? "Simple" : "Doble"
        let sections = mergedActivities.isEmpty ? [] : [LearningSituationSessionSectionDraft(title: "QUICK VIEW", lines: mergedActivities.map { [$0.timeLabel, $0.activity].filter { !$0.isEmpty }.joined(separator: " · ") })]
        return ParsedSessionPlan(
            title: title, sessionType: sessionType, effectiveMinutes: minutes, objective: objective,
            criteria: criterionCodes(in: criteriaRaw), material: material, development: sections,
            activities: mergedActivities, adaptations: [], organisation: organisation,
            coreKnowledge: coreKnowledge, assessment: assessment, guidingQuestions: guidingQuestions,
            closure: closureLines.joined(separator: "\n")
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
        let longActivities: [LearningSituationSessionActivityDraft]
        let longMinutes: Int?
        let shortSections: [LearningSituationSessionSectionDraft]
        let shortActivities: [LearningSituationSessionActivityDraft]
        let shortMinutes: Int?
        let sharedSections: [LearningSituationSessionSectionDraft]
        let sharedActivities: [LearningSituationSessionActivityDraft]
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
                activities: week.longActivities + week.sharedActivities,
                adaptations: week.adaptations,
                cycleIndex: week.number,
                weekKey: "week-\(week.number)",
                blockRole: .long,
                sequenceFormat: "weekly-long-short-v1"
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
                activities: week.shortActivities + week.sharedActivities,
                adaptations: week.adaptations,
                cycleIndex: week.number,
                weekKey: "week-\(week.number)",
                blockRole: .short,
                sequenceFormat: "weekly-long-short-v1"
            ))
        }

        let activityIDPattern = try! NSRegularExpression(pattern: #"^W[0-9]{2}-[LS]-[0-9]{2}$"#)
        for plan in plans {
            let expectedBlock = plan.blockRole == .short ? "S" : "L"
            var seen: Set<String> = []
            for activity in plan.activities {
                let key = activity.activityKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if key.isEmpty {
                    warnings.append("\(plan.sourceLabel): actividad sin Activity ID.")
                    continue
                }
                if seen.contains(key) {
                    warnings.append("\(plan.sourceLabel): Activity ID duplicado \(key).")
                }
                seen.insert(key)
                let range = NSRange(key.startIndex..., in: key)
                if activityIDPattern.firstMatch(in: key, range: range) == nil || !key.contains("-\(expectedBlock)-") {
                    warnings.append("\(plan.sourceLabel): Activity ID no válido para este bloque (\(key)).")
                }
            }
        }

        // El documento es el mismo para los dos grupos: lo que cambia es el orden dentro de la
        // semana. La pantalla de programación usará la etiqueta del bloque para ubicar el largo
        // sobre dos franjas consecutivas y el corto sobre una franja simple.
        warnings.append("Formato semanal: cada semana se importa como dos sesiones (bloque largo y bloque corto). La previsualización ubicará el bloque largo en dos franjas consecutivas y el corto en una franja simple; si el horario no permite distinguirlas, mostrará un aviso para revisión docente.")
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
        var longActivities: [LearningSituationSessionActivityDraft] = []
        var shortSections: [LearningSituationSessionSectionDraft] = []
        var shortActivities: [LearningSituationSessionActivityDraft] = []
        var sharedSections: [LearningSituationSessionSectionDraft] = []
        var sharedActivities: [LearningSituationSessionActivityDraft] = []
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
        var activityDetailKey: String?
        var activityDetails: [String: [String: String]] = [:]

        func detailField(_ raw: String) -> String? {
            let value = normalized(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            switch value {
            case "purpose", "proposito", "proposito de la actividad": return "purpose"
            case "organisation", "organization", "organizacion", "grouping": return "organisation"
            case "set-up", "setup", "preparation", "preparacion": return "setup"
            case "teacher instructions", "teacher actions", "teacher narrative", "teacher script", "instrucciones del profesor", "acciones del docente", "narrativa del profesor": return "teacherActions"
            case "instructions for students", "student instructions", "student narrative", "learner narrative", "instrucciones para el alumnado", "narrativa del alumnado": return "studentInstructions"
            case "student actions", "student output", "what students do", "acciones del alumnado": return "studentActions"
            case "timing breakdown", "timing", "transition cue", "transition", "desglose temporal", "transicion": return "timingBreakdown"
            case "clil focus", "clil language", "enfoque clil": return "clilFocus"
            case "materials", "materiales": return "materials"
            case "evidence", "evidencia": return "evidence"
            case "adaptations", "adaptaciones": return "adaptations"
            case "if the group is slow", "slow group plan", "si el grupo va lento": return "slowGroupPlan"
            case "if the group is ahead", "fast group extension", "si el grupo termina antes": return "fastGroupExtension"
            default: return nil
            }
        }

        func storeDetail(_ key: String, field: String, value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            activityDetails[key, default: [:]][field] = trimmed
        }

        func mergeDetails(into activity: LearningSituationSessionActivityDraft) -> LearningSituationSessionActivityDraft {
            guard let values = activityDetails[activity.activityKey] else { return activity }
            return LearningSituationSessionActivityDraft(
                activityKey: activity.activityKey,
                activityType: activity.activityType,
                plannedMinutes: activity.plannedMinutes,
                timeLabel: activity.timeLabel,
                phase: activity.phase,
                activity: activity.activity,
                purpose: values["purpose"] ?? activity.purpose,
                organisation: values["organisation"] ?? activity.organisation,
                setup: values["setup"] ?? activity.setup,
                teacherActions: values["teacherActions"] ?? activity.teacherActions,
                studentInstructions: values["studentInstructions"] ?? activity.studentInstructions,
                studentActions: values["studentActions"] ?? activity.studentActions,
                timingBreakdown: values["timingBreakdown"] ?? activity.timingBreakdown,
                clilFocus: values["clilFocus"] ?? activity.clilFocus,
                evidence: values["evidence"] ?? activity.evidence,
                materials: values["materials"] ?? activity.materials,
                adaptations: values["adaptations"] ?? activity.adaptations,
                slowGroupPlan: values["slowGroupPlan"] ?? activity.slowGroupPlan,
                fastGroupExtension: values["fastGroupExtension"] ?? activity.fastGroupExtension
            )
        }

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
                if let blockHeading = weekBlockHeading(text) {
                    activityDetailKey = nil
                    flushSection()
                    reachedFinalSections = false
                    target = blockHeading.kind
                    switch blockHeading.kind {
                    case .long: longMinutes = blockHeading.minutes
                    case .short: shortMinutes = blockHeading.minutes
                    }
                    continue
                }
                if normalized(text) == "activity details" || normalized(text) == "detalle de actividades" {
                    activityDetailKey = nil
                    continue
                }
                if let match = text.range(
                    of: #"^ACTIVITY\s+[A-Z0-9][A-Z0-9_-]*(?:(?:\s+[-–—]\s*|\s*:\s*).*)?$"#,
                    options: [.regularExpression, .caseInsensitive]
                ) {
                    let heading = String(text[match])
                    activityDetailKey = heading.replacingOccurrences(
                        of: #"^ACTIVITY\s+"#, with: "", options: [.regularExpression, .caseInsensitive]
                    ).replacingOccurrences(
                        of: #"(?:\s+[-–—]\s*|\s*:\s*).*$"#, with: "", options: .regularExpression
                    ).trimmingCharacters(in: .whitespacesAndNewlines)
                    continue
                }
                if let activityDetailKey,
                   let separator = text.firstIndex(of: ":"),
                   let field = detailField(String(text[..<separator])) {
                    storeDetail(activityDetailKey, field: field, value: String(text[text.index(after: separator)...]))
                    continue
                }
                if activityDetailKey != nil { continue }
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
                let tableHeader = rows[0]
                let variantColumns = variantColumnIndexes(tableHeader)
                // A canonical SHORT QUICK VIEW includes PREPARES and CONSOLIDATES columns,
                // but it is still an executable time table because it also carries Time and
                // Activity ID. Legacy variant-only tables must keep their two-section projection.
                if isTimeTable(rows) && (variantColumns.isEmpty || hasActivityIDColumn(tableHeader)) {
                    let activities = timeTableActivities(rows)
                    if reachedFinalSections || target == nil {
                        sharedActivities.append(contentsOf: activities)
                    } else if target == .long {
                        longActivities.append(contentsOf: activities)
                    } else {
                        shortActivities.append(contentsOf: activities)
                    }
                    for line in timeTableLines(rows) { appendLine(line) }
                    continue
                }
                if !variantColumns.isEmpty {
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

        longActivities = longActivities.map(mergeDetails)
        shortActivities = shortActivities.map(mergeDetails)
        sharedActivities = sharedActivities.map(mergeDetails)

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
            longActivities: longActivities,
            longMinutes: longMinutes,
            shortSections: shortSections,
            shortActivities: shortActivities,
            shortMinutes: shortMinutes,
            sharedSections: sharedSections,
            sharedActivities: sharedActivities,
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
            criteria: criteria, material: material, development: development, activities: [],
            adaptations: adaptations, organisation: "", coreKnowledge: "", assessment: evidence,
            guidingQuestions: [], closure: ""
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
        let firstValue = normalized(first)
        let hasTime = header.contains { value in
            let normalizedValue = normalized(value)
            return normalizedValue == "time" || normalizedValue == "hora" ||
                normalizedValue == "horario" || normalizedValue == "tiempo"
        }
        let hasActivityID = hasActivityIDColumn(header)
        // New documents keep Time first for compatibility. The relaxed branch also accepts
        // hand-authored fixtures where Activity ID is the first column.
        return firstValue == "time" || firstValue == "hora" || firstValue == "horario" ||
            firstValue == "tiempo" || (hasTime && hasActivityID)
    }

    private func hasActivityIDColumn(_ header: [String]) -> Bool {
        header.contains {
            let value = normalized($0)
            return value.contains("activity id") || value.contains("activity key") ||
                value.contains("id actividad") || value.contains("clave actividad")
        }
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
        let teacherIndex = columnIndex(["teacher narrative", "teacher script", "teacher role", "teacher", "profesor", "docente"])
        let studentIndex = columnIndex(["student narrative", "learner narrative", "student role", "student", "alumno"])
        let evidenceIndex = columnIndex(["evidence", "evidencia"])
        let clilIndex = columnIndex(["clil", "language", "lengua", "scaffolding", "andamiaje"])
        let materialsIndex = columnIndex(["material", "materials", "materiales"])
        let adaptationsIndex = columnIndex(["adaptation", "adaptaciones", "inclusion", "inclusion"])
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
            if let clil = cell(row, clilIndex) { extras.append("CLIL: \(clil)") }
            if let materials = cell(row, materialsIndex) { extras.append("Material: \(materials)") }
            if let adaptations = cell(row, adaptationsIndex) { extras.append("Adaptaciones: \(adaptations)") }
            return extras.isEmpty ? head : "\(head) (\(extras.joined(separator: "; ")))"
        }
    }

    /// Convierte una tabla horaria en actividades tipadas. Las columnas son tolerantes
    /// a español/inglés para que el documento sea legible por el profesor y estable
    /// para el importador.
    private func timeTableActivities(_ rows: [[String]]) -> [LearningSituationSessionActivityDraft] {
        guard let header = rows.first else { return [] }
        let normalizedHeader = header.map(normalized)
        func columnIndex(_ candidates: [String]) -> Int? {
            normalizedHeader.firstIndex { column in
                if candidates.contains("activity") || candidates.contains("actividad") {
                    if column.contains("activity id") || column.contains("activity key") { return false }
                }
                return candidates.contains { column.contains($0) }
            }
        }
        func cell(_ row: [String], _ index: Int?) -> String {
            guard let index, index < row.count else { return "" }
            let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return value == "—" || value == "-" ? "" : value
        }
        let activityIDIndex = columnIndex(["activity id", "activity key", "id actividad", "clave actividad"])
        let typeIndex = columnIndex(["type", "activity type", "tipo"])
        let timeIndex = columnIndex(["time", "hora", "tiempo"])
        let minutesIndex = columnIndex(["minutes", "minutos", "duration", "duracion"])
        let phaseIndex = columnIndex(["phase", "fase"])
        let activityIndex = columnIndex(["activity", "actividad", "task", "tarea"])
        let purposeIndex = columnIndex(["purpose", "propósito", "proposito"])
        let organisationIndex = columnIndex(["organisation", "organization", "organizacion", "grouping"])
        let studentOutputIndex = columnIndex(["student output", "student instructions", "output alumno"])
        let teacherIndex = columnIndex(["teacher narrative", "teacher script", "teacher role", "teacher", "profesor", "docente"])
        let studentIndex = columnIndex(["student actions", "student narrative", "learner narrative", "student role", "student does", "student", "alumno", "learner", "alumnado"])
        let setupIndex = columnIndex(["set-up", "setup", "preparation", "preparacion"])
        let timingIndex = columnIndex(["timing breakdown", "transition cue", "transition", "desglose temporal", "timing"])
        let clilIndex = columnIndex(["clil", "language", "lengua", "scaffolding", "andamiaje"])
        let evidenceIndex = columnIndex(["evidence", "evidencia", "assessment", "evaluacion"])
        let materialsIndex = columnIndex(["material", "materials", "materiales"])
        let adaptationsIndex = columnIndex(["adaptation", "adaptaciones", "inclusion", "inclusion"])
        let slowGroupIndex = columnIndex(["slow group", "if the group is slow", "grupo lento"])
        let fastGroupIndex = columnIndex(["fast group", "if the group is ahead", "grupo adelantado", "extension"])

        return rows.dropFirst().enumerated().compactMap { offset, row in
            let activity = cell(row, activityIndex)
            let fallback = row.dropFirst().map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0 != "—" && $0 != "-" }
                .joined(separator: " · ")
            let resolvedActivity = activity.isEmpty ? fallback : activity
            guard !resolvedActivity.isEmpty else { return nil }
            let legacyKey = String(format: "LEGACY-%02d", offset + 1)
            let key = cell(row, activityIDIndex).isEmpty ? legacyKey : cell(row, activityIDIndex)
            let minutes = Int(cell(row, minutesIndex).filter { $0.isNumber })
            return LearningSituationSessionActivityDraft(
                activityKey: key,
                activityType: cell(row, typeIndex).isEmpty ? "core" : cell(row, typeIndex),
                plannedMinutes: minutes,
                timeLabel: cell(row, timeIndex),
                phase: cell(row, phaseIndex),
                activity: resolvedActivity,
                purpose: cell(row, purposeIndex),
                organisation: cell(row, organisationIndex),
                setup: cell(row, setupIndex),
                teacherActions: cell(row, teacherIndex),
                // QUICK VIEW's Student output is an expected artefact, not the teacher's
                // full instruction script. Keep it in the v2 studentOutput projection;
                // ACTIVITY DETAILS/Instructions for students populates studentInstructions
                // later without overwriting this value.
                studentInstructions: "",
                studentActions: cell(row, studentOutputIndex).isEmpty
                    ? cell(row, studentIndex)
                    : cell(row, studentOutputIndex),
                timingBreakdown: cell(row, timingIndex),
                clilFocus: cell(row, clilIndex),
                evidence: cell(row, evidenceIndex),
                materials: cell(row, materialsIndex),
                adaptations: cell(row, adaptationsIndex),
                slowGroupPlan: cell(row, slowGroupIndex),
                fastGroupExtension: cell(row, fastGroupIndex)
            )
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
        var activities: [LearningSituationSessionActivityDraft] = []
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
                    activities.append(contentsOf: timeTableActivities(rows))
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
            criteria: criteria, material: material, development: development, activities: activities,
            adaptations: adaptations, organisation: "", coreKnowledge: saberes, assessment: evidenceFromFicha,
            guidingQuestions: [], closure: ""
        )
    }

    /// B2: recorta el prefijo de tipo ("Simple:"/"Double:"/"Doble:", con plural opcional) y las
    /// anotaciones tipo "(NEW)"/"(nueva)" del texto que sigue al separador del encabezado.
    private func cleanRestTitle(_ rest: String) -> String {
        rest
            .replacingOccurrences(of: #"^\s*\([^)]*\)\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^(Simples?|Doubles?|Dobles?)\s*[:\-–—]?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^\s*\([^)]*\)\s*[-–—:]?\s*"#, with: "", options: .regularExpression)
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
        let pattern = #"^(?:SESSION|SESSIONS|SESI|SESSI)(?:ÓN|ON|ONES|ONS)?\s+[0-9]+(?:\s+(?:y|and|\&)\s+[0-9]+)?\s*(?:\([^)]*\)\s*)?(?:[.:\-–—]\s*)?(?:(?:Simples?|Doubles?|Dobles?)\s*[.:\-–—]?\s*)?(?:\([^)]*\)\s*)?(.*)$"#
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

enum ImportBlock {
    case heading(String)
    case paragraph(String)
    case table([[String]])
}

/// Variante de `WordDocumentTableReader` (ver `LearningSituationAssessmentInstrumentsImportService.swift`)
/// específica de este importador: además de distinguir párrafo de tabla, marca como `.heading`
/// cualquier párrafo con estilo de Word "Heading 1/2/3..." (`w:pStyle`), para que `sectionText`
/// pueda parar en el siguiente título real del documento en vez de depender solo de una lista de
/// sinónimos de encabezado.
private final class WordStyledParagraphReader: NSObject, XMLParserDelegate {
    private(set) var blocks: [ImportBlock] = []
    private var inParagraph = false
    private var inTable = false
    private var inRow = false
    private var inCell = false
    private var inText = false
    private var paragraphBuffer = ""
    private var cellBuffer = ""
    private var currentRow: [String] = []
    private var currentTable: [[String]] = []
    private var currentParagraphIsHeading = false

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
            if !inCell {
                paragraphBuffer = ""
                currentParagraphIsHeading = false
            }
        } else if inParagraph && !inCell && isElement(elementName, "pStyle") {
            if let styleId = attributeDict["w:val"], styleId.range(of: "^Heading[1-6]$", options: .regularExpression) != nil {
                currentParagraphIsHeading = true
            }
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
                if !value.isEmpty {
                    blocks.append(currentParagraphIsHeading ? .heading(value) : .paragraph(value))
                }
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
        elementName == "w:\(localName)" || elementName.hasSuffix(":\(localName)")
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
