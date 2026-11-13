import Foundation

// Árbol del cuadro como valor puro: columnas por ronda, partidos, conexiones (quién sube y quién
// baja), puestos finales y el camino de una pareja. Sirve a «Liguilla + puestos» y a las
// eliminatorias (`.knockout` y `.groupStageKnockout`). No decide nada: reutiliza
// `PlacementBracket` y `KnockoutBracketResolver`, y los resultados guardados en el plan.
// Sin vistas ni base de datos.

// MARK: - Tipos

enum BracketNodeStatus: Equatable, Sendable {
    /// Con resultado decisivo.
    case played
    /// Con las dos parejas conocidas, en la ronda que toca jugar.
    case inPlay
    case pending
}

enum BracketEdgeKind: String, Equatable, Sendable {
    /// El ganador sigue (sube).
    case winner
    /// El perdedor sigue (baja).
    case loser
}

enum BracketSideSlot: Equatable, Sendable {
    case home
    case away
}

/// Una de las dos filas de un partido.
struct BracketSide: Equatable, Sendable {
    /// Nombre de la pareja o etiqueta del hueco («Gana P5», «3º liguilla»).
    var label: String
    var teamID: String?
    var teamName: String?
    var score: Int?
    var isWinner: Bool
    /// La pareja llega a esta ronda sin haber jugado la anterior.
    var isDirectPass: Bool

    var isResolved: Bool { teamName != nil }
}

struct BracketNode: Identifiable, Equatable, Sendable {
    /// Identificador del partido en el calendario.
    let id: UUID
    /// Número del partido en el cuadro («P7»), el mismo que usan los huecos «Gana P7».
    let number: Int
    /// Columna, empezando en 0.
    let column: Int
    /// Ronda del cuadro, empezando en 1.
    let round: Int
    /// Orden dentro de la columna.
    let row: Int
    /// Altura en filas, ya con los huecos entre bandas de puestos. Puede ser decimal.
    var yRow: Double
    /// Primer partido de una banda de puestos (en el cuadro de puestos).
    let startsBand: Bool
    /// Puestos que se juegan; `nil` en eliminatoria.
    let positions: ClosedRange<Int>?
    let venue: Int
    var home: BracketSide
    var away: BracketSide
    var status: BracketNodeStatus
    /// Adónde va quien gana, en texto corto: «sigue por 1–4», «pasa a Semifinales».
    let winnerDestination: String
    let loserDestination: String

    var winnerTeamName: String? { home.isWinner ? home.teamName : (away.isWinner ? away.teamName : nil) }
    var loserTeamName: String? {
        guard status == .played else { return nil }
        return home.isWinner ? away.teamName : home.teamName
    }

    var destinationText: String { "Gana: \(winnerDestination) · Pierde: \(loserDestination)" }
}

struct BracketColumn: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable { case done, current, upcoming }

    let id: Int
    let title: String
    let subtitle: String?
    var state: State
    var nodeIDs: [UUID]

    var statusText: String? {
        switch state {
        case .done: return "jugada"
        case .current: return "en juego"
        case .upcoming: return nil
        }
    }

    /// Cabecera completa: «Ronda 3 · en juego».
    var headerText: String {
        statusText.map { "\(title) · \($0)" } ?? title
    }
}

struct BracketEdge: Identifiable, Equatable, Sendable {
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

/// Puesto final (o grupo de puestos, si el cuadro es corto).
struct BracketLeaf: Identifiable, Equatable, Sendable {
    /// Primer puesto del grupo.
    let id: Int
    let positions: ClosedRange<Int>
    /// Parejas ya conocidas, ordenadas por su puesto en la liguilla si se sabe.
    var teamNames: [String]
    var teamIDs: [String]
    /// Parejas que lo forman (conocidas o no).
    let slotCount: Int
    /// Partidos de los que viene, con el lado por el que salen.
    let sources: [BracketLeafSource]

    var isComplete: Bool { teamNames.count == slotCount }
}

struct BracketLeafSource: Equatable, Sendable {
    let nodeID: UUID
    let kind: BracketEdgeKind
}

/// Un paso en el camino de una pareja.
struct BracketPathStep: Identifiable, Equatable, Sendable {
    enum Outcome: Equatable, Sendable { case won, lost, playing, upcoming }

    let nodeID: UUID
    let number: Int
    let round: Int
    let outcome: Outcome
    /// Rival o etiqueta de su hueco.
    let opponent: String
    let ownScore: Int?
    let opponentScore: Int?
    /// Texto completo para leer: «Ronda 2 · P7: gana 15–10 a Pareja 4».
    let text: String
    /// Texto corto para la línea de resumen: «R2: gana 15–10 a Pareja 4 ↑».
    let shortText: String

