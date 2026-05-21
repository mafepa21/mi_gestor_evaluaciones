import SwiftUI
import MiGestorKit

// MARK: - IOSRootView
// iPad-first workspace shell equivalent to MacRootView on macOS.
// Uses NavigationSplitView (sidebar + detail) to provide a genuine desktop-touch
// experience, with a contextual toolbar and a transient banner overlay.
// Only compiled on iOS; the Mac target uses MacRootView.

#if !os(macOS)

// MARK: - Banner model
struct IOSRootBanner: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let systemImage: String
    let tint: Color

    static func == (lhs: IOSRootBanner, rhs: IOSRootBanner) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - IOSRootView
struct IOSRootView: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var layoutState = WorkspaceLayoutState()
    @StateObject private var selectionStore = StudentSelectionStore()

    // Scene storage keeps state across scene lifecycle
    @SceneStorage("ios.root.sidebarVisible") private var sidebarVisible = true
    @SceneStorage("ios.root.inspectorVisible") private var inspectorVisible = true
    @AppStorage("workspace.active.module") private var persistedModule = AppWorkspaceModule.dashboard.rawValue
    @AppStorage("workspace.selected.class.id") private var persistedClassId: Int = 0
    @AppStorage("workspace.selected.student.id") private var persistedStudentId: Int = 0

    @State private var activeModule: AppWorkspaceModule = .dashboard
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var banner: IOSRootBanner?
    @State private var bannerDismissTask: Task<Void, Never>?
    @State private var plannerContext = PlannerNavigationContext()
    @State private var activeSheet: ActiveWorkspaceSheet?
    @State private var showingRubricBuilder = false
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            IOSWorkspaceSidebar(
                activeModule: activeModule,
                onSelectModule: selectModule(_:)
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
        } detail: {
            VStack(spacing: 0) {
                IOSGlobalContextRow(
                    activeModule: activeModule,
                    layoutState: layoutState,
                    selectionStore: selectionStore,
                    searchText: $searchText
                )
                Divider().opacity(0.24)
                IOSWorkspaceContent(
                    activeModule: activeModule,
                    layoutState: layoutState,
                    selectionStore: selectionStore,
                    plannerContext: plannerContext,
                    activeSheet: $activeSheet,
                    showingRubricBuilder: $showingRubricBuilder,
                    searchText: $searchText,
                    onOpenModule: openModule(_:classId:studentId:),
                    onUpdatePlannerContext: { plannerContext = $0 },
                    onShowBanner: showBanner(_:)
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            IOSContextualToolbar(
                activeModule: activeModule,
                layoutState: layoutState,
                selectionStore: selectionStore,
                onSync: { Task { await bridge.pullMissingSyncChanges() } },
                onToggleInspector: toggleInspector
            )
        }
        .overlay(alignment: .top) {
            IOSBannerHost(banner: banner)
                .padding(.top, 8)
        }
        .sheet(item: $activeSheet) { sheet in
            iosSheetContent(for: sheet)
        }
        .appFullScreenCover(isPresented: $showingRubricBuilder) {
            RubricsBuilderScreen()
                .environmentObject(bridge)
        }
        .task {
            await bridge.ensureClassesLoaded()
            try? await bridge.refreshStudentsDirectory()
            try? await bridge.refreshRubrics()
            try? await bridge.refreshRubricClassLinks()
            restorePersistedState()
        }
        .appOnChange(of: activeModule) { newValue in
            persistedModule = newValue.rawValue
        }
        .appOnChange(of: selectionStore.selectedClassId) { newId in
            persistedClassId = Int(newId ?? 0)
            plannerContext.groupId = newId
            Task { await bridge.selectStudentsClass(classId: newId) }
            if let newId {
                bridge.selectClass(id: newId)
            }
        }
        .appOnChange(of: selectionStore.selectedStudentId) { newId in
            persistedStudentId = Int(newId ?? 0)
        }
        .appOnChange(of: layoutState.isSidebarVisible) { visible in
            columnVisibility = visible ? .all : .detailOnly
        }
        .appOnChange(of: columnVisibility) { newVisibility in
            // Persist sidebar visibility back into layoutState for toolbar sync
            let isVisible = newVisibility != .detailOnly
            if layoutState.isSidebarVisible != isVisible {
                layoutState.isSidebarVisible = isVisible
            }
        }
        .appWritingToolsDisabled()
    }

    // MARK: Persistence helpers
    private func restorePersistedState() {
        activeModule = AppWorkspaceModule(rawValue: persistedModule) ?? .dashboard
        if persistedClassId > 0,
           bridge.classes.contains(where: { $0.id == Int64(persistedClassId) }) {
            selectionStore.setClass(Int64(persistedClassId))
        } else if selectionStore.selectedClassId == nil {
            selectionStore.setClass(bridge.selectedStudentsClassId ?? bridge.classes.first?.id)
        }
        if persistedStudentId > 0 {
            selectionStore.setStudent(Int64(persistedStudentId))
        }
        columnVisibility = sidebarVisible ? .all : .detailOnly
    }

    // MARK: Navigation
    private func selectModule(_ module: AppWorkspaceModule) {
        guard activeModule != module else { return }
        activeModule = module
        searchText = ""
    }

    func openModule(_ module: AppWorkspaceModule, classId: Int64? = nil, studentId: Int64? = nil) {
        activeModule = module
        if let classId {
            selectionStore.setClass(classId)
            bridge.selectClass(id: classId)
        }
        if let studentId {
            selectionStore.setStudent(studentId)
        }
        searchText = ""
    }

    // MARK: Inspector
    private func toggleInspector() {
        inspectorVisible.toggle()
        // Delegate to module-specific inspector action when available
        switch activeModule {
        case .notebook:  layoutState.toggleNotebookInspector()
        case .dashboard: layoutState.toggleDashboardInspector()
        case .diary:     layoutState.toggleDiaryInspector()
        default:         break
        }
    }

    // MARK: Banner
    func showBanner(_ banner: IOSRootBanner) {
        bannerDismissTask?.cancel()
        withAnimation(.snappy(duration: 0.18)) { self.banner = banner }
        bannerDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.18)) { self.banner = nil }
        }
    }

    // MARK: Sheet builder
    @ViewBuilder
    private func iosSheetContent(for sheet: ActiveWorkspaceSheet) -> some View {
        switch sheet {
        case .create(let kind):
            switch kind {
            case .course:
                CreateCourseSheet { activeSheet = nil }
                    .environmentObject(bridge)
            case .student:
                CreateStudentSheet(defaultClassId: selectionStore.selectedClassId) { activeSheet = nil }
                    .environmentObject(bridge)
            case .evaluation:
                CreateEvaluationSheet(defaultClassId: selectionStore.selectedClassId) { activeSheet = nil }
                    .environmentObject(bridge)
            }
        case .contextualAI(let state):
            ContextualAIAssistantSheet(
                bridge: bridge,
                module: state.module,
                context: state.context
            )
        case .classroomCapture(_):
            EmptyView() // Handled inline by IOSWorkspaceContent
        case .bulkRubricEvaluation:
            RubricBulkEvaluationSheet(bridge: bridge)
                .presentationDetents([.large])
        }
    }
}

