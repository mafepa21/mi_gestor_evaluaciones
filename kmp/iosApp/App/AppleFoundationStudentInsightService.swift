import Foundation
import MiGestorKit

#if canImport(FoundationModels)
import FoundationModels
#endif

struct StudentInsightEvidence {
    let studentId: Int64
    let studentName: String
    let averageText: String
    let averageScore: Double?
    let attendanceStatus: String?
    let followUpCount: Int
    let incidentCount: Int
    let evidenceCount: Int
    let competencyLabels: [String]
    let observations: [NotebookInspectorObservation]
    let rubricSummaries: [NotebookInspectorRubricSummary]
    let averageExplanation: NotebookAverageExplanation?
    let trends: KmpBridge.AITrendsSnapshot?

    var hasEnoughData: Bool {
        averageScore != nil ||
        attendanceStatus?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
        followUpCount > 0 ||
        incidentCount > 0 ||
        evidenceCount > 0 ||
        !competencyLabels.isEmpty ||
        !observations.isEmpty ||
        !rubricSummaries.isEmpty ||
        trends != nil
    }

    func withTrends(_ trends: KmpBridge.AITrendsSnapshot?) -> StudentInsightEvidence {
        StudentInsightEvidence(
            studentId: studentId,
            studentName: studentName,
            averageText: averageText,
            averageScore: averageScore,
            attendanceStatus: attendanceStatus,
            followUpCount: followUpCount,
            incidentCount: incidentCount,
            evidenceCount: evidenceCount,
            competencyLabels: competencyLabels,
            observations: observations,
            rubricSummaries: rubricSummaries,
            averageExplanation: averageExplanation,
            trends: trends
        )
    }

    var evidenceLines: [String] {
        var lines: [String] = [
            "Alumno: \(studentName)",
            "Media: \(averageText)"
        ]
        if let attendanceStatus, !attendanceStatus.isEmpty {
            lines.append("Última asistencia: \(attendanceStatus)")
        }
        if followUpCount > 0 {
            lines.append("Seguimientos activos: \(followUpCount)")
        }
        if incidentCount > 0 {
            lines.append("Incidencias registradas: \(incidentCount)")
        }
        if evidenceCount > 0 {
            lines.append("Evidencias disponibles: \(evidenceCount)")
        }
        if !competencyLabels.isEmpty {
            lines.append("Competencias vinculadas: \(competencyLabels.prefix(4).joined(separator: ", "))")
        }
        if let averageExplanation {
            lines.append("Columnas que cuentan en media: \(averageExplanation.includedColumns.count)")
            lines.append("Columnas pendientes: \(averageExplanation.pendingCells.count)")
            lines.append("Peso total incluido: \(IosFormatting.decimal(from: averageExplanation.totalIncludedWeight))")
        }
        if let trends {
            lines.append("Tendencia de rendimiento: \(trends.trendDirection)")
            lines.append("Asistencia acumulada: \(IosFormatting.decimal(from: trends.attendanceRate))%")
            if !trends.attendanceCorrelationNote.isEmpty {
                lines.append("Nota asistencia/rendimiento: \(trends.attendanceCorrelationNote)")
            }
            if !trends.behaviorIncidentSummary.isEmpty {
                lines.append("Comportamiento: \(trends.behaviorIncidentSummary)")
            }
        }
        lines += observations.prefix(3).map { "Observación \($0.columnTitle): \($0.note)" }
        lines += rubricSummaries.prefix(3).map { "Rúbrica \($0.title): \($0.value)" }
        return AIContextBudget.evidenceLines(lines)
    }
}

struct RiskAnalysis: Codable, Hashable, Sendable {
    let severity: EarlyWarningSeverity
    let causes: [String]
    let evidence: [String]
    let confidence: Double
    let confidenceNote: String

