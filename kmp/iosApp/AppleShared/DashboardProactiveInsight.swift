import SwiftUI
import MiGestorKit

struct DashboardAIBriefingCacheKey: Hashable {
    let classId: Int64?
    let scope: String
    let dayStart: TimeInterval

    init(classId: Int64?, scope: String, date: Date = Date(), calendar: Calendar = .current) {
        self.classId = classId
        self.scope = scope
        self.dayStart = calendar.startOfDay(for: date).timeIntervalSince1970
    }
}

enum DashboardAIBriefingState: Equatable {
    case deterministic
    case updating
    case cached
    case fresh
    case failed

    var isUpdating: Bool {
        self == .updating
    }

    var statusText: String? {
        switch self {
        case .deterministic:
            return nil
        case .updating:
            return "Actualizando análisis"
        case .cached:
            return "Último análisis de hoy"
        case .fresh:
            return "Análisis actualizado"
        case .failed:
            return "Análisis local no disponible"
        }
    }
}

@MainActor
final class DashboardAIBriefingCache {
    static let shared = DashboardAIBriefingCache()

    private struct Entry {
        let draft: TeachingAssistantDraft
        let createdAt: Date
    }

    private let maxAge: TimeInterval = 24 * 60 * 60
    private var entries: [DashboardAIBriefingCacheKey: Entry] = [:]
    private var refreshesInFlight: Set<DashboardAIBriefingCacheKey> = []

    private init() {}

    func cachedDraft(for key: DashboardAIBriefingCacheKey, now: Date = Date()) -> TeachingAssistantDraft? {
        guard let entry = entries[key] else { return nil }
        guard now.timeIntervalSince(entry.createdAt) < maxAge else {
            entries[key] = nil
            return nil
        }
        return entry.draft
    }

    func beginRefresh(for key: DashboardAIBriefingCacheKey) -> Bool {
        guard !refreshesInFlight.contains(key) else { return false }
        refreshesInFlight.insert(key)
        return true
    }

    func store(_ draft: TeachingAssistantDraft, for key: DashboardAIBriefingCacheKey, at date: Date = Date()) {
        entries[key] = Entry(draft: draft, createdAt: date)
        refreshesInFlight.remove(key)
    }

    func finishRefresh(for key: DashboardAIBriefingCacheKey) {
        refreshesInFlight.remove(key)
    }
}

struct DashboardProactiveInsight: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case now
        case attendance
        case evaluation
        case risk
        case planning
        case physicalEducation
        case system
        case briefing

        var systemImage: String {
            switch self {
            case .now: return "bolt.badge.clock"
            case .attendance: return "person.crop.circle.badge.exclamationmark"
            case .evaluation: return "checklist.checked"
            case .risk: return "exclamationmark.triangle"
            case .planning: return "calendar.badge.clock"
            case .physicalEducation: return "figure.run.circle"
            case .system: return "checkmark.shield"
            case .briefing: return "sparkles"
            }
        }
    }

    enum Priority: Int, Comparable, Hashable {
        case critical = 4
        case high = 3
        case medium = 2
        case low = 1

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var label: String {
            switch self {
            case .critical: return "Crítica"
            case .high: return "Alta"
            case .medium: return "Media"
            case .low: return "Baja"
            }
        }

        var tint: Color {
            switch self {
            case .critical: return .red
            case .high: return .orange
            case .medium: return .blue
            case .low: return .secondary
            }
        }
    }

    let id: String
    let kind: Kind
    let priority: Priority
    let title: String
    let summary: String
    let facts: [String]
    let recommendedActions: [DashboardProactiveAction]
    let confidenceNote: String?
}

