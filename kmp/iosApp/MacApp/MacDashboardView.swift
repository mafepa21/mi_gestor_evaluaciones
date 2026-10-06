import SwiftUI
import MiGestorKit
import UniformTypeIdentifiers

struct MacDashboardToolbarActions {
    let canRunActions: Bool
    let refresh: () -> Void
    let passList: () -> Void
    let observation: () -> Void
}

enum MacDashboardDestination {
    case attendance(classId: Int64?)
    case notebook(classId: Int64?)
    case rubrics(classId: Int64?)
    case plannerAgenda
    case plannerSession(sessionId: Int64?)
    case students(classId: Int64?)
    case reports(classId: Int64?)
}

// MARK: - Dashboard de macOS
//
// Mismo diseño que iPad: Despacho en 3 franjas (AHORA, ATENCIÓN, CONTEXTO) y
// modo Clase, con las mismas vistas (DashboardDispatchView,
// DashboardClassroomView, DashboardHeaderView, DashboardStateViews) y el mismo
// modelo de presentación (DashboardPresentation). Aquí solo queda lo propio de
// Mac: navegación por el shell, atajos de teclado, la asistencia de hoy
// pendiente y el formulario de evaluación rápida de escritorio.

struct MacDashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let bridge: KmpBridge
    @ObservedObject var dashboardStore: DashboardBridgeStore
    @ObservedObject var backupStore: MacBackupStore
    let bootstrap: AppleBridgeBootstrap
    var onNavigate: (MacDashboardDestination) -> Void = { _ in }
    var onToolbarActionsChange: (MacDashboardToolbarActions?) -> Void = { _ in }
    var onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void = { _, _, _ in }

    /// Misma clave de preferencia que iPad.
    @AppStorage("dashboard_mode_preference") private var modePreferenceRaw: String = DashboardModePreference.auto.rawValue

    // Presentación (todo local: filtrar o plegar no llama a KMP).
    @State private var presentationCache = DashboardPresentationCache()
    @State private var hiddenKinds: Set<DashboardAttentionKind> = []
    @State private var showAllAttention = false
    @State private var openContext: Set<DashboardContextCard> = [.agenda]
    @State private var containerWidth: CGFloat = 1000

    // Inspector y hojas.
    @State private var inspectorSelection: DashboardInspectorSelection?
    @State private var isInspectorPresented = false
    @State private var activeSheet: DashboardSheet?

    // Análisis (briefing de una frase).
    @State private var classTrends: KmpBridge.AITrendsSnapshot?
    @State private var classTrendsLoadFailed = false
    @State private var proactiveInsights: [DashboardProactiveInsight] = []
    @State private var aiBriefing: TeachingAssistantDraft?
    @State private var aiBriefingState: DashboardAIBriefingState = .deterministic
    @State private var activeAIBriefingKey: DashboardAIBriefingCacheKey?
    @State private var trendsTask: Task<Void, Never>?
    @State private var aiBriefingTask: Task<Void, Never>?
    private let teachingAssistantService = AppleFoundationTeachingAssistantService()

    // Carga.
    @State private var reloadTask: Task<Void, Never>?
    @State private var reloadGeneration = 0
    @State private var isRefreshing = false
    @State private var loadFailed = false
    @State private var lastLoadedAt: Date?
    /// Clase con la asistencia de hoy sin pasar (información solo de Mac).
    @State private var attendancePendingClassId: Int64?

    private var modePreference: DashboardModePreference {
        DashboardModePreference(rawValue: modePreferenceRaw) ?? .auto
    }

    private var snapshot: DashboardSnapshot? { dashboardStore.dashboardSnapshot }

    private var activeContext: DashboardSessionContext? { snapshot?.currentContext }

    private var effectiveMode: DashboardMode { modePreference.resolved(for: activeContext) }

    private var isClassroomMode: Bool { effectiveMode == .classroom }

    /// Una columna en ventanas estrechas o con Dynamic Type de accesibilidad.
    private var singleColumn: Bool {
        containerWidth < 760 || dynamicTypeSize.isAccessibilitySize
    }

    private var snapshotIdentity: ObjectIdentifier? { snapshot.map { ObjectIdentifier($0) } }

    // MARK: Cuerpo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s3) {
                DashboardHeaderView(
                    greeting: greeting,
                    dateLine: dateLine,
                    modeRawValue: $modePreferenceRaw,
                    modeHint: modePreference.resolvedHint(for: activeContext),
                    snapshot: snapshot,
                    syncPill: syncPill
                )

                if loadFailed, snapshot != nil {
                    DashboardErrorBanner(lastLoadedAt: lastLoadedAt, isRetrying: isRefreshing, onRetry: retryLoad)
                        .transition(.opacity)
                }

                dashboardBody
            }
            .padding(MacAppStyle.pagePadding)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: loadFailed)
        }
        .overlay(alignment: .top) {
            if isRefreshing, snapshot != nil { DashboardSyncLine() }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
        .background { DashboardBackground() }
        .background { keyboardShortcuts }
        .inspector(isPresented: $isInspectorPresented) {
            DashboardInspectorContent(
                snapshot: snapshot,
                selection: inspectorSelection,
                onOpenModule: openModule,
                onNewObservation: { activeSheet = .observation(classId: activeClassId) },
                onClose: closeInspector
            )
            .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .quickEvaluation(let classId):
                QuickEvaluationSheet(bridge: bridge, initialClassId: classId) {
                    activeSheet = nil
                } onOpenNotebook: { classId in
                    activeSheet = nil
                    onNavigate(.notebook(classId: classId))
                }
                .frame(minWidth: 760, minHeight: 680)
            case .observation(let classId):
                DashboardObservationSheet(bridge: bridge, initialClassId: classId)
                    .frame(minWidth: 520, minHeight: 460)
            }
        }
        .task {
            await backupStore.loadBackups()
        }
        .task {
            await reloadDashboard()
        }
        .onAppear { scheduleToolbarActionsSync() }
        .onDisappear {
            reloadTask?.cancel()
            trendsTask?.cancel()
            aiBriefingTask?.cancel()
            onToolbarActionsChange(nil)
        }
        .appOnChange(of: toolbarKey) { _ in scheduleToolbarActionsSync() }
        // El modo efectivo decide el alcance del snapshot (Clase = solo el
        // grupo en curso). La sync (pendientes, host) ya NO recarga la página:
        // solo cambia la píldora.
        .appOnChange(of: isClassroomMode) { _ in triggerReload() }
        .appOnChange(of: snapshotIdentity) { _ in snapshotDidChange() }
    }

    /// Atajos propios del Dashboard: ⌘1/2/3 cambian de modo, ⌘N nueva observación.
    /// ⌘R (recargar) y Esc (salir de Clase) ya los cubren el shell y el modo Clase.
    private var keyboardShortcuts: some View {
        Group {
            Button("Modo Auto") { modePreferenceRaw = DashboardModePreference.auto.rawValue }
                .keyboardShortcut("1", modifiers: .command)
            Button("Modo Clase") { modePreferenceRaw = DashboardModePreference.classroom.rawValue }
                .keyboardShortcut("2", modifiers: .command)
            Button("Modo Despacho") { modePreferenceRaw = DashboardModePreference.office.rawValue }
                .keyboardShortcut("3", modifiers: .command)
            Button("Nueva observación") { activeSheet = .observation(classId: activeClassId) }
                .keyboardShortcut("n", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Contenido

    @ViewBuilder
    private var dashboardBody: some View {
        if let snapshot {
            if dashboardStore.classes.isEmpty {
                DashboardNoClassesView(singleColumn: singleColumn) { module in
                    openModule(module, nil, nil)
                }
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
        let presentation = presentationCache.model(for: snapshot, extraItems: extraAttentionItems)
        return Group {
            if isClassroomMode {
                DashboardClassroomView(
                    snapshot: snapshot,
                    colorScheme: colorScheme,
                    isCompact: singleColumn,
                    onAction: handleNowAction,
                    onExitClassroomMode: {
                        // Salir de Clase devuelve el selector a Auto; no fija Despacho.
                        modePreferenceRaw = DashboardModePreference.auto.rawValue
                    },
                    studentNames: studentNames
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
        .opacity(loadFailed ? 0.75 : 1)
        .saturation(loadFailed ? 0.7 : 1)
        .animation(reduceMotion ? .linear(duration: 0.2) : .easeInOut(duration: 0.35), value: isClassroomMode)
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

    /// La asistencia de hoy sin pasar solo se conoce en Mac: entra en la lista
    /// de Atención como una fila más, con la misma lógica que el resto.
    private var extraAttentionItems: [DashboardAttentionItem] {
        guard let classId = attendancePendingClassId else { return [] }
        return [
            DashboardAttentionItem(
                id: "attendance-today-\(classId)",
                kind: .pending,
                title: "Asistencia pendiente de hoy",
                detail: "Abre Asistencia para pasar lista.",
                classId: classId,
                studentId: nil,
                inspector: .attendance(classId: classId),
                action: DashboardAttentionAction(
                    title: "Pasar lista",
                    route: .module(.attendance, classId: classId, studentId: nil)
                )
            )
        ]
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

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 6 && hour < 14 { return "Buenos días" }
        if hour >= 14 && hour < 21 { return "Buenas tardes" }
        return "Buenas noches"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "EEEE, d 'de' MMMM"
        return formatter
    }()

    private var dateLine: String {
        let text = Self.dateFormatter.string(from: Date())
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private var activeClassId: Int64? {
        activeContext?.classId?.int64Value ?? dashboardStore.classes.first?.id
    }

    /// Nombres cortos ("Hugo P.") para la ficha de alerta del modo Clase.
    private var studentNames: [Int64: String] {
        Dictionary(
            dashboardStore.studentsInClass.map { ($0.id, "\($0.firstName) \($0.lastName.prefix(1)).") },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: Navegación

    private func handleNowAction(_ action: DashboardNowAction) {
        let classId = activeContext?.classId?.int64Value
        switch action {
        case .passList:
            onNavigate(.attendance(classId: classId))
        case .openNotebook:
            onNavigate(.notebook(classId: classId))
        case .evaluate:
            onNavigate(.rubrics(classId: classId))
        case .observation:
            activeSheet = .observation(classId: classId)
        case .quickEvaluation:
            activeSheet = .quickEvaluation(classId: classId)
        case .openPlanner:
            onNavigate(.plannerAgenda)
        case .openJournal:
            onNavigate(.plannerSession(sessionId: activeContext?.sessionId?.int64Value))
        }
    }

    private func performAttentionAction(_ item: DashboardAttentionItem) {
        switch item.action.route {
        case .module(let module, let classId, let studentId):
            openModule(module, classId, studentId)
        case .inspector:
            select(item.inspector)
        }
    }

    /// El shell de Mac no tiene todos los módulos de iPad: Rúbricas y Planner
    /// se abren por su destino propio, y los de Educación Física caen en el
    /// módulo general equivalente (si no, el shell solo enseñaría un aviso).
    private func openModule(_ module: AppWorkspaceModule, _ classId: Int64?, _ studentId: Int64?) {
        let classId = classId ?? activeClassId
        switch module {
        case .attendance:
            onNavigate(.attendance(classId: classId))
        case .rubrics, .peRubrics:
            onNavigate(.rubrics(classId: classId))
        case .planner, .peMaterial:
            onNavigate(.plannerAgenda)
        case .peIncidents:
            onOpenModule(.students, classId, studentId)
        default:
            onOpenModule(module, classId, studentId)
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

    // MARK: Barra de herramientas (shell)

    private var toolbarKey: String {
        "\(activeContext?.classId?.int64Value ?? -1)|\(activeContext.map { dashboardContextStatusLabel($0.status) } ?? "none")"
    }

    private func syncToolbarActions() {
        onToolbarActionsChange(
            MacDashboardToolbarActions(
                canRunActions: activeContext?.classId != nil,
                refresh: { retryLoad() },
                passList: { onNavigate(.attendance(classId: activeContext?.classId?.int64Value)) },
                observation: { activeSheet = .observation(classId: activeContext?.classId?.int64Value) }
            )
        )
    }

    private func scheduleToolbarActionsSync() {
        Task { @MainActor in syncToolbarActions() }
    }

    // MARK: Carga

    private func triggerReload() {
        reloadTask?.cancel()
        reloadGeneration += 1
        let generation = reloadGeneration
        reloadTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, generation == reloadGeneration else { return }
            await reloadDashboard(expectedGeneration: generation)
        }
    }

    private func retryLoad() {
        AccessibilityNotification.Announcement("Reintentando").post()
        reloadTask?.cancel()
        reloadGeneration += 1
        Task { @MainActor in await reloadDashboard() }
    }

    /// Recarga sin vaciar la pantalla: el contenido anterior se queda a la vista.
    @MainActor
    private func reloadDashboard(expectedGeneration: Int? = nil) async {
        if let expectedGeneration, expectedGeneration != reloadGeneration { return }
        isRefreshing = true
        defer {
            if expectedGeneration == nil || expectedGeneration == reloadGeneration {
                isRefreshing = false
            }
        }
        await bridge.ensureClassesLoaded()
        let previous = bridge.dashboardSnapshot
        // Se pide con el modo vigente y, si el automático cambia de opinión al
        // ver el contexto, se recarga una sola vez.
        let requestedMode = modePreference.resolved(for: previous?.currentContext)
        await bridge.refreshDashboard(mode: requestedMode)
        guard !Task.isCancelled else { return }
        var latest = bridge.dashboardSnapshot
        let settledMode = modePreference.resolved(for: latest?.currentContext)
        if settledMode != requestedMode {
            await bridge.refreshDashboard(mode: settledMode)
            latest = bridge.dashboardSnapshot
        }
        guard !Task.isCancelled else { return }
        if let expectedGeneration, expectedGeneration != reloadGeneration { return }

        // `refreshDashboard` no lanza: si falla deja el snapshot anterior y
        // escribe el error en `status`.
        if latest === previous && bridge.status.hasPrefix("Error dashboard operativo") {
            loadFailed = true
            return
        }
        if loadFailed {
            AccessibilityNotification.Announcement("Datos actualizados").post()
        }
        loadFailed = false
        lastLoadedAt = Date()
        await refreshAttendancePending(context: latest?.currentContext)
        startTrendsLoad()
    }

    private func refreshAttendancePending(context: DashboardSessionContext?) async {
        guard let context, let classId = context.classId?.int64Value,
              context.status == .active || context.status == .nextToday else {
            attendancePendingClassId = nil
            return
        }
        let records = (try? await bridge.attendanceRecords(for: classId, on: Date())) ?? []
        attendancePendingClassId = records.isEmpty ? classId : nil
    }

    private func snapshotDidChange() {
        guard snapshot != nil else { return }
        lastLoadedAt = Date()
        loadFailed = false
        rebuildProactiveRadar()
        scheduleToolbarActionsSync()
    }

    // MARK: Análisis (briefing)

    private var briefingSentence: String? {
        DashboardBriefing.oneSentence(aiBriefing?.summary ?? proactiveInsights.first?.summary)
    }

    private var contextClassName: String? {
        guard let name = activeContext?.className, !name.isEmpty else { return nil }
        return name
    }

    private func rebuildProactiveRadar() {
        guard let snapshot else {
            proactiveInsights = []
            aiBriefing = nil
            aiBriefingState = .deterministic
            return
        }
        proactiveInsights = DashboardProactiveInsightEngine.build(
            snapshot: snapshot,
            trends: classTrends,
            context: DashboardProactiveContext(
                className: contextClassName,
                // El motor compara con "Clase": antes Mac pasaba "macOS" y
                // nunca reconocía el modo Clase.
                modeLabel: isClassroomMode ? "Clase" : "Despacho",
                syncPendingChanges: dashboardStore.syncPendingChanges,
                pairedSyncHost: dashboardStore.pairedSyncHost,
                latestBackupDate: backupStore.latestBackup?.createdAt,
                platformName: "macOS"
            ),
            limit: 5
        )
        loadAIBriefingIfNeeded()
    }

    private func loadAIBriefingIfNeeded() {
        let classId = activeContext?.classId?.int64Value
        let key = DashboardAIBriefingCacheKey(classId: classId, scope: "macOS")
        activeAIBriefingKey = key
        if let cached = DashboardAIBriefingCache.shared.cachedDraft(for: key) {
            aiBriefing = cached
            aiBriefingState = .cached
            return
        }
        aiBriefing = DashboardProactiveInsightEngine.fallbackBriefing(from: proactiveInsights, className: contextClassName)
        aiBriefingState = .updating
        guard DashboardAIBriefingCache.shared.beginRefresh(for: key) else { return }
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
                if let fallback = DashboardProactiveInsightEngine.fallbackBriefing(from: proactiveInsights, className: contextClassName) {
                    aiBriefing = fallback
                }
                aiBriefingState = .failed
            }
        }
    }

    private func startTrendsLoad() {
        trendsTask?.cancel()
        trendsTask = Task { @MainActor in
            guard let classId = activeContext?.classId?.int64Value else {
                classTrends = nil
                classTrendsLoadFailed = false
                rebuildProactiveRadar()
                return
            }
            classTrendsLoadFailed = false
            do {
                classTrends = try await bridge.getAITrendsAndMetrics(classId: classId, studentId: nil)
            } catch {
                guard !Task.isCancelled else { return }
                classTrendsLoadFailed = true
            }
            guard !Task.isCancelled else { return }
            rebuildProactiveRadar()
        }
    }
}

private enum DashboardSheet: Identifiable, Hashable {
    case quickEvaluation(classId: Int64?)
    case observation(classId: Int64?)

    var id: String {
        switch self {
        case .quickEvaluation(let classId): return "quick-\(classId ?? -1)"
        case .observation(let classId): return "observation-\(classId ?? -1)"
        }
    }
}

private struct QuickEvaluationSheet: View {
    @ObservedObject var bridge: KmpBridge
    let initialClassId: Int64?
    let onCancel: () -> Void
    let onOpenNotebook: (Int64?) -> Void

    @State private var selectedClassId: Int64?
    @State private var instruments: [PreparedEvaluationInstrument] = PreparedEvaluationInstrument.defaults
    @State private var activeInstrumentId: UUID?
    @State private var showingRubricImporter = false
    @State private var showingRubricBuilder = false
    @State private var importPreview: AppleRubricImportPreview?
    @State private var errorMessage: String?
    @State private var isCreatingColumns = false

    private var selectedInstruments: [PreparedEvaluationInstrument] {
        instruments.filter(\.isSelected)
    }

    private var canCreateColumns: Bool {
        selectedClassId != nil &&
        !selectedInstruments.isEmpty &&
        selectedInstruments.allSatisfy { $0.rubricId != nil && parsedWeight(for: $0) != nil } &&
        !isCreatingColumns
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    classSelector
                    instrumentsSection
                    statusBlock
                }
                .padding(MacAppStyle.pagePadding)
            }

            Divider()
            footer
        }
        .background(MacAppStyle.pageBackground)
        .onAppear {
            selectedClassId = initialClassId ?? bridge.classes.first?.id
            loadSelection()
        }
        .appOnChange(of: selectedClassId) { _ in
            loadSelection()
        }
        .fileImporter(
            isPresented: $showingRubricImporter,
            allowedContentTypes: [.xlsx, .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleRubricImportFile(result) }
        }
        .sheet(item: $importPreview) { preview in
            DashboardRubricImportPreviewSheet(preview: preview) {
                importPreview = nil
            } confirm: {
                Task { await confirmRubricImport(preview) }
            }
        }
        .sheet(isPresented: $showingRubricBuilder) {
            RubricsBuilderScreen(onSaved: { rubricId in
                attachRubric(rubricId)
                showingRubricBuilder = false
            })
            .environmentObject(bridge)
            .frame(minWidth: 1_120, idealWidth: 1_280, maxWidth: 1_600, minHeight: 720, idealHeight: 900)
        }
        .alert("No se pudo preparar la evaluación", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "checklist.checked")
                .font(.title2.bold())
                .foregroundStyle(MacAppStyle.infoTint)
                .frame(width: 48, height: 48)
                .background(MacAppStyle.infoTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Preparar evaluación")
                    .font(.title2.weight(.semibold))
                Text("Crea columnas de rúbrica vinculadas al cuaderno de la clase.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, MacAppStyle.pagePadding)
        .padding(.vertical, 20)
    }

    private var classSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Grupo")
                .font(MacAppStyle.sectionTitle)

            Picker("Grupo", selection: $selectedClassId) {
                Text("Seleccionar").tag(Int64?.none)
                ForEach(bridge.classes, id: \.id) { schoolClass in
                    Text("\(schoolClass.name) · \(schoolClass.course)º").tag(Optional(schoolClass.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 320, alignment: .leading)
        }
        .padding(MacAppStyle.innerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }

    private var instrumentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Instrumentos")
                    .font(MacAppStyle.sectionTitle)
                Spacer()
                Button {
                    instruments.append(PreparedEvaluationInstrument(title: "Nueva rúbrica", weightText: "10"))
                } label: {
                    Label("Añadir", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            VStack(spacing: 12) {
                ForEach($instruments) { $instrument in
                    instrumentRow($instrument)
                }
            }
        }
    }

    private func instrumentRow(_ instrument: Binding<PreparedEvaluationInstrument>) -> some View {
        let value = instrument.wrappedValue
        let selectedRubric = bridge.rubrics.first { $0.rubric.id == value.rubricId }

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Toggle("", isOn: instrument.isSelected)
                    .labelsHidden()

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Nombre del instrumento", text: instrument.title)
                        .font(.headline)
                        .textFieldStyle(.plain)

                    HStack(spacing: 12) {
                        TextField("Peso", text: instrument.weightText)
                            .frame(width: 72)
                            .textFieldStyle(.roundedBorder)
                        Text("%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        MacStatusPill(
                            label: selectedRubric == nil ? "Sin rúbrica" : "Rúbrica vinculada",
                            isActive: selectedRubric != nil,
                            tint: selectedRubric == nil ? MacAppStyle.warningTint : MacAppStyle.successTint
                        )
                    }
                }

                Spacer(minLength: 16)

                Menu {
                    if availableRubrics.isEmpty {
                        Text("No hay rúbricas disponibles")
                    } else {
                        ForEach(availableRubrics, id: \.rubric.id) { rubric in
                            Button {
                                instrument.wrappedValue.rubricId = rubric.rubric.id
                                instrument.wrappedValue.rubricName = rubric.rubric.name
                            } label: {
                                Label(rubric.rubric.name, systemImage: "checklist")
                            }
                        }
                    }

                    Divider()

                    Button {
                        startRubricBuilder(for: value.id)
                    } label: {
                        Label("Crear rúbrica", systemImage: "plus.square")
                    }

                    Button {
                        activeInstrumentId = value.id
                        showingRubricImporter = true
                    } label: {
                        Label("Importar desde Excel", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("Rúbrica", systemImage: "ellipsis.circle")
                }
                .menuStyle(.button)
            }

            if let selectedRubric {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedRubric.rubric.name)
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 8) {
                        Label("\(selectedRubric.criteria.count) criterios", systemImage: "list.bullet.rectangle")
                        if isCurrentClassRubric(selectedRubric) {
                            Label("Grupo actual", systemImage: "person.2.fill")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MacAppStyle.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(MacAppStyle.innerPadding)
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private var statusBlock: some View {
        if selectedInstruments.isEmpty {
            Label("Selecciona al menos un instrumento.", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if !canCreateColumns {
            Label("Cada instrumento seleccionado necesita peso válido y rúbrica.", systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(MacAppStyle.warningTint)
        } else {
            Label("Se crearán \(selectedInstruments.count) columna(s) de rúbrica en el cuaderno.", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(MacAppStyle.successTint)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button("Cancelar", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button {
                onOpenNotebook(selectedClassId)
            } label: {
                Label("Abrir cuaderno", systemImage: "tablecells")
            }
            .disabled(selectedClassId == nil)

            Spacer()

            Button {
                Task { await createColumns() }
            } label: {
                Label(isCreatingColumns ? "Creando..." : "Crear columnas", systemImage: "plus.rectangle.on.rectangle")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canCreateColumns)
        }
        .padding(.horizontal, MacAppStyle.pagePadding)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }

    private var availableRubrics: [RubricDetail] {
        bridge.rubrics
            .filter { rubric in
                guard let selectedClassId else { return true }
                let directClassId = rubric.rubric.classId?.int64Value
                return directClassId == nil || directClassId == selectedClassId || bridge.rubricClassLinks[rubric.rubric.id]?.contains(selectedClassId) == true
            }
            .sorted { $0.rubric.name.localizedCaseInsensitiveCompare($1.rubric.name) == .orderedAscending }
    }

    private func loadSelection() {
        Task {
            guard let selectedClassId else { return }
            bridge.selectClass(id: selectedClassId)
            await bridge.selectStudentsClass(classId: selectedClassId)
            try? await bridge.refreshRubrics()
            try? await bridge.refreshRubricClassLinks()
        }
    }

    private func startRubricBuilder(for instrumentId: UUID) {
        activeInstrumentId = instrumentId
        bridge.resetRubricBuilder()
        if let selectedClassId {
            bridge.selectRubricClass(selectedClassId)
        }
        if let instrument = instruments.first(where: { $0.id == instrumentId }) {
            bridge.updateRubricName(instrument.title)
        }
        showingRubricBuilder = true
    }

    @MainActor
    private func handleRubricImportFile(_ result: Result<[URL], Error>) async {
        do {
            guard let url = try result.get().first else { return }
            let rows = try AppleSpreadsheetReader.readRows(from: url)
            importPreview = makeRubricImportPreview(from: rows)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func confirmRubricImport(_ preview: AppleRubricImportPreview) async {
        do {
            try await bridge.importRubricDraft(tsv: preview.tsv)
            if let selectedClassId {
                bridge.selectRubricClass(selectedClassId)
            }
            importPreview = nil
            showingRubricBuilder = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func attachRubric(_ rubricId: Int64) {
        guard let activeInstrumentId,
              let index = instruments.firstIndex(where: { $0.id == activeInstrumentId }) else { return }
        instruments[index].rubricId = rubricId
        instruments[index].rubricName = bridge.rubrics.first(where: { $0.rubric.id == rubricId })?.rubric.name ?? instruments[index].title
    }

    @MainActor
    private func createColumns() async {
        guard let selectedClassId else { return }
        isCreatingColumns = true
        defer { isCreatingColumns = false }
        bridge.selectClass(id: selectedClassId)

        do {
            for instrument in selectedInstruments {
                guard let rubricId = instrument.rubricId,
                      let weight = parsedWeight(for: instrument) else { continue }
                _ = try await bridge.addColumnWithOptionalCategory(
                    name: instrument.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rúbrica" : instrument.title,
                    type: NotebookColumnType.rubric.name,
                    weight: weight,
                    formula: nil,
                    rubricId: rubricId,
                    categoryKind: .evaluation,
                    instrumentKind: .rubric,
                    inputKind: .rubric,
                    scaleKind: .tenPoint,
                    iconName: "checklist",
                    countsTowardAverage: true
                )
            }
            onOpenNotebook(selectedClassId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parsedWeight(for instrument: PreparedEvaluationInstrument) -> Double? {
        let normalized = instrument.weightText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value >= 0 else { return nil }
        return value
    }

    private func isCurrentClassRubric(_ rubric: RubricDetail) -> Bool {
        guard let selectedClassId else { return false }
        return rubric.rubric.classId?.int64Value == selectedClassId ||
            bridge.rubricClassLinks[rubric.rubric.id]?.contains(selectedClassId) == true
    }

    private func makeRubricImportPreview(from rows: [[String]]) -> AppleRubricImportPreview {
        let tsv = rows.tsvText
        let nonEmptyRows = rows.filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        let header = nonEmptyRows.first ?? []
        let levels = header.dropFirst().filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let criteriaRows = nonEmptyRows.dropFirst().filter { row in
            row.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        var warnings: [String] = []
        if levels.isEmpty {
            warnings.append("No se han detectado niveles en la primera fila.")
        }
        if criteriaRows.isEmpty {
            warnings.append("No se han detectado criterios con descripción.")
        }
        for (index, row) in criteriaRows.enumerated() {
            let filledDescriptions = row.dropFirst().filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            let missingDescriptions = max(0, levels.count - filledDescriptions)
            if missingDescriptions > 0 {
                warnings.append("Criterio \(index + 1) tiene \(missingDescriptions) nivel(es) sin descripción.")
            }
        }
        let numericLevelCount = levels.filter { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) != nil }.count
        if numericLevelCount > 0 {
            warnings.append("\(numericLevelCount) nivel(es) parecen numéricos; revisa la escala antes de guardar.")
        }
        return AppleRubricImportPreview(
            title: "Rúbrica importada",
            levelCount: levels.count,
            criterionCount: criteriaRows.count,
            warnings: warnings,
            tsv: tsv
        )
    }
}

private struct PreparedEvaluationInstrument: Identifiable {
    let id = UUID()
    var title: String
    var weightText: String
    var isSelected = true
    var rubricId: Int64?
    var rubricName: String?

    static let defaults: [PreparedEvaluationInstrument] = [
        PreparedEvaluationInstrument(title: "Diseño del Plan de Entrenamiento", weightText: "40"),
        PreparedEvaluationInstrument(title: "Ejecución y Autorregulación", weightText: "40"),
        PreparedEvaluationInstrument(title: "Desempeño del Rol de Coach y Cooperación", weightText: "20")
    ]
}

private struct DashboardRubricImportPreviewSheet: View {
    let preview: AppleRubricImportPreview
    let cancel: () -> Void
    let confirm: () -> Void

    private var canConfirm: Bool {
        preview.levelCount > 0 && preview.criterionCount > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "checklist")
                    .font(.title2.bold())
                    .foregroundStyle(MacAppStyle.infoTint)
                    .frame(width: 48, height: 48)
                    .background(MacAppStyle.infoTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Importar rúbrica")
                        .font(.title2.weight(.semibold))
                    Text(preview.title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, MacAppStyle.pagePadding)
            .padding(.vertical, 20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        previewMetric(title: "Niveles", value: "\(preview.levelCount)", icon: "slider.horizontal.below.square")
                        previewMetric(title: "Criterios", value: "\(preview.criterionCount)", icon: "list.bullet.rectangle")
                        previewMetric(title: "Advertencias", value: "\(preview.warnings.count)", icon: "exclamationmark.triangle")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Validación")
                            .font(.headline)
                        if preview.warnings.isEmpty {
                            Label("Estructura lista para revisar en el editor.", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(MacAppStyle.successTint)
                        } else {
                            ForEach(preview.warnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle.fill")
                                    .font(.callout)
                                    .foregroundStyle(MacAppStyle.warningTint)
                            }
                        }
                    }
                    .padding(MacAppStyle.innerPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MacAppStyle.subtleFill)
                    .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
                }
                .padding(MacAppStyle.pagePadding)
            }

            Divider()

            HStack(spacing: 16) {
                Text(canConfirm ? "Se abrirá en el editor para revisión final." : "La rúbrica necesita niveles y criterios.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Cancelar", action: cancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                Button {
                    confirm()
                } label: {
                    Label("Abrir en editor", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canConfirm)
            }
            .padding(.horizontal, MacAppStyle.pagePadding)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
        }
        .frame(width: 600, height: 430)
        .background(MacAppStyle.pageBackground)
    }

    private func previewMetric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.bold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }
}

