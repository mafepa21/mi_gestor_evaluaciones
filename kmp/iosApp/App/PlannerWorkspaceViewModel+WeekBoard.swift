import SwiftUI
import MiGestorKit

@MainActor
extension PlannerWorkspaceViewModel {
    func rebuildVisiblePlannerStructure() {
        let relevantTeacherSlots = teacherScheduleSlots
        let relevantWeeklySlots = weeklySlots

        var rangesByPeriod: [Int: PlannerVisibleSlot] = [:]
        for slot in timeSlots {
            rangesByPeriod[Int(slot.period)] = PlannerVisibleSlot(
                period: Int(slot.period),
                startTime: slot.startTime,
                endTime: slot.endTime
            )
        }

        for session in sessions {
            if let matchingDefault = timeSlots.first(where: { Int($0.period) == Int(session.period) }) {
                rangesByPeriod[Int(session.period)] = PlannerVisibleSlot(
                    period: Int(session.period),
                    startTime: matchingDefault.startTime,
                    endTime: matchingDefault.endTime
                )
            } else if let startTime = session.startTime, let endTime = session.endTime {
                rangesByPeriod[Int(session.period)] = PlannerVisibleSlot(
                    period: Int(session.period),
                    startTime: startTime,
                    endTime: endTime
                )
            }
        }

        struct TimeRange: Hashable {
            let start: String
            let end: String
        }
        let teacherRanges: [TimeRange] = relevantTeacherSlots.map { TimeRange(start: $0.startTime, end: $0.endTime) }
        let weeklyRanges: [TimeRange] = relevantWeeklySlots.map { TimeRange(start: $0.startTime, end: $0.endTime) }
        let allRanges: [TimeRange] = teacherRanges + weeklyRanges
        let filteredRanges: [TimeRange] = allRanges.filter { range in
            !timeSlots.contains(where: { $0.startTime == range.start && $0.endTime == range.end })
        }
        let uniqueCustomRanges = Set(filteredRanges)
            .sorted { lhs, rhs in
                lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
            }

        var nextCustomPeriod = (timeSlots.map { Int($0.period) }.max() ?? 0) + 1
        for range in uniqueCustomRanges {
            rangesByPeriod[nextCustomPeriod] = PlannerVisibleSlot(
                period: nextCustomPeriod,
                startTime: range.start,
                endTime: range.end
            )
            nextCustomPeriod += 1
        }

        let scheduleDerivedSlots = rangesByPeriod.values.sorted {
            $0.startTime == $1.startTime ? $0.endTime < $1.endTime : $0.startTime < $1.startTime
        }

        visibleSlots = scheduleDerivedSlots.isEmpty
            ? timeSlots.map {
                PlannerVisibleSlot(period: Int($0.period), startTime: $0.startTime, endTime: $0.endTime)
            }
            : scheduleDerivedSlots

        let activeDays = Set(activeWeekdays)
        let slotDays = Set(relevantTeacherSlots.map { Int($0.dayOfWeek) } + relevantWeeklySlots.map { Int($0.dayOfWeek) })
        let mergedDays = activeDays.union(slotDays)
        let sortedDays = mergedDays.isEmpty ? [1, 2, 3, 4, 5] : mergedDays.sorted()
        visibleWeekdays = sortedDays.filter { (1...7).contains($0) }

        if !visibleWeekdays.contains(composerDraft.dayOfWeek) {
            composerDraft.dayOfWeek = visibleWeekdays.first ?? 1
        }
        if !visibleSlots.contains(where: { $0.period == composerDraft.period }) {
            composerDraft.period = visibleSlots.first?.period ?? 1
        }
        rebuildWeekRenderModel()
    }

    func entries(for day: Int, period: Int) -> [PlannerWeekCellEntry] {
        weekRenderModel.entriesByCell[PlannerCellKey(day: day, period: period)] ?? buildEntries(for: day, period: period)
    }

    func daySessions(for day: Int? = nil) -> [PlanningSession] {
        let targetDay = day ?? selectedDayForDayView
        return filteredPlannerSessions()
            .filter { Int($0.dayOfWeek) == targetDay }
            .sorted {
                let lhsStart = $0.startTime ?? timeLabel(for: Int($0.period))
                let rhsStart = $1.startTime ?? timeLabel(for: Int($1.period))
                if lhsStart == rhsStart { return $0.groupName < $1.groupName }
                return lhsStart < rhsStart
            }
    }

