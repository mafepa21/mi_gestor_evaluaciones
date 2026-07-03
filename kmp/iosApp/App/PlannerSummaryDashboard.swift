import SwiftUI
import MiGestorKit

struct PlannerSummaryDashboard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onOpenSettings: (() -> Void)?

    private var stats: PlannerSummaryStats {
        PlannerSummaryStats(vm: vm)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                metricsGrid

                HStack(alignment: .top, spacing: 24) {
                    PlannerUpcomingSessionsPanel(vm: vm, sessions: stats.upcomingSessions)
                        .frame(maxWidth: .infinity, alignment: .top)
                    PlannerCoveragePanel(vm: vm, rows: stats.coverageRows, onOpenSettings: onOpenSettings)
                        .frame(maxWidth: .infinity, alignment: .top)
                }

                PlannerAlertsPanel(alerts: stats.alerts)
            }
            .padding(EvaluationDesign.screenPadding)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Resumen")
                    .font(.title2.weight(.bold))
                Text("\(vm.weekLabel) · \(vm.dateRangeLabel)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let onOpenSettings {
                Button {
                    onOpenSettings()
                } label: {
                    Label("Agenda", systemImage: "calendar.badge.clock")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 16)], spacing: 16) {
            PlannerSummaryMetricCard(
                title: "Impartidas",
                value: "\(stats.completedSessions)",
                subtitle: "\(stats.completionPercent)% completitud",
                tint: EvaluationDesign.success,
                systemImage: "checkmark.seal.fill"
            )
            PlannerSummaryMetricCard(
                title: "Planificadas",
                value: "\(stats.plannedSessions)",
                subtitle: "Con sesión creada",
                tint: EvaluationDesign.accent,
                systemImage: "calendar"
            )
            PlannerSummaryMetricCard(
                title: "Pendientes",
                value: "\(stats.pendingSessions)",
                subtitle: "Sin diario cerrado",
                tint: IOSAppStyle.warning,
                systemImage: "exclamationmark.circle.fill"
            )
            PlannerSummaryMetricCard(
                title: "Cobertura",
                value: "\(stats.coveragePercent)%",
                subtitle: "\(stats.coveredSlots) de \(stats.totalSlots) franjas",
                tint: stats.coveragePercent >= 80 ? EvaluationDesign.success : EvaluationDesign.accent,
                systemImage: "chart.bar.xaxis"
            )
        }
    }
}

private struct PlannerSummaryStats {
    let completedSessions: Int
    let plannedSessions: Int
    let pendingSessions: Int
    let completionPercent: Int
    let coveredSlots: Int
    let totalSlots: Int
    let coveragePercent: Int
    let upcomingSessions: [PlanningSession]
    let coverageRows: [PlannerCoverageRow]
    let alerts: [PlannerSummaryAlert]

    @MainActor
    init(vm: PlannerWorkspaceViewModel) {
        let sessions = vm.filteredSessions
        completedSessions = sessions.count { session in
            session.status == .completed || vm.summary(for: session.id)?.status == .completed
        }
        plannedSessions = sessions.count
        pendingSessions = sessions.count { session in
            session.status != .completed && vm.summary(for: session.id)?.status != .completed
        }
        completionPercent = sessions.isEmpty ? 0 : Int((Double(completedSessions) / Double(sessions.count) * 100).rounded())

        let hasTeacherSchedule = !vm.teacherScheduleSlots.isEmpty
        coverageRows = vm.weekRenderModel.visibleDays.map { day in
            // Con agenda configurada, las franjas disponibles son las de ese día
            // (0 si el docente no imparte ese día); sin agenda, la parrilla visible.
            let available = hasTeacherSchedule
                ? vm.teacherScheduleSlots.filter { Int($0.dayOfWeek) == day }.count
                : vm.weekRenderModel.visibleSlots.count
            let coveredPeriods = Set(sessions.filter { Int($0.dayOfWeek) == day }.map { Int($0.period) }).count
            return PlannerCoverageRow(
                id: day,
                title: vm.dayHeaderLabel(for: day),
                covered: min(coveredPeriods, available),
                available: available
            )
        }
        coveredSlots = coverageRows.reduce(0) { $0 + $1.covered }
        totalSlots = coverageRows.reduce(0) { $0 + $1.available }
        coveragePercent = totalSlots == 0 ? 0 : Int((Double(coveredSlots) / Double(totalSlots) * 100).rounded())

        upcomingSessions = sessions
            .filter { session in
                session.status != .completed && vm.summary(for: session.id)?.status != .completed
            }
            .sorted {
                if $0.dayOfWeek == $1.dayOfWeek {
                    if $0.period == $1.period {
                        return ($0.startTime ?? "") < ($1.startTime ?? "")
                    }
                    return $0.period < $1.period
                }
                return $0.dayOfWeek < $1.dayOfWeek
            }
            .prefix(5)
            .map { $0 }

        var resolvedAlerts: [PlannerSummaryAlert] = []
        if pendingSessions > 0 {
            resolvedAlerts.append(.init(
                title: "\(pendingSessions) sesiones sin diario cerrado",
                message: "Revisa las próximas sesiones pendientes para mantener la continuidad docente.",
                tint: IOSAppStyle.warning,
                systemImage: "doc.badge.clock"
            ))
        }
        let emptyDays = coverageRows.filter { $0.covered == 0 && $0.available > 0 }
        if !emptyDays.isEmpty {
            resolvedAlerts.append(.init(
                title: "\(emptyDays.count) días sin sesiones creadas",
                message: emptyDays.map(\.title).joined(separator: " · "),
                tint: EvaluationDesign.accent,
                systemImage: "calendar.badge.exclamationmark"
            ))
        }
        let pendingSequences = vm.sequenceGroupsEnriched.reduce(0) { $0 + $1.pendingCount }
        if pendingSequences > 0 {
            resolvedAlerts.append(.init(
                title: "\(pendingSequences) sesiones de secuencia sin ubicar",
                message: "Abre Secuencia para revisar las situaciones con sesiones pendientes.",
                tint: IOSAppStyle.warning,
                systemImage: "point.3.connected.trianglepath.dotted"
            ))
        }
        if sessions.isEmpty {
            resolvedAlerts.append(.init(
                title: "Semana sin planificación",
                message: "Configura la agenda o crea sesiones desde Semana.",
                tint: .secondary,
                systemImage: "calendar.badge.plus"
            ))
        }
        alerts = resolvedAlerts
    }
}

