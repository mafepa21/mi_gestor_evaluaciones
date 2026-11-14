import Foundation

// Fases de un torneo y su progreso, como valor puro: Liguilla o Grupos → Cuadro → Podio.
// En eliminatoria pura cada ronda es una fase. Liga y Rotaciones solo tienen Liga → Podio.

enum TournamentPhaseKind: Hashable, Sendable {
    /// Liga, liguilla o fase de grupos.
    case league
    /// Cuadro de puestos o eliminatorias.
    case bracket
    /// Una ronda de una eliminatoria pura (empieza en 1).
    case round(Int)
    case podium
}

struct TournamentPhase: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable { case done, current, upcoming }

    let kind: TournamentPhaseKind
    /// Posición en la línea, empezando en 1.
    let number: Int
    let title: String
    let detail: String
    let played: Int
    let total: Int
    var state: State

    var id: TournamentPhaseKind { kind }
    var isCurrent: Bool { state == .current }
    var isDone: Bool { state == .done }

    /// Progreso de 0 a 1. El podio no tiene barra.
    var progress: Double {
        if kind == .podium { return state == .done ? 1 : 0 }
        return total > 0 ? min(1, Double(played) / Double(total)) : (state == .done ? 1 : 0)
    }
}

struct TournamentPhaseTimeline: Equatable, Sendable {
    var phases: [TournamentPhase]
    /// Fase en la que estamos. Siempre existe.
    var currentKind: TournamentPhaseKind
    /// Partidos de liguilla o grupos jugados y totales.
    var leaguePlayed: Int
    var leagueTotal: Int
    /// Partidos del cuadro jugados y totales.
    var bracketPlayed: Int
    var bracketTotal: Int
    /// Ronda en curso (tanda de liguilla o ronda del cuadro) y rondas totales de esa fase.
    var currentRound: Int?
    var currentRoundCount: Int?

    var current: TournamentPhase? { phases.first { $0.kind == currentKind } }

    func phase(_ kind: TournamentPhaseKind) -> TournamentPhase? { phases.first { $0.kind == kind } }

    /// `true` si ya se ha jugado algo.
    var hasStarted: Bool { leaguePlayed + bracketPlayed > 0 }

