import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleFoundationModelAvailability: Equatable {
    case disabled
    case localInferenceDisabled
    case frameworkUnavailable
    case unsupportedOS
    case unsupportedDevice
    case notEnabled
    case modelLoading
    case available
    case unavailable(String)
}

extension Notification.Name {
    static let appleFoundationModelsRuntimeFailure = Notification.Name("appleFoundationModelsRuntimeFailure")
}

enum TeachingAssistantUseCase: String, Identifiable, CaseIterable {
    case dailyBriefing
    case studentRiskRadar
    case notebookComment
    case tutoringDraft
    case groupInsight
    case sessionClosure
    case coverageAudit
    case physicalScaleRecommendation

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
        case .physicalScaleRecommendation: return "Recomendación de baremo físico"
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

    func applyingAIBudget() -> TeachingEvidencePack {
        TeachingEvidencePack(
            useCase: useCase,
            title: title,
            subtitle: subtitle,
            summary: AIContextBudget.text(summary, limit: 500),
            metrics: Array(metrics.prefix(AIContextBudget.maxMetrics)),
            factsUsed: AIContextBudget.evidenceLines(factTexts).map(FactItem.init),
            warnings: AIContextBudget.lines(warningTexts, maxItems: AIContextBudget.maxWarnings, itemLimit: 140).map(WarningItem.init),
            recommendedActions: AIContextBudget.lines(recommendedActionTexts, maxItems: AIContextBudget.maxActions, itemLimit: 140).map(RecommendedActionItem.init),
            confidenceNote: confidenceNote.map { AIContextBudget.text($0, limit: 220) },
            riskLevel: riskLevel,
            sourceDigest: AIContextBudget.sourceDigest([sourceDigest]),
            hasEnoughData: hasEnoughData
        )
    }
}

enum AIContextBudget {
    static let maxMetrics = 4
    static let maxFacts = 8
    static let maxWarnings = 4
    static let maxActions = 4
    static let maxCharts = 3
    static let maxSourceDigestCharacters = 1_500
    static let maxIncludedEvidenceItems = 8
    static let maxPromptCharacters = 6_000

    static func lines(_ lines: [String], maxItems: Int, itemLimit: Int) -> [String] {
        lines
            .map { text($0, limit: itemLimit) }
            .filter { !$0.isEmpty }
            .prefix(maxItems)
            .map { $0 }
    }

    static func evidenceLines(_ lines: [String]) -> [String] {
        self.lines(lines, maxItems: maxIncludedEvidenceItems, itemLimit: 180)
    }

    static func sourceDigest(_ groups: [String]...) -> String {
        var seen = Set<String>()
        let compacted = groups
            .flatMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
        return text(compacted.joined(separator: " "), limit: maxSourceDigestCharacters)
    }

    static func prompt(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxPromptCharacters else { return trimmed }
        return "\(trimmed.prefix(maxPromptCharacters))..."
    }

    static func text(_ value: String, limit: Int) -> String {
        let normalized = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard normalized.count > limit else { return normalized }
        return "\(normalized.prefix(limit))..."
    }
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
        let facts = AIContextBudget.lines(
            compactTexts(dashboard.factLines, Array(diary.factLines.prefix(2)), Array(evaluation.factLines.prefix(2))),
            maxItems: AIContextBudget.maxFacts,
            itemLimit: 180
        ).map(FactItem.init)
        let warnings = AIContextBudget.lines(compactTexts(
            dashboard.supportNotes,
            diary.supportNotes,
            dashboard.dataQualityNote.map { [$0] } ?? [],
            diary.dataQualityNote.map { [$0] } ?? [],
            evaluation.dataQualityNote.map { [$0] } ?? []
        ), maxItems: AIContextBudget.maxWarnings, itemLimit: 140).map(WarningItem.init)
        let actions = AIContextBudget.lines(compactTexts(
            dashboard.suggestedActions.map(\.subtitle),
            diary.suggestedActions.map(\.subtitle),
            evaluation.suggestedActions.map(\.subtitle)
        ), maxItems: AIContextBudget.maxActions, itemLimit: 140).map(RecommendedActionItem.init)
        return TeachingEvidencePack(
            useCase: .dailyBriefing,
            title: "Briefing docente diario",
            subtitle: dashboard.className ?? dashboard.subtitle,
            summary: "Panorámica breve del día con foco en prioridad operativa, seguimiento y evaluación pendiente.",
            metrics: Array(dashboard.metrics.prefix(AIContextBudget.maxMetrics)),
            factsUsed: facts,
            warnings: Array(warnings),
            recommendedActions: Array(actions),
            confidenceNote: firstNonEmpty(dashboard.dataQualityNote, diary.dataQualityNote, evaluation.dataQualityNote),
            riskLevel: nil,
            sourceDigest: AIContextBudget.sourceDigest([dashboard.summary, diary.summary, evaluation.summary]),
            hasEnoughData: dashboard.hasEnoughData || diary.hasEnoughData || evaluation.hasEnoughData
        )
    }
}

