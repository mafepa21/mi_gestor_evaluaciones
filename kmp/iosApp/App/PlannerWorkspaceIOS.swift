import SwiftUI
import MiGestorKit

struct PlannerWorkspaceIOS: View {
    @EnvironmentObject private var bridge: KmpBridge
    @EnvironmentObject private var layoutState: WorkspaceLayoutState
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var vm = PlannerWorkspaceViewModel()
    @State private var selectedDetailSession: PlanningSession? = nil
    @State private var selectedWeekCell: PlannerCellKey? = nil
    @State private var selectedWeekDay: Int? = nil
    @State private var isClearSchedulelessWeekConfirmationPresented = false
    @StateObject private var cascadeCoordinator = PlannerCascadeDropCoordinator()
    @State private var bannerDismissTask: Task<Void, Never>?
    private let initialSection: PlannerWorkspaceSection
    private let context: PlannerNavigationContext
    private let onOpenDiary: ((PlannerNavigationContext) -> Void)?
    private let onOpenSettings: (() -> Void)?
    private let onNavigationContextChange: ((PlannerNavigationContext) -> Void)?

    init(
        initialSection: PlannerWorkspaceSection = .week,
        context: PlannerNavigationContext = PlannerNavigationContext(),
        onOpenDiary: ((PlannerNavigationContext) -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onNavigationContextChange: ((PlannerNavigationContext) -> Void)? = nil
    ) {
        self.initialSection = initialSection
        self.context = context
        self.onOpenDiary = onOpenDiary
        self.onOpenSettings = onOpenSettings
        self.onNavigationContextChange = onNavigationContextChange
    }

    var body: some View {
        plannerMainContent
        .task {
            await vm.bind(bridge: bridge)
            vm.activeSection = initialSection
            await vm.applyExternalContext(
                week: context.week,
                year: context.year,
                groupId: context.groupId,
                sessionId: context.sessionId
            )
            configurePlannerToolbar()
            syncNavigationContext()
        }
        .onAppear(perform: configurePlannerToolbar)
        .appOnChange(of: context) { newValue in
            Task {
                await vm.applyExternalContext(
                    week: newValue.week,
                    year: newValue.year,
                    groupId: newValue.groupId,
                    sessionId: newValue.sessionId
                )
                syncNavigationContext()
            }
        }
        .appOnChange(of: vm.selectedSession?.id) { _ in configurePlannerToolbar() }
        .appOnChange(of: vm.activeSection) { _ in configurePlannerToolbar() }
        .appOnChange(of: vm.week) { _ in syncNavigationContext() }
        .appOnChange(of: vm.year) { _ in syncNavigationContext() }
        .appOnChange(of: vm.selectedGroupId) { _ in syncNavigationContext() }
        .appOnChange(of: vm.selectedSession?.id) { _ in syncNavigationContext() }
        .sheet(isPresented: $vm.showingComposer) {
            PlannerSessionComposerSheet(vm: vm)
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
                        onOpenDiary?(
                            PlannerNavigationContext(
                                week: vm.week,
                                year: vm.year,
                                groupId: session.groupId,
                                sessionId: session.id
                            )
                        )
                    },
                    onEdit: {
                        selectedDetailSession = nil
                        vm.openComposer(for: session)
                    }
                )
                .environmentObject(bridge)
            }
        }
        .onDisappear {
            layoutState.clearPlannerToolbar()
        }
        .confirmationDialog(
            "Eliminar sesiones de esta semana",
            isPresented: $isClearSchedulelessWeekConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Eliminar sesiones planificadas", role: .destructive) {
                Task { await vm.clearCurrentWeekSessionsWithoutSchedule() }
            }
            Button("Cancelar", role: .cancel) {}
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
        .appOnChange(of: cascadeCoordinator.transientMessage) { message in
            guard message != nil else { return }
            bannerDismissTask?.cancel()
            bannerDismissTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                cascadeCoordinator.transientMessage = nil
            }
        }
    }

    private var plannerMainContent: some View {
        VStack(spacing: 0) {
            PlannerToolbar(vm: vm, onUndoCascadeMove: { cascadeCoordinator.undoLastMove(vm: vm) })
            Group {
                switch vm.activeSection {
                case .week:
                    ZStack(alignment: .bottom) {
                        PlannerWeekMiniatureLayout(
                            weekBoard: vm.weekBoard,
                            vm: vm,
                            selectedCell: $selectedWeekCell,
                            selectedDay: $selectedWeekDay,
                            onOpenSession: openSessionInDiary,
                            onDropSession: { sessionId, day, period in
                                cascadeCoordinator.handleDrop(sessionId: sessionId, day: day, period: period, vm: vm)
                            }
                        )
                        .safeAreaInset(edge: .top) {
                            if let message = cascadeCoordinator.transientMessage {
                                PlannerInlineBanner(message: message)
                                    .padding(.horizontal, EvaluationDesign.screenPadding)
                                    .padding(.top, 8)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .safeAreaInset(edge: .bottom) {
                            Color.clear.frame(height: 96)
                        }

                        plannerFloatingControls
                            .padding(.horizontal, EvaluationDesign.screenPadding)
                            .padding(.bottom, 32)
                    }
                case .day:
                    PlannerDayView(vm: vm, onOpenSession: openSessionInDiary)
                case .sequence:
                    PlannerSequenceGanttView(vm: vm, onOpenSession: openSessionInDiary)
                case .summary:
                    PlannerSummaryDashboard(vm: vm, onOpenSettings: onOpenSettings, onOpenSession: openSessionInDiary)
                }
            }
            .background(appPageBackground(for: colorScheme).ignoresSafeArea())
        }
    }

    private func configurePlannerToolbar() {
        layoutState.configurePlannerToolbar(addSessionAvailable: true) {
            vm.openComposer()
        }
    }

    private var plannerFloatingControls: some View {
        PlannerLiquidGlassControls(
            density: $vm.density,
            canOpenDiary: vm.selectedSession != nil,
            canCopySelection: !vm.selectedSessionIds.isEmpty,
            canClearSchedulelessWeek: vm.canClearSchedulelessWeekSessions,
            isSelectionModeActive: vm.selectionMode,
            shareText: vm.exportText(),
            onPreviousWeek: { Task { await vm.previousWeek() } },
            onNextWeek: { Task { await vm.nextWeek() } },
            onToday: { Task { await vm.goToCurrentWeek() } },
            onSync: {
                Task {
                    await bridge.pullMissingSyncChanges()
                    await vm.refreshCurrentWeek()
                }
            },
            onToggleSelection: {
                vm.selectionMode.toggle()
                if !vm.selectionMode { vm.selectedSessionIds.removeAll() }
            },
            onCopyToNextWeek: { Task { await vm.bulkCopyToNextWeek() } },
            onMoveOneDay: { Task { await vm.bulkMoveOneDay() } },
            onClearSchedulelessWeek: {
                isClearSchedulelessWeekConfirmationPresented = true
            },
            onOpenDiary: openSelectedSessionInDiary,
            onNewSession: { vm.openComposer() }
        )
        .frame(maxWidth: .infinity)
    }

    private func openSelectedSessionInDiary() {
        guard let session = vm.selectedSession else { return }
        openSessionInDiary(session)
    }

    private func openSessionInDiary(_ session: PlanningSession) {
        Task { await vm.select(session: session) }
        selectedDetailSession = session
    }

    private func syncNavigationContext() {
        onNavigationContextChange?(
            PlannerNavigationContext(
                week: vm.week,
                year: vm.year,
                groupId: vm.selectedGroupId,
                sessionId: vm.selectedSession?.id
            )
        )
    }
}

struct PlannerToolbar: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    var onUndoCascadeMove: (() -> Void)? = nil
    /// En Mac, la navegación de semana/sección/grupo/búsqueda vive en la toolbar
    /// nativa (ver `PlannerMacToolbarActions`); aquí solo queda la tarjeta de
    /// progreso, que sí aporta información y no es mera navegación.
    var showsNavigationControls: Bool = true
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @AppStorage("planner_toolbar_progress_expanded") private var isProgressExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 16) {
                Button(action: {
                    withAnimation(uiFeatureFlags.interactionAnimation) {
                        isProgressExpanded.toggle()
                    }
                }) {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(toolbarTitle)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            Text(toolbarSubtitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer(minLength: 8)
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isProgressExpanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                if isProgressExpanded {
                    Group {
                        if let progress = vm.situationProgress(for: vm.selectedSession) {
                            PlannerSituationProgressStrip(progress: progress)
                        } else {
                            PlannerWeekProgressStrip(vm: vm)
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)).animation(.easeOut(duration: 0.2)),
                        removal: .opacity.animation(.easeIn(duration: 0.15))
                    ))
                }
            }
            .padding(16)
            .plannerGlassPanel(.hero, cornerRadius: 24)

            if showsNavigationControls {
                HStack(spacing: 8) {
                    PlannerFloatingTabBar(activeSection: $vm.activeSection)
                        .frame(maxWidth: 376)

                    weekNavigationCluster

                    HStack(spacing: 8) {
                        Picker("Grupo", selection: Binding(
                            get: { vm.selectedGroupId },
                            set: { vm.selectGroup($0) }
                        )) {
                            Text("Todos").tag(Optional<Int64>.none)
                            ForEach(vm.groups, id: \.id) { group in
                                Text(group.name).tag(Optional(group.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 180)
                    }
                    .controlSize(.small)

                    IOSSearchField(text: $vm.searchText, placeholder: "Buscar sesión, unidad, objetivo…")
                        .appOnChange(of: vm.searchText) { _ in vm.applySearch() }
                }
                .frame(height: 40)
            }

            if !vm.bulkSummary.isEmpty {
                Text(vm.bulkSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, EvaluationDesign.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var weekNavigationCluster: some View {
        HStack(spacing: 4) {
            Button {
                Task { await vm.previousWeek() }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: 28, minHeight: 28)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .accessibilityLabel("Semana anterior")

            Button {
                Task { await vm.goToCurrentWeek() }
            } label: {
                Text("Hoy")
                    .frame(minHeight: 28)
            }
            .keyboardShortcut("t", modifiers: .command)
            .accessibilityLabel("Ir a la semana actual")

            Button {
                Task { await vm.nextWeek() }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(minWidth: 28, minHeight: 28)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .accessibilityLabel("Semana siguiente")

            if vm.lastCascadeMove != nil {
                Button {
                    if let onUndoCascadeMove {
                        onUndoCascadeMove()
                    } else {
                        Task { try? await vm.restoreLastCascadeMove() }
                    }
                } label: {
                    Label("Deshacer movimiento", systemImage: "arrow.uturn.backward")
                        .frame(minHeight: 28)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .accessibilityLabel("Deshacer último movimiento de sesiones")
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .font(.subheadline.weight(.semibold))
    }

    private var toolbarTitle: String {
        vm.selectedSession?.teachingUnitName.nilIfBlank ?? vm.weekLabel
    }

    private var toolbarSubtitle: String {
        if let session = vm.selectedSession {
            return "\(vm.weekLabel) · \(vm.dateRangeLabel) · \(session.groupName)"
        }
        return vm.dateRangeLabel
    }
}

private struct PlannerSituationProgressStrip: View {
    let progress: PlannerSituationProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(progress.completed) de \(progress.total) sesiones completadas")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(progress.percentLabel)
                    .font(.headline.weight(.black))
                    .foregroundStyle(EvaluationDesign.accent)
            }

            ProgressView(value: progress.completionRatio)
                .tint(EvaluationDesign.accent)

            HStack(spacing: 12) {
                PlannerProgressMetric(title: "Completadas", value: "\(progress.completed)", tint: EvaluationDesign.success)
                PlannerProgressMetric(title: "Pendientes", value: "\(progress.pending)", tint: .secondary)
                PlannerProgressMetric(title: "Revisión", value: "\(progress.review)", tint: IOSAppStyle.warning)
            }
        }
        .padding(16)
        .plannerGlassPanel(.content, cornerRadius: 16)
    }
}

private struct PlannerWeekProgressStrip: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    private var totals: (total: Int, completed: Int, pending: Int, review: Int) {
        let total = vm.filteredSessions.count
        let completed = vm.filteredSessions.count { session in
            session.status == .completed || vm.summary(for: session.id)?.status == .completed
        }
        let review = vm.filteredSessions.count { session in
            guard let summary = vm.summary(for: session.id) else { return false }
            return summary.status == .draft || !summary.incidentTags.isEmpty
        }
        return (total, completed, max(total - completed, 0), review)
    }

    var body: some View {
        HStack(spacing: 12) {
            PlannerProgressMetric(title: "Sesiones", value: "\(totals.total)", tint: EvaluationDesign.accent)
            PlannerProgressMetric(title: "Completadas", value: "\(totals.completed)", tint: EvaluationDesign.success)
            PlannerProgressMetric(title: "Pendientes", value: "\(totals.pending)", tint: .secondary)
            PlannerProgressMetric(title: "Revisión", value: "\(totals.review)", tint: IOSAppStyle.warning)
        }
    }
}

private struct PlannerProgressMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.black))
                .foregroundStyle(tint)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}


private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        switch self?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case .some(let value) where !value.isEmpty: return value
        default: return nil
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
