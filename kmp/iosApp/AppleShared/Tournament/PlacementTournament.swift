import Foundation

// Modalidad «Liguilla + puestos»: una liguilla con tiempo fijo y un cuadro donde nadie queda
// eliminado. Quien gana sigue por los puestos de arriba y quien pierde por los de abajo.
// Valor puro: sin vistas ni base de datos.

// MARK: - Datos de entrada y cálculo

struct PlacementPlanInput: Equatable, Sendable {
    /// Por debajo de esto no se puede repartir una liguilla con cuadro.
    static let minimumTeams = 4
    /// Partidos más cortos que esto no se sugieren.
    static let minimumMatchMinutes = 4
    /// Partidos de liguilla que debe jugar como mínimo cada pareja.
    static let minimumLeagueMatchesPerTeam = 2

    var teamCount: Int
    var matchMinutes: Int
    var transitionMinutes: Int
    var totalMinutes: Int
    var venueCount: Int
    /// Rondas del cuadro. `nil` son todas las necesarias para ordenar cada puesto.
    var placementRounds: Int?
}

struct PlacementPlanCalculation: Equatable, Sendable {
    var fits: Bool
    var roundMinutes: Int
    var activeVenues: Int
    var restingPerRound: Int
    var leagueRounds: Int
    var minimumLeagueRounds: Int
    var leagueMatches: Int
    var leagueMatchesPerTeam: ClosedRange<Int>
    var placementRoundsUsed: Int
    var placementRoundsAvailable: Int
    var placementBatches: Int
    var placementMatches: Int
    /// Minutos que se usan si cabe; si no cabe, los que harían falta como mínimo.
    var neededMinutes: Int
}

enum PlacementPlanChange: Equatable, Sendable {
    case totalMinutes(Int)
    case matchMinutes(Int)
    case placementRounds(Int)
    case venueCount(Int)
}

struct PlacementSuggestion: Equatable, Identifiable, Sendable {
    var title: String
    var detail: String
    var change: PlacementPlanChange

    var id: String { title }
}

enum PlacementPlanner {
    static func calculate(_ input: PlacementPlanInput) -> PlacementPlanCalculation? {
        guard input.teamCount >= PlacementPlanInput.minimumTeams,
              input.venueCount > 0,
              input.matchMinutes > 0
        else { return nil }

        let roundMinutes = input.matchMinutes + max(0, input.transitionMinutes)
        let activeVenues = min(input.venueCount, input.teamCount / 2)
        let bracket = PlacementBracket(teamCount: input.teamCount, maxRounds: input.placementRounds)
        let batches = bracket.batches(venueCount: input.venueCount).count
        // El último partido no necesita cambio detrás.
        let availableRounds = (input.totalMinutes + max(0, input.transitionMinutes)) / roundMinutes
        let minimumNeeded = input.teamCount * PlacementPlanInput.minimumLeagueMatchesPerTeam / 2
        let minimumLeagueRounds = Int((Double(minimumNeeded) / Double(activeVenues)).rounded(.up))
        let leagueRounds = availableRounds - batches
        let fits = leagueRounds >= minimumLeagueRounds
        let usedRounds = (fits ? leagueRounds : minimumLeagueRounds) + batches
        let leagueMatches = fits ? leagueRounds * activeVenues : 0
        let appearances = leagueMatches * 2

        return PlacementPlanCalculation(
            fits: fits,
            roundMinutes: roundMinutes,
            activeVenues: activeVenues,
            restingPerRound: input.teamCount - 2 * activeVenues,
            leagueRounds: fits ? leagueRounds : minimumLeagueRounds,
            minimumLeagueRounds: minimumLeagueRounds,
            leagueMatches: leagueMatches,
            leagueMatchesPerTeam: (appearances / input.teamCount)...Int((Double(appearances) / Double(input.teamCount)).rounded(.up)),
            placementRoundsUsed: bracket.roundCount,
            placementRoundsAvailable: PlacementBracket(teamCount: input.teamCount, maxRounds: nil).roundCount,
            placementBatches: batches,
            placementMatches: bracket.matches.count,
            neededMinutes: usedRounds * roundMinutes - max(0, input.transitionMinutes)
        )
    }