@MainActor
enum StudentRiskEvidenceBuilder {
    static func build(bridge: KmpBridge, classId: Int64?, studentId: Int64) async throws -> TeachingEvidencePack {
        let profile = try await bridge.loadStudentProfile(studentId: studentId, classId: classId)
        let level = classify(profile: profile)
        let trends = try? await bridge.getAITrendsAndMetrics(classId: classId ?? 0, studentId: studentId)
        
        var factTexts = compactTexts(
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
        )
        
        if let trends {
            if trends.trendDirection == "UPWARD" {
                factTexts.append("Trayectoria de notas en el período: ascendente (+ \(IosFormatting.decimal(from: trends.averageGradeDelta)) pt).")
            } else if trends.trendDirection == "DOWNWARD" {
                factTexts.append("Trayectoria de notas en el período: descendente (- \(IosFormatting.decimal(from: abs(trends.averageGradeDelta))) pt).")
            } else if trends.trendDirection == "STABLE" {
                factTexts.append("Trayectoria de rendimiento: estable.")
            }
            factTexts.append("Cobertura curricular evaluada: \(IosFormatting.decimal(from: trends.curriculumCoveragePct))%.")
            if !trends.missingCompetencyLabels.isEmpty {
                factTexts.append("Competencias sin evaluar en cuaderno: \(trends.missingCompetencyLabels.joined(separator: ", ")).")
            }
        }
        
        let facts = factTexts.map(FactItem.init)
        
        var warningTexts = riskSignals(profile: profile, level: level)
        if let trends {
            if trends.trendDirection == "DOWNWARD" {
                warningTexts.append("La tendencia del rendimiento académico muestra un descenso significativo de calificaciones.")
            }
            if trends.attendanceRate < 85.0 {
                warningTexts.append("La baja asistencia acumulada puede dificultar el alcance de los resultados de aprendizaje.")
            }
            if !trends.missingCompetencyLabels.isEmpty {
                warningTexts.append("Hay brechas de cobertura LOMLOE (faltan evidencias de competencias clave: \(trends.missingCompetencyLabels.joined(separator: ", "))).")
            }
        }
        let warnings = warningTexts.map(WarningItem.init)
        
        var actionTexts = recommendedActions(profile: profile, level: level)
        if let trends {
            if trends.trendDirection == "DOWNWARD" {
                actionTexts.append("Planificar una tutoría individual para revisar los factores de la bajada de rendimiento.")
            }
            if !trends.missingCompetencyLabels.isEmpty {
                actionTexts.append("Programar actividades o instrumentos específicos para evaluar los criterios pendientes de \(trends.missingCompetencyLabels.prefix(3).joined(separator: ", ")).")
            }
        }
        let actions = actionTexts.map(RecommendedActionItem.init)

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
            factsUsed: Array(facts.prefix(7)),
            warnings: Array(warnings.prefix(5)),
            recommendedActions: Array(actions.prefix(5)),
            confidenceNote: profile.instrumentsCount == 0 ? "La lectura es prudente porque todavía hay poca evidencia evaluativa." : nil,
            riskLevel: level,
            sourceDigest: AIContextBudget.sourceDigest([level.summarySentence], warnings.map(\.text), actions.map(\.text)),
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
        var factTexts = compactTexts(
            [
                context.averageScore.map { "Media registrada: \(IosFormatting.decimal(from: $0))." },
                context.attendanceStatus.map { "Último estado de asistencia: \($0)." },
                "Seguimientos activos: \(context.followUpCount).",
                "Incidencias registradas: \(context.incidentCount).",
                "Evidencias registradas: \(context.evidenceCount)."
            ].compactMap { $0 },
            context.relevantValues.prefix(4).map { "\($0.title) [\($0.categoryLabel)]: \($0.value)." },
            context.competencyLabels.prefix(3).map { "Competencia relacionada: \($0)." }
        )
        
        if let trends = context.trends {
            if trends.trendDirection == "UPWARD" {
                factTexts.append("Rendimiento académico con progresión ascendente (+ \(IosFormatting.decimal(from: trends.averageGradeDelta)) pt).")
            } else if trends.trendDirection == "DOWNWARD" {
                factTexts.append("Rendimiento académico con progresión descendente (- \(IosFormatting.decimal(from: abs(trends.averageGradeDelta))) pt).")
            } else if trends.trendDirection == "STABLE" {
                factTexts.append("Rendimiento académico estable.")
            }
            factTexts.append("Cobertura curricular: \(IosFormatting.decimal(from: trends.curriculumCoveragePct))%.")
        }
        let facts = factTexts.map(FactItem.init)
        
        var warningTexts = compactTexts([
            context.dataQualityNote,
            context.relevantValues.isEmpty ? "Hay pocas columnas visibles con dato para este alumno." : nil,
            context.evidenceCount == 0 ? "No constan evidencias adjuntas en el periodo visible." : nil
        ].compactMap { $0 })
        
        if let trends = context.trends {
            if trends.trendDirection == "DOWNWARD" {
                warningTexts.append("Alerta: La tendencia de rendimiento académico del alumno en el trimestre es descendente.")
            }
            if !trends.missingCompetencyLabels.isEmpty {
                warningTexts.append("Brechas LOMLOE: Quedan competencias clave sin evidencias en el cuaderno (\(trends.missingCompetencyLabels.joined(separator: ", "))).")
            }
        }
        let warnings = warningTexts.map(WarningItem.init)
        
        var actionTexts = compactTexts([
            context.followUpCount > 0 ? "Mantener continuidad en el seguimiento individual." : nil,
            context.incidentCount > 0 ? "Conectar el comentario con observaciones verificables, no con causas supuestas." : nil,
            context.evidenceCount <= 1 ? "Añadir nuevas evidencias antes de cerrar una valoración más firme." : nil
        ].compactMap { $0 })
        
        if let trends = context.trends {
            if trends.trendDirection == "DOWNWARD" {
                actionTexts.append("Reforzar el apoyo individual y repasar tareas pendientes.")
            }
            if !trends.missingCompetencyLabels.isEmpty {
                actionTexts.append("Añadir nuevos instrumentos de evaluación para cubrir competencias pendientes.")
            }
        }
        let actions = actionTexts.map(RecommendedActionItem.init)
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
            sourceDigest: AIContextBudget.sourceDigest([context.summary], facts.map(\.text)),
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
        let selectedCharts = Array(charts.prefix(AIContextBudget.maxCharts))
        let facts = AIContextBudget.lines(
            selectedCharts.flatMap { chart in compactTexts(["\(chart.title): \(chart.teacherDigest)"], Array(chart.factLines.prefix(2))) },
            maxItems: AIContextBudget.maxFacts,
            itemLimit: 180
        ).map(FactItem.init)
        let warnings = AIContextBudget.lines(
            selectedCharts.flatMap { chart in compactTexts(chart.warnings, chart.emptyStateMessage.map { [$0] } ?? []) },
            maxItems: AIContextBudget.maxWarnings,
            itemLimit: 140
        ).map(WarningItem.init)
        let actions = AIContextBudget.lines(compactTexts([
            "Revisar primero el gráfico con más alertas o variación reciente.",
            "Cruzar asistencia, incidencias y evaluación antes de sacar conclusiones firmes.",
            "Usar este insight como apoyo de decisión, no como juicio automático."
        ]), maxItems: AIContextBudget.maxActions, itemLimit: 140).map(RecommendedActionItem.init)
        return TeachingEvidencePack(
            useCase: .groupInsight,
            title: "Inspector analítico del grupo",
            subtitle: selectedCharts.first?.subtitle ?? "Patrones del grupo",
            summary: "Lectura guiada del grupo a partir de paneles analíticos ya disponibles y hechos verificables.",
            metrics: Array((selectedCharts.first?.metrics ?? []).prefix(AIContextBudget.maxMetrics)),
            factsUsed: facts,
            warnings: warnings,
            recommendedActions: Array(actions),
            confidenceNote: selectedCharts.isEmpty ? "No hay paneles analíticos suficientes para una lectura fiable." : nil,
            riskLevel: nil,
            sourceDigest: AIContextBudget.sourceDigest(selectedCharts.map { $0.insertableSummary }),
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
            sourceDigest: AIContextBudget.sourceDigest([diary.summary], firstNonEmpty(pe?.summary).map { [$0] } ?? []),
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
        let facts = AIContextBudget.lines(
            compactTexts(Array(reportContext.factLines.prefix(AIContextBudget.maxFacts)), Array(evaluationContext.factLines.prefix(AIContextBudget.maxFacts))),
            maxItems: AIContextBudget.maxFacts,
            itemLimit: 180
        ).map(FactItem.init)
        let warnings = AIContextBudget.lines(
            compactTexts(Array(reportContext.needsAttention.prefix(AIContextBudget.maxWarnings)), evaluationContext.supportNotes, evaluationContext.dataQualityNote.map { [$0] } ?? []),
            maxItems: AIContextBudget.maxWarnings,
            itemLimit: 140
        ).map(WarningItem.init)
        let actions = AIContextBudget.lines(
            compactTexts(reportContext.recommendedActions, ["Añadir evidencias nuevas antes del siguiente informe si aparecen huecos de cobertura."]),
            maxItems: AIContextBudget.maxActions,
            itemLimit: 140
        ).map(RecommendedActionItem.init)
        return TeachingEvidencePack(
            useCase: .coverageAudit,
            title: "Auditoría de cobertura evaluativa",
            subtitle: reportContext.className,
            summary: "Lectura rápida de cobertura usando estructura evaluativa y evidencias registradas en el grupo.",
            metrics: Array(evaluationContext.metrics.prefix(AIContextBudget.maxMetrics)),
            factsUsed: facts,
            warnings: warnings,
            recommendedActions: actions,
            confidenceNote: reportContext.dataQualityNote ?? evaluationContext.dataQualityNote,
            riskLevel: nil,
            sourceDigest: AIContextBudget.sourceDigest([reportContext.summary, evaluationContext.summary]),
            hasEnoughData: reportContext.hasEnoughData || evaluationContext.hasEnoughData
        )
    }
}

@MainActor
final class AppleFoundationTeachingAssistantService {
    private let contextualService = AppleFoundationContextualAIService()
    private let aiOrchestrator = AppleAIOrchestrator()

