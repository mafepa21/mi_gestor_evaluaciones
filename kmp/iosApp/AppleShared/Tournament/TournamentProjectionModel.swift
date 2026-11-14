import Foundation

// Qué se enseña en la proyección de un torneo (el Mac conectado al proyector), como valor puro.
// A partir de `TournamentPlan` decide en qué momento está el torneo (`Stage`), qué escenas se
// ven y en qué orden rotan. Reutiliza `TournamentPhaseTimeline` y `BracketTreeLayout`: no
// repite ninguna regla de cuadro ni de fases. Sin vistas ni base de datos.
//
// SIN NOMBRES: cada equipo se llama «Equipo N», con N su posición (empezando en 1) en
// `plan.teams`, fija durante todo el torneo. Ninguna escena contiene el nombre de un equipo ni
// de un alumno: lo asegura `ProjectionTeamLabels` y lo vigilan las pruebas.
//
// Sin reloj: en esta fase no hay canal en directo, así que no se pinta ningún cronómetro (un
// reloj sin fuente fiable en el iPad sería un dato inventado). La ronda en juego es una
// deducción: la primera con partidos sin resultado.

// MARK: - Equipos sin nombre

/// Convierte equipos en «Equipo N». Lo que no es un equipo (huecos como «Gana P5» o
/// «1º liguilla») se deja tal cual: no contiene nombres.
struct ProjectionTeamLabels: Equatable, Sendable {
    private let numberByName: [String: Int]
    private let numberByID: [String: Int]

    init(plan: TournamentPlan) {
        var byName: [String: Int] = [:]
        var byID: [String: Int] = [:]
        for (offset, team) in plan.teams.enumerated() {
            if byName[team.name] == nil { byName[team.name] = offset + 1 }
            if byID[team.id] == nil { byID[team.id] = offset + 1 }
        }
        numberByName = byName
        numberByID = byID
    }

    func label(name: String) -> String {
        if let number = numberByName[name] { return "Equipo \(number)" }
        return Self.isSlotPlaceholder(name) ? name : Self.unknownTeam
    }

    /// Texto para un participante que no es un equipo del plan ni un hueco conocido. Nunca se
    /// devuelve el texto original: podría ser un nombre antiguo del alumnado.
    static let unknownTeam = "Equipo"

