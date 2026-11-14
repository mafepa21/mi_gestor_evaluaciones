import SwiftUI

/// Modo directo: ronda actual, temporizador, marcadores grandes con − / + y paso de ronda.
/// Cada toque se guarda al momento a través del `SdaTournamentStore`. En el iPad, además, publica
/// su estado (ronda, reloj, marcadores, escena) para la proyección del Mac (`TournamentLivePublisher`);
/// si no hay Mac enlazado o proyectando, no cambia nada.
struct SdaTournamentLiveView: View {
    @ObservedObject var store: SdaTournamentStore
    /// Cuando el modo directo ocupa toda la pantalla, quien lo presenta da aquí cómo cerrarlo
    /// y se muestra un botón «Salir» explícito. Sin él (uso apilado) se vuelve con «Atrás».
    var onExit: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @StateObject private var publisher: TournamentLivePublisher
    #endif
    @State private var projectionScene: TournamentLiveScene = .auto

    @State private var roundIndex: Int
    @State private var timerEnd: Date?
    @State private var pausedRemaining: Int?
    @State private var isRunning = false
    @State private var timeIsUp = false
    // Pensado para leerse a varios metros en el pabellón: marcador y reloj muy grandes.
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 96
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 88
    @ScaledMetric(relativeTo: .body) private var tapSize: CGFloat = 44

    /// `bridge` da el enlace con el Mac para la proyección; sin él (o en macOS) no se publica nada.
    init(store: SdaTournamentStore, bridge: KmpBridge? = nil, onExit: (() -> Void)? = nil) {
        self.store = store
        self.onExit = onExit
        #if os(iOS)
        _publisher = StateObject(wrappedValue: TournamentLivePublisher(bridge: bridge))
        #endif
        _roundIndex = State(initialValue: Self.firstPendingRoundIndex(store.plan))
    }

    // MARK: Datos

    private var plan: TournamentPlan { store.plan }
    private var rounds: [ScheduledRound] { plan.savedSchedule }

    private var currentRound: ScheduledRound? {
        rounds.indices.contains(roundIndex) ? rounds[roundIndex] : nil
    }

    private var roundSlots: [ScheduledMatchSlot] {
        guard let currentRound else { return [] }
        return plan.slots
            .filter { $0.roundNumber == currentRound.number }
            .sorted { $0.venueNumber < $1.venueNumber }
    }

    private var isLastRound: Bool { roundIndex >= rounds.count - 1 }

    private var pendingCount: Int {
        roundSlots.filter { !plan.hasResult($0) }.count
    }

    /// En eliminatoria un empate no resuelve el cruce: no se puede pasar de ronda con empates.
    private var hasKnockoutDraw: Bool {
        roundSlots.contains { slot in
            plan.isKnockoutSlot(slot) && (plan.result(for: slot)?.isDraw ?? false)
        }
    }

    private var canAdvance: Bool {
        if hasKnockoutDraw { return false }
        if isLastRound { return pendingCount == 0 }
        return true
    }

    private var restingTeams: [String] {
        guard currentRound?.stage == .league
            || (plan.format == .leaguePlacement && currentRound?.stage == .groupStage)
        else { return [] }
        let playing = Set(roundSlots.flatMap { [$0.match.homeTeam, $0.match.awayTeam] })
        return plan.teamNames.filter { !playing.contains($0) }
    }

    private static func firstPendingRoundIndex(_ plan: TournamentPlan) -> Int {
        let slots = plan.slots
        let done = ScheduleAnalytics.completedMatchIDs(tournament: plan, slots: slots)
        for (index, round) in plan.savedSchedule.enumerated() {
            // Liguilla cerrada a mano: sus partidos sin jugar ya no están pendientes.
            if plan.leagueClosedEarly == true, round.stage == .groupStage { continue }
            let pending = slots.contains { $0.roundNumber == round.number && !done.contains($0.id) }
            if pending { return index }
        }
        return max(plan.savedSchedule.count - 1, 0)
    }

