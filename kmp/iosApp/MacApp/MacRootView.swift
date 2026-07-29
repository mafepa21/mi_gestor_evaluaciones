import SwiftUI
import AppKit
import MiGestorKit

struct MacRootView: View {
    @ObservedObject var session: MacAppSessionController
    @ObservedObject private var commandCenter: MacCommandCenterCoordinator
    @ObservedObject private var backupStore: MacBackupStore
    @ObservedObject private var backupService = AppleBackupService.shared
    @ObservedObject private var rescueService = AppleDatabaseRescueService.shared
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @Environment(\.openWindow) private var openWindow
    @StateObject private var layoutState = WorkspaceLayoutState()
    @StateObject private var notebookInspectorState = NotebookMacInspectorState()
    @StateObject private var notebookToolbarActions = NotebookMacToolbarActions()
    @StateObject private var notebookStore = NotebookBridgeStore()
    @StateObject private var dashboardStore = DashboardBridgeStore()
    @StateObject private var studentsBridgeStore = StudentsBridgeStore()
    @StateObject private var attendanceStore = AttendanceBridgeStore()
    @StateObject private var physicalTestsToolbarActions = MacPhysicalTestsToolbarActions()
    @StateObject private var physicalTestsInspectorState = PhysicalTestsMacInspectorState()
    @StateObject private var studentsStore = MacStudentsStore()
    @StateObject private var studentSelection = StudentSelectionStore()
    @SceneStorage("mac.root.columnVisibility") private var storedColumnVisibility = MacRootColumnVisibilityValue.all
    @SceneStorage("mac.root.inspectorVisible") private var storedInspectorVisible = true
    @FocusState private var isNotebookSearchFocused: Bool
    @State private var attendanceToolbarActions: MacAttendanceToolbarActions? = nil
    @State private var isAttendanceFilterPopoverPresented = false
    @State private var dashboardToolbarActions: MacDashboardToolbarActions? = nil
    @State private var plannerToolbarActions: PlannerMacToolbarActions? = nil
    @State private var plannerInspectorSession: PlanningSession? = nil
    @State private var pendingPlannerDiarySession: PlanningSession? = nil
    @State private var plannerDiaryContext = PlannerNavigationContext()
    @StateObject private var plannerDiaryLayoutState = WorkspaceLayoutState()
    @State private var studentsReloadToken = 0
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isInspectorVisible = true
    @State private var selectedFeature: MacFeatureDescriptor.Feature = .dashboard
    @State private var banner: MacRootBanner?
    @State private var selectedPlannerSessionId: Int64? = nil
    @State private var bannerDismissTask: Task<Void, Never>?
    @State private var didRequestCommandCenterStart = false

    init(session: MacAppSessionController) {
        self.session = session
        _commandCenter = ObservedObject(wrappedValue: session.commandCenter)
        _backupStore = ObservedObject(wrappedValue: session.backupStore)
    }

    var body: some View {
        Group {
            switch session.bootstrapState {
            case .idle, .loading:
                ProgressView("Preparando shell macOS…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MacAppStyle.pageBackground)
            case .failed(let message):
                ContentUnavailableView {
                    Label("No se pudo iniciar la shell Mac", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Reintentar") {
                        session.retry()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MacAppStyle.pageBackground)
            case .ready:
                navigationSplit
            }
        }
        .onAppear {
            selectedFeature = normalizedFeature(session.selectedFeature)
            columnVisibility = NavigationSplitViewVisibility(macRootStoredValue: storedColumnVisibility)
            isInspectorVisible = storedInspectorVisible && session.inspectorVisible
        }
        .onboardingHost(bridge: session.bridge) { module in
            open(module: module, classId: nil, studentId: nil)
        }
        .appOnChange(of: session.bootstrapState) { state in
            // Sólo con la shell lista tiene sentido preguntar si la base está
            // vacía; antes lo parecería siempre.
            guard state == .ready else { return }
            Task { await OnboardingStore.shared.bootstrap(bridge: session.bridge) }
        }
        .task {
            rescueService.checkForPendingRescue()
            notebookStore.bind(to: session.bridge)
            dashboardStore.bind(to: session.bridge)
            studentsBridgeStore.bind(to: session.bridge)
            attendanceStore.bind(to: session.bridge)

            session.start()
            await startCommandCenterAfterInitialLayout()
        }
        .appOnChange(of: columnVisibility.macRootStoredValue) { newValue in
            guard session.bootstrapState == .ready else { return }
            storedColumnVisibility = newValue
        }
        .appOnChange(of: isInspectorVisible) { newValue in
            storedInspectorVisible = newValue
            session.inspectorVisible = newValue
        }
        .appWritingToolsDisabled()
        .overlay {
            if backupService.needsRestart {
                RestartRequiredOverlay()
            }
        }
        .alert(
            "No se pudo abrir la base de datos",
            isPresented: $rescueService.isAlertPresented,
            presenting: rescueService.pendingRescue
        ) { marker in
            Button("Reintentar apertura") {
                rescueService.retryRescuedDatabase()
            }
            Button("Abrir copias de seguridad") {
                openWindow(id: MacDesktopWindowID.backups.rawValue)
            }
            Button("Seguir con base vacía", role: .destructive) {
                rescueService.continueWithEmptyDatabase()
            }
        } message: { marker in
            Text(marker.displayMessage)
        }
    }

    private func startCommandCenterAfterInitialLayout() async {
        guard !didRequestCommandCenterStart else { return }
        didRequestCommandCenterStart = true
        await Task.yield()
        commandCenter.startIfNeeded()
    }

    // Un único `.toolbar { }` para todas las pantallas: antes esto alternaba
    // estructuralmente entre `.toolbar(id: "notebook.toolbar")` (personalizable)
    // y `.toolbar { }` (normal) según `selectedFeature`, y ese `if/else` en la
    // raíz hacía que SwiftUI tratara cada rama como una identidad de vista
    // distinta. Al cruzar la frontera Cuaderno↔otra pantalla, todo el árbol
    // (sidebar, detalle y el puente de la NSToolbar) se destruía y reconstruía
    // a la vez que la transición animada del panel de detalle, y eso disparaba
    // un bucle de "Update Constraints in Window pass" sobre la ventana de la
    // toolbar (crash real reportado por el usuario al navegar de Cuaderno a
    // Cursos/Situaciones). `macToolbar` ya decidía el contenido correcto según
    // `selectedFeature`; el modificador `.toolbar` en sí solo necesita
    // permanecer estable. Se pierde la personalización nativa (arrastrar/
    // ocultar) de la toolbar del Cuaderno a cambio de no crashear.
    private var navigationSplit: some View {
        navigationSplitContent
            .toolbar {
                macToolbar
            }
    }

    // Esta vista se trocea en subexpresiones a propósito: como una sola cadena
    // (split view + detalle ramificado + overlay + los .onReceive) agota el
    // tiempo del type-checker de Swift en máquinas lentas.
    @ViewBuilder
    private var detailPane: some View {
        // Attendance applies its own .inspector() internally; wrapping it in the
        // shell's system inspector too would nest two inspectors and reserve width twice.
        // Planner opts out too: its session detail needs the same wide layout used on
        // iPad (760-860pt), which the shell's generic inspector (maxWidth 440) can't give it.
        // Diary opts out too: DiaryWorkspaceView (shared with iPad/iOS) brings its own
        // 3-panel layout with an internal inspector.
        // Rubrics opts out too: featureInspector(for:) has no real case for .rubrics (falls
        // to the generic MacModuleInspectorPlaceholder), and MacRubricsView already has its
        // own HSplitView detail panel — the shell inspector was just reserving 320-440pt for
        // nothing (UI-13 de plan_auditoria_ui_2026-07-15.md).
        // Meetings opts out for the same reason: MacMeetingsView brings its own HSplitView
        // (lista + detalle del acta), y superponer el inspector del shell provocaba un bucle
        // de "Update Constraints in Window pass" de AppKit (dos gestores de anchura compitiendo).
        // Notebook opts out too: NotebookModuleView ya pinta su propio panel lateral en macOS
        // (shouldUseSideInspector es siempre true fuera de iOS) vía HStack + Divider cuando
        // isInspectorPresented está activo. Envolverlo además en el inspector nativo del shell
        // duplicaba la reserva de ancho con una segunda instancia de NotebookMacLayout, y al
        // navegar fuera de Cuaderno ambas instancias se destruían a la vez en plena animación,
        // provocando el mismo bucle de constraints de AppKit que crasheaba la app.
        if selectedFeature == .attendance || selectedFeature == .planner || selectedFeature == .diary
            || selectedFeature == .rubrics || selectedFeature == .meetings || selectedFeature == .notebook {
            featureContent(for: selectedFeature)
                .id(selectedFeature)
                .transition(uiFeatureFlags.contentSwitchTransition)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MacAppStyle.pageBackground)
        } else {
            featureContent(for: selectedFeature)
                .id(selectedFeature)
                .transition(uiFeatureFlags.contentSwitchTransition)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MacAppStyle.pageBackground)
                .inspector(isPresented: $isInspectorVisible) {
                    featureInspector(for: selectedFeature)
                        .frame(minWidth: 320, idealWidth: 360, maxWidth: 440)
                        .background(.thinMaterial)
                }
        }
    }

