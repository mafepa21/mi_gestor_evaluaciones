//
//  KmpBridge+Tournaments.swift
//  MiGestorKMP
//
//  Torneos dentro de la Situación de Aprendizaje: persistencia compartida (SQLDelight)
//  y sincronización LAN. El motor del torneo vive en Swift; KMP solo guarda los JSON.
//

import Foundation
import MiGestorKit

/// Torneo de una Situación de Aprendizaje en tipos Swift simples.
/// Los bloques `*JSON` son cadenas opacas para KMP: las codifica y decodifica el motor Swift.
struct TournamentRecord: Identifiable, Equatable, Sendable {
    /// UUID en texto, generado por quien crea el torneo (no choca entre dispositivos).
    var id: String
    /// `nil` si el torneo es solo de un curso (p. ej. migrado del módulo antiguo de EF).
    var learningSituationId: Int64?
    var classId: Int64
    var tabId: String?
    var name: String
    /// Formato del torneo (clave libre del motor, p. ej. "league", "knockout").
    var format: String
    /// Estado del torneo ("draft" por defecto).
    var status: String
    var configJSON: String
    var teamSnapshotJSON: String
    var scheduleJSON: String
    var resultsJSON: String
    var knockoutResultsJSON: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        learningSituationId: Int64? = nil,
        classId: Int64,
        tabId: String? = nil,
        name: String,
        format: String,
        status: String = "draft",
        configJSON: String = "{}",
        teamSnapshotJSON: String = "[]",
        scheduleJSON: String = "[]",
        resultsJSON: String = "{}",
        knockoutResultsJSON: String = "{}",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.learningSituationId = learningSituationId
        self.classId = classId
        self.tabId = tabId
        self.name = name
        self.format = format
        self.status = status
        self.configJSON = configJSON
        self.teamSnapshotJSON = teamSnapshotJSON
        self.scheduleJSON = scheduleJSON
        self.resultsJSON = resultsJSON
        self.knockoutResultsJSON = knockoutResultsJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Alumno miembro de un equipo (grupo de trabajo) con su nombre ya resuelto.
struct TournamentTeamMember: Identifiable, Equatable, Sendable {
    var studentId: Int64
    var fullName: String
    var id: Int64 { studentId }
}

/// Grupo de trabajo vinculado a una SdA, listo para usarse como equipo de un torneo.
struct TournamentWorkGroupTeam: Identifiable, Equatable, Sendable {
    var groupId: Int64
    var classId: Int64
    var tabId: String
    var name: String
    var members: [TournamentTeamMember]
    var id: Int64 { groupId }
}

@MainActor
extension KmpBridge {
    /// Torneos de una SdA, del más antiguo al más reciente.
    func tournaments(forLearningSituationId learningSituationId: Int64) async throws -> [TournamentRecord] {
        try await container.learningSituationsRepository
            .listTournaments(learningSituationId: learningSituationId)
            .map(Self.tournamentRecord(from:))
    }

    /// Torneos de un curso, con o sin SdA, del más antiguo al más reciente.
    func tournaments(forClassId classId: Int64) async throws -> [TournamentRecord] {
        try await container.learningSituationsRepository
            .listTournamentsByClass(classId: classId)
            .map(Self.tournamentRecord(from:))
    }

