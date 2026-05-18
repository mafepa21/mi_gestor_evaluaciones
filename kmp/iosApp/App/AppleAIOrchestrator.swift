import Foundation
import MiGestorKit

enum AppleAIAvailability: Equatable {
    case available
    case disabled(String)
    case preparing(String)
    case unavailable(String)

    var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }

    var message: String {
        switch self {
        case .available:
            return "Disponible"
        case .disabled(let message), .preparing(let message), .unavailable(let message):
            return message
        }
    }
}

enum AppleAIIntent: Equatable {
    case contextual(TeachingAssistantUseCase)
    case report(AIReportAudience)
    case analytics
}

enum AppleAIRequest {
    case report(KmpBridge.ReportGenerationContext, AIReportAudience, AIReportTone)
    case chartInsight(KmpBridge.ChartFacts)
    case notebookComment(KmpBridge.NotebookAICommentContext, AIReportAudience, AIReportTone)
    case teachingDraft(TeachingEvidencePack, AIReportAudience, AIReportTone, String?)
    case physicalScaleRecommendation(PhysicalScaleRecommendationInput)
    case formulaSuggestion(String, String, [NotebookColumnDefinition])
}

enum AppleAIResult {
    case report(AIReportDraft)
    case chartInsight(AIChartInsight)
    case notebookComment(NotebookAICommentDraft)
    case teachingDraft(TeachingAssistantDraft)
    case physicalScaleRecommendation(PhysicalScaleRecommendationDraft)
    case formulaSuggestion(String)
}

struct AppleAIGeneration {
    let result: AppleAIResult
    let metadata: AppleAIGenerationMetadata
}

@MainActor
final class AppleAIOrchestrator {
    private let contextual = AppleFoundationContextualAIService()
    private let reports = AppleFoundationReportService()
    private let analytics = AppleFoundationAnalyticsService()
    private let formulas = AppleFoundationFormulaService()

    func availability() -> AppleAIAvailability {
        let resolved = AppleFoundationModelSupport.resolveAvailability(isEnabled: true)
        switch resolved {
        case .available:
            return .available
        case .disabled:
            return .disabled("La IA local está desactivada.")
        case .modelLoading:
            return .preparing("Preparando Apple Intelligence. Se usará fallback por reglas hasta que esté listo.")
        case .notEnabled:
            return .disabled("Apple Intelligence está desactivado en el dispositivo.")
        case .unsupportedDevice:
            return .unavailable("Dispositivo no compatible con Apple Intelligence.")
        case .frameworkUnavailable:
            return .unavailable("Este build no incluye Foundation Models.")
        case .unsupportedOS:
            return .unavailable("El sistema no soporta Foundation Models.")
        case .unavailable(let message):
            return .unavailable(message)
        }
    }

    func prewarmIfUseful(for intent: AppleAIIntent) {
        guard availability().isAvailable else { return }
        switch intent {
        case .contextual:
            contextual.prewarm()
        case .report:
            reports.prewarm()
        case .analytics:
            analytics.prewarm()
        }
    }

    func generate(_ request: AppleAIRequest) async throws -> AppleAIResult {
        switch request {
        case let .report(context, audience, tone):
            return .report(try await reports.generateDraft(from: context, audience: audience, tone: tone))
        case let .chartInsight(facts):
            return .chartInsight(try await analytics.generateInsight(from: facts))
        case let .notebookComment(context, audience, tone):
            return .notebookComment(try await contextual.generateNotebookComment(from: context, audience: audience, tone: tone))
        case let .teachingDraft(evidence, audience, tone, customPrompt):
            return .teachingDraft(try await contextual.generateTeachingDraft(from: evidence, audience: audience, tone: tone, customPrompt: customPrompt))
        case let .physicalScaleRecommendation(input):
            return .physicalScaleRecommendation(try await contextual.generatePhysicalScaleRecommendation(from: input))
        case let .formulaSuggestion(prompt, currentFormula, columns):
            return .formulaSuggestion(try await formulas.generateFormula(request: prompt, currentFormula: currentFormula, availableColumns: columns))
        }
    }

    func generateWithTrace(
        _ request: AppleAIRequest,
        dataSource: String,
        includedEvidence: [String]
    ) async throws -> AppleAIGeneration {
        let startedAt = Date()
        let availability = availability()
        let result = try await generate(request)
        let durationMs = Int64(Date().timeIntervalSince(startedAt) * 1000)
        let usedFallback = fallbackWasUsed(result: result, availability: availability)
        let state: AppleAIGenerationState = usedFallback ? .rulesFallback : availability.generationState
        return AppleAIGeneration(
            result: result,
            metadata: AppleAIGenerationMetadata(
                state: state,
                availabilityMessage: usedFallback ? "Resultado generado con reglas locales revisables." : availability.message,
                audit: AppleAIGenerationAudit(
                    generatedAt: Date(),
                    dataSource: dataSource,
                    includedEvidence: includedEvidence,
                    usedRealAI: availability.isAvailable && !usedFallback,
                    usedFallback: usedFallback,
                    durationMs: durationMs
                )
            )
        )
    }

    func recordFailure(_ error: Error) {
        AppleFoundationModelSupport.recordRuntimeFailure(error)
    }

    private func fallbackWasUsed(result: AppleAIResult, availability: AppleAIAvailability) -> Bool {
        guard availability.isAvailable else { return true }
        switch result {
        case .report(let draft):
            return draft.appearsToBeRulesFallback
        case .chartInsight(let insight):
            return insight.appearsToBeRulesFallback
        case .notebookComment(let draft):
            return draft.appearsToBeRulesFallback
        case .teachingDraft(let draft):
            return draft.appearsToBeRulesFallback
        case .physicalScaleRecommendation(let draft):
            return draft.appearsToBeRulesFallback
        case .formulaSuggestion:
            return false
        }
    }
}