    /// Cambios que, aplicados de uno en uno, hacen que el torneo quepa.
    /// Nunca se propone cambiar las parejas: son el alumnado que hay.
    static func suggestions(for input: PlacementPlanInput) -> [PlacementSuggestion] {
        guard let calculation = calculate(input), !calculation.fits else { return [] }
        var result: [PlacementSuggestion] = []

        let rounded = Int((Double(calculation.neededMinutes) / 5).rounded(.up)) * 5
        result.append(
            PlacementSuggestion(
                title: "Ampliar a \(durationText(rounded))",
                detail: "Se juega todo lo previsto.",
                change: .totalMinutes(rounded)
            )
        )

        if input.matchMinutes > PlacementPlanInput.minimumMatchMinutes {
            for minutes in stride(from: input.matchMinutes - 1, through: PlacementPlanInput.minimumMatchMinutes, by: -1) {
                var attempt = input
                attempt.matchMinutes = minutes
                if calculate(attempt)?.fits == true {
                    result.append(
                        PlacementSuggestion(
                            title: "Partidos de \(minutes) min",
                            detail: "Mismo tiempo total, partidos más cortos.",
                            change: .matchMinutes(minutes)
                        )
                    )
                    break
                }
            }
        }

        if calculation.placementRoundsUsed > 1 {
            for rounds in stride(from: calculation.placementRoundsUsed - 1, through: 1, by: -1) {
                var attempt = input
                attempt.placementRounds = rounds
                if calculate(attempt)?.fits == true {
                    let size = Int((Double(input.teamCount) / pow(2, Double(rounds))).rounded(.up))
                    result.append(
                        PlacementSuggestion(
                            title: rounds == 1 ? "Cuadro de 1 ronda" : "Cuadro de \(rounds) rondas",
                            detail: "Quedan grupos de unas \(size) parejas y la liguilla decide el orden dentro de cada grupo.",
                            change: .placementRounds(rounds)
                        )
                    )
                    break
                }
            }
        }

        if calculation.activeVenues < input.teamCount / 2, input.venueCount < 12 {
            for venues in (input.venueCount + 1)...12 {
                var attempt = input
                attempt.venueCount = venues
                if calculate(attempt)?.fits == true {
                    result.append(
                        PlacementSuggestion(
                            title: "Usar \(venues) pistas",
                            detail: "Solo si tienes esas pistas libres.",
                            change: .venueCount(venues)
                        )
                    )
                    break
                }
            }
        }
        return result
    }

    static func durationText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}

extension PlacementPlanInput {
    mutating func apply(_ change: PlacementPlanChange) {
        switch change {
        case .totalMinutes(let value): totalMinutes = value
        case .matchMinutes(let value): matchMinutes = value
        case .placementRounds(let value): placementRounds = value
        case .venueCount(let value): venueCount = value
        }
    }
}

// MARK: - Cuadro de puestos

enum PlacementSlot: Hashable, Sendable {
    /// Puesto en la liguilla, empezando en 1.
    case seed(Int)
    /// Ganador o perdedor de un partido del cuadro, por su índice en `matches`.
    case winner(Int)
    case loser(Int)
}

struct PlacementMatchSpec: Hashable, Sendable {
    var index: Int
    var round: Int
    var positions: ClosedRange<Int>
    var home: PlacementSlot
    var away: PlacementSlot

    var dependencies: [Int] {
        [home, away].compactMap { slot in
            switch slot {
            case .seed: return nil
            case .winner(let index), .loser(let index): return index
            }
        }
    }
}

/// Pareja que pasa directa en una ronda porque su grupo de puestos es impar.
struct PlacementBye: Hashable, Sendable {
    var round: Int
    var positions: ClosedRange<Int>
    var slot: PlacementSlot
}

/// Grupo de puestos al que se llega al acabar el cuadro. Con cuadro completo tiene una sola
/// pareja; con cuadro corto, la liguilla decide el orden dentro del grupo.
struct PlacementLeaf: Hashable, Sendable {
    var firstPosition: Int
    var slots: [PlacementSlot]
}

