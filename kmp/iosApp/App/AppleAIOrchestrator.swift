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
    case studentInsight
}

enum EducationalIntelligenceAgent: String, CaseIterable, Identifiable {
    case tutor
    case evaluator
    case physicalEducation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tutor:
            return "Agente Tutor"
        case .evaluator:
            return "Agente Evaluador"
        case .physicalEducation:
            return "Agente EF"
        }
    }

    var summary: String {
        switch self {
        case .tutor:
            return "Prepara tutorias desde evidencias del alumno."
        case .evaluator:
            return "Explica medias e insights sin recalcular KMP."
        case .physicalEducation:
            return "Resume progreso fisico desde snapshots de pruebas."
        }
    }
}

enum EducationalIntelligenceAgentInput {
    case student(StudentInsightEvidence)
    case average(NotebookAverageExplanation, StudentInsightEvidence)
    case physical(PhysicalProgressEvidence)
}

enum EducationalIntelligenceAgentError: LocalizedError {
    case unsupportedInput(EducationalIntelligenceAgent)

    var errorDescription: String? {
        switch self {
        case .unsupportedInput(let agent):
            return "\(agent.title) no puede procesar esa evidencia."
        }
    }
}

enum AppleAIRequest {
    case report(KmpBridge.ReportGenerationContext, AIReportAudience, AIReportTone)
    case reportSummary(KmpBridge.ReportGenerationContext, AIReportAudience, AIReportTone)
    case chartInsight(KmpBridge.ChartFacts)
    case notebookComment(KmpBridge.NotebookAICommentContext, AIReportAudience, AIReportTone)
    case teachingDraft(TeachingEvidencePack, AIReportAudience, AIReportTone, String?)
    case studentInsight(StudentInsightEvidence)
    case averageExplanation(NotebookAverageExplanation, StudentInsightEvidence)
    case tutorMeetingSummary(StudentInsightEvidence)
    case earlyWarning(StudentInsightEvidence)
    case physicalScaleRecommendation(PhysicalScaleRecommendationInput)
    case physicalProgressAnalysis(PhysicalProgressEvidence)
    case formulaSuggestion(String, String, [NotebookColumnDefinition])
}

enum AppleAIResult {
    case report(AIReportDraft)
    case reportSummary(StudentReportSummary)
    case chartInsight(AIChartInsight)
    case notebookComment(NotebookAICommentDraft)
    case teachingDraft(TeachingAssistantDraft)
    case studentInsight(StudentInsightDraft)
    case averageExplanation(AverageExplanationDraft)
    case tutorMeetingSummary(TutorMeetingSummaryDraft)
    case earlyWarning(EarlyWarning)
    case physicalScaleRecommendation(PhysicalScaleRecommendationDraft)
    case physicalProgressAnalysis(PhysicalProgressAnalysis)
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
    private let studentInsights = AppleFoundationStudentInsightService()
    private let formulas = AppleFoundationFormulaService()

    func availability() -> AppleAIAvailability {
        let resolved = AppleFoundationModelSupport.resolveAvailability(isEnabled: true)
        switch resolved {
        case .available:
            return .available
        case .disabled:
            return .disabled("La IA local está desactivada.")
        case .localInferenceDisabled:
            return .disabled("Apple Foundation Models está desactivado en Ajustes de la app.")
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
        case .studentInsight:
            studentInsights.prewarm()
        }
    }

    func generate(_ request: AppleAIRequest) async throws -> AppleAIResult {
        switch request {
        case let .report(context, audience, tone):
            return .report(try await reports.generateDraft(from: context, audience: audience, tone: tone))
        case let .reportSummary(context, audience, tone):
            return .reportSummary(try await reports.generateSummary(from: context, audience: audience, tone: tone))
        case let .chartInsight(facts):
            return .chartInsight(try await analytics.generateInsight(from: facts))
        case let .notebookComment(context, audience, tone):
            return .notebookComment(try await contextual.generateNotebookComment(from: context, audience: audience, tone: tone))
        case let .teachingDraft(evidence, audience, tone, customPrompt):
            return .teachingDraft(try await contextual.generateTeachingDraft(from: evidence, audience: audience, tone: tone, customPrompt: customPrompt))
        case let .studentInsight(evidence):
            return .studentInsight(try await studentInsights.generateStudentInsight(from: evidence))
        case let .averageExplanation(explanation, evidence):
            return .averageExplanation(try await studentInsights.generateAverageExplanation(from: explanation, evidence: evidence))
        case let .tutorMeetingSummary(evidence):
            return .tutorMeetingSummary(try await studentInsights.generateTutorMeetingSummary(from: evidence))
        case let .earlyWarning(evidence):
            return .earlyWarning(try await studentInsights.generateEarlyWarning(from: evidence))
        case let .physicalScaleRecommendation(input):
            return .physicalScaleRecommendation(try await contextual.generatePhysicalScaleRecommendation(from: input))
        case let .physicalProgressAnalysis(evidence):
            return .physicalProgressAnalysis(try await contextual.generatePhysicalProgressAnalysis(from: evidence))
        case let .formulaSuggestion(prompt, currentFormula, columns):
            return .formulaSuggestion(try await formulas.generateFormula(request: prompt, currentFormula: currentFormula, availableColumns: columns))
        }
    }

    func generate(
        agent: EducationalIntelligenceAgent,
        input: EducationalIntelligenceAgentInput
    ) async throws -> AppleAIResult {
        switch (agent, input) {
        case (.tutor, .student(let evidence)):
            return try await generate(.tutorMeetingSummary(evidence))
        case (.evaluator, .student(let evidence)):
            return try await generate(.studentInsight(evidence))
        case (.evaluator, .average(let explanation, let evidence)):
            return try await generate(.averageExplanation(explanation, evidence))
        case (.physicalEducation, .physical(let evidence)):
            return try await generate(.physicalProgressAnalysis(evidence))
        default:
            throw EducationalIntelligenceAgentError.unsupportedInput(agent)
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
        let boundedEvidence = AIContextBudget.evidenceLines(includedEvidence)
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
                    includedEvidence: boundedEvidence,
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
        case .reportSummary(let summary):
            return summary.appearsToBeRulesFallback
        case .chartInsight(let insight):
            return insight.appearsToBeRulesFallback
        case .notebookComment(let draft):
            return draft.appearsToBeRulesFallback
        case .teachingDraft(let draft):
            return draft.appearsToBeRulesFallback
        case .studentInsight(let draft):
            return draft.appearsToBeRulesFallback
        case .averageExplanation(let draft):
            return draft.appearsToBeRulesFallback
        case .tutorMeetingSummary(let draft):
            return draft.appearsToBeRulesFallback
        case .earlyWarning(let warning):
            return warning.appearsToBeRulesFallback
        case .physicalScaleRecommendation(let draft):
            return draft.appearsToBeRulesFallback
        case .physicalProgressAnalysis(let analysis):
            return analysis.appearsToBeRulesFallback
        case .formulaSuggestion:
            return false
        }
    }
}