    /// Crea o actualiza un torneo y lo encola para SyncLAN. Devuelve el registro tal como quedó guardado.
    @discardableResult
    func saveTournament(_ record: TournamentRecord) async throws -> TournamentRecord {
        let repository = container.learningSituationsRepository
        let existing = try await repository.getTournament(id: record.id)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let now = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        let trace = AuditTrace(
            authorUserId: nil,
            createdAt: existing?.trace.createdAt ?? now,
            updatedAt: now,
            associatedGroupId: nil,
            deviceId: localDeviceId,
            syncVersion: (existing?.trace.syncVersion ?? 0) + 1
        )
        try await repository.saveTournament(
            tournament: LearningSituationTournament(
                id: record.id,
                learningSituationId: record.learningSituationId.map { KotlinLong(value: $0) },
                classId: record.classId,
                tabId: record.tabId,
                name: record.name,
                format: record.format,
                status: record.status,
                configJson: record.configJSON,
                teamSnapshotJson: record.teamSnapshotJSON,
                scheduleJson: record.scheduleJSON,
                resultsJson: record.resultsJSON,
                knockoutResultsJson: record.knockoutResultsJSON,
                trace: trace
            )
        )
        enqueueLocalChange(
            entity: "learning_situation_tournament",
            id: record.id,
            updatedAtEpochMs: nowMs,
            payload: [
                "id": record.id,
                "learningSituationId": record.learningSituationId ?? NSNull(),
                "classId": record.classId,
                "tabId": record.tabId ?? NSNull(),
                "name": record.name,
                "format": record.format,
                "status": record.status,
                "configJson": record.configJSON,
                "teamSnapshotJson": record.teamSnapshotJSON,
                "scheduleJson": record.scheduleJSON,
                "resultsJson": record.resultsJSON,
                "knockoutResultsJson": record.knockoutResultsJSON
            ]
        )
        guard let saved = try await repository.getTournament(id: record.id) else { return record }
        return Self.tournamentRecord(from: saved)
    }

    /// Borra un torneo y propaga el borrado por SyncLAN.
    func deleteTournament(id: String) async throws {
        try await container.learningSituationsRepository.deleteTournament(id: id)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        enqueueLocalChange(
            entity: "learning_situation_tournament",
            id: id,
            updatedAtEpochMs: nowMs,
            payload: ["id": id],
            op: "delete"
        )
    }

    /// Grupos de trabajo vinculados a la SdA (`learningSituationId`) con sus miembros y nombres de alumno.
    /// Se recorren los cursos vinculados a la SdA; un grupo sin vínculo con la SdA nunca se devuelve.
    func workGroupsLinkedToLearningSituation(learningSituationId: Int64) async throws -> [TournamentWorkGroupTeam] {
        let links = try await container.learningSituationsRepository
            .listClassLinks(learningSituationId: learningSituationId)
        var teams: [TournamentWorkGroupTeam] = []
        for classId in Set(links.map(\.classId)).sorted() {
            let groups = try await container.notebookConfigRepository
                .listWorkGroups(classId: classId, tabId: nil)
                .filter { $0.learningSituationId?.int64Value == learningSituationId }
            guard !groups.isEmpty else { continue }
            let members = try await container.notebookConfigRepository
                .listWorkGroupMembers(classId: classId, tabId: nil)
            let roster = try await container.classesRepository.listStudentsInClass(classId: classId)
            let namesById = Dictionary(roster.map { ($0.id, $0.fullName) }, uniquingKeysWith: { first, _ in first })
            for group in groups.sorted(by: { ($0.order, $0.id) < ($1.order, $1.id) }) {
                let groupMembers = members
                    .filter { $0.groupId == group.id }
                    .compactMap { member -> TournamentTeamMember? in
                        guard let name = namesById[member.studentId] else { return nil }
                        return TournamentTeamMember(studentId: member.studentId, fullName: name)
                    }
                    .sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending }
                teams.append(
                    TournamentWorkGroupTeam(
                        groupId: group.id,
                        classId: classId,
                        tabId: group.tabId,
                        name: group.name,
                        members: groupMembers
                    )
                )
            }
        }
        return teams
    }

    private static func tournamentRecord(from row: LearningSituationTournament) -> TournamentRecord {
        TournamentRecord(
            id: row.id,
            learningSituationId: row.learningSituationId?.int64Value,
            classId: row.classId,
            tabId: row.tabId,
            name: row.name,
            format: row.format,
            status: row.status,
            configJSON: row.configJson,
            teamSnapshotJSON: row.teamSnapshotJson,
            scheduleJSON: row.scheduleJson,
            resultsJSON: row.resultsJson,
            knockoutResultsJSON: row.knockoutResultsJson,
            createdAt: Date(timeIntervalSince1970: TimeInterval(row.trace.createdAt.toEpochMilliseconds()) / 1000),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(row.trace.updatedAt.toEpochMilliseconds()) / 1000)
        )
    }
}
