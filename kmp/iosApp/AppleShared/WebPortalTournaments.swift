import Foundation
import MiGestorKit

/// «Torneos» del portal del alumnado (ticket fase 3B, sección 4.1).
///
/// Arma el bloque `torneos` del tablón v1 por alumno a partir de `TournamentPlan`, reutilizando
/// `ProjectionTeamLabels`, `TournamentPhaseTimeline` y `BracketTreeLayout` para no duplicar
/// reglas de fases, cuadros ni clasificación.
///
/// Privacidad:
/// - Por defecto (`showNames == false`) cada equipo sale como «Equipo N» y los huecos seguros
///   del cuadro («Gana P5», «1º Grupo A»); nunca se exportan nombres de equipo ni de alumnado.
/// - Nunca salen incidencias (`TournamentNotes`), notas de rúbrica ni `studentIDs`.

// MARK: - Valores sencillos para la hoja y los tests

struct WebPortalTournamentRow: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let formatTitle: String
    let status: TournamentPlanStatus
    let teamCount: Int
    let playedMatches: Int
    let totalMatches: Int
    let hasSchedule: Bool

    var statusTitle: String { status.title }

    var subtitle: String {
        if hasSchedule, totalMatches > 0 {
            return "\(formatTitle) · \(teamCount) equipos · \(playedMatches)/\(totalMatches) partidos"
        }
        if teamCount > 0 {
            return "\(formatTitle) · \(teamCount) equipos · Sin calendario aún"
        }
        return "\(formatTitle) · Sin equipos aún"
    }
}

struct WebPortalTournamentOverview: Equatable, Sendable {
    let classId: Int64
    let studentCount: Int
    let tournaments: [WebPortalTournamentRow]
}

// MARK: - Etiquetas seguras en español (reutiliza las reglas de `ProjectionTeamLabels`)

struct WebPortalTournamentLabels {
    private let projection: ProjectionTeamLabels
    private let namesByPosition: [String]
    let showNames: Bool

    init(plan: TournamentPlan, showNames: Bool) {
        self.projection = ProjectionTeamLabels(plan: plan, showNames: showNames)
        self.namesByPosition = plan.teams.map(\.name)
        self.showNames = showNames
    }

    func label(number: Int) -> String {
        if showNames, namesByPosition.indices.contains(number - 1) {
            return WebPortalTournaments.clip(namesByPosition[number - 1])
        }
        return "Equipo \(number)"
    }