    @ViewBuilder
    private var bannerOverlay: some View {
        if let banner {
            MacRootTransientBanner(banner: banner)
                .padding(.top, 12)
                .padding(.trailing, 16)
                .transition(uiFeatureFlags.bannerTransition)
        }
    }

    private var splitViewShell: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            macSidebar
        } detail: {
            detailPane
        }
        .navigationSplitViewStyle(.balanced)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .overlay(alignment: .topTrailing) { bannerOverlay }
        .animation(uiFeatureFlags.interactionAnimation, value: banner?.id)
    }

    private var navigationSplitContent: some View {
        splitViewShell
        .onReceive(NotificationCenter.default.publisher(for: .appleAppAddNotebookColumnRequested)) { _ in
            performPrimaryCreation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appleAppSaveOrSyncRequested)) { _ in
            performSave()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appleAppRefreshRequested)) { _ in
            refreshCurrentFeature()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appleAppToggleSidebarRequested)) { _ in
            toggleSidebar()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appleAppToggleInspectorRequested)) { _ in
            toggleInspector()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appleAppBackupRequested)) { _ in
            performBackup()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appleAppSearchRequested)) { _ in
            focusSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appleAppShowHiddenNotebookColumnsRequested)) { _ in
            openNotebookHiddenColumns()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appleAppReorderNotebookColumnsRequested)) { _ in
            openNotebookColumnOrganizer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appleAppExportReportRequested)) { _ in
            openReports()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appleAppNavigateRequested)) { notification in
            navigateFromCommand(notification.object)
        }
        .onReceive(NotificationCenter.default.publisher(for: .appleAppPlannerSectionRequested)) { notification in
            selectPlannerSection(notification.object)
        }
        .appOnChange(of: session.selectedFeature) { newFeature in
            let newFeature = normalizedFeature(newFeature)
            guard selectedFeature != newFeature else { return }
            Task { @MainActor in
                await Task.yield()
                selectFeature(newFeature, propagateToSession: false)
            }
        }
        .appOnChange(of: selectedFeature) { newFeature in
            guard newFeature != .notebook else { return }
            isNotebookSearchFocused = false
        }
        .sheet(isPresented: isPlannerInspectorSessionPresented, onDismiss: presentPendingPlannerDiarySession) {
            plannerInspectorSheetContent
        }
    }

    // Extraídos como propiedades tipadas (en vez de `Binding(get:set:)` inline en el
    // modifier chain) porque el type-checker de Swift no resolvía la expresión combinada
    // en tiempo razonable ("unable to type-check this expression in reasonable time").
    private var isPlannerInspectorSessionPresented: Binding<Bool> {
        Binding(
            get: { plannerInspectorSession != nil },
            set: { isPresented in
                if !isPresented { plannerInspectorSession = nil }
            }
        )
    }

    /// SwiftUI no encadena de forma fiable "cerrar un sheet y navegar" si ambas
    /// mutaciones ocurren en el mismo ciclo (el sheet de detalle todavía no ha
    /// terminado de cerrarse). Por eso "Abrir ejecución" solo deja aparcada la
    /// sesión destino y la navegación al módulo Diario de aula ocurre aquí, en el
    /// `onDismiss` del sheet de detalle, una vez ha cerrado del todo.
    private func presentPendingPlannerDiarySession() {
        guard let pending = pendingPlannerDiarySession else { return }
        pendingPlannerDiarySession = nil
        plannerDiaryContext = PlannerNavigationContext(
            week: Int(pending.weekNumber),
            year: Int(pending.year),
            groupId: pending.groupId,
            sessionId: pending.id
        )
        selectFeature(.diary)
    }

    /// Navegación directa al Diario de aula desde el menú contextual de la
    /// miniatura semanal (sin pasar por la ficha de detalle).
    private func openDiaryDirect(_ session: PlanningSession) {
        plannerDiaryContext = PlannerNavigationContext(
            week: Int(session.weekNumber),
            year: Int(session.year),
            groupId: session.groupId,
            sessionId: session.id
        )
        selectFeature(.diary)
    }

    @ViewBuilder
    private var plannerInspectorSheetContent: some View {
        if let plannerSession = plannerInspectorSession {
            PlannerSessionDetailSheet(
                session: plannerSession,
                onOpenDiary: {
                    plannerToolbarActions?.onOpenDiary(plannerSession)
                    pendingPlannerDiarySession = plannerSession
                    plannerInspectorSession = nil
                },
                onEdit: { plannerToolbarActions?.onEditSession(plannerSession) },
                presentation: .sheet
            )
            .environmentObject(session.bridge)
        }
    }

    private var macSidebar: some View {
        List(selection: selectedFeatureBinding) {
            ForEach(MacFeatureSection.allCases) { section in
                Section(header: Text(section.rawValue)) {
                    ForEach(section.features) { featureType in
                        sidebarRow(for: featureType)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MiGestor")
        .navigationSubtitle(session.bridge.statsText)
    }

    @ViewBuilder
    private func sidebarRow(for featureType: MacFeatureDescriptor.Feature) -> some View {
        let feature = MacFeatureRegistry.descriptor(for: featureType)
        HStack(spacing: 10) {
            Image(systemName: feature.systemImage)
                .frame(width: 20, height: 20)
                .foregroundStyle(iconTint(for: featureType))
            VStack(alignment: .leading, spacing: 1) {
                Text(feature.title)
                    .font(.callout.weight(.medium))
                Text(feature.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .tag(featureType)
        .contextMenu {
            sidebarContextMenu(for: featureType)
        }
    }

    private var selectedFeatureBinding: Binding<MacFeatureDescriptor.Feature> {
        Binding(
            get: { selectedFeature },
            set: { selectFeature($0) }
        )
    }

    private func normalizedFeature(_ feature: MacFeatureDescriptor.Feature) -> MacFeatureDescriptor.Feature {
        feature == .teacherRadar ? .dashboard : feature
    }

    private func selectFeature(
        _ feature: MacFeatureDescriptor.Feature,
        propagateToSession: Bool = true
    ) {
        let feature = normalizedFeature(feature)
        guard selectedFeature != feature || session.selectedFeature != feature else { return }
        withAnimation(uiFeatureFlags.animation(.easeOut(duration: 0.2))) {
            selectedFeature = feature
        }
        isInspectorVisible = storedInspectorVisible
        columnVisibility = .all
        guard propagateToSession else { return }
        Task { @MainActor in
            await Task.yield()
            if session.selectedFeature != feature {
                session.selectedFeature = feature
            }
        }
    }

    @ViewBuilder
    private func featureContent(for feature: MacFeatureDescriptor.Feature) -> some View {
        switch feature {
        case .dashboard:
            MacDashboardView(
                bridge: session.bridge,
                dashboardStore: dashboardStore,
                backupStore: backupStore,
                bootstrap: session.bootstrap,
                onNavigate: navigateFromDashboard,
                onToolbarActionsChange: setDashboardToolbarActions,
                onOpenModule: open(module:classId:studentId:)
            )
        case .teacherRadar:
            MacDashboardView(
                bridge: session.bridge,
                dashboardStore: dashboardStore,
                backupStore: backupStore,
                bootstrap: session.bootstrap,
                onNavigate: navigateFromDashboard,
                onToolbarActionsChange: setDashboardToolbarActions,
                onOpenModule: open(module:classId:studentId:)
            )
        case .courses:
            CoursesWorkspaceView(
                selectedClassId: studentSelection.selectedClassBinding,
                onOpenModule: open(module:classId:studentId:),
                onCreateStudent: { classId in
                    studentSelection.setClass(classId)
                    selectFeature(.students)
                }
            )
            .environmentObject(session.bridge)
        case .notebook:
            NotebookMacLayout(
                bridge: session.bridge,
                notebookStore: notebookStore,
                layoutState: layoutState,
                toolbarActions: notebookToolbarActions,
                inspectorState: notebookInspectorState,
                selectedClassId: studentSelection.selectedClassBinding,
                selectedStudentId: studentSelection.selectedStudentBinding,
                onOpenModule: open(module:classId:studentId:),
                presentation: .full,
                onToggleInspectorColumn: toggleInspector
            )
        case .attendance:
            MacAttendanceView(
                bridge: session.bridge,
                attendanceStore: attendanceStore,
                selectedClassId: studentSelection.selectedClassBinding,
                selectedStudentId: studentSelection.selectedStudentBinding,
                onOpenModule: open(module:classId:studentId:),
                onToolbarActionsChange: setAttendanceToolbarActions
            )
        case .students:
            MacStudentsView(
                bridge: session.bridge,
                studentsBridgeStore: studentsBridgeStore,
                store: studentsStore,
                selectedClassId: studentSelection.selectedClassBinding,
                selectedStudentId: studentSelection.selectedStudentBinding,
                onOpenModule: open(module:classId:studentId:),
                presentation: .content,
                reloadToken: studentsReloadToken
            )
        case .rubrics:
            MacRubricsView(bridge: session.bridge)
        case .physicalTests:
            MacPhysicalTestsView(
                bridge: session.bridge,
                selectedClassId: studentSelection.selectedClassBinding,
                selectedStudentId: studentSelection.selectedStudentBinding,
                onOpenModule: open(module:classId:studentId:),
                toolbarActions: physicalTestsToolbarActions,
                inspectorState: physicalTestsInspectorState
            )
        case .reports:
            MacReportsView(
                bridge: session.bridge,
                selectedClassId: studentSelection.selectedClassBinding,
                selectedStudentId: studentSelection.selectedStudentBinding
            )
        case .planner:
            PlannerMacLayout(
                bridge: session.bridge,
                selectedSessionId: $selectedPlannerSessionId,
                inspectorSession: $plannerInspectorSession,
                onToolbarActionsChange: setPlannerToolbarActions,
                onOpenDiaryDirect: openDiaryDirect
            )
        case .diary:
            DiaryWorkspaceView(
                selectedClassId: studentSelection.selectedClassBinding,
                navigationContext: plannerDiaryContext,
                onOpenModule: open(module:classId:studentId:),
                onOpenPlanner: { context in
                    plannerDiaryContext = context
                    if let sessionId = context.sessionId {
                        selectedPlannerSessionId = sessionId
                    }
                    selectFeature(.planner)
                },
                onNavigationContextChange: { plannerDiaryContext = $0 }
            )
            .environmentObject(session.bridge)
            .environmentObject(plannerDiaryLayoutState)
        case .situations:
            LearningSituationsWorkspaceView(
                selectedClassId: studentSelection.selectedClassBinding,
                onOpenModule: open(module:classId:studentId:)
            )
            .environmentObject(session.bridge)
        case .meetings:
            MacMeetingsView(bridge: session.bridge)
                .environmentObject(session.bridge)
        case .sync:
            MacSyncView(bridge: session.bridge, commandCenter: commandCenter)
        case .backups:
            MacBackupsView(store: backupStore)
        case .settings:
            MacSettingsView(
                session: session,
                commandCenter: commandCenter,
                backupStore: backupStore,
                onOpenSync: { selectFeature(.sync) },
                selectedClassId: studentSelection.selectedClassBinding,
                onOpenModule: open(module:classId:studentId:)
            )
        }
    }

    @ViewBuilder
    private func featureInspector(for feature: MacFeatureDescriptor.Feature) -> some View {
        switch feature {
        case .students:
            MacStudentsView(
                bridge: session.bridge,
                studentsBridgeStore: studentsBridgeStore,
                store: studentsStore,
                selectedClassId: studentSelection.selectedClassBinding,
                selectedStudentId: studentSelection.selectedStudentBinding,
                onOpenModule: open(module:classId:studentId:),
                presentation: .inspector,
                reloadToken: studentsReloadToken
            )
        case .backups:
            MacBackupInspectorView(store: backupStore)
        case .physicalTests:
            MacPhysicalTestsInspectorView(
                bridge: session.bridge,
                inspectorState: physicalTestsInspectorState,
                selectedClassId: studentSelection.selectedClassBinding,
                selectedStudentId: studentSelection.selectedStudentBinding,
                onOpenModule: open(module:classId:studentId:)
            )
        case .planner:
            if let plannerSession = plannerInspectorSession {
                PlannerSessionDetailSheet(
                    session: plannerSession,
                    onOpenDiary: { plannerToolbarActions?.onOpenDiary(plannerSession) },
                    onEdit: { plannerToolbarActions?.onEditSession(plannerSession) },
                    onDelete: { plannerToolbarActions?.onDeleteSession(plannerSession) },
                    presentation: .inspector,
                    onClose: { plannerInspectorSession = nil }
                )
                .environmentObject(session.bridge)
            } else {
                MacModuleInspectorPlaceholder(feature: MacFeatureRegistry.descriptor(for: feature))
            }
        default:
            MacModuleInspectorPlaceholder(feature: MacFeatureRegistry.descriptor(for: feature))
        }
    }

    @ToolbarContentBuilder
    private var macToolbar: some ToolbarContent {
        if selectedFeature == .notebook {
            macNotebookToolbar
        } else {
            macDefaultWorkspaceToolbar
        }
    }

    @ToolbarContentBuilder
    private var macNotebookToolbar: some CustomizableToolbarContent {
        ToolbarItem(id: "notebook.classSelector", placement: .primaryAction) {
            macNotebookClassSelector
        }

        ToolbarItem(id: "notebook.syncStatus", placement: .primaryAction, showsByDefault: false) {
            if session.bridge.syncPendingChanges > 0 {
                MacStatusPill(
                    label: "\(session.bridge.syncPendingChanges) pendientes",
                    isActive: true,
                    tint: MacAppStyle.warningTint
                )
            }
        }

        ToolbarItem(id: "notebook.addColumn", placement: .primaryAction) {
            Button {
                notebookToolbarActions.addColumn()
            } label: {
                Label("Añadir columna", systemImage: "plus.rectangle.on.rectangle")
            }
            .disabled(!notebookToolbarActions.addColumnAvailable)
            .help("Añadir nueva columna (⌘N)")
        }

        ToolbarItem(id: "notebook.search", placement: .primaryAction) {
            HStack(spacing: 6) {
                Label("Buscar", systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)

                TextField("Buscar", text: Binding(
                    get: { layoutState.notebookSearchText },
                    set: { layoutState.setNotebookSearchText($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .focused($isNotebookSearchFocused)
                .frame(minWidth: 160, idealWidth: 220, maxWidth: 260)
            }
        }

        ToolbarItem(id: "notebook.more", placement: .primaryAction) {
            macNotebookOverflowMenu
        }
    }

    private var macNotebookClassSelector: some View {
        Menu {
            ForEach(groupedNotebookClasses, id: \.course) { group in
                Menu("\(group.course)º") {
                    ForEach(group.classes, id: \.id) { schoolClass in
                        Button {
                            selectNotebookClass(schoolClass.id)
                        } label: {
                            HStack {
                                if schoolClass.id == activeNotebookClass?.id {
                                    Image(systemName: "checkmark")
                                }
                                Text(schoolClass.name)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical.fill")
                    .foregroundStyle(Color.accentColor)
                Text(activeNotebookClassLabel)
                    .fontWeight(.medium)
            }
        }
        .menuStyle(.button)
        .help("Seleccionar clase activa")
    }

    private var macNotebookOverflowMenu: some View {
        Menu {
            Button {
                notebookToolbarActions.refresh()
            } label: {
                Label("Recargar", systemImage: "arrow.clockwise")
            }

            if let exportText = notebookToolbarActions.exportText {
                ShareLink(item: exportText) {
                    Label("Exportar", systemImage: "square.and.arrow.up")
                }
            }

            Button {
                notebookToolbarActions.undo()
            } label: {
                Label("Deshacer", systemImage: "arrow.uturn.backward")
            }
            .disabled(!notebookToolbarActions.canUndo)
            .keyboardShortcut("z", modifiers: .command)

            Divider()

            Button {
                notebookToolbarActions.openAdvancedMenu()
            } label: {
                Label("Opciones avanzadas", systemImage: "ellipsis.circle")
            }

            Picker("Vista", selection: Binding(
                get: { layoutState.notebookSurfaceMode },
                set: { layoutState.setNotebookSurfaceMode($0) }
            )) {
                Label("Grid", systemImage: "tablecells").tag("grid")
                Label("Plano", systemImage: "rectangle.3.group").tag("seatingPlan")
            }

            Button {
                notebookToolbarActions.toggleAttendanceQuickMode()
            } label: {
                Label(
                    notebookToolbarActions.isAttendanceQuickMode ? "Salir de asistencia rápida" : "Asistencia rápida",
                    systemImage: notebookToolbarActions.isAttendanceQuickMode ? "figure.walk.circle.fill" : "figure.walk.circle"
                )
            }

            Divider()

            Button {
                layoutState.openNotebookHiddenColumns()
            } label: {
                Label("Columnas ocultas", systemImage: "eye.slash")
            }
            .disabled(!notebookToolbarActions.organizationMenuAvailable)

            Button {
                notebookToolbarActions.openOrganizationMenu()
            } label: {
                Label("Organizar columnas", systemImage: "slider.horizontal.3")
            }
            .disabled(!notebookToolbarActions.organizationMenuAvailable)

            Button {
                notebookToolbarActions.openGroupManagement()
            } label: {
                Label("Gestionar grupos", systemImage: "person.2")
            }
            .disabled(!notebookToolbarActions.groupManagementAvailable)
        } label: {
            Label("Más", systemImage: "ellipsis.circle")
        }
        .help("Más acciones del cuaderno")
    }

    private var activeNotebookClass: SchoolClass? {
        let activeId = studentSelection.selectedClassId
            ?? session.bridge.notebookViewModel.currentClassId?.int64Value
            ?? session.bridge.selectedStudentsClassId
        guard let activeId else { return nil }
        return session.bridge.classes.first { $0.id == activeId }
    }

    private var activeNotebookClassLabel: String {
        guard let schoolClass = activeNotebookClass else {
            return "Seleccionar clase"
        }
        return notebookClassLabel(for: schoolClass)
    }

    private var groupedNotebookClasses: [(course: Int32, classes: [SchoolClass])] {
        let uniqueClasses = Dictionary(grouping: session.bridge.classes, by: \.id)
            .compactMap { $0.value.first }
        return Dictionary(grouping: uniqueClasses, by: \.course)
            .map { course, classes in
                (
                    course: course,
                    classes: classes.sorted {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                )
            }
            .sorted { $0.course < $1.course }
    }

    private func notebookClassLabel(for schoolClass: SchoolClass) -> String {
        "\(schoolClass.name) · \(schoolClass.course)º"
    }

    private func selectNotebookClass(_ classId: Int64) {
        studentSelection.select(classId: classId, studentId: nil)
        session.bridge.selectClass(id: classId)
        Task { @MainActor in
            await session.bridge.selectStudentsClass(classId: classId)
        }
    }

    @ToolbarContentBuilder
    private var macDefaultWorkspaceToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                Task { await session.bridge.pullMissingSyncChanges() }
            } label: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Sincronizar con desktop")

            if selectedFeature == .dashboard, let dashboardToolbarActions {
                Button {
                    dashboardToolbarActions.passList()
                } label: {
                    Label("Pasar lista", systemImage: "checkmark.circle")
                }
                .disabled(!dashboardToolbarActions.canRunActions)
                .keyboardShortcut("l", modifiers: [.command])
                .help("Pasar lista para la clase activa")

                Button {
                    dashboardToolbarActions.observation()
                } label: {
                    Label("Observación", systemImage: "note.text.badge.plus")
                }
                .disabled(!dashboardToolbarActions.canRunActions)
                .help("Registrar una observación rápida")
            }

            if selectedFeature == .attendance, let attendanceToolbarActions {
                Picker("Vista", selection: attendanceToolbarActions.mode) {
                    ForEach(AttendanceBoardMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)

                Menu {
                    Button("Todos los cursos") {
                        attendanceToolbarActions.mode.wrappedValue = .courses
                    }
                    Divider()
                    ForEach(attendanceToolbarActions.classes, id: \.id) { schoolClass in
                        Button {
                            attendanceToolbarActions.selectClass(schoolClass.id)
                        } label: {
                            if schoolClass.id == attendanceToolbarActions.selectedClassId {
                                Label(schoolClass.name, systemImage: "checkmark")
                            } else {
                                Text(schoolClass.name)
                            }
                        }
                    }
                } label: {
                    Label(attendanceSelectedClassLabel, systemImage: "rectangle.3.group")
                }
                .menuStyle(.button)

                DatePicker("", selection: attendanceToolbarActions.selectedDate, displayedComponents: .date)
                    .labelsHidden()
                    .disabled(attendanceToolbarActions.mode.wrappedValue == .courses)

                if attendanceToolbarActions.mode.wrappedValue == .day, attendanceToolbarActions.selectedClassId != nil {
                    Menu {
                        if attendanceToolbarActions.sessions.isEmpty {
                            Text("No hay sesiones planificadas")
                        } else {
                            ForEach(attendanceToolbarActions.sessions) { entry in
                                Button {
                                    attendanceToolbarActions.selectSession(entry.session.id)
                                } label: {
                                    if attendanceToolbarActions.selectedSessionId == entry.session.id {
                                        Label(attendanceToolbarActions.sessionLabel(entry), systemImage: "checkmark")
                                    } else {
                                        Text(attendanceToolbarActions.sessionLabel(entry))
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(attendanceSelectedSessionLabel, systemImage: attendanceToolbarActions.sessions.count > 1 ? "calendar.badge.clock" : "calendar")
                    }
                    .menuStyle(.button)
                    .disabled(attendanceToolbarActions.sessions.count <= 1)
                    .help(attendanceToolbarActions.sessions.count > 1 ? "Selecciona la sesión asociada a la asistencia." : "Sesión asociada automáticamente.")
                }

                Button {
                    isAttendanceFilterPopoverPresented.toggle()
                } label: {
                    Label(attendanceToolbarActions.filterLabel, systemImage: attendanceToolbarActions.filterIcon)
                }
                .disabled(attendanceToolbarActions.mode.wrappedValue == .courses)
                .popover(isPresented: $isAttendanceFilterPopoverPresented, arrowEdge: .bottom) {
                    attendanceFilterPopover(attendanceToolbarActions)
                }

                Button {
                    attendanceToolbarActions.markAllPresent()
                } label: {
                    Label("Marcar presentes", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!attendanceToolbarActions.canMarkAllPresent)
                .help("Marcar como presentes los alumnos filtrados")

                Button {
                    attendanceToolbarActions.repeatPattern()
                } label: {
                    Label("Repetir patrón", systemImage: "repeat")
                }
                .disabled(!attendanceToolbarActions.canRepeatPattern)
                .help("Repetir el último patrón de asistencia")

                if attendanceToolbarActions.canCloseSelection {
                    Button {
                        attendanceToolbarActions.clearSelection()
                    } label: {
                        Label("Cerrar ficha", systemImage: "sidebar.right")
                    }
                    .help("Cerrar el inspector del alumno")
                }
            }

            if selectedFeature == .physicalTests {
                Button {
                    physicalTestsToolbarActions.newBattery()
                } label: {
                    Label("Batería", systemImage: "plus.rectangle.on.rectangle")
                }
                .disabled(!physicalTestsToolbarActions.canUseClassActions)
                .help("Nueva batería de condición física")

                Button {
                    physicalTestsToolbarActions.capture()
                } label: {
                    Label("Captura", systemImage: "square.and.pencil")
                }
                .disabled(!physicalTestsToolbarActions.canUseClassActions)
                .help("Abrir captura de marcas")

                Button {
                    physicalTestsToolbarActions.createColumns()
                } label: {
                    Label("Cuaderno", systemImage: "tablecells")
                }
                .disabled(!physicalTestsToolbarActions.canUseClassActions)
                .help("Crear columnas de marca y nota en el cuaderno")
            }

            if selectedFeature == .planner, let plannerToolbarActions {
                Picker("Sección", selection: plannerToolbarActions.activeSection) {
                    ForEach(PlannerWorkspaceSection.allCases) { section in
                        Label(section.rawValue, systemImage: section.systemImage).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                .help("Cambiar de sección del planificador (⌘⌥1–4)")

                Button {
                    plannerToolbarActions.onPreviousWeek()
                } label: {
                    Label("Semana anterior", systemImage: "chevron.left")
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .help("Semana anterior (⌘←)")

                Button("Hoy") {
                    plannerToolbarActions.onToday()
                }
                .keyboardShortcut("t", modifiers: .command)
                .help("Ir a la semana actual (⌘T)")

                Button {
                    plannerToolbarActions.onNextWeek()
                } label: {
                    Label("Semana siguiente", systemImage: "chevron.right")
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .help("Semana siguiente (⌘→)")

                Picker("Grupo", selection: plannerToolbarActions.selectedGroupId) {
                    Text("Todos").tag(Optional<Int64>.none)
                    ForEach(plannerToolbarActions.groups, id: \.id) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }
                .frame(maxWidth: 160)
                .help("Filtrar por grupo")

                TextField("Buscar sesión, unidad, objetivo…", text: plannerToolbarActions.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 160, idealWidth: 220, maxWidth: 260)

                ShareLink(item: plannerToolbarActions.shareText) {
                    Label("Compartir semana", systemImage: "square.and.arrow.up")
                }
                .help("Compartir el resumen de la semana actual")

                Button {
                    plannerToolbarActions.onToggleSelectionMode()
                } label: {
                    Label(
                        plannerToolbarActions.isSelectionModeActive ? "Salir de selección" : "Seleccionar sesiones",
                        systemImage: plannerToolbarActions.isSelectionModeActive ? "checklist.checked" : "checklist"
                    )
                }
                .help(plannerToolbarActions.isSelectionModeActive ? "Salir del modo selección múltiple" : "Activar selección múltiple de sesiones")

                Button {
                    plannerToolbarActions.onCopyToNextWeek()
                } label: {
                    Label("Copiar a semana siguiente", systemImage: "doc.on.doc")
                }
                .disabled(!plannerToolbarActions.canCopySelection)
                .help("Copiar las sesiones seleccionadas a la semana siguiente")

                Button {
                    plannerToolbarActions.onMoveOneDay()
                } label: {
                    Label("Mover +1 día", systemImage: "arrow.right")
                }
                .disabled(!plannerToolbarActions.canCopySelection)
                .help("Mover las sesiones seleccionadas un día hacia delante")

                if plannerToolbarActions.canUndoCascadeMove {
                    Button {
                        plannerToolbarActions.onUndoCascadeMove()
                    } label: {
                        Label("Deshacer movimiento", systemImage: "arrow.uturn.backward")
                    }
                    .keyboardShortcut("z", modifiers: .command)
                    .help("Deshacer el último movimiento de sesiones (⌘Z)")
                }

                if plannerToolbarActions.canClearSchedulelessWeek {
                    Button(role: .destructive) {
                        plannerToolbarActions.onClearSchedulelessWeek()
                    } label: {
                        Label("Limpiar semana sin franjas", systemImage: "trash")
                    }
                    .help("Eliminar las sesiones planificadas de esta semana cuando no hay agenda configurada")
                }

                Button {
                    plannerToolbarActions.onNewSession()
                } label: {
                    Label("Nueva sesión", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("Nueva sesión (⌘⇧N)")
            }

            Button {
                refreshCurrentFeature()
            } label: {
                Label("Refrescar", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: [.command])
            .help("Refrescar datos")

        }

        ToolbarItem {
            MacStatusPill(
                label: session.bridge.syncPendingChanges > 0
                    ? "\(session.bridge.syncPendingChanges) pendientes"
                    : "Sincronizado",
                isActive: session.bridge.syncPendingChanges > 0,
                tint: session.bridge.syncPendingChanges > 0 ? MacAppStyle.warningTint : MacAppStyle.successTint
            )
        }
    }

    private func iconTint(for feature: MacFeatureDescriptor.Feature) -> Color {
        switch feature {
        case .dashboard: return .accentColor
        case .teacherRadar: return .accentColor
        case .courses: return .cyan
        case .notebook: return .purple
        case .attendance: return .green
        case .planner: return .orange
        case .diary: return .pink
        case .situations: return .indigo
        case .meetings: return .brown
        case .students: return .blue
        case .rubrics: return .teal
        case .physicalTests: return .orange
        case .sync: return .green
        case .backups: return .gray
        case .reports: return .indigo
        case .settings: return .secondary
        }
    }

    private func setDashboardToolbarActions(_ actions: MacDashboardToolbarActions?) {
        DispatchQueue.main.async {
            guard selectedFeature == .dashboard else { return }
            dashboardToolbarActions = actions
        }
    }

    private func setAttendanceToolbarActions(_ actions: MacAttendanceToolbarActions?) {
        DispatchQueue.main.async {
            guard selectedFeature == .attendance else { return }
            attendanceToolbarActions = actions
        }
    }

    private var attendanceSelectedClassLabel: String {
        guard let attendanceToolbarActions else { return "Curso" }
        return attendanceToolbarActions.classes.first { $0.id == attendanceToolbarActions.selectedClassId }?.name ?? "Curso"
    }

    private var attendanceSelectedSessionLabel: String {
        guard let attendanceToolbarActions else { return "Sin sesión" }
        guard let entry = attendanceToolbarActions.sessions.first(where: { $0.session.id == attendanceToolbarActions.selectedSessionId }) else {
            return "Sin sesión"
        }
        return attendanceToolbarActions.sessionLabel(entry)
    }

    private func attendanceFilterPopover(_ actions: MacAttendanceToolbarActions) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Buscar alumno", text: actions.searchText)
                .textFieldStyle(.roundedBorder)

            Picker("Estado", selection: actions.selectedStatusFilter) {
                Text("Todos").tag("TODOS")
                ForEach(AttendanceStatusOption.all) { option in
                    Text(option.label).tag(option.id)
                }
            }
            .pickerStyle(.menu)

            Button {
                actions.clearFilters()
            } label: {
                Label("Limpiar filtros", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .disabled(actions.searchText.wrappedValue.isEmpty && actions.selectedStatusFilter.wrappedValue == "TODOS")
        }
        .padding(24)
        .frame(width: 320)
    }

    private func setPlannerToolbarActions(_ actions: PlannerMacToolbarActions?) {
        DispatchQueue.main.async {
            guard selectedFeature == .planner else { return }
            plannerToolbarActions = actions
        }
    }

    private func toggleInspector() {
        let nextValue = !isInspectorVisible

        Task { @MainActor in
            await Task.yield()

            isInspectorVisible = nextValue
            columnVisibility = .all

            guard selectedFeature == .notebook else { return }
            if nextValue, notebookInspectorState.selection == nil {
                notebookToolbarActions.toggleInspector()
            } else if nextValue {
                notebookInspectorState.isPresented = true
                notebookToolbarActions.isInspectorPresented = true
            }
        }
    }

    private func toggleSidebar() {
        let nextValue: NavigationSplitViewVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        Task { @MainActor in
            await Task.yield()
            columnVisibility = nextValue
        }
    }

    private func closeNotebookInspectorStateAfterViewUpdate() {
        Task { @MainActor in
            await Task.yield()
            if notebookInspectorState.isPresented {
                notebookInspectorState.isPresented = false
            }
            if notebookToolbarActions.isInspectorPresented {
                notebookToolbarActions.isInspectorPresented = false
            }
        }
    }

    private func navigateFromDashboard(_ destination: MacDashboardDestination) {
        switch destination {
        case .attendance(let classId):
            open(module: .attendance, classId: classId, studentId: nil)
        case .notebook(let classId):
            open(module: .notebook, classId: classId, studentId: nil)
        case .rubrics(let classId):
            if let classId {
                studentSelection.setClass(classId)
            }
            selectFeature(.rubrics)
        case .plannerAgenda:
            selectFeature(.planner)
        case .plannerSession(let sessionId):
            selectedPlannerSessionId = sessionId
            selectFeature(.planner)
            if let sessionId {
                session.bridge.status = "Abriendo Planner para la sesión \(sessionId)."
            }
        case .students(let classId):
            open(module: .students, classId: classId, studentId: nil)
        case .reports(let classId):
            open(module: .reports, classId: classId, studentId: nil)
        }
    }

    @ViewBuilder
    private func sidebarContextMenu(for feature: MacFeatureDescriptor.Feature) -> some View {
        switch feature {
        case .notebook:
            if layoutState.notebookAddColumnAvailable {
                Button {
                    selectFeature(.notebook)
                    layoutState.showNotebookAddColumn()
                } label: {
                    Label("Nueva columna", systemImage: "plus.rectangle")
                }
            }
            if layoutState.notebookOrganizationMenuAvailable {
                Button {
                    selectFeature(.notebook)
                    layoutState.openNotebookOrganizationMenu()
                } label: {
                    Label("Abrir organización", systemImage: "folder.badge.gearshape")
                }
            }
        case .students:
            Button {
                selectFeature(.students)
                studentsReloadToken += 1
            } label: {
                Label("Recargar alumnado", systemImage: "arrow.clockwise")
            }
        case .attendance:
            if let attendanceToolbarActions {
                Button {
                    selectFeature(.attendance)
                    attendanceToolbarActions.markAllPresent()
                } label: {
                    Label("Todos presentes", systemImage: "checkmark.circle.fill")
                }
            }
        default:
            EmptyView()
        }
    }

    private func performPrimaryCreation() {
        switch selectedFeature {
        case .notebook:
            if notebookToolbarActions.addColumnAvailable {
                notebookToolbarActions.addColumn()
            } else if layoutState.notebookAddColumnAvailable {
                layoutState.showNotebookAddColumn()
            } else {
                showBanner("Selecciona un grupo para añadir columnas", systemImage: "plus.rectangle", tint: MacAppStyle.warningTint)
            }
        case .physicalTests:
            physicalTestsToolbarActions.newBattery()
        case .backups:
            performBackup()
        case .students:
            studentsReloadToken += 1
            showBanner("Alumnado actualizado", systemImage: "person.3.sequence", tint: MacAppStyle.infoTint)
        default:
            showBanner("Nueva acción no disponible aquí", systemImage: "plus.circle", tint: MacAppStyle.warningTint)
        }
    }

    private func focusSearch() {
        guard selectedFeature == .notebook else {
            showBanner("La búsqueda global está disponible en Cuaderno", systemImage: "magnifyingglass", tint: MacAppStyle.infoTint)
            isNotebookSearchFocused = false
            return
        }

        Task { @MainActor in
            await Task.yield()
            isNotebookSearchFocused = true
        }
    }

    private func openNotebookHiddenColumns() {
        selectFeature(.notebook)
        layoutState.openNotebookHiddenColumns()
    }

    private func openNotebookColumnOrganizer() {
        selectFeature(.notebook)
        if notebookToolbarActions.organizationMenuAvailable {
            notebookToolbarActions.openOrganizationMenu()
        } else if layoutState.notebookOrganizationMenuAvailable {
            layoutState.openNotebookOrganizationMenu()
        } else {
            showBanner("Organización no disponible", systemImage: "slider.horizontal.3", tint: MacAppStyle.warningTint)
        }
    }

    private func openReports() {
        openWindow(id: MacDesktopWindowID.reports.rawValue)
        showBanner("Informes abierto en ventana", systemImage: "doc.text.image", tint: MacAppStyle.infoTint)
    }

    private func navigateFromCommand(_ object: Any?) {
        guard let rawValue = object as? String,
              let destination = AppleAppCommandDestination(rawValue: rawValue)
        else { return }

        switch destination {
        case .notebook:
            selectFeature(.notebook)
        case .attendance:
            selectFeature(.attendance)
        case .planner:
            selectFeature(.planner)
        }
    }

    private func selectPlannerSection(_ object: Any?) {
        guard let rawValue = object as? String,
              let section = PlannerWorkspaceSection(rawValue: rawValue)
        else { return }

        if selectedFeature != .planner {
            selectFeature(.planner)
        }
        plannerToolbarActions?.activeSection.wrappedValue = section
    }

    private func performSave() {
        switch selectedFeature {
        case .notebook:
            notebookToolbarActions.refresh()
            showBanner("Guardado", systemImage: "checkmark.circle", tint: MacAppStyle.successTint)
        case .backups:
            performBackup()
        default:
            Task { await session.bridge.pullMissingSyncChanges() }
            showBanner("Sincronizando", systemImage: "arrow.triangle.2.circlepath", tint: MacAppStyle.infoTint)
        }
    }

    private func refreshCurrentFeature() {
        if selectedFeature == .dashboard, let dashboardToolbarActions {
            dashboardToolbarActions.refresh()
        } else if selectedFeature == .attendance, let attendanceToolbarActions {
            attendanceToolbarActions.refresh()
        } else if selectedFeature == .notebook {
            notebookToolbarActions.refresh()
        } else if selectedFeature == .physicalTests {
            physicalTestsToolbarActions.refresh()
        } else {
            Task { await session.bridge.refreshDashboard(mode: .office) }
        }
        showBanner("Actualizando", systemImage: "arrow.clockwise", tint: MacAppStyle.infoTint)
    }

    private func performBackup() {
        Task {
            await backupStore.createBackup()
            showBanner("Backup creado", systemImage: "externaldrive.badge.checkmark", tint: MacAppStyle.successTint)
        }
    }

    private func showBanner(_ title: String, systemImage: String, tint: Color) {
        bannerDismissTask?.cancel()
        banner = MacRootBanner(title: title, systemImage: systemImage, tint: tint)
        bannerDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            banner = nil
        }
    }

    private func open(module: AppWorkspaceModule, classId: Int64?, studentId: Int64?) {
        studentSelection.select(
            classId: classId ?? studentSelection.selectedClassId,
            studentId: studentId ?? studentSelection.selectedStudentId
        )

        switch module {
        case .teacherRadar:
            selectFeature(.dashboard)
        case .courses:
            // Cursos ya no es una entrada de la barra lateral: vive dentro de
            // Ajustes. Se pide la sección antes de navegar para que la pantalla
            // aparezca ya abierta por ella.
            SettingsNavigationStore.shared.request(.courses)
            selectFeature(.settings)
        case .notebook:
            selectFeature(.notebook)
        case .students:
            selectFeature(.students)
        case .reports:
            selectFeature(.reports)
        case .attendance:
            selectFeature(.attendance)
        case .peTests:
            selectFeature(.physicalTests)
        case .situations:
            selectFeature(.situations)
        case .diary:
            selectFeature(.diary)
        default:
            showBanner(
                "\(module.title) todavía no está disponible en la shell Mac.",
                systemImage: "exclamationmark.circle",
                tint: MacAppStyle.warningTint
            )
        }
    }
}

private struct MacRootBanner: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let tint: Color
}

private struct MacRootTransientBanner: View {
    let banner: MacRootBanner

    var body: some View {
        Label(banner.title, systemImage: banner.systemImage)
            .font(.callout.weight(.semibold))
            .foregroundStyle(banner.tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .macLiquidGlassPanel(
                .floatingBanner,
                cornerRadius: 999,
                isActive: true,
                tint: banner.tint,
                isInteractive: true
            )
            .accessibilityLabel(banner.title)
    }
}

private enum MacRootColumnVisibilityValue {
    static let all = "all"
    static let doubleColumn = "doubleColumn"
    static let detailOnly = "detailOnly"
    static let automatic = "automatic"
}

private extension NavigationSplitViewVisibility {
    init(macRootStoredValue value: String) {
        switch value {
        case MacRootColumnVisibilityValue.all:
            self = .all
        case MacRootColumnVisibilityValue.doubleColumn:
            self = .doubleColumn
        case MacRootColumnVisibilityValue.detailOnly:
            self = .detailOnly
        default:
            self = .automatic
        }
    }

    var macRootStoredValue: String {
        switch self {
        case .all:
            return MacRootColumnVisibilityValue.all
        case .doubleColumn:
            return MacRootColumnVisibilityValue.doubleColumn
        case .detailOnly:
            return MacRootColumnVisibilityValue.detailOnly
        case .automatic:
            return MacRootColumnVisibilityValue.automatic
        default:
            return MacRootColumnVisibilityValue.automatic
        }
    }
}

private struct MacModuleInspectorPlaceholder: View {
    let feature: MacFeatureDescriptor

    var body: some View {
        ContentUnavailableView(
            "\(feature.title)",
            systemImage: feature.systemImage,
            description: Text("Este módulo no tiene inspector contextual independiente en la shell Mac.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacAppStyle.cardBackground)
    }
}
