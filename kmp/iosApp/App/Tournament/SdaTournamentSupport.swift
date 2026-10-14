import Foundation

// Soporte de las pantallas de torneos de la Situación de Aprendizaje: conversión entre el
// registro guardado (`TournamentRecord`) y el motor (`TournamentPlan`), equipos desde los
// grupos de trabajo, anotación de resultados y presentación en español.

// MARK: - Registro <-> plan

extension TournamentRecord {
    /// Crea el registro de un torneo nuevo. El id del registro es el del plan.
    init(plan: TournamentPlan, learningSituationId: Int64?, classId: Int64, tabId: String?) throws {
        let columns = try plan.columns()
        self.init(
            id: columns.id,
            learningSituationId: learningSituationId,
            classId: classId,
            tabId: tabId,
            name: columns.name,
            format: plan.format.rawValue,
            status: plan.status.rawValue,
            configJSON: columns.configJSON,
            teamSnapshotJSON: columns.teamSnapshotJSON,
            scheduleJSON: columns.scheduleJSON,
            resultsJSON: columns.resultsJSON,
            knockoutResultsJSON: columns.knockoutResultsJSON
        )
    }

    /// Reconstruye el plan. Lanza si algún JSON no vacío es inválido (no se pisan datos reales).
    func plan() throws -> TournamentPlan {
        var plan = try TournamentPlan(
            columns: TournamentPlanColumns(
                id: id,
                name: name,
                configJSON: configJSON,
                teamSnapshotJSON: teamSnapshotJSON,
                scheduleJSON: scheduleJSON,
                resultsJSON: resultsJSON,
                knockoutResultsJSON: knockoutResultsJSON
            )
        )
        // La columna de estado manda sobre el JSON de configuración.
        if let status = TournamentPlanStatus(rawValue: status) {
            plan.status = status
        }
        return plan
    }

    /// Copia del registro con el contenido del plan. Conserva id, curso, pestaña y SdA.
    func updating(with plan: TournamentPlan) throws -> TournamentRecord {
        let columns = try plan.columns()
        var copy = self
        copy.name = columns.name
        copy.format = plan.format.rawValue
        copy.status = plan.status.rawValue
        copy.configJSON = columns.configJSON
        copy.teamSnapshotJSON = columns.teamSnapshotJSON
        copy.scheduleJSON = columns.scheduleJSON
        copy.resultsJSON = columns.resultsJSON
        copy.knockoutResultsJSON = columns.knockoutResultsJSON
        return copy
    }
}

// MARK: - Equipos desde los grupos de trabajo

enum SdaTournamentTeams {
    /// Nombres únicos: el motor identifica a los equipos por nombre, así que un nombre repetido
    /// se desambigua con «(2)», «(3)»…
    static func uniqueNames(_ names: [String]) -> [String] {
        var used = Set<String>()
        var counts: [String: Int] = [:]
        return names.map { raw in
            let base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = base.isEmpty ? "Grupo sin nombre" : base
            counts[name, default: 0] += 1
            var candidate = counts[name] == 1 ? name : "\(name) (\(counts[name] ?? 2))"
            var extra = counts[name] ?? 1
            while used.contains(candidate) {
                extra += 1
                candidate = "\(name) (\(extra))"
            }
            used.insert(candidate)
            return candidate
        }
    }

    static func planTeams(from groups: [TournamentWorkGroupTeam]) -> [TournamentPlanTeam] {
        let names = uniqueNames(groups.map(\.name))
        return zip(groups, names).map { group, name in
            TournamentPlanTeam(
                id: String(group.groupId),
                name: name,
                studentIDs: group.members.map { String($0.studentId) }.sorted()
            )
        }
    }

    /// Grupos actuales que ya estaban en el torneo, en el orden actual.
    private static func current(for snapshot: [TournamentPlanTeam], in groups: [TournamentWorkGroupTeam]) -> [TournamentWorkGroupTeam] {
        let ids = Set(snapshot.map(\.id))
        return groups.filter { ids.contains(String($0.groupId)) }
    }

