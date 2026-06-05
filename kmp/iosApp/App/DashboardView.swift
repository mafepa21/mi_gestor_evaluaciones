import SwiftUI
import MiGestorKit

// MARK: - Dashboard Module
private enum OperationalDashboardMode: String {
    case classroom
    case office

    var kotlinMode: DashboardMode {
        switch self {
        case .classroom: return .classroom
        case .office: return .office
        }
    }

    var title: String {
        switch self {
        case .classroom: return "Modo Clase"
        case .office: return "Modo Despacho"
        }
    }
}

private enum DashboardInspectorSelection: Hashable {
    case session(Int64)
    case alert(String)
    case pe(String)
}

private struct DashboardGroupRow: Identifiable {
    let id: Int64
    let groupName: String
    let attendancePct: Int
    let evaluationCompletedPct: Int
    let averageScore: Double
    let studentsInFollowUp: Int
}

private enum DashboardBlock: Hashable {
    case today
    case pending
    case risk
    case system
    case alerts
    case quickEvaluation
    case groupSummary
    case agenda
    case physicalEducation
    case lomloeAudit
}

private enum DashboardFilterOption: String, CaseIterable, Identifiable {
    case all = ""
    case high
    case medium
    case low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Todas"
        case .high: return "Alta"
        case .medium: return "Media"
        case .low: return "Baja"
        }
    }
}

private enum DashboardSessionFilterOption: String, CaseIterable, Identifiable {
    case all = ""
    case planned
    case inProgress = "in_progress"
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Todas"
        case .planned: return "Planificadas"
        case .inProgress: return "En curso"
        case .completed: return "Completadas"
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var bridge: KmpBridge
    @EnvironmentObject private var layoutState: WorkspaceLayoutState
    @Environment(\.colorScheme) private var colorScheme
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    @Binding var selectedClassId: Int64?
    @AppStorage("dashboard_operational_mode") private var modeRawValue: String = OperationalDashboardMode.office.rawValue
    @State private var severityFilter: DashboardFilterOption = .all
    @State private var priorityFilter: DashboardFilterOption = .all
    @State private var sessionStatusFilter: DashboardSessionFilterOption = .all
    @State private var inspectorSelection: DashboardInspectorSelection? = nil
    @State private var isInspectorPresented = false
    @State private var isQuickEvaluationPresented = false
    @State private var classTrends: KmpBridge.AITrendsSnapshot? = nil
    @State private var isLoadingClassTrends = false

    private var mode: OperationalDashboardMode {
        OperationalDashboardMode(rawValue: modeRawValue) ?? .office
    }

    private var isCompactWidth: Bool {
#if os(iOS)
        horizontalSizeClass == .compact
#else
        false
#endif
    }

    private var showsWideSummary: Bool {
        !isCompactWidth
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                dashboardHeader
                dashboardContent
            }

