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
            .environmentObject(bridge)
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
                context: resolvedPlannerContext,
                onOpenDiary: { context in
                    openDiary(context: context)
                },
                onNavigationContextChange: { context in
                    plannerContext = context
                }
            )
            .environmentObject(bridge)
        case .situations:
            LearningSituationsWorkspaceView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:)
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
        case .meetings:
            MeetingsWorkspaceView(bridge: bridge)
                .environmentObject(bridge)
        case .evaluationHub:
            EvaluationHubView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:)
            )
                .environmentObject(bridge)
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
            PhysicalTestsWorkspaceView(
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
            SettingsWorkspaceView(
                selectedClassId: $selectedClassId,
                onOpenModule: open(module:classId:studentId:)
            )
            .environmentObject(bridge)
        case .backups:
            BackupsWorkspaceView(selectedClassId: $selectedClassId)
        }
    }

}
