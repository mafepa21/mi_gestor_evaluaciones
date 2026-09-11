import SwiftUI
import MiGestorKit

struct PlannerMonthCalendarView: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    var onOpenSession: ((PlanningSession) -> Void)? = nil
    var onOpenSettings: (() -> Void)? = nil
    var showsInlineNavigation: Bool = true
    var showsInlineGroupFilter: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @State private var selectedOverflowDay: PlannerMonthDay? = nil

    private let weekdayShortNames = ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"]
    private let weekdayFullNames = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]

    var body: some View {
        let grid = vm.buildMonthGrid()

        VStack(spacing: 0) {
            monthHeader(grid: grid)
                .padding(.horizontal, EvaluationDesign.screenPadding)
                .padding(.vertical, 8)

            weekdayHeaderRow
                .padding(.horizontal, EvaluationDesign.screenPadding)
                .padding(.bottom, 6)

            monthCalendarGrid(grid: grid)
                .padding(.horizontal, EvaluationDesign.screenPadding)
                .padding(.bottom, EvaluationDesign.screenPadding)
        }
        .task {
            await vm.reloadMonthData()
        }
        .sheet(item: $selectedOverflowDay) { day in
            PlannerMonthDaySessionsSheet(
                day: day,
                vm: vm,
                onOpenSession: { session in
                    selectedOverflowDay = nil
                    onOpenSession?(session)
                }
            )
        }
    }

    // MARK: - Header
    @ViewBuilder
    private func monthHeader(grid: PlannerMonthGrid) -> some View {
        HStack(spacing: 12) {
            if showsInlineNavigation {
                HStack(spacing: 6) {
                    Button {
                        Task { await vm.previousMonth() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel("Mes anterior")

                    Button {
                        Task { await vm.goToTodayMonth() }
                    } label: {
                        Text("Hoy")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel("Ir al mes actual")

                    Button {
                        Task { await vm.nextMonth() }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel("Mes siguiente")
                }
            }

            Text(grid.monthName)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)

            HStack(spacing: 5) {
                Image(systemName: "calendar.badge.clock")
                    .font(.caption.weight(.semibold))
                Text("\(grid.totalSessionsCount) sesiones")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(EvaluationDesign.surfaceSoft, in: Capsule())

            Spacer()

            if showsInlineGroupFilter {
                Picker("Grupo", selection: Binding(
                    get: { vm.selectedGroupId },
                    set: { vm.selectGroup($0) }
                )) {
                    Text("Todos los grupos").tag(Optional<Int64>.none)
                    ForEach(vm.groups, id: \.id) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(maxWidth: 160)
            }

            Button {
                vm.openComposerForDate(vm.monthViewDate)
            } label: {
                Label("Nueva sesión", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
    }

    // MARK: - Weekday Header
    private var weekdayHeaderRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { index in
                let isWeekend = index >= 5
                HStack {
                    Spacer()
                    ViewThatFits {
                        Text(weekdayFullNames[index])
                            .font(.caption.weight(.bold))
                        Text(weekdayShortNames[index])
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(isWeekend ? Color.secondary.opacity(0.7) : Color.primary.opacity(0.85))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isWeekend ? Color.secondary.opacity(0.04) : Color.clear)
                )
            }
        }
    }

    // MARK: - Month Grid
    @ViewBuilder
    private func monthCalendarGrid(grid: PlannerMonthGrid) -> some View {
        GeometryReader { geometry in
            let weekCount = max(1, grid.weeks.count)
            let totalVerticalSpacing = CGFloat(weekCount - 1) * 6
            let availableHeight = max(100, geometry.size.height - totalVerticalSpacing)
            let rowHeight = max(105, availableHeight / CGFloat(weekCount))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(0..<grid.weeks.count, id: \.self) { weekIndex in
                        let week = grid.weeks[weekIndex]
                        HStack(spacing: 6) {
                            ForEach(week) { day in
                                PlannerMonthDayCell(
                                    day: day,
                                    vm: vm,
                                    onOpenSession: onOpenSession,
                                    onSelectOverflow: {
                                        selectedOverflowDay = day
                                    }
                                )
                                .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: .infinity)
                            }
                        }
                        .frame(minHeight: rowHeight)
                    }
                }
            }
        }
    }
}

// MARK: - Day Cell
private struct PlannerMonthDayCell: View {
    let day: PlannerMonthDay
    @ObservedObject var vm: PlannerWorkspaceViewModel
    var onOpenSession: ((PlanningSession) -> Void)?
    var onSelectOverflow: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            cellHeader

            if let milestone = day.milestones.first {
                milestoneBadge(milestone)
            }

            sessionsList

            Spacer(minLength: 0)
        }
        .padding(6)
        .background(cellBackground)
        .overlay(cellBorder)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isHovered = $0 }
        .contextMenu {
            Button {
                Task { await vm.jumpToDayView(for: day.date) }
            } label: {
                Label("Abrir vista Día", systemImage: "calendar.day.timeline.left")
            }

            Button {
                vm.openComposerForDate(day.date)
            } label: {
                Label("Nueva sesión en este día…", systemImage: "plus")
            }

            Button {
                Task { await vm.jumpToWeekView(for: day.date) }
            } label: {
                Label("Ir a la semana", systemImage: "calendar.badge.clock")
            }
        }
    }

    // MARK: - Cell Header
    private var cellHeader: some View {
        HStack(alignment: .center, spacing: 4) {
            if day.isToday {
                Text("\(day.dayNumber)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(EvaluationDesign.accent))
            } else {
                Text("\(day.dayNumber)")
                    .font(.system(size: 13, weight: day.isCurrentMonth ? .bold : .medium, design: .rounded))
                    .foregroundStyle(day.isCurrentMonth ? (day.isWeekend ? Color.secondary : Color.primary) : Color.secondary.opacity(0.4))
                    .frame(width: 22, height: 22)
            }

            Spacer(minLength: 0)

            if isHovered || day.isToday {
                Button {
                    Task { await vm.jumpToDayView(for: day.date) }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Abrir día \(day.dayNumber)")

                Button {
                    vm.openComposerForDate(day.date)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EvaluationDesign.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Añadir sesión el día \(day.dayNumber)")
            }
        }
    }

    // MARK: - Milestone Badge
    @ViewBuilder
    private func milestoneBadge(_ milestone: PlannerDayMilestone) -> some View {
        HStack(spacing: 3) {
            Image(systemName: milestone.category.iconName)
                .font(.system(size: 8, weight: .bold))
            Text(milestone.title)
                .font(.system(size: 9, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(milestone.category.accentColor)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(milestone.category.accentColor.opacity(0.12))
        )
    }

    // MARK: - Sessions List
    @ViewBuilder
    private var sessionsList: some View {
        let maxVisible = 3
        let visibleSessions = Array(day.sessions.prefix(maxVisible))
        let remaining = day.sessions.count - maxVisible

        VStack(spacing: 3) {
            ForEach(visibleSessions, id: \.id) { session in
                PlannerMonthSessionPill(
                    session: session,
                    classColorHex: vm.classColorHex(for: session.groupId),
                    onTap: { onOpenSession?(session) }
                )
            }

            if remaining > 0 {
                Button {
                    onSelectOverflow()
                } label: {
                    HStack(spacing: 2) {
                        Text("+\(remaining) más")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(EvaluationDesign.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(EvaluationDesign.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Background & Border
    private var cellBackground: some View {
        Group {
            if day.isToday {
                Color.accentColor.opacity(0.09)
            } else if !day.isCurrentMonth {
                Color.secondary.opacity(0.03)
            } else if day.isWeekend {
                EvaluationDesign.surfaceSoft.opacity(0.4)
            } else {
                EvaluationDesign.surfaceSoft
            }
        }
    }

    private var cellBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(
                day.isToday ? Color.accentColor.opacity(0.45) :
                (day.isHoliday ? Color.red.opacity(0.3) : Color.secondary.opacity(0.1)),
                lineWidth: day.isToday ? 1.5 : 1
            )
    }
}

// MARK: - Session Pill
private struct PlannerMonthSessionPill: View {
    let session: PlanningSession
    let classColorHex: String
    let onTap: () -> Void

    private var tint: Color {
        Color(hex: classColorHex)
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: 3)

                Text(session.period > 0 ? "\(session.period)ª" : "")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint)

                Text(session.groupName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                let title = session.teachingUnitName.nilIfBlank ?? session.objectives
                if !title.isEmpty {
                    Text("· \(title)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if session.status == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(EvaluationDesign.success)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Overflow Detail Sheet
struct PlannerMonthDaySessionsSheet: View {
    let day: PlannerMonthDay
    @ObservedObject var vm: PlannerWorkspaceViewModel
    var onOpenSession: (PlanningSession) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Cabecera del día
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Día \(day.dayNumber) · \(day.dateIso)")
                                .font(.title2.weight(.bold))
                            Text("\(day.sessions.count) sesiones planificadas")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()

                        Button {
                            Task {
                                dismiss()
                                await vm.jumpToDayView(for: day.date)
                            }
                        } label: {
                            Label("Abrir vista Día", systemImage: "calendar.day.timeline.left")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.bottom, 8)

                    if !day.milestones.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Hitos y eventos del día")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)

                            ForEach(day.milestones) { milestone in
                                HStack(spacing: 8) {
                                    Image(systemName: milestone.category.iconName)
                                        .foregroundStyle(milestone.category.accentColor)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(milestone.title)
                                            .font(.subheadline.weight(.semibold))
                                        if let subtitle = milestone.subtitle {
                                            Text(subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(milestone.category.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sesiones")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        if day.sessions.isEmpty {
                            Text("No hay sesiones programadas para este día.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 16)
                        } else {
                            ForEach(day.sessions, id: \.id) { session in
                                let tint = Color(hex: vm.classColorHex(for: session.groupId))
                                Button {
                                    onOpenSession(session)
                                } label: {
                                    HStack(spacing: 12) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(tint)
                                            .frame(width: 4)

                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack {
                                                Text(session.period > 0 ? "\(session.period)ª franja" : "Sesión")
                                                    .font(.caption.weight(.bold).monospaced())
                                                    .foregroundStyle(tint)

                                                if let start = session.startTime, let end = session.endTime {
                                                    Text("(\(start) - \(end))")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }

                                                Spacer()

                                                Text(session.groupName)
                                                    .font(.caption.weight(.bold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(tint.opacity(0.12), in: Capsule())
                                            }

                                            Text(session.teachingUnitName.nilIfBlank ?? "Sin unidad asignada")
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(.primary)

                                            if !session.objectives.isEmpty {
                                                Text(session.objectives)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Detalle del día")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(minWidth: 460, minHeight: 480)
        #endif
    }
}