            if isInspectorPresented && !isCompactWidth {
                inspectorPane
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isInspectorPresented)
        .background(appPageBackground(for: colorScheme).ignoresSafeArea())
        .sheet(isPresented: $isQuickEvaluationPresented) {
            DashboardQuickEvaluationSheet(
                bridge: bridge,
                initialClassId: dashboardActionClassId,
                mode: mode.kotlinMode
            )
        }
#if os(iOS)
        .sheet(isPresented: Binding(
            get: { isInspectorPresented && isCompactWidth },
            set: { isInspectorPresented = $0 }
        )) {
            dashboardInspector
                .presentationDetents([.medium, .large])
        }
#endif
        .task {
            await bridge.ensureClassesLoaded()
            if selectedClassId == nil {
                selectedClassId = bridge.classes.first?.id
            }
            await applyFiltersAndReload()
        }
        .onAppear(perform: scheduleToolbarStateSync)
        .appOnChange(of: selectedClassId) { _ in triggerDashboardReload() }
        .appOnChange(of: modeRawValue) { _ in triggerDashboardReload() }
        .appOnChange(of: severityFilter) { _ in triggerDashboardReload() }
        .appOnChange(of: priorityFilter) { _ in triggerDashboardReload() }
        .appOnChange(of: sessionStatusFilter) { _ in triggerDashboardReload() }
        .appOnChange(of: inspectorSelection) { _ in scheduleInspectorSelectionSync() }
        .appOnChange(of: isInspectorPresented) { _ in scheduleToolbarStateSync() }
        .appOnChange(of: toolbarStateKey) { _ in scheduleToolbarStateSync() }
        .onDisappear {
            layoutState.clearDashboardToolbar()
        }
        .refreshable {
            await applyFiltersAndReload()
            await bridge.pullMissingSyncChanges()
        }
    }

    private var inspectorPane: some View {
        Group {
            Divider().opacity(0.18)
            dashboardInspector
                .frame(width: 320)
                .background(appCardBackground(for: colorScheme))
        }
    }

    private func triggerDashboardReload() {
        Task {
            await applyFiltersAndReload()
        }
    }

    private func handleInspectorSelectionChange() {
        if inspectorSelection == nil {
            isInspectorPresented = false
        }
        syncToolbarState()
    }

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Centro de trabajo")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                    Text("Hoy, pendientes, riesgo y sistema · \(selectedClassLabel)")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let snapshot = bridge.dashboardSnapshot {
                    dashboardExportMenu(snapshot: snapshot)
                }

                Picker("Contexto", selection: $modeRawValue) {
                    Text("Clase").tag(OperationalDashboardMode.classroom.rawValue)
                    Text("Despacho").tag(OperationalDashboardMode.office.rawValue)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }

            dashboardFilterChips
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(appMutedCardBackground(for: colorScheme))
    }

    private var dashboardContent: some View {
        ScrollView {
            if let snapshot = bridge.dashboardSnapshot {
                VStack(alignment: .leading, spacing: EvaluationDesign.sectionSpacing) {
                    dashboardWorkCenter(snapshot: snapshot)

                    let blocks: [DashboardBlock] = mode == .classroom
                        ? [.quickEvaluation, .groupSummary, .agenda, .lomloeAudit]
                        : [.lomloeAudit, .groupSummary, .agenda, .quickEvaluation]

                    ForEach(blocks, id: \.self) { block in
                        switch block {
                        case .today:
                            dashboardTodayBlock(snapshot: snapshot)
                        case .pending:
                            dashboardPendingBlock(snapshot: snapshot)
                        case .risk:
                            dashboardRiskBlock(snapshot: snapshot)
                        case .system:
                            dashboardSystemBlock()
                        case .alerts:
                            dashboardAlertsBlock(snapshot: snapshot)
                        case .quickEvaluation:
                            dashboardQuickEvalBlock(snapshot: snapshot)
                        case .groupSummary:
                            dashboardGroupSummaryBlock(snapshot: snapshot)
                        case .agenda:
                            dashboardAgendaBlock(snapshot: snapshot)
                        case .physicalEducation:
                            dashboardPEBlock(snapshot: snapshot)
                        case .lomloeAudit:
                            dashboardLomloeAuditBlock(snapshot: snapshot)
                        }
                    }
                }
                .padding(EvaluationDesign.screenPadding)
            } else {
                ProgressView("Cargando dashboard operativo...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
            }
        }
    }

    private var dashboardInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detalle")
                .font(.title3.bold())

            if let snapshot = bridge.dashboardSnapshot {
                switch inspectorSelection {
                case .session(let id):
                    if let item = snapshot.todaySessions.first(where: { $0.id == id }) {
                        Text(item.groupName).font(.headline)
                        Text(item.didacticUnit)
                        Text("Horario: \(item.timeLabel)")
                        Text("Espacio: \(item.space)")
                        Text("Estado: \(dashboardSessionStatusLabel(item.sessionStatus))")
                    } else {
                        Text("Sesión no encontrada")
                    }
                case .alert(let id):
                    if let alert = snapshot.alerts.first(where: { $0.id == id }) {
                        Text(alert.title).font(.headline)
                        Text(alert.detail)
                        Text("Severidad: \(dashboardFilterLabel(alert.severity))")
                        Text("Prioridad: \(dashboardFilterLabel(alert.priority))")
                    } else {
                        Text("Alerta no encontrada")
                    }
                case .pe(let id):
                    if let item = snapshot.peItems.first(where: { $0.id == id }) {
                        Text(item.title).font(.headline)
                        Text(item.detail)
                        Text("Severidad: \(dashboardFilterLabel(item.severity))")
                    } else {
                        Text("Ítem EF no encontrado")
                    }
                case .none:
                    Text("Selecciona una sesión, alerta o bloque EF para revisar.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Sin datos")
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var selectedClassLabel: String {
        guard let selectedClassId,
              let schoolClass = bridge.classes.first(where: { $0.id == selectedClassId }) else {
            return "Clase global activa"
        }
        return "\(schoolClass.name) · \(schoolClass.course)º"
    }

    private var dashboardActionClassId: Int64? {
        selectedClassId ?? bridge.classes.first?.id
    }

    private var toolbarStateKey: String {
        let classKey = selectedClassId ?? -1
        let inspectorKey: String
        switch inspectorSelection {
        case .session(let id):
            inspectorKey = "session_\(id)"
        case .alert(let id):
            inspectorKey = "alert_\(id)"
        case .pe(let id):
            inspectorKey = "pe_\(id)"
        case .none:
            inspectorKey = "none"
        }
        return "\(classKey)|\(modeRawValue)|\(severityFilter.rawValue)|\(priorityFilter.rawValue)|\(sessionStatusFilter.rawValue)|\(inspectorKey)|\(isInspectorPresented)"
    }

    private var dashboardFilterChips: some View {
        HStack(alignment: .bottom, spacing: 12) {
            dashboardFilterPicker(title: "Severidad", selection: $severityFilter, options: DashboardFilterOption.allCases)
            dashboardFilterPicker(title: "Prioridad", selection: $priorityFilter, options: DashboardFilterOption.allCases)
            dashboardSessionFilterPicker(title: "Sesiones", selection: $sessionStatusFilter, options: DashboardSessionFilterOption.allCases)
        }
    }

    @ViewBuilder
    private func dashboardKpiRow(snapshot: DashboardSnapshot) -> some View {
        HStack(spacing: 12) {
            dashboardKpiCard(title: "Hoy", value: "\(snapshot.todayCount)")
            dashboardKpiCard(title: "Alertas", value: "\(snapshot.alertsCount)")
            dashboardKpiCard(title: "Pendientes", value: "\(snapshot.pendingCount)")
            dashboardKpiCard(title: "Próxima sesión", value: snapshot.nextSessionLabel)
        }
    }

    @ViewBuilder
    private func dashboardKpiCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(appCardBackground(for: colorScheme))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func dashboardWorkCenter(snapshot: DashboardSnapshot) -> some View {
        if isCompactWidth {
            VStack(spacing: EvaluationDesign.cardSpacing) {
                dashboardTodayBlock(snapshot: snapshot)
                dashboardPendingBlock(snapshot: snapshot)
                dashboardRiskBlock(snapshot: snapshot)
                dashboardSystemBlock()
            }
        } else {
            VStack(spacing: EvaluationDesign.cardSpacing) {
                dashboardTodayBlock(snapshot: snapshot)
                
                let columns = [
                    GridItem(.flexible(), spacing: EvaluationDesign.cardSpacing, alignment: .top),
                    GridItem(.flexible(), spacing: EvaluationDesign.cardSpacing, alignment: .top),
                    GridItem(.flexible(), spacing: EvaluationDesign.cardSpacing, alignment: .top)
                ]
                LazyVGrid(columns: columns, alignment: .center, spacing: EvaluationDesign.cardSpacing) {
                    dashboardPendingBlock(snapshot: snapshot)
                    dashboardRiskBlock(snapshot: snapshot)
                    dashboardSystemBlock()
                }
            }
        }
    }

    private func dashboardExportMenu(snapshot: DashboardSnapshot) -> some View {
        Menu {
            ShareLink("Hoy", item: csvToday(snapshot))
            ShareLink("Alertas", item: csvAlerts(snapshot))
            ShareLink("Grupos", item: csvGroups(snapshot.groupSummaries.map {
                DashboardGroupRow(
                    id: $0.classId,
                    groupName: $0.groupName,
                    attendancePct: Int($0.attendancePct),
                    evaluationCompletedPct: Int($0.evaluationCompletedPct),
                    averageScore: $0.averageScore,
                    studentsInFollowUp: Int($0.studentsInFollowUp)
                )
            }))
            ShareLink("Agenda", item: csvAgenda(snapshot))
        } label: {
            Label("Exportar", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func dashboardTodayBlock(snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Hoy", systemImage: "calendar.badge.clock")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Text("\(snapshot.todaySessions.count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            ForEach(snapshot.todaySessions, id: \.id) { item in
                Button {
                    inspectorSelection = .session(item.id)
                    isInspectorPresented = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(item.groupName) · \(item.timeLabel)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Text(item.didacticUnit)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("Espacio: \(item.space) · \(dashboardSessionStatusLabel(item.sessionStatus))")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        appMutedCardBackground(for: colorScheme)
                            .overlay(
                                RoundedRectangle(cornerRadius: EvaluationDesign.pillRadius, style: .continuous)
                                    .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                            )
                    )
                    .cornerRadius(EvaluationDesign.pillRadius)
                }
                .buttonStyle(ScaleButtonStyle())
            }
            if snapshot.todaySessions.isEmpty {
                Text("Sin sesiones hoy")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(EvaluationDesign.cardSpacing)
        .background(.regularMaterial)
        .cornerRadius(EvaluationDesign.innerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.06), lineWidth: 1)
        )
        .shadow(color: EvaluationDesign.accent.opacity(colorScheme == .dark ? 0.22 : 0.05), radius: 14, x: 0, y: 8)
    }

    @ViewBuilder
    private func dashboardPendingBlock(snapshot: DashboardSnapshot) -> some View {
        let pendingAlerts = snapshot.alerts.filter { isPendingAlert($0) }
        let pendingAgenda = snapshot.agendaItems.filter { !isClosedAgendaStatus($0.status) }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pendiente", systemImage: "tray.full")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Text("\(snapshot.pendingCount)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            ForEach(pendingAlerts.prefix(4), id: \.id) { alert in
                dashboardActionRow(
                    title: pendingTitle(alert),
                    subtitle: alert.detail,
                    systemImage: "circle.dotted",
                    tint: .orange
                ) {
                    inspectorSelection = .alert(alert.id)
                    isInspectorPresented = true
                }
            }

            ForEach(pendingAgenda.prefix(max(0, 5 - pendingAlerts.prefix(4).count)), id: \.id) { item in
                dashboardStaticRow(
                    title: item.title,
                    subtitle: item.subtitle,
                    systemImage: "calendar.badge.exclamationmark",
                    tint: .orange
                )
            }

            if pendingAlerts.isEmpty && pendingAgenda.isEmpty && snapshot.pendingCount == 0 {
                Text("Sin pendientes críticos con los datos disponibles.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(EvaluationDesign.cardSpacing)
        .background(.regularMaterial)
        .cornerRadius(EvaluationDesign.innerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.06), lineWidth: 1)
        )
        .shadow(color: Color.orange.opacity(colorScheme == .dark ? 0.22 : 0.05), radius: 14, x: 0, y: 8)
    }

    @ViewBuilder
    private func dashboardRiskBlock(snapshot: DashboardSnapshot) -> some View {
        let riskAlerts = snapshot.alerts.filter { !isPendingAlert($0) }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Riesgo", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Text("\(riskAlerts.count + snapshot.peItems.count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            ForEach(riskAlerts.prefix(4), id: \.id) { alert in
                dashboardActionRow(
                    title: riskTitle(alert),
                    subtitle: alert.detail,
                    systemImage: riskIcon(alert),
                    tint: riskTint(alert.severity)
                ) {
                    inspectorSelection = .alert(alert.id)
                    isInspectorPresented = true
                }
            }

            ForEach(snapshot.peItems.prefix(max(0, 5 - riskAlerts.prefix(4).count)), id: \.id) { item in
                dashboardActionRow(
                    title: item.title,
                    subtitle: item.detail,
                    systemImage: "cross.case",
                    tint: riskTint(item.severity)
                ) {
                    inspectorSelection = .pe(item.id)
                    isInspectorPresented = true
                }
            }

            if riskAlerts.isEmpty && snapshot.peItems.isEmpty {
                Text("Sin alumnado en riesgo detectado por las reglas actuales.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(EvaluationDesign.cardSpacing)
        .background(.regularMaterial)
        .cornerRadius(EvaluationDesign.innerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.06), lineWidth: 1)
        )
        .shadow(color: Color.red.opacity(colorScheme == .dark ? 0.22 : 0.05), radius: 14, x: 0, y: 8)
    }

    @ViewBuilder
    private func dashboardSystemBlock() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Sistema", systemImage: "checkmark.shield")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
            }
            dashboardStaticRow(
                title: bridge.pairedSyncHost == nil ? "Sync LAN inactivo" : "Sync LAN activo",
                subtitle: bridge.syncPendingChanges == 0 ? bridge.syncStatusMessage : "\(bridge.syncPendingChanges) cambios pendientes",
                systemImage: "arrow.triangle.2.circlepath",
                tint: bridge.syncPendingChanges == 0 && bridge.pairedSyncHost != nil ? .green : .orange
            )
            dashboardStaticRow(
                title: "Última sync",
                subtitle: bridge.syncLastRunAt.map(shortSystemDate) ?? "Sin registro",
                systemImage: "clock",
                tint: .secondary
            )
            dashboardStaticRow(
                title: "Último backup",
                subtitle: "Sin registro local en iPad. Revisa Backups en macOS.",
                systemImage: "externaldrive.badge.questionmark",
                tint: .secondary
            )
        }
        .padding(EvaluationDesign.cardSpacing)
        .background(.regularMaterial)
        .cornerRadius(EvaluationDesign.innerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.06), lineWidth: 1)
        )
        .shadow(color: Color.green.opacity(colorScheme == .dark ? 0.22 : 0.05), radius: 14, x: 0, y: 8)
    }

    @ViewBuilder
    private func dashboardAlertsBlock(snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Alertas")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
            }
            ForEach(snapshot.alerts.prefix(8), id: \.id) { alert in
                Button {
                    inspectorSelection = .alert(alert.id)
                    isInspectorPresented = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(alert.title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Text(alert.detail)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(dashboardFilterLabel(alert.severity))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(riskTint(alert.severity).opacity(0.12), in: Capsule())
                            .foregroundStyle(riskTint(alert.severity))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        appMutedCardBackground(for: colorScheme)
                            .overlay(
                                RoundedRectangle(cornerRadius: EvaluationDesign.pillRadius, style: .continuous)
                                    .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                            )
                    )
                    .cornerRadius(EvaluationDesign.pillRadius)
                }
                .buttonStyle(ScaleButtonStyle())
            }
            if snapshot.alerts.isEmpty {
                Text("Sin alertas")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(EvaluationDesign.cardSpacing)
        .background(.regularMaterial)
        .cornerRadius(EvaluationDesign.innerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.06), lineWidth: 1)
        )
        .shadow(color: Color.red.opacity(colorScheme == .dark ? 0.22 : 0.05), radius: 14, x: 0, y: 8)
    }

    @ViewBuilder
    private func dashboardQuickEvalBlock(snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Evaluación rápida")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
            }
            if !snapshot.quickColumns.isEmpty {
                Text("Columnas disponibles: \(snapshot.quickColumns.joined(separator: ", "))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if !snapshot.quickRubrics.isEmpty {
                Text("Rúbricas disponibles: \(snapshot.quickRubrics.joined(separator: ", "))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("Pasar lista") {
                    Task { await performPassList() }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Button("Nueva observación") {
                    Task { await performObservation() }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Button("Evaluar") {
                    isQuickEvaluationPresented = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(EvaluationDesign.cardSpacing)
        .background(.regularMaterial)
        .cornerRadius(EvaluationDesign.innerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.06), lineWidth: 1)
        )
        .shadow(color: EvaluationDesign.accent.opacity(colorScheme == .dark ? 0.22 : 0.05), radius: 14, x: 0, y: 8)
    }

    @ViewBuilder
    private func dashboardGroupSummaryBlock(snapshot: DashboardSnapshot) -> some View {
        let rows = snapshot.groupSummaries.map {
            DashboardGroupRow(
                id: $0.classId,
                groupName: $0.groupName,
                attendancePct: Int($0.attendancePct),
                evaluationCompletedPct: Int($0.evaluationCompletedPct),
                averageScore: $0.averageScore,
                studentsInFollowUp: Int($0.studentsInFollowUp)
            )
        }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Resumen por grupo")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
            }
            if showsWideSummary {
                Table(rows) {
                    TableColumn("Grupo") { Text($0.groupName) }
                    TableColumn("Asist") { Text("\($0.attendancePct)%") }
                    TableColumn("Eval") { Text("\($0.evaluationCompletedPct)%") }
                    TableColumn("Media") { Text(IosFormatting.decimal(from: $0.averageScore)) }
                    TableColumn("Seguim.") { Text("\($0.studentsInFollowUp)") }
                }
                .frame(minHeight: 180)
            } else {
                ForEach(rows) { summary in
                    HStack {
                        Text(summary.groupName).bold()
                        Spacer()
                        Text("As \(summary.attendancePct)% · Ev \(summary.evaluationCompletedPct)%")
                    }
                    .font(.system(size: 13, weight: .medium))
                }
            }
            if snapshot.groupSummaries.isEmpty {
                Text("Sin datos de grupos")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(EvaluationDesign.cardSpacing)
        .background(.regularMaterial)
        .cornerRadius(EvaluationDesign.innerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.06), lineWidth: 1)
        )
        .shadow(color: EvaluationDesign.accent.opacity(colorScheme == .dark ? 0.22 : 0.05), radius: 14, x: 0, y: 8)
    }

    @ViewBuilder
    private func dashboardAgendaBlock(snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Agenda docente")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
            }
            ForEach(snapshot.agendaItems, id: \.id) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text(item.subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(item.timeLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    appMutedCardBackground(for: colorScheme)
                        .overlay(
                            RoundedRectangle(cornerRadius: EvaluationDesign.pillRadius, style: .continuous)
                                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                        )
                )
                .cornerRadius(EvaluationDesign.pillRadius)
            }
            if snapshot.agendaItems.isEmpty {
                Text("Sin agenda para hoy")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(EvaluationDesign.cardSpacing)
        .background(.regularMaterial)
        .cornerRadius(EvaluationDesign.innerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.06), lineWidth: 1)
        )
        .shadow(color: Color.purple.opacity(colorScheme == .dark ? 0.22 : 0.05), radius: 14, x: 0, y: 8)
    }

    @ViewBuilder
    private func dashboardPEBlock(snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Educación Física")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
            }
            ForEach(snapshot.peItems, id: \.id) { item in
                Button {
                    inspectorSelection = .pe(item.id)
                    isInspectorPresented = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Text(item.detail)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(dashboardFilterLabel(item.severity))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(riskTint(item.severity).opacity(0.12), in: Capsule())
                            .foregroundStyle(riskTint(item.severity))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        appMutedCardBackground(for: colorScheme)
                            .overlay(
                                RoundedRectangle(cornerRadius: EvaluationDesign.pillRadius, style: .continuous)
                                    .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                            )
                    )
                    .cornerRadius(EvaluationDesign.pillRadius)
                }
                .buttonStyle(ScaleButtonStyle())
            }
            if snapshot.peItems.isEmpty {
                Text("Sin incidencias EF hoy")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(EvaluationDesign.cardSpacing)
        .background(.regularMaterial)
        .cornerRadius(EvaluationDesign.innerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.06), lineWidth: 1)
        )
        .shadow(color: Color.green.opacity(colorScheme == .dark ? 0.22 : 0.05), radius: 14, x: 0, y: 8)
    }

    private func dashboardFilterPicker(
        title: String,
        selection: Binding<DashboardFilterOption>,
        options: [DashboardFilterOption]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(options) { option in
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        Text(option.title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selection.wrappedValue == option
                                    ? EvaluationDesign.accent
                                    : Color.primary.opacity(0.04)
                            )
                            .foregroundStyle(
                                selection.wrappedValue == option
                                    ? .white
                                    : .primary
                            )
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        selection.wrappedValue == option
                                            ? EvaluationDesign.accent
                                            : Color.primary.opacity(0.06),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
    }

    private func dashboardSessionFilterPicker(
        title: String,
        selection: Binding<DashboardSessionFilterOption>,
        options: [DashboardSessionFilterOption]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(options) { option in
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        Text(option.title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selection.wrappedValue == option
                                    ? EvaluationDesign.accent
                                    : Color.primary.opacity(0.04)
                            )
                            .foregroundStyle(
                                selection.wrappedValue == option
                                    ? .white
                                    : .primary
                            )
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        selection.wrappedValue == option
                                            ? EvaluationDesign.accent
                                            : Color.primary.opacity(0.06),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
    }

    private func dashboardActionRow(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            dashboardRowContent(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func dashboardStaticRow(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        dashboardRowContent(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint)
    }

    private func dashboardRowContent(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            appMutedCardBackground(for: colorScheme)
                .overlay(
                    RoundedRectangle(cornerRadius: EvaluationDesign.pillRadius, style: .continuous)
                        .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                )
        )
        .cornerRadius(EvaluationDesign.pillRadius)
    }

    private func isPendingAlert(_ alert: AlertItem) -> Bool {
        let haystack = "\(alert.type) \(alert.title) \(alert.detail)".lowercased()
        return haystack.contains("pending")
            || haystack.contains("pendiente")
            || haystack.contains("sin nota")
            || haystack.contains("sin cerrar")
            || haystack.contains("informe")
            || haystack.contains("missing")
    }

    private func isClosedAgendaStatus(_ raw: String) -> Bool {
        switch raw.lowercased() {
        case "completed", "closed", "done", "completada", "cerrada":
            return true
        default:
            return false
        }
    }

    private func pendingTitle(_ alert: AlertItem) -> String {
        alert.count > 1 ? "\(alert.count) · \(alert.title)" : alert.title
    }

    private func riskTitle(_ alert: AlertItem) -> String {
        alert.count > 1 ? "\(alert.count) · \(alert.title)" : alert.title
    }

    private func riskIcon(_ alert: AlertItem) -> String {
        let haystack = "\(alert.type) \(alert.title) \(alert.detail)".lowercased()
        if haystack.contains("asistencia") || haystack.contains("attendance") {
            return "person.crop.circle.badge.exclamationmark"
        }
        if haystack.contains("lesion") || haystack.contains("lesión") || haystack.contains("injur") {
            return "cross.case"
        }
        return "chart.line.downtrend.xyaxis"
    }

    private func riskTint(_ raw: String) -> Color {
        switch raw.lowercased() {
        case "high": return .red
        case "medium": return .orange
        default: return .yellow
        }
    }

    private func shortSystemDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Hoy \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func dashboardFilterLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "high": return "Alta"
        case "medium": return "Media"
        case "low": return "Baja"
        default: return raw.isEmpty ? "Sin clasificar" : raw
        }
    }

    private func dashboardSessionStatusLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "planned": return "Planificada"
        case "in_progress": return "En curso"
        case "completed": return "Completada"
        default: return raw.isEmpty ? "Sin estado" : raw
        }
    }

    private func syncToolbarState() {
        layoutState.configureDashboardToolbar(
            inspectorAvailable: bridge.dashboardSnapshot != nil,
            isInspectorPresented: isInspectorPresented,
            actionsAvailable: dashboardActionClassId != nil,
            onToggleInspector: {
                toggleInspector()
            },
            onRefresh: {
                Task { await applyFiltersAndReload() }
            },
            onPassList: {
                Task { await performPassList() }
            },
            onObservation: {
                Task { await performObservation() }
            },
            onQuickEvaluation: {
                isQuickEvaluationPresented = true
            }
        )
    }

    private func scheduleToolbarStateSync() {
        Task { @MainActor in
            syncToolbarState()
        }
    }

    private func scheduleInspectorSelectionSync() {
        Task { @MainActor in
            handleInspectorSelectionChange()
        }
    }

    private func toggleInspector() {
        if !isInspectorPresented, inspectorSelection == nil {
            openInspectorForCurrentSnapshot()
        }
        if inspectorSelection != nil {
            isInspectorPresented.toggle()
        }
    }

    private func openInspectorForCurrentSnapshot() {
        guard let snapshot = bridge.dashboardSnapshot else { return }
        if let firstSession = snapshot.todaySessions.first {
            inspectorSelection = .session(firstSession.id)
        } else if let firstAlert = snapshot.alerts.first {
            inspectorSelection = .alert(firstAlert.id)
        } else if let firstPE = snapshot.peItems.first {
            inspectorSelection = .pe(firstPE.id)
        }
        if inspectorSelection != nil {
            isInspectorPresented = true
        }
    }

    private func performPassList() async {
        guard let classId = dashboardActionClassId else { return }
        await bridge.performQuickAction(
            type: .passList,
            mode: mode.kotlinMode,
            classId: classId,
            attendanceStatus: "presente"
        )
    }

    private func performObservation() async {
        guard let classId = dashboardActionClassId else { return }
        await bridge.performQuickAction(
            type: .registerObservation,
            mode: mode.kotlinMode,
            classId: classId,
            note: "Observación registrada desde dashboard"
        )
    }

    private func performQuickEvaluation() {
        isQuickEvaluationPresented = true
    }

    private func applyFiltersAndReload() async {
        bridge.updateDashboardFilters(
            classId: selectedClassId,
            severity: severityFilter.rawValue,
            priority: priorityFilter.rawValue,
            sessionStatus: sessionStatusFilter.rawValue
        )
        await bridge.refreshDashboard(mode: mode.kotlinMode)
        await loadClassTrends()
    }

    private func csvToday(_ snapshot: DashboardSnapshot) -> String {
        csv("group,time,didactic_unit,space,status", snapshot.todaySessions.map {
            "\($0.groupName),\($0.timeLabel),\($0.didacticUnit),\($0.space),\($0.sessionStatus)"
        })
    }

    private func csvAlerts(_ snapshot: DashboardSnapshot) -> String {
        csv("type,title,detail,severity,priority,count", snapshot.alerts.map {
            "\($0.type),\($0.title),\($0.detail),\($0.severity),\($0.priority),\($0.count)"
        })
    }

    private func csvQuick(_ snapshot: DashboardSnapshot) -> String {
        let rows = snapshot.quickColumns.map { "column,\($0)" } + snapshot.quickRubrics.map { "rubric,\($0)" }
        return csv("kind,value", rows)
    }

    private func csvGroups(_ rows: [DashboardGroupRow]) -> String {
        csv("group,attendance,evaluation,average,follow_up", rows.map {
            "\($0.groupName),\($0.attendancePct),\($0.evaluationCompletedPct),\($0.averageScore),\($0.studentsInFollowUp)"
        })
    }

    private func csvAgenda(_ snapshot: DashboardSnapshot) -> String {
        csv("type,title,subtitle,time,status", snapshot.agendaItems.map {
            "\($0.type),\($0.title),\($0.subtitle),\($0.timeLabel),\($0.status)"
        })
    }

    private func csvPe(_ snapshot: DashboardSnapshot) -> String {
        csv("type,title,detail,severity", snapshot.peItems.map {
            "\($0.type),\($0.title),\($0.detail),\($0.severity)"
        })
    }

    private func csv(_ header: String, _ rows: [String]) -> String {
        ([header] + rows).joined(separator: "\n")
    }

    @ViewBuilder
    private func dashboardLomloeAuditBlock(snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Auditoría LOMLOE y Alertas del Grupo", systemImage: "text.badge.checkmark")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                if isLoadingClassTrends {
                    ProgressView()
                        .tint(NotebookStyle.primaryTint)
                }
            }

            if let trends = classTrends {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        let directionInfo = trendDirectionInfo(trends.trendDirection, delta: trends.averageGradeDelta)
                        Image(systemName: directionInfo.icon)
                            .foregroundStyle(directionInfo.color)
                        Text("Trayectoria: \(directionInfo.label)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(directionInfo.color)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(trendBgColor(trends.trendDirection).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cobertura Curricular del Grupo")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text("\(IosFormatting.decimal(from: trends.curriculumCoveragePct))%")
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundStyle(NotebookStyle.primaryTint)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Asistencia Media")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text("\(IosFormatting.decimal(from: trends.attendanceRate))%")
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundStyle(trends.attendanceRate >= 85 ? Color.primary : Color.orange)
                        }
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(NotebookStyle.softBorder)
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(NotebookStyle.primaryTint)
                                .frame(width: geo.size.width * CGFloat(trends.curriculumCoveragePct / 100.0), height: 8)
                        }
                    }
                    .frame(height: 8)

                    if !trends.attendanceCorrelationNote.isEmpty {
                        Text(trends.attendanceCorrelationNote)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    if !trends.behaviorIncidentSummary.isEmpty {
                        Text(trends.behaviorIncidentSummary)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    if !trends.missingCompetencyLabels.isEmpty {
                        Divider()
                            .background(NotebookStyle.softBorder)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Competencias clave sin evidencias en el grupo:")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            
                            FlexibleTagRow(
                                items: trends.missingCompetencyLabels,
                                selected: ""
                            ) { _ in }
                            .disabled(true)
                        }
                    }
                }
            } else if !isLoadingClassTrends {
                Text("No hay datos suficientes para generar la auditoría de cobertura curricular y tendencias de este grupo.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(EvaluationDesign.cardSpacing)
        .background(.regularMaterial)
        .cornerRadius(EvaluationDesign.innerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.06), lineWidth: 1)
        )
        .shadow(color: EvaluationDesign.accent.opacity(colorScheme == .dark ? 0.22 : 0.05), radius: 14, x: 0, y: 8)
    }

    private func trendDirectionInfo(_ direction: String, delta: Double) -> (icon: String, label: String, color: Color) {
        switch direction {
        case "UPWARD":
            return ("arrow.up.right", "Al alza (+ \(IosFormatting.decimal(from: delta)))", .green)
        case "DOWNWARD":
            return ("arrow.down.right", "A la baja (- \(IosFormatting.decimal(from: abs(delta))))", .red)
        case "STABLE":
            return ("arrow.right", "Estable", .blue)
        default:
            return ("questionmark.circle", "Datos insuficientes", .gray)
        }
    }
    
    private func trendBgColor(_ direction: String) -> Color {
        switch direction {
        case "UPWARD": return .green
        case "DOWNWARD": return .red
        case "STABLE": return .blue
        default: return .gray
        }
    }

    private func loadClassTrends() async {
        guard let classId = selectedClassId else {
            classTrends = nil
            return
        }
        isLoadingClassTrends = true
        do {
            classTrends = try await bridge.getAITrendsAndMetrics(classId: classId, studentId: nil)
        } catch {
            print("Error loading class trends: \(error)")
        }
        isLoadingClassTrends = false
    }
}

