import SwiftUI
import MiGestorKit
#if canImport(VisionKit)
import VisionKit
#endif

// MARK: - Main Container
struct ContentView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    
    var body: some View {
        AppWorkspaceShell()
        .tint(.accentColor)
        .overlay(alignment: .bottom) {
            if bridge.rubricEvaluationState.rubricDetail != nil {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { bridge.rubricEvaluationState = RubricEvaluationUiState.companion.default() }
                
                RubricEvaluationView()
                    .frame(height: 650)
                    .appCornerRadius(32, corners: [.topLeft, .topRight])
                    .transition(.move(edge: .bottom))
                    .shadow(radius: 20)
            }
        }
        .animation(uiFeatureFlags.reduceMotion ? .none : .spring(), value: bridge.rubricEvaluationState.rubricDetail != nil)
    }
}

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

struct DashboardView: View {
    @EnvironmentObject var bridge: KmpBridge
    @EnvironmentObject private var layoutState: WorkspaceLayoutState
    @Environment(\.colorScheme) private var colorScheme
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    @Binding var selectedClassId: Int64?
    @AppStorage("dashboard_operational_mode") private var modeRawValue: String = OperationalDashboardMode.office.rawValue
    @State private var severityFilter: String = ""
    @State private var priorityFilter: String = ""
    @State private var sessionStatusFilter: String = ""
    @State private var inspectorSelection: DashboardInspectorSelection? = nil
    @State private var isInspectorPresented = false

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

            if isInspectorPresented {
                inspectorPane
            }
        }
        .background(appPageBackground(for: colorScheme).ignoresSafeArea())
        .task {
            await bridge.ensureClassesLoaded()
            if selectedClassId == nil {
                selectedClassId = bridge.classes.first?.id
            }
            await applyFiltersAndReload()
        }
        .onAppear(perform: syncToolbarState)
        .onChange(of: selectedClassId) { _ in triggerDashboardReload() }
        .onChange(of: modeRawValue) { _ in triggerDashboardReload() }
        .onChange(of: severityFilter) { _ in triggerDashboardReload() }
        .onChange(of: priorityFilter) { _ in triggerDashboardReload() }
        .onChange(of: sessionStatusFilter) { _ in triggerDashboardReload() }
        .onChange(of: inspectorSelection) { _ in handleInspectorSelectionChange() }
        .onChange(of: isInspectorPresented) { _ in syncToolbarState() }
        .onChange(of: toolbarStateKey) { _ in syncToolbarState() }
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
                    Text("Dashboard · \(mode.title)")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                    Text(selectedClassLabel)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Contexto", selection: $modeRawValue) {
                    Text("Clase").tag(OperationalDashboardMode.classroom.rawValue)
                    Text("Despacho").tag(OperationalDashboardMode.office.rawValue)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }

            if isCompactWidth {
                VStack(spacing: 10) {
                    dashboardFilterField(title: "Severidad", placeholder: "high / medium / low", text: $severityFilter)
                    dashboardFilterField(title: "Prioridad", placeholder: "high / medium / low", text: $priorityFilter)
                    dashboardFilterField(title: "Estado sesión", placeholder: "planned / in_progress / completed", text: $sessionStatusFilter)
                }
            } else {
                HStack(spacing: 12) {
                    dashboardFilterField(title: "Severidad", placeholder: "high / medium / low", text: $severityFilter)
                    dashboardFilterField(title: "Prioridad", placeholder: "high / medium / low", text: $priorityFilter)
                    dashboardFilterField(title: "Estado sesión", placeholder: "planned / in_progress / completed", text: $sessionStatusFilter)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(appMutedCardBackground(for: colorScheme))
    }

    private var dashboardContent: some View {
        ScrollView {
            if let snapshot = bridge.dashboardSnapshot {
                VStack(alignment: .leading, spacing: 16) {
                    dashboardKpiRow(snapshot: snapshot)

                    let blocks = mode == .classroom
                        ? ["C", "A", "F", "B", "D", "E"]
                        : ["D", "E", "B", "A", "C", "F"]

                    ForEach(blocks, id: \.self) { block in
                        switch block {
                        case "A":
                            dashboardTodayBlock(snapshot: snapshot)
                        case "B":
                            dashboardAlertsBlock(snapshot: snapshot)
                        case "C":
                            dashboardQuickEvalBlock(snapshot: snapshot)
                        case "D":
                            dashboardGroupSummaryBlock(snapshot: snapshot)
                        case "E":
                            dashboardAgendaBlock(snapshot: snapshot)
                        case "F":
                            dashboardPEBlock(snapshot: snapshot)
                        default:
                            EmptyView()
                        }
                    }
                }
                .padding(16)
            } else {
                ProgressView("Cargando dashboard operativo...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
            }
        }
    }

    private var dashboardInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inspector")
                .font(.title3.bold())
            Text("Estado: \(bridge.status)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let snapshot = bridge.dashboardSnapshot {
                switch inspectorSelection {
                case .session(let id):
                    if let item = snapshot.todaySessions.first(where: { $0.id == id }) {
                        Text(item.groupName).font(.headline)
                        Text(item.didacticUnit)
                        Text("Horario: \(item.timeLabel)")
                        Text("Espacio: \(item.space)")
                        Text("Estado: \(item.sessionStatus)")
                    } else {
                        Text("Sesión no encontrada")
                    }
                case .alert(let id):
                    if let alert = snapshot.alerts.first(where: { $0.id == id }) {
                        Text(alert.title).font(.headline)
                        Text(alert.detail)
                        Text("Severidad: \(alert.severity)")
                        Text("Prioridad: \(alert.priority)")
                    } else {
                        Text("Alerta no encontrada")
                    }
                case .pe(let id):
                    if let item = snapshot.peItems.first(where: { $0.id == id }) {
                        Text(item.title).font(.headline)
                        Text(item.detail)
                        Text("Severidad: \(item.severity)")
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
        return "\(classKey)|\(modeRawValue)|\(severityFilter)|\(priorityFilter)|\(sessionStatusFilter)|\(inspectorKey)|\(isInspectorPresented)"
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
    private func dashboardTodayBlock(snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("A · Hoy").font(.headline)
                Spacer()
                ShareLink("Exportar CSV", item: csvToday(snapshot))
                    .font(.caption)
            }
            ForEach(snapshot.todaySessions, id: \.id) { item in
                Button {
                    inspectorSelection = .session(item.id)
                    isInspectorPresented = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(item.groupName) · \(item.timeLabel)").font(.subheadline.bold())
                            Text(item.didacticUnit).font(.caption)
                            Text("Espacio: \(item.space) · \(item.sessionStatus)").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(appMutedCardBackground(for: colorScheme))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            if snapshot.todaySessions.isEmpty { Text("Sin sesiones hoy").foregroundStyle(.secondary) }
        }
        .padding(12)
        .background(appCardBackground(for: colorScheme))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func dashboardAlertsBlock(snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("B · Alertas").font(.headline)
                Spacer()
                ShareLink("Exportar CSV", item: csvAlerts(snapshot))
                    .font(.caption)
            }
            ForEach(snapshot.alerts.prefix(8), id: \.id) { alert in
                Button {
                    inspectorSelection = .alert(alert.id)
                    isInspectorPresented = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.title).font(.subheadline.bold())
                            Text(alert.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(alert.severity.uppercased()).font(.caption2.bold())
                    }
                    .padding(10)
                    .background(appMutedCardBackground(for: colorScheme))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            if snapshot.alerts.isEmpty { Text("Sin alertas").foregroundStyle(.secondary) }
        }
        .padding(12)
        .background(appCardBackground(for: colorScheme))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func dashboardQuickEvalBlock(snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("C · Evaluación rápida").font(.headline)
                Spacer()
                ShareLink("Exportar CSV", item: csvQuick(snapshot))
                    .font(.caption)
            }
            Text("Columnas: \(snapshot.quickColumns.joined(separator: ", "))").font(.caption)
            Text("Rúbricas: \(snapshot.quickRubrics.joined(separator: ", "))").font(.caption)
            HStack {
                Button("Pasar lista") {
                    Task { await performPassList() }
                }
                Button("Nueva observación") {
                    Task { await performObservation() }
                }
            }
        }
        .padding(12)
        .background(appCardBackground(for: colorScheme))
        .cornerRadius(12)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("D · Resumen por grupo").font(.headline)
                Spacer()
                ShareLink("Exportar CSV", item: csvGroups(rows))
                    .font(.caption)
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
                    .font(.caption)
                }
            }
            if snapshot.groupSummaries.isEmpty { Text("Sin datos de grupos").foregroundStyle(.secondary) }
        }
        .padding(12)
        .background(appCardBackground(for: colorScheme))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func dashboardAgendaBlock(snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("E · Agenda docente").font(.headline)
                Spacer()
                ShareLink("Exportar CSV", item: csvAgenda(snapshot))
                    .font(.caption)
            }
            ForEach(snapshot.agendaItems, id: \.id) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.bold())
                        Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(item.timeLabel).font(.caption2)
                }
                .padding(8)
                .background(appMutedCardBackground(for: colorScheme))
                .cornerRadius(8)
            }
            if snapshot.agendaItems.isEmpty { Text("Sin agenda para hoy").foregroundStyle(.secondary) }
        }
        .padding(12)
        .background(appCardBackground(for: colorScheme))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func dashboardPEBlock(snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("F · Educación Física").font(.headline)
                Spacer()
                ShareLink("Exportar CSV", item: csvPe(snapshot))
                    .font(.caption)
            }
            ForEach(snapshot.peItems, id: \.id) { item in
                Button {
                    inspectorSelection = .pe(item.id)
                    isInspectorPresented = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline.bold())
                            Text(item.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.severity).font(.caption2)
                    }
                    .padding(8)
                    .background(appMutedCardBackground(for: colorScheme))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            if snapshot.peItems.isEmpty { Text("Sin incidencias EF hoy").foregroundStyle(.secondary) }
        }
        .padding(12)
        .background(appCardBackground(for: colorScheme))
        .cornerRadius(12)
    }

    private func dashboardFilterField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                Task { await performQuickEvaluation() }
            }
        )
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

    private func performQuickEvaluation() async {
        guard let classId = dashboardActionClassId else { return }
        let target = await bridge.firstQuickEvaluationTarget(classId: classId)
        guard let studentId = target.studentId, let evaluationId = target.evaluationId else {
            bridge.status = "No hay alumno/evaluación disponible para quick evaluation"
            return
        }
        await bridge.performQuickAction(
            type: .quickEvaluation,
            mode: mode.kotlinMode,
            classId: classId,
            studentId: studentId,
            evaluationId: evaluationId,
            score: 7.0
        )
    }

    private func applyFiltersAndReload() async {
        bridge.updateDashboardFilters(
            classId: selectedClassId,
            severity: severityFilter,
            priority: priorityFilter,
            sessionStatus: sessionStatusFilter
        )
        await bridge.refreshDashboard(mode: mode.kotlinMode)
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
}
struct SettingsModuleView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appleCommandCenterState) private var commandCenterState
    @AppStorage("theme_mode") private var themeModeRawValue: String = AppThemeMode.system.rawValue
    @Binding var selectedClassId: Int64?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Ajustes")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .padding(.top, 8)

