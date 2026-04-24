import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleFoundationModelAvailability: Equatable {
    case disabled
    case frameworkUnavailable
    case unsupportedOS
    case unsupportedDevice
    case notEnabled
    case modelLoading
    case available
    case unavailable(String)
}

enum TeachingAssistantUseCase: String, Identifiable, CaseIterable {
    case dailyBriefing
    case studentRiskRadar
    case notebookComment
    case tutoringDraft
    case groupInsight
    case sessionClosure
    case coverageAudit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dailyBriefing: return "Briefing docente diario"
        case .studentRiskRadar: return "Radar de riesgo"
        case .notebookComment: return "Comentario inteligente"
        case .tutoringDraft: return "Borrador de tutoría"
        case .groupInsight: return "Inspector analítico"
        case .sessionClosure: return "Cierre de sesión"
        case .coverageAudit: return "Cobertura evaluativa"
        }
    }
}

enum RiskLevel: String, Identifiable, CaseIterable {
    case seguimientoNormal
    case atencionPuntual
    case atencionPrioritaria

    var id: String { rawValue }

    var title: String {
        switch self {
        case .seguimientoNormal: return "Seguimiento normal"
        case .atencionPuntual: return "Atención puntual"
        case .atencionPrioritaria: return "Atención prioritaria"
        }
    }

    var summarySentence: String {
        switch self {
        case .seguimientoNormal: return "No aparecen señales fuertes de riesgo con los datos actuales."
        case .atencionPuntual: return "Conviene revisar el caso con atención breve y seguimiento cercano."
        case .atencionPrioritaria: return "Hay varias señales concurrentes y merece atención prioritaria."
        }
    }
}

struct FactItem: Identifiable, Hashable {
    let id = UUID()
    let text: String
}

struct WarningItem: Identifiable, Hashable {
    let id = UUID()
    let text: String
}

struct RecommendedActionItem: Identifiable, Hashable {
    let id = UUID()
    let text: String
}

struct TeachingEvidencePack {
    let useCase: TeachingAssistantUseCase
    let title: String
    let subtitle: String
    let summary: String
    let metrics: [KmpBridge.ReportMetric]
    let factsUsed: [FactItem]
    let warnings: [WarningItem]
    let recommendedActions: [RecommendedActionItem]
    let confidenceNote: String?
    let riskLevel: RiskLevel?
    let sourceDigest: String
    let hasEnoughData: Bool

    var factTexts: [String] { factsUsed.map(\.text) }
    var warningTexts: [String] { warnings.map(\.text) }
    var recommendedActionTexts: [String] { recommendedActions.map(\.text) }
}

struct TeachingAssistantDraft {
    let title: String
    let subtitle: String
    let summary: String
    let factsUsed: [String]
    let warnings: [String]
    let recommendedActions: [String]
    let editableText: String
    let confidenceNote: String?
    let riskLevel: RiskLevel?
}

func compactTexts(_ groups: [String]...) -> [String] {
    let flattened = groups.flatMap { $0 }
    var seen = Set<String>()
    return flattened
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .filter { seen.insert($0).inserted }
}

func firstNonEmpty(_ candidates: String?...) -> String? {
    candidates.first { !($0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) } ?? nil
}

@MainActor
enum DailyBriefEvidenceBuilder {
    static func build(bridge: KmpBridge, classId: Int64?) async throws -> TeachingEvidencePack {
        let dashboard = try await bridge.buildDashboardAIContext(classId: classId)
        let diary = try await bridge.buildDiaryAIContext(classId: classId)
        let evaluation = try await bridge.buildEvaluationAIContext(classId: classId)
        let facts = compactTexts(dashboard.factLines, Array(diary.factLines.prefix(2)), Array(evaluation.factLines.prefix(2))).map(FactItem.init)
        let warnings = compactTexts(
            dashboard.supportNotes,
            diary.supportNotes,
            dashboard.dataQualityNote.map { [$0] } ?? [],
            diary.dataQualityNote.map { [$0] } ?? [],
            evaluation.dataQualityNote.map { [$0] } ?? []
        ).prefix(4).map(WarningItem.init)
        let actions = compactTexts(
            dashboard.suggestedActions.map(\.subtitle),
            diary.suggestedActions.map(\.subtitle),
            evaluation.suggestedActions.map(\.subtitle)
        ).prefix(4).map(RecommendedActionItem.init)
        return TeachingEvidencePack(
            useCase: .dailyBriefing,
            title: "Briefing docente diario",
            subtitle: dashboard.className ?? dashboard.subtitle,
            summary: "Panorámica breve del día con foco en prioridad operativa, seguimiento y evaluación pendiente.",
            metrics: dashboard.metrics,
            factsUsed: Array(facts.prefix(6)),
            warnings: Array(warnings),
            recommendedActions: Array(actions),
            confidenceNote: firstNonEmpty(dashboard.dataQualityNote, diary.dataQualityNote, evaluation.dataQualityNote),
            riskLevel: nil,
            sourceDigest: compactTexts([dashboard.summary, diary.summary, evaluation.summary]).joined(separator: " "),
            hasEnoughData: dashboard.hasEnoughData || diary.hasEnoughData || evaluation.hasEnoughData
        )
    }
}

