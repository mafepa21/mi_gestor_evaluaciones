import SwiftUI

// Escenas de la proyección de un torneo, pensadas para verse a 6-8 m en un proyector.
// Tipografía muy grande y redondeada, contraste alto y fondo claro SIEMPRE (no sigue el tema
// del sistema). Todos los tamaños salen del ancho de la ventana (1 unidad = 1 % del ancho,
// limitada por el alto para que nada se corte). El contenido lo decide `TournamentProjectionModel`;
// aquí solo se dibuja. Nunca se pintan nombres: el modelo solo entrega «Equipo N».

// MARK: - Colores

private enum ProjectionPalette {
    static let background = Color.white
    static let card = Color(red: 0.949, green: 0.949, blue: 0.969)
    static let text = Color.black
    static let muted = Color(red: 0.227, green: 0.227, blue: 0.235)
    static let accent = Color(red: 0, green: 0.388, blue: 0.8)
    static let gold = Color(red: 0.635, green: 0.42, blue: 0)
    static let live = Color(red: 0.788, green: 0.204, blue: 0)
    static let win = Color(red: 0.122, green: 0.478, blue: 0.22)
    static let lose = Color(red: 0.698, green: 0.314, blue: 0)
    static let line = Color(red: 0.78, green: 0.78, blue: 0.8)
}

/// Tamaños relativos al ancho de la ventana.
private struct ProjectionMetrics {
    let unit: CGFloat
    let size: CGSize

    init(size: CGSize) {
        self.size = size
        // 16:9 de referencia: si la ventana es más baja que eso, manda el alto.
        unit = max(min(size.width / 100, size.height / 56.25), 1)
    }

    func font(_ points: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: unit * points, weight: weight, design: .rounded)
    }

    func length(_ points: CGFloat) -> CGFloat { unit * points }
}

