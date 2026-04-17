import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AIReportAudience: String, CaseIterable, Identifiable {
    case docente
    case tutoria
    case familia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .docente: return "Docente"
        case .tutoria: return "Tutoría"
        case .familia: return "Familia"
        }
    }

    var promptLabel: String {
        rawValue
    }
}

enum AIReportTone: String, CaseIterable, Identifiable {
    case formal
    case claro
    case breve

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

enum AIReportAvailabilityState: Equatable {
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
            return "La redacción IA está desactivada por feature flag local."
        case .available:
            return "Apple Foundation Models disponible en este dispositivo."
        case .unavailable(let reason):
            return reason
        }
    }
}

struct AIReportDraft {
    let title: String
    let summary: String
    let strengths: [String]
    let needsAttention: [String]
    let recommendedActions: [String]
    let familyFacingVersion: String
    let teacherNotesVersion: String

    var editableText: String {
        let strengthBlock = strengths.isEmpty ? "Sin fortalezas concluyentes con los datos actuales." : strengths.map { "• \($0)" }.joined(separator: "\n")
        let attentionBlock = needsAttention.isEmpty ? "Sin alertas específicas con los datos actuales." : needsAttention.map { "• \($0)" }.joined(separator: "\n")
        let actionBlock = recommendedActions.isEmpty ? "• Mantener recogida de evidencias antes del próximo corte." : recommendedActions.map { "• \($0)" }.joined(separator: "\n")

        return """
        \(title)

        Resumen
        \(summary)

        Fortalezas observables
        \(strengthBlock)

        Aspectos a vigilar
        \(attentionBlock)

        Próximos pasos recomendados
        \(actionBlock)

        Versión para familia
        \(familyFacingVersion)

        Notas para el profesorado
        \(teacherNotesVersion)
        """
    }

    func editableText(for context: KmpBridge.ReportGenerationContext) -> String {
        guard context.kind == .lomloeEvaluationComment else {
            return editableText
        }
        return """
        ---
        COMENTARIO DE EVALUACIÓN — \(context.studentName ?? "Alumno/a") | \(context.courseLabel ?? context.className) | \(context.termLabel ?? "Trimestre")

        \(teacherNotesVersion)
        ---
        """
    }
}

enum AIReportServiceError: LocalizedError {
    case unavailable(String)
    case insufficientContext(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .insufficientContext(let message):
            return message
        }
    }
}

private enum AIReportFeatureFlags {
    private static let key = "reports.ai.enabled"

    static var isEnabled: Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }
}

private enum AIReportTelemetry {
    private static let defaults = UserDefaults.standard

    static func recordAvailability(_ state: AIReportAvailabilityState) {
        defaults.set(Date(), forKey: "reports.ai.lastAvailabilityCheck")
        defaults.set(state.message, forKey: "reports.ai.lastAvailabilityMessage")
    }

    static func recordGeneration(kind: KmpBridge.ReportKind) {
        let key = "reports.ai.generationCount.\(kind.rawValue)"
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
        defaults.set(Date(), forKey: "reports.ai.lastGenerationAt")
    }

    static func recordFailure(kind: KmpBridge.ReportKind, message: String) {
        defaults.set(message, forKey: "reports.ai.lastFailureMessage")
        defaults.set(kind.rawValue, forKey: "reports.ai.lastFailureKind")
        defaults.set(Date(), forKey: "reports.ai.lastFailureAt")
    }
}

final class AppleFoundationReportService {
#if os(macOS)
    func currentAvailability() -> AIReportAvailabilityState {
        let state: AIReportAvailabilityState = .unavailable("La redacción IA local todavía no está disponible en esta build macOS.")
        AIReportTelemetry.recordAvailability(state)
        return state
    }

    func generateDraft(
        from context: KmpBridge.ReportGenerationContext,
        audience: AIReportAudience,
        tone: AIReportTone
    ) async throws -> AIReportDraft {
        throw AIReportServiceError.unavailable(currentAvailability().message)
    }
#else
    func currentAvailability() -> AIReportAvailabilityState {
        guard AIReportFeatureFlags.isEnabled else {
            let state: AIReportAvailabilityState = .disabled
            AIReportTelemetry.recordAvailability(state)
            return state
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            let state: AIReportAvailabilityState
            switch model.availability {
            case .available:
                state = .available
            case .unavailable(let reason):
                state = .unavailable("Apple Intelligence no está disponible: \(reason)")
            @unknown default:
                state = .unavailable("No se pudo determinar la disponibilidad del modelo local.")
            }
            AIReportTelemetry.recordAvailability(state)
            return state
        } else {
            let state: AIReportAvailabilityState = .unavailable("La redacción IA requiere una versión del sistema compatible con Apple Foundation Models.")
            AIReportTelemetry.recordAvailability(state)
            return state
        }
        #else
        let state: AIReportAvailabilityState = .unavailable("Este build no incluye el framework Foundation Models.")
        AIReportTelemetry.recordAvailability(state)
        return state
        #endif
    }

