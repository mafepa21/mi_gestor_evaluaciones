import SwiftUI
import MiGestorKit

@Observable
class PlannerDayTimeTick {
    var currentTime = Date()
    private var timer: Timer?
    
    func start() {
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                self?.currentTime = Date()
            }
        }
    }
    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

private enum PlannerDayTimelineRow: Identifiable {
    case session(PlanningSession)
    case empty(PlannerVisibleSlot)
    case gap(start: String, end: String)
    case now

    var id: String {
        switch self {
        case .session(let session): return "session-\(session.id)"
        case .empty(let slot): return "empty-\(slot.period)"
        case .gap(let start, let end): return "gap-\(start)-\(end)"
        case .now: return "now"
        }
    }
}

struct PlannerDayView: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onOpenSession: (PlanningSession) -> Void

    @State private var timeTick = PlannerDayTimeTick()
    private var currentTime: Date { timeTick.currentTime }
    @State private var completionUndo: (session: PlanningSession, previousStatus: SessionStatus)?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var quickNoteSession: PlanningSession?
    @State private var quickNoteText = ""
    @State private var dragTranslation: CGFloat = 0
    @State private var showingQuickJournal = false

    private var sessions: [PlanningSession] { vm.daySessions() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                closingSummary
                timeline
            }
            .padding(EvaluationDesign.screenPadding)
        }
        .simultaneousGesture(daySwipeGesture)
        .onAppear { timeTick.start() }
        .onDisappear { timeTick.stop() }
        .sheet(
            isPresented: Binding(
                get: { quickNoteSession != nil },
                set: { if !$0 { quickNoteSession = nil } }
            )
        ) {
            if let session = quickNoteSession {
                PlannerQuickNoteSheet(
                    session: session,
                    text: $quickNoteText,
                    onCancel: { quickNoteSession = nil },
                    onSave: {
                        let text = quickNoteText
                        quickNoteSession = nil
                        quickNoteText = ""
                        Task { await vm.quickAddObservation(to: session, text: text) }
                    }
                )
            }
        }
        .sheet(isPresented: $showingQuickJournal) {
            PlannerDayQuickJournalSheet(
                vm: vm,
                sessions: sessions,
                onOpenSession: { session in
                    showingQuickJournal = false
                    onOpenSession(session)
                },
                onClose: { showingQuickJournal = false }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.dayHeaderLabel(for: vm.selectedDayForDayView))
                        .font(.title2.weight(.black))
                    Text(daySubtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    vm.openComposer(day: vm.selectedDayForDayView, period: vm.visibleSlots.first?.period ?? 1)
                } label: {
                    Label("Nueva sesión", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await vm.goToPreviousDayInDayView() }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(minWidth: 32, minHeight: 32)
                }
                Button("Hoy") {
                    Task { await vm.goToTodayInDayView() }
                }
                .frame(minHeight: 32)
                Button {
                    Task { await vm.goToNextDayInDayView() }
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(minWidth: 32, minHeight: 32)
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)

            if let completionUndo {
                PlannerInlineBanner(message: "Sesión marcada como impartida.")
                    .overlay(alignment: .trailing) {
                        Button("Deshacer") {
                            undoCompletion(completionUndo)
                        }
                        .font(.subheadline.weight(.bold))
                        .padding(.trailing, 14)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var closingSummary: some View {
        if !sessions.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(pendingJournalCount == 0 ? EvaluationDesign.success : IOSAppStyle.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(completedCount) de \(sessions.count) impartidas")
                        .font(.subheadline.weight(.bold))
                    Text(pendingJournalCount == 0 ? "Todos los diarios están al día." : "\(pendingJournalCount) diario(s) pendiente(s) de cerrar.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showingQuickJournal = true
                } label: {
                    Label("Diario rápido", systemImage: "bolt.badge.clock")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if let firstPending = firstPendingJournalSession {
                    Button("Cerrar") {
                        onOpenSession(firstPending)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private var timeline: some View {
        if sessions.isEmpty && vm.visibleSlots.isEmpty {
            PlannerEmptyState(
                title: "Sin sesiones este día",
                systemImage: "calendar.badge.plus",
                message: "Usa Nueva sesión o vuelve a Semana para concretar una franja."
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(timelineRows) { row in
                    rowView(for: row)
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(for row: PlannerDayTimelineRow) -> some View {
        switch row {
        case .session(let session):
            PlannerDaySessionRow(
                vm: vm,
                session: session,
                isCurrent: isCurrent(session),
                isNext: session.id == nextSession?.id,
                onOpen: { onOpenSession(session) },
                onComplete: { completeSession(session) },
                onQuickNote: {
                    quickNoteText = ""
                    quickNoteSession = session
                }
            )
        case .empty(let slot):
            PlannerDayEmptySlotRow(slot: slot) {
                vm.openComposer(day: vm.selectedDayForDayView, period: slot.period)
            }
        case .gap(let start, let end):
            PlannerDayGapRow(start: start, end: end)
        case .now:
            PlannerDayNowMarker(time: currentTime)
        }
    }

    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                dragTranslation = value.translation.width
            }
            .onEnded { value in
                defer { dragTranslation = 0 }
                let translation = value.translation
                guard abs(translation.width) > abs(translation.height) * 1.5,
                      abs(translation.width) > 60 else { return }
                if translation.width < 0 {
                    Task { await vm.goToNextDayInDayView() }
                } else {
                    Task { await vm.goToPreviousDayInDayView() }
                }
            }
    }

    private var daySubtitle: String {
        if let nextSession {
            return "Próxima: \(nextSession.groupName) · \(nextSession.startTime ?? vm.timeLabel(for: Int(nextSession.period)))"
        }
        return "\(sessions.count) sesiones planificadas"
    }

    private var nextSession: PlanningSession? {
        sessions.first { session in
            session.status != .completed && vm.summary(for: session.id)?.status != .completed
        }
    }

    private var completedCount: Int {
        sessions.count { $0.status == .completed }
    }

    private var pendingJournalCount: Int {
        sessions.count { session in
            session.status == .completed && vm.summary(for: session.id)?.status != .completed
        }
    }

    private var firstPendingJournalSession: PlanningSession? {
        sessions.first { session in
            session.status == .completed && vm.summary(for: session.id)?.status != .completed
        }
    }

    private var isTodayAndCurrentWeek: Bool {
        let current = PlannerCalendar.currentIsoYearWeek
        guard vm.week == current.week, vm.year == current.year else { return false }
        return vm.selectedDayForDayView == todayWeekdayIndex
    }

    private var todayWeekdayIndex: Int {
        let calendar = Calendar(identifier: .iso8601)
        return ((calendar.component(.weekday, from: currentTime) + 5) % 7) + 1
    }

    private var currentMinutesOfDay: Int {
        let calendar = Calendar.current
        return calendar.component(.hour, from: currentTime) * 60 + calendar.component(.minute, from: currentTime)
    }

    private var timelineRows: [PlannerDayTimelineRow] {
        let slots = vm.visibleSlots.sorted { (minutes(from: $0.startTime) ?? 0) < (minutes(from: $1.startTime) ?? 0) }
        let sessionsByPeriod = Dictionary(grouping: sessions, by: { Int($0.period) })
        var matchedSessionIds = Set<Int64>()
        var rows: [PlannerDayTimelineRow] = []
        var nowInserted = !isTodayAndCurrentWeek
        let nowMinutes = currentMinutesOfDay

        func insertNowIfNeeded(before startMinute: Int?) {
            guard !nowInserted, let startMinute, nowMinutes < startMinute else { return }
            rows.append(.now)
            nowInserted = true
        }

        for (index, slot) in slots.enumerated() {
            insertNowIfNeeded(before: minutes(from: slot.startTime))

            if let matchingSessions = sessionsByPeriod[slot.period], !matchingSessions.isEmpty {
                for session in matchingSessions.sorted(by: { ($0.startTime ?? "") < ($1.startTime ?? "") }) {
                    rows.append(.session(session))
                    matchedSessionIds.insert(session.id)
                }
            } else {
                rows.append(.empty(slot))
            }

            if index < slots.count - 1 {
                let next = slots[index + 1]
                if let end = minutes(from: slot.endTime), let nextStart = minutes(from: next.startTime), nextStart - end > 1 {
                    rows.append(.gap(start: slot.endTime, end: next.startTime))
                }
            }
        }

        let leftover = sessions.filter { !matchedSessionIds.contains($0.id) }
        for session in leftover.sorted(by: { ($0.startTime ?? "") < ($1.startTime ?? "") }) {
            rows.append(.session(session))
        }

        if !nowInserted, isTodayAndCurrentWeek {
            rows.append(.now)
        }

        return rows
    }

    private func completeSession(_ session: PlanningSession) {
        let previousStatus = session.status
        undoDismissTask?.cancel()
        Task { await vm.setSessionStatus(session, status: .completed) }
        withAnimation {
            completionUndo = (session, previousStatus)
        }
        undoDismissTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { completionUndo = nil }
        }
    }

    private func undoCompletion(_ pending: (session: PlanningSession, previousStatus: SessionStatus)) {
        undoDismissTask?.cancel()
        withAnimation { completionUndo = nil }
        Task { await vm.setSessionStatus(pending.session, status: pending.previousStatus) }
    }

    private func isCurrent(_ session: PlanningSession) -> Bool {
        guard let start = session.startTime, let end = session.endTime else { return false }
        guard isTodayAndCurrentWeek, Int(session.dayOfWeek) == vm.selectedDayForDayView else { return false }
        guard let startMinutes = minutes(from: start), let endMinutes = minutes(from: end) else { return false }
        return currentMinutesOfDay >= startMinutes && currentMinutesOfDay <= endMinutes
    }

    private func minutes(from value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return hour * 60 + minute
    }
}

private struct PlannerDaySessionRow: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let session: PlanningSession
    let isCurrent: Bool
    let isNext: Bool
    let onOpen: () -> Void
    let onComplete: () -> Void
    let onQuickNote: () -> Void

    @State private var isHovering = false

    private var tint: Color { Color(hex: vm.classColorHex(for: session.groupId)) }
    private var stateTint: Color { vm.sessionStateTint(for: session) }

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
                    PlannerStatusBadge(
                        label: vm.sessionStateLabel(for: session),
                        systemImage: vm.sessionStateIcon(for: session),
                        tint: stateTint
                    )
                }

                Text(session.teachingUnitName.nilIfBlank ?? "Sesión sin título")
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)

                if let objective = session.objectives.nilIfBlank ?? session.activities.nilIfBlank {
                    Text(objective)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(isCurrent ? 4 : 2)
                }

                HStack(spacing: 8) {
                    Button("Abrir ficha", action: onOpen)
                        .buttonStyle(.borderedProminent)
                    Button("Impartida", action: onComplete)
                        .buttonStyle(.bordered)
                        .disabled(session.status == .completed)
                    Button {
                        onQuickNote()
                    } label: {
                        Label("Nota rápida", systemImage: "text.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(isCurrent ? 20 : 16)
        .plannerGlassPanel(.content, cornerRadius: 16)
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(EvaluationDesign.success.opacity(0.55), lineWidth: 1.5)
            }
        }
        .overlay {
            if isHovering {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            }
        }
        .shadow(color: .black.opacity(isCurrent ? 0.10 : 0), radius: isCurrent ? 14 : 0, x: 0, y: 6)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture(count: 2, perform: onOpen)
    }

    private var timeRange: String {
        if let start = session.startTime, let end = session.endTime {
            return "\(start)-\(end)"
        }
        return vm.timeLabel(for: Int(session.period))
    }
}

private struct PlannerDayEmptySlotRow: View {
    let slot: PlannerVisibleSlot
    let onCreate: () -> Void

    var body: some View {
        Button(action: onCreate) {
            HStack(spacing: 16) {
                Text(slot.label)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 104, alignment: .leading)

                Label("Franja libre · Crear sesión", systemImage: "plus.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(EvaluationDesign.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PlannerDayGapRow: View {
    let start: String
    let end: String

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(EvaluationDesign.border)
                .frame(width: 104, height: 1)
            Image(systemName: "cup.and.saucer")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Recreo · \(start)-\(end)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(EvaluationDesign.border)
                .frame(height: 1)
        }
        .padding(.vertical, 2)
    }
}

private struct PlannerDayNowMarker: View {
    let time: Date

    private var label: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: time)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("Ahora \(label)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(EvaluationDesign.accent, in: Capsule())
            Rectangle()
                .fill(EvaluationDesign.accent)
                .frame(height: 2)
        }
    }
}

private struct PlannerQuickNoteSheet: View {
    let session: PlanningSession
    @Binding var text: String
    let onCancel: () -> Void
    let onSave: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.groupName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(session.teachingUnitName.nilIfBlank ?? "Sesión sin título")
                        .font(.headline.weight(.semibold))
                }

                TextEditor(text: $text)
                    .frame(minHeight: 140)
                    .focused($isFocused)
                    .padding(8)
                    .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Spacer()
            }
            .padding(EvaluationDesign.screenPadding)
            .navigationTitle("Nota rápida")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: onSave)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear { isFocused = true }
        .presentationDetents([.medium])
    }
}

struct PlannerEmptyState: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline.weight(.bold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding(24)
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
