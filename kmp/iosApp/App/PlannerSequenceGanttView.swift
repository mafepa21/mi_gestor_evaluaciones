import SwiftUI
import MiGestorKit

struct PlannerSequenceGanttView: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onOpenSession: (PlanningSession) -> Void

    @State private var selectedRange: PlannerGanttRange = .current
    @State private var selectedGroupId: Int64?
    @State private var expandedSituationIds: Set<String> = []

    private let labelWidth: CGFloat = 208
    private let weekWidth: CGFloat = 64
    private let rowHeight: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if vm.sequenceGroupsEnriched.isEmpty {
                emptyContent
            } else {
                ganttContent
            }
        }
        .padding(EvaluationDesign.screenPadding)
        .task {
            await vm.loadEnrichedSequences()
            expandInitialSituations()
        }
        .appOnChange(of: vm.selectedGroupId) { newValue in
            selectedGroupId = newValue
            Task {
                await vm.loadEnrichedSequences()
                expandInitialSituations()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Secuencia")
                    .font(.title2.weight(.bold))
                Text("Timeline del trimestre por situación de aprendizaje y grupo.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Picker("Periodo", selection: $selectedRange) {
                    Text("Periodo actual").tag(PlannerGanttRange.current)
                    ForEach(sortedEvaluationPeriods, id: \.id) { period in
                        Text(period.name).tag(PlannerGanttRange.period(period.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 176)

                Picker("Grupo", selection: $selectedGroupId) {
                    Text("Todos").tag(Optional<Int64>.none)
                    ForEach(vm.groups, id: \.id) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 176)
            }

            if vm.isLoadingSequences {
                ProgressView()
                    .tint(EvaluationDesign.accent)
            }
        }
    }

    private var emptyContent: some View {
        Group {
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
        }
    }

    private var ganttContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    timelineHeader

                    ForEach(situationRows) { situation in
                        PlannerGanttSituationRow(
                            situation: situation,
                            weeks: visibleWeeks,
                            weekWidth: weekWidth,
                            labelWidth: labelWidth,
                            rowHeight: rowHeight,
                            isExpanded: expandedSituationIds.contains(situation.id),
                            onToggle: {
                                toggle(situation.id)
                            },
                            onOpenSession: onOpenSession
                        )
                    }
                }
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(EvaluationDesign.border, lineWidth: 1)
                )
            }

            legend
        }
    }

    private var timelineHeader: some View {
        HStack(spacing: 0) {
            Text("Situación")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, height: rowHeight, alignment: .leading)
                .padding(.horizontal, 16)
                .background(EvaluationDesign.surfaceSoft)

            ForEach(visibleWeeks, id: \.self) { week in
                Text("S.\(week.week)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(week == currentWeek ? EvaluationDesign.accent : .secondary)
                    .frame(width: weekWidth, height: rowHeight)
                    .background(week == currentWeek ? EvaluationDesign.accent.opacity(0.10) : EvaluationDesign.surfaceSoft)
                    .overlay(alignment: .leading) {
                        if week == currentWeek {
                            Rectangle()
                                .fill(EvaluationDesign.accent)
                                .frame(width: 2)
                        }
                    }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            PlannerGanttLegendItem(label: "Impartida", tint: EvaluationDesign.success)
            PlannerGanttLegendItem(label: "Planificada", tint: EvaluationDesign.accent)
            PlannerGanttLegendItem(label: "Pendiente", tint: IOSAppStyle.warning)
            PlannerGanttLegendItem(label: "Sin asignar", tint: Color.secondary.opacity(0.35))
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var sortedEvaluationPeriods: [PlannerEvaluationPeriod] {
        vm.evaluationPeriods.sorted { ($0.sortOrder, $0.startDateIso) < ($1.sortOrder, $1.startDateIso) }
    }

    private var visibleWeeks: [PlannerGanttWeek] {
        switch selectedRange {
        case .current:
            return PlannerGanttWeek.range(around: Date(), before: 6, after: 6)
        case .period(let periodId):
            guard let period = vm.evaluationPeriods.first(where: { $0.id == periodId }),
                  let weeks = PlannerGanttWeek.range(fromIso: period.startDateIso, toIso: period.endDateIso),
                  !weeks.isEmpty else {
                return PlannerGanttWeek.range(around: Date(), before: 6, after: 6)
            }
            return weeks
        }
    }

    private var currentWeek: PlannerGanttWeek {
        PlannerGanttWeek(date: Date())
    }

    private var filteredGroups: [PlannerSequenceGroup] {
        vm.sequenceGroupsEnriched.filter { group in
            selectedGroupId.map { group.groupId == $0 } ?? true
        }
    }

    private var situationRows: [PlannerGanttSituation] {
        let grouped = Dictionary(grouping: filteredGroups) { group in
            group.sequenceVersionId.map { "seq-\($0)" } ?? "title-\(normalized(group.title))"
        }

        return grouped.compactMap { key, groups in
            guard let first = groups.sorted(by: { $0.title < $1.title }).first else { return nil }
            return PlannerGanttSituation(
                id: key,
                title: first.title,
                groups: groups.sorted { $0.groupName < $1.groupName }
            )
        }
        .sorted { $0.title < $1.title }
    }

    private func toggle(_ id: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            if expandedSituationIds.contains(id) {
                expandedSituationIds.remove(id)
            } else {
                expandedSituationIds.insert(id)
            }
        }
    }

    private func expandInitialSituations() {
        if expandedSituationIds.isEmpty {
            expandedSituationIds = Set(situationRows.prefix(3).map(\.id))
        }
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private enum PlannerGanttRange: Hashable {
    case current
    case period(Int64)
}

struct PlannerGanttWeek: Hashable {
    let year: Int
    let week: Int

    private static var isoCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone.current
        return calendar
    }

    init(year: Int, week: Int) {
        self.year = year
        self.week = week
    }

    init(date: Date) {
        let calendar = Self.isoCalendar
        year = calendar.component(.yearForWeekOfYear, from: date)
        week = calendar.component(.weekOfYear, from: date)
    }

    static func range(around reference: Date, before: Int, after: Int) -> [PlannerGanttWeek] {
        let calendar = isoCalendar
        return (-before...after).compactMap { offset in
            calendar.date(byAdding: .weekOfYear, value: offset, to: reference)
                .map(PlannerGanttWeek.init(date:))
        }
    }

    static func range(fromIso startIso: String, toIso endIso: String) -> [PlannerGanttWeek]? {
        guard let start = isoDate(startIso), let end = isoDate(endIso), start <= end else { return nil }
        let calendar = isoCalendar
        var weeks: [PlannerGanttWeek] = []
        var cursor = start
        // Límite de seguridad: un periodo de evaluación nunca supera un curso escolar.
        while cursor <= end && weeks.count < 60 {
            weeks.append(PlannerGanttWeek(date: cursor))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        return weeks
    }

    private static func isoDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = isoCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

private struct PlannerGanttSituation: Identifiable {
    let id: String
    let title: String
    let groups: [PlannerSequenceGroup]

    var completed: Int { groups.reduce(0) { $0 + $1.completedCount } }
    var total: Int { groups.reduce(0) { $0 + $1.totalSessionsCount } }
    var pending: Int { groups.reduce(0) { $0 + $1.pendingCount } }
}

private struct PlannerGanttSituationRow: View {
    let situation: PlannerGanttSituation
    let weeks: [PlannerGanttWeek]
    let weekWidth: CGFloat
    let labelWidth: CGFloat
    let rowHeight: CGFloat
    let isExpanded: Bool
    let onToggle: () -> Void
    let onOpenSession: (PlanningSession) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(situation.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("\(situation.completed) de \(situation.total) sesiones · \(situation.pending) pendientes")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                    }
                    .frame(width: labelWidth, height: rowHeight, alignment: .leading)
                    .padding(.horizontal, 16)
                    .background(EvaluationDesign.surfaceSoft.opacity(0.72))

                    PlannerGanttTimelineCells(
                        sessions: situation.groups.flatMap(\.rows),
                        weeks: weeks,
                        weekWidth: weekWidth,
                        rowHeight: rowHeight,
                        onOpenSession: onOpenSession
                    )
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(situation.groups) { group in
                    PlannerGanttGroupRow(
                        group: group,
                        weeks: weeks,
                        weekWidth: weekWidth,
                        labelWidth: labelWidth,
                        rowHeight: rowHeight,
                        onOpenSession: onOpenSession
                    )
                }
            }
        }
    }
}

private struct PlannerGanttGroupRow: View {
    let group: PlannerSequenceGroup
    let weeks: [PlannerGanttWeek]
    let weekWidth: CGFloat
    let labelWidth: CGFloat
    let rowHeight: CGFloat
    let onOpenSession: (PlanningSession) -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.groupName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(group.plannedCount) planificadas")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: labelWidth, height: rowHeight, alignment: .leading)
            .padding(.horizontal, 40)
            .background(EvaluationDesign.surfaceSoft.opacity(0.36))

            PlannerGanttTimelineCells(
                sessions: group.rows,
                weeks: weeks,
                weekWidth: weekWidth,
                rowHeight: rowHeight,
                onOpenSession: onOpenSession
            )
        }
    }
}

