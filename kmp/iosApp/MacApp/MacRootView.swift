import SwiftUI
import AppKit
import MiGestorKit

struct MacRootView: View {
    @ObservedObject var session: MacAppSessionController
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @StateObject private var commandCenter = MacCommandCenterCoordinator()
    @StateObject private var layoutState = WorkspaceLayoutState()
    @StateObject private var notebookInspectorState = NotebookMacInspectorState()
    @StateObject private var notebookToolbarActions = NotebookMacToolbarActions()
    @StateObject private var physicalTestsToolbarActions = MacPhysicalTestsToolbarActions()
    @StateObject private var physicalTestsInspectorState = PhysicalTestsMacInspectorState()
    @StateObject private var studentsStore = MacStudentsStore()
    @StateObject private var studentSelection = StudentSelectionStore()
    @StateObject private var backupStore: MacBackupStore
    @SceneStorage("mac.root.columnVisibility") private var storedColumnVisibility = MacRootColumnVisibilityValue.all
    @SceneStorage("mac.root.inspectorVisible") private var storedInspectorVisible = true
    @State private var attendanceToolbarActions: MacAttendanceToolbarActions? = nil
    @State private var dashboardToolbarActions: MacDashboardToolbarActions? = nil
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
        _backupStore = StateObject(wrappedValue: MacBackupStore(bridge: session.bridge))
    }

    var body: some View {
        Group {
            switch session.bootstrapState {
            case .idle, .loading:
                ProgressView("Preparando shell macOS…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MacAppStyle.pageBackground)
            case .failed(let message):
                ContentUnavailableView(
                    "No se pudo iniciar la shell Mac",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MacAppStyle.pageBackground)
            case .ready:
                navigationSplit
            }
        }
        .onAppear {
            selectedFeature = session.selectedFeature
            columnVisibility = NavigationSplitViewVisibility(macRootStoredValue: storedColumnVisibility)
            isInspectorVisible = storedInspectorVisible && session.inspectorVisible
        }
        .task {
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
    }

    private func startCommandCenterAfterInitialLayout() async {
        guard !didRequestCommandCenterStart else { return }
        didRequestCommandCenterStart = true
        await Task.yield()
        commandCenter.startIfNeeded()
    }

    @ViewBuilder
    private var navigationSplit: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            macSidebar
        } detail: {
            featureContent(for: selectedFeature)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MacAppStyle.pageBackground)
                .inspector(isPresented: $isInspectorVisible) {
                    featureInspector(for: selectedFeature)
                        .frame(minWidth: 320, idealWidth: 360, maxWidth: 440)
                        .background(MacAppStyle.pageBackground)
                }
        }
        .navigationSplitViewStyle(.balanced)
        .overlay(alignment: .topTrailing) {
            if let banner {
                MacRootTransientBanner(banner: banner)
                    .padding(.top, 12)
                    .padding(.trailing, 16)
                    .transition(uiFeatureFlags.bannerTransition)
            }
        }
        .animation(uiFeatureFlags.interactionAnimation, value: banner?.id)
        .toolbar {
            macToolbar
        }
        .onReceive(NotificationCenter.default.publisher(for: .macRootNewItemRequested)) { _ in
            performPrimaryCreation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macRootSaveRequested)) { _ in
            performSave()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macRootRefreshRequested)) { _ in
            refreshCurrentFeature()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macRootToggleSidebarRequested)) { _ in
            toggleSidebar()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macRootToggleInspectorRequested)) { _ in
            toggleInspector()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macRootBackupRequested)) { _ in
            performBackup()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macRootExportRequested)) { _ in
            selectFeature(.reports)
            showBanner("Informes", systemImage: "doc.text.image", tint: MacAppStyle.infoTint)
        }
        .appOnChange(of: session.selectedFeature) { newFeature in
            guard selectedFeature != newFeature else { return }
            Task { @MainActor in
                await Task.yield()
                selectFeature(newFeature, propagateToSession: false)
            }
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

    private func selectFeature(
        _ feature: MacFeatureDescriptor.Feature,
        propagateToSession: Bool = true
    ) {
        guard selectedFeature != feature || session.selectedFeature != feature else { return }
        selectedFeature = feature
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
                backupStore: backupStore,
                bootstrap: session.bootstrap,
                onNavigate: navigateFromDashboard,
                onToolbarActionsChange: setDashboardToolbarActions
            )
        case .teacherRadar:
            TeacherRadarDetailView(
                bridge: session.bridge,
                selectedClassId: studentSelection.selectedClassBinding,
                selectedStudentId: studentSelection.selectedStudentBinding,
                onOpenModule: open(module:classId:studentId:)
            )
        case .notebook:
            NotebookMacLayout(
                bridge: session.bridge,
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
                selectedClassId: studentSelection.selectedClassBinding,
                selectedStudentId: studentSelection.selectedStudentBinding,
                onOpenModule: open(module:classId:studentId:),
                onToolbarActionsChange: setAttendanceToolbarActions
            )
        case .students:
            MacStudentsView(
                bridge: session.bridge,
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
            PlannerMacLayout(bridge: session.bridge, selectedSessionId: $selectedPlannerSessionId)
        case .situations:
            LearningSituationsWorkspaceView(
                selectedClassId: studentSelection.selectedClassBinding,
                onOpenModule: open(module:classId:studentId:)
            )
            .environmentObject(session.bridge)
        case .sync:
            MacSyncView(bridge: session.bridge, commandCenter: commandCenter)
        case .backups:
            MacBackupsView(store: backupStore)
        case .settings:
            MacSettingsView(session: session, commandCenter: commandCenter, backupStore: backupStore) {
                selectFeature(.sync)
            }
        }
    }

    @ViewBuilder
    private func featureInspector(for feature: MacFeatureDescriptor.Feature) -> some View {
        switch feature {
        case .notebook:
            NotebookMacLayout(
                bridge: session.bridge,
                layoutState: layoutState,
                toolbarActions: notebookToolbarActions,
                inspectorState: notebookInspectorState,
                selectedClassId: studentSelection.selectedClassBinding,
                selectedStudentId: studentSelection.selectedStudentBinding,
                onOpenModule: open(module:classId:studentId:),
                presentation: .inspector
            )
        case .students:
            MacStudentsView(
                bridge: session.bridge,
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
        default:
            MacModuleInspectorPlaceholder(feature: MacFeatureRegistry.descriptor(for: feature))
        }
    }

    @ToolbarContentBuilder
    private var macToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                toggleSidebar()
            } label: {
                Label("Barra lateral", systemImage: "sidebar.leading")
            }
            .help("Mostrar/Ocultar barra lateral (⌘⌥S)")
        }

        if selectedFeature == .notebook {
            macNotebookToolbar
        } else {
            macDefaultWorkspaceToolbar
        }
    }

    @ToolbarContentBuilder
    private var macNotebookToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            macNotebookClassSelector
                .layoutPriority(3)

            if session.bridge.syncPendingChanges > 0 {
                MacStatusPill(
                    label: "\(session.bridge.syncPendingChanges) pendientes",
                    isActive: true,
                    tint: MacAppStyle.warningTint
                )
            }

            Button {
                notebookToolbarActions.addColumn()
            } label: {
                Label("Nueva columna", systemImage: "plus")
            }
            .disabled(!notebookToolbarActions.addColumnAvailable)
            .keyboardShortcut("n", modifiers: .command)
            .help("Añadir nueva columna (⌘N)")
            .layoutPriority(3)

            Button {
                toggleInspector()
            } label: {
                Label(isInspectorVisible ? "Ocultar inspector" : "Mostrar inspector", systemImage: "sidebar.right")
            }
            .keyboardShortcut("i", modifiers: [.command])
            .help(isInspectorVisible ? "Ocultar inspector" : "Mostrar inspector")
            .layoutPriority(2)

            Label("Buscar", systemImage: "magnifyingglass")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .layoutPriority(2)

            TextField("Buscar", text: Binding(
                get: { layoutState.notebookSearchText },
                set: { layoutState.setNotebookSearchText($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 160, idealWidth: 220, maxWidth: 260)
            .layoutPriority(2)

            macNotebookOverflowMenu
                .layoutPriority(1)
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
                Button {
                    attendanceToolbarActions.markAllPresent()
                } label: {
                    Label("Todos presentes", systemImage: "checkmark.circle.fill")
                }
                .help("Marcar como presentes los alumnos filtrados")

                Button {
                    attendanceToolbarActions.repeatPattern()
                } label: {
                    Label("Repetir patrón", systemImage: "repeat")
                }
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

            Button {
                refreshCurrentFeature()
            } label: {
                Label("Refrescar", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: [.command])
            .help("Refrescar datos")

            Button {
                toggleInspector()
            } label: {
                Label(isInspectorVisible ? "Ocultar inspector" : "Mostrar inspector", systemImage: "sidebar.right")
            }
            .keyboardShortcut("i", modifiers: [.command])
            .help(isInspectorVisible ? "Ocultar inspector" : "Mostrar inspector")
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
        case .teacherRadar: return .red
        case .notebook: return .purple
        case .attendance: return .green
        case .planner: return .orange
        case .situations: return .indigo
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
            if layoutState.notebookAddColumnAvailable {
                layoutState.showNotebookAddColumn()
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
            selectFeature(.teacherRadar)
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
        default:
            session.bridge.status = "El módulo \(module.title) todavía no está disponible en la shell Mac."
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
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
            .accessibilityLabel(banner.title)
    }
}

extension Notification.Name {
    static let macRootNewItemRequested = Notification.Name("macRootNewItemRequested")
    static let macRootSaveRequested = Notification.Name("macRootSaveRequested")
    static let macRootRefreshRequested = Notification.Name("macRootRefreshRequested")
    static let macRootToggleInspectorRequested = Notification.Name("macRootToggleInspectorRequested")
    static let macRootToggleSidebarRequested = Notification.Name("macRootToggleSidebarRequested")
    static let macRootBackupRequested = Notification.Name("macRootBackupRequested")
    static let macRootExportRequested = Notification.Name("macRootExportRequested")
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
