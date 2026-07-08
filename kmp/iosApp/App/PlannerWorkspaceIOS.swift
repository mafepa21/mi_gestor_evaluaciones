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

private struct PlannerWeekBoard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onOpenDiary: (PlanningSession) -> Void

    private var columnWidth: CGFloat { vm.density == .compact ? 200 : 248 }
    private var timeAxisWidth: CGFloat { vm.density == .compact ? 96 : 112 }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    cellHeader("Franja", width: timeAxisWidth)
                    ForEach(vm.weekRenderModel.visibleDays, id: \.self) { day in
                        let isHoliday = vm.holidayDays.contains(day)
                        cellHeader(vm.dayHeaderLabel(for: day), width: columnWidth)
                            .foregroundStyle(isHoliday ? EvaluationDesign.danger : Color.primary)
                            .overlay(alignment: .trailing) {
                                if isHoliday {
                                    Image(systemName: "calendar.badge.minus")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(EvaluationDesign.danger)
                                        .padding(.trailing, 8)
                                }
                            }
                            .contextMenu {
                                Button {
                                    Task { await vm.toggleHoliday(for: day) }
                                } label: {
                                    Label(
                                        isHoliday ? "Marcar como lectivo" : "Marcar como festivo",
                                        systemImage: isHoliday ? "calendar.badge.plus" : "calendar.badge.minus"
                                    )
                                }
                            }
                    }
                }

                ForEach(vm.weekRenderModel.visibleSlots, id: \.period) { slot in
                    let rowHeight = rowHeight(for: slot)
                    HStack(spacing: 0) {
                        VStack(spacing: 4) {
                            Text(slot.period > 9 ? "Fx" : "P\(slot.period)")
                                .font(.caption.bold())
                            Text(slot.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: timeAxisWidth, height: rowHeight)
                        .background(EvaluationDesign.surfaceSoft)

                        ForEach(vm.weekRenderModel.visibleDays, id: \.self) { day in
                            PlannerWeekCellCard(
                                entries: vm.weekRenderModel.entriesByCell[PlannerCellKey(day: day, period: Int(slot.period))] ?? [],
                                isHoliday: vm.holidayDays.contains(day),
                                isCompact: vm.density == .compact,
                                cellWidth: columnWidth,
                                cellHeight: rowHeight,
                                onCreate: {
                                    vm.openComposer(day: day, period: Int(slot.period))
                                },
                                onOpenEntry: { entry in
                                    if let sessionId = entry.sessionId,
                                       let session = vm.sessions.first(where: { $0.id == sessionId }) {
                                        if vm.selectionMode {
                                            vm.toggleSelection(sessionId: session.id)
                                        } else {
                                            onOpenDiary(session)
                                        }
                                    } else {
                                        vm.selectGroup(entry.classId)
                                        vm.openComposer(day: day, period: Int(slot.period))
                                        vm.composerDraft.groupId = entry.classId
                                    }
                                },
                                onEditEntry: { entry in
                                    guard let sessionId = entry.sessionId,
                                          let session = vm.sessions.first(where: { $0.id == sessionId }) else { return }
                                    vm.openComposer(for: session)
                                },
                                onDuplicateEntry: { entry in
                                    guard let sessionId = entry.sessionId else { return }
                                    vm.selectedSessionIds = [sessionId]
                                    Task { await vm.bulkCopyToNextWeek() }
                                },
                                onCompleteEntry: { entry in
                                    guard let sessionId = entry.sessionId,
                                          let session = vm.sessions.first(where: { $0.id == sessionId }) else { return }
                                    Task { await vm.markCompleted(session) }
                                },
                                onOpenDiaryEntry: { entry in
                                    guard let sessionId = entry.sessionId,
                                          let session = vm.sessions.first(where: { $0.id == sessionId }) else { return }
                                    onOpenDiary(session)
                                }
                            )
                            .equatable()
                        }
                    }
                }
            }
            .padding(EvaluationDesign.screenPadding)
        }
    }

    private func cellHeader(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.caption.bold())
            .frame(width: width, height: 42)
            .background(EvaluationDesign.surfaceSoft)
    }

    private func rowHeight(for slot: PlannerVisibleSlot) -> CGFloat {
        guard let start = minutes(from: slot.startTime), let end = minutes(from: slot.endTime), end > start else {
            return vm.density == .compact ? 112 : 144
        }
        let duration = end - start
        let base = vm.density == .compact ? 104.0 : 136.0
        let extra = CGFloat(max(duration - 55, 0)) * (vm.density == .compact ? 0.7 : 0.9)
        return min(max(base + extra, base), vm.density == .compact ? 176 : 232)
    }

    private func minutes(from value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return hour * 60 + minute
    }
}

private struct PlannerWeekCellCard: View, Equatable {
    let entries: [PlannerWeekCellEntry]
    let isHoliday: Bool
    let isCompact: Bool
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let onCreate: () -> Void
    let onOpenEntry: (PlannerWeekCellEntry) -> Void
    let onEditEntry: (PlannerWeekCellEntry) -> Void
    let onDuplicateEntry: (PlannerWeekCellEntry) -> Void
    let onCompleteEntry: (PlannerWeekCellEntry) -> Void
    let onOpenDiaryEntry: (PlannerWeekCellEntry) -> Void

