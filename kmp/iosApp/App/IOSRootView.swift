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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags

    @StateObject private var layoutState = WorkspaceLayoutState()
    @StateObject private var selectionStore = IOSSelectionStore()
    @StateObject private var notebookStore = NotebookBridgeStore()
    @StateObject private var dashboardStore = DashboardBridgeStore()
    @StateObject private var studentsBridgeStore = StudentsBridgeStore()
    @StateObject private var attendanceStore = AttendanceBridgeStore()

    // Scene storage keeps state across scene lifecycle
    @SceneStorage("ios.root.sidebarVisible") private var sidebarVisible = true
    @AppStorage("workspace.active.module") private var persistedModule = AppWorkspaceModule.dashboard.rawValue
    @AppStorage("workspace.selected.class.id") private var persistedClassId: Int = 0
    @AppStorage("workspace.selected.student.id") private var persistedStudentId: Int = 0
    @AppStorage("teacher.enabledSubjectProfiles.v1") private var enabledSubjectProfilesRaw = TeacherSubjectProfile.general.rawValue

    @State private var activeModule: AppWorkspaceModule = .dashboard
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var banner: IOSRootBanner?
    @State private var bannerDismissTask: Task<Void, Never>?
    @State private var classSelectionTask: Task<Void, Never>?
    @State private var plannerContext = PlannerNavigationContext()
    @State private var activeSheet: ActiveWorkspaceSheet?
    @State private var showingRubricBuilder = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            IOSWorkspaceSidebar(
                activeModule: activeModule,
                onSelectModule: selectModule(_:)
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
        } detail: {
            VStack(spacing: 0) {
                if activeModule != .notebook && !(activeModule == .attendance && horizontalSizeClass == .regular) {
                    IOSGlobalContextRow(
                        activeModule: activeModule,
                        layoutState: layoutState,
                        selectionStore: selectionStore
                    )
                    Divider().opacity(0.24)
                }
                IOSWorkspaceContent(
                    activeModule: activeModule,
                    layoutState: layoutState,
                    selectionStore: selectionStore,
                    notebookStore: notebookStore,
                    dashboardStore: dashboardStore,
                    studentsBridgeStore: studentsBridgeStore,
                    attendanceStore: attendanceStore,
                    plannerContext: plannerContext,
                    activeSheet: $activeSheet,
                    showingRubricBuilder: $showingRubricBuilder,
                    onOpenModule: openModule(_:classId:studentId:),
                    onUpdatePlannerContext: { plannerContext = $0 },
                    onShowBanner: showBanner(_:)
                )
            }
            .toolbar {
                if activeModule == .notebook && horizontalSizeClass == .regular {
                    notebookToolbarItems
                } else if activeModule == .attendance && horizontalSizeClass == .regular {
                    attendanceToolbarItems
                } else {
                    IOSContextualToolbar(
                        activeModule: activeModule,
                        layoutState: layoutState,
                        selectionStore: selectionStore,
                        onSync: { Task { await bridge.pullMissingSyncChanges() } },
                        onToggleInspector: toggleInspector
                    )
                }
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .overlay(alignment: .top) {
            IOSBannerHost(banner: banner)
                .padding(.top, 8)
        }
        .sheet(item: $activeSheet) { sheet in
            iosSheetContent(for: sheet)
        }
        .onboardingHost(bridge: bridge) { module in
            openModule(module, classId: nil, studentId: nil)
        }
        .appFullScreenCover(isPresented: $showingRubricBuilder) {
            RubricsBuilderScreen()
                .environmentObject(bridge)
        }
        .task {
            notebookStore.bind(to: bridge)
            dashboardStore.bind(to: bridge)
            studentsBridgeStore.bind(to: bridge)
            attendanceStore.bind(to: bridge)

            // Restore UI layout state immediately to show the sidebar/left menu right away
            restorePersistedUIState()
            
            await bridge.ensureClassesLoaded()
            try? await bridge.refreshStudentsDirectory()
            try? await bridge.refreshRubrics()
            try? await bridge.refreshRubricClassLinks()
            
            // Restore class and student selection after KMP data is loaded
            await restorePersistedDataState()

            // Con los datos ya cargados: decidir si toca la bienvenida de
            // primer uso. Antes de este punto la base parecería vacía.
            await OnboardingStore.shared.bootstrap(bridge: bridge)
        }
        .appOnChange(of: activeModule) { newValue in
            persistedModule = newValue.rawValue
        }
        .appOnChange(of: enabledSubjectProfilesRaw) { _ in
            let normalized = normalizedModule(activeModule)
            if normalized != activeModule {
                activeModule = normalized
            }
        }
        .appOnChange(of: selectionStore.selectedClassId) { newId in
            persistedClassId = Int(newId ?? 0)
            plannerContext.groupId = newId
            if let newId {
                bridge.selectClass(id: newId)
            }
            classSelectionTask?.cancel()
            classSelectionTask = Task {
                await bridge.selectStudentsClass(classId: newId)
                guard !Task.isCancelled else { return }
                if let newId = newId {
                    if let studentId = selectionStore.selectedStudentId {
                        let students = (try? await bridge.students(forClassId: newId)) ?? bridge.studentsInClass
                        guard !Task.isCancelled else { return }
                        if !students.contains(where: { $0.id == studentId }) {
                            await MainActor.run {
                                selectionStore.selectedStudentId = nil
                            }
                        }
                    }
                } else {
                    await MainActor.run {
                        selectionStore.selectedStudentId = nil
                    }
                }
            }
        }
        .task(id: selectionStore.selectedClassId) {
            guard let classId = selectionStore.selectedClassId else { return }
            await bridge.preloadClassWorkspace(classId: classId)
        }
        .appOnChange(of: selectionStore.selectedStudentId) { newId in
            persistedStudentId = Int(newId ?? 0)
        }
        .appOnChange(of: layoutState.isSidebarVisible) { visible in
            let target: NavigationSplitViewVisibility = visible ? .all : .detailOnly
            if columnVisibility != target {
                columnVisibility = target
            }
        }
        .appOnChange(of: columnVisibility) { newVisibility in
            // Sync user-driven sidebar gesture back to layoutState.
            // Only update when it differs to avoid feedback cycles.
            let isVisible = newVisibility != .detailOnly
            if layoutState.isSidebarVisible != isVisible {
                layoutState.isSidebarVisible = isVisible
            }
            if sidebarVisible != isVisible {
                sidebarVisible = isVisible
            }
        }
        .appWritingToolsDisabled()
    }

    // MARK: Persistence helpers
    private func restorePersistedUIState() {
        activeModule = normalizedModule(AppWorkspaceModule(rawValue: persistedModule) ?? .dashboard)
        columnVisibility = sidebarVisible ? .all : .detailOnly
    }

    private func normalizedModule(_ module: AppWorkspaceModule) -> AppWorkspaceModule {
        if module == .teacherRadar { return .dashboard }
        // Un módulo `.courses` restaurado de una versión anterior dejaría la
        // barra lateral sin nada marcado: ahora vive dentro de Ajustes.
        if module == .courses { return .settings }
        if module.requiresPhysicalEducationProfile {
            let enabledProfiles = TeacherSubjectProfile.decodeSet(enabledSubjectProfilesRaw)
            if !enabledProfiles.contains(.physicalEducation) { return .dashboard }
        }
        return module
    }

    private func restorePersistedDataState() async {
        if persistedClassId > 0,
           bridge.classes.contains(where: { $0.id == Int64(persistedClassId) }) {
            selectionStore.selectedClassId = Int64(persistedClassId)
        } else if selectionStore.selectedClassId == nil {
            selectionStore.selectedClassId = bridge.selectedStudentsClassId ?? bridge.classes.first?.id
        }
        guard persistedStudentId > 0, let classId = selectionStore.selectedClassId else { return }
        let studentId = Int64(persistedStudentId)
        let students = (try? await bridge.students(forClassId: classId)) ?? bridge.studentsInClass
        if students.contains(where: { $0.id == studentId }) {
            selectionStore.selectedStudentId = studentId
        }
    }

    // MARK: Navigation
    private func selectModule(_ module: AppWorkspaceModule) {
        let module = normalizedModule(module)
        guard activeModule != module else { return }
        withAnimation(uiFeatureFlags.animation(.easeOut(duration: 0.22))) {
            activeModule = module
        }
    }

    func openModule(_ module: AppWorkspaceModule, classId: Int64? = nil, studentId: Int64? = nil) {
        // Cursos ya no es una entrada de la barra lateral: `normalizedModule`
        // lo reencamina a Ajustes, y aquí se pide además la sección para que la
        // pantalla aparezca ya abierta por ella.
        if module == .courses {
            SettingsNavigationStore.shared.request(.courses)
        }
        let module = normalizedModule(module)
        withAnimation(uiFeatureFlags.animation(.easeOut(duration: 0.22))) {
            activeModule = module
        }
        if classId != nil || studentId != nil {
            let targetClassId = classId ?? selectionStore.selectedClassId
            let targetStudentId = studentId ?? selectionStore.selectedStudentId
            selectionStore.select(classId: targetClassId, studentId: targetStudentId)
        }
        if let classId {
            bridge.selectClass(id: classId)
        }
    }

    // MARK: Inspector
    private func toggleInspector() {
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
        withAnimation(uiFeatureFlags.animation(.snappy(duration: 0.18))) { self.banner = banner }
        bannerDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(uiFeatureFlags.animation(.snappy(duration: 0.18))) { self.banner = nil }
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

    private var activeNotebookClassLabel: String {
        guard let classId = selectionStore.selectedClassId,
              let schoolClass = bridge.classes.first(where: { $0.id == classId })
        else { return "Seleccionar clase" }
        return "\(schoolClass.name) · \(schoolClass.course)º"
    }

    private var groupedNotebookClasses: [(course: Int32, classes: [SchoolClass])] {
        Dictionary(grouping: bridge.classes, by: \.course)
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

    private var notebookGroupFilterLabel: String {
        guard let selectedId = layoutState.notebookSelectedGroupId,
              let group = layoutState.notebookAvailableGroups.first(where: { $0.id == selectedId }) else {
            return "Grupo completo"
        }
        return group.name
    }

    @ViewBuilder
    private var notebookGroupFilterMenu: some View {
        Menu {
            Button("Grupo completo") {
                layoutState.setNotebookGroupFilter(nil)
            }
            ForEach(layoutState.notebookAvailableGroups) { groupOption in
                Button {
                    layoutState.setNotebookGroupFilter(groupOption.id)
                } label: {
                    HStack {
                        Text("\(groupOption.name) (\(groupOption.studentCount))")
                        if layoutState.notebookSelectedGroupId == groupOption.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(notebookGroupFilterLabel, systemImage: "person.2")
        }
        .buttonStyle(.bordered)
    }

    @ToolbarContentBuilder
    private var notebookToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Menu {
                ForEach(groupedNotebookClasses, id: \.course) { group in
                    Section("\(group.course)º") {
                        ForEach(group.classes, id: \.id) { schoolClass in
                            Button {
                                selectionStore.selectedClassId = schoolClass.id
                            } label: {
                                HStack {
                                    Text("\(schoolClass.name) · \(schoolClass.course)º")
                                    if selectionStore.selectedClassId == schoolClass.id {
                                        Image(systemName: "checkmark")
                                    }
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
            .disabled(bridge.classes.isEmpty)
        }

        if bridge.syncPendingChanges > 0 {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                    Text("\(bridge.syncPendingChanges) pnd.")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(IOSAppStyle.warning)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(IOSAppStyle.warning.opacity(0.12), in: Capsule())
            }
        }

        if !layoutState.notebookAvailableGroups.isEmpty {
            ToolbarItem(placement: .navigationBarTrailing) {
                notebookGroupFilterMenu
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Picker("Vista", selection: Binding(
                get: { layoutState.notebookSurfaceMode },
                set: { layoutState.setNotebookSurfaceMode($0) }
            )) {
                Text("Grid").tag("grid")
                Text("Plano").tag("seatingPlan")
            }
            .pickerStyle(.segmented)
            .frame(width: 112)
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                layoutState.showNotebookAddColumn()
            } label: {
                Label("Nueva columna", systemImage: "plus")
            }
            .disabled(!layoutState.notebookAddColumnAvailable)
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                layoutState.openNotebookOrganizationMenu()
            } label: {
                Label("Organizar", systemImage: "slider.horizontal.3")
            }
            .disabled(!layoutState.notebookOrganizationMenuAvailable)
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            if layoutState.isNotebookInspectorPresented {
                Button {
                    layoutState.toggleNotebookInspector()
                } label: {
                    Label("Ocultar inspector", systemImage: "sidebar.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!layoutState.notebookInspectorAvailable)
            } else {
                Button {
                    layoutState.toggleNotebookInspector()
                } label: {
                    Label("Mostrar inspector", systemImage: "sidebar.right")
                }
                .buttonStyle(.bordered)
                .disabled(!layoutState.notebookInspectorAvailable)
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    "Buscar",
                    text: Binding(
                        get: { layoutState.notebookSearchText },
                        set: { layoutState.setNotebookSearchText($0) }
                    )
                )
                .textFieldStyle(.plain)
                if !layoutState.notebookSearchText.isEmpty {
                    Button {
                        layoutState.setNotebookSearchText("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Borrar búsqueda")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(minWidth: 120, idealWidth: 180, maxWidth: 220)
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    layoutState.notebookRefresh()
                } label: {
                    Label("Recargar", systemImage: "arrow.clockwise")
                }

                if let exportText = layoutState.notebookExportText {
                    ShareLink(item: exportText) {
                        Label("Exportar", systemImage: "square.and.arrow.up")
                    }
                }

                Button {
                    layoutState.notebookUndo()
                } label: {
                    Label("Deshacer", systemImage: "arrow.uturn.backward")
                }
                .disabled(!layoutState.notebookCanUndo)

                Button {
                    layoutState.notebookToggleAttendanceQuickMode()
                } label: {
                    Label(
                        layoutState.notebookIsAttendanceQuickMode ? "Salir de asistencia rápida" : "Asistencia rápida",
                        systemImage: layoutState.notebookIsAttendanceQuickMode ? "figure.walk.circle.fill" : "figure.walk.circle"
                    )
                }

                Divider()

                Button {
                    layoutState.openNotebookHiddenColumns()
                } label: {
                    Label("Columnas ocultas", systemImage: "eye.slash")
                }
                .disabled(!layoutState.notebookOrganizationMenuAvailable)

                Button {
                    openModule(.courses)
                } label: {
                    Label("Gestión de grupos", systemImage: "person.2")
                }
            } label: {
                Label("Más", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: Attendance native toolbar (iPad regular width — parity with MacRootView's attendance toolbar)
    @ToolbarContentBuilder
    private var attendanceToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            attendanceClassMenu
        }

        ToolbarItem(placement: .navigationBarLeading) {
            Picker("Vista", selection: Binding(
                get: { layoutState.attendanceBoardMode },
                set: { layoutState.setAttendanceBoardMode($0) }
            )) {
                ForEach(AttendanceBoardMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
        }

        if bridge.syncPendingChanges > 0 {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                    Text("\(bridge.syncPendingChanges) pnd.")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(IOSAppStyle.warning)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(IOSAppStyle.warning.opacity(0.12), in: Capsule())
            }
        }

        if attendanceModeSelection != .courses {
            ToolbarItem(placement: .navigationBarTrailing) {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { layoutState.attendanceSelectedDate },
                        set: { layoutState.setAttendanceDate($0) }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
            }

            if attendanceModeSelection == .day {
                ToolbarItem(placement: .navigationBarTrailing) {
                    attendanceSessionMenu
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                attendanceFilterMenu
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    layoutState.attendanceMarkAllPresent()
                } label: {
                    Label("Todos presentes", systemImage: "checkmark.circle.fill")
                }
                Button {
                    layoutState.attendanceRepeatPattern()
                } label: {
                    Label("Repetir patrón", systemImage: "repeat")
                }
                if layoutState.attendanceHasSelection {
                    Button {
                        layoutState.attendanceClearSelection()
                    } label: {
                        Label("Cerrar ficha", systemImage: "xmark.circle")
                    }
                }
            } label: {
                Label("Acciones", systemImage: "ellipsis.circle")
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    "Buscar alumno",
                    text: Binding(
                        get: { layoutState.attendanceSearchText },
                        set: { layoutState.setAttendanceSearchText($0) }
                    )
                )
                .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(minWidth: 140, idealWidth: 180, maxWidth: 220)
        }
    }

    private var attendanceModeSelection: AttendanceBoardMode {
        AttendanceBoardMode(rawValue: layoutState.attendanceBoardMode) ?? .day
    }

    private var attendanceClassMenu: some View {
        Menu {
            Button("Sin clase activa") {
                selectionStore.selectedClassId = nil
            }
            ForEach(bridge.classes, id: \.id) { schoolClass in
                Button {
                    selectionStore.selectedClassId = schoolClass.id
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
            Label(activeAttendanceClassLabel, systemImage: "rectangle.3.group")
        }
    }

    private var activeAttendanceClassLabel: String {
        guard let classId = selectionStore.selectedClassId,
              let schoolClass = bridge.classes.first(where: { $0.id == classId }) else {
            return "Curso"
        }
        return schoolClass.name
    }

    private var attendanceFilterMenu: some View {
        Menu {
            Button("Todos los estados") {
                layoutState.setAttendanceStatusFilter("TODOS")
            }
            ForEach(AttendanceStatusOption.all) { option in
                Button(option.label) {
                    layoutState.setAttendanceStatusFilter(option.id)
                }
            }
        } label: {
            Label(attendanceFilterLabel, systemImage: attendanceFilterSystemImage)
        }
    }

    private var attendanceFilterLabel: String {
        layoutState.attendanceSelectedStatusFilter == "TODOS"
            ? "Filtrar"
            : (AttendanceStatusOption.option(for: layoutState.attendanceSelectedStatusFilter)?.label ?? "Filtrar")
    }

    private var attendanceFilterSystemImage: String {
        layoutState.attendanceSelectedStatusFilter == "TODOS"
            ? "line.3.horizontal.decrease.circle"
            : "line.3.horizontal.decrease.circle.fill"
    }

    private var attendanceSessionMenu: some View {
        Menu {
            if layoutState.attendanceSessions.isEmpty {
                Text("No hay sesiones planificadas")
            } else {
                ForEach(layoutState.attendanceSessions) { entry in
                    Button {
                        layoutState.setAttendanceSessionId(entry.session.id)
                    } label: {
                        if layoutState.attendanceSelectedSessionId == entry.session.id {
                            Label(attendanceSessionLabel(entry), systemImage: "checkmark")
                        } else {
                            Text(attendanceSessionLabel(entry))
                        }
                    }
                }
            }
        } label: {
            Label(
                attendanceSelectedSessionLabel,
                systemImage: layoutState.attendanceSessions.count > 1 ? "calendar.badge.clock" : "calendar"
            )
        }
        .disabled(layoutState.attendanceSessions.count <= 1)
    }

    private var attendanceSelectedSessionLabel: String {
        guard let entry = layoutState.attendanceSessions.first(where: { $0.session.id == layoutState.attendanceSelectedSessionId }) else {
            return "Sin sesión"
        }
        return attendanceSessionLabel(entry)
    }

    private func attendanceSessionLabel(_ entry: KmpBridge.AttendanceSessionSnapshot) -> String {
        AttendanceLogic.sessionLabel(for: entry)
    }
}

// MARK: - IOSGlobalContextRow
struct IOSGlobalContextRow: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme

    let activeModule: AppWorkspaceModule
    @ObservedObject var layoutState: WorkspaceLayoutState
    @ObservedObject var selectionStore: IOSSelectionStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                moduleTitle
                Spacer(minLength: 12)
                classMenu
                if showsSearchField { searchField }
            }

            VStack(alignment: .leading, spacing: 12) {
                moduleTitle
                HStack(spacing: 12) {
                    classMenu
                    if showsSearchField { searchField }
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
                selectionStore.selectedClassId = nil
            }
            ForEach(bridge.classes, id: \.id) { schoolClass in
                Button {
                    selectionStore.selectedClassId = schoolClass.id
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
        "Buscar alumno..."
    }

    /// El campo de búsqueda global solo tiene efecto real en Cuaderno y Asistencia,
    /// los únicos módulos que consumen `activeSearchBinding`. En el resto no hay
    /// destino que filtre nada, así que se oculta en lugar de mostrar un control inerte.
    private var showsSearchField: Bool {
        activeModule == .notebook || activeModule == .attendance
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
                    return ""
                }
            },
            set: { newValue in
                switch activeModule {
                case .notebook:
                    layoutState.setNotebookSearchText(newValue)
                case .attendance:
                    layoutState.setAttendanceSearchText(newValue)
                default:
                    break
                }
            }
        )
    }
}

// MARK: - IOSWorkspaceSidebar
struct IOSWorkspaceSidebar: View {
    let activeModule: AppWorkspaceModule
    let onSelectModule: (AppWorkspaceModule) -> Void
    @AppStorage("teacher.enabledSubjectProfiles.v1")
    private var enabledSubjectProfilesRaw: String = TeacherSubjectProfile.general.rawValue

    var body: some View {
        let enabledProfiles = TeacherSubjectProfile.decodeSet(enabledSubjectProfilesRaw)

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
                ForEach(IOSFeatureRegistry.secondary(enabledProfiles: enabledProfiles)) { feature in
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
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    let activeModule: AppWorkspaceModule
    @ObservedObject var layoutState: WorkspaceLayoutState
    @ObservedObject var selectionStore: IOSSelectionStore
    @ObservedObject var notebookStore: NotebookBridgeStore
    @ObservedObject var dashboardStore: DashboardBridgeStore
    @ObservedObject var studentsBridgeStore: StudentsBridgeStore
    @ObservedObject var attendanceStore: AttendanceBridgeStore
    var plannerContext: PlannerNavigationContext
    @Binding var activeSheet: ActiveWorkspaceSheet?
    @Binding var showingRubricBuilder: Bool

    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    let onUpdatePlannerContext: (PlannerNavigationContext) -> Void
    let onShowBanner: (IOSRootBanner) -> Void

    var body: some View {
        moduleContent
            .id(activeModule)
            .transition(uiFeatureFlags.contentSwitchTransition)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environmentObject(layoutState)
    }

    @ViewBuilder
    private var moduleContent: some View {
        switch activeModule {
        case .dashboard, .courses, .students, .teacherRadar, .notebook,
             .attendance, .planner, .situations, .diary, .meetings, .evaluationHub:
            academicContent
        default:
            evaluationAndPEContent
        }
    }

    @ViewBuilder
    private var academicContent: some View {
        switch activeModule {
        case .dashboard:
            DashboardView(
                bridge: bridge,
                dashboardStore: dashboardStore,
                selectedClassId: $selectionStore.selectedClassId,
                onOpenModule: onOpenModule
            )
        case .courses:
            CoursesWorkspaceView(
                selectedClassId: $selectionStore.selectedClassId,
                onOpenModule: onOpenModule,
                onCreateStudent: { classId in
                    selectionStore.selectedClassId = classId
                    activeSheet = .create(.student)
                }
            )
            .environmentObject(bridge)
        case .students:
            StudentProfilesWorkspaceView(
                bridge: bridge,
                studentsBridgeStore: studentsBridgeStore,
                selectedClassId: $selectionStore.selectedClassId,
                selectedStudentId: $selectionStore.selectedStudentId,
                onOpenModule: onOpenModule
            )
        case .teacherRadar:
            DashboardView(
                bridge: bridge,
                dashboardStore: dashboardStore,
                selectedClassId: $selectionStore.selectedClassId,
                onOpenModule: onOpenModule
            )
        case .notebook:
            NotebookModuleView(
                bridge: bridge,
                notebookStore: notebookStore,
                selectedClassId: $selectionStore.selectedClassId,
                selectedStudentId: $selectionStore.selectedStudentId,
                onOpenModule: onOpenModule,
                toolbarMode: notebookToolbarMode
            )
        case .attendance:
            AttendanceWorkspaceView(
                bridge: bridge,
                attendanceStore: attendanceStore,
                selectedClassId: $selectionStore.selectedClassId,
                preselectedStudentId: $selectionStore.selectedStudentId,
                onOpenModule: onOpenModule
            )
        case .planner:
            PlannerWorkspaceIOS(
                context: resolvedPlannerContext,
                onOpenDiary: { ctx in onOpenModule(.diary, ctx.groupId, nil); onUpdatePlannerContext(ctx) },
                onNavigationContextChange: onUpdatePlannerContext
            )
            .environmentObject(bridge)
        case .situations:
            LearningSituationsWorkspaceView(
                selectedClassId: $selectionStore.selectedClassId,
                onOpenModule: onOpenModule
            )
            .environmentObject(bridge)
        case .diary:
            DiaryWorkspaceView(
                selectedClassId: $selectionStore.selectedClassId,
                navigationContext: resolvedPlannerContext,
                onOpenModule: onOpenModule,
                onOpenPlanner: { ctx in onOpenModule(.planner, ctx.groupId, nil); onUpdatePlannerContext(ctx) },
                onNavigationContextChange: onUpdatePlannerContext
            )
            .environmentObject(bridge)
        case .evaluationHub:
            EvaluationHubView(
                selectedClassId: $selectionStore.selectedClassId,
                onOpenModule: onOpenModule
            )
            .environmentObject(bridge)
        case .meetings:
            MeetingsWorkspaceView(bridge: bridge)
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
                selectedClassId: $selectionStore.selectedClassId,
                onOpenModule: onOpenModule,
                onOpenBuilder: { bridge.resetRubricBuilder(); showingRubricBuilder = true },
                onEditRubric: { rubric in bridge.loadRubricForEditing(rubric); showingRubricBuilder = true }
            )
            .environmentObject(bridge)
        case .reports:
            ReportsWorkspaceView(
                selectedClassId: $selectionStore.selectedClassId,
                selectedStudentId: $selectionStore.selectedStudentId
            )
            .environmentObject(bridge)
        case .webSubmissions:
            WebSubmissionsIPadInfoView()
        case .library:
            LibraryWorkspaceView(
                selectedClassId: $selectionStore.selectedClassId,
                onOpenModule: onOpenModule
            )
            .environmentObject(bridge)
        case .peSessions:
            PESessionsWorkspaceView(
                selectedClassId: $selectionStore.selectedClassId,
                onOpenModule: onOpenModule
            )
            .environmentObject(bridge)
        case .peTests:
            PhysicalTestsWorkspaceView(
                selectedClassId: $selectionStore.selectedClassId,
                onOpenModule: onOpenModule
            )
            .environmentObject(bridge)
        case .peRubrics:
            RubricsWorkspaceView(
                selectedClassId: $selectionStore.selectedClassId,
                onOpenModule: onOpenModule,
                onOpenBuilder: { bridge.resetRubricBuilder(); showingRubricBuilder = true },
                onEditRubric: { rubric in bridge.loadRubricForEditing(rubric); showingRubricBuilder = true },
                peMode: true
            )
            .environmentObject(bridge)
        case .peIncidents:
            EFIncidentsWorkspaceView(
                selectedClassId: $selectionStore.selectedClassId,
                onOpenModule: onOpenModule
            )
            .environmentObject(bridge)
        case .peMaterial:
            PEMaterialWorkspaceView(
                selectedClassId: $selectionStore.selectedClassId,
                onOpenModule: onOpenModule
            )
            .environmentObject(bridge)
        case .peTournaments:
            PETournamentsWorkspaceView(selectedClassId: $selectionStore.selectedClassId)
                .environmentObject(bridge)
        case .settings:
            SettingsWorkspaceView(
                selectedClassId: $selectionStore.selectedClassId,
                onOpenModule: onOpenModule
            )
            .environmentObject(bridge)
        case .backups:
            BackupsWorkspaceView(selectedClassId: $selectionStore.selectedClassId)
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

    private var notebookToolbarMode: NotebookToolbarMode {
        #if os(iOS)
        horizontalSizeClass == .compact ? .inlineCompact : .macShellOwned
        #else
        .macShellOwned
        #endif
    }
}

// MARK: - IOSContextualToolbar
/// Renders contextual toolbar items that adapt to the active module,
/// mirroring what MacRootView does with its macToolbar.
struct IOSContextualToolbar: ToolbarContent {
    let activeModule: AppWorkspaceModule
    @ObservedObject var layoutState: WorkspaceLayoutState
    @ObservedObject var selectionStore: IOSSelectionStore
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
        case .dashboard, .diary: return true
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
