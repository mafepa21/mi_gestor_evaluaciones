import Foundation
import SwiftUI
import Speech
import AVFoundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Modelos de Entrada para "Voz de Pista"

struct CourtVoiceStudentDescriptor: Hashable, Sendable, Codable {
    let id: Int64
    let fullName: String
    let isCurrentlyInjured: Bool

    init(id: Int64, fullName: String, isCurrentlyInjured: Bool = false) {
        self.id = id
        self.fullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isCurrentlyInjured = isCurrentlyInjured
    }
}

struct CourtVoiceColumnDescriptor: Hashable, Sendable, Codable {
    let id: String
    let title: String
    let evaluationId: Int64?

    init(id: String, title: String, evaluationId: Int64? = nil) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.evaluationId = evaluationId
    }
}

struct CourtVoiceCaptureInput: Hashable, Sendable {
    let transcript: String
    let classId: Int64
    let className: String
    let sessionTitle: String?
    let students: [CourtVoiceStudentDescriptor]
    let evaluableColumns: [CourtVoiceColumnDescriptor]

    init(
        transcript: String,
        classId: Int64,
        className: String,
        sessionTitle: String? = nil,
        students: [CourtVoiceStudentDescriptor],
        evaluableColumns: [CourtVoiceColumnDescriptor] = []
    ) {
        self.transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        self.classId = classId
        self.className = className.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sessionTitle = sessionTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.students = students
        self.evaluableColumns = evaluableColumns
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
    /// Para `.attendance`: `PRESENTE`, `AUSENTE`, `TARDE`, `JUSTIFICADO`, `SIN_MATERIAL`, `EXENTO`.
    var attendanceStatus: String?
    /// Para `.observation`, `.attendance` o `.quickEvaluation`: texto descriptivo.
    var note: String
    /// Para `.observation`: `low`, `medium`, `high`.
    var severity: String
    /// Para `.quickEvaluation`: nota en escala 0-10.
    var score: Double?
    /// Para `.quickEvaluation`: identificador de columna del cuaderno.
    var columnId: String?
    var columnTitle: String?
    /// Para `.injury`: `true` = marcar lesionado, `false` = retirar lesión.
    var markInjured: Bool?
    /// Fragmento original del dictado que originó la acción.
    var sourceExcerpt: String

    init(
        id: String = UUID().uuidString,
        isSelected: Bool = true,
        kind: CourtVoiceActionKind,
        studentId: Int64?,
        studentName: String,
        attendanceStatus: String? = nil,
        note: String = "",
        severity: String = "low",
        score: Double? = nil,
        columnId: String? = nil,
        columnTitle: String? = nil,
        markInjured: Bool? = nil,
        sourceExcerpt: String = ""
    ) {
        self.id = id
        self.isSelected = isSelected
        self.kind = kind
        self.studentId = studentId
        self.studentName = AppleAIOutputNormalizer.nonEmpty(studentName, fallback: "Alumno por confirmar")
        self.attendanceStatus = attendanceStatus
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.severity = ["low", "medium", "high"].contains(severity.lowercased()) ? severity.lowercased() : "low"
        self.score = score.map { min(10.0, max(0.0, ($0 * 10).rounded() / 10)) }
        self.columnId = columnId
        self.columnTitle = columnTitle
        self.markInjured = markInjured
        self.sourceExcerpt = sourceExcerpt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var actionSummaryLine: String {
        switch kind {
        case .attendance:
            let statusLabel = AttendanceStatusOption.option(for: attendanceStatus)?.label ?? (attendanceStatus ?? "Retraso")
            return note.isEmpty ? "Marcar \(statusLabel)" : "Marcar \(statusLabel) · \(note)"
        case .observation:
            return note.isEmpty ? "Registrar observación de aula" : note
        case .quickEvaluation:
            let scoreLabel = score.map { String(format: "%.1f", $0).replacingOccurrences(of: ".0", with: "") } ?? "-"
            let colLabel = columnTitle ?? "Instrumento activo"
            return note.isEmpty ? "Nota \(scoreLabel) en \(colLabel)" : "Nota \(scoreLabel) en \(colLabel) · \(note)"
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
        self.unmatchedSegments = AppleAIOutputNormalizer.compactLimited(unmatchedSegments, limit: 4)
        self.confidenceNote = AppleAIOutputNormalizer.nonEmpty(
            confidenceNote,
            fallback: "Revisión docente obligatoria antes de aplicar al cuaderno."
        )
        self.appearsToBeRulesFallback = appearsToBeRulesFallback
    }
}

// MARK: - Servicio de IA Local + Fallback Determinista para Voz de Pista

@MainActor
final class AppleFoundationCourtVoiceService {
    #if canImport(FoundationModels)
    private var sessionStorage: Any?
    #endif

    func prewarm() {
        guard AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available else { return }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            _ = consumeSession()
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

        // Siempre calculamos el resultado determinista como red de seguridad y para enriquecer IDs.
        let deterministic = parseWithRulesFallback(from: input, reason: "Estructurado con motor de reglas locales en el dispositivo.")

        guard AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available else {
            return deterministic
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let response = try await consumeSession().respond(
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

    // MARK: - Mapeo de salida de Foundation Models a entidades KMP reales

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func consumeSession() -> LanguageModelSession {
        if let existing = sessionStorage as? LanguageModelSession {
            return existing
        }
        let session = LanguageModelSession(
            instructions: """
            Eres un asistente operativo de pista para un profesor de Educación Física.
            Tu única misión es transformar notas de voz rápidas dichas en el patio, pabellón o grabadas en Notas de Voz en una lista estructurada de acciones docentes revisables.
            REGLAS ESTRICTAS DE DISCRIMINACIÓN (INSTRUMENTO VS OBSERVACIÓN):
            1. Nunca inventes nombres que no estén en la lista de alumnado ni hagas diagnósticos médicos.
            2. Clasifica cada acción en uno de estos 4 tipos exactos (`kind`):
               - `attendance`: retrasos ("llega tarde", "5 min tarde"), faltas ("no ha venido", "ausente"), justificadas, olvido de ropa/material deportivo (`SIN_MATERIAL`) o exenciones (`EXENTO`).
               - `injury`: lesión física hoy, esguince, molestia en tobillo/rodilla/gemelo/hombro, indisposición o alta de lesión ("ya está recuperado").
               - `quickEvaluation`: SOLO cuando el profesor expresa intención de CALIFICAR o EVALUAR un instrumento/columna o da una nota numérica (0 a 10) o nivel de rúbrica ("sobresaliente"=9.5, "notable/avanzado"=8.0, "bien"=7.0, "suficiente/en proceso"=6.0, "insuficiente/inicial"=4.0). Si menciona una prueba, rúbrica, test, circuito, saque, golpeo o resistencia con nota, pon el nombre de la columna más parecida en `columnHint`.
               - `observation`: cuando el profesor comenta actitud, comportamiento, fair play, participación, esfuerzo, recogida de material, conflictos o anécdotas de sesión SIN pedir una calificación numérica ni nombrar una columna evaluable con nota. Ejemplos: "muy participativo ayudando con los conos", "distraído hablando en la explicación", "excelente compañero animando al equipo" (si no menciona instrumento ni nota, es `observation`).
            3. Si una frase menciona a varios alumnos ("Sofía, Mateo y Hugo tienen un 8 en resistencia" o "Sofía y Mateo llegan tarde"), genera una acción independiente por cada alumno con la misma nota e instrumento.
            4. Para `attendanceStatus` usa únicamente: `PRESENTE`, `AUSENTE`, `TARDE`, `JUSTIFICADO`, `SIN_MATERIAL` o `EXENTO`.
            """
        )
        sessionStorage = session
        return session
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func mapGeneratedActions(
        _ generated: [GeneratedCourtVoiceAction],
        input: CourtVoiceCaptureInput
    ) -> [CourtVoiceProposedAction] {
        generated.map { item in
            let fallbackScore = Self.extractScore(from: "\(item.note) \(item.sourceExcerpt)")
            let explicitColumn = Self.findBestMatchingColumn(
                in: "\(item.columnHint ?? "") \(item.note) \(item.sourceExcerpt)",
                columns: input.evaluableColumns
            )
            let resolvedKind: CourtVoiceActionKind
            if let parsed = CourtVoiceActionKind(rawValue: item.kind) {
                // Si el modelo dijo quickEvaluation pero no hay ni nota ni columna mencionada y parece actitud pura, corregimos a observation
                if parsed == .quickEvaluation && item.score == nil && fallbackScore == nil && explicitColumn == nil {
                    resolvedKind = inferKind(from: "\(item.note) \(item.sourceExcerpt)", columns: input.evaluableColumns)
                } else if parsed == .observation && (item.score != nil || (fallbackScore != nil && explicitColumn != nil)) {
                    resolvedKind = .quickEvaluation
                } else {
                    resolvedKind = parsed
                }
            } else {
                resolvedKind = inferKind(from: "\(item.note) \(item.sourceExcerpt)", columns: input.evaluableColumns)
            }

            let matchedStudent = Self.matchStudent(named: item.studentName, in: input.students)
            let matchedColumn = explicitColumn ?? Self.matchColumn(named: item.columnHint, in: input.evaluableColumns)
            let normalizedStatus = Self.normalizeAttendanceStatus(item.attendanceStatus, transcriptFragment: "\(item.note) \(item.sourceExcerpt)")
            let resolvedScore = item.score ?? fallbackScore ?? 7.5

            return CourtVoiceProposedAction(
                isSelected: matchedStudent != nil,
                kind: resolvedKind,
                studentId: matchedStudent?.id,
                studentName: matchedStudent?.fullName ?? item.studentName,
                attendanceStatus: resolvedKind == .attendance ? normalizedStatus : nil,
                note: item.note,
                severity: item.severity,
                score: resolvedKind == .quickEvaluation ? resolvedScore : nil,
                columnId: resolvedKind == .quickEvaluation ? matchedColumn?.id : nil,
                columnTitle: resolvedKind == .quickEvaluation ? matchedColumn?.title : nil,
                markInjured: resolvedKind == .injury ? (item.markInjured ?? true) : nil,
                sourceExcerpt: item.sourceExcerpt
            )
        }
    }
    #endif

    private func buildPrompt(from input: CourtVoiceCaptureInput) -> String {
        let rosterLines = input.students.prefix(40).map { "- \($0.fullName) (ID: \($0.id))" }.joined(separator: "\n")
        let columnLines = input.evaluableColumns.prefix(20).map { "- \($0.title) (ID: \($0.id))" }.joined(separator: "\n")
        return """
        Clase activa: \(input.className)
        Sesión: \(input.sessionTitle ?? "Sesión en pista")

        Alumnado del grupo:
        \(rosterLines.isEmpty ? "(Sin lista cargada, extrae los nombres tal cual se mencionen)" : rosterLines)

        Instrumentos / Columnas evaluables del cuaderno en esta clase:
        \(columnLines.isEmpty ? "(Usa la primera columna disponible si hay nota)" : columnLines)

        Transcripción de voz del docente en pista:
        "\(input.transcript)"
        """
    }

    // MARK: - Motor Determinista por Reglas (100% Offline e Instantáneo)

    func parseWithRulesFallback(from input: CourtVoiceCaptureInput, reason: String) -> CourtVoiceCaptureDraft {
        let raw = input.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = Self.splitIntoSegments(raw)

        var actions: [CourtVoiceProposedAction] = []
        var unmatched: [String] = []

        // Memoria contextual dentro de la misma nota de voz: si el profesor dice
        // "En la rúbrica de saque, Lucía un 8.5; Marcos un 7; Elena notable",
        // recordamos el último instrumento mencionado para aplicarlo a las frases siguientes.
        var lastRememberedColumn: CourtVoiceColumnDescriptor? = input.evaluableColumns.first

        for segment in segments {
            let trimmedSegment = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSegment.isEmpty else { continue }

            let explicitColumn = Self.findBestMatchingColumn(in: trimmedSegment, columns: input.evaluableColumns)
            if let explicitColumn {
                lastRememberedColumn = explicitColumn
            }

            let matchedStudents = Self.findAllStudents(in: trimmedSegment, roster: input.students)
            let kind = inferKind(from: trimmedSegment, columns: input.evaluableColumns)
            let columnToUse = explicitColumn ?? lastRememberedColumn ?? input.evaluableColumns.first

            if matchedStudents.isEmpty {
                if let candidateName = Self.extractCapitalizedNameCandidate(from: trimmedSegment) {
                    let action = buildRuleAction(
                        kind: kind,
                        student: nil,
                        fallbackName: candidateName,
                        segment: trimmedSegment,
                        column: columnToUse,
                        defaultSelect: false
                    )
                    actions.append(action)
                } else {
                    unmatched.append(trimmedSegment)
                }
            } else {
                for student in matchedStudents {
                    let action = buildRuleAction(
                        kind: kind,
                        student: student,
                        fallbackName: student.fullName,
                        segment: trimmedSegment,
                        column: columnToUse,
                        defaultSelect: true
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
        fallbackName: String,
        segment: String,
        column: CourtVoiceColumnDescriptor?,
        defaultSelect: Bool
    ) -> CourtVoiceProposedAction {
        switch kind {
        case .attendance:
            let status = Self.normalizeAttendanceStatus(nil, transcriptFragment: segment)
            return CourtVoiceProposedAction(
                isSelected: defaultSelect,
                kind: .attendance,
                studentId: student?.id,
                studentName: student?.fullName ?? fallbackName,
                attendanceStatus: status,
                note: Self.cleanObservationNote(segment, removingStudentName: student?.fullName ?? fallbackName),
                severity: "low",
                sourceExcerpt: segment
            )
        case .injury:
            let lower = Self.normalized(segment)
            let isRecovery = lower.contains("recuperad") || lower.contains("alta") || lower.contains("retirar lesion") || lower.contains("ya puede")
            return CourtVoiceProposedAction(
                isSelected: defaultSelect,
                kind: .injury,
                studentId: student?.id,
                studentName: student?.fullName ?? fallbackName,
                note: Self.cleanObservationNote(segment, removingStudentName: student?.fullName ?? fallbackName),
                severity: "medium",
                markInjured: !isRecovery,
                sourceExcerpt: segment
            )
        case .quickEvaluation:
            let score = Self.extractScore(from: segment) ?? 7.5
            return CourtVoiceProposedAction(
                isSelected: defaultSelect,
                kind: .quickEvaluation,
                studentId: student?.id,
                studentName: student?.fullName ?? fallbackName,
                note: Self.cleanObservationNote(segment, removingStudentName: student?.fullName ?? fallbackName),
                severity: "low",
                score: score,
                columnId: column?.id,
                columnTitle: column?.title,
                sourceExcerpt: segment
            )
        case .observation:
            let lower = Self.normalized(segment)
            let isWarning = lower.contains("aviso") || lower.contains("interrump") || lower.contains("conflicto") || lower.contains("brusc") || lower.contains("negativ") || lower.contains("no recoge") || lower.contains("mal comportamiento") || lower.contains("distraid")
            return CourtVoiceProposedAction(
                isSelected: defaultSelect,
                kind: .observation,
                studentId: student?.id,
                studentName: student?.fullName ?? fallbackName,
                note: Self.cleanObservationNote(segment, removingStudentName: student?.fullName ?? fallbackName),
                severity: isWarning ? "medium" : "low",
                sourceExcerpt: segment
            )
        }
    }

    private func inferKind(from text: String, columns: [CourtVoiceColumnDescriptor] = []) -> CourtVoiceActionKind {
        let lower = Self.normalized(text)

        // 1. Lesiones o estado físico
        let injuryKeywords = [
            "lesion", "esguince", "dolor", "molestia", "tobillo", "rodilla", "gemelo",
            "isquio", "hombro", "muneca", "vendaje", "escayola", "no puede correr",
            "parte medica", "indispuest", "mareo", "recuperad", "contractura", "tirón", "tiron"
        ]
        if injuryKeywords.contains(where: { lower.contains($0) }) {
            return .injury
        }

        // 2. Asistencia / puntualidad / material
        let attendanceKeywords = [
            "tarde", "retraso", "minutos tarde", "falta", "ausente", "no ha venido",
            "justificad", "sin material", "sin ropa", "sin zapatillas", "olvido el chandal",
            "exento", "exenta", "presente", "no trajo ropa"
        ]
        if attendanceKeywords.contains(where: { lower.contains($0) }) {
            return .attendance
        }

        // 3. Discriminación inteligente entre Evaluación Rápida (instrumento + nota) y Observación (actitud/convivencia)
        let extractedScore = Self.extractScore(from: text)
        let matchedColumn = Self.findBestMatchingColumn(in: text, columns: columns)

        // Palabras que indican claramente una observación conductual o de actitud aunque no haya instrumento
        let pureObservationPhrases = [
            "participativ", "recogiendo", "recoger el material", "ayudando", "ayuda a",
            "buen companero", "companerismo", "fair play", "juego limpio", "juego brusco",
            "hablando", "distraid", "interrumpe", "actitud", "comportamiento", "esfuerzo",
            "motivad", "colabora", "conflicto", "pelea", "discute", "aviso por", "amonestacion"
        ]
        let hasObservationSignal = pureObservationPhrases.contains(where: { lower.contains($0) })

        // Palabras explícitas de calificar un instrumento
        let explicitEvalPhrases = [
            "nota", "ponle", "poner", "califica", "evalua", "rubrica", "instrumento",
            "prueba", "test", "examen", "circuito", "control", "baremo", "en la columna",
            "tiene un", "saca un", "sacado un", "le pongo", "apuntale un"
        ]
        let hasExplicitEvalVerb = explicitEvalPhrases.contains(where: { lower.contains($0) })

        if let _ = extractedScore {
            // Si hay nota numérica o de rúbrica Y además menciona una columna del cuaderno o un verbo de evaluación, es Evaluación Rápida
            if matchedColumn != nil || hasExplicitEvalVerb {
                return .quickEvaluation
            }
            // Si hay nota numérica explícita (ej. "Lucía un 8,5") y NO es una frase puramente conductual sin nota, también es Evaluación Rápida
            if !hasObservationSignal {
                return .quickEvaluation
            }
        }

        // Si menciona explícitamente una columna del cuaderno junto con verbos de evaluar ("evalúa a Marcos en resistencia")
        if matchedColumn != nil && hasExplicitEvalVerb {
            return .quickEvaluation
        }

        return .observation
    }

    // MARK: - Utilidades de Matching de Alumnado, Instrumentos, Notas y Texto

    static func splitIntoSegments(_ text: String) -> [String] {
        let replaced = text
            .replacingOccurrences(of: "\n", with: ";")
            .replacingOccurrences(of: ". ", with: ";")
            .replacingOccurrences(of: " por otro lado ", with: ";", options: .caseInsensitive)
            .replacingOccurrences(of: " además ", with: ";", options: .caseInsensitive)
            .replacingOccurrences(of: " también ", with: ";", options: .caseInsensitive)
            .replacingOccurrences(of: " luego ", with: ";", options: .caseInsensitive)
            .replacingOccurrences(of: " después ", with: ";", options: .caseInsensitive)
        return replaced
            .split(separator: ";")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .lowercased()
    }

    static func findAllStudents(in segment: String, roster: [CourtVoiceStudentDescriptor]) -> [CourtVoiceStudentDescriptor] {
        let normSegment = normalized(segment)
        var found: [CourtVoiceStudentDescriptor] = []

        for student in roster {
            let normFull = normalized(student.fullName)
            if !normFull.isEmpty && normSegment.contains(normFull) {
                found.append(student)
                continue
            }
            let tokens = normFull.split(separator: " ").map(String.init).filter { $0.count >= 3 }
            if let firstName = tokens.first {
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: firstName))\\b"
                if normSegment.range(of: pattern, options: .regularExpression) != nil {
                    found.append(student)
                }
            }
        }
        return found
    }

    static func matchStudent(named query: String, in roster: [CourtVoiceStudentDescriptor]) -> CourtVoiceStudentDescriptor? {
        let normQuery = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !normQuery.isEmpty else { return nil }
        if let exact = roster.first(where: { normalized($0.fullName) == normQuery }) {
            return exact
        }
        if let contains = roster.first(where: { normalized($0.fullName).contains(normQuery) || normQuery.contains(normalized($0.fullName)) }) {
            return contains
        }
        let queryTokens = normQuery.split(separator: " ").map(String.init).filter { $0.count >= 3 }
        for token in queryTokens {
            if let byFirst = roster.first(where: { normalized($0.fullName).hasPrefix(token) || normalized($0.fullName).contains(" \(token)") }) {
                return byFirst
            }
        }
        return nil
    }

    /// Busca si un texto menciona de verdad alguna columna/instrumento del cuaderno usando coincidencias exactas,
    /// raíces de palabras y sinónimos habituales de Educación Física. Devuelve `nil` si ninguna columna encaja.
    static func findBestMatchingColumn(in text: String, columns: [CourtVoiceColumnDescriptor]) -> CourtVoiceColumnDescriptor? {
        guard !columns.isEmpty else { return nil }
        let normText = normalized(text)
        guard !normText.isEmpty else { return nil }

        // Diccionario de sinónimos de pista de EF para conectar cómo habla el profe con cómo se llama la columna
        let peSynonyms: [String: [String]] = [
            "resistencia": ["course navette", "navette", "cooper", "aerobica", "aguante", "carrera continua", " resistencia"],
            "velocidad": ["sprint", "50 metros", "rapidez", "velocidad", "relevos"],
            "fuerza": ["abdominales", "flexiones", "lanzamiento", "balon medicinal", "salto horizontal", "fuerza"],
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

        let stopWords: Set<String> = ["de", "la", "el", "los", "las", "en", "con", "del", "por", "para", "una", "uno"]

        var bestCol: CourtVoiceColumnDescriptor?
        var bestScore: Int = 0

        for col in columns {
            let normTitle = normalized(col.title)
            guard !normTitle.isEmpty else { continue }

            var score = 0
            if normText.contains(normTitle) {
                score += 100
            }

            let titleTokens = normTitle
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count >= 3 && !stopWords.contains($0) }

            for token in titleTokens {
                if normText.contains(token) {
                    score += 35
                } else if token.count >= 5 {
                    let stem = String(token.prefix(5))
                    if normText.contains(stem) {
                        score += 20
                    }
                }

                // Comprobar sinónimos de EF asociados al término de la columna
                for (key, synonyms) in peSynonyms {
                    if token.contains(key) || key.contains(token) {
                        if synonyms.contains(where: { normText.contains($0) }) {
                            score += 25
                        }
                    }
                }
            }

            if score > bestScore {
                bestScore = score
                bestCol = col
            }
        }

        return bestScore >= 20 ? bestCol : nil
    }

    static func matchColumn(named hint: String?, in columns: [CourtVoiceColumnDescriptor]) -> CourtVoiceColumnDescriptor? {
        if let hint, let matched = findBestMatchingColumn(in: hint, columns: columns) {
            return matched
        }
        return columns.first
    }

    static func normalizeAttendanceStatus(_ raw: String?, transcriptFragment: String) -> String {
        if let raw {
            let upper = raw.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if AttendanceStatusOption.all.contains(where: { $0.id == upper }) {
                return upper
            }
        }
        let lower = normalized(transcriptFragment)
        if lower.contains("sin material") || lower.contains("sin ropa") || lower.contains("zapatillas") || lower.contains("chandal") || lower.contains("no trajo") {
            return "SIN_MATERIAL"
        }
        if lower.contains("exent") {
            return "EXENTO"
        }
        if lower.contains("justificad") || lower.contains("medico") {
            return "JUSTIFICADO"
        }
        if lower.contains("tarde") || lower.contains("retraso") || lower.contains("minutos") {
            return "TARDE"
        }
        if lower.contains("presente") || lower.contains("ha llegado") {
            return "PRESENTE"
        }
        return "AUSENTE"
    }

    static func extractScore(from segment: String) -> Double? {
        let lower = normalized(segment)
        // Evitar confundir "5 minutos tarde" con una nota de 5
        if lower.contains("minut") || lower.contains("tarde") || lower.contains("retraso") || lower.contains("segundos") {
            return nil
        }

        // 1. Fracciones habladas en español: "ocho y medio", "7 y medio", "seis con cinco", "ocho coma cinco"
        let numberWordsMap: [String: Double] = [
            "diez": 10.0, "nueve": 9.0, "ocho": 8.0, "siete": 7.0,
            "seis": 6.0, "cinco": 5.0, "cuatro": 4.0, "tres": 3.0, "dos": 2.0, "uno": 1.0,
            "10": 10.0, "9": 9.0, "8": 8.0, "7": 7.0, "6": 6.0, "5": 5.0, "4": 4.0, "3": 3.0
        ]
        for (word, base) in numberWordsMap where base < 10.0 {
            if lower.contains("\(word) y medio") || lower.contains("\(word) con cinco") || lower.contains("\(word) coma cinco") {
                return base + 0.5
            }
        }

        // 2. Números con decimales explícitos en dígitos: "8,5" o "8.5"
        let decimalPattern = "\\b(10(?:[.,]0)?|[0-9][.,][0-9])\\b"
        if let regex = try? NSRegularExpression(pattern: decimalPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let range = Range(match.range(at: 1), in: lower) {
            let numberString = String(lower[range]).replacingOccurrences(of: ",", with: ".")
            if let val = Double(numberString), val >= 0 && val <= 10 {
                return val
            }
        }

        // 3. Números hablados con palabra o dígito precedidos de contexto de nota
        let wordNumbers: [(String, Double)] = [
            ("un diez", 10.0), ("de diez", 10.0), ("nota diez", 10.0),
            ("un nueve", 9.0), ("nota nueve", 9.0),
            ("un ocho", 8.0), ("nota ocho", 8.0),
            ("un siete", 7.0), ("nota siete", 7.0),
            ("un seis", 6.0), ("nota seis", 6.0),
            ("un cinco", 5.0), ("nota cinco", 5.0),
            ("un cuatro", 4.0), ("nota cuatro", 4.0)
        ]
        for (word, value) in wordNumbers where lower.contains(word) {
            return value
        }

        // 4. Patrón con contexto verbal o preposicional: "ponle un 8", "nota 7", "tiene 9", "saca 8", "un 7 en"
        let contextPattern = "(?:nota|ponle|poner|le pongo|tiene|saca|sacado|apuntale|un|de|calificacion|rubrica)\\s*(?:un\\s*)?(10|[0-9])\\b"
        if let regex = try? NSRegularExpression(pattern: contextPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let range = Range(match.range(at: 1), in: lower),
           let val = Double(lower[range]), val >= 0 && val <= 10 {
            return val
        }

        // 5. Niveles descriptivos LOMLOE / Rúbricas
        if lower.contains("sobresaliente") || lower.contains("excelente") || lower.contains("nivel 4") {
            return 9.5
        }
        if lower.contains("notable") || lower.contains("avanzado") || lower.contains("nivel 3") {
            return 8.0
        }
        if lower.contains("suficiente") || lower.contains("en proceso") || lower.contains("nivel 2") {
            return 6.0
        }
        if lower.contains("insuficiente") || lower.contains("inicial") || lower.contains("nivel 1") || lower.contains("suspenso") {
            return 4.0
        }

        return nil
    }

    static func extractCapitalizedNameCandidate(from segment: String) -> String? {
        let stopWords: Set<String> = [
            "Hoy", "En", "El", "La", "Los", "Las", "Un", "Una", "Ponle", "Nota",
            "Marcar", "Apunta", "Aviso", "Falta", "Retraso", "Lesión", "Lesion", "Muy", "Bien",
            "Rubrica", "Rúbrica", "Prueba", "Test", "Circuito", "Saque", "Golpeo", "Resistencia"
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

    static func cleanObservationNote(_ segment: String, removingStudentName name: String) -> String {
        var cleaned = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstToken = name.split(separator: " ").first.map(String.init) ?? name
        if cleaned.lowercased().hasPrefix(name.lowercased()) {
            cleaned = String(cleaned.dropFirst(name.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,:-·"))
        } else if cleaned.lowercased().hasPrefix(firstToken.lowercased()) {
            cleaned = String(cleaned.dropFirst(firstToken.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,:-·"))
        }
        guard !cleaned.isEmpty else { return segment }
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }
}

// MARK: - Servicio de Captura de Voz en Vivo (iOS + macOS)

@MainActor
final class CourtVoiceLiveRecognizer: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribingFile = false
    @Published var importedFileName: String?
    @Published var transcript = ""
    @Published var statusMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

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

    /// Transcribe un archivo de audio pregrabado (ej. de la app Notas de Voz de Apple: .m4a, .wav, .mp3, .caf)
    /// y devuelve el texto transcrito para estructurarlo automáticamente.
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

        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Copiamos a un archivo temporal local por si el usuario seleccionó un archivo en iCloud Drive / Notas de Voz
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
                            self.statusMessage = "No se pudo transcribir el audio (\(error.localizedDescription))."
                            continuation.resume(returning: nil)
                        }
                    }
                }
            }
        }
    }

    private func beginSession() {
        guard let recognizer, recognizer.isAvailable else {
            statusMessage = "El reconocedor de voz en español no está disponible ahora mismo. Puedes escribir o usar el dictado del teclado."
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
struct GeneratedCourtVoiceAction {
    @Guide(description: "Tipo de acción: 'attendance', 'observation', 'quickEvaluation' o 'injury'")
    let kind: String

    @Guide(description: "Nombre del alumno mencionado tal y como aparece en la lista de clase")
    let studentName: String

    @Guide(description: "Solo si kind es 'attendance': 'PRESENTE', 'AUSENTE', 'TARDE', 'JUSTIFICADO', 'SIN_MATERIAL' o 'EXENTO'")
    let attendanceStatus: String?

    @Guide(description: "Nota limpia y concisa explicando la observación, motivo del retraso, lesión o criterio evaluado")
    let note: String

    @Guide(description: "Severidad si es observación o incidencia: 'low', 'medium' o 'high'")
    let severity: String

    @Guide(description: "Solo si kind es 'quickEvaluation': calificación numérica de 0.0 a 10.0")
    let score: Double?

    @Guide(description: "Solo si kind es 'quickEvaluation': nombre o pista de la columna o instrumento evaluado")
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
