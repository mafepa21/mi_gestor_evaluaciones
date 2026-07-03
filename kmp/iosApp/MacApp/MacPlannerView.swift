import SwiftUI
import AppKit
import MiGestorKit

struct MacPlannerView: View {
    @ObservedObject var bridge: KmpBridge
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @Binding var selectedSessionIdFromRoot: Int64?
    @StateObject private var vm = PlannerWorkspaceViewModel()
    @State private var selectedTableSessionId: Int64?
    @State private var showingScheduleSettings = false
    @State private var showingExportConfirmation = false
    @State private var showingMoveFilteredConfirmation = false
    @State private var showingClearSchedulelessWeekConfirmation = false
    @State private var transientMessage: String?
    @State private var sessionFilter: MacPlannerSessionFilter = .all
    @State private var groupFilterId: Int64?
    @State private var selectedDetailSession: PlanningSession? = nil
    @State private var selectedWeekCell: PlannerCellKey? = nil
    @State private var selectedWeekDay: Int? = nil
    @StateObject private var cascadeCoordinator = PlannerCascadeDropCoordinator()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlannerToolbar(vm: vm, onUndoCascadeMove: { cascadeCoordinator.undoLastMove(vm: vm) })

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
        .appOnChange(of: selectedTableSessionId) { newValue in
            guard let sessionId = newValue else { return }
            guard let session = findSession(by: sessionId) else { return }
            Task {
                await vm.select(session: session)
                await syncInspectorStudents(for: session)
            }
        }
        .appOnChange(of: vm.selectedSession?.id) { newValue in
            selectedTableSessionId = newValue
            Task {
                await syncInspectorStudents(for: vm.selectedSession)
            }
        }
        .appOnChange(of: sessionFilter) { _ in
            Task { await normalizeSelectionForDisplayedSessions() }
        }
        .appOnChange(of: groupFilterId) { _ in
            Task { await normalizeSelectionForDisplayedSessions() }
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
        .alert("Exportación copiada", isPresented: $showingExportConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("El resumen actual de planificación se ha copiado al portapapeles.")
        }
        .alert("Mover sesiones filtradas", isPresented: $showingMoveFilteredConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Mover \(displayedSessions.count) sesiones", role: .destructive) {
                Task { await moveFilteredSessions() }
            }
        } message: {
            Text("Se moverán todas las sesiones visibles con los filtros actuales un día hacia delante.")
        }
        .alert("Limpiar semana sin franjas", isPresented: $showingClearSchedulelessWeekConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar sesiones planificadas", role: .destructive) {
                Task { await vm.clearCurrentWeekSessionsWithoutSchedule(groupId: groupFilterId) }
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
        .sheet(
            isPresented: Binding(
                get: { selectedDetailSession != nil },
                set: { if !$0 { selectedDetailSession = nil } }
            )
        ) {
            if let session = selectedDetailSession {
                PlannerSessionDetailSheet(
                    session: session,
                    onOpenDiary: {
                        selectedDetailSession = nil
                        Task {
                            await vm.select(session: session)
                        }
                    },
                    onEdit: {
                        selectedDetailSession = nil
                        vm.openComposer(for: session)
                    }
                )
                .environmentObject(bridge)
                .frame(minWidth: 760, idealWidth: 860, minHeight: 720, idealHeight: 820)
            }
        }
    }

