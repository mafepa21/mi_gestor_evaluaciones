import SwiftUI
import MiGestorKit

struct PlannerSequenceGanttView: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onOpenSession: (PlanningSession) -> Void

    @State private var selectedTerm: PlannerGanttTerm = .current
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
                Picker("Trimestre", selection: $selectedTerm) {
                    ForEach(PlannerGanttTerm.allCases) { term in
                        Text(term.title).tag(term)
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
                Text("S.\(week)")
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

    private var visibleWeeks: [Int] {
        selectedTerm.weekRange(currentWeek: currentWeek)
    }

    private var currentWeek: Int {
        let current = IsoWeekHelper.shared.current()
        return Int(truncating: current.first ?? KotlinInt(value: Int32(vm.week)))
    }

    private var filteredGroups: [PlannerSequenceGroup] {
        vm.sequenceGroupsEnriched.filter { group in
            selectedGroupId.map { group.groupId == $0 } ?? true
        }
    }

    private var situationRows: [PlannerGanttSituation] {
        let grouped = Dictionary(grouping: filteredGroups) { group in
            normalized(group.title)
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

private enum PlannerGanttTerm: String, CaseIterable, Identifiable {
    case current
    case first
    case second
    case third

    var id: String { rawValue }

    var title: String {
        switch self {
        case .current: return "Trimestre actual"
        case .first: return "1º trimestre"
        case .second: return "2º trimestre"
        case .third: return "3º trimestre"
        }
    }

    func weekRange(currentWeek: Int) -> [Int] {
        switch self {
        case .current:
            let start = max(1, currentWeek - 6)
            let end = min(53, start + 12)
            return Array(start...end)
        case .first:
            return Array(36...52)
        case .second:
            return Array(1...14)
        case .third:
            return Array(15...26)
        }
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
    let weeks: [Int]
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
    let weeks: [Int]
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
    let weeks: [Int]
    let weekWidth: CGFloat
    let rowHeight: CGFloat
    let onOpenSession: (PlanningSession) -> Void

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
                    } else {
                        HStack(spacing: 4) {
                            ForEach(rows.prefix(4)) { row in
                                PlannerGanttSessionBlock(row: row, onOpenSession: onOpenSession)
                            }
                        }
                    }
                }
                .frame(width: weekWidth, height: rowHeight)
            }
        }
    }

    private func rowsForWeek(_ week: Int) -> [PlannerSequenceRow] {
        sessions.filter { row in
            guard let session = row.planningSession else { return false }
            return Int(session.weekNumber) == week
        }
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
