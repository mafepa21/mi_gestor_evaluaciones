import SwiftUI
import MiGestorKit

@MainActor
extension PlannerWorkspaceViewModel {
    func addScheduleSlot() async {
        guard let bridge, let schedule = teacherSchedule, let groupId = scheduleFormGroupId else { return }
        scheduleSaveState = .saving
        do {
            _ = try await bridge.plannerSaveTeacherScheduleSlot(
                scheduleId: schedule.id,
                classId: groupId,
                subjectLabel: scheduleFormSubject,
                unitLabel: scheduleFormUnit.nilIfBlank,
                dayOfWeek: scheduleFormDay,
                startTime: scheduleFormStart,
                endTime: scheduleFormEnd
            )
            scheduleError = ""
            scheduleFormSubject = ""
            scheduleFormUnit = ""
            await reloadScheduleOnly()
            scheduleSaveState = .saved(Date())
        } catch {
            scheduleError = error.localizedDescription
            scheduleSaveState = .failed(scheduleError)
        }
    }

    func buildScheduleGenerationPreview(groupId: Int64? = nil) {
        let targetSlots = effectiveScheduleSlots.filter { slot in
            guard let groupId else { return true }
            return slot.schoolClassId == groupId
        }
        let rows = Dictionary(grouping: targetSlots, by: \.schoolClassId)
            .compactMap { classId, slots -> PlannerScheduleGenerationPreviewRow? in
                let className = groups.first(where: { $0.id == classId })?.name ?? "Grupo \(classId)"
                let detected = slots.count
                let existing = slots.filter { slot in
                    sessions.contains { session in
                        session.groupId == slot.schoolClassId &&
                        Int(session.dayOfWeek) == Int(slot.dayOfWeek) &&
                        (
                            session.teacherScheduleSlotId?.int64Value == slot.id ||
                            (session.startTime == slot.startTime && session.endTime == slot.endTime) ||
                            Int(session.period) == period(for: slot)
                        )
                    }
                }.count
                return PlannerScheduleGenerationPreviewRow(
                    classId: classId,
                    className: className,
                    detectedSessions: detected,
                    existingSessions: existing
                )
            }
            .sorted { $0.className < $1.className }
        scheduleGenerationPreview = rows
        let totals = rows.reduce(into: (detected: 0, omitted: 0)) { result, row in
            result.detected += row.detectedSessions
            result.omitted += row.existingSessions
        }
        scheduleGenerationSummary = "\(totals.detected) franjas detectadas · \(totals.omitted) sesiones ya existentes omitidas"
    }

    func generateSessionsFromSchedule(groupId: Int64? = nil) async {
        guard let bridge else { return }
        let targetSlots = effectiveScheduleSlots.filter { slot in
            guard let groupId else { return true }
            return slot.schoolClassId == groupId
        }
        guard !targetSlots.isEmpty else {
            scheduleGenerationSummary = "No hay franjas para generar sesiones."
            return
        }
        isGeneratingScheduleSessions = true
        defer { isGeneratingScheduleSessions = false }

        var created = 0
        var omitted = 0
        for slot in targetSlots {
            let slotPeriod = period(for: slot)
            let alreadyExists = sessions.contains { session in
                session.groupId == slot.schoolClassId &&
                Int(session.dayOfWeek) == Int(slot.dayOfWeek) &&
                (
                    session.teacherScheduleSlotId?.int64Value == slot.id ||
                    (session.startTime == slot.startTime && session.endTime == slot.endTime) ||
                    Int(session.period) == slotPeriod
                )
            }
            if alreadyExists {
                omitted += 1
                continue
            }

            do {
                _ = try await bridge.plannerSaveSessionWithLinks(
                    id: 0,
                    groupId: slot.schoolClassId,
                    groupName: groups.first(where: { $0.id == slot.schoolClassId })?.name ?? "Grupo \(slot.schoolClassId)",
                    dayOfWeek: Int(slot.dayOfWeek),
                    period: slotPeriod,
                    weekNumber: week,
                    year: year,
                    teachingUnitId: nil,
                    newTeachingUnitName: slot.unitLabel?.nilIfBlank ?? slot.subjectLabel.nilIfBlank ?? "Planificación semanal",
                    objectives: "",
                    activities: "",
                    teacherScheduleSlotId: slot.id,
                    startTime: slot.startTime,
                    endTime: slot.endTime,
                    selectedInstruments: []
                )
                created += 1
            } catch {
                omitted += 1
                scheduleGenerationSummary = "No se pudo generar una sesión: \(error.localizedDescription)"
            }
        }

        await reloadSessionsOnly(keepSelection: false)
        buildScheduleGenerationPreview(groupId: groupId)
        scheduleGenerationSummary = "\(created) sesiones creadas · \(omitted) omitidas"
    }