    func generateDraft(
        from context: KmpBridge.ReportGenerationContext,
        audience: AIReportAudience,
        tone: AIReportTone
    ) async throws -> AIReportDraft {
        guard context.hasEnoughData else {
            throw AIReportServiceError.insufficientContext(
                context.dataQualityNote ?? "Faltan datos suficientes para redactar un borrador con IA."
            )
        }

        let availability = currentAvailability()
        guard availability.isAvailable else {
            throw AIReportServiceError.unavailable(availability.message)
        }

        do {
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                let draft = try await generateLocalDraft(from: context, audience: audience, tone: tone)
                AIReportTelemetry.recordGeneration(kind: context.kind)
                return draft
            }
            #endif
            throw AIReportServiceError.unavailable("La redacción IA requiere una versión del sistema compatible con Apple Foundation Models.")
        } catch {
            AIReportTelemetry.recordFailure(kind: context.kind, message: error.localizedDescription)
            throw error
        }
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateLocalDraft(
        from context: KmpBridge.ReportGenerationContext,
        audience: AIReportAudience,
        tone: AIReportTone
    ) async throws -> AIReportDraft {
        let instructions = """
        Actúas como asistente de redacción docente dentro de una app escolar local-first.
        Usa exclusivamente los hechos proporcionados.
        No inventes notas, diagnósticos, sanciones ni causas.
        Si faltan datos, dilo con prudencia.
        No emitas juicios clínicos ni etiquetas sensibles.
        Redacta en español de España.
        """

        let session = LanguageModelSession(instructions: instructions)
        let options = GenerationOptions(temperature: 0.3)
        let response = try await session.respond(
            to: reportPrompt(from: context, audience: audience, tone: tone),
            generating: GeneratedAIReportDraft.self,
            includeSchemaInPrompt: true,
            options: options
        )
        let content = response.content
        return AIReportDraft(
            title: content.title,
            summary: content.summary,
            strengths: content.strengths,
            needsAttention: content.needsAttention,
            recommendedActions: content.recommendedActions,
            familyFacingVersion: content.familyFacingVersion,
            teacherNotesVersion: content.teacherNotesVersion
        )
    }

    @available(iOS 26.0, *)
    private func reportPrompt(
        from context: KmpBridge.ReportGenerationContext,
        audience: AIReportAudience,
        tone: AIReportTone
    ) -> String {
        let metrics = context.metrics.map { "- \($0.title): \($0.value)" }.joined(separator: "\n")
        let facts = context.factLines.map { "- \($0)" }.joined(separator: "\n")
        let strengths = context.strengths.isEmpty ? "- Sin fortalezas concluyentes." : context.strengths.map { "- \($0)" }.joined(separator: "\n")
        let needsAttention = context.needsAttention.isEmpty ? "- Sin alertas concluyentes." : context.needsAttention.map { "- \($0)" }.joined(separator: "\n")
        let actions = context.recommendedActions.isEmpty ? "- Mantener recogida de evidencias." : context.recommendedActions.map { "- \($0)" }.joined(separator: "\n")
        let notes = context.supportNotes.isEmpty ? "- Sin notas de apoyo adicionales." : context.supportNotes.map { "- \($0)" }.joined(separator: "\n")
        let curriculumReferences = context.curriculumReferences.isEmpty ? "- Sin referencias curriculares preseleccionadas." : context.curriculumReferences.map { "- \($0)" }.joined(separator: "\n")
        let promptDirectives = context.promptDirectives.isEmpty ? "- Redacción general prudente." : context.promptDirectives.map { "- \($0)" }.joined(separator: "\n")

        return """
        Genera un borrador estructurado para un informe escolar.

        Tipo de informe: \(context.kind.title)
        Clase: \(context.className)
        Curso: \(context.courseLabel ?? "No especificado")
        Trimestre: \(context.termLabel ?? "No especificado")
        Destinatario principal: \(audience.promptLabel)
        Tono: \(tone.rawValue)
        Destino específico: \(context.studentName ?? context.className)
        Resumen base: \(context.summary)
        Nota de calidad de datos: \(context.dataQualityNote ?? "Sin incidencias de calidad reseñables.")
        Nota interna orientativa: \(context.numericScore.map { IosFormatting.decimal(from: $0) } ?? "Sin nota consolidada")

        Métricas verificables
        \(metrics)

        Hechos verificables
        \(facts)

        Fortalezas detectadas por reglas
        \(strengths)

        Aspectos a vigilar detectados por reglas
        \(needsAttention)

        Acciones sugeridas por reglas
        \(actions)

        Notas de apoyo
        \(notes)

        Referencias curriculares sugeridas
        \(curriculumReferences)

        Directrices de salida
        \(promptDirectives)

        Requisitos de salida
        - summary: un párrafo breve y prudente.
        - strengths: entre 1 y 4 puntos.
        - needsAttention: entre 1 y 4 puntos.
        - recommendedActions: entre 1 y 4 acciones concretas.
        - familyFacingVersion: lenguaje claro, no técnico y respetuoso.
        - teacherNotesVersion: lenguaje profesional, accionable y conciso.

        Si el tipo es "Comentario LOMLOE":
        - teacherNotesVersion debe ser el comentario final completo, listo para copiar.
        - Debe sonar personalizado y coherente con la nota interna, pero sin mencionar la nota numérica.
        - Debe incluir referencia explícita a al menos una CE entre CE1 y CE5.
        - Debe usar 4 bloques integrados: resultados de aprendizaje, evolución personal, progresos/talentos y orientaciones.
        - Si hay adaptaciones o apoyos, añádelos en una frase breve antes de las orientaciones.
        """
    }

    @available(iOS 26.0, *)
    @Generable
    struct GeneratedAIReportDraft {
        let title: String
        let summary: String
        let strengths: [String]
        let needsAttention: [String]
        let recommendedActions: [String]
        let familyFacingVersion: String
        let teacherNotesVersion: String
    }
    #else
    private func generateLocalDraft(
        from context: KmpBridge.ReportGenerationContext,
        audience: AIReportAudience,
        tone: AIReportTone
    ) async throws -> AIReportDraft {
        throw AIReportServiceError.unavailable("Este build no incluye Apple Foundation Models.")
    }
    #endif
#endif
}