    static func == (lhs: PlannerWeekCellCard, rhs: PlannerWeekCellCard) -> Bool {
        lhs.isHoliday == rhs.isHoliday &&
        lhs.entries == rhs.entries &&
        lhs.isCompact == rhs.isCompact &&
        lhs.cellWidth == rhs.cellWidth &&
        lhs.cellHeight == rhs.cellHeight
    }

    var body: some View {
        let singleRichEntry = entries.count == 1 && entries.first?.kind == .session && !isCompact
        VStack(alignment: .leading, spacing: 8) {
            if isHoliday {
                ZStack {
                    if !entries.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(entries.prefix(singleRichEntry ? 1 : 3)) { entry in
                                PlannerWeekEntryCard(
                                    entry: entry,
                                    fillsCell: singleRichEntry,
                                    onTap: {},
                                    onEdit: {},
                                    onDuplicate: {},
                                    onComplete: {},
                                    onOpenDiary: {}
                                )
                            }
                        }
                        .opacity(0.2)
                        .disabled(true)
                    }
                    VStack(spacing: 4) {
                        Image(systemName: "umbrella.fill")
                            .font(.title2)
                            .foregroundStyle(EvaluationDesign.danger.opacity(0.7))
                        Text("No lectivo")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if entries.isEmpty {
                Button(action: onCreate) {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                        Text("Sin concretar")
                            .font(.caption.weight(.bold))
                        Text("Añadir sesión")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(entries.prefix(singleRichEntry ? 1 : 3)) { entry in
                    if singleRichEntry {
                        PlannerWeekEntryCard(
                            entry: entry,
                            fillsCell: true,
                            onTap: { onOpenEntry(entry) },
                            onEdit: { onEditEntry(entry) },
                            onDuplicate: { onDuplicateEntry(entry) },
                            onComplete: { onCompleteEntry(entry) },
                            onOpenDiary: { onOpenDiaryEntry(entry) }
                        )
                    } else {
                        PlannerWeekCompactEntryRow(
                            entry: entry,
                            onTap: { onOpenEntry(entry) },
                            onEdit: { onEditEntry(entry) },
                            onDuplicate: { onDuplicateEntry(entry) },
                            onComplete: { onCompleteEntry(entry) },
                            onOpenDiary: { onOpenDiaryEntry(entry) }
                        )
                    }
                }
                if !singleRichEntry && entries.count > 3 {
                    Text("+\(entries.count - 3) más")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
        }
        .frame(width: cellWidth, height: cellHeight, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isHoliday ? EvaluationDesign.surfaceSoft.opacity(0.5) : EvaluationDesign.surfaceSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isHoliday ? EvaluationDesign.danger.opacity(0.15) : EvaluationDesign.border,
                    style: StrokeStyle(lineWidth: 1, dash: entries.isEmpty && !isHoliday ? [6, 5] : [])
                )
        )
    }
}

private struct PlannerWeekCompactEntryRow: View {
    let entry: PlannerWeekCellEntry
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onComplete: () -> Void
    let onOpenDiary: () -> Void

    private var tint: Color { Color(hex: entry.classColorHex) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(tint)
                    .frame(width: 5, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.className) · \(entry.title)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(stateLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(stateTint)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: stateIcon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(stateTint)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(tint.opacity(entry.kind == .session ? 0.10 : 0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if entry.sessionId != nil {
                Button("Abrir ficha", action: onTap)
                Button("Completar diario", action: onOpenDiary)
                Button("Editar", action: onEdit)
                Button("Duplicar próxima semana", action: onDuplicate)
                Button("Marcar impartida", action: onComplete)
            }
        }
    }

    private var stateLabel: String {
        if entry.kind == .scheduledSlot { return "Sin concretar" }
        if entry.journalStatus == .completed { return "Diario cerrado" }
        if entry.journalStatus == .draft { return "Diario pendiente" }
        if entry.sessionStatus == .completed { return "Impartida" }
        return "Planificada"
    }

    private var stateIcon: String {
        if entry.kind == .scheduledSlot { return "plus.circle.fill" }
        if entry.journalStatus == .completed { return "checkmark.seal.fill" }
        if entry.journalStatus == .draft { return "doc.text.fill" }
        if entry.sessionStatus == .completed { return "checkmark.circle.fill" }
        return "circle"
    }

    private var stateTint: Color {
        if entry.kind == .scheduledSlot { return tint }
        if entry.journalStatus == .completed { return EvaluationDesign.success }
        if entry.journalStatus == .draft || entry.sessionStatus == .completed { return IOSAppStyle.warning }
        return .secondary
    }
}

private struct PlannerWeekEntryCard: View {
    let entry: PlannerWeekCellEntry
    let fillsCell: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onComplete: () -> Void
    let onOpenDiary: () -> Void

    private var tint: Color { Color(hex: entry.classColorHex) }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Capsule()
                        .fill(tint)
                        .frame(width: 8, height: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(entry.className)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)
                }

                HStack(spacing: 6) {
                    Image(systemName: stateIcon)
                        .font(.caption.weight(.bold))
                    Text(stateLabel)
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(stateTint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule(style: .continuous).fill(stateTint.opacity(0.12)))

                Text(entry.preview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(fillsCell ? 4 : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderColor, lineWidth: entry.isCompleted ? 1.4 : 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if entry.sessionId != nil {
                Button("Abrir diario", action: onOpenDiary)
                Button("Edición rápida", action: onEdit)
                Button("Duplicar próxima semana", action: onDuplicate)
                Button("Marcar impartida", action: onComplete)
            }
        }
    }

    private var stateLabel: String {
        if entry.kind == .scheduledSlot { return "Crear sesión" }
        if entry.journalStatus == .completed { return "Cerrada" }
        if entry.journalStatus == .draft { return "Borrador" }
        if entry.sessionStatus == .completed { return "Diario pendiente" }
        return "Planificada"
    }

    private var stateIcon: String {
        if entry.kind == .scheduledSlot { return "plus.circle.fill" }
        if entry.journalStatus == .completed { return "checkmark.seal.fill" }
        if entry.journalStatus == .draft { return "doc.text.fill" }
        if entry.sessionStatus == .completed { return "checkmark.circle.fill" }
        return "calendar"
    }

    private var stateTint: Color {
        if entry.kind == .scheduledSlot { return tint }
        if entry.journalStatus == .completed { return EvaluationDesign.success }
        if entry.journalStatus == .draft { return EvaluationDesign.accent }
        if entry.sessionStatus == .completed { return IOSAppStyle.warning }
        return tint.opacity(0.9)
    }

    private var backgroundFill: Color {
        switch entry.kind {
        case .scheduledSlot:
            return tint.opacity(0.10)
        case .session:
            return entry.isCompleted ? tint.opacity(0.24) : tint.opacity(0.14)
        }
    }

    private var borderColor: Color {
        switch entry.kind {
        case .scheduledSlot:
            return tint.opacity(0.35)
        case .session:
            return entry.isCompleted ? tint.opacity(0.8) : tint.opacity(0.45)
        }
    }
}

private struct PlannerStatusPill: View {
    let status: SessionJournalStatus

    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(tint.opacity(0.12)))
    }

    private var label: String {
        switch status {
        case .empty: return "Vacío"
        case .draft: return "Borrador"
        case .completed: return "Cerrado"
        default: return "Borrador"
        }
    }

    private var tint: Color {
        switch status {
        case .empty: return .secondary
        case .draft: return EvaluationDesign.accent
        case .completed: return EvaluationDesign.success
        default: return EvaluationDesign.accent
        }
    }
}

private struct PlannerDaySessionRow: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let session: PlanningSession
    let isCurrent: Bool
    let isNext: Bool
    let onOpen: () -> Void
    let onComplete: () -> Void

    private var tint: Color { Color(hex: vm.classColorHex(for: session.groupId)) }
    private var stateTint: Color { vm.sessionStateTint(sessionStatus: session.status, journalStatus: vm.summary(for: session.id)?.status) }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(timeRange)
                    .font(.headline.monospacedDigit())
                Text(isCurrent ? "Ahora" : (isNext ? "Próxima" : ""))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isCurrent ? EvaluationDesign.success : EvaluationDesign.accent)
            }
            .frame(width: 104, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.groupName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(tint)
                    Spacer()
                    Label(vm.sessionStateLabel(for: session), systemImage: vm.sessionStateIcon(sessionStatus: session.status, journalStatus: vm.summary(for: session.id)?.status))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(stateTint)
                }

