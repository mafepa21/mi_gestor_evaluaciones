//
//  LegacyTournamentMigrator.swift
//  MiGestorKMP
//
//  Migra los torneos del módulo antiguo de Educación Física (guardados en UserDefaults como
//  `TournamentViewState`) al motor nuevo: cada uno pasa a ser un `TournamentPlan` guardado
//  como `TournamentRecord` de solo curso (sin Situación de Aprendizaje).
//
//  - Se ejecuta una sola vez (marca en UserDefaults) y es idempotente: el id del registro es el
//    UUID antiguo, y un torneo que ya existe en la base no se vuelve a escribir.
//  - La clave antigua NO se borra: queda como copia de seguridad.
//  - El mapeo (`LegacyTournamentMapper`) es puro y no necesita el bridge.
//

import Foundation
import os
import MiGestorKit

// MARK: - Tipos antiguos (solo para decodificar)

/// Plantillas del módulo antiguo. Los valores de texto son los que se guardaron en UserDefaults.
enum LegacyTournamentTemplate: String, Codable {
    case roundRobin = "Round-robin"
    case knockout = "Eliminatoria"
    case groupsAndKnockout = "Fase de grupos + eliminatoria"
}

/// Estados del módulo antiguo (valores de texto guardados).
enum LegacyTournamentStatus: String, Codable {
    case draft = "Borrador"
    case active = "Activo"
    case closed = "Cerrado"
    case archived = "Archivado"
}

struct LegacyTournamentTeam: Codable {
    let id: UUID
    var name: String
    var colorHex: String
    var studentIds: [Int64]
}

struct LegacyTournamentMatch: Codable {
    let id: UUID
    var phase: String
    var round: Int
    var homeLabel: String
    var awayLabel: String
    var homeTeamId: UUID?
    var awayTeamId: UUID?
    var homeScore: Int
    var awayScore: Int
    var court: String
    var linkedSessionId: Int64?
}

struct LegacyTournamentStudentProfile: Codable {
    let id: Int64
    /// Texto guardado del nivel ("Fuerte", "Medio", "Débil").
    var level: String
    var incompatibleStudentIds: [Int64]
}

/// Mismo formato de JSON que `TournamentViewState` del módulo retirado.
struct LegacyTournamentState: Identifiable, Codable {
    let id: UUID
    let classId: Int64
    var name: String
    var sport: String
    var template: LegacyTournamentTemplate
    var status: LegacyTournamentStatus
    var pointsWin: Int
    var pointsDraw: Int
    var pointsLoss: Int
    var tieBreaker: String
    var teams: [LegacyTournamentTeam]
    var matches: [LegacyTournamentMatch]
    var studentProfiles: [LegacyTournamentStudentProfile]?
    var createdAt: Date
}

// MARK: - Lectura de UserDefaults

enum LegacyTournamentStore {
    /// Clave donde el módulo antiguo guardaba los torneos. No se borra nunca (copia de seguridad).
    static let storageKey = "workspace.pe.tournaments.v1"
    /// Marca de "migración terminada".
    static let migrationFlagKey = "workspace.pe.tournaments.migratedToSda.v1"

    struct LoadResult {
        var tournaments: [LegacyTournamentState]
        /// Elementos del array que no se pudieron leer (se cuentan, no se pierden en silencio).
        var undecodableCount: Int
        /// `true` si hay datos guardados pero el JSON entero no se pudo decodificar como lista.
        /// En ese caso no hay que dar la migración por hecha: los datos siguen en la clave antigua.
        var fileUnreadable = false
    }

    /// Lee elemento a elemento: un torneo corrupto no impide migrar los demás.
    static func load(defaults: UserDefaults = .standard) -> LoadResult {
        guard let data = defaults.data(forKey: storageKey) else {
            return LoadResult(tournaments: [], undecodableCount: 0)
        }
        return decode(data)
    }

    static func decode(_ data: Data) -> LoadResult {
        guard let items = try? JSONDecoder().decode([Lossy<LegacyTournamentState>].self, from: data) else {
            return LoadResult(tournaments: [], undecodableCount: 0, fileUnreadable: true)
        }
        return LoadResult(
            tournaments: items.compactMap(\.value),
            undecodableCount: items.filter { $0.value == nil }.count
        )
    }

    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }
}

// MARK: - Mapeo puro

struct LegacyTournamentMapping {
    var plan: TournamentPlan
    var classId: Int64
    var createdAt: Date
    /// Nombres de equipo que se renombraron por estar repetidos o vacíos (antiguo, nuevo).
    var renamedTeams: [(old: String, new: String)]
    /// Partidos contra «BYE» que no se migran (el motor nuevo no los representa).
    var droppedByeMatches: Int
    /// Marcadores que no se pudieron asignar a equipos reales (cruces sin resolver).
    var droppedResults: Int
}