    init(
        severity: EarlyWarningSeverity,
        causes: [String],
        evidence: [String],
        confidence: Double,
        confidenceNote: String
    ) {
        self.severity = severity
        self.causes = AppleAIOutputNormalizer.compactLimited(causes, limit: 3)
        self.evidence = AppleAIOutputNormalizer.compactLimited(evidence, limit: 5)
        self.confidence = AppleAIOutputNormalizer.clampedConfidence(confidence)
        self.confidenceNote = AppleAIOutputNormalizer.nonEmpty(
            confidenceNote,
            fallback: "Confianza basada en evidencias disponibles."
        )
    }
}

struct StudentInsight: Codable, Hashable, Sendable {
    let summary: String
    let strengths: [String]
    let improvementAreas: [String]
    let attendanceSignal: String
    let performanceSignal: String
    let riskAnalysis: RiskAnalysis
    let recommendations: [String]
    let confidenceNote: String

    var risks: [String] {
        riskAnalysis.causes
    }

    init(
        summary: String,
        strengths: [String],
        improvementAreas: [String],
        attendanceSignal: String,
        performanceSignal: String,
        riskAnalysis: RiskAnalysis,
        recommendations: [String],
        confidenceNote: String
    ) {
        self.summary = AppleAIOutputNormalizer.nonEmpty(summary, fallback: "Lectura educativa no disponible.")
        self.strengths = AppleAIOutputNormalizer.compactLimited(strengths, limit: 3)
        self.improvementAreas = AppleAIOutputNormalizer.compactLimited(improvementAreas, limit: 3)
        self.attendanceSignal = AppleAIOutputNormalizer.nonEmpty(attendanceSignal, fallback: "Sin señal reciente de asistencia.")
        self.performanceSignal = AppleAIOutputNormalizer.nonEmpty(performanceSignal, fallback: "Sin tendencia suficiente.")
        self.riskAnalysis = riskAnalysis
        self.recommendations = AppleAIOutputNormalizer.compactLimited(recommendations, limit: 3)
        self.confidenceNote = AppleAIOutputNormalizer.nonEmpty(
            confidenceNote,
            fallback: "Confianza basada en evidencias disponibles."
        )
    }

    init(
        summary: String,
        strengths: [String],
        improvementAreas: [String],
        attendanceSignal: String,
        performanceSignal: String,
        risks: [String],
        recommendations: [String],
        confidenceNote: String
    ) {
        self.init(
            summary: summary,
            strengths: strengths,
            improvementAreas: improvementAreas,
            attendanceSignal: attendanceSignal,
            performanceSignal: performanceSignal,
            riskAnalysis: RiskAnalysis(
                severity: risks.isEmpty ? .normal : .moderate,
                causes: risks,
                evidence: [],
                confidence: risks.isEmpty ? 0.35 : 0.55,
                confidenceNote: confidenceNote
            ),
            recommendations: recommendations,
            confidenceNote: confidenceNote
        )
    }
}

typealias StudentInsightDraft = StudentInsight

struct AverageExplanation: Codable, Hashable, Sendable {
    let explanation: String
    let includedSummary: String
    let excludedSummary: String
    let pendingSummary: String
    let weightSummary: String
    let warnings: [String]

    init(
        explanation: String,
        includedSummary: String,
        excludedSummary: String,
        pendingSummary: String,
        weightSummary: String,
        warnings: [String]
    ) {
        self.explanation = AppleAIOutputNormalizer.nonEmpty(explanation, fallback: "Media explicada no disponible.")
        self.includedSummary = AppleAIOutputNormalizer.nonEmpty(includedSummary, fallback: "Sin columnas incluidas.")
        self.excludedSummary = AppleAIOutputNormalizer.nonEmpty(excludedSummary, fallback: "Sin columnas excluidas.")
        self.pendingSummary = AppleAIOutputNormalizer.nonEmpty(pendingSummary, fallback: "Sin columnas pendientes.")
        self.weightSummary = AppleAIOutputNormalizer.nonEmpty(weightSummary, fallback: "Peso no disponible.")
        self.warnings = AppleAIOutputNormalizer.compactLimited(warnings, limit: 3)
    }
}