                Text(session.teachingUnitName.nilIfBlank ?? "Sesión sin título")
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)

                if let objective = session.objectives.nilIfBlank ?? session.activities.nilIfBlank {
                    Text(objective)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Button("Abrir ficha", action: onOpen)
                        .buttonStyle(.borderedProminent)
                    Button("Impartida", action: onComplete)
                        .buttonStyle(.bordered)
                        .disabled(session.status == .completed)
                    Button("Observación", action: onOpen)
                        .buttonStyle(.bordered)
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isCurrent ? EvaluationDesign.success.opacity(0.55) : EvaluationDesign.border, lineWidth: isCurrent ? 1.5 : 1)
        }
    }

    private var timeRange: String {
        if let start = session.startTime, let end = session.endTime {
            return "\(start)-\(end)"
        }
        return vm.timeLabel(for: Int(session.period))
    }
}

struct PlannerSequenceView: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onOpenSession: (PlanningSession) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Secuencias didácticas")
                            .font(.title2.weight(.black))
                        Text("Secuencia didáctica completa y progresión de las sesiones.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if vm.isLoadingSequences {
                        ProgressView()
                            .tint(EvaluationDesign.accent)
                    }
                }

                if vm.sequenceGroupsEnriched.isEmpty {
                    if vm.isLoadingSequences {
                        VStack {
                            ProgressView("Cargando secuencias...")
                                .padding()
                        }
                        .frame(maxWidth: .infinity, minHeight: 280)
                    } else {
                        PlannerEmptyState(
                            title: "Sin secuencias",
                            systemImage: "point.3.connected.trianglepath.dotted",
                            message: "Selecciona otro grupo o crea sesiones vinculadas a una situación."
                        )
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(vm.sequenceGroupsEnriched) { group in
                            PlannerSequenceCard(
                                vm: vm,
                                group: group,
                                onOpenSession: onOpenSession
                            )
                        }
                    }
                }
            }
            .padding(EvaluationDesign.screenPadding)
        }
        .task {
            await vm.loadEnrichedSequences()
        }
        .appOnChange(of: vm.selectedGroupId) { _ in
            Task {
                await vm.loadEnrichedSequences()
            }
        }
    }
}

