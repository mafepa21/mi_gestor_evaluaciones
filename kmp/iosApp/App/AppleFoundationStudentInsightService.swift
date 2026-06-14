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

struct StudentInsightDraft: Hashable {
    let summary: String
    let strengths: [String]
    let improvementAreas: [String]
    let attendanceSignal: String
    let performanceSignal: String
    let risks: [String]
    let recommendations: [String]
    let confidenceNote: String
}

struct AverageExplanationDraft: Hashable {
    let explanation: String
    let includedSummary: String
    let excludedSummary: String
    let pendingSummary: String
    let weightSummary: String
    let warnings: [String]
}

struct TutorMeetingSummaryDraft: Hashable {
    let keyPoints: [String]
    let concerns: [String]
    let actions: [String]
    let familyFacingSummary: String
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
    #endif

    func prewarm() {
        guard AppleFoundationModelSupport.resolveAvailability(isEnabled: true) == .available else { return }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            _ = consumeInsightSession()
            _ = consumeAverageSession()
            _ = consumeTutorSession()
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
