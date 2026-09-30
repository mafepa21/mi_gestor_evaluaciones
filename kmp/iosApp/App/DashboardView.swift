import SwiftUI
import MiGestorKit

// MARK: - Dashboard (iPad / iPadOS / Catalyst)
//
// Este archivo es solo la carcasa: estado, recarga y navegación. Lo que se ve
// vive en archivos propios:
// - DashboardStyle.swift: tokens, tarjeta, cristal de controles, movimiento.
// - DashboardPresentation.swift: modelo de presentación (una vez por snapshot).
// - DashboardHeaderView.swift: saludo, selector de modo, exportar, sync.
// - DashboardDispatchView.swift: Despacho en 3 franjas (AHORA, ATENCIÓN, CONTEXTO).
// - DashboardClassroomView.swift: modo Clase.
// - DashboardStateViews.swift: esqueletos, error de red, sync en curso.
// - DashboardInspectorContent.swift: detalle en el inspector nativo.

struct DashboardView: View {
    let bridge: KmpBridge
    @ObservedObject var dashboardStore: DashboardBridgeStore
    @EnvironmentObject private var layoutState: WorkspaceLayoutState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    @AppStorage("dashboard_mode_preference") private var modeRawValue: String = DashboardModePreference.auto.rawValue

    // Presentación (todo local: filtrar o plegar no llama a KMP).
    @State private var presentationCache = DashboardPresentationCache()
    @State private var hiddenKinds: Set<DashboardAttentionKind> = []
    @State private var showAllAttention = false
    @State private var openContext: Set<DashboardContextCard> = [.agenda]

    // Inspector y hojas.
    @State private var inspectorSelection: DashboardInspectorSelection? = nil
    @State private var isInspectorPresented = false
    @State private var isQuickEvaluationPresented = false
    @State private var isObservationPresented = false

    // Análisis (briefing de una frase).
    @State private var classTrends: KmpBridge.AITrendsSnapshot? = nil
    @State private var classTrendsLoadFailed = false
    @State private var proactiveInsights: [DashboardProactiveInsight] = []
    @State private var aiBriefing: TeachingAssistantDraft? = nil
    @State private var aiBriefingState: DashboardAIBriefingState = .deterministic
    @State private var activeAIBriefingKey: DashboardAIBriefingCacheKey?

    // Carga.
    @State private var dashboardReloadTask: Task<Void, Never>? = nil
    @State private var dashboardReloadGeneration = 0
    @State private var trendsTask: Task<Void, Never>? = nil
    @State private var aiBriefingTask: Task<Void, Never>? = nil
    @State private var isRefreshing = false
    @State private var loadFailed = false
    @State private var lastLoadedAt: Date? = nil

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

    // MARK: Modo y anchura

    private var modePreference: DashboardModePreference {
        DashboardModePreference(rawValue: modeRawValue) ?? .auto
    }

    /// El modo efectivo sale del horario cuando la preferencia es `auto`. Sin
    /// contexto todavía (primera carga) cae a Despacho, que es el estado
    /// seguro: enseña de más, no de menos.
    private var mode: DashboardMode {
        modePreference.resolved(for: dashboardStore.dashboardSnapshot?.currentContext)
    }

    private var isClassroomMode: Bool { mode == .classroom }

    private var isCompactWidth: Bool {
#if os(iOS)
        horizontalSizeClass == .compact
#else
        false
#endif
    }

    /// Una columna con anchura compacta o con Dynamic Type de accesibilidad.
    private var singleColumn: Bool {
        isCompactWidth || dynamicTypeSize.isAccessibilitySize
    }

    private var snapshotIdentity: ObjectIdentifier? {
        dashboardStore.dashboardSnapshot.map { ObjectIdentifier($0) }
    }

    // MARK: Cuerpo