private struct PlannerSequenceCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let group: PlannerSequenceGroup
    let onOpenSession: (PlanningSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.headline.weight(.bold))
                    Text("\(group.groupName) · \(group.completedCount) de \(group.totalSessionsCount) sesiones completadas")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 8) {
                        if group.completedCount > 0 {
                            Text("Impartidas: \(group.completedCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.green)
                        }
                        if group.plannedCount > 0 {
                            Text("Planificadas: \(group.plannedCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(EvaluationDesign.accent)
                        }
                        if group.pendingCount > 0 {
                            Text("Pendientes: \(group.pendingCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer()
                ProgressView(value: group.totalSessionsCount == 0 ? 0 : Double(group.completedCount) / Double(group.totalSessionsCount))
                    .frame(width: 120)
                    .tint(EvaluationDesign.accent)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.rows) { row in
                    if let session = row.planningSession {
                        Button {
                            onOpenSession(session)
                        } label: {
                            rowLabel(row: row, session: session)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            vm.openComposer(
                                learningSituationSessionPlanId: row.learningSituationSessionPlanId,
                                initialObjectives: row.title,
                                initialActivities: row.objective,
                                initialTeachingUnitName: group.title
                            )
                        } label: {
                            rowLabel(row: row, session: nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(EvaluationDesign.border, lineWidth: 1))
    }

    private func rowLabel(row: PlannerSequenceRow, session: PlanningSession?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.statusIcon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(row.statusColor)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(row.sessionNumber). \(row.title.nilIfBlank ?? "Sesión")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(session == nil ? .secondary : .primary)
                    .lineLimit(1)
                
                if let session = session {
                    Text("\(vm.dayLabel(for: Int(session.dayOfWeek))) · \(vm.timeLabel(for: Int(session.period))) · \(row.statusText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(row.statusText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
            Spacer()
            if session != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            } else {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct PlannerSessionsList: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let source: [PlanningSession]
    let onOpenDiary: (PlanningSession) -> Void

    private var groupedSessions: [(day: Int, sessions: [PlanningSession])] {
        Dictionary(grouping: source, by: { Int($0.dayOfWeek) })
            .map { day, sessions in
                (
                    day: day,
                    sessions: sessions.sorted {
                        if $0.period == $1.period {
                            return ($0.startTime ?? "") < ($1.startTime ?? "")
                        }
                        return $0.period < $1.period
                    }
                )
            }
            .sorted { $0.day < $1.day }
    }

    var body: some View {
        List {
            ForEach(groupedSessions, id: \.day) { group in
                Section(vm.dayLabel(for: group.day)) {
                    ForEach(group.sessions, id: \.id) { session in
                        PlannerAgendaSessionRow(
                            vm: vm,
                            session: session,
                            onSelect: {
                                Task { await vm.select(session: session) }
                            },
                            onOpen: {
                                onOpenDiary(session)
                            },
                            onComplete: {
                                Task { await vm.markCompleted(session) }
                            }
                        )
                    }
                }
            }
        }
    }
}

private struct PlannerAgendaSessionRow: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let session: PlanningSession
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onComplete: () -> Void

    private var stateTint: Color {
        vm.sessionStateTint(sessionStatus: session.status, journalStatus: vm.summary(for: session.id)?.status)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.timeLabel(for: Int(session.period)))
                    .font(.caption.weight(.bold))
                Text("P\(session.period)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.teachingUnitName)
                        .font(.headline)
                        .lineLimit(2)
                    Spacer()
                    Label(vm.sessionStateLabel(for: session), systemImage: vm.sessionStateIcon(sessionStatus: session.status, journalStatus: vm.summary(for: session.id)?.status))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(stateTint)
                        .labelStyle(.titleAndIcon)
                }

                Text(session.groupName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let objective = session.objectives.nilIfBlank {
                    Text(objective)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Button("Abrir sesión", action: onOpen)
                        .buttonStyle(.borderedProminent)
                    Button("Impartida", action: onComplete)
                        .buttonStyle(.bordered)
                        .disabled(session.status == .completed)
                    Button("Observación", action: onOpen)
                        .buttonStyle(.bordered)
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Observación", action: onOpen)
                .tint(EvaluationDesign.accent)

            Button("Impartida", action: onComplete)
                .tint(EvaluationDesign.success)
        }
        .contextMenu {
            Button("Abrir sesión", action: onOpen)
            Button("Marcar impartida", action: onComplete)
            Button("Registrar observación", action: onOpen)
        }
    }
}

private struct PlannerScheduleBoard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onOpenSettings: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IOSAppStyle.sectionSpacing) {
                PremiumCard.section(title: "Resumen operativo", systemImage: "calendar.badge.clock") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("La configuración editable vive ahora en Ajustes para que Planner conserve una sola tarea principal.")
                            .font(IOSAppStyle.captionText)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            IOSMetricCard(title: "Agenda", value: vm.scheduleName, tint: .blue)
                            IOSMetricCard(title: "Curso", value: "\(vm.scheduleStartDate) · \(vm.scheduleEndDate)", tint: .indigo)
                            IOSMetricCard(title: "Franjas", value: "\(vm.visibleScheduleSlotsSummaryCount)", tint: .teal)
                            IOSMetricCard(title: "Evaluaciones", value: "\(vm.evaluationPeriods.count)", tint: .orange)
                        }

                        Label(vm.activeWeekdaySummary, systemImage: "calendar.badge.clock")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if let onOpenSettings {
                            Button("Configurar en Ajustes") {
                                onOpenSettings()
                            }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }

                PremiumCard.section(title: "Franjas activas", systemImage: "clock.fill") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Resumen de las franjas que ya están alimentando el tablero semanal actual.")
                            .font(IOSAppStyle.captionText)
                            .foregroundStyle(.secondary)

                        if vm.effectiveScheduleSlots.isEmpty {
                            Text("Todavía no hay franjas definidas para esta agenda.")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        if vm.isUsingLegacyWeeklySlots {
                            Text("Mostrando franjas heredadas del horario original de KMP Desktop.")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        ForEach(vm.effectiveScheduleSlots, id: \.id) { slot in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(vm.dayLabel(for: Int(slot.dayOfWeek))) · \(slot.startTime)-\(slot.endTime)")
                                        .font(.body.weight(.semibold))
                                    Text([
                                        vm.groups.first(where: { $0.id == slot.schoolClassId })?.name ?? "Grupo \(slot.schoolClassId)",
                                        slot.subjectLabel,
                                        slot.unitLabel
                                    ]
                                    .compactMap { value in
                                        guard let string = value?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else { return nil }
                                        return string
                                    }
                                    .joined(separator: " · "))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }

                PremiumCard.section(title: "Previsión lectiva", systemImage: "calendar.badge.exclamationmark") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Sigue visible en Planner para contrastar lo previsto con lo ya creado, pero se edita desde Ajustes.")
                            .font(IOSAppStyle.captionText)
                            .foregroundStyle(.secondary)

                        if vm.evaluationPeriods.isEmpty {
                            Text("Aún no hay periodos evaluativos configurados.")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(vm.evaluationPeriods.sorted(by: { ($0.sortOrder, $0.startDateIso) < ($1.sortOrder, $1.startDateIso) }), id: \.id) { period in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(period.name)
                                                .font(.headline)
                                            Text("\(period.startDateIso) · \(period.endDateIso)")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    let periodForecast = vm.forecastRows.filter { $0.periodId == period.id }
                                    if periodForecast.isEmpty {
                                        Text("Sin previsión todavía. Añade franjas o revisa las fechas del curso.")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(Array(periodForecast.enumerated()), id: \.offset) { _, row in
                                            PlannerForecastRowView(row: row)
                                        }
                                    }
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(EvaluationDesign.surfaceSoft)
                                )
                            }
                        }
                    }
                }
            }
            .padding(IOSAppStyle.pagePadding)
        }
    }
}

// PlannerSummaryMetric removed in favor of IOSMetricCard

private struct PlannerForecastRowView: View {
    let row: PlannerSessionForecast

    private var deltaColor: Color {
        row.remainingSessions > 0 ? EvaluationDesign.danger : EvaluationDesign.success
    }

    private var progress: Double {
        guard row.expectedSessions > 0 else { return 0 }
        return min(Double(row.plannedSessions) / Double(row.expectedSessions), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.className)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(row.plannedSessions) / \(row.expectedSessions)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(deltaColor)
            }

            ProgressView(value: progress)
                .tint(deltaColor)

            if row.remainingSessions > 0 {
                Label("Faltan \(row.remainingSessions) sesiones para completar la previsión", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(deltaColor)
            }
        }
        .padding(12)
        .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SessionJournalHeaderCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let session: PlanningSession

    var body: some View {
        PremiumCard.glass {
            VStack(alignment: .leading, spacing: 14) {
                EvaluationSectionTitle(
                    eyebrow: "Diario",
                    title: session.teachingUnitName,
                    subtitle: "\(session.groupName) · \(vm.timeLabel(for: Int(session.period)))"
                )

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    quickField("Fecha", value: vm.dateRangeLabel)
                    quickField("Grupo", value: session.groupName)
                    quickField("Hora", value: vm.timeLabel(for: Int(session.period)))
                    editableField("Profesor", text: $vm.journalDraft.teacherName)
                    editableField("Espacio", text: $vm.journalDraft.scheduledSpace)
                    editableField("Unidad / SA", text: $vm.journalDraft.unitLabel)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Objetivo previsto")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    TextField("Pase y juego sin balón", text: $vm.journalDraft.objectivePlanned)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
        }
    }

    private func quickField(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            Text(value.isEmpty ? "Sin dato" : value)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editableField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

private struct SessionJournalQuickPulseCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        PremiumCard.glass {
            VStack(alignment: .leading, spacing: 16) {
                EvaluationSectionTitle(
                    eyebrow: "10 segundos",
                    title: "Pulso de la sesión",
                    subtitle: "Cierra lo esencial sin convertir el diario en un informe."
                )

                HStack(spacing: 8) {
                    pulseButton("Muy bien", icon: "checkmark.circle.fill", climate: 5, usefulTime: 5, difficulty: 1, tint: EvaluationDesign.success)
                    pulseButton("Normal", icon: "circle.lefthalf.filled", climate: 3, usefulTime: 3, difficulty: 3, tint: EvaluationDesign.accent)
                    pulseButton("Revisar", icon: "exclamationmark.triangle.fill", climate: 2, usefulTime: 2, difficulty: 5, tint: IOSAppStyle.warning)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Participación")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        participationButton("Baja", value: 2)
                        participationButton("Media", value: 3)
                        participationButton("Alta", value: 5)
                    }
                }
            }
        }
    }

    private func pulseButton(_ title: String, icon: String, climate: Int, usefulTime: Int, difficulty: Int, tint: Color) -> some View {
        let isSelected = vm.journalDraft.climateScore == climate
            && vm.journalDraft.usefulTimeScore == usefulTime
            && vm.journalDraft.perceivedDifficultyScore == difficulty
        return Button {
            vm.journalDraft.climateScore = climate
            vm.journalDraft.usefulTimeScore = usefulTime
            vm.journalDraft.perceivedDifficultyScore = difficulty
            if title == "Revisar", !vm.journalDraft.incidentTags.contains("Revisión") {
                vm.journalDraft.incidentTags.append("Revisión")
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.white : tint)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? tint : tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(isSelected ? 0 : 0.25), lineWidth: 1)
        )
    }

    private func participationButton(_ title: String, value: Int) -> some View {
        let isSelected = vm.journalDraft.participationScore == value
        return Button {
            vm.journalDraft.participationScore = value
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.white : EvaluationDesign.accent)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? EvaluationDesign.accent : EvaluationDesign.accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(EvaluationDesign.accent.opacity(isSelected ? 0 : 0.22), lineWidth: 1)
        )
    }
}

private struct SessionJournalQuickObservationCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "30 segundos",
            title: "Observación rápida",
            subtitle: "Una nota breve basta para mantener trazabilidad diaria."
        ) {
            TextField("Han necesitado más tiempo para la actividad 2…", text: $vm.journalDraft.groupObservations, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

private struct SessionJournalQuickNextStepCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "Siguiente sesión",
            title: "Próximo paso",
            subtitle: "Una decisión breve para no perder continuidad."
        ) {
            TextField("Repetir actividad 2, avanzar, adaptar material…", text: $vm.journalDraft.nextStepText, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

private struct SessionJournalDevelopmentCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "Reflexión completa",
            title: "Lo planificado y lo realizado",
            subtitle: "Completar solo cuando haga falta más detalle pedagógico."
        ) {
            JournalTextBlock(title: "Qué estaba planificado", text: $vm.journalDraft.plannedText)
            JournalTextBlock(title: "Qué se ha hecho realmente", text: $vm.journalDraft.actualText)
            JournalTextBlock(title: "Nivel de consecución", text: $vm.journalDraft.attainmentText)
            JournalTextBlock(title: "Adaptaciones realizadas", text: $vm.journalDraft.adaptationsText)
            JournalTextBlock(title: "Incidencias", text: $vm.journalDraft.incidentsText)
            JournalTextBlock(title: "Observaciones del grupo", text: $vm.journalDraft.groupObservations)

            JournalQuickChips(
                title: "Incidencias",
                options: ["Lesión", "Equipación", "Material", "Clima", "Espacio", "Tiempo"],
                selected: $vm.journalDraft.incidentTags
            )
        }
    }
}

