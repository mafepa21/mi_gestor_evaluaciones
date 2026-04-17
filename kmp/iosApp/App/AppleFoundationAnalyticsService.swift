import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AIAnalyticsAvailabilityState: Equatable {
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
            return "La analítica IA está desactivada por feature flag local."
        case .available:
            return "Apple Foundation Models disponible para analítica local."
        case .unavailable(let reason):
            return reason
        }
    }
}

struct AIChartInsight {
    let title: String
    let subtitle: String
    let insight: String
    let warnings: [String]
    let recommendedActions: [String]
    let insertableSummary: String
}

struct AIAnalyticsInterpretation {
    let chartKind: KmpBridge.ChartKind
    let querySummary: String
    let warnings: [String]
}

enum AIAnalyticsServiceError: LocalizedError {
    case unavailable(String)
    case insufficientContext(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .insufficientContext(let message):
            return message
        }
    }
}

private enum AIAnalyticsFeatureFlags {
    private static let key = "analytics.ai.enabled"

    static var isEnabled: Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }
}

private enum AIAnalyticsTelemetry {
    private static let defaults = UserDefaults.standard

    static func recordAvailability(_ state: AIAnalyticsAvailabilityState) {
        defaults.set(Date(), forKey: "analytics.ai.lastAvailabilityCheck")
        defaults.set(state.message, forKey: "analytics.ai.lastAvailabilityMessage")
    }

    static func recordInsight(kind: KmpBridge.ChartKind) {
        defaults.set(Date(), forKey: "analytics.ai.lastInsightAt")
        let key = "analytics.ai.insightCount.\(kind.rawValue)"
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }

    static func recordInterpretation() {
        defaults.set(Date(), forKey: "analytics.ai.lastInterpretationAt")
    }
}

final class AppleFoundationAnalyticsService {
#if os(macOS)
    func currentAvailability() -> AIAnalyticsAvailabilityState {
        let state: AIAnalyticsAvailabilityState = .unavailable("La analítica IA local todavía no está disponible en esta build macOS.")
        AIAnalyticsTelemetry.recordAvailability(state)
        return state
    }

    func generateInsight(from facts: KmpBridge.ChartFacts) async throws -> AIChartInsight {
        throw AIAnalyticsServiceError.unavailable(currentAvailability().message)
    }

    func interpret(prompt: String, availableCharts: [KmpBridge.ChartKind]) async throws -> AIAnalyticsInterpretation {
        throw AIAnalyticsServiceError.unavailable(currentAvailability().message)
    }
#else
    func currentAvailability() -> AIAnalyticsAvailabilityState {
        guard AIAnalyticsFeatureFlags.isEnabled else {
            let state: AIAnalyticsAvailabilityState = .disabled
            AIAnalyticsTelemetry.recordAvailability(state)
            return state
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            let state: AIAnalyticsAvailabilityState
            switch model.availability {
            case .available:
                state = .available
            case .unavailable(let reason):
                state = .unavailable("Apple Intelligence no está disponible: \(reason)")
            @unknown default:
                state = .unavailable("No se pudo determinar la disponibilidad del modelo local.")
            }
            AIAnalyticsTelemetry.recordAvailability(state)
            return state
        } else {
            let state: AIAnalyticsAvailabilityState = .unavailable("La analítica IA requiere una versión del sistema compatible con Apple Foundation Models.")
            AIAnalyticsTelemetry.recordAvailability(state)
            return state
        }
        #else
        let state: AIAnalyticsAvailabilityState = .unavailable("Este build no incluye el framework Foundation Models.")
        AIAnalyticsTelemetry.recordAvailability(state)
        return state
        #endif
    }

    func generateInsight(from facts: KmpBridge.ChartFacts) async throws -> AIChartInsight {
        guard facts.hasEnoughData else {
            throw AIAnalyticsServiceError.insufficientContext(
                facts.emptyStateMessage ?? "Faltan datos suficientes para generar un insight IA."
            )
        }
        let availability = currentAvailability()
        guard availability.isAvailable else {
            throw AIAnalyticsServiceError.unavailable(availability.message)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let result = try await generateLocalInsight(from: facts)
            AIAnalyticsTelemetry.recordInsight(kind: facts.chartKind)
            return result
        }
        #endif
        throw AIAnalyticsServiceError.unavailable("La analítica IA requiere una versión del sistema compatible con Apple Foundation Models.")
    }

