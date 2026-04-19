import SwiftUI
import MiGestorKit

struct NotebookToolbarGroupOption: Identifiable, Equatable {
    let id: Int64
    let name: String
    let studentCount: Int
}

@MainActor
final class WorkspaceLayoutState: ObservableObject {
    @Published var isSidebarVisible: Bool = true
    @Published var isFocusModeEnabled: Bool = false
    @Published var notebookInspectorAvailable: Bool = false
    @Published var isNotebookInspectorPresented: Bool = false
    @Published var notebookAddColumnAvailable: Bool = false
    @Published var notebookOrganizationMenuAvailable: Bool = false
    @Published var notebookSearchText: String = ""
    @Published var notebookSurfaceMode: String = "grid"
    @Published var notebookSelectedGroupId: Int64? = nil
    @Published var notebookAvailableGroups: [NotebookToolbarGroupOption] = []
    @Published var dashboardInspectorAvailable: Bool = false
    @Published var isDashboardInspectorPresented: Bool = false
    @Published var dashboardActionsAvailable: Bool = false
    @Published var diaryInspectorAvailable: Bool = false
    @Published var isDiaryInspectorPresented: Bool = false
    @Published var plannerAddSessionAvailable: Bool = false
    @Published var attendanceToolbarAvailable: Bool = false
    @Published var attendanceSearchText: String = ""
    @Published var attendanceSelectedDate: Date = Date()
    @Published var attendanceBoardMode: String = "Día"
    @Published var attendanceSelectedStatusFilter: String = "TODOS"
    @Published var attendanceHasSelection: Bool = false

    private var notebookInspectorAction: (() -> Void)?
    private var notebookAddColumnAction: (() -> Void)?
    private var notebookSearchAction: ((String) -> Void)?
    private var notebookSurfaceModeAction: ((String) -> Void)?
    private var notebookGroupFilterAction: ((Int64?) -> Void)?
    private var notebookOrganizationMenuAction: (() -> Void)?
    private var dashboardInspectorAction: (() -> Void)?
    private var dashboardRefreshAction: (() -> Void)?
    private var dashboardPassListAction: (() -> Void)?
    private var dashboardObservationAction: (() -> Void)?
    private var dashboardQuickEvaluationAction: (() -> Void)?
    private var diaryInspectorAction: (() -> Void)?
    private var plannerAddSessionAction: (() -> Void)?
    private var attendanceSearchAction: ((String) -> Void)?
    private var attendanceDateAction: ((Date) -> Void)?
    private var attendanceBoardModeAction: ((String) -> Void)?
    private var attendanceStatusFilterAction: ((String) -> Void)?
    private var attendanceMarkAllPresentAction: (() -> Void)?
    private var attendanceRepeatPatternAction: (() -> Void)?
    private var attendanceClearSelectionAction: (() -> Void)?

    private func publishDeferred(_ mutation: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            mutation()
        }
    }

    func toggleFocusMode() {
        isFocusModeEnabled.toggle()
        isSidebarVisible = !isFocusModeEnabled
    }

    func configureNotebookToolbar(
        inspectorAvailable: Bool,
        isInspectorPresented: Bool,
        addColumnAvailable: Bool,
        searchText: String,
        surfaceMode: String,
        selectedGroupId: Int64?,
        availableGroups: [NotebookToolbarGroupOption],
        organizationMenuAvailable: Bool,
        onToggleInspector: @escaping () -> Void,
        onAddColumn: @escaping () -> Void,
        onSearchChange: @escaping (String) -> Void,
        onSurfaceModeChange: @escaping (String) -> Void,
        onGroupFilterChange: @escaping (Int64?) -> Void,
        onOpenOrganizationMenu: @escaping () -> Void
    ) {
        publishDeferred {
            self.notebookInspectorAvailable = inspectorAvailable
            self.isNotebookInspectorPresented = isInspectorPresented
            self.notebookAddColumnAvailable = addColumnAvailable
            self.notebookSearchText = searchText
            self.notebookSurfaceMode = surfaceMode
            self.notebookSelectedGroupId = selectedGroupId
            self.notebookAvailableGroups = availableGroups
            self.notebookOrganizationMenuAvailable = organizationMenuAvailable
            self.notebookInspectorAction = onToggleInspector
            self.notebookAddColumnAction = onAddColumn
            self.notebookSearchAction = onSearchChange
            self.notebookSurfaceModeAction = onSurfaceModeChange
            self.notebookGroupFilterAction = onGroupFilterChange
            self.notebookOrganizationMenuAction = onOpenOrganizationMenu
        }
    }

    func updateNotebookToolbar(
        inspectorAvailable: Bool,
        isInspectorPresented: Bool,
        addColumnAvailable: Bool,
        searchText: String,
        surfaceMode: String,
        selectedGroupId: Int64?,
        availableGroups: [NotebookToolbarGroupOption],
        organizationMenuAvailable: Bool
    ) {
        publishDeferred {
            self.notebookInspectorAvailable = inspectorAvailable
            self.isNotebookInspectorPresented = isInspectorPresented
            self.notebookAddColumnAvailable = addColumnAvailable
            self.notebookSearchText = searchText
            self.notebookSurfaceMode = surfaceMode
            self.notebookSelectedGroupId = selectedGroupId
            self.notebookAvailableGroups = availableGroups
            self.notebookOrganizationMenuAvailable = organizationMenuAvailable
        }
    }

    func clearNotebookToolbar() {
        publishDeferred {
            self.notebookInspectorAvailable = false
            self.isNotebookInspectorPresented = false
            self.notebookAddColumnAvailable = false
            self.notebookOrganizationMenuAvailable = false
            self.notebookSearchText = ""
            self.notebookSurfaceMode = "grid"
            self.notebookSelectedGroupId = nil
            self.notebookAvailableGroups = []
            self.notebookInspectorAction = nil
            self.notebookAddColumnAction = nil
            self.notebookSearchAction = nil
            self.notebookSurfaceModeAction = nil
            self.notebookGroupFilterAction = nil
            self.notebookOrganizationMenuAction = nil
        }
    }

    func toggleNotebookInspector() {
        notebookInspectorAction?()
    }

    func showNotebookAddColumn() {
        notebookAddColumnAction?()
    }

    func setNotebookSearchText(_ value: String) {
        notebookSearchText = value
        notebookSearchAction?(value)
    }

    func setNotebookSurfaceMode(_ value: String) {
        notebookSurfaceMode = value
        notebookSurfaceModeAction?(value)
    }

    func setNotebookGroupFilter(_ value: Int64?) {
        notebookSelectedGroupId = value
        notebookGroupFilterAction?(value)
    }

    func openNotebookOrganizationMenu() {
        notebookOrganizationMenuAction?()
    }

    func configureDashboardToolbar(
        inspectorAvailable: Bool,
        isInspectorPresented: Bool,
        actionsAvailable: Bool,
        onToggleInspector: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onPassList: @escaping () -> Void,
        onObservation: @escaping () -> Void,
        onQuickEvaluation: @escaping () -> Void
    ) {
        publishDeferred {
            self.dashboardInspectorAvailable = inspectorAvailable
            self.isDashboardInspectorPresented = isInspectorPresented
            self.dashboardActionsAvailable = actionsAvailable
            self.dashboardInspectorAction = onToggleInspector
            self.dashboardRefreshAction = onRefresh
            self.dashboardPassListAction = onPassList
            self.dashboardObservationAction = onObservation
            self.dashboardQuickEvaluationAction = onQuickEvaluation
        }
    }

    func clearDashboardToolbar() {
        publishDeferred {
            self.dashboardInspectorAvailable = false
            self.isDashboardInspectorPresented = false
            self.dashboardActionsAvailable = false
            self.dashboardInspectorAction = nil
            self.dashboardRefreshAction = nil
            self.dashboardPassListAction = nil
            self.dashboardObservationAction = nil
            self.dashboardQuickEvaluationAction = nil
        }
    }

    func toggleDashboardInspector() {
        dashboardInspectorAction?()
    }

    func configureDiaryToolbar(
        inspectorAvailable: Bool,
        isInspectorPresented: Bool,
        onToggleInspector: @escaping () -> Void
    ) {
        publishDeferred {
            self.diaryInspectorAvailable = inspectorAvailable
            self.isDiaryInspectorPresented = isInspectorPresented
            self.diaryInspectorAction = onToggleInspector
        }
    }

    func updateDiaryToolbar(inspectorAvailable: Bool, isInspectorPresented: Bool) {
        publishDeferred {
            self.diaryInspectorAvailable = inspectorAvailable
            self.isDiaryInspectorPresented = isInspectorPresented
        }
    }

    func clearDiaryToolbar() {
        publishDeferred {
            self.diaryInspectorAvailable = false
            self.isDiaryInspectorPresented = false
            self.diaryInspectorAction = nil
        }
    }

    func toggleDiaryInspector() {
        diaryInspectorAction?()
    }

    func configurePlannerToolbar(
        addSessionAvailable: Bool,
        onAddSession: @escaping () -> Void
    ) {
        publishDeferred {
            self.plannerAddSessionAvailable = addSessionAvailable
            self.plannerAddSessionAction = onAddSession
        }
    }

    func clearPlannerToolbar() {
        publishDeferred {
            self.plannerAddSessionAvailable = false
            self.plannerAddSessionAction = nil
        }
    }

    func openPlannerComposer() {
        plannerAddSessionAction?()
    }

    func refreshDashboard() {
        dashboardRefreshAction?()
    }

    func dashboardPassList() {
        dashboardPassListAction?()
    }

    func dashboardObservation() {
        dashboardObservationAction?()
    }

    func dashboardQuickEvaluation() {
        dashboardQuickEvaluationAction?()
    }

    func configureAttendanceToolbar(
        searchText: String,
        selectedDate: Date,
        boardMode: String,
        selectedStatusFilter: String,
        hasSelection: Bool,
        onSearchTextChange: @escaping (String) -> Void,
        onDateChange: @escaping (Date) -> Void,
        onBoardModeChange: @escaping (String) -> Void,
        onStatusFilterChange: @escaping (String) -> Void,
        onMarkAllPresent: @escaping () -> Void,
        onRepeatPattern: @escaping () -> Void,
        onClearSelection: @escaping () -> Void
    ) {
        publishDeferred {
            self.attendanceToolbarAvailable = true
            self.attendanceSearchText = searchText
            self.attendanceSelectedDate = selectedDate
            self.attendanceBoardMode = boardMode
            self.attendanceSelectedStatusFilter = selectedStatusFilter
            self.attendanceHasSelection = hasSelection
            self.attendanceSearchAction = onSearchTextChange
            self.attendanceDateAction = onDateChange
            self.attendanceBoardModeAction = onBoardModeChange
            self.attendanceStatusFilterAction = onStatusFilterChange
            self.attendanceMarkAllPresentAction = onMarkAllPresent
            self.attendanceRepeatPatternAction = onRepeatPattern
            self.attendanceClearSelectionAction = onClearSelection
        }
    }

    func updateAttendanceToolbar(
        searchText: String,
        selectedDate: Date,
        boardMode: String,
        selectedStatusFilter: String,
        hasSelection: Bool
    ) {
        publishDeferred {
            self.attendanceToolbarAvailable = true
            self.attendanceSearchText = searchText
            self.attendanceSelectedDate = selectedDate
            self.attendanceBoardMode = boardMode
            self.attendanceSelectedStatusFilter = selectedStatusFilter
            self.attendanceHasSelection = hasSelection
        }
    }

    func clearAttendanceToolbar() {
        publishDeferred {
            self.attendanceToolbarAvailable = false
            self.attendanceSearchText = ""
            self.attendanceSelectedDate = Date()
            self.attendanceBoardMode = "Día"
            self.attendanceSelectedStatusFilter = "TODOS"
            self.attendanceHasSelection = false
            self.attendanceSearchAction = nil
            self.attendanceDateAction = nil
            self.attendanceBoardModeAction = nil
            self.attendanceStatusFilterAction = nil
            self.attendanceMarkAllPresentAction = nil
            self.attendanceRepeatPatternAction = nil
            self.attendanceClearSelectionAction = nil
        }
    }

    func setAttendanceSearchText(_ value: String) {
        attendanceSearchText = value
        attendanceSearchAction?(value)
    }

    func setAttendanceDate(_ value: Date) {
        attendanceSelectedDate = value
        attendanceDateAction?(value)
    }

    func setAttendanceBoardMode(_ value: String) {
        attendanceBoardMode = value
        attendanceBoardModeAction?(value)
    }

    func setAttendanceStatusFilter(_ value: String) {
        attendanceSelectedStatusFilter = value
        attendanceStatusFilterAction?(value)
    }

    func attendanceMarkAllPresent() {
        attendanceMarkAllPresentAction?()
    }

    func attendanceRepeatPattern() {
        attendanceRepeatPatternAction?()
    }

    func attendanceClearSelection() {
        attendanceClearSelectionAction?()
    }
}


enum AppWorkspaceSection: String, CaseIterable, Identifiable {
    case academic = "Académico"
    case operations = "Operativa"
    case evaluation = "Evaluación"
    case physicalEducation = "Educación Física"
    case system = "Sistema"

    var id: String { rawValue }
}

enum AppWorkspaceModule: String, CaseIterable, Identifiable {
    case dashboard
    case courses
    case students
    case notebook
    case attendance
    case planner
    case diary
    case evaluationHub
    case rubrics
    case reports
    case library
    case peSessions
    case peTests
    case peRubrics
    case peIncidents
    case peMaterial
    case peTournaments
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .courses: return "Cursos"
        case .students: return "Alumnado"
        case .notebook: return "Cuaderno"
        case .attendance: return "Asistencia"
        case .planner: return "Planner"
        case .diary: return "Diario de aula"
        case .evaluationHub: return "Evaluación"
        case .rubrics: return "Rúbricas"
        case .reports: return "Informes"
        case .library: return "Biblioteca"
        case .peSessions: return "EF · Sesiones"
        case .peTests: return "EF · Pruebas físicas"
        case .peRubrics: return "EF · Rúbricas"
        case .peIncidents: return "EF · Incidencias"
        case .peMaterial: return "EF · Material"
        case .peTournaments: return "EF · Torneos"
        case .settings: return "Ajustes"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: return "Visión operativa"
        case .courses: return "Gestión de grupos"
        case .students: return "Perfiles y seguimiento"
        case .notebook: return "Registro evaluativo"
        case .attendance: return "Control diario y semanal"
        case .planner: return "Preparación lectiva"
        case .diary: return "Trazabilidad de sesión"
        case .evaluationHub: return "Instrumentos y calendario"
        case .rubrics: return "Banco de rúbricas"
        case .reports: return "Salida docente"
        case .library: return "Plantillas reutilizables"
        case .peSessions: return "Operativa en pista"
        case .peTests: return "Marcas e históricos"
        case .peRubrics: return "Rúbricas motrices"
        case .peIncidents: return "Seguridad y seguimiento"
        case .peMaterial: return "Inventario rápido"
        case .peTournaments: return "Competición y resultados"
        case .settings: return "Configuración"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .courses: return "rectangle.3.group.bubble.left.fill"
        case .students: return "person.3.fill"
        case .notebook: return "book.closed.fill"
        case .attendance: return "checklist.checked"
        case .planner: return "calendar.badge.clock"
        case .diary: return "doc.text.fill"
        case .evaluationHub: return "chart.bar.doc.horizontal"
        case .rubrics: return "checklist"
        case .reports: return "doc.richtext.fill"
        case .library: return "books.vertical.fill"
        case .peSessions: return "figure.run"
        case .peTests: return "stopwatch.fill"
        case .peRubrics: return "figure.cooldown"
        case .peIncidents: return "cross.case.fill"
        case .peMaterial: return "shippingbox.fill"
        case .peTournaments: return "trophy.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var section: AppWorkspaceSection {
        switch self {
        case .dashboard, .courses, .students, .notebook:
            return .academic
        case .attendance, .planner, .diary:
            return .operations
        case .evaluationHub, .rubrics, .reports, .library:
            return .evaluation
        case .peSessions, .peTests, .peRubrics, .peIncidents, .peMaterial, .peTournaments:
            return .physicalEducation
        case .settings:
            return .system
        }
    }
}

private enum WorkspaceCreateSheet: String, Identifiable {
    case course
    case student
    case evaluation

    var id: String { rawValue }
}

private struct WorkspaceSearchResult: Identifiable {
    enum Kind {
        case module(AppWorkspaceModule)
        case schoolClass(Int64)
        case student(Int64)
    }

    let id = UUID()
    let title: String
    let subtitle: String
    let kind: Kind
}

private struct ContextualAISheetState: Identifiable {
    let module: AppWorkspaceModule
    let context: KmpBridge.ScreenAIContext

    var id: String {
        "\(module.rawValue)|\(context.kind.rawValue)|\(context.classId ?? -1)|\(context.studentId ?? -1)"
    }
}

