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

    static func recordFailure(message: String) {
        defaults.set(message, forKey: "analytics.ai.lastFailureMessage")
        defaults.set(Date(), forKey: "analytics.ai.lastFailureAt")
    }
}

@MainActor
final class AppleFoundationAnalyticsService {
    private let availabilityMessages = AppleFoundationModelMessages(
        disabled: "La analítica IA está desactivada por feature flag local.",
        available: "Apple Foundation Models disponible para analítica local.",
        frameworkUnavailable: "Este build no incluye el framework Foundation Models.",
        unsupportedOS: "La analítica IA requiere una versión del sistema compatible con Apple Foundation Models.",
        unsupportedDevice: "Apple Intelligence no está disponible en este dispositivo compatible con la app.",
        notEnabled: "Apple Intelligence está desactivado en el dispositivo. Actívalo en Ajustes para usar la analítica IA.",
        modelLoading: "Apple Intelligence se está preparando en este dispositivo. Vuelve a intentarlo en unos segundos."
    )
    private var availabilityRetryTask: Task<Void, Never>?

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private var insightSession: LanguageModelSession {
        LanguageModelSession(
            instructions: """
            Actúas como asistente de analítica docente local-first.
            Usa exclusivamente los hechos proporcionados.
            No inventes causas, diagnósticos ni comparaciones no presentes en los datos.
            Si los datos son insuficientes, dilo con prudencia.
            Redacta en español de España.
            """
        )
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var interpretationSession: LanguageModelSession {
        LanguageModelSession(
            instructions: """
            Actúas como selector de visualizaciones docentes.
            Elige solo uno de los tipos de gráfico disponibles.
            No inventes nuevos tipos.
            Resume la intención del docente en una frase breve y accionable.
            """
        )
    }
    #endif

    func currentAvailability() -> AIAnalyticsAvailabilityState {
        let resolved = AppleFoundationModelSupport.resolveAvailability(isEnabled: AIAnalyticsFeatureFlags.isEnabled)
        let state = mapAvailability(resolved)
        AIAnalyticsTelemetry.recordAvailability(state)
        scheduleAvailabilityRetryIfNeeded(for: resolved)
        return state
    }

    func prewarm() {
        let resolved = AppleFoundationModelSupport.resolveAvailability(isEnabled: AIAnalyticsFeatureFlags.isEnabled)
        scheduleAvailabilityRetryIfNeeded(for: resolved)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), resolved == .available {
            _ = insightSession
            _ = interpretationSession
        }
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
            return fallbackInsight(from: facts)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let result = try await generateLocalInsight(from: facts)
                AIAnalyticsTelemetry.recordInsight(kind: facts.chartKind)
                return result
            } catch {
                AppleFoundationModelSupport.recordRuntimeFailure(error)
                AIAnalyticsTelemetry.recordFailure(message: AppleFoundationModelSupport.runtimeFailureKind(for: error))
                return fallbackInsight(from: facts)
            }
        }
        #endif
        return fallbackInsight(from: facts)
    }

    func interpret(prompt: String, availableCharts: [KmpBridge.ChartKind]) async throws -> AIAnalyticsInterpretation {
        let cleaned = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw AIAnalyticsServiceError.insufficientContext("Escribe una consulta para que la IA pueda proponer un gráfico.")
        }
        let availability = currentAvailability()
        guard availability.isAvailable else {
            return fallbackInterpretation(prompt: cleaned, availableCharts: availableCharts)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let result = try await interpretLocally(prompt: cleaned, availableCharts: availableCharts)
                AIAnalyticsTelemetry.recordInterpretation()
                return result
            } catch {
                AppleFoundationModelSupport.recordRuntimeFailure(error)
                AIAnalyticsTelemetry.recordFailure(message: AppleFoundationModelSupport.runtimeFailureKind(for: error))
                return fallbackInterpretation(prompt: cleaned, availableCharts: availableCharts)
            }
        }
        #endif
        return fallbackInterpretation(prompt: cleaned, availableCharts: availableCharts)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func generateLocalInsight(from facts: KmpBridge.ChartFacts) async throws -> AIChartInsight {
        let response = try await insightSession.respond(
            to: insightPrompt(from: facts),
            generating: GeneratedAnalyticsInsight.self,
            includeSchemaInPrompt: true,
            options: AppleFoundationModelSupport.generationOptions(temperature: 0.25)
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

    @available(iOS 26.0, macOS 26.0, *)
    private func interpretLocally(
        prompt: String,
        availableCharts: [KmpBridge.ChartKind]
    ) async throws -> AIAnalyticsInterpretation {
        let options = availableCharts.map { "- \($0.rawValue): \($0.title)" }.joined(separator: "\n")
        let response = try await interpretationSession.respond(
            to: """
            Consulta del docente: \(prompt)

            Gráficos disponibles
            \(options)
            """,
            generating: GeneratedAnalyticsInterpretation.self,
            includeSchemaInPrompt: true,
            options: AppleFoundationModelSupport.generationOptions(temperature: 0.1)
        )
        let kind = availableCharts.first(where: { $0.rawValue == response.content.chartKind }) ?? .attendanceTrend
        return AIAnalyticsInterpretation(
            chartKind: kind,
            querySummary: response.content.querySummary,
            warnings: response.content.warnings
        )
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func insightPrompt(from facts: KmpBridge.ChartFacts) -> String {
        let metrics = facts.metrics.prefix(4).map { "- \($0.title): \($0.value)" }.joined(separator: "\n")
        let factLines = facts.factLines.prefix(6).map { "- \($0)" }.joined(separator: "\n")
        let highlights = facts.highlights.prefix(3).map { "- \($0)" }.joined(separator: "\n")
        let warnings = facts.warnings.prefix(3).map { "- \($0)" }.joined(separator: "\n")
        let series = facts.series.prefix(2).map { series in
            let points = series.points.prefix(6).map { "\($0.label): \(String(format: "%.2f", $0.value))" }.joined(separator: ", ")
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

    private func fallbackInsight(from facts: KmpBridge.ChartFacts) -> AIChartInsight {
        let highlights = Array(facts.highlights.prefix(3))
        let warnings = Array(facts.warnings.prefix(3))
        let metricDigest = facts.metrics.prefix(3).map { "\($0.title): \($0.value)" }.joined(separator: "; ")
        let baseInsight = firstNonEmpty(
            facts.teacherDigest,
            highlights.first,
            metricDigest,
            facts.factLines.first,
            "Hay pocos datos para interpretar este gráfico con seguridad."
        ) ?? "Hay pocos datos para interpretar este gráfico con seguridad."
        let recommendedActions = compactTexts([
            "Contrastar el gráfico con evidencias del cuaderno antes de decidir.",
            warnings.isEmpty ? nil : "Revisar las alertas visibles antes de compartir la conclusión.",
            "Usar esta lectura como borrador editable, no como cierre automático."
        ].compactMap { $0 })
        return AIChartInsight(
            title: facts.chartKind.title,
            subtitle: facts.subtitle,
            insight: baseInsight,
            warnings: warnings + ["Generado por reglas porque la IA local no está disponible."],
            recommendedActions: Array(recommendedActions.prefix(3)),
            insertableSummary: firstNonEmpty(facts.insertableSummary, baseInsight) ?? baseInsight
        )
    }

    private func fallbackInterpretation(
        prompt: String,
        availableCharts: [KmpBridge.ChartKind]
    ) -> AIAnalyticsInterpretation {
        let normalized = prompt.lowercased()
        let selected = availableCharts.first { chart in
            normalized.contains(chart.title.lowercased()) || normalized.contains(chart.rawValue.lowercased())
        } ?? availableCharts.first ?? .attendanceTrend
        return AIAnalyticsInterpretation(
            chartKind: selected,
            querySummary: "Consulta interpretada por reglas: \(prompt)",
            warnings: ["Apple Intelligence no está disponible; se ha elegido el gráfico más cercano por reglas."]
        )
    }

    private func mapAvailability(_ availability: AppleFoundationModelAvailability) -> AIAnalyticsAvailabilityState {
        switch availability {
        case .disabled:
            return .disabled
        case .available:
            return .available
        case .frameworkUnavailable,
                .unsupportedOS,
                .unsupportedDevice,
                .notEnabled,
                .modelLoading,
                .unavailable(_):
            return .unavailable(availabilityMessages.message(for: availability))
        }
    }

    private func scheduleAvailabilityRetryIfNeeded(for availability: AppleFoundationModelAvailability) {
        guard availability == .modelLoading else {
            availabilityRetryTask?.cancel()
            availabilityRetryTask = nil
            return
        }

        guard availabilityRetryTask == nil else { return }
        availabilityRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.retryAvailabilityAfterDelay()
        }
    }

    private func retryAvailabilityAfterDelay() {
        availabilityRetryTask = nil
        prewarm()
        _ = currentAvailability()
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct GeneratedAnalyticsInsight {
        let title: String
        let subtitle: String
        let insight: String
        let warnings: [String]
        let recommendedActions: [String]
        let insertableSummary: String
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct GeneratedAnalyticsInterpretation {
        let chartKind: String
        let querySummary: String
        let warnings: [String]
    }
    #endif
}