    func interpret(prompt: String, availableCharts: [KmpBridge.ChartKind]) async throws -> AIAnalyticsInterpretation {
        let cleaned = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw AIAnalyticsServiceError.insufficientContext("Escribe una consulta para que la IA pueda proponer un gráfico.")
        }
        let availability = currentAvailability()
        guard availability.isAvailable else {
            throw AIAnalyticsServiceError.unavailable(availability.message)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let result = try await interpretLocally(prompt: cleaned, availableCharts: availableCharts)
            AIAnalyticsTelemetry.recordInterpretation()
            return result
        }
        #endif
        throw AIAnalyticsServiceError.unavailable("La analítica IA requiere una versión del sistema compatible con Apple Foundation Models.")
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateLocalInsight(from facts: KmpBridge.ChartFacts) async throws -> AIChartInsight {
        let session = LanguageModelSession(
            instructions: """
            Actúas como asistente de analítica docente local-first.
            Usa exclusivamente los hechos proporcionados.
            No inventes causas, diagnósticos ni comparaciones no presentes en los datos.
            Si los datos son insuficientes, dilo con prudencia.
            Redacta en español de España.
            """
        )
        let response = try await session.respond(
            to: insightPrompt(from: facts),
            generating: GeneratedAnalyticsInsight.self,
            includeSchemaInPrompt: true,
            options: GenerationOptions(temperature: 0.25)
        )
        return AIChartInsight(
            title: response.content.title,
            subtitle: response.content.subtitle,
            insight: response.content.insight,
            warnings: response.content.warnings,
            recommendedActions: response.content.recommendedActions,
            insertableSummary: response.content.insertableSummary
        )
    }

    @available(iOS 26.0, *)
    private func interpretLocally(
        prompt: String,
        availableCharts: [KmpBridge.ChartKind]
    ) async throws -> AIAnalyticsInterpretation {
        let options = availableCharts.map { "- \($0.rawValue): \($0.title)" }.joined(separator: "\n")
        let session = LanguageModelSession(
            instructions: """
            Actúas como selector de visualizaciones docentes.
            Elige solo uno de los tipos de gráfico disponibles.
            No inventes nuevos tipos.
            Resume la intención del docente en una frase breve y accionable.
            """
        )
        let response = try await session.respond(
            to: """
            Consulta del docente: \(prompt)

            Gráficos disponibles
            \(options)
            """,
            generating: GeneratedAnalyticsInterpretation.self,
            includeSchemaInPrompt: true,
            options: GenerationOptions(temperature: 0.1)
        )
        let kind = availableCharts.first(where: { $0.rawValue == response.content.chartKind }) ?? .attendanceTrend
        return AIAnalyticsInterpretation(
            chartKind: kind,
            querySummary: response.content.querySummary,
            warnings: response.content.warnings
        )
    }

    @available(iOS 26.0, *)
    private func insightPrompt(from facts: KmpBridge.ChartFacts) -> String {
        let metrics = facts.metrics.map { "- \($0.title): \($0.value)" }.joined(separator: "\n")
        let factLines = facts.factLines.map { "- \($0)" }.joined(separator: "\n")
        let highlights = facts.highlights.map { "- \($0)" }.joined(separator: "\n")
        let warnings = facts.warnings.map { "- \($0)" }.joined(separator: "\n")
        let series = facts.series.map { series in
            let points = series.points.map { "\($0.label): \(String(format: "%.2f", $0.value))" }.joined(separator: ", ")
            return "- \(series.name): \(points)"
        }.joined(separator: "\n")

        return """
        Genera un insight breve y prudente sobre un gráfico docente.

        Tipo: \(facts.chartKind.title)
        Subtítulo: \(facts.subtitle)
        Tipo de gráfico: \(facts.chartType)
        Horizonte temporal: \(facts.timeRange)
        Agrupación: \(facts.grouping)

        Métricas
        \(metrics)

        Hechos
        \(factLines)

        Destacados
        \(highlights.isEmpty ? "- Sin destacados previos." : highlights)

        Alertas
        \(warnings.isEmpty ? "- Sin alertas previas." : warnings)

        Series
        \(series.isEmpty ? "- Sin series lineales; usa el resto del contexto." : series)

        Requisitos de salida
        - insight: 2 o 3 frases, concretas y útiles para el docente.
        - warnings: entre 0 y 3 advertencias prudentes.
        - recommendedActions: entre 1 y 3 acciones concretas.
        - insertableSummary: una frase breve apta para informe o digest interno.
        """
    }

    @available(iOS 26.0, *)
    @Generable
    struct GeneratedAnalyticsInsight {
        let title: String
        let subtitle: String
        let insight: String
        let warnings: [String]
        let recommendedActions: [String]
        let insertableSummary: String
    }

    @available(iOS 26.0, *)
    @Generable
    struct GeneratedAnalyticsInterpretation {
        let chartKind: String
        let querySummary: String
        let warnings: [String]
    }
    #endif
#endif
}
