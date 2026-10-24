import SwiftUI
import MiGestorKit

/// Detalle de un torneo de la SdA: calendario por rondas, clasificación o cuadro, resultados,
/// estado, exportar y borrar. Se muestra embebido en la pantalla «Torneos» (sin barra propia) o en
/// una hoja con su propia pila de navegación. El modo directo ocupa siempre toda la pantalla.
struct SdaTournamentDetailView: View {
    enum Presentation {
        /// Dentro de una hoja: barra con «Cerrar», compartir y más acciones.
        case sheet
        /// Dentro de la pantalla «Torneos»: cabecera propia en el contenido.
        case embedded
    }

    let presentation: Presentation
    @StateObject private var store: SdaTournamentStore
    let currentTeams: [TournamentWorkGroupTeam]
    let className: String
    let onDeleted: () -> Void
    /// Se llama con el nombre del torneo si al cerrar no se pudieron guardar los últimos cambios.
    let onSaveFailedAtClose: (String) -> Void
    /// Avisa de que el modo directo se abre o se cierra (la pantalla «Torneos» oculta su lista).
    let onLiveModeChange: (Bool) -> Void
    let deleteRequest: SdaTournamentDeleteRequest?

    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    @State private var rosterPhase: RosterPhase = .loading
    @State private var students: [(id: String, name: String)] = []
    @State private var situationTitle: String?
    @State private var selectedTab: Tab = .calendar
    @State private var scoreTarget: SdaScoreTarget?
    @State private var isConfirmingDelete = false
    @State private var isConfirmingRefresh = false
    @State private var actionError: String?
    @State private var isLive = false
    @State private var contentWidth: CGFloat = 0
    @State private var showingRegistration = false

    /// Ancho a partir del cual la clasificación de una liga se muestra al lado del calendario.
    private static let wideLayoutWidth: CGFloat = 820

    private enum Tab: String, Identifiable {
        case calendar, standings, groups, bracket, teams
        var id: String { rawValue }
        var title: String {
            switch self {
            case .calendar: return "Calendario"
            case .standings: return "Clasificación"
            case .groups: return "Grupos"
            case .bracket: return "Cuadro"
            case .teams: return "Equipos"
            }
        }
    }

    private enum RosterPhase {
        case loading, failed, ready
    }

    private struct SdaScoreTarget: Identifiable {
        let id: UUID
    }

    init(
        record: TournamentRecord,
        plan: TournamentPlan,
        bridge: KmpBridge,
        currentTeams: [TournamentWorkGroupTeam],
        className: String,
        onSaved: @escaping (TournamentRecord) -> Void,
        onDeleted: @escaping () -> Void,
        presentation: Presentation = .sheet,
        onSaveFailedAtClose: @escaping (String) -> Void = { _ in },
        onLiveModeChange: @escaping (Bool) -> Void = { _ in },
        deleteRequest: SdaTournamentDeleteRequest? = nil
    ) {
        self.presentation = presentation
        self.onLiveModeChange = onLiveModeChange
        self.deleteRequest = deleteRequest
        let store = SdaTournamentStore(record: record, plan: plan, bridge: bridge)
        store.onSaved = onSaved
        _store = StateObject(wrappedValue: store)
        self.currentTeams = currentTeams
        self.className = className
        self.onDeleted = onDeleted
        self.onSaveFailedAtClose = onSaveFailedAtClose
    }

    private var plan: TournamentPlan { store.plan }

    private var isEmbedded: Bool { presentation == .embedded }

    private var isWide: Bool { isEmbedded && contentWidth >= Self.wideLayoutWidth }

    /// En una liga y con ancho de sobra, la clasificación va al lado del calendario.
    private var showsStandingsBeside: Bool {
        isWide && (plan.format == .roundRobin || plan.format == .rotation)
    }

    private var tabs: [Tab] {
        switch plan.format {
        case .roundRobin, .rotation:
            return showsStandingsBeside ? [.calendar, .teams] : [.calendar, .standings, .teams]
        case .knockout: return [.calendar, .bracket, .teams]
        case .groupStageKnockout: return [.calendar, .groups, .bracket, .teams]
        }
    }

    /// Torneo creado desde cero para inscribirse por formulario: sin situación ni equipos todavía.
    private var isFromScratch: Bool {
        store.record.learningSituationId == nil && plan.teams.isEmpty
    }

