import SwiftUI
import MiGestorKit

enum PlannerSessionDragPayload {
    static let prefix = "planner-session:"

    static func encode(_ sessionId: Int64) -> String {
        prefix + String(sessionId)
    }

    static func decode(_ value: String) -> Int64? {
        guard value.hasPrefix(prefix) else { return nil }
        return Int64(value.dropFirst(prefix.count))
    }
}

struct PlannerWeekMiniatureGrid: View {
    @ObservedObject var weekBoard: PlannerWeekBoardStore
    let vm: PlannerWorkspaceViewModel
    @Binding var selectedCell: PlannerCellKey?
    @Binding var selectedDay: Int?
    let onOpenSession: (PlanningSession) -> Void
    var onDropSession: ((Int64, Int, Int) -> Void)? = nil
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags

    private let timeAxisWidth: CGFloat = 72
    private let headerHeight: CGFloat = 40
    private let gridSpacing: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let days = weekBoard.weekRenderModel.visibleDays
            let slots = weekBoard.weekRenderModel.visibleSlots
            let columnWidth = gridWidth(proxy.size.width, days: days.count)
            let rowHeight = gridHeight(proxy.size.height, rows: slots.count)

            // El grid tiene celdas de tamaño fijo calculado geométricamente; a partir de
            // tamaños de accesibilidad grandes el texto rompería el layout, así que se
            // limita el crecimiento de Dynamic Type aquí (el resto del Planner escala libre).
            VStack(spacing: gridSpacing) {
                HStack(spacing: gridSpacing) {
                    Text("Franja")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: timeAxisWidth, height: headerHeight)

                    ForEach(days, id: \.self) { day in
                        let isToday = day == todayDayIndex
                        Button {
                            withAnimation(uiFeatureFlags.interactionAnimation) {
                                selectedDay = day
                                selectedCell = nil
                            }
                        } label: {
                            VStack(spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(vm.dayLabel(for: day))
                                        .font(.caption.weight(.bold))
                                    if isToday {
                                        Circle()
                                            .fill(selectedDay == day ? Color.white : EvaluationDesign.accent)
                                            .frame(width: 4, height: 4)
                                    }
                                }
                                .foregroundStyle(selectedDay == day ? Color.white : Color.primary)
                                if let dateStr = dateLabel(for: day), !dateStr.isEmpty {
                                    Text(dateStr)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(selectedDay == day ? Color.white.opacity(0.8) : .secondary)
                                }
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(width: columnWidth, height: headerHeight)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selectedDay == day ? EvaluationDesign.accent : EvaluationDesign.surfaceSoft)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isToday && selectedDay != day ? EvaluationDesign.accent.opacity(0.6) : .clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Ver día \(vm.dayHeaderLabel(for: day))\(isToday ? ", hoy" : "")")
                    }
                }

