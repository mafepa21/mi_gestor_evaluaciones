import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AIContextualAvailabilityState: Equatable {
    case disabled
    case available
    case unavailable(String)

    var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }

    var message: String {
        switch self {
        case .disabled:
            return "La IA contextual está desactivada por feature flag local."
        case .available:
            return "Apple Foundation Models disponible para ayuda contextual."
        case .unavailable(let reason):
            return reason
        }
    }
}

struct ContextualAIResult {
    let title: String
    let subtitle: String
    let summary: String
    let bullets: [String]
    let recommendedActions: [String]
    let editableText: String
}

struct NotebookAICommentDraft {
    let summary: String
    let strengths: [String]
    let needsAttention: [String]
    let nextSteps: [String]
    let commentText: String
}

enum AIContextualServiceError: LocalizedError {
    case unavailable(String)
    case insufficientContext(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .insufficientContext(let message):
            return message
        }
    }
}

private enum AIContextualFeatureFlags {
    private static let key = "contextual.ai.enabled"

    static var isEnabled: Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }
}

private enum AIContextualTelemetry {
    private static let defaults = UserDefaults.standard

    static func recordAvailability(_ state: AIContextualAvailabilityState) {
        defaults.set(Date(), forKey: "contextual.ai.lastAvailabilityCheck")
        defaults.set(state.message, forKey: "contextual.ai.lastAvailabilityMessage")
    }

    static func recordScreenGeneration(kind: KmpBridge.ScreenAIContextKind, action: KmpBridge.ContextualAIAction.ActionID) {
        defaults.set(Date(), forKey: "contextual.ai.lastGenerationAt")
        let key = "contextual.ai.generationCount.\(kind.rawValue).\(action.rawValue)"
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }

    static func recordNotebookGeneration() {
        defaults.set(Date(), forKey: "contextual.ai.notebook.lastGenerationAt")
        let key = "contextual.ai.notebook.generationCount"
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }
}

final class AppleFoundationContextualAIService {
#if os(macOS)
    func currentAvailability() -> AIContextualAvailabilityState {
        let state: AIContextualAvailabilityState = .unavailable("La IA contextual local todavía no está disponible en esta build macOS.")
        AIContextualTelemetry.recordAvailability(state)
        return state
    }

    func generateResult(
        from context: KmpBridge.ScreenAIContext,
        action: KmpBridge.ContextualAIAction,
        audience: AIReportAudience,
        tone: AIReportTone,
        customPrompt: String?
    ) async throws -> ContextualAIResult {
        throw AIContextualServiceError.unavailable(currentAvailability().message)
    }

    func generateNotebookComment(
        from context: KmpBridge.NotebookAICommentContext,
        audience: AIReportAudience,
        tone: AIReportTone
    ) async throws -> NotebookAICommentDraft {
        throw AIContextualServiceError.unavailable(currentAvailability().message)
    }
#else
    func currentAvailability() -> AIContextualAvailabilityState {
        guard AIContextualFeatureFlags.isEnabled else {
            let state: AIContextualAvailabilityState = .disabled
            AIContextualTelemetry.recordAvailability(state)
            return state
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            let state: AIContextualAvailabilityState
            switch model.availability {
            case .available:
                state = .available
            case .unavailable(let reason):
                state = .unavailable("Apple Intelligence no está disponible: \(reason)")
            @unknown default:
                state = .unavailable("No se pudo determinar la disponibilidad del modelo local.")
            }
            AIContextualTelemetry.recordAvailability(state)
            return state
        } else {
            let state: AIContextualAvailabilityState = .unavailable("La IA contextual requiere una versión del sistema compatible con Apple Foundation Models.")
            AIContextualTelemetry.recordAvailability(state)
            return state
        }
        #else
        let state: AIContextualAvailabilityState = .unavailable("Este build no incluye el framework Foundation Models.")
        AIContextualTelemetry.recordAvailability(state)
        return state
        #endif
    }