#if os(macOS)
                if commandCenterState.isAvailable {
                    MacCommandCenterPairingCard(commandCenterState: commandCenterState)
                }
#else
                SyncLanCard()
#endif

                VStack(alignment: .leading, spacing: 8) {
                    Text("Apariencia")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                    Picker("Tema", selection: $themeModeRawValue) {
                        ForEach(AppThemeMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(16)
                .background(appCardBackground(for: colorScheme))
                .cornerRadius(16)

                TeacherScheduleSettingsPanel(selectedClassId: $selectedClassId)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(appPageBackground(for: colorScheme).ignoresSafeArea())
        .refreshable {
            await bridge.pullMissingSyncChanges()
        }
    }
}

#if os(macOS)
fileprivate struct MacCommandCenterPairingCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let commandCenterState: AppleCommandCenterState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Enlazar iPhone o iPad")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                Text(headlineText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 24) {
                Group {
                    if commandCenterState.serviceState.showsPairingCode,
                       let payload = commandCenterState.pairingPayload,
                       !payload.isEmpty {
                        QRCodeView(payload: payload, size: 176, padding: 16)
                    } else {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.quaternary)
                            .frame(width: 208, height: 208)
                            .overlay {
                                VStack(spacing: 8) {
                                    Image(systemName: placeholderSymbol)
                                        .font(.system(size: 30, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                    Text(placeholderText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    statusBadge

                    if let host = commandCenterState.pairingHost,
                       commandCenterState.serviceState.showsPairingCode {
                        commandMetric(title: "Host", value: host)
                    }
                    if let port = commandCenterState.pairingPort,
                       commandCenterState.serviceState.showsPairingCode {
                        commandMetric(title: "Puerto", value: "\(port)")
                    }
                    if let pin = commandCenterState.pairingPin,
                       commandCenterState.serviceState.showsPairingCode {
                        commandMetric(title: "PIN", value: pin)
                    }
                    if let payload = commandCenterState.pairingPayload,
                       !payload.isEmpty,
                       commandCenterState.serviceState.showsPairingCode {
                        commandMetric(title: "Payload", value: payload)
                    }
                    Text(commandCenterState.statusMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button(primaryActionTitle) {
                            NotificationCenter.default.post(
                                name: primaryActionNotification,
                                object: nil
                            )
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Regenerar PIN") {
                            NotificationCenter.default.post(
                                name: .appleCommandCenterRegeneratePinRequested,
                                object: nil
                            )
                        }
                        .buttonStyle(.bordered)
                        .disabled(commandCenterState.serviceState == .starting)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .background(appCardBackground(for: colorScheme))
        .cornerRadius(24)
    }

    @ViewBuilder
    private func commandMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    private var headlineText: String {
        switch commandCenterState.serviceState {
        case .stopped:
            return "La sincronización LAN no está activa en este Mac."
        case .starting:
            return "Arrancando servicio de enlace en la red local."
        case .running:
            return "Escanea este QR desde el iPad para enlazar."
        case .networkError:
            return "Error de red local. Revisa la red de este Mac antes de enlazar."
        case .connected:
            return "iPad conectado a este Mac. Puedes volver a escanear el QR si necesitas reconectar."
        case .failed:
            return "No se pudo preparar el servicio de enlace en este Mac."
        }
    }

    private var placeholderText: String {
        switch commandCenterState.serviceState {
        case .starting:
            return "Arrancando servicio"
        case .networkError:
            return "Error de red local"
        case .failed:
            return "Servicio no disponible"
        case .connected, .running, .stopped:
            return "Sin código disponible"
        }
    }

    private var placeholderSymbol: String {
        switch commandCenterState.serviceState {
        case .networkError, .failed:
            return "wifi.exclamationmark"
        case .starting:
            return "bolt.horizontal.circle"
        case .connected, .running, .stopped:
            return "qrcode"
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        Text(badgeText)
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(badgeColor.opacity(0.16), in: Capsule())
            .foregroundStyle(badgeColor)
    }

    private var badgeText: String {
        switch commandCenterState.serviceState {
        case .stopped:
            return "Servicio detenido"
        case .starting:
            return "Arrancando servicio"
        case .running:
            return "Listo para enlazar"
        case .networkError:
            return "Error de red local"
        case .connected:
            return "Conectado a iPad"
        case .failed:
            return "Servicio no disponible"
        }
    }

    private var badgeColor: Color {
        switch commandCenterState.serviceState {
        case .running, .connected:
            return .green
        case .starting:
            return .orange
        case .networkError, .failed:
            return .red
        case .stopped:
            return .secondary
        }
    }

    private var primaryActionTitle: String {
        switch commandCenterState.serviceState {
        case .stopped, .failed:
            return "Activar enlace"
        case .starting, .running, .networkError, .connected:
            return "Detener enlace"
        }
    }

    private var primaryActionNotification: Notification.Name {
        switch commandCenterState.serviceState {
        case .stopped, .failed:
            return .appleCommandCenterStartRequested
        case .starting, .running, .networkError, .connected:
            return .appleCommandCenterStopRequested
        }
    }
}
#endif

fileprivate struct SyncLanCard: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedHost: String = ""
    @State private var selectedPort: String = "8765"
    @State private var pin: String = ""
    @State private var showingQrScanner = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Sincronización LAN", systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text(bridge.syncStatusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if bridge.pairedSyncHost != nil {
                HStack(spacing: 10) {
                    Text("Vinculado con \(bridge.pairedSyncHost ?? "-")")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Desvincular") {
                        Task {
                            await bridge.unpairLanSync()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                HStack(spacing: 10) {
                    TextField("Host desktop (ej. migestor.local)", text: $selectedHost)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Puerto", text: $selectedPort)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 80)
                    TextField("PIN", text: $pin)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 90)
                    Button {
                        showingQrScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    .buttonStyle(.bordered)
                    Button("Emparejar") {
                        Task {
                            let normalizedHost = selectedHost.trimmingCharacters(in: .whitespacesAndNewlines)
                            let normalizedPin = pin.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !normalizedHost.isEmpty else {
                                bridge.syncStatusMessage = "Introduce un host LAN válido del Mac."
                                return
                            }
                            guard let port = Int(selectedPort), (1...65535).contains(port) else {
                                bridge.syncStatusMessage = "El puerto de enlace no es válido."
                                return
                            }
                            guard port == 8765 else {
                                bridge.syncStatusMessage = "Esta compilación del iPad usa el puerto 8765 para enlazar con el Mac."
                                return
                            }
                            guard !normalizedPin.isEmpty else {
                                bridge.syncStatusMessage = "Introduce el PIN de enlace."
                                return
                            }

                            do {
                                let hostToUse = normalizedHost.isEmpty ? bridge.discoveredSyncHosts.first ?? "" : normalizedHost
                                let peer = bridge.discoveredPeer(forHost: hostToUse)
                                try await bridge.pairLanSync(
                                    host: hostToUse,
                                    pin: normalizedPin,
                                    expectedServerId: peer?.serverId,
                                    expectedFingerprint: peer?.fingerprint
                                )
                                selectedHost = hostToUse
                            } catch {
                                bridge.syncStatusMessage = "Error emparejando: \(error.localizedDescription)"
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAttemptPairing)
                }
            }

            if !bridge.discoveredSyncHosts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(bridge.discoveredSyncHosts, id: \.self) { host in
                            Button(host) { selectedHost = host }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Pull") {
                    Task {
                        do {
                            try await bridge.runLanPullSync()
                        } catch {
                            bridge.syncStatusMessage = "Error pull: \(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(bridge.pairedSyncHost == nil)

                Button("Push") {
                    Task {
                        do {
                            try await bridge.runLanPushSync()
                        } catch {
                            bridge.syncStatusMessage = "Error push: \(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(bridge.pairedSyncHost == nil)

                Spacer()
                Text("Pendientes: \(bridge.syncPendingChanges)")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(16)
        .background(appCardBackground(for: colorScheme))
        .cornerRadius(20)
        .sheet(isPresented: $showingQrScanner) {
            LanQrScannerSheet { payload in
                guard let parsed = parseSyncPayload(payload) else {
                    bridge.syncStatusMessage = "QR no válido para sincronización"
                    return
                }
                selectedHost = parsed.host
                selectedPort = "\(parsed.port)"
                pin = parsed.pin
                Task {
                    do {
                        guard parsed.port == 8765 else {
                            bridge.syncStatusMessage = "Este QR usa un puerto no compatible con esta compilación del iPad."
                            return
                        }
                        try await bridge.pairLanSync(
                            host: parsed.host,
                            pin: parsed.pin,
                            expectedServerId: parsed.serverId,
                            expectedFingerprint: parsed.fingerprint
                        )
                    } catch {
                        bridge.syncStatusMessage = "Error emparejando: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private var canAttemptPairing: Bool {
        let normalizedHost = selectedHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPin = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty,
              let port = Int(selectedPort),
              (1...65535).contains(port),
              !normalizedPin.isEmpty else {
            return false
        }
        return true
    }

    private func parseSyncPayload(_ payload: String) -> (host: String, port: Int, pin: String, serverId: String?, fingerprint: String?)? {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }

        if let components = URLComponents(string: text),
           let queryItems = components.queryItems,
           let host = queryItems.first(where: { $0.name.lowercased() == "host" })?.value,
           let portValue = queryItems.first(where: { $0.name.lowercased() == "port" })?.value,
           let port = Int(portValue),
           let pin = queryItems.first(where: { $0.name.lowercased() == "pin" })?.value,
           !host.isEmpty, !pin.isEmpty, (1...65535).contains(port) {
            let sid = queryItems.first(where: { $0.name.lowercased() == "sid" })?.value
            let fp = queryItems.first(where: { $0.name.lowercased() == "fp" })?.value
            return (host, port, pin, sid, fp)
        }

        if text.hasPrefix("{"),
           let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let host = object["host"] as? String,
           let port = (object["port"] as? Int) ?? ((object["port"] as? String).flatMap(Int.init)),
           let pin = object["pin"] as? String,
           !host.isEmpty, !pin.isEmpty, (1...65535).contains(port) {
            return (host, port, pin, object["sid"] as? String, object["fp"] as? String)
        }

        if text.contains("host="), text.contains("port="), text.contains("pin=") {
            let normalized = text.replacingOccurrences(of: " ", with: "&")
            if let components = URLComponents(string: "migestor://sync?\(normalized)"),
               let queryItems = components.queryItems,
               let host = queryItems.first(where: { $0.name.lowercased() == "host" })?.value,
               let portValue = queryItems.first(where: { $0.name.lowercased() == "port" })?.value,
               let port = Int(portValue),
               let pin = queryItems.first(where: { $0.name.lowercased() == "pin" })?.value {
                let sid = queryItems.first(where: { $0.name.lowercased() == "sid" })?.value
                let fp = queryItems.first(where: { $0.name.lowercased() == "fp" })?.value
                if !host.isEmpty, !pin.isEmpty, (1...65535).contains(port) {
                    return (host, port, pin, sid, fp)
                }
            }
        }

        return nil
    }
}

struct LanQrScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPayload: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
#if os(iOS) && canImport(VisionKit)
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    LanQrScannerView { payload in
                        onPayload(payload)
                        dismiss()
                    }
                } else {
                    Text("El escáner QR no está disponible en este dispositivo.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
#else
                Text("El escáner QR no está disponible en esta compilación.")
                    .foregroundStyle(.secondary)
                    .padding()
#endif
            }
            .navigationTitle("Escanear QR")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}

#if os(iOS) && canImport(VisionKit)
struct LanQrScannerView: UIViewControllerRepresentable {
    let onFoundCode: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFoundCode: onFoundCode)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .accurate,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onFoundCode: (String) -> Void
        private var didHandleCode = false

        init(onFoundCode: @escaping (String) -> Void) {
            self.onFoundCode = onFoundCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didHandleCode else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let payload = barcode.payloadStringValue,
                   !payload.isEmpty {
                    didHandleCode = true
                    onFoundCode(payload)
                    return
                }
            }
        }
    }
}
#endif

fileprivate struct UpcomingClassItem: View {
    let event: CalendarEvent
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        HStack(spacing: 16) {
            Circle().fill(Color.accentColor.opacity(0.1)).frame(width: 48, height: 48).overlay(Image(systemName: "book.pages").foregroundColor(.accentColor))
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.system(size: 16, weight: .bold))
                Text(event.description_ ?? "Aula General").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text(formatTime(event.startAt)).font(.system(size: 14, weight: .black, design: .monospaced)).padding(.horizontal, 12).padding(.vertical, 6).background(Color.accentColor.opacity(0.05)).cornerRadius(10)
        }
        .padding(16).background(appCardBackground(for: colorScheme)).cornerRadius(20).shadow(color: Color.black.opacity(0.02), radius: 10, x: 0, y: 5)
    }
    private func formatTime(_ instant: Instant) -> String {
        let date = Date(timeIntervalSince1970: Double(instant.epochSeconds))
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

fileprivate struct TaskItem: View {
    let incident: Incident
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.15)).frame(width: 40, height: 40).overlay(Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.system(size: 14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(incident.title).font(.system(size: 14, weight: .bold)).lineLimit(1)
                Text(incident.detail ?? "").font(.system(size: 12)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
        }.padding(12).background(appCardBackground(for: colorScheme)).cornerRadius(18)
    }
}

fileprivate struct DistributionRow: View {
    let label: String; let percentage: Int; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(label).font(.system(size: 12, weight: .bold)); Spacer(); Text("\(percentage)%").font(.system(size: 12, weight: .black)).foregroundColor(color) }
            GeometryReader { geo in ZStack(alignment: .leading) { Capsule().fill(color.opacity(0.1)); Capsule().fill(color).frame(width: geo.size.width * CGFloat(percentage) / 100) } }.frame(height: 6)
        }
    }
}

// Notebook components moved to separate files:
// - NotebookModuleView.swift
// - NotebookDataGrid.swift
// - NotebookTopBar.swift

// MARK: - Column Editor
struct WeightEditorSheet: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.dismiss) var dismiss
    let column: NotebookColumnDefinition
    @State private var weight: String
    @State private var width: String
    @State private var order: String
    @State private var colorHex: String
    @State private var selectedTabIds: Set<String>

    private let palette: [String] = ["#4A90D9", "#2D9CDB", "#27AE60", "#F2994A", "#EB5757", "#9B51E0", "#111827", "#F4B400"]

    init(column: NotebookColumnDefinition) {
        self.column = column
        _weight = State(initialValue: String(format: "%.1f", column.weight))
        _width = State(initialValue: String(format: "%.0f", column.widthDp > 0 ? column.widthDp : 132.0))
        _order = State(initialValue: String(column.order >= 0 ? column.order : 0))
        _colorHex = State(initialValue: column.colorHex ?? "#4A90D9")
        _selectedTabIds = State(initialValue: Set(column.tabIds))
    }

    var body: some View {
        let accentText = contrastingTextColor(for: colorHex)

        NavigationStack {
            ZStack {
                EvaluationBackdrop()

                ScrollView {
                    VStack(spacing: NotebookStyle.sectionSpacing) {
                        VStack(spacing: NotebookStyle.stackSpacing) {
                            ZStack {
                                RoundedRectangle(cornerRadius: NotebookStyle.cardRadius, style: .continuous)
                                    .fill(Color(hex: colorHex).opacity(0.14))
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 32, weight: .regular))
                                    .foregroundColor(accentText)
                            }
                            .frame(width: 80, height: 80)
                            Text(column.title)
                                .font(.system(size: 28, weight: .black, design: .rounded))
                            Text("Ajusta peso, ancho, orden, color y pestañas asociadas de esta columna.")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .padding(.top, 40)

                        columnTabsSection

                        settingCard(title: "Peso (%)") {
                            TextField("0.0", text: $weight)
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .appKeyboardType(.decimalPad)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 16)
                        }

                        settingCard(title: "Ancho (dp)") {
                            VStack(alignment: .leading, spacing: NotebookStyle.controlSpacing) {
                                Slider(value: Binding(
                                    get: { Double(width.replacingOccurrences(of: ",", with: ".")) ?? 132.0 },
                                    set: { width = String(format: "%.0f", $0) }
                                ), in: 96...260, step: 8)
                                Text(width + " dp")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }

                        settingCard(title: "Orden") {
                            TextField("0", text: $order)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .appKeyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 16)
                        }

                        settingCard(title: "Color") {
                            FlowLayout(spacing: NotebookStyle.controlSpacing) {
                                ForEach(palette, id: \.self) { hex in
                                    Button {
                                        colorHex = hex
                                    } label: {
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 32, height: 32)
                                            .overlay(
                                                Circle().stroke(colorHex == hex ? Color.primary : Color.clear, lineWidth: 3)
                                            )
                                    }
                                }
                            }
                        }

                        Button(action: saveWeight) {
                            Text("Actualizar columna")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(accentText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color(hex: colorHex))
                                .clipShape(RoundedRectangle(cornerRadius: NotebookStyle.innerRadius, style: .continuous))
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                }
            }
            .appInlineNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Hecho") { saveWeight() }.fontWeight(.bold) }
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancelar") { dismiss() } }
            }
        }
    }
    private func saveWeight() {
        let weightValue = Double(weight.replacingOccurrences(of: ",", with: ".")) ?? column.weight
        let widthValue = Double(width.replacingOccurrences(of: ",", with: ".")) ?? (column.widthDp > 0 ? column.widthDp : 132.0)
        let orderValue = Int32(order.trimmingCharacters(in: .whitespacesAndNewlines)) ?? column.order
        let updated = NotebookColumnDefinition(
            id: column.id,
            title: column.title,
            type: column.type,
            categoryKind: column.categoryKind,
            instrumentKind: column.instrumentKind,
            inputKind: column.inputKind,
            evaluationId: column.evaluationId,
            rubricId: column.rubricId,
            formula: column.formula,
            weight: weightValue,
            dateEpochMs: column.dateEpochMs,
            unitOrSituation: column.unitOrSituation,
            competencyCriteriaIds: column.competencyCriteriaIds,
            scaleKind: column.scaleKind,
            tabIds: selectedTabIds.isEmpty ? column.tabIds : Array(selectedTabIds).sorted(),
            sessions: column.sessions,
            sharedAcrossTabs: selectedTabIds.count > 1,
            colorHex: colorHex,
            iconName: column.iconName,
            order: orderValue,
            widthDp: widthValue,
            categoryId: column.categoryId,
            ordinalLevels: column.ordinalLevels,
            availableIcons: column.availableIcons,
            countsTowardAverage: column.countsTowardAverage,
            isPinned: column.isPinned,
            isHidden: column.isHidden,
            visibility: column.visibility,
            isLocked: column.isLocked,
            isTemplate: column.isTemplate,
            trace: column.trace
        )
        bridge.saveColumn(column: updated)
        dismiss()
    }

    @ViewBuilder
    private var columnTabsSection: some View {
        if let data = bridge.notebookState as? NotebookUiStateData, !data.sheet.tabs.isEmpty {
            settingCard(title: "Pestañas") {
                FlowLayout(spacing: NotebookStyle.controlSpacing) {
                    ForEach(data.sheet.tabs, id: \.id) { tab in
                        let isSelected = selectedTabIds.contains(tab.id)
                        Button {
                            if isSelected {
                                selectedTabIds.remove(tab.id)
                            } else {
                                selectedTabIds.insert(tab.id)
                            }
                        } label: {
                            NotebookPill(
                                label: tab.title,
                                active: isSelected,
                                tint: NotebookStyle.primaryTint,
                                compact: true
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func settingCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        NotebookSurface(cornerRadius: NotebookStyle.cardRadius, fill: NotebookStyle.surface, padding: NotebookStyle.stackSpacing) {
            VStack(alignment: .leading, spacing: NotebookStyle.controlSpacing) {
                NotebookSectionLabel(text: title)
                content()
            }
        }
        .padding(.horizontal, 24)
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleaned.count {
        case 3:
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        default:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        }
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

// MARK: - Rubrics Module
struct RubricsModuleView: View {
    var body: some View {
        RubricsScreen()
    }
}

struct RubricDetailView: View {
    let rubric: RubricDetail
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) { 
                    Text(rubric.rubric.name).font(.system(size: 28, weight: .black, design: .rounded))
                    Text("Detalles de la evaluación formativa").font(.subheadline).foregroundColor(.secondary) 
                }.padding(.horizontal, 24)
                
                ForEach(rubric.criteria, id: \.criterion.id) { item in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(item.criterion.description_).font(.system(size: 14, weight: .bold)).foregroundColor(.secondary).padding(.horizontal, 24)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(item.levels, id: \.id) { level in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(level.name).font(.system(size: 14, weight: .bold))
                                        Text(level.description_ ?? "").font(.system(size: 12)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                                        Spacer(); Text("\(level.points) pts").font(.system(size: 12, weight: .black)).foregroundColor(.orange)
                                    }
                                    .padding(16)
                                    .frame(width: 160, height: 140)
                                    .background(appCardBackground(for: colorScheme))
                                    .cornerRadius(18)
                                    .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
                                }
                            }.padding(.horizontal, 24)
                        }
                    }
                }
            }.padding(.vertical, 24)
        }
        .background(appPageBackground(for: colorScheme))
        .appInlineNavigationBarTitleDisplayMode()
    }
}

struct RubricEvaluationView: View {
    @EnvironmentObject var bridge: KmpBridge

    private var state: RubricEvaluationUiState {
        bridge.rubricEvaluationState
    }

    var body: some View {
        NavigationStack {
            ZStack {
                EvaluationBackdrop()

                if let rubric = state.rubricDetail {
                    GeometryReader { proxy in
                        let isWide = proxy.size.width >= 960
                        let selectedScore = rubric.calculateScore(selectedLevelIds: state.selectedLevels)

                        ScrollView {
                            VStack(alignment: .leading, spacing: EvaluationDesign.sectionSpacing) {
                                headerSection(rubric: rubric, score: selectedScore)

                                if isWide {
                                    HStack(alignment: .top, spacing: EvaluationDesign.sectionSpacing) {
                                        criteriaPanel(rubric: rubric)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        summaryPanel(rubric: rubric, score: selectedScore)
                                            .frame(width: 300)
                                    }
                                } else {
                                    VStack(spacing: EvaluationDesign.sectionSpacing) {
                                        criteriaPanel(rubric: rubric)
                                        summaryPanel(rubric: rubric, score: selectedScore)
                                    }
                                }
                            }
                            .padding(EvaluationDesign.screenPadding)
                        }
                    }
                    .onChange(of: state.isSaveSuccessful) { saved in
                        guard saved else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            closeRubric()
                        }
                    }
                } else {
                    ProgressView("Cargando rúbrica...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func headerSection(rubric: RubricDetail, score: Double) -> some View {
        HStack(alignment: .top, spacing: 16) {
            EvaluationIconButton(systemImage: "chevron.down", tint: .primary) {
                closeRubric()
            }

            EvaluationAvatar(initials: String(state.studentName.prefix(2)))

            VStack(alignment: .leading, spacing: 6) {
                Text("Evaluación individual")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)

                Text(state.studentName)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)

                Text(rubric.rubric.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 12) {
                EvaluationScoreBadge(
                    title: "Nota actual",
                    value: IosFormatting.scoreOutOfTen(from: score)
                )

                EvaluationPrimaryButton(label: "Guardar evaluación", systemImage: "square.and.arrow.down.fill") {
                    bridge.saveRubricEvaluation(
                        manual: true,
                        onSuccess: {
                            bridge.refreshCurrentNotebook()
                            closeRubric()
                        }
                    )
                }
                .frame(width: 220)
            }
        }
    }

    private func criteriaPanel(rubric: RubricDetail) -> some View {
        EvaluationGlassCard(cornerRadius: 32, fillOpacity: 0.88) {
            VStack(alignment: .leading, spacing: EvaluationDesign.sectionSpacing) {
                HStack(spacing: 12) {
                    EvaluationChip(
                        label: "\(rubric.criteria.count) criterios",
                        systemImage: "checklist",
                        tint: EvaluationDesign.accent
                    )

                    EvaluationChip(
                        label: "Selecciona el nivel",
                        systemImage: "hand.tap.fill",
                        tint: EvaluationDesign.accent
                    )
                }

                VStack(spacing: 16) {
                    ForEach(rubric.criteria, id: \.criterion.id) { criterion in
                        RubricCriterionRow(
                            item: criterion,
                            selectedLevelId: state.selectedLevels[KotlinLong(value: criterion.criterion.id)]?.int64Value,
                            onSelectLevel: { levelId in
                                bridge.rubricEvaluationViewModel.selectLevel(
                                    criterionId: criterion.criterion.id,
                                    levelId: levelId
                                )
                            }
                        )
                    }
                }
            }
        }
    }

    private func summaryPanel(rubric: RubricDetail, score: Double) -> some View {
        EvaluationGlassCard(cornerRadius: 32, fillOpacity: 0.92) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    EvaluationChip(
                        label: "Resumen",
                        systemImage: "sparkles",
                        tint: EvaluationDesign.accent
                    )
                    Spacer()
                    Text(IosFormatting.decimal(from: score))
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(EvaluationDesign.accent)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Progreso")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text("\(state.selectedLevels.count) de \(rubric.criteria.count) criterios resueltos")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    ProgressView(value: Double(state.selectedLevels.count), total: Double(max(rubric.criteria.count, 1)))
                        .tint(EvaluationDesign.accent)
                }

                EvaluationDivider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Siguiente paso")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text("Revisa cada criterio y guarda cuando la rúbrica quede completa.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func closeRubric() {
        bridge.rubricEvaluationState = RubricEvaluationUiState.companion.default()
    }
}

struct RubricCriterionRow: View {
    let item: RubricCriterionWithLevels
    let selectedLevelId: Int64?
    let onSelectLevel: (Int64) -> Void

    var body: some View {
        EvaluationGlassCard(cornerRadius: 24, fillOpacity: 0.96) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.criterion.description_)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Elige el nivel que mejor describe el desempeño")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(item.levels, id: \.id) { level in
                            let isSelected = selectedLevelId == level.id

                            EvaluationLevelTile(
                                title: level.name,
                                subtitle: level.description_ ?? "",
                                isSelected: isSelected,
                                tint: EvaluationDesign.accent
                            ) {
                                onSelectLevel(level.id)
                            }
                            .frame(width: 160)
                            .overlay(alignment: .bottomTrailing) {
                                Text("\(Int(level.points)) pts")
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .foregroundStyle(isSelected ? .white : EvaluationDesign.accent)
                                    .padding(.trailing, 12)
                                    .padding(.bottom, 10)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Students Module
struct StudentsModuleView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    @State private var className = ""
    @State private var classCourse = "3"
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var search = ""

    private var filteredStudents: [Student] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return bridge.studentsInClass }
        return bridge.studentsInClass.filter {
            "\($0.firstName) \($0.lastName)".localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Alumnos")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Clase activa")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                    Picker("Clase", selection: Binding(
                        get: { bridge.selectedStudentsClassId ?? -1 },
                        set: { value in
                            Task { await bridge.selectStudentsClass(classId: value > 0 ? value : nil) }
                        }
                    )) {
                        ForEach(bridge.classes, id: \.id) { schoolClass in
                            Text(schoolClass.name).tag(schoolClass.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(14)
                .background(appCardBackground(for: colorScheme))
                .cornerRadius(16)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Crear clase")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("Nombre de clase", text: $className)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Curso (1-6)", text: $classCourse)
                        .appKeyboardType(.numberPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("Guardar clase") {
                        Task {
                            guard let course = Int32(classCourse), !className.isEmpty else { return }
                            do {
                                _ = try await bridge.createClass(name: className, course: course)
                                className = ""
                            } catch {
                                bridge.status = "Error creando clase: \(error.localizedDescription)"
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(14)
                .background(appCardBackground(for: colorScheme))
                .cornerRadius(16)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Alta de alumno")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("Nombre", text: $firstName).textFieldStyle(RoundedBorderTextFieldStyle())
                        TextField("Apellido", text: $lastName).textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    Button("Añadir a clase") {
                        Task {
                            guard !firstName.isEmpty, !lastName.isEmpty else { return }
                            do {
                                try await bridge.createStudentInSelectedClass(firstName: firstName, lastName: lastName)
                                firstName = ""
                                lastName = ""
                            } catch {
                                bridge.status = "Error creando alumno: \(error.localizedDescription)"
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(14)
                .background(appCardBackground(for: colorScheme))
                .cornerRadius(16)

                TextField("Buscar alumno...", text: $search)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                VStack(spacing: 10) {
                    ForEach(filteredStudents, id: \.id) { student in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(student.firstName) \(student.lastName)")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("ID \(student.id)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu {
                                Button("Quitar de la clase") {
                                    Task { try? await bridge.removeStudentFromSelectedClass(studentId: student.id) }
                                }
                                Button("Eliminar definitivamente", role: .destructive) {
                                    Task { try? await bridge.deleteStudentEverywhere(studentId: student.id) }
                                }
                            } label: {
                                Label("Acciones", systemImage: "ellipsis.circle")
                                    .labelStyle(.iconOnly)
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(12)
                        .background(appCardBackground(for: colorScheme))
                        .cornerRadius(14)
                    }
                    if filteredStudents.isEmpty {
                        Text("No hay alumnos en la clase seleccionada.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(appPageBackground(for: colorScheme).ignoresSafeArea())
        .task {
            try? await bridge.refreshStudentsDirectory()
        }
        .refreshable {
            await bridge.pullMissingSyncChanges()
            try? await bridge.refreshStudentsDirectory()
        }
    }
}

// MARK: - Planning Module
struct PlanningModuleView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    @State private var periodName = ""
    @State private var unitTitle = ""
    @State private var sessionDescription = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Planificación")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Nueva sesión")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                    TextField("Semana/Periodo", text: $periodName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Unidad didáctica", text: $unitTitle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Descripción de sesión", text: $sessionDescription, axis: .vertical)
                        .lineLimit(3...5)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("Guardar sesión") {
                        Task {
                            guard !unitTitle.isEmpty, !sessionDescription.isEmpty else { return }
                            do {
                                try await bridge.createPlanning(
                                    periodName: periodName.isEmpty ? "Semana actual" : periodName,
                                    unitTitle: unitTitle,
                                    sessionDescription: sessionDescription
                                )
                                unitTitle = ""
                                sessionDescription = ""
                            } catch {
                                bridge.status = "Error planificación: \(error.localizedDescription)"
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(14)
                .background(appCardBackground(for: colorScheme))
                .cornerRadius(16)

                ForEach(bridge.planning, id: \.period.id) { period in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(period.period.name)
                            .font(.system(size: 18, weight: .bold))
                        ForEach(period.units, id: \.unit.id) { unit in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(unit.unit.title)
                                    .font(.system(size: 15, weight: .semibold))
                                ForEach(unit.sessions, id: \.id) { session in
                                    Text("• \(session.description_)")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(.secondary)
                                }
                                if unit.sessions.isEmpty {
                                    Text("Sin sesiones en esta unidad")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .background(appCardBackground(for: colorScheme))
                            .cornerRadius(14)
                        }
                    }
                }

                if bridge.planning.isEmpty {
                    Text("No hay planificación para la semana actual.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(appPageBackground(for: colorScheme).ignoresSafeArea())
        .task { try? await bridge.refreshPlanning() }
        .refreshable {
            await bridge.pullMissingSyncChanges()
            try? await bridge.refreshPlanning()
        }
    }
}

// MARK: - Identifiable Conformances
extension RubricDetail: @retroactive Identifiable { public var id: Int64 { self.rubric.id } }
extension RubricLevel: @retroactive Identifiable {}

// MARK: - Helpers & Styles
// Helpers moved to specific component files where appropriate

// MARK: - Organic Precision Rubrics Screen


struct RubricsScreen: View {
    @EnvironmentObject var bridge: KmpBridge
    @State private var selectedFilterClassId: Int64? = nil
    @State private var searchText = ""
    @State private var showingBuilder = false
    @State private var deletingRubric: RubricDetail? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 520), spacing: 16)
    ]

    private var filteredRubrics: [RubricDetail] {
        let byClass: [RubricDetail]
        if let classId = selectedFilterClassId {
            byClass = bridge.rubrics.filter { detail in
                let linkedClasses = bridge.rubricClassLinks[detail.rubric.id] ?? []
                return linkedClasses.contains(classId)
            }
        } else {
            byClass = bridge.rubrics
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let byText = query.isEmpty ? byClass : byClass.filter { detail in
            detail.rubric.name.localizedCaseInsensitiveContains(query) ||
            detail.criteria.contains(where: { $0.criterion.description_.localizedCaseInsensitiveContains(query) })
        }

        return byText.sorted {
            if $0.criteria.count == $1.criteria.count {
                return $0.rubric.name.localizedCaseInsensitiveCompare($1.rubric.name) == .orderedAscending
            }
            return $0.criteria.count > $1.criteria.count
        }
    }

    var body: some View {
        ZStack {
            MeshBackgroundView()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                RubricsHeaderView()
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(
                            label: "Todas",
                            isSelected: selectedFilterClassId == nil,
                            action: {
                                selectedFilterClassId = nil
                                bridge.setRubricFilterClass(nil)
                            }
                        )

                        ForEach(bridge.classes, id: \.id) { schoolClass in
                            FilterChip(
                                label: schoolClass.name,
                                isSelected: selectedFilterClassId == schoolClass.id,
                                action: {
                                    selectedFilterClassId = schoolClass.id
                                    bridge.setRubricFilterClass(schoolClass.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                }

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white.opacity(0.65))
                    TextField("Buscar rúbrica, criterio o uso…", text: $searchText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.white.opacity(0.08), in: Capsule())
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

                if filteredRubrics.isEmpty {
                    RubricsEmptyStateView {
                        bridge.resetRubricBuilder()
                        showingBuilder = true
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(filteredRubrics, id: \.rubric.id) { rubric in
                                RubricBankCard(
                                    rubric: rubric,
                                    onAssign: { bridge.startAssignRubric(rubric.rubric) },
                                    onEdit: {
                                        bridge.loadRubricForEditing(rubric)
                                        showingBuilder = true
                                    },
                                    onDelete: { deletingRubric = rubric }
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .padding(.bottom, 100)
                    }
                }
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    LiquidGlassFab(label: "Nueva Rúbrica", icon: "plus") {
                        bridge.resetRubricBuilder()
                        showingBuilder = true
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 32)
                }
            }
        }
        .appFullScreenCover(isPresented: $showingBuilder) {
            RubricsBuilderScreen()
                .environmentObject(bridge)
        }
        .sheet(
            isPresented: Binding(
                get: { bridge.rubricsUiState?.assignDialogState != nil },
                set: { visible in
                    if !visible {
                        bridge.dismissAssignRubricDialog()
                    }
                }
            )
        ) {
            AssignRubricToTabView()
                .environmentObject(bridge)
        }
        .alert("Eliminar rúbrica", isPresented: Binding(
            get: { deletingRubric != nil },
            set: { visible in if !visible { deletingRubric = nil } }
        )) {
            Button("Cancelar", role: .cancel) {
                deletingRubric = nil
            }
            Button("Eliminar", role: .destructive) {
                if let rubric = deletingRubric {
                    bridge.deleteRubric(id: rubric.rubric.id)
                }
                deletingRubric = nil
            }
        } message: {
            Text("Esta acción no se puede deshacer.")
        }
        .task {
            try? await bridge.refreshRubrics()
            try? await bridge.refreshRubricClassLinks()
        }
        .refreshable {
            await bridge.pullMissingSyncChanges()
            try? await bridge.refreshRubrics()
            try? await bridge.refreshRubricClassLinks()
        }
    }
}

struct RubricsHeaderView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Banco de Rúbricas")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()

            Text("\(bridge.rubrics.count)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(contrastingTextColor(for: appCardBackground(for: colorScheme)))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(appCardBackground(for: colorScheme).opacity(0.85), in: Capsule())
        }
    }
}

struct FilterChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(chipForeground)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule().fill(chipSelectedBackground)
                    } else {
                        Capsule()
                            .fill(chipBackground)
                            .overlay(Capsule().stroke(chipBorder, lineWidth: 1))
                    }
                }
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.25), value: isSelected)
    }

    private var chipForeground: Color {
        if isSelected { return contrastingTextColor(for: chipSelectedBackground) }
        return colorScheme == .dark ? .white.opacity(0.85) : .primary.opacity(0.85)
    }

    private var chipSelectedBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.33, blue: 0.62)
            : Color.accentColor
    }

    private var chipBackground: Color {
        colorScheme == .dark
            ? appCardBackground(for: colorScheme).opacity(0.92)
            : appSecondarySystemBackgroundColor()
    }

    private var chipBorder: Color {
        colorScheme == .dark ? .white.opacity(0.18) : .black.opacity(0.08)
    }
}

struct RubricBankCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let rubric: RubricDetail
    let onAssign: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rubric.rubric.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Label(
                            "\(rubric.criteria.count) criterio\(rubric.criteria.count == 1 ? "" : "s")",
                            systemImage: "checklist"
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                CriteriaCountBadge(count: rubric.criteria.count)
            }

            Divider()
                .background(colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.08))

            HStack(spacing: 8) {
                CardActionButton(
                    label: "Asignar",
                    icon: "link.badge.plus",
                    style: .accent,
                    action: onAssign
                )

                CardActionButton(
                    label: "Editar",
                    icon: "pencil",
                    style: .secondary,
                    action: onEdit
                )

                Spacer()

                CardActionButton(
                    label: "",
                    icon: "trash",
                    style: .destructive,
                    action: onDelete
                )
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(isHovered ? 0.12 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.25), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(duration: 0.2), value: isHovered)
        .onHover { hovering in isHovered = hovering }
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture { onEdit() }
    }
}

struct CriteriaCountBadge: View {
    let count: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.6, blue: 1.0), Color(red: 0.4, green: 0.3, blue: 0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)

            Text("\(count)")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

enum CardActionStyle { case accent, secondary, destructive }

struct CardActionButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let icon: String
    let style: CardActionStyle
    let action: () -> Void

    private var foregroundColor: Color {
        switch style {
        case .accent: return Color(red: 0.2, green: 0.6, blue: 1.0)
        case .secondary: return colorScheme == .dark ? .white.opacity(0.7) : .primary.opacity(0.72)
        case .destructive: return Color(red: 1.0, green: 0.35, blue: 0.35)
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .accent: return Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.15)
        case .secondary: return colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.05)
        case .destructive: return Color(red: 1.0, green: 0.35, blue: 0.35).opacity(0.12)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, label.isEmpty ? 10 : 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(foregroundColor.opacity(0.3), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct LiquidGlassFab: View {
    let label: String
    let icon: String
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                Text(label)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.2, green: 0.55, blue: 1.0),
                                Color(red: 0.35, green: 0.25, blue: 0.9)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color(red: 0.2, green: 0.55, blue: 1.0).opacity(0.5), radius: 16, x: 0, y: 6)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(duration: 0.15), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

struct MeshBackgroundView: View {
    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.10)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.2, green: 0.4, blue: 0.9).opacity(0.35), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 300
                    )
                )
                .frame(width: 500, height: 500)
                .offset(x: -100, y: -200)
                .blur(radius: 60)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.5, green: 0.2, blue: 0.8).opacity(0.25), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 250
                    )
                )
                .frame(width: 400, height: 400)
                .offset(x: 150, y: 300)
                .blur(radius: 70)
        }
    }
}