    private func period(for slot: TeacherScheduleSlot) -> Int {
        if let visibleSlot = visibleSlots.first(where: { $0.startTime == slot.startTime && $0.endTime == slot.endTime }) {
            return visibleSlot.period
        }
        if let defaultSlot = timeSlots.first(where: { $0.startTime == slot.startTime && $0.endTime == slot.endTime }) {
            return Int(defaultSlot.period)
        }
        return Int(slot.dayOfWeek) * 100 + Int(slot.id % 100)
    }

    func deleteScheduleSlot(_ slotId: Int64) async {
        guard let bridge else { return }
        scheduleSaveState = .saving
        do {
            try await bridge.plannerDeleteTeacherScheduleSlot(slotId: slotId)
            await reloadScheduleOnly()
            scheduleSaveState = .saved(Date())
        } catch {
            scheduleError = error.localizedDescription
            scheduleSaveState = .failed(scheduleError)
        }
    }

    func saveTeacherSchedule() async {
        guard let bridge, let schedule = teacherSchedule else { return }
        scheduleSaveState = .saving
        do {
            let savedId = try await bridge.plannerSaveTeacherSchedule(
                scheduleId: schedule.id,
                ownerUserId: schedule.ownerUserId,
                academicYearId: schedule.academicYearId,
                name: scheduleName,
                startDateIso: scheduleStartDate,
                endDateIso: scheduleEndDate,
                activeWeekdaysCsv: activeWeekdays.sorted().map(String.init).joined(separator: ","),
                trace: schedule.trace
            )
            teacherSchedule = TeacherSchedule(
                id: savedId,
                ownerUserId: schedule.ownerUserId,
                academicYearId: schedule.academicYearId,
                name: scheduleName,
                startDateIso: scheduleStartDate,
                endDateIso: scheduleEndDate,
                activeWeekdaysCsv: activeWeekdays.sorted().map(String.init).joined(separator: ","),
                trace: schedule.trace
            )
            await reloadScheduleOnly()
            scheduleSaveState = .saved(Date())
        } catch {
            scheduleError = error.localizedDescription
            scheduleSaveState = .failed(scheduleError)
        }
    }

    func addEvaluationPeriod() async {
        guard let bridge, let schedule = teacherSchedule else { return }
        let normalizedName = evaluationFormName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            scheduleError = "Añade un nombre para la evaluación."
            scheduleSaveState = .failed(scheduleError)
            return
        }
        scheduleSaveState = .saving
        do {
            _ = try await bridge.plannerSaveEvaluationPeriod(
                periodId: 0,
                scheduleId: schedule.id,
                name: normalizedName,
                startDateIso: evaluationFormStart,
                endDateIso: evaluationFormEnd,
                sortOrder: evaluationPeriods.count + 1
            )
            evaluationFormName = ""
            evaluationFormStart = ""
            evaluationFormEnd = ""
            scheduleError = ""
            await reloadScheduleOnly()
            scheduleSaveState = .saved(Date())
        } catch {
            scheduleError = error.localizedDescription
            scheduleSaveState = .failed(scheduleError)
        }
    }

    func deleteEvaluationPeriod(_ periodId: Int64) async {
        guard let bridge else { return }
        scheduleSaveState = .saving
        do {
            try await bridge.plannerDeleteEvaluationPeriod(periodId: periodId)
            await reloadScheduleOnly()
            scheduleSaveState = .saved(Date())
        } catch {
            scheduleError = error.localizedDescription
            scheduleSaveState = .failed(scheduleError)
        }
    }

    func toggleActiveWeekday(_ day: Int) {
        if activeWeekdays.contains(day) {
            activeWeekdays.remove(day)
        } else {
            activeWeekdays.insert(day)
        }
    }

    func reloadScheduleConfiguration() async {
        guard let bridge else { return }
        scheduleFormGroupId = await scheduleStore.reload(bridge: bridge, groups: groups, scheduleFormGroupId: scheduleFormGroupId)
        teacherSchedule = scheduleStore.teacherSchedule
        teacherScheduleSlots = scheduleStore.teacherScheduleSlots
        weeklySlots = scheduleStore.weeklySlots
        evaluationPeriods = scheduleStore.evaluationPeriods
        forecastRows = scheduleStore.forecastRows
        scheduleError = scheduleStore.scheduleError
        if let schedule = teacherSchedule {
            scheduleName = schedule.name
            scheduleStartDate = schedule.startDateIso
            scheduleEndDate = schedule.endDateIso
            activeWeekdays = Set(
                schedule.activeWeekdaysCsv
                    .split(separator: ",")
                    .compactMap { Int(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            )
            rebuildVisiblePlannerStructure()
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