    func prewarm() {
        contextualService.prewarm()
        aiOrchestrator.prewarmIfUseful(for: .analytics)
    }

    func clearActiveConversation() {
        contextualService.clearActiveConversation()
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
            let pack = try await DailyBriefEvidenceBuilder.build(bridge: bridge, classId: context.classId)
            return try await tracedTeachingDraft(pack, audience: audience, tone: tone, customPrompt: customPrompt)
        case .studentRiskRadar:
            guard let studentId = context.studentId else {
                throw AIContextualServiceError.insufficientContext("Selecciona un alumno para generar el radar de riesgo.")
            }
            let pack = try await StudentRiskEvidenceBuilder.build(bridge: bridge, classId: context.classId, studentId: studentId)
            return try await tracedTeachingDraft(pack, audience: audience, tone: tone, customPrompt: customPrompt)
        case .tutoringDraft:
            guard let classId = context.classId else {
                throw AIReportServiceError.insufficientContext("Selecciona una clase antes de preparar un borrador de tutoría.")
            }
            let kind: KmpBridge.ReportKind = context.studentId == nil ? .groupOverview : .studentSummary
            let reportContext = try await bridge.buildReportGenerationContext(classId: classId, studentId: context.studentId, kind: kind, termLabel: nil)
            let generation = try await aiOrchestrator.generateWithTrace(
                .report(reportContext, audience, tone),
                dataSource: reportContext.className,
                includedEvidence: AIContextBudget.evidenceLines(reportContext.factLines)
            )
            guard case .report(let draft) = generation.result else {
                throw AIContextualServiceError.insufficientContext("No se pudo preparar el borrador de tutoría.")
            }
            return TeachingAssistantDraft(title: draft.title, subtitle: reportContext.studentName ?? reportContext.className, summary: draft.summary, factsUsed: Array(reportContext.factLines.prefix(6)), warnings: Array(reportContext.needsAttention.prefix(4)), recommendedActions: Array(draft.recommendedActions.prefix(4)), editableText: draft.editableText(for: reportContext), confidenceNote: reportContext.dataQualityNote, riskLevel: nil)
        case .groupInsight:
            let pack = try await GroupInsightEvidenceBuilder.build(bridge: bridge, classId: context.classId)
            guard let resolvedClassId = context.classId else {
                return try await tracedTeachingDraft(pack, audience: audience, tone: tone, customPrompt: customPrompt)
            }
            if let chart = try? await bridge.buildChartFacts(
                classId: resolvedClassId,
                request: KmpBridge.AnalyticsRequest(chartKind: .sameCourseComparison, timeRange: .last30Days, selectedClassIds: context.classId.map { [$0] } ?? [], selectedClassNames: context.className.map { [$0] } ?? [], prompt: nil, querySummary: "Comparativa global del grupo")
            ), chart.hasEnoughData {
                let generation = try? await aiOrchestrator.generateWithTrace(
                    .chartInsight(chart),
                    dataSource: chart.subtitle,
                    includedEvidence: AIContextBudget.evidenceLines(chart.factLines)
                )
                let insight: AIChartInsight? = {
                    guard case .chartInsight(let value) = generation?.result else { return nil }
                    return value
                }()
                let enrichedPack = TeachingEvidencePack(useCase: pack.useCase, title: pack.title, subtitle: chart.subtitle, summary: insight?.insight ?? pack.summary, metrics: chart.metrics, factsUsed: pack.factsUsed, warnings: compactTexts(pack.warningTexts, insight?.warnings ?? []).map(WarningItem.init), recommendedActions: compactTexts(pack.recommendedActionTexts, insight?.recommendedActions ?? []).map(RecommendedActionItem.init), confidenceNote: pack.confidenceNote, riskLevel: nil, sourceDigest: AIContextBudget.sourceDigest([pack.sourceDigest], firstNonEmpty(insight?.insertableSummary).map { [$0] } ?? []), hasEnoughData: true).applyingAIBudget()
                return try await tracedTeachingDraft(enrichedPack, audience: audience, tone: tone, customPrompt: customPrompt)
            }
            return try await tracedTeachingDraft(pack, audience: audience, tone: tone, customPrompt: customPrompt)
        case .sessionClosure:
            let pack = try await SessionClosureEvidenceBuilder.build(bridge: bridge, classId: context.classId)
            return try await tracedTeachingDraft(pack, audience: audience, tone: tone, customPrompt: customPrompt)
        default:
            throw AIContextualServiceError.insufficientContext("Esta acción sigue usando el flujo contextual estándar.")
        }
    }

    func generateDailyBriefingDraft(bridge: KmpBridge, classId: Int64?, audience: AIReportAudience, tone: AIReportTone, customPrompt: String?) async throws -> TeachingAssistantDraft {
        let pack = try await DailyBriefEvidenceBuilder.build(bridge: bridge, classId: classId)
        return try await tracedTeachingDraft(pack, audience: audience, tone: tone, customPrompt: customPrompt)
    }

    func refineActiveDraft(with followUp: String) async throws -> TeachingAssistantDraft {
        do {
            return try await contextualService.refineActiveTeachingDraft(with: followUp)
        } catch AIContextualServiceError.insufficientContext {
            throw AIContextualServiceError.insufficientContext("No hay un borrador docente activo para refinar.")
        }
    }