enum LegacyTournamentMapper {
    static func map(_ legacy: LegacyTournamentState) -> LegacyTournamentMapping {
        // 1. Equipos: id antiguo en texto; nombres únicos.
        var renamed: [(old: String, new: String)] = []
        var usedNames = Set<String>()
        var teams: [TournamentPlanTeam] = []
        var nameByLegacyID: [UUID: String] = [:]
        for (index, team) in legacy.teams.enumerated() {
            let trimmed = team.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = trimmed.isEmpty ? "Equipo \(index + 1)" : trimmed
            var candidate = base
            var suffix = 2
            while usedNames.contains(candidate) {
                candidate = "\(base) (\(suffix))"
                suffix += 1
            }
            usedNames.insert(candidate)
            if candidate != team.name { renamed.append((old: team.name, new: candidate)) }
            nameByLegacyID[team.id] = candidate
            teams.append(
                TournamentPlanTeam(
                    id: team.id.uuidString,
                    name: candidate,
                    studentIDs: team.studentIds.map { String($0) }
                )
            )
        }

        // 2. Partidos válidos (se descartan los de «BYE») conservando el orden.
        let bye = "BYE"
        var kept: [LegacyTournamentMatch] = []
        var droppedBye = 0
        for match in legacy.matches {
            let awayIsBye = match.awayTeamId == nil
                && match.awayLabel.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == bye
            if awayIsBye {
                droppedBye += 1
            } else {
                kept.append(match)
            }
        }

        func stage(for phase: String) -> ScheduledRoundStage {
            if phase == "Liga" { return .league }
            if phase.hasPrefix("Grupo") { return .groupStage }
            return .knockout
        }
        let isLeagueLike: (LegacyTournamentMatch) -> Bool = { stage(for: $0.phase) != .knockout }

        // Posición (1..n) de cada partido eliminatorio entre los eliminatorios: es el «P<n>» del motor.
        let knockoutMatches = kept.filter { !isLeagueLike($0) }
        var knockoutPosition: [UUID: Int] = [:]
        for (offset, match) in knockoutMatches.enumerated() { knockoutPosition[match.id] = offset + 1 }

        /// Nombre del participante para el motor: equipo real, o texto de cruce traducido a su formato.
        func participantName(teamID: UUID?, label: String) -> String {
            if let teamID, let name = nameByLegacyID[teamID] { return name }
            let text = label.trimmingCharacters(in: .whitespacesAndNewlines)
            // «1A» / «2B» -> «Clasificado 1 Grupo A»
            let chars = Array(text)
            if chars.count == 2, let position = chars[0].wholeNumberValue, position > 0, chars[1].isLetter {
                return "Clasificado \(position) Grupo \(String(chars[1]).uppercased())"
            }
            // «Ganador SF1» -> ganador del 1.º partido de la fase «Semifinal».
            if text.hasPrefix("Ganador SF"), let number = Int(text.dropFirst("Ganador SF".count)), number > 0 {
                let semis = knockoutMatches.filter { $0.phase == "Semifinal" }
                if semis.indices.contains(number - 1), let position = knockoutPosition[semis[number - 1].id] {
                    return "Ganador P\(position)"
                }
            }
            // «Ganador <equipo>» -> ganador del partido donde ese equipo era local; sin partido
            // (tenía BYE) el equipo pasa directamente.
            if text.hasPrefix("Ganador ") {
                let teamName = String(text.dropFirst("Ganador ".count))
                if let source = knockoutMatches.first(where: {
                    participantNameForSource($0, nameByLegacyID: nameByLegacyID) == teamName
                }), let position = knockoutPosition[source.id] {
                    return "Ganador P\(position)"
                }
                if usedNames.contains(teamName) { return teamName }
            }
            return text
        }

        // 3. Rondas: (fase, ronda) en orden de aparición.
        struct RoundKey: Hashable { let phase: String; let round: Int }
        var order: [RoundKey] = []
        var grouped: [RoundKey: [LegacyTournamentMatch]] = [:]
        for match in kept {
            let key = RoundKey(phase: match.phase, round: match.round)
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(match)
        }

        var maxVenue = 1
        var rounds: [ScheduledRound] = []
        for (index, key) in order.enumerated() {
            let matches = (grouped[key] ?? []).map { match -> ScheduledMatch in
                let venue = venueNumber(from: match.court)
                maxVenue = max(maxVenue, venue)
                return ScheduledMatch(
                    id: match.id,
                    homeTeam: participantName(teamID: match.homeTeamId, label: match.homeLabel),
                    awayTeam: participantName(teamID: match.awayTeamId, label: match.awayLabel),
                    venueNumber: venue
                )
            }
            // Id de ronda estable (el del primer partido): migrar dos veces da el mismo calendario.
            rounds.append(
                ScheduledRound(id: matches[0].id, number: index + 1, matches: matches, stage: stage(for: key.phase))
            )
        }

        // 4. Resultados. El módulo antiguo no marcaba «jugado»: se considera jugado todo partido
        //    con algún tanto anotado (un 0-0 real no se puede distinguir de «sin jugar»).
        let teamNames = teams.map(\.name)
        let teamNameSet = Set(teamNames)
        var leagueResults: [MatchResult] = []
        var knockoutResults: [KnockoutMatchResult] = []
        var droppedResults = 0
        let scheduledByID = Dictionary(
            rounds.flatMap(\.matches).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let groupCountGuess = Set(kept.filter { $0.phase.hasPrefix("Grupo") }.map(\.phase)).count
        for match in kept where match.homeScore != 0 || match.awayScore != 0 {
            guard let scheduled = scheduledByID[match.id] else { continue }
            if isLeagueLike(match) {
                guard teamNameSet.contains(scheduled.homeTeam), teamNameSet.contains(scheduled.awayTeam) else {
                    droppedResults += 1
                    continue
                }
                leagueResults.append(
                    MatchResult(
                        id: match.id,
                        matchID: match.id,
                        homeTeam: scheduled.homeTeam,
                        awayTeam: scheduled.awayTeam,
                        homeScore: match.homeScore,
                        awayScore: match.awayScore
                    )
                )
            } else {
                // Los cruces («Ganador P2»…) se resuelven con lo ya anotado para guardar equipos reales.
                let home = KnockoutBracketResolver.resolvedParticipant(
                    scheduled.homeTeam, rounds: rounds, results: knockoutResults,
                    groupResults: leagueResults, teamNames: teamNames, groupCount: groupCountGuess
                )
                let away = KnockoutBracketResolver.resolvedParticipant(
                    scheduled.awayTeam, rounds: rounds, results: knockoutResults,
                    groupResults: leagueResults, teamNames: teamNames, groupCount: groupCountGuess
                )
                guard teamNameSet.contains(home), teamNameSet.contains(away) else {
                    droppedResults += 1
                    continue
                }
                knockoutResults.append(
                    KnockoutMatchResult(
                        matchID: match.id,
                        homeTeam: home,
                        awayTeam: away,
                        homeScore: match.homeScore,
                        awayScore: match.awayScore
                    )
                )
            }
        }

        // 5. Formato, estado y configuración.
        let format: TournamentFormat
        switch legacy.template {
        case .roundRobin: format = .roundRobin
        case .knockout: format = .knockout
        case .groupsAndKnockout: format = .groupStageKnockout
        }
        let status: TournamentPlanStatus
        switch legacy.status {
        case .draft: status = rounds.isEmpty ? .draft : .scheduled
        case .active: status = rounds.isEmpty ? .draft : .live
        case .closed, .archived: status = .finished
        }

        var plan = TournamentPlan(
            id: legacy.id,
            name: legacy.name,
            startDate: legacy.createdAt,
            format: format,
            teams: teams,
            groupCount: format == .groupStageKnockout ? max(2, groupCountGuess) : 0,
            qualifiedTeamsPerGroup: 2,
            venueCount: maxVenue,
            status: status
        )
        plan.savedSchedule = rounds
        plan.savedResults = leagueResults
        plan.savedKnockoutResults = knockoutResults
        plan.legacyExtras = TournamentLegacyExtras(
            sport: legacy.sport,
            pointsWin: legacy.pointsWin,
            pointsDraw: legacy.pointsDraw,
            pointsLoss: legacy.pointsLoss,
            tieBreaker: legacy.tieBreaker,
            legacyTemplate: legacy.template.rawValue,
            legacyStatus: legacy.status.rawValue,
            originalCreatedAt: legacy.createdAt,
            teamColorHexByTeamID: Dictionary(
                legacy.teams.map { ($0.id.uuidString, $0.colorHex) },
                uniquingKeysWith: { first, _ in first }
            ),
            linkedSessionIDByMatchID: Dictionary(
                legacy.matches.compactMap { match in
                    match.linkedSessionId.map { (match.id.uuidString, $0) }
                },
                uniquingKeysWith: { first, _ in first }
            ),
            studentProfiles: (legacy.studentProfiles ?? []).map {
                TournamentLegacyExtras.StudentProfile(
                    studentID: String($0.id),
                    level: $0.level,
                    incompatibleStudentIDs: $0.incompatibleStudentIds.map { String($0) }
                )
            }
        )

        return LegacyTournamentMapping(
            plan: plan,
            classId: legacy.classId,
            createdAt: legacy.createdAt,
            renamedTeams: renamed,
            droppedByeMatches: droppedBye,
            droppedResults: droppedResults
        )
    }

    /// Registro de solo curso (sin SdA) listo para `saveTournament`. El id es el UUID antiguo.
    static func record(for mapping: LegacyTournamentMapping) throws -> TournamentRecord {
        let columns = try mapping.plan.columns()
        return TournamentRecord(
            id: columns.id,
            learningSituationId: nil,
            classId: mapping.classId,
            tabId: nil,
            name: columns.name,
            format: mapping.plan.format.rawValue,
            status: mapping.plan.status.rawValue,
            configJSON: columns.configJSON,
            teamSnapshotJSON: columns.teamSnapshotJSON,
            scheduleJSON: columns.scheduleJSON,
            resultsJSON: columns.resultsJSON,
            knockoutResultsJSON: columns.knockoutResultsJSON,
            createdAt: mapping.createdAt
        )
    }

    /// Número de pista: primer número que aparezca en el texto («Pista 2» -> 2), o 1.
    static func venueNumber(from court: String) -> Int {
        var digits = ""
        for character in court {
            if character.isNumber, let _ = character.wholeNumberValue {
                digits.append(character)
            } else if !digits.isEmpty {
                break
            }
        }
        guard let value = Int(digits), value > 0 else { return 1 }
        return value
    }

    private static func participantNameForSource(
        _ match: LegacyTournamentMatch,
        nameByLegacyID: [UUID: String]
    ) -> String {
        if let id = match.homeTeamId, let name = nameByLegacyID[id] { return name }
        return match.homeLabel
    }
}

// MARK: - Ejecución al arrancar

@MainActor
extension KmpBridge {
    /// Migra una sola vez los torneos antiguos de EF. Seguro de repetir: no duplica ni pisa
    /// torneos ya migrados. Si algún guardado falla, no pone la marca y se reintenta al siguiente arranque.
    func migrateLegacyTournamentsIfNeeded(defaults: UserDefaults = .standard) async {
        guard !defaults.bool(forKey: LegacyTournamentStore.migrationFlagKey) else { return }
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MiGestorKMP", category: "LegacyTournamentMigration")
        let loaded = LegacyTournamentStore.load(defaults: defaults)
        if loaded.undecodableCount > 0 {
            logger.error("Torneos antiguos ilegibles: \(loaded.undecodableCount). Se conservan en la clave antigua sin migrar.")
        }
        if loaded.fileUnreadable {
            // No se pone la marca: los datos siguen en la clave antigua y se reintenta al siguiente arranque.
            logger.error("Los torneos antiguos no se pudieron leer (JSON no válido). No se marca la migración como terminada.")
            return
        }
        guard !loaded.tournaments.isEmpty else {
            defaults.set(true, forKey: LegacyTournamentStore.migrationFlagKey)
            return
        }

        // Se pregunta directamente al repositorio: `ensureClassesLoaded()` traga los errores y,
        // si los cursos aún no han llegado, se descartarían todos los torneos por error.
        let knownClassIds: Set<Int64>
        do {
            knownClassIds = Set(try await container.classesRepository.listClasses().map(\.id))
        } catch {
            logger.error("No se pudieron cargar los cursos para migrar los torneos antiguos: \(error.localizedDescription). Se reintenta en el siguiente arranque.")
            return
        }
        guard !knownClassIds.isEmpty else {
            // Sin cursos no se puede saber si un torneo es huérfano o si los cursos aún no han llegado (p. ej. por sync).
            logger.notice("Hay \(loaded.tournaments.count) torneos antiguos pero todavía no hay cursos. Se reintenta en el siguiente arranque.")
            return
        }
        var failures = 0
        var migrated = 0
        for legacy in loaded.tournaments {
            // Con la lista de cursos cargada y no vacía, un curso inexistente es un descarte definitivo.
            guard knownClassIds.contains(legacy.classId) else {
                logger.notice("Torneo «\(legacy.name)» omitido: su curso \(legacy.classId) ya no existe.")
                continue
            }
            do {
                let alreadyThere = try await container.learningSituationsRepository
                    .getTournament(id: legacy.id.uuidString) != nil
                if alreadyThere { continue }
                let mapping = LegacyTournamentMapper.map(legacy)
                try await saveTournament(try LegacyTournamentMapper.record(for: mapping))
                migrated += 1
            } catch {
                failures += 1
                logger.error("No se pudo migrar el torneo «\(legacy.name)»: \(error.localizedDescription)")
            }
        }
        logger.notice("Torneos antiguos migrados: \(migrated). Fallos: \(failures). Ilegibles: \(loaded.undecodableCount).")
        if failures == 0 {
            defaults.set(true, forKey: LegacyTournamentStore.migrationFlagKey)
        }
    }
}