private struct PlannerCoverageRow: Identifiable {
    let id: Int
    let title: String
    let covered: Int
    let available: Int

    var ratio: Double {
        guard available > 0 else { return 0 }
        return min(Double(covered) / Double(available), 1)
    }
}

private struct PlannerSummaryAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let tint: Color
    let systemImage: String
}

private struct PlannerSummaryMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let tint: Color
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(EvaluationDesign.border, lineWidth: 1)
        )
    }
}

private struct PlannerUpcomingSessionsPanel: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let sessions: [PlanningSession]

    var body: some View {
        PlannerSummaryPanel(title: "Próximas sesiones", systemImage: "clock.badge") {
            if sessions.isEmpty {
                PlannerCompactEmptyState(
                    title: "Sin pendientes próximos",
                    message: "No hay sesiones abiertas para esta semana."
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(sessions, id: \.id) { session in
                        PlannerUpcomingSessionRow(vm: vm, session: session)
                    }
                }
            }
        }
    }
}

private struct PlannerUpcomingSessionRow: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let session: PlanningSession

    private var tint: Color { Color(hex: vm.classColorHex(for: session.groupId)) }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.dayLabel(for: Int(session.dayOfWeek)))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(vm.timeLabel(for: Int(session.period)))
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 88, alignment: .leading)

            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.teachingUnitName.trimmedOrFallback("Sesión sin título"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(session.groupName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(12)
        .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PlannerCoveragePanel: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let rows: [PlannerCoverageRow]
    let onOpenSettings: (() -> Void)?

    var body: some View {
        PlannerSummaryPanel(title: "Cobertura horaria", systemImage: "chart.bar.xaxis") {
            if rows.isEmpty {
                PlannerCompactEmptyState(
                    title: "Sin franjas",
                    message: "Configura la agenda docente para ver cobertura."
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(rows) { row in
                        PlannerCoverageRowView(row: row)
                    }

                    if let onOpenSettings {
                        Button {
                            onOpenSettings()
                        } label: {
                            Label("Ajustar agenda", systemImage: "slider.horizontal.3")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                    }
                }
            }
        }
    }
}

private struct PlannerCoverageRowView: View {
    let row: PlannerCoverageRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.title)
                    .font(.caption.weight(.bold))
                Spacer()
                Text("\(row.covered)/\(row.available)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.secondary.opacity(0.14))
                    Capsule(style: .continuous)
                        .fill(tint)
                        .frame(width: proxy.size.width * row.ratio)
                }
            }
            .frame(height: 8)
        }
    }

    private var tint: Color {
        if row.ratio >= 0.8 { return EvaluationDesign.success }
        if row.ratio > 0 { return EvaluationDesign.accent }
        return IOSAppStyle.warning
    }
}

private struct PlannerAlertsPanel: View {
    let alerts: [PlannerSummaryAlert]

    var body: some View {
        PlannerSummaryPanel(title: "Alertas", systemImage: "bell.badge") {
            if alerts.isEmpty {
                PlannerCompactEmptyState(
                    title: "Sin alertas",
                    message: "La semana no tiene pendientes relevantes."
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(alerts) { alert in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: alert.systemImage)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(alert.tint)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(alert.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(alert.message)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                        }
                        .padding(12)
                        .background(alert.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }
}

private struct PlannerSummaryPanel<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(EvaluationDesign.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline.weight(.bold))
            }

            content
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(EvaluationDesign.border, lineWidth: 1)
        )
    }
}

private struct PlannerCompactEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension String {
    func trimmedOrFallback(_ fallback: String) -> String {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? fallback : value
    }
}