    private func tracedTeachingDraft(_ pack: TeachingEvidencePack, audience: AIReportAudience, tone: AIReportTone, customPrompt: String?) async throws -> TeachingAssistantDraft {
        let budgetedPack = pack.applyingAIBudget()
        let generation = try await aiOrchestrator.generateWithTrace(
            .teachingDraft(budgetedPack, audience, tone, customPrompt),
            dataSource: budgetedPack.subtitle,
            includedEvidence: AIContextBudget.evidenceLines(budgetedPack.factTexts)
        )
        guard case .teachingDraft(let draft) = generation.result else {
            throw AIContextualServiceError.insufficientContext("No se pudo generar el borrador docente.")
        }
        return draft
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
        case .localInferenceDisabled:
            return "Apple Foundation Models está desactivado en Ajustes de la app."
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
    static let localInferenceEnabledDefaultsKey = "apple.foundation.models.localInference.enabled"
    static let reportsEnabledDefaultsKey = "reports.ai.enabled"
    static let contextualEnabledDefaultsKey = "contextual.ai.enabled"
    static let analyticsEnabledDefaultsKey = "analytics.ai.enabled"

    private static var cachedAvailability: (checkedAt: Date, value: AppleFoundationModelAvailability)?
    private static var runtimeUnavailableUntil: Date?
    private static var runtimeUnavailableKind: String?
    private static let availableCacheWindow: TimeInterval = 300
    private static let unavailableCacheWindow: TimeInterval = 300
    private static let runtimeFailureCooldown: TimeInterval = 300
    private static let assetsUnavailableCooldown: TimeInterval =
        ProcessInfo.processInfo.environment["DEBUG_AI_COOLDOWN"] != nil ? 30 : 900

    static func resolveAvailability(isEnabled: Bool) -> AppleFoundationModelAvailability {
        guard isEnabled else {
            return .disabled
        }
        guard isLocalInferenceEnabled else {
            return .localInferenceDisabled
        }

        let now = Date()
        if let runtimeUnavailableUntil, runtimeUnavailableUntil > now {
            return runtimeUnavailableAvailability(kind: runtimeUnavailableKind ?? "runtimeFailure")
        }
        if let cachedAvailability,
           now.timeIntervalSince(cachedAvailability.checkedAt) < cacheWindow(for: cachedAvailability.value) {
            return cachedAvailability.value
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let resolved: AppleFoundationModelAvailability
            switch SystemLanguageModel.default.availability {
            case .available:
                resolved = .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    resolved = .unsupportedDevice
                case .appleIntelligenceNotEnabled:
                    resolved = .notEnabled
                case .modelNotReady:
                    resolved = .modelLoading
                @unknown default:
                    resolved = .unavailable("No se pudo determinar la disponibilidad del modelo local.")
                }
            @unknown default:
                resolved = .unavailable("No se pudo determinar la disponibilidad del modelo local.")
            }
            cachedAvailability = (now, resolved)
            return resolved
        } else {
            return .unsupportedOS
        }
        #else
        return .frameworkUnavailable
        #endif
    }

    private static func cacheWindow(for availability: AppleFoundationModelAvailability) -> TimeInterval {
        availability == .available ? availableCacheWindow : unavailableCacheWindow
    }

    static var isLocalInferenceEnabled: Bool {
        if ProcessInfo.processInfo.environment["ENABLE_APPLE_FOUNDATION_MODELS"] == "1" {
            return true
        }
        if UserDefaults.standard.object(forKey: localInferenceEnabledDefaultsKey) != nil {
            return UserDefaults.standard.bool(forKey: localInferenceEnabledDefaultsKey)
        }
        return true
    }

