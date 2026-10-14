import SwiftUI

/// Modo directo: ronda actual, temporizador, marcadores grandes con − / + y paso de ronda.
/// Cada toque se guarda al momento a través del `SdaTournamentStore`.
struct SdaTournamentLiveView: View {
    @ObservedObject var store: SdaTournamentStore
    @Environment(\.dismiss) private var dismiss

    @State private var roundIndex: Int
    @State private var timerEnd: Date?
    @State private var pausedRemaining: Int?
    @State private var isRunning = false
    @State private var timeIsUp = false
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 56
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 56
    @ScaledMetric(relativeTo: .body) private var tapSize: CGFloat = 44

    init(store: SdaTournamentStore) {
        self.store = store
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
        guard currentRound?.stage == .league else { return [] }
        let playing = Set(roundSlots.flatMap { [$0.match.homeTeam, $0.match.awayTeam] })
        return plan.teamNames.filter { !playing.contains($0) }
    }

    private static func firstPendingRoundIndex(_ plan: TournamentPlan) -> Int {
        let slots = plan.slots
        let done = ScheduleAnalytics.completedMatchIDs(tournament: plan, slots: slots)
        for (index, round) in plan.savedSchedule.enumerated() {
            let pending = slots.contains { $0.roundNumber == round.number && !done.contains($0.id) }
            if pending { return index }
        }
        return max(plan.savedSchedule.count - 1, 0)
    }

    // MARK: Cuerpo

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if store.saveFailed {
                    LearningSituationInlineNotice(
                        kind: .error,
                        message: "No se pudo guardar el último cambio.",
                        actionTitle: "Reintentar"
                    ) {
                        store.retrySave()
                    }
                }
                timerCard
                if currentRound == nil {
                    LearningSituationInlineNotice(kind: .warning, message: "Este torneo no tiene rondas.")
                }
                ForEach(roundSlots) { slot in
                    matchCard(slot)
                }
                if !restingTeams.isEmpty {
                    Label("Descansan: \(restingTeams.joined(separator: ", "))", systemImage: "pause.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                }
                if hasKnockoutDraw {
                    LearningSituationInlineNotice(
                        kind: .info,
                        message: "En eliminatoria no puede haber empate. Suma un punto a quien gane para pasar de ronda."
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .navigationTitle(currentRound.map { "Ronda \($0.number) de \(rounds.count)" } ?? "En directo")
        .appInlineNavigationBarTitleDisplayMode()
        .sensoryFeedback(.warning, trigger: timeIsUp)
        .task(id: timerEnd) { await watchTimer() }
        #if os(iOS)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        #endif
    }

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

    private var timerCard: some View {
        LearningSituationCard(title: nil) {
            VStack(spacing: 16) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = remainingSeconds(at: context.date)
                    Text(clock(seconds))
                        .font(.system(size: timerSize, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(seconds == 0 ? Color.red : Color.primary)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Temporizador")
                        .accessibilityValue(spoken(seconds))
                        .accessibilityAddTraits(.updatesFrequently)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { timerButtons }
                    VStack(spacing: 8) { timerButtons }
                }
            }
            .frame(maxWidth: .infinity)
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

    private func matchCard(_ slot: ScheduledMatchSlot) -> some View {
        let names = plan.displayTeams(for: slot)
        let score = plan.result(for: slot)
        let canScore = plan.canScore(slot)
        return LearningSituationCard(title: nil) {
            VStack(spacing: 16) {
                Text("Pista \(slot.venueNumber)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        side(slot, name: names.home, score: score?.homeScore, isHome: true, enabled: canScore)
                        side(slot, name: names.away, score: score?.awayScore, isHome: false, enabled: canScore)
                    }
                    VStack(spacing: 16) {
                        side(slot, name: names.home, score: score?.homeScore, isHome: true, enabled: canScore)
                        side(slot, name: names.away, score: score?.awayScore, isHome: false, enabled: canScore)
                    }
                }
                if !canScore {
                    Text(plan.format == .groupStageKnockout && slot.stage == .knockout
                        ? "Se abre al terminar la fase de grupos."
                        : "Aún no se conocen los dos equipos.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if score == nil {
                    Button("Registrar 0 – 0") {
                        store.mutate { $0.setScore(for: slot, home: 0, away: 0) }
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: tapSize)
                }
            }
        }
    }

    private func side(_ slot: ScheduledMatchSlot, name: String, score: Int?, isHome: Bool, enabled: Bool) -> some View {
        VStack(spacing: 8) {
            VStack(spacing: 4) {
                Text(name)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Text(score.map(String.init) ?? "–")
                    .font(.system(size: scoreSize, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(score == nil ? Color.secondary : Color.primary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityValue(score.map { sdaPlural($0, "punto", "puntos") } ?? "Sin empezar")
            HStack(spacing: 12) {
                Button {
                    adjust(slot, isHome: isHome, by: -1)
                } label: {
                    Image(systemName: "minus")
                        .font(.title2.weight(.bold))
                        .frame(minWidth: tapSize + 12, minHeight: tapSize + 12)
                }
                .buttonStyle(.bordered)
                .disabled(!enabled || (score ?? 0) == 0)
                .accessibilityLabel("Restar un punto a \(name)")
                Button {
                    adjust(slot, isHome: isHome, by: 1)
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.bold))
                        .frame(minWidth: tapSize + 12, minHeight: tapSize + 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!enabled)
                .accessibilityLabel("Sumar un punto a \(name)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func adjust(_ slot: ScheduledMatchSlot, isHome: Bool, by delta: Int) {
        let current = plan.result(for: slot)
        var home = current?.homeScore ?? 0
        var away = current?.awayScore ?? 0
        if isHome { home = max(0, home + delta) } else { away = max(0, away + delta) }
        store.mutate { $0.setScore(for: slot, home: home, away: away) }
    }

    // MARK: Barra inferior

    private var bottomBar: some View {
        VStack(spacing: 8) {
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

    private func advance() {
        if isLastRound {
            store.mutate { $0.status = .finished }
            dismiss()
        } else {
            move(by: 1)
        }
    }
}