@MainActor
enum StudentRiskEvidenceBuilder {
    static func build(bridge: KmpBridge, classId: Int64?, studentId: Int64) async throws -> TeachingEvidencePack {
        let profile = try await bridge.loadStudentProfile(studentId: studentId, classId: classId)
        let level = classify(profile: profile)
        let facts = compactTexts(
            [
                "Asistencia estimada: \(profile.attendanceRate)%.",
                profile.averageScore > 0 ? "Media registrada: \(IosFormatting.decimal(from: profile.averageScore))." : "Sin media consolidada todavía.",
                "Incidencias registradas: \(profile.incidentCount).",
                "Seguimientos activos: \(profile.followUpCount).",
                "Evidencias registradas: \(profile.evidenceCount).",
                "Comunicaciones con familia registradas: \(profile.familyCommunicationCount)."
            ],
            profile.latestAttendanceStatus.map { ["Último estado de asistencia: \($0)."] } ?? [],
            profile.timeline.prefix(2).map { "\($0.title) · \($0.subtitle)" }
        ).map(FactItem.init)
        let warnings = riskSignals(profile: profile, level: level).map(WarningItem.init)
        let actions = recommendedActions(profile: profile, level: level).map(RecommendedActionItem.init)
        return TeachingEvidencePack(
            useCase: .studentRiskRadar,
            title: "Radar de riesgo por alumno",
            subtitle: "\(profile.student.fullName) · \(level.title)",
            summary: level.summarySentence,
            metrics: [
                KmpBridge.ReportMetric(title: "Asistencia", value: "\(profile.attendanceRate)%", systemImage: "checklist.checked"),
                KmpBridge.ReportMetric(title: "Media", value: IosFormatting.decimal(profile.averageScore), systemImage: "sum"),
                KmpBridge.ReportMetric(title: "Incidencias", value: "\(profile.incidentCount)", systemImage: "exclamationmark.bubble.fill"),
                KmpBridge.ReportMetric(title: "Evidencias", value: "\(profile.evidenceCount)", systemImage: "paperclip")
            ],
            factsUsed: Array(facts.prefix(6)),
            warnings: Array(warnings.prefix(4)),
            recommendedActions: Array(actions.prefix(4)),
            confidenceNote: profile.instrumentsCount == 0 ? "La lectura es prudente porque todavía hay poca evidencia evaluativa." : nil,
            riskLevel: level,
            sourceDigest: compactTexts([level.summarySentence], warnings.map(\.text), actions.map(\.text)).joined(separator: " "),
            hasEnoughData: profile.instrumentsCount > 0 || profile.incidentCount > 0 || profile.followUpCount > 0 || profile.journalNoteCount > 0
        )
    }

    static func classify(profile: KmpBridge.StudentProfileSnapshot) -> RiskLevel {
        let lowAttendance = profile.attendanceRate > 0 && profile.attendanceRate < 80
        let repeatedIncidents = profile.incidentCount >= 3
        let sustainedFollowUp = profile.followUpCount >= 3
        let noEvidenceWithActivity = profile.evidenceCount == 0 && (profile.incidentCount > 0 || profile.followUpCount > 0 || profile.instrumentsCount > 0)
        let needsAttention = profile.attendanceRate > 0 && profile.attendanceRate < 90 || profile.incidentCount > 0 || profile.followUpCount > 0 || profile.evidenceCount <= 1
        if lowAttendance || repeatedIncidents || sustainedFollowUp || noEvidenceWithActivity { return .atencionPrioritaria }
        if needsAttention { return .atencionPuntual }
        return .seguimientoNormal
    }

    private static func riskSignals(profile: KmpBridge.StudentProfileSnapshot, level: RiskLevel) -> [String] {
        compactTexts([
            profile.attendanceRate > 0 && profile.attendanceRate < 80 ? "La asistencia está claramente por debajo del umbral deseable." : nil,
            (80..<90).contains(profile.attendanceRate) ? "La asistencia pide revisión puntual." : nil,
            profile.incidentCount >= 3 ? "Se acumulan varias incidencias registradas." : nil,
            profile.incidentCount > 0 && profile.incidentCount < 3 ? "Hay incidencias que conviene contextualizar." : nil,
            profile.followUpCount >= 3 ? "Existe seguimiento recurrente en asistencia o convivencia." : nil,
            profile.followUpCount > 0 && profile.followUpCount < 3 ? "Hay seguimiento activo abierto." : nil,
            profile.evidenceCount == 0 ? "Faltan evidencias observables que respalden mejor la valoración." : nil,
            profile.familyCommunicationCount == 0 && level != .seguimientoNormal ? "No consta comunicación con familia en un caso con señales de atención." : nil
        ].compactMap { $0 })
    }

    private static func recommendedActions(profile: KmpBridge.StudentProfileSnapshot, level: RiskLevel) -> [String] {
        compactTexts([
            level == .atencionPrioritaria ? "Revisar el caso en tutoría con prioridad y acordar seguimiento concreto." : nil,
            profile.attendanceRate > 0 && profile.attendanceRate < 90 ? "Contrastar ausencias recientes y reforzar rutina de asistencia." : nil,
            profile.incidentCount > 0 ? "Leer las incidencias en secuencia antes de redactar observaciones formales." : nil,
            profile.evidenceCount <= 1 ? "Recoger nuevas evidencias de aula o cuaderno antes del siguiente corte." : nil,
            profile.familyCommunicationCount == 0 && level != .seguimientoNormal ? "Valorar una comunicación breve y prudente a familia o tutoría." : nil
        ].compactMap { $0 })
    }
}