    static func setLocalInferenceEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: localInferenceEnabledDefaultsKey)
        clearCachedAvailability()
    }

    static func clearCachedAvailability() {
        cachedAvailability = nil
    }

    static var lastRuntimeFailureKind: String? {
        runtimeUnavailableKind
    }

    static var runtimeCooldownRemaining: TimeInterval? {
        guard let runtimeUnavailableUntil else { return nil }
        let remaining = runtimeUnavailableUntil.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    static func diagnosticSummary() -> String {
        let availability = resolveAvailability(isEnabled: true)
        if let remaining = runtimeCooldownRemaining {
            return "\(diagnosticTitle(for: availability)) · reintento en \(Int(remaining.rounded(.up))) s"
        }
        return diagnosticTitle(for: availability)
    }

    static func diagnosticTitle(for availability: AppleFoundationModelAvailability) -> String {
        switch availability {
        case .disabled:
            return "Desactivado por módulo"
        case .localInferenceDisabled:
            return "Desactivado en Ajustes"
        case .frameworkUnavailable:
            return "Framework no incluido"
        case .unsupportedOS:
            return "Sistema no compatible"
        case .unsupportedDevice:
            return "Dispositivo no compatible"
        case .notEnabled:
            return "Apple Intelligence apagado"
        case .modelLoading:
            return "Preparando modelo"
        case .available:
            return "Disponible"
        case .unavailable:
            return "No responde"
        }
    }

    static func recordRuntimeFailure(_ error: Error) {
        let failureKind = runtimeFailureKind(for: error)
        let cooldown = cooldown(for: failureKind)
        runtimeUnavailableKind = failureKind
        runtimeUnavailableUntil = Date().addingTimeInterval(cooldown)
        cachedAvailability = (
            Date(),
            runtimeUnavailableAvailability(kind: failureKind)
        )
        if failureKind == "assetsUnavailable" {
            NotificationCenter.default.post(name: .appleFoundationModelsRuntimeFailure, object: failureKind)
        }
        debugPrint("[AppleFoundationModels] runtime unavailable [\(failureKind), cooldown: \(Int(cooldown))s]: \(error.localizedDescription)")
    }

    static func runtimeFailureKind(for error: Error) -> String {
        let description = "\(String(reflecting: error)) \(error.localizedDescription)".lowercased()
        let knownGenerationErrors: [(needle: String, label: String)] = [
            ("assetsunavailable", "assetsUnavailable"),
            ("assets unavailable", "assetsUnavailable"),
            ("decodingfailure", "decodingFailure"),
            ("decoding failure", "decodingFailure"),
            ("exceededcontextwindowsize", "exceededContextWindowSize"),
            ("context window", "exceededContextWindowSize"),
            ("guardrailviolation", "guardrailViolation"),
            ("guardrail", "guardrailViolation"),
            ("ratelimited", "rateLimited"),
            ("rate limited", "rateLimited"),
            ("refusal", "refusal"),
            ("concurrentrequests", "concurrentRequests"),
            ("concurrent requests", "concurrentRequests"),
            ("unsupportedlanguageorlocale", "unsupportedLanguageOrLocale"),
            ("unsupported language", "unsupportedLanguageOrLocale"),
            ("afisdevicegreymattereligible", "deviceNotEligible"),
            ("greymatter", "deviceNotEligible"),
            ("os_eligibility", "deviceNotEligible"),
            ("com.apple.modelcatalog.catalog code=4097", "assetsUnavailable"),
            ("connection to service named com.apple.modelcatalog.catalog", "assetsUnavailable"),
            ("modelcatalog.catalog", "assetsUnavailable"),
            ("nscocoaerrordomain code=4097", "assetsUnavailable"),
            ("xpc server interrupted", "assetsUnavailable")
        ]
        return knownGenerationErrors.first { description.contains($0.needle) }?.label ?? "runtimeFailure"
    }

    private static func cooldown(for failureKind: String) -> TimeInterval {
        failureKind == "assetsUnavailable" ? assetsUnavailableCooldown : runtimeFailureCooldown
    }

    private static func runtimeUnavailableAvailability(kind: String) -> AppleFoundationModelAvailability {
        if kind == "assetsUnavailable" {
            return .unavailable("Los modelos locales de Apple Intelligence no responden ahora mismo. Se usará el flujo manual y se reintentará más tarde.")
        }
        if kind == "deviceNotEligible" {
            return .unsupportedDevice
        }
        return .unavailable("Apple Foundation Models no está respondiendo ahora mismo. Se usará el flujo manual y se reintentará más tarde.")
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

struct PhysicalScaleRecommendationInput: Hashable {
    var testId: String
    var testName: String
    var capacity: String
    var measurementKind: String
    var unit: String
    var directionLabel: String
    var sex: String
    var course: String
    var ageFrom: Int?
    var ageTo: Int?
    var objective: String
    var scoreScale: String = "0-10"
}

struct PhysicalScaleRecommendedRange: Identifiable, Hashable {
    let id = UUID()
    var minValue: Double?
    var maxValue: Double?
    var score: Double
    var label: String
}

struct PhysicalScaleRecommendationDraft: Hashable {
    var title: String
    var summary: String
    var ranges: [PhysicalScaleRecommendedRange]
    var explanation: String
    var warnings: [String]
    var editableProposal: String
}

struct PhysicalProgressMetric: Identifiable, Hashable {
    let id: String
    let testName: String
    let average: Double
    let best: Double?
    let recordedCount: Int
    let totalCount: Int
    let directionLabel: String
}

struct PhysicalProgressEvidence: Hashable {
    let className: String
    let termLabel: String?
    let metrics: [PhysicalProgressMetric]

    var recordedCount: Int {
        metrics.reduce(0) { $0 + $1.recordedCount }
    }

    var totalCount: Int {
        metrics.reduce(0) { $0 + $1.totalCount }
    }

    var completionRate: Double {
        guard totalCount > 0 else { return 0 }
        return Double(recordedCount) / Double(totalCount) * 100
    }

    var hasEnoughData: Bool {
        metrics.contains { $0.recordedCount > 0 }
    }

    var evidenceLines: [String] {
        var lines = [
            "Grupo: \(className)",
            "Evaluación: \(termLabel ?? "No especificada")",
            "Cobertura de registros: \(IosFormatting.decimal(from: completionRate))%"
        ]
        lines += metrics.prefix(8).map { metric in
            let bestText = metric.best.map { IosFormatting.decimal(from: $0) } ?? "sin mejor marca"
            return "\(metric.testName): media \(IosFormatting.decimal(from: metric.average)), mejor \(bestText), registros \(metric.recordedCount)/\(metric.totalCount), dirección \(metric.directionLabel)"
        }
        return AIContextBudget.evidenceLines(lines)
    }
}

struct PhysicalProgressAnalysis: Codable, Hashable, Sendable {
    let summary: String
    let trend: String
    let improvementPercentage: Double?
    let strengths: [String]
    let weaknesses: [String]
    let recommendations: [String]
    let alerts: [String]
    let confidenceNote: String

    init(
        summary: String,
        trend: String,
        improvementPercentage: Double?,
        strengths: [String],
        weaknesses: [String],
        recommendations: [String],
        alerts: [String],
        confidenceNote: String
    ) {
        self.summary = AppleAIOutputNormalizer.nonEmpty(summary, fallback: "Análisis EF no disponible.")
        self.trend = AppleAIOutputNormalizer.nonEmpty(trend, fallback: "Sin tendencia suficiente.")
        self.improvementPercentage = improvementPercentage
        self.strengths = AppleAIOutputNormalizer.compactLimited(strengths, limit: 4)
        self.weaknesses = AppleAIOutputNormalizer.compactLimited(weaknesses, limit: 4)
        self.recommendations = AppleAIOutputNormalizer.compactLimited(recommendations, limit: 4)
        self.alerts = AppleAIOutputNormalizer.compactLimited(alerts, limit: 3)
        self.confidenceNote = AppleAIOutputNormalizer.nonEmpty(
            confidenceNote,
            fallback: "Confianza basada en marcas registradas."
        )
    }
}

extension PhysicalProgressAnalysis {
    var appearsToBeRulesFallback: Bool {
        confidenceNote.localizedCaseInsensitiveContains("reglas") ||
        confidenceNote.localizedCaseInsensitiveContains("faltan marcas")
    }
}

struct StudentSexInferenceDraft: Hashable {
    var sex: String
    var confidence: Double
    var reason: String
    var warning: String
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
    private var cachedContextualSessionStorage: Any?
    private var cachedNotebookSessionStorage: Any?
    private var activeTeachingSessionStorage: Any?
    #endif

    private var activeTeachingRiskLevel: RiskLevel?
    private var activeTeachingConfidenceFallback: String?
    private var contextualPromptCache: [String: String] = [:]
    private var notebookPromptCache: [String: String] = [:]
    private var runtimeFailureObserver: NSObjectProtocol?

    init() {
        #if canImport(FoundationModels)
        runtimeFailureObserver = NotificationCenter.default.addObserver(
            forName: .appleFoundationModelsRuntimeFailure,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.clearCachedSessions()
            }
        }
        #endif
    }

    deinit {
        if let runtimeFailureObserver {
            NotificationCenter.default.removeObserver(runtimeFailureObserver)
        }
    }

    #if canImport(FoundationModels)
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
        if let cachedContextualSession = cachedContextualSessionStorage as? LanguageModelSession {
            self.cachedContextualSessionStorage = nil
            return cachedContextualSession
        }
        return makeContextualSession()
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func consumeNotebookSession() -> LanguageModelSession {
        if let cachedNotebookSession = cachedNotebookSessionStorage as? LanguageModelSession {
            self.cachedNotebookSessionStorage = nil
            return cachedNotebookSession
        }
        return makeNotebookSession()
    }

    private func clearCachedSessions() {
        cachedContextualSessionStorage = nil
        cachedNotebookSessionStorage = nil
        activeTeachingSessionStorage = nil
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
        if #available(iOS 26.0, macOS 26.0, *), resolved == .available {
            if cachedContextualSessionStorage == nil {
                cachedContextualSessionStorage = makeContextualSession()
            }
            if cachedNotebookSessionStorage == nil {
                cachedNotebookSessionStorage = makeNotebookSession()
            }
        }
        #endif
    }

    func clearActiveConversation() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            activeTeachingSessionStorage = nil
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
            return fallbackResult(from: context, action: action)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let result = try await generateLocalResult(
                    from: context,
                    action: action,
                    audience: audience,
                    tone: tone,
                    customPrompt: customPrompt
                )
                AIContextualTelemetry.recordScreenGeneration(kind: context.kind, action: action.actionId)
                return result
            } catch {
                AppleFoundationModelSupport.recordRuntimeFailure(error)
                return fallbackResult(from: context, action: action)
            }
        }
        #endif
        return fallbackResult(from: context, action: action)
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
            return fallbackNotebookComment(from: context)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let result = try await generateLocalNotebookComment(from: context, audience: audience, tone: tone)
                AIContextualTelemetry.recordNotebookGeneration()
                return result
            } catch {
                AppleFoundationModelSupport.recordRuntimeFailure(error)
                return fallbackNotebookComment(from: context)
            }
        }
        #endif
        return fallbackNotebookComment(from: context)
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
            return fallbackTeachingDraft(from: evidence)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                return try await generateLocalTeachingDraft(
                    from: evidence,
                    audience: audience,
                    tone: tone,
                    customPrompt: customPrompt
                )
            } catch {
                AppleFoundationModelSupport.recordRuntimeFailure(error)
                return fallbackTeachingDraft(from: evidence)
            }
        }
        #endif
        return fallbackTeachingDraft(from: evidence)
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

    func generatePhysicalScaleRecommendation(
        from input: PhysicalScaleRecommendationInput
    ) async throws -> PhysicalScaleRecommendationDraft {
        let seedRanges = PhysicalScaleProfileCatalog.seedRanges(for: input)
        let availability = currentAvailability()
        guard availability.isAvailable else {
            return fallbackPhysicalScaleRecommendation(from: input, seedRanges: seedRanges)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await generateLocalPhysicalScaleRecommendation(from: input, seedRanges: seedRanges)
        }
        #endif
        return fallbackPhysicalScaleRecommendation(from: input, seedRanges: seedRanges)
    }

    func generatePhysicalProgressAnalysis(
        from evidence: PhysicalProgressEvidence
    ) async throws -> PhysicalProgressAnalysis {
        guard evidence.hasEnoughData else {
            return fallbackPhysicalProgressAnalysis(from: evidence, reason: "Faltan marcas suficientes para analizar evolución física.")
        }
        let availability = currentAvailability()
        guard availability.isAvailable else {
            return fallbackPhysicalProgressAnalysis(from: evidence, reason: "Generado por reglas porque la IA local no está disponible.")
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await generateLocalPhysicalProgressAnalysis(from: evidence)
        }
        #endif
        return fallbackPhysicalProgressAnalysis(from: evidence, reason: "Generado por reglas porque la IA local no está disponible.")
    }

    func inferStudentSex(firstName: String, lastName: String) async throws -> StudentSexInferenceDraft {
        let cleanedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return StudentSexInferenceDraft(
            sex: "UNSPECIFIED",
            confidence: 0,
            reason: cleanedFirstName.isEmpty ? "No hay nombre suficiente para configurar sexo." : "La app no infiere sexo por nombre.",
            warning: "Configura manualmente no especificado, masculino o femenino solo si se necesita para baremos físicos."
        )
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func refineActiveTeachingDraftLocally(with cleaned: String) async throws -> TeachingAssistantDraft {
        guard let session = activeTeachingSessionStorage as? LanguageModelSession else {
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
            to: cachedContextualPrompt(from: context, action: action, audience: audience, tone: tone, customPrompt: customPrompt),
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
            to: cachedNotebookPrompt(from: context, audience: audience, tone: tone),
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
        activeTeachingSessionStorage = session
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
    private func generateLocalPhysicalScaleRecommendation(
        from input: PhysicalScaleRecommendationInput,
        seedRanges: [PhysicalScaleRecommendedRange]
    ) async throws -> PhysicalScaleRecommendationDraft {
        let session = LanguageModelSession(
            instructions: """
            Actúas como asistente local para Educación Física.
            Generas propuestas orientativas de baremos editables, nunca oficiales.
            No inventes normativa, percentiles oficiales ni referencias legales.
            No generes baremos genéricos; adapta siempre los rangos al testId, unidad, edad, objetivo y dirección.
            Recomienda siempre revisión docente antes de usar la propuesta.
            Prioriza claridad, rangos simples y edición rápida.
            Redacta en español de España.
            """
        )
        do {
            let response = try await session.respond(
                to: physicalScalePrompt(from: input, seedRanges: seedRanges),
                generating: GeneratedPhysicalScaleRecommendation.self,
                includeSchemaInPrompt: true,
                options: AppleFoundationModelSupport.generationOptions(temperature: 0.1)
            )
            let mapped = mapPhysicalScaleRecommendation(response.content, input: input)
            guard PhysicalScaleProfileCatalog.isValid(ranges: mapped.ranges, for: input) else {
                return fallbackPhysicalScaleRecommendation(from: input, seedRanges: seedRanges)
            }
            return mapped
        } catch {
            AppleFoundationModelSupport.recordRuntimeFailure(error)
            return fallbackPhysicalScaleRecommendation(from: input, seedRanges: seedRanges)
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func generateLocalPhysicalProgressAnalysis(
        from evidence: PhysicalProgressEvidence
    ) async throws -> PhysicalProgressAnalysis {
        let session = LanguageModelSession(
            instructions: """
            Actúas como asistente local de Educación Física.
            Analizas progreso físico de grupo desde marcas objetivas ya calculadas por la app.
            No inventes mediciones, percentiles, diagnósticos ni normativa.
            Devuelve un objeto breve para SwiftUI con fortalezas, debilidades, recomendaciones y alertas.
            Redacta en español de España.
            """
        )
        do {
            let response = try await session.respond(
                to: physicalProgressPrompt(from: evidence),
                generating: GeneratedPhysicalProgressAnalysis.self,
                includeSchemaInPrompt: true,
                options: AppleFoundationModelSupport.generationOptions(temperature: 0.2)
            )
            return PhysicalProgressAnalysis(
                summary: response.content.summary,
                trend: response.content.trend,
                improvementPercentage: response.content.improvementPercentage,
                strengths: response.content.strengths,
                weaknesses: response.content.weaknesses,
                recommendations: response.content.recommendations,
                alerts: response.content.alerts,
                confidenceNote: response.content.confidenceNote
            )
        } catch {
            AppleFoundationModelSupport.recordRuntimeFailure(error)
            return fallbackPhysicalProgressAnalysis(from: evidence, reason: "Generado por reglas porque la IA local no está disponible.")
        }
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
        let metrics = context.metrics.prefix(4).map { "- \($0.title): \($0.value)" }.joined(separator: "\n")
        let facts = context.factLines.prefix(6).map { "- \($0)" }.joined(separator: "\n")
        let notes = context.supportNotes.prefix(3).map { "- \($0)" }.joined(separator: "\n")

        return AIContextBudget.prompt("""
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
        """)
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func cachedContextualPrompt(
        from context: KmpBridge.ScreenAIContext,
        action: KmpBridge.ContextualAIAction,
        audience: AIReportAudience,
        tone: AIReportTone,
        customPrompt: String?
    ) -> String {
        let key = [
            "screen",
            context.kind.rawValue,
            "\(context.classId ?? -1)",
            "\(context.studentId ?? -1)",
            action.actionId.rawValue,
            audience.rawValue,
            tone.rawValue,
            customPrompt ?? "",
            context.summary,
            context.metrics.map { "\($0.title):\($0.value)" }.joined(separator: "|"),
            AIContextBudget.evidenceLines(context.factLines).joined(separator: "|"),
            AIContextBudget.lines(context.supportNotes, maxItems: AIContextBudget.maxWarnings, itemLimit: 140).joined(separator: "|"),
            context.dataQualityNote ?? ""
        ].joined(separator: "¬").hashValue.description

        if let cached = contextualPromptCache[key] {
            NotebookGridPerformanceDebug.event("contextualAIPrompt hit")
            return cached
        }
        let prompt = contextualPrompt(from: context, action: action, audience: audience, tone: tone, customPrompt: customPrompt)
        contextualPromptCache[key] = prompt
        if contextualPromptCache.count > 8 {
            contextualPromptCache.removeValue(forKey: contextualPromptCache.keys.first ?? key)
        }
        return prompt
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func notebookPrompt(
        from context: KmpBridge.NotebookAICommentContext,
        audience: AIReportAudience,
        tone: AIReportTone
    ) -> String {
        let evidence = NotebookCommentEvidenceBuilder.build(from: context)
        let values = context.relevantValues.prefix(5).map { "- \($0.title) [\($0.categoryLabel)]: \($0.value)" }.joined(separator: "\n")
        let competencies = context.competencyLabels.prefix(3).map { "- \($0)" }.joined(separator: "\n")
        let facts = evidence.factTexts.map { "- \($0)" }.joined(separator: "\n")
        let warnings = evidence.warningTexts.map { "- \($0)" }.joined(separator: "\n")
        let actions = evidence.recommendedActionTexts.map { "- \($0)" }.joined(separator: "\n")

        return AIContextBudget.prompt("""
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
        """)
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func cachedNotebookPrompt(
        from context: KmpBridge.NotebookAICommentContext,
        audience: AIReportAudience,
        tone: AIReportTone
    ) -> String {
        let key = [
            "notebook",
            "\(context.classId)",
            "\(context.studentId)",
            audience.rawValue,
            tone.rawValue,
            context.summary,
            "\(context.averageScore ?? -1)",
            "\(context.followUpCount)",
            "\(context.incidentCount)",
            "\(context.evidenceCount)",
            context.relevantValues.prefix(5).map { "\($0.title):\($0.categoryLabel):\($0.value)" }.joined(separator: "|"),
            context.competencyLabels.prefix(3).joined(separator: "|"),
            context.dataQualityNote ?? "",
            context.existingComment ?? ""
        ].joined(separator: "¬").hashValue.description

        if let cached = notebookPromptCache[key] {
            NotebookGridPerformanceDebug.event("notebookAIPrompt hit")
            return cached
        }
        let prompt = notebookPrompt(from: context, audience: audience, tone: tone)
        notebookPromptCache[key] = prompt
        if notebookPromptCache.count > 8 {
            notebookPromptCache.removeValue(forKey: notebookPromptCache.keys.first ?? key)
        }
        return prompt
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func teachingPrompt(
        from evidence: TeachingEvidencePack,
        audience: AIReportAudience,
        tone: AIReportTone,
        customPrompt: String?
    ) -> String {
        let metrics = evidence.metrics.prefix(4).map { "- \($0.title): \($0.value)" }.joined(separator: "\n")
        let facts = evidence.factTexts.prefix(6).map { "- \($0)" }.joined(separator: "\n")
        let warnings = evidence.warningTexts.prefix(3).map { "- \($0)" }.joined(separator: "\n")
        let actions = evidence.recommendedActionTexts.prefix(3).map { "- \($0)" }.joined(separator: "\n")

        return AIContextBudget.prompt("""
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
        """)
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func physicalScalePrompt(
        from input: PhysicalScaleRecommendationInput,
        seedRanges: [PhysicalScaleRecommendedRange]
    ) -> String {
        let seeds = seedRanges.enumerated().map { index, range in
            let minText = range.minValue.map { String(format: "%.2f", $0) } ?? "null"
            let maxText = range.maxValue.map { String(format: "%.2f", $0) } ?? "null"
            return #"{"index":\#(index + 1),"minValue":\#(minText),"maxValue":\#(maxText),"score":\#(String(format: "%.1f", range.score)),"label":"\#(range.label)"}"#
        }.joined(separator: "\n")
        return AIContextBudget.prompt("""
        Genera una propuesta editable de baremo físico para el módulo Mediciones y baremos.
        Debes devolver exactamente la estructura generada por el schema, equivalente a JSON estricto.

        Caso de uso: \(TeachingAssistantUseCase.physicalScaleRecommendation.title)
        TestId: \(input.testId)
        Nombre del test: \(input.testName)
        Capacidad física: \(input.capacity)
        Tipo de medición: \(input.measurementKind)
        Unidad: \(input.unit)
        Dirección: \(input.directionLabel)
        Sexo del baremo: \(input.sex.isEmpty ? "Sin especificar" : input.sex)
        Curso: \(input.course)
        Edad desde: \(input.ageFrom.map(String.init) ?? "Sin dato")
        Edad hasta: \(input.ageTo.map(String.init) ?? "Sin dato")
        Objetivo: \(input.objective)
        Escala de nota: \(input.scoreScale)
        Perfil local: \(PhysicalScaleProfileCatalog.profileSummary(for: input))

        SeedRanges deterministas. Úsalos como base numérica; puedes ajustar etiquetas y explicación, pero mantén la familia de valores:
        \(seeds)

        Reglas obligatorias
        - La respuesta debe decir que es una propuesta orientativa.
        - La respuesta debe incluir que la revisión docente es necesaria.
        - No presentes los rangos como baremos oficiales.
        - No cites normativa, percentiles oficiales ni estándares externos.
        - Ajusta la propuesta al sexo indicado cuando sea MALE o FEMALE; si es Sin especificar, conserva un baremo neutro.
        - Devuelve exactamente 5 rangos claros, ordenados para edición rápida.
        - Prohibido devolver baremos genéricos como Poco/Menor/Medio sin valores minValue/maxValue adecuados.
        - La unidad de todas las etiquetas debe ser \(input.unit).
        - Cada rango debe tener minValue o maxValue cuando corresponda, score entre 0 y 10 y una etiqueta breve con unidad.
        - Para mayor/mejor, las notas deben subir con la marca; para menor/mejor, las notas deben bajar con la marca.
        - Respeta la precisión del perfil local.
        - warnings debe incluir prudencia sobre contexto, seguridad, diversidad del alumnado y revisión docente.
        - warnings debe incluir literalmente: \(PhysicalScaleProfileCatalog.safetyWarnings.joined(separator: " | "))
        - editableProposal debe poder pegarse como borrador docente breve.
        """)
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func mapPhysicalScaleRecommendation(
        _ content: GeneratedPhysicalScaleRecommendation,
        input: PhysicalScaleRecommendationInput
    ) -> PhysicalScaleRecommendationDraft {
        let mappedRanges = content.ranges.map { range in
            PhysicalScaleRecommendedRange(
                minValue: range.minValue,
                maxValue: range.maxValue,
                score: min(max(range.score, 0), 10),
                label: range.label.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let safetyWarnings = compactTexts(
            content.warnings,
            PhysicalScaleProfileCatalog.safetyWarnings
        )
        return PhysicalScaleRecommendationDraft(
            title: normalizedOptional(content.title) ?? "Propuesta IA de baremo · \(input.testName)",
            summary: normalizedOptional(content.summary) ?? "Propuesta orientativa editable para revisión docente.",
            ranges: mappedRanges,
            explanation: normalizedOptional(content.explanation) ?? "Rangos pensados para edición rápida y revisión docente.",
            warnings: Array(safetyWarnings.prefix(5)),
            editableProposal: normalizedOptional(content.editableProposal) ?? "Propuesta orientativa. Revisar y ajustar antes de usar."
        )
    }

    #endif

    private func fallbackPhysicalScaleRecommendation(
        from input: PhysicalScaleRecommendationInput,
        seedRanges: [PhysicalScaleRecommendedRange]
    ) -> PhysicalScaleRecommendationDraft {
        PhysicalScaleRecommendationDraft(
            title: "Propuesta IA de baremo · \(input.testName)",
            summary: "Propuesta orientativa generada desde el perfil local de \(input.testName), preparada para revisión docente.",
            ranges: seedRanges,
            explanation: "Se usan rangos seed deterministas adaptados a test, edad, unidad, objetivo y dirección de mejora.",
            warnings: PhysicalScaleProfileCatalog.safetyWarnings,
            editableProposal: "Baremo orientativo para \(input.testName). Revisar, adaptar al grupo y no usar como baremo oficial sin criterio docente."
        )
    }

    private func physicalProgressPrompt(from evidence: PhysicalProgressEvidence) -> String {
        AIContextBudget.prompt(
            """
            Genera PhysicalProgressAnalysis para el grupo.

            Evidencia
            \(evidence.evidenceLines.map { "- \($0)" }.joined(separator: "\n"))

            Reglas:
            - No calcules nuevos resultados ni inventes mediciones.
            - improvementPercentage puede ser nil si no hay histórico comparable.
            - Máximo 3 fortalezas, 3 debilidades, 3 recomendaciones y 3 alertas.
            - Si solo hay una medición por prueba, habla de estado actual y no de evolución temporal.
            """
        )
    }

    private func fallbackPhysicalProgressAnalysis(
        from evidence: PhysicalProgressEvidence,
        reason: String
    ) -> PhysicalProgressAnalysis {
        let completedMetrics = evidence.metrics.filter { $0.recordedCount > 0 }
        let fullMetrics = completedMetrics.filter { $0.recordedCount >= $0.totalCount && $0.totalCount > 0 }
        let incompleteMetrics = evidence.metrics.filter { $0.recordedCount < $0.totalCount }
        let highAverages = completedMetrics.filter { $0.average >= 7 }
        let lowAverages = completedMetrics.filter { $0.average > 0 && $0.average < 5 }

        return PhysicalProgressAnalysis(
            summary: evidence.hasEnoughData
                ? "Lectura inicial de condición física basada en las marcas registradas del grupo."
                : "Aún no hay marcas suficientes para analizar la condición física del grupo.",
            trend: fullMetrics.count >= max(1, evidence.metrics.count / 2) ? "Cobertura suficiente" : "Cobertura parcial",
            improvementPercentage: nil,
            strengths: compactOptionalTexts([
                highAverages.first.map { "Buen rendimiento medio en \($0.testName)." },
                fullMetrics.first.map { "Registro completo en \($0.testName)." },
                evidence.completionRate >= 80 ? "Cobertura alta de registros físicos." : nil
            ]).prefix(3).map { $0 },
            weaknesses: compactOptionalTexts([
                lowAverages.first.map { "Media baja en \($0.testName)." },
                incompleteMetrics.first.map { "Faltan registros en \($0.testName)." },
                evidence.completionRate < 60 ? "Cobertura de datos todavía limitada." : nil
            ]).prefix(3).map { $0 },
            recommendations: compactOptionalTexts([
                "Completar marcas pendientes antes de comparar evolución.",
                lowAverages.first.map { "Revisar propuesta didáctica asociada a \($0.testName)." },
                "Contrastar los resultados con observación técnica y contexto del grupo."
            ]).prefix(3).map { $0 },
            alerts: compactOptionalTexts([
                evidence.completionRate < 50 ? "Menos de la mitad de registros completados." : nil,
                lowAverages.count >= 2 ? "Varias pruebas presentan medias bajas." : nil
            ]).prefix(3).map { $0 },
            confidenceNote: reason
        )
    }

    private func compactOptionalTexts(_ values: [String?]) -> [String] {
        var seen = Set<String>()
        return values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private func fallbackResult(
        from context: KmpBridge.ScreenAIContext,
        action: KmpBridge.ContextualAIAction
    ) -> ContextualAIResult {
        let facts = Array(context.factLines.prefix(5))
        let warnings = compactTexts(
            Array(context.supportNotes.prefix(3)),
            context.dataQualityNote.map { [$0] } ?? []
        )
        let actions = compactTexts([
            action.promptHint,
            "Revisar los hechos visibles antes de insertar el borrador.",
            "Añadir o ajustar evidencias si faltan datos relevantes."
        ])
        let summary = context.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Borrador por reglas preparado con los datos visibles de la pantalla."
            : context.summary
        return ContextualAIResult(
            title: action.title,
            subtitle: context.subtitle,
            summary: summary,
            bullets: facts.isEmpty ? ["No hay hechos adicionales suficientes."] : facts,
            factsUsed: facts,
            warnings: warnings,
            recommendedActions: Array(actions.prefix(3)),
            editableText: """
            \(action.title)

            \(summary)

            Hechos observables
            \((facts.isEmpty ? ["Sin hechos adicionales suficientes."] : facts).map { "• \($0)" }.joined(separator: "\n"))

            Próximos pasos
            \(actions.prefix(3).map { "• \($0)" }.joined(separator: "\n"))
            """,
            confidenceNote: context.dataQualityNote ?? "Generado por reglas porque la IA local no está disponible."
        )
    }

    private func fallbackNotebookComment(from context: KmpBridge.NotebookAICommentContext) -> NotebookAICommentDraft {
        let evidence = NotebookCommentEvidenceBuilder.build(from: context)
        let fact = evidence.factTexts.first ?? "datos visibles limitados"
        let action = evidence.recommendedActionTexts.first ?? "recoger una nueva evidencia observable"
        let comment = "\(context.studentName) muestra \(fact.lowercased()). Conviene reforzar \(action.lowercased()). Próximo paso: revisar el progreso en la próxima sesión."
        return NotebookAICommentDraft(
            summary: context.summary,
            strengths: Array(evidence.factTexts.prefix(2)),
            needsAttention: Array(evidence.warningTexts.prefix(2)),
            nextSteps: Array((evidence.recommendedActionTexts.isEmpty ? [action] : evidence.recommendedActionTexts).prefix(3)),
            factsUsed: Array(evidence.factTexts.prefix(5)),
            warnings: Array(evidence.warningTexts.prefix(3)) + ["Generado por reglas porque la IA local no está disponible."],
            commentText: comment
        )
    }

    private func fallbackTeachingDraft(from evidence: TeachingEvidencePack) -> TeachingAssistantDraft {
        let facts = Array(evidence.factTexts.prefix(6))
        let warnings = Array(evidence.warningTexts.prefix(4))
        let actions = Array((evidence.recommendedActionTexts.isEmpty ? ["Mantener seguimiento prudente y recoger nuevas evidencias."] : evidence.recommendedActionTexts).prefix(4))
        return TeachingAssistantDraft(
            title: evidence.title,
            subtitle: evidence.subtitle,
            summary: evidence.summary,
            factsUsed: facts,
            warnings: warnings,
            recommendedActions: actions,
            editableText: """
            \(evidence.title)

            \(evidence.summary)

            Hechos usados
            \((facts.isEmpty ? ["Sin hechos adicionales suficientes."] : facts).map { "• \($0)" }.joined(separator: "\n"))

            Alertas
            \((warnings.isEmpty ? ["Sin alertas específicas con los datos actuales."] : warnings).map { "• \($0)" }.joined(separator: "\n"))

            Próximas acciones
            \(actions.map { "• \($0)" }.joined(separator: "\n"))
            """,
            confidenceNote: evidence.confidenceNote ?? "Generado por reglas porque la IA local no está disponible.",
            riskLevel: evidence.riskLevel
        )
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
                .localInferenceDisabled,
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

    #if canImport(FoundationModels)
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

    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct GeneratedPhysicalScaleRange {
        let minValue: Double?
        let maxValue: Double?
        let score: Double
        let label: String
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct GeneratedPhysicalScaleRecommendation {
        let title: String
        let summary: String
        let ranges: [GeneratedPhysicalScaleRange]
        let explanation: String
        let warnings: [String]
        let editableProposal: String
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct GeneratedPhysicalProgressAnalysis {
        let summary: String
        let trend: String
        let improvementPercentage: Double?
        let strengths: [String]
        let weaknesses: [String]
        let recommendations: [String]
        let alerts: [String]
        let confidenceNote: String
    }

    #endif
}
