import Foundation
import SwiftUI
import Speech
import AVFoundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Modelos de Entrada para "Voz de Pista"

struct CourtVoiceStudentDescriptor: Hashable, Sendable, Codable, Identifiable {
    let id: Int64
    let firstName: String
    let lastName: String
    let fullName: String
    let isCurrentlyInjured: Bool
    let aliases: [String]

    init(
        id: Int64,
        firstName: String? = nil,
        lastName: String? = nil,
        fullName: String,
        isCurrentlyInjured: Bool = false,
        aliases: [String] = []
    ) {
        self.id = id
        let trimmedFull = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fullName = trimmedFull
        if let f = firstName?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty {
            self.firstName = f
            self.lastName = (lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let parts = trimmedFull.split(separator: " ").map(String.init)
            self.firstName = parts.first ?? trimmedFull
            self.lastName = parts.dropFirst().joined(separator: " ")
        }
        self.isCurrentlyInjured = isCurrentlyInjured
        self.aliases = aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

enum CourtVoiceColumnScaleKind: String, Codable, Hashable, Sendable {
    case tenPoint = "TEN_POINT"
    case fourLevel = "FOUR_LEVEL"
    case percentage = "PERCENTAGE"
    case time = "TIME"
    case distance = "DISTANCE"
    case repetitions = "REPETITIONS"
    case letterABCD = "LETTER_ABCD"
    case achievement = "ACHIEVEMENT"
    case yesNo = "YES_NO"
    case custom = "CUSTOM"

    var isRawPhysicalMark: Bool {
        self == .time || self == .distance || self == .repetitions
    }
}

struct CourtVoiceColumnDescriptor: Hashable, Sendable, Codable, Identifiable {
    let id: String
    let title: String
    let evaluationId: Int64?
    let columnType: String
    let inputKind: String
    let scaleKind: CourtVoiceColumnScaleKind
    let ordinalLevels: [String]
    let unitOrSituation: String?
    let dateEpochMs: Int64?
    let isLocked: Bool
    let isHiddenOrArchived: Bool
    let tabIds: [String]
    let aliases: [String]

    init(
        id: String,
        title: String,
        evaluationId: Int64? = nil,
        columnType: String = "NUMERIC",
        inputKind: String = "NUMERIC_0_10",
        scaleKind: CourtVoiceColumnScaleKind = .tenPoint,
        ordinalLevels: [String] = [],
        unitOrSituation: String? = nil,
        dateEpochMs: Int64? = nil,
        isLocked: Bool = false,
        isHiddenOrArchived: Bool = false,
        tabIds: [String] = [],
        aliases: [String] = []
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.evaluationId = evaluationId
        self.columnType = columnType
        self.inputKind = inputKind
        self.scaleKind = scaleKind
        self.ordinalLevels = ordinalLevels
        self.unitOrSituation = unitOrSituation?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.dateEpochMs = dateEpochMs
        self.isLocked = isLocked
        self.isHiddenOrArchived = isHiddenOrArchived
        self.tabIds = tabIds
        self.aliases = aliases
    }

    var isEvaluableCandidate: Bool {
        !isLocked && !isHiddenOrArchived && !["CALCULATED", "ATTENDANCE"].contains(columnType.uppercased())
    }

    /// Columnas de niveles (1-4, A-D, ordinales). Un "entregado / no entregado" no equivale a ningún nivel.
    var isLevelScale: Bool {
        columnType.uppercased() == "ORDINAL" || !ordinalLevels.isEmpty || scaleKind == .fourLevel || scaleKind == .letterABCD
    }

    /// Instrumento estructurado (checklist, observación, formulario o quiz). Su nota sale de las respuestas de
    /// la plantilla, así que Voz de Pista solo puede marcar el estado de entrega, nunca dictar una nota.
    var isStructuredInstrument: Bool {
        CourtVoiceColumnDescriptor.structuredInputKinds.contains(inputKind.uppercased())
    }

    static let structuredInputKinds: Set<String> = [
        "STRUCTURED_CHECKLIST", "STRUCTURED_OBSERVATION", "STRUCTURED_FORM", "STRUCTURED_QUIZ"
    ]
}

/// Estado de entrega que Voz de Pista escribe en columnas de instrumento estructurado.
enum CourtVoiceDeliveryStatus: String, CaseIterable, Sendable {
    case completed = "Completo"
    case pending = "Pendiente"

    var label: String {
        switch self {
        case .completed: return "Completada"
        case .pending: return "Pendiente"
        }
    }

    static func from(_ text: String?) -> CourtVoiceDeliveryStatus? {
        guard let text else { return nil }
        return CourtVoiceDeliveryStatus(rawValue: text)
    }
}

struct CourtVoiceStudentCandidate: Hashable, Sendable, Codable, Identifiable {
    let id: Int64
    let fullName: String
    let confidence: Double
    let matchReason: String
}

struct CourtVoiceColumnCandidate: Hashable, Sendable, Codable, Identifiable {
    let id: String
    let title: String
    let confidence: Double
    let matchReason: String
}

struct CourtVoiceCaptureInput: Hashable, Sendable {
    let transcript: String
    let classId: Int64
    let className: String
    let sessionTitle: String?
    let activeTabId: String?
    let referenceDate: Date
    let students: [CourtVoiceStudentDescriptor]
    let evaluableColumns: [CourtVoiceColumnDescriptor]

    init(
        transcript: String,
        classId: Int64,
        className: String,
        sessionTitle: String? = nil,
        activeTabId: String? = nil,
        referenceDate: Date = .now,
        students: [CourtVoiceStudentDescriptor],
        evaluableColumns: [CourtVoiceColumnDescriptor] = []
    ) {
        self.transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        self.classId = classId
        self.className = className.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sessionTitle = sessionTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.activeTabId = activeTabId?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.referenceDate = referenceDate
        self.students = students
        self.evaluableColumns = evaluableColumns.filter(\.isEvaluableCandidate)
    }
}

// MARK: - Aprendizaje de Alias por Clase (Persistencia ligera local)

enum CourtVoiceAliasStore {
    private static let studentKeyPrefix = "court.voice.aliases.student.v1."
    private static let columnKeyPrefix = "court.voice.aliases.column.v1."

    static func studentAliases(forClassId classId: Int64) -> [String: Int64] {
        guard let raw = UserDefaults.standard.dictionary(forKey: "\(studentKeyPrefix)\(classId)") as? [String: NSNumber] else {
            return [:]
        }
        return raw.mapValues { $0.int64Value }
    }

    static func columnAliases(forClassId classId: Int64) -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: "\(columnKeyPrefix)\(classId)") as? [String: String]) ?? [:]
    }

    static func learnStudentAlias(mention: String, studentId: Int64, classId: Int64) {
        let norm = AppleFoundationCourtVoiceService.normalized(mention)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard norm.count >= 2, norm != "alumno por confirmar" else { return }
        var current = UserDefaults.standard.dictionary(forKey: "\(studentKeyPrefix)\(classId)") as? [String: NSNumber] ?? [:]
        current[norm] = NSNumber(value: studentId)
        UserDefaults.standard.set(current, forKey: "\(studentKeyPrefix)\(classId)")
    }

    static func learnColumnAlias(mention: String, columnId: String, classId: Int64) {
        let norm = AppleFoundationCourtVoiceService.normalized(mention)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard norm.count >= 2 else { return }
        var current = columnAliases(forClassId: classId)
        current[norm] = columnId
        UserDefaults.standard.set(current, forKey: "\(columnKeyPrefix)\(classId)")
    }
}

// MARK: - Modelos de Salida Estructurados (Contrato revisable)

enum CourtVoiceActionKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case attendance
    case observation
    case quickEvaluation
    case injury

    var id: String { rawValue }

    var title: String {
        switch self {
        case .attendance:
            return "Asistencia"
        case .observation:
            return "Observación / Actitud"
        case .quickEvaluation:
            return "Evaluación rápida"
        case .injury:
            return "Estado físico / Lesión"
        }
    }

    var systemImage: String {
        switch self {
        case .attendance:
            return "checkmark.circle.fill"
        case .observation:
            return "eye.fill"
        case .quickEvaluation:
            return "sparkles"
        case .injury:
            return "bandage.fill"
        }
    }

    var tint: Color {
        switch self {
        case .attendance:
            return DashboardStyle.accent
        case .observation:
            return NotebookStyle.primaryTint
        case .quickEvaluation:
            return DashboardStyle.Tint.success
        case .injury:
            return DashboardStyle.Tint.alert
        }
    }
}

struct CourtVoiceProposedAction: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var isSelected: Bool
    var kind: CourtVoiceActionKind
    var studentId: Int64?
    var studentName: String
    var studentMention: String
    var studentCandidates: [CourtVoiceStudentCandidate]
    /// Para `.attendance`: `PRESENTE`, `AUSENTE`, `TARDE`, `JUSTIFICADO`, `SIN_MATERIAL`, `EXENTO`.
    var attendanceStatus: String?
    /// Para `.observation`, `.attendance` o `.quickEvaluation`: texto descriptivo.
    var note: String
    /// Para `.observation`: `low`, `medium`, `high`.
    var severity: String
    /// Para `.quickEvaluation`: nota numérica o dato bruto físico (segundos, metros, repeticiones, palier).
    var score: Double?
    /// Valor formateado o nivel ordinal convertido según la escala de la columna (`ordinalLevels`, `LETTER_ABCD`, `YES_NO`, etc.).
    var formattedScaleValue: String?
    /// Unidad detectada si es prueba física (`s`, `m`, `rep`, `palier`).
    var rawUnit: String?
    /// 10 = entregado, 0 = no entregado. Solo cuando el dictado habla de entrega, no de nota.
    var deliveryRawScore: Double?
    /// Para `.quickEvaluation`: identificador de columna del cuaderno (`nil` si no se reconoció instrumento).
    var columnId: String?
    var columnTitle: String?
    var columnMention: String?
    var columnCandidates: [CourtVoiceColumnCandidate]
    /// Criterios de la rúbrica o ítems de la plantilla de `criteriaColumnId` que encajan con la frase.
    /// En `.quickEvaluation` coincide con `columnId`; en `.observation` es la sugerencia de evaluar con ese instrumento.
    var criterionProposals: [CourtVoiceCriterionProposal]?
    /// «Igual que Irene» / «igual que el primero»: acción de la que se copian los criterios no dichos.
    var inheritsCriteriaFromActionId: String?
    var criteriaColumnId: String?
    var criteriaColumnTitle: String?
    /// Para `.injury`: `true` = marcar lesionado, `false` = retirar lesión.
    var markInjured: Bool?
    /// Fragmento original del dictado que originó la acción.
    var sourceExcerpt: String
    /// Explicación breve de por qué se asignó el alumno/columna o por qué requiere revisión.
    var resolutionReason: String?
    var confidence: Double

    init(
        id: String = UUID().uuidString,
        isSelected: Bool = true,
        kind: CourtVoiceActionKind,
        studentId: Int64?,
        studentName: String,
        studentMention: String = "",
        studentCandidates: [CourtVoiceStudentCandidate] = [],
        attendanceStatus: String? = nil,
        note: String = "",
        severity: String = "low",
        score: Double? = nil,
        formattedScaleValue: String? = nil,
        rawUnit: String? = nil,
        deliveryRawScore: Double? = nil,
        columnId: String? = nil,
        columnTitle: String? = nil,
        columnMention: String? = nil,
        columnCandidates: [CourtVoiceColumnCandidate] = [],
        markInjured: Bool? = nil,
        sourceExcerpt: String = "",
        resolutionReason: String? = nil,
        confidence: Double = 1.0
    ) {
        self.id = id
        self.isSelected = isSelected
        self.kind = kind
        self.studentId = studentId
        self.studentName = AppleAIOutputNormalizer.nonEmpty(studentName, fallback: "Alumno por confirmar")
        self.studentMention = studentMention.trimmingCharacters(in: .whitespacesAndNewlines)
        self.studentCandidates = studentCandidates
        self.attendanceStatus = attendanceStatus
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.severity = ["low", "medium", "high"].contains(severity.lowercased()) ? severity.lowercased() : "low"
        self.score = score.map { (($0 * 100).rounded() / 100) }
        self.formattedScaleValue = formattedScaleValue
        self.rawUnit = rawUnit
        self.deliveryRawScore = deliveryRawScore
        self.columnId = columnId
        self.columnTitle = columnTitle
        self.columnMention = columnMention?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.columnCandidates = columnCandidates
        self.markInjured = markInjured
        self.sourceExcerpt = sourceExcerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.resolutionReason = resolutionReason
        self.confidence = min(1.0, max(0.0, confidence))
    }

    /// Indica si una evaluación rápida está completa para poder aplicarse sin inventar nota ni columna.
    var isReadyToApply: Bool {
        guard studentId != nil else { return false }
        if kind == .quickEvaluation {
            let hasValue = score != nil || !(formattedScaleValue?.isEmpty ?? true) || hasChosenCriteria
            return hasValue && columnId != nil
        }
        return true
    }

    /// Hay al menos un criterio valorado para el instrumento elegido.
    var hasChosenCriteria: Bool {
        guard let columnId, criteriaColumnId == columnId else { return false }
        return criterionProposals?.hasChosenLevel ?? false
    }

    var actionSummaryLine: String {
        switch kind {
        case .attendance:
            let statusLabel = AttendanceStatusOption.option(for: attendanceStatus)?.label ?? (attendanceStatus ?? "Retraso")
            return note.isEmpty ? "Marcar \(statusLabel)" : "Marcar \(statusLabel) · \(note)"
        case .observation:
            return note.isEmpty ? "Registrar observación de aula" : note
        case .quickEvaluation:
            let valueLabel: String
            if let formatted = formattedScaleValue, !formatted.isEmpty {
                valueLabel = formatted
            } else if let score {
                let num = String(format: "%.1f", score).replacingOccurrences(of: ".0", with: "")
                valueLabel = rawUnit.map { "\(num) \($0)" } ?? num
            } else {
                valueLabel = "Sin nota (elige valor)"
            }
            let colLabel = columnTitle ?? "Sin instrumento (elige uno)"
            return note.isEmpty ? "Valor \(valueLabel) en \(colLabel)" : "Valor \(valueLabel) en \(colLabel) · \(note)"
        case .injury:
            let stateLabel = (markInjured ?? true) ? "Marcar con lesión / adaptación física" : "Retirar lesión (disponible)"
            return note.isEmpty ? stateLabel : "\(stateLabel) · \(note)"
        }
    }
}

struct CourtVoiceCaptureDraft: Codable, Hashable, Sendable {
    let rawTranscript: String
    let className: String
    var actions: [CourtVoiceProposedAction]
    let unmatchedSegments: [String]
    let confidenceNote: String
    let appearsToBeRulesFallback: Bool

    init(
        rawTranscript: String,
        className: String,
        actions: [CourtVoiceProposedAction],
        unmatchedSegments: [String] = [],
        confidenceNote: String,
        appearsToBeRulesFallback: Bool = false
    ) {
        self.rawTranscript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        self.className = AppleAIOutputNormalizer.nonEmpty(className, fallback: "Clase activa")
        self.actions = actions
        self.unmatchedSegments = AppleAIOutputNormalizer.compactLimited(unmatchedSegments, limit: 6)
        self.confidenceNote = AppleAIOutputNormalizer.nonEmpty(
            confidenceNote,
            fallback: "Revisión docente obligatoria antes de aplicar al cuaderno."
        )
        self.appearsToBeRulesFallback = appearsToBeRulesFallback
    }
}

// MARK: - Servicio de IA Local + Resolutor Determinista con Confianza

@MainActor
final class AppleFoundationCourtVoiceService {

