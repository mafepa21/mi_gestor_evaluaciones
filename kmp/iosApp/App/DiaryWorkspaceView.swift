import SwiftUI
import MiGestorKit

struct DiaryWorkspaceView: View {
    @EnvironmentObject var bridge: KmpBridge
    @EnvironmentObject var layoutState: WorkspaceLayoutState
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @Binding var selectedClassId: Int64?
    let navigationContext: PlannerNavigationContext
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    let onOpenPlanner: (PlannerNavigationContext) -> Void
    let onNavigationContextChange: (PlannerNavigationContext) -> Void

    @StateObject var vm = PlannerWorkspaceViewModel()
    @State var selectedFilter: DiaryStatusFilter = .all
    @State var selectedDayFilter = "Todos"
    @State var selectedUnitFilter = "Todas"
    @State var showingInspector = false

    var availableDays: [String] {
        ["Todos", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes"]
    }

    var availableUnits: [String] {
        ["Todas"] + Array(Set(vm.sessions.map(\.teachingUnitName))).sorted()
    }

    var diarySessions: [PlanningSession] {
        vm.filteredSessions.filter { session in
            let summary = vm.summary(for: session.id)
            let matchesFilter: Bool = {
                switch selectedFilter {
                case .all:
                    return true
                case .drafts:
                    return summary?.status == .draft
                case .completed:
                    return summary?.status == .completed
                case .incomplete:
                    let status = summary?.status ?? .empty
                    return status != .completed
                case .incidents:
                    return !(summary?.incidentTags.isEmpty ?? true)
                case .empty:
                    return summary == nil || summary?.status == .empty
                }
            }()

            let matchesDay = selectedDayFilter == "Todos" || weekdayLabel(session.dayOfWeek) == selectedDayFilter
            let matchesUnit = selectedUnitFilter == "Todas" || session.teachingUnitName == selectedUnitFilter

            return matchesFilter && matchesDay && matchesUnit
        }
    }

    var currentNavigationContext: PlannerNavigationContext {
        PlannerNavigationContext(
            week: vm.week,
            year: vm.year,
            groupId: selectedSession?.groupId ?? selectedClassId,
            sessionId: selectedSession?.id
        )
    }

    var selectedSession: PlanningSession? {
        vm.selectedSession
    }

    var diaryMetrics: (total: Int, pending: Int, incidents: Int) {
        let total = diarySessions.count
        let pending = diarySessions.filter { (vm.summary(for: $0.id)?.status ?? .empty) != .completed }.count
        let incidents = diarySessions.filter { !(vm.summary(for: $0.id)?.incidentTags.isEmpty ?? true) }.count
        return (total, pending, incidents)
    }

    var selectedSummary: SessionJournalSummary? {
        selectedSession.flatMap { vm.summary(for: $0.id) }
    }

    var diaryToolbarKey: String {
        "\(selectedSession?.id ?? -1)-\(showingInspector)"
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 16) {
                diaryLocalToolbar

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(diarySessions, id: \.id) { session in
                            let sessionSummary = vm.summary(for: session.id)
                            let isSessionSelected = session.id == selectedSession?.id
                            let sessionTimeLabel = vm.timeLabel(for: Int(session.period))
                            DiarySessionRailCard(
                                session: session,
                                summary: sessionSummary,
                                isSelected: isSessionSelected,
                                timeLabel: sessionTimeLabel,
                                onTap: {
                                    AppleInteractionFeedback.play(.selection)
                                    Task { await vm.select(session: session) }
                                },
                                onOpenAttendance: {
                                    onOpenModule(.attendance, session.groupId, nil)
                                },
                                onOpenNotebook: {
                                    onOpenModule(.notebook, session.groupId, nil)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
            .frame(minWidth: 320, maxWidth: 360, maxHeight: .infinity, alignment: .top)
            .background(appMutedCardBackground(for: colorScheme).opacity(0.28))

            Divider().opacity(0.2)

            Group {
                if selectedSession != nil {
                    PlannerJournalDetailPane(vm: vm, efVisibility: .contextual)
                } else {
                    VStack(spacing: 18) {
                        WorkspaceEmptyState(
                            title: "Selecciona una sesión",
                            subtitle: "La sesión activa ocupará este espacio con edición inline, métricas y seguimiento sin saltar a otra pantalla."
                        )
                        HStack(spacing: 12) {
                            Button("Ver planner") {
                                onOpenPlanner(currentNavigationContext)
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Ir a asistencia") {
                                onOpenModule(.attendance, selectedClassId, nil)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appPageBackground(for: colorScheme))

            if showingInspector, let session = selectedSession {
                Divider().opacity(0.2)
                DiaryInspectorPanel(
                    session: session,
                    summary: selectedSummary,
                    timeLabel: vm.timeLabel(for: Int(session.period)),
                    onOpenAttendance: {
                        onOpenModule(.attendance, session.groupId, nil)
                    },
                    onOpenNotebook: {
                        onOpenModule(.notebook, session.groupId, nil)
                    },
                    onOpenStudents: {
                        onOpenModule(.students, session.groupId, nil)
                    }
                )
                .frame(width: 340)
                .background(appMutedCardBackground(for: colorScheme).opacity(0.22))
                .transition(uiFeatureFlags.inspectorTransition)
            }
        }
        .task {
            await vm.bind(bridge: bridge)
            await vm.applyExternalContext(
                week: navigationContext.week,
                year: navigationContext.year,
                groupId: navigationContext.groupId ?? selectedClassId,
                sessionId: navigationContext.sessionId
            )
            syncSelection()
            configureDiaryToolbar()
            syncNavigationContext()
        }
        .appOnChange(of: selectedClassId) { _ in
            Task {
                await vm.applyExternalContext(
                    week: navigationContext.week ?? vm.week,
                    year: navigationContext.year ?? vm.year,
                    groupId: selectedClassId,
                    sessionId: selectedSession?.id
                )
                syncSelection()
                syncNavigationContext()
            }
        }
        .appOnChange(of: navigationContext) { newValue in
            Task {
                await vm.applyExternalContext(
                    week: newValue.week,
                    year: newValue.year,
                    groupId: newValue.groupId ?? selectedClassId,
                    sessionId: newValue.sessionId
                )
                syncSelection()
                syncNavigationContext()
            }
        }
        .appOnChange(of: vm.searchText) { _ in
            vm.applySearch()
        }
        .appOnChange(of: diaryToolbarKey) { _ in
            configureDiaryToolbar()
        }
        .appOnChange(of: diarySessions.map(\.id)) { _ in
            syncSelection()
        }
        .appOnChange(of: vm.week) { _ in syncNavigationContext() }
        .appOnChange(of: vm.year) { _ in syncNavigationContext() }
        .appOnChange(of: vm.selectedSession?.id) { _ in
            syncSelection()
            syncNavigationContext()
        }
        .onDisappear {
            layoutState.clearDiaryToolbar()
        }
        .animation(uiFeatureFlags.interactionAnimation, value: showingInspector)
    }

    func weekdayLabel(_ dayOfWeek: Int32) -> String {
        switch Int(dayOfWeek) {
        case 1: return "Lunes"
        case 2: return "Martes"
        case 3: return "Miércoles"
        case 4: return "Jueves"
        case 5: return "Viernes"
        default: return "Sesión"
        }
    }

    func fallback(_ value: String, empty placeholder: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? placeholder : value
    }

    var diaryLocalToolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Semana \(vm.week), \(vm.year)")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                    Text(vm.dateRangeLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await vm.previousWeek() }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await vm.nextWeek() }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Buscar sesión, unidad o grupo…", text: $vm.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 8) {
                Picker("Estado", selection: $selectedFilter) {
                    ForEach(DiaryStatusFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.menu)

                Picker("Día", selection: $selectedDayFilter) {
                    ForEach(availableDays, id: \.self) { day in
                        Text(day).tag(day)
                    }
                }
                .pickerStyle(.menu)

                Picker("Unidad", selection: $selectedUnitFilter) {
                    ForEach(availableUnits, id: \.self) { unit in
                        Text(unit).tag(unit)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 10) {
                WorkspaceCompactStat(title: "Sesiones", value: "\(diaryMetrics.total)", tint: .blue)
                WorkspaceCompactStat(title: "Pendientes", value: "\(diaryMetrics.pending)", tint: .orange)
                WorkspaceCompactStat(title: "Incidencias", value: "\(diaryMetrics.incidents)", tint: .pink)
            }
        }
        .padding(16)
    }

    @MainActor
    func syncSelection() {
        if !availableUnits.contains(selectedUnitFilter) {
            selectedUnitFilter = "Todas"
        }

        guard !diarySessions.isEmpty else { return }
        if let current = selectedSession, diarySessions.contains(where: { $0.id == current.id }) {
            return
        }

        if let first = diarySessions.first {
            Task { await vm.select(session: first) }
        }
    }

    func configureDiaryToolbar() {
        layoutState.configureDiaryToolbar(
            inspectorAvailable: selectedSession != nil,
            isInspectorPresented: showingInspector,
            onToggleInspector: {
                showingInspector.toggle()
            }
        )
    }

    func syncNavigationContext() {
        onNavigationContextChange(currentNavigationContext)
    }
}

enum DiaryStatusFilter: String, CaseIterable, Identifiable {
    case all
    case drafts
    case completed
    case incomplete
    case incidents
    case empty

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Todos"
        case .drafts: return "Borradores"
        case .completed: return "Completadas"
        case .incomplete: return "Incompletas"
        case .incidents: return "Con incidencias"
        case .empty: return "Sin diario"
        }
    }
}

struct DiarySessionRailCard: View {
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    let session: PlanningSession
    let summary: SessionJournalSummary?
    let isSelected: Bool
    let timeLabel: String
    let onTap: () -> Void
    let onOpenAttendance: () -> Void
    let onOpenNotebook: () -> Void

    @State private var revealsActions = false
    @State private var trackpadTranslation: CGFloat = 0
    @GestureState private var translation: CGFloat = 0

    private let actionWidth: CGFloat = 150

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 6) {
                diarySwipeButton("Asistencia", systemImage: "checklist.checked", tint: EvaluationDesign.success, action: onOpenAttendance)
                diarySwipeButton("Cuaderno", systemImage: "book.closed", tint: EvaluationDesign.accent, action: onOpenNotebook)
            }
            .padding(.trailing, 8)

            Button(action: onTap) {
                NotebookSurface(
                    cornerRadius: 18,
                    fill: isSelected ? NotebookStyle.surface : NotebookStyle.surfaceSoft,
                    padding: 14
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.teachingUnitName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text("\(weekdayLabel(session.dayOfWeek)) · \(timeLabel)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            NotebookPill(
                                label: diaryStatusText(summary),
                                systemImage: "doc.text",
                                active: isSelected,
                                tint: badgeTint
                            )
                        }

                        Text(session.groupName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if !(summary?.incidentTags.isEmpty ?? true) {
                            Text(summary?.incidentTags.prefix(2).joined(separator: " · ") ?? "")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.pink)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isSelected ? EvaluationDesign.accent.opacity(0.28) : .clear, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
            .offset(x: cardOffset)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 12)
                .updating($translation) { value, state, _ in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    state = revealsActions ? value.translation.width : min(0, value.translation.width)
                }
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    withAnimation(uiFeatureFlags.interactionAnimation) {
                        if revealsActions {
                            revealsActions = value.translation.width < 36
                        } else {
                            revealsActions = value.translation.width < -36
                        }
                    }
                }
        )
        .macTrackpadSwipe { delta in
            trackpadTranslation = delta
        } onEnded: { delta in
            withAnimation(uiFeatureFlags.interactionAnimation) {
                if revealsActions {
                    revealsActions = delta < 36
                } else {
                    revealsActions = delta < -36
                }
            }
            trackpadTranslation = 0
        }
        .animation(uiFeatureFlags.interactionAnimation, value: isSelected)
    }

    private var cardOffset: CGFloat {
        let activeTranslation = trackpadTranslation != 0 ? trackpadTranslation : translation
        return max(-actionWidth, min(0, (revealsActions ? -actionWidth : 0) + activeTranslation))
    }

    private func diarySwipeButton(
        _ title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            withAnimation(.easeOut(duration: 0.15)) {
                revealsActions = false
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 66, height: 48)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    var badgeTint: Color {
        switch summary?.status ?? .empty {
        case .completed: return EvaluationDesign.success
        case .draft: return EvaluationDesign.accent
        default: return .secondary
        }
    }

    func diaryStatusText(_ summary: SessionJournalSummary?) -> String {
        guard let summary else { return "Sin diario" }
        if !(summary.incidentTags.isEmpty) {
            return "\(summary.status.name.capitalized) · alerta"
        }
        return summary.status.name.capitalized
    }

    func weekdayLabel(_ dayOfWeek: Int32) -> String {
        switch Int(dayOfWeek) {
        case 1: return "Lunes"
        case 2: return "Martes"
        case 3: return "Miércoles"
        case 4: return "Jueves"
        case 5: return "Viernes"
        default: return "Sesión"
        }
    }
}

struct DiaryInspectorPanel: View {
    let session: PlanningSession
    let summary: SessionJournalSummary?
    let timeLabel: String
    let onOpenAttendance: () -> Void
    let onOpenNotebook: () -> Void
    let onOpenStudents: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WorkspaceInspectorHero(
                    title: session.teachingUnitName,
                    subtitle: "\(session.groupName) · \(weekdayLabel(session.dayOfWeek)) · \(timeLabel)"
                )

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    WorkspaceMetricCard(
                        title: "Estado",
                        value: summary?.status.name.capitalized ?? "Sin diario",
                        systemImage: "doc.text"
                    )
                    WorkspaceMetricCard(
                        title: "Clima",
                        value: summary.map { "\($0.climateScore)/5" } ?? "-",
                        systemImage: "sun.max.fill"
                    )
                    WorkspaceMetricCard(
                        title: "Participación",
                        value: summary.map { "\($0.participationScore)/5" } ?? "-",
                        systemImage: "person.3.sequence.fill"
                    )
                    WorkspaceMetricCard(
                        title: "Adjuntos",
                        value: summary.map { "\($0.mediaCount)" } ?? "0",
                        systemImage: "paperclip"
                    )
                }

                WorkspaceDetailBlock(title: "Objetivos", content: fallback(session.objectives, empty: "Sin objetivos definidos"))
                WorkspaceDetailBlock(title: "Actividades", content: fallback(session.activities, empty: "Sin actividades descritas"))
                WorkspaceDetailBlock(title: "Evaluación", content: fallback(session.evaluation, empty: "Sin observaciones evaluativas"))

                if let summary, !summary.incidentTags.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Incidencias")
                            .font(.headline)
                        WorkspaceFlowLayout(spacing: 8) {
                            ForEach(Array(summary.incidentTags.enumerated()), id: \.offset) { _, tag in
                                WorkspaceTag(text: tag, systemImage: "exclamationmark.triangle.fill")
                            }
                        }
                    }
                }

                if let summary {
                    WorkspaceDetailBlock(
                        title: "Pulso de la sesión",
                        content: fallback(summary.weatherText, empty: "Sin observaciones contextuales")
                    )
                }

                VStack(spacing: 10) {
                    WorkspaceActionRow(title: "Ir a asistencia", systemImage: "checklist.checked", action: onOpenAttendance)
                    WorkspaceActionRow(title: "Abrir cuaderno", systemImage: "square.grid.3x3.fill", action: onOpenNotebook)
                    WorkspaceActionRow(title: "Ver alumnado", systemImage: "person.3.fill", action: onOpenStudents)
                }
            }
            .padding(20)
        }
    }

    func weekdayLabel(_ dayOfWeek: Int32) -> String {
        switch Int(dayOfWeek) {
        case 1: return "Lunes"
        case 2: return "Martes"
        case 3: return "Miércoles"
        case 4: return "Jueves"
        case 5: return "Viernes"
        default: return "Sesión"
        }
    }

    func fallback(_ value: String, empty placeholder: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? placeholder : value
    }
}