/// Árbol fijo del cuadro: se decide entero al crear el calendario.
/// En cada grupo juega el mejor hueco contra el peor. Si el grupo es impar, pasa directo el primer
/// hueco por el que aún no haya podido pasar una pareja que ya pasó directa. Ganadores arriba,
/// perdedores abajo, hasta que no queden rondas o el grupo sea de una pareja.
struct PlacementBracket: Hashable, Sendable {
    private(set) var matches: [PlacementMatchSpec] = []
    private(set) var byes: [PlacementBye] = []
    private(set) var leaves: [PlacementLeaf] = []
    let roundCount: Int

    private struct Entry {
        var slot: PlacementSlot
        /// `true` si por este hueco puede llegar una pareja que ya pasó directa.
        var mayHaveHadBye: Bool
    }

    init(teamCount: Int, maxRounds: Int?) {
        var deepest = 0
        var builtMatches: [PlacementMatchSpec] = []
        var builtByes: [PlacementBye] = []
        var builtLeaves: [PlacementLeaf] = []

        func split(_ entries: [Entry], from: Int, round: Int) {
            if entries.count < 2 || (maxRounds.map { round > $0 } ?? false) {
                if !entries.isEmpty {
                    builtLeaves.append(PlacementLeaf(firstPosition: from, slots: entries.map(\.slot)))
                }
                return
            }
            deepest = max(deepest, round)
            let positions = from...(from + entries.count - 1)
            var upper: [Entry] = []
            var lower: [Entry] = []
            var rest = entries
            if entries.count % 2 == 1 {
                let chosen = entries.firstIndex(where: { !$0.mayHaveHadBye }) ?? 0
                builtByes.append(PlacementBye(round: round, positions: positions, slot: entries[chosen].slot))
                var passing = entries[chosen]
                passing.mayHaveHadBye = true
                upper.append(passing)
                rest.remove(at: chosen)
            }
            for offset in 0..<(rest.count / 2) {
                let home = rest[offset]
                let away = rest[rest.count - 1 - offset]
                let index = builtMatches.count
                builtMatches.append(
                    PlacementMatchSpec(index: index, round: round, positions: positions, home: home.slot, away: away.slot)
                )
                let tainted = home.mayHaveHadBye || away.mayHaveHadBye
                upper.append(Entry(slot: .winner(index), mayHaveHadBye: tainted))
                lower.append(Entry(slot: .loser(index), mayHaveHadBye: tainted))
            }
            split(upper, from: from, round: round + 1)
            split(lower, from: from + upper.count, round: round + 1)
        }

        if teamCount > 0 {
            split(
                (1...teamCount).map { Entry(slot: .seed($0), mayHaveHadBye: false) },
                from: 1,
                round: 1
            )
        }
        matches = builtMatches
        byes = builtByes
        leaves = builtLeaves.sorted { $0.firstPosition < $1.firstPosition }
        roundCount = deepest
    }

    /// Reparte los partidos en tandas: un partido entra cuando ya se jugaron los que le dan sus parejas.
    func batches(venueCount: Int) -> [[PlacementMatchSpec]] {
        guard venueCount > 0 else { return [] }
        var done = Set<Int>()
        var pending = matches
        var result: [[PlacementMatchSpec]] = []
        while !pending.isEmpty {
            let ready = Array(
                pending
                    .filter { $0.dependencies.allSatisfy(done.contains) }
                    .sorted { ($0.round, $0.index) < ($1.round, $1.index) }
                    .prefix(venueCount)
            )
            guard !ready.isEmpty else { break }
            done.formUnion(ready.map(\.index))
            let taken = Set(ready.map(\.index))
            pending.removeAll { taken.contains($0.index) }
            result.append(ready)
        }
        return result
    }
}

// MARK: - Liguilla

/// Reparte la liguilla en tandas: descansa quien menos ha descansado (y, a igualdad, quien más ha
/// jugado) y se evita repetir rival mientras se pueda.
enum PlacementLeagueScheduler {
    struct Round: Equatable {
        var resting: [Int]
        var pairs: [[Int]]
    }