enum DashboardProactiveAction: String, Identifiable, Hashable {
    case passList
    case openNotebook
    case evaluatePending
    case openPlanner
    case openReports
    case reviewPhysicalEducation
    case reviewSystem
    case openInspector
    case quickEvaluation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passList: return "Pasar lista"
        case .openNotebook: return "Abrir cuaderno"
        case .evaluatePending: return "Evaluar"
        case .openPlanner: return "Abrir planner"
        case .openReports: return "Abrir informes"
        case .reviewPhysicalEducation: return "Revisar EF"
        case .reviewSystem: return "Revisar sistema"
        case .openInspector: return "Ver detalle"
        case .quickEvaluation: return "Evaluación rápida"
        }
    }

    var systemImage: String {
        switch self {
        case .passList: return "checkmark.circle"
        case .openNotebook: return "tablecells"
        case .evaluatePending: return "checklist.checked"
        case .openPlanner: return "calendar"
        case .openReports: return "doc.text.magnifyingglass"
        case .reviewPhysicalEducation: return "figure.run"
        case .reviewSystem: return "arrow.triangle.2.circlepath"
        case .openInspector: return "sidebar.right"
        case .quickEvaluation: return "sparkles"
        }
    }
}

struct DashboardProactiveContext {
    let className: String?
    let modeLabel: String
    let syncPendingChanges: Int
    let pairedSyncHost: String?
    let latestBackupDate: Date?
    let platformName: String

    init(
        className: String?,
        modeLabel: String,
        syncPendingChanges: Int,
        pairedSyncHost: String?,
        latestBackupDate: Date? = nil,
        platformName: String
    ) {
        self.className = className
        self.modeLabel = modeLabel
        self.syncPendingChanges = syncPendingChanges
        self.pairedSyncHost = pairedSyncHost
        self.latestBackupDate = latestBackupDate
        self.platformName = platformName
    }
}

struct DashboardProactiveSnapshot {
    let todayCount: Int
    let alertsCount: Int
    let pendingCount: Int
    let nextSessionLabel: String
    let todaySessions: [DashboardProactiveSession]
    let alerts: [DashboardProactiveSignal]
    let peItems: [DashboardProactiveSignal]
    let groupSummaries: [DashboardProactiveGroupSummary]
    let agendaItems: [DashboardProactiveAgendaItem]
    let quickColumns: [String]
    let quickRubrics: [String]

    init(
        todayCount: Int,
        alertsCount: Int,
        pendingCount: Int,
        nextSessionLabel: String,
        todaySessions: [DashboardProactiveSession] = [],
        alerts: [DashboardProactiveSignal] = [],
        peItems: [DashboardProactiveSignal] = [],
        groupSummaries: [DashboardProactiveGroupSummary] = [],
        agendaItems: [DashboardProactiveAgendaItem] = [],
        quickColumns: [String] = [],
        quickRubrics: [String] = []
    ) {
        self.todayCount = todayCount
        self.alertsCount = alertsCount
        self.pendingCount = pendingCount
        self.nextSessionLabel = nextSessionLabel
        self.todaySessions = todaySessions
        self.alerts = alerts
        self.peItems = peItems
        self.groupSummaries = groupSummaries
        self.agendaItems = agendaItems
        self.quickColumns = quickColumns
        self.quickRubrics = quickRubrics
    }

    init(snapshot: DashboardSnapshot) {
        self.init(
            todayCount: Int(snapshot.todayCount),
            alertsCount: Int(snapshot.alertsCount),
            pendingCount: Int(snapshot.pendingCount),
            nextSessionLabel: snapshot.nextSessionLabel,
            todaySessions: snapshot.todaySessions.map {
                DashboardProactiveSession(
                    id: "\($0.id)",
                    groupName: $0.groupName,
                    timeLabel: $0.timeLabel,
                    didacticUnit: $0.didacticUnit,
                    sessionStatus: $0.sessionStatus
                )
            },
            alerts: snapshot.alerts.map {
                DashboardProactiveSignal(
                    id: $0.id,
                    type: $0.type,
                    title: $0.title,
                    detail: $0.detail,
                    severity: $0.severity,
                    count: Int($0.count)
                )
            },
            peItems: snapshot.peItems.map {
                DashboardProactiveSignal(
                    id: $0.id,
                    type: $0.type,
                    title: $0.title,
                    detail: $0.detail,
                    severity: $0.severity,
                    count: 1
                )
            },
            groupSummaries: snapshot.groupSummaries.map {
                DashboardProactiveGroupSummary(
                    classId: Int64($0.classId),
                    groupName: $0.groupName,
                    attendancePct: Int($0.attendancePct),
                    evaluationCompletedPct: Int($0.evaluationCompletedPct),
                    averageScore: $0.averageScore,
                    studentsInFollowUp: Int($0.studentsInFollowUp),
                    lastNotes: $0.lastNotes
                )
            },
            agendaItems: snapshot.agendaItems.map {
                DashboardProactiveAgendaItem(
                    id: $0.id,
                    type: $0.type,
                    title: $0.title,
                    subtitle: $0.subtitle,
                    timeLabel: $0.timeLabel,
                    status: $0.status
                )
            },
            quickColumns: snapshot.quickColumns,
            quickRubrics: snapshot.quickRubrics
        )
    }
}