                ForEach(slots, id: \.period) { slot in
                    let isCurrentPeriod = slot.period == currentPeriodNumber
                    HStack(spacing: gridSpacing) {
                        VStack(spacing: 2) {
                            Text("P\(slot.period)")
                                .font(.caption2.weight(.bold))
                            Text(slot.label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(isCurrentPeriod ? EvaluationDesign.accent : Color.primary)
                        .frame(width: timeAxisWidth, height: rowHeight)
                        .background(
                            isCurrentPeriod ? EvaluationDesign.accent.opacity(0.14) : EvaluationDesign.surfaceSoft,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )

                        ForEach(days, id: \.self) { day in
                            let key = PlannerCellKey(day: day, period: slot.period)
                            let entries = weekBoard.weekRenderModel.entriesByCell[key] ?? []
                            PlannerWeekMiniatureCell(
                                entries: entries,
                                isHoliday: weekBoard.holidayDays.contains(day),
                                isSelected: selectedCell == key,
                                isToday: day == todayDayIndex,
                                vm: vm,
                                onTap: {
                                    withAnimation(uiFeatureFlags.interactionAnimation) {
                                        selectedCell = key
                                        selectedDay = nil
                                    }
                                },
                                onOpenSession: onOpenSession,
                                onDropSession: onDropSession.map { handler in
                                    { sessionId in handler(sessionId, day, slot.period) }
                                }
                            )
                            .frame(width: columnWidth, height: rowHeight)
                            .accessibilityLabel(accessibilityLabel(day: day, slot: slot, entries: entries))
                        }
                    }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private var isCurrentWeek: Bool {
        weekBoard.week == PlannerCalendar.currentIsoWeek && weekBoard.year == PlannerCalendar.currentIsoYear
    }

    private var todayDayIndex: Int? {
        guard isCurrentWeek else { return nil }
        let calendar = Calendar(identifier: .iso8601)
        return ((calendar.component(.weekday, from: Date()) + 5) % 7) + 1
    }

    private var currentPeriodNumber: Int? {
        guard isCurrentWeek, todayDayIndex != nil else { return nil }
        let calendar = Calendar.current
        let nowMinutes = calendar.component(.hour, from: Date()) * 60 + calendar.component(.minute, from: Date())
        return weekBoard.weekRenderModel.visibleSlots.first { slot in
            guard let start = minutes(from: slot.startTime), let end = minutes(from: slot.endTime) else { return false }
            return nowMinutes >= start && nowMinutes <= end
        }?.period
    }

    private func minutes(from value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return hour * 60 + minute
    }

    private func gridWidth(_ totalWidth: CGFloat, days: Int) -> CGFloat {
        guard days > 0 else { return 0 }
        let spacing = gridSpacing * CGFloat(days)
        return max((totalWidth - timeAxisWidth - spacing) / CGFloat(days), 44)
    }

    private func gridHeight(_ totalHeight: CGFloat, rows: Int) -> CGFloat {
        guard rows > 0 else { return 0 }
        let spacing = gridSpacing * CGFloat(rows)
        return max((totalHeight - headerHeight - spacing) / CGFloat(rows), 36)
    }

    private func dateLabel(for day: Int) -> String? {
        let days = IsoWeekHelper.shared.daysOf(isoWeek: Int32(weekBoard.week), year: Int32(weekBoard.year))
        guard day >= 1 && day <= days.count else { return nil }
        let date = days[day - 1]
        return "\(date.dayOfMonth)/\(date.monthNumber)"
    }


    private func accessibilityLabel(day: Int, slot: PlannerVisibleSlot, entries: [PlannerWeekCellEntry]) -> String {
        let dayLabel = vm.dayHeaderLabel(for: day)
        guard !entries.isEmpty else { return "\(dayLabel), \(slot.label), sin sesión" }
        return "\(dayLabel), \(slot.label), \(entries.count) sesiones"
    }
}

private struct PlannerCellDragSourceModifier: ViewModifier {
    let sessionId: Int64?

    func body(content: Content) -> some View {
        if let sessionId {
            content.draggable(PlannerSessionDragPayload.encode(sessionId))
        } else {
            content
        }
    }
}

private struct PlannerCellDropTargetModifier: ViewModifier {
    let onDropSession: ((Int64) -> Void)?
    @Binding var isTargeted: Bool

    func body(content: Content) -> some View {
        if let onDropSession {
            content.dropDestination(for: String.self) { items, _ in
                guard let payload = items.first, let sessionId = PlannerSessionDragPayload.decode(payload) else {
                    return false
                }
                onDropSession(sessionId)
                return true
            } isTargeted: { targeted in
                isTargeted = targeted
            }
        } else {
            content
        }
    }
}

private struct PlannerWeekMiniatureCell: View {
    let entries: [PlannerWeekCellEntry]
    let isHoliday: Bool
    let isSelected: Bool
    let isToday: Bool
    let vm: PlannerWorkspaceViewModel
    let onTap: () -> Void
    let onOpenSession: (PlanningSession) -> Void
    var onDropSession: ((Int64) -> Void)? = nil

    @State private var isDropTargeted = false
    @State private var isHovering = false

    var body: some View {
        cellButton
            .modifier(PlannerCellDragSourceModifier(sessionId: draggableSessionId))
            .modifier(
                PlannerCellDropTargetModifier(
                    onDropSession: onDropSession,
                    isTargeted: $isDropTargeted
                )
            )
            .contextMenu {
                contextMenuContent
            }
            .onHover { hovering in
                isHovering = hovering
            }
            // Doble click en Mac abre la ficha directamente; el tap sencillo
            // (Button) sigue seleccionando la celda como siempre.
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    openSessionDirectly()
                }
            )
    }

    private func openSessionDirectly() {
        guard entries.count == 1,
              let entry = entries.first,
              entry.kind == .session,
              let sessionId = entry.sessionId,
              let session = vm.sessions.first(where: { $0.id == sessionId }) else { return }
        onOpenSession(session)
    }

    private var cellButton: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fillColor)