    static func rounds(teamCount: Int, venueCount: Int, roundCount: Int) -> [Round] {
        let active = min(venueCount, teamCount / 2)
        guard active > 0, roundCount > 0 else { return [] }
        var played = Array(repeating: 0, count: teamCount)
        var rested = Array(repeating: 0, count: teamCount)
        var met = Array(repeating: Array(repeating: 0, count: teamCount), count: teamCount)
        var rounds: [Round] = []

        for _ in 0..<roundCount {
            let order = (0..<teamCount).sorted { a, b in
                if rested[a] != rested[b] { return rested[a] < rested[b] }
                if played[a] != played[b] { return played[a] > played[b] }
                return a > b
            }
            let restingCount = teamCount - 2 * active
            let resting = Array(order.prefix(restingCount))
            let playing = order.dropFirst(restingCount).sorted()
            resting.forEach { rested[$0] += 1 }

            let pairs = bestPairing(playing, met: met)
            for pair in pairs {
                met[pair[0]][pair[1]] += 1
                met[pair[1]][pair[0]] += 1
                played[pair[0]] += 1
                played[pair[1]] += 1
            }
            rounds.append(Round(resting: resting, pairs: pairs))
        }
        return rounds
    }

    /// Busca emparejar a todos sin repetir rival; si no se puede, permite una vez más cada vez.
    private static func bestPairing(_ playing: [Int], met: [[Int]]) -> [[Int]] {
        let lowest = playing.flatMap { a in playing.filter { $0 != a }.map { met[a][$0] } }.min() ?? 0
        let highest = playing.flatMap { a in playing.filter { $0 != a }.map { met[a][$0] } }.max() ?? 0
        for cap in lowest...highest {
            var steps = 0
            if let found = search(playing, cap: cap, met: met, steps: &steps) {
                return found
            }
        }
        // Red de seguridad: en orden, aunque se repita rival.
        return stride(from: 0, to: playing.count - 1, by: 2).map { [playing[$0], playing[$0 + 1]] }
    }

    private static func search(_ left: [Int], cap: Int, met: [[Int]], steps: inout Int) -> [[Int]]? {
        guard let first = left.first else { return [] }
        steps += 1
        if steps > 20_000 { return nil }
        let others = Array(left.dropFirst())
        for candidate in others where met[first][candidate] <= cap {
            let remaining = others.filter { $0 != candidate }
            if let rest = search(remaining, cap: cap, met: met, steps: &steps) {
                return [[first, candidate]] + rest
            }
        }
        return nil
    }
}

// MARK: - Calendario

enum PlacementScheduleGenerator {
    static func generate(teamNames: [String], input: PlacementPlanInput) throws -> [ScheduledRound] {
        guard teamNames.count >= PlacementPlanInput.minimumTeams else {
            throw ScheduleGenerationError.notEnoughTeams
        }
        guard input.venueCount > 0 else { throw ScheduleGenerationError.noVenues }
        guard let calculation = PlacementPlanner.calculate(input), calculation.fits else {
            throw ScheduleGenerationError.notEnoughTime
        }

        let league = PlacementLeagueScheduler.rounds(
            teamCount: teamNames.count,
            venueCount: input.venueCount,
            roundCount: calculation.leagueRounds
        )
        var rounds: [ScheduledRound] = league.enumerated().map { offset, round in
            ScheduledRound(
                number: offset + 1,
                matches: round.pairs.enumerated().map { venue, pair in
                    ScheduledMatch(homeTeam: teamNames[pair[0]], awayTeam: teamNames[pair[1]], venueNumber: venue + 1)
                },
                stage: .groupStage
            )
        }

        let bracket = PlacementBracket(teamCount: teamNames.count, maxRounds: input.placementRounds)
        let batches = bracket.batches(venueCount: input.venueCount)
        let numbers = PlacementResolver.matchNumbers(batches)
        for batch in batches {
            rounds.append(
                ScheduledRound(
                    number: rounds.count + 1,
                    matches: batch.enumerated().map { venue, spec in
                        ScheduledMatch(
                            homeTeam: PlacementResolver.placeholder(spec.home, numbers: numbers),
                            awayTeam: PlacementResolver.placeholder(spec.away, numbers: numbers),
                            venueNumber: venue + 1
                        )
                    },
                    stage: .knockout
                )
            )
        }
        return rounds
    }
}

