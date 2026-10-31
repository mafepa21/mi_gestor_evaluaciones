import SwiftUI
import MiGestorKit

// WorkspaceModuleSwitcher routes the active workspace views on iOS/macOS shells.
// Selection bindings are supplied directly from the hosting shell's state properties.
extension AppWorkspaceShell {
    @ViewBuilder
    var activeWorkspace: some View {
        switch activeModule {
        case .dashboard:
            DashboardView(
                bridge: bridge,
                dashboardStore: dashboardStore,
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:)
            )
        case .courses:
            CoursesWorkspaceView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:),
                onCreateStudent: { classId in
                    selectedClassId = classId
                    createSheet = .student
                }
            )
            .kmpBridgeEnvironment(bridge)
        case .students:
            StudentProfilesWorkspaceView(
                bridge: bridge,
                studentsBridgeStore: studentsBridgeStore,
                selectedClassId: $selectedClassId,
                selectedStudentId: $selectedStudentId,
                onOpenModule: open(module:classId:studentId:)
            )
        case .teacherRadar:
            DashboardView(
                bridge: bridge,
                dashboardStore: dashboardStore,
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:)
            )
        case .notebook:
            NotebookModuleView(
                bridge: bridge,
                notebookStore: notebookStore,
                dashboardStore: dashboardStore,
                selectedClassId: $selectedClassId,
                selectedStudentId: $selectedStudentId,
                onOpenModule: open(module:classId:studentId:),
                toolbarMode: notebookToolbarMode
            )
        case .attendance:
            AttendanceWorkspaceView(
                bridge: bridge,
                attendanceStore: attendanceStore,
                selectedClassId: $selectedClassId,
                preselectedStudentId: $selectedStudentId,
                onOpenModule: open(module:classId:studentId:)
            )
        case .planner:
            PlannerWorkspaceIOS(
                viewModel: workspaceStores.planner,
                context: resolvedPlannerContext,
                onOpenDiary: { context in
                    openDiary(context: context)
                },
                onNavigationContextChange: { context in
                    plannerContext = context
                }
            )
            .kmpBridgeEnvironment(bridge)
        case .situations:
            LearningSituationsWorkspaceView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:)
            )
            .kmpBridgeEnvironment(bridge)
        case .diary:
            DiaryWorkspaceView(
                vm: workspaceStores.planner,
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
            .kmpBridgeEnvironment(bridge)
        case .libreta:
            #if os(iOS)
            LibretaModuleView()
            #else
            EmptyView()
            #endif
        case .meetings:
            MeetingsWorkspaceView(bridge: bridge)
                .kmpBridgeEnvironment(bridge)
        case .inclusion:
            InclusionTrackerView(bridge: bridge, selectedClassId: $selectedClassId)
        case .evaluationSessions:
            EvaluationSessionView(bridge: bridge, selectedClassId: $selectedClassId)
        case .evaluationHub:
            EvaluationHubView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:),
                onCreateEvaluation: { createSheet = .evaluation }
            )
                .kmpBridgeEnvironment(bridge)
        case .webSubmissions:
            WebSubmissionsIPadInfoView()
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
            .kmpBridgeEnvironment(bridge)
        case .reports:
            ReportsWorkspaceView(
                selectedClassId: $selectedClassId,
                selectedStudentId: $selectedStudentId
            )
                .kmpBridgeEnvironment(bridge)
        case .library:
            LibraryWorkspaceView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:)
            )
                .kmpBridgeEnvironment(bridge)
        case .peSessions:
            PESessionsWorkspaceView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:)
            )
            .kmpBridgeEnvironment(bridge)
        case .peTests:
            PhysicalTestsWorkspaceView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:)
            )
            .kmpBridgeEnvironment(bridge)
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
            .kmpBridgeEnvironment(bridge)
        case .peIncidents:
            EFIncidentsWorkspaceView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:)
            )
            .kmpBridgeEnvironment(bridge)
        case .peMaterial:
            PEMaterialWorkspaceView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:)
            )
            .kmpBridgeEnvironment(bridge)
        case .peTournaments:
            TournamentsWorkspaceView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:)
            )
            .kmpBridgeEnvironment(bridge)
        case .settings:
            SettingsWorkspaceView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:)
            )
            .kmpBridgeEnvironment(bridge)
        case .backups:
            BackupsWorkspaceView(selectedClassId: $selectedClassId)
        }
    }

}