typealias AverageExplanationDraft = AverageExplanation

struct TutorMeetingSummary: Codable, Hashable, Sendable {
    let keyPoints: [String]
    let concerns: [String]
    let actions: [String]
    let familyFacingSummary: String

    init(
        keyPoints: [String],
        concerns: [String],
        actions: [String],
        familyFacingSummary: String
    ) {
        self.keyPoints = AppleAIOutputNormalizer.compactLimited(keyPoints, limit: 4)
        self.concerns = AppleAIOutputNormalizer.compactLimited(concerns, limit: 3)
        self.actions = AppleAIOutputNormalizer.compactLimited(actions, limit: 3)
        self.familyFacingSummary = AppleAIOutputNormalizer.nonEmpty(
            familyFacingSummary,
            fallback: "Resumen prudente basado en los datos actuales del cuaderno."
        )
    }
}

typealias TutorMeetingSummaryDraft = TutorMeetingSummary

enum EarlyWarningSeverity: String, CaseIterable, Hashable, Codable, Sendable {
    case normal
    case moderate
    case priority

    var title: String {
        switch self {
        case .normal: return "Seguimiento ordinario"
        case .moderate: return "Revisar señales"
        case .priority: return "Revisión prioritaria"
        }
    }

    static func normalized(_ rawValue: String) -> EarlyWarningSeverity {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = EarlyWarningSeverity(rawValue: normalized) {
            return exact
        }
        if normalized.contains("prior") || normalized.contains("alto") || normalized.contains("urg") {
            return .priority
        }
        if normalized.contains("mod") || normalized.contains("revis") || normalized.contains("medio") {
            return .moderate
        }
        return .normal
    }
}

struct EarlyWarning: Codable, Hashable, Sendable {
    let severity: EarlyWarningSeverity
    let causes: [String]
    let evidence: [String]
    let recommendations: [String]
    let confidence: Double
    let confidenceNote: String

    init(
        severity: EarlyWarningSeverity,
        causes: [String],
        evidence: [String],
        recommendations: [String],
        confidence: Double,
        confidenceNote: String
    ) {
        self.severity = severity
        self.causes = AppleAIOutputNormalizer.compactLimited(causes, limit: 3)
        self.evidence = AppleAIOutputNormalizer.compactLimited(evidence, limit: 6)
        self.recommendations = AppleAIOutputNormalizer.compactLimited(recommendations, limit: 3)
        self.confidence = AppleAIOutputNormalizer.clampedConfidence(confidence)
        self.confidenceNote = AppleAIOutputNormalizer.nonEmpty(
            confidenceNote,
            fallback: "Confianza basada en evidencias disponibles."
        )
    }
}

enum AppleAIOutputNormalizer {
    static func compactLimited(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .prefix(limit)
            .map { $0 }
    }

    static func nonEmpty(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    static func clampedConfidence(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

enum StudentInsightServiceError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        }
    }
}

@MainActor
final class AppleFoundationStudentInsightService {
    #if canImport(FoundationModels)
    private var insightSessionStorage: Any?
    private var averageSessionStorage: Any?
    private var tutorSessionStorage: Any?
    private var earlyWarningSessionStorage: Any?
    #endif