// MARK: - Clasificación de la liguilla

struct PlacementStandingRow: Equatable, Identifiable, Sendable {
    var teamName: String
    var played = 0
    var wins = 0
    var draws = 0
    var losses = 0
    var pointsFor = 0
    var pointsAgainst = 0

    var id: String { teamName }
    var pointDifference: Int { pointsFor - pointsAgainst }
    /// Porcentaje de victorias: así descansar más no resta. Un empate vale media victoria.
    var winRate: Double {
        played == 0 ? 0 : (Double(wins) + Double(draws) / 2) / Double(played)
    }
}

enum PlacementStandings {
    static func rank(teamNames: [String], results: [MatchResult]) -> [PlacementStandingRow] {
        var rows = Dictionary(uniqueKeysWithValues: teamNames.map { ($0, PlacementStandingRow(teamName: $0)) })
        for result in results {
            guard var home = rows[result.homeTeam], var away = rows[result.awayTeam] else { continue }
            home.played += 1
            away.played += 1
            home.pointsFor += result.homeScore
            home.pointsAgainst += result.awayScore
            away.pointsFor += result.awayScore
            away.pointsAgainst += result.homeScore
            if result.homeScore > result.awayScore {
                home.wins += 1
                away.losses += 1
            } else if result.homeScore < result.awayScore {
                away.wins += 1
                home.losses += 1
            } else {
                home.draws += 1
                away.draws += 1
            }
            rows[result.homeTeam] = home
            rows[result.awayTeam] = away
        }
        return rows.values.sorted { a, b in
            if a.winRate != b.winRate { return a.winRate > b.winRate }
            if a.pointDifference != b.pointDifference { return a.pointDifference > b.pointDifference }
            if a.pointsFor != b.pointsFor { return a.pointsFor > b.pointsFor }
            return a.teamName.localizedStandardCompare(b.teamName) == .orderedAscending
        }
    }
}

// MARK: - Resolver nombres y tabla final

struct PlacementFinalRow: Equatable, Identifiable, Sendable {
    var position: Int
    var teamName: String
    /// Puesto con el que acabó la liguilla.
    var leaguePosition: Int

    var id: Int { position }
}

enum PlacementResolver {
    private static let seedPrefix = "Clasificado "
    private static let winnerPrefix = "Ganador P"
    private static let loserPrefix = "Perdedor P"

    /// Número de cada partido (índice del árbol → «P7»), en el orden en que se juegan.
    static func matchNumbers(_ batches: [[PlacementMatchSpec]]) -> [Int: Int] {
        var numbers: [Int: Int] = [:]
        for spec in batches.flatMap({ $0 }) {
            numbers[spec.index] = numbers.count + 1
        }
        return numbers
    }

    static func placeholder(_ slot: PlacementSlot, numbers: [Int: Int]) -> String {
        switch slot {
        case .seed(let position): return "\(seedPrefix)\(position)"
        case .winner(let index): return "\(winnerPrefix)\(numbers[index] ?? 0)"
        case .loser(let index): return "\(loserPrefix)\(numbers[index] ?? 0)"
        }
    }

    /// Texto para enseñar un hueco cuando aún no se conoce a la pareja.
    static func displayName(forPlaceholder name: String) -> String {
        if name.hasPrefix(seedPrefix) {
            return "Puesto \(name.dropFirst(seedPrefix.count)) en liguilla"
        }
        return name
    }