    static func make(plan: TournamentPlan) -> TournamentPhaseTimeline {
        let slots = plan.slots
        let done = ScheduleAnalytics.completedMatchIDs(tournament: plan, slots: slots)
        let hasBracket = plan.format.includesKnockoutPhase

        // Partidos de liguilla / grupos / liga y partidos del cuadro.
        let leagueRounds = plan.savedSchedule.filter { !(hasBracket && ($0.stage == .knockout || plan.format == .knockout)) }
        let bracketRounds = hasBracket ? plan.savedSchedule.filter { $0.stage == .knockout || plan.format == .knockout } : []
        let leagueIDs = leagueRounds.flatMap(\.matches).map(\.id)
        let bracketIDs = bracketRounds.flatMap(\.matches).map(\.id)
        let leaguePlayed = leagueIDs.filter(done.contains).count
        var leagueTotal = leagueIDs.count
        // Liguilla cerrada a mano: los partidos que no se jugaron ya no cuentan.
        let closedEarly = plan.format == .leaguePlacement && plan.leagueClosedEarly == true
        if closedEarly { leagueTotal = leaguePlayed }
        let bracketPlayed = bracketIDs.filter(done.contains).count
        let bracketTotal = bracketIDs.count

        let leagueDone: Bool
        switch plan.format {
        case .leaguePlacement: leagueDone = leagueTotal > 0 && plan.placementLeagueIsClosed
        case .groupStageKnockout: leagueDone = leagueTotal > 0 && plan.groupStageIsComplete
        default: leagueDone = leagueTotal > 0 && leaguePlayed == leagueTotal
        }
        let bracketDone = bracketTotal > 0 && bracketPlayed == bracketTotal

        func roundInfo(_ rounds: [ScheduledRound]) -> (current: Int, count: Int)? {
            guard !rounds.isEmpty else { return nil }
            let index = rounds.firstIndex { round in round.matches.contains { !done.contains($0.id) } } ?? (rounds.count - 1)
            return (index + 1, rounds.count)
        }

        var phases: [TournamentPhase] = []
        var currentKind: TournamentPhaseKind = .league
        var currentRound: Int?
        var currentRoundCount: Int?

        func phase(
            _ kind: TournamentPhaseKind, _ title: String, _ detail: String,
            played: Int, total: Int, isDone: Bool
        ) -> TournamentPhase {
            TournamentPhase(
                kind: kind, number: phases.count + 1, title: title, detail: detail,
                played: played, total: total, state: isDone ? .done : .upcoming
            )
        }

        func matchesText(_ count: Int) -> String { count == 1 ? "1 partido" : "\(count) partidos" }

        let leagueTitle: String
        switch plan.format {
        case .groupStageKnockout: leagueTitle = "Fase 1 · Grupos"
        case .leaguePlacement: leagueTitle = "Fase 1 · Liguilla"
        case .rotation: leagueTitle = "Rotaciones"
        default: leagueTitle = "Liga"
        }

        if plan.format == .knockout {
            // Cada ronda de la eliminatoria es una fase.
            let stages = KnockoutBracketResolver.stages(in: plan.savedSchedule)
            for stage in stages {
                let ids = stage.matches.map(\.id)
                let played = ids.filter(done.contains).count
                let isDone = !ids.isEmpty && played == ids.count
                let detail = isDone ? "Terminada · \(matchesText(ids.count))"
                    : played == 0 ? "Sin empezar · \(matchesText(ids.count))"
                    : "\(played) de \(ids.count)"
                phases.append(phase(.round(stage.id + 1), "Fase \(stage.id + 1) · \(stage.title)", detail, played: played, total: ids.count, isDone: isDone))
            }
        } else {
            let leagueDetail: String
            if leagueDone {
                leagueDetail = "Terminada · \(matchesText(leagueTotal))"
            } else if leaguePlayed == 0 {
                leagueDetail = "Sin empezar · \(matchesText(leagueTotal))"
            } else if let info = roundInfo(leagueRounds), hasBracket || plan.format == .roundRobin || plan.format == .rotation {
                leagueDetail = "Ronda \(info.current) de \(info.count) · \(leaguePlayed) de \(leagueTotal)"
            } else {
                leagueDetail = "\(leaguePlayed) de \(leagueTotal)"
            }
            phases.append(phase(.league, leagueTitle, leagueDetail, played: leaguePlayed, total: leagueTotal, isDone: leagueDone))

            if hasBracket {
                let bracketTitle = plan.format == .leaguePlacement ? "Fase 2 · Cuadro de puestos" : "Fase 2 · Eliminatorias"
                let layout = BracketTreeLayout.make(plan: plan)
                let rounds = layout?.columns.count ?? 0
                let detail: String
                if bracketDone {
                    detail = "Terminado · \(matchesText(bracketTotal))"
                } else if !leagueDone {
                    detail = plan.format == .leaguePlacement ? "Se abre al acabar la liguilla" : "Se abre al acabar los grupos"
                } else if bracketPlayed == 0 {
                    detail = "Sin empezar · \(matchesText(bracketTotal))"
                } else {
                    let column = (layout?.currentColumn ?? 0) + 1
                    detail = "Ronda \(column) de \(rounds) · \(bracketPlayed) de \(bracketTotal)"
                }
                phases.append(phase(.bracket, bracketTitle, detail, played: bracketPlayed, total: bracketTotal, isDone: bracketDone))
            }
        }

        let finished = hasBracket ? bracketDone : leagueDone
        let podiumTitle = hasBracket ? "Podio" : "Clasificación final"
        let podiumDetail = finished ? "Clasificación final" : (hasBracket ? "Al acabar el cuadro" : "Al acabar la liga")
        var podium = phase(.podium, podiumTitle, podiumDetail, played: finished ? 1 : 0, total: 1, isDone: false)
        podium.state = .upcoming
        phases.append(podium)

        // Fase actual: la primera sin terminar; el podio cuando ya no queda nada.
        if let first = phases.firstIndex(where: { $0.kind != .podium && !$0.isDone }) {
            currentKind = phases[first].kind
        } else {
            currentKind = .podium
        }
        for index in phases.indices {
            let kind = phases[index].kind
            if kind == currentKind {
                phases[index].state = .current
            } else if kind != .podium, phases[index].isDone {
                phases[index].state = .done
            } else {
                phases[index].state = .upcoming
            }
        }
        switch currentKind {
        case .league:
            let info = roundInfo(leagueRounds)
            currentRound = info?.current; currentRoundCount = info?.count
        case .bracket:
            if let layout = BracketTreeLayout.make(plan: plan), let column = layout.currentColumn {
                currentRound = column + 1; currentRoundCount = layout.columns.count
            }
        case .round(let number):
            let stages = KnockoutBracketResolver.stages(in: plan.savedSchedule)
            currentRound = number; currentRoundCount = stages.count
        case .podium:
            break
        }

        return TournamentPhaseTimeline(
            phases: phases,
            currentKind: currentKind,
            leaguePlayed: leaguePlayed,
            leagueTotal: leagueTotal,
            bracketPlayed: bracketPlayed,
            bracketTotal: bracketTotal,
            currentRound: currentRound,
            currentRoundCount: currentRoundCount
        )
    }
}