    var body: some View {
        dashboardScroll
            .background { DashboardBackground() }
            .inspector(isPresented: $isInspectorPresented) {
                DashboardInspectorContent(
                    snapshot: dashboardStore.dashboardSnapshot,
                    selection: inspectorSelection,
                    onOpenModule: onOpenModule,
                    onNewObservation: performObservation,
                    onClose: closeInspector
                )
                .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
            }
            .sheet(isPresented: $isQuickEvaluationPresented) {
                DashboardQuickEvaluationSheet(
                    bridge: bridge,
                    initialClassId: dashboardActionClassId,
                    mode: mode
                )
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
            }
            .sheet(isPresented: $isObservationPresented) {
                DashboardObservationSheet(bridge: bridge, initialClassId: dashboardActionClassId)
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
                await reloadDashboard()
            }
            .onAppear(perform: scheduleToolbarStateSync)
            .appOnChange(of: selectedClassId) { _ in triggerDashboardReload() }
            // El modo efectivo decide el alcance del snapshot (Clase = solo el
            // grupo en curso); si cambia, se recarga con contenido a la vista.
            .appOnChange(of: isClassroomMode) { _ in triggerDashboardReload() }
            .appOnChange(of: snapshotIdentity) { _ in snapshotDidChange() }
            .appOnChange(of: inspectorSelection) { _ in scheduleInspectorSelectionSync() }
            .appOnChange(of: isInspectorPresented) { _ in scheduleToolbarStateSync() }
            .appOnChange(of: toolbarStateKey) { _ in scheduleToolbarStateSync() }
            .onDisappear {
                dashboardReloadTask?.cancel()
                dashboardReloadTask = nil
                trendsTask?.cancel()
                trendsTask = nil
                aiBriefingTask?.cancel()
                aiBriefingTask = nil
                layoutState.clearDashboardToolbar()
            }
            .refreshable {
                cancelPendingDashboardReload()
                await reloadDashboard()
                await bridge.pullMissingSyncChanges()
            }
    }