private struct DashboardQuickEvaluationSheet: View {
    @ObservedObject var bridge: KmpBridge
    let initialClassId: Int64?
    let mode: DashboardMode
    @Environment(\.dismiss) private var dismiss

    @State private var selectedClassId: Int64?
    @State private var selectedStudentId: Int64?
    @State private var selectedColumnId: String?
    @State private var scoreText = ""
    @State private var note = ""
    @State private var isSaving = false
    @State private var message: String?

    private var notebookColumns: [NotebookColumnDefinition] {
        guard let data = bridge.notebookState as? NotebookUiStateData else { return [] }
        return data.sheet.columns.filter { column in
            column.evaluationId != nil && column.type != .calculated
        }
    }

    private var selectedColumn: NotebookColumnDefinition? {
        notebookColumns.first { $0.id == selectedColumnId }
    }

    private var parsedScore: Double? {
        Double(scoreText.replacingOccurrences(of: ",", with: "."))
    }

    private var canSave: Bool {
        selectedClassId != nil &&
        selectedStudentId != nil &&
        selectedColumn != nil &&
        parsedScore.map { $0 >= 0 && $0 <= 10 } == true &&
        !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Selección") {
                    Picker("Clase", selection: $selectedClassId) {
                        Text("Seleccionar").tag(Int64?.none)
                        ForEach(bridge.classes, id: \.id) { schoolClass in
                            Text("\(schoolClass.name) · \(schoolClass.course)º").tag(Optional(schoolClass.id))
                        }
                    }

                    Picker("Alumno", selection: $selectedStudentId) {
                        Text("Seleccionar").tag(Int64?.none)
                        ForEach(bridge.studentsInClass, id: \.id) { student in
                            Text(student.fullName).tag(Optional(student.id))
                        }
                    }

                    Picker("Columna", selection: $selectedColumnId) {
                        Text("Seleccionar").tag(String?.none)
                        ForEach(notebookColumns, id: \.id) { column in
                            Text(column.title).tag(Optional(column.id))
                        }
                    }
                }

