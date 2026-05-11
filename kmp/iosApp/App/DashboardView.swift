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
