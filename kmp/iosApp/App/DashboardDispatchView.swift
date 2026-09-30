import SwiftUI
import MiGestorKit

// MARK: - Despacho en 3 franjas
//
// AHORA (qué clase tengo y qué hago) -> ATENCIÓN (una sola lista por
// urgencia) -> CONTEXTO (Agenda, Resumen por grupo y Educación Física
// plegables). Sin franja de KPIs: cada dato vive en un único bloque.
// Un solo árbol de vistas: el paso a 1 columna se hace con `AnyLayout`, no con
// `ViewThatFits` y árboles duplicados.

/// Tarjetas plegables de CONTEXTO.
enum DashboardContextCard: Hashable {
    case agenda
    case groups
    case physicalEducation
}

struct DashboardDispatchHandlers {
    var onNowAction: (DashboardNowAction) -> Void
    var onAttentionAction: (DashboardAttentionItem) -> Void
    var onAttentionSelect: (DashboardAttentionItem) -> Void
    var onSelectSession: (Int64) -> Void
    var onSelectPE: (String) -> Void
    var onRetryAnalysis: () -> Void
}

struct DashboardDispatchView: View {
    let presentation: DashboardPresentation
    /// Frase del briefing de IA (o del radar si la IA no ha respondido).
    let briefing: String?
    let analysisFailed: Bool
    let singleColumn: Bool
    @Binding var hiddenKinds: Set<DashboardAttentionKind>
    @Binding var showAllAttention: Bool
    @Binding var openContext: Set<DashboardContextCard>
    let handlers: DashboardDispatchHandlers

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s4) {
            DashboardNowCard(
                model: presentation.now,
                empty: presentation.nowEmpty,
                singleColumn: singleColumn,
                onAction: handlers.onNowAction
            )
            .dashboardReveal(1)

            DashboardAttentionCard(
                presentation: presentation,
                briefing: briefing,
                analysisFailed: analysisFailed,
                singleColumn: singleColumn,
                hiddenKinds: $hiddenKinds,
                showAll: $showAllAttention,
                handlers: handlers
            )
            .dashboardReveal(2)

            DashboardContextStrip(
                presentation: presentation,
                singleColumn: singleColumn,
                open: $openContext,
                handlers: handlers
            )
            .dashboardReveal(8)
        }
    }
}

// MARK: - Etiqueta de franja

private struct DashboardBandLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(DashboardStyle.Typography.footnoteStrong)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - AHORA