    func prewarm() {
        guard AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available else { return }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            _ = consumeInsightSession()
            _ = consumeAverageSession()
            _ = consumeTutorSession()
            _ = consumeEarlyWarningSession()
        }
        #endif
    }

    func generateStudentInsight(from evidence: StudentInsightEvidence) async throws -> StudentInsightDraft {
        guard evidence.hasEnoughData else {
            return fallbackStudentInsight(from: evidence, reason: "Datos insuficientes")
        }
        guard AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available else {
            return fallbackStudentInsight(from: evidence, reason: "Resultado generado con reglas locales revisables.")
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let response = try await consumeInsightSession().respond(
                    to: studentInsightPrompt(from: evidence),
                    generating: GeneratedStudentInsightDraft.self,
                    includeSchemaInPrompt: true,
                    options: AppleFoundationModelSupport.generationOptions(temperature: 0.2)
                )
                return StudentInsightDraft(
                    summary: response.content.summary,
                    strengths: response.content.strengths,
                    improvementAreas: response.content.improvementAreas,
                    attendanceSignal: response.content.attendanceSignal,
                    performanceSignal: response.content.performanceSignal,
                    risks: response.content.risks,
                    recommendations: response.content.recommendations,
                    confidenceNote: response.content.confidenceNote
                )
            } catch {
                AppleFoundationModelSupport.recordRuntimeFailure(error)
                return fallbackStudentInsight(from: evidence, reason: "Resultado generado con reglas locales revisables.")
            }
        }
        #endif

        return fallbackStudentInsight(from: evidence, reason: "Resultado generado con reglas locales revisables.")
    }

    func generateAverageExplanation(
        from explanation: NotebookAverageExplanation,
        evidence: StudentInsightEvidence
    ) async throws -> AverageExplanationDraft {
        guard AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available else {
            return fallbackAverageExplanation(from: explanation)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let response = try await consumeAverageSession().respond(
                    to: averagePrompt(from: explanation, evidence: evidence),
                    generating: GeneratedAverageExplanationDraft.self,
                    includeSchemaInPrompt: true,
                    options: AppleFoundationModelSupport.generationOptions(temperature: 0.15)
                )
                return AverageExplanationDraft(
                    explanation: response.content.explanation,
                    includedSummary: response.content.includedSummary,
                    excludedSummary: response.content.excludedSummary,
                    pendingSummary: response.content.pendingSummary,
                    weightSummary: response.content.weightSummary,
                    warnings: response.content.warnings
                )
            } catch {
                AppleFoundationModelSupport.recordRuntimeFailure(error)
                return fallbackAverageExplanation(from: explanation)
            }
        }
        #endif

        return fallbackAverageExplanation(from: explanation)
    }

    func generateTutorMeetingSummary(from evidence: StudentInsightEvidence) async throws -> TutorMeetingSummaryDraft {
        guard evidence.hasEnoughData else {
            return fallbackTutorSummary(from: evidence)
        }
        guard AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available else {
            return fallbackTutorSummary(from: evidence)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let response = try await consumeTutorSession().respond(
                    to: tutorPrompt(from: evidence),
                    generating: GeneratedTutorMeetingSummaryDraft.self,
                    includeSchemaInPrompt: true,
                    options: AppleFoundationModelSupport.generationOptions(temperature: 0.2)
                )
                return TutorMeetingSummaryDraft(
                    keyPoints: response.content.keyPoints,
                    concerns: response.content.concerns,
                    actions: response.content.actions,
                    familyFacingSummary: response.content.familyFacingSummary
                )
            } catch {
                AppleFoundationModelSupport.recordRuntimeFailure(error)
                return fallbackTutorSummary(from: evidence)
            }
        }
        #endif

        return fallbackTutorSummary(from: evidence)
    }

    func generateEarlyWarning(from evidence: StudentInsightEvidence) async throws -> EarlyWarning {
        guard evidence.hasEnoughData else {
            return fallbackEarlyWarning(from: evidence, reason: "Datos insuficientes para señal preventiva.")
        }
        guard AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available else {
            return fallbackEarlyWarning(from: evidence, reason: "Generado por reglas locales revisables.")
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let response = try await consumeEarlyWarningSession().respond(
                    to: earlyWarningPrompt(from: evidence),
                    generating: GeneratedEarlyWarning.self,
                    includeSchemaInPrompt: true,
                    options: AppleFoundationModelSupport.generationOptions(temperature: 0.1)
                )
                return EarlyWarning(
                    severity: EarlyWarningSeverity.normalized(response.content.severity),
                    causes: response.content.causes,
                    evidence: response.content.evidence,
                    recommendations: response.content.recommendations,
                    confidence: response.content.confidence,
                    confidenceNote: response.content.confidenceNote
                )
            } catch {
                AppleFoundationModelSupport.recordRuntimeFailure(error)
                return fallbackEarlyWarning(from: evidence, reason: "Generado por reglas locales revisables.")
            }
        }
        #endif

        return fallbackEarlyWarning(from: evidence, reason: "Generado por reglas locales revisables.")
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func makeInsightSession() -> LanguageModelSession {
        LanguageModelSession(
            instructions: """
            Actúas como motor local de inteligencia educativa.
            Devuelve un objeto breve y estructurado para SwiftUI.
            Usa exclusivamente la evidencia proporcionada.
            No calcules notas, pesos ni medias. No inventes diagnósticos.
            Redacta en español de España, con tono docente y prudente.
            """
        )
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func makeAverageSession() -> LanguageModelSession {
        LanguageModelSession(
            instructions: """
            Explicas una media ya calculada por la app.
            No recalcules ni corrijas la media. No cambies columnas, pesos ni pendientes.
            Convierte los datos en una explicación clara para uso docente.
            Redacta en español de España.
            """
        )
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func makeTutorSession() -> LanguageModelSession {
        LanguageModelSession(
            instructions: """
            Preparas una tutoría breve a partir de evidencia docente.
            Usa exclusivamente los hechos proporcionados.
            Evita diagnósticos, etiquetas personales y afirmaciones no respaldadas.
            Devuelve puntos, preocupaciones y acciones concretas.
            """
        )
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func makeEarlyWarningSession() -> LanguageModelSession {
        LanguageModelSession(
            instructions: """
            Actúas como sistema local de señal preventiva educativa.
            Usa exclusivamente la evidencia proporcionada.
            No diagnostiques, no etiquetes al alumno y no inventes causas.
            Clasifica severidad solo como normal, moderate o priority.
            Redacta causas como señales observables del cuaderno, no como motivos personales.
            Devuelve evidencia y recomendaciones revisables por el docente antes de actuar.
            """
        )
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func consumeInsightSession() -> LanguageModelSession {
        if let session = insightSessionStorage as? LanguageModelSession { return session }
        let session = makeInsightSession()
        insightSessionStorage = session
        return session
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func consumeAverageSession() -> LanguageModelSession {
        if let session = averageSessionStorage as? LanguageModelSession { return session }
        let session = makeAverageSession()
        averageSessionStorage = session
        return session
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func consumeTutorSession() -> LanguageModelSession {
        if let session = tutorSessionStorage as? LanguageModelSession { return session }
        let session = makeTutorSession()
        tutorSessionStorage = session
        return session
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func consumeEarlyWarningSession() -> LanguageModelSession {
        if let session = earlyWarningSessionStorage as? LanguageModelSession { return session }
        let session = makeEarlyWarningSession()
        earlyWarningSessionStorage = session
        return session
    }
    #endif

    private func studentInsightPrompt(from evidence: StudentInsightEvidence) -> String {
        AIContextBudget.prompt(
            """
            Genera un StudentInsightDraft para el inspector del Cuaderno.

            Evidencia
            \(evidence.evidenceLines.map { "- \($0)" }.joined(separator: "\n"))

            Reglas:
            - Máximo 3 fortalezas, 3 áreas de mejora, 3 riesgos y 3 recomendaciones.
            - Si una señal es insuficiente, indícalo con prudencia.
            - No propongas sanciones ni diagnósticos.
            """
        )
    }

    private func averagePrompt(
        from explanation: NotebookAverageExplanation,
        evidence: StudentInsightEvidence
    ) -> String {
        let included = explanation.includedColumns.prefix(6).map {
            "- \($0.title): valor \(IosFormatting.decimal(from: $0.value)), peso \(IosFormatting.decimal(from: $0.weight))"
        }.joined(separator: "\n")
        let excluded = explanation.excludedColumns.prefix(6).map {
            "- \($0.title): \($0.reason)"
        }.joined(separator: "\n")
        let pending = explanation.pendingCells.prefix(6).map {
            "- \($0.title): peso previsto \(IosFormatting.decimal(from: $0.expectedWeight))"
        }.joined(separator: "\n")

        return AIContextBudget.prompt(
            """
            Explica la media del alumno \(evidence.studentName) sin recalcularla.

            Media final: \(evidence.averageText)
            Peso total incluido: \(IosFormatting.decimal(from: explanation.totalIncludedWeight))

            Columnas incluidas
            \(included.isEmpty ? "- Ninguna" : included)

            Columnas excluidas
            \(excluded.isEmpty ? "- Ninguna" : excluded)

            Columnas pendientes
            \(pending.isEmpty ? "- Ninguna" : pending)

            Reglas:
            - No cambies el valor de la media.
            - No afirmes que una columna cuenta si no aparece en incluidas.
            - Sé breve y docente.
            """
        )
    }

    private func tutorPrompt(from evidence: StudentInsightEvidence) -> String {
        AIContextBudget.prompt(
            """
            Prepara un TutorMeetingSummaryDraft breve para \(evidence.studentName).

            Evidencia
            \(evidence.evidenceLines.map { "- \($0)" }.joined(separator: "\n"))

            Reglas:
            - Máximo 4 puntos clave, 3 preocupaciones y 3 acciones.
            - La versión para familia debe ser respetuosa y no técnica.
            """
        )
    }

    private func earlyWarningPrompt(from evidence: StudentInsightEvidence) -> String {
        AIContextBudget.prompt(
            """
            Genera un EarlyWarning preventivo para el alumno.

            Evidencia
            \(evidence.evidenceLines.map { "- \($0)" }.joined(separator: "\n"))

            Reglas:
            - severity debe ser uno de: normal, moderate, priority.
            - confidence entre 0 y 1.
            - Máximo 3 causas, 4 evidencias y 3 recomendaciones.
            - Si faltan datos, usa normal o moderate con confidence bajo.
            - No inventes factores personales, clínicos ni familiares.
            - Las causas deben ser señales visibles en la evidencia, no conclusiones diagnósticas.
            - Las recomendaciones deben ser acciones docentes revisables y no decisiones automáticas.
            """
        )
    }

    private func fallbackStudentInsight(from evidence: StudentInsightEvidence, reason: String) -> StudentInsightDraft {
        let strengths = compactLimited([
            evidence.evidenceCount > 0 ? "Hay evidencias registradas en el cuaderno." : nil,
            evidence.averageScore.map { $0 >= 7 ? "Rendimiento académico actualmente sólido." : nil } ?? nil,
            evidence.trends?.trendDirection == "UPWARD" ? "Tendencia reciente al alza." : nil,
            evidence.incidentCount == 0 && evidence.followUpCount == 0 ? "Sin señales de seguimiento prioritario con los datos actuales." : nil
        ], limit: 3)
        let improvementAreas = compactLimited([
            evidence.averageScore.map { $0 < 5 ? "Conviene revisar las actividades evaluables con menor resultado." : nil } ?? nil,
            evidence.averageExplanation?.pendingCells.isEmpty == false ? "Hay columnas evaluables pendientes." : nil,
            evidence.trends?.trendDirection == "DOWNWARD" ? "La tendencia reciente recomienda seguimiento." : nil
        ], limit: 3)
        let risks = compactLimited([
            evidence.incidentCount > 0 ? "Existen incidencias registradas." : nil,
            evidence.followUpCount > 0 ? "Hay seguimientos activos." : nil,
            (evidence.trends?.attendanceRate ?? 100) < 80 ? "La asistencia acumulada es baja." : nil
        ], limit: 3)
        let recommendations = compactLimited([
            "Revisar próximas evidencias antes de tomar decisiones.",
            evidence.averageExplanation?.pendingCells.isEmpty == false ? "Priorizar el cierre de columnas pendientes." : nil,
            !evidence.rubricSummaries.isEmpty ? "Contrastar la lectura con las rúbricas asociadas." : nil
        ], limit: 3)

        return StudentInsightDraft(
            summary: evidence.hasEnoughData
                ? "Lectura local basada en media, seguimiento, evidencias y tendencias disponibles."
                : "Aún no hay datos suficientes para una lectura educativa sólida.",
            strengths: strengths.isEmpty ? ["Sin fortalezas destacables con los datos actuales."] : strengths,
            improvementAreas: improvementAreas.isEmpty ? ["Sin áreas críticas detectadas con los datos actuales."] : improvementAreas,
            attendanceSignal: evidence.attendanceStatus.map { "Último estado: \($0)" } ?? "Sin señal reciente de asistencia.",
            performanceSignal: evidence.trends.map { "Tendencia \($0.trendDirection.lowercased())." } ?? "Sin tendencia suficiente.",
            risks: risks,
            recommendations: recommendations,
            confidenceNote: reason
        )
    }

    private func fallbackAverageExplanation(from explanation: NotebookAverageExplanation) -> AverageExplanationDraft {
        let includedCount = explanation.includedColumns.count
        let excludedCount = explanation.excludedColumns.count
        let pendingCount = explanation.pendingCells.count
        let weight = IosFormatting.decimal(from: explanation.totalIncludedWeight)
        return AverageExplanationDraft(
            explanation: "La media procede solo de las columnas evaluables incluidas por la configuración del cuaderno.",
            includedSummary: includedCount == 1 ? "Cuenta 1 columna evaluable." : "Cuentan \(includedCount) columnas evaluables.",
            excludedSummary: excludedCount == 1 ? "Hay 1 columna excluida." : "Hay \(excludedCount) columnas excluidas.",
            pendingSummary: pendingCount == 1 ? "Queda 1 columna pendiente." : "Quedan \(pendingCount) columnas pendientes.",
            weightSummary: "Peso total incluido: \(weight).",
            warnings: ["Explicación generada con reglas locales; la media no se recalcula."]
        )
    }

    private func fallbackTutorSummary(from evidence: StudentInsightEvidence) -> TutorMeetingSummaryDraft {
        TutorMeetingSummaryDraft(
            keyPoints: compactLimited([
                "Media actual: \(evidence.averageText).",
                evidence.attendanceStatus.map { "Última asistencia: \($0)." },
                evidence.evidenceCount > 0 ? "Hay \(evidence.evidenceCount) evidencias disponibles." : nil
            ], limit: 4),
            concerns: compactLimited([
                evidence.incidentCount > 0 ? "Revisar incidencias registradas." : nil,
                evidence.followUpCount > 0 ? "Revisar seguimientos activos." : nil,
                evidence.averageExplanation?.pendingCells.isEmpty == false ? "Cerrar columnas pendientes antes de conclusiones finales." : nil
            ], limit: 3),
            actions: compactLimited([
                "Contrastar la evolución con las últimas evidencias.",
                "Acordar una acción concreta y revisable.",
                evidence.averageExplanation?.pendingCells.isEmpty == false ? "Completar registros pendientes." : nil
            ], limit: 3),
            familyFacingSummary: "Resumen prudente basado en los datos actuales del cuaderno."
        )
    }

    private func fallbackEarlyWarning(from evidence: StudentInsightEvidence, reason: String) -> EarlyWarning {
        var score = 0
        if let average = evidence.averageScore, average < 5 { score += 2 }
        if evidence.trends?.trendDirection == "DOWNWARD" { score += 2 }
        if (evidence.trends?.attendanceRate ?? 100) < 80 { score += 2 }
        if evidence.followUpCount > 0 { score += 1 }
        if evidence.incidentCount > 0 { score += 1 }
        if evidence.averageExplanation?.pendingCells.isEmpty == false { score += 1 }

        let severity: EarlyWarningSeverity
        if score >= 5 {
            severity = .priority
        } else if score >= 2 {
            severity = .moderate
        } else {
            severity = .normal
        }

        let causes = compactLimited([
            evidence.averageScore.map { $0 < 5 ? "Media actual por debajo de 5." : nil } ?? nil,
            evidence.trends?.trendDirection == "DOWNWARD" ? "Tendencia reciente descendente." : nil,
            (evidence.trends?.attendanceRate ?? 100) < 80 ? "Asistencia acumulada baja." : nil,
            evidence.followUpCount > 0 ? "Seguimientos activos registrados." : nil,
            evidence.incidentCount > 0 ? "Incidencias registradas." : nil,
            evidence.averageExplanation?.pendingCells.isEmpty == false ? "Columnas evaluables pendientes." : nil
        ], limit: 3)

        let recommendations = compactLimited([
            severity == .normal ? "Mantener observación ordinaria y recoger evidencias." : "Revisar el caso en la próxima sesión de seguimiento.",
            evidence.averageExplanation?.pendingCells.isEmpty == false ? "Cerrar columnas pendientes antes de tomar decisiones." : nil,
            evidence.trends?.trendDirection == "DOWNWARD" ? "Contrastar la bajada con evidencias recientes." : nil
        ], limit: 3)

        return EarlyWarning(
            severity: severity,
            causes: causes,
            evidence: evidence.evidenceLines,
            recommendations: recommendations,
            confidence: evidence.hasEnoughData ? min(0.35 + Double(score) * 0.1, 0.85) : 0.2,
            confidenceNote: reason
        )
    }

    private func compactLimited(_ values: [String?], limit: Int) -> [String] {
        var seen = Set<String>()
        return values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .prefix(limit)
            .map { $0 }
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct GeneratedStudentInsightDraft {
        let summary: String
        let strengths: [String]
        let improvementAreas: [String]
        let attendanceSignal: String
        let performanceSignal: String
        let risks: [String]
        let recommendations: [String]
        let confidenceNote: String
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct GeneratedAverageExplanationDraft {
        let explanation: String
        let includedSummary: String
        let excludedSummary: String
        let pendingSummary: String
        let weightSummary: String
        let warnings: [String]
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct GeneratedTutorMeetingSummaryDraft {
        let keyPoints: [String]
        let concerns: [String]
        let actions: [String]
        let familyFacingSummary: String
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct GeneratedEarlyWarning {
        let severity: String
        let causes: [String]
        let evidence: [String]
        let recommendations: [String]
        let confidence: Double
        let confidenceNote: String
    }
    #endif
}

extension StudentInsightDraft {
    var appearsToBeRulesFallback: Bool {
        confidenceNote.localizedCaseInsensitiveContains("reglas") ||
        confidenceNote.localizedCaseInsensitiveContains("insuficientes")
    }
}

extension AverageExplanationDraft {
    var appearsToBeRulesFallback: Bool {
        warnings.contains { $0.localizedCaseInsensitiveContains("reglas") }
    }
}

extension TutorMeetingSummaryDraft {
    var appearsToBeRulesFallback: Bool {
        familyFacingSummary.localizedCaseInsensitiveContains("datos actuales")
    }
}

extension EarlyWarning {
    var appearsToBeRulesFallback: Bool {
        confidenceNote.localizedCaseInsensitiveContains("reglas") ||
        confidenceNote.localizedCaseInsensitiveContains("insuficientes")
    }
}