// MARK: - IOSGlobalContextRow
struct IOSGlobalContextRow: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme

    let activeModule: AppWorkspaceModule
    @ObservedObject var layoutState: WorkspaceLayoutState
    @ObservedObject var selectionStore: StudentSelectionStore
    @Binding var searchText: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                moduleTitle
                Spacer(minLength: 12)
                classMenu
                searchField
            }

            VStack(alignment: .leading, spacing: 12) {
                moduleTitle
                HStack(spacing: 12) {
                    classMenu
                    searchField
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(appMutedCardBackground(for: colorScheme).opacity(0.94))
    }

    private var moduleTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(activeModule.subtitle.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(activeModule.title)
                .font(.system(size: 24, weight: .black, design: .rounded))
        }
        .frame(minWidth: 180, alignment: .leading)
    }

    private var classMenu: some View {
        Menu {
            Button("Sin clase activa") {
                selectionStore.setClass(nil)
            }
            ForEach(bridge.classes, id: \.id) { schoolClass in
                Button {
                    selectionStore.setClass(schoolClass.id)
                } label: {
                    HStack {
                        Text(schoolClass.name)
                        if selectionStore.selectedClassId == schoolClass.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(activeClassLabel, systemImage: "rectangle.3.group")
                .lineLimit(1)
                .frame(minWidth: 220, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(searchPlaceholder, text: activeSearchBinding)
                .textFieldStyle(.plain)
            if !activeSearchBinding.wrappedValue.isEmpty {
                Button {
                    activeSearchBinding.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: 520)
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var activeClassLabel: String {
        guard let classId = selectionStore.selectedClassId,
              let schoolClass = bridge.classes.first(where: { $0.id == classId }) else {
            return "Clase global"
        }
        return schoolClass.name
    }

    private var searchPlaceholder: String {
        activeModule == .notebook ? "Buscar alumno..." : "Buscar módulos, grupos o alumnado..."
    }

    private var activeSearchBinding: Binding<String> {
        Binding(
            get: {
                switch activeModule {
                case .notebook:
                    return layoutState.notebookSearchText
                case .attendance:
                    return layoutState.attendanceSearchText
                default:
                    return searchText
                }
            },
            set: { newValue in
                switch activeModule {
                case .notebook:
                    layoutState.setNotebookSearchText(newValue)
                case .attendance:
                    layoutState.setAttendanceSearchText(newValue)
                default:
                    searchText = newValue
                }
            }
        )
    }
}

// MARK: - IOSWorkspaceSidebar
struct IOSWorkspaceSidebar: View {
    let activeModule: AppWorkspaceModule
    let onSelectModule: (AppWorkspaceModule) -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MiGestor")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                    Text("App docente iPad-first")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Uso diario") {
                ForEach(IOSFeatureRegistry.daily) { feature in
                    sidebarRow(for: feature)
                }
            }

            Section("Más herramientas") {
                ForEach(IOSFeatureRegistry.secondary) { feature in
                    sidebarRow(for: feature)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Workspace")
    }

    @ViewBuilder
    private func sidebarRow(for feature: IOSFeatureDescriptor) -> some View {
        let isSelected = activeModule == feature.module
        Button {
            onSelectModule(feature.module)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: feature.systemImage)
                    .frame(width: 22, height: 22)
                    .foregroundColor(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(feature.title)
                        .font(.callout.weight(.medium))
                        .foregroundColor(isSelected ? Color.accentColor : Color.primary)
                    Text(feature.subtitle)
                        .font(.caption2)
                        .foregroundColor(Color.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .listRowBackground(
            isSelected
                ? AnyView(Color.accentColor.opacity(0.1).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)))
                : AnyView(Color.clear)
        )
    }
}

// MARK: - IOSWorkspaceContent
/// The detail pane of the split view. Delegates all module rendering to AppWorkspaceShell's
/// existing activeWorkspace system, keeping feature parity without duplicating code.
struct IOSWorkspaceContent: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme

    let activeModule: AppWorkspaceModule
    @ObservedObject var layoutState: WorkspaceLayoutState
    @ObservedObject var selectionStore: StudentSelectionStore
    var plannerContext: PlannerNavigationContext
    @Binding var activeSheet: ActiveWorkspaceSheet?
    @Binding var showingRubricBuilder: Bool
    @Binding var searchText: String

    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    let onUpdatePlannerContext: (PlannerNavigationContext) -> Void
    let onShowBanner: (IOSRootBanner) -> Void

    var body: some View {
        moduleContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environmentObject(layoutState)
    }

    @ViewBuilder
    private var moduleContent: some View {
        switch activeModule {
        case .dashboard, .courses, .students, .teacherRadar, .notebook,
             .attendance, .planner, .diary, .evaluationHub:
            academicContent
        default:
            evaluationAndPEContent
        }
    }

    @ViewBuilder
    private var academicContent: some View {
        switch activeModule {
        case .dashboard:
            DashboardView(selectedClassId: selectionStore.selectedClassBinding)
        case .courses:
            CoursesWorkspaceView(
                selectedClassId: selectionStore.selectedClassBinding,
                onOpenModule: onOpenModule,
                onCreateStudent: { classId in
                    selectionStore.setClass(classId)
                    activeSheet = .create(.student)
                }
            )
            .environmentObject(bridge)
        case .students:
            StudentProfilesWorkspaceView(
                selectedClassId: selectionStore.selectedClassBinding,
                selectedStudentId: selectionStore.selectedStudentBinding,
                onOpenModule: onOpenModule
            )
            .environmentObject(bridge)
        case .teacherRadar:
            TeacherRadarDetailView(
                bridge: bridge,
                selectedClassId: selectionStore.selectedClassBinding,
                selectedStudentId: selectionStore.selectedStudentBinding,
                onOpenModule: onOpenModule
            )
        case .notebook:
            NotebookModuleView(
                bridge: bridge,
                selectedClassId: selectionStore.selectedClassBinding,
                selectedStudentId: selectionStore.selectedStudentBinding,
                onOpenModule: onOpenModule
            )
        case .attendance:
            AttendanceWorkspaceView(
                selectedClassId: selectionStore.selectedClassBinding,
                preselectedStudentId: selectionStore.selectedStudentBinding,
                onOpenModule: onOpenModule
            )
            .environmentObject(bridge)
        case .planner:
            PlannerWorkspaceIOS(
                context: resolvedPlannerContext,
                onOpenDiary: { ctx in onOpenModule(.diary, ctx.groupId, nil); onUpdatePlannerContext(ctx) },
                onOpenSettings: { onOpenModule(.settings, selectionStore.selectedClassId, nil) },
                onNavigationContextChange: onUpdatePlannerContext
            )
            .environmentObject(bridge)
        case .diary:
            DiaryWorkspaceView(
                selectedClassId: selectionStore.selectedClassBinding,
                navigationContext: resolvedPlannerContext,
                onOpenModule: onOpenModule,
                onOpenPlanner: { ctx in onOpenModule(.planner, ctx.groupId, nil); onUpdatePlannerContext(ctx) },
                onNavigationContextChange: onUpdatePlannerContext
            )
            .environmentObject(bridge)
        case .evaluationHub:
            EvaluationHubView(
                selectedClassId: selectionStore.selectedClassBinding,
                onOpenModule: onOpenModule
            )
            .environmentObject(bridge)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var evaluationAndPEContent: some View {
        switch activeModule {
        case .rubrics:
            RubricsWorkspaceView(
                selectedClassId: selectionStore.selectedClassBinding,
                onOpenModule: onOpenModule,
                onOpenBuilder: { bridge.resetRubricBuilder(); showingRubricBuilder = true },
                onEditRubric: { rubric in bridge.loadRubricForEditing(rubric); showingRubricBuilder = true }
            )
            .environmentObject(bridge)
        case .reports:
            ReportsWorkspaceView(
                selectedClassId: selectionStore.selectedClassBinding,
                selectedStudentId: selectionStore.selectedStudentBinding
            )
            .environmentObject(bridge)
        case .library:
            LibraryWorkspaceView(
                selectedClassId: selectionStore.selectedClassBinding,
                onOpenModule: onOpenModule
            )
            .environmentObject(bridge)
        case .peSessions:
            PESessionsWorkspaceView(
                selectedClassId: selectionStore.selectedClassBinding,
                onOpenModule: onOpenModule
            )
            .environmentObject(bridge)
        case .peTests:
            PhysicalTestsWorkspaceView(
                selectedClassId: selectionStore.selectedClassBinding,
                onOpenModule: onOpenModule
            )
            .environmentObject(bridge)
        case .peRubrics:
            RubricsWorkspaceView(
                selectedClassId: selectionStore.selectedClassBinding,
                onOpenModule: onOpenModule,
                onOpenBuilder: { bridge.resetRubricBuilder(); showingRubricBuilder = true },
                onEditRubric: { rubric in bridge.loadRubricForEditing(rubric); showingRubricBuilder = true },
                peMode: true
            )
            .environmentObject(bridge)
        case .peIncidents:
            EFIncidentsWorkspaceView(
                selectedClassId: selectionStore.selectedClassBinding,
                onOpenModule: onOpenModule
            )
            .environmentObject(bridge)
        case .peMaterial:
            PEMaterialWorkspaceView(
                selectedClassId: selectionStore.selectedClassBinding,
                onOpenModule: onOpenModule
            )
            .environmentObject(bridge)
        case .peTournaments:
            PETournamentsWorkspaceView(selectedClassId: selectionStore.selectedClassBinding)
                .environmentObject(bridge)
        case .settings:
            SettingsWorkspaceView()
                .environmentObject(bridge)
        case .backups:
            BackupsWorkspaceView(selectedClassId: selectionStore.selectedClassBinding)
        default:
            EmptyView()
        }
    }

    private var resolvedPlannerContext: PlannerNavigationContext {
        PlannerNavigationContext(
            week: plannerContext.week,
            year: plannerContext.year,
            groupId: plannerContext.groupId ?? selectionStore.selectedClassId,
            sessionId: plannerContext.sessionId
        )
    }
}

// MARK: - IOSContextualToolbar
/// Renders contextual toolbar items that adapt to the active module,
/// mirroring what MacRootView does with its macToolbar.
struct IOSContextualToolbar: ToolbarContent {
    let activeModule: AppWorkspaceModule
    @ObservedObject var layoutState: WorkspaceLayoutState
    @ObservedObject var selectionStore: StudentSelectionStore
    let onSync: () -> Void
    let onToggleInspector: () -> Void

    var body: some ToolbarContent {
        // Sync — always present on the trailing side
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: onSync) {
                Label("Sincronizar", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Sincronizar cambios pendientes")
        }

        // Notebook-specific actions
        if activeModule == .notebook {
            ToolbarItem(placement: .topBarTrailing) {
                Button { layoutState.showNotebookAddColumn() } label: {
                    Label("Añadir columna", systemImage: "plus.rectangle.on.rectangle")
                }
                .disabled(!layoutState.notebookAddColumnAvailable)
                .help("Añadir columna de evaluación")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { layoutState.openNotebookOrganizationMenu() } label: {
                    Label("Organizar", systemImage: "list.bullet.indent")
                }
                .disabled(!layoutState.notebookOrganizationMenuAvailable)
                .help("Organizar columnas y pestañas")
            }
        }

        // Dashboard-specific actions
        if activeModule == .dashboard {
            ToolbarItem(placement: .topBarTrailing) {
                Button { layoutState.dashboardPassList() } label: {
                    Label("Pasar lista", systemImage: "checkmark.circle")
                }
                .disabled(!layoutState.dashboardActionsAvailable)
                .help("Pasar lista para la clase activa")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { layoutState.dashboardObservation() } label: {
                    Label("Observación", systemImage: "note.text.badge.plus")
                }
                .disabled(!layoutState.dashboardActionsAvailable)
                .help("Registrar una observación rápida")
            }
        }

        // Attendance-specific actions
        if activeModule == .attendance {
            ToolbarItem(placement: .topBarTrailing) {
                Button { layoutState.attendanceMarkAllPresent() } label: {
                    Label("Todos presentes", systemImage: "checkmark.circle.fill")
                }
                .help("Marcar como presentes todos los alumnos filtrados")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { layoutState.attendanceRepeatPattern() } label: {
                    Label("Repetir patrón", systemImage: "repeat")
                }
                .help("Repetir el último patrón de asistencia")
            }
            if layoutState.attendanceHasSelection {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { layoutState.attendanceClearSelection() } label: {
                        Label("Cerrar ficha", systemImage: "xmark.circle")
                    }
                    .help("Cerrar la ficha del alumno seleccionado")
                }
            }
        }

        // Inspector toggle — for modules that support it
        if activeModule.supportsInspector {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onToggleInspector) {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help("Mostrar u ocultar el inspector")
            }
        }
    }
}

// MARK: - AppWorkspaceModule + Inspector support
private extension AppWorkspaceModule {
    var supportsInspector: Bool {
        switch self {
        case .notebook, .dashboard, .diary, .students: return true
        default: return false
        }
    }
}

// MARK: - IOSBannerHost
/// Top overlay for transient status/confirmation messages.
struct IOSBannerHost: View {
    let banner: IOSRootBanner?

    var body: some View {
        if let banner {
            HStack(spacing: 10) {
                Image(systemName: banner.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(banner.tint)
                Text(banner.message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 6)
            .padding(.horizontal, 24)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.snappy(duration: 0.18), value: banner.id)
            .zIndex(999)
        }
    }
}

#endif // !os(macOS)