    func generateResult(
        from context: KmpBridge.ScreenAIContext,
        action: KmpBridge.ContextualAIAction,
        audience: AIReportAudience,
        tone: AIReportTone,
        customPrompt: String?
    ) async throws -> ContextualAIResult {
        guard context.hasEnoughData else {
            throw AIContextualServiceError.insufficientContext(
                context.dataQualityNote ?? "Faltan datos suficientes para generar una ayuda contextual."
            )
        }
        let availability = currentAvailability()
        guard availability.isAvailable else {
            throw AIContextualServiceError.unavailable(availability.message)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let result = try await generateLocalResult(
                from: context,
                action: action,
                audience: audience,
                tone: tone,
                customPrompt: customPrompt
            )
            AIContextualTelemetry.recordScreenGeneration(kind: context.kind, action: action.actionId)
            return result
        }
        #endif
        throw AIContextualServiceError.unavailable("La IA contextual requiere una versión del sistema compatible con Apple Foundation Models.")
    }

    func generateNotebookComment(
        from context: KmpBridge.NotebookAICommentContext,
        audience: AIReportAudience,
        tone: AIReportTone
    ) async throws -> NotebookAICommentDraft {
        guard context.hasEnoughData else {
            throw AIContextualServiceError.insufficientContext(
                context.dataQualityNote ?? "Faltan datos suficientes para generar un comentario de cuaderno."
            )
        }
        let availability = currentAvailability()
        guard availability.isAvailable else {
            throw AIContextualServiceError.unavailable(availability.message)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let result = try await generateLocalNotebookComment(from: context, audience: audience, tone: tone)
            AIContextualTelemetry.recordNotebookGeneration()
            return result
        }
        #endif
        throw AIContextualServiceError.unavailable("La IA contextual requiere una versión del sistema compatible con Apple Foundation Models.")
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateLocalResult(
        from context: KmpBridge.ScreenAIContext,
        action: KmpBridge.ContextualAIAction,
        audience: AIReportAudience,
        tone: AIReportTone,
        customPrompt: String?
    ) async throws -> ContextualAIResult {
        let session = LanguageModelSession(
            instructions: """
            Actúas como asistente contextual docente local-first.
            Usa exclusivamente los hechos proporcionados.
            No inventes causas, diagnósticos, sanciones ni comparaciones que no estén en el contexto.
            Si faltan datos, dilo con prudencia.
            Redacta en español de España.
            """
        )
        let response = try await session.respond(
            to: contextualPrompt(from: context, action: action, audience: audience, tone: tone, customPrompt: customPrompt),
            generating: GeneratedContextualAIResult.self,
            includeSchemaInPrompt: true,
            options: GenerationOptions(temperature: 0.25)
        )
        let content = response.content
        let bulletBlock = content.bullets.map { "• \($0)" }.joined(separator: "\n")
        let actionBlock = content.recommendedActions.map { "• \($0)" }.joined(separator: "\n")
        return ContextualAIResult(
            title: content.title,
            subtitle: content.subtitle,
            summary: content.summary,
            bullets: content.bullets,
            recommendedActions: content.recommendedActions,
            editableText: """
            \(content.title)

            \(content.subtitle)

            \(content.summary)

            Puntos clave
            \(bulletBlock.isEmpty ? "• Sin puntos adicionales." : bulletBlock)

            Próximos pasos
            \(actionBlock.isEmpty ? "• Mantener observación y recogida de evidencias." : actionBlock)
            """
        )
    }

    @available(iOS 26.0, *)
    private func generateLocalNotebookComment(
        from context: KmpBridge.NotebookAICommentContext,
        audience: AIReportAudience,
        tone: AIReportTone
    ) async throws -> NotebookAICommentDraft {
        let session = LanguageModelSession(
            instructions: """
            Actúas como asistente de comentarios docentes para el cuaderno.
            Usa exclusivamente los hechos del contexto.
            No inventes diagnósticos, causas ni notas oficiales.
            Si faltan datos, reconoce la limitación con prudencia.
            El comentario debe ser breve, útil y editable por el profesorado.
            Redacta en español de España.
            """
        )
        let response = try await session.respond(
            to: notebookPrompt(from: context, audience: audience, tone: tone),
            generating: GeneratedNotebookCommentDraft.self,
            includeSchemaInPrompt: true,
            options: GenerationOptions(temperature: 0.3)
        )
        let content = response.content
        return NotebookAICommentDraft(
            summary: content.summary,
            strengths: content.strengths,
            needsAttention: content.needsAttention,
            nextSteps: content.nextSteps,
            commentText: content.commentText
        )
    }

    @available(iOS 26.0, *)
    private func contextualPrompt(
        from context: KmpBridge.ScreenAIContext,
        action: KmpBridge.ContextualAIAction,
        audience: AIReportAudience,
        tone: AIReportTone,
        customPrompt: String?
    ) -> String {
        let metrics = context.metrics.map { "- \($0.title): \($0.value)" }.joined(separator: "\n")
        let facts = context.factLines.map { "- \($0)" }.joined(separator: "\n")
        let notes = context.supportNotes.map { "- \($0)" }.joined(separator: "\n")

        return """
        Genera una ayuda contextual breve para la pantalla activa.

        Pantalla: \(context.title)
        Subtítulo: \(context.subtitle)
        Tipo: \(context.kind.rawValue)
        Acción pedida: \(action.title)
        Intención sugerida: \(action.promptHint)
        Audiencia: \(audience.promptLabel)
        Tono: \(tone.rawValue)

        Resumen base
        \(context.summary)

        Métricas
        \(metrics.isEmpty ? "- Sin métricas estructuradas." : metrics)

        Hechos
        \(facts.isEmpty ? "- Sin hechos adicionales." : facts)

        Notas de apoyo
        \(notes.isEmpty ? "- Sin notas complementarias." : notes)

        Nota de calidad
        \(context.dataQualityNote ?? "Sin incidencias de calidad reseñables.")

        Variación pedida por el docente
        \(normalizedOptional(customPrompt) ?? "Sin variación adicional.")

        Requisitos
        - summary: 2 o 3 frases concretas.
        - bullets: entre 2 y 4 puntos accionables.
        - recommendedActions: entre 1 y 3 acciones concretas.
        - No repitas literalmente todas las métricas.
        """
    }

    @available(iOS 26.0, *)
    private func notebookPrompt(
        from context: KmpBridge.NotebookAICommentContext,
        audience: AIReportAudience,
        tone: AIReportTone
    ) -> String {
        let values = context.relevantValues.map { "- \($0.title) [\($0.categoryLabel)]: \($0.value)" }.joined(separator: "\n")
        let competencies = context.competencyLabels.map { "- \($0)" }.joined(separator: "\n")

        return """
        Genera un comentario de cuaderno editable por el profesorado.

        Alumno: \(context.studentName)
        Grupo: \(context.className)
        Audiencia: \(audience.promptLabel)
        Tono: \(tone.rawValue)
        Resumen base: \(context.summary)

        Métricas de seguimiento
        - Media aproximada: \(context.averageScore.map { String(format: "%.2f", $0) } ?? "Sin media")
        - Última asistencia: \(context.attendanceStatus ?? "Sin dato")
        - Seguimientos: \(context.followUpCount)
        - Incidencias: \(context.incidentCount)
        - Evidencias: \(context.evidenceCount)

        Competencias o criterios vinculados
        \(competencies.isEmpty ? "- Sin competencias enlazadas." : competencies)

        Valores relevantes del cuaderno
        \(values.isEmpty ? "- Sin valores visibles suficientes." : values)

        Comentario previo
        \(normalizedOptional(context.existingComment) ?? "Sin comentario previo.")

        Requisitos
        - commentText: 3 o 4 frases máximo, tono profesional y positivo.
        - strengths: entre 1 y 3 fortalezas observables.
        - needsAttention: entre 0 y 3 aspectos a vigilar, en positivo.
        - nextSteps: entre 1 y 3 pasos siguientes concretos.
        - No menciones una nota oficial ni inventes causas.
        """
    }

    private func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @available(iOS 26.0, *)
    @Generable
    struct GeneratedContextualAIResult {
        let title: String
        let subtitle: String
        let summary: String
        let bullets: [String]
        let recommendedActions: [String]
    }

    @available(iOS 26.0, *)
    @Generable
    struct GeneratedNotebookCommentDraft {
        let summary: String
        let strengths: [String]
        let needsAttention: [String]
        let nextSteps: [String]
        let commentText: String
    }
    #endif
#endif
}
