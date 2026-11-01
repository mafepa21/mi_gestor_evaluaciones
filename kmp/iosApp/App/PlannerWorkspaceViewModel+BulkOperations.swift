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

    /// Copia una sesión a otra franja de la semana visible (⌘/⌥ + arrastrar).
    /// La copia toma el grupo con clase en la franja de destino; si la franja no
    /// tiene clase o su grupo ya no existe, conserva el grupo de origen. Sin
    /// `overwrite`, un destino ocupado devuelve `.occupied` sin tocar nada para
    /// que la vista confirme.
    func copySession(sessionId: Int64, day: Int, period: Int, overwrite: Bool) async throws -> PlannerSessionCopyOutcome {
        let source = try await copySource(sessionId)
        let slotGroupId = copyTargetGroupId(day: day, period: period)
        let knownSlotGroupId = slotGroupId.flatMap { id in groups.contains(where: { $0.id == id }) ? id : nil }
        let target = PlannerSessionCopyTarget(
            groupId: knownSlotGroupId ?? source.groupId,
            dayOffset: day - Int(source.dayOfWeek),
            period: period
        )
        let outcome = try await copySession(source, to: target, overwrite: overwrite)
        if case .copied(let summary) = outcome, slotGroupId != nil, knownSlotGroupId == nil {
            return .copied(summary: "\(summary) La franja es de un grupo que ya no existe: se ha copiado en el grupo de origen. Revisa el horario.")
        }
        return outcome
    }

    /// Copia una sesión al grupo, día (de cualquier semana) y franja elegidos
    /// en «Copiar a…».
    func copySession(sessionId: Int64, toGroupId groupId: Int64, date: Date, period: Int, overwrite: Bool) async throws -> PlannerSessionCopyOutcome {
        let source = try await copySource(sessionId)
        guard let sourceDate = calendarDate(of: source) else { throw PlannerSessionCopyError.sessionNotFound }
        let calendar = Calendar.current
        let dayOffset = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: sourceDate),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        return try await copySession(
            source,
            to: PlannerSessionCopyTarget(groupId: groupId, dayOffset: dayOffset, period: period),
            overwrite: overwrite
        )
    }

    /// Grupo con clase en la franja según la proyección semanal (nil si no hay).
    func copyTargetGroupId(day: Int, period: Int) -> Int64? {
        weekRenderModel.entriesByCell[PlannerCellKey(day: day, period: period)]?
            .first(where: { $0.classId > 0 })?
            .classId
    }

    /// Franjas del horario de un grupo en un día de la semana (1 = lunes), con
    /// el número de franja visible del Planner. Vacío si ese día no tiene clase.
    func copyCandidateSlots(groupId: Int64, weekday: Int) -> [PlannerVisibleSlot] {
        let ranges = teacherScheduleSlots
            .filter { $0.schoolClassId == groupId && Int($0.dayOfWeek) == weekday }
            .map { ($0.startTime, $0.endTime) }
        return visibleSlots.filter { slot in
            ranges.contains { $0.0 == slot.startTime && $0.1 == slot.endTime }
        }
    }

    /// Fecha real de una sesión (semana ISO + día).
    func calendarDate(of session: PlanningSession) -> Date? {
        let days = IsoWeekHelper.shared.daysOf(isoWeek: session.weekNumber, year: session.year)
        let index = Int(session.dayOfWeek) - 1
        guard days.indices.contains(index) else { return nil }
        let day = days[index]
        return Calendar.current.date(from: DateComponents(
            year: Int(day.year),
            month: Int(day.monthNumber),
            day: Int(day.dayOfMonth)
        ))
    }

    private func copySource(_ sessionId: Int64) async throws -> PlanningSession {
        if let source = sessions.first(where: { $0.id == sessionId }) { return source }
        guard let bridge else { throw PlannerSessionCopyError.bridgeUnavailable }
        return try await bridge.plannerGetSession(id: sessionId)
    }

    private func copySession(_ source: PlanningSession, to target: PlannerSessionCopyTarget, overwrite: Bool) async throws -> PlannerSessionCopyOutcome {
        guard let bridge else { throw PlannerSessionCopyError.bridgeUnavailable }
        if target.groupId == source.groupId, target.dayOffset == 0, target.period == Int(source.period) {
            return .sameSlot
        }
        let result = try await bridge.plannerCopySessions(
            sourceSessionIds: [source.id],
            targetGroupId: target.groupId,
            targetPeriod: target.period,
            dayOffset: target.dayOffset,
            resolution: overwrite ? .overwrite : .cancel
        )
        if result.movedOrCopied == 0 {
            return result.failed > 0 ? .occupied : .failed
        }
        var copies: [PlanningSession] = []
        for id in result.affectedSessionIds.map({ $0.int64Value }) {
            let copy = try await bridge.plannerGetSession(id: id)
            try await adjustCopiedSession(copy, target: target)
            copies.append(copy)
        }
        await reloadSessionsOnly()
        let groupText = groupLabel(target.groupId, fallback: copies.first?.groupName ?? source.groupName)
        let dateText = copies.first.flatMap(calendarDate(of:)).map { " (\(Self.copyDateFormatter.string(from: $0)))" } ?? ""
        return .copied(summary: overwrite
            ? "Sesión sustituida por la copia en \(groupText)\(dateText)."
            : "Sesión copiada a \(groupText)\(dateText).")
    }

    /// El repositorio copia la sesión tal cual: estado, horas y franja del
    /// horario del original. La copia queda planificada y con la hora y la
    /// franja del grupo de destino (si no, la rejilla la pinta en otra fila).
    private func adjustCopiedSession(_ copy: PlanningSession, target: PlannerSessionCopyTarget) async throws {
        guard let bridge else { return }
        let slot = visibleSlots.first { $0.period == target.period }
        let scheduleSlot = slot.flatMap { visible in
            teacherScheduleSlots.first {
                $0.schoolClassId == target.groupId
                    && Int($0.dayOfWeek) == Int(copy.dayOfWeek)
                    && $0.startTime == visible.startTime
                    && $0.endTime == visible.endTime
            }
        }
        _ = try await bridge.plannerUpsertSession(
            id: copy.id,
            teachingUnitId: copy.teachingUnitId,
            teachingUnitName: copy.teachingUnitName,
            teachingUnitColor: copy.teachingUnitColor,
            groupId: copy.groupId,
            groupName: copy.groupName,
            dayOfWeek: Int(copy.dayOfWeek),
            period: Int(copy.period),
            weekNumber: Int(copy.weekNumber),
            year: Int(copy.year),
            objectives: copy.objectives,
            activities: copy.activities,
            evaluation: copy.evaluation,
            linkedAssessmentIdsCsv: copy.linkedAssessmentIdsCsv,
            teacherScheduleSlotId: scheduleSlot?.id,
            startTime: slot?.startTime ?? copy.startTime,
            endTime: slot?.endTime ?? copy.endTime,
            learningSituationSessionPlanId: copy.learningSituationSessionPlanId?.int64Value,
            status: .planned
        )
    }

    private static let copyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "EEE d/M"
        return formatter
    }()

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

/// Destino de una copia: grupo, días desde la fecha del original y franja visible.
struct PlannerSessionCopyTarget: Equatable {
    let groupId: Int64
    let dayOffset: Int
    let period: Int
}

enum PlannerSessionCopyOutcome: Equatable {
    case copied(summary: String)
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