    private var groupsChanged: Bool {
        // Los torneos migrados (sin SdA) no tienen grupos de trabajo que releer, y los de
        // inscripción por formulario forman sus equipos con las respuestas, no con los grupos.
        guard store.record.learningSituationId != nil, plan.registration == nil else { return false }
        return SdaTournamentTeams.hasChanged(
            snapshot: plan.teams,
            current: currentTeams.filter { $0.classId == store.record.classId }
        )
    }

    // MARK: Cuerpo

    var body: some View {
        Group {
            if isEmbedded {
                scrollContent
            } else {
                NavigationStack {
                    scrollContent
                        .navigationTitle(plan.name)
                        .appInlineNavigationBarTitleDisplayMode()
                        .toolbar { toolbarContent }
                }
            }
        }
        .sheet(item: $scoreTarget) { target in
            scoreSheet(for: target)
        }
        .sheet(isPresented: $showingRegistration) {
            SdaTournamentRegistrationSheet(store: store, className: className)
        }
        .confirmationDialog(
            "¿Borrar «\(plan.name)»?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Borrar", role: .destructive) { Task { await deleteTournament() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borran el calendario y los resultados en todos tus dispositivos.")
        }
        .confirmationDialog(
            "¿Actualizar los equipos?",
            isPresented: $isConfirmingRefresh,
            titleVisibility: .visible
        ) {
            Button("Actualizar y borrar resultados", role: .destructive) { refreshTeams() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borran el calendario y los resultados, y se crea un calendario nuevo con los grupos de hoy.")
        }
        .modifier(SdaLiveModePresentation(isPresented: $isLive) {
            NavigationStack {
                SdaTournamentLiveView(store: store, onExit: exitLiveMode)
            }
        })
        .onChange(of: isLive) { _, live in onLiveModeChange(live) }
        .onChange(of: deleteRequest) { _, request in
            if let request, request.tournamentId == store.record.id {
                Task { await deleteTournament() }
            }
        }
        // Al cerrar la pantalla (también arrastrando una hoja) se termina el guardado en curso. La tarea
        // retiene el store, así que acaba aunque la vista ya no exista; si falla, se avisa en la pantalla de origen.
        .onDisappear {
            let store = store
            let notify = onSaveFailedAtClose
            Task {
                await store.flush()
                if store.saveFailed, !store.isDeleted { notify(store.plan.name) }
            }
            if isLive { onLiveModeChange(false) }
        }
        .modifier(SdaSheetChrome(isSheet: !isEmbedded))
        .task {
            // Recién creado desde cero: lo primero es la inscripción.
            if isFromScratch, plan.registration == nil { showingRegistration = true }
            await loadRoster()
        }
        .onChange(of: tabs) { _, newTabs in
            if !newTabs.contains(selectedTab) { selectedTab = .calendar }
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isEmbedded { embeddedHeader }
                summaryCard
                notices
                if plan.savedSchedule.isEmpty {
                    if plan.registration != nil || isFromScratch {
                        LearningSituationInlineNotice(
                            kind: .info,
                            message: "Este torneo no tiene calendario. Forma las parejas desde la inscripción.",
                            actionTitle: "Abrir inscripción"
                        ) {
                            showingRegistration = true
                        }
                    } else {
                        LearningSituationInlineNotice(
                            kind: .warning,
                            message: store.record.learningSituationId == nil
                                ? "Este torneo no tiene calendario."
                                : "Este torneo no tiene calendario. Actualiza los equipos para generarlo.",
                            actionTitle: groupsChanged ? "Actualizar equipos" : nil
                        ) {
                            isConfirmingRefresh = true
                        }
                    }
                } else {
                    if tabs.count > 1 {
                        Picker("Vista", selection: $selectedTab) {
                            ForEach(tabs) { tab in
                                Text(tab.title).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityLabel("Vista del torneo")
                    }
                    content
                }
            }
            .padding(16)
            .frame(maxWidth: isEmbedded ? 1100 : 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            guard abs(contentWidth - newWidth) > 1 else { return }
            contentWidth = newWidth
        }
    }

    private func enterLiveMode() {
        isLive = true
    }

    private func exitLiveMode() {
        isLive = false
        let store = store
        Task { await store.flush() }
    }

    // MARK: Cabecera

    private var summaryCard: some View {
        LearningSituationCard(title: nil) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    if isEmbedded {
                        Spacer(minLength: 0)
                    } else {
                        Image(systemName: plan.format.symbolName)
                            .font(.title2)
                            .foregroundStyle(EvaluationDesign.accent)
                            .accessibilityHidden(true)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    statusMenu
                }
                if plan.totalMatchCount > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(plan.completedMatchCount) de \(sdaPlural(plan.totalMatchCount, "partido", "partidos")) con resultado")
                            .font(.subheadline)
                        ProgressView(
                            value: Double(plan.completedMatchCount),
                            total: Double(max(plan.totalMatchCount, 1))
                        )
                        .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                }
                DatePicker(
                    "Empieza",
                    selection: Binding(
                        get: { store.plan.startDate },
                        set: { newValue in store.mutate { $0.startDate = newValue } }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .frame(minHeight: 44)
                if !isEmbedded, !plan.savedSchedule.isEmpty {
                    liveModeButton(fillsWidth: true)
                }
            }
        }
    }

    private func liveModeButton(fillsWidth: Bool) -> some View {
        Button(action: enterLiveMode) {
            Label("Modo directo", systemImage: "play.circle.fill")
                .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityHint("Abre a pantalla completa el temporizador y los marcadores grandes de la ronda actual.")
    }

    /// Cabecera de la pantalla «Torneos»: nombre, acciones y datos del torneo.
    private var embeddedHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(plan.name)
                    .font(.title.weight(.bold))
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                ShareLink(item: plan.exportText, subject: Text(plan.name)) {
                    Label("Compartir", systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .disabled(plan.savedSchedule.isEmpty)
                .accessibilityLabel("Compartir calendario y resultados")
                moreActionsMenu
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !plan.savedSchedule.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        liveModeButton(fillsWidth: false)
                        printButton(prominent: false, fillsWidth: false)
                    }
                    VStack(spacing: 12) {
                        liveModeButton(fillsWidth: true)
                        printButton(prominent: false, fillsWidth: true)
                    }
                }
            }
        }
    }

    private var moreActionsMenu: some View {
        Menu {
            Button {
                showingRegistration = true
            } label: {
                Label(plan.registration == nil ? "Inscripción por formulario…" : "Inscripción…", systemImage: "person.crop.circle.badge.plus")
            }
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Borrar torneo…", systemImage: "trash")
            }
        } label: {
            Label("Más acciones", systemImage: "ellipsis.circle")
        }
        .accessibilityLabel("Más acciones")
    }