struct RubricsEmptyStateView: View {
    let onNewRubric: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checklist.unchecked")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.white.opacity(0.3))

            VStack(spacing: 8) {
                Text("Sin rúbricas todavía")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                Text("Crea tu primera rúbrica para empezar\na evaluar por criterios.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
            }

            LiquidGlassFab(label: "Crear rúbrica", icon: "plus", action: onNewRubric)
        }
        .padding(40)
    }
}

struct AssignRubricToTabView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss

    private var dialog: AssignRubricDialogState? {
        bridge.rubricsUiState?.assignDialogState
    }

    var body: some View {
        NavigationStack {
            Group {
                if let state = dialog {
                    Form {
                        Section("Rúbrica") {
                            Text(state.rubricName)
                        }

                        Section("Clase") {
                            Picker(
                                "Selecciona clase",
                                selection: Binding<Int64>(
                                    get: { state.selectedClassId?.int64Value ?? 0 },
                                    set: { bridge.onAssignClassSelected($0) }
                                )
                            ) {
                                Text("Elige una clase").tag(Int64(0))
                                ForEach(bridge.classes, id: \.id) { schoolClass in
                                    Text(schoolClass.name).tag(schoolClass.id)
                                }
                            }
                        }

                        if state.selectedClassId != nil {
                            Section("Destino") {
                                Toggle(
                                    "Crear pestaña nueva",
                                    isOn: Binding(
                                        get: { state.createNewTab },
                                        set: { bridge.onToggleCreateNewTab($0) }
                                    )
                                )

                                if state.createNewTab {
                                    TextField(
                                        "Nombre de pestaña",
                                        text: Binding(
                                            get: { state.newTabName },
                                            set: { bridge.onNewTabNameChanged($0) }
                                        )
                                    )
                                } else {
                                    Picker(
                                        "Pestaña",
                                        selection: Binding<String>(
                                            get: { state.selectedTab ?? "" },
                                            set: { bridge.onAssignTabSelected($0) }
                                        )
                                    ) {
                                        ForEach(state.availableTabs, id: \.self) { tab in
                                            Text(tab).tag(tab)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    ProgressView("Cargando…")
                }
            }
            .navigationTitle("Asignar rúbrica")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") {
                        bridge.dismissAssignRubricDialog()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Asignar") {
                        bridge.confirmAssignRubric()
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(!canAssign)
                }
            }
        }
    }

    private var canAssign: Bool {
        guard let state = dialog, state.selectedClassId != nil else { return false }
        if state.createNewTab {
            return !state.newTabName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return state.selectedTab != nil || !state.availableTabs.isEmpty
    }
}

struct RubricsBuilderScreen: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var saveFeedback: String? = nil

    private var state: RubricUiState? {
        bridge.rubricsUiState
    }

    var body: some View {
        NavigationStack {
            Group {
                if let state {
                    VStack(alignment: .leading, spacing: 16) {
                        RubricBuilderHeader(
                            state: state,
                            rubricName: rubricNameBinding,
                            selectedClassId: selectedClassBinding,
                            selectedTeachingUnitId: selectedTeachingUnitBinding
                        )
                        .environmentObject(bridge)

                        TextEditor(text: instructionsBinding)
                            .frame(height: 88)
                            .padding(10)
                            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(.gray.opacity(0.12), lineWidth: 1)
                            )

                        RubricBuilderGridView(state: state)
                            .environmentObject(bridge)
                            .frame(maxHeight: .infinity)

                        Button {
                            bridge.addRubricCriterion()
                        } label: {
                            Label("Añadir Nuevo Criterio", systemImage: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        HStack {
                            if state.isSaving {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Guardando...")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.system(size: 14))
                                Text(saveFeedback ?? "Guardado")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                bridge.saveRubricFromBuilder { success in
                                    saveFeedback = success ? "Rúbrica guardada correctamente" : "Error al guardar"
                                    if success {
                                        dismiss()
                                    }
                                }
                            } label: {
                            Label("Guardar Rúbrica", systemImage: "square.and.arrow.down")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(contrastingTextColor(for: Color.accentColor))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(state.rubricName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isSaving)
                        }
                    }
                    .padding(20)
                } else {
                    ProgressView("Cargando editor...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(appPageBackground(for: colorScheme).ignoresSafeArea())
            .appInlineNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    private var rubricNameBinding: Binding<String> {
        Binding(
            get: { bridge.rubricsUiState?.rubricName ?? "" },
            set: { bridge.updateRubricName($0) }
        )
    }

    private var instructionsBinding: Binding<String> {
        Binding(
            get: { bridge.rubricsUiState?.instructions ?? "" },
            set: { bridge.updateRubricInstructions($0) }
        )
    }

    private var selectedClassBinding: Binding<Int64?> {
        Binding(
            get: { bridge.rubricsUiState?.selectedClassId?.int64Value },
            set: { bridge.selectRubricClass($0) }
        )
    }

    private var selectedTeachingUnitBinding: Binding<Int64?> {
        Binding(
            get: { bridge.selectedRubricTeachingUnitId },
            set: { bridge.selectRubricTeachingUnit($0) }
        )
    }
}

private struct RubricBuilderHeader: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    let state: RubricUiState
    let rubricName: Binding<String>
    let selectedClassId: Binding<Int64?>
    let selectedTeachingUnitId: Binding<Int64?>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("¿Cómo se llama esta rúbrica?", text: rubricName)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .textFieldStyle(.plain)

            HStack(spacing: 10) {
                Menu {
                    Button("Ninguna") { selectedClassId.wrappedValue = nil }
                    ForEach(state.allClasses, id: \.id) { schoolClass in
                        Button(schoolClass.name) { selectedClassId.wrappedValue = schoolClass.id }
                    }
                } label: {
                    Label(
                        selectedClassName ?? "+ Asignar clase",
                        systemImage: "person.3.fill"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(appCardBackground(for: colorScheme), in: Capsule())
                }
                .buttonStyle(.plain)

                if selectedClassId.wrappedValue != nil {
                    Menu {
                        Button("Sin SA concreta") { selectedTeachingUnitId.wrappedValue = nil }
                        ForEach(bridge.rubricBuilderTeachingUnits, id: \.id) { unit in
                            Button(unit.name) { selectedTeachingUnitId.wrappedValue = unit.id }
                        }
                    } label: {
                        Label(
                            selectedTeachingUnitName ?? "+ Asignar SA",
                            systemImage: "square.stack.3d.up.fill"
                        )
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(appCardBackground(for: colorScheme), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Text("Niveles:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(["Estándar", "Binario", "Numérico"], id: \.self) { preset in
                    Button(preset) { bridge.applyRubricPreset(preset) }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(appCardBackground(for: colorScheme).opacity(0.95), in: Capsule())
                        .buttonStyle(.plain)
                }

                Spacer()
                Label(
                    "Peso: \(Int((state.totalWeight * 100).rounded()))%",
                    systemImage: state.totalWeight == 1.0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(state.totalWeight == 1.0 ? Color.green : Color.red)
            }
        }
    }

    private var selectedClassName: String? {
        guard let selectedId = selectedClassId.wrappedValue else { return nil }
        return state.allClasses.first(where: { $0.id == selectedId })?.name
    }

    private var selectedTeachingUnitName: String? {
        guard let selectedId = selectedTeachingUnitId.wrappedValue else { return nil }
        return bridge.rubricBuilderTeachingUnits.first(where: { $0.id == selectedId })?.name
    }
}

private struct RubricBuilderGridView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    let state: RubricUiState

    var body: some View {
        GeometryReader { proxy in
            let layout = makeLayout(in: proxy.size)
            VStack(alignment: .leading, spacing: layout.rowSpacing) {
                headerRow(layout: layout)
                ForEach(Array(state.criteria.enumerated()), id: \.offset) { index, criterion in
                    criterionRow(index: index, criterion: criterion, layout: layout)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(4)
        }
    }

    private func headerRow(layout: RubricGridLayout) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("Criterio / Niveles")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: layout.criterionWidth, alignment: .leading)
                .padding(.top, 8)

            ForEach(Array(state.levels.enumerated()), id: \.element.uid) { index, level in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        TextField("Nivel", text: Binding(
                            get: { level.name },
                            set: { bridge.updateRubricLevelName(at: index, name: $0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button(role: .destructive) {
                            bridge.removeRubricLevel(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }

                    Stepper(value: Binding(
                        get: { Int(level.points) },
                        set: { bridge.updateRubricLevelPoints(at: index, points: $0) }
                    ), in: 0...20) {
                        Text("Puntos: \(level.points)")
                            .font(.caption)
                    }
                }
                .frame(width: layout.levelWidth, alignment: .leading)
            }

            Button {
                bridge.addRubricLevel()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    private func criterionRow(index: Int, criterion: RubricCriterionState, layout: RubricGridLayout) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Nombre del criterio", text: Binding(
                    get: { criterion.description_ },
                    set: { bridge.updateRubricCriterionDescription(at: index, description: $0) }
                ), axis: .vertical)
                .lineLimit(2...3)
                .textFieldStyle(RoundedBorderTextFieldStyle())

                Slider(value: Binding(
                    get: { criterion.weight },
                    set: { bridge.updateRubricCriterionWeight(at: index, weight: $0) }
                ), in: 0...1)
                Text("\(Int((criterion.weight * 100).rounded()))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: layout.criterionWidth, alignment: .leading)

            ForEach(state.levels, id: \.uid) { level in
                TextEditor(text: Binding(
                    get: { criterion.levelDescriptions[level.uid] ?? "" },
                    set: { bridge.updateRubricLevelDescription(criterionIndex: index, levelUid: level.uid, description: $0) }
                ))
                .frame(width: layout.levelWidth, height: layout.editorHeight)
                .padding(8)
                .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.gray.opacity(0.15), lineWidth: 1)
                )
            }

            Button(role: .destructive) {
                bridge.removeRubricCriterion(at: index)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(.vertical, layout.rowPadding)
    }

    private func makeLayout(in size: CGSize) -> RubricGridLayout {
        let horizontalPadding: CGFloat = 24
        let spacing: CGFloat = 8
        let availableWidth = max(size.width - horizontalPadding, 320)
        let controlsWidth: CGFloat = 42
        let criterionWidth = min(max(availableWidth * 0.26, 170), 260)
        let levelCount = max(state.levels.count, 1)
        let levelsArea = availableWidth - criterionWidth - controlsWidth - (spacing * CGFloat(levelCount + 1))
        let levelWidth = min(max(levelsArea / CGFloat(levelCount), 88), 220)

        let availableHeight = max(size.height - 24, 240)
        let criteriaCount = max(state.criteria.count, 1)
        let headerHeight: CGFloat = 88
        let rowsHeight = max(availableHeight - headerHeight, 120)
        let editorHeight = min(max((rowsHeight / CGFloat(criteriaCount)) - 24, 56), 130)
        let rowPadding = max(min((rowsHeight / CGFloat(criteriaCount) - editorHeight) / 2, 8), 2)

        return RubricGridLayout(
            criterionWidth: criterionWidth,
            levelWidth: levelWidth,
            editorHeight: editorHeight,
            rowSpacing: 6,
            rowPadding: rowPadding
        )
    }
}

private struct RubricGridLayout {
    let criterionWidth: CGFloat
    let levelWidth: CGFloat
    let editorHeight: CGFloat
    let rowSpacing: CGFloat
    let rowPadding: CGFloat
}

private enum PlannerTabIOS: String, CaseIterable, Identifiable {
    case week = "Semana"
    case timeline = "Timeline"
    case day = "Día"
    case detail = "Detalle"
    var id: String { rawValue }
}

@MainActor
final class PlannerIOSViewModel: ObservableObject {
    @Published var isLoaded = false
    @Published var week: Int = 1
    @Published var year: Int = 2026
    @Published var weekLabel = ""
    @Published var dateRangeLabel = ""
    @Published var groups: [SchoolClass] = []
    @Published var selectedGroupId: Int64?
    @Published var selectedSession: PlanningSession?
    @Published var sessions: [PlanningSession] = []
    @Published var slots: [WeeklySlotTemplate] = []
    @Published var timeSlots: [TimeSlotConfig] = []
    @Published var lastBulkSummary = ""
    @Published var isSelectionMode = false
    @Published var selectedSessionIds: Set<Int64> = []
    @Published var cellSessionIndex: [String: PlanningSession] = [:]
    @Published var showingSessionEditor = false
    @Published var showingClassSelector = false
    @Published var showingWeeklyConfig = false
    @Published var showingCopyMove = false
    @Published var editingSession: PlanningSession?
    @Published var editorDayOfWeek = 1
    @Published var editorPeriod = 1

    private weak var bridge: KmpBridge?

    func bind(bridge: KmpBridge) async {
        guard !isLoaded else { return }
        self.bridge = bridge
        let current = IsoWeekHelper.shared.current()
        week = Int(truncating: current.first ?? KotlinInt(value: 1))
        year = Int(truncating: current.second ?? KotlinInt(value: 2026))
        timeSlots = bridge.plannerTimeSlots()
        await reloadAll()
        isLoaded = true
    }

    func reloadAll() async {
        guard let bridge else { return }
        await bridge.ensureClassesLoaded()
        groups = bridge.classes.sorted { $0.name < $1.name }
        if selectedGroupId == nil {
            selectedGroupId = groups.first?.id
        }
        weekLabel = "Semana \(week), \(year)"
        dateRangeLabel = weekRangeLabel(week: week, year: year)
        slots = bridge.plannerWeeklySlots(classId: selectedGroupId)
        sessions = (try? await bridge.plannerListSessions(weekNumber: week, year: year, classId: selectedGroupId)) ?? []
        rebuildCellIndex()
    }

    func previousWeek() async {
        if week <= 1 {
            week = 52
            year -= 1
        } else {
            week -= 1
        }
        await reloadAll()
    }

    func nextWeek() async {
        if week >= 52 {
            week = 1
            year += 1
        } else {
            week += 1
        }
        await reloadAll()
    }

    func selectGroup(_ id: Int64?) async {
        selectedGroupId = id
        selectedSession = nil
        selectedSessionIds.removeAll()
        await reloadAll()
    }

    func openEditor(day: Int, period: Int, session: PlanningSession?) {
        editingSession = session
        editorDayOfWeek = day
        editorPeriod = period
        showingSessionEditor = true
    }

    func saveSession(
        unitTitle: String,
        objectives: String,
        activities: String,
        evaluation: String
    ) async {
        guard let bridge, let groupId = selectedGroupId else { return }
        let groupName = groups.first(where: { $0.id == groupId })?.name ?? "Grupo \(groupId)"
        let currentStatus = editingSession?.status ?? SessionStatus.planned
        let unitName = unitTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Sesión" : unitTitle

        _ = try? await bridge.plannerUpsertSession(
            id: editingSession?.id ?? 0,
            teachingUnitId: editingSession?.teachingUnitId ?? 0,
            teachingUnitName: unitName,
            teachingUnitColor: editingSession?.teachingUnitColor ?? "#4A90D9",
            groupId: groupId,
            groupName: groupName,
            dayOfWeek: editingSession.map { Int($0.dayOfWeek) } ?? editorDayOfWeek,
            period: editingSession.map { Int($0.period) } ?? editorPeriod,
            weekNumber: week,
            year: year,
            objectives: objectives,
            activities: activities,
            evaluation: evaluation,
            status: currentStatus
        )
        showingSessionEditor = false
        editingSession = nil
        await reloadAll()
    }

    func deleteSession(_ session: PlanningSession) async {
        guard let bridge else { return }
        try? await bridge.plannerDeleteSession(sessionId: session.id)
        if selectedSession?.id == session.id {
            selectedSession = nil
        }
        selectedSessionIds.remove(session.id)
        await reloadAll()
    }

    func toggleSelection(sessionId: Int64) {
        if selectedSessionIds.contains(sessionId) {
            selectedSessionIds.remove(sessionId)
        } else {
            selectedSessionIds.insert(sessionId)
        }
    }

    func moveSelected(dayOffset: Int = 0, periodOffset: Int = 0, resolution: CollisionResolution = .skip) async {
        guard let bridge, !selectedSessionIds.isEmpty else { return }
        let result = try? await bridge.plannerShiftSessions(
            sourceSessionIds: Array(selectedSessionIds),
            dayOffset: dayOffset,
            periodOffset: periodOffset,
            resolution: resolution
        )
        if let result {
            lastBulkSummary = "Movidas/copiadas: \(result.movedOrCopied) · Sobrescritas: \(result.overwritten) · Omitidas: \(result.skipped + result.failed)"
        }
        isSelectionMode = false
        selectedSessionIds.removeAll()
        await reloadAll()
    }

    func copySelected(
        to targetGroupId: Int64,
        dayOffset: Int = 0,
        periodOffset: Int = 0,
        resolution: CollisionResolution = .skip
    ) async {
        guard let bridge, !selectedSessionIds.isEmpty else { return }
        let result = try? await bridge.plannerCopySessions(
            sourceSessionIds: Array(selectedSessionIds),
            targetGroupId: targetGroupId,
            dayOffset: dayOffset,
            periodOffset: periodOffset,
            resolution: resolution
        )
        if let result {
            lastBulkSummary = "Movidas/copiadas: \(result.movedOrCopied) · Sobrescritas: \(result.overwritten) · Omitidas: \(result.skipped + result.failed)"
        }
        isSelectionMode = false
        selectedSessionIds.removeAll()
        await reloadAll()
    }

    func previewRelocation(
        to targetGroupId: Int64?,
        dayOffset: Int,
        periodOffset: Int
    ) async -> [SessionRelocationConflict] {
        guard let bridge else { return [] }
        return (try? await bridge.plannerPreviewRelocation(
            sourceSessionIds: Array(selectedSessionIds),
            targetGroupId: targetGroupId,
            dayOffset: dayOffset,
            periodOffset: periodOffset
        )) ?? []
    }

    func saveWeeklySlot(classId: Int64, dayOfWeek: Int, startTime: String, endTime: String, editingSlotId: Int64?) async throws {
        guard let bridge else { return }
        _ = try await bridge.plannerSaveWeeklySlot(
            classId: classId,
            dayOfWeek: dayOfWeek,
            startTime: startTime,
            endTime: endTime,
            editingSlotId: editingSlotId
        )
        slots = bridge.plannerWeeklySlots(classId: selectedGroupId)
    }

    func deleteWeeklySlot(slotId: Int64) async {
        guard let bridge else { return }
        try? await bridge.plannerDeleteWeeklySlot(slotId: slotId)
        slots = bridge.plannerWeeklySlots(classId: selectedGroupId)
    }

    private func rebuildCellIndex() {
        var mapped: [String: PlanningSession] = [:]
        for session in sessions {
            let key = "\(session.dayOfWeek)|\(session.period)|\(session.groupId)"
            mapped[key] = session
        }
        cellSessionIndex = mapped
    }

    func sessionAt(day: Int, period: Int) -> PlanningSession? {
        guard let groupId = selectedGroupId else { return nil }
        return cellSessionIndex["\(day)|\(period)|\(groupId)"]
    }

    private func weekRangeLabel(week: Int, year: Int) -> String {
        let days = IsoWeekHelper.shared.daysOf(isoWeek: Int32(week), year: Int32(year))
        guard let first = days.first, let last = days.last else { return "" }
        return "\(first.dayOfMonth) - \(last.dayOfMonth)"
    }
}

struct PlannerScreenIOS: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var vm = PlannerIOSViewModel()
    @State private var activeTab: PlannerTabIOS = .week

    var body: some View {
        VStack(spacing: 0) {
            PlannerHeaderBarIOS(vm: vm)
            PlannerTabsIOS(activeTab: $activeTab)
            if !vm.lastBulkSummary.isEmpty {
                Text(vm.lastBulkSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            Group {
                switch activeTab {
                case .week:
                    WeekGridViewIOS(vm: vm)
                case .timeline:
                    PlannerPlaceholder(title: "Timeline (v1)")
                case .day:
                    PlannerPlaceholder(title: "Día (v1)")
                case .detail:
                    SessionDetailPanelIOS(vm: vm)
                }
            }
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: activeTab)
        }
        .task { await vm.bind(bridge: bridge) }
        .sheet(isPresented: $vm.showingSessionEditor) {
            SessionEditorSheet(vm: vm)
        }
        .sheet(isPresented: $vm.showingClassSelector) {
            ClassSelectorSheet(vm: vm)
        }
        .sheet(isPresented: $vm.showingWeeklyConfig) {
            WeeklyTemplateConfigSheet(vm: vm)
        }
        .sheet(isPresented: $vm.showingCopyMove) {
            CopyMoveSessionsSheet(vm: vm)
        }
    }
}

private struct PlannerHeaderBarIOS: View {
    @ObservedObject var vm: PlannerIOSViewModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.weekLabel).font(.title2.weight(.black))
                    Text(vm.dateRangeLabel).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await vm.previousWeek() } } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.bordered)
                Button { Task { await vm.nextWeek() } } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.bordered)
            }
            HStack(spacing: 8) {
                Picker("Grupo", selection: Binding(
                    get: { vm.selectedGroupId ?? -1 },
                    set: { value in Task { await vm.selectGroup(value > 0 ? value : nil) } }
                )) {
                    ForEach(vm.groups, id: \.id) { group in
                        Text(group.name).tag(group.id)
                    }
                }
                .pickerStyle(.menu)
                Button("Horario") { vm.showingWeeklyConfig = true }.buttonStyle(.bordered)
                Button("Seleccionar") {
                    vm.isSelectionMode.toggle()
                    if !vm.isSelectionMode {
                        vm.selectedSessionIds.removeAll()
                    }
                }
                .buttonStyle(.bordered)
                Button("Copiar/Mover") { vm.showingCopyMove = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.selectedSessionIds.isEmpty)
            }
        }
        .padding(16)
    }
}

private struct PlannerTabsIOS: View {
    @Binding var activeTab: PlannerTabIOS

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PlannerTabIOS.allCases) { tab in
                Button(tab.rawValue) { activeTab = tab }
                    .buttonStyle(.bordered)
                    .tint(activeTab == tab ? .accentColor : .gray)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

private struct WeekGridViewIOS: View {
    @ObservedObject var vm: PlannerIOSViewModel
    private let dayHeaders = [(1, "Lun"), (2, "Mar"), (3, "Mié"), (4, "Jue"), (5, "Vie")]

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("Franja")
                        .font(.caption.bold())
                        .frame(width: 90, height: 42)
                        .background(Color.secondary.opacity(0.08))
                    ForEach(dayHeaders, id: \.0) { item in
                        Text(item.1)
                            .font(.caption.bold())
                            .frame(width: 170, height: 42)
                            .background(Color.secondary.opacity(0.08))
                    }
                }
                ForEach(vm.timeSlots, id: \.period) { slot in
                    HStack(spacing: 0) {
                        VStack(spacing: 2) {
                            Text("P\(slot.period)").font(.caption2.bold())
                            Text("\(slot.startTime)-\(slot.endTime)").font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(width: 90, height: 90)
                        .background(Color.secondary.opacity(0.04))

                        ForEach(dayHeaders, id: \.0) { day in
                            let session = vm.sessionAt(day: day.0, period: Int(slot.period))
                            WeekCellView(
                                session: session,
                                selected: session.map { vm.selectedSessionIds.contains($0.id) } ?? false,
                                selectionMode: vm.isSelectionMode
                            ) {
                                if let session {
                                    vm.selectedSession = session
                                    if vm.isSelectionMode {
                                        vm.toggleSelection(sessionId: session.id)
                                    } else {
                                        vm.openEditor(day: day.0, period: Int(slot.period), session: session)
                                    }
                                } else if !vm.isSelectionMode {
                                    vm.openEditor(day: day.0, period: Int(slot.period), session: nil)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct WeekCellView: View {
    let session: PlanningSession?
    let selected: Bool
    let selectionMode: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                if let session {
                    Text(session.teachingUnitName).font(.caption.bold()).lineLimit(1)
                    Text(session.activities).font(.caption2).lineLimit(2)
                } else {
                    Text(selectionMode ? "Vacía" : "Añadir")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 170, height: 90, alignment: .topLeading)
            .padding(8)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var background: some ShapeStyle {
        if selected { return AnyShapeStyle(Color.accentColor.opacity(0.14)) }
        if session != nil { return AnyShapeStyle(Color.blue.opacity(0.08)) }
        return AnyShapeStyle(Color.clear)
    }
}

private struct SessionDetailPanelIOS: View {
    @ObservedObject var vm: PlannerIOSViewModel

    var body: some View {
        Group {
            if let session = vm.selectedSession {
                VStack(alignment: .leading, spacing: 12) {
                    Text(session.teachingUnitName).font(.title3.weight(.bold))
                    Text("Grupo \(session.groupName) · Día \(session.dayOfWeek) · Periodo \(session.period)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !session.objectives.isEmpty {
                        Text("Objetivos").font(.caption.bold())
                        Text(session.objectives).font(.subheadline)
                    }
                    if !session.activities.isEmpty {
                        Text("Actividades").font(.caption.bold())
                        Text(session.activities).font(.subheadline)
                    }
                    if !session.evaluation.isEmpty {
                        Text("Evaluación").font(.caption.bold())
                        Text(session.evaluation).font(.subheadline)
                    }
                    HStack {
                        Button("Editar") {
                            vm.openEditor(day: Int(session.dayOfWeek), period: Int(session.period), session: session)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Eliminar", role: .destructive) {
                            Task { await vm.deleteSession(session) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
            } else {
                PlannerPlaceholder(title: "Selecciona una sesión")
            }
        }
    }
}

private struct SessionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: PlannerIOSViewModel
    @State private var title = ""
    @State private var objectives = ""
    @State private var activities = ""
    @State private var evaluation = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Datos mínimos") {
                    TextField("UD", text: $title)
                    TextField("Actividades", text: $activities, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("Avanzado") {
                    TextField("Objetivos", text: $objectives, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Evaluación", text: $evaluation, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(vm.editingSession == nil ? "Nueva sesión" : "Editar sesión")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") {
                        Task {
                            await vm.saveSession(
                                unitTitle: title,
                                objectives: objectives,
                                activities: activities,
                                evaluation: evaluation
                            )
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                if let existing = vm.editingSession {
                    title = existing.teachingUnitName
                    objectives = existing.objectives
                    activities = existing.activities
                    evaluation = existing.evaluation
                }
            }
        }
    }
}

private struct ClassSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: PlannerIOSViewModel

    var body: some View {
        NavigationStack {
            List(vm.groups, id: \.id) { group in
                Button(group.name) {
                    Task {
                        await vm.selectGroup(group.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Seleccionar grupo")
        }
    }
}

private struct WeeklyTemplateConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: PlannerIOSViewModel
    @State private var day = 1
    @State private var startTime = "08:05"
    @State private var endTime = "09:00"
    @State private var startTimeValue = AppDateTimeSupport.time(from: "08:05")
    @State private var endTimeValue = AppDateTimeSupport.time(from: "09:00")
    @State private var errorText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Form {
                    Section("Nueva franja") {
                        Picker("Día", selection: $day) {
                            Text("Lunes").tag(1)
                            Text("Martes").tag(2)
                            Text("Miércoles").tag(3)
                            Text("Jueves").tag(4)
                            Text("Viernes").tag(5)
                        }
                        DatePicker("Inicio", selection: $startTimeValue, displayedComponents: .hourAndMinute)
                        DatePicker("Fin", selection: $endTimeValue, displayedComponents: .hourAndMinute)
                        Button("Guardar franja") {
                            Task {
                                guard let classId = vm.selectedGroupId else { return }
                                do {
                                    startTime = AppDateTimeSupport.timeString(from: startTimeValue)
                                    endTime = AppDateTimeSupport.timeString(from: endTimeValue)
                                    try await vm.saveWeeklySlot(
                                        classId: classId,
                                        dayOfWeek: day,
                                        startTime: startTime,
                                        endTime: endTime,
                                        editingSlotId: nil
                                    )
                                    errorText = ""
                                } catch {
                                    errorText = error.localizedDescription
                                }
                            }
                        }
                    }
                    Section("Franjas actuales") {
                        ForEach(vm.slots.sorted(by: { ($0.dayOfWeek, $0.startTime) < ($1.dayOfWeek, $1.startTime) }), id: \.id) { slot in
                            HStack {
                                Text("D\(slot.dayOfWeek) · \(slot.startTime)-\(slot.endTime)")
                                Spacer()
                                Button(role: .destructive) {
                                    Task { await vm.deleteWeeklySlot(slotId: slot.id) }
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Configurar horario")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}

private struct CopyMoveSessionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: PlannerIOSViewModel
    @State private var targetGroupId: Int64 = -1
    @State private var dayOffset = 0
    @State private var periodOffset = 0
    @State private var modeCopy = true
    @State private var conflicts: [SessionRelocationConflict] = []
    @State private var resolution: CollisionResolution = .skip

    var body: some View {
        NavigationStack {
            Form {
                Section("Operación") {
                    Picker("Tipo", selection: $modeCopy) {
                        Text("Copiar").tag(true)
                        Text("Mover").tag(false)
                    }
                    .pickerStyle(.segmented)
                    if modeCopy {
                        Picker("Grupo destino", selection: $targetGroupId) {
                            ForEach(vm.groups.filter { $0.id != vm.selectedGroupId }, id: \.id) { group in
                                Text(group.name).tag(group.id)
                            }
                        }
                    }
                    Stepper("Desplazar días: \(dayOffset)", value: $dayOffset, in: -7...7)
                    Stepper("Desplazar periodos: \(periodOffset)", value: $periodOffset, in: -6...6)
                }
                Section("Conflictos") {
                    if conflicts.isEmpty {
                        Text("Sin conflictos detectados.")
                    } else {
                        Text("\(conflicts.count) conflicto(s) detectados")
                        Picker("Resolver", selection: $resolution) {
                            Text("Omitir").tag(CollisionResolution.skip)
                            Text("Sobrescribir").tag(CollisionResolution.overwrite)
                            Text("Cancelar").tag(CollisionResolution.cancel)
                        }
                    }
                    Button("Previsualizar") {
                        Task {
                            conflicts = await vm.previewRelocation(
                                to: modeCopy ? (targetGroupId > 0 ? targetGroupId : nil) : nil,
                                dayOffset: dayOffset,
                                periodOffset: periodOffset
                            )
                        }
                    }
                    .disabled(vm.selectedSessionIds.isEmpty)
                }
                Section {
                    Button(modeCopy ? "Confirmar copia" : "Confirmar movimiento") {
                        Task {
                            if modeCopy {
                                guard targetGroupId > 0 else { return }
                                await vm.copySelected(
                                    to: targetGroupId,
                                    dayOffset: dayOffset,
                                    periodOffset: periodOffset,
                                    resolution: resolution
                                )
                            } else {
                                await vm.moveSelected(
                                    dayOffset: dayOffset,
                                    periodOffset: periodOffset,
                                    resolution: resolution
                                )
                            }
                            dismiss()
                        }
                    }
                    .disabled(vm.selectedSessionIds.isEmpty || (modeCopy && targetGroupId <= 0))
                }
            }
            .navigationTitle("Copiar / Mover")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .onAppear {
                if let first = vm.groups.first(where: { $0.id != vm.selectedGroupId }) {
                    targetGroupId = first.id
                }
            }
        }
    }
}

private struct PlannerPlaceholder: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
