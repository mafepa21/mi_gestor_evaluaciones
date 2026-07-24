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
    @Published var notebookHiddenColumnsRequestID: UUID?
    @Published var notebookSearchText: String = ""
    @Published var notebookSurfaceMode: String = "grid"
    @Published var notebookSelectedGroupId: Int64? = nil
    @Published var notebookAvailableGroups: [NotebookToolbarGroupOption] = []
    @Published var notebookCanUndo: Bool = false
    @Published var notebookIsAttendanceQuickMode: Bool = false
    @Published var notebookCanMarkAllPresent: Bool = false
    @Published var notebookExportText: String? = nil
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
    @Published var attendanceSessions: [KmpBridge.AttendanceSessionSnapshot] = []
    @Published var attendanceSelectedSessionId: Int64? = nil

    var notebookInspectorAction: (() -> Void)?
    var notebookAddColumnAction: (() -> Void)?
    var notebookSearchAction: ((String) -> Void)?
    var notebookSurfaceModeAction: ((String) -> Void)?
    var notebookGroupFilterAction: ((Int64?) -> Void)?
    var notebookOrganizationMenuAction: (() -> Void)?
    var notebookUndoAction: (() -> Void)?
    var notebookToggleAttendanceQuickModeAction: (() -> Void)?
    var notebookMarkAllPresentAction: (() -> Void)?
    var notebookRefreshAction: (() -> Void)?
    var notebookGenerateSummaryAction: (() -> Void)?

    var dashboardInspectorAction: (() -> Void)?
    var dashboardRefreshAction: (() -> Void)?
    var dashboardPassListAction: (() -> Void)?
    var dashboardObservationAction: (() -> Void)?
    var dashboardQuickEvaluationAction: (() -> Void)?
    var diaryInspectorAction: (() -> Void)?
    var plannerAddSessionAction: (() -> Void)?
    var attendanceSearchAction: ((String) -> Void)?
    var attendanceDateAction: ((Date) -> Void)?
    var attendanceBoardModeAction: ((String) -> Void)?
    var attendanceStatusFilterAction: ((String) -> Void)?
    var attendanceMarkAllPresentAction: (() -> Void)?
    var attendanceRepeatPatternAction: (() -> Void)?
    var attendanceClearSelectionAction: (() -> Void)?
    var attendanceSessionAction: ((Int64) -> Void)?

    func publishDeferred(_ mutation: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            await Task.yield()
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
        canUndo: Bool = false,
        isAttendanceQuickMode: Bool = false,
        canMarkAllPresent: Bool = false,
        exportText: String? = nil,
        onToggleInspector: @escaping () -> Void,
        onAddColumn: @escaping () -> Void,
        onSearchChange: @escaping (String) -> Void,
        onSurfaceModeChange: @escaping (String) -> Void,
        onGroupFilterChange: @escaping (Int64?) -> Void,
        onOpenOrganizationMenu: @escaping () -> Void,
        onUndo: (() -> Void)? = nil,
        onToggleAttendanceQuickMode: (() -> Void)? = nil,
        onMarkAllPresent: (() -> Void)? = nil,
        onRefresh: (() -> Void)? = nil,
        onGenerateSummary: (() -> Void)? = nil
    ) {
        publishDeferred {
            self.notebookInspectorAvailable = inspectorAvailable
            self.isNotebookInspectorPresented = isInspectorPresented
            self.notebookAddColumnAvailable = addColumnAvailable
            if self.notebookSearchText != searchText {
                self.notebookSearchText = searchText
            }
            self.notebookSurfaceMode = surfaceMode
            self.notebookSelectedGroupId = selectedGroupId
            self.notebookAvailableGroups = availableGroups
            self.notebookOrganizationMenuAvailable = organizationMenuAvailable
            self.notebookCanUndo = canUndo
            self.notebookIsAttendanceQuickMode = isAttendanceQuickMode
            self.notebookCanMarkAllPresent = canMarkAllPresent
            self.notebookExportText = exportText
            self.notebookInspectorAction = onToggleInspector
            self.notebookAddColumnAction = onAddColumn
            self.notebookSearchAction = onSearchChange
            self.notebookSurfaceModeAction = onSurfaceModeChange
            self.notebookGroupFilterAction = onGroupFilterChange
            self.notebookOrganizationMenuAction = onOpenOrganizationMenu
            self.notebookUndoAction = onUndo
            self.notebookToggleAttendanceQuickModeAction = onToggleAttendanceQuickMode
            self.notebookMarkAllPresentAction = onMarkAllPresent
            self.notebookRefreshAction = onRefresh
            self.notebookGenerateSummaryAction = onGenerateSummary
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
        organizationMenuAvailable: Bool,
        canUndo: Bool = false,
        isAttendanceQuickMode: Bool = false,
        canMarkAllPresent: Bool = false,
        exportText: String? = nil
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
            self.notebookCanUndo = canUndo
            self.notebookIsAttendanceQuickMode = isAttendanceQuickMode
            self.notebookCanMarkAllPresent = canMarkAllPresent
            self.notebookExportText = exportText
        }
    }

    func clearNotebookToolbar() {
        publishDeferred {
            self.notebookInspectorAvailable = false
            self.isNotebookInspectorPresented = false
            self.notebookAddColumnAvailable = false
            self.notebookOrganizationMenuAvailable = false
            self.notebookHiddenColumnsRequestID = nil
            self.notebookSearchText = ""
            self.notebookSurfaceMode = "grid"
            self.notebookSelectedGroupId = nil
            self.notebookAvailableGroups = []
            self.notebookCanUndo = false
            self.notebookIsAttendanceQuickMode = false
            self.notebookCanMarkAllPresent = false
            self.notebookExportText = nil
            self.notebookInspectorAction = nil
            self.notebookAddColumnAction = nil
            self.notebookSearchAction = nil
            self.notebookSurfaceModeAction = nil
            self.notebookGroupFilterAction = nil
            self.notebookOrganizationMenuAction = nil
            self.notebookUndoAction = nil
            self.notebookToggleAttendanceQuickModeAction = nil
            self.notebookMarkAllPresentAction = nil
            self.notebookRefreshAction = nil
            self.notebookGenerateSummaryAction = nil
        }
    }

    func toggleNotebookInspector() {
        notebookInspectorAction?()
    }

    func showNotebookAddColumn() {
        notebookAddColumnAction?()
    }

    func notebookUndo() {
        notebookUndoAction?()
    }

    func notebookToggleAttendanceQuickMode() {
        notebookToggleAttendanceQuickModeAction?()
    }

    func notebookMarkAllPresent() {
        notebookMarkAllPresentAction?()
    }

    func notebookRefresh() {
        notebookRefreshAction?()
    }

    func notebookGenerateSummary() {
        notebookGenerateSummaryAction?()
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

    func openNotebookHiddenColumns() {
        notebookHiddenColumnsRequestID = UUID()
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
        sessions: [KmpBridge.AttendanceSessionSnapshot] = [],
        selectedSessionId: Int64? = nil,
        onSearchTextChange: @escaping (String) -> Void,
        onDateChange: @escaping (Date) -> Void,
        onBoardModeChange: @escaping (String) -> Void,
        onStatusFilterChange: @escaping (String) -> Void,
        onMarkAllPresent: @escaping () -> Void,
        onRepeatPattern: @escaping () -> Void,
        onClearSelection: @escaping () -> Void,
        onSessionChange: ((Int64) -> Void)? = nil
    ) {
        publishDeferred {
            self.attendanceToolbarAvailable = true
            self.attendanceSearchText = searchText
            self.attendanceSelectedDate = selectedDate
            self.attendanceBoardMode = boardMode
            self.attendanceSelectedStatusFilter = selectedStatusFilter
            self.attendanceHasSelection = hasSelection
            self.attendanceSessions = sessions
            self.attendanceSelectedSessionId = selectedSessionId
            self.attendanceSearchAction = onSearchTextChange
            self.attendanceDateAction = onDateChange
            self.attendanceBoardModeAction = onBoardModeChange
            self.attendanceStatusFilterAction = onStatusFilterChange
            self.attendanceMarkAllPresentAction = onMarkAllPresent
            self.attendanceRepeatPatternAction = onRepeatPattern
            self.attendanceClearSelectionAction = onClearSelection
            self.attendanceSessionAction = onSessionChange
        }
    }

    func updateAttendanceToolbar(
        searchText: String,
        selectedDate: Date,
        boardMode: String,
        selectedStatusFilter: String,
        hasSelection: Bool,
        sessions: [KmpBridge.AttendanceSessionSnapshot] = [],
        selectedSessionId: Int64? = nil
    ) {
        publishDeferred {
            self.attendanceToolbarAvailable = true
            self.attendanceSearchText = searchText
            self.attendanceSelectedDate = selectedDate
            self.attendanceBoardMode = boardMode
            self.attendanceSelectedStatusFilter = selectedStatusFilter
            self.attendanceHasSelection = hasSelection
            self.attendanceSessions = sessions
            self.attendanceSelectedSessionId = selectedSessionId
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
            self.attendanceSessions = []
            self.attendanceSelectedSessionId = nil
            self.attendanceSearchAction = nil
            self.attendanceDateAction = nil
            self.attendanceBoardModeAction = nil
            self.attendanceStatusFilterAction = nil
            self.attendanceMarkAllPresentAction = nil
            self.attendanceRepeatPatternAction = nil
            self.attendanceClearSelectionAction = nil
            self.attendanceSessionAction = nil
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

    func setAttendanceSessionId(_ value: Int64) {
        attendanceSelectedSessionId = value
        attendanceSessionAction?(value)
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
    case domainModules = "Módulos de dominio"
    case system = "Sistema"

    var id: String { rawValue }
}

enum AppWorkspaceModule: String, CaseIterable, Identifiable {
    case dashboard
    case courses
    case students
    case teacherRadar
    case notebook
    case attendance
    case planner
    case situations
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
    case backups

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .courses: return "Cursos"
        case .students: return "Alumnado"
        case .teacherRadar: return "Radar"
        case .notebook: return "Cuaderno"
        case .attendance: return "Asistencia"
        case .planner: return "Planner"
        case .situations: return "Situaciones"
        case .diary: return "Diario de aula"
        case .evaluationHub: return "Evaluación"
        case .rubrics: return "Rúbricas"
        case .reports: return "Informes"
        case .library: return "Biblioteca"
        case .peSessions: return "Sesiones prácticas"
        case .peTests: return "EF · Condición física"
        case .peRubrics: return "Rúbricas por área"
        case .peIncidents: return "Incidencias y seguridad"
        case .peMaterial: return "Recursos y material"
        case .peTournaments: return "Retos y torneos"
        case .settings: return "Ajustes"
        case .backups: return "Seguridad"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: return "Visión operativa"
        case .courses: return "Gestión de grupos"
        case .students: return "Perfiles y seguimiento"
        case .teacherRadar: return "Alertas docentes"
        case .notebook: return "Registro evaluativo"
        case .attendance: return "Control diario y semanal"
        case .planner: return "Preparación lectiva"
        case .situations: return "Programación curricular"
        case .diary: return "Trazabilidad de sesión"
        case .evaluationHub: return "Instrumentos y calendario"
        case .rubrics: return "Banco de rúbricas"
        case .reports: return "Salida docente"
        case .library: return "Plantillas reutilizables"
        case .peSessions: return "Operativa de actividades"
        case .peTests: return "Progreso, marcas e históricos"
        case .peRubrics: return "Criterios específicos"
        case .peIncidents: return "Seguimiento operativo"
        case .peMaterial: return "Inventario rápido"
        case .peTournaments: return "Competición y resultados"
        case .settings: return "Configuración"
        case .backups: return "Copias y restauración"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .courses: return "rectangle.3.group.bubble.left.fill"
        case .students: return "person.3.fill"
        case .teacherRadar: return "scope"
        case .notebook: return "book.closed.fill"
        case .attendance: return "checklist.checked"
        case .planner: return "calendar.badge.clock"
        case .situations: return "doc.text.magnifyingglass"
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
        case .backups: return "lock.shield.fill"
        }
    }

    var section: AppWorkspaceSection {
        switch self {
        case .dashboard, .courses, .students, .teacherRadar, .notebook:
            return .academic
        case .attendance, .planner, .situations, .diary:
            return .operations
        case .evaluationHub, .rubrics, .reports, .library:
            return .evaluation
        case .peSessions, .peTests, .peRubrics, .peIncidents, .peMaterial, .peTournaments:
            return .domainModules
        case .settings, .backups:
            return .system
        }
    }

    var requiresPhysicalEducationProfile: Bool {
        switch self {
        case .peSessions, .peTests, .peRubrics, .peIncidents, .peMaterial, .peTournaments:
            return true
        default:
            return false
        }
    }
}

enum WorkspaceCreateSheet: String, Identifiable {
    case course
    case student
    case evaluation

    var id: String { rawValue }
}

struct WorkspaceSearchResult: Identifiable {
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

struct ContextualAISheetState: Identifiable {
    let module: AppWorkspaceModule
    let context: KmpBridge.ScreenAIContext

    var id: String {
        "\(module.rawValue)|\(context.kind.rawValue)|\(context.classId ?? -1)|\(context.studentId ?? -1)"
    }
}

enum ClassroomCaptureSheet: Identifiable {
    case quickNote
    case observation
    case injury

    var id: String {
        switch self {
        case .quickNote: return "quickNote"
        case .observation: return "observation"
        case .injury: return "injury"
        }
    }
}

enum ActiveWorkspaceSheet: Identifiable {
    case create(WorkspaceCreateSheet)
    case contextualAI(ContextualAISheetState)
    case classroomCapture(ClassroomCaptureSheet)
    case bulkRubricEvaluation

    var id: String {
        switch self {
        case .create(let sheet): return "create_\(sheet.id)"
        case .contextualAI(let state): return "contextualAI_\(state.id)"
        case .classroomCapture(let sheet): return "classroomCapture_\(sheet.id)"
        case .bulkRubricEvaluation: return "bulkRubricEvaluation"
        }
    }
}

struct AppWorkspaceShell: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) var colorScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    @AppStorage("workspace.active.module") var persistedActiveModule = AppWorkspaceModule.dashboard.rawValue
    @AppStorage("workspace.selected.class.id") var persistedSelectedClassId: Int = 0
    @AppStorage("workspace.selected.student.id") var persistedSelectedStudentId: Int = 0
    @State var activeModule: AppWorkspaceModule = .dashboard
    @State var searchText = ""
    @State var selectedClassId: Int64? = nil
    @State var selectedStudentId: Int64? = nil
    @State var plannerContext = PlannerNavigationContext()
    @State var activeWorkspaceSheet: ActiveWorkspaceSheet?
    var createSheet: WorkspaceCreateSheet? {
        get {
            if case .create(let s) = activeWorkspaceSheet { return s }
            return nil
        }
        nonmutating set {
            activeWorkspaceSheet = newValue.map { .create($0) }
        }
    }
    @State var showingRubricBuilder = false
    @StateObject var layoutState = WorkspaceLayoutState()
    @StateObject var notebookStore = NotebookBridgeStore()
    @StateObject var dashboardStore = DashboardBridgeStore()
    @StateObject var studentsBridgeStore = StudentsBridgeStore()
    @StateObject var attendanceStore = AttendanceBridgeStore()
    @State var rootSplitVisibility: NavigationSplitViewVisibility = .all
    @State var debouncedSearchText = ""
    var contextualAISheetState: ContextualAISheetState? {
        get {
            if case .contextualAI(let s) = activeWorkspaceSheet { return s }
            return nil
        }
        nonmutating set {
            activeWorkspaceSheet = newValue.map { .contextualAI($0) }
        }
    }
    @State var isLoadingContextualAI = false
    @State var classroomContext: KmpBridge.ClassroomCaptureContextSnapshot?
    var classroomCaptureSheet: ClassroomCaptureSheet? {
        get {
            if case .classroomCapture(let s) = activeWorkspaceSheet { return s }
            return nil
        }
        nonmutating set {
            activeWorkspaceSheet = newValue.map { .classroomCapture($0) }
        }
    }
    @State var classroomCaptureStudentId: Int64?
    @State var classroomCaptureText = ""
    @State var isSavingClassroomCapture = false
    @State private var isClassPickerPresented = false
    @State private var isSearchPresented = false

    var activeNotebookClassLabel: String {
        guard let selectedClassId,
              let schoolClass = bridge.classes.first(where: { $0.id == selectedClassId })
        else { return "Seleccionar clase" }
        return "\(schoolClass.name) · \(schoolClass.course)º"
    }

    var groupedNotebookClasses: [(course: Int32, classes: [SchoolClass])] {
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

    var searchResults: [WorkspaceSearchResult] {
        let query = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        let enabledProfiles = TeacherSubjectProfile.decodeSet(UserDefaults.standard.string(forKey: "teacher.enabledSubjectProfiles.v1") ?? TeacherSubjectProfile.general.rawValue)
        let moduleResults = IOSFeatureRegistry.all(enabledProfiles: enabledProfiles)
            .filter { $0.title.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query) }
            .map { WorkspaceSearchResult(title: $0.title, subtitle: $0.subtitle, kind: .module($0.module)) }

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
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
        } detail: {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    if layoutState.isFocusModeEnabled {
                        compactFocusToolbar
                    } else if activeModule != .notebook {
                        workspaceToolbar
                        Divider().opacity(0.24)
                    }
                    activeWorkspace
                        .id(activeModule)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.animation(.easeOut(duration: 0.15)),
                                removal: .opacity.animation(.easeIn(duration: 0.10))
                            )
                        )
                        .environmentObject(layoutState)
                }
                .background(appPageBackground(for: colorScheme).ignoresSafeArea())

                if !searchResults.isEmpty {
                    searchResultsOverlay
                        .padding(.top, 88)
                        .padding(.horizontal, 24)
                }
            }
            .appSearchable(
                text: Binding(
                    get: {
                        if activeModule == .notebook {
                            return layoutState.notebookSearchText
                        } else if activeModule == .attendance {
                            return layoutState.attendanceSearchText
                        } else {
                            return searchText
                        }
                    },
                    set: { newValue in
                        if activeModule == .notebook {
                            layoutState.setNotebookSearchText(newValue)
                        } else if activeModule == .attendance {
                            layoutState.setAttendanceSearchText(newValue)
                        } else {
                            searchText = newValue
                        }
                    }
                ),
                isPresented: $isSearchPresented,
                placement: .toolbar,
                prompt: activeModule == .notebook ? "Buscar alumnado o columnas" :
                        activeModule == .attendance ? "Buscar alumno…" :
                        "Buscar alumno, rúbrica o sesión…"
            )
            .avoidHidingContentDuringSearch()
            .toolbar {
                if activeModule == .notebook && isRegularWidth {
                    notebookToolbarItems
                }
            }
        }
        #if os(macOS)
        .navigationSplitViewStyle(.automatic)
        #else
        .navigationSplitViewStyle(.balanced)
        #endif
        #if os(macOS)
        .ignoresSafeArea(.all, edges: .leading)
        #endif
        .sheet(item: Binding<ActiveWorkspaceSheet?>(
            get: { activeWorkspaceSheet },
            set: { newValue in
                if activeWorkspaceSheet != nil && newValue == nil {
                    if case .bulkRubricEvaluation = activeWorkspaceSheet {
                        bridge.closeBulkRubricEvaluation()
                    }
                }
                activeWorkspaceSheet = newValue
            }
        )) { sheet in
            switch sheet {
            case .create(let workspaceCreateSheet):
                switch workspaceCreateSheet {
                case .course:
                    CreateCourseSheet {
                        activeWorkspaceSheet = nil
                    }
                    .environmentObject(bridge)
                case .student:
                    CreateStudentSheet(defaultClassId: selectedClassId) {
                        activeWorkspaceSheet = nil
                    }
                    .environmentObject(bridge)
                case .evaluation:
                    CreateEvaluationSheet(defaultClassId: selectedClassId) {
                        activeWorkspaceSheet = nil
                    }
                    .environmentObject(bridge)
                }
            case .contextualAI(let state):
                contextualAISheet(state)
            case .classroomCapture(let kind):
                classroomCaptureSheetView(kind)
            case .bulkRubricEvaluation:
                RubricBulkEvaluationSheet(bridge: bridge)
                    #if os(macOS)
                    .frame(minWidth: 900, idealWidth: 1180, minHeight: 600, idealHeight: 760)
                    #else
                    .presentationDetents([.large])
                    #endif
            }
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

            let restoredModule = AppWorkspaceModule(rawValue: persistedActiveModule) ?? .dashboard
            activeModule = restoredModule == .teacherRadar ? .dashboard : restoredModule
            
            await bridge.ensureClassesLoaded()
            try? await bridge.refreshStudentsDirectory()
            try? await bridge.refreshRubrics()
            try? await bridge.refreshRubricClassLinks()
            
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
            await reloadClassroomContext()
            updateBulkRubricSheetState(showing: bridge.showingBulkRubricEvaluation, module: activeModule)
        }
        .appOnChange(of: activeModule) { newValue in
            persistedActiveModule = newValue.rawValue
            updateBulkRubricSheetState(showing: bridge.showingBulkRubricEvaluation, module: newValue)
        }
        .appOnChange(of: bridge.showingBulkRubricEvaluation) { newValue in
            updateBulkRubricSheetState(showing: newValue, module: activeModule)
        }
        .appOnChange(of: selectedClassId) { newValue in
            persistedSelectedClassId = Int(newValue ?? 0)
            Task { await reloadClassroomContext() }
        }
        .appOnChange(of: selectedStudentId) { newValue in persistedSelectedStudentId = Int(newValue ?? 0) }
        .task(id: searchText) {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            debouncedSearchText = searchText
        }
        .onAppear(perform: syncRootSplitVisibility)
        .appOnChange(of: layoutState.isSidebarVisible) { _ in syncRootSplitVisibility() }
        .appOnChange(of: layoutState.isFocusModeEnabled) { _ in syncRootSplitVisibility() }
        .appOnChange(of: rootSplitVisibility) { newVisibility in
            // El sistema puede escribir directamente en rootSplitVisibility (swipe, auto-collapse).
            // Sincronizamos de vuelta a layoutState para que el estado sea coherente.
            let isVisible = (newVisibility != .detailOnly)
            if layoutState.isSidebarVisible != isVisible && !layoutState.isFocusModeEnabled {
                layoutState.isSidebarVisible = isVisible
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appleAppAddNotebookColumnRequested)) { _ in
            performNotebookAddColumnCommand()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appleAppSearchRequested)) { _ in
            isSearchPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .appleAppSaveOrSyncRequested)) { _ in
            performSaveOrSyncCommand()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appleAppShowHiddenNotebookColumnsRequested)) { _ in
            performNotebookHiddenColumnsCommand()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appleAppReorderNotebookColumnsRequested)) { _ in
            performNotebookReorderColumnsCommand()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appleAppExportReportRequested)) { _ in
            activeModule = .reports
        }
        .onReceive(NotificationCenter.default.publisher(for: .appleAppNavigateRequested)) { notification in
            navigateFromCommand(notification.object)
        }
    }

    var notebookToolbarMode: NotebookToolbarMode {
        #if os(iOS)
        horizontalSizeClass == .compact ? .inlineCompact : .macShellOwned
        #else
        .macShellOwned
        #endif
    }

    func performNotebookAddColumnCommand() {
        // ⌘N solo actúa si ya estamos en el Cuaderno: forzar la navegación aquí
        // interrumpiría sin avisar el trabajo en otro módulo (Asistencia, Planner…).
        guard activeModule == .notebook else { return }
        Task { @MainActor in
            await Task.yield()
            layoutState.showNotebookAddColumn()
        }
    }

    func performNotebookHiddenColumnsCommand() {
        activeModule = .notebook
        Task { @MainActor in
            await Task.yield()
            layoutState.openNotebookHiddenColumns()
        }
    }

    func performNotebookReorderColumnsCommand() {
        activeModule = .notebook
        Task { @MainActor in
            await Task.yield()
            layoutState.openNotebookOrganizationMenu()
        }
    }

    func performSaveOrSyncCommand() {
        Task {
            if activeModule == .notebook {
                await MainActor.run {
                    layoutState.notebookRefresh()
                }
            }
            await bridge.pullMissingSyncChanges()
            try? await bridge.refreshStudentsDirectory()
        }
    }

    func navigateFromCommand(_ object: Any?) {
        guard let rawValue = object as? String,
              let destination = AppleAppCommandDestination(rawValue: rawValue)
        else { return }

        switch destination {
        case .notebook:
            activeModule = .notebook
        case .attendance:
            activeModule = .attendance
        case .planner:
            activeModule = .planner
        }
    }

    func contextualAISheet(_ sheet: ContextualAISheetState) -> some View {
        ContextualAIAssistantSheet(
            bridge: bridge,
            module: sheet.module,
            context: sheet.context
        )
    }

    func updateBulkRubricSheetState(showing: Bool, module: AppWorkspaceModule) {
        if showing && module != .notebook {
            if activeWorkspaceSheet == nil {
                activeWorkspaceSheet = .bulkRubricEvaluation
            }
        } else {
            if case .bulkRubricEvaluation = activeWorkspaceSheet {
                activeWorkspaceSheet = nil
            }
        }
    }

    var workspaceToolbar: some View {
        Group {
            if activeModule == .notebook {
                EmptyView()
            } else {
                VStack(spacing: 16) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 24) {
                            workspaceToolbarTitle

                            Spacer(minLength: 16)

                            workspaceToolbarActions
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            workspaceToolbarTitle
                            workspaceToolbarActions
                        }
                    }

                    if activeModule == .attendance && layoutState.attendanceToolbarAvailable {
                        attendanceGlobalToolbarRow
                    } else if activeModule == .planner || activeModule == .diary {
                        moduleContextToolbarRow
                    } else if activeModule == .notebook {
                        notebookContextToolbarRow
                    } else {
                        dailyContextToolbarRow
                    }

                    if shouldShowClassroomCaptureBar {
                        ClassroomCaptureBar(
                            contextTitle: classroomCaptureTitle,
                            isCompactNotebookMode: activeModule == .notebook && layoutState.notebookSurfaceMode != "grid",
                            onOpenAttendance: {
                                open(module: .attendance, classId: selectedClassId, studentId: selectedStudentId)
                            },
                            onOpenRubric: {
                                Task { await openClassroomRubricCapture() }
                            },
                            onQuickNote: {
                                presentClassroomCapture(.quickNote)
                            },
                            onInjury: {
                                presentClassroomCapture(.injury)
                            },
                            onObservation: {
                                presentClassroomCapture(.observation)
                            }
                        )
                    }

                    workspaceStatusLine
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [appPageBackground(for: colorScheme), appMutedCardBackground(for: colorScheme).opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    var workspaceToolbarTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(activeModule.subtitle.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(activeModule == .dashboard ? "Hoy" : activeModule.title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    var workspaceToolbarActions: some View {
        if activeModule == .dashboard {
            dashboardToolbarActions
        } else if activeModule == .planner {
            plannerToolbarActions
        } else if activeModule == .diary {
            diaryToolbarActions
        } else if activeModule == .attendance {
            focusToggleButton
        } else {
            HStack(spacing: 12) {
                focusToggleButton

                if shouldShowGlobalContextualAIButton {
                    Button {
                        presentContextualAI()
                    } label: {
                        if isLoadingContextualAI {
                            ProgressView()
                                .controlSize(.small)
                                .frame(minWidth: 24)
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
                    Label("Recargar", systemImage: "arrow.clockwise")
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
    }

    var dailyContextToolbarRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                workspaceClassMenu
                workspaceStatusPill
                Spacer(minLength: 8)
            }

            VStack(alignment: .leading, spacing: 8) {
                workspaceClassMenu
                workspaceStatusPill
            }
        }
    }

    var workspaceClassMenu: some View {
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
                .lineLimit(1)
                .frame(minWidth: 220, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(bridge.classes.isEmpty)
        .accessibilityLabel("Cambiar clase activa")
    }

    var workspaceStatusPill: some View {
        Label(statusLineText, systemImage: "checkmark.seal")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(appCardBackground(for: colorScheme), in: Capsule(style: .continuous))
    }

    var workspaceStatusLine: some View {
        Text(activeModule == .notebook ? "" : statusLineText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(2)
    }

    var compactFocusToolbar: some View {
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

    var attendanceGlobalToolbarRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                attendanceClassMenu
                attendanceFilterMenu
                attendanceActionsMenu
                Spacer(minLength: 8)
                attendanceDatePicker
                attendanceModePicker(width: 250)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    attendanceClassMenu
                    attendanceFilterMenu
                    attendanceActionsMenu
                    Spacer(minLength: 8)
                    attendanceDatePicker
                }
                HStack(spacing: 12) {
                    attendanceModePicker(width: 280)
                }
            }
        }
    }

    var attendanceClassMenu: some View {
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

    var attendanceFilterMenu: some View {
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
        .buttonStyle(.bordered)
    }

    var attendanceActionsMenu: some View {
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
    }

    var attendanceDatePicker: some View {
        DatePicker(
            "Fecha",
            selection: Binding(
                get: { layoutState.attendanceSelectedDate },
                set: { layoutState.setAttendanceDate($0) }
            ),
            displayedComponents: .date
        )
        .labelsHidden()
        #if os(macOS)
        .controlSize(.small)
        #endif
        .fixedSize()
    }

    func attendanceModePicker(width: CGFloat) -> some View {
        Picker(
            "Vista",
            selection: Binding(
                get: { layoutState.attendanceBoardMode },
                set: { layoutState.setAttendanceBoardMode($0) }
            )
        ) {
            Text("Cursos").tag("Cursos")
            Text("Día").tag("Día")
            Text("Historial").tag("Historial")
        }
        .pickerStyle(.segmented)
        // minWidth prevents AppKit from compressing below its intrinsic minimum,
        // which causes SystemSegmentedControl 'maximum length' warnings.
        .frame(minWidth: 80, maxWidth: width)
    }

    var attendanceFilterLabel: String {
        layoutState.attendanceSelectedStatusFilter == "TODOS" ? "Filtros" : "Filtro activo"
    }

    var attendanceFilterSystemImage: String {
        layoutState.attendanceSelectedStatusFilter == "TODOS"
            ? "line.3.horizontal.decrease.circle"
            : "line.3.horizontal.decrease.circle.fill"
    }

    var moduleContextToolbarRow: some View {
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
    var focusToggleButton: some View {
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

    var notebookGroupFilterLabel: String {
        guard let selectedId = layoutState.notebookSelectedGroupId,
              let group = layoutState.notebookAvailableGroups.first(where: { $0.id == selectedId }) else {
            return "Grupo completo"
        }
        return group.name
    }

    var dashboardToolbarActions: some View {
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

    var diaryToolbarActions: some View {
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

    var plannerToolbarActions: some View {
        EmptyView()
    }

    private var isRegularWidth: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        true
        #endif
    }

    @ToolbarContentBuilder
    var notebookToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            notebookClassSelectorButton
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            SyncStatusBadge(
                syncStatusMessage: dashboardStore.syncStatusMessage,
                syncPendingChanges: dashboardStore.syncPendingChanges,
                syncLastRunAt: dashboardStore.syncLastRunAt,
                pairedSyncHost: dashboardStore.pairedSyncHost
            )
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
            // Use minWidth instead of exact width so AppKit can satisfy its minimum
            // intrinsic size and avoids SystemSegmentedControl 'maximum length' warnings.
            .frame(minWidth: 112)
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
            notebookInspectorButton
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
            notebookOverflowMenu
        }
    }

    var notebookClassSelectorButton: some View {
        Button {
            isClassPickerPresented = true
        } label: {
            Label(activeNotebookClassLabel, systemImage: "rectangle.3.group")
                .lineLimit(1)
                .frame(minWidth: 132, maxWidth: 180, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(bridge.classes.isEmpty)
        .popover(isPresented: $isClassPickerPresented, arrowEdge: .top) {
            NotebookClassPickerPopover(
                classes: bridge.classes,
                selectedClassId: selectedClassId,
                onSelectClass: { updateGlobalClassContext($0) },
                onClose: { isClassPickerPresented = false }
            )
        }
        .help("Cambiar clase del cuaderno")
    }

    @ViewBuilder
    var notebookInspectorButton: some View {
        if layoutState.isNotebookInspectorPresented {
            Button {
                layoutState.toggleNotebookInspector()
            } label: {
                Label("Ocultar inspector", systemImage: "sidebar.right")
            }
            #if os(iOS)
            .buttonStyle(.borderedProminent)
            #else
            .buttonStyle(.bordered)
            #endif
            .disabled(!layoutState.notebookInspectorAvailable)
            .keyboardShortcut("i", modifiers: [.command])
            .help("Ocultar inspector")
        } else {
            Button {
                layoutState.toggleNotebookInspector()
            } label: {
                Label("Mostrar inspector", systemImage: "sidebar.right")
            }
            .buttonStyle(.bordered)
            .disabled(!layoutState.notebookInspectorAvailable)
            .keyboardShortcut("i", modifiers: [.command])
            .help("Mostrar inspector")
        }
    }

    var notebookOverflowMenu: some View {
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

            Divider()

            Button {
                layoutState.notebookGenerateSummary()
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
                layoutState.notebookToggleAttendanceQuickMode()
            } label: {
                Label(
                    layoutState.notebookIsAttendanceQuickMode ? "Salir de asistencia rápida" : "Asistencia rápida",
                    systemImage: layoutState.notebookIsAttendanceQuickMode ? "figure.walk.circle.fill" : "figure.walk.circle"
                )
            }

            Divider()

            Button {
                layoutState.openNotebookOrganizationMenu()
            } label: {
                Label("Organizar columnas", systemImage: "slider.horizontal.3")
            }
            .disabled(!layoutState.notebookOrganizationMenuAvailable)

            Button {
                layoutState.openNotebookHiddenColumns()
            } label: {
                Label("Mostrar columnas ocultas", systemImage: "eye.slash")
            }
            .disabled(!layoutState.notebookOrganizationMenuAvailable)

            Button {
                activeModule = .courses
            } label: {
                Label("Gestión de grupos", systemImage: "person.2")
            }
        } label: {
            Label("Más", systemImage: "ellipsis.circle")
        }
        .buttonStyle(.bordered)
        .help("Más acciones del cuaderno")
    }

    var notebookToolbarActions: some View {
        HStack(spacing: 12) {
            focusToggleButton

            if bridge.syncPendingChanges > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                    Text("\(bridge.syncPendingChanges) pendientes")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(IOSAppStyle.warning)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(IOSAppStyle.warning.opacity(0.12), in: Capsule())
            }

            Picker("Vista", selection: Binding(
                get: { layoutState.notebookSurfaceMode },
                set: { layoutState.setNotebookSurfaceMode($0) }
            )) {
                Image(systemName: "tablecells").tag("grid")
                Image(systemName: "rectangle.3.group").tag("seatingPlan")
            }
            .pickerStyle(.segmented)
            // minWidth prevents AppKit from compressing below intrinsic minimum.
            .frame(minWidth: 90)

            Button {
                layoutState.showNotebookAddColumn()
            } label: {
                Label("Nueva columna", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!layoutState.notebookAddColumnAvailable)

            Button {
                layoutState.openNotebookOrganizationMenu()
            } label: {
                Label("Organizar", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .disabled(!layoutState.notebookOrganizationMenuAvailable)

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

            Menu {
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
                        systemImage: layoutState.notebookIsAttendanceQuickMode ? "bolt.slash" : "bolt"
                    )
                }

                Button {
                    layoutState.notebookGenerateSummary()
                } label: {
                    Label("Generar síntesis", systemImage: "apple.intelligence")
                }

                Button {
                    layoutState.notebookRefresh()
                } label: {
                    Label("Recargar", systemImage: "arrow.clockwise")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 32, height: 32)
                    .background(Color.secondary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    var notebookContextToolbarRow: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(bridge.classes, id: \.id) { schoolClass in
                    Button {
                        updateGlobalClassContext(schoolClass.id)
                    } label: {
                        HStack {
                            Text("\(schoolClass.name) · \(schoolClass.course)º")
                            if selectedClassId == schoolClass.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(activeClassLabel, systemImage: "rectangle.3.group")
                    .frame(minWidth: 200, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(bridge.classes.isEmpty)

            if !layoutState.notebookAvailableGroups.isEmpty {
                notebookGroupFilterMenu
            }

            Spacer(minLength: 8)
        }
    }

    var notebookGroupFilterMenu: some View {
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


    var searchResultsOverlay: some View {
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

}

struct EFPlaceholderModuleView: View {
    @Environment(\.colorScheme) var colorScheme
    let title: String
    let subtitle: String

    var body: some View {
        WorkspaceEmptyState(title: title, subtitle: subtitle)
            .background(appPageBackground(for: colorScheme).ignoresSafeArea())
    }
}

struct AttendanceRowCard: View {
    @Environment(\.colorScheme) var colorScheme
    let row: AttendanceEntryRow
    let isInjured: Bool
    let onPickStatus: (AttendanceStatusOption) -> Void
    let onSelect: () -> Void
    let isSaving: Bool

    var primaryOptions: [AttendanceStatusOption] {
        AttendanceStatusOption.all.filter { ["PRESENTE", "AUSENTE", "TARDE"].contains($0.id) }
    }

    var secondaryOptions: [AttendanceStatusOption] {
        AttendanceStatusOption.all.filter { !["PRESENTE", "AUSENTE", "TARDE"].contains($0.id) }
    }

    var selectedOption: AttendanceStatusOption? {
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
                        if isInjured {
                            Label("LESIÓN", systemImage: "cross.case.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.orange.opacity(0.14), in: Capsule())
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
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .appInteractiveHighlight()
            }
        }
        .padding(24)
        .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    var secondaryLabel: String {
        guard let selectedOption,
              secondaryOptions.contains(where: { $0.id == selectedOption.id }) else {
            return "Más estados"
        }
        return selectedOption.label
    }

    func attendanceStatusButton(_ option: AttendanceStatusOption) -> some View {
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
        .appInteractiveHighlight()
        .accessibilityAddTraits(row.record?.status == option.id ? .isSelected : [])
        .opacity(isSaving && row.record?.status != option.id ? 0.84 : 1)
    }
}

struct WorkspaceInspectorHero: View {
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

struct ProfileSummaryLine: View {
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

struct WorkspaceDetailBlock: View {
    @Environment(\.colorScheme) var colorScheme
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

struct WorkspaceMetricCard: View {
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

struct EvaluationInspectorModel {
    let title: String
    let subtitle: String
    let code: String
    let weightText: String
    let rubricName: String
    let linkedClassCountText: String
    let summary: String
    let readinessTags: [String]
}

struct RubricInspectorModel {
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

enum PEIncidentWorkflowState: String, Codable, CaseIterable, Identifiable {
    case open = "Abierta"
    case followUp = "Seguimiento"
    case closed = "Cerrada"

    var id: String { rawValue }
}

struct PEIncidentMetadata: Identifiable, Codable {
    let id: Int64
    var category: String
    var workflowState: PEIncidentWorkflowState
    var sessionId: Int64?
    var followUpNote: String
}

enum PEMaterialStatus: String, Codable, CaseIterable, Identifiable {
    case prepared = "Preparado"
    case used = "Usado"
    case missing = "Faltante"
    case damaged = "Dañado"
    case replenish = "Reponer"

    var id: String { rawValue }
}

struct PEMaterialRecord: Identifiable, Codable {
    let id: UUID
    let classId: Int64
    let sessionId: Int64?
    var itemName: String
    var quantity: Int
    var status: PEMaterialStatus
    var note: String
    var createdAt: Date
}

enum TournamentTemplate: String, Codable, CaseIterable, Identifiable {
    case roundRobin = "Round-robin"
    case knockout = "Eliminatoria"
    case groupsAndKnockout = "Fase de grupos + eliminatoria"

    var id: String { rawValue }
}

enum TournamentStatus: String, Codable, CaseIterable, Identifiable {
    case draft = "Borrador"
    case active = "Activo"
    case closed = "Cerrado"
    case archived = "Archivado"

    var id: String { rawValue }
}

enum TournamentStudentLevel: String, Codable, CaseIterable, Identifiable {
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

let peIncidentMetadataStorageKey = "workspace.pe.incident.metadata.v1"
let peMaterialStorageKey = "workspace.pe.material.records.v1"
let peTournamentStorageKey = "workspace.pe.tournaments.v1"
let peTournamentSportsStorageKey = "workspace.pe.tournaments.sports.v1"
let peTournamentTieBreakersStorageKey = "workspace.pe.tournaments.tieBreakers.v1"

func storedItems<T: Decodable>(forKey key: String, as type: T.Type) -> [T] {
    guard let data = UserDefaults.standard.data(forKey: key),
          let decoded = try? JSONDecoder().decode([T].self, from: data) else {
        return []
    }
    return decoded
}

func persistItems<T: Encodable>(_ items: [T], forKey key: String) {
    guard let data = try? JSONEncoder().encode(items) else { return }
    UserDefaults.standard.set(data, forKey: key)
}

func sanitizeDomainText(_ value: String?, fallback: String = "Sin descripción") -> String {
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

func captureField(_ field: String, from raw: String, until marker: String) -> String? {
    guard let startRange = raw.range(of: "\(field)=") else { return nil }
    let start = startRange.upperBound
    let tail = raw[start...]
    if let endRange = tail.range(of: marker) {
        return String(tail[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return String(tail).trimmingCharacters(in: .whitespacesAndNewlines)
}

func evaluationPresentation(
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

func rubricPresentation(_ rubric: RubricDetail) -> RubricInspectorModel {
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

func colorHex(for status: PEMaterialStatus) -> String {
    switch status {
    case .prepared: return "#1976D2"
    case .used: return "#2E7D32"
    case .missing: return "#F57C00"
    case .damaged: return "#C62828"
    case .replenish: return "#6A1B9A"
    }
}

func generateTeams(
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

func normalizedProfiles(
    students: [Student],
    existingProfiles: [TournamentStudentProfile]?
) -> [TournamentStudentProfile] {
    let lookup = Dictionary(uniqueKeysWithValues: (existingProfiles ?? []).map { ($0.id, $0) })
    return students.map { student in
        lookup[student.id] ?? TournamentStudentProfile(id: student.id, level: .balanced, incompatibleStudentIds: [])
    }
}

func generateBalancedTeams(
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

func generateTournamentMatches(
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

func generateRoundRobinMatches(
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

func generateKnockoutMatches(teams: [TournamentTeam]) -> [TournamentMatch] {
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

func syncTournamentMatchLabels(_ tournament: inout TournamentViewState) {
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

struct WorkspaceCompactStat: View {
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

struct WorkspaceTag: View {
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

struct WorkspaceFlowLayout<Content: View>: View {
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

struct WorkspaceActionRow: View {
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

struct WorkspaceEmptyState: View {
    let title: String
    let subtitle: String

    var body: some View {
        PremiumEmptyState(title: title, subtitle: subtitle)
    }
}


struct EditPESessionOperationalSheet: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.dismiss) var dismiss
    let snapshot: KmpBridge.PESessionSnapshot
    let onDismiss: () -> Void

    @State var scheduledSpace = ""
    @State var usedSpace = ""
    @State var materialToPrepare = ""
    @State var materialUsed = ""
    @State var injuries = ""
    @State var unequipped = ""
    @State var intensity = 0
    @State var stationObservations = ""
    @State var physicalIncidents = ""
    @State var journalStatus: SessionJournalStatus = .draft

    var body: some View {
        WorkspaceCreateSheetScaffold(
            title: "Operativa sesión EF",
            subtitle: "Actualiza el contexto real de la sesión sin salir del workspace diario.",
            systemImage: "figure.strengthtraining.traditional",
            canSave: true,
            onCancel: { dismiss() },
            onSave: save
        ) {
            PremiumCard.section(title: "Espacio y material", systemImage: "sportscourt") {
                VStack(alignment: .leading, spacing: 16) {
                    WorkspaceCreateTextField(title: "Espacio previsto", placeholder: "Pabellón", text: $scheduledSpace)
                    WorkspaceCreateTextField(title: "Espacio usado", placeholder: "Pista exterior", text: $usedSpace)
                    WorkspaceCreateMultilineField(title: "Material a preparar", placeholder: "Material previsto", text: $materialToPrepare)
                    WorkspaceCreateMultilineField(title: "Material usado", placeholder: "Material realmente usado", text: $materialUsed)
                }
            }

            PremiumCard.section(title: "Seguimiento de clase", systemImage: "waveform.path.ecg") {
                VStack(alignment: .leading, spacing: 16) {
                    Stepper("Intensidad \(intensity)/5", value: $intensity, in: 0...5)
                    WorkspaceCreateMultilineField(title: "Lesiones", placeholder: "Alumnado lesionado o adaptaciones", text: $injuries)
                    WorkspaceCreateMultilineField(title: "Sin equipación", placeholder: "Alumnado sin equipación", text: $unequipped)
                    WorkspaceCreateMultilineField(title: "Observaciones por estaciones", placeholder: "Notas rápidas de ejecución", text: $stationObservations)
                    WorkspaceCreateMultilineField(title: "Incidencias físicas", placeholder: "Incidencias durante la sesión", text: $physicalIncidents)
                }
            }

            PremiumCard.section(title: "Diario", systemImage: "book.closed") {
                Picker("Estado de diario", selection: $journalStatus) {
                    Text("Vacío").tag(SessionJournalStatus.empty)
                    Text("Borrador").tag(SessionJournalStatus.draft)
                    Text("Completado").tag(SessionJournalStatus.completed)
                }
                .pickerStyle(.segmented)
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

    private func save() {
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
}

extension Date {
    var stripTime: Date {
        Calendar.current.startOfDay(for: self)
    }
}

struct ContextualAIAssistantSheet: View {
    let bridge: KmpBridge
    let module: AppWorkspaceModule
    let context: KmpBridge.ScreenAIContext

    @Environment(\.dismiss) var dismiss
    @State var selectedAction: KmpBridge.ContextualAIAction?
    @State var audience: AIReportAudience = .docente
    @State var tone: AIReportTone = .claro
    @State var customPrompt = ""
    @State var result: ContextualAIResult?
    @State var editableText = ""
    @State var isGenerating = false
    @State var isRefining = false
    @State var feedbackMessage: String?
    @State var teachingDraft: TeachingAssistantDraft?
    @State var refinePrompt = ""
    @State var aiAvailability: AIContextualAvailabilityState = .unavailable("Comprobando disponibilidad…")

    let aiService = AppleFoundationContextualAIService()
    let teachingAssistantService = AppleFoundationTeachingAssistantService()

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
                aiAvailability = aiService.currentAvailability()
                aiService.prewarm()
                teachingAssistantService.prewarm()
                selectedAction = context.suggestedActions.first
            }
        }
    }

    var availabilityCard: some View {
        PremiumCard.glass {
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
                if let riskTitle = teachingDraft?.riskLevel?.title {
                    Text(riskTitle)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(NotebookStyle.primaryTint.opacity(0.12), in: Capsule(style: .continuous))
                }
                Text(aiAvailability.message)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(aiAvailability.isAvailable ? NotebookStyle.successTint : NotebookStyle.warningTint)

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

    var actionCard: some View {
        PremiumCard.glass {
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
                            teachingAssistantService.clearActiveConversation()
                            refinePrompt = ""
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
                    .appOnChange(of: audience) { _ in
                        teachingAssistantService.clearActiveConversation()
                    }

                    Picker("Tono", selection: $tone) {
                        ForEach(AIReportTone.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .appOnChange(of: tone) { _ in
                        teachingAssistantService.clearActiveConversation()
                    }

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
                    .disabled(!context.hasEnoughData || selectedAction == nil || isGenerating)
                }
            }
        }
    }

    var resultCard: some View {
        PremiumCard.glass {
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
                    if let result {
                        evidenceSummary(
                            facts: result.factsUsed,
                            warnings: result.warnings,
                            recommendedActions: result.recommendedActions,
                            confidenceNote: result.confidenceNote
                        )
                    } else if let teachingDraft {
                        evidenceSummary(
                            facts: teachingDraft.factsUsed,
                            warnings: teachingDraft.warnings,
                            recommendedActions: teachingDraft.recommendedActions,
                            confidenceNote: teachingDraft.confidenceNote
                        )
                    }

                    TextEditor(text: $editableText)
                        .frame(minHeight: 220)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(NotebookStyle.surface)
                        )

                    if teachingDraft != nil {
                        HStack(alignment: .top, spacing: 10) {
                            TextField("Refinar: más breve, más cálido, foco en próximos pasos...", text: $refinePrompt, axis: .vertical)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .lineLimit(2, reservesSpace: true)
                            Button {
                                refineTeachingDraft()
                            } label: {
                                if isRefining {
                                    ProgressView()
                                } else {
                                    Label("Refinar", systemImage: "wand.and.stars")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRefining || refinePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    func evidenceSummary(
        facts: [String],
        warnings: [String],
        recommendedActions: [String],
        confidenceNote: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let confidenceNote {
                Text(confidenceNote)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if !facts.isEmpty {
                summarySection(title: "Hechos usados", items: facts)
            }
            if !warnings.isEmpty {
                summarySection(title: "Alertas", items: warnings)
            }
            if !recommendedActions.isEmpty {
                summarySection(title: "Acciones recomendadas", items: recommendedActions)
            }
        }
        .padding(.bottom, 10)
    }

    func summarySection(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            ForEach(items, id: \.self) { item in
                Text("• \(item)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
        }
    }

    func generate() {
        guard let selectedAction else { return }
        isGenerating = true
        feedbackMessage = nil
        result = nil
        teachingDraft = nil
        refinePrompt = ""
        Task {
            do {
                await MainActor.run {
                    aiAvailability = aiService.currentAvailability()
                    feedbackMessage = nil
                }

                if teachingAssistantService.canHandle(selectedAction.actionId) {
                    let generated = try await teachingAssistantService.generateDraft(
                        for: selectedAction.actionId,
                        bridge: bridge,
                        context: context,
                        audience: audience,
                        tone: tone,
                        customPrompt: customPrompt.nilIfBlank
                    )
                    await MainActor.run {
                        teachingDraft = generated
                        editableText = generated.editableText
                        isGenerating = false
                    }
                } else {
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
                }
            } catch {
                await MainActor.run {
                    feedbackMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }

    func refineTeachingDraft() {
        isRefining = true
        feedbackMessage = nil
        let startedAt = Date()
        Task {
            do {
                let refined = try await teachingAssistantService.refineActiveDraft(with: refinePrompt)
                await MainActor.run {
                    teachingDraft = refined
                    editableText = refined.editableText
                    refinePrompt = ""
                    isRefining = false
                }
                await bridge.recordAIAuditEvent(
                    service: "contextual",
                    useCase: "refine_draft",
                    reportKind: nil,
                    classId: context.classId,
                    studentId: context.studentId,
                    availability: "Disponible",
                    modelAvailable: true,
                    success: true,
                    durationMs: Int64(Date().timeIntervalSince(startedAt) * 1000)
                )
            } catch {
                await MainActor.run {
                    feedbackMessage = error.localizedDescription
                    isRefining = false
                }
                await bridge.recordAIAuditEvent(
                    service: "contextual",
                    useCase: "refine_draft",
                    reportKind: nil,
                    classId: context.classId,
                    studentId: context.studentId,
                    availability: "Disponible",
                    modelAvailable: true,
                    success: false,
                    durationMs: Int64(Date().timeIntervalSince(startedAt) * 1000),
                    errorKind: String(describing: type(of: error)),
                    errorMessage: error.localizedDescription
                )
            }
        }
    }
}

extension View {
    @ViewBuilder
    func avoidHidingContentDuringSearch() -> some View {
        if #available(iOS 17.1, macOS 14.1, *) {
            self.searchPresentationToolbarBehavior(.avoidHidingContent)
        } else {
            self
        }
    }
}