private struct PlannerGanttTimelineCells: View {
    let sessions: [PlannerSequenceRow]
    let weeks: [PlannerGanttWeek]
    let weekWidth: CGFloat
    let rowHeight: CGFloat
    let onOpenSession: (PlanningSession) -> Void

    private let maxVisibleBlocks = 4

    var body: some View {
        HStack(spacing: 0) {
            ForEach(weeks, id: \.self) { week in
                let rows = rowsForWeek(week)
                ZStack {
                    Rectangle()
                        .fill(Color.clear)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.10))
                        .frame(width: 1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if rows.isEmpty {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.secondary.opacity(0.16))
                            .frame(width: weekWidth - 24, height: 8)
                    } else if rows.count <= maxVisibleBlocks {
                        HStack(spacing: 4) {
                            ForEach(rows) { row in
                                PlannerGanttSessionBlock(row: row, onOpenSession: onOpenSession)
                            }
                        }
                    } else {
                        HStack(spacing: 4) {
                            ForEach(rows.prefix(maxVisibleBlocks - 1)) { row in
                                PlannerGanttSessionBlock(row: row, onOpenSession: onOpenSession)
                            }
                            PlannerGanttOverflowBlock(
                                rows: Array(rows.dropFirst(maxVisibleBlocks - 1)),
                                onOpenSession: onOpenSession
                            )
                        }
                    }
                }
                .frame(width: weekWidth, height: rowHeight)
            }
        }
    }

    private func rowsForWeek(_ week: PlannerGanttWeek) -> [PlannerSequenceRow] {
        sessions.filter { row in
            guard let session = row.planningSession else { return false }
            return Int(session.weekNumber) == week.week && Int(session.year) == week.year
        }
    }
}