    var id: UUID { nodeID }
}

struct BracketTeamPath: Equatable, Sendable {
    let teamID: String
    let teamName: String
    /// «3º en la liguilla», «2º en Grupo A». `nil` si aún no hay resultados.
    let leagueText: String?
    let steps: [BracketPathStep]
    let finalPosition: Int?
    let highlightedNodeIDs: Set<UUID>
    let highlightedEdgeIDs: Set<String>
    let highlightedLeafIDs: Set<Int>

    /// Resumen en una línea. Es lo que se enseña encima del árbol.
    var summaryText: String {
        var parts: [String] = []
        if let leagueText { parts.append("Liguilla: \(leagueText)") }
        parts.append(contentsOf: steps.map(\.shortText))
        if let finalPosition { parts.append("Puesto final: \(finalPosition)º") }
        if parts.isEmpty { return "\(teamName) aún no entra en el cuadro." }
        return parts.joined(separator: " → ")
    }
}

// MARK: - Árbol

struct BracketTreeLayout: Equatable, Sendable {
    var columns: [BracketColumn]
    var nodes: [BracketNode]
    var edges: [BracketEdge]
    var leaves: [BracketLeaf]
    /// Título de la columna final: «Puesto final» o «Podio».
    var finalColumnTitle: String
    var finalColumnSubtitle: String?
    /// Columna en la que se juega ahora; `nil` si no hay (cuadro cerrado o terminado).
    var currentColumn: Int?
    /// Altura total en filas.
    var totalRows: Double
    /// Cuadro de puestos (con bandas) o eliminatoria clásica.
    var isPlacement: Bool
    /// `true` si el cuadro ya se puede jugar (liguilla o grupos cerrados).
    var isOpen: Bool

    fileprivate var teamNamesByID: [String: String]
    fileprivate var leagueNotes: [String: String]
    fileprivate var finalPositionsByName: [String: Int]

    func node(_ id: UUID) -> BracketNode? { nodes.first { $0.id == id } }