    func prewarm() {
        guard AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available else { return }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let session = makeFreshSession()
            session.prewarm()
        }
        #endif
    }

    func parseVoiceCapture(from input: CourtVoiceCaptureInput) async -> CourtVoiceCaptureDraft {
        let trimmed = input.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return CourtVoiceCaptureDraft(
                rawTranscript: "",
                className: input.className,
                actions: [],
                unmatchedSegments: [],
                confidenceNote: "Dicta o escribe una nota de pista para analizar acciones.",
                appearsToBeRulesFallback: true
            )
        }

        // Calculamos el resultado determinista como red de seguridad y referencia.
        let deterministic = parseWithRulesFallback(from: input, reason: "Estructurado con motor de reglas locales en el dispositivo.")

        guard AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available else {
            return deterministic
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                // Un dictado largo (p. ej. 9 minutos alumno a alumno) no cabe en los ~4K tokens del modelo:
                // se trocea por bloques de alumno ya separados por las reglas y se une el resultado.
                let chunks = Self.chunkTranscript(trimmed)
                var resolvedActions: [CourtVoiceProposedAction] = []
                var unmatchedFromAI: [String] = []
                for chunk in chunks {
                    let chunkInput = CourtVoiceCaptureInput(
                        transcript: chunk,
                        classId: input.classId,
                        className: input.className,
                        sessionTitle: input.sessionTitle,
                        activeTabId: input.activeTabId,
                        referenceDate: input.referenceDate,
                        students: input.students,
                        evaluableColumns: input.evaluableColumns
                    )
                    do {
                        // Sesión limpia por trozo para no acumular historial ni agotar el contexto.
                        let session = makeFreshSession()
                        let response = try await session.respond(
                            to: buildPrompt(from: chunkInput),
                            generating: GeneratedCourtVoiceCaptureDraft.self,
                            includeSchemaInPrompt: true,
                            options: AppleFoundationModelSupport.generationOptions(temperature: 0.1)
                        )
                        resolvedActions.append(contentsOf: mapGeneratedActions(response.content.actions, input: chunkInput))
                        unmatchedFromAI.append(contentsOf: response.content.unmatchedSegments)
                    } catch where chunks.count > 1 && AppleFoundationModelSupport.requestScopedFailureKinds.contains(AppleFoundationModelSupport.runtimeFailureKind(for: error)) {
                        // Si falla un trozo, las reglas lo completan al combinar.
                        AppleFoundationModelSupport.recordRequestFailure(error)
                    }
                }
                guard let merged = Self.mergeWithRules(aiActions: resolvedActions, ruleActions: deterministic.actions) else {
                    return deterministic
                }
                return CourtVoiceCaptureDraft(
                    rawTranscript: trimmed,
                    className: input.className,
                    actions: merged.actions,
                    unmatchedSegments: unmatchedFromAI,
                    confidenceNote: merged.addedFromRules > 0
                        ? "Apple Intelligence on-device, completado con reglas locales (\(merged.addedFromRules)). Revisa antes de confirmar."
                        : "Acciones extraídas con Apple Intelligence on-device. Revisa antes de confirmar.",
                    appearsToBeRulesFallback: false
                )
            } catch {
                // Un fallo de esta petición (texto largo, respuesta mal formada…) no apaga la IA para las siguientes.
                AppleFoundationModelSupport.recordRequestFailure(error)
                return deterministic
            }
        }
        #endif

        return deterministic
    }

    /// Trozos de como mucho `maxLength` caracteres sin partir el bloque de un alumno. Un texto corto va entero.
    static func chunkTranscript(_ text: String, ruleActions: [CourtVoiceProposedAction] = [], maxLength: Int = 900) -> [String] {
        guard text.count > maxLength else { return [text] }
        // Se trocea el texto original por frases (no se pierde nada) y nunca se deja un nombre solo
        // («Noemí.») al final de un trozo: su descripción va en el siguiente.
        let sentences = text
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var chunks: [[String]] = []
        var current: [String] = []
        var length = 0
        for sentence in sentences {
            if !current.isEmpty && length + sentence.count + 2 > maxLength {
                var carry: [String] = []
                if let last = current.last, last.split(separator: " ").count <= 3, current.count > 1 {
                    carry = [current.removeLast()]
                }
                chunks.append(current)
                current = carry
                length = carry.reduce(0) { $0 + $1.count + 2 }
            }
            current.append(sentence)
            length += sentence.count + 2
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks.map { $0.joined(separator: ". ") }
    }

    /// Combina la respuesta de Apple Intelligence con las reglas en vez de descartarla entera.
    /// - Alumnos que la IA no recogió (p. ej. al resumir una enumeración): se añaden las acciones de las reglas.
    /// - Acción de la IA sin valor aplicable cuando las reglas sí lo tienen para el mismo alumno y tipo: se usa la de las reglas.
    /// Devuelve `nil` si la IA no devolvió nada, para usar solo las reglas.
    static func mergeWithRules(
        aiActions: [CourtVoiceProposedAction],
        ruleActions: [CourtVoiceProposedAction]
    ) -> (actions: [CourtVoiceProposedAction], addedFromRules: Int)? {
        guard !aiActions.isEmpty else { return nil }
        var merged = aiActions
        var usedRuleIds = Set<String>()
        var replaced = 0

        for index in merged.indices where !merged[index].isReadyToApply {
            let ai = merged[index]
            guard let studentId = ai.studentId,
                  let rule = ruleActions.first(where: {
                      $0.studentId == studentId && $0.kind == ai.kind && $0.isReadyToApply && !usedRuleIds.contains($0.id)
                  }) else { continue }
            merged[index] = rule
            usedRuleIds.insert(rule.id)
            replaced += 1
        }

        let aiStudents = Set(aiActions.compactMap(\.studentId))
        let missing = ruleActions.filter { rule in
            guard let studentId = rule.studentId else { return false }
            return !aiStudents.contains(studentId) && !usedRuleIds.contains(rule.id)
        }
        merged.append(contentsOf: missing)
        return (merged, replaced + missing.count)
    }

    // MARK: - Mapeo de salida de Foundation Models mediante el Resolutor Determinista

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func makeFreshSession() -> LanguageModelSession {
        LanguageModelSession(
            instructions: """
            Eres un asistente operativo de pista para un profesor de Educación Física.
            Tu misión es extraer menciones estructuradas a partir de notas de voz rápidas dichas en el patio o pabellón.
            REGLAS ESTRICTAS DE DISCRIMINACIÓN (INSTRUMENTO VS OBSERVACIÓN):
            1. Extrae en `studentName` la mención del alumno (nombre, apellido o apodo) sin inventar alumnos que no estén en la transcripción.
            2. Clasifica cada acción en uno de estos 4 tipos (`kind`):
               - `attendance`: retrasos ("llega tarde", "5 min tarde"), faltas ("no ha venido", "ausente"), justificadas, olvido de ropa/material deportivo (`SIN_MATERIAL`) o exenciones (`EXENTO`). Cuidado: "le falta técnica" o "esta tarde" NO son asistencia.
               - `injury`: lesión física hoy, esguince, molestia en tobillo/rodilla/gemelo/hombro, indisposición o alta médica ("ya está recuperado", "alta médica").
               - `quickEvaluation`: cuando el profesor expresa intención de CALIFICAR, registrar una marca/nota/nivel o indicar si un alumno HA COMPLETADO / ENTREGADO o NO HA COMPLETADO una rúbrica, autoevaluación, prueba o instrumento. Si dice "ha completado / sí / entregado", pon `score = 10.0`. Si dice "no la ha completado / no entregado", pon `score = 0.0`. Si no dice ninguna nota ni estado de completitud, deja `score` en `nil`.
               - `observation`: actitud, comportamiento, fair play, participación, esfuerzo, recogida de material, conflictos o anécdotas de sesión SIN pedir una calificación ni nombrar una columna evaluable. Ejemplo: "excelente compañero animando al equipo" es `observation`.
            3. Si una frase o enumeración menciona a varios alumnos ("Lucía un 8, Marcos un 7", "Sofía y Mateo llegan tarde", o "Ferran ha completado la rúbrica, Ignacio también, Emma también, José también, Nerea no la ha completado"), genera UNA ACCIÓN INDEPENDIENTE POR CADA ALUMNO heredando el instrumento y el valor cuando se dice "también" o invirtiéndolo cuando se dice "tampoco / no la ha completado".
            4. Si una segunda frase empieza por conector continuativo sin repetir el nombre ("Lucía un 8. Además ayudó a recoger"), mantén a ese alumno como sujeto.
            """
        )
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func mapGeneratedActions(
        _ generated: [GeneratedCourtVoiceAction],
        input: CourtVoiceCaptureInput
    ) -> [CourtVoiceProposedAction] {
        let rankedColumns = Self.rankRelevantColumns(input.evaluableColumns, sessionTitle: input.sessionTitle, activeTabId: input.activeTabId, referenceDate: input.referenceDate)
        var lastRememberedColumn: CourtVoiceColumnDescriptor?
        var lastRememberedColumnReason: String?
        var lastRememberedStudent: CourtVoiceStudentDescriptor?
        var lastRememberedKind: CourtVoiceActionKind?
        var lastRememberedScore: Double?
        var lastRememberedIsDelivery = false
        var lastRememberedNote: String?

        return generated.map { item in
            let combinedText = "\(item.columnHint ?? "") \(item.note) \(item.sourceExcerpt)"
            let extractedVal = Self.extractValueAndUnit(from: "\(item.note) \(item.sourceExcerpt)")
            let colResolution = Self.resolveColumn(
                mention: item.columnHint,
                segmentText: combinedText,
                columns: rankedColumns,
                classId: input.classId
            )

            if let matchedCol = colResolution.matched {
                lastRememberedColumn = matchedCol
                lastRememberedColumnReason = colResolution.reason
            }

            let isEllipticalSame = Self.isEllipticalSamePredicate(combinedText)
            let isEllipticalNegated = Self.isEllipticalNegatedPredicate(combinedText)

            let resolvedKind: CourtVoiceActionKind
            let rawKindStr = item.kind.rawValue
            if (isEllipticalSame || isEllipticalNegated), let rememberedKind = lastRememberedKind {
                resolvedKind = rememberedKind
            } else if let parsed = CourtVoiceActionKind(rawValue: rawKindStr) {
                if parsed == .quickEvaluation && item.score == nil && extractedVal == nil && colResolution.matched == nil && lastRememberedColumn == nil {
                    resolvedKind = inferKind(from: "\(item.note) \(item.sourceExcerpt)", columns: rankedColumns)
                } else if parsed == .observation && (item.score != nil || ((extractedVal != nil || Self.extractCompletionScore(from: combinedText) != nil) && (colResolution.matched != nil || lastRememberedColumn != nil))) {
                    resolvedKind = .quickEvaluation
                } else {
                    resolvedKind = parsed
                }
            } else {
                resolvedKind = inferKind(from: "\(item.note) \(item.sourceExcerpt)", columns: rankedColumns)
            }

            let studentRes = Self.resolveStudents(
                mention: item.studentName,
                in: input.students,
                classId: input.classId
            )

            let effectiveStudent: CourtVoiceStudentDescriptor?
            let studentCandidates = studentRes.candidates
            var reasons: [String] = []

            if let unico = studentRes.matched {
                effectiveStudent = unico
                lastRememberedStudent = unico
                if let r = studentRes.reason { reasons.append(r) }
            } else if studentCandidates.count > 1 {
                effectiveStudent = nil
                reasons.append("Nombre ambiguo (\(studentCandidates.map(\.fullName).joined(separator: " / ")))")
            } else if item.studentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let remembered = lastRememberedStudent {
                effectiveStudent = remembered
                reasons.append("Sujeto heredado: \(remembered.fullName)")
            } else {
                effectiveStudent = nil
            }

            let targetColumn: CourtVoiceColumnDescriptor?
            if resolvedKind == .quickEvaluation {
                if let explicit = colResolution.matched {
                    targetColumn = explicit
                    if let r = colResolution.reason { reasons.append(r) }
                } else if let remembered = lastRememberedColumn {
                    targetColumn = remembered
                    reasons.append(lastRememberedColumnReason.map { "\($0) (contexto)" } ?? "Instrumento heredado de frase anterior")
                } else {
                    targetColumn = nil
                    reasons.append("Sin instrumento especificado: elige columna")
                }
            } else {
                targetColumn = nil
            }

            let completionScore = Self.extractCompletionScore(from: combinedText)
            let rawScore: Double?
            if isEllipticalNegated {
                rawScore = 0.0
            } else if let s = item.score ?? extractedVal?.numericValue ?? completionScore {
                rawScore = s
            } else if isEllipticalSame {
                rawScore = lastRememberedScore
            } else {
                rawScore = nil
            }

            let isDelivery = isEllipticalNegated
                || (item.score == nil && extractedVal == nil && (completionScore != nil || (isEllipticalSame && lastRememberedIsDelivery)))
            let converted = Self.convertValueForColumn(
                rawScore: rawScore,
                rawText: "\(item.note) \(item.sourceExcerpt)",
                unit: extractedVal?.unit,
                column: targetColumn,
                isDeliveryStatement: isDelivery
            )
            if resolvedKind == .quickEvaluation && converted.numericScore == nil && converted.formattedText == nil {
                reasons.append(isDelivery && targetColumn?.isLevelScale == true ? "Entregar no es un nivel: elige nivel" : "Sin calificación detectada: indica nota")
            }

            if resolvedKind != .observation {
                lastRememberedKind = resolvedKind
            }
            if let validScore = isDelivery ? rawScore : (converted.numericScore ?? rawScore) {
                lastRememberedScore = validScore
                lastRememberedIsDelivery = isDelivery
            }
            if !item.note.isEmpty && !isEllipticalSame {
                lastRememberedNote = item.note
            }

            let effectiveNote = (isEllipticalSame && (item.note.count <= 12 || Self.normalized(item.note) == "tambien"))
                ? (lastRememberedNote ?? item.note)
                : item.note

            let normalizedStatus = Self.normalizeAttendanceStatus(item.attendanceStatus, transcriptFragment: "\(effectiveNote) \(item.sourceExcerpt)")
            let isReady = effectiveStudent != nil && (resolvedKind != .quickEvaluation || (targetColumn != nil && (converted.numericScore != nil || converted.formattedText != nil)))

            return CourtVoiceProposedAction(
                isSelected: isReady && studentRes.confidence >= 0.75,
                kind: resolvedKind,
                studentId: effectiveStudent?.id,
                studentName: effectiveStudent?.fullName ?? (item.studentName.isEmpty ? "Alumno por confirmar" : item.studentName),
                studentMention: item.studentName,
                studentCandidates: studentCandidates,
                attendanceStatus: resolvedKind == .attendance ? normalizedStatus : nil,
                note: effectiveNote,
                severity: item.severity,
                score: resolvedKind == .quickEvaluation ? converted.numericScore : nil,
                formattedScaleValue: resolvedKind == .quickEvaluation ? converted.formattedText : nil,
                rawUnit: resolvedKind == .quickEvaluation ? (converted.unit ?? extractedVal?.unit) : nil,
                columnId: resolvedKind == .quickEvaluation ? targetColumn?.id : nil,
                columnTitle: resolvedKind == .quickEvaluation ? targetColumn?.title : nil,
                columnMention: item.columnHint,
                columnCandidates: colResolution.candidates,
                markInjured: resolvedKind == .injury ? (item.markInjured ?? !Self.isInjuryRecovery(in: "\(effectiveNote) \(item.sourceExcerpt)")) : nil,
                sourceExcerpt: item.sourceExcerpt,
                resolutionReason: reasons.isEmpty ? nil : reasons.joined(separator: " · "),
                confidence: min(studentRes.confidence, resolvedKind == .quickEvaluation ? (targetColumn != nil ? max(0.75, colResolution.confidence) : 0.4) : 1.0)
            )
        }
    }
    #endif

    private func buildPrompt(from input: CourtVoiceCaptureInput) -> String {
        let rankedColumns = Self.rankRelevantColumns(
            input.evaluableColumns,
            sessionTitle: input.sessionTitle,
            activeTabId: input.activeTabId,
            referenceDate: input.referenceDate
        )
        let rosterLines = input.students.prefix(40).map { "- \($0.fullName) (ID: \($0.id))" }.joined(separator: "\n")
        let columnLines = rankedColumns.prefix(12).map { col in
            let scaleInfo = col.scaleKind.rawValue
            let unitInfo = col.unitOrSituation.map { " · UD: \($0)" } ?? ""
            return "- \(col.title) (ID: \(col.id), Escala: \(scaleInfo)\(unitInfo))"
        }.joined(separator: "\n")

        return """
        Clase activa: \(input.className)
        Sesión del día: \(input.sessionTitle ?? "Sesión en pista")

        Alumnado del grupo:
        \(rosterLines.isEmpty ? "(Sin lista cargada, extrae los nombres tal cual se mencionen)" : rosterLines)

        Instrumentos / Columnas evaluables relevantes en esta clase:
        \(columnLines.isEmpty ? "(Ninguna columna cargada; deja columnHint vacío si no se menciona instrumento)" : columnLines)

        Transcripción de voz del docente en pista:
        "\(input.transcript)"
        """
    }

    // MARK: - Motor Determinista por Reglas (100% Offline e Instantáneo)

    func parseWithRulesFallback(from input: CourtVoiceCaptureInput, reason: String) -> CourtVoiceCaptureDraft {
        let raw = input.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let rankedColumns = Self.rankRelevantColumns(
            input.evaluableColumns,
            sessionTitle: input.sessionTitle,
            activeTabId: input.activeTabId,
            referenceDate: input.referenceDate
        )
        let segments = Self.splitIntoSegments(raw, roster: input.students, classId: input.classId)

        var actions: [CourtVoiceProposedAction] = []
        var unmatched: [String] = []

        // Memoria contextual dentro de la misma nota de voz:
        // - Instrumento: SOLO se recuerda si el docente ya mencionó uno explícitamente (nunca se inventa la primera columna por defecto).
        // - Alumno: si una frase continuativa ("Además ayudó a recoger") no menciona otro nombre, hereda el último alumno único.
        // - Predicado elíptico ("Ignacio Alemán también", "Emma Ambel también", "Nerea Cardo no la ha completado"): hereda kind, columna y nota/estado de la acción previa.
        var lastRememberedColumn: CourtVoiceColumnDescriptor? = nil
        var lastRememberedColumnReason: String? = nil
        var lastRememberedStudent: CourtVoiceStudentDescriptor? = nil
        var lastRememberedKind: CourtVoiceActionKind? = nil
        var lastRememberedScore: Double? = nil
        var lastRememberedIsDelivery = false
        var lastRememberedAttendanceStatus: String? = nil
        var lastRememberedNote: String? = nil
        // Bloques de dictado alumno a alumno («Noemí.», «Daniela, …»). Con dos o más, todo el dictado se trata así.
        var headerBlockIds: Set<String> = []

        for segment in segments {
            let trimmedSegment = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSegment.isEmpty else { continue }

            let colResolution = Self.resolveColumn(
                mention: nil,
                segmentText: trimmedSegment,
                columns: rankedColumns,
                classId: input.classId
            )
            if let explicitCol = colResolution.matched {
                lastRememberedColumn = explicitCol
                lastRememberedColumnReason = colResolution.reason
            }

            let allMatches = Self.findAllStudentMentions(in: trimmedSegment, roster: input.students, classId: input.classId)
            // «Igual que Irene»: Irene es una referencia, no el sujeto de la frase.
            let referencedIds = Self.referencedStudentIds(in: trimmedSegment, matches: allMatches)
            let studentMatches = allMatches.filter { match in
                guard let id = match.matched?.id else { return true }
                return !referencedIds.contains(id)
            }
            let referenceActionId: String? = {
                if let refId = referencedIds.first {
                    return actions.last(where: { $0.studentId == refId && ($0.kind == .quickEvaluation || $0.kind == .observation) })?.id
                }
                return nil
            }()
            let isSameEllipsis = Self.isEllipticalSamePredicate(trimmedSegment)
            let isNegatedEllipsis = Self.isEllipticalNegatedPredicate(trimmedSegment)

            let inferredKind = inferKind(from: trimmedSegment, columns: rankedColumns, inheritedColumn: lastRememberedColumn)
            let kind: CourtVoiceActionKind
            if (isSameEllipsis || isNegatedEllipsis), let prevKind = lastRememberedKind {
                kind = prevKind
            } else {
                kind = inferredKind
            }

            let columnToUse = colResolution.matched ?? lastRememberedColumn
            let colReason = colResolution.matched != nil
                ? colResolution.reason
                : (lastRememberedColumn != nil ? "\(lastRememberedColumnReason ?? "Instrumento") (contexto)" : nil)

            // Si el segmento solo introduce el instrumento ("En la rúbrica de saque") sin alumno ni nota ni verbo de acción,
            // actualizamos la memoria de instrumento y pasamos al siguiente segmento sin ensuciar unmatched.
            // Si el fragmento tiene más contenido que el nombre del instrumento («hace lanzamiento con el empeine»), no es una presentación:
            // se trata como descripción del alumno en curso.
            if studentMatches.isEmpty, let introColumn = colResolution.matched,
               Self.extractValueAndUnit(from: trimmedSegment, column: introColumn) == nil,
               Self.extractCompletionScore(from: trimmedSegment) == nil,
               Self.isOnlyInstrumentMention(trimmedSegment, column: introColumn) {
                continue
            }

            if studentMatches.isEmpty {
                if let inherited = lastRememberedStudent, Self.looksLikeContinuationSegment(trimmedSegment) {
                    let action = buildRuleAction(
                        kind: kind,
                        student: inherited,
                        studentMention: inherited.firstName,
                        studentCandidates: [],
                        studentConfidence: 0.85,
                        studentReason: "Sujeto heredado (\(inherited.fullName))",
                        fallbackName: inherited.fullName,
                        segment: trimmedSegment,
                        column: columnToUse,
                        columnCandidates: colResolution.candidates,
                        columnReason: colReason,
                        inheritedScore: isSameEllipsis ? lastRememberedScore : (isNegatedEllipsis ? 0.0 : nil),
                        inheritedIsDelivery: isNegatedEllipsis || (isSameEllipsis && lastRememberedIsDelivery),
                        inheritedAttendance: isSameEllipsis ? lastRememberedAttendanceStatus : nil,
                        inheritedNote: isSameEllipsis ? lastRememberedNote : nil,
                        defaultSelect: true
                    )
                    actions.append(action)
                    updateRememberedActionState(from: action, kind: &lastRememberedKind, score: &lastRememberedScore, isDelivery: &lastRememberedIsDelivery, attendance: &lastRememberedAttendanceStatus, note: &lastRememberedNote, isElliptical: isSameEllipsis)
                } else if let openIndex = openBlockIndex(in: actions),
                          kind == .observation || kind == .quickEvaluation,
                          headerBlockIds.contains(actions[openIndex].id) || Self.startsLowercase(trimmedSegment),
                          (!Self.isNewAttempt(trimmedSegment) || Self.isHeaderOnly(actions[openIndex])),
                          Self.extractHeaderNameCandidate(from: trimmedSegment, roster: input.students, classId: input.classId) == nil {
                    // Descripción sin nombre tras «Noemí.»: pertenece al alumno del bloque abierto.
                    let ownReference = referenceActionId
                        ?? (Self.refersToPreviousAttempt(trimmedSegment) ? actions[..<openIndex].last(where: { $0.studentId != nil && $0.studentId == actions[openIndex].studentId })?.id : nil)
                    actions[openIndex] = mergeIntoBlock(
                        actions[openIndex],
                        segment: trimmedSegment,
                        roster: input.students,
                        columns: rankedColumns,
                        column: columnToUse,
                        columnCandidates: colResolution.candidates,
                        columnReason: colReason,
                        reference: ownReference
                    )
                    updateRememberedActionState(from: actions[openIndex], kind: &lastRememberedKind, score: &lastRememberedScore, isDelivery: &lastRememberedIsDelivery, attendance: &lastRememberedAttendanceStatus, note: &lastRememberedNote, isElliptical: false)
                } else if let candidateName = Self.extractHeaderNameCandidate(from: trimmedSegment, roster: input.students, classId: input.classId) {
                    let fuzzyRes = Self.resolveStudents(mention: candidateName, in: input.students, classId: input.classId)
                    if let matched = fuzzyRes.matched {
                        lastRememberedStudent = matched
                    }
                    let action = buildRuleAction(
                        kind: kind,
                        student: fuzzyRes.matched,
                        studentMention: candidateName,
                        studentCandidates: fuzzyRes.candidates,
                        studentConfidence: fuzzyRes.confidence,
                        studentReason: fuzzyRes.reason,
                        fallbackName: fuzzyRes.matched?.fullName ?? candidateName,
                        segment: trimmedSegment,
                        column: columnToUse,
                        columnCandidates: colResolution.candidates,
                        columnReason: colReason,
                        inheritedScore: isSameEllipsis ? lastRememberedScore : (isNegatedEllipsis ? 0.0 : nil),
                        inheritedIsDelivery: isNegatedEllipsis || (isSameEllipsis && lastRememberedIsDelivery),
                        inheritedAttendance: isSameEllipsis ? lastRememberedAttendanceStatus : nil,
                        inheritedNote: isSameEllipsis ? lastRememberedNote : nil,
                        defaultSelect: fuzzyRes.matched != nil && fuzzyRes.confidence >= 0.75
                    )
                    if Self.opensRollCallBlock(action) || headerBlockIds.count >= 2 { headerBlockIds.insert(action.id) }
                    actions.append(action)
                    updateRememberedActionState(from: action, kind: &lastRememberedKind, score: &lastRememberedScore, isDelivery: &lastRememberedIsDelivery, attendance: &lastRememberedAttendanceStatus, note: &lastRememberedNote, isElliptical: isSameEllipsis)
                } else {
                    unmatched.append(trimmedSegment)
                }
            } else if studentMatches.count == 1,
                      let openIndex = openBlockIndex(in: actions),
                      let openStudentId = actions[openIndex].studentId,
                      let single = studentMatches.first?.matched
                        ?? (studentMatches.first?.candidates.contains { $0.id == openStudentId } == true
                            ? input.students.first { $0.id == openStudentId } : nil),
                      actions[openIndex].studentId == single.id,
                      headerBlockIds.contains(actions[openIndex].id),
                      Self.extractValueAndUnit(from: trimmedSegment, column: columnToUse) == nil,
                      kind == .observation || kind == .quickEvaluation,
                      !Self.isNewAttempt(trimmedSegment) || Self.isHeaderOnly(actions[openIndex]) {
                // «Rocío. Posición… Rocío. posición…»: el mismo alumno seguido es un solo bloque.
                lastRememberedStudent = single
                actions[openIndex] = mergeIntoBlock(
                    actions[openIndex],
                    segment: trimmedSegment,
                    roster: input.students,
                    columns: rankedColumns,
                    column: columnToUse,
                    columnCandidates: colResolution.candidates,
                    columnReason: colReason,
                    reference: referenceActionId
                )
                updateRememberedActionState(from: actions[openIndex], kind: &lastRememberedKind, score: &lastRememberedScore, isDelivery: &lastRememberedIsDelivery, attendance: &lastRememberedAttendanceStatus, note: &lastRememberedNote, isElliptical: false)
            } else {
                if studentMatches.count == 1, let single = studentMatches.first?.matched {
                    lastRememberedStudent = single
                }
                for match in studentMatches {
                    let action = buildRuleAction(
                        kind: kind,
                        student: match.matched,
                        studentMention: match.mention,
                        studentCandidates: match.candidates,
                        studentConfidence: match.confidence,
                        studentReason: match.reason,
                        fallbackName: match.matched?.fullName ?? match.mention,
                        segment: trimmedSegment,
                        column: columnToUse,
                        columnCandidates: colResolution.candidates,
                        columnReason: colReason,
                        inheritedScore: isSameEllipsis ? lastRememberedScore : (isNegatedEllipsis ? 0.0 : nil),
                        inheritedIsDelivery: isNegatedEllipsis || (isSameEllipsis && lastRememberedIsDelivery),
                        inheritedAttendance: isSameEllipsis ? lastRememberedAttendanceStatus : nil,
                        inheritedNote: isSameEllipsis ? lastRememberedNote : nil,
                        defaultSelect: match.matched != nil && match.confidence >= 0.75
                    )
                    var withReference = action
                    if studentMatches.count == 1 {
                        withReference.inheritsCriteriaFromActionId = referenceActionId
                            ?? (Self.refersToPreviousAttempt(trimmedSegment) ? actions.last(where: { $0.studentId != nil && $0.studentId == match.matched?.id })?.id : nil)
                    }
                    if Self.opensRollCallBlock(withReference) || headerBlockIds.count >= 2 { headerBlockIds.insert(withReference.id) }
                    actions.append(withReference)
                    updateRememberedActionState(from: action, kind: &lastRememberedKind, score: &lastRememberedScore, isDelivery: &lastRememberedIsDelivery, attendance: &lastRememberedAttendanceStatus, note: &lastRememberedNote, isElliptical: isSameEllipsis)
                }
            }
        }

        // Un nombre dicho sin descripción («Daniela.» seguido de otro nombre) no es una acción.
        let headerOnly = actions.filter(Self.isHeaderOnly)
        unmatched.append(contentsOf: headerOnly.map { "\($0.studentName): sin descripción" })
        let headerOnlyIds = Set(headerOnly.map(\.id))
        actions.removeAll { headerOnlyIds.contains($0.id) }

        return CourtVoiceCaptureDraft(
            rawTranscript: raw,
            className: input.className,
            actions: actions,
            unmatchedSegments: unmatched,
            confidenceNote: reason,
            appearsToBeRulesFallback: true
        )
    }

    // MARK: - Bloques por alumno (dictado alumno a alumno)

    /// Última acción a la que se le puede seguir añadiendo descripción (evaluación u observación).
    private func openBlockIndex(in actions: [CourtVoiceProposedAction]) -> Int? {
        guard let last = actions.indices.last else { return nil }
        let kind = actions[last].kind
        return (kind == .observation || kind == .quickEvaluation) ? last : nil
    }

    /// Une un fragmento al bloque del alumno y rehace la acción con todo el texto.
    private func mergeIntoBlock(
        _ block: CourtVoiceProposedAction,
        segment: String,
        roster: [CourtVoiceStudentDescriptor],
        columns: [CourtVoiceColumnDescriptor],
        column: CourtVoiceColumnDescriptor?,
        columnCandidates: [CourtVoiceColumnCandidate],
        columnReason: String?,
        reference: String?
    ) -> CourtVoiceProposedAction {
        let base = block.sourceExcerpt.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let combined = base.isEmpty ? segment : "\(base). \(segment)"
        let inferred = inferKind(from: combined, columns: columns, inheritedColumn: column)
        let kind: CourtVoiceActionKind = (block.kind == .quickEvaluation || inferred == .quickEvaluation) ? .quickEvaluation : .observation
        let student = roster.first { $0.id == block.studentId }
        var rebuilt = buildRuleAction(
            kind: kind,
            student: student,
            studentMention: block.studentMention,
            studentCandidates: block.studentCandidates,
            studentConfidence: block.confidence,
            studentReason: block.resolutionReason,
            fallbackName: block.studentName,
            segment: combined,
            column: column,
            columnCandidates: columnCandidates,
            columnReason: columnReason,
            defaultSelect: student != nil && block.confidence >= 0.75
        )
        rebuilt.id = block.id
        rebuilt.inheritsCriteriaFromActionId = block.inheritsCriteriaFromActionId ?? reference
        return rebuilt
    }

    /// «En la rúbrica de saque»: el fragmento no dice nada más que el instrumento.
    static func isOnlyInstrumentMention(_ segment: String, column: CourtVoiceColumnDescriptor) -> Bool {
        let filler: Set<String> = ["para", "ahora", "vamos", "con", "la", "el", "de", "del", "en", "los", "las", "una", "uno", "esta", "este", "evaluamos", "evaluar", "apunta", "pasamos"]
        let columnWords = Set(normalized(column.title).split(whereSeparator: { !$0.isLetter }).map(String.init))
        let residual = normalized(segment)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 && !filler.contains($0) && !columnWords.contains($0) }
        return residual.isEmpty
    }

    /// Acción que solo contiene el nombre del alumno («Noemí.»), a la espera de su descripción.
    static func isHeaderOnly(_ action: CourtVoiceProposedAction) -> Bool {
        guard action.kind == .observation else { return false }
        let nameWords = Set(
            (normalized(action.studentName) + " " + normalized(action.studentMention))
                .split(whereSeparator: { !$0.isLetter }).map(String.init)
        )
        let rest = normalized(action.sourceExcerpt)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 1 && !nameWords.contains($0) }
        return rest.isEmpty
    }

    /// «Noemí.» o «Daniela, segundo tiro…»: el nombre va solo o seguido de coma/punto, como quien pasa lista.
    /// Las frases sin nombre que siguen a ese bloque son del mismo alumno.
    static func opensRollCallBlock(_ action: CourtVoiceProposedAction) -> Bool {
        if isHeaderOnly(action) { return true }
        let excerpt = action.sourceExcerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        for name in [action.studentMention, action.studentName.split(separator: " ").first.map(String.init) ?? ""] where !name.isEmpty {
            guard excerpt.lowercased().hasPrefix(name.lowercased()) else { continue }
            let rest = excerpt.dropFirst(name.count).drop { $0 == " " }
            if rest.first == "," || rest.first == "." { return true }
            // «Marta V. …»: nombre con inicial del apellido.
            if rest.count >= 2, rest.first?.isUppercase == true, rest.dropFirst().first == "." || rest.dropFirst().first == "," { return true }
        }
        return false
    }

    /// El dictado del sistema corta frases en las pausas: un fragmento que empieza en minúscula sigue la frase anterior.
    static func startsLowercase(_ segment: String) -> Bool {
        segment.first(where: { $0.isLetter })?.isLowercase ?? false
    }

    /// «segundo lanzamiento», «otro tiro», «repite»: empieza un intento nuevo del mismo alumno.
    static func isNewAttempt(_ segment: String) -> Bool {
        let norm = normalized(segment)
        let markers = ["segundo", "segunda", "tercer", "tercera", "otro lanzamiento", "otro tiro", "otra vez", "repite"]
        return markers.contains { containsKeyword(norm, keyword: $0) }
    }

    /// «igual que el primero», «en el anterior»: copia lo no dicho del intento anterior del mismo alumno.
    static func refersToPreviousAttempt(_ segment: String) -> Bool {
        let norm = normalized(segment)
        return ["igual que el primero", "igual que el anterior", "en el anterior", "como el primero", "como el anterior", "lo mismo que antes"]
            .contains { norm.contains($0) }
    }

    /// Alumnos citados como comparación («igual que Irene», «como Lucía»), que no son el sujeto.
    static func referencedStudentIds(in segment: String, matches: [StudentResolutionResult]) -> Set<Int64> {
        let norm = normalized(segment)
        var ids = Set<Int64>()
        for match in matches {
            guard let student = match.matched else { continue }
            let mention = normalized(match.mention)
            let first = normalized(student.firstName)
            for prefix in ["igual que ", "como ", "lo mismo que ", "parecido a "] {
                if norm.contains(prefix + mention) || norm.contains(prefix + first) {
                    ids.insert(student.id)
                }
            }
        }
        return ids
    }

    /// Nombre en mayúscula que puede ser un alumno. Una palabra en mayúscula al empezar la frase solo cuenta
    /// si va sola, seguida de coma o punto («Sirena.», «Doemí, lanzamiento…») o si se parece mucho a un alumno;
    /// así «Buen pie de apoyo» o «Tiene apoyo bien» no crean alumnos inventados.
    static func extractHeaderNameCandidate(
        from segment: String,
        roster: [CourtVoiceStudentDescriptor],
        classId: Int64
    ) -> String? {
        guard let candidate = extractCapitalizedNameCandidate(from: segment) else { return nil }
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(separator: " ")
        let isFirstWord = words.first.map { $0.trimmingCharacters(in: .punctuationCharacters) == candidate } ?? false
        if words.count == 1 { return candidate }
        let resolution = resolveStudents(mention: candidate, in: roster, classId: classId)
        let bestConfidence = resolution.candidates.first?.confidence ?? 0
        // En mitad de la frase, una mayúscula que no se parece a nadie de la clase es un error del dictado («… coordinada Lanza bien»).
        guard isFirstWord else { return bestConfidence > 0 ? candidate : nil }
        let firstToken = String(words[0])
        let isVocative = firstToken.hasSuffix(",") || firstToken.hasSuffix(".")
        if isVocative && bestConfidence > 0 { return candidate }
        return bestConfidence >= 0.80 ? candidate : nil
    }

    private func updateRememberedActionState(
        from action: CourtVoiceProposedAction,
        kind: inout CourtVoiceActionKind?,
        score: inout Double?,
        isDelivery: inout Bool,
        attendance: inout String?,
        note: inout String?,
        isElliptical: Bool
    ) {
        kind = action.kind
        if let delivered = action.deliveryRawScore {
            score = delivered
            isDelivery = true
        } else if let s = action.score {
            score = s
            isDelivery = false
        } else if let status = CourtVoiceDeliveryStatus.from(action.formattedScaleValue) {
            // Estado de entrega (columna estructurada): se recuerda como 10/0 para que "también"/"tampoco" lo hereden.
            score = status == .completed ? 10.0 : 0.0
        }
        if let att = action.attendanceStatus {
            attendance = att
        }
        if !isElliptical && !action.note.isEmpty {
            note = action.note
        }
    }

    private func buildRuleAction(
        kind: CourtVoiceActionKind,
        student: CourtVoiceStudentDescriptor?,
        studentMention: String,
        studentCandidates: [CourtVoiceStudentCandidate],
        studentConfidence: Double,
        studentReason: String?,
        fallbackName: String,
        segment: String,
        column: CourtVoiceColumnDescriptor?,
        columnCandidates: [CourtVoiceColumnCandidate],
        columnReason: String?,
        inheritedScore: Double? = nil,
        inheritedIsDelivery: Bool = false,
        inheritedAttendance: String? = nil,
        inheritedNote: String? = nil,
        defaultSelect: Bool
    ) -> CourtVoiceProposedAction {
        var reasons: [String] = []
        if let studentReason, !studentReason.isEmpty {
            reasons.append(studentReason)
        }
        let rawCleanedNote = Self.cleanObservationNote(segment, removingStudentName: student?.fullName ?? fallbackName, studentMention: studentMention)
        let cleanedNote: String
        if let inheritedNote, Self.isEllipticalSamePredicate(segment), rawCleanedNote.count <= 14 {
            cleanedNote = inheritedNote
        } else {
            cleanedNote = rawCleanedNote
        }

        switch kind {
        case .attendance:
            let status = inheritedAttendance ?? Self.normalizeAttendanceStatus(nil, transcriptFragment: segment)
            return CourtVoiceProposedAction(
                isSelected: defaultSelect && student != nil,
                kind: .attendance,
                studentId: student?.id,
                studentName: student?.fullName ?? fallbackName,
                studentMention: studentMention,
                studentCandidates: studentCandidates,
                attendanceStatus: status,
                note: cleanedNote,
                severity: "low",
                sourceExcerpt: segment,
                resolutionReason: reasons.isEmpty ? nil : reasons.joined(separator: " · "),
                confidence: studentConfidence
            )
        case .injury:
            let isRecovery = Self.isInjuryRecovery(in: segment)
            return CourtVoiceProposedAction(
                isSelected: defaultSelect && student != nil,
                kind: .injury,
                studentId: student?.id,
                studentName: student?.fullName ?? fallbackName,
                studentMention: studentMention,
                studentCandidates: studentCandidates,
                note: cleanedNote,
                severity: "medium",
                markInjured: !isRecovery,
                sourceExcerpt: segment,
                resolutionReason: reasons.isEmpty ? nil : reasons.joined(separator: " · "),
                confidence: studentConfidence
            )
        case .quickEvaluation:
            let extracted = Self.extractValueAndUnit(from: segment, column: column)
            let completionScore = Self.extractCompletionScore(from: segment)
            let effectiveRawScore = extracted?.numericValue ?? completionScore ?? inheritedScore
            let isDelivery = extracted == nil && (completionScore != nil || (inheritedScore != nil && inheritedIsDelivery))
            let converted = Self.convertValueForColumn(
                rawScore: effectiveRawScore,
                rawText: segment,
                unit: extracted?.unit,
                column: column,
                isDeliveryStatement: isDelivery
            )
            if let columnReason, !columnReason.isEmpty {
                reasons.append(columnReason)
            } else if column == nil {
                reasons.append("Sin instrumento especificado: elige columna")
            }
            if converted.numericScore == nil && converted.formattedText == nil {
                reasons.append(isDelivery && column?.isLevelScale == true ? "Entregar no es un nivel: elige nivel" : "Sin calificación detectada: indica valor")
            }
            let hasValue = converted.numericScore != nil || converted.formattedText != nil
            let canPreselect = defaultSelect && student != nil && column != nil && hasValue
            return CourtVoiceProposedAction(
                isSelected: canPreselect,
                kind: .quickEvaluation,
                studentId: student?.id,
                studentName: student?.fullName ?? fallbackName,
                studentMention: studentMention,
                studentCandidates: studentCandidates,
                note: cleanedNote,
                severity: "low",
                score: converted.numericScore,
                formattedScaleValue: converted.formattedText,
                rawUnit: converted.unit ?? extracted?.unit,
                deliveryRawScore: isDelivery ? effectiveRawScore : nil,
                columnId: column?.id,
                columnTitle: column?.title,
                columnCandidates: columnCandidates,
                sourceExcerpt: segment,
                resolutionReason: reasons.isEmpty ? nil : reasons.joined(separator: " · "),
                confidence: studentConfidence
            )
        case .observation:
            let lower = Self.normalized(segment)
            let warningKeywords = ["aviso", "interrump", "conflicto", "brusc", "negativ", "no recoge", "mal comportamiento", "distraid"]
            let isWarning = warningKeywords.contains(where: { Self.containsKeyword(lower, keyword: $0, prefixMatch: true) })
            return CourtVoiceProposedAction(
                isSelected: defaultSelect && student != nil,
                kind: .observation,
                studentId: student?.id,
                studentName: student?.fullName ?? fallbackName,
                studentMention: studentMention,
                studentCandidates: studentCandidates,
                note: cleanedNote,
                severity: isWarning ? "medium" : "low",
                sourceExcerpt: segment,
                resolutionReason: reasons.isEmpty ? nil : reasons.joined(separator: " · "),
                confidence: studentConfidence
            )
        }
    }

    // MARK: - Clasificación de Intención con Límites de Palabra y Exclusiones Semánticas

    func inferKind(
        from text: String,
        columns: [CourtVoiceColumnDescriptor] = [],
        inheritedColumn: CourtVoiceColumnDescriptor? = nil
    ) -> CourtVoiceActionKind {
        let lower = Self.normalized(text)

        // 1. Lesiones o estado físico (con límites de palabra para evitar "salta" -> "alta")
        let injuryWords = [
            "lesion", "lesionado", "lesionada", "esguince", "dolor", "molestia",
            "tobillo", "rodilla", "gemelo", "isquio", "isquiotibiales", "hombro",
            "muneca", "vendaje", "escayola", "indispuesto", "indispuesta", "mareo",
            "recuperado", "recuperada", "contractura", "tiron"
        ]
        let injuryPhrases = [
            "no puede correr", "parte medico", "parte medica", "alta medica", "alta de lesion", "retirar lesion", "ya puede hacer"
        ]
        if injuryWords.contains(where: { Self.containsWholeWord(lower, word: $0) }) ||
           injuryPhrases.contains(where: { lower.contains($0) }) {
            return .injury
        }

        // 2. Asistencia / puntualidad / material (evitando falsos positivos como "le falta técnica" o "esta tarde")
        if Self.matchesAttendanceIntent(lower) {
            return .attendance
        }

        // 3. Discriminación entre Evaluación Rápida (instrumento + nota/marca/completitud) y Observación (actitud/convivencia)
        let matchedColumn = Self.findBestMatchingColumn(in: text, columns: columns)?.column ?? inheritedColumn
        let extractedVal = Self.extractValueAndUnit(from: text, column: matchedColumn)
        let completionScore = Self.extractCompletionScore(from: text)

        let pureObservationPhrases = [
            "participativ", "recogiendo", "recoger el material", "ayudando", "ayuda a",
            "buen companero", "excelente companero", "gran companero", "companerismo",
            "fair play", "juego limpio", "juego brusco", "hablando", "distraid",
            "interrumpe", "comportamiento", "motivad", "colabora", "conflicto",
            "pelea", "discute", "aviso por", "amonestacion", "animando al equipo"
        ]
        let hasObservationSignal = pureObservationPhrases.contains(where: { lower.contains($0) })

        let explicitEvalWords = [
            "nota", "ponle", "poner", "califica", "evalua", "rubrica", "autoevaluacion", "coevaluacion",
            "instrumento", "prueba", "test", "examen", "circuito", "control", "baremo", "palier", "marca",
            "completado", "completada", "completo", "entregado", "entregada", "realizado", "realizada", "hecho"
        ]
        let explicitEvalPhrases = [
            "en la columna", "tiene un", "saca un", "sacado un", "le pongo", "apuntale un",
            "ha completado", "la ha completado", "no la ha completado", "no ha completado",
            "ha entregado", "no ha entregado"
        ]
        let hasExplicitEvalVerb = explicitEvalWords.contains(where: { Self.containsWholeWord(lower, word: $0) }) ||
            explicitEvalPhrases.contains(where: { lower.contains($0) })

        if completionScore != nil && (matchedColumn != nil || hasExplicitEvalVerb) {
            return .quickEvaluation
        }

        if let extracted = extractedVal {
            // Si es un dato bruto con unidad física ("8,2 segundos en 50m", "palier 7,5") y hay columna física o palabra de prueba
            if extracted.unit != nil && (matchedColumn != nil || hasExplicitEvalVerb) {
                return .quickEvaluation
            }
            if matchedColumn != nil || hasExplicitEvalVerb {
                return .quickEvaluation
            }
            if !hasObservationSignal && extracted.unit == nil {
                return .quickEvaluation
            }
        }

        if matchedColumn != nil && hasExplicitEvalVerb {
            return .quickEvaluation
        }

        return .observation
    }

    /// Detecta expresiones de completitud/entrega de instrumentos ("ha completado la rúbrica", "no la ha completado", "entregado", "no entregado").
    static func extractCompletionScore(from text: String) -> Double? {
        let lower = normalized(text)
        let negativePhrases = [
            "no la ha completado", "no lo ha completado", "no ha completado", "sin completar",
            "no completado", "no completada", "no ha entregado", "no la ha entregado", "sin entregar",
            "no entregado", "no entregada", "no la ha hecho", "no lo ha hecho", "pendiente de completar"
        ]
        if negativePhrases.contains(where: { lower.contains($0) }) {
            return 0.0
        }
        let positivePhrases = [
            "ha completado", "la ha completado", "lo ha completado", "completado la", "completada la",
            "ha entregado", "la ha entregado", "lo ha entregado", "ha rellenado", "ha realizado la"
        ]
        if positivePhrases.contains(where: { lower.contains($0) }) {
            return 10.0
        }
        return nil
    }

    /// Estado de entrega para columnas estructuradas. Prioriza la frase dictada ("ha completado" / "no la ha completado");
    /// si no la hay, solo acepta el 10/0 que hereda una elipsis ("también", "tampoco"). Cualquier otra nota queda sin valor.
    static func deliveryStatus(rawScore: Double?, rawText: String) -> CourtVoiceDeliveryStatus? {
        if let completion = extractCompletionScore(from: rawText) {
            return completion >= 5.0 ? .completed : .pending
        }
        switch rawScore {
        case 10.0?: return .completed
        case 0.0?: return .pending
        default: return nil
        }
    }

    /// Detecta si un segmento es una continuación elíptica afirmativa que repite la acción anterior para un nuevo alumno ("Ignacio Alemán también", "Emma Ambel igual", "y José Bautista también").
    static func isEllipticalSamePredicate(_ text: String) -> Bool {
        let lower = normalized(text)
        if extractCompletionScore(from: text) != nil || extractValueAndUnit(from: text) != nil {
            return false
        }
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        return words.contains("tambien") || words.contains("igual") || lower.hasSuffix("lo mismo")
    }

    /// Detecta si un segmento niega el predicado anterior para un nuevo alumno ("Nerea Cardo tampoco", "Nerea Cardo no", "Nerea Cardo no la ha completado").
    static func isEllipticalNegatedPredicate(_ text: String) -> Bool {
        let lower = normalized(text)
        if extractCompletionScore(from: text) == 0.0 {
            return true
        }
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        return words.contains("tampoco") || words.last == "no"
    }

    static func matchesAttendanceIntent(_ lower: String) -> Bool {
        let materialPhrases = [
            "sin material", "sin ropa", "sin zapatillas", "olvido el chandal", "no trajo ropa", "no trae ropa", "viene sin material"
        ]
        if materialPhrases.contains(where: { lower.contains($0) }) {
            return true
        }

        let unambiguousWords = ["retraso", "ausente", "justificado", "justificada", "exento", "exenta", "presente"]
        if unambiguousWords.contains(where: { containsWholeWord(lower, word: $0) }) {
            return true
        }

        let unambiguousPhrases = ["no ha venido", "no vino", "ha faltado", "minutos tarde", "min tarde", "llega tarde", "llegan tarde", "llego tarde", "llegaron tarde"]
        if unambiguousPhrases.contains(where: { lower.contains($0) }) {
            return true
        }

        // "tarde" solo es asistencia si no va precedido de "esta tarde", "por la tarde", "mas tarde"
        if containsWholeWord(lower, word: "tarde") {
            let nonAttendanceTarde = ["esta tarde", "por la tarde", "mas tarde", "de la tarde"]
            if !nonAttendanceTarde.contains(where: { lower.contains($0) }) {
                return true
            }
        }

        // "falta" solo es asistencia si significa ausencia ("tiene falta", "ponle falta", "falta hoy"), NUNCA en "le falta técnica/fuerza/ritmo" o "hace falta"
        if containsWholeWord(lower, word: "falta") {
            let nonAttendanceFalta = [
                "le falta", "les falta", "hace falta", "falta de ", "falta tecnica",
                "falta fuerza", "falta ritmo", "falta precision", "falta intensidad", "falta control"
            ]
            if !nonAttendanceFalta.contains(where: { lower.contains($0) }) {
                return true
            }
        }

        return false
    }

    static func isInjuryRecovery(in segment: String) -> Bool {
        let lower = normalized(segment)
        if containsWholeWord(lower, word: "recuperado") || containsWholeWord(lower, word: "recuperada") {
            return true
        }
        let recoveryPhrases = ["alta medica", "alta de lesion", "dado de alta", "dada de alta", "tiene el alta", "retirar lesion", "ya puede"]
        return recoveryPhrases.contains(where: { lower.contains($0) })
    }

    // MARK: - Segmentación Inteligente (Comas, Conectores, Pausas y Elipsis "X también")

    static func splitIntoSegments(
        _ text: String,
        roster: [CourtVoiceStudentDescriptor] = [],
        classId: Int64 = 0
    ) -> [String] {
        // Protegemos decimales con coma ("8,5") antes de inspeccionar comas separadoras
        let decimalProtected = text.replacingOccurrences(
            of: "(\\d),(\\d)",
            with: "$1.__DEC__$2",
            options: .regularExpression
        )

        // IMPORTANTE:
        // - Cortar ANTES de conectores continuativos ("además", "luego", "después"), pero
        // - En el caso de "también" / "tampoco" pospuesto tras un alumno ("Ignacio Alemán también Emma Ambel también"),
        //   el corte va DESPUÉS de "también" / "tampoco" si no iba precedido de punto/coma.
        let connectorReplaced = decimalProtected
            .replacingOccurrences(of: "\n", with: ";")
            .replacingOccurrences(of: ". ", with: ";")
            .replacingOccurrences(of: " por otro lado ", with: ";", options: .caseInsensitive)
            .replacingOccurrences(of: " además ", with: "; además ", options: .caseInsensitive)
            .replacingOccurrences(of: " luego ", with: "; luego ", options: .caseInsensitive)
            .replacingOccurrences(of: " después ", with: "; después ", options: .caseInsensitive)
            .replacingOccurrences(
                of: "(?i)\\b(tambi[eé]n|tampoco)\\b(?=\\s+[\\p{Lu}])",
                with: "$1;",
                options: .regularExpression
            )

        let primaryChunks = connectorReplaced
            .split(separator: ";")
            .map { String($0).replacingOccurrences(of: ".__DEC__", with: ",").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var finalSegments: [String] = []
        for chunk in primaryChunks {
            let subChunks = splitCommaSeparatedClauseIfIndependent(chunk, roster: roster, classId: classId)
            for sub in subChunks {
                finalSegments.append(contentsOf: splitRunOnStudentClauses(sub, roster: roster, classId: classId))
            }
        }
        return finalSegments
    }

    /// Si un bloque sin puntuación contiene una cláusula cerrada ("... ha completado la rúbrica de autoevaluación Ignacio Alemán también ...")
    /// o "... también Nerea Cardo no la ha completado", divide justo antes del siguiente nombre de alumno cuando la primera parte ya tiene verbo/predicado propio.
    private static func splitRunOnStudentClauses(
        _ chunk: String,
        roster: [CourtVoiceStudentDescriptor],
        classId: Int64
    ) -> [String] {
        let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Cortar tras "también" o "tampoco" cuando va seguido de cualquier alumno de la clase (incluso en minúsculas) o de otro predicado
        let afterTambienPattern = "(?i)\\b(tambi[eé]n|tampoco)\\b\\s+(?=[\\p{L}]{3,})"
        if let regex = try? NSRegularExpression(pattern: afterTambienPattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let fullRange = Range(match.range, in: trimmed),
           let wordRange = Range(match.range(at: 1), in: trimmed) {
            let prefixPart = String(trimmed[..<wordRange.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let suffixPart = String(trimmed[fullRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Solo cortamos si prefixPart ya nombra a un alumno (p. ej. "Ignacio Alemán también") y no empieza por "también"
            let prefixNorm = normalized(prefixPart)
            if !prefixNorm.hasPrefix("tambien") && !prefixNorm.hasPrefix("tampoco") && !suffixPart.isEmpty {
                var pieces: [String] = [prefixPart]
                pieces.append(contentsOf: splitRunOnStudentClauses(suffixPart, roster: roster, classId: classId))
                return pieces
            }
        }

        // Si el segmento tiene varios alumnos de la lista NO unidos por "y" / "e" / "ni", y entre ellos ya hay un predicado ("ha completado la rúbrica de autoevaluación Ignacio Alemán..."),
        // separamos antes del segundo alumno.
        guard !roster.isEmpty else { return [trimmed] }
        let norm = normalized(trimmed)
        var studentSpans: [(student: CourtVoiceStudentDescriptor, range: Range<String.Index>)] = []
        for student in roster.sorted(by: { $0.fullName.count > $1.fullName.count }) {
            let normFull = normalized(student.fullName)
            guard normFull.count >= 4 else { continue }
            let pattern = "(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: normFull))(?![\\p{L}\\p{N}])"
            if let r = Self.cachedRegexRange(pattern, in: norm) {
                if !studentSpans.contains(where: { $0.range.overlaps(r) }) {
                    studentSpans.append((student, r))
                }
            }
        }
        studentSpans.sort { $0.range.lowerBound < $1.range.lowerBound }
        if studentSpans.count >= 2 {
            let firstSpan = studentSpans[0]
            let secondSpan = studentSpans[1]
            let between = String(norm[firstSpan.range.upperBound..<secondSpan.range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if between != "y" && between != "e" && between != "ni" && between != "," && between.count >= 4 {
                // Convertimos el índice de `norm` a posición aproximada por palabras en `trimmed`
                let fullNamePattern = "(?i)(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: secondSpan.student.fullName))(?![\\p{L}\\p{N}])"
                if let origRange = trimmed.range(of: fullNamePattern, options: [.regularExpression, .diacriticInsensitive, .caseInsensitive]) {
                    let firstPart = String(trimmed[..<origRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let restPart = String(trimmed[origRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !firstPart.isEmpty && !restPart.isEmpty {
                        return [firstPart] + splitRunOnStudentClauses(restPart, roster: roster, classId: classId)
                    }
                }
            }
        }

        return [trimmed]
    }

    /// Divide por comas cuando una sub-cláusula después de la coma tiene su propio predicado/acción o su propio alumno + valor
    /// Ej.: "Lucía un 8, Marcos un 7, Elena notable" -> 3 segmentos independientes.
    /// Ej.: "Sofía y Mateo llegan tarde, Hugo muy participativo" -> 2 segmentos independientes.
    /// Ej.: "Ferran ha completado la rúbrica, Ignacio también, Emma también" -> 3 segmentos independientes.
    /// Pero conserva enumeraciones conjuntivas: "Sofía, Mateo y Hugo llegan tarde" -> 1 solo segmento.
    private static func splitCommaSeparatedClauseIfIndependent(
        _ chunk: String,
        roster: [CourtVoiceStudentDescriptor],
        classId: Int64
    ) -> [String] {
        let protectedChunk = chunk.replacingOccurrences(
            of: "(\\d),(\\d)",
            with: "$1.__DEC__$2",
            options: .regularExpression
        )
        let parts = protectedChunk
            .split(separator: ",")
            .map { String($0).replacingOccurrences(of: ".__DEC__", with: ",").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard parts.count > 1 else { return [chunk] }

        // Una cláusula es autónoma si contiene una nota/valor, una palabra clave de acción, una elipsis ("también"/"tampoco") o un verbo/predicado
        func hasOwnPredicate(_ part: String) -> Bool {
            let norm = normalized(part)
            if extractValueAndUnit(from: part) != nil { return true }
            if extractCompletionScore(from: part) != nil { return true }
            if isEllipticalSamePredicate(part) || isEllipticalNegatedPredicate(part) { return true }
            if matchesAttendanceIntent(norm) { return true }
            let predicateHints = [
                "tarde", "retraso", "ausente", "falta", "material", "lesion", "esguince",
                "dolor", "molestia", "tobillo", "rodilla", "participativ", "recog", "ayud",
                "hablando", "distraid", "aviso", "buen", "excelente", "muy ", "viene", "llega",
                "tiene", "saca", "ponle", "nota", "completad", "entregad", "autoevaluacion", "rubrica"
            ]
            return predicateHints.contains(where: { norm.contains($0) })
        }

        var result: [String] = []
        var accumulator = parts[0]

        for idx in 1..<parts.count {
            let nextPart = parts[idx]
            let accHasPredicate = hasOwnPredicate(accumulator)
            let nextHasStudentOrCap = !findAllStudentMentions(in: nextPart, roster: roster, classId: classId).isEmpty ||
                extractCapitalizedNameCandidate(from: nextPart) != nil
            let nextHasPredicate = hasOwnPredicate(nextPart)

            if accHasPredicate && nextHasStudentOrCap && nextHasPredicate {
                result.append(accumulator)
                accumulator = nextPart
            } else {
                accumulator += ", " + nextPart
            }
        }
        result.append(accumulator)
        return result
    }

    static func looksLikeContinuationSegment(_ segment: String) -> Bool {
        let norm = normalized(segment)
        let starters = ["ademas", "tambien", "luego", "despues", "y tambien", "y ademas", "ayudo", "estuvo", "participo", "recogio"]
        return starters.contains(where: { norm.hasPrefix($0) })
    }

    // MARK: - Normalización Fonética del Español y Fuzzy Matching (Jaro-Winkler)

    nonisolated static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .lowercased()
    }

    /// Normalización fonética española para tolerar errores típicos de STT ("Isan" -> "Izan", "Ugo" -> "Hugo", "Bictor" -> "Víctor", "Yago"/"Llago").
    nonisolated static func spanishPhoneticKey(_ text: String) -> String {
        var s = normalized(text)
        s = s.replacingOccurrences(of: "h", with: "")
        s = s.replacingOccurrences(of: "v", with: "b")
        s = s.replacingOccurrences(of: "ll", with: "y")
        s = s.replacingOccurrences(of: "z", with: "s")
        s = s.replacingOccurrences(of: "ce", with: "se")
        s = s.replacingOccurrences(of: "ci", with: "si")
        s = s.replacingOccurrences(of: "ge", with: "je")
        s = s.replacingOccurrences(of: "gi", with: "ji")
        s = s.replacingOccurrences(of: "qu", with: "k")
        s = s.replacingOccurrences(of: "ca", with: "ka")
        s = s.replacingOccurrences(of: "co", with: "ko")
        s = s.replacingOccurrences(of: "cu", with: "ku")
        s = s.replacingOccurrences(of: "tx", with: "ch")
        s = s.replacingOccurrences(of: "x", with: "s")
        return s
    }

    /// Las mismas expresiones se buscan cientos de veces en un dictado largo; compilarlas una sola vez
    /// baja el análisis de 9 minutos de audio de varios segundos a menos de uno.
    private static var regexCache: [String: NSRegularExpression] = [:]

    static func cachedRegexRange(_ pattern: String, in text: String) -> Range<String.Index>? {
        let regex: NSRegularExpression
        if let cached = regexCache[pattern] {
            regex = cached
        } else {
            guard let compiled = try? NSRegularExpression(pattern: pattern) else { return nil }
            if regexCache.count > 2_000 { regexCache.removeAll(keepingCapacity: true) }
            regexCache[pattern] = compiled
            regex = compiled
        }
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return Range(match.range, in: text)
    }

    static func containsWholeWord(_ normalizedText: String, word: String) -> Bool {
        let normWord = normalized(word)
        guard !normWord.isEmpty else { return false }
        let pattern = "(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: normWord))(?![\\p{L}\\p{N}])"
        return Self.cachedRegexRange(pattern, in: normalizedText) != nil
    }

    static func containsKeyword(_ normalizedText: String, keyword: String, prefixMatch: Bool = false) -> Bool {
        let normKey = normalized(keyword)
        guard !normKey.isEmpty else { return false }
        let suffix = prefixMatch ? "[\\p{L}]*" : ""
        let pattern = "(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: normKey))\(suffix)(?![\\p{L}\\p{N}])"
        return Self.cachedRegexRange(pattern, in: normalizedText) != nil
    }

    nonisolated static func jaroWinklerSimilarity(_ s1: String, _ s2: String) -> Double {
        let a = Array(s1)
        let b = Array(s2)
        if a == b { return 1.0 }
        if a.isEmpty || b.isEmpty { return 0.0 }

        let matchDistance = max(0, max(a.count, b.count) / 2 - 1)
        var aMatches = Array(repeating: false, count: a.count)
        var bMatches = Array(repeating: false, count: b.count)

        var matches = 0.0
        for i in 0..<a.count {
            let start = max(0, i - matchDistance)
            let end = min(i + matchDistance + 1, b.count)
            guard start < end else { continue }
            for j in start..<end {
                if bMatches[j] || a[i] != b[j] { continue }
                aMatches[i] = true
                bMatches[j] = true
                matches += 1
                break
            }
        }
        if matches == 0 { return 0.0 }

        var t = 0.0
        var k = 0
        for i in 0..<a.count where aMatches[i] {
            while !bMatches[k] { k += 1 }
            if a[i] != b[k] { t += 1 }
            k += 1
        }
        let transpositions = t / 2.0
        let jaro = ((matches / Double(a.count)) + (matches / Double(b.count)) + ((matches - transpositions) / matches)) / 3.0

        var prefix = 0
        for i in 0..<min(4, min(a.count, b.count)) {
            if a[i] == b[i] { prefix += 1 } else { break }
        }
        return jaro + Double(prefix) * 0.1 * (1.0 - jaro)
    }

    // MARK: - Resolutor de Alumnos con Confianza, Apellidos, Nombres Compuestos y Desambiguación

    struct StudentResolutionResult {
        let mention: String
        let matched: CourtVoiceStudentDescriptor?
        let candidates: [CourtVoiceStudentCandidate]
        let confidence: Double
        let reason: String?
    }

    static func resolveStudents(
        mention: String,
        in roster: [CourtVoiceStudentDescriptor],
        classId: Int64 = 0
    ) -> StudentResolutionResult {
        let trimmedMention = mention.trimmingCharacters(in: .whitespacesAndNewlines)
        let normQuery = normalized(trimmedMention)
        guard !normQuery.isEmpty, !roster.isEmpty else {
            return StudentResolutionResult(mention: trimmedMention, matched: nil, candidates: [], confidence: 0.0, reason: nil)
        }

        // 1. Alias aprendido en esta clase
        let learnedAliases = CourtVoiceAliasStore.studentAliases(forClassId: classId)
        if let aliasedId = learnedAliases[normQuery],
           let student = roster.first(where: { $0.id == aliasedId }) {
            let candidate = CourtVoiceStudentCandidate(id: student.id, fullName: student.fullName, confidence: 0.98, matchReason: "\(trimmedMention) → \(student.fullName) (alias aprendido)")
            return StudentResolutionResult(mention: trimmedMention, matched: student, candidates: [candidate], confidence: 0.98, reason: candidate.matchReason)
        }

        let queryPhonetic = spanishPhoneticKey(normQuery)
        var scoredCandidates: [CourtVoiceStudentCandidate] = []

        for student in roster {
            let normFull = normalized(student.fullName)
            let normFirst = normalized(student.firstName)
            let normLast = normalized(student.lastName)
            let lastTokens = normLast.split(separator: " ").map(String.init).filter { $0.count >= 2 }
            let studentAliases = student.aliases.map(normalized)

            var bestScore: Double = 0.0
            var bestReason: String = ""

            if normFull == normQuery {
                bestScore = 1.0
                bestReason = "Nombre completo exacto"
            } else if studentAliases.contains(normQuery) {
                bestScore = 0.97
                bestReason = "\(trimmedMention) → \(student.fullName) (apodo)"
            } else if normFirst == normQuery {
                bestScore = 0.94
                bestReason = "Nombre exacto"
            } else if !normLast.isEmpty && (normLast == normQuery || lastTokens.contains(normQuery)) {
                bestScore = 0.92
                bestReason = "Apellido (\(student.lastName))"
            } else if normQuery.count >= 3 && normFirst.hasPrefix(normQuery + " ") {
                // Caso "María" frente a "María José": menor puntuación que un "María" exacto para no confundirlos
                bestScore = 0.82
                bestReason = "Nombre compuesto parcial (\(student.firstName))"
            } else if spanishPhoneticKey(normFull) == queryPhonetic || spanishPhoneticKey(normFirst) == queryPhonetic || lastTokens.contains(where: { spanishPhoneticKey($0) == queryPhonetic }) {
                bestScore = 0.89
                bestReason = "\(trimmedMention) → \(student.fullName) (fonético)"
            } else {
                let firstSim = jaroWinklerSimilarity(normFirst, normQuery)
                let phoneticFirstSim = jaroWinklerSimilarity(spanishPhoneticKey(normFirst), queryPhonetic)
                let lastSim = lastTokens.map { max(jaroWinklerSimilarity($0, normQuery), jaroWinklerSimilarity(spanishPhoneticKey($0), queryPhonetic)) }.max() ?? 0.0
                let fullSim = jaroWinklerSimilarity(normFull, normQuery)
                let maxSim = max(max(firstSim, phoneticFirstSim), max(lastSim, fullSim))
                if maxSim >= 0.84 {
                    bestScore = maxSim * 0.90
                    bestReason = "\(trimmedMention) ≈ \(student.fullName) (similitud)"
                }
            }

            if bestScore >= 0.72 {
                scoredCandidates.append(
                    CourtVoiceStudentCandidate(
                        id: student.id,
                        fullName: student.fullName,
                        confidence: bestScore,
                        matchReason: bestReason
                    )
                )
            }
        }

        scoredCandidates.sort { lhs, rhs in
            if abs(lhs.confidence - rhs.confidence) > 0.001 {
                return lhs.confidence > rhs.confidence
            }
            return lhs.fullName < rhs.fullName
        }

        let topCandidates = Array(scoredCandidates.prefix(3))
        guard let best = topCandidates.first else {
            return StudentResolutionResult(mention: trimmedMention, matched: nil, candidates: [], confidence: 0.0, reason: nil)
        }

        // Comprobar ambigüedad: si hay dos candidatos con confianza muy similar (p. ej. dos "Lucía" en la misma clase),
        // NO se preselecciona ninguno automáticamente; se devuelve `matched: nil` y los top 3 candidatos para elegir con 1 toque.
        if topCandidates.count >= 2 {
            let second = topCandidates[1]
            if abs(best.confidence - second.confidence) < 0.04 {
                let names = topCandidates.map(\.fullName).joined(separator: " / ")
                return StudentResolutionResult(
                    mention: trimmedMention,
                    matched: nil,
                    candidates: topCandidates,
                    confidence: 0.45,
                    reason: "Ambigüedad entre \(names): confirma el alumno"
                )
            }
        }

        let matchedStudent = roster.first(where: { $0.id == best.id })
        return StudentResolutionResult(
            mention: trimmedMention,
            matched: matchedStudent,
            candidates: topCandidates,
            confidence: best.confidence,
            reason: best.matchReason
        )
    }

    /// Detecta todas las menciones de alumnos en un segmento (por nombre completo, nombre compuesto, nombre de pila, apellido o fonética).
    /// Si un nombre es ambiguo (ej. dos "Lucía"), devuelve una única entrada desmarcada con ambos candidatos en lugar de duplicar acciones seleccionadas.
    static func findAllStudentMentions(
        in segment: String,
        roster: [CourtVoiceStudentDescriptor],
        classId: Int64 = 0
    ) -> [StudentResolutionResult] {
        guard !roster.isEmpty else { return [] }
        let normSegment = normalized(segment)
        var consumedRanges: [Range<String.Index>] = []
        var results: [StudentResolutionResult] = []
        var matchedStudentIds: Set<Int64> = []

        func overlapsConsumed(_ range: Range<String.Index>) -> Bool {
            consumedRanges.contains { $0.overlaps(range) }
        }

        // 1. Alias aprendidos de la clase
        let learnedAliases = CourtVoiceAliasStore.studentAliases(forClassId: classId)
        for (alias, studentId) in learnedAliases.sorted(by: { $0.key.count > $1.key.count }) {
            let pattern = "(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: alias))(?![\\p{L}\\p{N}])"
            if let range = Self.cachedRegexRange(pattern, in: normSegment),
               !overlapsConsumed(range),
               let student = roster.first(where: { $0.id == studentId }) {
                consumedRanges.append(range)
                matchedStudentIds.insert(student.id)
                let cand = CourtVoiceStudentCandidate(id: student.id, fullName: student.fullName, confidence: 0.98, matchReason: "\(alias) → \(student.fullName) (alias aprendido)")
                results.append(StudentResolutionResult(mention: alias, matched: student, candidates: [cand], confidence: 0.98, reason: cand.matchReason))
            }
        }

        // 2. Nombres completos exactos (ordenados de más largo a más corto para priorizar "María José García" sobre "María")
        for student in roster.sorted(by: { $0.fullName.count > $1.fullName.count }) {
            let normFull = normalized(student.fullName)
            guard normFull.count >= 3 else { continue }
            let pattern = "(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: normFull))(?![\\p{L}\\p{N}])"
            if let range = Self.cachedRegexRange(pattern, in: normSegment), !overlapsConsumed(range) {
                consumedRanges.append(range)
                matchedStudentIds.insert(student.id)
                let cand = CourtVoiceStudentCandidate(id: student.id, fullName: student.fullName, confidence: 1.0, matchReason: "Nombre completo")
                results.append(StudentResolutionResult(mention: student.fullName, matched: student, candidates: [cand], confidence: 1.0, reason: "Nombre completo"))
            }
        }

        // 3. Nombres de pila compuestos (ej. "María José") antes que simples ("María")
        let sortedFirstNames = Set(roster.map { normalized($0.firstName) })
            .filter { $0.count >= 3 }
            .sorted { $0.count > $1.count }

        for normFirst in sortedFirstNames {
            let pattern = "(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: normFirst))(?![\\p{L}\\p{N}])"
            guard let range = Self.cachedRegexRange(pattern, in: normSegment), !overlapsConsumed(range) else {
                continue
            }
            consumedRanges.append(range)
            var resolution = resolveStudents(mention: normFirst, in: roster, classId: classId)
            if resolution.matched == nil,
               let byInitial = resolveBySurnameInitial(firstName: normFirst, in: segment, roster: roster) {
                resolution = byInitial
            }
            if let m = resolution.matched {
                if !matchedStudentIds.contains(m.id) {
                    matchedStudentIds.insert(m.id)
                    results.append(resolution)
                }
            } else if !resolution.candidates.isEmpty {
                results.append(resolution)
            }
        }

        // 4. Primer token de nombre de pila o apellidos si aún no se consumió
        var tokenCandidates: Set<String> = []
        for student in roster {
            let firstTokens = normalized(student.firstName).split(separator: " ").map(String.init).filter { $0.count >= 3 }
            if let first = firstTokens.first { tokenCandidates.insert(first) }
            let lastTokens = normalized(student.lastName).split(separator: " ").map(String.init).filter { $0.count >= 3 }
            for lt in lastTokens { tokenCandidates.insert(lt) }
        }

        for token in tokenCandidates.sorted(by: { $0.count > $1.count }) {
            let pattern = "(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: token))(?![\\p{L}\\p{N}])"
            guard let range = Self.cachedRegexRange(pattern, in: normSegment), !overlapsConsumed(range) else {
                continue
            }
            consumedRanges.append(range)
            let resolution = resolveStudents(mention: token, in: roster, classId: classId)
            if let m = resolution.matched {
                if !matchedStudentIds.contains(m.id) {
                    matchedStudentIds.insert(m.id)
                    results.append(resolution)
                }
            } else if !resolution.candidates.isEmpty {
                results.append(resolution)
            }
        }

        // 5. Si no se encontró ningún nombre exacto pero hay un candidato en mayúscula con fonética similar ("Isan", "Ugo", "Bictor")
        if results.isEmpty, let capCandidate = extractHeaderNameCandidate(from: segment, roster: roster, classId: classId) {
            let resolution = resolveStudents(mention: capCandidate, in: roster, classId: classId)
            if resolution.matched != nil || !resolution.candidates.isEmpty {
                results.append(resolution)
            }
        }

        return results
    }

    /// «Marta V.», «Marta B,»: la inicial del apellido (en mayúscula, tras el nombre) desambigua entre alumnos con el mismo nombre.
    static func resolveBySurnameInitial(
        firstName normFirst: String,
        in segment: String,
        roster: [CourtVoiceStudentDescriptor]
    ) -> StudentResolutionResult? {
        let sameName = roster.filter { normalized($0.firstName) == normFirst }
        guard sameName.count >= 2 else { return nil }
        let folded = segment.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "es_ES"))
        let pattern = "(?i:\(NSRegularExpression.escapedPattern(for: normFirst)))\\s+(\\p{Lu})(?![\\p{L}])"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: folded, range: NSRange(folded.startIndex..., in: folded)),
              let initialRange = Range(match.range(at: 1), in: folded) else { return nil }
        let initial = normalized(String(folded[initialRange]))
        let hits = sameName.filter { normalized($0.lastName).hasPrefix(initial) }
        guard hits.count == 1, let student = hits.first else { return nil }
        let reason = "Inicial del apellido (\(initial.uppercased()).) → \(student.fullName)"
        let candidate = CourtVoiceStudentCandidate(id: student.id, fullName: student.fullName, confidence: 0.93, matchReason: reason)
        return StudentResolutionResult(mention: "\(student.firstName) \(initial.uppercased()).", matched: student, candidates: [candidate], confidence: 0.93, reason: reason)
    }

    static func findAllStudents(in segment: String, roster: [CourtVoiceStudentDescriptor]) -> [CourtVoiceStudentDescriptor] {
        findAllStudentMentions(in: segment, roster: roster).compactMap(\.matched)
    }

    static func matchStudent(named query: String, in roster: [CourtVoiceStudentDescriptor]) -> CourtVoiceStudentDescriptor? {
        resolveStudents(mention: query, in: roster).matched
    }

    // MARK: - Resolutor y Ranking Contextual de Columnas / Instrumentos

    struct ColumnResolutionResult {
        let matched: CourtVoiceColumnDescriptor?
        let candidates: [CourtVoiceColumnCandidate]
        let confidence: Double
        let reason: String?
    }

    static func rankRelevantColumns(
        _ columns: [CourtVoiceColumnDescriptor],
        sessionTitle: String? = nil,
        activeTabId: String? = nil,
        referenceDate: Date = .now
    ) -> [CourtVoiceColumnDescriptor] {
        let valid = columns.filter(\.isEvaluableCandidate)
        let normSession = normalized(sessionTitle ?? "")
        let refMs = Int64(referenceDate.timeIntervalSince1970 * 1000)

        return valid.sorted { lhs, rhs in
            let scoreL = relevanceScore(for: lhs, normSession: normSession, activeTabId: activeTabId, refMs: refMs)
            let scoreR = relevanceScore(for: rhs, normSession: normSession, activeTabId: activeTabId, refMs: refMs)
            if scoreL != scoreR { return scoreL > scoreR }
            return lhs.id < rhs.id
        }
    }

    private static func relevanceScore(
        for col: CourtVoiceColumnDescriptor,
        normSession: String,
        activeTabId: String?,
        refMs: Int64
    ) -> Int {
        var score = 0
        if let activeTabId, !activeTabId.isEmpty, col.tabIds.contains(activeTabId) {
            score += 30
        }
        if !normSession.isEmpty {
            let normUnit = normalized(col.unitOrSituation ?? "")
            let normTitle = normalized(col.title)
            if !normUnit.isEmpty && (normSession.contains(normUnit) || normUnit.contains(normSession)) {
                score += 50
            } else {
                let sessionTokens = normSession.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 4 }
                if sessionTokens.contains(where: { normTitle.contains($0) || normUnit.contains($0) }) {
                    score += 35
                }
            }
        }
        if let colMs = col.dateEpochMs {
            let daysDiff = abs(Double(refMs - colMs)) / (1000.0 * 60.0 * 60.0 * 24.0)
            if daysDiff <= 1.5 {
                score += 25
            } else if daysDiff <= 7.0 {
                score += 12
            }
        }
        return score
    }

    static func resolveColumn(
        mention: String?,
        segmentText: String,
        columns: [CourtVoiceColumnDescriptor],
        classId: Int64 = 0
    ) -> ColumnResolutionResult {
        let validColumns = columns.filter(\.isEvaluableCandidate)
        guard !validColumns.isEmpty else {
            return ColumnResolutionResult(matched: nil, candidates: [], confidence: 0.0, reason: nil)
        }

        // 1. Comprobar alias aprendidos por clase
        let learnedAliases = CourtVoiceAliasStore.columnAliases(forClassId: classId)
        let combinedSearch = normalized("\(mention ?? "") \(segmentText)").trimmingCharacters(in: .whitespacesAndNewlines)
        for (alias, colId) in learnedAliases.sorted(by: { $0.key.count > $1.key.count }) {
            if containsKeyword(combinedSearch, keyword: alias),
               let col = validColumns.first(where: { $0.id == colId }) {
                let reason = "\(alias) → \(col.title) (alias aprendido)"
                let cand = CourtVoiceColumnCandidate(id: col.id, title: col.title, confidence: 0.98, matchReason: reason)
                return ColumnResolutionResult(matched: col, candidates: [cand], confidence: 0.98, reason: reason)
            }
        }

        // 2. Buscar mención explícita o sinónimo
        if let hint = mention, !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let match = findBestMatchingColumn(in: hint, columns: validColumns) {
            return ColumnResolutionResult(matched: match.column, candidates: match.candidates, confidence: match.confidence, reason: match.reason)
        }

        if let match = findBestMatchingColumn(in: segmentText, columns: validColumns) {
            return ColumnResolutionResult(matched: match.column, candidates: match.candidates, confidence: match.confidence, reason: match.reason)
        }

        // Si no se reconoce ninguna columna, NO inventamos la primera columna: devolvemos `matched: nil` y las 3 columnas más relevantes como sugerencias.
        let topFallback = validColumns.prefix(3).map {
            CourtVoiceColumnCandidate(id: $0.id, title: $0.title, confidence: 0.35, matchReason: "Sugerencia de la sesión")
        }
        return ColumnResolutionResult(matched: nil, candidates: Array(topFallback), confidence: 0.0, reason: nil)
    }

    static func findBestMatchingColumn(
        in text: String,
        columns: [CourtVoiceColumnDescriptor]
    ) -> (column: CourtVoiceColumnDescriptor, confidence: Double, reason: String, candidates: [CourtVoiceColumnCandidate])? {
        let validColumns = columns.filter(\.isEvaluableCandidate)
        guard !validColumns.isEmpty else { return nil }
        let normText = normalized(text)
        guard !normText.isEmpty else { return nil }

        let peSynonyms: [String: [String]] = [
            "resistencia": ["course navette", "navette", "cooper", "aerobica", "aguante", "carrera continua", "resistencia", "palier"],
            "velocidad": ["sprint", "50 metros", "50 m", "50m", "rapidez", "velocidad", "relevos"],
            "fuerza": ["abdominales", "flexiones", "lanzamiento", "balon medicinal", "salto horizontal", "fuerza", "plancha"],
            "flexibilidad": ["estiramientos", "cajon", "wells", "elasticidad", "flexibilidad"],
            "golpeo": ["toque de dedos", "antebrazos", "remate", "drive", "reves", "volea", "golpeo", "raqueta", "pala"],
            "saque": ["servicio", "saque mano baja", "saque"],
            "bote": ["dribbling", "control de balon", "conduccion", "bote", "manejo"],
            "pase": ["pases", "recepcion", "combinacion", "pase"],
            "tiro": ["lanzamiento a canasta", "entrada a canasta", "porteria", "chut", "tiro"],
            "tactica": ["posicionamiento", "desmarque", "juego colectivo", "tactica", "situacion de juego"],
            "tecnica": ["ejecucion", "gesto tecnico", "coordina", "tecnica"],
            "actitud": ["esfuerzo", "participacion", "convivencia", "habitos", "autonomia"]
        ]

        let stopWords: Set<String> = ["de", "la", "el", "los", "las", "en", "con", "del", "por", "para", "una", "uno", "test", "prueba", "rubrica", "evaluacion"]

        var scored: [(col: CourtVoiceColumnDescriptor, score: Int, reason: String)] = []

        for col in validColumns {
            let normTitle = normalized(col.title)
            guard !normTitle.isEmpty else { continue }

            var score = 0
            var matchedReason = ""

            if normText.contains(normTitle) {
                score += 100
                matchedReason = "\(col.title) (coincidencia exacta)"
            }

            let titleTokens = normTitle
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count >= 3 && !stopWords.contains($0) }

            for token in titleTokens {
                if containsWholeWord(normText, word: token) {
                    score += 40
                    if matchedReason.isEmpty { matchedReason = "\(token) → \(col.title)" }
                } else if token.count >= 5 {
                    let stem = String(token.prefix(5))
                    if containsKeyword(normText, keyword: stem, prefixMatch: true) {
                        score += 22
                        if matchedReason.isEmpty { matchedReason = "\(token) → \(col.title)" }
                    }
                }

                for (key, synonyms) in peSynonyms {
                    if token.contains(key) || key.contains(token) {
                        if let matchedSyn = synonyms.first(where: { containsKeyword(normText, keyword: $0) }) {
                            score += 30
                            if matchedReason.isEmpty { matchedReason = "\(matchedSyn) → \(col.title) (sinónimo)" }
                        }
                    }
                }
            }

            if score >= 22 {
                scored.append((col, score, matchedReason.isEmpty ? col.title : matchedReason))
            }
        }

        scored.sort { $0.score > $1.score }
        guard let best = scored.first else { return nil }
        let candidates = scored.prefix(3).map {
            CourtVoiceColumnCandidate(
                id: $0.col.id,
                title: $0.col.title,
                confidence: min(1.0, Double($0.score) / 100.0),
                matchReason: $0.reason
            )
        }
        return (best.col, min(1.0, Double(best.score) / 100.0), best.reason, Array(candidates))
    }

    static func matchColumn(named hint: String?, in columns: [CourtVoiceColumnDescriptor]) -> CourtVoiceColumnDescriptor? {
        guard let hint, !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return findBestMatchingColumn(in: hint, columns: columns)?.column
    }

    static func normalizeAttendanceStatus(_ raw: String?, transcriptFragment: String) -> String {
        if let raw {
            let upper = raw.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if AttendanceStatusOption.all.contains(where: { $0.id == upper }) {
                return upper
            }
        }
        let lower = normalized(transcriptFragment)
        if lower.contains("sin material") || lower.contains("sin ropa") || lower.contains("zapatillas") || lower.contains("chandal") || lower.contains("no trajo") || lower.contains("no trae") {
            return "SIN_MATERIAL"
        }
        if containsKeyword(lower, keyword: "exent", prefixMatch: true) {
            return "EXENTO"
        }
        if containsKeyword(lower, keyword: "justificad", prefixMatch: true) || containsWholeWord(lower, word: "medico") {
            return "JUSTIFICADO"
        }
        if containsWholeWord(lower, word: "tarde") || containsWholeWord(lower, word: "retraso") || lower.contains("minutos tarde") || lower.contains("min tarde") {
            return "TARDE"
        }
        if containsWholeWord(lower, word: "presente") || lower.contains("ha llegado") {
            return "PRESENTE"
        }
        return "AUSENTE"
    }

    // MARK: - Extracción de Calificaciones, Escalas Ordinales y Marcas Físicas Brutas

    struct ExtractedValueResult {
        let numericValue: Double
        let unit: String?
        let descriptiveTerm: String?
    }

    /// Extrae tanto calificaciones (0-10) como marcas de pruebas físicas ("8,2 segundos", "palier 7,5", "35 abdominales", "2,15 metros").
    /// Evita falsos positivos como "grupos de 4", "5 minutos tarde", "excelente compañero" o "10 abdominales" cuando no se evalúa fuerza/repeticiones.
    static func extractValueAndUnit(
        from segment: String,
        column: CourtVoiceColumnDescriptor? = nil
    ) -> ExtractedValueResult? {
        let lower = normalized(segment)

        // Si es claramente un retraso de asistencia ("5 minutos tarde"), no hay nota
        if matchesAttendanceIntent(lower) && (lower.contains("minut") || lower.contains("tarde") || lower.contains("retraso")) {
            return nil
        }

        // Excluir expresiones organizativas ("grupos de 4", "equipos de 5", "parejas de 2", "3 series de 10")
        let nonScoreRanges = [
            "(?:grupos?|equipos?|parejas?|filas?|estaciones?|postura|series?|rondas?)\\s+de\\s+\\d+"
        ]
        var cleanedForScore = lower
        for pattern in nonScoreRanges {
            cleanedForScore = cleanedForScore.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        // 1. Marcas de pruebas físicas con unidades explícitas: segundos, metros, centímetros, palier, repeticiones
        let physicalPatterns: [(pattern: String, unit: String)] = [
            ("\\b(\\d+(?:[.,]\\d+)?)\\s*(?:segundos?|seg|s)\\b", "s"),
            ("\\b(?:palier|periodo)\\s*(\\d+(?:[.,]\\d+)?)\\b", "palier"),
            ("\\b(\\d+(?:[.,]\\d+)?)\\s*(?:metros?|m|centimetros?|cm)\\b", "m"),
            ("\\b(\\d+)\\s*(?:repeticiones?|rep|abdominales?|flexiones?)\\b", "rep")
        ]
        for (pattern, unit) in physicalPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: cleanedForScore, range: NSRange(cleanedForScore.startIndex..., in: cleanedForScore)),
               let range = Range(match.range(at: 1), in: cleanedForScore) {
                let numStr = String(cleanedForScore[range]).replacingOccurrences(of: ",", with: ".")
                if let val = Double(numStr) {
                    // Si es "10 abdominales" o "15 flexiones", solo lo tratamos como marca evaluable si la columna es física/repeticiones o hay verbo explícito de evaluar/registrar
                    if unit == "rep" {
                        let isPhysicalCol = column?.scaleKind.isRawPhysicalMark == true ||
                            normalized(column?.title ?? "").contains("fuerza") ||
                            normalized(column?.title ?? "").contains("abdominal") ||
                            normalized(column?.title ?? "").contains("flexion") ||
                            normalized(column?.title ?? "").contains("test") ||
                            normalized(column?.title ?? "").contains("prueba")
                        let hasExplicitRecordVerb = ["ponle", "apunta", "registra", "marca", "hizo", "ha hecho", "consigue", "logra", "en el test", "en la prueba"].contains(where: { cleanedForScore.contains($0) })
                        if !isPhysicalCol && !hasExplicitRecordVerb {
                            return nil
                        }
                    }
                    return ExtractedValueResult(numericValue: val, unit: unit, descriptiveTerm: nil)
                }
            }
        }

        // 2. Fracciones habladas en español: "ocho y medio", "7 y medio", "seis con cinco", "ocho coma cinco"
        let numberWordsMap: [String: Double] = [
            "diez": 10.0, "nueve": 9.0, "ocho": 8.0, "siete": 7.0,
            "seis": 6.0, "cinco": 5.0, "cuatro": 4.0, "tres": 3.0, "dos": 2.0, "uno": 1.0,
            "10": 10.0, "9": 9.0, "8": 8.0, "7": 7.0, "6": 6.0, "5": 5.0, "4": 4.0, "3": 3.0
        ]
        for (word, base) in numberWordsMap where base < 10.0 {
            if cleanedForScore.contains("\(word) y medio") || cleanedForScore.contains("\(word) con cinco") || cleanedForScore.contains("\(word) coma cinco") {
                return ExtractedValueResult(numericValue: base + 0.5, unit: nil, descriptiveTerm: nil)
            }
        }

        // 3. Números con decimales explícitos en dígitos: "8,5" o "8.5"
        let decimalPattern = "(?<![\\p{L}\\p{N}])(10(?:[.,]0)?|[0-9][.,][0-9]{1,2})(?![\\p{L}\\p{N}])"
        if let regex = try? NSRegularExpression(pattern: decimalPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: cleanedForScore, range: NSRange(cleanedForScore.startIndex..., in: cleanedForScore)),
           let range = Range(match.range(at: 1), in: cleanedForScore) {
            let numberString = String(cleanedForScore[range]).replacingOccurrences(of: ",", with: ".")
            if let val = Double(numberString), val >= 0 && val <= 10 {
                return ExtractedValueResult(numericValue: val, unit: nil, descriptiveTerm: nil)
            }
        }

        // 4. Números hablados con palabra precedidos de contexto de nota
        let wordNumbers: [(String, Double)] = [
            ("un diez", 10.0), ("nota diez", 10.0),
            ("un nueve", 9.0), ("nota nueve", 9.0),
            ("un ocho", 8.0), ("nota ocho", 8.0),
            ("un siete", 7.0), ("nota siete", 7.0),
            ("un seis", 6.0), ("nota seis", 6.0),
            ("un cinco", 5.0), ("nota cinco", 5.0),
            ("un cuatro", 4.0), ("nota cuatro", 4.0),
            ("un tres", 3.0), ("nota tres", 3.0),
            ("un dos", 2.0), ("nota dos", 2.0),
            ("un uno", 1.0), ("nota uno", 1.0)
        ]
        for (word, value) in wordNumbers where containsKeyword(cleanedForScore, keyword: word) {
            return ExtractedValueResult(numericValue: value, unit: nil, descriptiveTerm: nil)
        }

        // 5. Patrón con contexto verbal o de nota (sin "de" suelto para no capturar "grupos de 4"):
        // "ponle un 8", "nota 7", "tiene un 9", "saca 8", "un 7", "Lucía 8"
        let contextPattern = "(?:\\bnota|\\bponle|\\bponer|\\ble pongo|\\btiene un|\\bsaca un|\\bsaca|\\bsacado un|\\bapuntale un|\\bapuntale|\\bun|\\bcalificacion)\\s*(?:un\\s*)?(10|[0-9])(?![.,\\p{L}\\p{N}])"
        if let regex = try? NSRegularExpression(pattern: contextPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: cleanedForScore, range: NSRange(cleanedForScore.startIndex..., in: cleanedForScore)),
           let range = Range(match.range(at: 1), in: cleanedForScore),
           let val = Double(cleanedForScore[range]), val >= 0 && val <= 10 {
            return ExtractedValueResult(numericValue: val, unit: nil, descriptiveTerm: nil)
        }

        // 6. Niveles descriptivos LOMLOE / Rúbricas (evitando adjetivos seguidos de sustantivo conductual como "excelente compañero/actitud")
        let descriptiveExcludeNouns = ["companero", "companera", "actitud", "comportamiento", "esfuerzo", "trabajo en equipo", "persona", "gesto", "ayuda"]
        let isBehavioralAdjective = descriptiveExcludeNouns.contains { noun in
            cleanedForScore.contains("excelente \(noun)") ||
            cleanedForScore.contains("notable \(noun)") ||
            cleanedForScore.contains("buen \(noun)") ||
            cleanedForScore.contains("buena \(noun)")
        }
        if !isBehavioralAdjective {
            if containsWholeWord(cleanedForScore, word: "sobresaliente") || containsWholeWord(cleanedForScore, word: "excelente") || containsKeyword(cleanedForScore, keyword: "nivel 4") {
                return ExtractedValueResult(numericValue: 9.5, unit: nil, descriptiveTerm: "sobresaliente")
            }
            if containsWholeWord(cleanedForScore, word: "notable") || containsWholeWord(cleanedForScore, word: "avanzado") || containsKeyword(cleanedForScore, keyword: "nivel 3") {
                return ExtractedValueResult(numericValue: 8.0, unit: nil, descriptiveTerm: "notable")
            }
            if containsWholeWord(cleanedForScore, word: "suficiente") || containsKeyword(cleanedForScore, keyword: "en proceso") || containsKeyword(cleanedForScore, keyword: "nivel 2") {
                return ExtractedValueResult(numericValue: 6.0, unit: nil, descriptiveTerm: "suficiente")
            }
            if containsWholeWord(cleanedForScore, word: "insuficiente") || containsWholeWord(cleanedForScore, word: "inicial") || containsKeyword(cleanedForScore, keyword: "nivel 1") || containsWholeWord(cleanedForScore, word: "suspenso") {
                return ExtractedValueResult(numericValue: 4.0, unit: nil, descriptiveTerm: "insuficiente")
            }
        }

        return nil
    }

    static func extractScore(from segment: String) -> Double? {
        guard let res = extractValueAndUnit(from: segment), res.unit == nil else { return nil }
        return res.numericValue
    }

    /// Adapta el valor extraído a la escala real de la columna (`FOUR_LEVEL`, `ORDINAL`, `LETTER_ABCD`, `YES_NO`, `PERCENTAGE`, `TIME`, `DISTANCE`, `REPETITIONS` o `TEN_POINT`).
    static func convertValueForColumn(
        rawScore: Double?,
        rawText: String,
        unit: String?,
        column: CourtVoiceColumnDescriptor?,
        isDeliveryStatement: Bool = false
    ) -> (numericScore: Double?, formattedText: String?, unit: String?) {
        guard let column else {
            return (rawScore, nil, unit)
        }

        // Instrumento estructurado: solo estado de entrega. Nunca se convierte a escala ni se inventa nota.
        if column.isStructuredInstrument {
            return (nil, deliveryStatus(rawScore: rawScore, rawText: rawText)?.rawValue, nil)
        }

        // Columna de niveles: "ha entregado" no es un 4 ni "no ha entregado" un 1. Queda sin valor para revisión.
        if isDeliveryStatement && column.isLevelScale {
            return (nil, nil, nil)
        }

        let normText = normalized(rawText)

        // Si la columna es de tipo ORDINAL y tiene niveles configurados (`ordinalLevels`)
        if column.columnType.uppercased() == "ORDINAL" || !column.ordinalLevels.isEmpty {
            let levels = column.ordinalLevels
            if !levels.isEmpty {
                // 1. ¿Mencionó directamente alguno de los niveles?
                if let direct = levels.first(where: { containsKeyword(normText, keyword: $0) }) {
                    return (rawScore, direct, nil)
                }
                // 2. Convertir nota 0-10 al nivel ordinal correspondiente según umbrales pedagógicos
                if let score = rawScore {
                    let firstNorm = normalized(levels.first ?? "")
                    let descending = firstNorm.contains("excel") || firstNorm.contains("sobresal") || firstNorm.contains("avanz") || firstNorm.contains("lograd") || firstNorm == "4" || firstNorm == "a"
                    let idx: Int
                    if levels.count == 4 {
                        let tier: Int // 0 = más bajo (<5), 1 = suficiente (5..6.4), 2 = bien/notable (6.5..8.4), 3 = excelente (>=8.5)
                        if score >= 8.5 { tier = 3 }
                        else if score >= 6.5 { tier = 2 }
                        else if score >= 5.0 { tier = 1 }
                        else { tier = 0 }
                        idx = descending ? (3 - tier) : tier
                    } else {
                        let normalizedRatio = min(1.0, max(0.0, score / 10.0))
                        if descending {
                            idx = Int(((1.0 - normalizedRatio) * Double(levels.count - 1)).rounded(.down))
                        } else {
                            idx = Int((normalizedRatio * Double(levels.count - 1)).rounded(.down))
                        }
                    }
                    let clampedIdx = min(levels.count - 1, max(0, idx))
                    return (score, levels[clampedIdx], nil)
                }
            }
        }

        switch column.scaleKind {
        case .fourLevel:
            guard let score = rawScore else { return (nil, nil, nil) }
            let levelScore: Double
            if score <= 4.0 && (normText.contains("nivel") || score == 1 || score == 2 || score == 3 || score == 4) {
                levelScore = max(1.0, min(4.0, score.rounded()))
            } else if score >= 8.5 {
                levelScore = 4.0
            } else if score >= 6.5 {
                levelScore = 3.0
            } else if score >= 5.0 {
                levelScore = 2.0
            } else {
                levelScore = 1.0
            }
            return (levelScore, String(Int(levelScore)), nil)

        case .letterABCD:
            if let score = rawScore {
                let letter: String
                if score >= 8.5 { letter = "A" }
                else if score >= 6.5 { letter = "B" }
                else if score >= 5.0 { letter = "C" }
                else { letter = "D" }
                return (score, letter, nil)
            }
            return (nil, nil, nil)

        case .yesNo:
            if containsWholeWord(normText, word: "si") || containsWholeWord(normText, word: "logrado") || containsWholeWord(normText, word: "apto") || (rawScore ?? 0) >= 5.0 {
                return (10.0, "true", nil)
            } else if containsWholeWord(normText, word: "no") || (rawScore != nil && (rawScore ?? 0) < 5.0) {
                return (0.0, "false", nil)
            }
            return (nil, nil, nil)

        case .percentage:
            guard let score = rawScore else { return (nil, nil, nil) }
            let pct = score <= 10.0 ? score * 10.0 : min(100.0, max(0.0, score))
            return (pct, String(format: "%.0f", pct), "%")

        case .time:
            return (rawScore, nil, unit ?? "s")

        case .distance:
            return (rawScore, nil, unit ?? "m")

        case .repetitions:
            return (rawScore, nil, unit ?? "rep")

        case .achievement, .tenPoint, .custom:
            if let score = rawScore {
                let clamped = min(10.0, max(0.0, score))
                return (clamped, nil, unit)
            }
            return (nil, nil, unit)
        }
    }

    static func extractCapitalizedNameCandidate(from segment: String) -> String? {
        let stopWords: Set<String> = [
            "Hoy", "En", "El", "La", "Los", "Las", "Un", "Una", "Ponle", "Nota",
            "Marcar", "Apunta", "Aviso", "Falta", "Retraso", "Lesión", "Lesion", "Muy", "Bien",
            "Rubrica", "Rúbrica", "Prueba", "Test", "Circuito", "Saque", "Golpeo", "Resistencia",
            "Además", "Ademas", "También", "Tambien", "Luego", "Después", "Despues", "Excelente",
            "Notable", "Suficiente", "Insuficiente", "Sobresaliente", "Grupos", "Equipos", "Esta", "Este"
        ]
        let words = segment.split(separator: " ").map {
            $0.trimmingCharacters(in: CharacterSet.punctuationCharacters)
        }
        for word in words where word.count >= 3 {
            guard let first = word.first, first.isUppercase, !stopWords.contains(word) else { continue }
            return word
        }
        return nil
    }

    static func cleanObservationNote(_ segment: String, removingStudentName name: String, studentMention: String = "") -> String {
        var cleaned = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstToken = name.split(separator: " ").first.map(String.init) ?? name
        let candidatesToRemove = [name, studentMention, firstToken].filter { !$0.isEmpty }
        for cand in candidatesToRemove {
            if cleaned.lowercased().hasPrefix(cand.lowercased()) {
                cleaned = String(cleaned.dropFirst(cand.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,:-·"))
                break
            }
        }
        guard !cleaned.isEmpty else { return segment }
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }
}

// MARK: - Servicio de Captura de Voz en Vivo (iOS + macOS) con contextualStrings y On-Device

@MainActor
final class CourtVoiceLiveRecognizer: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribingFile = false
    @Published var importedFileName: String?
    @Published var importedFileCreationDate: Date?
    @Published var transcript = ""
    @Published var statusMessage: String?

    /// Vocabulario contextual de la clase activa (nombres, apellidos, alias, títulos de columnas) para mejorar el STT.
    var contextualStrings: [String] = []

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func updateContextualVocabulary(
        students: [CourtVoiceStudentDescriptor],
        columns: [CourtVoiceColumnDescriptor],
        classId: Int64,
        extraPhrases: [String] = []
    ) {
        var phrases: Set<String> = Set(extraPhrases)
        for s in students {
            phrases.insert(s.fullName)
            phrases.insert(s.firstName)
            if !s.lastName.isEmpty { phrases.insert(s.lastName) }
            s.aliases.forEach { phrases.insert($0) }
        }
        for c in columns {
            phrases.insert(c.title)
        }
        for alias in CourtVoiceAliasStore.studentAliases(forClassId: classId).keys {
            phrases.insert(alias)
        }
        for alias in CourtVoiceAliasStore.columnAliases(forClassId: classId).keys {
            phrases.insert(alias)
        }
        phrases.formUnion(["Course Navette", "palier", "bádminton", "rúbrica", "fair play", "sin material", "esguince"])
        phrases.formUnion(CourtVoiceDictationCorrections.vocabulary)
        // Apple recomienda no pasar de ~100 frases; si sobran, se descartan las más largas.
        contextualStrings = Array(phrases.filter { !$0.isEmpty }.sorted { $0.count < $1.count }.prefix(100))
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        statusMessage = nil
        importedFileName = nil
        importedFileCreationDate = nil
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            Task { @MainActor in
                guard let self else { return }
                guard authStatus == .authorized else {
                    self.statusMessage = "Activa el permiso de Reconocimiento de Voz en Ajustes para dictar desde la pista."
                    return
                }
                self.beginSession()
            }
        }
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        isTranscribingFile = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// Transcribe un archivo de audio pregrabado (.m4a, .wav, .mp3, .caf) y extrae su fecha de creación original.
    func transcribeAudioFile(url: URL) async -> String? {
        if isRecording {
            stopRecording()
        }
        recognitionTask?.cancel()
        recognitionTask = nil
        statusMessage = nil

        let authStatus = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard authStatus == .authorized else {
            statusMessage = "Activa el permiso de Reconocimiento de Voz en Ajustes para transcribir notas de voz."
            return nil
        }

        guard let recognizer, recognizer.isAvailable else {
            statusMessage = "El reconocedor de voz en español no está disponible ahora mismo."
            return nil
        }

        guard recognizer.supportsOnDeviceRecognition else {
            statusMessage = "Para garantizar privacidad 100% local (sin enviar audio ni nombres de alumnos a servidores externos), descarga el modelo de dictado sin conexión en español desde Ajustes del sistema."
            return nil
        }

        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let creationDate = (attrs[.creationDate] as? Date) ?? (attrs[.modificationDate] as? Date) {
            importedFileCreationDate = creationDate
        } else {
            importedFileCreationDate = nil
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("court-voice-\(UUID().uuidString)-\(url.lastPathComponent)")
        do {
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            try FileManager.default.copyItem(at: url, to: tempURL)
        } catch {
            statusMessage = "No se pudo leer el archivo de audio seleccionado."
            return nil
        }
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        importedFileName = url.lastPathComponent
        isTranscribingFile = true
        transcript = ""

        let request = SFSpeechURLRecognitionRequest(url: tempURL)
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = contextualStrings
        if #available(iOS 17.0, macOS 14.0, *) {
            request.addsPunctuation = true
        }

        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            var hasResumed = false
            var committedUtterances: [String] = []
            var currentUtterance: String = ""

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else {
                        if !hasResumed {
                            hasResumed = true
                            continuation.resume(returning: nil)
                        }
                        return
                    }

                    if let result {
                        let newText = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !newText.isEmpty {
                            Self.mergeUtteranceUpdate(
                                newText: newText,
                                currentUtterance: &currentUtterance,
                                committedUtterances: &committedUtterances
                            )
                            let fullTranscript = Self.joinUtterances(committed: committedUtterances, current: currentUtterance)
                            self.transcript = fullTranscript
                        }

                        if result.isFinal && !hasResumed {
                            hasResumed = true
                            self.isTranscribingFile = false
                            self.recognitionTask = nil
                            let finalTranscript = Self.joinUtterances(committed: committedUtterances, current: currentUtterance)
                            self.transcript = finalTranscript
                            continuation.resume(returning: finalTranscript)
                        }
                    }

                    if let error, !hasResumed {
                        hasResumed = true
                        self.isTranscribingFile = false
                        self.recognitionTask = nil
                        let finalTranscript = Self.joinUtterances(committed: committedUtterances, current: currentUtterance)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !finalTranscript.isEmpty {
                            self.transcript = finalTranscript
                            continuation.resume(returning: finalTranscript)
                        } else {
                            self.statusMessage = "No se pudo transcribir el audio en local (\(error.localizedDescription))."
                            continuation.resume(returning: nil)
                        }
                    }
                }
            }
        }
    }

    private func beginSession() {
        guard let recognizer, recognizer.isAvailable else {
            statusMessage = "El reconocedor de voz en español no está disponible ahora mismo. Puedes escribir en el cuadro de texto."
            return
        }

        guard recognizer.supportsOnDeviceRecognition else {
            statusMessage = "Para garantizar privacidad 100% local (sin enviar audio ni nombres de alumnos a servidores externos), descarga el modelo de dictado sin conexión en español desde Ajustes del sistema."
            return
        }

        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            statusMessage = "No se pudo activar el micrófono del dispositivo."
            return
        }
        #endif

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = contextualStrings
        if #available(iOS 17.0, macOS 14.0, *) {
            request.addsPunctuation = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            statusMessage = "No se pudo iniciar la captura de audio."
            recognitionRequest = nil
            return
        }

        var committedUtterances: [String] = []
        var currentUtterance: String = ""

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let newText = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !newText.isEmpty {
                        Self.mergeUtteranceUpdate(
                            newText: newText,
                            currentUtterance: &currentUtterance,
                            committedUtterances: &committedUtterances
                        )
                        self.transcript = Self.joinUtterances(committed: committedUtterances, current: currentUtterance)
                    }
                }
                if error != nil && self.isRecording {
                    self.stopRecording()
                }
            }
        }
    }

    /// En `requiresOnDeviceRecognition = true`, cuando el hablante hace una pausa (~0.8s), `SFSpeechRecognizer` reinicia
    /// `bestTranscription.formattedString` desde 0 con la nueva frase en lugar de acumular todo el archivo.
    /// Este método detecta cuándo `newText` es un nuevo enunciado tras una pausa y preserva los enunciados anteriores en `committedUtterances`.
    nonisolated static func mergeUtteranceUpdate(
        newText: String,
        currentUtterance: inout String,
        committedUtterances: inout [String]
    ) {
        let trimmedNew = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNew.isEmpty else { return }

        guard !currentUtterance.isEmpty else {
            currentUtterance = trimmedNew
            return
        }

        let normCurrent = AppleFoundationCourtVoiceService.normalized(currentUtterance)
        let normNew = AppleFoundationCourtVoiceService.normalized(trimmedNew)

        // Si es extensión de la frase actual o refinamiento del mismo comienzo, reemplazamos `currentUtterance`
        if normNew.hasPrefix(normCurrent) || normCurrent.hasPrefix(normNew) {
            // Pero cuidado: si `currentUtterance` ya tenía una frase larga (>= 12 caracteres) y `trimmedNew` empieza desde 1 palabra corta que casualmente no comparte el primer token, no entraría aquí.
            currentUtterance = trimmedNew
            return
        }

        let currentFirstToken = normCurrent.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).first.map(String.init) ?? ""
        let newFirstToken = normNew.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).first.map(String.init) ?? ""

        // Si comparten la primera palabra (o muy similar fonéticamente), es una revisión de la misma frase en curso
        if !currentFirstToken.isEmpty && !newFirstToken.isEmpty {
            if currentFirstToken == newFirstToken ||
               AppleFoundationCourtVoiceService.spanishPhoneticKey(currentFirstToken) == AppleFoundationCourtVoiceService.spanishPhoneticKey(newFirstToken) ||
               AppleFoundationCourtVoiceService.jaroWinklerSimilarity(currentFirstToken, newFirstToken) >= 0.82 {
                currentUtterance = trimmedNew
                return
            }
        }

        // Si `newText` ya contiene toda la frase anterior al principio (con pequeñas variaciones de puntuación), actualizamos
        let currentWords = normCurrent.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let newWords = normNew.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if currentWords.count >= 2 && newWords.count >= currentWords.count {
            let prefixOverlap = zip(currentWords.prefix(2), newWords.prefix(2)).filter { $0 == $1 }.count
            if prefixOverlap >= 1 {
                currentUtterance = trimmedNew
                return
            }
        }

        // En caso contrario, el reconocedor on-device ha reiniciado el buffer tras una pausa de voz:
        // consolidamos `currentUtterance` y empezamos el nuevo tramo con `trimmedNew`.
        committedUtterances.append(currentUtterance)
        currentUtterance = trimmedNew
    }

    nonisolated static func joinUtterances(committed: [String], current: String) -> String {
        var all = committed.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let trimmedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCurrent.isEmpty {
            all.append(trimmedCurrent)
        }
        guard !all.isEmpty else { return "" }
        return all.enumerated().map { idx, piece in
            let clean = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            if idx < all.count - 1, let last = clean.last, !".;:!?,".contains(last) {
                return clean + "."
            }
            return clean
        }.joined(separator: " ")
    }
}