    var selectedDayForDayView: Int {
        if let dayViewSelectedDay {
            return dayViewSelectedDay
        }
        if let selectedSession {
            return Int(selectedSession.dayOfWeek)
        }
        let current = IsoWeekHelper.shared.current()
        let currentIsoFallback = PlannerCalendar.currentIsoYearWeek
        let currentWeek = Int(truncating: current.first ?? KotlinInt(value: Int32(currentIsoFallback.week)))
        let currentYear = Int(truncating: current.second ?? KotlinInt(value: Int32(currentIsoFallback.year)))
        if week == currentWeek, year == currentYear {
            var calendar = Calendar(identifier: .iso8601)
            calendar.locale = Locale.current
            let today = ((calendar.component(.weekday, from: Date()) + 5) % 7) + 1
            if visibleWeekdays.contains(today) { return today }
        }
        return visibleWeekdays.first ?? 1
    }

    func rebuildWeekRenderModel() {
        var entriesByCell: [PlannerCellKey: [PlannerWeekCellEntry]] = [:]
        for day in visibleWeekdays {
            for slot in visibleSlots {
                let entries = buildEntries(for: day, period: Int(slot.period))
                if !entries.isEmpty {
                    entriesByCell[PlannerCellKey(day: day, period: Int(slot.period))] = entries
                }
            }
        }
        weekRenderModel = PlannerWeekRenderModel(
            entriesByCell: entriesByCell,
            visibleSlots: visibleSlots,
            visibleDays: visibleWeekdays,
            holidays: holidayDays
        )
    }

    func filteredPlannerSessions() -> [PlanningSession] {
        sessions.filter { session in
            selectedGroupId.map { session.groupId == $0 } ?? true
        }
    }

    private func buildEntries(for day: Int, period: Int) -> [PlannerWeekCellEntry] {
        let sessionEntries = filteredPlannerSessions()
            .filter { Int($0.dayOfWeek) == day && Int($0.period) == period }
            .sorted {
                if $0.groupName == $1.groupName { return $0.teachingUnitName < $1.teachingUnitName }
                return $0.groupName < $1.groupName
            }
            .map { session in
                let summary = summary(for: session.id)
                let glance = sessionGlance(for: session)
                let sections = previewSections(
                    teachingUnitName: session.teachingUnitName,
                    objective: session.objectives,
                    activity: session.activities,
                    evaluation: session.evaluation
                )
                let preview = glance.objective ?? glance.activity ?? sections.first?.value ?? preferredPreviewText(
                    objective: session.objectives,
                    activity: session.activities,
                    evaluation: session.evaluation
                )
                let completed = session.status == .completed || summary?.status == .completed
                return PlannerWeekCellEntry(
                    id: "session-\(session.id)",
                    kind: .session,
                    classId: session.groupId,
                    className: session.groupName,
                    classColorHex: classColorHex(for: session.groupId),
                    dayOfWeek: Int(session.dayOfWeek),
                    period: Int(session.period),
                    title: glance.sessionTitle,
                    preview: preview,
                    sessionGlance: glance,
                    sectionPreviews: sections,
                    sessionId: session.id,
                    sessionStatus: session.status,
                    journalStatus: summary?.status,
                    scheduledSlotId: nil,
                    isCompleted: completed
                )
            }

        let existingClassIds = Set(sessionEntries.map(\.classId))
        let scheduledEntries = teacherScheduleSlots
            .filter { slot in
                guard Int(slot.dayOfWeek) == day else { return false }
                if let selectedGroupId, slot.schoolClassId != selectedGroupId { return false }
                guard let visibleSlot = visibleSlots.first(where: { $0.period == period }) else { return false }
                return slot.startTime == visibleSlot.startTime && slot.endTime == visibleSlot.endTime && !existingClassIds.contains(slot.schoolClassId)
            }
            .sorted { lhs, rhs in
                let lhsName = groups.first(where: { $0.id == lhs.schoolClassId })?.name ?? ""
                let rhsName = groups.first(where: { $0.id == rhs.schoolClassId })?.name ?? ""
                return lhsName < rhsName
            }
            .map { slot in
                PlannerWeekCellEntry(
                    id: "slot-\(slot.id)",
                    kind: .scheduledSlot,
                    classId: slot.schoolClassId,
                    className: groups.first(where: { $0.id == slot.schoolClassId })?.name ?? "Grupo \(slot.schoolClassId)",
                    classColorHex: classColorHex(for: slot.schoolClassId),
                    dayOfWeek: Int(slot.dayOfWeek),
                    period: period,
                    title: slot.unitLabel?.nilIfBlank ?? slot.subjectLabel.nilIfBlank ?? "Franja preparada",
                    preview: slot.subjectLabel.nilIfBlank ?? "Pendiente de concretar",
                    sessionGlance: nil,
                    sectionPreviews: [
                        PlannerSectionPreview(title: "Curso", value: groups.first(where: { $0.id == slot.schoolClassId })?.name ?? "Grupo \(slot.schoolClassId)"),
                        PlannerSectionPreview(title: "Bloque", value: slot.unitLabel?.nilIfBlank ?? slot.subjectLabel.nilIfBlank ?? "Pendiente")
                    ],
                    sessionId: nil,
                    sessionStatus: nil,
                    journalStatus: nil,
                    scheduledSlotId: slot.id,
                    isCompleted: false
                )
            }

        return sessionEntries + scheduledEntries
    }