struct DashboardProactiveSession: Hashable {
    let id: String
    let groupName: String
    let timeLabel: String
    let didacticUnit: String
    let sessionStatus: String
}

struct DashboardProactiveSignal: Hashable {
    let id: String
    let type: String
    let title: String
    let detail: String
    let severity: String
    let count: Int
}

struct DashboardProactiveGroupSummary: Hashable {
    let classId: Int64
    let groupName: String
    let attendancePct: Int
    let evaluationCompletedPct: Int
    let averageScore: Double
    let studentsInFollowUp: Int
    let lastNotes: String
}

struct DashboardProactiveAgendaItem: Hashable {
    let id: String
    let type: String
    let title: String
    let subtitle: String
    let timeLabel: String
    let status: String
}

@MainActor
enum DashboardProactiveInsightEngine {
    static func build(
        snapshot: DashboardSnapshot,
        trends: KmpBridge.AITrendsSnapshot?,
        context: DashboardProactiveContext,
        limit: Int = 5
    ) -> [DashboardProactiveInsight] {
        build(
            snapshot: DashboardProactiveSnapshot(snapshot: snapshot),
            trends: trends,
            context: context,
            limit: limit
        )
    }

    static func build(
        snapshot: DashboardProactiveSnapshot,
        trends: KmpBridge.AITrendsSnapshot?,
        context: DashboardProactiveContext,
        limit: Int = 5
    ) -> [DashboardProactiveInsight] {
        var insights: [DashboardProactiveInsight] = []

        if let firstSession = snapshot.todaySessions.first {
            let hasAttendancePending = snapshot.alerts.contains { alert in
                containsAny("\(alert.type) \(alert.title) \(alert.detail)", ["asistencia", "attendance", "lista"])
            }
            insights.append(
                DashboardProactiveInsight(
                    id: "now-\(firstSession.id)",
                    kind: .now,
                    priority: hasAttendancePending ? .critical : .high,
                    title: context.modeLabel == "Clase" ? "Prioridad ahora" : "Próxima franja docente",
                    summary: "\(firstSession.groupName) · \(firstSession.timeLabel). \(firstSession.didacticUnit)",
                    facts: compact([
                        "Sesión detectada hoy: \(firstSession.groupName) a \(firstSession.timeLabel).",
                        "Estado de sesión: \(firstSession.sessionStatus).",
                        hasAttendancePending ? "Hay señales de asistencia pendiente asociadas al dashboard." : nil
                    ]),
                    recommendedActions: hasAttendancePending ? [.passList, .openNotebook, .openInspector] : [.openPlanner, .openNotebook, .openInspector],
                    confidenceNote: "Basado en sesiones de hoy y alertas operativas cargadas."
                )
            )
        } else if snapshot.pendingCount > 0 {
            insights.append(
                DashboardProactiveInsight(
                    id: "pending-overview",
                    kind: .planning,
                    priority: .medium,
                    title: "Preparar pendientes",
                    summary: "Hay \(snapshot.pendingCount) pendientes antes de cerrar el día docente.",
                    facts: ["Pendientes operativos: \(snapshot.pendingCount).", "Próxima sesión: \(snapshot.nextSessionLabel)."],
                    recommendedActions: [.openPlanner, .openInspector],
                    confidenceNote: "Basado en el snapshot operativo del dashboard."
                )
            )
        }

        let pendingAlerts = snapshot.alerts.filter { alert in
            containsAny("\(alert.type) \(alert.title) \(alert.detail)", ["pending", "pendiente", "sin nota", "sin cerrar", "missing"])
        }
        if !pendingAlerts.isEmpty {
            let first = pendingAlerts[0]
            insights.append(
                DashboardProactiveInsight(
                    id: "evaluation-\(first.id)",
                    kind: .evaluation,
                    priority: pendingAlerts.contains { $0.severity.lowercased() == "high" } ? .high : .medium,
                    title: "Evaluación pendiente",
                    summary: pendingAlerts.count == 1 ? first.title : "\(pendingAlerts.count) señales evaluativas pendientes.",
                    facts: Array(pendingAlerts.prefix(3).map { "\($0.title): \($0.detail)" }),
                    recommendedActions: [.quickEvaluation, .evaluatePending, .openInspector],
                    confidenceNote: "Ordenado desde alertas del dashboard, sin generar datos nuevos."
                )
            )
        }

        if let evaluationInsight = buildEvaluationClosureInsight(snapshot: snapshot, context: context) {
            insights.append(evaluationInsight)
        }

        let riskAlerts = snapshot.alerts.filter { alert in
            !pendingAlerts.contains(where: { $0.id == alert.id })
        }
        if !riskAlerts.isEmpty {
            let highCount = riskAlerts.filter { $0.severity.lowercased() == "high" }.count
            insights.append(
                DashboardProactiveInsight(
                    id: "risk-\(riskAlerts[0].id)",
                    kind: .risk,
                    priority: highCount > 0 ? .critical : .high,
                    title: "Alumnado a revisar",
                    summary: highCount > 0 ? "\(highCount) señales de riesgo alto." : "\(riskAlerts.count) señales de seguimiento.",
                    facts: Array(riskAlerts.prefix(3).map { "\($0.title): \($0.detail)" }),
                    recommendedActions: [.openInspector, .openNotebook],
                    confidenceNote: "Basado en alertas clasificadas por severidad."
                )
            )
        }

        if let physicalEducationInsight = buildPhysicalEducationInsight(snapshot: snapshot) {
            insights.append(physicalEducationInsight)
        }

        if let trends, let curriculumInsight = buildCurriculumCoverageInsight(trends: trends) {
            insights.append(curriculumInsight)
        }

        if context.syncPendingChanges > 0 || context.pairedSyncHost == nil || (context.platformName == "macOS" && context.latestBackupDate == nil) {
            insights.append(
                DashboardProactiveInsight(
                    id: "system-\(context.syncPendingChanges)-\(context.pairedSyncHost ?? "none")-\(context.latestBackupDate?.timeIntervalSince1970 ?? 0)",
                    kind: .system,
                    priority: context.syncPendingChanges > 0 ? .medium : .low,
                    title: "Sistema",
                    summary: context.syncPendingChanges > 0 ? "\(context.syncPendingChanges) cambios pendientes de sync." : "Revisa sync o backup cuando cierres la jornada.",
                    facts: compact([
                        context.syncPendingChanges > 0 ? "Cambios pendientes: \(context.syncPendingChanges)." : nil,
                        context.pairedSyncHost.map { "Host sync: \($0)." } ?? "Sync local sin host activo.",
                        context.platformName == "macOS" ? (context.latestBackupDate.map { "Último backup: \($0.formatted(date: .abbreviated, time: .shortened))." } ?? "Sin backup registrado en macOS.") : nil
                    ]),
                    recommendedActions: [.reviewSystem],
                    confidenceNote: "Basado en estado local de sync y backup."
                )
            )
        }

        return Array(
            insights
                .sorted { lhs, rhs in
                    if lhs.priority == rhs.priority { return lhs.kind.rawValue < rhs.kind.rawValue }
                    return lhs.priority > rhs.priority
                }
                .prefix(max(1, limit))
        )
    }