enum NotebookCommentEvidenceBuilder {
    static func build(from context: KmpBridge.NotebookAICommentContext) -> TeachingEvidencePack {
        let facts = compactTexts(
            [
                context.averageScore.map { "Media registrada: \(IosFormatting.decimal(from: $0))." },
                context.attendanceStatus.map { "Último estado de asistencia: \($0)." },
                "Seguimientos activos: \(context.followUpCount).",
                "Incidencias registradas: \(context.incidentCount).",
                "Evidencias registradas: \(context.evidenceCount)."
            ].compactMap { $0 },
            context.relevantValues.prefix(4).map { "\($0.title) [\($0.categoryLabel)]: \($0.value)." },
            context.competencyLabels.prefix(3).map { "Competencia relacionada: \($0)." }
        ).map(FactItem.init)
        let warnings = compactTexts([
            context.dataQualityNote,
            context.relevantValues.isEmpty ? "Hay pocas columnas visibles con dato para este alumno." : nil,
            context.evidenceCount == 0 ? "No constan evidencias adjuntas en el periodo visible." : nil
        ].compactMap { $0 }).map(WarningItem.init)
        let actions = compactTexts([
            context.followUpCount > 0 ? "Mantener continuidad en el seguimiento individual." : nil,
            context.incidentCount > 0 ? "Conectar el comentario con observaciones verificables, no con causas supuestas." : nil,
            context.evidenceCount <= 1 ? "Añadir nuevas evidencias antes de cerrar una valoración más firme." : nil
        ].compactMap { $0 }).map(RecommendedActionItem.init)
        return TeachingEvidencePack(
            useCase: .notebookComment,
            title: "Comentario inteligente de cuaderno",
            subtitle: "\(context.studentName) · \(context.className)",
            summary: context.summary,
            metrics: [
                KmpBridge.ReportMetric(title: "Media", value: context.averageScore.map { IosFormatting.decimal(from: $0) } ?? "Sin dato", systemImage: "sum"),
                KmpBridge.ReportMetric(title: "Seguimiento", value: "\(context.followUpCount)", systemImage: "arrow.triangle.branch"),
                KmpBridge.ReportMetric(title: "Incidencias", value: "\(context.incidentCount)", systemImage: "exclamationmark.bubble.fill"),
                KmpBridge.ReportMetric(title: "Evidencias", value: "\(context.evidenceCount)", systemImage: "paperclip")
            ],
            factsUsed: Array(facts.prefix(7)),
            warnings: Array(warnings.prefix(3)),
            recommendedActions: Array(actions.prefix(3)),
            confidenceNote: context.dataQualityNote,
            riskLevel: nil,
            sourceDigest: compactTexts([context.summary], facts.map(\.text)).joined(separator: " "),
            hasEnoughData: context.hasEnoughData
        )
    }
}

@MainActor
enum GroupInsightEvidenceBuilder {
    static func build(bridge: KmpBridge, classId: Int64?, timeRange: KmpBridge.AnalyticsTimeRange = .last30Days) async throws -> TeachingEvidencePack {
        guard let classId else {
            return TeachingEvidencePack(
                useCase: .groupInsight,
                title: "Inspector analítico del grupo",
                subtitle: "Sin grupo activo",
                summary: "Selecciona un grupo para analizar patrones.",
                metrics: [],
                factsUsed: [FactItem(text: "No hay grupo activo para cargar paneles analíticos.")],
                warnings: [WarningItem(text: "El inspector analítico necesita una clase seleccionada.")],
                recommendedActions: [],
                confidenceNote: "Sin grupo activo.",
                riskLevel: nil,
                sourceDigest: "Sin grupo activo.",
                hasEnoughData: false
            )
        }
        let charts = try await bridge.buildPrebuiltAnalyticsCharts(classId: classId, timeRange: timeRange)
        let selectedCharts = Array(charts.prefix(3))
        let facts = selectedCharts.flatMap { chart in compactTexts(["\(chart.title): \(chart.teacherDigest)"], Array(chart.factLines.prefix(2))) }.map(FactItem.init)
        let warnings = selectedCharts.flatMap { chart in compactTexts(chart.warnings, chart.emptyStateMessage.map { [$0] } ?? []) }.map(WarningItem.init)
        let actions = compactTexts([
            "Revisar primero el gráfico con más alertas o variación reciente.",
            "Cruzar asistencia, incidencias y evaluación antes de sacar conclusiones firmes.",
            "Usar este insight como apoyo de decisión, no como juicio automático."
        ]).map(RecommendedActionItem.init)
        return TeachingEvidencePack(
            useCase: .groupInsight,
            title: "Inspector analítico del grupo",
            subtitle: selectedCharts.first?.subtitle ?? "Patrones del grupo",
            summary: "Lectura guiada del grupo a partir de paneles analíticos ya disponibles y hechos verificables.",
            metrics: selectedCharts.first?.metrics ?? [],
            factsUsed: Array(facts.prefix(8)),
            warnings: Array(warnings.prefix(4)),
            recommendedActions: Array(actions),
            confidenceNote: selectedCharts.isEmpty ? "No hay paneles analíticos suficientes para una lectura fiable." : nil,
            riskLevel: nil,
            sourceDigest: selectedCharts.map { $0.insertableSummary }.joined(separator: " "),
            hasEnoughData: selectedCharts.contains { $0.hasEnoughData }
        )
    }
}