    /// Huecos del cuadro que genera la app («Gana P5», «Ganador P3», «Clasificado 1 Grupo A»,
    /// «3º liguilla», «1º Grupo A»). Solo estos pasan tal cual a la proyección.
    static func isSlotPlaceholder(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.range(of: #"^(Gana|Pierde|Ganador|Perdedor) P\d+$"#, options: .regularExpression) != nil
            || value.range(of: #"^Clasificado \d+( Grupo [A-Z0-9]+)?$"#, options: .regularExpression) != nil
            || value.range(of: #"^\d+º (liguilla|Grupo [A-Z0-9]+)$"#, options: .regularExpression) != nil
    }

    func label(id: String) -> String? {
        numberByID[id].map { "Equipo \($0)" }
    }

    /// Para ordenar equipos por su número.
    func number(name: String) -> Int? { numberByName[name] }
}

// MARK: - Contenido de las escenas

struct ProjectionHeader: Equatable, Sendable {
    /// Rótulo pequeño en color: la fase o el momento.
    var kicker: String
    var title: String

    var texts: [String] { [kicker, title] }
}

enum ProjectionSide: Equatable, Sendable { case home, away }

/// Un partido en una pista. `home` y `away` son «Equipo N» o el hueco de donde saldrá la pareja.
struct ProjectionMatch: Identifiable, Equatable, Sendable {
    let id: UUID
    let venue: Int
    let home: String
    let away: String
    let homeScore: Int?
    let awayScore: Int?
    /// «Puestos 1–4» en el cuadro de puestos.
    var caption: String?
    /// «Gana: sigue por 1–4 · Pierde: por 5–8», solo en el cuadro de puestos.
    var destination: String?

    var venueTitle: String { "Pista \(venue)" }
    var isPlayed: Bool { homeScore != nil && awayScore != nil }

    var winner: ProjectionSide? {
        guard let homeScore, let awayScore, homeScore != awayScore else { return nil }
        return homeScore > awayScore ? .home : .away
    }

    /// Cómo se lee un marcador: «Equipo 3 · Pista 2».
    var markerText: String { "\(home) · \(venueTitle)" }

    var texts: [String] {
        [venueTitle, home, away, caption, destination].compactMap { $0 }
    }
}

/// Ronda en juego: partidos por pista con su marcador.
struct ProjectionRound: Equatable, Sendable {
    var header: ProjectionHeader
    var matches: [ProjectionMatch]
    /// «Descansan: Equipo 3, Equipo 5».
    var restingText: String?
    var playedCount: Int

    var texts: [String] { header.texts + matches.flatMap(\.texts) + [restingText].compactMap { $0 } }
}

/// «Prepárate»: la ronda que viene (o la primera, si no ha empezado).
struct ProjectionUpNext: Equatable, Sendable {
    var header: ProjectionHeader
    var note: String?
    var matches: [ProjectionMatch]
    var restingText: String?

    var texts: [String] {
        header.texts + matches.flatMap(\.texts) + [note, restingText].compactMap { $0 }
    }
}

struct ProjectionStandingRow: Identifiable, Equatable, Sendable {
    let position: Int
    let team: String
    /// «3-1-0» (ganados, empatados, perdidos).
    let record: String
    /// «+12» (diferencia) o «9 pts».
    let extra: String

    var id: Int { position }
}

struct ProjectionStandingsTable: Identifiable, Equatable, Sendable {
    /// «Grupo A»; `nil` si es una sola tabla.
    var title: String?
    var rows: [ProjectionStandingRow]

    var id: String { title ?? "tabla" }
}

struct ProjectionStandings: Equatable, Sendable {
    var header: ProjectionHeader
    var recordHeader: String
    var extraHeader: String
    var tables: [ProjectionStandingsTable]

    var texts: [String] {
        header.texts + [recordHeader, extraHeader]
            + tables.flatMap { table in
                [table.title].compactMap { $0 } + table.rows.flatMap { [$0.team, $0.record, $0.extra] }
            }
    }
}

struct ProjectionBracketColumn: Identifiable, Equatable, Sendable {
    let id: Int
    var title: String
    var subtitle: String?
    var isCurrent: Bool
}

struct ProjectionBracketSide: Equatable, Sendable {
    var label: String
    var score: Int?
    var isWinner: Bool
    var isDirectPass: Bool
}

struct ProjectionBracketNode: Identifiable, Equatable, Sendable {
    let id: UUID
    /// El número que usan los huecos «Gana P5».
    let number: Int
    /// Columna dentro de lo que se dibuja (empieza en 0).
    let column: Int
    /// Altura en filas, ya recolocada para esta mitad.
    var row: Double
    var home: ProjectionBracketSide
    var away: ProjectionBracketSide
    var status: BracketNodeStatus
}

struct ProjectionBracketEdge: Identifiable, Equatable, Sendable {
    enum Target: Equatable, Sendable {
        case node(UUID, BracketSideSlot)
        case leaf(Int)
    }

    let from: UUID
    let kind: BracketEdgeKind
    let target: Target

    var id: String {
        switch target {
        case .node(let node, let side): return "\(from)-\(kind.rawValue)-\(node)-\(side == .home ? "h" : "a")"
        case .leaf(let leaf): return "\(from)-\(kind.rawValue)-leaf\(leaf)"
        }
    }
}

struct ProjectionBracketLeaf: Identifiable, Equatable, Sendable {
    let id: Int
    /// «1º», «5–6».
    var positionText: String
    /// «Equipo 3»; vacío si aún no se sabe.
    var teams: [String]
    var row: Double
}

struct ProjectionBracket: Equatable, Sendable {
    enum Part: Equatable, Sendable { case whole, first, second }

    var header: ProjectionHeader
    var part: Part
    var columns: [ProjectionBracketColumn]
    var nodes: [ProjectionBracketNode]
    var edges: [ProjectionBracketEdge]
    var leaves: [ProjectionBracketLeaf]
    /// Altura total en filas.
    var rows: Double
    var isPlacement: Bool

    var texts: [String] {
        header.texts
            + columns.flatMap { [$0.title, $0.subtitle].compactMap { $0 } }
            + nodes.flatMap { [$0.home.label, $0.away.label] }
            + leaves.flatMap { [$0.positionText] + $0.teams }
    }
}

/// Fin de la liguilla o de los grupos: empieza el cuadro.
struct ProjectionPhaseEnd: Equatable, Sendable {
    var header: ProjectionHeader
    var note: String?
    var matches: [ProjectionMatch]

    var texts: [String] { header.texts + matches.flatMap(\.texts) + [note].compactMap { $0 } }
}

struct ProjectionPlace: Identifiable, Equatable, Sendable {
    let position: Int
    let team: String

    var id: Int { position }
}

struct ProjectionPodium: Equatable, Sendable {
    var header: ProjectionHeader
    /// Primeros puestos (hasta el 3º), en orden.
    var places: [ProjectionPlace]
    /// El resto de la clasificación.
    var others: [ProjectionPlace]

    var texts: [String] { header.texts + (places + others).map(\.team) }
}

struct ProjectionMessage: Equatable, Sendable {
    var header: ProjectionHeader
    var message: String

    var texts: [String] { header.texts + [message] }
}

// MARK: - Escena

enum TournamentProjectionScene: Equatable, Identifiable, Sendable {
    case empty(ProjectionMessage)
    /// Sin resultados todavía.
    case notStarted(ProjectionUpNext)
    case round(ProjectionRound)
    case upNext(ProjectionUpNext)
    case standings(ProjectionStandings)
    case bracket(ProjectionBracket)
    case phaseEnd(ProjectionPhaseEnd)
    case podium(ProjectionPodium)

    enum Kind: Equatable, Sendable {
        case empty, notStarted, round, upNext, standings, bracket, phaseEnd, podium
    }

    var kind: Kind {
        switch self {
        case .empty: return .empty
        case .notStarted: return .notStarted
        case .round: return .round
        case .upNext: return .upNext
        case .standings: return .standings
        case .bracket: return .bracket
        case .phaseEnd: return .phaseEnd
        case .podium: return .podium
        }
    }

    /// Identidad para animar el cambio de escena: dos mitades del cuadro son escenas distintas.
    var id: String {
        if case .bracket(let bracket) = self { return "bracket-\(bracket.part)" }
        return "\(kind)"
    }

    var header: ProjectionHeader {
        switch self {
        case .empty(let value): return value.header
        case .notStarted(let value), .upNext(let value): return value.header
        case .round(let value): return value.header
        case .standings(let value): return value.header
        case .bracket(let value): return value.header
        case .phaseEnd(let value): return value.header
        case .podium(let value): return value.header
        }
    }

    /// Todas las cadenas que se pintan. Las pruebas comprueban que ninguna lleva un nombre.
    var texts: [String] {
        switch self {
        case .empty(let value): return value.texts
        case .notStarted(let value), .upNext(let value): return value.texts
        case .round(let value): return value.texts
        case .standings(let value): return value.texts
        case .bracket(let value): return value.texts
        case .phaseEnd(let value): return value.texts
        case .podium(let value): return value.texts
        }
    }
}

struct ProjectionFooterPhase: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable { case done, current, upcoming }

    let id: Int
    var title: String
    var state: State
}

// MARK: - Modelo

struct TournamentProjectionModel: Equatable, Sendable {
    /// Momento del torneo. Decide las escenas.
    enum Stage: Equatable, Sendable {
        /// Sin calendario (o sin equipos).
        case empty
        /// Con calendario pero sin ningún resultado.
        case notStarted
        /// Ronda de la liguilla, los grupos o la liga con partidos en juego.
        case leagueInPlay
        /// Entre dos rondas: la anterior está completa y de la nueva no hay resultados.
        case rest
        /// Liguilla o grupos terminados, cuadro sin empezar.
        case leagueEnded
        case bracketInPlay
        /// No queda nada por jugar.
        case finished
    }

    /// Segundos que dura cada escena en la rotación automática.
    static let rotationSeconds: TimeInterval = 15
    /// Más partidos que estos en una ronda y el cuadro se enseña en dos mitades.
    static let matchesPerRoundBeforeSplitting = 8

    let tournamentName: String
    let stage: Stage
    /// Línea de fases del pie: «1 · Liguilla», «2 · Cuadro», «Podio».
    let footer: [ProjectionFooterPhase]
    /// Escenas en el orden de la rotación. Nunca vacío.
    let scenes: [TournamentProjectionScene]

    /// Escena de la vuelta número `rotation` (da la vuelta sola).
    func scene(at rotation: Int) -> TournamentProjectionScene {
        let count = scenes.count
        return scenes[((rotation % count) + count) % count]
    }

    /// Todas las cadenas de todas las escenas y del pie.
    var allTexts: [String] {
        [tournamentName] + footer.map(\.title) + scenes.flatMap(\.texts)
    }

    // MARK: Construcción

    static func make(plan: TournamentPlan) -> TournamentProjectionModel {
        let labels = ProjectionTeamLabels(plan: plan)
        guard !plan.savedSchedule.isEmpty, plan.teams.count >= 2 else {
            return emptyModel(
                plan: plan,
                title: "Todavía no hay calendario",
                message: "Prepara el torneo en el iPad o en el Mac y vuelve a proyectar."
            )
        }

        let timeline = TournamentPhaseTimeline.make(plan: plan)
        let footer = footerPhases(plan: plan, timeline: timeline)
        let slots = plan.slots
        let slotsByID = Dictionary(slots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let hasBracket = plan.format.includesKnockoutPhase
        let layout = BracketTreeLayout.make(plan: plan)

        // Liguilla, grupos o liga: rondas con partidos y resultados ya resueltos.
        let leagueSchedule = plan.savedSchedule.filter { !(hasBracket && ($0.stage == .knockout || plan.format == .knockout)) }
        let leagueRounds = leagueSchedule.map { round in
            leagueRound(round, plan: plan, labels: labels, slotsByID: slotsByID)
        }

        func make(_ stage: Stage, _ scenes: [TournamentProjectionScene]) -> TournamentProjectionModel {
            TournamentProjectionModel(tournamentName: plan.name, stage: stage, footer: footer, scenes: scenes)
        }

        let leaguePhase = timeline.phase(.league)
        let leagueTitle = leaguePhase?.title ?? "Liga"

        // Sin ningún resultado: se enseña la primera ronda.
        if !timeline.hasStarted {
            let first: [ProjectionMatch]
            let resting: String?
            if hasBracket && plan.format == .knockout, let layout, let column = layout.columns.indices.first {
                first = bracketMatches(layout, column: column, labels: labels)
                resting = nil
            } else {
                first = leagueRounds.first?.matches ?? []
                resting = leagueRounds.first?.restingText
            }
            let kicker = timeline.phases.first?.title ?? leagueTitle
            let scene = TournamentProjectionScene.notStarted(
                ProjectionUpNext(
                    header: ProjectionHeader(kicker: "Empieza el torneo", title: "Prepárate"),
                    note: "\(kicker). La clasificación aparecerá al terminar la primera ronda.",
                    matches: first,
                    restingText: resting
                )
            )
            return make(.notStarted, [scene])
        }

        switch timeline.currentKind {
        case .podium:
            guard let podium = podium(plan: plan, layout: layout, labels: labels) else {
                return emptyModel(
                    plan: plan,
                    title: "Torneo terminado",
                    message: "Los resultados están completos."
                )
            }
            return make(.finished, [.podium(podium)])

        case .league:
            guard let index = leagueSchedule.indices.first(where: { index in
                leagueRounds[index].matches.contains { !$0.isPlayed }
            }) else {
                return make(.leagueInPlay, [.standings(standings(plan: plan, labels: labels, isFinal: false, leagueTitle: leagueTitle))])
            }
            let round = leagueRounds[index]
            let roundText = "Ronda \(index + 1) de \(leagueRounds.count)"
            let standingsScene = TournamentProjectionScene.standings(
                standings(plan: plan, labels: labels, isFinal: false, leagueTitle: leagueTitle)
            )
            let playedCount = round.matches.filter(\.isPlayed).count
            if index > 0, playedCount == 0 {
                let upNext = ProjectionUpNext(
                    header: ProjectionHeader(kicker: "Descanso · Prepárate", title: "\(leagueTitle) · \(roundText)"),
                    note: nil,
                    matches: round.matches,
                    restingText: round.restingText
                )
                return make(.rest, [.upNext(upNext), standingsScene])
            }
            let scene = TournamentProjectionScene.round(
                ProjectionRound(
                    header: ProjectionHeader(kicker: "\(leagueTitle) · \(roundText)", title: "Ahora en juego"),
                    matches: round.matches,
                    restingText: round.restingText,
                    playedCount: playedCount
                )
            )
            return make(.leagueInPlay, [scene, standingsScene])

        case .bracket, .round:
            guard let layout else {
                return emptyModel(
                    plan: plan,
                    title: "No se puede dibujar el cuadro",
                    message: "El cuadro no coincide con el calendario. Revísalo en el torneo."
                )
            }
            // Liguilla o grupos recién cerrados y cuadro sin empezar.
            if timeline.bracketPlayed == 0, plan.format != .knockout, let column = layout.currentColumn {
                let note: String? = plan.format == .leaguePlacement
                    ? "Nadie queda eliminado: quien gana sigue por los puestos de arriba, quien pierde por los de abajo."
                    : "Los mejores de cada grupo pasan al cuadro."
                let end = ProjectionPhaseEnd(
                    header: ProjectionHeader(
                        kicker: "Fin de la fase 1",
                        title: "\(plan.format == .leaguePlacement ? "Liguilla" : "Grupos") terminados. Empieza el cuadro."
                    ),
                    note: note,
                    matches: bracketMatches(layout, column: column, labels: labels)
                )
                let table = standings(plan: plan, labels: labels, isFinal: true, leagueTitle: leagueTitle)
                return make(.leagueEnded, [.phaseEnd(end), .standings(table)])
            }
            guard let column = layout.currentColumn else {
                return emptyModel(
                    plan: plan,
                    title: "No se puede dibujar el cuadro",
                    message: "El cuadro no coincide con el calendario. Revísalo en el torneo."
                )
            }
            let phaseTitle = timeline.phase(timeline.currentKind)?.title ?? "Cuadro"
            let roundText = plan.format == .knockout
                ? layout.columns[column].title
                : "Ronda \(column + 1) de \(layout.columns.count)"
            let kicker = plan.format == .knockout ? phaseTitle : "\(phaseTitle) · \(roundText)"
            let matches = bracketMatches(layout, column: column, labels: labels)
            let brackets = bracketScenes(layout: layout, plan: plan, labels: labels, phaseTitle: phaseTitle)
            let playedCount = matches.filter(\.isPlayed).count
            if column > 0, playedCount == 0 {
                let upNext = ProjectionUpNext(
                    header: ProjectionHeader(kicker: "Descanso · Prepárate", title: plan.format == .knockout ? roundText : "\(phaseTitle) · \(roundText)"),
                    note: nil,
                    matches: matches,
                    restingText: nil
                )
                return make(.rest, [.upNext(upNext)] + brackets)
            }
            let scene = TournamentProjectionScene.round(
                ProjectionRound(
                    header: ProjectionHeader(kicker: kicker, title: "Ahora en juego"),
                    matches: matches,
                    restingText: nil,
                    playedCount: playedCount
                )
            )
            return make(.bracketInPlay, [scene] + brackets)
        }
    }

    // MARK: Casos sueltos

    private static func emptyModel(plan: TournamentPlan, title: String, message: String) -> TournamentProjectionModel {
        TournamentProjectionModel(
            tournamentName: plan.name,
            stage: .empty,
            footer: [],
            scenes: [.empty(ProjectionMessage(header: ProjectionHeader(kicker: "Torneo", title: title), message: message))]
        )
    }

    private static func footerPhases(plan: TournamentPlan, timeline: TournamentPhaseTimeline) -> [ProjectionFooterPhase] {
        timeline.phases.enumerated().map { offset, phase in
            let title: String
            switch phase.kind {
            case .podium: title = "Podio"
            case .league: title = phase.title.replacingOccurrences(of: "Fase ", with: "")
            case .bracket: title = plan.format == .leaguePlacement ? "\(phase.number) · Cuadro" : "\(phase.number) · Eliminatorias"
            case .round: title = phase.title.replacingOccurrences(of: "Fase ", with: "")
            }
            let state: ProjectionFooterPhase.State
            switch phase.state {
            case .done: state = .done
            case .current: state = .current
            case .upcoming: state = .upcoming
            }
            return ProjectionFooterPhase(id: offset, title: title, state: state)
        }
    }

    // MARK: Ronda de liguilla

    private struct LeagueRoundData {
        var matches: [ProjectionMatch]
        var restingText: String?
    }

    private static func leagueRound(
        _ round: ScheduledRound,
        plan: TournamentPlan,
        labels: ProjectionTeamLabels,
        slotsByID: [UUID: ScheduledMatchSlot]
    ) -> LeagueRoundData {
        let matches: [ProjectionMatch] = round.matches.compactMap { match in
            guard let slot = slotsByID[match.id] else { return nil }
            let score = ScheduleAnalytics.result(for: slot, tournament: plan)
            return ProjectionMatch(
                id: slot.id,
                venue: slot.venueNumber,
                home: labels.label(name: slot.match.homeTeam),
                away: labels.label(name: slot.match.awayTeam),
                homeScore: score?.homeScore,
                awayScore: score?.awayScore,
                caption: nil,
                destination: nil
            )
        }.sorted { $0.venue < $1.venue }

        // Quién no juega esta ronda (no aplica a los grupos: los demás grupos juegan a la vez).
        var resting: String?
        if plan.format != .groupStageKnockout {
            let playing = Set(round.matches.flatMap { [$0.homeTeam, $0.awayTeam] })
            let waiting = plan.teams.enumerated()
                .filter { !playing.contains($0.element.name) }
                .map { "Equipo \($0.offset + 1)" }
            if waiting.count == 1 {
                resting = "Descansa: \(waiting[0])"
            } else if waiting.count > 1, waiting.count <= 6 {
                resting = "Descansan: \(waiting.joined(separator: ", "))"
            } else if waiting.count > 6 {
                resting = "Descansan \(waiting.count) equipos"
            }
        }
        return LeagueRoundData(matches: matches, restingText: resting)
    }

    // MARK: Cuadro

    private static func positionsText(_ range: ClosedRange<Int>) -> String {
        if range.lowerBound == range.upperBound { return "\(range.lowerBound)º" }
        if range.count == 2 { return "\(range.lowerBound)º–\(range.upperBound)º" }
        return "\(range.lowerBound)–\(range.upperBound)"
    }

    private static func side(_ side: BracketSide, labels: ProjectionTeamLabels) -> ProjectionBracketSide {
        let label = side.teamID.flatMap { labels.label(id: $0) } ?? labels.label(name: side.label)
        return ProjectionBracketSide(label: label, score: side.score, isWinner: side.isWinner, isDirectPass: side.isDirectPass)
    }

    /// Partidos de una columna del cuadro, por pista.
    private static func bracketMatches(
        _ layout: BracketTreeLayout,
        column: Int,
        labels: ProjectionTeamLabels
    ) -> [ProjectionMatch] {
        layout.nodes.filter { $0.column == column }.map { node in
            let home = side(node.home, labels: labels)
            let away = side(node.away, labels: labels)
            let played = node.status == .played
            return ProjectionMatch(
                id: node.id,
                venue: node.venue,
                home: home.label,
                away: away.label,
                homeScore: played ? home.score : nil,
                awayScore: played ? away.score : nil,
                caption: node.positions.map { "Puestos \(positionsText($0))" },
                // «A qué lleva ganar o perder» solo tiene sentido en el cuadro de puestos.
                destination: layout.isPlacement ? node.destinationText : nil
            )
        }.sorted { ($0.venue, $0.id.uuidString) < ($1.venue, $1.id.uuidString) }
    }

    /// El cuadro entero o, con más de 8 partidos en una ronda, en dos mitades.
    private static func bracketScenes(
        layout: BracketTreeLayout,
        plan: TournamentPlan,
        labels: ProjectionTeamLabels,
        phaseTitle: String
    ) -> [TournamentProjectionScene] {
        let widest = layout.columns.map { column in layout.nodes.filter { $0.column == column.id }.count }.max() ?? 0
        let split = widest > matchesPerRoundBeforeSplitting && layout.columns.count >= 2
        let parts: [ProjectionBracket.Part] = split ? [.first, .second] : [.whole]
        return parts.map { .bracket(bracket(layout: layout, plan: plan, labels: labels, part: $0, phaseTitle: phaseTitle)) }
    }

    static func bracket(
        layout: BracketTreeLayout,
        plan: TournamentPlan,
        labels: ProjectionTeamLabels,
        part: ProjectionBracket.Part,
        phaseTitle: String
    ) -> ProjectionBracket {
        let teamCount = plan.teamCount
        let half = (teamCount + 1) / 2

        // Qué partidos entran en esta parte.
        var included = Set<UUID>()
        for node in layout.nodes {
            switch part {
            case .whole:
                included.insert(node.id)
            case .first, .second:
                let isFirst = part == .first
                if layout.isPlacement {
                    // La primera ronda ya se vio en «Ahora en juego»; cada mitad lleva los puestos de arriba o de abajo.
                    guard node.column >= 1, let positions = node.positions else { continue }
                    if (positions.lowerBound <= half) == isFirst { included.insert(node.id) }
                } else {
                    let count = layout.nodes.filter { $0.column == node.column }.count
                    if count == 1 {
                        included.insert(node.id)
                    } else if (node.row < (count + 1) / 2) == isFirst {
                        included.insert(node.id)
                    }
                }
            }
        }

        let usedColumns = Array(Set(layout.nodes.filter { included.contains($0.id) }.map(\.column))).sorted()
        let newColumn = Dictionary(uniqueKeysWithValues: usedColumns.enumerated().map { ($1, $0) })
        let minRow = layout.nodes.filter { included.contains($0.id) }.map(\.yRow).min() ?? 0

        let nodes: [ProjectionBracketNode] = layout.nodes.compactMap { node in
            guard included.contains(node.id), let column = newColumn[node.column] else { return nil }
            return ProjectionBracketNode(
                id: node.id,
                number: node.number,
                column: column,
                row: node.yRow - minRow,
                home: side(node.home, labels: labels),
                away: side(node.away, labels: labels),
                status: node.status
            )
        }
        let rowByID = Dictionary(nodes.map { ($0.id, $0.row) }, uniquingKeysWith: { first, _ in first })

        var edges: [ProjectionBracketEdge] = []
        var leafIDs = Set<Int>()
        let leaves = layout.leaves.filter { leaf in
            switch part {
            case .whole: return true
            case .first, .second:
                guard layout.isPlacement else { return true }
                return (leaf.positions.lowerBound <= half) == (part == .first)
            }
        }
        let leafIDSet = Set(leaves.map(\.id))
        for edge in layout.edges where included.contains(edge.from) {
            switch edge.target {
            case .node(let target, let slot):
                if included.contains(target) {
                    edges.append(ProjectionBracketEdge(from: edge.from, kind: edge.kind, target: .node(target, slot)))
                }
            case .leaf(let leaf):
                if leafIDSet.contains(leaf) {
                    edges.append(ProjectionBracketEdge(from: edge.from, kind: edge.kind, target: .leaf(leaf)))
                    leafIDs.insert(leaf)
                }
            }
        }

        // Puestos finales: a la altura de su partido de origen y sin pisarse.
        let leafHeight = 0.5
        var wanted: [(leaf: BracketLeaf, row: Double)] = []
        for leaf in leaves where leafIDs.contains(leaf.id) {
            let rows = leaf.sources.compactMap { source -> Double? in
                guard let row = rowByID[source.nodeID] else { return nil }
                return row + (source.kind == .winner ? 0.3 : 0.7) - leafHeight / 2
            }
            guard !rows.isEmpty else { continue }
            wanted.append((leaf, rows.reduce(0, +) / Double(rows.count)))
        }
        var leafModels: [ProjectionBracketLeaf] = []
        var last = -leafHeight
        var bottom = (nodes.map(\.row).max() ?? 0) + 1
        for item in wanted.sorted(by: { ($0.row, $0.leaf.id) < ($1.row, $1.leaf.id) }) {
            let row = max(item.row, last + leafHeight + 0.05)
            last = row
            bottom = max(bottom, row + leafHeight)
            leafModels.append(
                ProjectionBracketLeaf(
                    id: item.leaf.id,
                    positionText: positionsText(item.leaf.positions),
                    teams: item.leaf.teamIDs.compactMap { labels.label(id: $0) },
                    row: row
                )
            )
        }

        let columns: [ProjectionBracketColumn] = usedColumns.compactMap { old in
            guard layout.columns.indices.contains(old), let new = newColumn[old] else { return nil }
            let source = layout.columns[old]
            return ProjectionBracketColumn(
                id: new,
                title: source.title,
                subtitle: source.subtitle,
                isCurrent: source.state == .current
            )
        }

        let title: String
        switch part {
        case .whole: title = "Cuadro"
        case .first: title = layout.isPlacement ? "Cuadro · puestos 1 a \(half)" : "Cuadro · mitad de arriba"
        case .second: title = layout.isPlacement ? "Cuadro · puestos \(half + 1) a \(teamCount)" : "Cuadro · mitad de abajo"
        }
        return ProjectionBracket(
            header: ProjectionHeader(kicker: phaseTitle, title: title),
            part: part,
            columns: columns,
            nodes: nodes,
            edges: edges,
            leaves: leafModels,
            rows: bottom,
            isPlacement: layout.isPlacement
        )
    }

    // MARK: Clasificación

    private static func record(_ wins: Int, _ draws: Int, _ losses: Int) -> String { "\(wins)-\(draws)-\(losses)" }

    private static func standings(
        plan: TournamentPlan,
        labels: ProjectionTeamLabels,
        isFinal: Bool,
        leagueTitle: String
    ) -> ProjectionStandings {
        let kicker = isFinal ? "Fin de la fase 1" : leagueTitle
        let title = isFinal ? "Clasificación final" : (plan.format == .groupStageKnockout ? "Clasificación por grupos" : "Clasificación")

        func points(_ value: Standing) -> String { "\(value.points) pts" }

        switch plan.format {
        case .leaguePlacement:
            let rows = plan.placementStandings.enumerated().map { offset, row in
                let diff = row.pointDifference
                return ProjectionStandingRow(
                    position: offset + 1,
                    team: labels.label(name: row.teamName),
                    record: record(row.wins, row.draws, row.losses),
                    extra: diff > 0 ? "+\(diff)" : "\(diff)"
                )
            }
            return ProjectionStandings(
                header: ProjectionHeader(kicker: kicker, title: title),
                recordHeader: "G-E-P",
                extraHeader: "Dif",
                tables: [ProjectionStandingsTable(title: nil, rows: rows)]
            )
        case .groupStageKnockout:
            // `groupStandings` antepone «Grupo » a un nombre que ya lo lleva: se usa el nombre limpio.
            let tables = plan.groupStandings.enumerated().map { index, group in
                ProjectionStandingsTable(
                    title: GroupStageConfiguration.groupName(index: index),
                    rows: group.standings.enumerated().map { offset, row in
                        ProjectionStandingRow(
                            position: offset + 1,
                            team: labels.label(name: row.teamName),
                            record: record(row.wins, row.draws, row.losses),
                            extra: points(row)
                        )
                    }
                )
            }
            return ProjectionStandings(
                header: ProjectionHeader(kicker: kicker, title: title),
                recordHeader: "G-E-P",
                extraHeader: "Pts",
                tables: tables
            )
        default:
            let rows = plan.leagueStandings.enumerated().map { offset, row in
                ProjectionStandingRow(
                    position: offset + 1,
                    team: labels.label(name: row.teamName),
                    record: record(row.wins, row.draws, row.losses),
                    extra: points(row)
                )
            }
            return ProjectionStandings(
                header: ProjectionHeader(kicker: kicker, title: title),
                recordHeader: "G-E-P",
                extraHeader: "Pts",
                tables: [ProjectionStandingsTable(title: nil, rows: rows)]
            )
        }
    }

    // MARK: Podio

    private static func podium(
        plan: TournamentPlan,
        layout: BracketTreeLayout?,
        labels: ProjectionTeamLabels
    ) -> ProjectionPodium? {
        var ranking: [ProjectionPlace] = []
        if plan.format == .leaguePlacement {
            ranking = (plan.placementFinalTable ?? []).map {
                ProjectionPlace(position: $0.position, team: labels.label(name: $0.teamName))
            }
        } else if plan.format.includesKnockoutPhase {
            ranking = (layout?.leaves ?? [])
                .filter { $0.isComplete && $0.slotCount == 1 }
                .compactMap { leaf in
                    leaf.teamIDs.first.flatMap { labels.label(id: $0) }.map {
                        ProjectionPlace(position: leaf.positions.lowerBound, team: $0)
                    }
                }
                .sorted { $0.position < $1.position }
        } else {
            ranking = plan.leagueStandings.enumerated().map {
                ProjectionPlace(position: $0.offset + 1, team: labels.label(name: $0.element.teamName))
            }
        }
        guard !ranking.isEmpty else { return nil }
        return ProjectionPodium(
            header: ProjectionHeader(kicker: "Fin del torneo", title: "Podio"),
            places: ranking.filter { $0.position <= 3 },
            others: ranking.filter { $0.position > 3 }
        )
    }
}
