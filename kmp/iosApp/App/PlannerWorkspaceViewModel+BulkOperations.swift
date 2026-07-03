import SwiftUI
import MiGestorKit

@MainActor
extension PlannerWorkspaceViewModel {
    func toggleSelection(sessionId: Int64) {
        if selectedSessionIds.contains(sessionId) {
            selectedSessionIds.remove(sessionId)
        } else {
            selectedSessionIds.insert(sessionId)
        }
    }

    func bulkCopyToNextWeek() async {
        guard let bridge, !selectedSessionIds.isEmpty else { return }
        let result = try? await bridge.plannerCopySessions(
            sourceSessionIds: Array(selectedSessionIds),
            targetGroupId: nil,
            dayOffset: 7,
            periodOffset: 0,
            resolution: .skip
        )
        if let result {
            bulkSummary = "Copiadas \(result.movedOrCopied) · omitidas \(result.skipped + result.failed)"
        }
        selectionMode = false
        selectedSessionIds.removeAll()
        await reloadSessionsOnly()
    }

    func bulkMoveOneDay() async {
        guard let bridge, !selectedSessionIds.isEmpty else { return }
        let result = try? await bridge.plannerShiftSessions(
            sourceSessionIds: Array(selectedSessionIds),
            dayOffset: 1,
            periodOffset: 0,
            resolution: .skip
        )
        if let result {
            bulkSummary = "Movidas \(result.movedOrCopied) · omitidas \(result.skipped + result.failed)"
        }
        selectionMode = false
        selectedSessionIds.removeAll()
        await reloadSessionsOnly()
    }

    func clearCurrentWeekSessionsWithoutSchedule(groupId: Int64? = nil) async {
        guard let bridge, effectiveScheduleSlots.isEmpty else { return }
        let ids = sessions
            .filter { session in
                (groupId == nil || session.groupId == groupId) && session.status != .completed
            }
            .map(\.id)
        guard !ids.isEmpty else {
            bulkSummary = "No hay sesiones planificadas que limpiar en esta semana."
            return
        }

        for id in ids {
            try? await bridge.plannerDeleteSession(sessionId: id)
        }
        selectedSessionIds.removeAll()
        selectedSession = nil
        bulkSummary = "Eliminadas \(ids.count) sesiones de la semana sin franjas de agenda."
        await reloadSessionsOnly(keepSelection: false)
    }

    func markCompleted(_ session: PlanningSession) async {
        guard let bridge else { return }
        _ = try? await bridge.plannerUpsertSession(
            id: session.id,
            teachingUnitId: session.teachingUnitId,
            teachingUnitName: session.teachingUnitName,
            teachingUnitColor: session.teachingUnitColor,
            groupId: session.groupId,
            groupName: session.groupName,
            dayOfWeek: Int(session.dayOfWeek),
            period: Int(session.period),
            weekNumber: Int(session.weekNumber),
            year: Int(session.year),
            objectives: session.objectives,
            activities: session.activities,
            evaluation: session.evaluation,
            linkedAssessmentIdsCsv: session.linkedAssessmentIdsCsv,
            teacherScheduleSlotId: session.teacherScheduleSlotId?.int64Value,
            startTime: session.startTime,
            endTime: session.endTime,
            status: .completed
        )
        updateLocalSession(session, status: .completed)
        await reloadJournalSummaries()
    }

}