@MainActor
enum SessionClosureEvidenceBuilder {
    static func build(bridge: KmpBridge, classId: Int64?) async throws -> TeachingEvidencePack {
        let diary = try await bridge.buildDiaryAIContext(classId: classId)
        let pe = try? await bridge.buildPEAIContext(classId: classId)
        let facts = compactTexts(diary.factLines, Array((pe?.factLines ?? []).prefix(2))).map(FactItem.init)
        let warnings = compactTexts(diary.supportNotes, pe?.supportNotes ?? [], diary.dataQualityNote.map { [$0] } ?? []).map(WarningItem.init)
        let actions = compactTexts([
            "Cerrar la sesión con una síntesis breve de lo que funcionó y lo que conviene ajustar.",
            "Identificar alumnado o grupos que merecen atención en la próxima clase.",
            "Convertir el diario en una siguiente acción concreta y verificable."
        ]).map(RecommendedActionItem.init)
        return TeachingEvidencePack(
            useCase: .sessionClosure,
            title: "Cierre de sesión y siguiente paso",
            subtitle: diary.subtitle,
            summary: "Síntesis del diario reciente para convertir la reflexión docente en una acción próxima concreta.",
            metrics: diary.metrics,
            factsUsed: Array(facts.prefix(6)),
            warnings: Array(warnings.prefix(4)),
            recommendedActions: Array(actions),
            confidenceNote: diary.dataQualityNote,
            riskLevel: nil,
            sourceDigest: compactTexts([diary.summary], firstNonEmpty(pe?.summary).map { [$0] } ?? []).joined(separator: " "),
            hasEnoughData: diary.hasEnoughData || (pe?.hasEnoughData ?? false)
        )
    }
}

@MainActor
enum CoverageAuditEvidenceBuilder {
    static func build(bridge: KmpBridge, classId: Int64?) async throws -> TeachingEvidencePack {
        guard let classId else {
            return TeachingEvidencePack(useCase: .coverageAudit, title: "Auditoría de cobertura evaluativa", subtitle: "Sin grupo activo", summary: "Selecciona un grupo para revisar huecos de cobertura.", metrics: [], factsUsed: [FactItem(text: "No hay clase activa.")], warnings: [WarningItem(text: "La auditoría necesita un grupo seleccionado.")], recommendedActions: [], confidenceNote: "Sin grupo activo.", riskLevel: nil, sourceDigest: "Sin grupo activo.", hasEnoughData: false)
        }
        let reportContext = try await bridge.buildReportGenerationContext(classId: classId, kind: .groupOverview, termLabel: nil)
        let evaluationContext = try await bridge.buildEvaluationAIContext(classId: classId)
        let facts = compactTexts(reportContext.factLines, evaluationContext.factLines).map(FactItem.init)
        let warnings = compactTexts(reportContext.needsAttention, evaluationContext.supportNotes, evaluationContext.dataQualityNote.map { [$0] } ?? []).map(WarningItem.init)
        let actions = compactTexts(reportContext.recommendedActions, ["Añadir evidencias nuevas antes del siguiente informe si aparecen huecos de cobertura."]).map(RecommendedActionItem.init)
        return TeachingEvidencePack(
            useCase: .coverageAudit,
            title: "Auditoría de cobertura evaluativa",
            subtitle: reportContext.className,
            summary: "Lectura rápida de cobertura usando estructura evaluativa y evidencias registradas en el grupo.",
            metrics: evaluationContext.metrics,
            factsUsed: Array(facts.prefix(8)),
            warnings: Array(warnings.prefix(4)),
            recommendedActions: Array(actions.prefix(4)),
            confidenceNote: reportContext.dataQualityNote ?? evaluationContext.dataQualityNote,
            riskLevel: nil,
            sourceDigest: compactTexts([reportContext.summary, evaluationContext.summary]).joined(separator: " "),
            hasEnoughData: reportContext.hasEnoughData || evaluationContext.hasEnoughData
        )
    }
}

@MainActor
final class AppleFoundationTeachingAssistantService {
    private let contextualService = AppleFoundationContextualAIService()
    private let reportService = AppleFoundationReportService()
    private let analyticsService = AppleFoundationAnalyticsService()

    func prewarm() {
        contextualService.prewarm()
        reportService.prewarm()
        analyticsService.prewarm()
    }

    func clearActiveConversation() {
        contextualService.clearActiveConversation()
        reportService.clearActiveConversation()
    }

    func canHandle(_ actionId: KmpBridge.ContextualAIAction.ActionID) -> Bool {
        switch actionId {
        case .dailyBriefing, .studentRiskRadar, .tutoringDraft, .groupInsight, .sessionClosure:
            return true
        default:
            return false
        }
    }

