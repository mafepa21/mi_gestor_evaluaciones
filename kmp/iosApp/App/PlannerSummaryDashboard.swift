import SwiftUI
import MiGestorKit

struct PlannerSummaryDashboard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onOpenSettings: (() -> Void)?
    let onOpenSession: (PlanningSession) -> Void
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags

    @State private var selectedRange: PlannerReportRange = .week
    @State private var rangeData: PlannerRangeData = .empty
    @State private var isLoadingRange = false
    @State private var isGeneratingReport = false
    @State private var reportURL: URL?
    @State private var reportError: String?
    @State private var showingReportShare = false

    @State private var stats: PlannerSummaryStats = PlannerSummaryStats()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                metricsGrid

                if selectedRange == .week {
                    HStack(alignment: .top, spacing: 24) {
                        PlannerUpcomingSessionsPanel(vm: vm, sessions: stats.upcomingSessions)
                            .frame(maxWidth: .infinity, alignment: .top)
                        PlannerCoveragePanel(vm: vm, rows: stats.coverageRows, onOpenSettings: onOpenSettings)
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                }

                PlannerAlertsPanel(alerts: stats.alerts)
            }
            .padding(EvaluationDesign.screenPadding)
        }
        .task(id: rangeTaskKey) {
            await reloadRangeData()
        }
        .alert("No se pudo generar el informe", isPresented: Binding(
            get: { reportError != nil },
            set: { if !$0 { reportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reportError ?? "")
        }
        .sheet(isPresented: $showingReportShare) {
            if let reportURL {
                #if os(iOS)
                NavigationStack {
                    reportSuccessView(reportURL: reportURL)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cerrar") { showingReportShare = false }
                            }
                        }
                }
                .presentationDetents([.medium])
                #else
                VStack(spacing: 0) {
                    reportSuccessView(reportURL: reportURL)
                    
                    HStack {
                        Spacer()
                        Button("Cerrar") { showingReportShare = false }
                    }
                    .padding()
                }
                .frame(width: 320, height: 280)
                #endif
            }
        }
    }
    
    private func reportSuccessView(reportURL: URL) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(EvaluationDesign.success)
            
            VStack(spacing: 8) {
                Text("Informe generado")
                    .font(.title2.weight(.bold))
                
                Text("El documento PDF está listo.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            ShareLink(item: reportURL) {
                Label("Compartir informe", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    #if os(iOS)
                    .frame(maxWidth: .infinity)
                    #endif
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            #if os(iOS)
            .padding(.horizontal, 32)
            #endif
        }
        .padding(32)
    }

    private var rangeTaskKey: String {
        let periodSuffix: String
        if case .evaluationPeriod(let id) = selectedRange { periodSuffix = "-\(id)" } else { periodSuffix = "" }
        return "\(selectedRange)\(periodSuffix)-\(vm.selectedGroupId ?? -1)"
    }

    private func reloadRangeData() async {
        isLoadingRange = true
        reportURL = nil
        defer { isLoadingRange = false }
        let data = await vm.loadRangeData(selectedRange, groupId: vm.selectedGroupId)
        let newStats = PlannerSummaryStats(vm: vm, rangeData: data, onOpenSession: onOpenSession)
        withAnimation(uiFeatureFlags.interactionAnimation) {
            rangeData = data
            stats = newStats
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Resumen")
                        .font(.title2.weight(.bold))
                    Text(rangeData.rangeLabel.isEmpty ? "\(vm.weekLabel) · \(vm.dateRangeLabel)" : rangeData.rangeLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isLoadingRange {
                    ProgressView()
                        .tint(EvaluationDesign.accent)
                }

                if let onOpenSettings {
                    Button {
                        onOpenSettings()
                    } label: {
                        Label("Agenda", systemImage: "calendar.badge.clock")
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 8) {
                Picker("Rango", selection: $selectedRange) {
                    Text("Semana").tag(PlannerReportRange.week)
                    Text("Mes").tag(PlannerReportRange.month)
                    ForEach(sortedEvaluationPeriods, id: \.id) { period in
                        Text(period.name).tag(PlannerReportRange.evaluationPeriod(period.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)

                Spacer()

                exportButton
            }
        }
    }

    @ViewBuilder
    private var exportButton: some View {
        if isGeneratingReport {
            ProgressView()
                .controlSize(.small)
        } else {
            Button {
                Task { await generateReport() }
            } label: {
                Label("Generar informe PDF", systemImage: "doc.richtext")
            }
            .buttonStyle(.borderedProminent)
            .disabled(rangeData.sessions.isEmpty)
        }
    }

    private func generateReport() async {
        if reportURL != nil {
            showingReportShare = true
            return
        }
        
        isGeneratingReport = true
        defer { isGeneratingReport = false }

        let groupName = vm.selectedGroupId.flatMap { id in vm.groups.first { $0.id == id }?.name }
        let document = PlannerReportDocument.build(rangeData: rangeData, groupFilterName: groupName, vm: vm)
        guard let url = PlannerReportPDFRenderer.writeToTemporaryFile(document, suggestedName: "informe-planificacion") else {
            reportError = "No se pudo escribir el archivo PDF. Inténtalo de nuevo."
            return
        }
        reportURL = url
        showingReportShare = true
    }

    private var sortedEvaluationPeriods: [PlannerEvaluationPeriod] {
        vm.evaluationPeriods.sorted { ($0.sortOrder, $0.startDateIso) < ($1.sortOrder, $1.startDateIso) }
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
                title: "No impartidas",
                value: "\(stats.notDeliveredSessions)",
                subtitle: "De semanas ya pasadas",
                tint: stats.notDeliveredSessions > 0 ? IOSAppStyle.warning : EvaluationDesign.success,
                systemImage: "exclamationmark.triangle.fill"
            )
            if selectedRange == .week {
                PlannerSummaryMetricCard(
                    title: "Cobertura",
                    value: "\(stats.coveragePercent)%",
                    subtitle: "\(stats.coveredSlots) de \(stats.totalSlots) franjas",
                    tint: stats.coveragePercent >= 80 ? EvaluationDesign.success : EvaluationDesign.accent,
                    systemImage: "chart.bar.xaxis"
                )
            } else {
                PlannerSummaryMetricCard(
                    title: "Canceladas",
                    value: "\(stats.cancelledSessions)",
                    subtitle: "En el rango seleccionado",
                    tint: stats.cancelledSessions > 0 ? IOSAppStyle.warning : .secondary,
                    systemImage: "xmark.circle"
                )
            }
        }
    }
}

private struct PlannerSummaryStats {
    let completedSessions: Int
    let plannedSessions: Int
    let pendingSessions: Int
    let cancelledSessions: Int
    let notDeliveredSessions: Int
    let completionPercent: Int
    let coveredSlots: Int
    let totalSlots: Int
    let coveragePercent: Int
    let upcomingSessions: [PlanningSession]
    let coverageRows: [PlannerCoverageRow]
    let alerts: [PlannerSummaryAlert]

    init() {
        self.completedSessions = 0
        self.plannedSessions = 0
        self.pendingSessions = 0
        self.cancelledSessions = 0
        self.notDeliveredSessions = 0
        self.completionPercent = 0
        self.coveredSlots = 0
        self.totalSlots = 0
        self.coveragePercent = 0
        self.upcomingSessions = []
        self.coverageRows = []
        self.alerts = []
    }

    @MainActor
    init(vm: PlannerWorkspaceViewModel, rangeData: PlannerRangeData, onOpenSession: @escaping (PlanningSession) -> Void) {
        let sessions = rangeData.sessions
        let currentWeek = PlannerGanttWeek(date: Date())

        func summary(for sessionId: Int64) -> SessionJournalSummary? {
            rangeData.journalSummaryBySessionId[sessionId]
        }
        func isPastAndNotDelivered(_ session: PlanningSession) -> Bool {
            guard session.status != .completed, session.status != .cancelled else { return false }
            let week = PlannerGanttWeek(year: Int(session.year), week: Int(session.weekNumber))
            return week.weeks(until: currentWeek) > 0
        }

        completedSessions = sessions.count { $0.status == .completed }
        cancelledSessions = sessions.count { $0.status == .cancelled }
        notDeliveredSessions = sessions.count { isPastAndNotDelivered($0) }
        plannedSessions = sessions.count
        pendingSessions = sessions.count { session in
            session.status == .completed && summary(for: session.id)?.status != .completed
        }
        completionPercent = sessions.isEmpty ? 0 : Int((Double(completedSessions) / Double(sessions.count) * 100).rounded())

        let hasTeacherSchedule = !vm.teacherScheduleSlots.isEmpty
        if rangeData.range == .week {
            coverageRows = vm.weekRenderModel.visibleDays.map { day in
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
        } else {
            coverageRows = []
        }
        coveredSlots = coverageRows.reduce(0) { $0 + $1.covered }
        totalSlots = coverageRows.reduce(0) { $0 + $1.available }
        coveragePercent = totalSlots == 0 ? 0 : Int((Double(coveredSlots) / Double(totalSlots) * 100).rounded())

        upcomingSessions = sessions
            .filter { session in
                session.status != .completed && summary(for: session.id)?.status != .completed
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
        let pendingJournalSessions = sessions.filter { session in
            session.status == .completed && summary(for: session.id)?.status != .completed
        }
        if let firstPending = pendingJournalSessions.first {
            resolvedAlerts.append(.init(
                title: "\(pendingJournalSessions.count) sesiones sin diario cerrado",
                message: "Abre la primera pendiente para ponerte al día.",
                tint: IOSAppStyle.warning,
                systemImage: "doc.badge.clock",
                action: { onOpenSession(firstPending) }
            ))
        }
        if notDeliveredSessions > 0, let firstNotDelivered = sessions.first(where: isPastAndNotDelivered) {
            resolvedAlerts.append(.init(
                title: "\(notDeliveredSessions) sesiones no impartidas",
                message: "De semanas ya pasadas y sin marcar como impartidas.",
                tint: IOSAppStyle.warning,
                systemImage: "exclamationmark.triangle.fill",
                action: { onOpenSession(firstNotDelivered) }
            ))
        }
        if rangeData.range == .week {
            let emptyDays = coverageRows.filter { $0.covered == 0 && $0.available > 0 }
            if !emptyDays.isEmpty {
                resolvedAlerts.append(.init(
                    title: "\(emptyDays.count) días sin sesiones creadas",
                    message: emptyDays.map(\.title).joined(separator: " · "),
                    tint: EvaluationDesign.accent,
                    systemImage: "calendar.badge.exclamationmark",
                    action: { vm.activeSection = .week }
                ))
            }
            let pendingSequences = vm.sequenceGroupsEnriched.reduce(0) { $0 + $1.pendingCount }
            if pendingSequences > 0 {
                resolvedAlerts.append(.init(
                    title: "\(pendingSequences) sesiones de secuencia sin ubicar",
                    message: "Abre Secuencia para revisar las situaciones con sesiones pendientes.",
                    tint: IOSAppStyle.warning,
                    systemImage: "point.3.connected.trianglepath.dotted",
                    action: { vm.activeSection = .sequence }
                ))
            }
            if sessions.isEmpty {
                resolvedAlerts.append(.init(
                    title: "Semana sin planificación",
                    message: "Configura la agenda o crea sesiones desde Semana.",
                    tint: .secondary,
                    systemImage: "calendar.badge.plus",
                    action: { vm.activeSection = .week }
                ))
            }
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
    let action: (() -> Void)?
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
                    .contentTransition(.numericText())
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .plannerGlassPanel(.content, cornerRadius: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value), \(subtitle)")
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
            VStack(alignment: .leading, spacing: 12) {
                if let remainingWeeks {
                    Label(
                        "Quedan \(remainingWeeks) semana\(remainingWeeks == 1 ? "" : "s") lectiva\(remainingWeeks == 1 ? "" : "s")",
                        systemImage: "calendar"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(EvaluationDesign.accent)
                }

                if rows.isEmpty {
                    PlannerCompactEmptyState(
                        title: "Sin franjas",
                        message: "Configura la agenda docente para ver cobertura."
                    )
                } else {
                    ForEach(rows) { row in
                        PlannerCoverageRowView(row: row)
                    }
                }

                // Antes este botón vivía dentro del `else` de `rows.isEmpty`:
                // justo el profesor sin agenda configurada —el único que de
                // verdad la necesita— era el único que no lo veía.
                if let onOpenSettings {
                    if rows.isEmpty {
                        Button {
                            onOpenSettings()
                        } label: {
                            Label("Configurar mi horario", systemImage: "slider.horizontal.3")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                    } else {
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

    /// Semanas restantes hasta el final de curso configurado (`vm.scheduleEndDate`),
    /// para dar contexto a un porcentaje de cobertura que si no queda sin referencia.
    private var remainingWeeks: Int? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        guard let endDate = formatter.date(from: vm.scheduleEndDate) else { return nil }
        let days = Calendar(identifier: .iso8601).dateComponents([.day], from: Date(), to: endDate).day ?? 0
        guard days > 0 else { return nil }
        return Int((Double(days) / 7.0).rounded(.up))
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
                    .contentTransition(.numericText())
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
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityValue("\(row.covered) de \(row.available) cubiertas, \(Int(row.ratio * 100)) por ciento")
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
                    message: "El rango seleccionado no tiene pendientes relevantes."
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(alerts) { alert in
                        PlannerAlertRow(alert: alert)
                    }
                }
            }
        }
    }
}

private struct PlannerAlertRow: View {
    let alert: PlannerSummaryAlert

    var body: some View {
        if let action = alert.action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: alert.systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(alert.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(alert.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(alert.message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if alert.action != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(alert.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
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
        .plannerGlassPanel(.content, cornerRadius: 12)
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
