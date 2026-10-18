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
            Tu única misión es transformar notas de voz rápidas dichas en el patio o gimnasio en una lista estructurada de acciones docentes revisables.
            REGLAS ESTRICTAS:
            1. Nunca inventes nombres que no estén en la lista de alumnado ni hagas diagnósticos médicos o clínicos.
            2. Clasifica cada acción en uno de estos 4 tipos exactos (`kind`):
               - `attendance`: retrasos, faltas de asistencia, faltas justificadas, olvido de ropa/material deportivo (`SIN_MATERIAL`) o exenciones (`EXENTO`).
               - `observation`: actitud, fair play, participación, ayuda con el material, comportamiento o notas rápidas de sesión.
               - `quickEvaluation`: calificaciones numéricas (0 a 10) o niveles de desempeño ("sobresaliente" = 9.5, "notable/avanzado" = 8.0, "suficiente/medio" = 6.0, "insuficiente/inicial" = 3.5).
               - `injury`: alumno lesionado, molestia física hoy, esguince, dolor o retiro de lesión ("ya está recuperado").
            3. Si una frase menciona a dos o más alumnos ("Sofía y Mateo llegan 5 minutos tarde"), genera una acción separada por cada alumno.
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
            let kind = CourtVoiceActionKind(rawValue: item.kind) ?? inferKind(from: item.note)
            let matchedStudent = Self.matchStudent(named: item.studentName, in: input.students)
            let matchedColumn = Self.matchColumn(named: item.columnHint, in: input.evaluableColumns)
            let normalizedStatus = Self.normalizeAttendanceStatus(item.attendanceStatus, transcriptFragment: item.note)
            return CourtVoiceProposedAction(
                isSelected: matchedStudent != nil,
                kind: kind,
                studentId: matchedStudent?.id,
                studentName: matchedStudent?.fullName ?? item.studentName,
                attendanceStatus: kind == .attendance ? normalizedStatus : nil,
                note: item.note,
                severity: item.severity,
                score: kind == .quickEvaluation ? item.score : nil,
                columnId: kind == .quickEvaluation ? matchedColumn?.id : nil,
                columnTitle: kind == .quickEvaluation ? matchedColumn?.title : nil,
                markInjured: kind == .injury ? item.markInjured : nil,
                sourceExcerpt: item.sourceExcerpt
            )
        }
    }
    #endif

    private func buildPrompt(from input: CourtVoiceCaptureInput) -> String {
        let rosterLines = input.students.prefix(40).map { "- \($0.fullName) (ID: \($0.id))" }.joined(separator: "\n")
        let columnLines = input.evaluableColumns.prefix(15).map { "- \($0.title) (ID: \($0.id))" }.joined(separator: "\n")
        return """
        Clase activa: \(input.className)
        Sesión: \(input.sessionTitle ?? "Sesión en pista")

        Alumnado del grupo:
        \(rosterLines.isEmpty ? "(Sin lista cargada, extrae los nombres tal cual se mencionen)" : rosterLines)

        Columnas / Instrumentos evaluables disponibles:
        \(columnLines.isEmpty ? "(Usa la primera columna disponible si hay nota)" : columnLines)

        Transcripción de voz del docente en pista:
        "\(input.transcript)"
        """
    }

    // MARK: - Motor Determinista por Reglas (100% Offline y Instantáneo)

    func parseWithRulesFallback(from input: CourtVoiceCaptureInput, reason: String) -> CourtVoiceCaptureDraft {
        let raw = input.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        // Dividimos por punto, punto y coma, saltos de línea o conectores claros de cambio de sujeto
        let segments = Self.splitIntoSegments(raw)

        var actions: [CourtVoiceProposedAction] = []
        var unmatched: [String] = []

        for segment in segments {
            let trimmedSegment = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSegment.isEmpty else { continue }

            let matchedStudents = Self.findAllStudents(in: trimmedSegment, roster: input.students)
            let kind = inferKind(from: trimmedSegment)
            let column = Self.matchColumn(named: trimmedSegment, in: input.evaluableColumns) ?? input.evaluableColumns.first

            if matchedStudents.isEmpty {
                // Intentar extraer un nombre propio con mayúscula inicial para que el docente pueda reasignarlo en la bandeja
                if let candidateName = Self.extractCapitalizedNameCandidate(from: trimmedSegment) {
                    let action = buildRuleAction(
                        kind: kind,
                        student: nil,
                        fallbackName: candidateName,
                        segment: trimmedSegment,
                        column: column,
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
                        column: column,
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
            let score = Self.extractScore(from: segment) ?? 7.0
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
            let isWarning = lower.contains("aviso") || lower.contains("interrump") || lower.contains("conflicto") || lower.contains("brusc") || lower.contains("negativ") || lower.contains("no recoge")
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

    private func inferKind(from text: String) -> CourtVoiceActionKind {
        let lower = Self.normalized(text)

        // 1. Lesiones o estado físico
        let injuryKeywords = [
            "lesion", "esguince", "dolor", "molestia", "tobillo", "rodilla", "gemelo",
            "isquio", "hombro", "muñeca", "vendaje", "escayola", "no puede correr",
            "parte medica", "indispuest", "mareo", "recuperad"
        ]
        if injuryKeywords.contains(where: { lower.contains($0) }) {
            return .injury
        }

        // 2. Asistencia / puntualidad / material
        let attendanceKeywords = [
            "tarde", "retraso", "minutos tarde", "falta", "ausente", "no ha venido",
            "justificad", "sin material", "sin ropa", "sin zapatillas", "olvido el chandal",
            "exento", "exenta", "presente"
        ]
        if attendanceKeywords.contains(where: { lower.contains($0) }) {
            return .attendance
        }

        // 3. Evaluación rápida / notas / niveles de rúbrica
        if Self.extractScore(from: text) != nil {
            let evalKeywords = [
                "nota", "ponle", "poner", "evalua", "rubrica", "nivel", "golpeo",
                "tecnica", "tactica", "saque", "reves", "punto", "baremo", "prueba",
                "sobresaliente", "notable", "avanzado", "suficiente", "inicial", "insuficiente",
                "un 10", "un 9", "un 8", "un 7", "un 6", "un 5", "un 4"
            ]
            if evalKeywords.contains(where: { lower.contains($0) }) {
                return .quickEvaluation
            }
        }

        return .observation
    }

    // MARK: - Utilidades de Matching de Alumnado, Notas y Texto

    static func splitIntoSegments(_ text: String) -> [String] {
        let replaced = text
            .replacingOccurrences(of: "\n", with: ";")
            .replacingOccurrences(of: ". ", with: ";")
            .replacingOccurrences(of: " por otro lado ", with: ";", options: .caseInsensitive)
            .replacingOccurrences(of: " además ", with: ";", options: .caseInsensitive)
            .replacingOccurrences(of: " también ", with: ";", options: .caseInsensitive)
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
                // Comprobar límite de palabra para el nombre de pila
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

    static func matchColumn(named hint: String?, in columns: [CourtVoiceColumnDescriptor]) -> CourtVoiceColumnDescriptor? {
        guard let hint, !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return columns.first
        }
        let normHint = normalized(hint)
        for col in columns {
            let normTitle = normalized(col.title)
            if normHint.contains(normTitle) || normTitle.contains(normHint) {
                return col
            }
            let words = normTitle.split(separator: " ").map(String.init).filter { $0.count >= 4 }
            if words.contains(where: { normHint.contains($0) }) {
                return col
            }
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
        if lower.contains("sin material") || lower.contains("sin ropa") || lower.contains("zapatillas") || lower.contains("chandal") {
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
        if lower.contains("minut") || lower.contains("tarde") || lower.contains("retraso") {
            return nil
        }

        // Niveles descriptivos LOMLOE / Rúbricas
        if lower.contains("sobresaliente") || lower.contains("excelente") || lower.contains("nivel 4") {
            return 9.5
        }
        if lower.contains("notable") || lower.contains("avanzado") || lower.contains("muy bien") || lower.contains("nivel 3") {
            return 8.0
        }
        if lower.contains("suficiente") || lower.contains("en proceso") || lower.contains("nivel 2") {
            return 6.0
        }
        if lower.contains("insuficiente") || lower.contains("inicial") || lower.contains("nivel 1") {
            return 4.0
        }

        // Buscar patrones numéricos explícitos: "un 8,5", "nota 7", "8.5", "un diez"
        let wordNumbers: [(String, Double)] = [
            ("un diez", 10.0), ("de diez", 10.0), ("un nueve", 9.0), ("un ocho", 8.0),
            ("un siete", 7.0), ("un seis", 6.0), ("un cinco", 5.0), ("un cuatro", 4.0)
        ]
        for (word, value) in wordNumbers where lower.contains(word) {
            return value
        }

        let pattern = "(?:nota|ponle|poner|un|de|calificacion|rubrica)\\s*(10(?:[.,]0)?|[0-9](?:[.,][0-9])?)\\b"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let range = Range(match.range(at: 1), in: lower) {
            let numberString = String(lower[range]).replacingOccurrences(of: ",", with: ".")
            if let val = Double(numberString), val >= 0 && val <= 10 {
                return val
            }
        }
        return nil
    }

    static func extractCapitalizedNameCandidate(from segment: String) -> String? {
        let stopWords: Set<String> = [
            "Hoy", "En", "El", "La", "Los", "Las", "Un", "Una", "Ponle", "Nota",
            "Marcar", "Apunta", "Aviso", "Falta", "Retraso", "Lesión", "Lesion", "Muy", "Bien"
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
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
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