    // MARK: Cuerpo

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            // Horizontal: reloj a la izquierda y pistas a la derecha. Vertical: reloj arriba.
            if size.width > size.height, size.width >= 700 {
                HStack(alignment: .top, spacing: 24) {
                    ScrollView {
                        VStack(spacing: 16) {
                            timerCard(compact: false)
                            sideNotices
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: min(320, size.width * 0.3))
                    courtsGrid(available: CGSize(width: size.width - min(320, size.width * 0.3) - 24 - 32, height: size.height - 32))
                }
                .padding(16)
            } else {
                VStack(spacing: 16) {
                    timerCard(compact: true)
                    courtsGrid(available: CGSize(width: size.width - 32, height: size.height - 32 - compactTimerHeight - 16 - noticesReserve))
                    sideNotices
                }
                .padding(16)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .navigationTitle(currentRound.map { "Ronda \($0.number) de \(rounds.count)" } ?? "En directo")
        .appInlineNavigationBarTitleDisplayMode()
        .toolbar {
            if onExit != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        leave()
                    } label: {
                        Label("Salir", systemImage: "xmark")
                    }
                    .accessibilityHint("Sale del modo directo y guarda los cambios.")
                }
            }
            #if os(iOS)
            if publisher.connection != .notPaired {
                ToolbarItemGroup(placement: .primaryAction) {
                    projectionSceneMenu
                    projectionChip
                }
            }
            #endif
        }
        .sensoryFeedback(.warning, trigger: timeIsUp)
        .task(id: timerEnd) { await watchTimer() }
        // El modo directo se usa con el torneo en marcha: un gesto sin querer no debe cerrar la hoja.
        .interactiveDismissDisabled()
        .onChange(of: store.saveFailed) { _, failed in
            if failed {
                AccessibilityNotification.Announcement("No se pudo guardar el último cambio. Hay un botón para reintentar.").post()
            }
        }
        .onDisappear { Task { await store.flush() } }
        #if os(iOS)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            publisher.publish(livePayload)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            publisher.end()
        }
        .onChange(of: liveDraft) { _, _ in publisher.publish(livePayload) }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: publisher.suspend()
            case .active: publisher.resume()
            default: break
            }
        }
        #endif
    }

    // MARK: Avisos

    /// Altura que se reserva para los avisos bajo las pistas en vertical.
    private var noticesReserve: CGFloat { hasSideNotices ? 72 : 0 }

    private var hasSideNotices: Bool {
        currentRound == nil || !restingTeams.isEmpty || showsCloseLeague || hasKnockoutDraw
    }

    private var showsCloseLeague: Bool {
        plan.format == .leaguePlacement && currentRound?.stage == .groupStage && !plan.placementLeagueIsClosed
    }

    @ViewBuilder
    private var sideNotices: some View {
        if currentRound == nil {
            LearningSituationInlineNotice(kind: .warning, message: "Este torneo no tiene rondas.")
        }
        if !restingTeams.isEmpty {
            Label("Descansan: \(restingTeams.joined(separator: ", "))", systemImage: "pause.circle")
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
        }
        if showsCloseLeague {
            SdaCloseLeagueButton(store: store)
        }
        if hasKnockoutDraw {
            LearningSituationInlineNotice(
                kind: .info,
                message: "En eliminatoria no puede haber empate. Suma un punto a quien gane para pasar de ronda."
            )
        }
    }

    // MARK: Proyección en el Mac

    /// Lo que cambia de verdad (no cada segundo): ronda, reloj, marcadores y escena. Un cambio
    /// de cualquiera de ellos se publica al momento.
    private struct LiveDraft: Equatable {
        var roundNumber: Int?
        var timerEnd: Date?
        var pausedRemaining: Int?
        var totalSeconds: Int
        var isRunning: Bool
        var timeIsUp: Bool
        var scene: TournamentLiveScene
        var scores: [String: [Int]]
    }

    private var liveDraft: LiveDraft {
        var scores: [String: [Int]] = [:]
        for slot in roundSlots.prefix(TournamentLiveState.maxScores) {
            guard let result = plan.result(for: slot) else { continue }
            scores[slot.id.uuidString] = [min(max(result.homeScore, 0), 999), min(max(result.awayScore, 0), 999)]
        }
        return LiveDraft(
            roundNumber: currentRound?.number,
            timerEnd: timerEnd,
            pausedRemaining: pausedRemaining,
            totalSeconds: totalSeconds,
            isRunning: isRunning,
            timeIsUp: timeIsUp,
            scene: projectionScene,
            scores: scores
        )
    }

    private var livePayload: TournamentLivePayload {
        let draft = liveDraft
        let status: TournamentLiveStatus = draft.timeIsUp ? .timeUp : (draft.isRunning ? .running : .paused)
        return TournamentLivePayload(
            tournamentId: store.record.id,
            status: status,
            roundNumber: draft.roundNumber,
            timer: TournamentLiveTimer(
                endAtMs: draft.timerEnd.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) },
                pausedRemainingS: draft.pausedRemaining,
                totalS: draft.totalSeconds
            ),
            scene: draft.scene,
            scores: draft.scores
        )
    }

    #if os(iOS)
    /// Chip discreto: gris, sin aspecto de error. «Mac sin proyección» no impide seguir apuntando.
    private var projectionChip: some View {
        let connection = publisher.connection
        let isProjecting = connection == .projecting
        let text: String
        switch connection {
        case .projecting: text = "Proyectando en Mac"
        case .needsRepair: text = "Vuelve a enlazar el iPad con el Mac para proyectar"
        default: text = "Mac sin proyección"
        }
        return HStack(spacing: 6) {
            Image(systemName: connection == .needsRepair ? "link.badge.plus" : (isProjecting ? "tv.fill" : "tv"))
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(isProjecting ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isProjecting ? "Proyectando en el Mac" : text)
    }

    /// Qué enseña la proyección: «Automático» rota sola; las demás fijan una escena.
    private var projectionSceneMenu: some View {
        Menu {
            Picker("En el proyector", selection: $projectionScene) {
                Text("Automático").tag(TournamentLiveScene.auto)
                Text("Pistas").tag(TournamentLiveScene.courts)
                Text("Clasificación").tag(TournamentLiveScene.standings)
                if plan.format.includesKnockoutPhase {
                    Text("Cuadro").tag(TournamentLiveScene.bracket)
                }
            }
        } label: {
            Label("En el proyector", systemImage: "tv.and.mediabox")
        }
        .disabled(publisher.connection != .projecting)
        .accessibilityHint("Elige qué se ve en la proyección del Mac.")
    }
    #endif

    // MARK: Temporizador

    private var totalSeconds: Int { max(1, plan.matchDurationMinutes * 60) }

    private func remainingSeconds(at date: Date) -> Int {
        if isRunning, let timerEnd {
            return max(0, Int(ceil(timerEnd.timeIntervalSince(date))))
        }
        return pausedRemaining ?? totalSeconds
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func spoken(_ seconds: Int) -> String {
        "\(sdaPlural(seconds / 60, "minuto", "minutos")) y \(sdaPlural(seconds % 60, "segundo", "segundos"))"
    }

    /// Alto del reloj compacto (modo vertical), para repartir el resto entre las pistas.
    private var compactTimerHeight: CGFloat { max(tapSize, 64) + 32 }

    private func timerCard(compact: Bool) -> some View {
        LearningSituationCard(title: nil) {
            if compact {
                HStack(spacing: 16) {
                    timerFace(size: 56)
                    HStack(spacing: 8) { timerButtons }
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 16) {
                    timerFace(size: timerSize)
                    VStack(spacing: 8) { timerButtons }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func timerFace(size: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = remainingSeconds(at: context.date)
            VStack(spacing: 4) {
                if timeIsUp {
                    Text("¡Tiempo!")
                        .font(.system(size: size * 0.6, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                Text(clock(seconds))
                    .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .foregroundStyle(timeIsUp ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, timeIsUp ? 8 : 0)
            // Fin de tiempo: cambio visual muy fuerte además del aviso háptico y de VoiceOver.
            .background(timeIsUp ? Color.red : Color.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Temporizador")
            .accessibilityValue(timeIsUp ? "¡Tiempo! \(spoken(seconds))" : spoken(seconds))
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    @ViewBuilder
    private var timerButtons: some View {
        Button {
            toggleTimer()
        } label: {
            Label(isRunning ? "Pausar" : "Iniciar", systemImage: isRunning ? "pause.fill" : "play.fill")
                .frame(maxWidth: .infinity, minHeight: tapSize)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        Button {
            resetTimer()
        } label: {
            Label("Reiniciar", systemImage: "arrow.counterclockwise")
                .frame(maxWidth: .infinity, minHeight: tapSize)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func toggleTimer() {
        if isRunning {
            pausedRemaining = remainingSeconds(at: Date())
            isRunning = false
            timerEnd = nil
        } else {
            let remaining = pausedRemaining ?? totalSeconds
            let seconds = remaining == 0 ? totalSeconds : remaining
            timeIsUp = false
            timerEnd = Date().addingTimeInterval(TimeInterval(seconds))
            isRunning = true
        }
    }

    private func resetTimer() {
        isRunning = false
        timerEnd = nil
        pausedRemaining = nil
        timeIsUp = false
    }

    /// Avisa al acabar el tiempo (también con VoiceOver). Se cancela solo si se pausa o reinicia.
    private func watchTimer() async {
        guard isRunning, let end = timerEnd else { return }
        let interval = end.timeIntervalSinceNow
        if interval > 0 {
            try? await Task.sleep(for: .seconds(interval))
        }
        guard !Task.isCancelled, isRunning, timerEnd == end else { return }
        isRunning = false
        timerEnd = nil
        pausedRemaining = 0
        timeIsUp = true
        AccessibilityNotification.Announcement("Se acabó el tiempo.").post()
    }

    // MARK: Partidos

    /// Separación entre tarjetas y relleno interior (rejilla de 8 pt).
    private let gridSpacing: CGFloat = 16
    private let cardPadding: CGFloat = 16
    private let cardHeaderHeight: CGFloat = 32

    /// Todas las pistas a la vista: 2 columnas (1 si no caben) y filas que se reparten la altura.
    /// Si ni con el mínimo táctil caben, la cuadrícula se desplaza en lugar de cortar botones.
    private func courtsGrid(available: CGSize) -> some View {
        let count = max(roundSlots.count, 1)
        let columns = available.width >= 560 && count > 1 ? 2 : 1
        let rows = Int(ceil(Double(count) / Double(columns)))
        let perCard = (available.height - CGFloat(rows - 1) * gridSpacing) / CGFloat(rows)
        // Cada tarjeta: cabecera + dos filas de equipo + separaciones.
        let rowHeight = min(96, max(tapSize + 4, (perCard - cardHeaderHeight - cardPadding * 2 - 16) / 2))
        return ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: gridSpacing, alignment: .top), count: columns),
                spacing: gridSpacing
            ) {
                ForEach(roundSlots) { slot in
                    courtCard(slot, rowHeight: rowHeight)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func courtCard(_ slot: ScheduledMatchSlot, rowHeight: CGFloat) -> some View {
        let names = plan.displayTeams(for: slot)
        let score = plan.result(for: slot)
        let canScore = plan.canScore(slot)
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Pista \(slot.venueNumber)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if !canScore {
                    Text(unavailableText(for: slot))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                } else if score == nil {
                    Button("0 – 0") {
                        store.mutate { $0.setScore(for: slot, home: 0, away: 0) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Registrar 0 a 0")
                }
            }
            .frame(minHeight: cardHeaderHeight)
            side(slot, name: names.home, score: score?.homeScore, isHome: true, enabled: canScore, height: rowHeight)
            side(slot, name: names.away, score: score?.awayScore, isHome: false, enabled: canScore, height: rowHeight)
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity)
        .background(IOSAppStyle.cardBackground, in: RoundedRectangle(cornerRadius: IOSAppStyle.cardRadius, style: .continuous))
    }

    private func unavailableText(for slot: ScheduledMatchSlot) -> String {
        if plan.format == .leaguePlacement {
            if slot.stage != .knockout { return "La liguilla ya está cerrada." }
            if !plan.placementLeagueIsClosed { return "Se abre al terminar la liguilla." }
        }
        if plan.format == .groupStageKnockout, slot.stage == .knockout {
            return "Se abre al terminar la fase de grupos."
        }
        return "Aún no se conocen las dos parejas."
    }

    private func side(_ slot: ScheduledMatchSlot, name: String, score: Int?, isHome: Bool, enabled: Bool, height: CGFloat) -> some View {
        let button = max(tapSize, min(height, 72))
        return HStack(spacing: 8) {
            Text(name)
                .font(.system(size: min(28, max(17, height * 0.32)), weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                adjust(slot, name: name, isHome: isHome, by: -1)
            } label: {
                Image(systemName: "minus")
                    .font(.title2.weight(.bold))
                    .frame(width: button, height: button)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .disabled(!enabled || (score ?? 0) == 0)
            Text(score.map(String.init) ?? "–")
                .font(.system(size: min(scoreSize, height * 0.8), weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(score == nil ? Color.secondary : Color.primary)
                .frame(minWidth: height * 1.2)
            Button {
                adjust(slot, name: name, isHome: isHome, by: 1)
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.bold))
                    .frame(width: button, height: button)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .disabled(!enabled)
        }
        .frame(minHeight: height)
        // Para VoiceOver el equipo es un único control ajustable (deslizar arriba/abajo suma o resta).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(score.map { sdaPlural($0, "punto", "puntos") } ?? "Sin empezar")
        .accessibilityHint(enabled ? "Desliza hacia arriba para sumar un punto y hacia abajo para restarlo." : "")
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            switch direction {
            case .increment: adjust(slot, name: name, isHome: isHome, by: 1)
            case .decrement: adjust(slot, name: name, isHome: isHome, by: -1)
            @unknown default: break
            }
        }
        .sensoryFeedback(.impact, trigger: score) { old, new in (new ?? 0) > (old ?? 0) }
    }

    private func adjust(_ slot: ScheduledMatchSlot, name: String, isHome: Bool, by delta: Int) {
        let current = plan.result(for: slot)
        var home = current?.homeScore ?? 0
        var away = current?.awayScore ?? 0
        if isHome { home = max(0, home + delta) } else { away = max(0, away + delta) }
        store.mutate { $0.setScore(for: slot, home: home, away: away) }
        // Los cambios con +/- no mueven el foco de VoiceOver: se anuncia el valor nuevo.
        AccessibilityNotification.Announcement("\(name): \(sdaPlural(isHome ? home : away, "punto", "puntos"))").post()
    }

    // MARK: Barra inferior

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if store.saveFailed {
                LearningSituationInlineNotice(
                    kind: .error,
                    message: "No se pudo guardar el último cambio.",
                    actionTitle: "Reintentar"
                ) {
                    store.retrySave()
                }
            }
            if pendingCount > 0 {
                Text(sdaPlural(pendingCount, "partido sin resultado", "partidos sin resultado"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { navigationButtons }
                VStack(spacing: 8) { navigationButtons }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder
    private var navigationButtons: some View {
        Button {
            move(by: -1)
        } label: {
            Label("Ronda anterior", systemImage: "chevron.left")
                .frame(maxWidth: .infinity, minHeight: tapSize)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(roundIndex <= 0)
        Button {
            advance()
        } label: {
            Label(
                isLastRound ? "Terminar torneo" : "Siguiente ronda",
                systemImage: isLastRound ? "flag.checkered" : "chevron.right"
            )
            .frame(maxWidth: .infinity, minHeight: tapSize)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canAdvance || currentRound == nil)
    }

    private func move(by delta: Int) {
        let target = roundIndex + delta
        guard rounds.indices.contains(target) else { return }
        resetTimer()
        roundIndex = target
    }

    private func leave() {
        #if os(iOS)
        publisher.end()
        #endif
        if let onExit {
            onExit()
        } else {
            dismiss()
        }
    }

    private func advance() {
        if isLastRound {
            store.mutate { $0.status = .finished }
            leave()
        } else {
            move(by: 1)
        }
    }
}