private struct SessionJournalEvaluationCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "Evaluación",
            title: "Cómo ha funcionado la sesión",
            subtitle: "Valora rápidamente el clima, la participación y el tiempo útil."
        ) {
            JournalMetricStrip(title: "Clima de aula", value: $vm.journalDraft.climateScore)
            JournalMetricStrip(title: "Participación", value: $vm.journalDraft.participationScore)
            JournalMetricStrip(title: "Tiempo útil", value: $vm.journalDraft.usefulTimeScore)
            JournalMetricStrip(title: "Dificultad percibida", value: $vm.journalDraft.perceivedDifficultyScore)

            VStack(alignment: .leading, spacing: 8) {
                Text("Decisión pedagógica")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    decisionButton("Repetir", value: .repeatSession)
                    decisionButton("Reforzar", value: .reinforce)
                    decisionButton("Avanzar", value: .advance)
                }
            }
        }
    }

    private func decisionButton(_ title: String, value: SessionJournalDecision) -> some View {
        Button(title) {
            vm.journalDraft.pedagogicalDecision = value
        }
        .buttonStyle(.bordered)
        .tint(vm.journalDraft.pedagogicalDecision == value ? EvaluationDesign.accent : .gray)
    }
}

private struct SessionJournalClosingCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "Cierre",
            title: "Qué queda pendiente",
            subtitle: "Prepara la siguiente sesión y deja trazabilidad docente."
        ) {
            JournalTextBlock(title: "Tareas pendientes", text: $vm.journalDraft.pendingTasksText)
            JournalTextBlock(title: "Material a preparar", text: $vm.journalDraft.materialToPrepareText)
            JournalTextBlock(title: "Alumnado a revisar", text: $vm.journalDraft.studentsToReviewText)
            JournalTextBlock(title: "Comunicación con familias", text: $vm.journalDraft.familyCommunicationText)
            JournalTextBlock(title: "Siguiente paso", text: $vm.journalDraft.nextStepText)

            VStack(alignment: .leading, spacing: 8) {
                Text("Próxima acción")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    actionChip("Repetir tarea 2")
                    actionChip("Adaptar a Pablo")
                    actionChip("Llevar más conos")
                }
            }
        }
    }

    private func actionChip(_ title: String) -> some View {
        Button(title) {
            if !vm.journalDraft.actions.contains(where: { $0.title == title }) {
                vm.journalDraft.actions.append(PlannerJournalDraftAction(title: title))
            }
        }
        .buttonStyle(.bordered)
    }
}

