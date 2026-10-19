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
        !isLocked && !isHiddenOrArchived && columnType.uppercased() != "CALCULATED"
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
    /// Para `.quickEvaluation`: identificador de columna del cuaderno (`nil` si no se reconoció instrumento).
    var columnId: String?
    var columnTitle: String?
    var columnMention: String?
    var columnCandidates: [CourtVoiceColumnCandidate]
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
            let hasValue = score != nil || !(formattedScaleValue?.isEmpty ?? true)
            return hasValue && columnId != nil
        }
        return true
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
                // Creamos una sesión limpia por análisis para no acumular historial de otras clases ni agotar los ~4K tokens.
                let session = makeFreshSession()
                let response = try await session.respond(
                    to: buildPrompt(from: input),
                    generating: GeneratedCourtVoiceCaptureDraft.self,
                    includeSchemaInPrompt: true,
                    options: AppleFoundationModelSupport.generationOptions(temperature: 0.1)
                )
                let resolvedActions = mapGeneratedActions(response.content.actions, input: input)
                if resolvedActions.isEmpty && !deterministic.actions.isEmpty {
                    return deterministic
                }
                return CourtVoiceCaptureDraft(
                    rawTranscript: trimmed,
                    className: input.className,
                    actions: resolvedActions,
                    unmatchedSegments: response.content.unmatchedSegments,
                    confidenceNote: "Acciones extraídas con Apple Intelligence on-device. Revisa antes de confirmar.",
                    appearsToBeRulesFallback: false
                )
            } catch {
                AppleFoundationModelSupport.recordRuntimeFailure(error)
                return deterministic
            }
        }
        #endif

        return deterministic
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
               - `quickEvaluation`: SOLO cuando el profesor expresa intención de CALIFICAR o registrar una marca/nota/nivel en un instrumento. Si no se dice ninguna nota ni marca, deja `score` en `nil` (nunca inventes un 7.5). Si no se menciona ningún instrumento, deja `columnHint` en `nil`.
               - `observation`: actitud, comportamiento, fair play, participación, esfuerzo, recogida de material, conflictos o anécdotas de sesión SIN pedir una calificación numérica ni nombrar una columna evaluable con nota. Ejemplo: "excelente compañero animando al equipo" es `observation`.
            3. Si una frase o lista separada por comas menciona a varios alumnos ("Lucía un 8, Marcos un 7, Elena notable" o "Sofía y Mateo llegan tarde"), genera una acción independiente por cada alumno con su propio valor.
            4. Si una segunda frase continúa hablando del mismo alumno sin repetir su nombre ("Lucía un 8. Además ayudó a recoger"), mantén a ese alumno como sujeto.
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

            let resolvedKind: CourtVoiceActionKind
            let rawKindStr = item.kind.rawValue
            if let parsed = CourtVoiceActionKind(rawValue: rawKindStr) {
                if parsed == .quickEvaluation && item.score == nil && extractedVal == nil && colResolution.matched == nil {
                    resolvedKind = inferKind(from: "\(item.note) \(item.sourceExcerpt)", columns: rankedColumns)
                } else if parsed == .observation && (item.score != nil || (extractedVal != nil && colResolution.matched != nil)) {
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

            let rawScore = item.score ?? extractedVal?.numericValue
            let converted = Self.convertValueForColumn(
                rawScore: rawScore,
                rawText: "\(item.note) \(item.sourceExcerpt)",
                unit: extractedVal?.unit,
                column: targetColumn
            )
            if resolvedKind == .quickEvaluation && converted.numericScore == nil && converted.formattedText == nil {
                reasons.append("Sin calificación detectada: indica nota")
            }

            let normalizedStatus = Self.normalizeAttendanceStatus(item.attendanceStatus, transcriptFragment: "\(item.note) \(item.sourceExcerpt)")
            let isReady = effectiveStudent != nil && (resolvedKind != .quickEvaluation || (targetColumn != nil && (converted.numericScore != nil || converted.formattedText != nil)))

            return CourtVoiceProposedAction(
                isSelected: isReady && studentRes.confidence >= 0.75,
                kind: resolvedKind,
                studentId: effectiveStudent?.id,
                studentName: effectiveStudent?.fullName ?? (item.studentName.isEmpty ? "Alumno por confirmar" : item.studentName),
                studentMention: item.studentName,
                studentCandidates: studentCandidates,
                attendanceStatus: resolvedKind == .attendance ? normalizedStatus : nil,
                note: item.note,
                severity: item.severity,
                score: resolvedKind == .quickEvaluation ? converted.numericScore : nil,
                formattedScaleValue: resolvedKind == .quickEvaluation ? converted.formattedText : nil,
                rawUnit: resolvedKind == .quickEvaluation ? (converted.unit ?? extractedVal?.unit) : nil,
                columnId: resolvedKind == .quickEvaluation ? targetColumn?.id : nil,
                columnTitle: resolvedKind == .quickEvaluation ? targetColumn?.title : nil,
                columnMention: item.columnHint,
                columnCandidates: colResolution.candidates,
                markInjured: resolvedKind == .injury ? (item.markInjured ?? !Self.isInjuryRecovery(in: "\(item.note) \(item.sourceExcerpt)")) : nil,
                sourceExcerpt: item.sourceExcerpt,
                resolutionReason: reasons.isEmpty ? nil : reasons.joined(separator: " · "),
                confidence: min(studentRes.confidence, resolvedKind == .quickEvaluation ? colResolution.confidence : 1.0)
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
        var lastRememberedColumn: CourtVoiceColumnDescriptor? = nil
        var lastRememberedColumnReason: String? = nil
        var lastRememberedStudent: CourtVoiceStudentDescriptor? = nil

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

            let studentMatches = Self.findAllStudentMentions(in: trimmedSegment, roster: input.students, classId: input.classId)
            let kind = inferKind(from: trimmedSegment, columns: rankedColumns)
            let columnToUse = colResolution.matched ?? lastRememberedColumn
            let colReason = colResolution.matched != nil
                ? colResolution.reason
                : (lastRememberedColumn != nil ? "\(lastRememberedColumnReason ?? "Instrumento") (contexto)" : nil)

            // Si el segmento solo introduce el instrumento ("En la rúbrica de saque") sin alumno ni nota ni verbo de acción,
            // actualizamos la memoria de instrumento y pasamos al siguiente segmento sin ensuciar unmatched.
            if studentMatches.isEmpty, colResolution.matched != nil, Self.extractValueAndUnit(from: trimmedSegment, column: colResolution.matched) == nil {
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
                        defaultSelect: true
                    )
                    actions.append(action)
                } else if let candidateName = Self.extractCapitalizedNameCandidate(from: trimmedSegment) {
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
                        defaultSelect: fuzzyRes.matched != nil && fuzzyRes.confidence >= 0.75
                    )
                    actions.append(action)
                } else {
                    unmatched.append(trimmedSegment)
                }
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
                        defaultSelect: match.matched != nil && match.confidence >= 0.75
                    )
                    actions.append(action)
                }
            }
        }

        return CourtVoiceCaptureDraft(
            rawTranscript: raw,
            className: input.className,
            actions: actions,
            unmatchedSegments: unmatched,
            confidenceNote: reason,
            appearsToBeRulesFallback: true
        )
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
        defaultSelect: Bool
    ) -> CourtVoiceProposedAction {
        var reasons: [String] = []
        if let studentReason, !studentReason.isEmpty {
            reasons.append(studentReason)
        }
        let cleanedNote = Self.cleanObservationNote(segment, removingStudentName: student?.fullName ?? fallbackName, studentMention: studentMention)

        switch kind {
        case .attendance:
            let status = Self.normalizeAttendanceStatus(nil, transcriptFragment: segment)
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
            let converted = Self.convertValueForColumn(
                rawScore: extracted?.numericValue,
                rawText: segment,
                unit: extracted?.unit,
                column: column
            )
            if let columnReason, !columnReason.isEmpty {
                reasons.append(columnReason)
            } else if column == nil {
                reasons.append("Sin instrumento especificado: elige columna")
            }
            if converted.numericScore == nil && converted.formattedText == nil {
                reasons.append("Sin calificación detectada: indica valor")
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

    func inferKind(from text: String, columns: [CourtVoiceColumnDescriptor] = []) -> CourtVoiceActionKind {
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

        // 3. Discriminación entre Evaluación Rápida (instrumento + nota/marca) y Observación (actitud/convivencia)
        let matchedColumn = Self.findBestMatchingColumn(in: text, columns: columns)?.column
        let extractedVal = Self.extractValueAndUnit(from: text, column: matchedColumn)

        let pureObservationPhrases = [
            "participativ", "recogiendo", "recoger el material", "ayudando", "ayuda a",
            "buen companero", "excelente companero", "gran companero", "companerismo",
            "fair play", "juego limpio", "juego brusco", "hablando", "distraid",
            "interrumpe", "comportamiento", "motivad", "colabora", "conflicto",
            "pelea", "discute", "aviso por", "amonestacion", "animando al equipo"
        ]
        let hasObservationSignal = pureObservationPhrases.contains(where: { lower.contains($0) })

        let explicitEvalWords = [
            "nota", "ponle", "poner", "califica", "evalua", "rubrica", "instrumento",
            "prueba", "test", "examen", "circuito", "control", "baremo", "palier", "marca"
        ]
        let explicitEvalPhrases = [
            "en la columna", "tiene un", "saca un", "sacado un", "le pongo", "apuntale un"
        ]
        let hasExplicitEvalVerb = explicitEvalWords.contains(where: { Self.containsWholeWord(lower, word: $0) }) ||
            explicitEvalPhrases.contains(where: { lower.contains($0) })

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

    // MARK: - Segmentación Inteligente (Comas, Conectores y Sujeto Heredado)

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

        let connectorReplaced = decimalProtected
            .replacingOccurrences(of: "\n", with: ";")
            .replacingOccurrences(of: ". ", with: ";")
            .replacingOccurrences(of: " por otro lado ", with: ";", options: .caseInsensitive)
            .replacingOccurrences(of: " además ", with: "; además ", options: .caseInsensitive)
            .replacingOccurrences(of: " también ", with: "; también ", options: .caseInsensitive)
            .replacingOccurrences(of: " luego ", with: "; luego ", options: .caseInsensitive)
            .replacingOccurrences(of: " después ", with: "; después ", options: .caseInsensitive)

        let primaryChunks = connectorReplaced
            .split(separator: ";")
            .map { String($0).replacingOccurrences(of: ".__DEC__", with: ",").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var finalSegments: [String] = []
        for chunk in primaryChunks {
            let subChunks = splitCommaSeparatedClauseIfIndependent(chunk, roster: roster, classId: classId)
            finalSegments.append(contentsOf: subChunks)
        }
        return finalSegments
    }

    /// Divide por comas cuando una sub-cláusula después de la coma tiene su propio predicado/acción o su propio alumno + valor
    /// Ej.: "Lucía un 8, Marcos un 7, Elena notable" -> 3 segmentos independientes.
    /// Ej.: "Sofía y Mateo llegan tarde, Hugo muy participativo" -> 2 segmentos independientes.
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

        // Una cláusula es autónoma si contiene una nota/valor, una palabra clave de acción o un verbo/predicado (más allá de un simple nombre propio)
        func hasOwnPredicate(_ part: String) -> Bool {
            let norm = normalized(part)
            if extractValueAndUnit(from: part) != nil { return true }
            if matchesAttendanceIntent(norm) { return true }
            let predicateHints = [
                "tarde", "retraso", "ausente", "falta", "material", "lesion", "esguince",
                "dolor", "molestia", "tobillo", "rodilla", "participativ", "recog", "ayud",
                "hablando", "distraid", "aviso", "buen", "excelente", "muy ", "viene", "llega",
                "tiene", "saca", "ponle", "nota"
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

    static func containsWholeWord(_ normalizedText: String, word: String) -> Bool {
        let normWord = normalized(word)
        guard !normWord.isEmpty else { return false }
        let pattern = "(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: normWord))(?![\\p{L}\\p{N}])"
        return normalizedText.range(of: pattern, options: .regularExpression) != nil
    }

    static func containsKeyword(_ normalizedText: String, keyword: String, prefixMatch: Bool = false) -> Bool {
        let normKey = normalized(keyword)
        guard !normKey.isEmpty else { return false }
        let suffix = prefixMatch ? "[\\p{L}]*" : ""
        let pattern = "(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: normKey))\(suffix)(?![\\p{L}\\p{N}])"
        return normalizedText.range(of: pattern, options: .regularExpression) != nil
    }

    static func jaroWinklerSimilarity(_ s1: String, _ s2: String) -> Double {
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
            if let range = normSegment.range(of: pattern, options: .regularExpression),
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
            if let range = normSegment.range(of: pattern, options: .regularExpression), !overlapsConsumed(range) {
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
            guard let range = normSegment.range(of: pattern, options: .regularExpression), !overlapsConsumed(range) else {
                continue
            }
            consumedRanges.append(range)
            let resolution = resolveStudents(mention: normFirst, in: roster, classId: classId)
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
            guard let range = normSegment.range(of: pattern, options: .regularExpression), !overlapsConsumed(range) else {
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
        if results.isEmpty, let capCandidate = extractCapitalizedNameCandidate(from: segment) {
            let resolution = resolveStudents(mention: capCandidate, in: roster, classId: classId)
            if resolution.matched != nil || !resolution.candidates.isEmpty {
                results.append(resolution)
            }
        }

        return results
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
        column: CourtVoiceColumnDescriptor?
    ) -> (numericScore: Double?, formattedText: String?, unit: String?) {
        guard let column else {
            return (rawScore, nil, unit)
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
        classId: Int64
    ) {
        var phrases: Set<String> = []
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
        contextualStrings = Array(phrases).filter { !$0.isEmpty }
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
                        let text = result.bestTranscription.formattedString
                        self.transcript = text
                        if result.isFinal && !hasResumed {
                            hasResumed = true
                            self.isTranscribingFile = false
                            self.recognitionTask = nil
                            continuation.resume(returning: text)
                        }
                    }

                    if let error, !hasResumed {
                        hasResumed = true
                        self.isTranscribingFile = false
                        self.recognitionTask = nil
                        let current = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !current.isEmpty {
                            continuation.resume(returning: current)
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

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil && self.isRecording {
                    self.stopRecording()
                }
            }
        }
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

