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
    @ObservedObject var vm: PlannerWorkspaceViewModel
    @Binding var selectedCell: PlannerCellKey?
    @Binding var selectedDay: Int?
    var onDropSession: ((Int64, Int, Int) -> Void)? = nil

    private let timeAxisWidth: CGFloat = 72
    private let headerHeight: CGFloat = 40
    private let gridSpacing: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let days = vm.weekRenderModel.visibleDays
            let slots = vm.weekRenderModel.visibleSlots
            let columnWidth = gridWidth(proxy.size.width, days: days.count)
            let rowHeight = gridHeight(proxy.size.height, rows: slots.count)

            VStack(spacing: gridSpacing) {
                HStack(spacing: gridSpacing) {
                    Text("Franja")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: timeAxisWidth, height: headerHeight)

                    ForEach(days, id: \.self) { day in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                selectedDay = day
                                selectedCell = nil
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text(vm.dayLabel(for: day))
                                    .font(.caption.weight(.bold))
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
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Ver día \(vm.dayHeaderLabel(for: day))")
                    }
                }

                ForEach(slots, id: \.period) { slot in
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
                        .frame(width: timeAxisWidth, height: rowHeight)
                        .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        ForEach(days, id: \.self) { day in
                            let key = PlannerCellKey(day: day, period: slot.period)
                            let entries = vm.weekRenderModel.entriesByCell[key] ?? []
                            PlannerWeekMiniatureCell(
                                entries: entries,
                                isHoliday: vm.holidayDays.contains(day),
                                isSelected: selectedCell == key,
                                onTap: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        selectedCell = key
                                        selectedDay = nil
                                    }
                                },
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
        let days = IsoWeekHelper.shared.daysOf(isoWeek: Int32(vm.week), year: Int32(vm.year))
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
    let onTap: () -> Void
    var onDropSession: ((Int64) -> Void)? = nil

    @State private var isDropTargeted = false

    var body: some View {
        cellButton
            .modifier(PlannerCellDragSourceModifier(sessionId: draggableSessionId))
            .modifier(
                PlannerCellDropTargetModifier(
                    onDropSession: onDropSession,
                    isTargeted: $isDropTargeted
                )
            )
    }

    private var cellButton: some View {
        Button(action: onTap) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(fillColor)
                .overlay(alignment: .bottomTrailing) {
                    if entries.count > 1 {
                        Text("\(entries.count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.24), in: Capsule(style: .continuous))
                            .padding(4)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(strokeColor, lineWidth: (isSelected || isDropTargeted) ? 2 : 1)
                )
                .scaleEffect(isSelected ? 0.96 : (isDropTargeted ? 1.04 : 1))
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDropTargeted)
        }
        .buttonStyle(.plain)
    }

    private var strokeColor: Color {
        if isDropTargeted { return EvaluationDesign.accent }
        if isSelected { return EvaluationDesign.accent }
        return EvaluationDesign.border.opacity(0.65)
    }

    /// Solo las celdas con exactamente una sesión real se pueden arrastrar;
    /// con varias entradas el origen sería ambiguo.
    private var draggableSessionId: Int64? {
        guard entries.count == 1,
              let entry = entries.first,
              entry.kind == .session else { return nil }
        return entry.sessionId
    }

    private var fillColor: Color {
        if isHoliday { return Color.secondary.opacity(0.18) }
        guard let entry = entries.first else { return Color.secondary.opacity(0.16) }
        if entries.contains(where: { $0.journalStatus == .completed || $0.sessionStatus == .completed }) {
            return EvaluationDesign.success.opacity(0.82)
        }
        if entry.kind == .scheduledSlot {
            return IOSAppStyle.warning.opacity(0.82)
        }
        return EvaluationDesign.accent.opacity(0.82)
    }
}