private extension Array {
    func projectionChunks(_ size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

// MARK: - Contenedor con rotación

/// La proyección entera: escena actual, pie con las fases y rotación automática cada 15 s.
struct SdaProjectionView: View {
    let plan: TournamentPlan
    /// Si el Mac tiene su propio ajuste de «Reducir movimiento».
    var forceReduceMotion = false
    /// Estado en directo del iPad (reloj, marcadores provisionales, ronda y escena). Sin él, el
    /// aspecto es el de siempre: lo guardado en el plan.
    var live: TournamentLiveProjection?

    @State private var rotation = 0
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || forceReduceMotion }

    var body: some View {
        let shownPlan = live?.plan(overlaying: plan) ?? plan
        let model = TournamentProjectionModel.make(plan: shownPlan, hints: live?.hints)
        GeometryReader { geometry in
            let metrics = ProjectionMetrics(size: geometry.size)
            ZStack {
                ProjectionPalette.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    let scene = model.scene(at: rotation)
                    ZStack {
                        sceneView(scene, metrics: metrics)
                            .id(scene.id)
                            .transition(.opacity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Mientras se juega, el reloj no desaparece al rotar: en las escenas que no son
                    // de pistas va más pequeño en la esquina.
                    .overlay(alignment: .topTrailing) {
                        if let live, live.showsClock, !scene.isRound {
                            ProjectionClockView(live: live, metrics: metrics, scale: 0.6)
                                .padding(.horizontal, metrics.length(1.2))
                                .padding(.vertical, metrics.length(0.4))
                                .background(ProjectionPalette.background.opacity(0.94), in: RoundedRectangle(cornerRadius: metrics.length(1), style: .continuous))
                        }
                    }
                    if let live, live.showsOfflineNotice {
                        ProjectionOfflineNotice(receivedAtMs: live.state.arrivalMs, metrics: metrics)
                    }
                    ProjectionFooterView(model: model, metrics: metrics)
                }
                .padding(.horizontal, metrics.length(3))
                .padding(.top, metrics.length(2.2))
                .padding(.bottom, metrics.length(1.2))
            }
        }
        .environment(\.colorScheme, .light)
        .task(id: model.scenes.count) {
            guard model.scenes.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(TournamentProjectionModel.rotationSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                advance()
            }
        }
    }

    private func advance() {
        if reduceMotion {
            rotation += 1
        } else {
            withAnimation(.easeInOut(duration: 0.6)) { rotation += 1 }
        }
    }

    @ViewBuilder
    private func sceneView(_ scene: TournamentProjectionScene, metrics: ProjectionMetrics) -> some View {
        switch scene {
        case .empty(let value): ProjectionMessageScene(value: value, metrics: metrics)
        case .notStarted(let value): ProjectionUpNextScene(value: value, metrics: metrics)
        case .upNext(let value): ProjectionUpNextScene(value: value, metrics: metrics)
        case .round(let value):
            ProjectionRoundScene(value: value, metrics: metrics, live: live?.showsClock == true ? live : nil)
        case .standings(let value): ProjectionStandingsScene(value: value, metrics: metrics)
        case .bracket(let value): ProjectionBracketScene(value: value, metrics: metrics)
        case .phaseEnd(let value): ProjectionPhaseEndScene(value: value, metrics: metrics)
        case .podium(let value): ProjectionPodiumScene(value: value, metrics: metrics)
        }
    }
}

private extension TournamentProjectionScene {
    var isRound: Bool {
        if case .round = self { return true }
        return false
    }
}

// MARK: - Piezas comunes

private struct ProjectionHeaderView: View {
    let header: ProjectionHeader
    let metrics: ProjectionMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.length(0.3)) {
            Text(header.kicker.uppercased())
                .font(metrics.font(1.9))
                .tracking(metrics.length(0.12))
                .foregroundStyle(ProjectionPalette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(header.title)
                .font(metrics.font(4.2, .heavy))
                .foregroundStyle(ProjectionPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct ProjectionFooterView: View {
    let model: TournamentProjectionModel
    let metrics: ProjectionMetrics

    var body: some View {
        HStack(spacing: metrics.length(2)) {
            HStack(spacing: metrics.length(0.8)) {
                ForEach(model.footer) { phase in
                    chip(phase)
                }
            }
            Spacer(minLength: 0)
            Text(model.tournamentName)
                .font(metrics.font(1.7, .semibold))
                .foregroundStyle(ProjectionPalette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(minHeight: metrics.length(3.4))
        .padding(.top, metrics.length(0.8))
    }

    private func chip(_ phase: ProjectionFooterPhase) -> some View {
        let isCurrent = phase.state == .current
        return Text((phase.state == .done ? "✓ " : "") + phase.title)
            .font(metrics.font(1.7, .semibold))
            .lineLimit(1)
            .foregroundStyle(isCurrent ? Color.white : ProjectionPalette.muted)
            .opacity(phase.state == .done ? 0.7 : 1)
            .padding(.horizontal, metrics.length(1.2))
            .padding(.vertical, metrics.length(0.45))
            .background(isCurrent ? ProjectionPalette.accent : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(isCurrent ? ProjectionPalette.accent : ProjectionPalette.muted, lineWidth: metrics.length(0.15)))
    }
}

// MARK: - Mensaje

private struct ProjectionMessageScene: View {
    let value: ProjectionMessage
    let metrics: ProjectionMetrics

    var body: some View {
        VStack(spacing: metrics.length(1.4)) {
            Text(value.header.title)
                .font(metrics.font(6, .heavy))
                .foregroundStyle(ProjectionPalette.text)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
            Text(value.message)
                .font(metrics.font(2.8, .medium))
                .foregroundStyle(ProjectionPalette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Ronda en juego

private struct ProjectionRoundScene: View {
    let value: ProjectionRound
    let metrics: ProjectionMetrics
    /// Con reloj en directo, se pinta a la derecha del título.
    var live: TournamentLiveProjection?

    private var columns: Int {
        switch value.matches.count {
        case ...3: return max(value.matches.count, 1)
        case 4: return 2
        case 5, 6: return 3
        default: return 4
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.length(1)) {
            HStack(alignment: .top, spacing: metrics.length(2)) {
                ProjectionHeaderView(header: value.header, metrics: metrics)
                if let live {
                    ProjectionClockView(live: live, metrics: metrics)
                }
            }
            Spacer(minLength: 0)
            let rows = value.matches.projectionChunks(columns)
            // Con muchas filas las tarjetas se encogen para caber.
            let scale = rows.count <= 2 ? 1 : max(0.55, 2.0 / CGFloat(rows.count) + 0.1)
            VStack(spacing: metrics.length(1.2)) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: metrics.length(1.2)) {
                        ForEach(row) { match in
                            ProjectionMatchCard(match: match, metrics: metrics, columns: columns, scale: scale)
                        }
                        if row.count < columns {
                            ForEach(0..<(columns - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                        }
                    }
                }
            }
            if let resting = value.restingText {
                Text(resting)
                    .font(metrics.font(2.2, .semibold))
                    .foregroundStyle(ProjectionPalette.muted)
                    .padding(.top, metrics.length(0.6))
            }
            Spacer(minLength: 0)
        }
    }
}

/// Reloj de la ronda: cuenta con el desfase entre el reloj del iPad y el del Mac, se refresca dos
/// veces por segundo y al llegar a cero dice «¡Tiempo!». Con el iPad sin conexión sigue contando.
private struct ProjectionClockView: View {
    let live: TournamentLiveProjection
    let metrics: ProjectionMetrics
    /// 1 en la escena de pistas; más pequeño en la esquina del resto de escenas.
    var scale: CGFloat = 1

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let nowMs = Int64(context.date.timeIntervalSince1970 * 1000)
            let seconds = live.clock.remainingSeconds(of: live.state, nowMs: nowMs) ?? 0
            let timeUp = seconds == 0
            let isPaused = live.state.status == .paused && !timeUp
            VStack(alignment: .trailing, spacing: metrics.length(0.2)) {
                if timeUp {
                    Text(ProjectionLiveTexts.timeUp)
                        .font(metrics.font(5.2 * scale, .heavy))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, metrics.length(1.4))
                        .padding(.vertical, metrics.length(0.3))
                        .background(ProjectionPalette.live, in: RoundedRectangle(cornerRadius: metrics.length(1), style: .continuous))
                } else {
                    Text(ProjectionLiveTexts.clock(seconds: seconds))
                        .font(metrics.font(6.4 * scale, .heavy).monospacedDigit())
                        .foregroundStyle(isPaused ? ProjectionPalette.muted : (seconds <= 10 ? ProjectionPalette.live : ProjectionPalette.text))
                    if isPaused {
                        Text(ProjectionLiveTexts.paused)
                            .font(metrics.font(max(1.8, 1.8 * scale), .semibold))
                            .foregroundStyle(ProjectionPalette.muted)
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Aviso discreto cuando el iPad dejó de enviar: la proyección sigue con la última foto.
private struct ProjectionOfflineNotice: View {
    let receivedAtMs: Int64
    let metrics: ProjectionMetrics

    var body: some View {
        Text(ProjectionLiveTexts.offlineNotice(atMs: receivedAtMs))
            .font(metrics.font(1.8, .semibold))
            .foregroundStyle(ProjectionPalette.muted)
            .padding(.horizontal, metrics.length(1.4))
            .padding(.vertical, metrics.length(0.4))
            .background(ProjectionPalette.card, in: Capsule())
            .overlay(Capsule().stroke(ProjectionPalette.line, lineWidth: metrics.length(0.12)))
            .padding(.bottom, metrics.length(0.4))
            .accessibilityLabel(ProjectionLiveTexts.offlineNotice(atMs: receivedAtMs))
    }
}

private struct ProjectionMatchCard: View {
    let match: ProjectionMatch
    let metrics: ProjectionMetrics
    let columns: Int
    let scale: CGFloat

    private var nameSize: CGFloat {
        (columns <= 2 ? 4.2 : columns == 3 ? 3.3 : 2.7) * scale
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.length(0.3)) {
            HStack {
                Text(match.venueTitle.uppercased())
                    .foregroundStyle(ProjectionPalette.accent)
                Spacer(minLength: metrics.length(0.5))
                if let caption = match.caption {
                    Text(caption).foregroundStyle(ProjectionPalette.muted)
                }
            }
            .font(metrics.font(1.8 * max(scale, 0.8)))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            row(match.home, score: match.homeScore, isWinner: match.winner == .home, isLoser: match.winner == .away)
            row(match.away, score: match.awayScore, isWinner: match.winner == .away, isLoser: match.winner == .home)
            if let destination = match.destination {
                Text(destination)
                    .font(metrics.font(1.5 * max(scale, 0.85), .medium))
                    .foregroundStyle(ProjectionPalette.muted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(metrics.length(1.2))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProjectionPalette.card, in: RoundedRectangle(cornerRadius: metrics.length(1.4), style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func row(_ team: String, score: Int?, isWinner: Bool, isLoser: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: metrics.length(0.8)) {
            Text(team)
                .font(metrics.font(nameSize, isWinner ? .heavy : .bold))
                .foregroundStyle(isLoser ? ProjectionPalette.muted : ProjectionPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer(minLength: 0)
            Text(score.map(String.init) ?? "–")
                .font(metrics.font(nameSize * 1.5, .heavy))
                .monospacedDigit()
                .foregroundStyle(score == nil ? ProjectionPalette.muted : (isLoser ? ProjectionPalette.muted : ProjectionPalette.text))
        }
    }

    private var accessibilityText: String {
        var parts = [match.venueTitle, match.home]
        if let score = match.homeScore { parts.append("\(score)") }
        parts.append("contra")
        parts.append(match.away)
        if let score = match.awayScore { parts.append("\(score)") }
        return parts.joined(separator: " ")
    }
}

// MARK: - Prepárate y fin de fase

private struct ProjectionMatchList: View {
    let matches: [ProjectionMatch]
    let metrics: ProjectionMetrics

    var body: some View {
        let columns = matches.count > 12 ? 3 : 2
        let perColumn = Int((Double(matches.count) / Double(columns)).rounded(.up))
        let size: CGFloat = perColumn <= 3 ? 3.6 : perColumn <= 5 ? 3.0 : perColumn <= 7 ? 2.4 : 1.9
        HStack(alignment: .top, spacing: metrics.length(4)) {
            ForEach(Array(matches.projectionChunks(max(perColumn, 1)).enumerated()), id: \.offset) { _, column in
                VStack(alignment: .leading, spacing: metrics.length(size * 0.2)) {
                    ForEach(column) { match in
                        VStack(alignment: .leading, spacing: 0) {
                            Text([match.venueTitle, match.caption].compactMap { $0 }.joined(separator: " · ").uppercased())
                                .font(metrics.font(size * 0.55))
                                .foregroundStyle(ProjectionPalette.accent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            (Text(match.home).font(metrics.font(size))
                                + Text("  contra  ").font(metrics.font(size * 0.7, .regular)).foregroundColor(ProjectionPalette.muted)
                                + Text(match.away).font(metrics.font(size)))
                                .foregroundStyle(ProjectionPalette.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, metrics.length(size * 0.15))
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(ProjectionPalette.card).frame(height: metrics.length(0.15))
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(match.venueTitle), \(match.home) contra \(match.away)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

private struct ProjectionUpNextScene: View {
    let value: ProjectionUpNext
    let metrics: ProjectionMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.length(1.2)) {
            ProjectionHeaderView(header: value.header, metrics: metrics)
            Spacer(minLength: 0)
            if let note = value.note {
                Text(note)
                    .font(metrics.font(2.3, .medium))
                    .foregroundStyle(ProjectionPalette.muted)
            }
            ProjectionMatchList(matches: value.matches, metrics: metrics)
            if let resting = value.restingText {
                Text(resting)
                    .font(metrics.font(2.2, .semibold))
                    .foregroundStyle(ProjectionPalette.muted)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ProjectionPhaseEndScene: View {
    let value: ProjectionPhaseEnd
    let metrics: ProjectionMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.length(1.2)) {
            ProjectionHeaderView(header: value.header, metrics: metrics)
            Spacer(minLength: 0)
            if let note = value.note {
                Text(note)
                    .font(metrics.font(2.4, .medium))
                    .foregroundStyle(ProjectionPalette.muted)
            }
            ProjectionMatchList(matches: value.matches, metrics: metrics)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Clasificación

private struct ProjectionStandingsScene: View {
    let value: ProjectionStandings
    let metrics: ProjectionMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.length(1)) {
            ProjectionHeaderView(header: value.header, metrics: metrics)
            Spacer(minLength: 0)
            if value.tables.count == 1, let table = value.tables.first {
                singleTable(table)
            } else {
                groupTables
            }
            Spacer(minLength: 0)
        }
    }

    private func singleTable(_ table: ProjectionStandingsTable) -> some View {
        let columns = table.rows.count <= 8 ? 1 : table.rows.count <= 20 ? 2 : 3
        let perColumn = Int((Double(table.rows.count) / Double(columns)).rounded(.up))
        // Que quepa en el alto que queda (cabecera y pie incluidos).
        let size = min(columns == 1 ? 3.4 : 2.7, 36 / (CGFloat(max(perColumn, 1)) * 1.45 + 1.2))
        return HStack(alignment: .top, spacing: metrics.length(4)) {
            ForEach(Array(table.rows.projectionChunks(max(perColumn, 1)).enumerated()), id: \.offset) { _, rows in
                tableColumn(rows: rows, size: size)
            }
        }
    }

    private var groupTables: some View {
        let columns = value.tables.count <= 2 ? value.tables.count : value.tables.count <= 4 ? 2 : 3
        let tallest = value.tables.map { $0.rows.count }.max() ?? 1
        let rowsOfGroups = value.tables.projectionChunks(max(columns, 1))
        let lines = CGFloat(rowsOfGroups.count) * (CGFloat(tallest) * 1.4 + 2.2)
        let size = min(2.6, 38 / max(lines, 1))
        return VStack(spacing: metrics.length(1.2)) {
            ForEach(Array(rowsOfGroups.enumerated()), id: \.offset) { _, tables in
                HStack(alignment: .top, spacing: metrics.length(1.5)) {
                    ForEach(tables) { table in
                        VStack(alignment: .leading, spacing: metrics.length(0.3)) {
                            Text(table.title ?? "")
                                .font(metrics.font(size * 0.95, .heavy))
                                .foregroundStyle(ProjectionPalette.accent)
                            tableColumn(rows: table.rows, size: size)
                        }
                        .padding(metrics.length(1))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .background(ProjectionPalette.card, in: RoundedRectangle(cornerRadius: metrics.length(1.2), style: .continuous))
                    }
                    if tables.count < columns {
                        ForEach(0..<(columns - tables.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                    }
                }
            }
        }
    }

    private func tableColumn(rows: [ProjectionStandingRow], size: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: metrics.length(size * 0.4)) {
                Text("#").frame(width: metrics.length(size * 1.5), alignment: .leading)
                Text("Equipo").frame(maxWidth: .infinity, alignment: .leading)
                Text(value.recordHeader).frame(width: metrics.length(size * 3), alignment: .trailing)
                Text(value.extraHeader).frame(width: metrics.length(size * 2.6), alignment: .trailing)
            }
            .font(metrics.font(size * 0.55, .semibold))
            .foregroundStyle(ProjectionPalette.muted)
            ForEach(rows) { row in
                HStack(spacing: metrics.length(size * 0.4)) {
                    Text("\(row.position)")
                        .foregroundStyle(ProjectionPalette.accent)
                        .frame(width: metrics.length(size * 1.5), alignment: .leading)
                    Text(row.team)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.record)
                        .font(metrics.font(size * 0.85, .semibold))
                        .frame(width: metrics.length(size * 3), alignment: .trailing)
                    Text(row.extra)
                        .font(metrics.font(size * 0.85, .semibold))
                        .frame(width: metrics.length(size * 2.6), alignment: .trailing)
                }
                .font(metrics.font(size, .bold))
                .monospacedDigit()
                .foregroundStyle(ProjectionPalette.text)
                .padding(.vertical, metrics.length(size * 0.12))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(ProjectionPalette.card).frame(height: metrics.length(0.12))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Puesto \(row.position), \(row.team), \(row.record), \(row.extra)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Podio

private struct ProjectionPodiumScene: View {
    let value: ProjectionPodium
    let metrics: ProjectionMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.length(1.2)) {
            ProjectionHeaderView(header: value.header, metrics: metrics)
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: metrics.length(2)) {
                ForEach(ordered) { place in
                    card(place)
                }
            }
            if !value.others.isEmpty {
                let size: CGFloat = value.others.count <= 8 ? 2.4 : 1.9
                let perColumn = Int((Double(value.others.count) / 4).rounded(.up))
                HStack(alignment: .top, spacing: metrics.length(3)) {
                    ForEach(Array(value.others.projectionChunks(max(perColumn, 1)).enumerated()), id: \.offset) { _, column in
                        VStack(alignment: .leading, spacing: metrics.length(0.2)) {
                            ForEach(column) { place in
                                HStack(spacing: metrics.length(0.8)) {
                                    Text("\(place.position)º").foregroundStyle(ProjectionPalette.muted)
                                        .frame(width: metrics.length(size * 1.6), alignment: .leading)
                                    Text(place.team).foregroundStyle(ProjectionPalette.text)
                                }
                                .font(metrics.font(size, .semibold))
                                .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, metrics.length(1.2))
            }
            Spacer(minLength: 0)
        }
    }

    /// 2º, 1º y 3º: el campeón en el centro.
    private var ordered: [ProjectionPlace] {
        let places = value.places
        guard places.count >= 3 else { return places.reversed() }
        return [places[1], places[0], places[2]]
    }

    private func card(_ place: ProjectionPlace) -> some View {
        let isFirst = place.position == 1
        return VStack(spacing: metrics.length(0.5)) {
            Text(isFirst ? "★ Campeones" : "\(place.position)º")
                .font(metrics.font(2.4))
                .foregroundStyle(isFirst ? ProjectionPalette.gold : ProjectionPalette.muted)
            Text(place.team)
                .font(metrics.font(isFirst ? 6 : 4, .heavy))
                .foregroundStyle(ProjectionPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(.vertical, metrics.length(isFirst ? 3.4 : 1.8))
        .padding(.horizontal, metrics.length(1))
        .frame(maxWidth: .infinity)
        .background(ProjectionPalette.card, in: RoundedRectangle(cornerRadius: metrics.length(1.6), style: .continuous))
        .overlay {
            if isFirst {
                RoundedRectangle(cornerRadius: metrics.length(1.6), style: .continuous)
                    .stroke(ProjectionPalette.gold, lineWidth: metrics.length(0.3))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Puesto \(place.position): \(place.team)")
    }
}

// MARK: - Cuadro

private struct ProjectionBracketScene: View {
    let value: ProjectionBracket
    let metrics: ProjectionMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.length(0.8)) {
            ProjectionHeaderView(header: value.header, metrics: metrics)
            ProjectionBracketCanvas(bracket: value, metrics: metrics)
        }
    }
}

/// Las tarjetas y las líneas del árbol, escaladas al hueco que haya.
private struct ProjectionBracketCanvas: View {
    let bracket: ProjectionBracket
    let metrics: ProjectionMetrics

    private struct Frame {
        var cardWidth: CGFloat
        var cardHeight: CGFloat
        var pitch: CGFloat
        var gap: CGFloat
        var headerHeight: CGFloat
        var leafWidth: CGFloat
        var leafHeight: CGFloat
    }

    private func frame(in size: CGSize) -> Frame {
        let columns = CGFloat(max(bracket.columns.count, 1))
        let gap = metrics.length(3)
        let leafWidth = metrics.length(14)
        let headerHeight = metrics.length(3)
        let cardWidth = max((size.width - leafWidth - gap * columns) / columns, 1)
        let pitch = max((size.height - headerHeight) / CGFloat(max(bracket.rows, 1)), 1)
        let cardHeight = min(pitch * 0.88, metrics.length(9))
        return Frame(
            cardWidth: cardWidth, cardHeight: cardHeight, pitch: pitch, gap: gap,
            headerHeight: headerHeight, leafWidth: leafWidth, leafHeight: min(pitch * 0.46, metrics.length(5))
        )
    }

    private func origin(of node: ProjectionBracketNode, _ f: Frame) -> CGPoint {
        CGPoint(
            x: CGFloat(node.column) * (f.cardWidth + f.gap),
            y: f.headerHeight + CGFloat(node.row) * f.pitch + (f.pitch - f.cardHeight) / 2
        )
    }

    private func leafOrigin(_ leaf: ProjectionBracketLeaf, _ f: Frame) -> CGPoint {
        CGPoint(
            x: CGFloat(bracket.columns.count) * (f.cardWidth + f.gap),
            y: f.headerHeight + CGFloat(leaf.row) * f.pitch
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let f = frame(in: geometry.size)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    drawEdges(&context, f)
                }
                .accessibilityHidden(true)
                ForEach(bracket.columns) { column in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(column.title)
                            .font(metrics.font(1.9))
                            .foregroundStyle(column.isCurrent ? ProjectionPalette.accent : ProjectionPalette.text)
                        if let subtitle = column.subtitle {
                            Text(subtitle)
                                .font(metrics.font(1.2, .medium))
                                .foregroundStyle(ProjectionPalette.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                    }
                    .frame(width: f.cardWidth, alignment: .leading)
                    .offset(x: CGFloat(column.id) * (f.cardWidth + f.gap), y: 0)
                }
                ForEach(bracket.nodes) { node in
                    nodeCard(node, f)
                        .frame(width: f.cardWidth, height: f.cardHeight)
                        .offset(x: origin(of: node, f).x, y: origin(of: node, f).y)
                }
                ForEach(bracket.leaves) { leaf in
                    leafView(leaf, f)
                        .frame(width: f.leafWidth, height: f.leafHeight, alignment: .leading)
                        .offset(x: leafOrigin(leaf, f).x, y: leafOrigin(leaf, f).y)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }

    private func nodeCard(_ node: ProjectionBracketNode, _ f: Frame) -> some View {
        let rowHeight = f.cardHeight / 2
        let fontSize = max(rowHeight * 0.56, 6)
        let isLive = node.status == .inPlay
        let isPending = node.status == .pending
        return VStack(spacing: 0) {
            sideRow(node.home, rowHeight: rowHeight, fontSize: fontSize, number: node.number)
            sideRow(node.away, rowHeight: rowHeight, fontSize: fontSize, number: nil)
        }
        .background(isPending ? Color.clear : ProjectionPalette.card, in: RoundedRectangle(cornerRadius: rowHeight * 0.5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: rowHeight * 0.5, style: .continuous)
                .stroke(
                    isLive ? ProjectionPalette.live : ProjectionPalette.line,
                    style: StrokeStyle(lineWidth: isLive ? metrics.length(0.3) : metrics.length(0.15), dash: isPending ? [6, 4] : [])
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Partido \(node.number): \(node.home.label) contra \(node.away.label)")
    }

    private func sideRow(_ side: ProjectionBracketSide, rowHeight: CGFloat, fontSize: CGFloat, number: Int?) -> some View {
        HStack(spacing: fontSize * 0.4) {
            Text(side.label)
                .font(.system(size: fontSize, weight: side.isWinner ? .heavy : .semibold, design: .rounded))
                .foregroundStyle(side.score != nil && !side.isWinner ? ProjectionPalette.muted : ProjectionPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer(minLength: 0)
            if let score = side.score {
                Text("\(score)")
                    .font(.system(size: fontSize, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(side.isWinner ? ProjectionPalette.text : ProjectionPalette.muted)
            }
        }
        .padding(.horizontal, fontSize * 0.6)
        .frame(height: rowHeight)
    }

    private func leafView(_ leaf: ProjectionBracketLeaf, _ f: Frame) -> some View {
        let fontSize = max(f.leafHeight * 0.55, 6)
        return HStack(spacing: fontSize * 0.5) {
            Text(leaf.positionText)
                .foregroundStyle(leaf.positionText == "1º" ? ProjectionPalette.gold : ProjectionPalette.muted)
            Text(leaf.teams.isEmpty ? "–" : leaf.teams.joined(separator: ", "))
                .foregroundStyle(ProjectionPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .font(.system(size: fontSize, weight: .bold, design: .rounded))
        .accessibilityElement(children: .combine)
    }

    private func drawEdges(_ context: inout GraphicsContext, _ f: Frame) {
        let nodes = Dictionary(bracket.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let leaves = Dictionary(bracket.leaves.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for edge in bracket.edges {
            guard let from = nodes[edge.from] else { continue }
            let start = origin(of: from, f)
            let startPoint = CGPoint(x: start.x + f.cardWidth, y: start.y + f.cardHeight / 2)
            let endPoint: CGPoint
            switch edge.target {
            case .node(let id, let slot):
                guard let target = nodes[id] else { continue }
                let end = origin(of: target, f)
                endPoint = CGPoint(x: end.x, y: end.y + f.cardHeight * (slot == .home ? 0.25 : 0.75))
            case .leaf(let id):
                guard let leaf = leaves[id] else { continue }
                let end = leafOrigin(leaf, f)
                endPoint = CGPoint(x: end.x, y: end.y + f.leafHeight / 2)
            }
            var path = Path()
            path.move(to: startPoint)
            path.addCurve(
                to: endPoint,
                control1: CGPoint(x: startPoint.x + f.gap * 0.6, y: startPoint.y),
                control2: CGPoint(x: endPoint.x - f.gap * 0.6, y: endPoint.y)
            )
            let isWinner = edge.kind == .winner
            context.stroke(
                path,
                with: .color(isWinner ? ProjectionPalette.win : ProjectionPalette.lose),
                style: StrokeStyle(lineWidth: metrics.length(0.25), lineCap: .round, dash: isWinner ? [] : [8, 6])
            )
        }
    }
}