// MARK: - Generable Schemas (FoundationModels)

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
enum GeneratedCourtVoiceActionKind: String, CaseIterable {
    case attendance
    case observation
    case quickEvaluation
    case injury
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedCourtVoiceAction {
    @Guide(description: "Tipo de acción: 'attendance', 'observation', 'quickEvaluation' o 'injury'")
    let kind: GeneratedCourtVoiceActionKind

    @Guide(description: "Nombre, apellido o apodo del alumno mencionado")
    let studentName: String

    @Guide(description: "Solo si kind es 'attendance': 'PRESENTE', 'AUSENTE', 'TARDE', 'JUSTIFICADO', 'SIN_MATERIAL' o 'EXENTO'")
    let attendanceStatus: String?

    @Guide(description: "Nota limpia y concisa explicando la observación, motivo del retraso, lesión o criterio evaluado")
    let note: String

    @Guide(description: "Severidad si es observación o incidencia: 'low', 'medium' o 'high'")
    let severity: String

    @Guide(description: "Solo si kind es 'quickEvaluation' y se ha dicho una nota o marca numérica explícita; nil si no se menciona nota")
    let score: Double?

    @Guide(description: "Solo si kind es 'quickEvaluation': nombre o pista de la columna o instrumento evaluado; nil si no se menciona ninguno")
    let columnHint: String?

    @Guide(description: "Solo si kind es 'injury': true para marcar lesionado/indispuesto, false si ya se ha recuperado")
    let markInjured: Bool?

    @Guide(description: "Fragmento breve literal del dictado del profesor de donde sale esta acción")
    let sourceExcerpt: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedCourtVoiceCaptureDraft {
    let actions: [GeneratedCourtVoiceAction]
    let unmatchedSegments: [String]
}
#endif

