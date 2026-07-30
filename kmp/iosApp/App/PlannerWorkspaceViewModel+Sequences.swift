import SwiftUI
import MiGestorKit

/// Grupo resultante de `sequenceGroups()`. Se usa una estructura nombrada en lugar de una
/// tupla con 4 etiquetas porque esta última hacía que el inferidor de tipos del compilador
/// se atascara (timeout de type-check) al inferir el tipo del `compactMap` de más abajo.
/// Nota: no confundir con `PlannerSequenceGroup` (definida en PlannerModels.swift), que es
/// un modelo distinto usado por `loadEnrichedSequences()`.
struct PlannerFilteredSequenceGroup {
    let key: String
    let title: String
    let groupName: String
    let sessions: [PlanningSession]
}

private struct PlannerSequenceCatalogEntry {
    let situationTitle: String
    let groupId: Int64
    let sequenceVersionId: Int64
    let equivalentVersionIds: Set<Int64>
    let plans: [LearningSituationSessionPlan]
}

enum PlannerSequenceVersionProjection {
    static func equivalentVersionIds(
        latestSha256: String,
        versions: [(id: Int64, sha256: String)]
    ) -> Set<Int64> {
        Set(versions.filter { $0.sha256 == latestSha256 }.map(\.id))
    }
}

@MainActor
extension PlannerWorkspaceViewModel {
    func sequenceGroups() -> [PlannerFilteredSequenceGroup] {
        let grouped = Dictionary(grouping: filteredPlannerSessions()) { session in
            "\(session.groupId)-\(session.teachingUnitId)-\(normalizedSituationTitle(session.teachingUnitName))"
        }
        let items: [PlannerFilteredSequenceGroup] = grouped.compactMap { key, sessions in
            guard let first = sessions.first else { return nil }
            let titleText: String = first.teachingUnitName.nilIfBlank ?? "Situación sin título"
            let sortedSessions: [PlanningSession] = sessions.sorted { lhs, rhs in
                if lhs.weekNumber == rhs.weekNumber {
                    if lhs.dayOfWeek == rhs.dayOfWeek { return lhs.period < rhs.period }
                    return lhs.dayOfWeek < rhs.dayOfWeek
                }
                return lhs.weekNumber < rhs.weekNumber
            }
            return PlannerFilteredSequenceGroup(key: key, title: titleText, groupName: first.groupName, sessions: sortedSessions)
        }
        return items.sorted { lhs, rhs in
            lhs.groupName == rhs.groupName ? lhs.title < rhs.title : lhs.groupName < rhs.groupName
        }
    }