    func generateDraft(for actionId: KmpBridge.ContextualAIAction.ActionID, bridge: KmpBridge, context: KmpBridge.ScreenAIContext, audience: AIReportAudience, tone: AIReportTone, customPrompt: String?) async throws -> TeachingAssistantDraft {
        switch actionId {
        case .dailyBriefing:
            return try await contextualService.generateTeachingDraft(from: DailyBriefEvidenceBuilder.build(bridge: bridge, classId: context.classId), audience: audience, tone: tone, customPrompt: customPrompt)
        case .studentRiskRadar:
            guard let studentId = context.studentId else {
                throw AIContextualServiceError.insufficientContext("Selecciona un alumno para generar el radar de riesgo.")
            }
            return try await contextualService.generateTeachingDraft(from: StudentRiskEvidenceBuilder.build(bridge: bridge, classId: context.classId, studentId: studentId), audience: audience, tone: tone, customPrompt: customPrompt)
        case .tutoringDraft:
            guard let classId = context.classId else {
                throw AIReportServiceError.insufficientContext("Selecciona una clase antes de preparar un borrador de tutoría.")
            }
            let kind: KmpBridge.ReportKind = context.studentId == nil ? .groupOverview : .studentSummary
            let reportContext = try await bridge.buildReportGenerationContext(classId: classId, studentId: context.studentId, kind: kind, termLabel: nil)
            let draft = try await reportService.generateDraft(from: reportContext, audience: audience, tone: tone)
            return TeachingAssistantDraft(title: draft.title, subtitle: reportContext.studentName ?? reportContext.className, summary: draft.summary, factsUsed: Array(reportContext.factLines.prefix(6)), warnings: Array(reportContext.needsAttention.prefix(4)), recommendedActions: Array(draft.recommendedActions.prefix(4)), editableText: draft.editableText(for: reportContext), confidenceNote: reportContext.dataQualityNote, riskLevel: nil)
        case .groupInsight:
            let pack = try await GroupInsightEvidenceBuilder.build(bridge: bridge, classId: context.classId)
            guard let resolvedClassId = context.classId else {
                return try await contextualService.generateTeachingDraft(from: pack, audience: audience, tone: tone, customPrompt: customPrompt)
            }
            if let chart = try? await bridge.buildChartFacts(
                classId: resolvedClassId,
                request: KmpBridge.AnalyticsRequest(chartKind: .sameCourseComparison, timeRange: .last30Days, selectedClassIds: context.classId.map { [$0] } ?? [], selectedClassNames: context.className.map { [$0] } ?? [], prompt: nil, querySummary: "Comparativa global del grupo")
            ), chart.hasEnoughData {
                let insight = try? await analyticsService.generateInsight(from: chart)
                let enrichedPack = TeachingEvidencePack(useCase: pack.useCase, title: pack.title, subtitle: chart.subtitle, summary: insight?.insight ?? pack.summary, metrics: chart.metrics, factsUsed: pack.factsUsed, warnings: compactTexts(pack.warningTexts, insight?.warnings ?? []).map(WarningItem.init), recommendedActions: compactTexts(pack.recommendedActionTexts, insight?.recommendedActions ?? []).map(RecommendedActionItem.init), confidenceNote: pack.confidenceNote, riskLevel: nil, sourceDigest: compactTexts([pack.sourceDigest], firstNonEmpty(insight?.insertableSummary).map { [$0] } ?? []).joined(separator: " "), hasEnoughData: true)
                return try await contextualService.generateTeachingDraft(from: enrichedPack, audience: audience, tone: tone, customPrompt: customPrompt)
            }
            return try await contextualService.generateTeachingDraft(from: pack, audience: audience, tone: tone, customPrompt: customPrompt)
        case .sessionClosure:
            return try await contextualService.generateTeachingDraft(from: SessionClosureEvidenceBuilder.build(bridge: bridge, classId: context.classId), audience: audience, tone: tone, customPrompt: customPrompt)
        default:
            throw AIContextualServiceError.insufficientContext("Esta acción sigue usando el flujo contextual estándar.")
        }
    }

    func refineActiveDraft(with followUp: String) async throws -> TeachingAssistantDraft {
        do {
            return try await contextualService.refineActiveTeachingDraft(with: followUp)
        } catch AIContextualServiceError.insufficientContext {
            throw AIContextualServiceError.insufficientContext("No hay un borrador docente activo para refinar.")
        }
    }
}

struct AppleFoundationModelMessages {
    let disabled: String
    let available: String
    let frameworkUnavailable: String
    let unsupportedOS: String
    let unsupportedDevice: String
    let notEnabled: String
    let modelLoading: String

    func message(for availability: AppleFoundationModelAvailability) -> String {
        switch availability {
        case .disabled:
            return disabled
        case .available:
            return available
        case .frameworkUnavailable:
            return frameworkUnavailable
        case .unsupportedOS:
            return unsupportedOS
        case .unsupportedDevice:
            return unsupportedDevice
        case .notEnabled:
            return notEnabled
        case .modelLoading:
            return modelLoading
        case .unavailable(let message):
            return message
        }
    }
}

enum AppleFoundationModelSupport {
    static func resolveAvailability(isEnabled: Bool) -> AppleFoundationModelAvailability {
        guard isEnabled else {
            return .disabled
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .unsupportedDevice
                case .appleIntelligenceNotEnabled:
                    return .notEnabled
                case .modelNotReady:
                    return .modelLoading
                @unknown default:
                    return .unavailable("No se pudo determinar la disponibilidad del modelo local.")
                }
            @unknown default:
                return .unavailable("No se pudo determinar la disponibilidad del modelo local.")
            }
        } else {
            return .unsupportedOS
        }
        #else
        return .frameworkUnavailable
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    static func generationOptions(temperature: Double) -> GenerationOptions {
        GenerationOptions(temperature: temperature)
    }
    #endif
}

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
    let factsUsed: [String]
    let warnings: [String]
    let recommendedActions: [String]
    let editableText: String
    let confidenceNote: String?
}