    /// Parejas del torneo en el orden de `plan.teams`: para el selector «Seguir a».
    var followableTeams: [(id: String, name: String)] {
        teamNamesByID.map { (id: $0.key, name: $0.value) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var playedCount: Int { nodes.filter { $0.status == .played }.count }

    static func positionsText(_ range: ClosedRange<Int>) -> String {
        range.lowerBound == range.upperBound ? "\(range.lowerBound)º" : "\(range.lowerBound)–\(range.upperBound)"
    }

    // MARK: Camino de una pareja

    func path(for teamID: String) -> BracketTeamPath? {
        guard let name = teamNamesByID[teamID] else { return nil }
        var steps: [BracketPathStep] = []
        var highlightedNodes = Set<UUID>()
        var highlightedEdges = Set<String>()
        var highlightedLeaves = Set<Int>()

        func follow(_ node: BracketNode, kind: BracketEdgeKind) {
            for edge in edges where edge.from == node.id && edge.kind == kind {
                highlightedEdges.insert(edge.id)
                switch edge.target {
                case .node(let id, _): highlightedNodes.insert(id)
                case .leaf(let id): highlightedLeaves.insert(id)
                }
            }
        }

        let mine = nodes.filter { $0.home.teamID == teamID || $0.away.teamID == teamID }
        for node in mine {
            let isHome = node.home.teamID == teamID
            let me = isHome ? node.home : node.away
            let other = isHome ? node.away : node.home
            let outcome: BracketPathStep.Outcome
            switch node.status {
            case .played: outcome = me.isWinner ? .won : .lost
            case .inPlay: outcome = .playing
            case .pending: outcome = .upcoming
            }
            highlightedNodes.insert(node.id)
            if node.status == .played { follow(node, kind: me.isWinner ? .winner : .loser) }
            steps.append(Self.step(node: node, me: me, other: other, outcome: outcome))
        }

        var finalPosition = finalPositionsByName[name]
        for leaf in leaves where leaf.teamIDs.contains(teamID) {
            highlightedLeaves.insert(leaf.id)
            if finalPosition == nil, leaf.slotCount == 1, leaf.isComplete { finalPosition = leaf.positions.lowerBound }
        }

        return BracketTeamPath(
            teamID: teamID,
            teamName: name,
            leagueText: leagueNotes[teamID],
            steps: steps,
            finalPosition: finalPosition,
            highlightedNodeIDs: highlightedNodes,
            highlightedEdgeIDs: highlightedEdges,
            highlightedLeafIDs: highlightedLeaves
        )
    }

    private static func step(
        node: BracketNode,
        me: BracketSide,
        other: BracketSide,
        outcome: BracketPathStep.Outcome
    ) -> BracketPathStep {
        let mine = me.score
        let theirs = other.score
        let scoreText = (mine != nil && theirs != nil) ? "\(mine!)–\(theirs!)" : ""
        let lead = "Ronda \(node.round) · P\(node.number)"
        let text: String
        let short: String
        switch outcome {
        case .won:
            text = "\(lead): gana \(scoreText) a \(other.label)"
            short = "R\(node.round): gana \(scoreText) a \(other.label) ↑"
        case .lost:
            text = "\(lead): pierde \(scoreText) ante \(other.label)"
            short = "R\(node.round): pierde \(scoreText) ante \(other.label) ↓"
        case .playing:
            text = "\(lead): juega con \(other.label) en la pista \(node.venue). \(node.destinationText)"
            short = "R\(node.round): juega con \(other.label), pista \(node.venue). \(node.destinationText)"
        case .upcoming:
            let rival = other.isResolved ? "juega con \(other.label)" : "espera rival (\(other.label))"
            text = "\(lead): \(rival). \(node.destinationText)"
            short = "R\(node.round): \(rival)"
        }
        return BracketPathStep(
            nodeID: node.id,
            number: node.number,
            round: node.round,
            outcome: outcome,
            opponent: other.label,
            ownScore: mine,
            opponentScore: theirs,
            text: text,
            shortText: short
        )
    }
}

// MARK: - Construcción desde el plan

extension BracketTreeLayout {
    /// Hueco que ocupa una pareja en un partido, antes de saber quién es.
    private enum Ref {
        case seed(Int)
        case qualifier(String)
        case team(String)
        case winner(Int)
        case loser(Int)
    }

    /// Partido del cuadro antes de resolver nombres y resultados.
    private struct Draft {
        var match: ScheduledMatch
        var number: Int
        var round: Int
        var positions: ClosedRange<Int>?
        var home: Ref
        var away: Ref
        var winnerDestination: String
        var loserDestination: String
    }

    private struct LeafDraft {
        var firstPosition: Int
        var slots: [Ref]
    }

    private static let winnerPrefix = "Ganador P"

    /// Árbol del torneo, o `nil` si el formato no tiene cuadro o el calendario no cuadra con él.
    static func make(plan: TournamentPlan) -> BracketTreeLayout? {
        guard plan.format.includesKnockoutPhase, !plan.savedSchedule.isEmpty else { return nil }
        let isPlacement = plan.format == .leaguePlacement
        let saved = KnockoutBracketResolver.allMatches(in: plan.savedSchedule)
        guard !saved.isEmpty else { return nil }

        var drafts: [Draft] = []
        var leafDrafts: [LeafDraft] = []
        var columnTitles: [Int: (title: String, subtitle: String?)] = [:]

        if isPlacement {
            let bracket = plan.placementBracket
            let numbers = PlacementResolver.matchNumbers(bracket.batches(venueCount: plan.venueCount))
            guard numbers.count == saved.count, numbers.count == bracket.matches.count else { return nil }
            func ref(_ slot: PlacementSlot) -> Ref {
                switch slot {
                case .seed(let position): return .seed(position)
                case .winner(let index): return .winner(numbers[index] ?? 0)
                case .loser(let index): return .loser(numbers[index] ?? 0)
                }
            }
            for spec in bracket.matches {
                guard let number = numbers[spec.index] else { return nil }
                let count = spec.positions.count
                let upper = (count + 1) / 2
                let first = spec.positions.lowerBound
                drafts.append(
                    Draft(
                        match: saved[number - 1],
                        number: number,
                        round: spec.round,
                        positions: spec.positions,
                        home: ref(spec.home),
                        away: ref(spec.away),
                        winnerDestination: destination(first...(first + upper - 1)),
                        loserDestination: destination((first + upper)...spec.positions.upperBound)
                    )
                )
            }
            leafDrafts = bracket.leaves.map { LeafDraft(firstPosition: $0.firstPosition, slots: $0.slots.map(ref)) }
            for round in Set(drafts.map(\.round)) {
                let ranges = Set(drafts.filter { $0.round == round }.compactMap(\.positions).map { [$0.lowerBound, $0.upperBound] })
                let sizes = Set(ranges.map { $0[1] - $0[0] + 1 })
                let subtitle: String?
                if sizes.count == 1, let size = sizes.first {
                    subtitle = "\(sdaGroups(ranges.count)) de \(size) puestos"
                } else {
                    subtitle = "\(sdaGroups(ranges.count)) de puestos"
                }
                columnTitles[round] = ("Ronda \(round)", subtitle)
            }
        } else {
            let stages = KnockoutBracketResolver.stages(in: plan.savedSchedule)
            let matchNumber = Dictionary(uniqueKeysWithValues: saved.enumerated().map { ($0.element.id, $0.offset + 1) })
            func ref(_ raw: String) -> Ref {
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.hasPrefix(winnerPrefix), let number = Int(text.dropFirst(winnerPrefix.count)) { return .winner(number) }
                if text.hasPrefix("Clasificado ") { return .qualifier(text) }
                return .team(raw)
            }
            for stage in stages {
                let isLast = stage.id == stages.count - 1
                let next = stages.indices.contains(stage.id + 1) ? stages[stage.id + 1].title : nil
                columnTitles[stage.id + 1] = (stage.title, nil)
                for match in stage.matches {
                    guard let number = matchNumber[match.id] else { return nil }
                    drafts.append(
                        Draft(
                            match: match,
                            number: number,
                            round: stage.id + 1,
                            positions: nil,
                            home: ref(match.homeTeam),
                            away: ref(match.awayTeam),
                            winnerDestination: isLast ? "campeón" : "pasa a \(next ?? "la siguiente ronda")",
                            loserDestination: isLast ? "subcampeón" : "queda eliminado"
                        )
                    )
                }
            }
            if let final = drafts.max(by: { $0.number < $1.number }) {
                leafDrafts = [
                    LeafDraft(firstPosition: 1, slots: [.winner(final.number)]),
                    LeafDraft(firstPosition: 2, slots: [.loser(final.number)])
                ]
            }
        }
        guard !drafts.isEmpty else { return nil }

        // Cuadro abierto: ya se conocen quiénes llegan desde la liguilla o los grupos.
        let isOpen: Bool
        switch plan.format {
        case .leaguePlacement: isOpen = plan.placementLeagueIsClosed
        case .groupStageKnockout: isOpen = plan.groupStageIsComplete
        default: isOpen = true
        }

        let slotByID = Dictionary(plan.slots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let teamIDByName = Dictionary(plan.teams.map { ($0.name, $0.id) }, uniquingKeysWith: { first, _ in first })
        let teamNames = Set(plan.teamNames)
        let ranking = plan.placementStandings.map(\.teamName)
        let rounds = Array(Set(drafts.map(\.round))).sorted()
        let firstRound = rounds.first ?? 1
        let roundByNumber = Dictionary(drafts.map { ($0.number, $0.round) }, uniquingKeysWith: { first, _ in first })

        // Orden dentro de cada columna.
        var nodes: [BracketNode] = []
        for (column, round) in rounds.enumerated() {
            let ordered = drafts.filter { $0.round == round }.sorted {
                (($0.positions?.lowerBound ?? 0), $0.number) < (($1.positions?.lowerBound ?? 0), $1.number)
            }
            for (row, draft) in ordered.enumerated() {
                let slot = slotByID[draft.match.id]
                let resolvedHome = slot?.match.homeTeam ?? draft.match.homeTeam
                let resolvedAway = slot?.match.awayTeam ?? draft.match.awayTeam
                let score = slot.flatMap { ScheduleAnalytics.result(for: $0, tournament: plan) }
                let decisive = score.map { !$0.isDraw } ?? false

                func side(_ ref: Ref, resolved: String, score: Int?, wins: Bool) -> BracketSide {
                    var label: String
                    var name: String?
                    var direct = false
                    switch ref {
                    case .team(let team):
                        label = team; name = teamNames.contains(team) ? team : nil
                        direct = column > 0
                    case .seed(let position):
                        label = "\(position)º liguilla"
                        if isOpen, teamNames.contains(resolved) { name = resolved }
                        direct = round > firstRound
                    case .qualifier(let raw):
                        label = qualifierLabel(raw)
                        if isOpen, teamNames.contains(resolved) { name = resolved }
                        direct = round > firstRound
                    case .winner(let number):
                        label = "Gana P\(number)"
                        if teamNames.contains(resolved) { name = resolved }
                        // Salta una ronda: esa pareja pasó directa.
                        direct = round - (roundByNumber[number] ?? round) > 1
                    case .loser(let number):
                        label = "Pierde P\(number)"
                        if teamNames.contains(resolved) { name = resolved }
                        direct = round - (roundByNumber[number] ?? round) > 1
                    }
                    if let name { label = name }
                    return BracketSide(
                        label: label,
                        teamID: name.flatMap { teamIDByName[$0] },
                        teamName: name,
                        score: score,
                        isWinner: wins && name != nil,
                        isDirectPass: direct
                    )
                }

                let home = side(
                    draft.home, resolved: resolvedHome, score: score?.homeScore,
                    wins: decisive && score?.winningSide == .home
                )
                let away = side(
                    draft.away, resolved: resolvedAway, score: score?.awayScore,
                    wins: decisive && score?.winningSide == .away
                )
                // Sin los dos nombres no hay resultado que enseñar.
                var shownHome = home
                var shownAway = away
                if !home.isResolved || !away.isResolved {
                    shownHome.score = nil; shownAway.score = nil
                    shownHome.isWinner = false; shownAway.isWinner = false
                }
                let played = decisive && home.isResolved && away.isResolved
                nodes.append(
                    BracketNode(
                        id: draft.match.id,
                        number: draft.number,
                        column: column,
                        round: round,
                        row: row,
                        yRow: Double(row),
                        startsBand: row > 0 && draft.positions != nil && ordered[row - 1].positions != draft.positions,
                        positions: draft.positions,
                        venue: draft.match.venueNumber,
                        home: shownHome,
                        away: shownAway,
                        status: played ? .played : .pending,
                        winnerDestination: draft.winnerDestination,
                        loserDestination: draft.loserDestination
                    )
                )
            }
        }

        // Columna actual: la primera con partidos por jugar, solo si el cuadro está abierto.
        let firstOpenColumn = (0..<rounds.count).first { column in
            nodes.contains { $0.column == column && $0.status != .played }
        }
        let currentColumn = isOpen ? firstOpenColumn : nil
        if let currentColumn {
            for index in nodes.indices where nodes[index].column == currentColumn && nodes[index].status == .pending
                && nodes[index].home.isResolved && nodes[index].away.isResolved {
                nodes[index].status = .inPlay
            }
        }

        let numberToID = Dictionary(nodes.map { ($0.number, $0.id) }, uniquingKeysWith: { first, _ in first })
        let indexByID = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })

        // Conexiones entre partidos.
        var edges: [BracketEdge] = []
        for draft in drafts {
            for (ref, slot) in [(draft.home, BracketSideSlot.home), (draft.away, .away)] {
                switch ref {
                case .winner(let number):
                    if let from = numberToID[number] {
                        edges.append(BracketEdge(from: from, kind: .winner, target: .node(draft.match.id, slot)))
                    }
                case .loser(let number):
                    if let from = numberToID[number] {
                        edges.append(BracketEdge(from: from, kind: .loser, target: .node(draft.match.id, slot)))
                    }
                default: break
                }
            }
        }

        // Alturas: en el cuadro de puestos, filas con un hueco entre bandas; en eliminatoria,
        // cada partido centrado entre los que lo alimentan.
        var totalRows = 0.0
        if isPlacement {
            let bandGap = 0.25
            for round in rounds {
                var offset = 0.0
                for index in nodes.indices where nodes[index].round == round {
                    if nodes[index].startsBand { offset += bandGap }
                    nodes[index].yRow = Double(nodes[index].row) + offset
                    totalRows = max(totalRows, nodes[index].yRow + 1)
                }
            }
        } else {
            for column in 0..<rounds.count {
                var previous = -1.0
                for index in nodes.indices where nodes[index].column == column {
                    let parents = edges.compactMap { edge -> Double? in
                        guard case .node(let target, _) = edge.target, target == nodes[index].id,
                              let from = indexByID[edge.from] else { return nil }
                        return nodes[from].yRow
                    }
                    var y = parents.isEmpty ? Double(nodes[index].row) : parents.reduce(0, +) / Double(parents.count)
                    y = max(y, previous + 1)
                    nodes[index].yRow = y
                    previous = y
                    totalRows = max(totalRows, y + 1)
                }
            }
        }

        // Puestos finales.
        func name(of ref: Ref) -> String? {
            switch ref {
            case .winner(let number): return numberToID[number].flatMap { id in nodes.first { $0.id == id }?.winnerTeamName }
            case .loser(let number): return numberToID[number].flatMap { id in nodes.first { $0.id == id }?.loserTeamName }
            case .seed(let position):
                return isOpen && ranking.indices.contains(position - 1) ? ranking[position - 1] : nil
            case .team(let team): return teamNames.contains(team) ? team : nil
            case .qualifier: return nil
            }
        }
        let leaguePosition = Dictionary(ranking.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        var leaves: [BracketLeaf] = []
        for draft in leafDrafts {
            var sources: [BracketLeafSource] = []
            for slot in draft.slots {
                switch slot {
                case .winner(let number): if let id = numberToID[number] { sources.append(BracketLeafSource(nodeID: id, kind: .winner)) }
                case .loser(let number): if let id = numberToID[number] { sources.append(BracketLeafSource(nodeID: id, kind: .loser)) }
                default: break
                }
            }
            let names = draft.slots.compactMap(name(of:)).sorted {
                (leaguePosition[$0] ?? .max) < (leaguePosition[$1] ?? .max)
            }
            for source in sources {
                edges.append(BracketEdge(from: source.nodeID, kind: source.kind, target: .leaf(draft.firstPosition)))
            }
            leaves.append(
                BracketLeaf(
                    id: draft.firstPosition,
                    positions: draft.firstPosition...(draft.firstPosition + draft.slots.count - 1),
                    teamNames: names,
                    teamIDs: names.compactMap { teamIDByName[$0] },
                    slotCount: draft.slots.count,
                    sources: sources
                )
            )
        }
        leaves.sort { $0.id < $1.id }

        var finalPositions: [String: Int] = [:]
        if let table = plan.placementFinalTable {
            for row in table { finalPositions[row.teamName] = row.position }
        } else {
            for leaf in leaves where leaf.slotCount == 1 && leaf.isComplete {
                finalPositions[leaf.teamNames[0]] = leaf.positions.lowerBound
            }
        }

        // Dónde quedó cada pareja en la liguilla o en su grupo.
        var notes: [String: String] = [:]
        if !plan.savedResults.isEmpty {
            if isPlacement {
                for (index, team) in ranking.enumerated() {
                    if let id = teamIDByName[team] { notes[id] = "\(index + 1)º en la liguilla" }
                }
            } else if plan.format == .groupStageKnockout {
                for group in plan.groupStandings {
                    for (index, standing) in group.standings.enumerated() {
                        if let id = teamIDByName[standing.teamName] { notes[id] = "\(index + 1)º en \(group.name)" }
                    }
                }
            }
        }

        let columns: [BracketColumn] = rounds.enumerated().map { column, round in
            let columnNodes = nodes.filter { $0.column == column }
            let state: BracketColumn.State
            if columnNodes.allSatisfy({ $0.status == .played }) {
                state = .done
            } else if column == currentColumn {
                state = .current
            } else {
                state = .upcoming
            }
            return BracketColumn(
                id: column,
                title: columnTitles[round]?.title ?? "Ronda \(round)",
                subtitle: columnTitles[round]?.subtitle,
                state: state,
                nodeIDs: columnNodes.map(\.id)
            )
        }

        return BracketTreeLayout(
            columns: columns,
            nodes: nodes,
            edges: edges,
            leaves: leaves,
            finalColumnTitle: isPlacement ? "Puesto final" : "Podio",
            finalColumnSubtitle: isPlacement ? "Nadie queda eliminado" : nil,
            currentColumn: currentColumn,
            totalRows: totalRows,
            isPlacement: isPlacement,
            isOpen: isOpen,
            teamNamesByID: Dictionary(plan.teams.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }),
            leagueNotes: notes,
            finalPositionsByName: finalPositions
        )
    }

    /// «puesto 1º» si es uno solo; «sigue por 1–4» si es un grupo.
    private static func destination(_ range: ClosedRange<Int>) -> String {
        range.count == 1 ? "puesto \(range.lowerBound)º" : "sigue por \(range.lowerBound)–\(range.upperBound)"
    }

    private static func sdaGroups(_ count: Int) -> String {
        count == 1 ? "1 grupo" : "\(count) grupos"
    }

    /// «Clasificado 1 Grupo A» → «1º Grupo A»; «Clasificado 3» → «3º liguilla».
    private static func qualifierLabel(_ raw: String) -> String {
        let parts = raw.split(separator: " ")
        guard parts.count >= 2, let position = Int(parts[1]) else { return raw }
        if parts.count >= 4, parts[2] == "Grupo" { return "\(position)º Grupo \(parts[3])" }
        return "\(position)º liguilla"
    }
}
