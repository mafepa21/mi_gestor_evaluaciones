import SwiftUI
import MiGestorKit

struct MacDashboardToolbarActions {
    let modeRawValue: String
    let canRunActions: Bool
    let setMode: (String) -> Void
    let refresh: () -> Void
    let passList: () -> Void
    let observation: () -> Void
}

struct MacDashboardView: View {
    @ObservedObject var bridge: KmpBridge
    let bootstrap: AppleBridgeBootstrap
    var onToolbarActionsChange: (MacDashboardToolbarActions?) -> Void = { _ in }

    @State private var selectedClassId: Int64? = nil
    @AppStorage("dashboard_operational_mode") private var modeRawValue: String = MacDashboardMode.office.rawValue
    @State private var severityFilter = ""
    @State private var priorityFilter = ""
    @State private var sessionStatusFilter = ""
    @State private var inspectorSelection: MacDashboardInspectorSelection? = nil
    @State private var inspectorTab: MacDashboardInspectorTab = .detail
    @State private var activeSheet: DashboardSheet? = nil
    @State private var briefingEvidence: TeachingEvidencePack?
    @State private var showsFilters = false

    private var mode: MacDashboardMode {
        MacDashboardMode(rawValue: modeRawValue) ?? .office
    }

    private var actionClassId: Int64? {
        selectedClassId ?? bridge.classes.first?.id
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    pageHeader
                    briefingCard

                    if let snapshot = bridge.dashboardSnapshot {
                        if proxy.size.width >= 1100 {
                            wideDashboard(snapshot: snapshot)
                        } else {
                            compactDashboard(snapshot: snapshot)
                        }
                    } else {
                        ContentUnavailableView(
                            "Preparando dashboard operativo",
                            systemImage: "chart.bar.doc.horizontal",
                            description: Text("Refresca o selecciona una clase para cargar la vista de hoy.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 320)
                    }

                    systemSection
                }
                .padding(MacAppStyle.pagePadding)
            }
        }
        .background(MacAppStyle.pageBackground)
        .sheet(item: $activeSheet, onDismiss: {
            triggerReload()
        }) { sheet in
            switch sheet {
            case .rubric(let target):
                AgendaRubricEvaluationSheet(bridge: bridge, target: target)
            case .rubricPicker(let item):
                PendingEvaluationPickerSheet(bridge: bridge, item: item)
            }
        }
        .task {
            await bridge.ensureClassesLoaded()
            if selectedClassId == nil {
                selectedClassId = bridge.classes.first?.id
            }
            await applyFiltersAndReload()
            briefingEvidence = try? await DailyBriefEvidenceBuilder.build(bridge: bridge, classId: selectedClassId)
        }
        .task(id: selectedClassId) {
            briefingEvidence = try? await DailyBriefEvidenceBuilder.build(bridge: bridge, classId: selectedClassId)
        }
        .onAppear(perform: syncToolbarActions)
        .onDisappear { onToolbarActionsChange(nil) }
        .onChange(of: toolbarStateKey) { _ in syncToolbarActions() }
        .onChange(of: selectedClassId) { _ in triggerReload() }
        .onChange(of: modeRawValue) { _ in triggerReload() }
        .onChange(of: severityFilter) { _ in triggerReload() }
        .onChange(of: priorityFilter) { _ in triggerReload() }
        .onChange(of: sessionStatusFilter) { _ in triggerReload() }
        .onChange(of: inspectorSelection) { _ in inspectorTab = .detail }
    }

    @ViewBuilder
    private var briefingCard: some View {
        if let briefingEvidence, briefingEvidence.hasEnoughData {
            VStack(alignment: .leading, spacing: 16) {
                Label("Briefing IA", systemImage: "sparkles")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(MacAppStyle.infoTint)

                Text(briefingEvidence.summary)
                    .font(.system(size: 13, weight: .semibold))

                if let confidenceNote = briefingEvidence.confidenceNote {
                    Text(confidenceNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(briefingEvidence.factTexts.prefix(3)), id: \.self) { fact in
                        Label(fact, systemImage: "checkmark.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(briefingEvidence.recommendedActionTexts.prefix(2)), id: \.self) { action in
                        Label(action, systemImage: "arrowshape.right.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
            }
            .padding(MacAppStyle.innerPadding)
            .background(MacAppStyle.infoTint.opacity(0.06))
            .overlay {
                RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                    .stroke(MacAppStyle.infoTint.opacity(0.25), lineWidth: 0.75)
            }
            .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Dashboard")
                    .font(MacAppStyle.pageTitle)
                Text("\(Date.now.formatted(date: .complete, time: .omitted)) · \(mode.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            MacStatusPill(
                label: bridge.pairedSyncHost != nil ? "LAN activa" : "Sin sync",
                isActive: bridge.pairedSyncHost != nil,
                tint: bridge.pairedSyncHost != nil ? MacAppStyle.successTint : .secondary
            )
        }
    }

    private func wideDashboard(snapshot: DashboardSnapshot) -> some View {
        HStack(alignment: .top, spacing: 24) {
            leftColumn(snapshot: snapshot)
                .frame(width: 280)

            centerColumn(snapshot: snapshot)
                .frame(maxWidth: .infinity)

            inspector(snapshot: snapshot)
                .frame(width: 340)
        }
    }

    private func compactDashboard(snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            leftColumn(snapshot: snapshot)
            centerColumn(snapshot: snapshot)
            inspector(snapshot: snapshot)
        }
    }

    private func leftColumn(snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                MacMetricCard(label: "Hoy", value: "\(snapshot.todayCount)", tint: MacAppStyle.infoTint, systemImage: "calendar")
                MacMetricCard(
                    label: "Alertas",
                    value: "\(snapshot.alertsCount)",
                    tint: snapshot.alertsCount > 0 ? MacAppStyle.warningTint : MacAppStyle.successTint,
                    systemImage: "exclamationmark.bubble"
                )
                MacMetricCard(
                    label: "Pendientes",
                    value: "\(snapshot.pendingCount)",
                    tint: snapshot.pendingCount > 0 ? MacAppStyle.dangerTint : MacAppStyle.successTint,
                    systemImage: "clock.badge.exclamationmark"
                )
                MacMetricCard(label: "Próxima", value: snapshot.nextSessionLabel, tint: MacAppStyle.infoTint, systemImage: "forward.end.circle")
            }

            classPicker
                .padding(.horizontal, 8)

            filtersSection
        }
    }

    private var filtersSection: some View {
        DisclosureGroup(isExpanded: $showsFilters) {
            VStack(alignment: .leading, spacing: 8) {
                filterPicker("Severidad", options: MacDashboardFilterOptions.severity, selection: $severityFilter)
                filterPicker("Prioridad", options: MacDashboardFilterOptions.priority, selection: $priorityFilter)
                filterPicker("Estado sesión", options: MacDashboardFilterOptions.sessionStatus, selection: $sessionStatusFilter)
            }
            .padding(.top, 8)
        } label: {
            Label("Filtros", systemImage: "line.3.horizontal.decrease.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(MacAppStyle.innerPadding)
        .background(MacAppStyle.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }

    private var classPicker: some View {
        Picker("Clase", selection: $selectedClassId) {
            Text("Global").tag(Int64?.none)
            ForEach(bridge.classes, id: \.id) { schoolClass in
                Text("\(schoolClass.name) · \(schoolClass.course)º").tag(Optional(schoolClass.id))
            }
        }
        .pickerStyle(.menu)
    }

    private func centerColumn(snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            todayBlock(snapshot: snapshot)
            quickEvaluationBlock(snapshot: snapshot)
            agendaBlock(snapshot: snapshot)
            peBlock(snapshot: snapshot)
            alertsBlock(snapshot: snapshot)
        }
    }

    private func todayBlock(snapshot: DashboardSnapshot) -> some View {
        MacPanel(title: "A · Hoy") {
            VStack(spacing: 8) {
                if snapshot.todaySessions.isEmpty {
                    emptyRow("Sin sesiones hoy")
                } else {
                    ForEach(snapshot.todaySessions, id: \.id) { item in
                        sessionButton(item)
                    }
                }
            }
        }
    }

    private func alertsBlock(snapshot: DashboardSnapshot) -> some View {
        MacPanel(title: "B · Alertas") {
            VStack(spacing: 8) {
                if snapshot.alerts.isEmpty {
                    emptyRow("Sin alertas")
                } else {
                    ForEach(snapshot.alerts.prefix(8), id: \.id) { alert in
                        alertButton(alert)
                    }
                }
            }
        }
    }

    private func quickEvaluationBlock(snapshot: DashboardSnapshot) -> some View {
        MacPanel(title: "C · Evaluación rápida") {
            VStack(alignment: .leading, spacing: 16) {
                dashboardListText("Columnas", snapshot.quickColumns)
                dashboardListText("Rúbricas", snapshot.quickRubrics)

                HStack(spacing: 8) {
                    Button {
                        Task { await performPassList() }
                    } label: {
                        Label("Pasar lista", systemImage: "checkmark.circle")
                    }
                    .keyboardShortcut("l", modifiers: [.command])

                    Button {
                        Task { await performObservation() }
                    } label: {
                        Label("Observación", systemImage: "note.text.badge.plus")
                    }
                }
                .disabled(actionClassId == nil)
            }
        }
    }

    private func agendaBlock(snapshot: DashboardSnapshot) -> some View {
        MacPanel(title: "E · Agenda docente") {
            VStack(spacing: 8) {
                if snapshot.agendaItems.isEmpty {
                    emptyRow("Sin agenda para hoy")
                } else {
                    ForEach(snapshot.agendaItems, id: \.id) { item in
                        agendaRow(item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func agendaRow(_ item: AgendaItem) -> some View {
        if item.navigationTargets.isEmpty {
            MacHoverRow {
                agendaRowContent(item, showsDisclosure: false)
            }
        } else {
            Button {
                openAgendaItem(item)
            } label: {
                MacHoverRow {
                    agendaRowContent(item, showsDisclosure: true)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func agendaRowContent(_ item: AgendaItem, showsDisclosure: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title).font(.callout.weight(.semibold))
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.timeLabel).font(.caption.weight(.medium))
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func peBlock(snapshot: DashboardSnapshot) -> some View {
        MacPanel(title: "F · Educación Física") {
            VStack(spacing: 8) {
                if snapshot.peItems.isEmpty {
                    emptyRow("Sin incidencias EF hoy")
                } else {
                    ForEach(snapshot.peItems, id: \.id) { item in
                        peButton(item)
                    }
                }
            }
        }
    }

    private func sessionButton(_ item: TodaySessionItem) -> some View {
        Button {
            inspectorSelection = .session(item.id)
        } label: {
            MacHoverRow {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(item.groupName) · \(item.timeLabel)").font(.callout.weight(.semibold))
                        Text(item.didacticUnit).font(.caption).foregroundStyle(.secondary)
                        Text("Espacio: \(item.space) · \(readableSessionStatus(item.sessionStatus))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Pasar lista", systemImage: "checkmark.circle") {
                Task { await performPassList() }
            }
            Button("Nueva observación", systemImage: "note.text.badge.plus") {
                Task { await performObservation() }
            }
        }
    }

    private func alertButton(_ alert: AlertItem) -> some View {
        Button {
            inspectorSelection = .alert(alert.id)
        } label: {
            MacHoverRow {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(alert.title).font(.callout.weight(.semibold))
                        Text(alert.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    MacStatusPill(label: readableLevel(alert.severity), isActive: true, tint: levelTint(alert.severity))
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Ver acciones", systemImage: "bolt.circle") {
                inspectorSelection = .alert(alert.id)
                inspectorTab = .actions
            }
            Button("Nueva observación", systemImage: "note.text.badge.plus") {
                Task { await performObservation() }
            }
        }
    }

    private func peButton(_ item: PEOperationalItem) -> some View {
        Button {
            inspectorSelection = .pe(item.id)
        } label: {
            MacHoverRow {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title).font(.callout.weight(.semibold))
                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    MacStatusPill(label: readableLevel(item.severity), isActive: true, tint: levelTint(item.severity))
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Nueva observación", systemImage: "note.text.badge.plus") {
                Task { await performObservation() }
            }
        }
    }

    private func inspector(snapshot: DashboardSnapshot) -> some View {
        MacPanel(title: "Selección activa") {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Vista", selection: $inspectorTab) {
                    ForEach(MacDashboardInspectorTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                switch inspectorTab {
                case .detail:
                    inspectorDetail(snapshot: snapshot)
                case .history:
                    inspectorHistory(snapshot: snapshot)
                case .actions:
                    inspectorActions
                }
            }
        }
    }

    @ViewBuilder
    private func inspectorDetail(snapshot: DashboardSnapshot) -> some View {
        switch inspectorSelection {
        case .session(let id):
            if let item = snapshot.todaySessions.first(where: { $0.id == id }) {
                inspectorTitle(item.groupName, subtitle: item.didacticUnit, systemImage: "calendar")
                inspectorMetric("Horario", item.timeLabel)
                inspectorMetric("Espacio", item.space)
                inspectorMetric("Estado", readableSessionStatus(item.sessionStatus))
            } else {
                emptyRow("Sesión no encontrada")
            }
        case .alert(let id):
            if let alert = snapshot.alerts.first(where: { $0.id == id }) {
                inspectorTitle(alert.title, subtitle: alert.detail, systemImage: "exclamationmark.bubble")
                inspectorMetric("Severidad", readableLevel(alert.severity))
                inspectorMetric("Prioridad", readableLevel(alert.priority))
                inspectorMetric("Recuento", "\(alert.count)")
            } else {
                emptyRow("Alerta no encontrada")
            }
        case .pe(let id):
            if let item = snapshot.peItems.first(where: { $0.id == id }) {
                inspectorTitle(item.title, subtitle: item.detail, systemImage: "figure.run")
                inspectorMetric("Tipo", item.type)
                inspectorMetric("Severidad", readableLevel(item.severity))
            } else {
                emptyRow("Ítem EF no encontrado")
            }
        case .none:
            emptyRow("Selecciona una sesión, alerta o bloque EF.")
        }
    }

    @ViewBuilder
    private func inspectorHistory(snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            inspectorMetric("Sesiones hoy", "\(snapshot.todayCount)")
            inspectorMetric("Alertas activas", "\(snapshot.alertsCount)")
            inspectorMetric("Pendientes", "\(snapshot.pendingCount)")
            inspectorMetric("Próxima sesión", snapshot.nextSessionLabel)
        }
    }

    private var inspectorActions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                Task { await performPassList() }
            } label: {
                Label("Pasar lista", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)

            Button {
                Task { await performObservation() }
            } label: {
                Label("Nueva observación", systemImage: "note.text.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await performQuickEvaluation() }
            } label: {
                Label("Evaluación rápida", systemImage: "sparkles")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .disabled(actionClassId == nil)
    }

    private var systemSection: some View {
        MacPanel(title: "Sistema") {
            VStack(alignment: .leading, spacing: 8) {
                labeledRow("Plataforma", value: bootstrap.platformName)
                Divider()
                labeledRow("Base de datos", value: URL(fileURLWithPath: bootstrap.databasePath).lastPathComponent)
                Divider()
                labeledRow("Bridge", value: bridge.status)
            }
        }
    }

    private func filterPicker(_ title: String, options: [MacDashboardFilterOption], selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(options) { option in
                Label(option.label, systemImage: option.systemImage).tag(option.rawValue)
            }
        }
        .pickerStyle(.menu)
        .controlSize(.regular)
    }

    private func dashboardListText(_ title: String, _ values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(values.isEmpty ? "Sin datos disponibles" : values.joined(separator: ", "))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inspectorTitle(_ title: String, subtitle: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(MacAppStyle.infoTint)
                .frame(width: 32, height: 32)
                .background(MacAppStyle.infoTint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func inspectorMetric(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "Sin dato" : value)
                .font(.caption)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(MacAppStyle.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }

    private func emptyRow(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MacAppStyle.innerPadding)
            .background(MacAppStyle.subtleFill)
            .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }

    private func labeledRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .lineLimit(1)
        }
    }

    private var toolbarStateKey: String {
        let classKey = selectedClassId ?? -1
        let selectionKey: String
        switch inspectorSelection {
        case .session(let id): selectionKey = "session_\(id)"
        case .alert(let id): selectionKey = "alert_\(id)"
        case .pe(let id): selectionKey = "pe_\(id)"
        case .none: selectionKey = "none"
        }
        return "\(classKey)|\(modeRawValue)|\(severityFilter)|\(priorityFilter)|\(sessionStatusFilter)|\(selectionKey)|\(bridge.dashboardSnapshot != nil)"
    }

    private func syncToolbarActions() {
        onToolbarActionsChange(
            MacDashboardToolbarActions(
                modeRawValue: modeRawValue,
                canRunActions: actionClassId != nil,
                setMode: { modeRawValue = $0 },
                refresh: { Task { await applyFiltersAndReload() } },
                passList: { Task { await performPassList() } },
                observation: { Task { await performObservation() } }
            )
        )
    }

    private func triggerReload() {
        Task { await applyFiltersAndReload() }
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

    private func performPassList() async {
        guard let classId = actionClassId else { return }
        await bridge.performQuickAction(
            type: .passList,
            mode: mode.kotlinMode,
            classId: classId,
            attendanceStatus: "presente"
        )
    }

    private func performObservation() async {
        guard let classId = actionClassId else { return }
        await bridge.performQuickAction(
            type: .registerObservation,
            mode: mode.kotlinMode,
            classId: classId,
            note: "Observación registrada desde dashboard Mac"
        )
    }

    private func performQuickEvaluation() async {
        guard let classId = actionClassId else { return }
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

    private func levelTint(_ rawValue: String) -> Color {
        switch rawValue.lowercased() {
        case "high": return MacAppStyle.dangerTint
        case "medium": return MacAppStyle.warningTint
        case "low": return MacAppStyle.successTint
        default: return MacAppStyle.infoTint
        }
    }

    private func readableLevel(_ rawValue: String) -> String {
        switch rawValue.lowercased() {
        case "high": return "Alta"
        case "medium": return "Media"
        case "low": return "Baja"
        default: return rawValue.isEmpty ? "Sin dato" : rawValue
        }
    }

    private func readableSessionStatus(_ rawValue: String) -> String {
        switch rawValue.lowercased() {
        case "planned": return "Planificada"
        case "in_progress": return "En curso"
        case "completed": return "Completada"
        default: return rawValue.isEmpty ? "Sin dato" : rawValue
        }
    }

    private func openAgendaItem(_ item: AgendaItem) {
        let targets = item.navigationTargets
        guard !targets.isEmpty else { return }
        if targets.count == 1, let target = targets.first {
            activeSheet = .rubric(target: target)
        } else {
            activeSheet = .rubricPicker(item: item)
        }
    }
}

private enum MacDashboardMode: String {
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

private enum MacDashboardInspectorSelection: Hashable {
    case session(Int64)
    case alert(String)
    case pe(String)
}

private enum MacDashboardInspectorTab: String, CaseIterable, Identifiable {
    case detail = "Detalle"
    case history = "Historial"
    case actions = "Acciones"

    var id: String { rawValue }
}

private enum DashboardSheet: Identifiable {
    case rubric(target: AgendaNavigationTarget)
    case rubricPicker(item: AgendaItem)

    var id: String {
        switch self {
        case .rubric(let target):
            return "rubric-\(target.id)"
        case .rubricPicker(let item):
            return "picker-\(item.id)"
        }
    }
}

private struct MacDashboardFilterOption: Identifiable, Hashable {
    let rawValue: String
    let label: String
    let systemImage: String

    var id: String { rawValue }
}

private enum MacDashboardFilterOptions {
    static let severity: [MacDashboardFilterOption] = [
        .init(rawValue: "", label: "Todas", systemImage: "line.3.horizontal.decrease.circle"),
        .init(rawValue: "high", label: "Alta", systemImage: "exclamationmark.triangle.fill"),
        .init(rawValue: "medium", label: "Media", systemImage: "exclamationmark.circle.fill"),
        .init(rawValue: "low", label: "Baja", systemImage: "checkmark.circle.fill")
    ]

    static let priority: [MacDashboardFilterOption] = [
        .init(rawValue: "", label: "Todas", systemImage: "line.3.horizontal.decrease.circle"),
        .init(rawValue: "high", label: "Alta", systemImage: "flag.fill"),
        .init(rawValue: "medium", label: "Media", systemImage: "flag"),
        .init(rawValue: "low", label: "Baja", systemImage: "flag.slash")
    ]

    static let sessionStatus: [MacDashboardFilterOption] = [
        .init(rawValue: "", label: "Todas", systemImage: "calendar"),
        .init(rawValue: "planned", label: "Planificada", systemImage: "calendar.badge.clock"),
        .init(rawValue: "in_progress", label: "En curso", systemImage: "play.circle.fill"),
        .init(rawValue: "completed", label: "Completada", systemImage: "checkmark.circle.fill")
    ]
}

private struct MacPanel<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MacSectionHeader(title: title)
            content
        }
        .padding(MacAppStyle.innerPadding)
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }
}

private struct MacHoverRow<Content: View>: View {
    @State private var isHovering = false
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(MacAppStyle.innerPadding)
            .background(isHovering ? MacAppStyle.infoTint.opacity(0.08) : MacAppStyle.subtleFill)
            .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                    .stroke(isHovering ? MacAppStyle.infoTint.opacity(0.35) : Color.clear, lineWidth: 1)
            }
            .onHover { isHovering = $0 }
    }
}