    func loadEnrichedSequences() async {
        guard let bridge = self.bridge else { return }
        let requestedGroupId = selectedGroupId
        isLoadingSequences = true
        sequenceLoadErrorMessage = nil
        defer {
            if requestedGroupId == selectedGroupId {
                isLoadingSequences = false
            }
        }
        
        do {
            let allSessions = try await bridge.plannerListAllSessions()
            try Task.checkCancellation()
            let filteredSessions = allSessions.filter { session in
                requestedGroupId.map { session.groupId == $0 } ?? true
            }

            let situations = try await bridge.learningSituations()
            try Task.checkCancellation()
            let groupNames = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.name) })
            let allowedGroupIds = Set(groupNames.keys.filter { classId in
                requestedGroupId.map { classId == $0 } ?? true
            })

            var catalog: [PlannerSequenceCatalogEntry] = []
            for situation in situations {
                try Task.checkCancellation()
                let links = try await bridge.learningSituationClassLinks(id: situation.id)
                    .filter { allowedGroupIds.contains($0.classId) }
                guard !links.isEmpty else { continue }

                let versions = try await bridge.learningSituationSessionSequenceVersions(
                    learningSituationId: situation.id
                )
                guard let latestVersion = versions.max(by: { $0.versionNumber < $1.versionNumber }) else {
                    continue
                }
                let plans = try await bridge.learningSituationSessionPlans(sequenceVersionId: latestVersion.id)
                    .sorted { $0.sessionNumber < $1.sessionNumber }
                guard !plans.isEmpty else { continue }
                let equivalentVersionIds = PlannerSequenceVersionProjection.equivalentVersionIds(
                    latestSha256: latestVersion.sha256,
                    versions: versions.map { (id: $0.id, sha256: $0.sha256) }
                )

                for link in links {
                    catalog.append(
                        PlannerSequenceCatalogEntry(
                            situationTitle: situation.title.nilIfBlank ?? "Situación sin título",
                            groupId: link.classId,
                            sequenceVersionId: latestVersion.id,
                            equivalentVersionIds: equivalentVersionIds,
                            plans: plans
                        )
                    )
                }
            }

            var planBySessionId: [Int64: LearningSituationSessionPlan] = [:]
            for session in filteredSessions {
                if let planId = session.learningSituationSessionPlanId?.int64Value {
                    planBySessionId[session.id] = try await bridge.learningSituationSessionPlan(id: planId)
                }
            }

            try Task.checkCancellation()
            var enriched: [PlannerSequenceGroup] = []
            var catalogSessionIds = Set<Int64>()

            for entry in catalog {
                let sequenceSessions = filteredSessions.filter { session in
                    session.groupId == entry.groupId
                        && planBySessionId[session.id].map {
                            entry.equivalentVersionIds.contains($0.sequenceVersionId)
                        } == true
                }
                catalogSessionIds.formUnion(sequenceSessions.map(\.id))
                var rows: [PlannerSequenceRow] = []

                for plan in entry.plans {
                    let matchingSession = sequenceSessions.first {
                        planBySessionId[$0.id]?.sessionNumber == plan.sessionNumber
                    }
                    rows.append(
                        PlannerSequenceRow(
                            id: matchingSession.map { "plan-\(plan.id)-session-\($0.id)" } ?? "plan-\(plan.id)-unlocated",
                            sessionNumber: Int(plan.sessionNumber),
                            title: plan.title,
                            objective: plan.objective,
                            status: matchingSession.map { sequenceStatus(for: $0) } ?? .unlocated,
                            planningSession: matchingSession,
                            learningSituationSessionPlanId: plan.id
                        )
                    )
                }

                enriched.append(
                    makeSequenceGroup(
                        id: "\(entry.groupId)-seq-\(entry.sequenceVersionId)",
                        title: entry.situationTitle,
                        groupName: groupNames[entry.groupId] ?? "Grupo \(entry.groupId)",
                        groupId: entry.groupId,
                        sequenceVersionId: entry.sequenceVersionId,
                        rows: rows,
                        theoreticalTotal: entry.plans.count
                    )
                )
            }

            let fallbackSessions = filteredSessions.filter { !catalogSessionIds.contains($0.id) }
            let fallbackGroups = Dictionary(grouping: fallbackSessions) {
                "\($0.groupId)-\($0.teachingUnitId)-\(normalizedSituationTitle($0.teachingUnitName))"
            }
            for (fallbackKey, sessions) in fallbackGroups {
                guard let first = sessions.first else { continue }
                let sorted = sessions.sorted {
                    if $0.year != $1.year { return $0.year < $1.year }
                    if $0.weekNumber != $1.weekNumber { return $0.weekNumber < $1.weekNumber }
                    if $0.dayOfWeek != $1.dayOfWeek { return $0.dayOfWeek < $1.dayOfWeek }
                    return $0.period < $1.period
                }
                let rows = sorted.enumerated().map { index, session in
                    PlannerSequenceRow(
                        id: "fallback-session-\(session.id)",
                        sessionNumber: index + 1,
                        title: session.objectives.nilIfBlank ?? "Sesión de calendario",
                        objective: session.activities,
                        status: fallbackStatus(for: session),
                        planningSession: session,
                        learningSituationSessionPlanId: session.learningSituationSessionPlanId?.int64Value
                    )
                }
                enriched.append(
                    makeSequenceGroup(
                        id: "\(first.groupId)-fallback-\(fallbackKey)",
                        title: first.teachingUnitName.nilIfBlank ?? "Situación sin título",
                        groupName: groupNames[first.groupId] ?? first.groupName,
                        groupId: first.groupId,
                        sequenceVersionId: nil,
                        rows: rows,
                        theoreticalTotal: rows.count
                    )
                )
            }

            try Task.checkCancellation()
            guard requestedGroupId == selectedGroupId else { return }
            sequenceGroupsEnriched = enriched.sorted {
                $0.groupName == $1.groupName ? $0.title < $1.title : $0.groupName < $1.groupName
            }
        } catch is CancellationError {
            return
        } catch {
            guard requestedGroupId == selectedGroupId else { return }
            sequenceGroupsEnriched = []
            sequenceLoadErrorMessage = error.localizedDescription
        }
    }

    private func sequenceStatus(for session: PlanningSession) -> PlannerSequenceStatus {
        if journalSummaryBySessionId[session.id]?.status == .completed {
            return .closed
        }
        switch session.status {
        case .completed: return .taught
        case .inProgress: return .inProgress
        case .cancelled: return .cancelled
        default: return .planned
        }
    }

    private func fallbackStatus(for session: PlanningSession) -> PlannerSequenceStatus {
        let status = sequenceStatus(for: session)
        return status == .planned ? .calendarOnly : status
    }

    private func makeSequenceGroup(
        id: String,
        title: String,
        groupName: String,
        groupId: Int64,
        sequenceVersionId: Int64?,
        rows: [PlannerSequenceRow],
        theoreticalTotal: Int
    ) -> PlannerSequenceGroup {
        PlannerSequenceGroup(
            id: id,
            title: title,
            groupName: groupName,
            groupId: groupId,
            sequenceVersionId: sequenceVersionId,
            totalSessionsCount: theoreticalTotal,
            plannedCount: rows.count { $0.status == .planned || $0.status == .inProgress || $0.status == .calendarOnly },
            pendingCount: rows.count { $0.status == .unlocated },
            completedCount: rows.count { $0.status.isCompleted },
            closedCount: rows.count { $0.status == .closed },
            taughtCount: rows.count { $0.status == .taught },
            cancelledCount: rows.count { $0.status == .cancelled },
            rows: rows
        )
    }
}