struct NotebookAICommentDraft {
    let summary: String
    let strengths: [String]
    let needsAttention: [String]
    let nextSteps: [String]
    let factsUsed: [String]
    let warnings: [String]
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

@MainActor
final class AppleFoundationContextualAIService {
    private let availabilityMessages = AppleFoundationModelMessages(
        disabled: "La IA contextual está desactivada por feature flag local.",
        available: "Apple Foundation Models disponible para ayuda contextual.",
        frameworkUnavailable: "Este build no incluye el framework Foundation Models.",
        unsupportedOS: "La IA contextual requiere una versión del sistema compatible con Apple Foundation Models.",
        unsupportedDevice: "Apple Intelligence no está disponible en este dispositivo compatible con la app.",
        notEnabled: "Apple Intelligence está desactivado en el dispositivo. Actívalo en Ajustes para usar la IA contextual.",
        modelLoading: "Apple Intelligence se está preparando en este dispositivo. Vuelve a intentarlo en unos segundos."
    )
    private var availabilityRetryTask: Task<Void, Never>?

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private var cachedContextualSession: LanguageModelSession?

    @available(iOS 26.0, macOS 26.0, *)
    private var cachedNotebookSession: LanguageModelSession?

    @available(iOS 26.0, macOS 26.0, *)
    private var activeTeachingSession: LanguageModelSession?

    private var activeTeachingRiskLevel: RiskLevel?
    private var activeTeachingConfidenceFallback: String?

    @available(iOS 26.0, macOS 26.0, *)
    private func makeContextualSession() -> LanguageModelSession {
        LanguageModelSession(
            instructions: """
            Actúas como asistente contextual docente local-first.
            Usa exclusivamente los hechos proporcionados.
            No inventes causas, diagnósticos, sanciones ni comparaciones que no estén en el contexto.
            Si faltan datos, dilo con prudencia.
            Redacta en español de España.
            """
        )
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func makeNotebookSession() -> LanguageModelSession {
        LanguageModelSession(
            instructions: """
            Actúas como asistente de comentarios docentes para el cuaderno.
            Usa exclusivamente los hechos del contexto.
            No inventes diagnósticos, causas ni notas oficiales.
            Si faltan datos, reconoce la limitación con prudencia.
            El comentario debe ser breve, útil y editable por el profesorado.
            Redacta en español de España.
            """
        )
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func consumeContextualSession() -> LanguageModelSession {
        if let cachedContextualSession {
            self.cachedContextualSession = nil
            return cachedContextualSession
        }
        return makeContextualSession()
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func consumeNotebookSession() -> LanguageModelSession {
        if let cachedNotebookSession {
            self.cachedNotebookSession = nil
            return cachedNotebookSession
        }
        return makeNotebookSession()
    }
    #endif

    func currentAvailability() -> AIContextualAvailabilityState {
        let resolved = AppleFoundationModelSupport.resolveAvailability(isEnabled: AIContextualFeatureFlags.isEnabled)
        let state = mapAvailability(resolved)
        AIContextualTelemetry.recordAvailability(state)
        scheduleAvailabilityRetryIfNeeded(for: resolved)
        return state
    }

    func prewarm() {
        let resolved = AppleFoundationModelSupport.resolveAvailability(isEnabled: AIContextualFeatureFlags.isEnabled)
        scheduleAvailabilityRetryIfNeeded(for: resolved)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), resolved == .available || resolved == .modelLoading {
            if cachedContextualSession == nil {
                cachedContextualSession = makeContextualSession()
            }
            if cachedNotebookSession == nil {
                cachedNotebookSession = makeNotebookSession()
            }
        }
        #endif
    }

    func clearActiveConversation() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            activeTeachingSession = nil
        }
        #endif
        activeTeachingRiskLevel = nil
        activeTeachingConfidenceFallback = nil
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
        if #available(iOS 26.0, macOS 26.0, *) {
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
        if #available(iOS 26.0, macOS 26.0, *) {
            let result = try await generateLocalNotebookComment(from: context, audience: audience, tone: tone)
            AIContextualTelemetry.recordNotebookGeneration()
            return result
        }
        #endif
        throw AIContextualServiceError.unavailable("La IA contextual requiere una versión del sistema compatible con Apple Foundation Models.")
    }

    func generateTeachingDraft(
        from evidence: TeachingEvidencePack,
        audience: AIReportAudience,
        tone: AIReportTone,
        customPrompt: String?
    ) async throws -> TeachingAssistantDraft {
        guard evidence.hasEnoughData else {
            throw AIContextualServiceError.insufficientContext(
                evidence.confidenceNote ?? "Faltan datos suficientes para generar una propuesta docente grounded."
            )
        }
        let availability = currentAvailability()
        guard availability.isAvailable else {
            throw AIContextualServiceError.unavailable(availability.message)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await generateLocalTeachingDraft(
                from: evidence,
                audience: audience,
                tone: tone,
                customPrompt: customPrompt
            )
        }
        #endif
        throw AIContextualServiceError.unavailable("La IA contextual requiere una versión del sistema compatible con Apple Foundation Models.")
    }

