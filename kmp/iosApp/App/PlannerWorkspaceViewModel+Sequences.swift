import SwiftUI
import MiGestorKit

@MainActor
extension PlannerWorkspaceViewModel {
    func sequenceGroups() -> [(key: String, title: String, groupName: String, sessions: [PlanningSession])] {
        let grouped = Dictionary(grouping: filteredPlannerSessions()) { session in
            "\(session.groupId)-\(session.teachingUnitId)-\(normalizedSituationTitle(session.teachingUnitName))"
        }
        return grouped.compactMap { key, sessions in
            guard let first = sessions.first else { return nil }
            return (
                key: key,
                title: first.teachingUnitName.nilIfBlank ?? "Situación sin título",
                groupName: first.groupName,
                sessions: sessions.sorted {
                    if $0.weekNumber == $1.weekNumber {
                        if $0.dayOfWeek == $1.dayOfWeek { return $0.period < $1.period }
                        return $0.dayOfWeek < $1.dayOfWeek
                    }
                    return $0.weekNumber < $1.weekNumber
                }
            )
        }
        .sorted { lhs, rhs in
            lhs.groupName == rhs.groupName ? lhs.title < rhs.title : lhs.groupName < rhs.groupName
        }
    }

    func loadEnrichedSequences() async {
        guard let bridge = self.bridge else { return }
        isLoadingSequences = true
        defer { isLoadingSequences = false }
        
        do {
            let allSessions = try await bridge.plannerListAllSessions()
            let filteredSessions = allSessions.filter { session in
                self.selectedGroupId.map { session.groupId == $0 } ?? true
            }
            
            var uniqueSequenceVersionIds = Set<Int64>()
            for session in filteredSessions {
                if let planId = session.learningSituationSessionPlanId?.int64Value {
                    if let plan = try? await bridge.learningSituationSessionPlan(id: planId) {
                        uniqueSequenceVersionIds.insert(plan.sequenceVersionId)
                    }
                }
            }
            
            var sessionPlansBySequence: [Int64: [LearningSituationSessionPlan]] = [:]
            for seqId in uniqueSequenceVersionIds {
                if let plans = try? await bridge.learningSituationSessionPlans(sequenceVersionId: seqId) {
                    sessionPlansBySequence[seqId] = plans.sorted { $0.sessionNumber < $1.sessionNumber }
                }
            }
            
            var enriched: [PlannerSequenceGroup] = []
            let groupNames = Dictionary(uniqueKeysWithValues: self.groups.map { ($0.id, $0.name) })
            let sessionsByGroup = Dictionary(grouping: filteredSessions, by: { $0.groupId })
            
            for (groupId, groupSessions) in sessionsByGroup {
                let groupName = groupNames[groupId] ?? "Grupo \(groupId)"
                var seqIdBySessionId: [Int64: Int64] = [:]
                var planBySessionId: [Int64: LearningSituationSessionPlan] = [:]
                
                for session in groupSessions {
                    if let planId = session.learningSituationSessionPlanId?.int64Value {
                        if let plan = try? await bridge.learningSituationSessionPlan(id: planId) {
                            seqIdBySessionId[session.id] = plan.sequenceVersionId
                            planBySessionId[session.id] = plan
                        }
                    }
                }
                
                let sessionsWithSeq = groupSessions.filter { seqIdBySessionId[$0.id] != nil }
                let sessionsWithoutSeq = groupSessions.filter { seqIdBySessionId[$0.id] == nil }
                let sessionsBySeqId = Dictionary(grouping: sessionsWithSeq, by: { seqIdBySessionId[$0.id]! })
                
                for (seqId, seqSessions) in sessionsBySeqId {
                    guard let sortedPlans = sessionPlansBySequence[seqId] else { continue }
                    let firstSeqSession = seqSessions.first
                    let seqTitle = sortedPlans.first?.title.nilIfBlank 
                        ?? firstSeqSession?.teachingUnitName.nilIfBlank 
                        ?? "Secuencia didáctica"
                    
                    var rows: [PlannerSequenceRow] = []
                    var mappedSessionIds = Set<Int64>()
                    
                    for plan in sortedPlans {
                        let matchingSession = seqSessions.first { $0.learningSituationSessionPlanId?.int64Value == plan.id }
                        
                        if let session = matchingSession {
                            mappedSessionIds.insert(session.id)
                            let isCompleted = session.status == .completed || self.journalSummaryBySessionId[session.id]?.status == .completed
                            let statusText: String
                            let statusIcon: String
                            let statusColor: Color
                            
                            if isCompleted {
                                statusText = "Cerrada"
                                statusIcon = "checkmark.seal.fill"
                                statusColor = Color.green
                            } else if session.status == .completed {
                                statusText = "Impartida"
                                statusIcon = "checkmark.circle.fill"
                                statusColor = Color.green
                            } else if session.status == .inProgress {
                                statusText = "En Curso"
                                statusIcon = "circle.lefthalf.filled"
                                statusColor = Color.yellow
                            } else if session.status == .cancelled {
                                statusText = "Cancelada"
                                statusIcon = "xmark.circle.fill"
                                statusColor = Color.red
                            } else {
                                statusText = "Planificada"
                                statusIcon = "circle"
                                statusColor = EvaluationDesign.accent
                            }
                            
                            rows.append(PlannerSequenceRow(
                                id: "plan-\(plan.id)-session-\(session.id)",
                                sessionNumber: Int(plan.sessionNumber),
                                title: plan.title,
                                objective: plan.objective,
                                statusText: statusText,
                                statusIcon: statusIcon,
                                statusColor: statusColor,
                                planningSession: session,
                                learningSituationSessionPlanId: plan.id
                            ))
                        } else {
                            rows.append(PlannerSequenceRow(
                                id: "plan-\(plan.id)-unlocated",
                                sessionNumber: Int(plan.sessionNumber),
                                title: plan.title,
                                objective: plan.objective,
                                statusText: "Pendiente de ubicar",
                                statusIcon: "calendar.badge.plus",
                                statusColor: Color.orange,
                                planningSession: nil,
                                learningSituationSessionPlanId: plan.id
                            ))
                        }
                    }
                    
                    let unmappedSeqSessions = seqSessions.filter { !mappedSessionIds.contains($0.id) }
                    for session in unmappedSeqSessions {
                        rows.append(PlannerSequenceRow(
                            id: "session-fallback-\(session.id)",
                            sessionNumber: rows.count + 1,
                            title: session.objectives.nilIfBlank ?? "Sesión de calendario",
                            objective: session.activities,
                            statusText: "Solo calendario",
                            statusIcon: "calendar",
                            statusColor: Color.secondary,
                            planningSession: session,
                            learningSituationSessionPlanId: session.learningSituationSessionPlanId?.int64Value
                        ))
                    }
                    
                    let plannedCount = rows.count { $0.statusText == "Planificada" }
                    let pendingCount = rows.count { $0.statusText == "Pendiente de ubicar" }
                    let completedCount = rows.count { $0.statusText == "Cerrada" || $0.statusText == "Impartida" }
                    
                    enriched.append(PlannerSequenceGroup(
                        id: "\(groupId)-seq-\(seqId)",
                        title: seqTitle,
                        groupName: groupName,
                        groupId: groupId,
                        sequenceVersionId: seqId,
                        totalSessionsCount: sortedPlans.count,
                        plannedCount: plannedCount,
                        pendingCount: pendingCount,
                        completedCount: completedCount,
                        closedCount: rows.count { $0.statusText == "Cerrada" },
                        rows: rows
                    ))
                }
                
                let groupedFallback = Dictionary(grouping: sessionsWithoutSeq, by: { "\($0.teachingUnitId)-\(self.normalizedSituationTitle($0.teachingUnitName))" })
                for (fallbackKey, fallbackSessions) in groupedFallback {
                    guard let first = fallbackSessions.first else { continue }
                    let title = first.teachingUnitName.nilIfBlank ?? "Situación sin título"
                    
                    let sortedFallbackSessions = fallbackSessions.sorted {
                        if $0.weekNumber == $1.weekNumber {
                            if $0.dayOfWeek == $1.dayOfWeek { return $0.period < $1.period }
                            return $0.dayOfWeek < $1.dayOfWeek
                        }
                        return $0.weekNumber < $1.weekNumber
                    }
                    
                    let rows = sortedFallbackSessions.enumerated().map { index, session in
                        let isCompleted = session.status == .completed || self.journalSummaryBySessionId[session.id]?.status == .completed
                        let statusText: String
                        let statusIcon: String
                        let statusColor: Color
                        
                        if isCompleted {
                            statusText = "Cerrada"
                            statusIcon = "checkmark.seal.fill"
                            statusColor = Color.green
                        } else if session.status == .completed {
                            statusText = "Impartida"
                            statusIcon = "checkmark.circle.fill"
                            statusColor = Color.green
                        } else {
                            statusText = "Solo calendario"
                            statusIcon = "calendar"
                            statusColor = Color.secondary
                        }
                        
                        return PlannerSequenceRow(
                            id: "fallback-session-\(session.id)",
                            sessionNumber: index + 1,
                            title: session.objectives.nilIfBlank ?? "Sesión de calendario",
                            objective: session.activities,
                            statusText: statusText,
                            statusIcon: statusIcon,
                            statusColor: statusColor,
                            planningSession: session,
                            learningSituationSessionPlanId: session.learningSituationSessionPlanId?.int64Value
                        )
                    }
                    
                    let plannedCount = rows.count { $0.statusText == "Planificada" || $0.statusText == "Solo calendario" }
                    let completedCount = rows.count { $0.statusText == "Cerrada" || $0.statusText == "Impartida" }
                    
                    enriched.append(PlannerSequenceGroup(
                        id: "\(groupId)-fallback-\(fallbackKey)",
                        title: title,
                        groupName: groupName,
                        groupId: groupId,
                        sequenceVersionId: nil,
                        totalSessionsCount: rows.count,
                        plannedCount: plannedCount,
                        pendingCount: 0,
                        completedCount: completedCount,
                        closedCount: rows.count { $0.statusText == "Cerrada" },
                        rows: rows
                    ))
                }
            }
            
            self.sequenceGroupsEnriched = enriched.sorted { lhs, rhs in
                lhs.groupName == rhs.groupName ? lhs.title < rhs.title : lhs.groupName < rhs.groupName
            }
        } catch {
            print("Error loading enriched sequences: \(error)")
        }
    }

}

private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        switch self?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case .some(let value) where !value.isEmpty: return value
        default: return nil
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
