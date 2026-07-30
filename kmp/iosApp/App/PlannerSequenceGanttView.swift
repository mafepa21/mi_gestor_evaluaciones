import SwiftUI
import MiGestorKit

struct PlannerSequenceGanttView: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let onOpenSession: (PlanningSession) -> Void
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags

    @State private var selectedRange: PlannerGanttRange = .current
    @State private var selectedGroupId: Int64?
    @State private var expandedSituationIds: Set<String> = []
    @AppStorage("plannerGanttHintDismissed") private var ganttHintDismissed = false

    private let labelWidth: CGFloat = 208
    private let weekWidth: CGFloat = 64
    private let rowHeight: CGFloat = 40
    private let monthHeaderHeight: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            progressSummaryStrip

            if vm.sequenceGroupsEnriched.isEmpty {
                emptyContent
            } else {
                onboardingHint
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
                Text("Progreso de tus situaciones de aprendizaje")
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
                    message: "Todavía no hay sesiones vinculadas a situaciones de aprendizaje. Crea sesiones desde la vista Semana y vincúlalas a una SA para ver su progreso aquí."
                )
            }
        }
    }

    private var ganttContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    monthHeader
                    timelineHeader

                    ForEach(situationRows) { situation in
                        PlannerGanttSituationRow(
                            vm: vm,
                            situation: situation,
                            weeks: visibleWeeks,
                            vacationWeeks: vacationWeeks,
                            weekWidth: weekWidth,
                            labelWidth: labelWidth,
                            rowHeight: rowHeight,
                            currentWeek: currentWeek,
                            isExpanded: expandedSituationIds.contains(situation.id),
                            onToggle: {
                                toggle(situation.id)
                            },
                            onOpenSession: onOpenSession
                        )
                    }
                }
                .plannerGlassPanel(.content, cornerRadius: 12)
            }

            legend
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: labelWidth, height: monthHeaderHeight)

            ForEach(monthSpans, id: \.id) { span in
                Text(span.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: weekWidth * CGFloat(span.weekCount), height: monthHeaderHeight, alignment: .leading)
                    .padding(.leading, 6)
            }
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
        if week == currentWeek { return EvaluationDesign.accent.opacity(0.10) }
        if vacationWeeks.contains(week) { return Color.secondary.opacity(0.14) }
        return EvaluationDesign.surfaceSoft
    }

    /// Strip de progreso global visible encima del Gantt: muestra de un vistazo
    /// cuántas sesiones se han impartido, cuántas faltan y cuántas están pendientes de ubicar.
    @ViewBuilder
    private var progressSummaryStrip: some View {
        let rows = situationRows
        let totalSessions = rows.reduce(0) { $0 + $1.total }
        let completedSessions = rows.reduce(0) { $0 + $1.completed }
        let pendingLocate = rows.reduce(0) { $0 + $1.pending }
        let remaining = max(totalSessions - completedSessions - pendingLocate, 0)

        if totalSessions > 0 {
            VStack(alignment: .leading, spacing: 10) {
                // Barra de progreso visual
                GeometryReader { proxy in
                    let width = proxy.size.width
                    let completedWidth = totalSessions > 0 ? width * CGFloat(completedSessions) / CGFloat(totalSessions) : 0
                    let pendingWidth = totalSessions > 0 ? width * CGFloat(pendingLocate) / CGFloat(totalSessions) : 0

                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(EvaluationDesign.success)
                            .frame(width: max(completedWidth, completedSessions > 0 ? 4 : 0))
                        RoundedRectangle(cornerRadius: 0, style: .continuous)
                            .fill(EvaluationDesign.accent.opacity(0.5))
                            .frame(width: max(width - completedWidth - pendingWidth, 0))
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(IOSAppStyle.warning)
                            .frame(width: max(pendingWidth, pendingLocate > 0 ? 4 : 0))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .frame(height: 8)

                // Métricas compactas
                HStack(spacing: 16) {
                    PlannerProgressMetric(
                        value: "\(completedSessions)",
                        label: "impartidas",
                        tint: EvaluationDesign.success,
                        icon: "checkmark.circle.fill"
                    )
                    PlannerProgressMetric(
                        value: "\(remaining)",
                        label: "planificadas",
                        tint: EvaluationDesign.accent,
                        icon: "calendar"
                    )
                    if pendingLocate > 0 {
                        PlannerProgressMetric(
                            value: "\(pendingLocate)",
                            label: "sin ubicar",
                            tint: IOSAppStyle.warning,
                            icon: "exclamationmark.triangle.fill"
                        )
                    }
                    Spacer()
                    Text("\(completedSessions) de \(totalSessions) sesiones")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(EvaluationDesign.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    /// Aviso de "cómo se lee esto" mostrado solo la primera vez (mismo patrón
    /// `@AppStorage` que el aviso de arrastre del grid semanal), con cierre explícito.
    @ViewBuilder
    private var onboardingHint: some View {
        if !ganttHintDismissed {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(EvaluationDesign.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cada fila es una situación de aprendizaje")
                        .font(.caption.weight(.bold))
                    Text("Cada marca de color es una sesión: toca una para abrir su ficha. El color indica su estado — mira la leyenda de abajo.")
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
            .padding(12)
            .plannerGlassPanel(.control, cornerRadius: 12)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            PlannerGanttLegendItem(label: "Impartida", tint: EvaluationDesign.success)
            PlannerGanttLegendItem(label: "Planificada", tint: EvaluationDesign.accent)
            PlannerGanttLegendItem(label: "Pendiente de ubicar", tint: IOSAppStyle.warning)
            PlannerGanttLegendItem(label: "Cancelada", tint: EvaluationDesign.danger)
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

    /// Semanas visibles que no caen dentro de ningún periodo de evaluación configurado:
    /// son los huecos reales entre evaluaciones (Navidad, Semana Santa, verano...).
    /// Si no hay periodos configurados no se sombrea nada (no hay con qué comparar).
    private var vacationWeeks: Set<PlannerGanttWeek> {
        guard !vm.evaluationPeriods.isEmpty else { return [] }
        let coveredWeeks = Set(
            vm.evaluationPeriods.flatMap { period in
                PlannerGanttWeek.range(fromIso: period.startDateIso, toIso: period.endDateIso) ?? []
            }
        )
        return Set(visibleWeeks.filter { !coveredWeeks.contains($0) })
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
        withAnimation(uiFeatureFlags.interactionAnimation) {
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

    /// Lunes de esta semana ISO, usado para ordenar/comparar semanas por fecha real
    /// y para derivar el nombre del mes en la cabecera.
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
        // Límite de seguridad: un periodo de evaluación nunca supera un curso escolar.
        while cursor <= end && weeks.count < 60 {
            weeks.append(PlannerGanttWeek(date: cursor))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        return weeks
    }

    /// Diferencia en semanas ISO entre dos semanas (positiva si `other` es posterior).
    func weeks(until other: PlannerGanttWeek) -> Int {
        guard let selfDate = mondayDate, let otherDate = other.mondayDate else { return 0 }
        let days = Calendar(identifier: .iso8601).dateComponents([.day], from: selfDate, to: otherDate).day ?? 0
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

private struct PlannerGanttSituation: Identifiable {
    let id: String
    let title: String
    let groups: [PlannerSequenceGroup]

    var completed: Int { groups.reduce(0) { $0 + $1.completedCount } }
    var total: Int { groups.reduce(0) { $0 + $1.totalSessionsCount } }
    var pending: Int { groups.reduce(0) { $0 + $1.pendingCount } }
}

private struct PlannerGanttSituationRow: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let situation: PlannerGanttSituation
    let weeks: [PlannerGanttWeek]
    let vacationWeeks: Set<PlannerGanttWeek>
    let weekWidth: CGFloat
    let labelWidth: CGFloat
    let rowHeight: CGFloat
    let currentWeek: PlannerGanttWeek
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
                            Text("\(situation.completed) de \(situation.total) sesiones · \(situation.pending) sin ubicar")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                    }
                    .frame(width: labelWidth, height: rowHeight, alignment: .leading)
                    .padding(.horizontal, 16)
                    .background(EvaluationDesign.surfaceSoft.opacity(0.72))

                    PlannerGanttContinuousBar(
                        rows: situation.groups.flatMap(\.rows),
                        weeks: weeks,
                        vacationWeeks: vacationWeeks,
                        weekWidth: weekWidth,
                        rowHeight: rowHeight,
                        onOpenSession: onOpenSession
                    )
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(situation.title): \(situation.completed) de \(situation.total) sesiones, \(situation.pending) sin ubicar")
            .accessibilityValue(isExpanded ? "Expandido" : "Contraído")
            .accessibilityHint("Alterna el detalle por grupo")

            if isExpanded {
                ForEach(situation.groups) { group in
                    PlannerGanttGroupRow(
                        vm: vm,
                        group: group,
                        weeks: weeks,
                        vacationWeeks: vacationWeeks,
                        weekWidth: weekWidth,
                        labelWidth: labelWidth,
                        rowHeight: rowHeight,
                        currentWeek: currentWeek,
                        onOpenSession: onOpenSession
                    )
                }
            }
        }
    }
}

private struct PlannerGanttGroupRow: View {
    @ObservedObject var vm: PlannerWorkspaceViewModel
    let group: PlannerSequenceGroup
    let weeks: [PlannerGanttWeek]
    let vacationWeeks: Set<PlannerGanttWeek>
    let weekWidth: CGFloat
    let labelWidth: CGFloat
    let rowHeight: CGFloat
    let currentWeek: PlannerGanttWeek
    let onOpenSession: (PlanningSession) -> Void

    private var unlocatedRows: [PlannerSequenceRow] {
        group.rows.filter { $0.planningSession == nil }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.groupName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let pace = paceLabel {
                        if pace.isBehind {
                            Button {
                                vm.selectGroup(group.groupId)
                                vm.activeSection = .week
                            } label: {
                                Label(pace.text, systemImage: "arrow.right.circle.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(pace.tint)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Abre la Semana filtrada por \(group.groupName) para ponerte al día")
                        } else {
                            Text(pace.text)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(pace.tint)
                                .lineLimit(1)
                        }
                    } else {
                        Text("\(group.plannedCount) planificadas")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(group.groupName): \(paceLabel?.text ?? "\(group.plannedCount) planificadas")")

                if !unlocatedRows.isEmpty {
                    locateMenu
                }
            }
            .frame(width: labelWidth, height: rowHeight, alignment: .leading)
            .padding(.horizontal, 40)
            .background(EvaluationDesign.surfaceSoft.opacity(0.36))

            PlannerGanttContinuousBar(
                rows: group.rows,
                weeks: weeks,
                vacationWeeks: vacationWeeks,
                weekWidth: weekWidth,
                rowHeight: rowHeight,
                onOpenSession: onOpenSession
            )
        }
    }

    private var locateMenu: some View {
        Menu {
            ForEach(unlocatedRows) { row in
                Button {
                    locate(row)
                } label: {
                    Label("Ubicar S\(row.sessionNumber) · \(row.title.isEmpty ? "Sesión" : row.title)", systemImage: "calendar.badge.plus")
                }
            }
        } label: {
            Label("\(unlocatedRows.count) sin ubicar", systemImage: "calendar.badge.plus")
                .font(.caption2.weight(.bold))
                .foregroundStyle(IOSAppStyle.warning)
        }
    }

    private func locate(_ row: PlannerSequenceRow) {
        vm.selectGroup(group.groupId)
        vm.openComposer(
            learningSituationSessionPlanId: row.learningSituationSessionPlanId,
            initialObjectives: row.objective,
            initialTeachingUnitName: row.title
        )
    }

    /// Sesiones esperadas a día de hoy (proporcional al punto en que estamos dentro
    /// del rango real de semanas de la situación) frente a las realmente completadas.
    private var paceLabel: (text: String, tint: Color, isBehind: Bool)? {
        let assignedWeeks = group.rows.compactMap { row -> PlannerGanttWeek? in
            guard let session = row.planningSession else { return nil }
            return PlannerGanttWeek(year: Int(session.year), week: Int(session.weekNumber))
        }
        guard let firstWeek = assignedWeeks.min(by: { $0.weeks(until: $1) > 0 }),
              let lastWeek = assignedWeeks.max(by: { $0.weeks(until: $1) > 0 }),
              group.totalSessionsCount > 0 else { return nil }

        let totalSpanWeeks = max(firstWeek.weeks(until: lastWeek) + 1, 1)
        let elapsedWeeks = min(max(firstWeek.weeks(until: currentWeek) + 1, 0), totalSpanWeeks)
        guard elapsedWeeks > 0 else { return nil }
        guard currentWeek.weeks(until: lastWeek) >= -4 else { return nil }

        let expected = Int((Double(group.totalSessionsCount) * Double(elapsedWeeks) / Double(totalSpanWeeks)).rounded())
        let delta = group.completedCount - expected

        if delta == 0 {
            return ("Al día con el plan", EvaluationDesign.success, false)
        } else if delta > 0 {
            return ("Vas \(delta) sesión\(delta == 1 ? "" : "es") por delante", EvaluationDesign.success, false)
        } else {
            return ("Vas \(-delta) sesión\(-delta == 1 ? "" : "es") por detrás", IOSAppStyle.warning, true)
        }
    }
}

private struct PlannerGanttContinuousBar: View {
    let rows: [PlannerSequenceRow]
    let weeks: [PlannerGanttWeek]
    let vacationWeeks: Set<PlannerGanttWeek>
    let weekWidth: CGFloat
    let rowHeight: CGFloat
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
            let week = PlannerGanttWeek(year: Int(session.year), week: Int(session.weekNumber))
            return weeks.firstIndex(of: week)
        }
        guard let minIndex = indices.min(), let maxIndex = indices.max() else { return nil }
        return minIndex...maxIndex
    }

    @ViewBuilder
    private func segment(for week: PlannerGanttWeek) -> some View {
        let weekRows = rowsForWeek(week)
        let isWithinSpan = weeks.firstIndex(of: week).map { spanIndexRange?.contains($0) ?? false } ?? false
        let isVacation = vacationWeeks.contains(week)

        ZStack {
            if isVacation {
                Rectangle().fill(Color.secondary.opacity(0.08))
                    .accessibilityHidden(true)
            } else if isWithinSpan {
                Rectangle().fill(segmentColor(for: weekRows))
                    .accessibilityHidden(true)
            }

            Rectangle()
                .fill(Color.secondary.opacity(0.10))
                .frame(width: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)

            if !weekRows.isEmpty {
                PlannerGanttWeekMarks(rows: weekRows, onOpenSession: onOpenSession)
            }
        }
    }

    /// Cuántas ganas de llamar la atención del docente tiene cada estado si una semana
    /// tiene varias filas: lo que necesita acción (ubicar/cancelada) gana a lo ya resuelto.
    private func attentionRank(for statusText: String) -> Int {
        switch statusText {
        case "Pendiente de ubicar": return 4
        case "Cancelada": return 3
        case "Cerrada", "Impartida": return 2
        default: return 1 // Planificada, En Curso, Solo calendario
        }
    }

    /// Única fuente de color: el `statusColor` ya calculado en el ViewModel para cada fila
    /// (evita que esta vista re-derive el color por su cuenta y se desincronice de él).
    private func segmentColor(for rows: [PlannerSequenceRow]) -> Color {
        guard let leading = rows.max(by: { attentionRank(for: $0.statusText) < attentionRank(for: $1.statusText) }) else {
            return EvaluationDesign.accent.opacity(0.16)
        }
        let opacity: Double = leading.statusText == "Cerrada" || leading.statusText == "Impartida" ? 0.30 : 0.24
        return leading.statusColor.opacity(opacity)
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
                            Label("S\(row.sessionNumber) · \(row.title.isEmpty ? "Sesión" : row.title)", systemImage: row.statusIcon)
                        }
                    }
                }
            } label: {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Text("\(rows.count)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    )
            }
            .accessibilityLabel("\(rows.count) sesiones esta semana")
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
        } else {
            mark
        }
    }

    private var mark: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint)
            .frame(width: 18, height: 18)
            .overlay(
                Text("\(row.sessionNumber)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
            )
    }

    /// Mismo `statusColor` que ya trae la fila desde el ViewModel — nada de re-derivarlo aquí.
    private var tint: Color { row.statusColor }
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

private struct PlannerProgressMetric: View {
    let value: String
    let label: String
    let tint: Color
    let icon: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.caption.weight(.black))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}