private struct SessionJournalEFCard: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "EF",
            title: "Bloque específico de Educación Física",
            subtitle: "Meteorología, material, lesiones e intensidad en una misma ficha."
        ) {
            editableGridField("Meteorología", text: $vm.journalDraft.weatherText)
            editableGridField("Espacio usado", text: $vm.journalDraft.usedSpace)
            editableGridField("Material empleado", text: $vm.journalDraft.materialUsedText)
            editableGridField("Incidencias físicas", text: $vm.journalDraft.physicalIncidentsText)
            editableGridField("Lesiones / molestias", text: $vm.journalDraft.injuriesText)
            editableGridField("Sin equipación", text: $vm.journalDraft.unequippedStudentsText)

            JournalMetricStrip(title: "Intensidad percibida", value: $vm.journalDraft.intensityScore)

            HStack(spacing: 12) {
                minuteStepper("Calentamiento", value: $vm.journalDraft.warmupMinutes)
                minuteStepper("Parte principal", value: $vm.journalDraft.mainPartMinutes)
                minuteStepper("Vuelta a la calma", value: $vm.journalDraft.cooldownMinutes)
            }

            JournalTextBlock(title: "Observaciones motrices por grupos o estaciones", text: $vm.journalDraft.stationObservationsText)
        }
    }

    private func editableGridField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }

    private func minuteStepper(_ title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            Stepper("\(value.wrappedValue) min", value: value, in: 0...90, step: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct JournalIndividualNotesList: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "Alumnado",
            title: "Observaciones individuales",
            subtitle: "Notas breves por alumno con intención de seguimiento."
        ) {
            ForEach(vm.journalDraft.notes, id: \.id) { note in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Alumno", text: noteBinding(note.id, \.studentName))
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                        TextField("Tag", text: noteBinding(note.id, \.tag))
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button(role: .destructive) {
                            vm.journalDraft.notes.removeAll { $0.id == note.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }

                    TextField("Observación", text: noteBinding(note.id, \.note), axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.vertical, 4)
            }

            Button {
                vm.journalDraft.notes.append(PlannerJournalDraftNote())
            } label: {
                Label("Añadir observación individual", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
        }
    }

    private func noteBinding(_ id: UUID, _ keyPath: WritableKeyPath<PlannerJournalDraftNote, String>) -> Binding<String> {
        Binding(
            get: {
                vm.journalDraft.notes.first(where: { $0.id == id })?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                guard let index = vm.journalDraft.notes.firstIndex(where: { $0.id == id }) else { return }
                vm.journalDraft.notes[index][keyPath: keyPath] = newValue
            }
        )
    }
}

private struct JournalActionBar: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel

    var body: some View {
        SessionJournalSectionCard(
            eyebrow: "Acciones",
            title: "Integraciones y seguimiento",
            subtitle: "Lanza acciones explícitas y deja trazabilidad de lo ya trasladado."
        ) {
            HStack(spacing: 10) {
                Button("Enviar observación al cuaderno") {
                    vm.appendTraceLink(type: .notebook, label: "Pendiente de trasladar al cuaderno")
                }
                .buttonStyle(.bordered)

                Button("Registrar incidencia") {
                    Task { await vm.appendIncidentLink() }
                }
                .buttonStyle(.bordered)

                Button("Reflejar asistencia") {
                    vm.appendTraceLink(type: .attendance, label: "Asistencia / participación reflejada")
                }
                .buttonStyle(.bordered)

                Button("Seguimiento familias") {
                    vm.appendTraceLink(type: .family, label: "Seguimiento familiar marcado")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                saveStateLabel
                    .font(.caption)
                    .foregroundStyle(saveStateColor)
                Spacer()
                Button("Guardar ahora") { Task { await vm.saveJournal() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.journalSaveState == .saving)
            }

            ForEach(vm.journalDraft.links) { link in
                HStack {
                    Text(link.type.title)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(link.label)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var saveStateLabel: Text {
        switch vm.journalSaveState {
        case .idle:
            return Text("Usa el dictado nativo del teclado en cualquier campo de texto para capturar voz.")
        case .saving:
            return Text("Guardando...")
        case .saved(let date):
            let seconds = max(0, Int(Date().timeIntervalSince(date)))
            return Text(seconds < 3 ? "Guardado ahora" : "Guardado hace \(seconds) s")
        case .failed(let message):
            return Text("Error al guardar: \(message)")
        }
    }

    private var saveStateColor: Color {
        switch vm.journalSaveState {
        case .failed:
            return .red
        default:
            return .secondary
        }
    }
}

private struct SessionJournalSectionCard<Content: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let content: Content

    init(
        eyebrow: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        PremiumCard.glass {
            VStack(alignment: .leading, spacing: 16) {
                EvaluationSectionTitle(eyebrow: eyebrow, title: title, subtitle: subtitle)
                content
            }
        }
    }
}

private struct JournalTextBlock: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField(title, text: $text, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

private struct JournalMetricStrip: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { item in
                    Button("\(item)") { value = item }
                        .buttonStyle(.bordered)
                        .tint(value == item ? EvaluationDesign.accent : .gray)
                }
            }
        }
    }
}

private struct JournalQuickChips: View {
    let title: String
    let options: [String]
    @Binding var selected: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        if selected.contains(option) {
                            selected.removeAll { $0 == option }
                        } else {
                            selected.append(option)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(selected.contains(option) ? EvaluationDesign.danger : .gray)
                }
            }
        }
    }
}