    /// Nombres reales de cada partido del cuadro según los resultados guardados.
    static func resolvedNames(
        rounds: [ScheduledRound],
        ranking: [String],
        results: [KnockoutMatchResult]
    ) -> [UUID: (home: String, away: String)] {
        let matches = rounds.filter { $0.stage == .knockout }.flatMap(\.matches)
        let resultByID = Dictionary(results.map { ($0.matchID, $0) }, uniquingKeysWith: { _, last in last })
        var resolved: [UUID: (home: String, away: String)] = [:]

        func name(_ participant: String) -> String {
            if participant.hasPrefix(seedPrefix), let position = Int(participant.dropFirst(seedPrefix.count)) {
                return ranking.indices.contains(position - 1) ? ranking[position - 1] : participant
            }
            let isWinner = participant.hasPrefix(winnerPrefix)
            let isLoser = participant.hasPrefix(loserPrefix)
            guard isWinner || isLoser,
                  let number = Int(participant.dropFirst((isWinner ? winnerPrefix : loserPrefix).count)),
                  matches.indices.contains(number - 1),
                  let result = resultByID[matches[number - 1].id],
                  let winner = result.winner
            else { return participant }
            if isWinner { return winner }
            return winner == result.homeTeam ? result.awayTeam : result.homeTeam
        }

        for match in matches {
            resolved[match.id] = (name(match.homeTeam), name(match.awayTeam))
        }
        return resolved
    }
}

// MARK: - En el plan

extension TournamentPlan {
    var placementInput: PlacementPlanInput {
        PlacementPlanInput(
            teamCount: teamCount,
            matchMinutes: matchDurationMinutes,
            transitionMinutes: transitionMinutes,
            totalMinutes: totalTimeMinutes ?? 60,
            venueCount: venueCount,
            placementRounds: placementRounds
        )
    }

    /// Aplica una sugerencia o un ajuste a la configuración del torneo.
    mutating func applyPlacementChange(_ change: PlacementPlanChange) {
        switch change {
        case .totalMinutes(let value): totalTimeMinutes = value
        case .matchMinutes(let value): matchDurationMinutes = value
        case .placementRounds(let value): placementRounds = value
        case .venueCount(let value): venueCount = value
        }
    }

    /// Calendario según el formato. Es el único sitio que sabe qué pide cada uno.
    func generatedRounds() throws -> [ScheduledRound] {
        if format == .leaguePlacement {
            return try PlacementScheduleGenerator.generate(teamNames: teamNames, input: placementInput)
        }
        return try TournamentScheduleGenerator.generate(
            format: format,
            teamNames: teamNames,
            venueCount: venueCount,
            groupCount: format == .groupStageKnockout ? groupCount : nil,
            qualifiedTeamsPerGroup: qualifiedTeamsPerGroup
        )
    }

    /// Clasificación de la liguilla, con los criterios de esta modalidad.
    var placementStandings: [PlacementStandingRow] {
        PlacementStandings.rank(teamNames: teamNames, results: savedResults)
    }

    /// Árbol fijo del cuadro de puestos. Se expone para dibujarlo (`BracketTreeLayout`); no cambia el calendario.
    var placementBracket: PlacementBracket {
        PlacementBracket(teamCount: teamCount, maxRounds: placementRounds)
    }

    /// Partidos del cuadro agrupados por ronda y grupo de puestos, para la vista del cuadro.
    var placementStages: [PlacementStage] {
        let saved = savedSchedule.filter { $0.stage == .knockout }.flatMap(\.matches)
        let bracket = placementBracket
        let batches = bracket.batches(venueCount: venueCount)
        let numbers = PlacementResolver.matchNumbers(batches)
        var stages: [PlacementStage] = []
        for round in 1...max(bracket.roundCount, 1) {
            let specs = bracket.matches.filter { $0.round == round }
            guard !specs.isEmpty else { continue }
            let ranges = specs.map(\.positions).reduce(into: [ClosedRange<Int>]()) { list, range in
                if !list.contains(range) { list.append(range) }
            }.sorted { $0.lowerBound < $1.lowerBound }
            let groups = ranges.map { range in
                PlacementStage.Group(
                    positions: range,
                    matchIDs: specs.filter { $0.positions == range }.compactMap { spec in
                        numbers[spec.index].flatMap { saved.indices.contains($0 - 1) ? saved[$0 - 1].id : nil }
                    },
                    byeName: bracket.byes.first { $0.round == round && $0.positions == range }.flatMap {
                        placementName(for: $0.slot, numbers: numbers, saved: saved)
                    }
                )
            }
            stages.append(PlacementStage(round: round, groups: groups))
        }
        return stages
    }

