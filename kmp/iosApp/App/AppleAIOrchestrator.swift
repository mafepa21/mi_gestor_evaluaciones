import Foundation

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
    case teachingDraft(TeachingEvidencePack, AIReportAudience, AIReportTone, String?)
}

enum AppleAIResult {
    case report(AIReportDraft)
    case chartInsight(AIChartInsight)
    case teachingDraft(TeachingAssistantDraft)
}

@MainActor
final class AppleAIOrchestrator {
    private let contextual = AppleFoundationContextualAIService()
    private let reports = AppleFoundationReportService()
    private let analytics = AppleFoundationAnalyticsService()

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
        case let .teachingDraft(evidence, audience, tone, customPrompt):
            return .teachingDraft(try await contextual.generateTeachingDraft(from: evidence, audience: audience, tone: tone, customPrompt: customPrompt))
        }
    }

    func recordFailure(_ error: Error) {
        AppleFoundationModelSupport.recordRuntimeFailure(error)
    }
}