private struct PlannerGanttOverflowBlock: View {
    let rows: [PlannerSequenceRow]
    let onOpenSession: (PlanningSession) -> Void

    var body: some View {
        Menu {
            ForEach(rows) { row in
                if let session = row.planningSession {
                    Button {
                        onOpenSession(session)
                    } label: {
                        Label(
                            "S\(row.sessionNumber) · \(row.title.isEmpty ? "Sesión" : row.title)",
                            systemImage: row.statusIcon
                        )
                    }
                }
            }
        } label: {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.28))
                .frame(width: 18, height: 18)
                .overlay(
                    Text("+\(rows.count)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.6)
                )
        }
        .accessibilityLabel("\(rows.count) sesiones más esta semana")
    }
}

private struct PlannerGanttSessionBlock: View {
    let row: PlannerSequenceRow
    let onOpenSession: (PlanningSession) -> Void

    var body: some View {
        Group {
            if let session = row.planningSession {
                Button {
                    onOpenSession(session)
                } label: {
                    block
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Abrir sesión \(row.sessionNumber)")
            } else {
                block
            }
        }
    }

    private var block: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint)
            .frame(width: 18, height: 18)
            .overlay(
                Text("\(row.sessionNumber)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
            )
    }

    private var tint: Color {
        if row.planningSession == nil { return IOSAppStyle.warning }
        if row.statusText.localizedCaseInsensitiveContains("cerrad")
            || row.statusText.localizedCaseInsensitiveContains("impart") {
            return EvaluationDesign.success
        }
        return EvaluationDesign.accent
    }
}

private struct PlannerGanttLegendItem: View {
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(tint)
                .frame(width: 14, height: 14)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}