    static func fallbackBriefing(from insights: [DashboardProactiveInsight], className: String?) -> TeachingAssistantDraft? {
        guard let first = insights.first else { return nil }
        let facts = Array(insights.flatMap(\.facts).prefix(6))
        let actions = Array(insights.flatMap { $0.recommendedActions.map(\.title) }.removingDuplicates().prefix(4))
        return TeachingAssistantDraft(
            title: "Briefing docente",
            subtitle: className ?? "Dashboard",
            summary: first.summary,
            factsUsed: facts,
            warnings: Array(insights.filter { $0.priority >= .high }.map(\.title).prefix(4)),
            recommendedActions: actions.isEmpty ? ["Revisar el detalle del dashboard."] : actions,
            editableText: ([first.title, first.summary] + facts).joined(separator: "\n"),
            confidenceNote: "Generado por reglas del radar porque la IA local no ha aportado un briefing adicional.",
            riskLevel: nil
        )
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        let lowercased = value.lowercased()
        return needles.contains { lowercased.contains($0) }
    }

    private static func buildEvaluationClosureInsight(
        snapshot: DashboardProactiveSnapshot,
        context: DashboardProactiveContext
    ) -> DashboardProactiveInsight? {
        guard !snapshot.groupSummaries.isEmpty || !snapshot.quickColumns.isEmpty || !snapshot.quickRubrics.isEmpty else {
            return nil
        }

        let selectedGroup = context.className.flatMap { className in
            snapshot.groupSummaries.first { summary in
                className.localizedCaseInsensitiveContains(summary.groupName)
                    || summary.groupName.localizedCaseInsensitiveContains(className)
            }
        }
        let candidate = selectedGroup
            ?? snapshot.groupSummaries.sorted { lhs, rhs in
                if lhs.evaluationCompletedPct == rhs.evaluationCompletedPct {
                    return lhs.studentsInFollowUp > rhs.studentsInFollowUp
                }
                return lhs.evaluationCompletedPct < rhs.evaluationCompletedPct
            }.first

        var facts: [String] = []
        var priority: DashboardProactiveInsight.Priority = .low
        var summary = "Revisa instrumentos y evidencias antes de cerrar la lectura evaluativa."

        if let candidate {
            facts.append("\(candidate.groupName): evaluación completada al \(candidate.evaluationCompletedPct)%.")
            if candidate.averageScore > 0 {
                facts.append("Media visible: \(format(candidate.averageScore)).")
            }
            if candidate.studentsInFollowUp > 0 {
                facts.append("Alumnado en seguimiento: \(candidate.studentsInFollowUp).")
            }
            if !candidate.lastNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                facts.append("Últimas notas: \(candidate.lastNotes).")
            }

            if candidate.evaluationCompletedPct < 60 {
                priority = .high
                summary = "La media del grupo puede no ser fiable: faltan evidencias suficientes."
            } else if candidate.evaluationCompletedPct < 80 || candidate.studentsInFollowUp > 0 {
                priority = .medium
                summary = "Conviene completar evidencias antes de usar la media como lectura cerrada."
            }
        }

