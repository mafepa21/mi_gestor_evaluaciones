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
    case alerts
    case quickEvaluation
    case groupSummary
    case agenda
    case physicalEducation
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
            }
        }
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
                    Text("Hoy")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                    Text("\(mode.title) · \(selectedClassLabel)")
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
                VStack(alignment: .leading, spacing: 16) {
                    dashboardKpiRow(snapshot: snapshot)

                    let blocks: [DashboardBlock] = mode == .classroom
                        ? [.quickEvaluation, .today, .physicalEducation, .alerts, .groupSummary, .agenda]
                        : [.groupSummary, .agenda, .alerts, .today, .quickEvaluation, .physicalEducation]

                    ForEach(blocks, id: \.self) { block in
                        switch block {
                        case .today:
                            dashboardTodayBlock(snapshot: snapshot)
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
        VStack(alignment: .leading, spacing: 10) {
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Hoy").font(.headline)
                Spacer()
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
                            Text("Espacio: \(item.space) · \(dashboardSessionStatusLabel(item.sessionStatus))").font(.caption2).foregroundStyle(.secondary)
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
                Text("Alertas").font(.headline)
                Spacer()
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
                        Text(dashboardFilterLabel(alert.severity)).font(.caption2.bold())
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
                Text("Evaluación rápida").font(.headline)
                Spacer()
            }
            if !snapshot.quickColumns.isEmpty {
                Text("Columnas disponibles: \(snapshot.quickColumns.joined(separator: ", "))").font(.caption)
            }
            if !snapshot.quickRubrics.isEmpty {
                Text("Rúbricas disponibles: \(snapshot.quickRubrics.joined(separator: ", "))").font(.caption)
            }
            HStack {
                Button("Pasar lista") {
                    Task { await performPassList() }
                }
                Button("Nueva observación") {
                    Task { await performObservation() }
                }
                Button("Evaluar") {
                    isQuickEvaluationPresented = true
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
                Text("Resumen por grupo").font(.headline)
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
                Text("Agenda docente").font(.headline)
                Spacer()
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
                Text("Educación Física").font(.headline)
                Spacer()
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
                        Text(dashboardFilterLabel(item.severity)).font(.caption2)
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

    private func dashboardFilterPicker(
        title: String,
        selection: Binding<DashboardFilterOption>,
        options: [DashboardFilterOption]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(options) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func dashboardSessionFilterPicker(
        title: String,
        selection: Binding<DashboardSessionFilterOption>,
        options: [DashboardSessionFilterOption]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(options) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
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
