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
        copy.persistSchedule(try copy.generatedRounds())
        self = copy
    }
}

// MARK: - Integrantes

enum TournamentMembersError: Error, Equatable {
    case unknownTeam
    case emptyTeam(String)
    case repeatedStudent(String)
}

extension TournamentPlan {
    /// Cambia solo los alumnos de cada equipo. Conserva nombres, calendario y resultados
    /// (los partidos van atados al nombre del equipo). No modifica el plan si algo falla.
    /// Con `firstNames`, los equipos con nombre automático («Ana y Bruno») se renombran con
    /// sus integrantes nuevos, también en calendario y resultados.
    mutating func updateMembers(
        _ members: [String: [String]],
        firstNames: [String: String]? = nil,
        markManual: Bool = true
    ) throws {
        let ids = Set(teams.map(\.id))
        guard Set(members.keys).isSubset(of: ids) else { throw TournamentMembersError.unknownTeam }
        var copy = teams
        var seen = Set<String>()
        for index in copy.indices {
            let list = members[copy[index].id] ?? copy[index].studentIDs
            guard !list.isEmpty else { throw TournamentMembersError.emptyTeam(copy[index].name) }
            for student in list {
                guard seen.insert(student).inserted else { throw TournamentMembersError.repeatedStudent(student) }
            }
            copy[index].studentIDs = list.sorted()
        }
        let before = teams
        teams = copy
        if let firstNames { renameAutoNamedTeams(previous: before, firstNames: firstNames) }
        if markManual { teamsEditedManually = true }
    }

    /// Nombre automático a partir de los nombres de pila: «Ana y Bruno», «Ana, Bruno y Carla».
    static func autoTeamName(for studentIDs: [String], firstNames: [String: String]) -> String {
        let names = studentIDs.map { firstNames[$0] ?? "Alumno" }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard names.count > 1 else { return names.first ?? "Equipo" }
        return names.dropLast().joined(separator: ", ") + " y " + names[names.count - 1]
    }