        if !snapshot.quickRubrics.isEmpty {
            facts.append("Rúbricas disponibles para evaluación rápida: \(snapshot.quickRubrics.prefix(3).joined(separator: ", ")).")
            priority = max(priority, .medium)
        }
        if !snapshot.quickColumns.isEmpty {
            facts.append("Columnas rápidas disponibles: \(snapshot.quickColumns.prefix(3).joined(separator: ", ")).")
        }

        let openEvaluationAgenda = snapshot.agendaItems.filter { item in
            !isClosedAgendaStatus(item.status)
                && containsAny("\(item.type) \(item.title) \(item.subtitle)", ["evalu", "rúbrica", "rubric", "nota", "evidencia"])
        }
        if !openEvaluationAgenda.isEmpty {
            facts.append("Agenda evaluativa abierta: \(openEvaluationAgenda.prefix(2).map(\.title).joined(separator: ", ")).")
            priority = max(priority, .medium)
        }

        guard priority >= .medium, !facts.isEmpty else { return nil }

        return DashboardProactiveInsight(
            id: "evaluation-closure-\(candidate?.classId ?? -1)-\(snapshot.quickRubrics.count)-\(openEvaluationAgenda.count)",
            kind: .evaluation,
            priority: priority,
            title: "Media y cierre evaluativo",
            summary: summary,
            facts: Array(facts.prefix(5)),
            recommendedActions: [.openNotebook, .evaluatePending, .quickEvaluation, .openReports],
            confidenceNote: "Basado en resumen de grupo, agenda e instrumentos rápidos ya cargados."
        )
    }

    private static func buildPhysicalEducationInsight(
        snapshot: DashboardProactiveSnapshot
    ) -> DashboardProactiveInsight? {
        guard !snapshot.peItems.isEmpty else { return nil }

        let highItems = snapshot.peItems.filter { $0.severity.lowercased() == "high" }
        let mediumItems = snapshot.peItems.filter { $0.severity.lowercased() == "medium" }
        let regressionItems = snapshot.peItems.filter { item in
            containsAny("\(item.type) \(item.title) \(item.detail)", ["regresión", "regresion", "empeor", "descenso", "baja"])
        }
        let missingItems = snapshot.peItems.filter { item in
            containsAny("\(item.type) \(item.title) \(item.detail)", ["faltan", "pendiente", "incomplet", "sin registro", "sin marca"])
        }

        var facts = Array(snapshot.peItems.prefix(3).map { "\($0.title): \($0.detail)" })
        if !regressionItems.isEmpty {
            facts.append("Señales de regresión detectadas: \(regressionItems.count).")
        }
        if !missingItems.isEmpty {
            facts.append("Registros o marcas pendientes: \(missingItems.count).")
        }

        let priority: DashboardProactiveInsight.Priority
        if !highItems.isEmpty || !regressionItems.isEmpty {
            priority = .high
        } else if !mediumItems.isEmpty || !missingItems.isEmpty {
            priority = .medium
        } else {
            priority = .low
        }

        guard priority >= .medium else { return nil }

        let summary: String
        if !regressionItems.isEmpty {
            summary = "Conviene revisar evolución física antes de cerrar la sesión o el bloque."
        } else if !missingItems.isEmpty {
            summary = "Hay marcas o evidencias EF pendientes que pueden afectar al seguimiento."
        } else {
            summary = snapshot.peItems.count == 1 ? snapshot.peItems[0].title : "\(snapshot.peItems.count) señales EF para revisar."
        }

        return DashboardProactiveInsight(
            id: "pe-advanced-\(snapshot.peItems[0].id)-\(regressionItems.count)-\(missingItems.count)",
            kind: .physicalEducation,
            priority: priority,
            title: "Seguimiento EF",
            summary: summary,
            facts: Array(facts.prefix(5)),
            recommendedActions: [.reviewPhysicalEducation, .openNotebook, .openInspector],
            confidenceNote: "Basado en señales EF operativas ya presentes en el dashboard."
        )
    }

    private static func buildCurriculumCoverageInsight(
        trends: KmpBridge.AITrendsSnapshot
    ) -> DashboardProactiveInsight? {
        var facts: [String] = []
        if trends.curriculumCoveragePct < 85 {
            facts.append("Cobertura curricular: \(format(trends.curriculumCoveragePct))%.")
        }
        if !trends.missingCompetencyLabels.isEmpty {
            facts.append("Competencias sin evidencia: \(trends.missingCompetencyLabels.prefix(4).joined(separator: ", ")).")
        }
        if trends.attendanceRate > 0, trends.attendanceRate < 85 {
            facts.append("Asistencia media: \(format(trends.attendanceRate))%.")
        }
        if trends.trendDirection == "DOWNWARD" {
            facts.append("Tendencia de rendimiento: descendente (\(format(abs(trends.averageGradeDelta))) pt).")
        }

        let hasCoverageGap = trends.curriculumCoveragePct < 85 || !trends.missingCompetencyLabels.isEmpty
        let hasReliabilityGap = trends.attendanceRate > 0 && trends.attendanceRate < 85
        guard hasCoverageGap || hasReliabilityGap || trends.trendDirection == "DOWNWARD" else { return nil }

        let priority: DashboardProactiveInsight.Priority
        if trends.curriculumCoveragePct < 50 || trends.attendanceRate < 75 || trends.trendDirection == "DOWNWARD" {
            priority = .high
        } else {
            priority = .medium
        }

        let summary: String
        if !trends.missingCompetencyLabels.isEmpty {
            summary = "Faltan evidencias competenciales antes de una lectura LOMLOE sólida."
        } else if hasReliabilityGap {
            summary = "La asistencia puede estar afectando a la fiabilidad de la lectura del grupo."
        } else {
            summary = "Conviene revisar cobertura curricular antes de cerrar evaluación."
        }

        return DashboardProactiveInsight(
            id: "lomloe-advanced-\(format(trends.curriculumCoveragePct))-\(trends.missingCompetencyLabels.count)",
            kind: .evaluation,
            priority: priority,
            title: "Cobertura LOMLOE",
            summary: summary,
            facts: Array(facts.prefix(5)),
            recommendedActions: [.openNotebook, .evaluatePending, .openReports],
            confidenceNote: "Basado en tendencias, asistencia y auditoría LOMLOE del grupo."
        )
    }

    private static func isClosedAgendaStatus(_ raw: String) -> Bool {
        switch raw.lowercased() {
        case "completed", "closed", "done", "completada", "cerrada":
            return true
        default:
            return false
        }
    }

    private static func compact(_ values: [String?]) -> [String] {
        values.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
    }

    private static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