    private var subtitle: String {
        [
            className,
            plan.format.shortTitle,
            sdaPlural(plan.teamCount, "equipo", "equipos"),
            sdaPlural(plan.venueCount, "pista", "pistas"),
            "\(plan.matchDurationMinutes) min por partido"
        ].joined(separator: " · ")
    }

    private var statusMenu: some View {
        Menu {
            ForEach([TournamentPlanStatus.draft, .scheduled, .live, .finished], id: \.self) { status in
                Button {
                    store.mutate { $0.status = status }
                } label: {
                    if status == plan.status {
                        Label(status.title, systemImage: "checkmark")
                    } else {
                        Text(status.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                SdaStatusBadge(status: plan.status)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Cambiar estado")
        .accessibilityValue(plan.status.title)
    }

    @ViewBuilder
    private var notices: some View {
        if store.saveFailed {
            LearningSituationInlineNotice(
                kind: .error,
                message: "No se pudo guardar el último cambio.",
                actionTitle: "Reintentar"
            ) {
                store.retrySave()
            }
        }
        if let actionError {
            LearningSituationInlineNotice(kind: .error, message: actionError)
        }
        if groupsChanged, !plan.savedSchedule.isEmpty {
            LearningSituationInlineNotice(
                kind: .warning,
                message: "Los grupos han cambiado desde que creaste este torneo.",
                actionTitle: "Actualizar equipos"
            ) {
                isConfirmingRefresh = true
            }
        }
    }

    // MARK: Barra

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cerrar") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
            ShareLink(item: plan.exportText, subject: Text(plan.name)) {
                Label("Compartir", systemImage: "square.and.arrow.up")
            }
            .disabled(plan.savedSchedule.isEmpty)
            .accessibilityLabel("Compartir calendario y resultados")
        }
        ToolbarItem(placement: .primaryAction) {
            moreActionsMenu
        }
    }

    // MARK: Contenido

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .calendar:
            if showsStandingsBeside {
                HStack(alignment: .top, spacing: 16) {
                    calendarContent
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    standingsContent
                        .frame(width: 340, alignment: .topLeading)
                }
            } else {
                calendarContent
            }
        case .standings: standingsContent
        case .groups: groupsContent
        case .bracket: bracketContent
        case .teams: teamsContent
        }
    }

    private var calendarContent: some View {
        let slots = plan.slots
        let slotsByRound = Dictionary(grouping: slots, by: \.roundNumber)
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(plan.savedSchedule.enumerated()), id: \.element.id) { index, round in
                let roundSlots = (slotsByRound[round.number] ?? []).sorted { $0.venueNumber < $1.venueNumber }
                let showsStage = index == 0 || plan.savedSchedule[index - 1].stage != round.stage
                VStack(alignment: .leading, spacing: 8) {
                    if showsStage, let stageTitle = round.stage.sdaTitle {
                        Text(stageTitle)
                            .font(.title3.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, index == 0 ? 0 : 8)
                    }
                    LearningSituationCard(title: nil) {
                        roundHeader(round, startDate: roundSlots.first?.startDate)
                        ForEach(Array(roundSlots.enumerated()), id: \.element.id) { matchIndex, slot in
                            if matchIndex > 0 { Divider() }
                            matchRow(slot)
                        }
                    }
                }
            }
        }
    }

    private func roundHeader(_ round: ScheduledRound, startDate: Date?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Ronda \(round.number)")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let startDate {
                Text(startDate.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func matchRow(_ slot: ScheduledMatchSlot) -> some View {
        let names = plan.displayTeams(for: slot)
        return SdaMatchRow(
            venue: slot.venueNumber,
            home: names.home,
            away: names.away,
            score: plan.result(for: slot),
            isEnabled: plan.canScore(slot)
        ) {
            scoreTarget = SdaScoreTarget(id: slot.id)
        }
    }

    private var standingsContent: some View {
        LearningSituationCard(title: "Clasificación") {
            if plan.savedResults.isEmpty {
                Text("Aún no hay resultados. La tabla se llena al anotarlos en el calendario.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            SdaStandingsTable(standings: plan.leagueStandings)
        }
    }

    private var groupsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(plan.groupStandings.enumerated()), id: \.offset) { _, group in
                LearningSituationCard(title: group.name) {
                    SdaStandingsTable(standings: group.standings)
                }
            }
        }
    }

    private var bracketContent: some View {
        let slotsByID = Dictionary(plan.slots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let stages = KnockoutBracketResolver.stages(in: plan.savedSchedule)
        return VStack(alignment: .leading, spacing: 16) {
            if let champion = plan.champion {
                Label("Campeón: \(champion)", systemImage: "trophy.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(IOSAppStyle.success)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityElement(children: .combine)
            }
            if plan.format == .groupStageKnockout, !plan.groupStageIsComplete {
                LearningSituationInlineNotice(
                    kind: .info,
                    message: "Los cruces se abren cuando terminan todos los partidos de la fase de grupos."
                )
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                ForEach(stages) { stage in
                    LearningSituationCard(title: stage.title) {
                        ForEach(Array(stage.matches.enumerated()), id: \.element.id) { index, match in
                            if index > 0 { Divider() }
                            if let slot = slotsByID[match.id] {
                                matchRow(slot)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Equipos

    private var resolvedTeams: [SdaResolvedTeam] {
        SdaTournamentRoster.resolve(teams: plan.teams, students: students)
    }

    /// Contenido de la hoja imprimible; `nil` mientras no se conocen los nombres.
    private var teamsSheetContent: SdaTeamsSheetContent? {
        guard rosterPhase == .ready else { return nil }
        return SdaTeamsSheetContent.make(
            plan: plan,
            situationTitle: situationTitle,
            className: className,
            teams: resolvedTeams
        )
    }

    @ViewBuilder
    private var teamsContent: some View {
        switch rosterPhase {
        case .loading:
            LearningSituationSkeletonBlock(lines: 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Cargando equipos")
        case .failed:
            LearningSituationInlineNotice(
                kind: .error,
                message: "No se pudieron cargar los nombres de los alumnos.",
                actionTitle: "Reintentar"
            ) {
                Task { await loadRoster() }
            }
        case .ready:
            VStack(alignment: .leading, spacing: 16) {
                ForEach(resolvedTeams) { team in
                    LearningSituationCard(title: nil) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(team.name)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            Spacer(minLength: 8)
                            Text(team.countText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if team.memberNames.isEmpty {
                            Text("Sin alumnos. Añádelos en el Cuaderno.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(team.memberNames.enumerated()), id: \.offset) { _, name in
                                    Text(name)
                                        .font(.subheadline)
                                        .italic(name == SdaResolvedTeam.missingStudentName)
                                        .foregroundStyle(name == SdaResolvedTeam.missingStudentName ? .secondary : .primary)
                                }
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                printButton(prominent: true, fillsWidth: true)
            }
        }
    }

    @ViewBuilder
    private func printButton(prominent: Bool, fillsWidth: Bool) -> some View {
        if let content = teamsSheetContent {
            #if os(macOS)
            Button {
                // El PDF se genera al pulsar: nunca hay un fichero viejo o borrado.
                if let url = SdaTeamsSheetPDF.writeToTemporaryFile(content) {
                    SdaTeamsSheetPrinter.printPDF(at: url)
                }
            } label: {
                printLabel(fillsWidth: fillsWidth)
            }
            .sdaPrintButtonStyle(prominent: prominent)
            #else
            let document = SdaTeamsSheetDocument(content: content)
            ShareLink(item: document, preview: SharePreview("Equipos de \(plan.name)", image: Image(systemName: "doc.richtext"))) {
                printLabel(fillsWidth: fillsWidth)
            }
            .sdaPrintButtonStyle(prominent: prominent)
            .accessibilityHint("Abre la hoja de compartir con el PDF. Elige Imprimir.")
            #endif
        } else {
            printLabel(fillsWidth: fillsWidth)
                .foregroundStyle(.secondary)
                .accessibilityHint("Preparando el PDF.")
        }
    }

    private func printLabel(fillsWidth: Bool) -> some View {
        Label("Imprimir equipos", systemImage: "printer")
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 44)
    }

    private func loadRoster() async {
        rosterPhase = .loading
        do {
            let classStudents = try await bridge.students(forClassId: store.record.classId)
            students = classStudents.map { (id: String($0.id), name: $0.fullName) }
            if let situationId = store.record.learningSituationId {
                situationTitle = try? await bridge.learningSituations().first(where: { $0.id == situationId })?.title
            }
            rosterPhase = .ready
        } catch {
            rosterPhase = .failed
        }
    }

    // MARK: Hoja de resultado

    @ViewBuilder
    private func scoreSheet(for target: SdaScoreTarget) -> some View {
        if let slot = store.plan.slots.first(where: { $0.id == target.id }) {
            let names = store.plan.displayTeams(for: slot)
            SdaMatchScoreSheet(
                home: names.home,
                away: names.away,
                venue: slot.venueNumber,
                requiresWinner: store.plan.isKnockoutSlot(slot),
                initialScore: store.plan.result(for: slot),
                onSave: { home, away in
                    store.mutate { $0.setScore(for: slot, home: home, away: away) }
                },
                onClear: {
                    store.mutate { $0.clearScore(for: slot) }
                }
            )
        }
    }

    // MARK: Acciones

    private func refreshTeams() {
        actionError = nil
        do {
            try store.mutateThrowing { try $0.updateTeams(from: currentTeams.filter { $0.classId == store.record.classId }) }
        } catch {
            actionError = "No se pudo actualizar. Hacen falta al menos dos grupos en el curso."
        }
    }

    private func deleteTournament() async {
        actionError = nil
        do {
            try await store.delete()
            onDeleted()
            if !isEmbedded { dismiss() }
        } catch {
            actionError = "No se pudo borrar el torneo. Inténtalo de nuevo."
        }
    }
}

/// Petición de borrar el torneo mostrado, hecha desde fuera (menú contextual de la lista). La atiende
/// el propio detalle para que el borrado espere al guardado en curso. `nonce` permite repetirla.
struct SdaTournamentDeleteRequest: Equatable {
    let tournamentId: String
    let nonce = UUID()
}

/// Contenido de un torneo (dentro de una SdA o migrado, solo de curso), en hoja o embebido. Lee el
/// registro una sola vez al abrirse, así borrarlo no deja ver un estado intermedio mientras se cierra.
/// Quien lo embebe debe darle `.id(record.id)` para que cambiar de torneo lo recargue.
struct SdaTournamentSheetHost: View {
    let presentation: SdaTournamentDetailView.Presentation
    let currentTeams: [TournamentWorkGroupTeam]
    let className: String
    let onSaved: (TournamentRecord) -> Void
    let onDeleted: () -> Void
    let onSaveFailedAtClose: (String) -> Void
    let onLiveModeChange: (Bool) -> Void
    let deleteRequest: SdaTournamentDeleteRequest?
    private let recordId: String?
    private let recordName: String
    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: Loaded?
    @State private var isConfirmingUnreadableDelete = false
    @State private var unreadableDeleteError: String?

    private struct Loaded {
        let record: TournamentRecord
        let plan: TournamentPlan
    }

    init(
        record: TournamentRecord?,
        currentTeams: [TournamentWorkGroupTeam],
        className: String,
        onSaved: @escaping (TournamentRecord) -> Void,
        onDeleted: @escaping () -> Void,
        presentation: SdaTournamentDetailView.Presentation = .sheet,
        onSaveFailedAtClose: @escaping (String) -> Void,
        onLiveModeChange: @escaping (Bool) -> Void = { _ in },
        deleteRequest: SdaTournamentDeleteRequest? = nil
    ) {
        self.presentation = presentation
        self.onLiveModeChange = onLiveModeChange
        self.deleteRequest = deleteRequest
        self.recordId = record?.id
        self.recordName = record?.name ?? "este torneo"
        self.currentTeams = currentTeams
        self.className = className
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        self.onSaveFailedAtClose = onSaveFailedAtClose
        let loaded = record.flatMap { record in
            (try? record.plan()).map { Loaded(record: record, plan: $0) }
        }
        _loaded = State(initialValue: loaded)
    }

    var body: some View {
        if let loaded {
            SdaTournamentDetailView(
                record: loaded.record,
                plan: loaded.plan,
                bridge: bridge,
                currentTeams: currentTeams,
                className: className,
                onSaved: onSaved,
                onDeleted: onDeleted,
                presentation: presentation,
                onSaveFailedAtClose: onSaveFailedAtClose,
                onLiveModeChange: onLiveModeChange,
                deleteRequest: deleteRequest
            )
        } else if presentation == .embedded {
            VStack(spacing: 16) {
                ContentUnavailableView(
                    "No se pudo abrir el torneo",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Su contenido guardado no se puede leer. Puedes borrarlo.")
                )
                if let unreadableDeleteError {
                    LearningSituationInlineNotice(kind: .error, message: unreadableDeleteError)
                        .padding(.horizontal, 16)
                }
                Button(role: .destructive) {
                    isConfirmingUnreadableDelete = true
                } label: {
                    Label("Borrar torneo…", systemImage: "trash")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(recordId == nil)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .confirmationDialog(
                "¿Borrar «\(recordName)»?",
                isPresented: $isConfirmingUnreadableDelete,
                titleVisibility: .visible
            ) {
                Button("Borrar", role: .destructive) { Task { await deleteUnreadable() } }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se borran el calendario y los resultados en todos tus dispositivos.")
            }
            .onChange(of: deleteRequest) { _, request in
                if let request, request.tournamentId == recordId {
                    Task { await deleteUnreadable() }
                }
            }
        } else {
            NavigationStack {
                ContentUnavailableView(
                    "No se pudo abrir el torneo",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Su contenido guardado no se puede leer.")
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { dismiss() }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 420, minHeight: 320)
            #endif
        }
    }
}

extension SdaTournamentSheetHost {
    /// Borra un torneo cuyo contenido no se puede leer (no hay store: se borra directo).
    fileprivate func deleteUnreadable() async {
        guard let recordId else { return }
        do {
            try await bridge.deleteTournament(id: recordId)
            onDeleted()
        } catch {
            unreadableDeleteError = "No se pudo borrar el torneo. Inténtalo de nuevo."
        }
    }
}

// MARK: - Presentación

/// Tamaño y asa de arrastre solo cuando el detalle va en una hoja.
private struct SdaSheetChrome: ViewModifier {
    let isSheet: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        if isSheet {
            content.frame(minWidth: 560, minHeight: 640)
        } else {
            content
        }
        #else
        if isSheet {
            content
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        } else {
            content
        }
        #endif
    }
}

/// Modo directo a pantalla completa. iOS e iPadOS: `fullScreenCover` (tapa también el menú lateral).
/// macOS no tiene `fullScreenCover`: una capa opaca sobre todo el contenido de la pantalla «Torneos».
private struct SdaLiveModePresentation<Live: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let live: () -> Live

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .accessibilityHidden(isPresented)
            .disabled(isPresented)
            .overlay {
            if isPresented {
                live()
                    .background(.background)
                    .transition(.opacity)
            }
        }
        #else
        content.fullScreenCover(isPresented: $isPresented) { live() }
        #endif
    }
}

private extension View {
    @ViewBuilder
    func sdaPrintButtonStyle(prominent: Bool) -> some View {
        if prominent {
            self.buttonStyle(.borderedProminent).controlSize(.large)
        } else {
            self.buttonStyle(.bordered).controlSize(.large)
        }
    }
}