                Section("Nota") {
                    TextField("0-10", text: $scoreText)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                    TextField("Observación opcional", text: $note, axis: .vertical)
                }

                if notebookColumns.isEmpty {
                    Section {
                        Text("No hay columnas de evaluación cargadas para esta clase. Abre o prepara el cuaderno antes de guardar desde el dashboard.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let message {
                    Section {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Evaluación rápida")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Guardando..." : "Confirmar") {
                        Task { await save() }
                    }
                    .disabled(!canSave)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 520)
        .onAppear {
            selectedClassId = initialClassId ?? bridge.classes.first?.id
            loadClassContext()
        }
        .appOnChange(of: selectedClassId) { _ in
            selectedStudentId = nil
            selectedColumnId = nil
            loadClassContext()
        }
    }

    private func loadClassContext() {
        Task { @MainActor in
            guard let selectedClassId else { return }
            bridge.selectClass(id: selectedClassId)
            await bridge.selectStudentsClass(classId: selectedClassId)
            await Task.yield()
            selectedStudentId = selectedStudentId ?? bridge.studentsInClass.first?.id
            selectedColumnId = selectedColumnId ?? notebookColumns.first?.id
        }
    }

    private func save() async {
        guard let classId = selectedClassId,
              let studentId = selectedStudentId,
              let column = selectedColumn,
              let score = parsedScore else { return }
        isSaving = true
        bridge.selectClass(id: classId)
        bridge.saveColumnGrade(studentId: studentId, column: column, value: IosFormatting.decimal(from: score))
        if let evaluationId = column.evaluationId?.int64Value {
            await bridge.performQuickAction(
                type: .quickEvaluation,
                mode: mode,
                classId: classId,
                studentId: studentId,
                evaluationId: evaluationId,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines),
                score: score
            )
        }
        bridge.status = "Evaluación guardada desde dashboard"
        isSaving = false
        dismiss()
    }
}

// MARK: - Premium Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