struct DashboardProactiveInsightCard: View {
    let insights: [DashboardProactiveInsight]
    let aiBriefing: TeachingAssistantDraft?
    let aiBriefingState: DashboardAIBriefingState
    let actionAvailability: (DashboardProactiveAction) -> Bool
    let onAction: (DashboardProactiveAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let aiBriefing {
                briefingBlock(aiBriefing)
            } else if aiBriefingState.isUpdating {
                briefingLoadingBlock
            }
            if insights.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(insights.prefix(3)) { insight in
                        insightRow(insight)
                    }
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Label("Radar docente", systemImage: "scope")
                .font(.headline)
            Spacer()
            if let statusText = aiBriefingState.statusText {
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            if aiBriefingState.isUpdating {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Actualizando análisis")
            }
        }
    }

    private func briefingBlock(_ draft: TeachingAssistantDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(EvaluationDesign.accent)
                    .accessibilityHidden(true)
                Text(draft.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            Text(draft.summary)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let confidence = draft.confidenceNote {
                Text(confidence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(EvaluationDesign.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var briefingLoadingBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.12))
                .frame(width: 160, height: 10)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(maxWidth: .infinity, minHeight: 10, maxHeight: 10)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 220, height: 10)
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Generando briefing docente")
    }

    private func insightRow(_ insight: DashboardProactiveInsight) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: insight.kind.systemImage)
                    .foregroundStyle(insight.priority.tint)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(insight.title)
                            .font(.subheadline.weight(.semibold))
                        Text(insight.priority.label)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(insight.priority.tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(insight.priority.tint.opacity(0.12), in: Capsule())
                    }
                    Text(insight.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            actionRow(for: insight)

            if !insight.facts.isEmpty || insight.confidenceNote != nil {
                DisclosureGroup("Hechos usados") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(insight.facts, id: \.self) { fact in
                            Text("• \(fact)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let confidence = insight.confidenceNote {
                            Text(confidence)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func actionRow(for insight: DashboardProactiveInsight) -> some View {
        let actions = insight.recommendedActions.filter(actionAvailability)
        return Group {
            if !actions.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(actions.prefix(3)) { action in
                        Button {
                            onAction(action)
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        Text("Sin señales prioritarias con los datos cargados.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