private struct PlannerInstrumentCompactGroup: Identifiable {
    let title: String
    let items: [PlannerAssessmentInstrument]

    var id: String { title }
}

private struct PlannerInstrumentDisclosureSection: View {
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    let title: String
    let items: [PlannerAssessmentInstrument]
    @Binding var isExpanded: Bool
    let selectedIds: Set<String>
    let toggle: (PlannerAssessmentInstrument) -> Void

    private var selectedCount: Int {
        items.filter { selectedIds.contains($0.id) }.count
    }

    private var recommendedCount: Int {
        items.filter(\.isRecommendedForCurrentSA).count
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(uiFeatureFlags.interactionAnimation) {
                    isExpanded.toggle()
                }
                AppleInteractionFeedback.play(.lightImpact)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(plannerSafeDisplayText(title, fallback: "Sin situación asignada"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                            .textCase(.uppercase)
                            .lineLimit(1)

                        Text(sectionSubtitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if selectedCount > 0 {
                        Text("\(selectedCount) seleccionados")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(EvaluationDesign.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(EvaluationDesign.accent.opacity(0.12), in: Capsule())
                    }

                    Text("\(items.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(
                    isExpanded ? EvaluationDesign.surfaceSoft : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(items) { instrument in
                        PlannerInstrumentCompactRow(
                            instrument: instrument,
                            isSelected: selectedIds.contains(instrument.id),
                            toggle: { toggle(instrument) }
                        )
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .transition(uiFeatureFlags.reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(EvaluationDesign.border, lineWidth: 0.5)
        }
        .shadow(color: EvaluationDesign.shadow, radius: 12, x: 0, y: 4)
    }

    private var sectionSubtitle: String {
        if selectedCount > 0 {
            return "\(selectedCount) de \(items.count) seleccionados"
        }
        if recommendedCount > 0 {
            return "\(recommendedCount) recomendados para esta SA"
        }
        return "\(items.count) instrumentos"
    }
}

private struct PlannerInstrumentCompactRow: View {
    let instrument: PlannerAssessmentInstrument
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? EvaluationDesign.accent : .secondary)
                    .font(.callout.weight(.semibold))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(safeTitle)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if instrument.isRecommendedForCurrentSA {
                            Text("SA")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(EvaluationDesign.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(EvaluationDesign.accent.opacity(0.12), in: Capsule())
                        }
                    }

                    Text(safeSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(instrument.kind == .rubric ? "Rúbrica" : "Evaluación")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected ? EvaluationDesign.accent.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var safeTitle: String {
        plannerSafeDisplayText(instrument.title, fallback: "Instrumento")
    }

    private var safeSubtitle: String {
        plannerSafeDisplayText(instrument.subtitle, fallback: instrument.kind == .rubric ? "Rúbrica" : "Evaluación")
    }
}

private func plannerSafeDisplayText(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let upper = trimmed.uppercased()

    if trimmed.isEmpty ||
        upper.contains("EVALUATION(") ||
        upper.contains("CLASSID=") ||
        upper.contains("RUBRICID=") ||
        upper.contains("TRACE=") ||
        upper.contains("AUDITTRACE") ||
        upper.contains("UPDATEDAT=") ||
        upper.contains("CREATEDAT=") {
        return fallback
    }

    return trimmed
}

private struct PlannerSaveStateInlineStatus: View {
    let state: PlannerSaveState

    var body: some View {
        if let message {
            HStack(spacing: 8) {
                if state == .saving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: iconName)
                }
                Text(message)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(tint)
        }
    }

    private var message: String? {
        switch state {
        case .idle:
            return nil
        case .saving:
            return "Guardando..."
        case .saved:
            return "Guardado"
        case .failed(let text):
            return text
        }
    }

    private var iconName: String {
        switch state {
        case .failed:
            return "exclamationmark.triangle.fill"
        default:
            return "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .failed:
            return EvaluationDesign.danger
        case .saving:
            return EvaluationDesign.accent
        default:
            return EvaluationDesign.success
        }
    }
}

private extension SessionJournalMediaType {
    var title: String {
        switch self {
        case .photo: return "Foto"
        case .audio: return "Audio"
        case .transcript: return "Dictado"
        default: return "Media"
        }
    }
}

private extension SessionJournalLinkType {
    var title: String {
        switch self {
        case .notebook: return "Cuaderno"
        case .attendance: return "Asistencia"
        case .incident: return "Incidencia"
        case .family: return "Familias"
        default: return "Enlace"
        }
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