    private var dashboardScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s3) {
                DashboardHeaderView(
                    greeting: dashboardGreeting,
                    dateLine: dashboardDateLine,
                    modeRawValue: $modeRawValue,
                    modeHint: modePreference.resolvedHint(for: dashboardStore.dashboardSnapshot?.currentContext),
                    snapshot: dashboardStore.dashboardSnapshot,
                    syncPill: syncPill,
                    singleColumn: singleColumn
                )

                if loadFailed, dashboardStore.dashboardSnapshot != nil {
                    DashboardErrorBanner(
                        lastLoadedAt: lastLoadedAt,
                        isRetrying: isRefreshing,
                        onRetry: retryLoad
                    )
                    .transition(.opacity)
                }

                dashboardBody
            }
            .padding(.horizontal, singleColumn ? DashboardStyle.Spacing.s2 : DashboardStyle.Spacing.s3)
            .padding(.top, DashboardStyle.Spacing.s2)
            .padding(.bottom, DashboardStyle.Spacing.s5)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: loadFailed)
        }
        .overlay(alignment: .top) {
            if isRefreshing, dashboardStore.dashboardSnapshot != nil {
                DashboardSyncLine()
            }
        }
    }

    @ViewBuilder
    private var dashboardBody: some View {
        if let snapshot = dashboardStore.dashboardSnapshot {
            if dashboardStore.classes.isEmpty {
                // Con cero clases, todos los bloques dirían "sin datos": un
                // único estado con una salida clara, como ya tiene macOS.
                dashboardEmptyState
            } else {
                loadedContent(snapshot: snapshot)
            }
        } else if loadFailed {
            DashboardLoadFailureView(onRetry: retryLoad)
        } else if isClassroomMode {
            DashboardClassroomSkeleton(singleColumn: singleColumn)
        } else {
            DashboardDispatchSkeleton(singleColumn: singleColumn)
        }
    }

    private func loadedContent(snapshot: DashboardSnapshot) -> some View {
        let presentation = presentationCache.model(for: snapshot)
        return Group {
            if isClassroomMode {
                DashboardClassroomView(
                    snapshot: snapshot,
                    colorScheme: colorScheme,
                    isCompact: isCompactWidth,
                    onAction: handleNowAction,
                    onExitClassroomMode: {
                        // Salir de Clase devuelve el selector a Auto; no fija Despacho.
                        modeRawValue = DashboardModePreference.auto.rawValue
                    }
                )
                .dashboardModeTransition(reduceMotion: reduceMotion)
                .id("modo-clase")
            } else {
                DashboardDispatchView(
                    presentation: presentation,
                    briefing: briefingSentence,
                    analysisFailed: classTrendsLoadFailed && briefingSentence == nil,
                    singleColumn: singleColumn,
                    hiddenKinds: $hiddenKinds,
                    showAllAttention: $showAllAttention,
                    openContext: $openContext,
                    handlers: dispatchHandlers
                )
                .dashboardModeTransition(reduceMotion: reduceMotion)
                .id("modo-despacho")
            }
        }
        // Error de red: el contenido anterior sigue a la vista, atenuado al 75 %.
        .opacity(loadFailed ? 0.75 : 1)
        .saturation(loadFailed ? 0.7 : 1)
        .animation(
            reduceMotion ? .linear(duration: 0.2) : .easeInOut(duration: 0.35),
            value: isClassroomMode
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(staleDataLabel ?? "Dashboard")
    }

    private var staleDataLabel: String? {
        guard loadFailed, let lastLoadedAt else { return nil }
        return "Datos de las \(lastLoadedAt.formatted(date: .omitted, time: .shortened))"
    }

    private var dispatchHandlers: DashboardDispatchHandlers {
        DashboardDispatchHandlers(
            onNowAction: handleNowAction,
            onAttentionAction: performAttentionAction,
            onAttentionSelect: { select($0.inspector) },
            onSelectSession: { select(.session($0)) },
            onSelectPE: { select(.pe($0)) },
            onRetryAnalysis: startTrendsLoad
        )
    }

    // MARK: Cabecera

    private var syncPill: DashboardSyncPill {
        if loadFailed { return .offline }
        if isRefreshing { return .syncing }
        return DashboardSyncPill.make(
            message: dashboardStore.syncStatusMessage,
            pendingChanges: dashboardStore.syncPendingChanges,
            pairedHost: dashboardStore.pairedSyncHost
        )
    }

    private var dashboardGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 6 && hour < 14 {
            return "Buenos días"
        } else if hour >= 14 && hour < 21 {
            return "Buenas tardes"
        } else {
            return "Buenas noches"
        }
    }

    private static let dashboardDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "EEEE, d 'de' MMMM"
        return formatter
    }()

    private var dashboardDateLine: String {
        let dateString = Self.dashboardDateFormatter.string(from: Date())
        let date = dateString.prefix(1).uppercased() + dateString.dropFirst()
        guard let name = selectedClassName else { return date }
        return "\(date) · \(name)"
    }

    private var selectedClassName: String? {
        guard let selectedClassId,
              let schoolClass = dashboardStore.classes.first(where: { $0.id == selectedClassId }) else {
            return nil
        }
        return "\(schoolClass.name) · \(schoolClass.course)º"
    }

    private var selectedClassLabel: String {
        selectedClassName ?? "Clase global activa"
    }

    private var dashboardActionClassId: Int64? {
        selectedClassId ?? dashboardStore.classes.first?.id
    }

    // MARK: Sin clases

    private var dashboardEmptyState: some View {
        let layout = singleColumn
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DashboardStyle.Spacing.s1))
            : AnyLayout(HStackLayout(alignment: .top, spacing: DashboardStyle.Spacing.s1))
        return VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s3) {
            HStack(alignment: .top, spacing: DashboardStyle.Spacing.s2) {
                Image(systemName: "person.3.sequence")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(DashboardStyle.accent)
                    .frame(width: 56, height: 56)
                    .background(DashboardStyle.accent.opacity(0.12), in: DashboardStyle.controlShape())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s1) {
                    Text("Sin clases todavía")
                        .font(DashboardStyle.Typography.title)
                    Text("Crea tu primera clase para empezar a ver aquí las sesiones, alertas y evaluaciones del día.")
                        .font(DashboardStyle.Typography.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Sin clases, la salida buena no es "crea una clase suelta" sino el
            // recorrido guiado: fechas → horario → grupos → alumnado.
            Button("Configurar mi curso") {
                OnboardingStore.shared.openChecklist()
            }
            .dashboardButtonStyle(prominent: true, large: true)

            layout {
                emptyActionCard(
                    title: "Crear grupo",
                    subtitle: "Empieza por el alumnado y sus clases.",
                    systemImage: "person.3.sequence"
                ) { onOpenModule(.courses, nil, nil) }
                emptyActionCard(
                    title: "Planificar semana",
                    subtitle: "Define sesiones aunque no haya grupo aún.",
                    systemImage: "calendar.badge.plus"
                ) { onOpenModule(.planner, nil, nil) }
                emptyActionCard(
                    title: "Importar situación",
                    subtitle: "Sube un documento LOMLOE para programarlo después.",
                    systemImage: "doc.text.magnifyingglass"
                ) { onOpenModule(.situations, nil, nil) }
            }
        }
        .dashboardCard()
    }

    private func emptyActionCard(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DashboardStyle.Spacing.s1) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(DashboardStyle.accent)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DashboardStyle.Spacing.micro) {
                    Text(title)
                        .font(DashboardStyle.Typography.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(DashboardStyle.Typography.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(DashboardStyle.Spacing.s2)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .background(DashboardStyle.insetFill, in: DashboardStyle.controlShape())
            .contentShape(DashboardStyle.controlShape())
        }
        .buttonStyle(.plain)
    }

    // MARK: Acciones

    private func handleNowAction(_ action: DashboardNowAction) {
        let classId = dashboardStore.dashboardSnapshot?.currentContext?.classId?.int64Value ?? dashboardActionClassId
        switch action {
        case .passList:
            onOpenModule(.attendance, classId, nil)
        case .openNotebook:
            onOpenModule(.notebook, classId, nil)
        case .evaluate:
            onOpenModule(.rubrics, classId, nil)
        case .observation:
            performObservation()
        case .quickEvaluation:
            performQuickEvaluation()
        case .openPlanner, .openJournal:
            onOpenModule(.planner, classId, nil)
        }
    }

    private func performAttentionAction(_ item: DashboardAttentionItem) {
        switch item.action.route {
        case .module(let module, let classId, let studentId):
            onOpenModule(module, classId, studentId)
        case .inspector:
            select(item.inspector)
        }
    }

    private func select(_ selection: DashboardInspectorSelection) {
        inspectorSelection = selection
        isInspectorPresented = true
    }

    private func closeInspector() {
        inspectorSelection = nil
        isInspectorPresented = false
    }

    /// "Pasar lista" solo abre Asistencia: el dashboard no marca a nadie por su cuenta.
    private func performPassList() {
        let classId = dashboardStore.dashboardSnapshot?.currentContext?.classId?.int64Value ?? dashboardActionClassId
        onOpenModule(.attendance, classId, nil)
    }

    /// "Nueva observación" abre un formulario; no crea nada hasta que se guarda con texto.
    private func performObservation() {
        isObservationPresented = true
    }

    private func performQuickEvaluation() {
        isQuickEvaluationPresented = true
    }

    // MARK: Barra de herramientas (shell)

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
        return "\(classKey)|\(modeRawValue)|\(inspectorKey)|\(isInspectorPresented)"
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
                Task { await reloadDashboard() }
            },
            onPassList: {
                performPassList()
            },
            onObservation: {
                performObservation()
            },
            onQuickEvaluation: {
                performQuickEvaluation()
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
            if inspectorSelection == nil {
                isInspectorPresented = false
            }
            syncToolbarState()
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
        if let first = presentationCache.model(for: snapshot).queue.first {
            inspectorSelection = first.inspector
        } else if let firstSession = snapshot.todaySessions.first {
            inspectorSelection = .session(firstSession.id)
        }
        if inspectorSelection != nil {
            isInspectorPresented = true
        }
    }

    // MARK: Carga

    private func triggerDashboardReload() {
        dashboardReloadTask?.cancel()
        dashboardReloadGeneration += 1
        let generation = dashboardReloadGeneration
        dashboardReloadTask = Task { @MainActor in
            // Un cambio de clase y de modo casi simultáneos se funden en una
            // sola carga, sin esperas fijas.
            await Task.yield()
            guard !Task.isCancelled, generation == dashboardReloadGeneration else { return }
            await reloadDashboard(expectedReloadGeneration: generation)
        }
    }

    private func cancelPendingDashboardReload() {
        dashboardReloadTask?.cancel()
        dashboardReloadTask = nil
        dashboardReloadGeneration += 1
    }

    private func retryLoad() {
        AccessibilityNotification.Announcement("Reintentando").post()
        cancelPendingDashboardReload()
        Task { await reloadDashboard() }
    }

    /// Recarga el snapshot SIN vaciar la pantalla: el contenido anterior se
    /// queda a la vista y solo aparece la línea de sincronización. El filtrado
    /// de Atención es local, así que aquí solo se pide el alcance (clase).
    private func reloadDashboard(expectedReloadGeneration: Int? = nil) async {
        if let expectedReloadGeneration, expectedReloadGeneration != dashboardReloadGeneration {
            return
        }
        isRefreshing = true
        defer {
            if expectedReloadGeneration == nil || expectedReloadGeneration == dashboardReloadGeneration {
                isRefreshing = false
            }
        }
        bridge.updateDashboardFilters(
            classId: selectedClassId,
            severity: nil,
            priority: nil,
            sessionStatus: nil
        )
        let previous = bridge.dashboardSnapshot
        await bridge.refreshDashboard(mode: mode)
        guard !Task.isCancelled else { return }
        if let expectedReloadGeneration, expectedReloadGeneration != dashboardReloadGeneration {
            return
        }

        // `refreshDashboard` no lanza: si falla deja el snapshot anterior y
        // escribe el error en `status`.
        let failed = bridge.dashboardSnapshot === previous
            && bridge.status.hasPrefix("Error dashboard operativo")
        if failed {
            loadFailed = true
            return
        }
        if loadFailed {
            AccessibilityNotification.Announcement("Datos actualizados").post()
        }
        loadFailed = false
        lastLoadedAt = Date()

        // Pendiente y Riesgo ya se ven con el snapshot (el briefing se rehace en
        // `snapshotDidChange`). Las tendencias llegan después, sin bloquear nada.
        startTrendsLoad()
    }

    private func snapshotDidChange() {
        guard dashboardStore.dashboardSnapshot != nil else { return }
        lastLoadedAt = Date()
        loadFailed = false
        rebuildProactiveRadar()
    }

    // MARK: Análisis (briefing)

    private var briefingSentence: String? {
        DashboardBriefing.oneSentence(aiBriefing?.summary ?? proactiveInsights.first?.summary)
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
        loadAIBriefingIfNeeded()
    }

    private func loadAIBriefingIfNeeded() {
        let key = DashboardAIBriefingCacheKey(classId: selectedClassId, scope: "iOS-\(modeRawValue)")
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
        aiBriefingTask?.cancel()
        aiBriefingTask = Task { @MainActor in
            defer { DashboardAIBriefingCache.shared.finishRefresh(for: key) }
            do {
                let draft = try await teachingAssistantService.generateDailyBriefingDraft(
                    bridge: bridge,
                    classId: classId,
                    audience: .docente,
                    tone: .breve,
                    customPrompt: nil
                )
                guard !Task.isCancelled, activeAIBriefingKey == key else { return }
                DashboardAIBriefingCache.shared.store(draft, for: key)
                aiBriefing = draft
                aiBriefingState = .fresh
            } catch {
                guard !Task.isCancelled, activeAIBriefingKey == key else { return }
                if let fallback = DashboardProactiveInsightEngine.fallbackBriefing(from: proactiveInsights, className: selectedClassLabel) {
                    aiBriefing = fallback
                }
                aiBriefingState = .failed
            }
        }
    }

    private func startTrendsLoad() {
        trendsTask?.cancel()
        trendsTask = Task { @MainActor in
            await loadClassTrends()
            guard !Task.isCancelled else { return }
            rebuildProactiveRadar()
        }
    }

    private func loadClassTrends() async {
        guard let classId = selectedClassId else {
            classTrends = nil
            classTrendsLoadFailed = false
            return
        }
        classTrendsLoadFailed = false
        do {
            classTrends = try await bridge.getAITrendsAndMetrics(classId: classId, studentId: nil)
        } catch {
            guard !Task.isCancelled else { return }
            classTrendsLoadFailed = true
        }
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


// MARK: - Formulario de nueva observación

private struct DashboardObservationSheet: View {
    @ObservedObject var bridge: KmpBridge
    let initialClassId: Int64?
    @Environment(\.dismiss) private var dismiss

    @State private var selectedClassId: Int64?
    @State private var selectedStudentId: Int64?
    @State private var text = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didSave = false

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        selectedClassId != nil && selectedStudentId != nil && !trimmedText.isEmpty && !isSaving && !didSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
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
                }
                Section("Observación") {
                    TextField("Escribe qué has observado", text: $text, axis: .vertical)
                        .font(.body)
                        .lineLimit(4...8)
                        .frame(minHeight: 88, alignment: .topLeading)
                }
                if didSave {
                    Label("Observación guardada", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Nueva observación")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(!canSave)
                }
            }
        }
        .onAppear {
            selectedClassId = initialClassId ?? bridge.classes.first?.id
            loadStudents()
        }
        .appOnChange(of: selectedClassId) { _ in
            selectedStudentId = nil
            loadStudents()
        }
    }

    private func loadStudents() {
        Task { @MainActor in
            guard let selectedClassId else { return }
            await bridge.selectStudentsClass(classId: selectedClassId)
        }
    }

    @MainActor
    private func save() async {
        guard let classId = selectedClassId, let studentId = selectedStudentId, !trimmedText.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await bridge.createIncident(
                classId: classId,
                studentId: studentId,
                title: "Observación",
                detail: trimmedText
            )
            didSave = true
            bridge.status = "Observación guardada desde el dashboard"
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar: \(error.localizedDescription)"
        }
    }
}
