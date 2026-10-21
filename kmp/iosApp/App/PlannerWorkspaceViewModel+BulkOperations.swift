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
        do {
            let result = try await bridge.plannerCopySessions(
                sourceSessionIds: Array(selectedSessionIds),
                targetGroupId: nil,
                dayOffset: 7,
                periodOffset: 0,
                resolution: .skip
            )
            bulkSummary = "Copiadas \(result.movedOrCopied) · omitidas \(result.skipped + result.failed)"
        } catch {
            bulkSummary = "No se pudieron copiar las sesiones: \(error.localizedDescription)"
        }
        selectionMode = false
        selectedSessionIds.removeAll()
        await reloadSessionsOnly()
    }

    func bulkMoveOneDay() async {
        guard let bridge, !selectedSessionIds.isEmpty else { return }
        do {
            let result = try await bridge.plannerShiftSessions(
                sourceSessionIds: Array(selectedSessionIds),
                dayOffset: 1,
                periodOffset: 0,
                resolution: .skip
            )
            bulkSummary = "Movidas \(result.movedOrCopied) · omitidas \(result.skipped + result.failed)"
        } catch {
            bulkSummary = "No se pudieron mover las sesiones: \(error.localizedDescription)"
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

        var deleted = 0
        var failed = 0
        for id in ids {
            do {
                try await bridge.plannerDeleteSession(sessionId: id)
                deleted += 1
            } catch {
                failed += 1
            }
        }
        selectedSessionIds.removeAll()
        selectedSession = nil
        bulkSummary = failed == 0
            ? "Eliminadas \(deleted) sesiones de la semana sin franjas de agenda."
            : "Eliminadas \(deleted) / fallidas \(failed)"
        await reloadSessionsOnly(keepSelection: false)
    }

    func deleteSession(_ session: PlanningSession) async {
        guard let bridge else { return }
        do {
            try await bridge.plannerDeleteSession(sessionId: session.id)
        } catch {
            bulkSummary = "No se pudo eliminar la sesión: \(error.localizedDescription)"
            return
        }
        selectedSessionIds.remove(session.id)
        if selectedSession?.id == session.id {
            selectedSession = nil
        }
        bulkSummary = "Sesión eliminada."
        await reloadSessionsOnly(keepSelection: false)
    }

    /// Copia una única sesión a la semana siguiente sin activar el modo de selección
    /// múltiple ni tocar `selectedSessionIds` (a diferencia de `bulkCopyToNextWeek`).
    func copySessionToNextWeek(_ session: PlanningSession) async {
        guard let bridge else { return }
        do {
            let result = try await bridge.plannerCopySessions(
                sourceSessionIds: [session.id],
                targetGroupId: nil,
                dayOffset: 7,
                periodOffset: 0,
                resolution: .skip
            )
            bulkSummary = result.movedOrCopied > 0
                ? "Sesión copiada a la semana siguiente."
                : "No se pudo copiar la sesión a la semana siguiente."
        } catch {
            bulkSummary = "No se pudo copiar la sesión: \(error.localizedDescription)"
        }
        await reloadSessionsOnly()
    }

    /// Copia una sesión a otra franja de la semana visible (⌘ + arrastrar).
    /// La copia toma el grupo con clase en la franja de destino; si la franja no
    /// tiene clase, conserva el grupo de origen. Sin `overwrite`, un destino
    /// ocupado devuelve `.occupied` sin tocar nada para que la vista confirme.
    func copySession(sessionId: Int64, day: Int, period: Int, overwrite: Bool) async throws -> PlannerSessionCopyOutcome {
        guard let bridge else { throw PlannerSessionCopyError.bridgeUnavailable }
        guard let source = sessions.first(where: { $0.id == sessionId }) else {
            throw PlannerSessionCopyError.sessionNotFound
        }
        let targetGroupId = copyTargetGroupId(day: day, period: period) ?? source.groupId
        if targetGroupId == source.groupId, Int(source.dayOfWeek) == day, Int(source.period) == period {
            return .sameSlot
        }
        let result = try await bridge.plannerCopySessions(
            sourceSessionIds: [sessionId],
            targetGroupId: targetGroupId,
            targetDayOfWeek: day,
            targetPeriod: period,
            resolution: overwrite ? .overwrite : .cancel
        )
        if result.movedOrCopied == 0 {
            return result.failed > 0 ? .occupied : .failed
        }
        await reloadSessionsOnly()
        // El repositorio copia también el estado: una copia de una sesión
        // impartida no está impartida en el grupo de destino.
        let copiedIds = Set(result.affectedSessionIds.map { $0.int64Value })
        for copy in sessions where copiedIds.contains(copy.id) && copy.status != .planned {
            await setSessionStatus(copy, status: .planned)
        }
        let groupName = groups.first(where: { $0.id == targetGroupId })?.name ?? source.groupName
        return .copied(groupName: groupName)
    }

    /// Grupo con clase en la franja según la proyección semanal (nil si no hay).
    func copyTargetGroupId(day: Int, period: Int) -> Int64? {
        weekRenderModel.entriesByCell[PlannerCellKey(day: day, period: period)]?
            .first(where: { $0.classId > 0 })?
            .classId
    }

    func markCompleted(_ session: PlanningSession) async {
        await setSessionStatus(session, status: .completed)
    }

    /// Cambia el estado de una sesión (usado por `markCompleted` y por el
    /// deshacer de la vista Día, que necesita poder restaurar el estado previo).
    func setSessionStatus(_ session: PlanningSession, status: SessionStatus) async {
        guard let bridge else { return }
        do {
            _ = try await bridge.plannerUpsertSession(
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
                status: status
            )
        } catch {
            bulkSummary = "No se pudo actualizar el estado de la sesión."
            return
        }
        updateLocalSession(session, status: status)
        await reloadJournalSummaries()
    }

}

enum PlannerSessionCopyOutcome: Equatable {
    case copied(groupName: String)
    case occupied
    case sameSlot
    case failed
}

private enum PlannerSessionCopyError: LocalizedError {
    case bridgeUnavailable
    case sessionNotFound

    var errorDescription: String? {
        switch self {
        case .bridgeUnavailable: "El Planner todavía no está preparado."
        case .sessionNotFound: "La sesión ya no está en la semana visible."
        }
    }
}