    private func openMacSession(_ session: PlanningSession) {
        Task {
            await vm.select(session: session)
        }
        selectedDetailSession = session
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
            selectedDetailSession = session
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
                onDropSession: { sessionId, day, period in
                    cascadeCoordinator.handleDrop(sessionId: sessionId, day: day, period: period, vm: vm)
                }
            )
        case .day:
            PlannerDayView(vm: vm, onOpenSession: openMacSession)
        case .sequence:
            PlannerSequenceGanttView(vm: vm, onOpenSession: openMacSession)
        case .summary:
            PlannerSummaryDashboard(
                vm: vm,
                onOpenSettings: { showingScheduleSettings = true }
            )
        }
    }

    private func findSession(by id: Int64) -> PlanningSession? {
        vm.filteredSessions.first(where: { $0.id == id }) ?? vm.sessions.first(where: { $0.id == id })
    }

    private var displayedSessions: [PlanningSession] {
        vm.filteredSessions.filter { session in
            let matchesGroup = groupFilterId.map { session.groupId == $0 } ?? true
            let matchesStatus: Bool
            switch sessionFilter {
            case .all:
                matchesStatus = true
            case .planned:
                matchesStatus = session.status != .completed
            case .completed:
                matchesStatus = session.status == .completed
            }
            return matchesGroup && matchesStatus
        }
    }

    private var displayedRows: [MacPlannerSessionRow] {
        displayedSessions.map { session in
            MacPlannerSessionRow(
                session: session,
                dayLabel: vm.dayLabel(for: Int(session.dayOfWeek)),
                timeLabel: vm.timeLabel(for: Int(session.period)),
                sessionStatusLabel: session.status == .completed ? "Impartida" : "Planificada",
                diaryStatusLabel: diaryStatusLabel(for: session)
            )
        }
    }

    private func diaryStatusLabel(for session: PlanningSession) -> String {
        switch vm.summary(for: session.id)?.status {
        case .completed:
            return "Cerrado"
        case .draft:
            return "Borrador"
        case .empty, .none:
            return "Vacío"
        default:
            return "Vacío"
        }
    }

    private func openComposerForCurrentFilter() {
        vm.openComposer()
        if let groupFilterId {
            vm.composerDraft.groupId = groupFilterId
        }
    }

    private func copyFilteredWeek() async {
        guard !displayedSessions.isEmpty else { return }
        vm.selectedSessionIds = Set(displayedSessions.map(\.id))
        await vm.bulkCopyToNextWeek()
    }

    private func moveFilteredSessions() async {
        guard !displayedSessions.isEmpty else { return }
        vm.selectedSessionIds = Set(displayedSessions.map(\.id))
        await vm.bulkMoveOneDay()
    }

    private func normalizeSelectionForDisplayedSessions() async {
        let visible = displayedSessions
        if let selectedSession = vm.selectedSession,
           visible.contains(where: { $0.id == selectedSession.id }) {
            return
        }
        if let first = visible.first {
            await vm.select(session: first)
            selectedTableSessionId = first.id
        } else {
            vm.clearSelection()
            selectedTableSessionId = nil
        }
    }

    private func exportCurrentContext() {
        let text: String
        if vm.selectedSession != nil {
            text = vm.exportText()
        } else {
            let sessionLines = displayedRows.map {
                "\($0.unit) · \($0.group) · \($0.day) · \($0.time) · \($0.sessionStatus) · \($0.diaryStatus)"
            }
            text = ([ "\(vm.weekLabel) · \(vm.dateRangeLabel)" ] + sessionLines).joined(separator: "\n")
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        transientMessage = "Resumen exportado al portapapeles."
        showingExportConfirmation = true
    }
}

private enum MacPlannerSessionFilter: String, CaseIterable, Identifiable {
    case all = "Todas"
    case planned = "Planificadas"
    case completed = "Impartidas"

    var id: String { rawValue }
}

private struct MacPlannerSessionRow: Identifiable {
    let session: PlanningSession
    let dayLabel: String
    let timeLabel: String
    let sessionStatusLabel: String
    let diaryStatusLabel: String

    var id: Int64 { session.id }
    var unit: String { session.teachingUnitName }
    var group: String { session.groupName }
    var day: String { dayLabel }
    var time: String { timeLabel }
    var sessionStatus: String { sessionStatusLabel }
    var diaryStatus: String { diaryStatusLabel }
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
        VStack(spacing: 0) {
            MacPopupActionBar(
                title: "Configurar agenda",
                subtitle: "Horario docente, curso y previsión lectiva",
                onClose: onClose
            )
            .frame(maxWidth: .infinity)
            .zIndex(2)

            ScrollView(.vertical, showsIndicators: true) {
                MacTeacherScheduleSettingsPanel(
                    bridge: bridge,
                    selectedClassId: $selectedClassId
                )
                .padding(MacAppStyle.pagePadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(MacAppStyle.pageBackground)
        }
        .background(MacAppStyle.pageBackground)
    }
}
