import SwiftUI
import AppKit
import MiGestorKit

/// Acciones/estado que `MacPlannerView` publica hacia `MacRootView` para poder
/// pintar una toolbar nativa de macOS (en vez de la barra estilo iOS) — mismo
/// patrón ya usado por Notebook/Dashboard/Asistencia/Pruebas físicas
/// (`onToolbarActionsChange` + `@State` en el root).
struct PlannerMacToolbarActions {
    var activeSection: Binding<PlannerWorkspaceSection>
    var selectedGroupId: Binding<Int64?>
    var searchText: Binding<String>
    let groups: [SchoolClass]
    let canUndoCascadeMove: Bool
    let canClearSchedulelessWeek: Bool
    /// Estado/acciones del modo selección múltiple, espejo de
    /// `PlannerLiquidGlassControls` en iPad (`vm.selectionMode` / `vm.selectedSessionIds`).
    let isSelectionModeActive: Bool
    let canCopySelection: Bool
    let shareText: String
    let onPreviousWeek: () -> Void
    let onNextWeek: () -> Void
    let onToday: () -> Void
    let onNewSession: () -> Void
    let onUndoCascadeMove: () -> Void
    let onClearSchedulelessWeek: () -> Void
    let onToggleSelectionMode: () -> Void
    let onCopyToNextWeek: () -> Void
    let onMoveOneDay: () -> Void
    /// Usados por el inspector de sesión en `MacRootView` (que no tiene acceso
    /// directo al `PlannerWorkspaceViewModel`, propio de `MacPlannerView`).
    let onOpenDiary: (PlanningSession) -> Void
    let onEditSession: (PlanningSession) -> Void
    let onDeleteSession: (PlanningSession) -> Void
}

struct MacPlannerView: View {
    @ObservedObject var bridge: KmpBridge
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @Binding var selectedSessionIdFromRoot: Int64?
    @Binding var inspectorSession: PlanningSession?
    let onToolbarActionsChange: (PlannerMacToolbarActions?) -> Void
    let onOpenDiaryDirect: (PlanningSession) -> Void
    @StateObject private var vm = PlannerWorkspaceViewModel()
    @State private var showingScheduleSettings = false
    @State private var showingClearSchedulelessWeekConfirmation = false
    @State private var transientMessage: String?
    @State private var groupFilterId: Int64?
    @State private var selectedWeekCell: PlannerCellKey? = nil
    @State private var selectedWeekDay: Int? = nil
    @StateObject private var cascadeCoordinator = PlannerCascadeDropCoordinator()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlannerToolbar(
                vm: vm,
                onUndoCascadeMove: { cascadeCoordinator.undoLastMove(vm: vm) },
                showsNavigationControls: false
            )

            if let transientMessage, !transientMessage.isEmpty {
                MacPlannerBanner(message: transientMessage)
                    .padding(.horizontal, EvaluationDesign.screenPadding)
                    .padding(.bottom, 8)
                    .transition(uiFeatureFlags.bannerTransition)
            }

            plannerCenterContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(MacAppStyle.pageBackground)
        .animation(uiFeatureFlags.interactionAnimation, value: transientMessage)
        .appOnChange(of: cascadeCoordinator.transientMessage) { newValue in
            guard let newValue else { return }
            transientMessage = newValue
        }
        .task {
            await vm.bind(bridge: bridge)
            await syncInspectorStudents(for: vm.selectedSession)
            if let sessionId = selectedSessionIdFromRoot {
                await applySessionIdFromRoot(sessionId)
            }
        }
        .appOnChange(of: selectedSessionIdFromRoot) { newValue in
            guard let newValue else { return }
            Task {
                await applySessionIdFromRoot(newValue)
            }
        }
        .appOnChange(of: vm.selectedSession?.id) { _ in
            Task {
                await syncInspectorStudents(for: vm.selectedSession)
            }
        }
        .sheet(isPresented: $vm.showingComposer) {
            PlannerSessionComposerSheet(vm: vm)
                .frame(minWidth: 920, minHeight: 720)
        }
        .sheet(isPresented: $showingScheduleSettings, onDismiss: {
            Task { await vm.reloadAll() }
        }) {
            MacPlannerScheduleSettingsSheet(
                bridge: bridge,
                selectedClassId: Binding(
                    get: { groupFilterId },
                    set: { groupFilterId = $0 }
                ),
                onClose: {
                    showingScheduleSettings = false
                }
            )
            .frame(minWidth: 980, minHeight: 760)
        }
        .alert("Limpiar semana sin franjas", isPresented: $showingClearSchedulelessWeekConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar sesiones planificadas", role: .destructive) {
                Task { await vm.clearCurrentWeekSessionsWithoutSchedule(groupId: vm.selectedGroupId) }
            }
        } message: {
            Text("No hay franjas en la agenda. Se eliminarán las sesiones planificadas de la semana actual y se conservarán las completadas.")
        }
        .alert(
            "Mover sesiones impartidas",
            isPresented: Binding(
                get: { cascadeCoordinator.pendingConfirmation != nil },
                set: { if !$0 { cascadeCoordinator.pendingConfirmation = nil } }
            )
        ) {
            Button("Cancelar", role: .cancel) {
                cascadeCoordinator.cancelPendingMove()
            }
            Button("Mover") {
                cascadeCoordinator.confirmPendingMove(vm: vm)
            }
        } message: {
            Text("La cascada incluye una o más sesiones ya impartidas. Se conservarán sus diarios y referencias.")
        }
        .task {
            publishToolbarActions()
        }
        .appOnChange(of: vm.activeSection) { _ in publishToolbarActions() }
        .appOnChange(of: vm.groups.map(\.id)) { _ in publishToolbarActions() }
        .appOnChange(of: vm.lastCascadeMove?.movedCount) { _ in publishToolbarActions() }
        .appOnChange(of: vm.sessions.count) { _ in publishToolbarActions() }
        .appOnChange(of: vm.selectionMode) { _ in publishToolbarActions() }
        .appOnChange(of: vm.selectedSessionIds) { _ in publishToolbarActions() }
        .onDisappear {
            onToolbarActionsChange(nil)
        }
    }

    private func publishToolbarActions() {
        onToolbarActionsChange(
            PlannerMacToolbarActions(
                activeSection: Binding(get: { vm.activeSection }, set: { vm.activeSection = $0 }),
                selectedGroupId: Binding(get: { vm.selectedGroupId }, set: { vm.selectGroup($0) }),
                searchText: Binding(
                    get: { vm.searchText },
                    set: { vm.searchText = $0; vm.applySearch() }
                ),
                groups: vm.groups,
                canUndoCascadeMove: vm.lastCascadeMove != nil,
                canClearSchedulelessWeek: vm.canClearSchedulelessWeekSessions,
                isSelectionModeActive: vm.selectionMode,
                canCopySelection: !vm.selectedSessionIds.isEmpty,
                shareText: vm.exportText(),
                onPreviousWeek: { Task { await vm.previousWeek() } },
                onNextWeek: { Task { await vm.nextWeek() } },
                onToday: { Task { await vm.goToCurrentWeek() } },
                onNewSession: { openComposerForCurrentFilter() },
                onUndoCascadeMove: { cascadeCoordinator.undoLastMove(vm: vm) },
                onClearSchedulelessWeek: { showingClearSchedulelessWeekConfirmation = true },
                onToggleSelectionMode: {
                    vm.selectionMode.toggle()
                    if !vm.selectionMode { vm.selectedSessionIds.removeAll() }
                },
                onCopyToNextWeek: { Task { await vm.bulkCopyToNextWeek() } },
                onMoveOneDay: { Task { await vm.bulkMoveOneDay() } },
                onOpenDiary: { session in
                    inspectorSession = nil
                    Task { await vm.select(session: session) }
                },
                onEditSession: { session in
                    inspectorSession = nil
                    vm.openComposer(for: session)
                },
                onDeleteSession: { session in
                    inspectorSession = nil
                    Task { await vm.deleteSession(session) }
                }
            )
        )
    }

    private func openMacSession(_ session: PlanningSession) {
        Task {
            await vm.select(session: session)
        }
        inspectorSession = session
    }

    private func openMacSessionDiary(_ session: PlanningSession) {
        Task {
            await vm.select(session: session)
        }
        onOpenDiaryDirect(session)
    }

    private func applySessionIdFromRoot(_ sessionId: Int64) async {
        do {
            let session = try await bridge.plannerGetSession(id: sessionId)
            await vm.applyExternalContext(
                week: Int(session.weekNumber),
                year: Int(session.year),
                groupId: session.groupId,
                sessionId: session.id
            )
            selectedSessionIdFromRoot = nil

            await vm.select(session: session)
            inspectorSession = session
        } catch {
            print("Error getting session from root: \(error)")
        }
    }

    private func syncInspectorStudents(for session: PlanningSession?) async {
        guard let session else { return }
        await Task.yield()
        bridge.selectClass(id: session.groupId)
        await bridge.selectStudentsClass(classId: session.groupId)
    }

    @ViewBuilder
    private var plannerCenterContent: some View {
        switch vm.activeSection {
        case .week:
            PlannerWeekMiniatureLayout(
                weekBoard: vm.weekBoard,
                vm: vm,
                selectedCell: $selectedWeekCell,
                selectedDay: $selectedWeekDay,
                onOpenSession: openMacSession,
                onOpenDiary: openMacSessionDiary,
                onDropSession: { sessionId, day, period in
                    cascadeCoordinator.handleDrop(sessionId: sessionId, day: day, period: period, vm: vm)
                },
                onOpenSettings: { showingScheduleSettings = true }
            )
        case .day:
            PlannerDayView(vm: vm, onOpenSession: openMacSession)
        case .sequence:
            PlannerSequenceGanttView(vm: vm, onOpenSession: openMacSession)
        case .summary:
            PlannerSummaryDashboard(
                vm: vm,
                onOpenSettings: { showingScheduleSettings = true },
                onOpenSession: openMacSession
            )
        }
    }

    private func openComposerForCurrentFilter() {
        vm.openComposer()
        if let groupFilterId {
            vm.composerDraft.groupId = groupFilterId
        }
    }
}

private struct MacPlannerBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(MacAppStyle.successTint)
            Text(message)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacAppStyle.successTint.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }
}

private struct MacPlannerScheduleSettingsSheet: View {
    @ObservedObject var bridge: KmpBridge
    @Binding var selectedClassId: Int64?
    let onClose: () -> Void

    var body: some View {
        TeacherScheduleWizard(
            bridge: bridge,
            selectedClassId: $selectedClassId,
            onClose: onClose
        )
        .background(MacAppStyle.pageBackground)
    }
}
