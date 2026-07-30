import SwiftUI
import MiGestorKit

struct PlannerSequenceGanttView: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onOpenSession: (PlanningSession) -> Void
    var showsInlineGroupFilter = true

    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @State private var selectedRange: PlannerGanttRange = .rolling
    @State private var attentionScope: PlannerGanttAttentionScope = .all
    @State private var expandedSituationIds: Set<String> = []
    @State private var didSelectInitialRange = false
    @AppStorage("plannerGanttHintDismissed") private var ganttHintDismissed = false

    private var metrics: PlannerGanttMetrics {
        PlannerGanttMetrics(density: vm.density)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            progressSummaryStrip

            if let message = vm.sequenceLoadErrorMessage {
                errorContent(message)
            } else if vm.isLoadingSequences && vm.sequenceGroupsEnriched.isEmpty {
                loadingContent
            } else if situationRows.isEmpty {
                emptyContent
            } else if visibleSituations.isEmpty {
                allClearContent
            } else {
                pendingRepairBanner
                onboardingHint
                ganttContent
            }
        }
        .padding(EvaluationDesign.screenPadding)
        .task(id: vm.selectedGroupId) {
            selectInitialRangeIfNeeded()
            await vm.loadEnrichedSequences()
            reconcileExpandedSituations()
        }
        .appOnChange(of: vm.evaluationPeriods.map(\.id)) { _ in
            validateSelectedRange()
            selectInitialRangeIfNeeded()
        }
        .appOnChange(of: attentionScope) { _ in
            reconcileExpandedSituations()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Secuencia")
                    .font(.title2.weight(.bold))
                Text("Qué está al día, qué se retrasa y qué falta por ubicar")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                Picker("Atención", selection: $attentionScope) {
                    ForEach(PlannerGanttAttentionScope.allCases) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 248)

                Picker("Periodo", selection: $selectedRange) {
                    Text("13 semanas").tag(PlannerGanttRange.rolling)
                    ForEach(sortedEvaluationPeriods, id: \.id) { period in
                        Text(period.name).tag(PlannerGanttRange.period(period.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 176)

                if showsInlineGroupFilter {
                    Picker(
                        "Grupo",
                        selection: Binding(
                            get: { vm.selectedGroupId },
                            set: { vm.selectGroup($0) }
                        )
                    ) {
                        Text("Todos").tag(Optional<Int64>.none)
                        ForEach(vm.groups, id: \.id) { group in
                            Text(group.name).tag(Optional(group.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 176)
                }
            }

            if vm.isLoadingSequences {
                ProgressView()
                    .controlSize(.small)
                    .tint(EvaluationDesign.accent)
            }
        }
    }

    private var loadingContent: some View {
        VStack {
            ProgressView("Cargando el plan completo…")
                .padding()
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private func errorContent(_ message: String) -> some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "No se pudo cargar la secuencia",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
            Button("Reintentar") {
                Task {
                    await vm.loadEnrichedSequences()
                    reconcileExpandedSituations()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private var emptyContent: some View {
        PlannerEmptyState(
            title: "Sin secuencias",
            systemImage: "point.3.connected.trianglepath.dotted",
            message: "Importa una secuencia en Situaciones de aprendizaje y vincúlala a un grupo. Aparecerá aquí antes incluso de agendar su primera sesión."
        )
    }

    private var allClearContent: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Todo está al día",
                systemImage: "checkmark.seal",
                description: Text("No hay sesiones sin ubicar, cancelaciones ni grupos retrasados en este periodo.")
            )
            Button("Mostrar todas las situaciones") {
                attentionScope = .all
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private var ganttContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    fixedRail

                    ScrollView(.horizontal) {
                        timeline
                            .frame(width: timelineWidth, alignment: .leading)
                    }
                    .scrollIndicators(.visible)
                }
                .plannerGlassPanel(.content, cornerRadius: 16)
            }

            legend
        }
    }

    @ViewBuilder
    private var pendingRepairBanner: some View {
        if let target = firstUnlocatedTarget {
            HStack(spacing: 16) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(IOSAppStyle.warning)
                    .frame(width: 40, height: 40)
                    .background(IOSAppStyle.warning.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(visiblePendingCount) \(visiblePendingCount == 1 ? "sesión necesita" : "sesiones necesitan") fecha")
                        .font(.headline)
                    Text("No están perdidas: siguen vinculadas al plan y puedes programarlas ahora.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Button {
                    locate(target.row, in: target.group)
                } label: {
                    Label(
                        visiblePendingCount == 1 ? "Programar sesión" : "Programar siguiente",
                        systemImage: "calendar.badge.plus"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(IOSAppStyle.warning)
            }
            .padding(16)
            .background(IOSAppStyle.warning.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(IOSAppStyle.warning.opacity(0.22), lineWidth: 1)
            }
        }
    }

    private var fixedRail: some View {
        VStack(spacing: 0) {
            Text(rangeContextLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .frame(width: metrics.labelWidth, height: metrics.monthHeaderHeight, alignment: .leading)
                .background(EvaluationDesign.surfaceSoft)

            Text("Situación / grupo")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .frame(width: metrics.labelWidth, height: metrics.headerHeight, alignment: .leading)
                .background(EvaluationDesign.surfaceSoft)

            ForEach(displayRows) { row in
                fixedRailRow(row)
            }
        }
    }

    @ViewBuilder
    private func fixedRailRow(_ row: PlannerGanttDisplayRow) -> some View {
        switch row {
        case .situation(let situation):
            Button {
                toggle(situation.id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expandedSituationIds.contains(situation.id) ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(situation.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(situationSummary(situation))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 16)
                .frame(width: metrics.labelWidth, height: metrics.rowHeight, alignment: .leading)
                .contentShape(Rectangle())
                .background(EvaluationDesign.surfaceSoft.opacity(0.72))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(situation.title), \(situationSummary(situation))")
            .accessibilityValue(expandedSituationIds.contains(situation.id) ? "Expandida" : "Contraída")
            .accessibilityHint("Alterna el detalle por grupo")

        case .group(_, let group):
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.groupName)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                    Text(pace(for: group)?.text ?? "\(group.plannedCount) planificadas")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(pace(for: group)?.tint ?? .secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if group.pendingCount > 0 {
                    locateMenu(for: group)
                }
            }
            .padding(.leading, 40)
            .padding(.trailing, 12)
            .frame(width: metrics.labelWidth, height: metrics.rowHeight, alignment: .leading)
            .background(EvaluationDesign.surfaceSoft.opacity(0.36))
            .accessibilityElement(children: .contain)
        }
    }

    private func locateMenu(for group: PlannerSequenceGroup) -> some View {
        Menu {
            ForEach(group.rows.filter { $0.status == .unlocated }) { row in
                Button {
                    locate(row, in: group)
                } label: {
                    Label(
                        "S\(row.sessionNumber) · \(row.title.isEmpty ? "Sesión" : row.title)",
                        systemImage: "calendar.badge.plus"
                    )
                }
            }
        } label: {
            Label("Programar \(group.pendingCount)", systemImage: "calendar.badge.plus")
                .font(.caption.weight(.bold))
        }
        .menuStyle(.button)
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(IOSAppStyle.warning)
        .help("Programar las sesiones que aún no tienen fecha en \(group.groupName)")
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            monthHeader
            timelineHeader

            ForEach(displayRows) { row in
                switch row {
                case .situation(let situation):
                    PlannerGanttContinuousBar(
                        rows: situation.groups.flatMap(\.rows),
                        weeks: visibleWeeks,
                        vacationWeeks: vacationWeeks,
                        weekWidth: metrics.weekWidth,
                        rowHeight: metrics.rowHeight,
                        currentWeek: currentWeek,
                        onOpenSession: onOpenSession
                    )
                case .group(_, let group):
                    PlannerGanttContinuousBar(
                        rows: group.rows,
                        weeks: visibleWeeks,
                        vacationWeeks: vacationWeeks,
                        weekWidth: metrics.weekWidth,
                        rowHeight: metrics.rowHeight,
                        currentWeek: currentWeek,
                        onOpenSession: onOpenSession
                    )
                }
            }
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 0) {
            ForEach(monthSpans) { span in
                Text(span.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(
                        width: metrics.weekWidth * CGFloat(span.weekCount),
                        height: metrics.monthHeaderHeight,
                        alignment: .leading
                    )
                    .padding(.leading, 8)
            }
        }
        .background(EvaluationDesign.surfaceSoft)
    }

    private var timelineHeader: some View {
        HStack(spacing: 0) {
            ForEach(visibleWeeks, id: \.self) { week in
                Text("S.\(week.week)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(week == currentWeek ? EvaluationDesign.accent : .secondary)
                    .frame(width: metrics.weekWidth, height: metrics.headerHeight)
                    .background(weekHeaderBackground(for: week))
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

    private func weekHeaderBackground(for week: PlannerGanttWeek) -> Color {
        if week == currentWeek { return EvaluationDesign.accent.opacity(0.12) }
        if vacationWeeks.contains(week) { return Color.secondary.opacity(0.14) }
        return EvaluationDesign.surfaceSoft
    }

    @ViewBuilder
    private var progressSummaryStrip: some View {
        let groups = visibleSituations.flatMap(\.groups)
        let total = groups.reduce(0) { $0 + $1.totalSessionsCount }
        let completed = groups.reduce(0) { $0 + $1.completedCount }
        let pending = groups.reduce(0) { $0 + $1.pendingCount }
        let cancelled = groups.reduce(0) { $0 + $1.cancelledCount }
        let planned = max(total - completed - pending - cancelled, 0)

        if total > 0 {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        progressSegment(value: completed, total: total, width: proxy.size.width, tint: EvaluationDesign.success)
                        progressSegment(value: planned, total: total, width: proxy.size.width, tint: EvaluationDesign.accent.opacity(0.55))
                        progressSegment(value: pending, total: total, width: proxy.size.width, tint: IOSAppStyle.warning)
                        progressSegment(value: cancelled, total: total, width: proxy.size.width, tint: EvaluationDesign.danger)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .frame(height: 8)

                HStack(spacing: 16) {
                    PlannerProgressMetric(value: "\(completed)", label: "impartidas", tint: EvaluationDesign.success, icon: "checkmark.circle.fill")
                    PlannerProgressMetric(value: "\(planned)", label: "planificadas", tint: EvaluationDesign.accent, icon: "calendar")
                    if pending > 0 {
                        PlannerProgressMetric(value: "\(pending)", label: "sin ubicar", tint: IOSAppStyle.warning, icon: "calendar.badge.plus")
                    }
                    if cancelled > 0 {
                        PlannerProgressMetric(value: "\(cancelled)", label: "canceladas", tint: EvaluationDesign.danger, icon: "xmark.circle.fill")
                    }
                    Spacer()
                    Text("\(completed) de \(total) completadas")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func progressSegment(value: Int, total: Int, width: CGFloat, tint: Color) -> some View {
        Rectangle()
            .fill(tint)
            .frame(width: total > 0 ? width * CGFloat(value) / CGFloat(total) : 0)
    }

    @ViewBuilder
    private var onboardingHint: some View {
        if !ganttHintDismissed {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(EvaluationDesign.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lee el plan y actúa sin salir del Gantt")
                        .font(.caption.weight(.bold))
                    Text("Expande una situación para comparar grupos. Abre una marca para revisar la sesión o usa Ubicar para agendar lo pendiente.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    withAnimation(uiFeatureFlags.interactionAnimation) {
                        ganttHintDismissed = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Descartar aviso")
            }
            .padding(16)
            .plannerGlassPanel(.control, cornerRadius: 16)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            PlannerGanttLegendItem(label: "Cerrada", tint: PlannerSequenceStatus.closed.tint)
            PlannerGanttLegendItem(label: "Impartida", tint: PlannerSequenceStatus.taught.tint)
            PlannerGanttLegendItem(label: "Planificada", tint: PlannerSequenceStatus.planned.tint)
            PlannerGanttLegendItem(label: "Cancelada", tint: PlannerSequenceStatus.cancelled.tint)
            PlannerGanttLegendItem(label: "Vacaciones", tint: Color.secondary.opacity(0.35))
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var sortedEvaluationPeriods: [PlannerEvaluationPeriod] {
        vm.evaluationPeriods.sorted { ($0.sortOrder, $0.startDateIso) < ($1.sortOrder, $1.startDateIso) }
    }

    private var visibleWeeks: [PlannerGanttWeek] {
        switch selectedRange {
        case .rolling:
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

    private var timelineWidth: CGFloat {
        metrics.weekWidth * CGFloat(max(visibleWeeks.count, 1))
    }

    private var currentWeek: PlannerGanttWeek {
        PlannerGanttWeek(date: Date())
    }

    private var vacationWeeks: Set<PlannerGanttWeek> {
        guard !vm.evaluationPeriods.isEmpty else { return [] }
        let covered = Set(
            vm.evaluationPeriods.flatMap {
                PlannerGanttWeek.range(fromIso: $0.startDateIso, toIso: $0.endDateIso) ?? []
            }
        )
        return Set(visibleWeeks.filter { !covered.contains($0) })
    }

    private var situationRows: [PlannerGanttSituation] {
        let grouped = Dictionary(grouping: vm.sequenceGroupsEnriched) { group in
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
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var visibleSituations: [PlannerGanttSituation] {
        switch attentionScope {
        case .all:
            return situationRows
        case .attention:
            return situationRows.filter { situation in
                situation.groups.contains { group in
                    group.requiresAttention || pace(for: group)?.isBehind == true
                }
            }
        }
    }

    private var displayRows: [PlannerGanttDisplayRow] {
        visibleSituations.flatMap { situation in
            var rows: [PlannerGanttDisplayRow] = [.situation(situation)]
            if expandedSituationIds.contains(situation.id) {
                rows.append(contentsOf: situation.groups.map { .group(parentId: situation.id, group: $0) })
            }
            return rows
        }
    }

    private var rangeContextLabel: String {
        switch selectedRange {
        case .rolling:
            return "VENTANA ACTUAL"
        case .period(let periodId):
            return sortedEvaluationPeriods.first(where: { $0.id == periodId })?.name.uppercased() ?? "PERIODO"
        }
    }

    private func situationSummary(_ situation: PlannerGanttSituation) -> String {
        var parts = ["\(situation.completed) de \(situation.total) completadas"]
        if situation.pending > 0 { parts.append("\(situation.pending) sin ubicar") }
        if situation.cancelled > 0 { parts.append("\(situation.cancelled) canceladas") }
        return parts.joined(separator: " · ")
    }

    private func pace(for group: PlannerSequenceGroup) -> PlannerSequencePace? {
        PlannerSequencePace.evaluate(group: group, currentWeek: currentWeek)
    }

    private var visiblePendingCount: Int {
        visibleSituations.reduce(0) { partial, situation in
            partial + situation.groups.reduce(0) { $0 + $1.pendingCount }
        }
    }

    private var firstUnlocatedTarget: (row: PlannerSequenceRow, group: PlannerSequenceGroup)? {
        for situation in visibleSituations {
            for group in situation.groups {
                if let row = group.rows.first(where: { $0.status == .unlocated }) {
                    return (row, group)
                }
            }
        }
        return nil
    }

    private func locate(_ row: PlannerSequenceRow, in group: PlannerSequenceGroup) {
        vm.selectGroup(group.groupId)
        vm.openComposer(
            learningSituationSessionPlanId: row.learningSituationSessionPlanId,
            initialObjectives: row.objective,
            initialTeachingUnitName: row.title
        )
    }

    private func toggle(_ id: String) {
        withAnimation(uiFeatureFlags.interactionAnimation) {
            if expandedSituationIds.contains(id) {
                expandedSituationIds.remove(id)
            } else {
                expandedSituationIds.insert(id)
            }
        }
    }

    private func reconcileExpandedSituations() {
        let validIds = Set(visibleSituations.map(\.id))
        expandedSituationIds.formIntersection(validIds)
        guard expandedSituationIds.isEmpty else { return }
        let attentionFirst = visibleSituations.sorted {
            let lhs = $0.groups.contains { $0.requiresAttention || pace(for: $0)?.isBehind == true }
            let rhs = $1.groups.contains { $0.requiresAttention || pace(for: $0)?.isBehind == true }
            return lhs && !rhs
        }
        expandedSituationIds = Set(attentionFirst.prefix(3).map(\.id))
    }

    private func selectInitialRangeIfNeeded() {
        guard !didSelectInitialRange else { return }
        didSelectInitialRange = true
        if let currentPeriod = sortedEvaluationPeriods.first(where: {
            (PlannerGanttWeek.range(fromIso: $0.startDateIso, toIso: $0.endDateIso) ?? []).contains(currentWeek)
        }) {
            selectedRange = .period(currentPeriod.id)
        }
    }

    private func validateSelectedRange() {
        guard case .period(let id) = selectedRange,
              !vm.evaluationPeriods.contains(where: { $0.id == id }) else { return }
        selectedRange = .rolling
        didSelectInitialRange = false
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private struct MonthSpan: Identifiable {
        let id: String
        let title: String
        let weekCount: Int
    }

    private var monthSpans: [MonthSpan] {
        var spans: [MonthSpan] = []
        for week in visibleWeeks {
            let label = week.monthTitle
            if let last = spans.last, last.title == label {
                spans[spans.count - 1] = MonthSpan(id: last.id, title: last.title, weekCount: last.weekCount + 1)
            } else {
                spans.append(MonthSpan(id: "\(week.year)-\(label)-\(spans.count)", title: label, weekCount: 1))
            }
        }
        return spans
    }
}

enum PlannerGanttRange: Hashable {
    case rolling
    case period(Int64)
}

enum PlannerGanttAttentionScope: String, CaseIterable, Identifiable {
    case all
    case attention

    var id: String { rawValue }
    var label: String { self == .all ? "Todas" : "Requieren atención" }
}

struct PlannerGanttMetrics: Equatable {
    let labelWidth: CGFloat
    let weekWidth: CGFloat
    let rowHeight: CGFloat
    let monthHeaderHeight: CGFloat = 24
    let headerHeight: CGFloat = 40

    init(density: PlannerDensity) {
        switch density {
        case .compact:
            labelWidth = 216
            weekWidth = 48
            rowHeight = 40
        case .standard:
            labelWidth = 240
            weekWidth = 64
            rowHeight = 48
        }
    }
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

    var mondayDate: Date? {
        var components = DateComponents()
        components.yearForWeekOfYear = year
        components.weekOfYear = week
        components.weekday = 2
        return Self.isoCalendar.date(from: components)
    }

    var monthTitle: String {
        guard let date = mondayDate else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = Self.isoCalendar
        formatter.locale = Locale.current
        formatter.dateFormat = "LLLL"
        return formatter.string(from: date).capitalized
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
        while cursor <= end && weeks.count < 60 {
            let week = PlannerGanttWeek(date: cursor)
            if weeks.last != week {
                weeks.append(week)
            }
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        return weeks
    }

    func weeks(until other: PlannerGanttWeek) -> Int {
        guard let selfDate = mondayDate, let otherDate = other.mondayDate else { return 0 }
        let days = Self.isoCalendar.dateComponents([.day], from: selfDate, to: otherDate).day ?? 0
        return Int((Double(days) / 7.0).rounded())
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

struct PlannerSequencePace: Equatable {
    let delta: Int

    var isBehind: Bool { delta < 0 }
    var tint: Color { isBehind ? IOSAppStyle.warning : EvaluationDesign.success }

    var text: String {
        if delta == 0 { return "Al día con el plan" }
        if delta > 0 { return "Vas \(delta) sesión\(delta == 1 ? "" : "es") por delante" }
        let behind = -delta
        return "Vas \(behind) sesión\(behind == 1 ? "" : "es") por detrás"
    }

    static func evaluate(group: PlannerSequenceGroup, currentWeek: PlannerGanttWeek) -> PlannerSequencePace? {
        let assignedWeeks = group.rows.compactMap { row -> PlannerGanttWeek? in
            guard let session = row.planningSession else { return nil }
            return PlannerGanttWeek(year: Int(session.year), week: Int(session.weekNumber))
        }
        guard let firstWeek = assignedWeeks.min(by: { $0.weeks(until: $1) > 0 }),
              let lastWeek = assignedWeeks.max(by: { $0.weeks(until: $1) > 0 }),
              group.totalSessionsCount > 0 else { return nil }

        let span = max(firstWeek.weeks(until: lastWeek) + 1, 1)
        let elapsed = min(max(firstWeek.weeks(until: currentWeek) + 1, 0), span)
        guard elapsed > 0, currentWeek.weeks(until: lastWeek) >= -4 else { return nil }
        let expected = Int((Double(group.totalSessionsCount) * Double(elapsed) / Double(span)).rounded())
        return PlannerSequencePace(delta: group.completedCount - expected)
    }
}

struct PlannerGanttSituation: Identifiable {
    let id: String
    let title: String
    let groups: [PlannerSequenceGroup]

    var completed: Int { groups.reduce(0) { $0 + $1.completedCount } }
    var total: Int { groups.reduce(0) { $0 + $1.totalSessionsCount } }
    var pending: Int { groups.reduce(0) { $0 + $1.pendingCount } }
    var cancelled: Int { groups.reduce(0) { $0 + $1.cancelledCount } }
}

enum PlannerGanttDisplayRow: Identifiable {
    case situation(PlannerGanttSituation)
    case group(parentId: String, group: PlannerSequenceGroup)

    var id: String {
        switch self {
        case .situation(let situation): return "situation-\(situation.id)"
        case .group(let parentId, let group): return "group-\(parentId)-\(group.id)"
        }
    }
}

private struct PlannerGanttContinuousBar: View {
    let rows: [PlannerSequenceRow]
    let weeks: [PlannerGanttWeek]
    let vacationWeeks: Set<PlannerGanttWeek>
    let weekWidth: CGFloat
    let rowHeight: CGFloat
    let currentWeek: PlannerGanttWeek
    let onOpenSession: (PlanningSession) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(weeks, id: \.self) { week in
                segment(for: week)
                    .frame(width: weekWidth, height: rowHeight)
            }
        }
    }

    private var spanIndexRange: ClosedRange<Int>? {
        let indices = rows.compactMap { row -> Int? in
            guard let session = row.planningSession else { return nil }
            return weeks.firstIndex(of: PlannerGanttWeek(year: Int(session.year), week: Int(session.weekNumber)))
        }
        guard let minIndex = indices.min(), let maxIndex = indices.max() else { return nil }
        return minIndex...maxIndex
    }

    @ViewBuilder
    private func segment(for week: PlannerGanttWeek) -> some View {
        let weekRows = rowsForWeek(week)
        let withinSpan = weeks.firstIndex(of: week).map { spanIndexRange?.contains($0) ?? false } ?? false

        ZStack {
            if vacationWeeks.contains(week) {
                Rectangle().fill(Color.secondary.opacity(0.08))
            } else if withinSpan {
                Rectangle().fill(segmentColor(for: weekRows))
            }

            Rectangle()
                .fill(Color.secondary.opacity(0.10))
                .frame(width: 1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !weekRows.isEmpty {
                PlannerGanttWeekMarks(rows: weekRows, onOpenSession: onOpenSession)
            }
        }
        .overlay(alignment: .leading) {
            if week == currentWeek {
                Rectangle()
                    .fill(EvaluationDesign.accent)
                    .frame(width: 2)
            }
        }
    }

    private func segmentColor(for rows: [PlannerSequenceRow]) -> Color {
        guard let leading = rows.max(by: { attentionRank($0.status) < attentionRank($1.status) }) else {
            return EvaluationDesign.accent.opacity(0.14)
        }
        return leading.statusColor.opacity(leading.status.isCompleted ? 0.28 : 0.22)
    }

    private func attentionRank(_ status: PlannerSequenceStatus) -> Int {
        switch status {
        case .unlocated: return 6
        case .cancelled: return 5
        case .inProgress: return 4
        case .planned, .calendarOnly: return 3
        case .taught: return 2
        case .closed: return 1
        }
    }

    private func rowsForWeek(_ week: PlannerGanttWeek) -> [PlannerSequenceRow] {
        rows.filter { row in
            guard let session = row.planningSession else { return false }
            return Int(session.weekNumber) == week.week && Int(session.year) == week.year
        }
    }
}

private struct PlannerGanttWeekMarks: View {
    let rows: [PlannerSequenceRow]
    let onOpenSession: (PlanningSession) -> Void

    var body: some View {
        if rows.count == 1, let row = rows.first {
            PlannerGanttSessionMark(row: row, onOpenSession: onOpenSession)
        } else {
            Menu {
                ForEach(rows) { row in
                    if let session = row.planningSession {
                        Button {
                            onOpenSession(session)
                        } label: {
                            Label("S\(row.sessionNumber) · \(row.title.nilIfBlank ?? "Sesión")", systemImage: row.statusIcon)
                        }
                    }
                }
            } label: {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: 20, height: 20)
                    .overlay {
                        Text("\(rows.count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
            }
            .accessibilityLabel("\(rows.count) sesiones esta semana")
            .help("\(rows.count) sesiones; abre el menú para elegir")
        }
    }
}

private struct PlannerGanttSessionMark: View {
    let row: PlannerSequenceRow
    let onOpenSession: (PlanningSession) -> Void

    var body: some View {
        if let session = row.planningSession {
            Button {
                onOpenSession(session)
            } label: {
                mark
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir sesión \(row.sessionNumber): \(row.statusText)")
            .help(helpText(for: session))
        } else {
            mark
        }
    }

    private var mark: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(row.statusColor)
            .frame(width: 20, height: 20)
            .overlay {
                Text("\(row.sessionNumber)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
    }

    private func helpText(for session: PlanningSession) -> String {
        [
            "S\(row.sessionNumber) · \(row.title.nilIfBlank ?? "Sesión")",
            session.groupName,
            "Semana \(session.weekNumber) · \(row.statusText)"
        ].joined(separator: "\n")
    }
}

private struct PlannerGanttLegendItem: View {
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(tint)
                .frame(width: 14, height: 14)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct PlannerProgressMetric: View {
    let value: String
    let label: String
    let tint: Color
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.caption.weight(.black))
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}