    /// `true` si algún grupo del torneo se borró, se renombró o cambió de miembros.
    /// Los grupos nuevos no cuentan: pueden haberse dejado fuera a propósito.
    static func hasChanged(snapshot: [TournamentPlanTeam], current groups: [TournamentWorkGroupTeam]) -> Bool {
        let restricted = current(for: snapshot, in: groups)
        guard restricted.count == snapshot.count else { return true }
        let fresh = Dictionary(
            planTeams(from: restricted).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for team in snapshot {
            guard let now = fresh[team.id] else { return true }
            if now.name != team.name { return true }
            if Set(now.studentIDs) != Set(team.studentIDs) { return true }
        }
        return false
    }

    /// Equipos actualizados: los mismos grupos del torneo con nombre y miembros de hoy.
    static func refreshed(snapshot: [TournamentPlanTeam], current groups: [TournamentWorkGroupTeam]) -> [TournamentPlanTeam] {
        planTeams(from: current(for: snapshot, in: groups))
    }
}

extension TournamentPlan {
    /// Vuelve a leer los grupos: sustituye equipos, borra calendario y resultados y genera un
    /// calendario nuevo. No modifica el plan si algo falla.
    mutating func updateTeams(from groups: [TournamentWorkGroupTeam]) throws {
        var copy = self
        copy.replaceTeams(SdaTournamentTeams.refreshed(snapshot: teams, current: groups))
        let rounds = try TournamentScheduleGenerator.generate(
            format: copy.format,
            teamNames: copy.teamNames,
            venueCount: copy.venueCount,
            groupCount: copy.format == .groupStageKnockout ? copy.groupCount : nil,
            qualifiedTeamsPerGroup: copy.qualifiedTeamsPerGroup
        )
        copy.persistSchedule(rounds)
        self = copy
    }
}

// MARK: - Resultados

extension TournamentPlan {
    /// Partidos con hora, pista y nombres ya resueltos (ganadores y clasificados).
    var slots: [ScheduledMatchSlot] {
        ScheduleAnalytics.slots(tournament: self, rounds: savedSchedule)
    }

    func isKnockoutSlot(_ slot: ScheduledMatchSlot) -> Bool {
        format == .knockout || (format == .groupStageKnockout && slot.stage == .knockout)
    }

    func result(for slot: ScheduledMatchSlot) -> ScheduleMatchScore? {
        ScheduleAnalytics.result(for: slot, tournament: self)
    }

    func hasResult(_ slot: ScheduledMatchSlot) -> Bool {
        ScheduleAnalytics.isCompleted(slot, tournament: self)
    }

    var completedMatchCount: Int {
        let all = slots
        return ScheduleAnalytics.completedMatchIDs(tournament: self, slots: all).count
    }

    var totalMatchCount: Int {
        savedSchedule.reduce(0) { $0 + $1.matches.count }
    }

    /// En liguilla + eliminatorias los cruces solo se juegan al terminar la fase de grupos.
    var groupStageIsComplete: Bool {
        guard format == .groupStageKnockout else { return true }
        let all = slots
        let done = ScheduleAnalytics.completedMatchIDs(tournament: self, slots: all)
        return all.filter { $0.stage == .groupStage }.allSatisfy { done.contains($0.id) }
    }

    /// `true` si el partido ya tiene dos equipos reales y su fase está abierta.
    func canScore(_ slot: ScheduledMatchSlot) -> Bool {
        guard teamNames.contains(slot.match.homeTeam), teamNames.contains(slot.match.awayTeam) else {
            return false
        }
        if format == .groupStageKnockout, slot.stage == .knockout {
            return groupStageIsComplete
        }
        return true
    }