    func refineActiveTeachingDraft(with followUp: String) async throws -> TeachingAssistantDraft {
        let cleaned = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw AIContextualServiceError.insufficientContext("Escribe cómo quieres refinar el borrador activo.")
        }
        let availability = currentAvailability()
        guard availability.isAvailable else {
            throw AIContextualServiceError.unavailable(availability.message)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await refineActiveTeachingDraftLocally(with: cleaned)
        }
        #endif
        throw AIContextualServiceError.unavailable("La IA contextual requiere una versión del sistema compatible con Apple Foundation Models.")
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func refineActiveTeachingDraftLocally(with cleaned: String) async throws -> TeachingAssistantDraft {
        guard let session = activeTeachingSession else {
            throw AIContextualServiceError.insufficientContext("No hay un borrador activo para refinar.")
        }
        let response = try await session.respond(
            to: """
            Refina el último borrador manteniendo estrictamente los mismos hechos verificables.
            Instrucción del docente: \(cleaned)

            No añadas hechos, causas, diagnósticos, sanciones ni etiquetas sensibles nuevas.
            Si la petición pide inventar información, recházala de forma prudente dentro del borrador.
            confidenceNote debe quedar vacío salvo que haya una limitación real de datos.
            """,
            generating: GeneratedTeachingAssistantDraft.self,
            includeSchemaInPrompt: true,
            options: AppleFoundationModelSupport.generationOptions(temperature: 0.2)
        )
        return mapTeachingDraft(
            response.content,
            riskLevel: activeTeachingRiskLevel,
            confidenceFallback: activeTeachingConfidenceFallback
        )
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func generateLocalResult(
        from context: KmpBridge.ScreenAIContext,
        action: KmpBridge.ContextualAIAction,
        audience: AIReportAudience,
        tone: AIReportTone,
        customPrompt: String?
    ) async throws -> ContextualAIResult {
        let session = consumeContextualSession()
        let response = try await session.respond(
            to: contextualPrompt(from: context, action: action, audience: audience, tone: tone, customPrompt: customPrompt),
            generating: GeneratedContextualAIResult.self,
            includeSchemaInPrompt: true,
            options: AppleFoundationModelSupport.generationOptions(temperature: 0.25)
        )
        let content = response.content
        let bulletBlock = content.bullets.map { "• \($0)" }.joined(separator: "\n")
        let actionBlock = content.recommendedActions.map { "• \($0)" }.joined(separator: "\n")
        return ContextualAIResult(
            title: content.title,
            subtitle: content.subtitle,
            summary: content.summary,
            bullets: content.bullets,
            factsUsed: content.factsUsed,
            warnings: content.warnings,
            recommendedActions: content.recommendedActions,
            editableText: """
            \(content.title)

            \(content.subtitle)

            \(content.summary)

            Puntos clave
            \(bulletBlock.isEmpty ? "• Sin puntos adicionales." : bulletBlock)

            Hechos usados
            \(content.factsUsed.isEmpty ? "• Sin hechos adicionales." : content.factsUsed.map { "• \($0)" }.joined(separator: "\n"))

            Alertas
            \(content.warnings.isEmpty ? "• Sin alertas adicionales." : content.warnings.map { "• \($0)" }.joined(separator: "\n"))

            Próximos pasos
            \(actionBlock.isEmpty ? "• Mantener observación y recogida de evidencias." : actionBlock)
            """,
            confidenceNote: normalizedOptional(content.confidenceNote)
        )
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func generateLocalNotebookComment(
        from context: KmpBridge.NotebookAICommentContext,
        audience: AIReportAudience,
        tone: AIReportTone
    ) async throws -> NotebookAICommentDraft {
        let session = consumeNotebookSession()
        let response = try await session.respond(
            to: notebookPrompt(from: context, audience: audience, tone: tone),
            generating: GeneratedNotebookCommentDraft.self,
            includeSchemaInPrompt: true,
            options: AppleFoundationModelSupport.generationOptions(temperature: 0.3)
        )
        let content = response.content
        return NotebookAICommentDraft(
            summary: content.summary,
            strengths: content.strengths,
            needsAttention: content.needsAttention,
            nextSteps: content.nextSteps,
            factsUsed: content.factsUsed,
            warnings: content.warnings,
            commentText: content.commentText
        )
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func generateLocalTeachingDraft(
        from evidence: TeachingEvidencePack,
        audience: AIReportAudience,
        tone: AIReportTone,
        customPrompt: String?
    ) async throws -> TeachingAssistantDraft {
        let session = makeContextualSession()
        activeTeachingSession = session
        activeTeachingRiskLevel = evidence.riskLevel
        activeTeachingConfidenceFallback = evidence.confidenceNote
        let response = try await session.respond(
            to: teachingPrompt(from: evidence, audience: audience, tone: tone, customPrompt: customPrompt),
            generating: GeneratedTeachingAssistantDraft.self,
            includeSchemaInPrompt: true,
            options: AppleFoundationModelSupport.generationOptions(temperature: 0.2)
        )
        return mapTeachingDraft(response.content, riskLevel: evidence.riskLevel, confidenceFallback: evidence.confidenceNote)
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func mapTeachingDraft(
        _ content: GeneratedTeachingAssistantDraft,
        riskLevel: RiskLevel?,
        confidenceFallback: String?
    ) -> TeachingAssistantDraft {
        let factsBlock = content.factsUsed.map { "• \($0)" }.joined(separator: "\n")
        let warningBlock = content.warnings.map { "• \($0)" }.joined(separator: "\n")
        let actionBlock = content.recommendedActions.map { "• \($0)" }.joined(separator: "\n")

        return TeachingAssistantDraft(
            title: content.title,
            subtitle: content.subtitle,
            summary: content.summary,
            factsUsed: content.factsUsed,
            warnings: content.warnings,
            recommendedActions: content.recommendedActions,
            editableText: """
            \(content.title)

            \(content.subtitle)

            \(content.summary)

            Hechos usados
            \(factsBlock.isEmpty ? "• Sin hechos adicionales." : factsBlock)

            Alertas
            \(warningBlock.isEmpty ? "• Sin alertas adicionales." : warningBlock)

            Próximas acciones
            \(actionBlock.isEmpty ? "• Mantener seguimiento prudente." : actionBlock)
            """,
            confidenceNote: normalizedOptional(content.confidenceNote) ?? confidenceFallback,
            riskLevel: riskLevel
        )
    }

    @available(iOS 26.0, macOS 26.0, *)
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

    @available(iOS 26.0, macOS 26.0, *)
    private func notebookPrompt(
        from context: KmpBridge.NotebookAICommentContext,
        audience: AIReportAudience,
        tone: AIReportTone
    ) -> String {
        let evidence = NotebookCommentEvidenceBuilder.build(from: context)
        let values = context.relevantValues.map { "- \($0.title) [\($0.categoryLabel)]: \($0.value)" }.joined(separator: "\n")
        let competencies = context.competencyLabels.map { "- \($0)" }.joined(separator: "\n")
        let facts = evidence.factTexts.map { "- \($0)" }.joined(separator: "\n")
        let warnings = evidence.warningTexts.map { "- \($0)" }.joined(separator: "\n")
        let actions = evidence.recommendedActionTexts.map { "- \($0)" }.joined(separator: "\n")

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

        Hechos usados
        \(facts.isEmpty ? "- Sin hechos adicionales." : facts)

        Advertencias
        \(warnings.isEmpty ? "- Sin advertencias adicionales." : warnings)

        Próximas acciones sugeridas
        \(actions.isEmpty ? "- Mantener seguimiento prudente." : actions)

        Comentario previo
        \(normalizedOptional(context.existingComment) ?? "Sin comentario previo.")

        Requisitos
        - commentText: 3 o 4 frases máximo, tono profesional y positivo.
        - strengths: entre 1 y 3 fortalezas observables.
        - needsAttention: entre 0 y 3 aspectos a vigilar, en positivo.
        - nextSteps: entre 1 y 3 pasos siguientes concretos.
        - factsUsed: entre 2 y 5 hechos realmente utilizados.
        - warnings: entre 0 y 3 advertencias prudentes.
        - No menciones una nota oficial ni inventes causas.
        """
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func teachingPrompt(
        from evidence: TeachingEvidencePack,
        audience: AIReportAudience,
        tone: AIReportTone,
        customPrompt: String?
    ) -> String {
        let metrics = evidence.metrics.map { "- \($0.title): \($0.value)" }.joined(separator: "\n")
        let facts = evidence.factTexts.map { "- \($0)" }.joined(separator: "\n")
        let warnings = evidence.warningTexts.map { "- \($0)" }.joined(separator: "\n")
        let actions = evidence.recommendedActionTexts.map { "- \($0)" }.joined(separator: "\n")

        return """
        Genera una ayuda docente grounded y accionable.

        Caso de uso: \(evidence.useCase.title)
        Título base: \(evidence.title)
        Subtítulo base: \(evidence.subtitle)
        Audiencia: \(audience.promptLabel)
        Tono: \(tone.rawValue)
        Nivel de riesgo: \(evidence.riskLevel?.title ?? "No aplica")

        Resumen base
        \(evidence.summary)

        Métricas
        \(metrics.isEmpty ? "- Sin métricas estructuradas." : metrics)

        Hechos verificables
        \(facts.isEmpty ? "- Sin hechos adicionales." : facts)

        Advertencias prudentes
        \(warnings.isEmpty ? "- Sin advertencias adicionales." : warnings)

        Próximas acciones sugeridas por reglas
        \(actions.isEmpty ? "- Mantener observación prudente." : actions)

        Nota de confianza
        \(evidence.confidenceNote ?? "Sin incidencias de calidad reseñables.")

        Variación pedida por el docente
        \(normalizedOptional(customPrompt) ?? "Sin variación adicional.")

        Requisitos
        - summary: 2 o 3 frases concretas.
        - factsUsed: entre 2 y 6 hechos realmente utilizados.
        - warnings: entre 0 y 4 advertencias prudentes.
        - recommendedActions: entre 1 y 4 acciones concretas.
        - confidenceNote: deja una cadena vacía salvo que haya una limitación real de datos; si la hay, una sola frase breve.
        - No inventes causas, diagnósticos, sanciones ni etiquetas sensibles.
        """
    }

    private func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func mapAvailability(_ availability: AppleFoundationModelAvailability) -> AIContextualAvailabilityState {
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
    struct GeneratedContextualAIResult {
        let title: String
        let subtitle: String
        let summary: String
        let bullets: [String]
        let factsUsed: [String]
        let warnings: [String]
        let recommendedActions: [String]
        let confidenceNote: String
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct GeneratedNotebookCommentDraft {
        let summary: String
        let strengths: [String]
        let needsAttention: [String]
        let nextSteps: [String]
        let factsUsed: [String]
        let warnings: [String]
        let commentText: String
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct GeneratedTeachingAssistantDraft {
        let title: String
        let subtitle: String
        let summary: String
        let factsUsed: [String]
        let warnings: [String]
        let recommendedActions: [String]
        let confidenceNote: String
    }
    #endif
}
