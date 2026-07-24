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

private enum DashboardLoadPhase: Int {
    case shell
    case metrics
    case lists
    case ai

    func includes(_ phase: DashboardLoadPhase) -> Bool {
        rawValue >= phase.rawValue
    }
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
    let bridge: KmpBridge
    @ObservedObject var dashboardStore: DashboardBridgeStore
    @EnvironmentObject private var layoutState: WorkspaceLayoutState
    @Environment(\.colorScheme) private var colorScheme
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    @AppStorage("dashboard_operational_mode") private var modeRawValue: String = OperationalDashboardMode.office.rawValue
    @State private var severityFilter: DashboardFilterOption = .all
    @State private var priorityFilter: DashboardFilterOption = .all
    @State private var sessionStatusFilter: DashboardSessionFilterOption = .all
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @State private var inspectorSelection: DashboardInspectorSelection? = nil
    @State private var isInspectorPresented = false
    @State private var isQuickEvaluationPresented = false
    @State private var classTrends: KmpBridge.AITrendsSnapshot? = nil
    @State private var isLoadingClassTrends = false
    @State private var classTrendsLoadFailed = false
    @State private var proactiveInsights: [DashboardProactiveInsight] = []
    @State private var aiBriefing: TeachingAssistantDraft? = nil
    @State private var aiBriefingState: DashboardAIBriefingState = .deterministic
    @State private var activeAIBriefingKey: DashboardAIBriefingCacheKey?
    @State private var dashboardReloadTask: Task<Void, Never>? = nil
    @State private var dashboardReloadGeneration = 0
    @State private var loadPhase: DashboardLoadPhase = .shell

    private let teachingAssistantService = AppleFoundationTeachingAssistantService()

    init(
        bridge: KmpBridge,
        dashboardStore: DashboardBridgeStore,
        selectedClassId: Binding<Int64?>,
        onOpenModule: @escaping (AppWorkspaceModule, Int64?, Int64?) -> Void = { _, _, _ in }
    ) {
        self.bridge = bridge
        self.dashboardStore = dashboardStore
        self._selectedClassId = selectedClassId
        self.onOpenModule = onOpenModule
    }

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
        VStack(spacing: 0) {
            dashboardHeader
            dashboardContent
        }
        .animation(uiFeatureFlags.inspectorAnimation(presented: isInspectorPresented), value: isInspectorPresented)
        .background(appPageBackground(for: colorScheme).ignoresSafeArea())
        .sheet(isPresented: $isQuickEvaluationPresented) {
            DashboardQuickEvaluationSheet(
                bridge: bridge,
                initialClassId: dashboardActionClassId,
                mode: mode.kotlinMode
            )
            #if os(iOS)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .task {
            await bridge.ensureClassesLoaded()
            if selectedClassId == nil {
                selectedClassId = dashboardStore.classes.first?.id
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
            dashboardReloadTask?.cancel()
            dashboardReloadTask = nil
            layoutState.clearDashboardToolbar()
        }
        .refreshable {
            cancelPendingDashboardReload()
            await applyFiltersAndReload()
            await bridge.pullMissingSyncChanges()
        }
    }