    func label(name: String) -> String {
        if let number = projection.number(name: name) {
            return label(number: number)
        }
        // Hueco estándar del cuadro en español («Gana P5», «1º Grupo A», etc.): nunca lleva nombres.
        if ProjectionTeamLabels.isSlotPlaceholder(name) {
            return WebPortalTournaments.clip(name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return "Equipo"
    }

    func label(id: String) -> String? {
        guard let index = numberByID(id: id) else { return nil }
        return label(number: index)
    }

    func number(name: String) -> Int? { projection.number(name: name) }

    /// Posición (empezando en 1) del equipo al que pertenece `studentId`, o `nil`.
    static func teamNumber(forStudentId studentId: Int64, in plan: TournamentPlan) -> Int? {
        let key = String(studentId)
        guard let index = plan.teams.firstIndex(where: { $0.studentIDs.contains(key) }) else { return nil }
        return index + 1
    }

    private func numberByID(id: String) -> Int? {
        guard let labelText = projection.label(id: id) else { return nil }
        if !showNames {
            // `ProjectionTeamLabels` devuelve «Team N» cuando showNames == false.
            let digits = labelText.split(separator: " ").last.flatMap { Int($0) }
            return digits
        }
        return projection.number(name: labelText)
    }
}

// MARK: - Construcción del bloque `torneos` (4.1)

enum WebPortalTournaments {
    static let shortTextLimit = WebPortalGrades.shortTextLimit
    static let maxTournaments = 10
    static let maxTeams = 64
    static let maxRounds = 40
    static let maxMatchesPerRound = 64

    static func clip(_ text: String, _ limit: Int = shortTextLimit) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= limit ? trimmed : String(trimmed.prefix(limit))
    }

    static func formatKey(_ format: TournamentFormat) -> String {
        switch format {
        case .roundRobin: return "liga"
        case .knockout: return "eliminatoria"
        case .groupStageKnockout: return "grupos_eliminatoria"
        case .rotation: return "rotaciones"
        case .leaguePlacement: return "liguilla_puestos"
        }
    }

    static func statusKey(plan: TournamentPlan, timeline: TournamentPhaseTimeline) -> String {
        if plan.savedSchedule.isEmpty || plan.teams.count < 2 {
            return plan.status == .draft ? "borrador" : "planificado"
        }
        if timeline.currentKind == .podium || plan.status == .finished {
            return "finalizado"
        }
        if !timeline.hasStarted {
            return "planificado"
        }
        return "en_curso"
    }

    static func decodePlan(from record: TournamentRecord) -> TournamentPlan? {
        let columns = TournamentPlanColumns(
            id: record.id,
            name: record.name,
            configJSON: record.configJSON,
            teamSnapshotJSON: record.teamSnapshotJSON,
            scheduleJSON: record.scheduleJSON,
            resultsJSON: record.resultsJSON,
            knockoutResultsJSON: record.knockoutResultsJSON
        )
        return try? TournamentPlan(columns: columns)
    }

    /// Fila resumen para la pestaña «Torneos» de `WebPortalSheet`.
    static func row(from record: TournamentRecord) -> WebPortalTournamentRow {
        if let plan = decodePlan(from: record) {
            let timeline = TournamentPhaseTimeline.make(plan: plan)
            let layout = BracketTreeLayout.make(plan: plan)
            let leagueSchedule = plan.savedSchedule.filter {
                !(plan.format.includesKnockoutPhase && ($0.stage == .knockout || plan.format == .knockout))
            }
            let leagueTotal = leagueSchedule.reduce(0) { $0 + $1.matches.count }
            let bracketTotal = layout?.nodes.count ?? 0
            let played = timeline.leaguePlayed + timeline.bracketPlayed
            let total = leagueTotal + bracketTotal
            let effectiveStatus: TournamentPlanStatus
            if timeline.currentKind == .podium || plan.status == .finished {
                effectiveStatus = .finished
            } else if timeline.hasStarted || plan.status == .live {
                effectiveStatus = .live
            } else if !plan.savedSchedule.isEmpty {
                effectiveStatus = .scheduled
            } else {
                effectiveStatus = plan.status
            }
            return WebPortalTournamentRow(
                id: record.id,
                name: record.name,
                formatTitle: plan.format.title,
                status: effectiveStatus,
                teamCount: plan.teams.count,
                playedMatches: played,
                totalMatches: total,
                hasSchedule: !plan.savedSchedule.isEmpty
            )
        }
        let format = TournamentFormat(rawValue: record.format)?.title ?? "Torneo"
        let status = TournamentPlanStatus(rawValue: record.status) ?? .draft
        return WebPortalTournamentRow(
            id: record.id,
            name: record.name,
            formatTitle: format,
            status: status,
            teamCount: 0,
            playedMatches: 0,
            totalMatches: 0,
            hasSchedule: false
        )
    }

    /// Construye la entrada de un torneo para un alumno concreto (o `nil` si no es válida).
    static func tournamentEntry(
        id: String,
        plan: TournamentPlan,
        groupName: String,
        studentId: Int64,
        showNames: Bool
    ) -> [String: Any] {
        let labels = WebPortalTournamentLabels(plan: plan, showNames: showNames)
        let timeline = TournamentPhaseTimeline.make(plan: plan)
        let layout = BracketTreeLayout.make(plan: plan)
        let myNumber = WebPortalTournamentLabels.teamNumber(forStudentId: studentId, in: plan)
        let myTeam = myNumber.flatMap { plan.teams.indices.contains($0 - 1) ? plan.teams[$0 - 1] : nil }
        let myLabel = myNumber.map { labels.label(number: $0) }

        func isMyTeam(name: String) -> Bool {
            guard let myNumber else { return false }
            return labels.number(name: name) == myNumber
        }

        func isMySide(_ side: BracketSide) -> Bool {
            guard let myTeam else { return false }
            if let teamID = side.teamID, teamID == myTeam.id { return true }
            return isMyTeam(name: side.label)
        }

        // Fases
        let fases: [[String: Any]] = timeline.phases.map { phase in
            let clave: String
            switch phase.kind {
            case .league: clave = "liguilla"
            case .bracket: clave = "cuadro"
            case .round: clave = "ronda"
            case .podium: clave = "podio"
            }
            let estado: String
            switch phase.state {
            case .done: estado = "hecha"
            case .current: estado = "ahora"
            case .upcoming: estado = "pendiente"
            }
            return [
                "clave": clave,
                "etiqueta": clip(phase.title, 60),
                "estado": estado,
            ]
        }

        // Clasificación
        let clasificacion = buildStandings(plan: plan, labels: labels, isMyTeam: isMyTeam)

        // Rondas (liga/liguilla + cuadro)
        let (rondas, proximoPartido) = buildRoundsAndNext(
            plan: plan,
            layout: layout,
            labels: labels,
            isMyTeam: isMyTeam,
            isMySide: isMySide
        )

        // Podio (solo si terminado)
        let estado = statusKey(plan: plan, timeline: timeline)
        let podio = estado == "finalizado"
            ? buildPodium(plan: plan, layout: layout, labels: labels, isMyTeam: isMyTeam, myTeamId: myTeam?.id)
            : []

        var item: [String: Any] = [
            "id": clip(id, 64),
            "titulo": clip(plan.name),
            "grupo": clip(groupName),
            "formato": formatKey(plan.format),
            "estado": estado,
            "fases": fases,
            "clasificacion": clasificacion,
            "rondas": rondas,
        ]
        if !podio.isEmpty { item["podio"] = podio }

        if let myNumber, let myLabel {
            var mine: [String: Any] = [
                "numero": myNumber,
                "etiqueta": myLabel,
            ]
            if let summary = myTeamSummary(
                plan: plan,
                myTeamName: myTeam?.name,
                myTeamId: myTeam?.id,
                estado: estado,
                podio: podio,
                clasificacion: clasificacion
            ) {
                mine["resumen"] = clip(summary)
            }
            item["miEquipo"] = mine
        }
        if let proximoPartido {
            item["proximoPartido"] = proximoPartido
        }
        return item
    }

    /// Bloque `torneos` completo para un alumno, o `nil` si no hay ningún torneo visible.
    static func torneosBlock(entries: [[String: Any]], now: Date = Date()) -> [String: Any]? {
        let limited = Array(entries.prefix(maxTournaments))
        guard !limited.isEmpty else { return nil }
        return [
            "actualizado": WebPortalGrades.isoString(now),
            "lista": limited,
        ]
    }

    static func merge(_ first: [String: Any], _ second: [String: Any]) -> [String: Any] {
        var result = first
        let a = first["lista"] as? [[String: Any]] ?? []
        let b = second["lista"] as? [[String: Any]] ?? []
        result["lista"] = Array((a + b).prefix(maxTournaments))
        return result
    }

    /// Huella del bloque sin la fecha de actualización, para no subir duplicados.
    static func digest(of torneos: [String: Any]?) -> String {
        guard var torneos else { return "" }
        torneos.removeValue(forKey: "actualizado")
        guard let data = try? JSONSerialization.data(withJSONObject: torneos, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "?" }
        return WebPortalCrypto.sha256Hex(text)
    }

    // MARK: Helpers privados

    private static func buildStandings(
        plan: TournamentPlan,
        labels: WebPortalTournamentLabels,
        isMyTeam: (String) -> Bool
    ) -> [[String: Any]] {
        guard plan.format != .knockout, !plan.teams.isEmpty else { return [] }
        switch plan.format {
        case .leaguePlacement:
            let rows = plan.placementStandings.prefix(maxTeams).enumerated().map { offset, row -> [String: Any] in
                [
                    "posicion": offset + 1,
                    "equipo": labels.label(name: row.teamName),
                    "esMio": isMyTeam(row.teamName),
                    "jugados": row.played,
                    "ganados": row.wins,
                    "empatados": row.draws,
                    "perdidos": row.losses,
                    "puntos": row.wins * 3 + row.draws,
                    "diferencia": row.pointDifference,
                ]
            }
            return rows.isEmpty ? [] : [["titulo": "Liguilla", "filas": rows]]

        case .groupStageKnockout:
            return plan.groupStandings.enumerated().compactMap { index, group in
                let rows = group.standings.prefix(maxTeams).enumerated().map { offset, row -> [String: Any] in
                    [
                        "posicion": offset + 1,
                        "equipo": labels.label(name: row.teamName),
                        "esMio": isMyTeam(row.teamName),
                        "jugados": row.played,
                        "ganados": row.wins,
                        "empatados": row.draws,
                        "perdidos": row.losses,
                        "puntos": row.points,
                    ]
                }
                guard !rows.isEmpty else { return nil }
                return [
                    "titulo": "Grupo \(GroupStageConfiguration.groupName(index: index))",
                    "filas": rows,
                ]
            }

        default:
            let rows = plan.leagueStandings.prefix(maxTeams).enumerated().map { offset, row -> [String: Any] in
                [
                    "posicion": offset + 1,
                    "equipo": labels.label(name: row.teamName),
                    "esMio": isMyTeam(row.teamName),
                    "jugados": row.played,
                    "ganados": row.wins,
                    "empatados": row.draws,
                    "perdidos": row.losses,
                    "puntos": row.points,
                ]
            }
            return rows.isEmpty ? [] : [["titulo": "Clasificación", "filas": rows]]
        }
    }

    private static func buildRoundsAndNext(
        plan: TournamentPlan,
        layout: BracketTreeLayout?,
        labels: WebPortalTournamentLabels,
        isMyTeam: (String) -> Bool,
        isMySide: (BracketSide) -> Bool
    ) -> ([[String: Any]], [String: Any]?) {
        var rounds: [[String: Any]] = []
        var nextMatch: [String: Any]?

        let hasBracket = plan.format.includesKnockoutPhase
        let slotsByID = Dictionary(plan.slots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let leagueSchedule = plan.savedSchedule.filter {
            !(hasBracket && ($0.stage == .knockout || plan.format == .knockout))
        }

        // Identifica primera ronda de liga con partidos sin jugar.
        let currentLeagueIndex = leagueSchedule.firstIndex { round in
            round.matches.contains { match in
                guard let slot = slotsByID[match.id] else { return false }
                return ScheduleAnalytics.result(for: slot, tournament: plan) == nil
            }
        }

        for (index, round) in leagueSchedule.enumerated() where rounds.count < maxRounds {
            let matches: [[String: Any]] = round.matches.prefix(maxMatchesPerRound).compactMap { match in
                guard let slot = slotsByID[match.id] else { return nil }
                let score = ScheduleAnalytics.result(for: slot, tournament: plan)
                let home = labels.label(name: slot.match.homeTeam)
                let away = labels.label(name: slot.match.awayTeam)
                let mine = isMyTeam(slot.match.homeTeam) || isMyTeam(slot.match.awayTeam)
                var dict: [String: Any] = [
                    "pista": slot.venueNumber,
                    "local": home,
                    "visitante": away,
                    "esMio": mine,
                ]
                if let score {
                    dict["marcadorLocal"] = score.homeScore
                    dict["marcadorVisitante"] = score.awayScore
                } else if mine, nextMatch == nil {
                    nextMatch = [
                        "ronda": "Ronda \(round.number)",
                        "pista": slot.venueNumber,
                        "local": home,
                        "visitante": away,
                    ]
                }
                return dict
            }.sorted { ($0["pista"] as? Int ?? 0) < ($1["pista"] as? Int ?? 0) }

            var entry: [String: Any] = [
                "titulo": "Ronda \(round.number)",
                "fase": "liguilla",
                "actual": currentLeagueIndex == index,
                "partidos": matches,
            ]
            if plan.format != .groupStageKnockout {
                let playing = Set(round.matches.flatMap { [$0.homeTeam, $0.awayTeam] })
                let resting = plan.teams.enumerated()
                    .filter { !playing.contains($0.element.name) }
                    .map { labels.label(number: $0.offset + 1) }
                if !resting.isEmpty { entry["descansan"] = resting }
            }
            rounds.append(entry)
        }

        if let layout {
            for column in layout.columns where rounds.count < maxRounds {
                let nodes = layout.nodes
                    .filter { $0.column == column.id }
                    .sorted { ($0.venue, $0.row) < ($1.venue, $1.row) }
                let matches: [[String: Any]] = nodes.prefix(maxMatchesPerRound).map { node in
                    let homeLabel = node.home.teamID.flatMap { labels.label(id: $0) } ?? labels.label(name: node.home.label)
                    let awayLabel = node.away.teamID.flatMap { labels.label(id: $0) } ?? labels.label(name: node.away.label)
                    let mine = isMySide(node.home) || isMySide(node.away)
                    var dict: [String: Any] = [
                        "pista": node.venue,
                        "local": homeLabel,
                        "visitante": awayLabel,
                        "esMio": mine,
                    ]
                    if node.status == .played, let hs = node.home.score, let aws = node.away.score {
                        dict["marcadorLocal"] = hs
                        dict["marcadorVisitante"] = aws
                    } else if mine, nextMatch == nil, !node.home.isDirectPass, !node.away.isDirectPass {
                        var rondaTexto = column.title
                        if let pos = node.positions {
                            rondaTexto += " · Puestos \(pos.lowerBound)–\(pos.upperBound)"
                        }
                        nextMatch = [
                            "ronda": clip(rondaTexto, 80),
                            "pista": node.venue,
                            "local": homeLabel,
                            "visitante": awayLabel,
                        ]
                    }
                    if let pos = node.positions {
                        dict["etiqueta"] = "Puestos \(pos.lowerBound)–\(pos.upperBound)"
                    }
                    if layout.isPlacement, !node.destinationText.isEmpty {
                        dict["destino"] = clip(node.destinationText, 100)
                    }
                    return dict
                }
                rounds.append([
                    "titulo": clip(column.title, 80),
                    "fase": "cuadro",
                    "actual": column.state == .current,
                    "partidos": matches,
                ])
            }
        }

        return (rounds, nextMatch)
    }

    private static func buildPodium(
        plan: TournamentPlan,
        layout: BracketTreeLayout?,
        labels: WebPortalTournamentLabels,
        isMyTeam: (String) -> Bool,
        myTeamId: String?
    ) -> [[String: Any]] {
        var ranking: [(position: Int, label: String, mine: Bool)] = []
        if plan.format == .leaguePlacement {
            ranking = (plan.placementFinalTable ?? []).map {
                ($0.position, labels.label(name: $0.teamName), isMyTeam($0.teamName))
            }
        } else if plan.format.includesKnockoutPhase {
            ranking = (layout?.leaves ?? [])
                .filter { $0.isComplete && $0.slotCount == 1 }
                .compactMap { leaf in
                    guard let tid = leaf.teamIDs.first, let lbl = labels.label(id: tid) else { return nil }
                    return (leaf.positions.lowerBound, lbl, tid == myTeamId)
                }
                .sorted { $0.position < $1.position }
        } else {
            ranking = plan.leagueStandings.enumerated().map {
                ($0.offset + 1, labels.label(name: $0.element.teamName), isMyTeam($0.element.teamName))
            }
        }
        return ranking.filter { $0.position <= 3 }.map {
            ["puesto": $0.position, "equipo": $0.label, "esMio": $0.mine]
        }
    }

    private static func myTeamSummary(
        plan: TournamentPlan,
        myTeamName: String?,
        myTeamId: String?,
        estado: String,
        podio: [[String: Any]],
        clasificacion: [[String: Any]]
    ) -> String? {
        if estado == "finalizado" {
            if let place = podio.first(where: { ($0["esMio"] as? Bool) == true }),
               let pos = place["puesto"] as? Int {
                return "\(pos)º puesto final"
            }
            if plan.format == .leaguePlacement, let name = myTeamName,
               let row = plan.placementFinalTable?.first(where: { $0.teamName == name }) {
                return "\(row.position)º puesto final"
            }
        }
        for table in clasificacion {
            let title = table["titulo"] as? String ?? ""
            let rows = table["filas"] as? [[String: Any]] ?? []
            if let mine = rows.first(where: { ($0["esMio"] as? Bool) == true }),
               let pos = mine["posicion"] as? Int,
               let wins = mine["ganados"] as? Int,
               let losses = mine["perdidos"] as? Int {
                let draws = mine["empatados"] as? Int ?? 0
                let rec = draws > 0 ? "\(wins)G \(draws)E \(losses)P" : "\(wins)G \(losses)P"
                return title.hasPrefix("Grupo ") ? "\(pos)º en \(title) · \(rec)" : "\(pos)º · \(rec)"
            }
        }
        return nil
    }
}

// MARK: - Bloques de varios grupos

struct WebPortalTournamentBlocks {
    var known = Set<Int64>()
    var torneos: [Int64: [String: Any]] = [:]
    var failedClassIds = Set<Int64>()
    var classIdsWithTournaments = Set<Int64>()
    var readClassIds = Set<Int64>()

    func torneos(for studentId: Int64) -> [String: Any]? {
        known.contains(studentId) ? torneos[studentId] : nil
    }

    mutating func add(_ other: WebPortalTournamentBlocks) {
        known.formUnion(other.known)
        for (studentId, block) in other.torneos {
            torneos[studentId] = torneos[studentId].map { WebPortalTournaments.merge($0, block) } ?? block
        }
        failedClassIds.formUnion(other.failedClassIds)
        classIdsWithTournaments.formUnion(other.classIdsWithTournaments)
        readClassIds.formUnion(other.readClassIds)
    }
}

extension WebPortalTournaments {
    /// Construye el bloque `torneos` de todos los alumnos de un grupo (trabajo síncrono puro:
    /// apto para `Task.detached(priority: .utility)`).
    static func blocks(
        classId: Int64,
        groupName: String,
        studentIds: [Int64],
        records: [TournamentRecord],
        settings: WebPortalGroupTournamentSettings,
        now: Date = Date()
    ) -> WebPortalTournamentBlocks {
        var result = WebPortalTournamentBlocks()
        result.known = Set(studentIds)
        result.readClassIds = [classId]

        let visiblePlans: [(id: String, plan: TournamentPlan, showNames: Bool)] = records.compactMap { record in
            guard settings.isVisible(tournamentId: record.id),
                  let plan = decodePlan(from: record) else { return nil }
            return (record.id, plan, settings.showsNames(tournamentId: record.id))
        }
        guard !visiblePlans.isEmpty else { return result }

        // Ordenar: en curso primero, luego planificados, luego finalizados.
        let ordered = visiblePlans.sorted { lhs, rhs in
            let order: [TournamentPlanStatus: Int] = [.live: 0, .scheduled: 1, .finished: 2, .draft: 3]
            return (order[lhs.plan.status] ?? 4) < (order[rhs.plan.status] ?? 4)
        }

        for studentId in studentIds {
            let entries = ordered.map { item in
                tournamentEntry(
                    id: item.id,
                    plan: item.plan,
                    groupName: groupName,
                    studentId: studentId,
                    showNames: item.showNames
                )
            }
            if let block = torneosBlock(entries: entries, now: now) {
                result.torneos[studentId] = block
                result.classIdsWithTournaments.insert(classId)
            }
        }
        return result
    }
}

// MARK: - Enganche con KmpBridge (`suspend` en `@MainActor`; cálculos en segundo plano)

extension KmpBridge {
    /// Bloques `torneos` de todos los grupos con torneos activos, pedidos, pendientes o ya publicados.
    func portalTournamentBlocks(extraClassIds: Set<Int64> = []) async -> WebPortalTournamentBlocks {
        guard let url = WebPortalTournamentSettings.standardURL() else { return WebPortalTournamentBlocks() }
        let settings = WebPortalTournamentSettings.load(fileURL: url)
        let watcher = WebPortalTournamentsWatcher.shared
        let wanted = settings.activeClassIds
            .union(extraClassIds)
            .union(watcher.debouncer.pendingClassIds)
            .union(watcher.publishedState.conTorneos)
        guard !wanted.isEmpty else { return WebPortalTournamentBlocks() }

        var result = WebPortalTournamentBlocks()
        for classId in wanted.sorted() {
            let groupName = classes.first(where: { $0.id == classId })?.name ?? ""
            let groupSettings = settings[classId]
            let roster = try? await container.classesRepository.listStudentsInClass(classId: classId)
            let records = try? await tournaments(forClassId: classId)
            guard let roster, let records else {
                var failed = WebPortalTournamentBlocks()
                failed.failedClassIds = [classId]
                if let roster { failed.known = Set(roster.map(\.id)) }
                result.add(failed)
                continue
            }
            let studentIds = roster.map(\.id)
            let blocks = await Task.detached(priority: .utility) {
                WebPortalTournaments.blocks(
                    classId: classId,
                    groupName: groupName,
                    studentIds: studentIds,
                    records: records,
                    settings: groupSettings
                )
            }.value
            result.add(blocks)
        }
        return result
    }

    /// Para la pestaña «Torneos» de `WebPortalSheet`.
    func portalTournamentOverview(classId: Int64) async -> WebPortalTournamentOverview? {
        guard let records = try? await tournaments(forClassId: classId) else { return nil }
        let studentCount = (try? await container.classesRepository.listStudentsInClass(classId: classId))?.count ?? 0
        return await Task.detached(priority: .utility) {
            let rows = records.map(WebPortalTournaments.row(from:)).reversed()
            return WebPortalTournamentOverview(classId: classId, studentCount: studentCount, tournaments: Array(rows))
        }.value
    }
}

// MARK: - Resumen para no subir duplicados

struct WebPortalTournamentsSummary {
    private var published: [Int64: String] = [:]

    func hasChanged(studentId: Int64, torneos: [String: Any]?) -> Bool {
        published[studentId] != WebPortalTournaments.digest(of: torneos)
    }

    mutating func record(studentId: Int64, torneos: [String: Any]?) {
        published[studentId] = WebPortalTournaments.digest(of: torneos)
    }
}