    /// Nombre de la pareja de un hueco; `nil` si aún no se conoce.
    private func placementName(
        for slot: PlacementSlot,
        numbers: [Int: Int],
        saved: [ScheduledMatch]
    ) -> String? {
        let ranking = placementStandings.map(\.teamName)
        switch slot {
        case .seed(let position):
            return placementLeagueIsClosed && ranking.indices.contains(position - 1) ? ranking[position - 1] : nil
        case .winner(let index), .loser(let index):
            guard let number = numbers[index], saved.indices.contains(number - 1),
                  let result = savedKnockoutResults.first(where: { $0.matchID == saved[number - 1].id }),
                  let winner = result.winner
            else { return nil }
            if case .winner = slot { return winner }
            return winner == result.homeTeam ? result.awayTeam : result.homeTeam
        }
    }

    /// Tabla final. Solo existe cuando se han jugado todos los partidos del cuadro.
    var placementFinalTable: [PlacementFinalRow]? {
        guard format == .leaguePlacement, !savedSchedule.isEmpty, placementLeagueIsClosed else { return nil }
        let saved = savedSchedule.filter { $0.stage == .knockout }.flatMap(\.matches)
        let decided = saved.allSatisfy { match in
            savedKnockoutResults.contains { $0.matchID == match.id && $0.isDecisive }
        }
        guard decided else { return nil }

        let bracket = placementBracket
        let numbers = PlacementResolver.matchNumbers(bracket.batches(venueCount: venueCount))
        let ranking = placementStandings.map(\.teamName)
        let leaguePosition = Dictionary(
            ranking.enumerated().map { ($1, $0 + 1) },
            uniquingKeysWith: { first, _ in first }
        )
        var rows: [PlacementFinalRow] = []
        for leaf in bracket.leaves {
            let names = leaf.slots.compactMap { placementName(for: $0, numbers: numbers, saved: saved) }
            guard names.count == leaf.slots.count else { return nil }
            // Dentro de un grupo sin cuadro que lo ordene, decide la liguilla.
            let ordered = names.sorted { (leaguePosition[$0] ?? .max) < (leaguePosition[$1] ?? .max) }
            for (offset, name) in ordered.enumerated() {
                rows.append(
                    PlacementFinalRow(
                        position: leaf.firstPosition + offset,
                        teamName: name,
                        leaguePosition: leaguePosition[name] ?? 0
                    )
                )
            }
        }
        return rows
    }

    /// Partidos de liguilla que aún no tienen resultado.
    var pendingLeagueMatchCount: Int {
        let leagueIDs = savedSchedule.filter { $0.stage == .groupStage }.flatMap(\.matches).map(\.id)
        let played = Set(savedResults.compactMap(\.matchID))
        return leagueIDs.filter { !played.contains($0) }.count
    }

    /// `true` cuando el cuadro ya se puede jugar: liguilla terminada o cerrada a mano.
    var placementLeagueIsClosed: Bool {
        leagueClosedEarly == true || pendingLeagueMatchCount == 0
    }

    /// Cierra la liguilla aunque queden partidos: esos no cuentan y se abre el cuadro.
    mutating func closeLeagueEarly() {
        guard format == .leaguePlacement, !savedResults.isEmpty else { return }
        leagueClosedEarly = true
    }

    /// Deshace el cierre. Solo mientras no se haya jugado nada del cuadro.
    mutating func reopenLeague() {
        guard savedKnockoutResults.isEmpty else { return }
        leagueClosedEarly = nil
    }
}

struct PlacementStage: Equatable, Identifiable {
    struct Group: Equatable, Identifiable {
        var positions: ClosedRange<Int>
        var matchIDs: [UUID]
        var byeName: String?

        var id: Int { positions.lowerBound }
    }

    var round: Int
    var groups: [Group]

    var id: Int { round }
}