    /// Nombres para mostrar. Antes de cerrar los grupos se enseñan los huecos
    /// («Clasificado 1 Grupo A») y no un clasificado provisional.
    func displayTeams(for slot: ScheduledMatchSlot) -> (home: String, away: String) {
        if format == .groupStageKnockout, slot.stage == .knockout, !groupStageIsComplete,
           let raw = savedSchedule.flatMap(\.matches).first(where: { $0.id == slot.id }) {
            return (raw.homeTeam, raw.awayTeam)
        }
        return (slot.match.homeTeam, slot.match.awayTeam)
    }

    /// Guarda el marcador de un partido. En eliminatoria, un cambio de ganador borra los
    /// resultados de las rondas que dependían de él.
    mutating func setScore(for slot: ScheduledMatchSlot, home: Int, away: Int) {
        guard canScore(slot) else { return }
        let home = max(0, home)
        let away = max(0, away)
        if isKnockoutSlot(slot) {
            savedKnockoutResults.removeAll { $0.matchID == slot.id }
            savedKnockoutResults.append(
                KnockoutMatchResult(
                    matchID: slot.id,
                    homeTeam: slot.match.homeTeam,
                    awayTeam: slot.match.awayTeam,
                    homeScore: home,
                    awayScore: away
                )
            )
        } else {
            removeLeagueResult(for: slot)
            savedResults.append(
                MatchResult(
                    matchID: slot.id,
                    homeTeam: slot.match.homeTeam,
                    awayTeam: slot.match.awayTeam,
                    homeScore: home,
                    awayScore: away
                )
            )
        }
        pruneStaleKnockoutResults()
        if status == .draft || status == .scheduled {
            status = .live
        }
    }

    mutating func clearScore(for slot: ScheduledMatchSlot) {
        if isKnockoutSlot(slot) {
            savedKnockoutResults.removeAll { $0.matchID == slot.id }
        } else {
            removeLeagueResult(for: slot)
        }
        pruneStaleKnockoutResults()
    }

    private mutating func removeLeagueResult(for slot: ScheduledMatchSlot) {
        let pair = Set([slot.match.homeTeam, slot.match.awayTeam])
        savedResults.removeAll { result in
            if result.matchID == slot.id { return true }
            // Resultados antiguos sin id de partido: se emparejan por equipos.
            return result.matchID == nil && Set([result.homeTeam, result.awayTeam]) == pair
        }
    }

    /// Quita resultados de eliminatoria cuyos equipos ya no coinciden con los que
    /// resuelve el cuadro (cambió un ganador anterior o una clasificación de grupos).
    private mutating func pruneStaleKnockoutResults() {
        var changed = true
        while changed {
            changed = false
            for slot in slots where isKnockoutSlot(slot) {
                guard let saved = savedKnockoutResults.first(where: { $0.matchID == slot.id }) else { continue }
                if saved.homeTeam != slot.match.homeTeam || saved.awayTeam != slot.match.awayTeam {
                    savedKnockoutResults.removeAll { $0.matchID == slot.id }
                    changed = true
                    break
                }
            }
        }
    }

    // MARK: Clasificaciones

    /// Puntos por victoria/empate/derrota: los del torneo migrado si los trae; si no, 3/1/0 del motor.
    private var standingPoints: (win: Int, draw: Int, loss: Int) {
        guard let extras = legacyExtras else { return (3, 1, 0) }
        return (extras.pointsWin, extras.pointsDraw, extras.pointsLoss)
    }

    var leagueStandings: [Standing] {
        let points = standingPoints
        return StandingsCalculator.calculate(
            teamNames: teamNames,
            results: savedResults,
            pointsWin: points.win,
            pointsDraw: points.draw,
            pointsLoss: points.loss
        )
    }