struct AppWorkspaceShell: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("workspace.active.module") private var persistedActiveModule = AppWorkspaceModule.dashboard.rawValue
    @AppStorage("workspace.selected.class.id") private var persistedSelectedClassId: Int = 0
    @AppStorage("workspace.selected.student.id") private var persistedSelectedStudentId: Int = 0
    @State private var activeModule: AppWorkspaceModule = .dashboard
    @State private var searchText = ""
    @State private var selectedClassId: Int64? = nil
    @State private var selectedStudentId: Int64? = nil
    @State private var plannerContext = PlannerNavigationContext()
    @State private var createSheet: WorkspaceCreateSheet?
    @State private var showingRubricBuilder = false
    @StateObject private var layoutState = WorkspaceLayoutState()
    @State private var rootSplitVisibility: NavigationSplitViewVisibility = .all
    @State private var contextualAISheetState: ContextualAISheetState?
    @State private var isLoadingContextualAI = false

    private var searchResults: [WorkspaceSearchResult] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        let moduleResults = AppWorkspaceModule.allCases
            .filter { $0.title.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query) }
            .map { WorkspaceSearchResult(title: $0.title, subtitle: $0.subtitle, kind: .module($0)) }

        let classResults = bridge.classes
            .filter { $0.name.localizedCaseInsensitiveContains(query) }
            .map { WorkspaceSearchResult(title: $0.name, subtitle: "Curso \($0.course)", kind: .schoolClass($0.id)) }

        let studentResults = bridge.allStudents
            .filter { "\($0.firstName) \($0.lastName)".localizedCaseInsensitiveContains(query) }
            .prefix(8)
            .map { WorkspaceSearchResult(title: "\($0.firstName) \($0.lastName)", subtitle: "Abrir ficha de alumno", kind: .student($0.id)) }

        return Array((moduleResults + classResults + studentResults).prefix(12))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $rootSplitVisibility) {
            workspaceSidebar
        } detail: {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    if layoutState.isFocusModeEnabled {
                        compactFocusToolbar
                    } else {
                        workspaceToolbar
                        Divider().opacity(0.24)
                    }
                    activeWorkspace
                        .environmentObject(layoutState)
                }
                .background(appPageBackground(for: colorScheme).ignoresSafeArea())

                if !searchResults.isEmpty {
                    searchResultsOverlay
                        .padding(.top, 88)
                        .padding(.horizontal, 24)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $createSheet) { sheet in
            switch sheet {
            case .course:
                CreateCourseSheet {
                    createSheet = nil
                }
                .environmentObject(bridge)
            case .student:
                CreateStudentSheet(defaultClassId: selectedClassId) {
                    createSheet = nil
                }
                .environmentObject(bridge)
            case .evaluation:
                CreateEvaluationSheet(defaultClassId: selectedClassId) {
                    createSheet = nil
                }
                .environmentObject(bridge)
            }
        }
        .appFullScreenCover(isPresented: $showingRubricBuilder) {
            RubricsBuilderScreen()
                .environmentObject(bridge)
        }
        .sheet(item: $contextualAISheetState, content: contextualAISheet)
        .task {
            await bridge.ensureClassesLoaded()
            try? await bridge.refreshStudentsDirectory()
            try? await bridge.refreshRubrics()
            try? await bridge.refreshRubricClassLinks()
            activeModule = AppWorkspaceModule(rawValue: persistedActiveModule) ?? .dashboard
            if persistedSelectedClassId > 0,
               bridge.classes.contains(where: { $0.id == Int64(persistedSelectedClassId) }) {
                selectedClassId = Int64(persistedSelectedClassId)
            } else if selectedClassId == nil {
                selectedClassId = bridge.selectedStudentsClassId ?? bridge.classes.first?.id
            }
            selectedStudentId = persistedSelectedStudentId > 0 ? Int64(persistedSelectedStudentId) : nil
            if let selectedClassId {
                await bridge.selectStudentsClass(classId: selectedClassId)
            }
        }
        .onChange(of: activeModule) { newValue in persistedActiveModule = newValue.rawValue }
        .onChange(of: selectedClassId) { newValue in persistedSelectedClassId = Int(newValue ?? 0) }
        .onChange(of: selectedStudentId) { newValue in persistedSelectedStudentId = Int(newValue ?? 0) }
        .onAppear(perform: syncRootSplitVisibility)
        .onChange(of: layoutState.isSidebarVisible) { _ in syncRootSplitVisibility() }
        .onChange(of: layoutState.isFocusModeEnabled) { _ in syncRootSplitVisibility() }
    }

    private var workspaceSidebar: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MiGestor iPad")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                    Text("App iPad-first para evaluación, seguimiento y trabajo en clase.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
            }

            ForEach(AppWorkspaceSection.allCases) { section in
                Section(section.rawValue) {
                    ForEach(AppWorkspaceModule.allCases.filter { $0.section == section }) { module in
                        Button {
                            open(module: module)
                        } label: {
                            Label(module.title, systemImage: module.systemImage)
                                .foregroundStyle(activeModule == module ? Color.accentColor : .primary)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Workspace")
    }

    private func contextualAISheet(_ sheet: ContextualAISheetState) -> some View {
        ContextualAIAssistantSheet(
            module: sheet.module,
            context: sheet.context
        )
    }

    private var workspaceToolbar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(activeModule.subtitle.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(activeModule.title)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                }

                Spacer()

                if activeModule == .dashboard {
                    dashboardToolbarActions
                } else if activeModule == .planner {
                    plannerToolbarActions
                } else if activeModule == .diary {
                    diaryToolbarActions
                } else if activeModule == .attendance {
                    focusToggleButton
                } else {
                    focusToggleButton

                    if shouldShowGlobalContextualAIButton {
                        Button {
                            presentContextualAI()
                        } label: {
                            if isLoadingContextualAI {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(minWidth: 18)
                            } else {
                                Label("IA", systemImage: "apple.intelligence")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoadingContextualAI)
                    }

                    Menu {
                        Button("Recargar dashboard") { Task { await bridge.refreshDashboard(mode: .office) } }
                        Button("Recargar alumnado") { Task { try? await bridge.refreshStudentsDirectory() } }
                        Button("Recargar rúbricas") {
                            Task {
                                try? await bridge.refreshRubrics()
                                try? await bridge.refreshRubricClassLinks()
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise.circle")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.bordered)

                    Button {
                        triggerPrimaryAction()
                    } label: {
                        Label(primaryActionLabel, systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if activeModule == .attendance && layoutState.attendanceToolbarAvailable {
                attendanceGlobalToolbarRow
            } else if activeModule == .planner || activeModule == .diary {
                moduleContextToolbarRow
            } else if activeModule == .notebook {
                notebookGlobalToolbarRow
            } else {
                HStack(spacing: 12) {
                    Menu {
                        Button("Sin clase activa") {
                            updateGlobalClassContext(nil)
                        }
                        ForEach(bridge.classes, id: \.id) { schoolClass in
                            Button {
                                updateGlobalClassContext(schoolClass.id)
                            } label: {
                                HStack {
                                    Text(schoolClass.name)
                                    if selectedClassId == schoolClass.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(activeClassLabel, systemImage: "rectangle.3.group")
                            .frame(minWidth: 220, alignment: .leading)
                    }
                    .buttonStyle(.bordered)

                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(
                            activeModule == .notebook ? "Buscar alumno…" : "Buscar módulos, grupos o alumnado…",
                            text: Binding(
                                get: {
                                    activeModule == .notebook ? layoutState.notebookSearchText : searchText
                                },
                                set: { newValue in
                                    if activeModule == .notebook {
                                        layoutState.setNotebookSearchText(newValue)
                                    } else {
                                        searchText = newValue
                                    }
                                }
                            )
                        )
                            .textFieldStyle(.plain)
                        if !(activeModule == .notebook ? layoutState.notebookSearchText : searchText).isEmpty {
                            Button {
                                if activeModule == .notebook {
                                    layoutState.setNotebookSearchText("")
                                } else {
                                    searchText = ""
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }

            Text(bridge.status)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(0)
                .overlay(
                    Text(statusLineText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                )
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [appPageBackground(for: colorScheme), appMutedCardBackground(for: colorScheme).opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var compactFocusToolbar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(activeModule.title)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                Text(activeModule.subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            focusToggleButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [appPageBackground(for: colorScheme), appMutedCardBackground(for: colorScheme).opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var attendanceGlobalToolbarRow: some View {
        HStack(spacing: 12) {
            Menu {
                Button("Sin clase activa") {
                    updateGlobalClassContext(nil)
                }
                ForEach(bridge.classes, id: \.id) { schoolClass in
                    Button {
                        updateGlobalClassContext(schoolClass.id)
                    } label: {
                        HStack {
                            Text(schoolClass.name)
                            if selectedClassId == schoolClass.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(activeClassLabel, systemImage: "rectangle.3.group")
                    .frame(minWidth: 220, alignment: .leading)
            }
            .buttonStyle(.bordered)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    "Buscar alumno…",
                    text: Binding(
                        get: { layoutState.attendanceSearchText },
                        set: { layoutState.setAttendanceSearchText($0) }
                    )
                )
                .textFieldStyle(.plain)
                if !layoutState.attendanceSearchText.isEmpty {
                    Button {
                        layoutState.setAttendanceSearchText("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

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
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.title3.weight(.semibold))
            }
            .buttonStyle(.bordered)

            Menu {
                Button("Todos presentes") {
                    layoutState.attendanceMarkAllPresent()
                }
                Button("Repetir patrón") {
                    layoutState.attendanceRepeatPattern()
                }
                if layoutState.attendanceHasSelection {
                    Button("Cerrar ficha") {
                        layoutState.attendanceClearSelection()
                    }
                }
            } label: {
                Label("Acciones", systemImage: "ellipsis.circle")
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 8)

            DatePicker(
                "Fecha",
                selection: Binding(
                    get: { layoutState.attendanceSelectedDate },
                    set: { layoutState.setAttendanceDate($0) }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            .fixedSize()

            Picker(
                "Vista",
                selection: Binding(
                    get: { layoutState.attendanceBoardMode },
                    set: { layoutState.setAttendanceBoardMode($0) }
                )
            ) {
                Text("Día").tag("Día")
                Text("Semana").tag("Semana")
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
        }
    }

    private var moduleContextToolbarRow: some View {
        HStack(spacing: 12) {
            if activeModule == .diary {
                Menu {
                    Button("Sin clase activa") {
                        updateGlobalClassContext(nil)
                    }
                    ForEach(bridge.classes, id: \.id) { schoolClass in
                        Button {
                            updateGlobalClassContext(schoolClass.id)
                        } label: {
                            HStack {
                                Text(schoolClass.name)
                                if selectedClassId == schoolClass.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label(activeClassLabel, systemImage: "rectangle.3.group")
                        .frame(minWidth: 220, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }

            Spacer(minLength: 8)

            if activeModule == .diary {
                Button {
                    Task {
                        await bridge.pullMissingSyncChanges()
                        try? await bridge.refreshStudentsDirectory()
                    }
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var focusToggleButton: some View {
        if layoutState.isFocusModeEnabled {
            Button {
                layoutState.toggleFocusMode()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Salir del modo foco")
        } else {
            Button {
                layoutState.toggleFocusMode()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Entrar en modo foco")
        }
    }

    private var notebookToolbarActions: some View {
        HStack(spacing: 12) {
            Picker(
                "Vista del cuaderno",
                selection: Binding(
                    get: { layoutState.notebookSurfaceMode },
                    set: { layoutState.setNotebookSurfaceMode($0) }
                )
            ) {
                Label("Rejilla", systemImage: "tablecells").tag("grid")
                Label("Plano", systemImage: "square.grid.3x3.square").tag("seatingPlan")
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            if !layoutState.notebookAvailableGroups.isEmpty {
                Menu {
                    Button("Todo el grupo") {
                        layoutState.setNotebookGroupFilter(nil)
                    }

                    ForEach(layoutState.notebookAvailableGroups) { group in
                        Button {
                            layoutState.setNotebookGroupFilter(group.id)
                        } label: {
                            HStack {
                                Text(group.name)
                                Spacer()
                                Text("\(group.studentCount)")
                                    .foregroundStyle(.secondary)
                                if layoutState.notebookSelectedGroupId == group.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label(notebookGroupFilterLabel, systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.bordered)
            }

            if layoutState.notebookOrganizationMenuAvailable {
                Button {
                    layoutState.openNotebookOrganizationMenu()
                } label: {
                    Label("Columnas", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
            }

            if layoutState.isNotebookInspectorPresented {
                Button {
                    layoutState.toggleNotebookInspector()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!layoutState.notebookInspectorAvailable)
            } else {
                Button {
                    layoutState.toggleNotebookInspector()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .buttonStyle(.bordered)
                .disabled(!layoutState.notebookInspectorAvailable)
            }

            focusToggleButton

            Button {
                layoutState.showNotebookAddColumn()
            } label: {
                Label("Nueva columna", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!layoutState.notebookAddColumnAvailable)
        }
    }

    private var notebookGlobalToolbarRow: some View {
        HStack(spacing: 12) {
            Menu {
                Button("Sin clase activa") {
                    updateGlobalClassContext(nil)
                }
                ForEach(bridge.classes, id: \.id) { schoolClass in
                    Button {
                        updateGlobalClassContext(schoolClass.id)
                    } label: {
                        HStack {
                            Text(schoolClass.name)
                            if selectedClassId == schoolClass.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(activeClassLabel, systemImage: "rectangle.3.group")
                    .frame(minWidth: 220, alignment: .leading)
            }
            .buttonStyle(.bordered)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    "Buscar alumno…",
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
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Spacer(minLength: 0)

            notebookToolbarActions
        }
    }

    private var notebookGroupFilterLabel: String {
        guard let selectedId = layoutState.notebookSelectedGroupId,
              let group = layoutState.notebookAvailableGroups.first(where: { $0.id == selectedId }) else {
            return "Grupo completo"
        }
        return group.name
    }

    private var dashboardToolbarActions: some View {
        HStack(spacing: 12) {
            if layoutState.isDashboardInspectorPresented {
                Button {
                    layoutState.toggleDashboardInspector()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!layoutState.dashboardInspectorAvailable)
            } else {
                Button {
                    layoutState.toggleDashboardInspector()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .buttonStyle(.bordered)
                .disabled(!layoutState.dashboardInspectorAvailable)
            }

            focusToggleButton

            Button {
                layoutState.refreshDashboard()
            } label: {
                Label("Recargar", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Menu {
                Button("Pasar lista") {
                    layoutState.dashboardPassList()
                }
                Button("Registrar observación") {
                    layoutState.dashboardObservation()
                }
                Button("Evaluación rápida") {
                    layoutState.dashboardQuickEvaluation()
                }
            } label: {
                Label("Acciones", systemImage: "bolt.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!layoutState.dashboardActionsAvailable)
        }
    }

    private var diaryToolbarActions: some View {
        HStack(spacing: 12) {
            if layoutState.isDiaryInspectorPresented {
                Button {
                    layoutState.toggleDiaryInspector()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!layoutState.diaryInspectorAvailable)
            } else {
                Button {
                    layoutState.toggleDiaryInspector()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .buttonStyle(.bordered)
                .disabled(!layoutState.diaryInspectorAvailable)
            }

            focusToggleButton

            Button {
                openPlanner(context: resolvedPlannerContext)
            } label: {
                Label("Ver planner", systemImage: "calendar.badge.clock")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var plannerToolbarActions: some View {
        HStack(spacing: 12) {
            focusToggleButton

            Button {
                Task {
                    await bridge.pullMissingSyncChanges()
                    try? await bridge.refreshStudentsDirectory()
                }
            } label: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)

            Button {
                layoutState.openPlannerComposer()
            } label: {
                Label("Nueva sesión", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!layoutState.plannerAddSessionAvailable)
        }
    }

    private var searchResultsOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(searchResults) { result in
                Button {
                    apply(searchResult: result)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.title)
                            .font(.headline)
                        Text(result.subtitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                if result.id != searchResults.last?.id {
                    Divider().opacity(0.15)
                }
            }
        }
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 10)
    }

    @ViewBuilder
    private var activeWorkspace: some View {
        switch activeModule {
        case .dashboard:
            DashboardView(selectedClassId: $selectedClassId)
        case .courses:
            CoursesWorkspaceView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:),
                onCreateStudent: { classId in
                    selectedClassId = classId
                    createSheet = .student
                }
            )
            .environmentObject(bridge)
        case .students:
            StudentProfilesWorkspaceView(
                selectedClassId: $selectedClassId,
                selectedStudentId: $selectedStudentId,
                onOpenModule: open(module:classId:studentId:)
            )
            .environmentObject(bridge)
        case .notebook:
            NotebookModuleView(
                bridge: bridge,
                selectedClassId: $selectedClassId,
                selectedStudentId: $selectedStudentId,
                onOpenModule: open(module:classId:studentId:)
            )
        case .attendance:
            AttendanceWorkspaceView(
                selectedClassId: $selectedClassId,
                preselectedStudentId: $selectedStudentId,
                onOpenModule: open(module:classId:studentId:)
            )
            .environmentObject(bridge)
        case .planner:
            PlannerWorkspaceIOS(
                context: resolvedPlannerContext,
                onOpenDiary: { context in
                    openDiary(context: context)
                },
                onOpenSettings: {
                    open(module: .settings, classId: selectedClassId)
                },
                onNavigationContextChange: { context in
                    plannerContext = context
                }
            )
            .environmentObject(bridge)
        case .diary:
            DiaryWorkspaceView(
                selectedClassId: $selectedClassId,
                navigationContext: resolvedPlannerContext,
                onOpenModule: open(module:classId:studentId:),
                onOpenPlanner: { context in
                    openPlanner(context: context)
                },
                onNavigationContextChange: { context in
                    plannerContext = context
                }
            )
            .environmentObject(bridge)
        case .evaluationHub:
            EvaluationHubView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:)
            )
                .environmentObject(bridge)
        case .rubrics:
            RubricsWorkspaceView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:),
                onOpenBuilder: {
                    bridge.resetRubricBuilder()
                    showingRubricBuilder = true
                },
                onEditRubric: { rubric in
                    bridge.loadRubricForEditing(rubric)
                    showingRubricBuilder = true
                }
            )
            .environmentObject(bridge)
        case .reports:
            ReportsWorkspaceView(
                selectedClassId: $selectedClassId,
                selectedStudentId: $selectedStudentId
            )
                .environmentObject(bridge)
        case .library:
            LibraryWorkspaceView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:)
            )
                .environmentObject(bridge)
        case .peSessions:
            PESessionsWorkspaceView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:)
            )
            .environmentObject(bridge)
        case .peTests:
            EFPhysicalTestsWorkspaceView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:)
            )
            .environmentObject(bridge)
        case .peRubrics:
            RubricsWorkspaceView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:),
                onOpenBuilder: {
                    bridge.resetRubricBuilder()
                    showingRubricBuilder = true
                },
                onEditRubric: { rubric in
                    bridge.loadRubricForEditing(rubric)
                    showingRubricBuilder = true
                },
                peMode: true
            )
            .environmentObject(bridge)
        case .peIncidents:
            EFIncidentsWorkspaceView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:)
            )
            .environmentObject(bridge)
        case .peMaterial:
            PEMaterialWorkspaceView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:)
            )
            .environmentObject(bridge)
        case .peTournaments:
            PETournamentsWorkspaceView(selectedClassId: $selectedClassId)
                .environmentObject(bridge)
        case .settings:
            SettingsModuleView(selectedClassId: $selectedClassId)
        }
    }

    private var shouldShowGlobalContextualAIButton: Bool {
        switch activeModule {
        case .notebook, .planner, .rubrics, .library, .settings:
            return false
        default:
            return true
        }
    }

    private func presentContextualAI() {
        guard !isLoadingContextualAI else { return }
        isLoadingContextualAI = true
        Task {
            let module = activeModule
            let resolvedClassId = selectedClassId
            let resolvedStudentId = selectedStudentId
            let context: KmpBridge.ScreenAIContext
            do {
                context = try await loadContextualAIContext(
                    for: module,
                    classId: resolvedClassId,
                    studentId: resolvedStudentId
                )
            } catch {
                context = fallbackContext(for: module, classId: resolvedClassId, studentId: resolvedStudentId, message: error.localizedDescription)
            }
            await MainActor.run {
                contextualAISheetState = ContextualAISheetState(module: module, context: context)
                isLoadingContextualAI = false
            }
        }
    }

    private func loadContextualAIContext(
        for module: AppWorkspaceModule,
        classId: Int64?,
        studentId: Int64?
    ) async throws -> KmpBridge.ScreenAIContext {
        switch module {
        case .dashboard:
            return try await bridge.buildDashboardAIContext(classId: classId)
        case .courses:
            return try await bridge.buildCoursesAIContext(classId: classId)
        case .students:
            return try await bridge.buildStudentsAIContext(classId: classId, studentId: studentId)
        case .attendance:
            return try await bridge.buildAttendanceAIContext(classId: classId)
        case .diary, .planner:
            return try await bridge.buildDiaryAIContext(classId: classId)
        case .evaluationHub:
            return try await bridge.buildEvaluationAIContext(classId: classId)
        case .reports:
            return try await bridge.buildReportsAIContext(classId: classId, studentId: studentId)
        case .peSessions, .peTests, .peRubrics, .peIncidents, .peMaterial, .peTournaments:
            return try await bridge.buildPEAIContext(classId: classId)
        case .notebook:
            return bridge.buildNotebookAIContext(classId: classId)
        case .rubrics, .library, .settings:
            return fallbackContext(for: module, classId: classId, studentId: studentId, message: "Esta pantalla todavía no ofrece acciones IA contextuales.")
        }
    }

    private func fallbackContext(
        for module: AppWorkspaceModule,
        classId: Int64?,
        studentId: Int64?,
        message: String
    ) -> KmpBridge.ScreenAIContext {
        KmpBridge.ScreenAIContext(
            kind: module == .reports ? .reports : module.section == .physicalEducation ? .pe : .courses,
            title: module.title,
            subtitle: module.subtitle,
            classId: classId,
            className: bridge.classes.first(where: { $0.id == classId })?.name,
            studentId: studentId,
            studentName: bridge.allStudents.first(where: { $0.id == studentId }).map { "\($0.firstName) \($0.lastName)" },
            summary: message,
            metrics: [],
            factLines: [message],
            supportNotes: [],
            suggestedActions: [],
            hasEnoughData: false,
            dataQualityNote: message
        )
    }

    private var primaryActionLabel: String {
        switch activeModule {
        case .courses: return "Nueva clase"
        case .students: return "Nuevo alumno"
        case .planner: return "Nueva sesión"
        case .diary: return "Ver planner"
        case .evaluationHub: return "Nueva evaluación"
        case .rubrics, .peRubrics: return "Nueva rúbrica"
        case .peSessions: return "Nueva sesión EF"
        case .peTests: return "Nueva prueba"
        case .peIncidents: return "Nueva incidencia"
        case .peMaterial: return "Nuevo material"
        case .peTournaments: return "Nuevo torneo"
        default: return "Crear"
        }
    }

    private var statusLineText: String {
        let rawStatus = bridge.status.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawStatus.isEmpty, rawStatus != "Inicializando...", rawStatus != "La acción principal de este módulo se gestiona dentro de la vista." {
            return rawStatus
        }
        switch activeModule {
        case .dashboard:
            return "Selecciona un bloque del dashboard para ver contexto operativo y acciones inmediatas."
        case .courses:
            return "Abre un grupo para lanzar cuaderno, asistencia, diario, informes o alumnado desde el mismo panel."
        case .students:
            return "La ficha del alumno centraliza seguimiento, incidencias, evaluaciones y contexto docente."
        case .notebook:
            return "El cuaderno concentra calificación, seguimiento y acciones rápidas sobre columnas y alumnado."
        case .attendance:
            return "Marca asistencia, crea incidencias y revisa el pulso del grupo sin salir del módulo."
        case .planner:
            return "Planifica la semana, ajusta sesiones y salta al diario cuando necesites cerrar una sesión."
        case .diary:
            return "Cierra una sesión, deja trazabilidad docente y usa el inspector solo cuando necesites contexto secundario."
        case .evaluationHub:
            return "Selecciona un instrumento para revisar peso, rúbrica, vínculos y acceso directo al cuaderno."
        case .rubrics:
            return "El banco de rúbricas muestra criterios, niveles, clases y evaluaciones con lectura docente."
        case .reports:
            return "Genera vistas previas y comparte informes de grupo, individuales, evaluativos u operativos."
        case .library:
            return "La biblioteca agrupa plantillas reutilizables de cuaderno, rúbricas y estructura docente."
        case .peSessions:
            return "Crea sesiones EF, activa el trabajo en pista y registra material, intensidad e incidencias."
        case .peTests:
            return "Crea pruebas físicas, registra marcas y compara históricos del grupo desde un solo módulo."
        case .peRubrics:
            return "Usa plantillas EF de observación, seguridad y ejecución sin salir del banco de rúbricas."
        case .peIncidents:
            return "Registra lesiones, seguridad, conducta, equipación y seguimiento individual desde EF."
        case .peMaterial:
            return "Gestiona preparación, uso y estado del material vinculado a sesiones EF."
        case .peTournaments:
            return "Organiza torneos completos con plantillas, equipos, calendario y clasificación."
        case .settings:
            return "Configura agenda docente, calendario lectivo, sincronización y preferencias globales del workspace."
        }
    }

    private var activeClassLabel: String {
        guard let selectedClassId,
              let schoolClass = bridge.classes.first(where: { $0.id == selectedClassId })
        else { return "Clase global" }
        return schoolClass.name
    }

    private func syncRootSplitVisibility() {
        rootSplitVisibility = (layoutState.isSidebarVisible && !layoutState.isFocusModeEnabled) ? .all : .detailOnly
    }

    private func open(module: AppWorkspaceModule, classId: Int64? = nil, studentId: Int64? = nil) {
        activeModule = module
        if let classId {
            updateGlobalClassContext(classId)
        }
        if let studentId {
            selectedStudentId = studentId
        }
        searchText = ""
    }

    private var resolvedPlannerContext: PlannerNavigationContext {
        PlannerNavigationContext(
            week: plannerContext.week,
            year: plannerContext.year,
            groupId: plannerContext.groupId ?? selectedClassId,
            sessionId: plannerContext.sessionId
        )
    }

    private func openPlanner(context: PlannerNavigationContext) {
        plannerContext = context
        open(module: .planner, classId: context.groupId)
    }

    private func openDiary(context: PlannerNavigationContext) {
        plannerContext = context
        open(module: .diary, classId: context.groupId)
    }

    private func updateGlobalClassContext(_ classId: Int64?) {
        selectedClassId = classId
        plannerContext.groupId = classId
        Task {
            await bridge.selectStudentsClass(classId: classId)
        }
        if let classId {
            bridge.selectClass(id: classId)
        }
    }

    private func apply(searchResult: WorkspaceSearchResult) {
        switch searchResult.kind {
        case .module(let module):
            open(module: module)
        case .schoolClass(let classId):
            open(module: .courses, classId: classId)
        case .student(let studentId):
            open(module: .students, classId: selectedClassId, studentId: studentId)
        }
    }

    private func triggerPrimaryAction() {
        switch activeModule {
        case .courses:
            createSheet = .course
        case .students:
            createSheet = .student
        case .evaluationHub:
            createSheet = .evaluation
        case .rubrics, .peRubrics:
            bridge.resetRubricBuilder()
            showingRubricBuilder = true
        case .planner:
            layoutState.openPlannerComposer()
        case .diary:
            openPlanner(context: resolvedPlannerContext)
        default:
            bridge.status = ""
        }
    }
}

private struct CoursesWorkspaceView: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    let onCreateStudent: (Int64) -> Void
    @State private var selectedSummary: KmpBridge.CourseInspectorSnapshot?

    var body: some View {
        HStack(spacing: 0) {
            List(selection: Binding(
                get: { selectedClassId },
                set: { newValue in
                    selectedClassId = newValue
                    guard let newValue else { return }
                    Task { await loadSummary(for: newValue) }
                }
            )) {
                Section("Cursos") {
                    ForEach(bridge.classes, id: \.id) { schoolClass in
                        Button {
                            selectedClassId = schoolClass.id
                            Task { await loadSummary(for: schoolClass.id) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(schoolClass.name)
                                    .font(.headline)
                                Text("Curso \(schoolClass.course)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minWidth: 320, maxWidth: 360)

            Divider().opacity(0.2)

            Group {
                if let summary = selectedSummary {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            WorkspaceInspectorHero(
                                title: summary.schoolClass.name,
                                subtitle: summary.schoolClass.description_?.isEmpty == false ? summary.schoolClass.description_! : "Curso \(summary.schoolClass.course)"
                            )

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                                WorkspaceMetricCard(title: "Alumnado", value: "\(summary.studentCount)", systemImage: "person.3.fill")
                                WorkspaceMetricCard(title: "Lesionados", value: "\(summary.injuredStudentCount)", systemImage: "figure.run.circle")
                                WorkspaceMetricCard(title: "Asistencia", value: "\(summary.attendanceRate)%", systemImage: "checklist.checked")
                                WorkspaceMetricCard(title: "Evaluaciones", value: "\(summary.evaluationCount)", systemImage: "chart.bar.doc.horizontal")
                                WorkspaceMetricCard(title: "Incidencias", value: "\(summary.incidentCount)", systemImage: "exclamationmark.bubble.fill")
                                WorkspaceMetricCard(title: "Huecos semanales", value: "\(summary.weeklySlotCount)", systemImage: "calendar.badge.clock")
                                WorkspaceMetricCard(title: "Media", value: IosFormatting.decimal(from: summary.averageScore), systemImage: "sum")
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                Text("Pulso de hoy")
                                    .font(.headline)
                                HStack(spacing: 12) {
                                    WorkspaceCompactStat(title: "Presentes", value: "\(summary.todayPresentCount)", tint: .green)
                                    WorkspaceCompactStat(title: "Ausencias", value: "\(summary.todayAbsentCount)", tint: .red)
                                    WorkspaceCompactStat(title: "Retrasos", value: "\(summary.todayLateCount)", tint: .orange)
                                    WorkspaceCompactStat(title: "Críticas", value: "\(summary.severeIncidentCount)", tint: .pink)
                                }
                            }

                            if !summary.activeEvaluationNames.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Evaluaciones activas")
                                        .font(.headline)
                                    FlowLayout(spacing: 10) {
                                        ForEach(summary.activeEvaluationNames, id: \.self) { name in
                                            WorkspaceTag(text: name, systemImage: "chart.bar.doc.horizontal")
                                        }
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Roster rápido")
                                    .font(.headline)
                                if summary.rosterPreview.isEmpty {
                                    Text("Todavía no hay alumnado asignado a este curso.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(summary.rosterPreview, id: \.id) { student in
                                        Button {
                                            onOpenModule(.students, summary.schoolClass.id, student.id)
                                        } label: {
                                            HStack(spacing: 12) {
                                                Circle()
                                                    .fill(student.isInjured ? Color.orange.opacity(0.25) : Color.accentColor.opacity(0.16))
                                                    .frame(width: 38, height: 38)
                                                    .overlay(
                                                        Image(systemName: student.isInjured ? "cross.case.fill" : "person.fill")
                                                            .font(.caption.bold())
                                                            .foregroundStyle(student.isInjured ? Color.orange : Color.accentColor)
                                                    )
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("\(student.firstName) \(student.lastName)")
                                                        .font(.subheadline.weight(.bold))
                                                        .foregroundStyle(.primary)
                                                    Text(student.isInjured ? "Seguimiento físico activo" : "Abrir ficha")
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(12)
                                            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            WorkspaceActionRow(title: "Abrir cuaderno", systemImage: "book.closed.fill") {
                                onOpenModule(.notebook, summary.schoolClass.id, nil)
                            }
                            WorkspaceActionRow(title: "Abrir alumnado", systemImage: "person.text.rectangle.fill") {
                                onOpenModule(.students, summary.schoolClass.id, summary.rosterPreview.first?.id)
                            }
                            WorkspaceActionRow(title: "Pasar a asistencia", systemImage: "checklist.checked") {
                                onOpenModule(.attendance, summary.schoolClass.id, nil)
                            }
                            WorkspaceActionRow(title: "Entrar al diario", systemImage: "doc.text.fill") {
                                onOpenModule(.diary, summary.schoolClass.id, nil)
                            }
                            WorkspaceActionRow(title: "Ver informes", systemImage: "doc.richtext.fill") {
                                onOpenModule(.reports, summary.schoolClass.id, nil)
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                Text("Acciones de grupo")
                                    .font(.headline)

                                Button {
                                    onCreateStudent(summary.schoolClass.id)
                                } label: {
                                    Label("Alta rápida de alumno", systemImage: "person.badge.plus")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.borderedProminent)

                                if bridge.classes.contains(where: { $0.id != summary.schoolClass.id }) {
                                    Menu {
                                        ForEach(bridge.classes.filter { $0.id != summary.schoolClass.id }, id: \.id) { targetClass in
                                            Button(targetClass.name) {
                                                Task { await duplicateNotebookStructure(from: summary.schoolClass.id, to: targetClass.id) }
                                            }
                                        }
                                    } label: {
                                        Label("Duplicar estructura de cuaderno", systemImage: "square.on.square")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .padding(24)
                    }
                } else {
                    WorkspaceEmptyState(
                        title: "Selecciona un curso",
                        subtitle: "Desde aquí centralizamos el acceso a cuaderno, asistencia, diario e informes."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appPageBackground(for: colorScheme))
        }
        .task {
            await bridge.ensureClassesLoaded()
            if selectedClassId == nil {
                selectedClassId = bridge.classes.first?.id
            }
            if let selectedClassId {
                await loadSummary(for: selectedClassId)
            }
        }
    }

    @MainActor
    private func loadSummary(for classId: Int64) async {
        selectedSummary = try? await bridge.loadCourseSummary(classId: classId)
    }

    @MainActor
    private func duplicateNotebookStructure(from sourceClassId: Int64, to targetClassId: Int64) async {
        do {
            bridge.selectClass(id: sourceClassId)
            try await bridge.duplicateNotebookStructure(to: targetClassId)
            let destinationName = bridge.classes.first(where: { $0.id == targetClassId })?.name ?? "el curso destino"
            bridge.status = "Estructura duplicada en \(destinationName)."
        } catch {
            bridge.status = "No se pudo duplicar la estructura: \(error.localizedDescription)"
        }
    }
}

private enum AttendanceBoardMode: String, CaseIterable, Identifiable {
    case day = "Día"
    case week = "Semana"

    var id: String { rawValue }
}

private struct AttendanceStatusOption: Identifiable, Hashable {
    let id: String
    let label: String
    let shortLabel: String
    let color: Color

    static let all: [AttendanceStatusOption] = [
        .init(id: "PRESENTE", label: "Presente", shortLabel: "P", color: .green),
        .init(id: "AUSENTE", label: "Ausente", shortLabel: "A", color: .red),
        .init(id: "TARDE", label: "Retraso", shortLabel: "R", color: .orange),
        .init(id: "JUSTIFICADO", label: "Justificada", shortLabel: "J", color: .gray),
        .init(id: "SIN_MATERIAL", label: "Sin material", shortLabel: "M", color: .brown),
        .init(id: "EXENTO", label: "Exento", shortLabel: "E", color: .indigo)
    ]
}

private struct AttendanceEntryRow: Identifiable {
    let id: Int64
    let student: Student
    let record: KmpBridge.AttendanceRecordSnapshot?
}

private struct AttendanceWorkspaceView: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var layoutState: WorkspaceLayoutState
    @Binding var selectedClassId: Int64?
    @Binding var preselectedStudentId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void

    @State private var selectedDate = Date()
    @State private var boardMode: AttendanceBoardMode = .day
    @State private var selectedStatusFilter = "TODOS"
    @State private var searchText = ""
    @State private var selectedStudentId: Int64?
    @State private var recordsByStudentId: [Int64: KmpBridge.AttendanceRecordSnapshot] = [:]
    @State private var savingStudentIds: Set<Int64> = []
    @State private var saveRevisionByStudentId: [Int64: Int] = [:]
    @State private var history: [KmpBridge.AttendanceRecordSnapshot] = []
    @State private var incidents: [Incident] = []
    @State private var sessions: [KmpBridge.AttendanceSessionSnapshot] = []
    @State private var noteDraft = ""

    private var boardSummary: (present: Int, absent: Int, late: Int, untracked: Int) {
        let rows = bridge.studentsInClass.map { recordsByStudentId[$0.id] }
        let present = rows.filter { $0?.status.uppercased().contains("PRESENT") == true }.count
        let absent = rows.filter { $0?.status.uppercased().contains("AUS") == true }.count
        let late = rows.filter { status in
            guard let status = status?.status.uppercased() else { return false }
            return status.contains("TARD") || status.contains("RETR")
        }.count
        let untracked = max(bridge.studentsInClass.count - present - absent - late, 0)
        return (present, absent, late, untracked)
    }

    private var filteredRows: [AttendanceEntryRow] {
        bridge.studentsInClass
            .map { student in AttendanceEntryRow(id: student.id, student: student, record: recordsByStudentId[student.id]) }
            .filter {
                let matchesStatus = selectedStatusFilter == "TODOS" || $0.record?.status == selectedStatusFilter
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                let fullName = "\($0.student.firstName) \($0.student.lastName)"
                let matchesSearch = query.isEmpty || fullName.localizedCaseInsensitiveContains(query)
                return matchesStatus && matchesSearch
            }
    }

    private var selectedStudent: Student? {
        bridge.studentsInClass.first(where: { $0.id == selectedStudentId })
    }

    private var selectedAttendance: KmpBridge.AttendanceRecordSnapshot? {
        guard let selectedStudentId else { return nil }
        return recordsByStudentId[selectedStudentId]
    }

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -2, to: selectedDate) ?? selectedDate
        return (0..<5).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var isInspectorPresented: Bool {
        selectedStudentId != nil && !layoutState.isFocusModeEnabled
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                attendanceToolbar

                if boardMode == .day {
                    List(filteredRows) { row in
                        AttendanceRowCard(
                            row: row,
                            onPickStatus: { status in
                                Task { await updateAttendance(for: row.student, status: status.id) }
                            },
                            onSelect: { selectedStudentId = row.student.id },
                            isSaving: savingStudentIds.contains(row.student.id)
                        )
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                weekCellHeader("Alumno", width: 220)
                                ForEach(weekDates, id: \.self) { date in
                                    weekCellHeader(Self.weekdayString(date), width: 120)
                                }
                            }

                            ForEach(bridge.studentsInClass, id: \.id) { student in
                                HStack(spacing: 0) {
                                    Button {
                                        selectedStudentId = student.id
                                    } label: {
                                        HStack {
                                            Text("\(student.firstName) \(student.lastName)")
                                                .font(.subheadline.weight(.semibold))
                                            Spacer()
                                        }
                                        .padding(.horizontal, 12)
                                        .frame(width: 220, height: 54)
                                    }
                                    .buttonStyle(.plain)
                                    .background(appCardBackground(for: colorScheme))

                                    ForEach(weekDates, id: \.self) { date in
                                        let status = weekStatus(for: student.id, date: date)
                                        attendanceWeekStatusCell(status)
                                    }
                                }
                            }
                        }
                    }
                    .background(appPageBackground(for: colorScheme))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appPageBackground(for: colorScheme))

            if isInspectorPresented {
                Divider().opacity(0.12)

                attendanceInspector
                    .frame(width: 336)
                    .background(appMutedCardBackground(for: colorScheme))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .task {
            await bridge.ensureClassesLoaded()
            if selectedClassId == nil {
                selectedClassId = bridge.classes.first?.id
            }
            await syncClassSelection()
            if let preselectedStudentId {
                selectedStudentId = preselectedStudentId
                self.preselectedStudentId = nil
            }
        }
        .onChange(of: selectedClassId) { _ in
            Task { await syncClassSelection() }
        }
        .onChange(of: selectedDate) { _ in
            Task { await reloadAttendance() }
        }
        .onChange(of: boardMode) { _ in
            selectedStudentId = nil
        }
        .onChange(of: selectedStudentId) { _ in
            noteDraft = selectedAttendance?.note ?? ""
        }
        .onAppear(perform: syncAttendanceToolbar)
        .onChange(of: toolbarStateKey) { _ in
            syncAttendanceToolbar()
        }
        .onDisappear {
            layoutState.clearAttendanceToolbar()
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: isInspectorPresented)
    }

    private var attendanceToolbar: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let selectedStudent {
                Button {
                    selectedStudentId = nil
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(selectedStudent.firstName) \(selectedStudent.lastName)")
                                .font(.headline)
                            Text(selectedAttendance?.status ?? "Sin registro")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Ocultar ficha")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(16)
                    .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                WorkspaceCompactStat(title: "Presentes", value: "\(boardSummary.present)", tint: .green)
                WorkspaceCompactStat(title: "Ausencias", value: "\(boardSummary.absent)", tint: .red)
                WorkspaceCompactStat(title: "Retrasos", value: "\(boardSummary.late)", tint: .orange)
                WorkspaceCompactStat(title: "Pendientes", value: "\(boardSummary.untracked)", tint: .gray)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .background(appPageBackground(for: colorScheme))
    }

    @ViewBuilder
    private var attendanceInspector: some View {
        if let student = selectedStudent {
            let studentIncidents = incidents.filter { $0.studentId?.int64Value == student.id }
            let recentStatuses = history.filter { $0.studentId == student.id }.sorted { $0.date > $1.date }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 12) {
                        WorkspaceInspectorHero(
                            title: "\(student.firstName) \(student.lastName)",
                            subtitle: "Histórico de asistencia e incidencias"
                        )
                        Spacer()
                        Button {
                            selectedStudentId = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .background(appCardBackground(for: colorScheme), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    WorkspaceMetricCard(
                        title: "Último estado",
                        value: recentStatuses.first?.status ?? "Sin registros",
                        systemImage: "clock.badge.checkmark"
                    )

                    if let latest = recentStatuses.first {
                        WorkspaceMetricCard(
                            title: "Seguimiento",
                            value: latest.followUpRequired ? "Requiere revisión" : "Sin seguimiento",
                            systemImage: latest.followUpRequired ? "arrow.triangle.branch" : "checkmark.circle"
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Histórico reciente")
                            .font(.headline)
                        ForEach(Array(recentStatuses.prefix(6)), id: \.id) { attendance in
                            HStack {
                                Text(dateLabel(from: attendance.date))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(attendance.status)
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }

                    if !sessions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Sesiones del día")
                                .font(.headline)
                            ForEach(sessions) { entry in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(entry.session.teachingUnitName)
                                            .font(.subheadline.weight(.bold))
                                        Spacer()
                                        Text("P\(entry.session.period)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(entry.session.status.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    if let journalSummary = entry.journalSummary {
                                        Text("Diario: \(journalSummary.status.name.capitalized) · clima \(journalSummary.climateScore)/5")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("Sin diario registrado todavía")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(12)
                                .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Incidencias")
                            .font(.headline)
                        if studentIncidents.isEmpty {
                            Text("Sin incidencias asociadas")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(studentIncidents.prefix(4)), id: \.id) { incident in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(incident.title)
                                        .font(.subheadline.weight(.bold))
                                    Text(incident.detail ?? "Sin detalle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Nota de asistencia")
                            .font(.headline)
                        TextField("Observación rápida de la sesión…", text: $noteDraft, axis: .vertical)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .lineLimit(3, reservesSpace: true)

                        Button("Guardar nota") {
                            Task { await saveAttendanceNote(for: student.id) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedAttendance == nil)
                    }

                    HStack(spacing: 12) {
                        Button("Abrir ficha de alumno") {
                            onOpenModule(.students, selectedClassId, student.id)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Abrir diario") {
                            onOpenModule(.diary, selectedClassId, student.id)
                        }
                        .buttonStyle(.bordered)

                        Button("Abrir cuaderno") {
                            onOpenModule(.notebook, selectedClassId, student.id)
                        }
                        .buttonStyle(.bordered)
                    }

                    if let selectedClassId {
                        Button("Registrar incidencia desde asistencia") {
                            Task { await createAttendanceIncident(for: student.id, classId: selectedClassId, latestStatus: recentStatuses.first?.status) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(20)
            }
        } else {
            WorkspaceEmptyState(
                title: "Selecciona un alumno",
                subtitle: "El inspector muestra histórico, patrón reciente e incidencias de asistencia."
            )
        }
    }

    @MainActor
    private func syncClassSelection() async {
        selectedStudentId = nil
        await bridge.selectStudentsClass(classId: selectedClassId)
        await reloadAttendance()
        syncAttendanceToolbar()
    }

    @MainActor
    private func reloadAttendance() async {
        guard let selectedClassId else { return }
        let records = (try? await bridge.attendanceRecords(for: selectedClassId, on: selectedDate)) ?? []
        recordsByStudentId = Dictionary(
            uniqueKeysWithValues: normalizedAttendanceRecords(records).map { ($0.studentId, $0) }
        )
        history = (try? await bridge.attendanceHistory(for: selectedClassId, days: 21)) ?? []
        incidents = (try? await bridge.incidents(for: selectedClassId)) ?? []
        sessions = (try? await bridge.attendanceSessions(for: selectedClassId, on: selectedDate)) ?? []
        noteDraft = selectedAttendance?.note ?? ""
        syncAttendanceToolbar()
    }

    private func normalizedAttendanceRecords(
        _ records: [KmpBridge.AttendanceRecordSnapshot]
    ) -> [KmpBridge.AttendanceRecordSnapshot] {
        Dictionary(grouping: records, by: \.studentId)
            .values
            .compactMap { duplicates in
                duplicates.max { lhs, rhs in
                    attendanceRecordPriority(lhs) < attendanceRecordPriority(rhs)
                }
            }
    }

    private func attendanceRecordPriority(_ record: KmpBridge.AttendanceRecordSnapshot) -> (Int, Int64) {
        let sessionPriority = record.sessionId == nil ? 0 : 1
        return (sessionPriority, record.id)
    }

    private var toolbarStateKey: String {
        [
            searchText,
            selectedStatusFilter,
            boardMode.rawValue,
            String(Int(selectedDate.timeIntervalSince1970)),
            selectedStudentId.map(String.init) ?? "none"
        ].joined(separator: "|")
    }

    private func syncAttendanceToolbar() {
        if layoutState.attendanceToolbarAvailable {
            layoutState.updateAttendanceToolbar(
                searchText: searchText,
                selectedDate: selectedDate,
                boardMode: boardMode.rawValue,
                selectedStatusFilter: selectedStatusFilter,
                hasSelection: selectedStudentId != nil
            )
        } else {
            layoutState.configureAttendanceToolbar(
                searchText: searchText,
                selectedDate: selectedDate,
                boardMode: boardMode.rawValue,
                selectedStatusFilter: selectedStatusFilter,
                hasSelection: selectedStudentId != nil,
                onSearchTextChange: { searchText = $0 },
                onDateChange: { selectedDate = $0 },
                onBoardModeChange: { rawValue in
                    if let mode = AttendanceBoardMode(rawValue: rawValue) {
                        boardMode = mode
                    }
                },
                onStatusFilterChange: { selectedStatusFilter = $0 },
                onMarkAllPresent: {
                    Task { await markAllPresent() }
                },
                onRepeatPattern: {
                    Task { await repeatPattern() }
                },
                onClearSelection: {
                    selectedStudentId = nil
                }
            )
        }
    }

    private func updateAttendance(for student: Student, status: String) async {
        guard let selectedClassId else { return }
        let previousRecord = recordsByStudentId[student.id]
        let revision = (saveRevisionByStudentId[student.id] ?? 0) + 1
        saveRevisionByStudentId[student.id] = revision
        savingStudentIds.insert(student.id)
        applyLocalAttendanceStatus(status, for: student, classId: selectedClassId)

        do {
            try await bridge.saveAttendance(
                studentId: student.id,
                classId: selectedClassId,
                on: selectedDate,
                status: status
            )
            selectedStudentId = student.id
            if saveRevisionByStudentId[student.id] == revision {
                savingStudentIds.remove(student.id)
                bridge.status = "Asistencia actualizada."
            }
        } catch {
            if saveRevisionByStudentId[student.id] == revision {
                recordsByStudentId[student.id] = previousRecord
                savingStudentIds.remove(student.id)
            }
            bridge.status = "No se pudo guardar la asistencia: \(error.localizedDescription)"
        }
    }

    private func applyLocalAttendanceStatus(_ status: String, for student: Student, classId: Int64) {
        let baseRecord = recordsByStudentId[student.id]
        recordsByStudentId[student.id] = KmpBridge.AttendanceRecordSnapshot(
            id: baseRecord?.id ?? -student.id,
            studentId: student.id,
            classId: classId,
            date: selectedDate,
            status: status,
            note: baseRecord?.note ?? "",
            hasIncident: baseRecord?.hasIncident ?? false,
            followUpRequired: baseRecord?.followUpRequired ?? false,
            sessionId: baseRecord?.sessionId
        )
        if selectedStudentId == student.id {
            noteDraft = recordsByStudentId[student.id]?.note ?? ""
        }
    }

    private func markAllPresent() async {
        guard let selectedClassId else { return }
        for student in bridge.studentsInClass {
            applyLocalAttendanceStatus("PRESENTE", for: student, classId: selectedClassId)
            try? await bridge.saveAttendance(studentId: student.id, classId: selectedClassId, on: selectedDate, status: "PRESENTE")
        }
        savingStudentIds.removeAll()
        await reloadAttendance()
    }

    private func repeatPattern() async {
        guard let selectedClassId else { return }
        let applied = (try? await bridge.repeatLatestAttendancePattern(classId: selectedClassId, targetDate: selectedDate)) ?? 0
        bridge.status = applied > 0 ? "Patrón anterior aplicado a \(applied) registros" : "No había patrón anterior reutilizable"
        await reloadAttendance()
    }

    private func weekStatus(for studentId: Int64, date: Date) -> AttendanceStatusOption {
        let dayEpoch = Int64(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        let record = history.first {
            $0.studentId == studentId &&
            Int64($0.date.stripTime.timeIntervalSince1970) == dayEpoch
        }
        return AttendanceStatusOption.all.first(where: { $0.id == record?.status }) ?? .init(id: "--", label: "Sin dato", shortLabel: "-", color: .clear)
    }

    private func attendanceWeekStatusCell(_ status: AttendanceStatusOption) -> some View {
        let borderColor = Color.white.opacity(0.08)
        return Text(status.shortLabel)
            .font(.caption.bold())
            .frame(width: 120, height: 54)
            .background(status.color.opacity(0.18))
            .overlay(Rectangle().stroke(borderColor, lineWidth: 0.5))
    }

    private func weekCellHeader(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.caption.bold())
            .frame(width: width, height: 44)
            .background(appMutedCardBackground(for: colorScheme))
    }

    private func dateLabel(from date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private static func weekdayString(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day())
    }

    private func createAttendanceIncident(for studentId: Int64, classId: Int64, latestStatus: String?) async {
        let statusText = latestStatus ?? "sin registro previo"
        let detail = "Incidencia creada desde asistencia el \(selectedDate.formatted(date: .abbreviated, time: .omitted)). Estado observado: \(statusText)."
        do {
            _ = try await bridge.createIncident(
                classId: classId,
                studentId: studentId,
                title: "Seguimiento de asistencia",
                detail: detail,
                severity: "medium"
            )
            incidents = (try? await bridge.incidents(for: classId)) ?? incidents
            bridge.status = "Incidencia registrada desde asistencia."
        } catch {
            bridge.status = "No se pudo crear la incidencia: \(error.localizedDescription)"
        }
    }

    private func saveAttendanceNote(for studentId: Int64) async {
        guard let selectedClassId else { return }
        let currentStatus = selectedAttendance?.status ?? "PRESENTE"
        do {
            try await bridge.saveAttendance(
                studentId: studentId,
                classId: selectedClassId,
                on: selectedDate,
                status: currentStatus,
                note: noteDraft,
                hasIncident: selectedAttendance?.hasIncident ?? false
            )
            bridge.status = "Nota de asistencia guardada."
            await reloadAttendance()
        } catch {
            bridge.status = "No se pudo guardar la nota: \(error.localizedDescription)"
        }
    }
}

private struct EvaluationHubView: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    @State private var evaluations: [Evaluation] = []
    @State private var selectedEvaluationId: Int64?
    @State private var searchText = ""
    @State private var selectedTypeFilter = "Todas"

    private var availableTypes: [String] {
        ["Todas"] + Array(Set(evaluations.map(\.type))).sorted()
    }

    private var filteredEvaluations: [Evaluation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return evaluations.filter { evaluation in
            let matchesType = selectedTypeFilter == "Todas" || evaluation.type == selectedTypeFilter
            let matchesText = query.isEmpty
                || evaluation.name.localizedCaseInsensitiveContains(query)
                || evaluation.code.localizedCaseInsensitiveContains(query)
                || (evaluation.description_?.localizedCaseInsensitiveContains(query) ?? false)
            return matchesType && matchesText
        }
        .sorted { lhs, rhs in
            if lhs.weight == rhs.weight {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.weight > rhs.weight
        }
    }

    private var selectedEvaluation: Evaluation? {
        filteredEvaluations.first(where: { $0.id == selectedEvaluationId }) ?? evaluations.first(where: { $0.id == selectedEvaluationId })
    }

    private var selectedPresentation: EvaluationInspectorModel? {
        guard let selectedEvaluation else { return nil }
        return evaluationPresentation(
            evaluation: selectedEvaluation,
            rubrics: bridge.rubrics,
            rubricClassLinks: bridge.rubricClassLinks
        )
    }

    private var rubricName: String {
        guard let rubricId = selectedEvaluation?.rubricId?.int64Value else { return "Sin asignar" }
        return bridge.rubrics.first(where: { $0.rubric.id == rubricId })?.rubric.name ?? "Rúbrica #\(rubricId)"
    }

    private var linkedClassCountText: String {
        guard let rubricId = selectedEvaluation?.rubricId?.int64Value else { return "0" }
        return "\(bridge.rubricClassLinks[rubricId]?.count ?? 0)"
    }

    private var evaluationMetrics: (total: Int, linkedRubrics: Int, averageWeight: Double) {
        let total = filteredEvaluations.count
        let linkedRubrics = filteredEvaluations.filter { $0.rubricId != nil }.count
        let averageWeight = filteredEvaluations.isEmpty ? 0 : filteredEvaluations.map(\.weight).reduce(0, +) / Double(filteredEvaluations.count)
        return (total, linkedRubrics, averageWeight)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Buscar evaluación o código…", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Picker("Tipo", selection: $selectedTypeFilter) {
                        ForEach(availableTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 10) {
                        WorkspaceCompactStat(title: "Total", value: "\(evaluationMetrics.total)", tint: .blue)
                        WorkspaceCompactStat(title: "Con rúbrica", value: "\(evaluationMetrics.linkedRubrics)", tint: .green)
                        WorkspaceCompactStat(title: "Peso medio", value: String(format: "%.1f", evaluationMetrics.averageWeight), tint: .orange)
                    }
                }
                .padding(16)

                List {
                    Section("Evaluaciones") {
                        ForEach(filteredEvaluations, id: \.id) { evaluation in
                            Button {
                                selectedEvaluationId = evaluation.id
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(evaluation.name)
                                        .font(.headline)
                                    Text("\(evaluation.type) · Peso \(String(format: "%.1f", evaluation.weight))")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 320, maxWidth: 360)

            Divider().opacity(0.2)

            Group {
                if selectedEvaluation != nil, let presentation = selectedPresentation {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            WorkspaceInspectorHero(title: presentation.title, subtitle: presentation.subtitle)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                                WorkspaceMetricCard(title: "Peso", value: presentation.weightText, systemImage: "scalemass")
                                WorkspaceMetricCard(title: "Código", value: presentation.code, systemImage: "number")
                                WorkspaceMetricCard(title: "Rúbrica", value: presentation.rubricName, systemImage: "checklist")
                                WorkspaceMetricCard(
                                    title: "Clases con rúbrica",
                                    value: presentation.linkedClassCountText,
                                    systemImage: "rectangle.3.group"
                                )
                            }

                            HStack(spacing: 12) {
                                Button("Abrir cuaderno") {
                                    onOpenModule(.notebook, selectedClassId, nil)
                                }
                                .buttonStyle(.borderedProminent)
                                Button("Ir a rúbricas") {
                                    onOpenModule(.rubrics, selectedClassId, nil)
                                }
                                .buttonStyle(.bordered)
                            }

                            WorkspaceDetailBlock(title: "Resumen del instrumento", content: presentation.summary)

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Contexto evaluativo")
                                    .font(.headline)
                                FlowLayout(spacing: 10) {
                                    WorkspaceTag(text: selectedClassId == nil ? "Clase global" : "Clase activa", systemImage: "rectangle.3.group")
                                    ForEach(Array(presentation.readinessTags.enumerated()), id: \.offset) { _, tag in
                                        WorkspaceTag(text: tag, systemImage: "tag.fill")
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Acciones rápidas")
                                    .font(.headline)
                                WorkspaceActionRow(title: "Abrir cuaderno del grupo", systemImage: "book.closed.fill") {
                                    onOpenModule(.notebook, selectedClassId, nil)
                                }
                                WorkspaceActionRow(title: "Ir a banco de rúbricas", systemImage: "checklist") {
                                    onOpenModule(.rubrics, selectedClassId, nil)
                                }
                            }
                        }
                        .padding(24)
                    }
                } else {
                    VStack(spacing: 18) {
                        WorkspaceEmptyState(
                            title: "Selecciona una evaluación",
                            subtitle: "Revisa instrumentos, peso, rúbrica asociada y acceso directo a cuaderno o banco de rúbricas."
                        )
                        HStack(spacing: 12) {
                            Button("Crear evaluación") {
                                bridge.status = "Usa el botón superior para crear una evaluación nueva."
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Abrir cuaderno") {
                                onOpenModule(.notebook, selectedClassId, nil)
                            }
                            .buttonStyle(.bordered)
                            Button("Abrir rúbricas") {
                                onOpenModule(.rubrics, selectedClassId, nil)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appPageBackground(for: colorScheme))
        }
        .task { await reload() }
        .onChange(of: selectedClassId) { _ in
            Task { await reload() }
        }
    }

    @MainActor
    private func reload() async {
        guard let selectedClassId else {
            evaluations = []
            selectedEvaluationId = nil
            return
        }
        evaluations = (try? await bridge.evaluations(for: selectedClassId)) ?? []
        if selectedEvaluationId == nil {
            selectedEvaluationId = evaluations.first?.id
        } else if !evaluations.contains(where: { $0.id == selectedEvaluationId }) {
            selectedEvaluationId = evaluations.first?.id
        }
    }
}

private struct DiaryWorkspaceView: View {
    @EnvironmentObject private var bridge: KmpBridge
    @EnvironmentObject private var layoutState: WorkspaceLayoutState
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedClassId: Int64?
    let navigationContext: PlannerNavigationContext
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    let onOpenPlanner: (PlannerNavigationContext) -> Void
    let onNavigationContextChange: (PlannerNavigationContext) -> Void

    @StateObject private var vm = PlannerWorkspaceViewModel()
    @State private var selectedFilter: DiaryStatusFilter = .all
    @State private var selectedDayFilter = "Todos"
    @State private var selectedUnitFilter = "Todas"
    @State private var showingInspector = false

    private var availableDays: [String] {
        ["Todos", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes"]
    }

    private var availableUnits: [String] {
        ["Todas"] + Array(Set(vm.sessions.map(\.teachingUnitName))).sorted()
    }

    private var diarySessions: [PlanningSession] {
        vm.filteredSessions.filter { session in
            let summary = vm.summary(for: session.id)
            let matchesFilter: Bool = {
                switch selectedFilter {
                case .all:
                    return true
                case .drafts:
                    return summary?.status == .draft
                case .completed:
                    return summary?.status == .completed
                case .incomplete:
                    let status = summary?.status ?? .empty
                    return status != .completed
                case .incidents:
                    return !(summary?.incidentTags.isEmpty ?? true)
                case .empty:
                    return summary == nil || summary?.status == .empty
                }
            }()

            let matchesDay = selectedDayFilter == "Todos" || weekdayLabel(session.dayOfWeek) == selectedDayFilter
            let matchesUnit = selectedUnitFilter == "Todas" || session.teachingUnitName == selectedUnitFilter

            return matchesFilter && matchesDay && matchesUnit
        }
    }

    private var currentNavigationContext: PlannerNavigationContext {
        PlannerNavigationContext(
            week: vm.week,
            year: vm.year,
            groupId: selectedSession?.groupId ?? selectedClassId,
            sessionId: selectedSession?.id
        )
    }

    private var selectedSession: PlanningSession? {
        vm.selectedSession
    }

    private var diaryMetrics: (total: Int, pending: Int, incidents: Int) {
        let total = diarySessions.count
        let pending = diarySessions.filter { (vm.summary(for: $0.id)?.status ?? .empty) != .completed }.count
        let incidents = diarySessions.filter { !(vm.summary(for: $0.id)?.incidentTags.isEmpty ?? true) }.count
        return (total, pending, incidents)
    }

    private var selectedSummary: SessionJournalSummary? {
        selectedSession.flatMap { vm.summary(for: $0.id) }
    }

    private var diaryToolbarKey: String {
        "\(selectedSession?.id ?? -1)-\(showingInspector)"
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 16) {
                diaryLocalToolbar

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(diarySessions, id: \.id) { session in
                            let sessionSummary = vm.summary(for: session.id)
                            let isSessionSelected = session.id == selectedSession?.id
                            let sessionTimeLabel = vm.timeLabel(for: Int(session.period))
                            DiarySessionRailCard(
                                session: session,
                                summary: sessionSummary,
                                isSelected: isSessionSelected,
                                timeLabel: sessionTimeLabel,
                                onTap: {
                                    Task { await vm.select(session: session) }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
            .frame(minWidth: 320, maxWidth: 360, maxHeight: .infinity, alignment: .top)
            .background(appMutedCardBackground(for: colorScheme).opacity(0.28))

            Divider().opacity(0.2)

            Group {
                if selectedSession != nil {
                    PlannerJournalDetailPane(vm: vm, efVisibility: .contextual)
                } else {
                    VStack(spacing: 18) {
                        WorkspaceEmptyState(
                            title: "Selecciona una sesión",
                            subtitle: "La sesión activa ocupará este espacio con edición inline, métricas y seguimiento sin saltar a otra pantalla."
                        )
                        HStack(spacing: 12) {
                            Button("Ver planner") {
                                onOpenPlanner(currentNavigationContext)
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Ir a asistencia") {
                                onOpenModule(.attendance, selectedClassId, nil)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appPageBackground(for: colorScheme))

            if showingInspector, let session = selectedSession {
                Divider().opacity(0.2)
                DiaryInspectorPanel(
                    session: session,
                    summary: selectedSummary,
                    timeLabel: vm.timeLabel(for: Int(session.period)),
                    onOpenAttendance: {
                        onOpenModule(.attendance, session.groupId, nil)
                    },
                    onOpenNotebook: {
                        onOpenModule(.notebook, session.groupId, nil)
                    },
                    onOpenStudents: {
                        onOpenModule(.students, session.groupId, nil)
                    }
                )
                .frame(width: 340)
                .background(appMutedCardBackground(for: colorScheme).opacity(0.22))
            }
        }
        .task {
            await vm.bind(bridge: bridge)
            await vm.applyExternalContext(
                week: navigationContext.week,
                year: navigationContext.year,
                groupId: navigationContext.groupId ?? selectedClassId,
                sessionId: navigationContext.sessionId
            )
            syncSelection()
            configureDiaryToolbar()
            syncNavigationContext()
        }
        .onChange(of: selectedClassId) { _ in
            Task {
                await vm.applyExternalContext(
                    week: navigationContext.week ?? vm.week,
                    year: navigationContext.year ?? vm.year,
                    groupId: selectedClassId,
                    sessionId: selectedSession?.id
                )
                syncSelection()
                syncNavigationContext()
            }
        }
        .onChange(of: navigationContext) { newValue in
            Task {
                await vm.applyExternalContext(
                    week: newValue.week,
                    year: newValue.year,
                    groupId: newValue.groupId ?? selectedClassId,
                    sessionId: newValue.sessionId
                )
                syncSelection()
                syncNavigationContext()
            }
        }
        .onChange(of: vm.searchText) { _ in
            vm.applySearch()
        }
        .onChange(of: diaryToolbarKey) { _ in
            configureDiaryToolbar()
        }
        .onChange(of: diarySessions.map(\.id)) { _ in
            syncSelection()
        }
        .onChange(of: vm.week) { _ in syncNavigationContext() }
        .onChange(of: vm.year) { _ in syncNavigationContext() }
        .onChange(of: vm.selectedSession?.id) { _ in
            syncSelection()
            syncNavigationContext()
        }
        .onDisappear {
            layoutState.clearDiaryToolbar()
        }
    }

    private func weekdayLabel(_ dayOfWeek: Int32) -> String {
        switch Int(dayOfWeek) {
        case 1: return "Lunes"
        case 2: return "Martes"
        case 3: return "Miércoles"
        case 4: return "Jueves"
        case 5: return "Viernes"
        default: return "Sesión"
        }
    }

    private func fallback(_ value: String, empty placeholder: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? placeholder : value
    }

    private var diaryLocalToolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Semana \(vm.week), \(vm.year)")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                    Text(vm.dateRangeLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await vm.previousWeek() }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await vm.nextWeek() }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Buscar sesión, unidad o grupo…", text: $vm.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 8) {
                Picker("Estado", selection: $selectedFilter) {
                    ForEach(DiaryStatusFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.menu)

                Picker("Día", selection: $selectedDayFilter) {
                    ForEach(availableDays, id: \.self) { day in
                        Text(day).tag(day)
                    }
                }
                .pickerStyle(.menu)

                Picker("Unidad", selection: $selectedUnitFilter) {
                    ForEach(availableUnits, id: \.self) { unit in
                        Text(unit).tag(unit)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 10) {
                WorkspaceCompactStat(title: "Sesiones", value: "\(diaryMetrics.total)", tint: .blue)
                WorkspaceCompactStat(title: "Pendientes", value: "\(diaryMetrics.pending)", tint: .orange)
                WorkspaceCompactStat(title: "Incidencias", value: "\(diaryMetrics.incidents)", tint: .pink)
            }
        }
        .padding(16)
    }

    @MainActor
    private func syncSelection() {
        if !availableUnits.contains(selectedUnitFilter) {
            selectedUnitFilter = "Todas"
        }

        guard !diarySessions.isEmpty else { return }
        if let current = selectedSession, diarySessions.contains(where: { $0.id == current.id }) {
            return
        }

        if let first = diarySessions.first {
            Task { await vm.select(session: first) }
        }
    }

    private func configureDiaryToolbar() {
        layoutState.configureDiaryToolbar(
            inspectorAvailable: selectedSession != nil,
            isInspectorPresented: showingInspector,
            onToggleInspector: {
                showingInspector.toggle()
            }
        )
    }

    private func syncNavigationContext() {
        onNavigationContextChange(currentNavigationContext)
    }
}

private enum DiaryStatusFilter: String, CaseIterable, Identifiable {
    case all
    case drafts
    case completed
    case incomplete
    case incidents
    case empty

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Todos"
        case .drafts: return "Borradores"
        case .completed: return "Completadas"
        case .incomplete: return "Incompletas"
        case .incidents: return "Con incidencias"
        case .empty: return "Sin diario"
        }
    }
}

private struct DiarySessionRailCard: View {
    let session: PlanningSession
    let summary: SessionJournalSummary?
    let isSelected: Bool
    let timeLabel: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            NotebookSurface(
                cornerRadius: 18,
                fill: isSelected ? NotebookStyle.surface : NotebookStyle.surfaceSoft,
                padding: 14
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.teachingUnitName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text("\(weekdayLabel(session.dayOfWeek)) · \(timeLabel)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        NotebookPill(
                            label: diaryStatusText(summary),
                            systemImage: "doc.text",
                            active: isSelected,
                            tint: badgeTint
                        )
                    }

                    Text(session.groupName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if !(summary?.incidentTags.isEmpty ?? true) {
                        Text(summary?.incidentTags.prefix(2).joined(separator: " · ") ?? "")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.pink)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? EvaluationDesign.accent.opacity(0.28) : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var badgeTint: Color {
        switch summary?.status ?? .empty {
        case .completed: return EvaluationDesign.success
        case .draft: return EvaluationDesign.accent
        default: return .secondary
        }
    }

    private func diaryStatusText(_ summary: SessionJournalSummary?) -> String {
        guard let summary else { return "Sin diario" }
        if !(summary.incidentTags.isEmpty) {
            return "\(summary.status.name.capitalized) · alerta"
        }
        return summary.status.name.capitalized
    }

    private func weekdayLabel(_ dayOfWeek: Int32) -> String {
        switch Int(dayOfWeek) {
        case 1: return "Lunes"
        case 2: return "Martes"
        case 3: return "Miércoles"
        case 4: return "Jueves"
        case 5: return "Viernes"
        default: return "Sesión"
        }
    }
}

private struct DiaryInspectorPanel: View {
    let session: PlanningSession
    let summary: SessionJournalSummary?
    let timeLabel: String
    let onOpenAttendance: () -> Void
    let onOpenNotebook: () -> Void
    let onOpenStudents: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WorkspaceInspectorHero(
                    title: session.teachingUnitName,
                    subtitle: "\(session.groupName) · \(weekdayLabel(session.dayOfWeek)) · \(timeLabel)"
                )

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    WorkspaceMetricCard(
                        title: "Estado",
                        value: summary?.status.name.capitalized ?? "Sin diario",
                        systemImage: "doc.text"
                    )
                    WorkspaceMetricCard(
                        title: "Clima",
                        value: summary.map { "\($0.climateScore)/5" } ?? "-",
                        systemImage: "sun.max.fill"
                    )
                    WorkspaceMetricCard(
                        title: "Participación",
                        value: summary.map { "\($0.participationScore)/5" } ?? "-",
                        systemImage: "person.3.sequence.fill"
                    )
                    WorkspaceMetricCard(
                        title: "Adjuntos",
                        value: summary.map { "\($0.mediaCount)" } ?? "0",
                        systemImage: "paperclip"
                    )
                }

                WorkspaceDetailBlock(title: "Objetivos", content: fallback(session.objectives, empty: "Sin objetivos definidos"))
                WorkspaceDetailBlock(title: "Actividades", content: fallback(session.activities, empty: "Sin actividades descritas"))
                WorkspaceDetailBlock(title: "Evaluación", content: fallback(session.evaluation, empty: "Sin observaciones evaluativas"))

                if let summary, !summary.incidentTags.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Incidencias")
                            .font(.headline)
                        FlowLayout(spacing: 8) {
                            ForEach(Array(summary.incidentTags.enumerated()), id: \.offset) { _, tag in
                                WorkspaceTag(text: tag, systemImage: "exclamationmark.triangle.fill")
                            }
                        }
                    }
                }

                if let summary {
                    WorkspaceDetailBlock(
                        title: "Pulso de la sesión",
                        content: fallback(summary.weatherText, empty: "Sin observaciones contextuales")
                    )
                }

                VStack(spacing: 10) {
                    WorkspaceActionRow(title: "Ir a asistencia", systemImage: "checklist.checked", action: onOpenAttendance)
                    WorkspaceActionRow(title: "Abrir cuaderno", systemImage: "square.grid.3x3.fill", action: onOpenNotebook)
                    WorkspaceActionRow(title: "Ver alumnado", systemImage: "person.3.fill", action: onOpenStudents)
                }
            }
            .padding(20)
        }
    }

    private func weekdayLabel(_ dayOfWeek: Int32) -> String {
        switch Int(dayOfWeek) {
        case 1: return "Lunes"
        case 2: return "Martes"
        case 3: return "Miércoles"
        case 4: return "Jueves"
        case 5: return "Viernes"
        default: return "Sesión"
        }
    }

    private func fallback(_ value: String, empty placeholder: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? placeholder : value
    }
}

private struct RubricsWorkspaceView: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    let onOpenBuilder: () -> Void
    let onEditRubric: (RubricDetail) -> Void
    var peMode = false

    @State private var searchText = ""
    @State private var selectedFilter = "Todas"
    @State private var selectedRubricId: Int64?
    @State private var usageSummary: KmpBridge.RubricUsageSnapshot?

    private var availableFilters: [String] {
        ["Todas", "Vinculadas", "Sin vincular", "Multiclase"]
    }

    private var baseRubrics: [RubricDetail] {
        let source = bridge.rubrics
        guard peMode else { return source }
        return source.filter { detail in
            let haystack = "\(detail.rubric.name) \(detail.rubric.description_ ?? "")".lowercased()
            return haystack.contains("ef")
                || haystack.contains("educación física")
                || (bridge.rubricClassLinks[detail.rubric.id]?.contains(selectedClassId ?? -1) ?? false)
        }
    }

    private var filteredRubrics: [RubricDetail] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return baseRubrics.filter { detail in
            let linkedClasses = bridge.rubricClassLinks[detail.rubric.id] ?? []
            let matchesFilter: Bool = {
                switch selectedFilter {
                case "Vinculadas":
                    return !linkedClasses.isEmpty
                case "Sin vincular":
                    return linkedClasses.isEmpty
                case "Multiclase":
                    return linkedClasses.count > 1
                default:
                    return true
                }
            }()

            let matchesQuery = query.isEmpty || [
                detail.rubric.name,
                detail.rubric.description_ ?? "",
                detail.criteria.map { sanitizeDomainText($0.criterion.description, fallback: "criterio") }.joined(separator: " ")
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)

            return matchesFilter && matchesQuery
        }
        .sorted { $0.rubric.name.localizedCaseInsensitiveCompare($1.rubric.name) == .orderedAscending }
    }

    private var selectedRubric: RubricDetail? {
        filteredRubrics.first(where: { $0.rubric.id == selectedRubricId }) ?? baseRubrics.first(where: { $0.rubric.id == selectedRubricId })
    }

    private var rubricMetrics: (total: Int, linked: Int, avgCriteria: Double) {
        let total = filteredRubrics.count
        let linked = filteredRubrics.filter { !(bridge.rubricClassLinks[$0.rubric.id] ?? []).isEmpty }.count
        let avg = filteredRubrics.isEmpty ? 0 : Double(filteredRubrics.map { $0.criteria.count }.reduce(0, +)) / Double(filteredRubrics.count)
        return (total, linked, avg)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Buscar rúbrica, criterio o descripción…", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    HStack(spacing: 10) {
                        Picker("Filtro", selection: $selectedFilter) {
                            ForEach(availableFilters, id: \.self) { filter in
                                Text(filter).tag(filter)
                            }
                        }
                        .pickerStyle(.menu)

                        Spacer()

                        Button {
                            onOpenBuilder()
                        } label: {
                            Label("Nueva rúbrica", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    HStack(spacing: 10) {
                        WorkspaceCompactStat(title: "Total", value: "\(rubricMetrics.total)", tint: .blue)
                        WorkspaceCompactStat(title: "Vinculadas", value: "\(rubricMetrics.linked)", tint: .green)
                        WorkspaceCompactStat(title: "Criterios", value: String(format: "%.1f", rubricMetrics.avgCriteria), tint: .orange)
                    }
                }
                .padding(16)

                List(filteredRubrics, id: \.rubric.id) { rubric in
                    Button {
                        selectedRubricId = rubric.rubric.id
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(rubric.rubric.name)
                                .font(.headline)
                            Text("\(rubric.criteria.count) criterios · \((bridge.rubricClassLinks[rubric.rubric.id] ?? []).count) clases")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 320, maxWidth: 380)

            Divider().opacity(0.2)

            Group {
                if let rubric = selectedRubric {
                    let presentation = rubricPresentation(rubric)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            WorkspaceInspectorHero(
                                title: presentation.title,
                                subtitle: presentation.subtitle
                            )

                            let linkedClasses = bridge.rubricClassLinks[rubric.rubric.id] ?? []
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                                WorkspaceMetricCard(title: "Criterios", value: "\(rubric.criteria.count)", systemImage: "list.bullet.rectangle")
                                WorkspaceMetricCard(
                                    title: "Niveles",
                                    value: "\(rubric.criteria.map { $0.levels.count }.max() ?? 0)",
                                    systemImage: "chart.bar.xaxis"
                                )
                                WorkspaceMetricCard(title: "Clases", value: "\(linkedClasses.count)", systemImage: "rectangle.3.group")
                                WorkspaceMetricCard(
                                    title: "Evaluaciones",
                                    value: "\(usageSummary?.evaluationCount ?? 0)",
                                    systemImage: "chart.bar.doc.horizontal"
                                )
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Criterios y niveles")
                                    .font(.headline)
                                ForEach(presentation.criteria) { item in
                                    rubricCriterionCard(item)
                                }
                            }

                            if !linkedClasses.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Uso en clases")
                                        .font(.headline)
                                    FlowLayout(spacing: 10) {
                                        ForEach(Array(linkedClasses).sorted(), id: \.self) { classId in
                                            if let schoolClass = bridge.classes.first(where: { $0.id == classId }) {
                                                WorkspaceTag(text: schoolClass.name, systemImage: "rectangle.3.group")
                                            }
                                        }
                                    }
                                }
                            }

                            if let usageSummary, !usageSummary.evaluationUsages.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Impacto evaluativo")
                                        .font(.headline)
                                    WorkspaceDetailBlock(
                                        title: "Resumen",
                                        content: "Esta rúbrica está vinculada a \(usageSummary.evaluationCount) evaluación(es) en \(usageSummary.classCount) clase(s)."
                                    )
                                    ForEach(Array(usageSummary.evaluationUsages.prefix(6))) { usage in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(usage.evaluationName)
                                                .font(.subheadline.weight(.bold))
                                            Text("\(usage.className) · \(usage.evaluationType) · Peso \(String(format: "%.1f", usage.weight))")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(12)
                                        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    }
                                }
                            } else {
                                WorkspaceDetailBlock(
                                    title: "Impacto evaluativo",
                                    content: "Todavía no hay evaluaciones activas enlazadas a esta rúbrica."
                                )
                            }

                            HStack(spacing: 12) {
                                Button("Asignar a clase") {
                                    bridge.startAssignRubric(rubric.rubric)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Editar") {
                                    onEditRubric(rubric)
                                }
                                .buttonStyle(.bordered)

                                Button("Ir a evaluación") {
                                    onOpenModule(.evaluationHub, selectedClassId, nil)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(24)
                    }
                } else {
                    VStack(spacing: 18) {
                        WorkspaceEmptyState(
                            title: peMode ? "Selecciona una rúbrica EF" : "Selecciona una rúbrica",
                            subtitle: peMode
                                ? "Crea o reutiliza rúbricas EF para seguridad, ejecución, cooperación y fair play."
                                : "El banco de rúbricas centraliza criterios, clases vinculadas y acceso directo a evaluación."
                        )
                        HStack(spacing: 12) {
                            Button(peMode ? "Nueva rúbrica EF" : "Nueva rúbrica") {
                                onOpenBuilder()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Ver uso evaluativo") {
                                onOpenModule(.evaluationHub, selectedClassId, nil)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appPageBackground(for: colorScheme))
        }
        .task {
            if selectedRubricId == nil {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            await reloadUsageSummary()
        }
        .onChange(of: selectedClassId) { _ in
            if selectedRubricId == nil || !filteredRubrics.contains(where: { $0.rubric.id == selectedRubricId }) {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            Task { await reloadUsageSummary() }
        }
        .onChange(of: selectedFilter) { _ in
            if selectedRubricId == nil || !filteredRubrics.contains(where: { $0.rubric.id == selectedRubricId }) {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            Task { await reloadUsageSummary() }
        }
        .onChange(of: searchText) { _ in
            if selectedRubricId == nil || !filteredRubrics.contains(where: { $0.rubric.id == selectedRubricId }) {
                selectedRubricId = filteredRubrics.first?.rubric.id
            }
            Task { await reloadUsageSummary() }
        }
        .onChange(of: selectedRubricId) { _ in
            Task { await reloadUsageSummary() }
        }
    }

    private func rubricCriterionCard(_ item: RubricInspectorModel.CriterionModel) -> some View {
        let background = appCardBackground(for: colorScheme)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.title)
                    .font(.subheadline.weight(.bold))
                Spacer()
                WorkspaceTag(text: "Peso \(item.weightText)", systemImage: "scalemass")
            }
            FlowLayout(spacing: 8) {
                ForEach(item.levels, id: \.self) { level in
                    WorkspaceTag(text: level, systemImage: "checkmark.circle")
                }
            }
        }
        .padding(12)
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func fallback(_ value: String, empty placeholder: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? placeholder : value
    }

    @MainActor
    private func reloadUsageSummary() async {
        guard let rubricId = selectedRubric?.rubric.id else {
            usageSummary = nil
            return
        }
        usageSummary = try? await bridge.loadRubricUsage(rubricId: rubricId)
    }
}

private struct ReportsWorkspaceView: View {
    private enum ReportTerm: String, CaseIterable, Identifiable {
        case first = "1er Trimestre"
        case second = "2º Trimestre"
        case third = "3er Trimestre"

        var id: String { rawValue }
    }

    private enum WorkspaceSurface: String, CaseIterable, Identifiable {
        case reports
        case analytics

        var id: String { rawValue }
    }

    private enum AnalyticsMode: String, CaseIterable, Identifiable {
        case dashboards
        case askAI

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dashboards: return "Dashboards"
            case .askAI: return "Pregunta a la IA"
            }
        }
    }

    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?

    @State private var activeSurface: WorkspaceSurface = .reports
    @State private var preview: KmpBridge.ReportPreviewPayload?
    @State private var reportContext: KmpBridge.ReportGenerationContext?
    @State private var selectedReportKind: KmpBridge.ReportKind = .groupOverview
    @State private var selectedReportTerm: ReportTerm = .first
    @State private var aiAudience: AIReportAudience = .docente
    @State private var aiTone: AIReportTone = .claro
    @State private var aiAvailability: AIReportAvailabilityState = .unavailable("Comprobando disponibilidad…")
    @State private var aiDraft: AIReportDraft?
    @State private var editableDraftText = ""
    @State private var aiFeedbackMessage: String?
    @State private var isGeneratingAIDraft = false

    @State private var analyticsMode: AnalyticsMode = .dashboards
    @State private var analyticsAvailability: AIAnalyticsAvailabilityState = .unavailable("Comprobando disponibilidad…")
    @State private var selectedAnalyticsRange: KmpBridge.AnalyticsTimeRange = .last30Days
    @State private var selectedChartKind: KmpBridge.ChartKind = .attendanceTrend
    @State private var analyticsDashboards: [KmpBridge.ChartFacts] = []
    @State private var queriedAnalyticsFacts: KmpBridge.ChartFacts?
    @State private var analyticsInsight: AIChartInsight?
    @State private var analyticsPrompt = ""
    @State private var analyticsFeedbackMessage: String?
    @State private var isGeneratingAnalyticsInsight = false
    @State private var isResolvingAnalyticsPrompt = false

    private let aiReportService = AppleFoundationReportService()
    private let aiAnalyticsService = AppleFoundationAnalyticsService()

    private var selectedClass: SchoolClass? {
        guard let selectedClassId else { return nil }
        return bridge.classes.first(where: { $0.id == selectedClassId })
    }

    private var selectedStudent: Student? {
        guard let selectedStudentId else { return nil }
        let source = bridge.studentsInClass.isEmpty ? bridge.allStudents : bridge.studentsInClass
        return source.first(where: { $0.id == selectedStudentId })
    }

    private var reportMetrics: (students: Int, evaluations: Int, rubrics: Int) {
        let studentCount = bridge.studentsInClass.count
        let evaluations = bridge.evaluationsInClass.count
        let rubricIds = Set(bridge.evaluationsInClass.compactMap { $0.rubricId?.int64Value })
        return (studentCount, evaluations, rubricIds.count)
    }

    private var shareableReportText: String {
        let trimmedDraft = editableDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDraft.isEmpty {
            return trimmedDraft
        }
        return preview?.previewText ?? "Sin informe disponible."
    }

    private var canGenerateAIDraft: Bool {
        guard !isGeneratingAIDraft else { return false }
        guard aiAvailability.isAvailable else { return false }
        guard let reportContext, reportContext.hasEnoughData else { return false }
        return !selectedReportKind.requiresStudentSelection || selectedStudent != nil
    }

    private var currentAnalyticsFacts: KmpBridge.ChartFacts? {
        if analyticsMode == .askAI, let queriedAnalyticsFacts {
            return queriedAnalyticsFacts
        }
        return analyticsDashboards.first(where: { $0.chartKind == selectedChartKind })
    }

    private var canAskAnalyticsAI: Bool {
        analyticsAvailability.isAvailable && !(analyticsPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider().opacity(0.2)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(appPageBackground(for: colorScheme))
        }
        .task {
            refreshAvailability()
            await refreshWorkspaceContext()
        }
        .onChange(of: selectedClassId) { _ in
            Task { await refreshWorkspaceContext() }
        }
        .onChange(of: selectedStudentId) { _ in
            Task { await reloadPreview() }
        }
        .onChange(of: selectedReportKind) { _ in
            if selectedReportKind == .lomloeEvaluationComment {
                aiAudience = .familia
                aiTone = .formal
            }
            Task { await reloadPreview() }
        }
        .onChange(of: selectedReportTerm) { _ in
            Task { await reloadPreview() }
        }
        .onChange(of: selectedAnalyticsRange) { _ in
            Task { await reloadAnalyticsDashboards() }
        }
        .onChange(of: analyticsMode) { _ in
            analyticsInsight = nil
            analyticsFeedbackMessage = nil
        }
        .onChange(of: selectedChartKind) { _ in
            analyticsInsight = nil
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Superficie", selection: $activeSurface) {
                    Text("Informes").tag(WorkspaceSurface.reports)
                    Text("Analítica IA").tag(WorkspaceSurface.analytics)
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    WorkspaceCompactStat(title: "Alumnado", value: "\(reportMetrics.students)", tint: .blue)
                    WorkspaceCompactStat(
                        title: activeSurface == .reports ? "Evaluaciones" : "Gráficos",
                        value: activeSurface == .reports ? "\(reportMetrics.evaluations)" : "\(analyticsDashboards.count)",
                        tint: .orange
                    )
                    WorkspaceCompactStat(
                        title: activeSurface == .reports ? "Rúbricas" : "IA",
                        value: activeSurface == .reports ? "\(reportMetrics.rubrics)" : (analyticsAvailability.isAvailable ? "On" : "Off"),
                        tint: .green
                    )
                }
            }
            .padding(16)

            List {
                if activeSurface == .reports {
                    reportsSidebarSections
                } else {
                    analyticsSidebarSections
                }
            }
            .listStyle(.plain)
        }
        .frame(minWidth: 320, maxWidth: 360)
    }

    @ViewBuilder
    private var reportsSidebarSections: some View {
        Section("Informes disponibles") {
            ForEach(KmpBridge.ReportKind.allCases) { kind in
                reportButton(kind: kind)
            }
        }

        Section("Contexto actual") {
            currentContextSection
        }

        Section("Redacción IA") {
            LabeledContent("Estado") {
                Text(aiAvailabilityLabel)
                    .foregroundStyle(aiAvailabilityColor)
            }

            if selectedReportKind == .lomloeEvaluationComment {
                Picker("Trimestre", selection: $selectedReportTerm) {
                    ForEach(ReportTerm.allCases) { term in
                        Text(term.rawValue).tag(term)
                    }
                }
            }

            Picker("Audiencia", selection: $aiAudience) {
                ForEach(AIReportAudience.allCases) { audience in
                    Text(audience.title).tag(audience)
                }
            }

            Picker("Tono", selection: $aiTone) {
                ForEach(AIReportTone.allCases) { tone in
                    Text(tone.title).tag(tone)
                }
            }

            if let reportContext {
                LabeledContent("Datos") {
                    Text(reportContext.hasEnoughData ? "Suficientes" : "Insuficientes")
                        .foregroundStyle(reportContext.hasEnoughData ? .green : .secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var analyticsSidebarSections: some View {
        Section("Analítica visual") {
            Picker("Modo", selection: $analyticsMode) {
                ForEach(AnalyticsMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker("Periodo", selection: $selectedAnalyticsRange) {
                ForEach(KmpBridge.AnalyticsTimeRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
        }

        Section("Contexto actual") {
            currentContextSection
        }

        Section("Dashboards") {
            ForEach(KmpBridge.ChartKind.allCases) { kind in
                Button {
                    analyticsMode = .dashboards
                    selectedChartKind = kind
                    analyticsInsight = nil
                    queriedAnalyticsFacts = nil
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(kind.title, systemImage: kind.systemImage)
                                .font(.headline)
                            Spacer()
                            if selectedChartKind == kind && analyticsMode == .dashboards {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        Text(kind.subtitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }

        Section("IA local") {
            LabeledContent("Estado") {
                Text(analyticsAvailabilityLabel)
                    .foregroundStyle(analyticsAvailabilityColor)
            }
            Text(analyticsAvailability.message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var currentContextSection: some View {
        if let selectedClass {
            LabeledContent("Clase") {
                Text(selectedClass.name)
            }
        } else {
            Text("Selecciona una clase para trabajar con informes o analítica.")
                .foregroundStyle(.secondary)
        }

        if let selectedStudent {
            LabeledContent("Alumno") {
                Text("\(selectedStudent.firstName) \(selectedStudent.lastName)")
            }
        } else {
            LabeledContent("Alumno") {
                Text("Sin selección")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detail: AnyView {
        if activeSurface == .reports {
            return AnyView(reportsDetail)
        } else {
            return AnyView(analyticsDetail)
        }
    }

    @ViewBuilder
    private var reportsDetail: some View {
        if let preview {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    WorkspaceInspectorHero(title: selectedReportKind.title, subtitle: preview.className)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                        WorkspaceMetricCard(title: "Tipo", value: selectedReportKind.title, systemImage: selectedReportKind.systemImage)
                        WorkspaceMetricCard(
                            title: "Generado",
                            value: preview.generatedAt.formatted(date: .abbreviated, time: .shortened),
                            systemImage: "clock.badge.checkmark"
                        )
                        WorkspaceMetricCard(
                            title: "Destino",
                            value: selectedStudent.map { "\($0.firstName) \($0.lastName)" } ?? preview.className,
                            systemImage: selectedStudent == nil ? "rectangle.3.group" : "person.fill"
                        )
                        ForEach(reportContext?.metrics ?? []) { metric in
                            WorkspaceMetricCard(title: metric.title, value: metric.value, systemImage: metric.systemImage)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Parámetros")
                            .font(.headline)
                        WorkspaceDetailBlock(title: "Descripción", content: selectedReportKind.subtitle)
                        WorkspaceDetailBlock(title: "Contexto", content: reportContextDescription)
                        if let reportContext, !reportContext.curriculumReferences.isEmpty {
                            WorkspaceDetailBlock(title: "Referencias curriculares", content: reportContext.curriculumReferences.joined(separator: ", "))
                        }
                        if let dataQualityNote = reportContext?.dataQualityNote {
                            WorkspaceDetailBlock(title: "Calidad de datos", content: dataQualityNote)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Redacción IA")
                                    .font(.headline)
                                Text("Borrador generado en local. Revisión docente obligatoria antes de compartir.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task { await generateAIDraft() }
                            } label: {
                                if isGeneratingAIDraft {
                                    ProgressView()
                                } else {
                                    Label("Generar borrador", systemImage: "apple.intelligence")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canGenerateAIDraft)
                        }

                        WorkspaceDetailBlock(title: "Disponibilidad", content: aiAvailability.message)

                        if let aiFeedbackMessage {
                            WorkspaceDetailBlock(title: "Estado de la generación", content: aiFeedbackMessage)
                        }

                        if let aiDraft {
                            WorkspaceDetailBlock(title: "Resumen IA", content: aiDraft.summary)
                        } else if selectedReportKind.requiresStudentSelection && selectedStudent == nil {
                            WorkspaceDetailBlock(title: "IA pendiente", content: "Selecciona un alumno para generar un borrador individual con Foundation Models.")
                        } else {
                            WorkspaceDetailBlock(title: "IA pendiente", content: "Configura audiencia y tono, luego genera un borrador editable.")
                        }

                        TextEditor(text: $editableDraftText)
                            .font(.system(.body, design: .default))
                            .frame(minHeight: 260)
                            .padding(12)
                            .scrollContentBackground(.hidden)
                            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    ShareLink(item: shareableReportText) {
                        Label("Compartir informe revisado", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Vista clásica")
                            .font(.headline)
                        Text(preview.previewText)
                            .font(.system(.body, design: .monospaced))
                            .padding(18)
                            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .padding(24)
            }
        } else {
            WorkspaceEmptyState(
                title: "Genera una vista previa",
                subtitle: "El módulo de informes reutiliza el `ReportService` y lo eleva a una superficie iPad propia."
            )
        }
    }

    @ViewBuilder
    private var analyticsDetail: some View {
        if selectedClassId == nil {
            WorkspaceEmptyState(
                title: "Selecciona una clase",
                subtitle: "La analítica visual necesita un grupo activo para comparar asistencia, incidencias y medias."
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            WorkspaceInspectorHero(
                                title: analyticsMode == .dashboards ? "Dashboards" : "Pregunta a la IA",
                                subtitle: selectedClass?.name ?? "Sin clase"
                            )
                            Text("La app calcula y dibuja los gráficos; la IA local los interpreta y ayuda a elegir la vista cuando está disponible.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let facts = currentAnalyticsFacts {
                            Button {
                                Task { await generateAnalyticsInsight(for: facts) }
                            } label: {
                                if isGeneratingAnalyticsInsight {
                                    ProgressView()
                                } else {
                                    Label("Generar insight IA", systemImage: "apple.intelligence")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!analyticsAvailability.isAvailable || !facts.hasEnoughData || isGeneratingAnalyticsInsight)
                        }
                    }

                    if analyticsMode == .askAI {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Consulta libre")
                                .font(.headline)
                            TextField("Ej.: compárame 2º ESO A y B en asistencia y faltas de equipación este trimestre", text: $analyticsPrompt, axis: .vertical)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .lineLimit(3, reservesSpace: true)

                            HStack(spacing: 10) {
                                ForEach([
                                    "Comparar grupos del mismo curso",
                                    "Detectar alertas de asistencia",
                                    "Ver incidencias por semana",
                                    "Ranking de medias"
                                ], id: \.self) { suggestion in
                                    Button(suggestion) {
                                        analyticsPrompt = suggestion
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            HStack {
                                Button {
                                    Task { await runAnalyticsQuery() }
                                } label: {
                                    if isResolvingAnalyticsPrompt {
                                        ProgressView()
                                    } else {
                                        Label("Generar gráfico", systemImage: "wand.and.stars")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!canAskAnalyticsAI || isResolvingAnalyticsPrompt)

                                Text(analyticsAvailability.message)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(18)
                        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    if let facts = currentAnalyticsFacts {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                            WorkspaceMetricCard(title: "Gráfico", value: facts.chartKind.title, systemImage: facts.chartKind.systemImage)
                            WorkspaceMetricCard(title: "Tipo", value: facts.chartType, systemImage: "chart.bar.fill")
                            WorkspaceMetricCard(title: "Periodo", value: facts.timeRange, systemImage: "calendar")
                            WorkspaceMetricCard(title: "Agrupación", value: facts.grouping, systemImage: "square.grid.2x2")
                            ForEach(facts.metrics) { metric in
                                WorkspaceMetricCard(title: metric.title, value: metric.value, systemImage: metric.systemImage)
                            }
                        }

                        AnalyticsChartPanel(facts: facts, colorScheme: colorScheme)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Lectura docente")
                                .font(.headline)
                            WorkspaceDetailBlock(title: "Resumen base", content: facts.teacherDigest)
                            if let analyticsInsight {
                                WorkspaceDetailBlock(title: analyticsInsight.title, content: analyticsInsight.insight)
                                if !analyticsInsight.warnings.isEmpty {
                                    WorkspaceDetailBlock(title: "Advertencias IA", content: analyticsInsight.warnings.joined(separator: "\n"))
                                }
                                if !analyticsInsight.recommendedActions.isEmpty {
                                    WorkspaceDetailBlock(title: "Acciones sugeridas", content: analyticsInsight.recommendedActions.joined(separator: "\n"))
                                }
                            } else {
                                WorkspaceDetailBlock(title: "Insight IA", content: analyticsAvailability.isAvailable ? "Genera un insight para obtener lectura comparativa y sugerencias." : "La consulta libre y la narrativa IA solo están disponibles cuando Apple Foundation Models está activo.")
                            }
                            if let analyticsFeedbackMessage {
                                WorkspaceDetailBlock(title: "Estado", content: analyticsFeedbackMessage)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Hechos verificables")
                                .font(.headline)
                            ForEach(facts.factLines, id: \.self) { line in
                                Text("• \(line)")
                                    .font(.subheadline)
                            }
                            if !facts.warnings.isEmpty {
                                ForEach(facts.warnings, id: \.self) { warning in
                                    Text("• \(warning)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(18)
                        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                        ShareLink(item: analyticsInsight?.insertableSummary ?? facts.insertableSummary) {
                            Label("Compartir resumen visual", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        WorkspaceEmptyState(
                            title: analyticsMode == .dashboards ? "Selecciona un dashboard" : "Formula una pregunta",
                            subtitle: analyticsMode == .dashboards ? "Elige una vista de la barra lateral para comparar grupos y detectar patrones." : "La IA local elegirá el gráfico más útil y luego te devolverá una lectura breve."
                        )
                    }
                }
                .padding(24)
            }
        }
    }

    private var reportContextDescription: String {
        switch selectedReportKind {
        case .groupOverview:
            return "Resumen por grupo con foco en medias del alumnado y consistencia general del cuaderno."
        case .studentSummary:
            if let selectedStudent {
                return "Resumen individual centrado en \(selectedStudent.firstName) \(selectedStudent.lastName) para revisión o tutoría."
            }
            return "Selecciona un alumno para obtener un informe individual con más sentido pedagógico."
        case .evaluationDigest:
            return "Panorámica de instrumentos activos, rúbricas vinculadas y carga evaluativa del grupo."
        case .operationsSnapshot:
            return "Salida operativa para asistencia, incidencias y estado del trabajo reciente."
        case .lomloeEvaluationComment:
            return "Comentario trimestral breve y competencial de Educación Física, alineado con CE1-CE5 y listo para informe."
        }
    }

    private var aiAvailabilityLabel: String {
        switch aiAvailability {
        case .available: return "Disponible"
        case .disabled: return "Desactivada"
        case .unavailable: return "No disponible"
        }
    }

    private var aiAvailabilityColor: Color {
        switch aiAvailability {
        case .available: return .green
        case .disabled: return .secondary
        case .unavailable: return .orange
        }
    }

    private var analyticsAvailabilityLabel: String {
        switch analyticsAvailability {
        case .available: return "Disponible"
        case .disabled: return "Desactivada"
        case .unavailable: return "No disponible"
        }
    }

    private var analyticsAvailabilityColor: Color {
        switch analyticsAvailability {
        case .available: return .green
        case .disabled: return .secondary
        case .unavailable: return .orange
        }
    }

    private func reportButton(kind: KmpBridge.ReportKind) -> some View {
        Button {
            selectedReportKind = kind
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(kind.title, systemImage: kind.systemImage)
                        .font(.headline)
                    Spacer()
                    if selectedReportKind == kind {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(kind.subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func refreshWorkspaceContext() async {
        guard let selectedClassId else { return }
        refreshAvailability()
        bridge.selectClass(id: selectedClassId)
        bridge.evaluationsInClass = (try? await bridge.evaluations(for: selectedClassId)) ?? []
        await bridge.selectStudentsClass(classId: selectedClassId)
        await reloadPreview()
        await reloadAnalyticsDashboards()
    }

    @MainActor
    private func reloadPreview() async {
        guard let selectedClassId else { return }
        aiDraft = nil
        editableDraftText = ""
        aiFeedbackMessage = nil

        guard let context = try? await bridge.buildReportGenerationContext(
            classId: selectedClassId,
            studentId: selectedStudentId,
            kind: selectedReportKind,
            termLabel: selectedReportKind == .lomloeEvaluationComment ? selectedReportTerm.rawValue : nil
        ) else {
            reportContext = nil
            preview = nil
            return
        }
        reportContext = context
        let basePreview = try? await bridge.buildReportPreview(
            classId: selectedClassId,
            studentId: selectedStudentId,
            kind: selectedReportKind,
            termLabel: selectedReportKind == .lomloeEvaluationComment ? selectedReportTerm.rawValue : nil
        )
        guard let basePreview else {
            preview = nil
            return
        }

        let decoratedText = """
        \(selectedReportKind.title)
        \(selectedClass?.name ?? basePreview.className)
        \(selectedStudent.map { "Alumno: \($0.firstName) \($0.lastName)" } ?? "Ámbito: grupo completo")

        \(reportContextDescription)

        \(context.summary)

        \(basePreview.previewText)
        """

        preview = KmpBridge.ReportPreviewPayload(
            classId: basePreview.classId,
            className: basePreview.className,
            previewText: decoratedText,
            generatedAt: Date()
        )
    }

    @MainActor
    private func reloadAnalyticsDashboards() async {
        guard let selectedClassId else { return }
        analyticsFeedbackMessage = nil
        analyticsInsight = nil
        queriedAnalyticsFacts = nil
        analyticsDashboards = (try? await bridge.buildPrebuiltAnalyticsCharts(
            classId: selectedClassId,
            timeRange: selectedAnalyticsRange
        )) ?? []
        if !analyticsDashboards.contains(where: { $0.chartKind == selectedChartKind }) {
            selectedChartKind = analyticsDashboards.first?.chartKind ?? .attendanceTrend
        }
    }

    @MainActor
    private func generateAIDraft() async {
        guard let reportContext else { return }
        isGeneratingAIDraft = true
        aiFeedbackMessage = nil
        defer { isGeneratingAIDraft = false }

        do {
            let draft = try await aiReportService.generateDraft(
                from: reportContext,
                audience: aiAudience,
                tone: aiTone
            )
            aiDraft = draft
            editableDraftText = draft.editableText(for: reportContext)
            aiFeedbackMessage = "Borrador generado. Revísalo y edítalo antes de compartir."
        } catch {
            aiFeedbackMessage = error.localizedDescription
        }
    }

    @MainActor
    private func generateAnalyticsInsight(for facts: KmpBridge.ChartFacts) async {
        isGeneratingAnalyticsInsight = true
        analyticsFeedbackMessage = nil
        defer { isGeneratingAnalyticsInsight = false }

        do {
            analyticsInsight = try await aiAnalyticsService.generateInsight(from: facts)
            analyticsFeedbackMessage = "Insight generado en local. Revísalo antes de compartirlo o insertarlo en un informe."
        } catch {
            analyticsFeedbackMessage = error.localizedDescription
        }
    }

    @MainActor
    private func runAnalyticsQuery() async {
        guard let selectedClassId else { return }
        isResolvingAnalyticsPrompt = true
        analyticsFeedbackMessage = nil
        analyticsInsight = nil
        defer { isResolvingAnalyticsPrompt = false }

        do {
            let fallbackRequest = try await bridge.resolveAnalyticsRequest(
                classId: selectedClassId,
                prompt: analyticsPrompt,
                timeRange: selectedAnalyticsRange
            )
            let interpreted: AIAnalyticsInterpretation?
            if analyticsAvailability.isAvailable {
                interpreted = try? await aiAnalyticsService.interpret(
                    prompt: analyticsPrompt,
                    availableCharts: KmpBridge.ChartKind.allCases
                )
            } else {
                interpreted = nil
            }

            let request = KmpBridge.AnalyticsRequest(
                chartKind: interpreted?.chartKind ?? fallbackRequest.chartKind,
                timeRange: fallbackRequest.timeRange,
                selectedClassIds: fallbackRequest.selectedClassIds,
                selectedClassNames: fallbackRequest.selectedClassNames,
                prompt: fallbackRequest.prompt,
                querySummary: interpreted?.querySummary ?? fallbackRequest.querySummary
            )
            let facts = try await bridge.buildChartFacts(classId: selectedClassId, request: request)
            queriedAnalyticsFacts = facts
            selectedChartKind = facts.chartKind
            analyticsFeedbackMessage = ([interpreted?.querySummary] + (interpreted?.warnings ?? [])).compactMap { $0 }.joined(separator: "\n")

            if analyticsAvailability.isAvailable && facts.hasEnoughData {
                analyticsInsight = try? await aiAnalyticsService.generateInsight(from: facts)
            }
        } catch {
            analyticsFeedbackMessage = error.localizedDescription
        }
    }

    private func refreshAvailability() {
        aiAvailability = aiReportService.currentAvailability()
        analyticsAvailability = aiAnalyticsService.currentAvailability()
    }
}

private struct AnalyticsChartPanel: View {
    let facts: KmpBridge.ChartFacts
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(facts.chartKind.title)
                        .font(.headline)
                    Text(facts.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(facts.chartType)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }

            if !facts.hasEnoughData {
                WorkspaceDetailBlock(title: "Sin datos suficientes", content: facts.emptyStateMessage ?? "Todavía no hay datos suficientes para construir el gráfico.")
            } else if facts.chartKind == .incidentHeatmap {
                AnalyticsHeatmapView(cells: facts.heatmapCells)
                    .frame(minHeight: 220)
            } else if facts.chartKind == .attendanceTrend {
                AnalyticsLineChartView(series: facts.series.first)
                    .frame(height: 220)
            } else if facts.chartKind == .groupAveragesRanking {
                AnalyticsHorizontalBarsView(series: facts.series.first)
            } else {
                AnalyticsGroupedBarsView(series: facts.series)
            }
        }
        .padding(20)
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct AnalyticsLineChartView: View {
    let series: KmpBridge.ChartSeries?

    var body: some View {
        GeometryReader { geometry in
            let points = series?.points ?? []
            let maxValue = max(points.map(\.value).max() ?? 1, 1)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor.opacity(0.05))

                if points.count > 1 {
                    Path { path in
                        for (index, point) in points.enumerated() {
                            let x = CGFloat(index) / CGFloat(max(points.count - 1, 1)) * geometry.size.width
                            let y = geometry.size.height - (CGFloat(point.value) / CGFloat(maxValue)) * geometry.size.height
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineJoin: .round))

                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        let x = CGFloat(index) / CGFloat(max(points.count - 1, 1)) * geometry.size.width
                        let y = geometry.size.height - (CGFloat(point.value) / CGFloat(maxValue)) * geometry.size.height
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 10, height: 10)
                            .position(x: x, y: y)
                    }
                }
            }
        }
    }
}

private struct AnalyticsGroupedBarsView: View {
    let series: [KmpBridge.ChartSeries]

    private var labels: [String] {
        Array(Set(series.flatMap { $0.points.map(\.label) })).sorted()
    }

    private var maxValue: Double {
        max(series.flatMap { $0.points.map(\.value) }.max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ForEach(series) { item in
                    Label(item.name, systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(analyticsColor(item.colorToken))
                }
            }

            ForEach(labels, id: \.self) { label in
                VStack(alignment: .leading, spacing: 6) {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(series) { item in
                            let point = item.points.first(where: { $0.label == label })
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(analyticsColor(item.colorToken).gradient)
                                    .frame(width: 30, height: max(8, CGFloat((point?.value ?? 0) / maxValue) * 90))
                                Text(point.map { valueLabel(for: $0.value) } ?? "--")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 120, alignment: .bottom)
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func valueLabel(for value: Double) -> String {
        value >= 10 ? "\(Int(value.rounded()))" : IosFormatting.decimal(from: value)
    }
}

private struct AnalyticsHorizontalBarsView: View {
    let series: KmpBridge.ChartSeries?

    var body: some View {
        let points = series?.points ?? []
        let maxValue = max(points.map(\.value).max() ?? 1, 1)

        return VStack(spacing: 10) {
            ForEach(points) { point in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(point.label)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(IosFormatting.decimal(from: point.value))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule()
                                .fill(Color.accentColor.gradient)
                                .frame(width: max(16, CGFloat(point.value / maxValue) * geometry.size.width))
                        }
                    }
                    .frame(height: 12)
                }
            }
        }
    }
}

private struct AnalyticsHeatmapView: View {
    let cells: [KmpBridge.HeatmapCell]

    private var rows: [String] {
        Array(Set(cells.map(\.rowLabel))).sorted()
    }

    private var columns: [String] {
        Array(Set(cells.map(\.columnLabel))).sorted()
    }

    private var maxValue: Double {
        max(cells.map(\.value).max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer().frame(width: 44)
                ForEach(columns, id: \.self) { column in
                    Text(column)
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    Text(row)
                        .font(.caption.weight(.bold))
                        .frame(width: 44, alignment: .leading)
                    ForEach(columns, id: \.self) { column in
                        let value = cells.first(where: { $0.rowLabel == row && $0.columnLabel == column })?.value ?? 0
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.orange.opacity(0.12 + (value / maxValue) * 0.76))
                            .frame(height: 28)
                            .overlay {
                                Text("\(Int(value))")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(value > maxValue * 0.5 ? .white : .primary)
                            }
                    }
                }
            }
        }
    }
}

private func analyticsColor(_ token: String) -> Color {
    switch token {
    case "green": return .green
    case "orange": return .orange
    case "purple": return .purple
    case "blue": return .blue
    default: return .accentColor
    }
}

private struct LibraryWorkspaceView: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    @State private var templates: [ConfigTemplate] = []
    @State private var versions: [ConfigTemplateVersion] = []
    @State private var selectedTemplateId: Int64?
    @State private var selectedKindFilter = "Todas"
    @State private var searchText = ""

    private var selectedTemplate: ConfigTemplate? {
        filteredTemplates.first(where: { $0.id == selectedTemplateId }) ?? templates.first(where: { $0.id == selectedTemplateId })
    }

    private var availableKinds: [String] {
        ["Todas"] + Array(Set(templates.map { templateKindLabel($0.kind) })).sorted()
    }

    private var filteredTemplates: [ConfigTemplate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return templates.filter { template in
            let matchesKind = selectedKindFilter == "Todas" || templateKindLabel(template.kind) == selectedKindFilter
            let matchesQuery = query.isEmpty || template.name.lowercased().contains(query)
            return matchesKind && matchesQuery
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selectedTemplateVersions: [ConfigTemplateVersion] {
        versions.sorted { $0.versionNumber > $1.versionNumber }
    }

    private var templateMetrics: (total: Int, kinds: Int, versions: Int) {
        (filteredTemplates.count, max(availableKinds.count - 1, 0), versions.count)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Buscar plantilla…", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    HStack(spacing: 10) {
                        Picker("Tipo", selection: $selectedKindFilter) {
                            ForEach(availableKinds, id: \.self) { kind in
                                Text(kind).tag(kind)
                            }
                        }
                        .pickerStyle(.menu)

                        Spacer()
                    }

                    HStack(spacing: 10) {
                        WorkspaceCompactStat(title: "Activos", value: "\(templateMetrics.total)", tint: .blue)
                        WorkspaceCompactStat(title: "Tipos", value: "\(templateMetrics.kinds)", tint: .orange)
                        WorkspaceCompactStat(title: "Versiones", value: "\(templateMetrics.versions)", tint: .green)
                    }
                }
                .padding(16)

                List {
                    Section("Plantillas") {
                        ForEach(filteredTemplates, id: \.id) { template in
                            Button {
                                selectedTemplateId = template.id
                                Task { await reloadVersions(templateId: template.id) }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(template.name).font(.headline)
                                    Text(templateKindLabel(template.kind)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 320, maxWidth: 360)

            Divider().opacity(0.2)

            Group {
                if let selectedTemplate {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            WorkspaceInspectorHero(title: selectedTemplate.name, subtitle: templateKindLabel(selectedTemplate.kind))
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                                WorkspaceMetricCard(title: "Versiones", value: "\(versions.count)", systemImage: "square.stack.3d.up.fill")
                                WorkspaceMetricCard(
                                    title: "Última versión",
                                    value: selectedTemplateVersions.first.map { "v\($0.versionNumber)" } ?? "Sin histórico",
                                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                                )
                                WorkspaceMetricCard(
                                    title: "Ámbito",
                                    value: selectedClassId == nil ? "Global" : "Clase activa",
                                    systemImage: "rectangle.3.group"
                                )
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Uso recomendado")
                                    .font(.headline)
                                WorkspaceDetailBlock(title: "Tipo", content: templateUsageDescription(selectedTemplate.kind))
                                WorkspaceDetailBlock(title: "Clase activa", content: selectedClassId == nil ? "La plantilla se muestra sin una clase concreta seleccionada." : "Puedes reutilizar esta configuración desde el contexto actual del grupo.")
                            }

                            HStack(spacing: 12) {
                                Button(templatePrimaryActionTitle(selectedTemplate.kind)) {
                                    onOpenModule(templatePrimaryModule(selectedTemplate.kind), selectedClassId, nil)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Abrir biblioteca relacionada") {
                                    onOpenModule(.library, selectedClassId, nil)
                                }
                                .buttonStyle(.bordered)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Histórico")
                                    .font(.headline)
                                if selectedTemplateVersions.isEmpty {
                                    Text("Sin versiones registradas todavía.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(selectedTemplateVersions, id: \.id) { version in
                                        templateVersionCard(version)
                                    }
                                }
                            }
                        }
                        .padding(24)
                    }
                } else {
                    WorkspaceEmptyState(
                        title: "Biblioteca de configuración",
                        subtitle: "Aquí centralizamos plantillas de cuaderno, rúbricas y futuras configuraciones reutilizables."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appPageBackground(for: colorScheme))
        }
        .task { await reloadTemplates() }
        .onChange(of: selectedKindFilter) { _ in
            if selectedTemplateId == nil || !filteredTemplates.contains(where: { $0.id == selectedTemplateId }) {
                selectedTemplateId = filteredTemplates.first?.id
            }
        }
        .onChange(of: searchText) { _ in
            if selectedTemplateId == nil || !filteredTemplates.contains(where: { $0.id == selectedTemplateId }) {
                selectedTemplateId = filteredTemplates.first?.id
            }
        }
    }

    @MainActor
    private func reloadTemplates() async {
        templates = (try? await bridge.loadTemplates()) ?? []
        if selectedTemplateId == nil {
            selectedTemplateId = filteredTemplates.first?.id
        }
        if let selectedTemplateId {
            await reloadVersions(templateId: selectedTemplateId)
        }
    }

    @MainActor
    private func reloadVersions(templateId: Int64) async {
        versions = (try? await bridge.loadTemplateVersions(templateId: templateId)) ?? []
    }

    private func templateKindLabel(_ kind: ConfigTemplateKind) -> String {
        switch kind {
        case .notebookColumns:
            return "Columnas de cuaderno"
        case .rubric:
            return "Rúbricas"
        case .unitTemplate:
            return "Unidades"
        case .classStructure:
            return "Estructura de clase"
        default:
            return kind.name
        }
    }

    private func templateUsageDescription(_ kind: ConfigTemplateKind) -> String {
        switch kind {
        case .notebookColumns:
            return "Reutiliza configuraciones de columnas, pesos y estructura del cuaderno."
        case .rubric:
            return "Banco de valoración reutilizable para evaluación continua o EF."
        case .unitTemplate:
            return "Base para secuencias didácticas y sesiones derivadas."
        case .classStructure:
            return "Plantilla operativa para preparar grupos, pestañas y configuración docente."
        default:
            return "Plantilla reutilizable dentro de la biblioteca."
        }
    }

    private func templatePrimaryModule(_ kind: ConfigTemplateKind) -> AppWorkspaceModule {
        switch kind {
        case .notebookColumns:
            return .notebook
        case .rubric:
            return .rubrics
        case .unitTemplate:
            return .diary
        case .classStructure:
            return .courses
        default:
            return .library
        }
    }

    private func templatePrimaryActionTitle(_ kind: ConfigTemplateKind) -> String {
        switch kind {
        case .notebookColumns:
            return "Abrir cuaderno"
        case .rubric:
            return "Abrir rúbricas"
        case .unitTemplate:
            return "Abrir diario"
        case .classStructure:
            return "Abrir cursos"
        default:
            return "Abrir módulo"
        }
    }

    private func templateVersionCard(_ version: ConfigTemplateVersion) -> some View {
        let background = appCardBackground(for: colorScheme)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Versión \(version.versionNumber)")
                .font(.subheadline.weight(.bold))
            Text(version.payloadJson)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        .padding(12)
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct EFIncidentsWorkspaceView: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void

    @State private var incidents: [Incident] = []
    @State private var searchText = ""
    @State private var selectedFilter = "Todas"
    @State private var selectedIncidentId: Int64?
    @State private var metadata: [PEIncidentMetadata] = storedItems(forKey: peIncidentMetadataStorageKey, as: PEIncidentMetadata.self)
    @State private var showingCreateSheet = false

    private var availableFilters: [String] {
        ["Todas", "Lesión", "Seguridad", "Conducta", "Material", "Equipación", "Críticas"]
    }

    private var selectedIncident: Incident? {
        filteredIncidents.first(where: { $0.id == selectedIncidentId }) ?? incidents.first(where: { $0.id == selectedIncidentId })
    }

    private var selectedMetadata: PEIncidentMetadata? {
        guard let selectedIncidentId else { return nil }
        return metadata.first(where: { $0.id == selectedIncidentId })
    }

    private var filteredIncidents: [Incident] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return incidents.filter { incident in
            let matchesFilter: Bool = {
                switch selectedFilter {
                case "Críticas":
                    return isCritical(incident)
                case "Todas":
                    return true
                default:
                    return incidentCategory(for: incident) == selectedFilter
                }
            }()

            let haystack = [
                incident.title,
                incident.detail ?? "",
                incident.severity
            ]
            .joined(separator: " ")
            .lowercased()

            return matchesFilter && (query.isEmpty || haystack.contains(query))
        }
        .sorted { lhs, rhs in
            lhs.date.epochSeconds > rhs.date.epochSeconds
        }
    }

    private var metrics: (total: Int, critical: Int, followUp: Int) {
        (
            filteredIncidents.count,
            filteredIncidents.filter(isCritical).count,
            filteredIncidents.filter { $0.studentId != nil }.count
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Buscar incidencia, detalle o severidad…", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    HStack(spacing: 10) {
                        Picker("Filtro", selection: $selectedFilter) {
                            ForEach(availableFilters, id: \.self) { filter in
                                Text(filter).tag(filter)
                            }
                        }
                        .pickerStyle(.menu)

                        Spacer()

                        Button {
                            showingCreateSheet = true
                        } label: {
                            Label("Nueva incidencia", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    HStack(spacing: 10) {
                        WorkspaceCompactStat(title: "Total", value: "\(metrics.total)", tint: .blue)
                        WorkspaceCompactStat(title: "Críticas", value: "\(metrics.critical)", tint: .pink)
                        WorkspaceCompactStat(title: "Con alumno", value: "\(metrics.followUp)", tint: .orange)
                    }
                }
                .padding(16)

                List(filteredIncidents, id: \.id) { incident in
                    Button {
                        selectedIncidentId = incident.id
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(incident.title)
                                    .font(.headline)
                                Spacer()
                                Text(incident.severity.capitalized)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(severityColor(incident.severity))
                            }
                            Text("\(incidentCategory(for: incident)) · \(incidentDateLabel(incident))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 320, maxWidth: 380)

            Divider().opacity(0.2)

            Group {
                if let incident = selectedIncident {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            WorkspaceInspectorHero(
                                title: incident.title,
                                subtitle: "\(incidentCategory(for: incident)) · \(incident.severity.capitalized)"
                            )

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                                WorkspaceMetricCard(
                                    title: "Severidad",
                                    value: incident.severity.capitalized,
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                                WorkspaceMetricCard(
                                    title: "Alumno",
                                    value: incidentStudentName(incident) ?? "Sin alumno",
                                    systemImage: "person.fill"
                                )
                                WorkspaceMetricCard(
                                    title: "Fecha",
                                    value: incidentDateLabel(incident),
                                    systemImage: "calendar"
                                )
                                WorkspaceMetricCard(
                                    title: "Estado",
                                    value: selectedMetadata?.workflowState.rawValue ?? "Abierta",
                                    systemImage: "flag.fill"
                                )
                            }

                            WorkspaceDetailBlock(
                                title: "Detalle",
                                content: fallback(incident.detail ?? "", empty: "Sin detalle adicional")
                            )

                            WorkspaceDetailBlock(
                                title: "Seguimiento",
                                content: fallback(selectedMetadata?.followUpNote ?? "", empty: "Sin notas de seguimiento todavía")
                            )

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Clasificación EF")
                                    .font(.headline)
                                FlowLayout(spacing: 10) {
                                    WorkspaceTag(text: selectedMetadata?.category ?? incidentCategory(for: incident), systemImage: categoryIcon(for: incident))
                                    if isCritical(incident) {
                                        WorkspaceTag(text: "Revisión prioritaria", systemImage: "flame.fill")
                                    }
                                    if incident.studentId != nil {
                                        WorkspaceTag(text: "Seguimiento individual", systemImage: "person.crop.circle.badge.checkmark")
                                    }
                                    WorkspaceTag(text: selectedMetadata?.workflowState.rawValue ?? "Abierta", systemImage: "flag.fill")
                                }
                            }

                            if let incidentId = selectedIncidentId {
                                let activeWorkflowState = selectedMetadata?.workflowState ?? .open
                                HStack(spacing: 10) {
                                    workflowButton(title: PEIncidentWorkflowState.open.rawValue, incidentId: incidentId, targetState: .open, activeState: activeWorkflowState)
                                    workflowButton(title: PEIncidentWorkflowState.followUp.rawValue, incidentId: incidentId, targetState: .followUp, activeState: activeWorkflowState)
                                    workflowButton(title: PEIncidentWorkflowState.closed.rawValue, incidentId: incidentId, targetState: .closed, activeState: activeWorkflowState)
                                }
                            }

                            HStack(spacing: 12) {
                                if let studentId = incident.studentId?.int64Value {
                                    Button("Abrir alumno") {
                                        onOpenModule(.students, selectedClassId, studentId)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }

                                Button("Abrir diario") {
                                    onOpenModule(.diary, selectedClassId, incident.studentId?.int64Value)
                                }
                                .buttonStyle(.bordered)

                                Button("Abrir asistencia") {
                                    onOpenModule(.attendance, selectedClassId, incident.studentId?.int64Value)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(24)
                    }
                } else {
                    WorkspaceEmptyState(
                        title: "Selecciona una incidencia EF",
                        subtitle: "Aquí agrupamos lesiones, seguridad, equipación, material y conducta con accesos cruzados a diario, asistencia y alumnado."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appPageBackground(for: colorScheme))
        }
        .task { await reload() }
        .sheet(isPresented: $showingCreateSheet) {
            CreatePEIncidentSheet(defaultClassId: selectedClassId) { incidentId, category, workflowState, sessionId, note in
                let entry = PEIncidentMetadata(
                    id: incidentId,
                    category: category,
                    workflowState: workflowState,
                    sessionId: sessionId,
                    followUpNote: note
                )
                metadata.removeAll { $0.id == incidentId }
                metadata.append(entry)
                persistItems(metadata, forKey: peIncidentMetadataStorageKey)
                Task { await reload() }
            }
            .environmentObject(bridge)
        }
        .onChange(of: selectedClassId) { _ in
            Task { await reload() }
        }
        .onChange(of: selectedFilter) { _ in
            if selectedIncidentId == nil || !filteredIncidents.contains(where: { $0.id == selectedIncidentId }) {
                selectedIncidentId = filteredIncidents.first?.id
            }
        }
        .onChange(of: searchText) { _ in
            if selectedIncidentId == nil || !filteredIncidents.contains(where: { $0.id == selectedIncidentId }) {
                selectedIncidentId = filteredIncidents.first?.id
            }
        }
    }

    @MainActor
    private func reload() async {
        guard let selectedClassId else {
            incidents = []
            selectedIncidentId = nil
            return
        }
        incidents = (try? await bridge.incidents(for: selectedClassId)) ?? []
        if selectedIncidentId == nil || !incidents.contains(where: { $0.id == selectedIncidentId }) {
            selectedIncidentId = filteredIncidents.first?.id ?? incidents.first?.id
        }
    }

    private func incidentCategory(for incident: Incident) -> String {
        let text = "\(incident.title) \(incident.detail ?? "")".lowercased()
        if text.contains("les") || text.contains("injur") || text.contains("dolor") || text.contains("golpe") {
            return "Lesión"
        }
        if text.contains("segur") || text.contains("riesgo") || text.contains("caída") || text.contains("choque") {
            return "Seguridad"
        }
        if text.contains("material") || text.contains("balón") || text.contains("cono") || text.contains("raqueta") {
            return "Material"
        }
        if text.contains("equip") || text.contains("ropa") || text.contains("zapat") {
            return "Equipación"
        }
        if text.contains("conduct") || text.contains("comport") || text.contains("disciplina") {
            return "Conducta"
        }
        return "Seguridad"
    }

    private func categoryIcon(for incident: Incident) -> String {
        switch incidentCategory(for: incident) {
        case "Lesión": return "cross.case.fill"
        case "Seguridad": return "shield.fill"
        case "Material": return "shippingbox.fill"
        case "Equipación": return "tshirt.fill"
        case "Conducta": return "person.crop.circle.badge.exclamationmark"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private func isCritical(_ incident: Incident) -> Bool {
        let severity = incident.severity.lowercased()
        return severity == "high" || severity == "critical"
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "critical":
            return .pink
        case "high":
            return .red
        case "medium":
            return .orange
        default:
            return .secondary
        }
    }

    private func incidentStudentName(_ incident: Incident) -> String? {
        guard let studentId = incident.studentId?.int64Value else { return nil }
        let source = bridge.studentsInClass.isEmpty ? bridge.allStudents : bridge.studentsInClass
        guard let student = source.first(where: { $0.id == studentId }) else { return nil }
        return "\(student.firstName) \(student.lastName)"
    }

    private func incidentDateLabel(_ incident: Incident) -> String {
        Date(timeIntervalSince1970: TimeInterval(incident.date.epochSeconds))
            .formatted(date: .abbreviated, time: .shortened)
    }

    private func fallback(_ value: String, empty placeholder: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? placeholder : value
    }

    private func updateMetadata(for incidentId: Int64, mutate: (inout PEIncidentMetadata) -> Void) {
        if let index = metadata.firstIndex(where: { $0.id == incidentId }) {
            var current = metadata[index]
            mutate(&current)
            metadata[index] = current
        } else {
            var newEntry = PEIncidentMetadata(id: incidentId, category: selectedIncident.map(incidentCategory(for:)) ?? "Seguridad", workflowState: .open, sessionId: nil, followUpNote: "")
            mutate(&newEntry)
            metadata.append(newEntry)
        }
        persistItems(metadata, forKey: peIncidentMetadataStorageKey)
    }

    private func setIncidentWorkflowState(for incidentId: Int64, state: PEIncidentWorkflowState) {
        updateMetadata(for: incidentId) { current in
            current.workflowState = state
        }
    }

    @ViewBuilder
    private func workflowButton(title: String, incidentId: Int64, targetState: PEIncidentWorkflowState, activeState: PEIncidentWorkflowState) -> some View {
        let isActive = activeState == targetState
        if isActive {
            Button(title) {
                setIncidentWorkflowState(for: incidentId, state: targetState)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(title) {
                setIncidentWorkflowState(for: incidentId, state: targetState)
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct EFPhysicalTestsWorkspaceView: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void

    @State private var tests: [KmpBridge.PhysicalTestSnapshot] = []
    @State private var selectedTestId: Int64?
    @State private var selectedStudentId: Int64?
    @State private var scoreDraft = ""
    @State private var searchText = ""
    @State private var showingCreateSheet = false

    private var selectedTest: KmpBridge.PhysicalTestSnapshot? {
        tests.first(where: { $0.evaluation.id == selectedTestId })
    }

    private var filteredResults: [KmpBridge.PhysicalTestSnapshot.StudentResult] {
        guard let selectedTest else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return selectedTest.results }
        return selectedTest.results.filter {
            "\($0.student.firstName) \($0.student.lastName)".localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedResult: KmpBridge.PhysicalTestSnapshot.StudentResult? {
        filteredResults.first(where: { $0.student.id == selectedStudentId }) ??
        selectedTest?.results.first(where: { $0.student.id == selectedStudentId })
    }

    private var metrics: (tests: Int, recorded: Int, avg: Double) {
        let recorded = selectedTest?.recordedCount ?? 0
        let avg = selectedTest?.average ?? 0
        return (tests.count, recorded, avg)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        WorkspaceCompactStat(title: "Pruebas", value: "\(metrics.tests)", tint: .blue)
                        WorkspaceCompactStat(title: "Registros", value: "\(metrics.recorded)", tint: .green)
                        WorkspaceCompactStat(title: "Media", value: IosFormatting.decimal(from: metrics.avg), tint: .orange)
                        Spacer()
                        Button {
                            showingCreateSheet = true
                        } label: {
                            Label("Nueva prueba", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Buscar alumno…", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(16)

                List {
                    Section("Pruebas") {
                        ForEach(tests, id: \.evaluation.id) { snapshot in
                            Button {
                                selectedTestId = snapshot.evaluation.id
                                selectedStudentId = snapshot.results.first?.student.id
                                scoreDraft = displayScore(snapshot.results.first?.value)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(snapshot.evaluation.name)
                                        .font(.headline)
                                    Text("\(snapshot.recordedCount) registros · media \(IosFormatting.decimal(from: snapshot.average))")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if selectedTest != nil {
                        Section("Resultados") {
                            ForEach(filteredResults, id: \.student.id) { result in
                                Button {
                                    selectedStudentId = result.student.id
                                    scoreDraft = displayScore(result.value)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("\(result.student.firstName) \(result.student.lastName)")
                                                .font(.subheadline.weight(.bold))
                                            Text(result.value == nil ? "Sin marca" : "Marca registrada")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(result.value.map { IosFormatting.decimal(from: $0) } ?? "—")
                                            .font(.headline.monospacedDigit())
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 340, maxWidth: 400)

            Divider().opacity(0.2)

            Group {
                if let test = selectedTest, let result = selectedResult {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            WorkspaceInspectorHero(
                                title: test.evaluation.name,
                                subtitle: "\(result.student.firstName) \(result.student.lastName)"
                            )

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                                WorkspaceMetricCard(
                                    title: "Marca actual",
                                    value: result.value.map { IosFormatting.decimal(from: $0) } ?? "Sin dato",
                                    systemImage: "stopwatch.fill"
                                )
                                WorkspaceMetricCard(
                                    title: "Mejor del grupo",
                                    value: test.best.map { IosFormatting.decimal(from: $0) } ?? "Sin dato",
                                    systemImage: "trophy.fill"
                                )
                                WorkspaceMetricCard(
                                    title: "Media grupo",
                                    value: IosFormatting.decimal(from: test.average),
                                    systemImage: "chart.line.uptrend.xyaxis"
                                )
                            }

                            WorkspaceDetailBlock(
                                title: "Tipo de prueba",
                                content: fallback(test.evaluation.type, empty: "Prueba física")
                            )

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Registrar marca")
                                    .font(.headline)
                                TextField("Ej. 12.40", text: $scoreDraft)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .appKeyboardType(.decimalPad)

                                Button("Guardar resultado") {
                                    Task { await savePhysicalTestResult(test: test, result: result) }
                                }
                                .buttonStyle(.borderedProminent)
                            }

                            HStack(spacing: 12) {
                                Button("Abrir alumno") {
                                    onOpenModule(.students, selectedClassId, result.student.id)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Abrir cuaderno") {
                                    onOpenModule(.notebook, selectedClassId, result.student.id)
                                }
                                .buttonStyle(.bordered)

                                Button("Abrir evaluación") {
                                    onOpenModule(.evaluationHub, selectedClassId, result.student.id)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(24)
                    }
                } else {
                    WorkspaceEmptyState(
                        title: "Selecciona una prueba física",
                        subtitle: "Aquí registramos marcas, comparamos resultados por grupo y enlazamos con alumnado, cuaderno y evaluación."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appPageBackground(for: colorScheme))
        }
        .task { await reload() }
        .sheet(isPresented: $showingCreateSheet) {
            CreatePhysicalTestSheet(defaultClassId: selectedClassId) {
                Task { await reload() }
            }
            .environmentObject(bridge)
        }
        .onChange(of: selectedClassId) { _ in
            Task { await reload() }
        }
        .onChange(of: selectedStudentId) { _ in
            scoreDraft = displayScore(selectedResult?.value)
        }
    }

    @MainActor
    private func reload() async {
        guard let selectedClassId else {
            tests = []
            selectedTestId = nil
            selectedStudentId = nil
            return
        }
        tests = (try? await bridge.loadPhysicalTests(classId: selectedClassId)) ?? []
        if selectedTestId == nil || !tests.contains(where: { $0.evaluation.id == selectedTestId }) {
            selectedTestId = tests.first?.evaluation.id
        }
        if selectedStudentId == nil || !(selectedTest?.results.contains(where: { $0.student.id == selectedStudentId }) ?? false) {
            selectedStudentId = selectedTest?.results.first?.student.id
        }
        scoreDraft = displayScore(selectedResult?.value)
    }

    private func savePhysicalTestResult(test: KmpBridge.PhysicalTestSnapshot, result: KmpBridge.PhysicalTestSnapshot.StudentResult) async {
        guard let selectedClassId else { return }
        let normalized = scoreDraft.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedValue = Double(normalized)
        do {
            try await bridge.saveGrade(
                studentId: result.student.id,
                evaluationId: test.evaluation.id,
                value: parsedValue,
                classId: selectedClassId
            )
            bridge.status = parsedValue == nil ? "Marca limpiada correctamente." : "Marca física guardada."
            await reload()
        } catch {
            bridge.status = "No se pudo guardar la prueba física: \(error.localizedDescription)"
        }
    }

    private func displayScore(_ value: Double?) -> String {
        guard let value else { return "" }
        return IosFormatting.decimal(from: value)
    }

    private func fallback(_ value: String, empty placeholder: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? placeholder : value
    }
}

private struct PESessionsWorkspaceView: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void

    @State private var sessions: [KmpBridge.PESessionSnapshot] = []
    @State private var selectedSessionId: Int64?
    @State private var timerStart = Date()
    @State private var now = Date()
    @State private var showingCreateSheet = false
    @State private var showingOperationalSheet = false

    private var selectedSession: KmpBridge.PESessionSnapshot? {
        sessions.first(where: { $0.id == selectedSessionId })
    }

    private var activeDurationText: String {
        let interval = Int(now.timeIntervalSince(timerStart))
        let minutes = interval / 60
        let seconds = interval % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        WorkspaceCompactStat(title: "Sesiones", value: "\(sessions.count)", tint: .blue)
                        WorkspaceCompactStat(title: "Con diario", value: "\(sessions.filter { $0.summary != nil }.count)", tint: .green)
                        WorkspaceCompactStat(title: "Activa", value: activeDurationText, tint: .orange)
                        Spacer()
                        Button {
                            showingCreateSheet = true
                        } label: {
                            Label("Nueva sesión EF", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(16)

                List(sessions, id: \.id) { snapshot in
                    Button {
                        selectedSessionId = snapshot.id
                        timerStart = Date()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(snapshot.session.teachingUnitName)
                                    .font(.headline)
                                Spacer()
                                Text("P\(snapshot.session.period)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(weekdayLabel(snapshot.session.dayOfWeek)) · \(snapshot.session.groupName)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 330, maxWidth: 390)

            Divider().opacity(0.2)

            Group {
                if let snapshot = selectedSession {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            WorkspaceInspectorHero(
                                title: snapshot.session.teachingUnitName,
                                subtitle: "Sesión activa · \(snapshot.session.groupName)"
                            )

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                                WorkspaceMetricCard(title: "Temporizador", value: activeDurationText, systemImage: "timer")
                                WorkspaceMetricCard(title: "Intensidad", value: snapshot.intensityScore == 0 ? "Sin dato" : "\(snapshot.intensityScore)/5", systemImage: "flame.fill")
                                WorkspaceMetricCard(title: "Estado", value: snapshot.summary?.status.name.capitalized ?? "Sin diario", systemImage: "doc.text.fill")
                                WorkspaceMetricCard(title: "Sesión", value: sessionStateText(snapshot.session.status), systemImage: "figure.run")
                            }

                            WorkspaceDetailBlock(title: "Material listo", content: fallback(snapshot.materialToPrepareText, empty: "Sin preparación registrada"))
                            WorkspaceDetailBlock(title: "Material usado", content: fallback(snapshot.materialUsedText, empty: "Sin material usado registrado"))
                            WorkspaceDetailBlock(title: "Lesiones", content: fallback(snapshot.injuriesText, empty: "Sin lesiones activas"))
                            WorkspaceDetailBlock(title: "Sin equipación", content: fallback(snapshot.unequippedStudentsText, empty: "Sin alumnado sin equipación"))
                            WorkspaceDetailBlock(title: "Estaciones", content: fallback(snapshot.stationObservationsText, empty: "Sin observaciones por estaciones"))

                            if !fallback(snapshot.physicalIncidentsText, empty: "").isEmpty {
                                WorkspaceDetailBlock(title: "Incidencias físicas", content: snapshot.physicalIncidentsText)
                            }

                            HStack(spacing: 12) {
                                Button("Editar operativa") {
                                    showingOperationalSheet = true
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Abrir diario") {
                                    onOpenModule(.diary, snapshot.session.groupId, nil)
                                }
                                .buttonStyle(.bordered)

                                Button("Abrir asistencia") {
                                    onOpenModule(.attendance, snapshot.session.groupId, nil)
                                }
                                .buttonStyle(.bordered)

                                Button("Ver incidencias EF") {
                                    onOpenModule(.peIncidents, snapshot.session.groupId, nil)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(24)
                    }
                } else {
                    WorkspaceEmptyState(
                        title: "Selecciona una sesión EF",
                        subtitle: "La sesión activa muestra temporizador, intensidad, material, lesiones y accesos rápidos de pista."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appPageBackground(for: colorScheme))
        }
        .task { await reload() }
        .sheet(isPresented: $showingCreateSheet) {
            CreatePESessionSheet(defaultClassId: selectedClassId) {
                Task { await reload() }
            }
            .environmentObject(bridge)
        }
        .sheet(isPresented: $showingOperationalSheet) {
            if let selectedSession {
                EditPESessionOperationalSheet(snapshot: selectedSession) {
                    Task { await reload() }
                }
                .environmentObject(bridge)
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
            now = tick
        }
        .onChange(of: selectedClassId) { _ in
            Task { await reload() }
        }
    }

    @MainActor
    private func reload() async {
        let calendar = Calendar(identifier: .iso8601)
        let date = Date()
        let week = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        sessions = (try? await bridge.loadPESessions(weekNumber: week, year: year, classId: selectedClassId)) ?? []
        if selectedSessionId == nil || !sessions.contains(where: { $0.id == selectedSessionId }) {
            selectedSessionId = sessions.first?.id
        }
        timerStart = Date()
    }

    private func weekdayLabel(_ dayOfWeek: Int32) -> String {
        switch Int(dayOfWeek) {
        case 1: return "Lunes"
        case 2: return "Martes"
        case 3: return "Miércoles"
        case 4: return "Jueves"
        case 5: return "Viernes"
        default: return "Sesión"
        }
    }

    private func fallback(_ value: String, empty placeholder: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? placeholder : value
    }

    private func sessionStateText(_ status: SessionStatus) -> String {
        switch status {
        case .planned: return "Planificada"
        case .inProgress: return "Activa"
        case .completed: return "Cerrada"
        case .cancelled: return "Cancelada"
        default: return status.name.capitalized
        }
    }
}

private struct PEMaterialWorkspaceView: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void

    @State private var sessions: [KmpBridge.PESessionSnapshot] = []
    @State private var records: [PEMaterialRecord] = storedItems(forKey: peMaterialStorageKey, as: PEMaterialRecord.self)
    @State private var selectedRecordId: UUID?
    @State private var showingCreateSheet = false

    private var filteredRecords: [PEMaterialRecord] {
        let scoped = selectedClassId.map { classId in
            records.filter { $0.classId == classId }
        } ?? records
        return scoped.sorted { $0.createdAt > $1.createdAt }
    }

    private var selectedRecord: PEMaterialRecord? {
        filteredRecords.first(where: { $0.id == selectedRecordId }) ?? filteredRecords.first
    }

    private var selectedSession: KmpBridge.PESessionSnapshot? {
        guard let sessionId = selectedRecord?.sessionId else { return nil }
        return sessions.first(where: { $0.id == sessionId })
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        WorkspaceCompactStat(title: "Registros", value: "\(filteredRecords.count)", tint: .blue)
                        WorkspaceCompactStat(title: "Dañado", value: "\(filteredRecords.filter { $0.status == .damaged }.count)", tint: .red)
                        WorkspaceCompactStat(title: "Reponer", value: "\(filteredRecords.filter { $0.status == .replenish }.count)", tint: .orange)
                        Spacer()
                        Button {
                            showingCreateSheet = true
                        } label: {
                            Label("Nuevo material", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(16)

                List(filteredRecords, id: \.id) { record in
                    Button {
                        selectedRecordId = record.id
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.itemName)
                                .font(.headline)
                            Text("\(record.status.rawValue) · \(record.quantity) uds")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 330, maxWidth: 390)

            Divider().opacity(0.2)

            Group {
                if let record = selectedRecord {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            WorkspaceInspectorHero(title: record.itemName, subtitle: record.status.rawValue)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                                WorkspaceMetricCard(title: "Cantidad", value: "\(record.quantity)", systemImage: "number")
                                WorkspaceMetricCard(title: "Estado", value: record.status.rawValue, systemImage: "shippingbox.fill")
                                WorkspaceMetricCard(
                                    title: "Sesión",
                                    value: selectedSession?.session.teachingUnitName ?? "Sin sesión",
                                    systemImage: "figure.run"
                                )
                            }
                            WorkspaceDetailBlock(title: "Nota logística", content: fallback(record.note, empty: "Sin notas adicionales"))
                            if let selectedSession {
                                WorkspaceDetailBlock(title: "Material de la sesión", content: fallback(selectedSession.materialUsedText, empty: "Sin material usado registrado"))
                            }

                            HStack(spacing: 12) {
                                if let selectedSession {
                                    Button("Abrir sesión EF") {
                                        onOpenModule(.peSessions, selectedSession.session.groupId, nil)
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button("Abrir diario") {
                                        onOpenModule(.diary, selectedSession.session.groupId, nil)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .padding(24)
                    }
                } else {
                    VStack(spacing: 18) {
                        WorkspaceEmptyState(
                            title: "Registra material EF",
                            subtitle: "Crea registros de preparación, uso, faltantes, daños o reposición vinculados a una sesión."
                        )
                        Button("Nuevo registro de material") {
                            showingCreateSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appPageBackground(for: colorScheme))
        }
        .task { await reload() }
        .sheet(isPresented: $showingCreateSheet) {
            CreatePEMaterialRecordSheet(defaultClassId: selectedClassId, sessions: sessions) { record in
                records.removeAll { $0.id == record.id }
                records.append(record)
                persistItems(records, forKey: peMaterialStorageKey)
                selectedRecordId = record.id
                Task { await reload() }
            }
            .environmentObject(bridge)
        }
        .onChange(of: selectedClassId) { _ in
            Task { await reload() }
        }
    }

    @MainActor
    private func reload() async {
        let calendar = Calendar(identifier: .iso8601)
        let date = Date()
        let week = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        sessions = (try? await bridge.loadPESessions(weekNumber: week, year: year, classId: selectedClassId)) ?? []
        if selectedRecordId == nil || !filteredRecords.contains(where: { $0.id == selectedRecordId }) {
            selectedRecordId = filteredRecords.first?.id
        }
    }

    private func fallback(_ value: String, empty placeholder: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? placeholder : value
    }
}

private struct PETournamentsWorkspaceView: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedClassId: Int64?

    @State private var tournaments: [TournamentViewState] = storedItems(forKey: peTournamentStorageKey, as: TournamentViewState.self)
    @State private var selectedTournamentId: UUID?
    @State private var selectedMatchId: UUID?
    @State private var showingCreateSheet = false
    @State private var showingBoardScreen = false

    private var scopedTournaments: [TournamentViewState] {
        tournaments
            .filter { selectedClassId == nil || $0.classId == selectedClassId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var selectedTournament: TournamentViewState? {
        scopedTournaments.first(where: { $0.id == selectedTournamentId }) ?? scopedTournaments.first
    }

    private var selectedMatch: TournamentMatch? {
        guard let selectedTournament else { return nil }
        return selectedTournament.matches.first(where: { $0.id == selectedMatchId }) ?? selectedTournament.matches.first
    }

    private var standings: [(team: TournamentTeam, points: Int, scored: Int, conceded: Int)] {
        guard let selectedTournament else { return [] }
        return computeStandings(for: selectedTournament, matches: selectedTournament.matches)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        WorkspaceCompactStat(title: "Torneos", value: "\(scopedTournaments.count)", tint: .blue)
                        WorkspaceCompactStat(title: "Equipos", value: "\(selectedTournament?.teams.count ?? 0)", tint: .orange)
                        WorkspaceCompactStat(title: "Partidos", value: "\(selectedTournament?.matches.count ?? 0)", tint: .green)
                    }
                }
                .padding(16)

                List {
                    Section("Torneos") {
                        ForEach(scopedTournaments, id: \.id) { tournament in
                            Button {
                                selectedTournamentId = tournament.id
                                selectedMatchId = tournament.matches.first?.id
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(tournament.name)
                                        .font(.headline)
                                    Text("\(tournament.template.rawValue) · \(tournament.status.rawValue)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 300, maxWidth: 340)

            Divider().opacity(0.2)

            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    if let selectedTournament {
                        HStack {
                            Text(selectedTournament.template.rawValue)
                                .font(.headline)
                            Spacer()
                            Button("Vista torneo") {
                                showingBoardScreen = true
                            }
                            .buttonStyle(.bordered)
                            Menu {
                                ForEach(TournamentStatus.allCases) { status in
                                    Button(status.rawValue) {
                                        updateTournament(selectedTournament.id) { current in
                                            current.status = status
                                        }
                                    }
                                }
                            } label: {
                                Label(selectedTournament.status.rawValue, systemImage: "flag.fill")
                            }
                        }
                    }
                }
                .padding(16)

                List {
                    if let selectedTournament {
                        Section("Partidos") {
                            ForEach(Array(selectedTournament.matches.enumerated()), id: \.element.id) { index, match in
                                Button {
                                    selectedMatchId = match.id
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("\(match.phase) · Ronda \(match.round)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.secondary)
                                        HStack {
                                            Text(match.homeLabel)
                                            Spacer()
                                            Stepper(value: matchBinding(tournamentId: selectedTournament.id, matchIndex: index, home: true), in: 0...99) {
                                                Text("\(match.homeScore)")
                                                    .font(.headline.monospacedDigit())
                                            }
                                        }
                                        HStack {
                                            Text(match.awayLabel)
                                            Spacer()
                                            Stepper(value: matchBinding(tournamentId: selectedTournament.id, matchIndex: index, home: false), in: 0...99) {
                                                Text("\(match.awayScore)")
                                                    .font(.headline.monospacedDigit())
                                            }
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 380, maxWidth: 470)

            Divider().opacity(0.2)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let selectedTournament {
                        WorkspaceInspectorHero(title: selectedTournament.name, subtitle: selectedClassLabel)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                            WorkspaceMetricCard(title: "Plantilla", value: selectedTournament.template.rawValue, systemImage: "square.grid.3x3.fill")
                            WorkspaceMetricCard(title: "Equipos", value: "\(selectedTournament.teams.count)", systemImage: "person.3.fill")
                            WorkspaceMetricCard(title: "Partidos", value: "\(selectedTournament.matches.count)", systemImage: "sportscourt.fill")
                            WorkspaceMetricCard(title: "Estado", value: selectedTournament.status.rawValue, systemImage: "flag.fill")
                        }

                        if let selectedMatch {
                            WorkspaceDetailBlock(
                                title: "Partido seleccionado",
                                content: "\(selectedMatch.phase) · Ronda \(selectedMatch.round)\n\(selectedMatch.homeLabel) vs \(selectedMatch.awayLabel)\nPista: \(selectedMatch.court.isEmpty ? "Sin asignar" : selectedMatch.court)"
                            )
                        }

                        HStack(spacing: 12) {
                            Button("Abrir progreso del torneo") {
                                showingBoardScreen = true
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Nuevo torneo") {
                                showingCreateSheet = true
                            }
                            .buttonStyle(.bordered)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Clasificación")
                                .font(.headline)
                            ForEach(Array(standings.enumerated()), id: \.offset) { index, standing in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("#\(index + 1) · \(standing.team.name)")
                                        .font(.headline)
                                    Text("\(standing.points) pts · \(standing.scored) a favor · \(standing.conceded) en contra")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }

                        if selectedTournament.template == .groupsAndKnockout {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Clasificación por grupos")
                                    .font(.headline)
                                ForEach(groupStandings(for: selectedTournament), id: \.key) { group, rows in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(group)
                                            .font(.subheadline.bold())
                                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                                            groupStandingRow(index: index, row: row)
                                        }
                                    }
                                    .padding(12)
                                    .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Equipos")
                                .font(.headline)
                            ForEach(selectedTournament.teams, id: \.id) { team in
                                WorkspaceDetailBlock(
                                    title: team.name,
                                    content: teamSummaryText(team, tournament: selectedTournament)
                                )
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            WorkspaceEmptyState(
                                title: "Organiza un torneo EF",
                                subtitle: "Crea torneos con plantillas Round-robin, Eliminatoria o Fase de grupos + eliminatoria."
                            )
                            Button("Nuevo torneo") {
                                showingCreateSheet = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appPageBackground(for: colorScheme))
        }
        .task { await reloadTeams() }
        .sheet(isPresented: $showingCreateSheet) {
            CreateTournamentSheet(defaultClassId: selectedClassId) { tournament in
                tournaments.append(tournament)
                persistItems(tournaments, forKey: peTournamentStorageKey)
                selectedTournamentId = tournament.id
                selectedMatchId = tournament.matches.first?.id
            }
            .environmentObject(bridge)
        }
        .appFullScreenCover(isPresented: $showingBoardScreen) {
            if let selectedTournament, let binding = tournamentBinding(for: selectedTournament.id) {
                TournamentBoardScreen(
                    tournament: binding,
                    classLabel: selectedClassLabel,
                    students: bridge.studentsInClass
                )
            } else {
                EmptyView()
            }
        }
        .onChange(of: selectedClassId) { _ in
            Task { await reloadTeams() }
        }
    }

    private var selectedClassLabel: String {
        guard let selectedClassId,
              let schoolClass = bridge.classes.first(where: { $0.id == selectedClassId }) else {
            return "Torneo de clase"
        }
        return schoolClass.name
    }

    @MainActor
    private func reloadTeams() async {
        await bridge.selectStudentsClass(classId: selectedClassId)
        if selectedTournamentId == nil || !scopedTournaments.contains(where: { $0.id == selectedTournamentId }) {
            selectedTournamentId = scopedTournaments.first?.id
        }
        if selectedMatchId == nil || !(selectedTournament?.matches.contains(where: { $0.id == selectedMatchId }) ?? false) {
            selectedMatchId = selectedTournament?.matches.first?.id
        }
    }

    private func updateTournament(_ tournamentId: UUID, mutate: (inout TournamentViewState) -> Void) {
        guard let index = tournaments.firstIndex(where: { $0.id == tournamentId }) else { return }
        var current = tournaments[index]
        mutate(&current)
        tournaments[index] = current
        persistItems(tournaments, forKey: peTournamentStorageKey)
    }

    private func tournamentBinding(for tournamentId: UUID) -> Binding<TournamentViewState>? {
        guard let index = tournaments.firstIndex(where: { $0.id == tournamentId }) else { return nil }
        return Binding(
            get: { tournaments[index] },
            set: { tournaments[index] = $0; persistItems(tournaments, forKey: peTournamentStorageKey) }
        )
    }

    private func matchBinding(tournamentId: UUID, matchIndex: Int, home: Bool) -> Binding<Int> {
        Binding(
            get: {
                guard let tournament = tournaments.first(where: { $0.id == tournamentId }),
                      tournament.matches.indices.contains(matchIndex) else { return 0 }
                return home ? tournament.matches[matchIndex].homeScore : tournament.matches[matchIndex].awayScore
            },
            set: { newValue in
                updateTournament(tournamentId) { current in
                    guard current.matches.indices.contains(matchIndex) else { return }
                    if home {
                        current.matches[matchIndex].homeScore = newValue
                    } else {
                        current.matches[matchIndex].awayScore = newValue
                    }
                }
            }
        )
    }

    private func computeStandings(
        for tournament: TournamentViewState,
        matches: [TournamentMatch]
    ) -> [(team: TournamentTeam, points: Int, scored: Int, conceded: Int)] {
        tournament.teams.map { team in
            let related = matches.filter { $0.homeTeamId == team.id || $0.awayTeamId == team.id }
            let points = related.reduce(0) { total, match in
                let isHome = match.homeTeamId == team.id
                let scored = isHome ? match.homeScore : match.awayScore
                let conceded = isHome ? match.awayScore : match.homeScore
                if scored > conceded { return total + tournament.pointsWin }
                if scored == conceded { return total + tournament.pointsDraw }
                return total + tournament.pointsLoss
            }
            let scored = related.reduce(0) { partial, match in
                partial + (match.homeTeamId == team.id ? match.homeScore : match.awayTeamId == team.id ? match.awayScore : 0)
            }
            let conceded = related.reduce(0) { partial, match in
                partial + (match.homeTeamId == team.id ? match.awayScore : match.awayTeamId == team.id ? match.homeScore : 0)
            }
            return (team, points, scored, conceded)
        }
        .sorted { lhs, rhs in
            if lhs.points == rhs.points { return lhs.scored > rhs.scored }
            return lhs.points > rhs.points
        }
    }

    private func groupStandings(for tournament: TournamentViewState) -> [(key: String, value: [(team: TournamentTeam, points: Int, scored: Int, conceded: Int)])] {
        let grouped = Dictionary(grouping: tournament.matches.filter { $0.phase.hasPrefix("Grupo") }) { $0.phase }
        return grouped.keys.sorted().map { key in
            (key, computeStandings(for: tournament, matches: grouped[key] ?? []))
        }
    }

    private func teamSummaryText(_ team: TournamentTeam, tournament: TournamentViewState) -> String {
        let names = team.studentIds.compactMap { studentId in
            bridge.studentsInClass.first(where: { $0.id == studentId }).map { "\($0.firstName) \($0.lastName)" }
        }
        guard !names.isEmpty else { return "Sin participantes asignados" }
        return "\(names.count) participante(s)\n" + names.joined(separator: ", ")
    }

    private func groupStandingRow(
        index: Int,
        row: (team: TournamentTeam, points: Int, scored: Int, conceded: Int)
    ) -> some View {
        let description = "#\(index + 1) · \(row.team.name) · \(row.points) pts"
        return Text(description)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct StudentProfilesWorkspaceView: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    @State private var searchText = ""
    @State private var profile: KmpBridge.StudentProfileSnapshot?

    private var filteredStudents: [Student] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = bridge.studentsInClass.isEmpty ? bridge.allStudents : bridge.studentsInClass
        guard !query.isEmpty else { return base }
        return base.filter {
            "\($0.firstName) \($0.lastName)".localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Buscar alumno…", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(16)

                List(filteredStudents, id: \.id) { student in
                    Button {
                        selectedStudentId = student.id
                        Task { await reloadProfile() }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(student.firstName) \(student.lastName)")
                                .font(.headline)
                            Text(student.isInjured ? "Seguimiento físico activo" : "Alumno")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 320, maxWidth: 360)

            Divider().opacity(0.2)

            Group {
                if let profile {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            WorkspaceInspectorHero(
                                title: "\(profile.student.firstName) \(profile.student.lastName)",
                                subtitle: profile.schoolClass?.name ?? "Sin grupo activo"
                            )

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                                WorkspaceMetricCard(title: "Asistencia", value: "\(profile.attendanceRate)%", systemImage: "checklist.checked")
                                WorkspaceMetricCard(title: "Media", value: IosFormatting.decimal(from: profile.averageScore), systemImage: "sum")
                                WorkspaceMetricCard(title: "Incidencias", value: "\(profile.incidentCount)", systemImage: "exclamationmark.bubble.fill")
                                WorkspaceMetricCard(title: "Seguimiento", value: "\(profile.followUpCount)", systemImage: "arrow.triangle.branch")
                                WorkspaceMetricCard(title: "Instrumentos", value: "\(profile.instrumentsCount)", systemImage: "chart.bar.doc.horizontal")
                                WorkspaceMetricCard(title: "Evidencias", value: "\(profile.evidenceCount)", systemImage: "paperclip")
                                WorkspaceMetricCard(title: "Sesiones diario", value: "\(profile.journalSessionCount)", systemImage: "doc.text.fill")
                                WorkspaceMetricCard(title: "Notas individuales", value: "\(profile.journalNoteCount)", systemImage: "note.text")
                            }

                            HStack(spacing: 12) {
                                WorkspaceCompactStat(
                                    title: "Último estado",
                                    value: profile.latestAttendanceStatus ?? "Sin registros",
                                    tint: profile.latestAttendanceStatus?.uppercased().contains("AUS") == true ? .red : .green
                                )
                                WorkspaceCompactStat(
                                    title: "Perfil físico",
                                    value: profile.student.isInjured ? "Lesionado" : "Disponible",
                                    tint: profile.student.isInjured ? .orange : .blue
                                )
                                WorkspaceCompactStat(
                                    title: "Familias",
                                    value: "\(profile.familyCommunicationCount)",
                                    tint: .indigo
                                )
                            }

                            if !profile.recentAttendance.isEmpty {
                                let recentAttendance = Array(profile.recentAttendance.prefix(4))
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Asistencia reciente")
                                        .font(.headline)
                                    ForEach(recentAttendance, id: \.id) { attendance in
                                        recentAttendanceCard(attendance)
                                    }
                                }
                            }

                            if !profile.incidents.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Incidencias destacadas")
                                        .font(.headline)
                                    ForEach(profile.incidents.prefix(3), id: \.id) { incident in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(incident.title)
                                                    .font(.subheadline.weight(.bold))
                                                Spacer()
                                                Text(incident.severity.capitalized)
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(.secondary)
                                            }
                                            Text(incident.detail ?? "Sin detalle")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(12)
                                        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    }
                                }
                            }

                            if !profile.evaluationTitles.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Instrumentos vinculados")
                                        .font(.headline)
                                    FlowLayout(spacing: 10) {
                                        ForEach(profile.evaluationTitles, id: \.self) { evaluation in
                                            WorkspaceTag(text: evaluation, systemImage: "checklist")
                                        }
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Resumen docente")
                                    .font(.headline)

                                VStack(alignment: .leading, spacing: 8) {
                                    ProfileSummaryLine(
                                        title: "Grupo activo",
                                        value: profile.schoolClass?.name ?? "Sin grupo filtrado"
                                    )
                                    ProfileSummaryLine(
                                        title: "Seguimientos abiertos",
                                        value: "\(profile.followUpCount)"
                                    )
                                    ProfileSummaryLine(
                                        title: "Registros con evidencia",
                                        value: "\(profile.evidenceCount)"
                                    )
                                    ProfileSummaryLine(
                                        title: "Instrumentos evaluativos",
                                        value: "\(profile.instrumentsCount)"
                                    )
                                    ProfileSummaryLine(
                                        title: "Sesiones con seguimiento",
                                        value: "\(profile.journalSessionCount)"
                                    )
                                }
                                .padding(14)
                                .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }

                            if profile.adaptationsSummary != nil || profile.familyCommunicationSummary != nil {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Contexto pedagógico")
                                        .font(.headline)

                                    if let adaptationsSummary = profile.adaptationsSummary {
                                        WorkspaceDetailBlock(
                                            title: "Adaptaciones recientes",
                                            content: adaptationsSummary
                                        )
                                    }

                                    if let familyCommunicationSummary = profile.familyCommunicationSummary {
                                        WorkspaceDetailBlock(
                                            title: "Comunicación con familias",
                                            content: familyCommunicationSummary
                                        )
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Timeline docente")
                                    .font(.headline)
                                if profile.timeline.isEmpty {
                                    Text("Todavía no hay registros vinculados en esta clase.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(profile.timeline) { entry in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(entry.title)
                                                .font(.subheadline.weight(.bold))
                                            Text(entry.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(12)
                                        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    }
                                }
                            }

                            HStack(spacing: 12) {
                                Button("Ir a asistencia") {
                                    onOpenModule(.attendance, selectedClassId, profile.student.id)
                                }
                                .buttonStyle(.bordered)
                                Button("Abrir diario") {
                                    onOpenModule(.diary, selectedClassId, profile.student.id)
                                }
                                .buttonStyle(.bordered)
                                Button("Abrir cuaderno") {
                                    onOpenModule(.notebook, selectedClassId, profile.student.id)
                                }
                                .buttonStyle(.borderedProminent)
                                Button("Ver informes") {
                                    onOpenModule(.reports, selectedClassId, profile.student.id)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(24)
                    }
                } else {
                    WorkspaceEmptyState(
                        title: "Selecciona un alumno",
                        subtitle: "La ficha reúne asistencia, evolución, incidencias y evidencias en un mismo flujo."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appPageBackground(for: colorScheme))
        }
        .task {
            await bridge.ensureClassesLoaded()
            await bridge.selectStudentsClass(classId: selectedClassId)
            if selectedStudentId == nil {
                selectedStudentId = bridge.studentsInClass.first?.id ?? bridge.allStudents.first?.id
            }
            await reloadProfile()
        }
        .onChange(of: selectedClassId) { _ in
            Task {
                await bridge.selectStudentsClass(classId: selectedClassId)
                if selectedStudentId == nil {
                    selectedStudentId = bridge.studentsInClass.first?.id
                }
                await reloadProfile()
            }
        }
        .onChange(of: selectedStudentId) { _ in
            Task { await reloadProfile() }
        }
    }

    private func recentAttendanceCard(_ attendance: KmpBridge.AttendanceRecordSnapshot) -> some View {
        let note = attendance.note.isEmpty ? "Registro diario" : attendance.note
        let background = appCardBackground(for: colorScheme)
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(attendance.status)
                    .font(.subheadline.weight(.bold))
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(attendance.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @MainActor
    private func reloadProfile() async {
        guard let selectedStudentId else { return }
        profile = try? await bridge.loadStudentProfile(studentId: selectedStudentId, classId: selectedClassId)
    }
}

private struct EFPlaceholderModuleView: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String

    var body: some View {
        WorkspaceEmptyState(title: title, subtitle: subtitle)
            .background(appPageBackground(for: colorScheme).ignoresSafeArea())
    }
}

private struct AttendanceRowCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let row: AttendanceEntryRow
    let onPickStatus: (AttendanceStatusOption) -> Void
    let onSelect: () -> Void
    let isSaving: Bool

    private var primaryOptions: [AttendanceStatusOption] {
        AttendanceStatusOption.all.filter { ["PRESENTE", "AUSENTE", "TARDE"].contains($0.id) }
    }

    private var secondaryOptions: [AttendanceStatusOption] {
        AttendanceStatusOption.all.filter { !["PRESENTE", "AUSENTE", "TARDE"].contains($0.id) }
    }

    private var selectedOption: AttendanceStatusOption? {
        AttendanceStatusOption.all.first(where: { $0.id == row.record?.status })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(row.student.firstName) \(row.student.lastName)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    HStack(spacing: 8) {
                        Text((selectedOption?.label ?? "Sin registro").uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        if isSaving {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                }
                Spacer()
                Button("Ficha") { onSelect() }
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                ForEach(primaryOptions) { option in
                    attendanceStatusButton(option)
                }

                Menu {
                    ForEach(secondaryOptions) { option in
                        Button(option.label) {
                            if row.record?.status != option.id {
                                onPickStatus(option)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "ellipsis.circle")
                            .font(.body.weight(.semibold))
                        Text(secondaryLabel)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let selectedOption,
                           secondaryOptions.contains(where: { $0.id == selectedOption.id }) {
                            Circle()
                                .fill(selectedOption.color)
                                .frame(width: 10, height: 10)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .background(appMutedCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var secondaryLabel: String {
        guard let selectedOption,
              secondaryOptions.contains(where: { $0.id == selectedOption.id }) else {
            return "Más estados"
        }
        return selectedOption.label
    }

    private func attendanceStatusButton(_ option: AttendanceStatusOption) -> some View {
        Button {
            if row.record?.status != option.id {
                onPickStatus(option)
            }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(option.color)
                    .frame(width: 10, height: 10)
                Text(option.label)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if row.record?.status == option.id {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(
                option.color.opacity(row.record?.status == option.id ? 0.18 : 0.08),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(option.color.opacity(row.record?.status == option.id ? 0.42 : 0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(isSaving && row.record?.status != option.id ? 0.84 : 1)
    }
}

private struct WorkspaceInspectorHero: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 30, weight: .black, design: .rounded))
            Text(subtitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProfileSummaryLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.bold))
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct WorkspaceDetailBlock: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let content: String

    var bodyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.bold))
            Text(content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    var body: some View {
        bodyView
    }
}

private struct WorkspaceMetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .black, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct EvaluationInspectorModel {
    let title: String
    let subtitle: String
    let code: String
    let weightText: String
    let rubricName: String
    let linkedClassCountText: String
    let summary: String
    let readinessTags: [String]
}

private struct RubricInspectorModel {
    struct CriterionModel: Identifiable {
        let id: Int64
        let title: String
        let weightText: String
        let levels: [String]
    }

    let title: String
    let subtitle: String
    let criteria: [CriterionModel]
}

private enum PEIncidentWorkflowState: String, Codable, CaseIterable, Identifiable {
    case open = "Abierta"
    case followUp = "Seguimiento"
    case closed = "Cerrada"

    var id: String { rawValue }
}

private struct PEIncidentMetadata: Identifiable, Codable {
    let id: Int64
    var category: String
    var workflowState: PEIncidentWorkflowState
    var sessionId: Int64?
    var followUpNote: String
}

private enum PEMaterialStatus: String, Codable, CaseIterable, Identifiable {
    case prepared = "Preparado"
    case used = "Usado"
    case missing = "Faltante"
    case damaged = "Dañado"
    case replenish = "Reponer"

    var id: String { rawValue }
}

private struct PEMaterialRecord: Identifiable, Codable {
    let id: UUID
    let classId: Int64
    let sessionId: Int64?
    var itemName: String
    var quantity: Int
    var status: PEMaterialStatus
    var note: String
    var createdAt: Date
}

private enum TournamentTemplate: String, Codable, CaseIterable, Identifiable {
    case roundRobin = "Round-robin"
    case knockout = "Eliminatoria"
    case groupsAndKnockout = "Fase de grupos + eliminatoria"

    var id: String { rawValue }
}

private enum TournamentStatus: String, Codable, CaseIterable, Identifiable {
    case draft = "Borrador"
    case active = "Activo"
    case closed = "Cerrado"
    case archived = "Archivado"

    var id: String { rawValue }
}

private enum TournamentStudentLevel: String, Codable, CaseIterable, Identifiable {
    case strong = "Fuerte"
    case balanced = "Medio"
    case developing = "Débil"

    var id: String { rawValue }

    var score: Int {
        switch self {
        case .strong: return 3
        case .balanced: return 2
        case .developing: return 1
        }
    }
}

private struct TournamentStudentProfile: Identifiable, Codable {
    let id: Int64
    var level: TournamentStudentLevel
    var incompatibleStudentIds: [Int64]
}

private struct TournamentTeam: Identifiable, Codable {
    let id: UUID
    var name: String
    var colorHex: String
    var studentIds: [Int64]
}

private struct TournamentMatch: Identifiable, Codable {
    let id: UUID
    var phase: String
    var round: Int
    var homeLabel: String
    var awayLabel: String
    var homeTeamId: UUID?
    var awayTeamId: UUID?
    var homeScore: Int
    var awayScore: Int
    var court: String
    var linkedSessionId: Int64?
}

private struct TournamentViewState: Identifiable, Codable {
    let id: UUID
    let classId: Int64
    var name: String
    var sport: String
    var template: TournamentTemplate
    var status: TournamentStatus
    var pointsWin: Int
    var pointsDraw: Int
    var pointsLoss: Int
    var tieBreaker: String
    var teams: [TournamentTeam]
    var matches: [TournamentMatch]
    var studentProfiles: [TournamentStudentProfile]?
    var createdAt: Date
}

private let peIncidentMetadataStorageKey = "workspace.pe.incident.metadata.v1"
private let peMaterialStorageKey = "workspace.pe.material.records.v1"
private let peTournamentStorageKey = "workspace.pe.tournaments.v1"
private let peTournamentSportsStorageKey = "workspace.pe.tournaments.sports.v1"
private let peTournamentTieBreakersStorageKey = "workspace.pe.tournaments.tieBreakers.v1"

private func storedItems<T: Decodable>(forKey key: String, as type: T.Type) -> [T] {
    guard let data = UserDefaults.standard.data(forKey: key),
          let decoded = try? JSONDecoder().decode([T].self, from: data) else {
        return []
    }
    return decoded
}

private func persistItems<T: Encodable>(_ items: [T], forKey key: String) {
    guard let data = try? JSONEncoder().encode(items) else { return }
    UserDefaults.standard.set(data, forKey: key)
}

private func sanitizeDomainText(_ value: String?, fallback: String = "Sin descripción") -> String {
    let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return fallback }

    if trimmed.contains("RubricCriterion("),
       let extracted = captureField("description", from: trimmed, until: ", weight=") {
        return extracted
    }
    if trimmed.contains("Evaluation(") {
        if let extracted = captureField("description", from: trimmed, until: ", competencyLinks="), !extracted.isEmpty {
            return sanitizeDomainText(extracted, fallback: fallback)
        }
        if let extracted = captureField("name", from: trimmed, until: ", type=") {
            return extracted
        }
    }
    if trimmed.contains("AuditTrace(") {
        return fallback
    }
    return trimmed
}

private func captureField(_ field: String, from raw: String, until marker: String) -> String? {
    guard let startRange = raw.range(of: "\(field)=") else { return nil }
    let start = startRange.upperBound
    let tail = raw[start...]
    if let endRange = tail.range(of: marker) {
        return String(tail[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return String(tail).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func evaluationPresentation(
    evaluation: Evaluation,
    rubrics: [RubricDetail],
    rubricClassLinks: [Int64: Set<Int64>]
) -> EvaluationInspectorModel {
    let rubricId = evaluation.rubricId?.int64Value
    let rubric = rubricId.flatMap { id in rubrics.first(where: { $0.rubric.id == id }) }
    let linkedClassCount = rubricId.flatMap { rubricClassLinks[$0]?.count } ?? 0
    let cleanDescription = sanitizeDomainText(evaluation.description_, fallback: "Instrumento listo para cuaderno y evaluación.")
    return EvaluationInspectorModel(
        title: sanitizeDomainText(evaluation.name, fallback: "Evaluación"),
        subtitle: sanitizeDomainText(evaluation.type, fallback: "Instrumento"),
        code: sanitizeDomainText(evaluation.code, fallback: "Sin código"),
        weightText: IosFormatting.decimal(from: evaluation.weight),
        rubricName: rubric?.rubric.name ?? (rubricId == nil ? "Sin asignar" : "Rúbrica #\(rubricId!)"),
        linkedClassCountText: "\(linkedClassCount)",
        summary: cleanDescription,
        readinessTags: [
            rubricId == nil ? "Pendiente de rúbrica" : "Con rúbrica",
            evaluation.weight >= 1 ? "Peso completo" : "Peso parcial",
            cleanDescription == "Instrumento listo para cuaderno y evaluación." ? "Sin descripción" : "Con contexto"
        ]
    )
}

private func rubricPresentation(_ rubric: RubricDetail) -> RubricInspectorModel {
    RubricInspectorModel(
        title: sanitizeDomainText(rubric.rubric.name, fallback: "Rúbrica"),
        subtitle: sanitizeDomainText(rubric.rubric.description_, fallback: "Banco de rúbricas"),
        criteria: rubric.criteria.map { item in
            RubricInspectorModel.CriterionModel(
                id: item.criterion.id,
                title: sanitizeDomainText(item.criterion.description, fallback: "Criterio"),
                weightText: IosFormatting.decimal(from: item.criterion.weight),
                levels: item.levels.map { level in
                    "\(sanitizeDomainText(level.name, fallback: "Nivel")) · \(level.points)"
                }
            )
        }
    )
}

private func colorHex(for status: PEMaterialStatus) -> String {
    switch status {
    case .prepared: return "#1976D2"
    case .used: return "#2E7D32"
    case .missing: return "#F57C00"
    case .damaged: return "#C62828"
    case .replenish: return "#6A1B9A"
    }
}

private func generateTeams(
    students: [Student],
    count: Int
) -> [TournamentTeam] {
    let normalizedCount = max(2, count)
    let colors = ["#1E88E5", "#43A047", "#FB8C00", "#8E24AA", "#E53935", "#00897B", "#3949AB", "#F4511E"]
    var buckets = Array(repeating: [Int64](), count: normalizedCount)
    for (index, student) in students.enumerated() {
        buckets[index % normalizedCount].append(student.id)
    }
    return (0..<normalizedCount).map { index in
        TournamentTeam(
            id: UUID(),
            name: "Equipo \(index + 1)",
            colorHex: colors[index % colors.count],
            studentIds: buckets[index]
        )
    }
}

private func normalizedProfiles(
    students: [Student],
    existingProfiles: [TournamentStudentProfile]?
) -> [TournamentStudentProfile] {
    let lookup = Dictionary(uniqueKeysWithValues: (existingProfiles ?? []).map { ($0.id, $0) })
    return students.map { student in
        lookup[student.id] ?? TournamentStudentProfile(id: student.id, level: .balanced, incompatibleStudentIds: [])
    }
}

private func generateBalancedTeams(
    students: [Student],
    count: Int,
    profiles: [TournamentStudentProfile],
    existingTeams: [TournamentTeam] = []
) -> [TournamentTeam] {
    let normalizedCount = max(2, count)
    let colors = ["#1E88E5", "#43A047", "#FB8C00", "#8E24AA", "#E53935", "#00897B", "#3949AB", "#F4511E"]
    let profileLookup = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
    let seededNames = existingTeams.map(\.name)

    var teams: [TournamentTeam] = (0..<normalizedCount).map { index in
        TournamentTeam(
            id: existingTeams.indices.contains(index) ? existingTeams[index].id : UUID(),
            name: seededNames.indices.contains(index) ? seededNames[index] : "Equipo \(index + 1)",
            colorHex: colors[index % colors.count],
            studentIds: []
        )
    }

    let orderedStudents = students.shuffled().sorted { lhs, rhs in
        let lhsScore = profileLookup[lhs.id]?.level.score ?? 2
        let rhsScore = profileLookup[rhs.id]?.level.score ?? 2
        if lhsScore == rhsScore {
            return lhs.firstName < rhs.firstName
        }
        return lhsScore > rhsScore
    }

    func teamLoad(_ team: TournamentTeam) -> Int {
        team.studentIds.reduce(0) { total, studentId in
            total + (profileLookup[studentId]?.level.score ?? 2)
        }
    }

    for student in orderedStudents {
        let profile = profileLookup[student.id] ?? TournamentStudentProfile(id: student.id, level: .balanced, incompatibleStudentIds: [])
        let preferredIndex = teams.indices.min { lhs, rhs in
            let lhsHasConflict = !Set(teams[lhs].studentIds).isDisjoint(with: profile.incompatibleStudentIds)
            let rhsHasConflict = !Set(teams[rhs].studentIds).isDisjoint(with: profile.incompatibleStudentIds)
            if lhsHasConflict != rhsHasConflict { return !lhsHasConflict }

            let lhsCount = teams[lhs].studentIds.count
            let rhsCount = teams[rhs].studentIds.count
            if lhsCount != rhsCount { return lhsCount < rhsCount }

            let lhsLoad = teamLoad(teams[lhs])
            let rhsLoad = teamLoad(teams[rhs])
            if lhsLoad != rhsLoad { return lhsLoad < rhsLoad }

            return lhs < rhs
        } ?? 0
        teams[preferredIndex].studentIds.append(student.id)
    }

    return teams
}

private func generateTournamentMatches(
    template: TournamentTemplate,
    teams: [TournamentTeam]
) -> [TournamentMatch] {
    switch template {
    case .roundRobin:
        return generateRoundRobinMatches(teams: teams)
    case .knockout:
        return generateKnockoutMatches(teams: teams)
    case .groupsAndKnockout:
        let midpoint = max(1, teams.count / 2)
        let groupA = Array(teams.prefix(midpoint))
        let groupB = Array(teams.dropFirst(midpoint))
        var matches = generateRoundRobinMatches(teams: groupA, phase: "Grupo A")
        matches += generateRoundRobinMatches(teams: groupB, phase: "Grupo B")
        matches.append(
            TournamentMatch(id: UUID(), phase: "Semifinal", round: 1, homeLabel: "1A", awayLabel: "2B", homeTeamId: nil, awayTeamId: nil, homeScore: 0, awayScore: 0, court: "", linkedSessionId: nil)
        )
        matches.append(
            TournamentMatch(id: UUID(), phase: "Semifinal", round: 2, homeLabel: "1B", awayLabel: "2A", homeTeamId: nil, awayTeamId: nil, homeScore: 0, awayScore: 0, court: "", linkedSessionId: nil)
        )
        matches.append(
            TournamentMatch(id: UUID(), phase: "Final", round: 3, homeLabel: "Ganador SF1", awayLabel: "Ganador SF2", homeTeamId: nil, awayTeamId: nil, homeScore: 0, awayScore: 0, court: "", linkedSessionId: nil)
        )
        return matches
    }
}

private func generateRoundRobinMatches(
    teams: [TournamentTeam],
    phase: String = "Liga"
) -> [TournamentMatch] {
    guard teams.count >= 2 else { return [] }
    var matches: [TournamentMatch] = []
    var round = 1
    for homeIndex in teams.indices {
        for awayIndex in teams.indices where awayIndex > homeIndex {
            let home = teams[homeIndex]
            let away = teams[awayIndex]
            matches.append(
                TournamentMatch(
                    id: UUID(),
                    phase: phase,
                    round: round,
                    homeLabel: home.name,
                    awayLabel: away.name,
                    homeTeamId: home.id,
                    awayTeamId: away.id,
                    homeScore: 0,
                    awayScore: 0,
                    court: "",
                    linkedSessionId: nil
                )
            )
            round += 1
        }
    }
    return matches
}

private func generateKnockoutMatches(teams: [TournamentTeam]) -> [TournamentMatch] {
    guard teams.count >= 2 else { return [] }
    var matches: [TournamentMatch] = []
    let orderedTeams = teams
    var round = 1
    var index = 0
    while index < orderedTeams.count {
        let home = orderedTeams[index]
        let away = index + 1 < orderedTeams.count ? orderedTeams[index + 1] : nil
        matches.append(
            TournamentMatch(
                id: UUID(),
                phase: "Eliminatoria",
                round: round,
                homeLabel: home.name,
                awayLabel: away?.name ?? "BYE",
                homeTeamId: home.id,
                awayTeamId: away?.id,
                homeScore: 0,
                awayScore: 0,
                court: "",
                linkedSessionId: nil
            )
        )
        round += 1
        index += 2
    }
    if matches.count > 1 {
        matches.append(
            TournamentMatch(
                id: UUID(),
                phase: "Final",
                round: round,
                homeLabel: "Ganador \(matches.first?.homeLabel ?? "A")",
                awayLabel: "Ganador \(matches.dropFirst().first?.homeLabel ?? "B")",
                homeTeamId: nil,
                awayTeamId: nil,
                homeScore: 0,
                awayScore: 0,
                court: "",
                linkedSessionId: nil
            )
        )
    }
    return matches
}

private func syncTournamentMatchLabels(_ tournament: inout TournamentViewState) {
    let lookup = Dictionary(uniqueKeysWithValues: tournament.teams.map { ($0.id, $0.name) })
    for index in tournament.matches.indices {
        if let homeId = tournament.matches[index].homeTeamId, let homeName = lookup[homeId] {
            tournament.matches[index].homeLabel = homeName
        }
        if let awayId = tournament.matches[index].awayTeamId, let awayName = lookup[awayId] {
            tournament.matches[index].awayLabel = awayName
        }
    }
}

private struct WorkspaceCompactStat: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct WorkspaceTag: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            HStack(spacing: spacing) {
                content
            }
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkspaceActionRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct WorkspaceEmptyState: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 42, weight: .thin))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 24, weight: .black, design: .rounded))
            Text(subtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct CreateCourseSheet: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var course = "3"
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre del curso", text: $name)
                TextField("Curso", text: $course)
                    .appKeyboardType(.numberPad)
            }
            .navigationTitle("Nueva clase")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") {
                        onDismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") {
                        Task {
                            guard let numericCourse = Int32(course), !name.isEmpty else { return }
                            _ = try? await bridge.createClass(name: name, course: numericCourse)
                            onDismiss()
                            dismiss()
                        }
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}

private struct CreateStudentSheet: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    let defaultClassId: Int64?
    let onDismiss: () -> Void
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var isInjured = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre", text: $firstName)
                TextField("Apellidos", text: $lastName)
                Toggle("Seguimiento físico activo", isOn: $isInjured)
            }
            .navigationTitle("Nuevo alumno")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") {
                        onDismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") {
                        Task {
                            if bridge.selectedStudentsClassId != defaultClassId {
                                await bridge.selectStudentsClass(classId: defaultClassId)
                            }
                            try? await bridge.createStudentInSelectedClass(firstName: firstName, lastName: lastName, isInjured: isInjured)
                            onDismiss()
                            dismiss()
                        }
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}

private struct CreateEvaluationSheet: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    let defaultClassId: Int64?
    let onDismiss: () -> Void
    @State private var code = ""
    @State private var name = ""
    @State private var type = "Rúbrica"
    @State private var weight = "1.0"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Código", text: $code)
                TextField("Nombre", text: $name)
                TextField("Tipo", text: $type)
                TextField("Peso", text: $weight)
                    .appKeyboardType(.decimalPad)
            }
            .navigationTitle("Nueva evaluación")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") {
                        onDismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") {
                        Task {
                            guard let defaultClassId, let numericWeight = Double(weight), !code.isEmpty, !name.isEmpty else { return }
                            try? await bridge.createEvaluation(classId: defaultClassId, code: code, name: name, type: type, weight: numericWeight)
                            onDismiss()
                            dismiss()
                        }
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}

private struct CreatePESessionSheet: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    let defaultClassId: Int64?
    let onDismiss: () -> Void

    @State private var title = ""
    @State private var objectives = ""
    @State private var activities = ""
    @State private var scheduledSpace = ""
    @State private var usedSpace = ""
    @State private var materialToPrepare = ""
    @State private var sessionDate = Date()
    @State private var period = 1
    @State private var status: SessionStatus = .planned

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre de la sesión", text: $title)
                TextField("Objetivos", text: $objectives, axis: .vertical)
                TextField("Actividades", text: $activities, axis: .vertical)
                TextField("Espacio previsto", text: $scheduledSpace)
                TextField("Espacio usado", text: $usedSpace)
                TextField("Material a preparar", text: $materialToPrepare, axis: .vertical)
                DatePicker("Fecha", selection: $sessionDate, displayedComponents: .date)
                Stepper("Periodo \(period)", value: $period, in: 1...8)
                Picker("Estado", selection: $status) {
                    Text("Planificada").tag(SessionStatus.planned)
                    Text("Activa").tag(SessionStatus.inProgress)
                    Text("Cerrada").tag(SessionStatus.completed)
                }
            }
            .navigationTitle("Nueva sesión EF")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") {
                        onDismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") {
                        Task {
                            guard let defaultClassId, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            let isoCalendar = Calendar(identifier: .iso8601)
                            let isoWeekday = ((isoCalendar.component(.weekday, from: sessionDate) + 5) % 7) + 1
                            _ = try? await bridge.createPESession(
                                classId: defaultClassId,
                                title: title,
                                dayOfWeek: isoWeekday,
                                period: period,
                                weekNumber: isoCalendar.component(.weekOfYear, from: sessionDate),
                                year: isoCalendar.component(.yearForWeekOfYear, from: sessionDate),
                                objectives: objectives,
                                activities: activities,
                                status: status,
                                scheduledSpace: scheduledSpace,
                                usedSpace: usedSpace,
                                materialToPrepare: materialToPrepare
                            )
                            onDismiss()
                            dismiss()
                        }
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}

private struct EditPESessionOperationalSheet: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    let snapshot: KmpBridge.PESessionSnapshot
    let onDismiss: () -> Void

    @State private var scheduledSpace = ""
    @State private var usedSpace = ""
    @State private var materialToPrepare = ""
    @State private var materialUsed = ""
    @State private var injuries = ""
    @State private var unequipped = ""
    @State private var intensity = 0
    @State private var stationObservations = ""
    @State private var physicalIncidents = ""
    @State private var journalStatus: SessionJournalStatus = .draft

    var body: some View {
        NavigationStack {
            Form {
                TextField("Espacio previsto", text: $scheduledSpace)
                TextField("Espacio usado", text: $usedSpace)
                TextField("Material a preparar", text: $materialToPrepare, axis: .vertical)
                TextField("Material usado", text: $materialUsed, axis: .vertical)
                TextField("Lesiones", text: $injuries, axis: .vertical)
                TextField("Sin equipación", text: $unequipped, axis: .vertical)
                Stepper("Intensidad \(intensity)/5", value: $intensity, in: 0...5)
                TextField("Observaciones por estaciones", text: $stationObservations, axis: .vertical)
                TextField("Incidencias físicas", text: $physicalIncidents, axis: .vertical)
                Picker("Estado de diario", selection: $journalStatus) {
                    Text("Vacío").tag(SessionJournalStatus.empty)
                    Text("Borrador").tag(SessionJournalStatus.draft)
                    Text("Completado").tag(SessionJournalStatus.completed)
                }
            }
            .navigationTitle("Operativa sesión EF")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") {
                        Task {
                            try? await bridge.savePESessionOperationalData(
                                sessionId: snapshot.id,
                                scheduledSpace: scheduledSpace,
                                usedSpace: usedSpace,
                                materialToPrepare: materialToPrepare,
                                materialUsed: materialUsed,
                                injuries: injuries,
                                unequippedStudents: unequipped,
                                intensityScore: intensity,
                                stationObservations: stationObservations,
                                physicalIncidents: physicalIncidents,
                                journalStatus: journalStatus
                            )
                            onDismiss()
                            dismiss()
                        }
                    }
                    .fontWeight(.bold)
                }
            }
            .task {
                materialToPrepare = snapshot.materialToPrepareText
                materialUsed = snapshot.materialUsedText
                injuries = snapshot.injuriesText
                unequipped = snapshot.unequippedStudentsText
                intensity = snapshot.intensityScore
                stationObservations = snapshot.stationObservationsText
                physicalIncidents = snapshot.physicalIncidentsText
                journalStatus = snapshot.summary?.status ?? .draft
            }
        }
    }
}

private struct CreatePhysicalTestSheet: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    let defaultClassId: Int64?
    let onDismiss: () -> Void

    @State private var code = ""
    @State private var name = ""
    @State private var kind = "Tiempo"
    @State private var weight = "1.0"
    @State private var description = ""

    private let templates = ["Tiempo", "Distancia", "Repeticiones", "Resistencia", "Flexibilidad"]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Tipo", selection: $kind) {
                    ForEach(templates, id: \.self) { template in
                        Text(template).tag(template)
                    }
                }
                TextField("Código", text: $code)
                TextField("Nombre", text: $name)
                TextField("Peso", text: $weight)
                    .appKeyboardType(.decimalPad)
                TextField("Descripción", text: $description, axis: .vertical)
            }
            .navigationTitle("Nueva prueba física")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") {
                        onDismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") {
                        Task {
                            guard let defaultClassId, let numericWeight = Double(weight), !code.isEmpty, !name.isEmpty else { return }
                            try? await bridge.createPhysicalTest(
                                classId: defaultClassId,
                                code: code,
                                name: name,
                                kind: kind,
                                weight: numericWeight,
                                description: description.nilIfBlank
                            )
                            onDismiss()
                            dismiss()
                        }
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}

private struct CreatePEIncidentSheet: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    let defaultClassId: Int64?
    let onSaved: (Int64, String, PEIncidentWorkflowState, Int64?, String) -> Void

    @State private var title = ""
    @State private var detail = ""
    @State private var category = "Lesión"
    @State private var severity = "medium"
    @State private var workflowState: PEIncidentWorkflowState = .open
    @State private var selectedStudentId: Int64?
    @State private var selectedSessionId: Int64?
    @State private var followUpNote = ""
    @State private var sessions: [KmpBridge.PESessionSnapshot] = []

    private let categories = ["Lesión", "Seguridad", "Conducta", "Material", "Equipación"]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Categoría", selection: $category) {
                    ForEach(categories, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }
                TextField("Título", text: $title)
                TextField("Detalle", text: $detail, axis: .vertical)
                Picker("Severidad", selection: $severity) {
                    Text("Baja").tag("low")
                    Text("Media").tag("medium")
                    Text("Alta").tag("high")
                    Text("Crítica").tag("critical")
                }
                Picker("Estado", selection: $workflowState) {
                    ForEach(PEIncidentWorkflowState.allCases) { state in
                        Text(state.rawValue).tag(state)
                    }
                }
                Picker("Alumno", selection: $selectedStudentId) {
                    Text("Sin alumno").tag(Int64?.none)
                    ForEach(bridge.studentsInClass, id: \.id) { student in
                        Text("\(student.firstName) \(student.lastName)").tag(Optional(student.id))
                    }
                }
                Picker("Sesión", selection: $selectedSessionId) {
                    Text("Sin sesión").tag(Int64?.none)
                    ForEach(sessions, id: \.id) { session in
                        Text(session.session.teachingUnitName).tag(Optional(session.id))
                    }
                }
                TextField("Nota de seguimiento", text: $followUpNote, axis: .vertical)
            }
            .navigationTitle("Nueva incidencia EF")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") {
                        Task {
                            guard let defaultClassId, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            let finalTitle = "\(category) · \(title)"
                            let finalDetail = [
                                detail,
                                selectedSessionId == nil ? nil : "Sesión vinculada #\(selectedSessionId!)",
                                followUpNote.nilIfBlank.map { "Seguimiento inicial: \($0)" }
                            ].compactMap { $0?.nilIfBlank }.joined(separator: "\n")
                            if let incidentId = try? await bridge.createIncident(
                                classId: defaultClassId,
                                studentId: selectedStudentId,
                                title: finalTitle,
                                detail: finalDetail,
                                severity: severity
                            ) {
                                onSaved(incidentId, category, workflowState, selectedSessionId, followUpNote)
                                dismiss()
                            }
                        }
                    }
                    .fontWeight(.bold)
                }
            }
            .task {
                await bridge.selectStudentsClass(classId: defaultClassId)
                let calendar = Calendar(identifier: .iso8601)
                sessions = (try? await bridge.loadPESessions(
                    weekNumber: calendar.component(.weekOfYear, from: Date()),
                    year: calendar.component(.yearForWeekOfYear, from: Date()),
                    classId: defaultClassId
                )) ?? []
            }
        }
    }
}

private struct CreatePEMaterialRecordSheet: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    let defaultClassId: Int64?
    let sessions: [KmpBridge.PESessionSnapshot]
    let onSaved: (PEMaterialRecord) -> Void

    @State private var itemName = ""
    @State private var quantity = 1
    @State private var status: PEMaterialStatus = .prepared
    @State private var note = ""
    @State private var selectedSessionId: Int64?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Material", text: $itemName)
                Stepper("Cantidad \(quantity)", value: $quantity, in: 1...100)
                Picker("Estado", selection: $status) {
                    ForEach(PEMaterialStatus.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                Picker("Sesión", selection: $selectedSessionId) {
                    Text("Sin sesión").tag(Int64?.none)
                    ForEach(sessions, id: \.id) { session in
                        Text(session.session.teachingUnitName).tag(Optional(session.id))
                    }
                }
                TextField("Nota", text: $note, axis: .vertical)
            }
            .navigationTitle("Nuevo material")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") {
                        Task {
                            guard let defaultClassId, !itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            let record = PEMaterialRecord(
                                id: UUID(),
                                classId: defaultClassId,
                                sessionId: selectedSessionId,
                                itemName: itemName,
                                quantity: quantity,
                                status: status,
                                note: note,
                                createdAt: Date()
                            )
                            if let session = sessions.first(where: { $0.id == selectedSessionId }) {
                                let materialLine = "\(itemName) x\(quantity)" + (note.nilIfBlank.map { " (\($0))" } ?? "")
                                let prepared = status == .prepared ? materialLine : session.materialToPrepareText
                                let used = status == .used ? materialLine : session.materialUsedText
                                try? await bridge.savePESessionOperationalData(
                                    sessionId: session.id,
                                    scheduledSpace: "",
                                    usedSpace: "",
                                    materialToPrepare: prepared,
                                    materialUsed: used,
                                    injuries: session.injuriesText,
                                    unequippedStudents: session.unequippedStudentsText,
                                    intensityScore: session.intensityScore,
                                    stationObservations: session.stationObservationsText,
                                    physicalIncidents: session.physicalIncidentsText,
                                    journalStatus: session.summary?.status ?? .draft
                                )
                            }
                            onSaved(record)
                            dismiss()
                        }
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}

private struct CreateTournamentSheet: View {
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    let defaultClassId: Int64?
    let onSaved: (TournamentViewState) -> Void

    @State private var name = ""
    @State private var sport = "Baloncesto"
    @State private var template: TournamentTemplate = .roundRobin
    @State private var teamCount = 4
    @State private var pointsWin = 3
    @State private var pointsDraw = 1
    @State private var pointsLoss = 0
    @State private var tieBreaker = "Diferencia de tantos"
    @State private var sportOptions: [String] = []
    @State private var tieBreakerOptions: [String] = []
    @State private var showingNewSportAlert = false
    @State private var showingNewTieBreakerAlert = false
    @State private var newSport = ""
    @State private var newTieBreaker = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre del torneo", text: $name)
                Menu {
                    ForEach(sportOptions, id: \.self) { option in
                        Button(option) { sport = option }
                    }
                    Divider()
                    Button("Añadir nueva opción…") {
                        showingNewSportAlert = true
                    }
                } label: {
                    tournamentOptionRow(title: "Deporte / modalidad", value: sport)
                }

                Picker("Plantilla", selection: $template) {
                    ForEach(TournamentTemplate.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }

                Stepper("Equipos \(teamCount)", value: $teamCount, in: 2...8)
                Stepper("Puntos victoria \(pointsWin)", value: $pointsWin, in: 0...10)
                Stepper("Puntos empate \(pointsDraw)", value: $pointsDraw, in: 0...10)
                Stepper("Puntos derrota \(pointsLoss)", value: $pointsLoss, in: 0...10)
                Menu {
                    ForEach(tieBreakerOptions, id: \.self) { option in
                        Button(option) { tieBreaker = option }
                    }
                    Divider()
                    Button("Añadir nueva opción…") {
                        showingNewTieBreakerAlert = true
                    }
                } label: {
                    tournamentOptionRow(title: "Desempate", value: tieBreaker)
                }
            }
            .navigationTitle("Nuevo torneo EF")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Crear") {
                        Task {
                            guard let defaultClassId else { return }
                            await bridge.selectStudentsClass(classId: defaultClassId)
                            let teams = generateTeams(students: bridge.studentsInClass, count: teamCount)
                            let tournament = TournamentViewState(
                                id: UUID(),
                                classId: defaultClassId,
                                name: name.nilIfBlank ?? "Torneo \(sport)",
                                sport: sport,
                                template: template,
                                status: .draft,
                                pointsWin: pointsWin,
                                pointsDraw: pointsDraw,
                                pointsLoss: pointsLoss,
                                tieBreaker: tieBreaker.nilIfBlank ?? "Diferencia de tantos",
                                teams: teams,
                                matches: generateTournamentMatches(template: template, teams: teams),
                                studentProfiles: normalizedProfiles(students: bridge.studentsInClass, existingProfiles: nil),
                                createdAt: Date()
                            )
                            onSaved(tournament)
                            dismiss()
                        }
                    }
                    .fontWeight(.bold)
                }
            }
            .task {
                sportOptions = storedItems(forKey: peTournamentSportsStorageKey, as: String.self)
                if sportOptions.isEmpty {
                    sportOptions = ["Baloncesto", "Fútbol sala", "Balonmano", "Voleibol", "Bádminton"]
                }
                tieBreakerOptions = storedItems(forKey: peTournamentTieBreakersStorageKey, as: String.self)
                if tieBreakerOptions.isEmpty {
                    tieBreakerOptions = ["Diferencia de tantos", "Enfrentamiento directo", "Fair play", "Tantos a favor"]
                }
                if !sportOptions.contains(sport) { sportOptions.append(sport) }
                if !tieBreakerOptions.contains(tieBreaker) { tieBreakerOptions.append(tieBreaker) }
            }
            .alert("Añadir deporte", isPresented: $showingNewSportAlert) {
                TextField("Nuevo deporte", text: $newSport)
                Button("Cancelar", role: .cancel) { newSport = "" }
                Button("Guardar") {
                    guard let option = newSport.nilIfBlank else { return }
                    if !sportOptions.contains(option) {
                        sportOptions.append(option)
                        persistItems(sportOptions, forKey: peTournamentSportsStorageKey)
                    }
                    sport = option
                    newSport = ""
                }
            }
            .alert("Añadir desempate", isPresented: $showingNewTieBreakerAlert) {
                TextField("Nuevo criterio", text: $newTieBreaker)
                Button("Cancelar", role: .cancel) { newTieBreaker = "" }
                Button("Guardar") {
                    guard let option = newTieBreaker.nilIfBlank else { return }
                    if !tieBreakerOptions.contains(option) {
                        tieBreakerOptions.append(option)
                        persistItems(tieBreakerOptions, forKey: peTournamentTieBreakersStorageKey)
                    }
                    tieBreaker = option
                    newTieBreaker = ""
                }
            }
        }
    }

    private func tournamentOptionRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(Color.accentColor)
            Image(systemName: "chevron.up.chevron.down")
                .foregroundStyle(.secondary)
        }
    }
}

private enum TournamentBoardSection: String, CaseIterable, Identifiable {
    case overview = "Resumen"
    case groups = "Grupos"
    case bracket = "Cuadro"
    case teams = "Equipos"

    var id: String { rawValue }
}

private struct TournamentBoardScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Binding var tournament: TournamentViewState
    let classLabel: String
    let students: [Student]

    @State private var section: TournamentBoardSection = .overview
    @State private var showingAutoBalance = false

    private var standings: [(team: TournamentTeam, points: Int, scored: Int, conceded: Int)] {
        computeStandings(matches: tournament.matches, teams: tournament.teams)
    }

    private var groupedStandings: [(String, [(team: TournamentTeam, points: Int, scored: Int, conceded: Int)])] {
        let grouped = Dictionary(grouping: tournament.matches.filter { $0.phase.hasPrefix("Grupo") }) { $0.phase }
        return grouped.keys.sorted().map { key in
            (key, computeStandings(matches: grouped[key] ?? [], teams: tournament.teams))
        }
    }

    private var bracketColumns: [(String, [TournamentMatch])] {
        let eliminationMatches = tournament.matches.filter { !$0.phase.hasPrefix("Grupo") && $0.phase != "Liga" }
        let grouped = Dictionary(grouping: eliminationMatches) { $0.phase }
        return grouped.keys.sorted().map { ($0, (grouped[$0] ?? []).sorted { $0.round < $1.round }) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    WorkspaceInspectorHero(title: tournament.name, subtitle: classLabel)

                    Picker("Vista", selection: $section) {
                        ForEach(TournamentBoardSection.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch section {
                    case .overview:
                        overviewSection
                    case .groups:
                        groupsSection
                    case .bracket:
                        bracketSection
                    case .teams:
                        teamsSection
                    }
                }
                .padding(24)
            }
            .background(appPageBackground(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Progreso del torneo")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Autoequilibrar") { showingAutoBalance = true }
                    Button("Equipos") { section = .teams }
                }
            }
        }
        .sheet(isPresented: $showingAutoBalance) {
            TournamentAutoBalanceSheet(tournament: $tournament, students: students)
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                WorkspaceMetricCard(title: "Clasificación general", value: "\(standings.count)", systemImage: "list.number")
                WorkspaceMetricCard(title: "Plantilla", value: tournament.template.rawValue, systemImage: "square.grid.3x3.fill")
                WorkspaceMetricCard(title: "Equipos", value: "\(tournament.teams.count)", systemImage: "person.3.fill")
                WorkspaceMetricCard(title: "Partidos", value: "\(tournament.matches.count)", systemImage: "sportscourt.fill")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Clasificación general")
                    .font(.headline)
                ForEach(Array(standings.enumerated()), id: \.offset) { index, row in
                    tournamentStandingCard(rank: index + 1, row: row)
                }
            }
        }
    }

    private var groupsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            if groupedStandings.isEmpty {
                WorkspaceEmptyState(title: "Sin fase de grupos", subtitle: "Este torneo no usa clasificación por grupos.")
            } else {
                ForEach(groupedStandings, id: \.0) { group, rows in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group)
                            .font(.title3.weight(.bold))
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            tournamentStandingCard(rank: index + 1, row: row)
                        }
                    }
                }
            }
        }
    }

    private var bracketSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            if bracketColumns.isEmpty {
                WorkspaceEmptyState(title: "Sin cuadro eliminatorio", subtitle: "Este torneo no tiene fase eliminatoria todavía.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(bracketColumns, id: \.0) { phase, matches in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(phase)
                                    .font(.headline)
                                ForEach(matches, id: \.id) { match in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Ronda \(match.round)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.secondary)
                                        tournamentMatchLine(match.homeLabel, score: match.homeScore)
                                        tournamentMatchLine(match.awayLabel, score: match.awayScore)
                                    }
                                    .padding(14)
                                    .frame(width: 220, alignment: .leading)
                                    .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var teamsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Button("Autoequilibrar equipos") {
                    showingAutoBalance = true
                }
                .buttonStyle(.borderedProminent)
                Button("Regenerar partidos") {
                    tournament.matches = generateTournamentMatches(template: tournament.template, teams: tournament.teams)
                    syncTournamentMatchLabels(&tournament)
                }
                .buttonStyle(.bordered)
            }

            ForEach(Array($tournament.teams.enumerated()), id: \.element.id) { index, $team in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("Nombre del equipo", text: $team.name)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: team.name) { _ in
                                syncTournamentMatchLabels(&tournament)
                            }
                        Text("Miembros: \(team.studentIds.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if team.studentIds.isEmpty {
                        Text("Sin alumnado asignado.")
                            .foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(team.studentIds, id: \.self) { studentId in
                                let name = studentName(studentId)
                                Button {
                                    remove(studentId: studentId, fromTeamAt: index)
                                } label: {
                                    Label(name, systemImage: "xmark.circle.fill")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    Menu {
                        ForEach(unassignedOrCurrentStudents(for: team), id: \.id) { student in
                            Button("\(student.firstName) \(student.lastName)") {
                                assign(studentId: student.id, toTeamAt: index)
                            }
                        }
                    } label: {
                        Label("Asignar alumnado", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
                .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func tournamentStandingCard(rank: Int, row: (team: TournamentTeam, points: Int, scored: Int, conceded: Int)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("#\(rank) · \(row.team.name)")
                .font(.headline)
            Text("\(row.points) pts · \(row.scored) a favor · \(row.conceded) en contra")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func tournamentMatchLine(_ title: String, score: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(score)")
                .font(.headline.monospacedDigit())
        }
    }

    private func computeStandings(
        matches: [TournamentMatch],
        teams: [TournamentTeam]
    ) -> [(team: TournamentTeam, points: Int, scored: Int, conceded: Int)] {
        teams.map { team in
            let related = matches.filter { $0.homeTeamId == team.id || $0.awayTeamId == team.id }
            let points = related.reduce(0) { total, match in
                let isHome = match.homeTeamId == team.id
                let scored = isHome ? match.homeScore : match.awayScore
                let conceded = isHome ? match.awayScore : match.homeScore
                if scored > conceded { return total + tournament.pointsWin }
                if scored == conceded { return total + tournament.pointsDraw }
                return total + tournament.pointsLoss
            }
            let scored = related.reduce(0) { partial, match in
                partial + (match.homeTeamId == team.id ? match.homeScore : match.awayTeamId == team.id ? match.awayScore : 0)
            }
            let conceded = related.reduce(0) { partial, match in
                partial + (match.homeTeamId == team.id ? match.awayScore : match.awayTeamId == team.id ? match.homeScore : 0)
            }
            return (team, points, scored, conceded)
        }
        .sorted { lhs, rhs in
            if lhs.points == rhs.points { return lhs.scored > rhs.scored }
            return lhs.points > rhs.points
        }
    }

    private func studentName(_ studentId: Int64) -> String {
        guard let student = students.first(where: { $0.id == studentId }) else { return "Alumno \(studentId)" }
        return "\(student.firstName) \(student.lastName)"
    }

    private func unassignedOrCurrentStudents(for team: TournamentTeam) -> [Student] {
        let assigned = Set(tournament.teams.flatMap(\.studentIds))
        return students.filter { !assigned.contains($0.id) || team.studentIds.contains($0.id) }
    }

    private func assign(studentId: Int64, toTeamAt index: Int) {
        for teamIndex in tournament.teams.indices {
            tournament.teams[teamIndex].studentIds.removeAll { $0 == studentId }
        }
        tournament.teams[index].studentIds.append(studentId)
    }

    private func remove(studentId: Int64, fromTeamAt index: Int) {
        tournament.teams[index].studentIds.removeAll { $0 == studentId }
    }
}

private struct TournamentAutoBalanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var tournament: TournamentViewState
    let students: [Student]

    @State private var profiles: [TournamentStudentProfile] = []
    @State private var teamCount = 4
    @State private var studentA: Int64?
    @State private var studentB: Int64?

    var body: some View {
        NavigationStack {
            Form {
                Section("Configuración") {
                    Stepper("Equipos \(teamCount)", value: $teamCount, in: 2...8)
                }

                Section("Nivel del alumnado") {
                    ForEach($profiles) { $profile in
                        HStack {
                            Text(studentName(profile.id))
                            Spacer()
                            Picker("Nivel", selection: $profile.level) {
                                ForEach(TournamentStudentLevel.allCases) { level in
                                    Text(level.rawValue).tag(level)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }

                Section("Incompatibilidades") {
                    Picker("Alumno A", selection: $studentA) {
                        Text("Selecciona").tag(Int64?.none)
                        ForEach(students, id: \.id) { student in
                            Text("\(student.firstName) \(student.lastName)").tag(Optional(student.id))
                        }
                    }
                    Picker("Alumno B", selection: $studentB) {
                        Text("Selecciona").tag(Int64?.none)
                        ForEach(students, id: \.id) { student in
                            Text("\(student.firstName) \(student.lastName)").tag(Optional(student.id))
                        }
                    }
                    Button("Añadir incompatibilidad") {
                        addIncompatibility()
                    }
                    .disabled(studentA == nil || studentB == nil || studentA == studentB)

                    ForEach(incompatibilityPairs, id: \.id) { pair in
                        HStack {
                            Text(pair.label)
                            Spacer()
                            Button(role: .destructive) {
                                removeIncompatibility(a: pair.a, b: pair.b)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Configurador de equipos")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Generar") {
                        tournament.studentProfiles = profiles
                        tournament.teams = generateBalancedTeams(
                            students: students,
                            count: teamCount,
                            profiles: profiles,
                            existingTeams: tournament.teams
                        )
                        tournament.matches = generateTournamentMatches(template: tournament.template, teams: tournament.teams)
                        syncTournamentMatchLabels(&tournament)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .task {
                profiles = normalizedProfiles(students: students, existingProfiles: tournament.studentProfiles)
                teamCount = max(2, tournament.teams.count)
            }
        }
    }

    private var incompatibilityPairs: [(id: String, a: Int64, b: Int64, label: String)] {
        var seen = Set<String>()
        var result: [(id: String, a: Int64, b: Int64, label: String)] = []
        for profile in profiles {
            for incompatible in profile.incompatibleStudentIds {
                let sorted = [profile.id, incompatible].sorted()
                let key = "\(sorted[0])-\(sorted[1])"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                result.append((key, sorted[0], sorted[1], "\(studentName(sorted[0])) / \(studentName(sorted[1]))"))
            }
        }
        return result.sorted { $0.label < $1.label }
    }

    private func addIncompatibility() {
        guard let studentA, let studentB, studentA != studentB else { return }
        updateProfile(studentA) { profile in
            if !profile.incompatibleStudentIds.contains(studentB) {
                profile.incompatibleStudentIds.append(studentB)
            }
        }
        updateProfile(studentB) { profile in
            if !profile.incompatibleStudentIds.contains(studentA) {
                profile.incompatibleStudentIds.append(studentA)
            }
        }
        self.studentA = nil
        self.studentB = nil
    }

    private func removeIncompatibility(a: Int64, b: Int64) {
        updateProfile(a) { profile in
            profile.incompatibleStudentIds.removeAll { $0 == b }
        }
        updateProfile(b) { profile in
            profile.incompatibleStudentIds.removeAll { $0 == a }
        }
    }

    private func updateProfile(_ id: Int64, mutate: (inout TournamentStudentProfile) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        mutate(&profiles[index])
    }

    private func studentName(_ id: Int64) -> String {
        guard let student = students.first(where: { $0.id == id }) else { return "Alumno \(id)" }
        return "\(student.firstName) \(student.lastName)"
    }
}

private extension Date {
    var stripTime: Date {
        Calendar.current.startOfDay(for: self)
    }
}

private struct ContextualAIAssistantSheet: View {
    let module: AppWorkspaceModule
    let context: KmpBridge.ScreenAIContext

    @Environment(\.dismiss) private var dismiss
    @State private var selectedAction: KmpBridge.ContextualAIAction?
    @State private var audience: AIReportAudience = .docente
    @State private var tone: AIReportTone = .claro
    @State private var customPrompt = ""
    @State private var result: ContextualAIResult?
    @State private var editableText = ""
    @State private var isGenerating = false
    @State private var feedbackMessage: String?

    private let aiService = AppleFoundationContextualAIService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    availabilityCard
                    actionCard
                    resultCard
                }
                .padding(24)
            }
            .background(EvaluationBackdrop())
            .navigationTitle("IA contextual")
            .appInlineNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .onAppear {
                aiService.prewarm()
                selectedAction = context.suggestedActions.first
            }
        }
    }

    private var availabilityCard: some View {
        let availability = aiService.currentAvailability()
        return EvaluationGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(module.title, systemImage: module.systemImage)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(context.title)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                Text(context.subtitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(context.summary)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                Text(availability.message)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(availability.isAvailable ? NotebookStyle.successTint : NotebookStyle.warningTint)

                if !context.metrics.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                        ForEach(context.metrics) { metric in
                            VStack(alignment: .leading, spacing: 6) {
                                Label(metric.title, systemImage: metric.systemImage)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Text(metric.value)
                                    .font(.system(size: 18, weight: .black, design: .rounded))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private var actionCard: some View {
        EvaluationGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Acciones sugeridas")
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                if context.suggestedActions.isEmpty {
                    Text(context.dataQualityNote ?? "Esta pantalla todavía no tiene acciones IA disponibles.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(context.suggestedActions) { action in
                        Button {
                            selectedAction = action
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: action.systemImage)
                                    .foregroundStyle(selectedAction == action ? NotebookStyle.primaryTint : .secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(action.title)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(.primary)
                                    Text(action.subtitle)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedAction == action {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(NotebookStyle.primaryTint)
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(selectedAction == action ? NotebookStyle.primaryTint.opacity(0.10) : NotebookStyle.surface)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Picker("Audiencia", selection: $audience) {
                        ForEach(AIReportAudience.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Tono", selection: $tone) {
                        ForEach(AIReportTone.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Variación opcional")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        TextField("Ej. más breve, más orientado a familia, foco en próximos pasos…", text: $customPrompt, axis: .vertical)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }

                    if let feedbackMessage {
                        Text(feedbackMessage)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotebookStyle.warningTint)
                    }

                    Button {
                        generate()
                    } label: {
                        if isGenerating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Generar ayuda contextual", systemImage: "apple.intelligence")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!context.hasEnoughData || selectedAction == nil || isGenerating || !aiService.currentAvailability().isAvailable)
                }
            }
        }
    }

    private var resultCard: some View {
        EvaluationGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Resultado")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Spacer()
                    if !editableText.isEmpty {
                        ShareLink(item: editableText) {
                            Label("Compartir", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Text("Borrador generado por IA. Revisión docente obligatoria.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                if editableText.isEmpty {
                    Text("Selecciona una acción y genera un borrador contextual para esta pantalla.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    TextEditor(text: $editableText)
                        .frame(minHeight: 220)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(NotebookStyle.surface)
                        )
                }
            }
        }
    }

    private func generate() {
        guard let selectedAction else { return }
        isGenerating = true
        feedbackMessage = nil
        Task {
            do {
                let generated = try await aiService.generateResult(
                    from: context,
                    action: selectedAction,
                    audience: audience,
                    tone: tone,
                    customPrompt: customPrompt.nilIfBlank
                )
                await MainActor.run {
                    result = generated
                    editableText = generated.editableText
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    feedbackMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