                if let entry = primaryEntry, !isHoliday {
                    Text(abbreviation(for: entry))
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(groupTint(for: entry))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 2)
                }

                if !isHoliday, let entry = primaryEntry, entries.count == 1 {
                    VStack {
                        HStack {
                            Spacer()
                            statusBadge(for: entry)
                        }
                        Spacer()
                    }
                    .padding(3)
                }

                if entries.count > 1 {
                    VStack {
                        Spacer()
                        HStack(spacing: 2) {
                            ForEach(entries.prefix(3)) { entry in
                                Circle()
                                    .fill(groupTint(for: entry))
                                    .frame(width: 5, height: 5)
                            }
                            if entries.count > 3 {
                                Text("+\(entries.count - 3)")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.bottom, 3)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(strokeColor, lineWidth: strokeWidth)
            )
            .brightness(isHovering && !isSelected ? 0.06 : 0)
            .scaleEffect(isSelected ? 0.96 : (isDropTargeted ? 1.04 : 1))
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDropTargeted)
            .animation(.easeOut(duration: 0.12), value: isHovering)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        if entries.count == 1,
           let entry = entries.first,
           entry.kind == .session,
           let sessionId = entry.sessionId,
           let session = vm.sessions.first(where: { $0.id == sessionId }) {
            Button {
                onOpenSession(session)
            } label: {
                Label("Abrir diario", systemImage: "book.pages")
            }
            Button {
                vm.openComposer(for: session)
            } label: {
                Label("Editar sesión", systemImage: "pencil")
            }
            Button {
                Task { await vm.markCompleted(session) }
            } label: {
                Label("Marcar impartida", systemImage: "checkmark.circle")
            }
            .disabled(session.status == .completed)
            Button {
                Task { await vm.copySessionToNextWeek(session) }
            } label: {
                Label("Copiar a la semana siguiente", systemImage: "doc.on.doc")
            }
        }
    }

    private var strokeColor: Color {
        if isDropTargeted { return EvaluationDesign.accent }
        if isSelected { return EvaluationDesign.accent }
        if isToday { return EvaluationDesign.accent.opacity(0.55) }
        return EvaluationDesign.border.opacity(0.65)
    }

    private var strokeWidth: CGFloat {
        (isSelected || isDropTargeted) ? 2 : (isToday ? 1.5 : 1)
    }

    private var primaryEntry: PlannerWeekCellEntry? { entries.first }

    /// Solo las celdas con exactamente una sesión real se pueden arrastrar;
    /// con varias entradas el origen sería ambiguo.
    private var draggableSessionId: Int64? {
        guard entries.count == 1,
              let entry = entries.first,
              entry.kind == .session else { return nil }
        return entry.sessionId
    }

    private func groupTint(for entry: PlannerWeekCellEntry) -> Color {
        Color(hex: entry.classColorHex)
    }

    private func abbreviation(for entry: PlannerWeekCellEntry) -> String {
        let words = entry.className
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
        if words.isEmpty { return "" }
        if words.count == 1 {
            return String(words[0].prefix(3)).uppercased()
        }
        return String(words.prefix(3).compactMap(\.first)).uppercased()
    }

    @ViewBuilder
    private func statusBadge(for entry: PlannerWeekCellEntry) -> some View {
        Image(systemName: statusIcon(for: entry))
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(.white)
            .padding(3)
            .background(statusTint(for: entry), in: Circle())
    }

    private func statusIcon(for entry: PlannerWeekCellEntry) -> String {
        if entry.kind == .scheduledSlot { return "plus" }
        return vm.sessionStateIcon(sessionStatus: entry.sessionStatus, journalStatus: entry.journalStatus)
    }

    private func statusTint(for entry: PlannerWeekCellEntry) -> Color {
        if entry.kind == .scheduledSlot { return IOSAppStyle.warning }
        return vm.sessionStateTint(sessionStatus: entry.sessionStatus, journalStatus: entry.journalStatus)
    }

    private var fillColor: Color {
        if isHoliday { return Color.secondary.opacity(0.16) }
        guard let entry = primaryEntry else { return Color.secondary.opacity(0.12) }
        return groupTint(for: entry).opacity(entry.kind == .scheduledSlot ? 0.14 : 0.22)
    }
}