    /// Una clasificación por grupo de la liguilla.
    var groupStandings: [(name: String, standings: [Standing])] {
        let resolved = groupCount > 0 ? groupCount : GroupStageConfiguration.defaultGroupCount(for: teamCount)
        let groups = GroupStageConfiguration.groups(teamNames: teamNames, groupCount: resolved)
        return groups.enumerated().map { index, names in
            (
                "Grupo \(GroupStageConfiguration.groupName(index: index))",
                StandingsCalculator.calculate(
                    teamNames: names,
                    results: savedResults,
                    pointsWin: standingPoints.win,
                    pointsDraw: standingPoints.draw,
                    pointsLoss: standingPoints.loss
                )
            )
        }
    }

    var champion: String? {
        guard format.includesKnockoutPhase else { return nil }
        return KnockoutBracketResolver.champion(rounds: savedSchedule, results: savedKnockoutResults)
    }

    // MARK: Exportar

    /// Calendario y, si los hay, resultados y clasificación, en texto plano.
    var exportText: String {
        var parts = [TournamentExportFormatter.scheduleText(tournament: self, rounds: savedSchedule)]
        switch format {
        case .roundRobin, .rotation:
            if !savedResults.isEmpty {
                parts.append(TournamentExportFormatter.roundRobinResultsText(tournament: self, results: savedResults))
            }
        case .knockout:
            if !savedKnockoutResults.isEmpty {
                parts.append(
                    TournamentExportFormatter.knockoutResultsText(
                        tournament: self,
                        rounds: savedSchedule,
                        results: savedKnockoutResults
                    )
                )
            }
        case .groupStageKnockout:
            if !savedResults.isEmpty {
                for group in groupStandings {
                    parts.append(
                        TournamentExportFormatter.standingsText(
                            tournamentName: "\(name) · \(group.name)",
                            standings: group.standings
                        )
                    )
                }
            }
            if !savedKnockoutResults.isEmpty {
                parts.append(
                    TournamentExportFormatter.knockoutResultsText(
                        tournament: self,
                        rounds: savedSchedule,
                        results: savedKnockoutResults
                    )
                )
            }
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Textos en español

extension TournamentFormat {
    /// Nombre corto de la maqueta aprobada.
    var shortTitle: String {
        switch self {
        case .roundRobin: return "Liga"
        case .knockout: return "Eliminatoria"
        case .groupStageKnockout: return "Liguilla + cruces"
        case .rotation: return "Rotaciones"
        }
    }

    var shortSubtitle: String {
        switch self {
        case .roundRobin: return "Todos contra todos"
        case .knockout: return "Quien pierde, fuera"
        case .groupStageKnockout: return "Grupos y final"
        case .rotation: return "Rondas rápidas"
        }
    }

    var symbolName: String {
        switch self {
        case .roundRobin: return "trophy"
        case .knockout: return "arrow.triangle.branch"
        case .groupStageKnockout: return "square.grid.2x2"
        case .rotation: return "arrow.triangle.2.circlepath"
        }
    }
}

extension ScheduledRoundStage {
    var sdaTitle: String? {
        switch self {
        case .league: return nil
        case .groupStage: return "Fase de grupos"
        case .knockout: return "Eliminatorias"
        }
    }
}

func sdaPlural(_ count: Int, _ singular: String, _ plural: String) -> String {
    "\(count) \(count == 1 ? singular : plural)"
}

/// Duración típica de una sesión de un curso a partir de su horario: la más repetida
/// (si hay empate, la más corta). `nil` si el curso no tiene huecos en el horario.
func sdaTypicalSessionMinutes(startEndTimes: [(start: String, end: String)]) -> Int? {
    func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return hour * 60 + minute
    }
    let durations = startEndTimes.compactMap { slot -> Int? in
        guard let start = minutes(slot.start), let end = minutes(slot.end), end > start else { return nil }
        return end - start
    }
    guard !durations.isEmpty else { return nil }
    let counts = Dictionary(grouping: durations, by: { $0 }).mapValues(\.count)
    return counts.max { lhs, rhs in
        lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
    }?.key
}