    /// `true` si el nombre está hecho con los nombres de pila de esos alumnos (en cualquier orden,
    /// con o sin el número que se añade para no repetir).
    static func isAutoTeamName(_ name: String, studentIDs: [String], firstNames: [String: String]) -> Bool {
        var base = name
        if let range = base.range(of: #" \d+$"#, options: .regularExpression) { base.removeSubrange(range) }
        let tokens = base.replacingOccurrences(of: ", ", with: " y ")
            .components(separatedBy: " y ")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .sorted()
        let expected = studentIDs.map { (firstNames[$0] ?? "Alumno").lowercased() }.sorted()
        return !expected.isEmpty && tokens == expected
    }

    /// `true` si el nombre está hecho con nombres de pila de la clase (al menos dos) pero no con
    /// los de sus integrantes de ahora: quedó desfasado de una edición anterior.
    static func isStaleAutoTeamName(_ name: String, studentIDs: [String], firstNames: [String: String]) -> Bool {
        guard !isAutoTeamName(name, studentIDs: studentIDs, firstNames: firstNames) else { return false }
        var base = name
        if let range = base.range(of: #" \d+$"#, options: .regularExpression) { base.removeSubrange(range) }
        let tokens = base.replacingOccurrences(of: ", ", with: " y ")
            .components(separatedBy: " y ")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let classNames = Set(firstNames.values.map { $0.lowercased() })
        return tokens.count >= 2 && tokens.allSatisfy { classNames.contains($0) }
    }

    /// Equipos cuyo nombre automático no coincide con sus integrantes.
    func hasStaleTeamNames(firstNames: [String: String]) -> Bool {
        teams.contains { Self.isStaleAutoTeamName($0.name, studentIDs: $0.studentIDs, firstNames: firstNames) }
    }

    private mutating func renameAutoNamedTeams(previous: [TournamentPlanTeam], firstNames: [String: String]) {
        let old = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        var used = Set(teams.map { $0.name.lowercased() })
        var renames: [String: String] = [:]
        for index in teams.indices {
            let team = teams[index]
            guard let was = old[team.id] else { continue }
            let changedAuto = Set(was.studentIDs) != Set(team.studentIDs)
                && Self.isAutoTeamName(team.name, studentIDs: was.studentIDs, firstNames: firstNames)
            let stale = Self.isStaleAutoTeamName(team.name, studentIDs: team.studentIDs, firstNames: firstNames)
            guard changedAuto || stale else { continue }
            used.remove(team.name.lowercased())
            let base = Self.autoTeamName(for: team.studentIDs, firstNames: firstNames)
            var name = base
            var counter = 2
            while used.contains(name.lowercased()) {
                name = "\(base) \(counter)"
                counter += 1
            }
            used.insert(name.lowercased())
            if name != team.name {
                renames[team.name] = name
                teams[index].name = name
            }
        }
        guard !renames.isEmpty else { return }
        func n(_ value: String) -> String { renames[value] ?? value }
        savedSchedule = savedSchedule.map { round in
            ScheduledRound(
                id: round.id,
                number: round.number,
                matches: round.matches.map {
                    ScheduledMatch(id: $0.id, homeTeam: n($0.homeTeam), awayTeam: n($0.awayTeam), venueNumber: $0.venueNumber)
                },
                stage: round.stage
            )
        }
        savedResults = savedResults.map {
            MatchResult(id: $0.id, matchID: $0.matchID, homeTeam: n($0.homeTeam), awayTeam: n($0.awayTeam),
                        homeScore: $0.homeScore, awayScore: $0.awayScore)
        }
        savedKnockoutResults = savedKnockoutResults.map {
            KnockoutMatchResult(matchID: $0.matchID, homeTeam: n($0.homeTeam), awayTeam: n($0.awayTeam),
                                homeScore: $0.homeScore, awayScore: $0.awayScore)
        }
    }

    /// Copia de los grupos de trabajo solo los integrantes (mismos equipos, mismos nombres).
    /// Los grupos borrados o nuevos se ignoran.
    mutating func copyMembers(from groups: [TournamentWorkGroupTeam]) throws {
        let fresh = Dictionary(
            uniqueKeysWithValues: groups.map { (String($0.groupId), $0.members.map { String($0.studentId) }) }
        )
        let members = teams.reduce(into: [String: [String]]()) { result, team in
            if let list = fresh[team.id], !list.isEmpty { result[team.id] = list }
        }
        try updateMembers(members, markManual: false)
    }
}

// MARK: - Resultados

extension TournamentPlan {
    /// Partidos con hora, pista y nombres ya resueltos (ganadores y clasificados).
    var slots: [ScheduledMatchSlot] {
        ScheduleAnalytics.slots(tournament: self, rounds: savedSchedule)
    }

    func isKnockoutSlot(_ slot: ScheduledMatchSlot) -> Bool {
        format == .knockout
            || ((format == .groupStageKnockout || format == .leaguePlacement) && slot.stage == .knockout)
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

    /// Los partidos de una liguilla cerrada a mano que no se jugaron ya no cuentan.
    var totalMatchCount: Int {
        let scheduled = savedSchedule.reduce(0) { $0 + $1.matches.count }
        return leagueClosedEarly == true ? scheduled - pendingLeagueMatchCount : scheduled
    }

    /// En liguilla + eliminatorias los cruces solo se juegan al terminar la fase de grupos.
    var groupStageIsComplete: Bool {
        if format == .leaguePlacement { return placementLeagueIsClosed }
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
        if format == .leaguePlacement {
            // La liguilla cerrada a mano ya no admite resultados: cambiaría el orden del cuadro.
            return slot.stage == .knockout ? placementLeagueIsClosed : leagueClosedEarly != true
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
        if format == .leaguePlacement, slot.stage == .knockout, !placementLeagueIsClosed,
           let raw = savedSchedule.flatMap(\.matches).first(where: { $0.id == slot.id }) {
            return (
                PlacementResolver.displayName(forPlaceholder: raw.homeTeam),
                PlacementResolver.displayName(forPlaceholder: raw.awayTeam)
            )
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
        if format == .leaguePlacement { return placementFinalTable?.first?.teamName }
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
        case .leaguePlacement:
            if !savedResults.isEmpty {
                var lines = ["", "Liguilla: \(name)"]
                for (offset, row) in placementStandings.enumerated() {
                    lines.append("\(offset + 1). \(row.teamName): \(row.wins) V, \(row.draws) E, \(row.losses) D, \(row.pointDifference) dif.")
                }
                parts.append(lines.joined(separator: "\n"))
            }
            if let table = placementFinalTable {
                var lines = ["", "Tabla final: \(name)"]
                for row in table {
                    lines.append("\(row.position). \(row.teamName)")
                }
                parts.append(lines.joined(separator: "\n"))
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
        case .leaguePlacement: return "Liguilla + puestos"
        }
    }

    var shortSubtitle: String {
        switch self {
        case .roundRobin: return "Todos contra todos"
        case .knockout: return "Quien pierde, fuera"
        case .groupStageKnockout: return "Grupos y final"
        case .rotation: return "Rondas rápidas"
        case .leaguePlacement: return "Nadie queda eliminado"
        }
    }

    var symbolName: String {
        switch self {
        case .roundRobin: return "trophy"
        case .knockout: return "arrow.triangle.branch"
        case .groupStageKnockout: return "square.grid.2x2"
        case .rotation: return "arrow.triangle.2.circlepath"
        case .leaguePlacement: return "list.number"
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

// MARK: - Integrantes de los equipos (desde el torneo, no desde los grupos de hoy)

/// Equipo del torneo con los nombres de sus alumnos ya resueltos.
struct SdaResolvedTeam: Identifiable, Equatable {
    static let missingStudentName = "Alumno no encontrado"

    var id: String
    var name: String
    /// Por nombre; los alumnos que ya no están en el curso van al final como «Alumno no encontrado».
    var memberNames: [String]
    var studentCount: Int { memberNames.count }

    /// «Sin alumnos», «1 alumno», «4 alumnos».
    var countText: String {
        switch memberNames.count {
        case 0: return "Sin alumnos"
        case 1: return "1 alumno"
        default: return "\(memberNames.count) alumnos"
        }
    }
}

enum SdaTournamentRoster {
    /// Resuelve los integrantes con `studentIDs` del torneo y los alumnos del curso del torneo.
    /// Un id que ya no está en el curso se enseña como «Alumno no encontrado».
    static func resolve(teams: [TournamentPlanTeam], students: [(id: String, name: String)]) -> [SdaResolvedTeam] {
        let namesById = Dictionary(students.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return teams.map { team in
            var found: [String] = []
            var missing = 0
            for studentID in Set(team.studentIDs) {
                if let name = namesById[studentID], !name.trimmingCharacters(in: .whitespaces).isEmpty {
                    found.append(name)
                } else {
                    missing += 1
                }
            }
            found.sort { $0.localizedStandardCompare($1) == .orderedAscending }
            let names = found + Array(repeating: SdaResolvedTeam.missingStudentName, count: missing)
            return SdaResolvedTeam(id: team.id, name: team.name, memberNames: names)
        }
    }

    /// Texto corto con los integrantes de un grupo (ayuda al pasar el ratón y lectores de pantalla).
    static func summary(of memberNames: [String]) -> String {
        memberNames.isEmpty ? "Sin alumnos" : memberNames.joined(separator: ", ")
    }
}

// MARK: - Primera ronda

/// Primera ronda para la hoja imprimible: pista y enfrentamiento, y quién descansa.
struct SdaFirstRound: Equatable {
    struct Match: Equatable {
        var venue: Int
        var text: String
    }

    var title: String
    var matches: [Match]
    var resting: [String]
}

extension TournamentPlan {
    /// `nil` si el torneo aún no tiene calendario. En liguilla + cruces es la primera ronda de grupos.
    var firstRoundSummary: SdaFirstRound? {
        guard let round = savedSchedule.first, !round.matches.isEmpty else { return nil }
        let matches = round.matches
            .sorted { $0.venueNumber < $1.venueNumber }
            .map { SdaFirstRound.Match(venue: $0.venueNumber, text: "\($0.homeTeam) – \($0.awayTeam)") }
        let playing = Set(round.matches.flatMap { [$0.homeTeam, $0.awayTeam] })
        let resting = teamNames.filter { !playing.contains($0) }
        return SdaFirstRound(
            title: round.stage == .groupStage ? "Primera ronda de grupos" : "Primera ronda",
            matches: matches,
            resting: resting
        )
    }
}
