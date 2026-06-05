import SwiftUI
import MiGestorKit

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

    init(
        todayCount: Int,
        alertsCount: Int,
        pendingCount: Int,
        nextSessionLabel: String,
        todaySessions: [DashboardProactiveSession] = [],
        alerts: [DashboardProactiveSignal] = [],
        peItems: [DashboardProactiveSignal] = []
    ) {
        self.todayCount = todayCount
        self.alertsCount = alertsCount
        self.pendingCount = pendingCount
        self.nextSessionLabel = nextSessionLabel
        self.todaySessions = todaySessions
        self.alerts = alerts
        self.peItems = peItems
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
            }
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

        if !snapshot.peItems.isEmpty {
            let severePE = snapshot.peItems.filter { $0.severity.lowercased() == "high" }.count
            insights.append(
                DashboardProactiveInsight(
                    id: "pe-\(snapshot.peItems[0].id)",
                    kind: .physicalEducation,
                    priority: severePE > 0 ? .high : .medium,
                    title: "Educación Física",
                    summary: snapshot.peItems.count == 1 ? snapshot.peItems[0].title : "\(snapshot.peItems.count) señales EF para revisar.",
                    facts: Array(snapshot.peItems.prefix(3).map { "\($0.title): \($0.detail)" }),
                    recommendedActions: [.reviewPhysicalEducation, .openInspector],
                    confidenceNote: "Basado en señales EF ya presentes en el dashboard."
                )
            )
        }

        if let trends {
            var trendFacts: [String] = []
            if trends.curriculumCoveragePct < 75 {
                trendFacts.append("Cobertura curricular: \(format(trends.curriculumCoveragePct))%.")
            }
            if trends.attendanceRate > 0, trends.attendanceRate < 85 {
                trendFacts.append("Asistencia media: \(format(trends.attendanceRate))%.")
            }
            if !trends.missingCompetencyLabels.isEmpty {
                trendFacts.append("Competencias sin evidencia: \(trends.missingCompetencyLabels.prefix(3).joined(separator: ", ")).")
            }
            if !trendFacts.isEmpty {
                insights.append(
                    DashboardProactiveInsight(
                        id: "lomloe-trends",
                        kind: .evaluation,
                        priority: trends.curriculumCoveragePct < 50 || trends.attendanceRate < 75 ? .high : .medium,
                        title: "Cobertura y fiabilidad",
                        summary: "Conviene revisar evidencias antes de dar por cerrada la lectura del grupo.",
                        facts: trendFacts,
                        recommendedActions: [.openNotebook, .evaluatePending, .openInspector],
                        confidenceNote: "Basado en tendencias y auditoría LOMLOE del grupo."
                    )
                )
            }
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
    let isLoadingAIBriefing: Bool
    let actionAvailability: (DashboardProactiveAction) -> Bool
    let onAction: (DashboardProactiveAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let aiBriefing {
                briefingBlock(aiBriefing)
            }
            if insights.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(insights.prefix(3)) { insight in
                        insightRow(insight)
                    }
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Label("Radar docente", systemImage: "scope")
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Spacer()
            if isLoadingAIBriefing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func briefingBlock(_ draft: TeachingAssistantDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                Text(draft.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
            }
            Text(draft.summary)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let confidence = draft.confidenceNote {
                Text(confidence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func insightRow(_ insight: DashboardProactiveInsight) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: insight.kind.systemImage)
                    .foregroundStyle(insight.priority.tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(insight.title)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text(insight.priority.label)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(insight.priority.tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(insight.priority.tint.opacity(0.12), in: Capsule())
                    }
                    Text(insight.summary)
                        .font(.system(size: 13, weight: .medium))
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
                                .padding(.top, 2)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func actionRow(for insight: DashboardProactiveInsight) -> some View {
        let actions = insight.recommendedActions.filter(actionAvailability)
        return Group {
            if !actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(actions.prefix(3)) { action in
                        Button {
                            onAction(action)
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .buttonStyle(.bordered)
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
            .padding(14)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