    private func triggerDashboardReload() {
        dashboardReloadTask?.cancel()
        dashboardReloadGeneration += 1
        let generation = dashboardReloadGeneration
        dashboardReloadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, generation == dashboardReloadGeneration else { return }
            await applyFiltersAndReload(expectedReloadGeneration: generation)
        }
    }

    private func cancelPendingDashboardReload() {
        dashboardReloadTask?.cancel()
        dashboardReloadTask = nil
        dashboardReloadGeneration += 1
    }

    private func handleInspectorSelectionChange() {
        if inspectorSelection == nil {
            isInspectorPresented = false
        }
        syncToolbarState()
    }

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 32) {
                    dashboardHeaderTitle

                    Spacer(minLength: 16)

                    dashboardHeaderControls
                }

                VStack(alignment: .leading, spacing: 16) {
                    dashboardHeaderTitle
                    dashboardHeaderControls
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .background(appMutedCardBackground(for: colorScheme))
    }

    private var dashboardHeaderTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hoy")
                .font(.system(size: 26, weight: .black, design: .rounded))
            Text("\(selectedClassLabel) · Dashboard y radar docente")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    private var dashboardHeaderControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                dashboardPrimaryActions
                dashboardModeAndExportControls
            }

            VStack(alignment: .leading, spacing: 16) {
                dashboardPrimaryActions
                dashboardModeAndExportControls
            }
        }
    }

    private var dashboardPrimaryActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                dashboardPrimaryActionButtons(labelsVisible: true)
            }

            HStack(spacing: 8) {
                dashboardPrimaryActionButtons(labelsVisible: false)
            }
        }
        .controlSize(.regular)
    }

    @ViewBuilder
    private func dashboardPrimaryActionButtons(labelsVisible: Bool) -> some View {
        Button {
            Task { await performPassList() }
        } label: {
            if labelsVisible {
                Label("Pasar lista", systemImage: "checkmark.circle")
            } else {
                Label("Pasar lista", systemImage: "checkmark.circle")
                    .labelStyle(.iconOnly)
            }
        }
        .buttonStyle(.bordered)
        .disabled(dashboardActionClassId == nil)
        .accessibilityLabel("Pasar lista")

        Button {
            Task { await performObservation() }
        } label: {
            if labelsVisible {
                Label("Observación", systemImage: "note.text.badge.plus")
            } else {
                Label("Observación", systemImage: "note.text.badge.plus")
                    .labelStyle(.iconOnly)
            }
        }
        .buttonStyle(.bordered)
        .disabled(dashboardActionClassId == nil)
        .accessibilityLabel("Nueva observación")

        Button {
            performQuickEvaluation()
        } label: {
            if labelsVisible {
                Label("Evaluar", systemImage: "checklist")
            } else {
                Label("Evaluar", systemImage: "checklist")
                    .labelStyle(.iconOnly)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(dashboardActionClassId == nil)
        .accessibilityLabel("Evaluar")
    }

    private var dashboardModeAndExportControls: some View {
        HStack(spacing: 16) {
            if let snapshot = dashboardStore.dashboardSnapshot {
                dashboardExportMenu(snapshot: snapshot)
            }

            Picker("Contexto", selection: $modeRawValue) {
                Text("Clase").tag(OperationalDashboardMode.classroom.rawValue)
                Text("Despacho").tag(OperationalDashboardMode.office.rawValue)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
        }
    }

    private var dashboardContent: some View {
        ScrollView {
            if let snapshot = dashboardStore.dashboardSnapshot {
                dashboardLoadedContent(snapshot: snapshot)
                .padding(EvaluationDesign.screenPadding)
            } else {
                dashboardSkeletonContent
                    .padding(EvaluationDesign.screenPadding)
            }
        }
    }

    @ViewBuilder
    private func dashboardLoadedContent(snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: EvaluationDesign.sectionSpacing) {
            // 1. Hoy — qué requiere atención inmediata
            dashboardTodayBlock(snapshot: snapshot)

            // 2. Alertas — accionables, priorizadas
            if loadPhase.includes(.lists) {
                dashboardAlertsSection(snapshot: snapshot)
            } else {
                dashboardListSkeleton
            }

            if isInspectorPresented {
                dashboardInspector
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // 3. KPIs — contexto cuantitativo
            dashboardKpiRow(snapshot: snapshot)

            dashboardFilterChips

            // 4. Accesos rápidos — iniciar una tarea
            dashboardQuickEvalBlock(snapshot: snapshot)

            // 5. Insight proactivo — una única tarjeta, descartable
            if loadPhase.includes(.ai) {
                dashboardProactiveRadar(snapshot: snapshot)
            } else {
                dashboardRadarSkeleton
            }

            // 6. Contexto secundario — agenda y estado del sistema
            dashboardSecondaryGrid(snapshot: snapshot)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: loadPhase.rawValue)
    }

    @ViewBuilder
    private func dashboardAlertsSection(snapshot: DashboardSnapshot) -> some View {
        if isCompactWidth {
            VStack(spacing: EvaluationDesign.cardSpacing) {
                dashboardPendingBlock(snapshot: snapshot)
                dashboardRiskBlock(snapshot: snapshot)
            }
        } else {
            HStack(alignment: .top, spacing: EvaluationDesign.cardSpacing) {
                dashboardPendingBlock(snapshot: snapshot)
                dashboardRiskBlock(snapshot: snapshot)
            }
        }
    }

    @ViewBuilder
    private func dashboardSecondaryGrid(snapshot: DashboardSnapshot) -> some View {
        let blocks: [DashboardBlock] = mode == .classroom
            ? [.groupSummary, .agenda, .physicalEducation, .lomloeAudit, .system]
            : [.lomloeAudit, .groupSummary, .agenda, .physicalEducation, .system]

        VStack(spacing: EvaluationDesign.cardSpacing) {
            ForEach(blocks, id: \.self) { block in
                switch block {
                case .groupSummary:
                    dashboardGroupSummaryBlock(snapshot: snapshot)
                case .agenda:
                    dashboardAgendaBlock(snapshot: snapshot)
                case .physicalEducation:
                    dashboardPEBlock(snapshot: snapshot)
                case .lomloeAudit:
                    dashboardLomloeAuditBlock(snapshot: snapshot)
                case .system:
                    dashboardSystemBlock()
                case .today, .pending, .risk, .alerts, .quickEvaluation:
                    EmptyView()
                }
            }
        }
    }

    private var dashboardSkeletonContent: some View {
        VStack(alignment: .leading, spacing: EvaluationDesign.sectionSpacing) {
            dashboardRadarSkeleton
            dashboardListSkeleton
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Cargando dashboard operativo")
    }

    private var dashboardInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Label("Detalle", systemImage: "sidebar.right")
                    .font(.headline)
                Spacer()
                Button {
                    inspectorSelection = nil
                    isInspectorPresented = false
                } label: {
                    Label("Cerrar", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cerrar detalle")
            }

            if let snapshot = dashboardStore.dashboardSnapshot {
                switch inspectorSelection {
                case .session(let id):
                    if let item = snapshot.todaySessions.first(where: { $0.id == id }) {
                        Text(item.groupName).font(.headline)
                        Text(item.didacticUnit)
                        Text("Horario: \(item.timeLabel)")
                        Text("Espacio: \(item.space)")
                        Text("Estado: \(dashboardSessionStatusLabel(item.sessionStatus))")
                        inspectorNavigationActions {
                            let classId = item.classId?.int64Value
                            inspectorNavigationButton(title: "Pasar lista", systemImage: "checkmark.circle") {
                                onOpenModule(.attendance, classId, nil)
                            }
                            inspectorNavigationButton(title: "Abrir cuaderno", systemImage: "book.closed") {
                                onOpenModule(.notebook, classId, nil)
                            }
                        }
                    } else {
                        Text("Sesión no encontrada")
                    }
                case .alert(let id):
                    if let alert = snapshot.alerts.first(where: { $0.id == id }) {
                        Text(alert.title).font(.headline)
                        Text(alert.detail)
                        Text("Severidad: \(dashboardFilterLabel(alert.severity))")
                        Text("Prioridad: \(dashboardFilterLabel(alert.priority))")
                        inspectorNavigationActions {
                            let targets = agendaNavigationTargets(for: alert, snapshot: snapshot)
                            if targets.isEmpty {
                                if let studentId = alert.studentId?.int64Value {
                                    inspectorNavigationButton(title: "Ver ficha del alumno", systemImage: "person.crop.circle") {
                                        onOpenModule(.students, alert.classId?.int64Value, studentId)
                                    }
                                    inspectorNavigationButton(title: "Abrir cuaderno", systemImage: "book.closed") {
                                        onOpenModule(.notebook, alert.classId?.int64Value, studentId)
                                    }
                                } else if let classId = alert.classId?.int64Value {
                                    inspectorNavigationButton(title: "Abrir cuaderno", systemImage: "book.closed") {
                                        onOpenModule(.notebook, classId, nil)
                                    }
                                }
                            } else {
                                ForEach(targets, id: \.id) { target in
                                    inspectorNavigationButton(title: "Evaluar: \(target.label)", systemImage: "checklist") {
                                        onOpenModule(.rubrics, target.classId?.int64Value, target.studentId?.int64Value)
                                    }
                                }
                            }
                        }
                    } else {
                        Text("Alerta no encontrada")
                    }
                case .pe(let id):
                    if let item = snapshot.peItems.first(where: { $0.id == id }) {
                        Text(item.title).font(.headline)
                        Text(item.detail)
                        Text("Severidad: \(dashboardFilterLabel(item.severity))")
                        if let destination = peDestination(for: item) {
                            inspectorNavigationActions {
                                inspectorNavigationButton(title: "Ir a Educación Física", systemImage: "figure.run") {
                                    onOpenModule(destination, item.classId?.int64Value, nil)
                                }
                            }
                        }
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
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(IOSAppStyle.cardBorder, lineWidth: 1)
        )
        .shadow(color: IOSAppStyle.shadow, radius: 12, x: 0, y: 4)
    }

    @ViewBuilder
    private func inspectorNavigationActions<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(.top, 4)
    }

    private func inspectorNavigationButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .buttonStyle(.bordered)
    }

    /// Empareja una alerta con el `AgendaItem` ("recordatorio") que el backend
    /// genera a partir de ella para transportar sus `navigationTargets`
    /// (rúbrica + alumno pendientes de evaluar). El backend no enlaza ambos
    /// por id, así que el emparejamiento se hace por contenido (mismo grupo,
    /// título y detalle), que es información suficiente porque el
    /// `AgendaItem` "recordatorio" siempre se construye 1:1 desde la alerta.
    private func agendaNavigationTargets(for alert: AlertItem, snapshot: DashboardSnapshot) -> [AgendaNavigationTarget] {
        snapshot.agendaItems.first {
            $0.type == "recordatorio"
                && $0.title == alert.title
                && $0.subtitle == alert.detail
                && $0.classId?.int64Value == alert.classId?.int64Value
        }?.navigationTargets ?? []
    }

    private func navigateAgendaItem(_ item: AgendaItem) {
        if let target = item.navigationTargets.first {
            onOpenModule(.rubrics, target.classId?.int64Value, target.studentId?.int64Value)
            return
        }
        let classId = item.classId?.int64Value
        switch item.type {
        case "sesion":
            onOpenModule(.attendance, classId, nil)
        case "revision":
            onOpenModule(.planner, classId, nil)
        default:
            guard let classId else { return }
            onOpenModule(.notebook, classId, nil)
        }
    }

    /// Los `PEOperationalItem` del backend nunca llevan `classId` (se agregan
    /// a nivel de todas las clases de EF), así que la navegación solo puede
    /// llevar al módulo relevante, no a un grupo o alumno concretos.
    private func peDestination(for item: PEOperationalItem) -> AppWorkspaceModule? {
        switch item.type {
        case "incidencias_fisicas":
            return .peIncidents
        case "exentos_adaptacion":
            return .students
        case "prueba_rubrica_activa":
            return .peRubrics
        case "material_hoy":
            return .peMaterial
        default:
            return nil
        }
    }

    private var selectedClassLabel: String {
        guard let selectedClassId,
              let schoolClass = dashboardStore.classes.first(where: { $0.id == selectedClassId }) else {
            return "Clase global activa"
        }
        return "\(schoolClass.name) · \(schoolClass.course)º"
    }

    private var dashboardActionClassId: Int64? {
        selectedClassId ?? dashboardStore.classes.first?.id
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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 16) {
                dashboardFilterPicker(title: "Severidad", selection: $severityFilter, options: DashboardFilterOption.allCases)
                dashboardFilterPicker(title: "Prioridad", selection: $priorityFilter, options: DashboardFilterOption.allCases)
                dashboardSessionFilterPicker(title: "Sesiones", selection: $sessionStatusFilter, options: DashboardSessionFilterOption.allCases)
            }

            VStack(alignment: .leading, spacing: 8) {
                dashboardFilterPicker(title: "Severidad", selection: $severityFilter, options: DashboardFilterOption.allCases)
                dashboardFilterPicker(title: "Prioridad", selection: $priorityFilter, options: DashboardFilterOption.allCases)
                dashboardSessionFilterPicker(title: "Sesiones", selection: $sessionStatusFilter, options: DashboardSessionFilterOption.allCases)
            }
        }
    }

    @ViewBuilder
    private func dashboardKpiRow(snapshot: DashboardSnapshot) -> some View {
        HStack(spacing: 12) {
            dashboardKpiCard(title: "Hoy", value: "\(snapshot.todayCount)", isNumeric: true)
            dashboardKpiCard(title: "Alertas", value: "\(snapshot.alertsCount)", isNumeric: true)
            dashboardKpiCard(title: "Pendientes", value: "\(snapshot.pendingCount)", isNumeric: true)
            dashboardKpiCard(title: "Próxima sesión", value: snapshot.nextSessionLabel, isNumeric: false)
        }
    }

    @ViewBuilder
    private func dashboardKpiCard(title: String, value: String, isNumeric: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            if isNumeric {
                Text(value)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
            } else {
                Text(value).font(.headline).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(appCardBackground(for: colorScheme))
        .cornerRadius(12)
    }

    private var dashboardMetricsSkeleton: some View {
        HStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                        .frame(width: index == 3 ? 96 : 56, height: 10)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: index == 3 ? 132 : 64, height: 18)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(appCardBackground(for: colorScheme))
                .cornerRadius(12)
            }
        }
        .redacted(reason: .placeholder)
    }

    private var dashboardRadarSkeleton: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 128, height: 14)
                Spacer()
                ProgressView()
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: 180, height: 10)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(maxWidth: .infinity, minHeight: 10, maxHeight: 10)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 240, height: 10)
            }
            .padding(16)
            .background(EvaluationDesign.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(IOSAppStyle.cardBorder, lineWidth: 1)
        )
        .shadow(color: IOSAppStyle.shadow, radius: 12, x: 0, y: 4)
        .redacted(reason: .placeholder)
    }

    private var dashboardListSkeleton: some View {
        VStack(spacing: EvaluationDesign.cardSpacing) {
            dashboardSkeletonBlock(rowCount: 3)

            let columns = [
                GridItem(.flexible(), spacing: EvaluationDesign.cardSpacing, alignment: .top),
                GridItem(.flexible(), spacing: EvaluationDesign.cardSpacing, alignment: .top),
                GridItem(.flexible(), spacing: EvaluationDesign.cardSpacing, alignment: .top)
            ]

            if isCompactWidth {
                VStack(spacing: EvaluationDesign.cardSpacing) {
                    dashboardSkeletonBlock(rowCount: 3)
                    dashboardSkeletonBlock(rowCount: 3)
                    dashboardSkeletonBlock(rowCount: 3)
                }
            } else {
                LazyVGrid(columns: columns, alignment: .center, spacing: EvaluationDesign.cardSpacing) {
                    dashboardSkeletonBlock(rowCount: 3)
                    dashboardSkeletonBlock(rowCount: 3)
                    dashboardSkeletonBlock(rowCount: 3)
                }
            }
        }
        .redacted(reason: .placeholder)
    }

    private func dashboardSkeletonBlock(rowCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 112, height: 14)
                Spacer()
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 28, height: 12)
            }

            ForEach(0..<rowCount, id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                        .frame(width: index == 0 ? 180 : 140, height: 12)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                        .frame(maxWidth: .infinity, minHeight: 10, maxHeight: 10)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(appMutedCardBackground(for: colorScheme))
                .cornerRadius(EvaluationDesign.pillRadius)
            }
        }
        .padding(EvaluationDesign.cardSpacing)
        .background(.regularMaterial)
        .cornerRadius(EvaluationDesign.innerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.06), lineWidth: 1)
        )
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

    @ViewBuilder
    private func dashboardIPadDailyCockpit(snapshot: DashboardSnapshot) -> some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                dashboardTodayBlock(snapshot: snapshot)
                    .frame(maxWidth: .infinity, alignment: .top)
                dashboardQuickEvalBlock(snapshot: snapshot)
                    .frame(width: 320, alignment: .top)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 16, alignment: .top),
                    GridItem(.flexible(), spacing: 16, alignment: .top),
                    GridItem(.flexible(), spacing: 16, alignment: .top)
                ],
                alignment: .center,
                spacing: 16
            ) {
                dashboardPendingBlock(snapshot: snapshot)
                dashboardRiskBlock(snapshot: snapshot)
                dashboardSystemBlock()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cockpit diario de iPad")
    }

    @ViewBuilder
    private func dashboardProactiveRadar(snapshot: DashboardSnapshot) -> some View {
        DashboardProactiveInsightCard(
            insights: proactiveInsights,
            aiBriefing: aiBriefing,
            aiBriefingState: aiBriefingState,
            actionAvailability: { action in
                proactiveActionAvailable(action, snapshot: snapshot)
            },
            onAction: { action in
                handleProactiveAction(action, snapshot: snapshot)
            }
        )
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
                dashboardActionRow(
                    title: item.title,
                    subtitle: item.subtitle,
                    systemImage: "calendar.badge.exclamationmark",
                    tint: .orange
                ) {
                    navigateAgendaItem(item)
                }
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
                VStack(alignment: .leading, spacing: 6) {
                    dashboardActionRow(
                        title: riskTitle(alert),
                        subtitle: alert.detail,
                        systemImage: riskIcon(alert),
                        tint: riskTint(alert.severity)
                    ) {
                        inspectorSelection = .alert(alert.id)
                        isInspectorPresented = true
                    }
                    if let recommendation = DashboardRecommendations.action(
                        type: alert.type, title: alert.title, detail: alert.detail
                    ) {
                        dashboardRecommendationLine(recommendation)
                    }
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
                title: dashboardStore.pairedSyncHost == nil ? "Sync LAN inactivo" : "Sync LAN activo",
                subtitle: dashboardStore.syncPendingChanges == 0 ? dashboardStore.syncStatusMessage : "\(dashboardStore.syncPendingChanges) cambios pendientes",
                systemImage: "arrow.triangle.2.circlepath",
                tint: dashboardStore.syncPendingChanges == 0 && dashboardStore.pairedSyncHost != nil ? .green : .orange
            )
            dashboardStaticRow(
                title: "Última sync",
                subtitle: dashboardStore.syncLastRunAt.map(shortSystemDate) ?? "Sin registro",
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
                let isNavigable = !item.navigationTargets.isEmpty || item.classId != nil
                Button {
                    navigateAgendaItem(item)
                } label: {
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
                        if isNavigable {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
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
                .disabled(!isNavigable)
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
                    .accessibilityAddTraits(selection.wrappedValue == option ? .isSelected : [])
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
                    .accessibilityAddTraits(selection.wrappedValue == option ? .isSelected : [])
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

    /// El "qué hacer" que acompaña a una alerta de riesgo (B-4). Deriva de la
    /// propia alerta; no es una acción con estado, solo una guía visible.
    private func dashboardRecommendationLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.yellow)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
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
            inspectorAvailable: dashboardStore.dashboardSnapshot != nil,
            isInspectorPresented: isInspectorPresented,
            actionsAvailable: dashboardActionClassId != nil,
            onToggleInspector: {
                toggleInspector()
            },
            onRefresh: {
                cancelPendingDashboardReload()
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
        guard let snapshot = dashboardStore.dashboardSnapshot else { return }
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

    private func applyFiltersAndReload(expectedReloadGeneration: Int? = nil) async {
        if let expectedReloadGeneration, expectedReloadGeneration != dashboardReloadGeneration {
            return
        }
        loadPhase = .shell
        proactiveInsights = []
        aiBriefing = nil
        aiBriefingState = .deterministic
        bridge.updateDashboardFilters(
            classId: selectedClassId,
            severity: severityFilter.rawValue,
            priority: priorityFilter.rawValue,
            sessionStatus: sessionStatusFilter.rawValue
        )
        await bridge.refreshDashboard(mode: mode.kotlinMode)
        guard !Task.isCancelled else { return }
        if let expectedReloadGeneration, expectedReloadGeneration != dashboardReloadGeneration {
            return
        }
        
        // Postergar la carga pesada de tendencias e IA brevemente para dar prioridad a la animación de entrada
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard !Task.isCancelled else { return }
        if let expectedReloadGeneration, expectedReloadGeneration != dashboardReloadGeneration {
            return
        }
        
        loadPhase = dashboardStore.dashboardSnapshot == nil ? .shell : .metrics
        await loadClassTrends()
        guard !Task.isCancelled else { return }
        if let expectedReloadGeneration, expectedReloadGeneration != dashboardReloadGeneration {
            return
        }
        loadPhase = dashboardStore.dashboardSnapshot == nil ? .shell : .lists
        rebuildProactiveRadar()
        loadPhase = dashboardStore.dashboardSnapshot == nil ? .shell : .ai
    }

    private func rebuildProactiveRadar() {
        guard let snapshot = dashboardStore.dashboardSnapshot else {
            proactiveInsights = []
            aiBriefing = nil
            aiBriefingState = .deterministic
            return
        }
        proactiveInsights = DashboardProactiveInsightEngine.build(
            snapshot: snapshot,
            trends: classTrends,
            context: DashboardProactiveContext(
                className: selectedClassLabel,
                modeLabel: mode == .classroom ? "Clase" : "Despacho",
                syncPendingChanges: dashboardStore.syncPendingChanges,
                pairedSyncHost: dashboardStore.pairedSyncHost,
                platformName: "iOS"
            ),
            limit: 5
        )
        loadAIBriefingIfNeeded(snapshot: snapshot)
    }

    private func loadAIBriefingIfNeeded(snapshot: DashboardSnapshot) {
        let key = aiBriefingKey(snapshot: snapshot)
        activeAIBriefingKey = key
        if let cached = DashboardAIBriefingCache.shared.cachedDraft(for: key) {
            aiBriefing = cached
            aiBriefingState = .cached
            return
        }
        aiBriefing = DashboardProactiveInsightEngine.fallbackBriefing(from: proactiveInsights, className: selectedClassLabel)
        aiBriefingState = .updating
        guard DashboardAIBriefingCache.shared.beginRefresh(for: key) else { return }
        let classId = selectedClassId
        Task { @MainActor in
            defer { DashboardAIBriefingCache.shared.finishRefresh(for: key) }
            do {
                let draft = try await teachingAssistantService.generateDailyBriefingDraft(
                    bridge: bridge,
                    classId: classId,
                    audience: .docente,
                    tone: .breve,
                    customPrompt: nil
                )
                guard activeAIBriefingKey == key else { return }
                DashboardAIBriefingCache.shared.store(draft, for: key)
                aiBriefing = draft
                aiBriefingState = .fresh
            } catch {
                guard activeAIBriefingKey == key else { return }
                let fallback = DashboardProactiveInsightEngine.fallbackBriefing(from: proactiveInsights, className: selectedClassLabel)
                if let fallback {
                    aiBriefing = fallback
                }
                aiBriefingState = .failed
            }
        }
    }

    private func aiBriefingKey(snapshot: DashboardSnapshot) -> DashboardAIBriefingCacheKey {
        DashboardAIBriefingCacheKey(classId: selectedClassId, scope: "iOS-\(modeRawValue)")
    }

    private func proactiveActionAvailable(_ action: DashboardProactiveAction, snapshot: DashboardSnapshot) -> Bool {
        switch action {
        case .passList:
            return dashboardActionClassId != nil
        case .quickEvaluation, .evaluatePending:
            return dashboardActionClassId != nil
        case .openInspector:
            return !snapshot.todaySessions.isEmpty || !snapshot.alerts.isEmpty || !snapshot.peItems.isEmpty
        case .reviewPhysicalEducation:
            return !snapshot.peItems.isEmpty
        case .reviewSystem:
            return false
        case .openNotebook, .openPlanner, .openReports:
            return false
        }
    }

    private func handleProactiveAction(_ action: DashboardProactiveAction, snapshot: DashboardSnapshot) {
        switch action {
        case .passList:
            Task { await performPassList() }
        case .quickEvaluation, .evaluatePending:
            performQuickEvaluation()
        case .openInspector:
            openInspectorForCurrentSnapshot()
        case .reviewPhysicalEducation:
            if let firstPE = snapshot.peItems.first {
                inspectorSelection = .pe(firstPE.id)
                isInspectorPresented = true
            }
        case .reviewSystem, .openNotebook, .openPlanner, .openReports:
            break
        }
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
            } else if classTrendsLoadFailed {
                HStack(spacing: 10) {
                    Label("No se pudo cargar la auditoría de este grupo.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(IOSAppStyle.warning)
                    Spacer()
                    Button("Reintentar") {
                        Task { await loadClassTrends() }
                    }
                    .font(.system(size: 13, weight: .semibold))
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
            classTrendsLoadFailed = false
            return
        }
        isLoadingClassTrends = true
        classTrendsLoadFailed = false
        do {
            classTrends = try await bridge.getAITrendsAndMetrics(classId: classId, studentId: nil)
        } catch {
            print("Error loading class trends: \(error)")
            classTrendsLoadFailed = true
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
        DashboardEvaluationSheetScaffold(
            title: "Evaluación rápida",
            subtitle: "Registra una nota puntual sin salir del cockpit diario.",
            systemImage: "square.and.pencil",
            canSave: canSave,
            isSaving: isSaving,
            onCancel: { dismiss() },
            onSave: { Task { await save() } }
        ) {
            PremiumCard.section(title: "Contexto", systemImage: "person.crop.rectangle.stack") {
                VStack(spacing: 14) {
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
                .pickerStyle(.menu)
            }

            PremiumCard.section(title: "Nota", systemImage: "number.square") {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("0-10", text: $scoreText)
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(EvaluationDesign.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(EvaluationDesign.border, lineWidth: 1)
                        }
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif

                    TextField("Observación opcional", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(EvaluationDesign.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(EvaluationDesign.border, lineWidth: 1)
                        }
                }
            }

            if notebookColumns.isEmpty {
                DashboardEvaluationNotice(
                    systemImage: "exclamationmark.triangle",
                    text: "No hay columnas de evaluación cargadas para esta clase. Abre o prepara el cuaderno antes de guardar desde el dashboard.",
                    tint: .orange
                )
            }

            if let message {
                DashboardEvaluationNotice(
                    systemImage: "info.circle",
                    text: message,
                    tint: EvaluationDesign.accent
                )
            }
        }
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

private struct DashboardEvaluationSheetScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let canSave: Bool
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    DashboardEvaluationHero(title: title, subtitle: subtitle, systemImage: systemImage)
                    content
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(EvaluationDesign.surface.opacity(0.45))
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Guardando..." : "Confirmar", action: onSave)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 640, maxWidth: 720, minHeight: 560, idealHeight: 640)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }
}

private struct DashboardEvaluationHero: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(EvaluationDesign.accent)
                .frame(width: 48, height: 48)
                .background(EvaluationDesign.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(EvaluationDesign.border, lineWidth: 1)
        }
    }
}

private struct DashboardEvaluationNotice: View {
    let systemImage: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EvaluationDesign.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(EvaluationDesign.border, lineWidth: 1)
        }
    }
}

// MARK: - Premium Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .appInteractiveHighlight()
    }
}