struct DashboardNowCard: View {
    let model: DashboardNowModel?
    let empty: DashboardNowEmpty
    let singleColumn: Bool
    let onAction: (DashboardNowAction) -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var timeSize: CGFloat = 48
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let model {
                if let clock = model.clock {
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        content(model, state: clock.state(at: timeline.date))
                    }
                } else {
                    content(model, state: nil)
                }
            } else {
                emptyContent
            }
        }
        .dashboardCard()
    }

    // MARK: Con clase

    private func content(_ model: DashboardNowModel, state: DashboardSessionClock.State?) -> some View {
        let layout = singleColumn
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DashboardStyle.Spacing.s2))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: DashboardStyle.Spacing.s2))
        return VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s2) {
            DashboardBandLabel(title: model.isLive ? "Ahora" : "Siguiente clase")

            layout {
                titleBlock(model)
                    .frame(maxWidth: .infinity, alignment: .leading)
                timeBlock(model, state: state)
            }

            if model.isLive, let state {
                DashboardProgressBar(
                    progress: state.progress,
                    elapsedMinutes: state.elapsed,
                    totalMinutes: state.total
                )
            }

            actions(model)
                .padding(.top, DashboardStyle.Spacing.s1)
        }
    }

    private func titleBlock(_ model: DashboardNowModel) -> some View {
        VStack(alignment: .leading, spacing: DashboardStyle.Spacing.micro) {
            Text(model.title)
                .font(singleColumn ? DashboardStyle.Typography.title : DashboardStyle.Typography.largeTitle)
                .lineLimit(2)
            if !model.subtitle.isEmpty {
                Text(model.subtitle)
                    .font(DashboardStyle.Typography.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func timeBlock(_ model: DashboardNowModel, state: DashboardSessionClock.State?) -> some View {
        if let state, model.isLive {
            minutesBlock(
                value: state.remaining,
                caption: "min restantes",
                spoken: state.remaining == 1 ? "Queda 1 minuto" : "Quedan \(state.remaining) minutos"
            )
        } else if let state, state.minutesToStart > 0, model.dayLabel == nil {
            minutesBlock(
                value: state.minutesToStart,
                caption: "min para empezar",
                spoken: state.minutesToStart == 1
                    ? "Falta 1 minuto para empezar"
                    : "Faltan \(state.minutesToStart) minutos para empezar"
            )
        } else if let day = model.dayLabel {
            VStack(alignment: singleColumn ? .leading : .trailing, spacing: DashboardStyle.Spacing.micro) {
                Text(day).font(DashboardStyle.Typography.title)
                if let range = model.timeRange {
                    Text(range)
                        .font(DashboardStyle.Typography.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private func minutesBlock(value: Int, caption: String, spoken: String) -> some View {
        VStack(alignment: singleColumn ? .leading : .trailing, spacing: 0) {
            Text("\(value)")
                .font(.system(size: timeSize, weight: .bold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(value)))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: value)
            Text(caption)
                .font(DashboardStyle.Typography.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func actions(_ model: DashboardNowModel) -> some View {
        let layout = singleColumn
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DashboardStyle.Spacing.s2))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DashboardStyle.Spacing.s2))
        return DashboardGlassGroup {
            layout {
                Button {
                    onAction(model.primary)
                } label: {
                    Label(model.primaryTitle, systemImage: model.primary.systemImage)
                        .font(DashboardStyle.Typography.headline)
                        .frame(maxWidth: singleColumn ? .infinity : nil)
                }
                .dashboardButtonStyle(prominent: true, large: true)
                .disabled(model.classId == nil)

                Menu {
                    ForEach(Array(model.menuGroups.enumerated()), id: \.offset) { index, group in
                        if index > 0 { Divider() }
                        ForEach(group) { action in
                            Button {
                                onAction(action)
                            } label: {
                                Label(action.title, systemImage: action.systemImage)
                            }
                            .disabled(model.classId == nil && action != .openPlanner)
                        }
                    }
                    if model.hasSessionJournal {
                        Button {
                            onAction(.openJournal)
                        } label: {
                            Label(DashboardNowAction.openJournal.title, systemImage: DashboardNowAction.openJournal.systemImage)
                        }
                    }
                    if model.offersCreateSession {
                        Divider()
                        Button {
                            onAction(.openPlanner)
                        } label: {
                            Label("Crear sesión en el Planner", systemImage: "calendar.badge.plus")
                        }
                    }
                } label: {
                    Label("Más", systemImage: "ellipsis")
                        .font(DashboardStyle.Typography.headline)
                        .frame(maxWidth: singleColumn ? .infinity : nil)
                }
                .dashboardButtonStyle(large: true)
                .accessibilityLabel("Más acciones")
            }
        }
    }

    // MARK: Sin clase

    private var emptyContent: some View {
        VStack(spacing: DashboardStyle.Spacing.s1) {
            Image(systemName: "calendar")
                .font(.title2)
                .foregroundStyle(DashboardStyle.Tint.pending)
                .frame(width: 56, height: 56)
                .background(DashboardStyle.Tint.pending.opacity(0.10), in: Circle())
                .accessibilityHidden(true)
            Text(empty.title)
                .font(DashboardStyle.Typography.headline)
            Text(empty.detail)
                .font(DashboardStyle.Typography.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(empty.buttonTitle) { onAction(.openPlanner) }
                .dashboardButtonStyle()
                .padding(.top, DashboardStyle.Spacing.s1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DashboardStyle.Spacing.s2)
    }
}

// MARK: - ATENCIÓN

struct DashboardAttentionCard: View {
    let presentation: DashboardPresentation
    let briefing: String?
    let analysisFailed: Bool
    let singleColumn: Bool
    @Binding var hiddenKinds: Set<DashboardAttentionKind>
    @Binding var showAll: Bool
    let handlers: DashboardDispatchHandlers

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let slice = presentation.attention(hidden: hiddenKinds, showAll: showAll)
        let total = presentation.totalAttention

        VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s2) {
            header(total: total)

            if total > 0 {
                briefingLine
            }

            if total == 0 {
                emptyState(
                    title: "Todo al día",
                    detail: "No hay nada que atender ahora.",
                    systemImage: "checkmark",
                    tint: DashboardStyle.Tint.success,
                    showsClear: false
                )
            } else if slice.rows.isEmpty {
                emptyState(
                    title: "Nada con estos filtros",
                    detail: "",
                    systemImage: "line.3.horizontal.decrease",
                    tint: .secondary,
                    showsClear: true
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(slice.rows.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider() }
                        DashboardAttentionRow(
                            item: item,
                            singleColumn: singleColumn,
                            onSelect: { handlers.onAttentionSelect(item) },
                            onAction: { handlers.onAttentionAction(item) }
                        )
                        .dashboardReveal(3 + min(index, 4))
                    }
                }
                .animation(reduceMotion ? nil : .snappy, value: slice.rows.map(\.id))

                footer(slice: slice)
            }
        }
        .dashboardCard()
    }

    // MARK: Cabecera

    private func header(total: Int) -> some View {
        HStack(alignment: .center, spacing: DashboardStyle.Spacing.s1) {
            DashboardBandLabel(title: "Atención")
            if total > 0 {
                Text("\(total)")
                    .font(DashboardStyle.Typography.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(DashboardStyle.accent, in: Capsule())
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(total)))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: total)
                    .accessibilityLabel("\(total) por atender")
            }
            Spacer(minLength: DashboardStyle.Spacing.s1)
            if total > 0 {
                filterMenu
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            ForEach(DashboardAttentionKind.allCases) { kind in
                Toggle(
                    kind.filterTitle,
                    systemImage: kind.systemImage,
                    isOn: Binding(
                        get: { !hiddenKinds.contains(kind) },
                        set: { isOn in
                            if isOn { hiddenKinds.remove(kind) } else { hiddenKinds.insert(kind) }
                        }
                    )
                )
            }
            if !hiddenKinds.isEmpty {
                Divider()
                Button("Quitar filtros", systemImage: "xmark.circle") { hiddenKinds.removeAll() }
            }
        } label: {
            HStack(spacing: DashboardStyle.Spacing.s1) {
                Image(systemName: "line.3.horizontal.decrease")
                Text("Filtrar")
                if !hiddenKinds.isEmpty {
                    Text("\(hiddenKinds.count)")
                        .font(DashboardStyle.Typography.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(DashboardStyle.accent, in: Capsule())
                }
            }
            .font(DashboardStyle.Typography.footnoteStrong)
        }
        .dashboardButtonStyle()
        .accessibilityLabel("Filtrar")
        .accessibilityValue(hiddenKinds.isEmpty ? "Sin filtros" : "\(hiddenKinds.count) filtros activos")
    }

    // MARK: Briefing

    @ViewBuilder
    private var briefingLine: some View {
        if analysisFailed {
            HStack(spacing: DashboardStyle.Spacing.s1) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(DashboardStyle.Tint.alert)
                    .accessibilityHidden(true)
                Text("No se pudo cargar el análisis.")
                    .font(DashboardStyle.Typography.subheadline)
                    .foregroundStyle(.secondary)
                Button("Reintentar", action: handlers.onRetryAnalysis)
                    .font(DashboardStyle.Typography.footnoteStrong)
                    .frame(minHeight: DashboardStyle.minTapSize)
            }
        } else if let briefing, !briefing.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: DashboardStyle.Spacing.s1) {
                Image(systemName: "sparkles")
                    .accessibilityHidden(true)
                Text(briefing)
                    .font(DashboardStyle.Typography.subheadline)
            }
            .foregroundStyle(.secondary)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Pie y vacíos

    @ViewBuilder
    private func footer(slice: DashboardAttentionSlice) -> some View {
        if slice.filteredCount > 5 {
            HStack(spacing: DashboardStyle.Spacing.s1) {
                Text(showAll
                     ? "Mostrando las \(slice.filteredCount)."
                     : "Mostrando \(slice.rows.count) de \(slice.filteredCount).")
                    .font(DashboardStyle.Typography.footnote)
                    .foregroundStyle(.secondary)
                Button(showAll ? "Ver menos" : "Ver todas") {
                    showAll.toggle()
                }
                .font(DashboardStyle.Typography.footnoteStrong)
                .frame(minHeight: DashboardStyle.minTapSize)
            }
        }
    }

    private func emptyState(title: String, detail: String, systemImage: String, tint: Color, showsClear: Bool) -> some View {
        VStack(spacing: DashboardStyle.Spacing.s1) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(tint.opacity(0.11), in: Circle())
                .accessibilityHidden(true)
            Text(title).font(DashboardStyle.Typography.headline)
            if !detail.isEmpty {
                Text(detail)
                    .font(DashboardStyle.Typography.subheadline)
                    .foregroundStyle(.secondary)
            }
            if showsClear {
                Button("Quitar filtros") { hiddenKinds.removeAll() }
                    .dashboardButtonStyle()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DashboardStyle.Spacing.s3)
        .accessibilityElement(children: .combine)
    }
}

private struct DashboardAttentionRow: View {
    let item: DashboardAttentionItem
    let singleColumn: Bool
    let onSelect: () -> Void
    let onAction: () -> Void

    var body: some View {
        let layout = singleColumn
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DashboardStyle.Spacing.s1))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DashboardStyle.Spacing.s2))
        layout {
            Button(action: onSelect) {
                HStack(alignment: .center, spacing: DashboardStyle.Spacing.s2) {
                    Image(systemName: item.kind.systemImage)
                        .font(.headline)
                        .foregroundStyle(item.kind.tint)
                        .frame(width: 40, height: 40)
                        .background(item.kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: DashboardStyle.Spacing.micro) {
                        Text(item.title)
                            .font(DashboardStyle.Typography.headline)
                            .multilineTextAlignment(.leading)
                        if !item.detail.isEmpty {
                            Text(item.detail)
                                .font(DashboardStyle.Typography.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.accessibilitySummary)
            .accessibilityHint("Abre el detalle")
            .accessibilityAction(named: Text(item.action.title), onAction)

            Button(action: onAction) {
                Text(item.action.title)
                    .font(DashboardStyle.Typography.footnoteStrong)
                    .padding(.horizontal, DashboardStyle.Spacing.micro)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(DashboardStyle.accent)
            .frame(minHeight: DashboardStyle.minTapSize)
            .accessibilityLabel("\(item.action.title): \(item.title)")
            .padding(.leading, singleColumn ? 56 : 0)
        }
        .padding(.vertical, DashboardStyle.Spacing.micro)
#if os(iOS)
        .hoverEffect(.highlight)
#endif
        .contextMenu {
            Button(item.action.title, action: onAction)
            Button("Ver detalle", action: onSelect)
        }
    }
}

// MARK: - CONTEXTO

struct DashboardContextStrip: View {
    let presentation: DashboardPresentation
    let singleColumn: Bool
    @Binding var open: Set<DashboardContextCard>
    let handlers: DashboardDispatchHandlers

    var body: some View {
        let layout = singleColumn
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DashboardStyle.Spacing.s2))
            : AnyLayout(HStackLayout(alignment: .top, spacing: DashboardStyle.Spacing.s2))

        VStack(alignment: .leading, spacing: DashboardStyle.Spacing.s1) {
            DashboardBandLabel(title: "Contexto")

            layout {
                DashboardDisclosureCard(
                    title: "Agenda de hoy",
                    systemImage: "calendar",
                    isExpanded: binding(.agenda)
                ) { agendaContent }

                DashboardDisclosureCard(
                    title: "Resumen por grupo",
                    systemImage: "person.3",
                    isExpanded: binding(.groups)
                ) { groupsContent }

                DashboardDisclosureCard(
                    title: "Educación Física",
                    systemImage: "figure.run",
                    isExpanded: binding(.physicalEducation)
                ) { physicalEducationContent }
            }
        }
    }

    private func binding(_ card: DashboardContextCard) -> Binding<Bool> {
        Binding(
            get: { open.contains(card) },
            set: { isOpen in
                if isOpen { open.insert(card) } else { open.remove(card) }
            }
        )
    }

    // MARK: Contenidos

    @ViewBuilder
    private var agendaContent: some View {
        if presentation.agenda.isEmpty {
            DashboardContextEmpty(text: "Sin sesiones hoy.")
        } else {
            ForEach(presentation.agenda) { row in
                Button {
                    handlers.onSelectSession(row.id)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: DashboardStyle.Spacing.s2) {
                        Text(row.timeLabel)
                            .monospacedDigit()
                        Text(row.title)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(DashboardStyle.Typography.subheadline.weight(row.isCurrent ? .semibold : .regular))
                    .foregroundStyle(row.isCurrent ? DashboardStyle.accent : Color.primary)
                    .frame(minHeight: DashboardStyle.minTapSize)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(row.timeLabel), \(row.title)\(row.isCurrent ? ", en curso" : "")")
                Divider()
            }
        }
    }

    @ViewBuilder
    private var groupsContent: some View {
        if presentation.groups.isEmpty {
            DashboardContextEmpty(text: "Sin datos de grupos.")
        } else {
            ForEach(presentation.groups) { group in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: DashboardStyle.Spacing.s1) {
                        Text(group.groupName)
                            .font(DashboardStyle.Typography.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(group.attendancePct) % · media \(IosFormatting.decimal(from: group.averageScore))")
                            .font(DashboardStyle.Typography.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .frame(minHeight: DashboardStyle.minTapSize)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(group.groupName): asistencia \(group.attendancePct) por ciento, media \(IosFormatting.decimal(from: group.averageScore))")
                Divider()
            }
        }
    }

    @ViewBuilder
    private var physicalEducationContent: some View {
        if presentation.peRows.isEmpty {
            DashboardContextEmpty(text: "Sin incidencias de EF hoy.")
        } else {
            ForEach(presentation.peRows) { row in
                Button {
                    handlers.onSelectPE(row.id)
                } label: {
                    VStack(alignment: .leading, spacing: DashboardStyle.Spacing.micro) {
                        Text(row.title).font(DashboardStyle.Typography.subheadline.weight(.semibold))
                        if !row.detail.isEmpty {
                            Text(row.detail)
                                .font(DashboardStyle.Typography.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: DashboardStyle.minTapSize, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                Divider()
            }
        }
    }
}

private struct DashboardContextEmpty: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DashboardStyle.Typography.subheadline)
            .foregroundStyle(.secondary)
            .frame(minHeight: DashboardStyle.minTapSize, alignment: .leading)
    }
}

private struct DashboardDisclosureCard<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                content()
            }
        } label: {
            Label(title, systemImage: systemImage)
                .font(DashboardStyle.Typography.headline)
                .foregroundStyle(.primary)
                .frame(minHeight: 56, alignment: .leading)
        }
        .padding(.horizontal, DashboardStyle.Spacing.s3)
        .padding(.bottom, isExpanded ? DashboardStyle.Spacing.s2 : 0)
        .dashboardCard(padding: 0)
    }
}