    func normalizedSituationTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func preferredPreviewText(objective: String, activity: String, evaluation: String) -> String {
        if let objective = objective.nilIfBlank { return objective }
        if let activity = activity.nilIfBlank { return activity }
        if let evaluation = evaluation.nilIfBlank { return evaluation }
        return "Sesión por concretar"
    }

    private func previewSections(
        teachingUnitName: String,
        objective: String,
        activity: String,
        evaluation: String
    ) -> [PlannerSectionPreview] {
        var sections: [PlannerSectionPreview] = []
        if let unit = teachingUnitName.nilIfBlank {
            sections.append(.init(title: "SA", value: unit))
        }
        if let objective = objective.nilIfBlank {
            sections.append(.init(title: "Objetivos", value: objective))
        }
        if let activity = activity.nilIfBlank {
            sections.append(.init(title: "Resumen", value: activity))
        }
        if let evaluation = evaluation.nilIfBlank {
            sections.append(.init(title: "Evaluación", value: evaluation))
        }
        return sections
    }

    func reloadHolidays() async {
        guard let bridge else { return }
        do {
            let events = try await bridge.plannerNonTeachingCalendarEvents(classId: nil)
            let days = IsoWeekHelper.shared.daysOf(isoWeek: Int32(week), year: Int32(year))
            var holidays: Set<Int> = []
            
            let calendar = Calendar.current
            
            for (index, dayDate) in days.enumerated() {
                var components = DateComponents()
                components.year = Int(dayDate.year)
                components.month = Int(dayDate.monthNumber)
                components.day = Int(dayDate.dayOfMonth)
                components.hour = 0
                components.minute = 0
                components.second = 0
                
                guard let startOfDay = calendar.date(from: components) else { continue }
                let startMs = Int64(startOfDay.timeIntervalSince1970 * 1000)
                
                components.hour = 23
                components.minute = 59
                components.second = 59
                guard let endOfDay = calendar.date(from: components) else { continue }
                let endMs = Int64(endOfDay.timeIntervalSince1970 * 1000)
                
                for event in events {
                    let eventStartMs = event.startAt.toEpochMilliseconds()
                    if eventStartMs >= startMs && eventStartMs <= endMs {
                        holidays.insert(index + 1)
                        break
                    }
                }
            }
            self.holidayDays = holidays
            rebuildWeekRenderModel()
        } catch {
            print("Error al cargar festivos: \(error)")
        }
    }

    func toggleHoliday(for day: Int) async {
        guard let bridge else { return }
        let days = IsoWeekHelper.shared.daysOf(isoWeek: Int32(week), year: Int32(year))
        guard day >= 1 && day <= days.count else { return }
        let targetDate = days[day - 1]
        
        let events = (try? await bridge.plannerNonTeachingCalendarEvents(classId: nil)) ?? []
        let calendar = Calendar.current
        
        var components = DateComponents()
        components.year = Int(targetDate.year)
        components.month = Int(targetDate.monthNumber)
        components.day = Int(targetDate.dayOfMonth)
        components.hour = 0
        components.minute = 0
        components.second = 0
        
        guard let startOfDay = calendar.date(from: components) else { return }
        let startEpochMs = Int64(startOfDay.timeIntervalSince1970 * 1000)
        
        components.hour = 23
        components.minute = 59
        components.second = 59
        guard let endOfDay = calendar.date(from: components) else { return }
        let endEpochMs = Int64(endOfDay.timeIntervalSince1970 * 1000)
        
        let existingEvent = events.first { event in
            let eventStartMs = event.startAt.toEpochMilliseconds()
            return eventStartMs >= startEpochMs && eventStartMs <= endEpochMs
        }
        
        do {
            if let event = existingEvent {
                _ = try await bridge.plannerSaveCalendarEvent(
                    id: event.id,
                    classId: nil,
                    title: "Lectivo",
                    description: "Clase ordinaria",
                    startEpochMs: event.startAt.toEpochMilliseconds(),
                    endEpochMs: event.endAt.toEpochMilliseconds()
                )
            } else {
                _ = try await bridge.plannerSaveCalendarEvent(
                    id: nil,
                    classId: nil,
                    title: "Festivo",
                    description: "Día no lectivo",
                    startEpochMs: startEpochMs,
                    endEpochMs: endEpochMs
                )
            }
            await reloadWeekSessions()
        } catch {
            print("Error al alternar festivo: \(error)")
        }
    }

}
