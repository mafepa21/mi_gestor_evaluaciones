//
//  KmpBridge+Planner.swift
//  MiGestorKMP
//
//  Created for modularization of KmpBridge.
//

import Foundation
import Combine
import MiGestorKit
import SwiftUI

@MainActor
extension KmpBridge {
    func refreshPlanning() async throws {
        let sessions = try await container.plannerRepository.listAllSessions()
        
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        let audit = AuditTrace(authorUserId: nil, createdAt: nowInstant, updatedAt: nowInstant, associatedGroupId: nil, deviceId: nil, syncVersion: 0)
        
        // Group sessions into PlanPeriod for UI compatibility
        let dummyPeriod = Period(id: 1, name: "Planificación (\(sessions.count) sesiones)", startAt: nowInstant, endAt: nowInstant, trace: audit)
        
        var unitMap: [Int64: PlanUnit] = [:]
        for session in sessions {
            let uId = session.teachingUnitId
            if unitMap[uId] == nil {
                let unit = UnitPlan(id: uId, periodId: 1, title: session.teachingUnitName, objectives: "", competences: "", trace: audit)
                unitMap[uId] = PlanUnit(unit: unit, sessions: [])
            }
            let updatedUnit = unitMap[uId]!
            var updatedSessions = updatedUnit.sessions
            let sessionPlan = SessionPlan(id: session.id, unitId: uId, date: nowInstant, description: session.activities, trace: audit)
            updatedSessions.append(sessionPlan)
            unitMap[uId] = PlanUnit(unit: updatedUnit.unit, sessions: updatedSessions)
        }
        
        let planPeriod = PlanPeriod(period: dummyPeriod, units: Array(unitMap.values))
        self.planning = [planPeriod]
    }

    // MARK: - Planner iOS (Week Grid + Copy/Move)
    func plannerTimeSlots() -> [TimeSlotConfig] {
        container.plannerRepository.getTimeSlots()
    }

    func plannerListAllSessions() async throws -> [PlanningSession] {
        try await container.plannerRepository.listAllSessions()
    }

    func plannerListSessions(weekNumber: Int, year: Int, classId: Int64? = nil) async throws -> [PlanningSession] {
        let sessions = try await container.plannerRepository.listSessions(weekNumber: Int32(weekNumber), year: Int32(year))
        guard let classId else { return sessions }
        return sessions.filter { $0.groupId == classId }
    }

    func plannerGetSession(id: Int64) async throws -> PlanningSession {
        let sessions = try await container.plannerRepository.listAllSessions()
        guard let session = sessions.first(where: { $0.id == id }) else {
            throw NSError(domain: "KmpBridge", code: 404, userInfo: [NSLocalizedDescriptionKey: "Session not found"])
        }
        return session
    }

    func plannerWeeklySlots(classId: Int64?) -> [WeeklySlotTemplate] {
        if let classId {
            return container.weeklyTemplateRepository.getSlotsForClass(schoolClassId: classId)
        }
        return classes.flatMap { container.weeklyTemplateRepository.getSlotsForClass(schoolClassId: $0.id) }
    }

    private func plannerTeachingUnitName(for teachingUnitId: Int64, cachedUnits: [TeachingUnit]) -> String? {
        cachedUnits.first(where: { $0.id == teachingUnitId })?.name
    }

    private func cleanPlannerInstrumentText(_ raw: String?, fallback: String) -> String {
        let trimmed = raw?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .joined(separator: " ") ?? ""
        guard !trimmed.isEmpty else { return fallback }

        let upper = trimmed.uppercased()
        let looksLikeObjectDump =
            upper.contains("EVALUATION(") ||
            upper.contains("CLASSID=") ||
            upper.contains("RUBRICID=") ||
            upper.contains("TRACE=") ||
            upper.contains("AUDITTRACE") ||
            upper.contains("UPDATEDAT=") ||
            upper.contains("CREATEDAT=")

        if looksLikeObjectDump {
            return fallback
        }
        return String(trimmed.prefix(90))
    }

    private func plannerInstrumentGroupTitle(
        teachingUnitId: Int64?,
        evaluationDescription: String?,
        cachedUnits: [TeachingUnit]
    ) -> String {
        if let teachingUnitId,
           let unitName = plannerTeachingUnitName(for: teachingUnitId, cachedUnits: cachedUnits) {
            return cleanPlannerInstrumentText(unitName, fallback: "Sin situación asignada")
        }
        let cleanDescription = cleanPlannerInstrumentText(evaluationDescription, fallback: "")
        if !cleanDescription.isEmpty {
            return cleanDescription
        }
        return "Sin situación asignada"
    }

    private func plannerInstrumentMatchesCurrentSA(
        teachingUnitId: Int64?,
        groupTitle: String,
        currentTeachingUnitId: Int64?,
        currentTeachingUnitName: String?
    ) -> Bool {
        if let teachingUnitId, let currentTeachingUnitId, teachingUnitId == currentTeachingUnitId {
            return true
        }
        guard let currentTeachingUnitName, !currentTeachingUnitName.isEmpty else { return false }
        return groupTitle.localizedCaseInsensitiveCompare(currentTeachingUnitName) == .orderedSame
    }

    private func resolvePlannerTeachingUnit(
        classId: Int64,
        teachingUnitId: Int64?,
        newTeachingUnitName: String?
    ) async throws -> TeachingUnit {
        let existingUnits = try await plannerTeachingUnits(for: classId)
        if let teachingUnitId,
           let found = existingUnits.first(where: { $0.id == teachingUnitId }) {
            return found
        }

        let normalizedName = newTeachingUnitName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let existing = existingUnits.first(where: { $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame }) {
            return existing
        }

        let classColor = plannerCourseColor(for: classId)
        let unit = TeachingUnit(
            id: 0,
            name: normalizedName.isEmpty ? "Sesión" : normalizedName,
            description: "",
            colorHex: classColor,
            groupId: KotlinLong(value: classId),
            schoolClassId: KotlinLong(value: classId),
            startDate: nil,
            endDate: nil
        )
        let savedId = try await container.plannerRepository.upsertTeachingUnit(unit: unit).int64Value
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        enqueueLocalChange(
            entity: "teaching_unit",
            id: "\(savedId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": savedId,
                "name": unit.name,
                "description": unit.description,
                "colorHex": unit.colorHex,
                "groupId": classId,
                "schoolClassId": classId
            ]
        )
        return TeachingUnit(
            id: savedId,
            name: unit.name,
            description: unit.description,
            colorHex: unit.colorHex,
            groupId: unit.groupId,
            schoolClassId: unit.schoolClassId,
            startDate: unit.startDate,
            endDate: unit.endDate
        )
    }

    private func resolvePlannerAssessmentLinks(
        classId: Int64,
        teachingUnit: TeachingUnit,
        selectedInstruments: [PlannerAssessmentInstrument]
    ) async throws -> String {
        var resolvedTokens: [String] = []
        for instrument in selectedInstruments {
            switch instrument.kind {
            case .evaluation:
                if let evaluationId = instrument.evaluationId {
                    try await ensureNotebookColumnForEvaluation(
                        classId: classId,
                        evaluationId: evaluationId,
                        title: instrument.title,
                        rubricId: instrument.rubricId
                    )
                    resolvedTokens.append("evaluation:\(evaluationId)")
                }
            case .rubric:
                guard let rubricId = instrument.rubricId else { continue }
                let evaluationId = try await ensureEvaluationForRubric(
                    classId: classId,
                    rubricId: rubricId,
                    teachingUnit: teachingUnit,
                    title: instrument.title
                )
                resolvedTokens.append("rubric:\(rubricId)")
                resolvedTokens.append("evaluation:\(evaluationId)")
            }
        }
        return Array(Set(resolvedTokens)).sorted().joined(separator: ",")
    }

    private func ensureEvaluationForRubric(
        classId: Int64,
        rubricId: Int64,
        teachingUnit: TeachingUnit,
        title: String
    ) async throws -> Int64 {
        let code = "PLN-RUB-\(rubricId)-SA-\(teachingUnit.id)"
        let existing = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
            .first { $0.code == code }
        let evaluationId = if let existing {
            existing.id
        } else {
            try await container.evaluationsRepository.saveEvaluation(
                id: nil,
                classId: classId,
                code: code,
                name: title,
                type: "Rúbrica",
                weight: 1.0,
                formula: nil,
                rubricId: KotlinLong(value: rubricId),
                description: teachingUnit.name,
                authorUserId: nil,
                createdAtEpochMs: 0,
                updatedAtEpochMs: 0,
                associatedGroupId: nil,
                deviceId: localDeviceId,
                syncVersion: 1
            ).int64Value
        }
        try await ensureNotebookColumnForEvaluation(classId: classId, evaluationId: evaluationId, title: title, rubricId: rubricId)
        return evaluationId
    }

    func ensureNotebookColumnForEvaluation(
        classId: Int64,
        evaluationId: Int64,
        title: String,
        rubricId: Int64?,
        targetTabId: String? = nil
    ) async throws {
        if try await container.notebookRepository.getColumnIdForEvaluation(evaluationId: evaluationId) != nil {
            return
        }
        let resolvedTabId = try await resolveNotebookTargetTabId(classId: classId, preferredTabId: targetTabId)

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let nowInstant = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        let columnType: NotebookColumnType = rubricId == nil ? .numeric : .rubric
        let column = NotebookColumnDefinition(
            id: "eval_\(evaluationId)",
            title: title,
            type: columnType,
            categoryKind: .evaluation,
            instrumentKind: rubricId == nil ? .writtenTest : .rubric,
            inputKind: rubricId == nil ? .numeric010 : .rubric,
            evaluationId: KotlinLong(value: evaluationId),
            rubricId: rubricId.map { KotlinLong(value: $0) },
            formula: nil,
            weight: 1.0,
            dateEpochMs: nil,
            unitOrSituation: nil,
            competencyCriteriaIds: [],
            scaleKind: .tenPoint,
            tabIds: [resolvedTabId],
            sessions: [],
            sharedAcrossTabs: false,
            colorHex: nil,
            iconName: nil,
            order: -1,
            widthDp: 0.0,
            categoryId: nil,
            ordinalLevels: [],
            availableIcons: [],
            countsTowardAverage: true,
            isPinned: false,
            isHidden: false,
            visibility: .visible,
            isLocked: false,
            isTemplate: false,
            emptyCellPolicy: .excludeFromAverage,
            trace: AuditTrace(
                authorUserId: nil,
                createdAt: nowInstant,
                updatedAt: nowInstant,
                associatedGroupId: nil,
                deviceId: nil,
                syncVersion: 0
            )
        )
        try await container.notebookRepository.saveColumn(classId: classId, column: column)
    }

    func plannerTeacherSchedule() async throws -> TeacherSchedule {
        try await container.teacherScheduleRepository.getOrCreatePrimarySchedule()
    }

    func plannerCourseColor(for classId: Int64) -> String {
        if let stored = plannerCourseColorByClassId[String(classId)],
           let normalized = normalizeHexColor(stored) {
            return normalized
        }
        let palette = Self.plannerCoursePalette
        let index = Int(abs(classId) % Int64(palette.count))
        return palette[index]
    }

    func plannerCourseColors(for classIds: [Int64]) -> [Int64: String] {
        Dictionary(
            classIds.map { ($0, plannerCourseColor(for: $0)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func plannerSetCourseColor(_ colorHex: String, for classId: Int64) {
        let normalized = normalizeHexColor(colorHex) ?? plannerCourseColor(for: classId)
        plannerCourseColorByClassId[String(classId)] = normalized
        UserDefaults.standard.set(plannerCourseColorByClassId, forKey: "planner.class.colors.v1")
    }

    func plannerTeacherScheduleSlots(scheduleId: Int64) async throws -> [TeacherScheduleSlot] {
        try await container.teacherScheduleRepository.listScheduleSlots(scheduleId: scheduleId)
    }

    func plannerEvaluationPeriods(scheduleId: Int64) async throws -> [PlannerEvaluationPeriod] {
        try await container.teacherScheduleRepository.listEvaluationPeriods(scheduleId: scheduleId)
    }

    func plannerForecast(scheduleId: Int64, classId: Int64? = nil) async throws -> [PlannerSessionForecast] {
        try await container.teacherScheduleRepository.buildForecasts(
            scheduleId: scheduleId,
            classId: classId.map { KotlinLong(value: $0) }
        )
    }

    func plannerNonTeachingCalendarEvents(classId: Int64? = nil) async throws -> [CalendarEvent] {
        let events = try await container.calendarRepository.listEvents(classId: classId.map { KotlinLong(value: $0) })
        return events
            .filter { classId != nil || $0.classId == nil }
            .filter { isNonTeachingCalendarEvent(title: $0.title, description: $0.description_) }
            .sorted { $0.startAt.toEpochMilliseconds() < $1.startAt.toEpochMilliseconds() }
    }

    func plannerAllCalendarEvents(classId: Int64? = nil) async throws -> [CalendarEvent] {
        let events = try await container.calendarRepository.listEvents(classId: classId.map { KotlinLong(value: $0) })
        return events.sorted { $0.startAt.toEpochMilliseconds() < $1.startAt.toEpochMilliseconds() }
    }


    func plannerSaveCalendarEvent(
        id: Int64?,
        classId: Int64?,
        title: String,
        description: String?,
        startEpochMs: Int64,
        endEpochMs: Int64
    ) async throws -> Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let savedId = try await container.calendarRepository.saveEvent(
            id: kotlinLong(id),
            classId: kotlinLong(classId),
            title: title,
            description: description,
            startEpochMs: startEpochMs,
            endEpochMs: endEpochMs,
            externalProvider: nil,
            externalId: nil,
            authorUserId: nil,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        ).int64Value
        
        enqueueLocalChange(
            entity: "calendar_event",
            id: "\(savedId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": savedId,
                "classId": classId ?? 0,
                "title": title,
                "description": description ?? "",
                "startEpochMs": startEpochMs,
                "endEpochMs": endEpochMs
            ]
        )
        return savedId
    }

    func plannerDeleteCalendarEvent(id: Int64) async throws {
        try await container.calendarRepository.deleteEvent(id: id)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        enqueueLocalChange(
            entity: "calendar_event",
            id: "\(id)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": id,
                "deleted": true
            ]
        )
    }

    func plannerSaveTeacherSchedule(
        scheduleId: Int64,
        ownerUserId: Int64,
        academicYearId: Int64,
        name: String,
        startDateIso: String,
        endDateIso: String,
        activeWeekdaysCsv: String,
        trace: AuditTrace
    ) async throws -> Int64 {
        let savedId = try await container.teacherScheduleRepository.saveSchedule(
            schedule: TeacherSchedule(
                id: scheduleId,
                ownerUserId: ownerUserId,
                academicYearId: academicYearId,
                name: name,
                startDateIso: startDateIso,
                endDateIso: endDateIso,
                activeWeekdaysCsv: activeWeekdaysCsv,
                trace: trace
            )
        ).int64Value
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        enqueueLocalChange(
            entity: "teacher_schedule",
            id: "\(savedId)",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": savedId,
                "ownerUserId": ownerUserId,
                "academicYearId": academicYearId,
                "name": name,
                "startDateIso": startDateIso,
                "endDateIso": endDateIso,
                "activeWeekdaysCsv": activeWeekdaysCsv,
                "authorUserId": trace.authorUserId?.int64Value ?? 0,
                "createdAtEpochMs": trace.createdAt.toEpochMilliseconds(),
                "updatedAtEpochMs": nowMs,
                "associatedGroupId": trace.associatedGroupId?.int64Value ?? 0
            ]
        )
        return savedId
    }

    func plannerSaveTeacherScheduleSlot(
        scheduleId: Int64,
        classId: Int64,
        subjectLabel: String,
        unitLabel: String?,
        dayOfWeek: Int,
        startTime: String,
        endTime: String,
        editingSlotId: Int64? = nil,
        existingWeeklyTemplateId: Int64? = nil
    ) async throws -> Int64 {
        let existing = try await container.teacherScheduleRepository.listScheduleSlots(scheduleId: scheduleId)
        let normalizedStart = startTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEnd = endTime.trimmingCharacters(in: .whitespacesAndNewlines)

        let collides = existing.contains {
            if let editingSlotId, $0.id == editingSlotId { return false }
            guard $0.schoolClassId == classId, Int($0.dayOfWeek) == dayOfWeek else { return false }
            return rangesOverlap(startA: $0.startTime, endA: $0.endTime, startB: normalizedStart, endB: normalizedEnd)
        }
        if collides {
            throw NSError(domain: "Planner", code: -320, userInfo: [NSLocalizedDescriptionKey: "La franja docente se solapa con otra del mismo grupo"])
        }

        if let existingWeeklyTemplateId {
            try? await container.weeklyTemplateRepository.delete(slotId: existingWeeklyTemplateId)
            enqueueLocalChange(
                entity: "weekly_slot",
                id: "\(existingWeeklyTemplateId)",
                updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
                payload: [
                    "id": existingWeeklyTemplateId,
                    "schoolClassId": classId
                ],
                op: "delete"
            )
        }

        let savedId = try await container.teacherScheduleRepository.saveScheduleSlot(
            slot: TeacherScheduleSlot(
                id: editingSlotId ?? 0,
                teacherScheduleId: scheduleId,
                schoolClassId: classId,
                subjectLabel: subjectLabel,
                unitLabel: unitLabel,
                dayOfWeek: Int32(dayOfWeek),
                startTime: normalizedStart,
                endTime: normalizedEnd,
                weeklyTemplateId: nil
            )
        ).int64Value
        enqueueLocalChange(
            entity: "teacher_schedule_slot",
            id: "\(savedId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "id": savedId,
                "teacherScheduleId": scheduleId,
                "schoolClassId": classId,
                "subjectLabel": subjectLabel,
                "unitLabel": unitLabel ?? "",
                "dayOfWeek": dayOfWeek,
                "startTime": normalizedStart,
                "endTime": normalizedEnd,
                "weeklyTemplateId": 0
            ]
        )
        return savedId
    }

    func plannerDeleteTeacherScheduleSlot(slotId: Int64) async throws {
        let existingSlot = try await container.teacherScheduleRepository.getScheduleSlot(slotId: slotId)
        if let slot = try await container.teacherScheduleRepository.getScheduleSlot(slotId: slotId),
           let weeklyTemplateId = slot.weeklyTemplateId {
            try? await container.weeklyTemplateRepository.delete(slotId: weeklyTemplateId.int64Value)
        }
        try await container.teacherScheduleRepository.deleteScheduleSlot(slotId: slotId)
        enqueueLocalChange(
            entity: "teacher_schedule_slot",
            id: "\(slotId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "id": slotId,
                "teacherScheduleId": existingSlot?.teacherScheduleId ?? 0
            ],
            op: "delete"
        )
    }

    func plannerSaveEvaluationPeriod(
        periodId: Int64,
        scheduleId: Int64,
        name: String,
        startDateIso: String,
        endDateIso: String,
        sortOrder: Int
    ) async throws -> Int64 {
        let savedId = try await container.teacherScheduleRepository.saveEvaluationPeriod(
            period: PlannerEvaluationPeriod(
                id: periodId,
                teacherScheduleId: scheduleId,
                name: name,
                startDateIso: startDateIso,
                endDateIso: endDateIso,
                sortOrder: Int32(sortOrder)
            )
        ).int64Value
        enqueueLocalChange(
            entity: "planner_evaluation_period",
            id: "\(savedId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "id": savedId,
                "teacherScheduleId": scheduleId,
                "name": name,
                "startDateIso": startDateIso,
                "endDateIso": endDateIso,
                "sortOrder": sortOrder
            ]
        )
        return savedId
    }

    func plannerDeleteEvaluationPeriod(periodId: Int64) async throws {
        try await container.teacherScheduleRepository.deleteEvaluationPeriod(periodId: periodId)
        enqueueLocalChange(
            entity: "planner_evaluation_period",
            id: "\(periodId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "id": periodId
            ],
            op: "delete"
        )
    }

    func plannerSaveWeeklySlot(
        classId: Int64,
        dayOfWeek: Int,
        startTime: String,
        endTime: String,
        editingSlotId: Int64? = nil
    ) async throws -> Int64 {
        let existing = container.weeklyTemplateRepository.getSlotsForClass(schoolClassId: classId)
        let normalizedStart = startTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEnd = endTime.trimmingCharacters(in: .whitespacesAndNewlines)

        let collides = existing.contains {
            if let editingSlotId, $0.id == editingSlotId { return false }
            guard $0.dayOfWeek == Int32(dayOfWeek) else { return false }
            return rangesOverlap(startA: $0.startTime, endA: $0.endTime, startB: normalizedStart, endB: normalizedEnd)
        }
        if collides {
            throw NSError(domain: "Planner", code: -310, userInfo: [NSLocalizedDescriptionKey: "La franja se solapa con otra del mismo grupo"])
        }

        let duplicated = existing.contains {
            if let editingSlotId, $0.id == editingSlotId { return false }
            return $0.dayOfWeek == Int32(dayOfWeek) && $0.startTime == normalizedStart
        }
        if duplicated {
            throw NSError(domain: "Planner", code: -311, userInfo: [NSLocalizedDescriptionKey: "Ya existe una franja con el mismo inicio"])
        }

        if let editingSlotId {
            enqueueLocalChange(
                entity: "weekly_slot",
                id: "\(editingSlotId)",
                updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
                payload: [
                    "id": editingSlotId,
                    "schoolClassId": classId
                ],
                op: "delete"
            )
            try await container.weeklyTemplateRepository.delete(slotId: editingSlotId)
        }

        let insertedId = try await container.weeklyTemplateRepository.insert(
            slot: WeeklySlotTemplate(
                id: 0,
                schoolClassId: classId,
                dayOfWeek: Int32(dayOfWeek),
                startTime: normalizedStart,
                endTime: normalizedEnd
            )
        )
        let updatedAtEpochMs = Int64(Date().timeIntervalSince1970 * 1000)
        enqueueLocalChange(
            entity: "weekly_slot",
            id: "\(insertedId.int64Value)",
            updatedAtEpochMs: updatedAtEpochMs,
            payload: [
                "id": insertedId.int64Value,
                "schoolClassId": classId,
                "dayOfWeek": dayOfWeek,
                "startTime": normalizedStart,
                "endTime": normalizedEnd
            ]
        )
        return insertedId.int64Value
    }

    func plannerDeleteWeeklySlot(slotId: Int64) async throws {
        let existingSlot = plannerWeeklySlots(classId: nil).first(where: { $0.id == slotId })
        try await container.weeklyTemplateRepository.delete(slotId: slotId)
        enqueueLocalChange(
            entity: "weekly_slot",
            id: "\(slotId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "id": slotId,
                "schoolClassId": existingSlot?.schoolClassId ?? 0
            ],
            op: "delete"
        )
    }

    func plannerUpsertSession(
        id: Int64,
        teachingUnitId: Int64,
        teachingUnitName: String,
        teachingUnitColor: String,
        groupId: Int64,
        groupName: String,
        dayOfWeek: Int,
        period: Int,
        weekNumber: Int,
        year: Int,
        objectives: String,
        activities: String,
        evaluation: String,
        linkedAssessmentIdsCsv: String = "",
        teacherScheduleSlotId: Int64? = nil,
        startTime: String? = nil,
        endTime: String? = nil,
        learningSituationSessionPlanId: Int64? = nil,
        status: SessionStatus
    ) async throws -> Int64 {
        let session = PlanningSession(
            id: id,
            teachingUnitId: teachingUnitId,
            teachingUnitName: teachingUnitName,
            teachingUnitColor: teachingUnitColor,
            groupId: groupId,
            groupName: groupName,
            dayOfWeek: Int32(dayOfWeek),
            period: Int32(period),
            weekNumber: Int32(weekNumber),
            year: Int32(year),
            objectives: objectives,
            activities: activities,
            evaluation: evaluation,
            linkedAssessmentIdsCsv: linkedAssessmentIdsCsv,
            teacherScheduleSlotId: teacherScheduleSlotId.map { KotlinLong(value: $0) },
            startTime: startTime,
            endTime: endTime,
            learningSituationSessionPlanId: learningSituationSessionPlanId.map { KotlinLong(value: $0) },
            status: status
        )
        let sessionId = try await container.plannerRepository.upsertSession(session: session).int64Value
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        var payload: [String: Any] = [
            "id": sessionId,
            "teachingUnitId": teachingUnitId,
            "teachingUnitName": teachingUnitName,
            "teachingUnitColor": teachingUnitColor,
            "groupId": groupId,
            "groupName": groupName,
            "dayOfWeek": dayOfWeek,
            "period": period,
            "weekNumber": weekNumber,
            "year": year,
            "objectives": objectives,
            "activities": activities,
            "evaluation": evaluation,
            "linkedAssessmentIdsCsv": linkedAssessmentIdsCsv,
            "status": status.name
        ]
        if let teacherScheduleSlotId {
            payload["teacherScheduleSlotId"] = teacherScheduleSlotId
        }
        if let startTime {
            payload["startTime"] = startTime
        }
        if let endTime {
            payload["endTime"] = endTime
        }
        if let learningSituationSessionPlanId {
            payload["learningSituationSessionPlanId"] = learningSituationSessionPlanId
        }
        enqueueLocalChange(
            entity: "planning_session",
            id: "\(sessionId)",
            updatedAtEpochMs: nowMs,
            payload: payload
        )
        return sessionId
    }

    func plannerDeleteSession(sessionId: Int64) async throws {
        try await container.plannerRepository.deleteSession(sessionId: sessionId)
        enqueueLocalChange(
            entity: "planning_session",
            id: "\(sessionId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: [
                "id": sessionId
            ],
            op: "delete"
        )
    }

    func plannerListSessionTemplates() async throws -> [PlannerSessionTemplate] {
        try await container.plannerRepository.listSessionTemplates()
    }

    func plannerSaveSessionTemplate(
        id: Int64 = 0,
        title: String,
        category: String = "GENERAL",
        objectives: String,
        activities: String,
        evaluation: String = ""
    ) async throws -> Int64 {
        let template = PlannerSessionTemplate(
            id: id,
            title: title,
            category: category,
            objectives: objectives,
            activities: activities,
            evaluation: evaluation,
            createdAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
        return try await container.plannerRepository.saveSessionTemplate(template: template).int64Value
    }

    func plannerDeleteSessionTemplate(id: Int64) async throws -> Bool {
        try await container.plannerRepository.deleteSessionTemplate(templateId: id).boolValue
    }

    func plannerJournal(for session: PlanningSession) async throws -> SessionJournalAggregate {
        try await container.sessionJournalRepository.getOrCreateJournal(session: session)
    }

    func plannerJournalSummaries(sessionIds: [Int64]) async throws -> [SessionJournalSummary] {
        try await container.sessionJournalRepository.listSummariesForSessions(
            planningSessionIds: sessionIds.map { KotlinLong(value: $0) }
        )
    }

    func plannerSaveJournal(_ aggregate: SessionJournalAggregate) async throws -> Int64 {
        let savedId = try await container.sessionJournalRepository.saveJournalAggregate(aggregate: aggregate).int64Value
        if let stored = try await container.sessionJournalRepository.getJournalForSession(
            planningSessionId: aggregate.journal.planningSessionId
        ) {
            enqueueSavedJournal(stored)
        } else {
            enqueueSavedJournal(aggregate)
        }
        return savedId
    }

    func enqueueSavedJournal(_ aggregate: SessionJournalAggregate) {
        let encoded = SessionJournalSyncCodec.shared.encode(aggregate: aggregate)
        guard let data = encoded.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        enqueueLocalChange(
            entity: "session_journal",
            id: "\(aggregate.journal.planningSessionId)",
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            payload: payload
        )
    }

    func plannerRegisterJournalIncident(
        session: PlanningSession,
        title: String,
        detail: String
    ) async throws -> SessionJournalLink {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let incidentId = try await container.incidentsRepository.saveIncident(
            id: nil,
            classId: session.groupId,
            studentId: nil,
            title: title,
            detail: detail,
            severity: "medium",
            dateEpochMs: nowMs,
            authorUserId: nil,
            updatedAtEpochMs: nowMs,
            deviceId: localDeviceId,
            syncVersion: 1
        )
        return SessionJournalLink(
            id: 0,
            journalId: 0,
            type: .incident,
            targetId: "incident_\(incidentId.int64Value)",
            label: title
        )
    }

    func plannerPreviewRelocation(
        sourceSessionIds: [Int64],
        targetGroupId: Int64? = nil,
        targetDayOfWeek: Int? = nil,
        targetPeriod: Int? = nil,
        dayOffset: Int = 0,
        periodOffset: Int = 0
    ) async throws -> [SessionRelocationConflict] {
        let request = SessionRelocationRequest(
            sourceSessionIds: sourceSessionIds.map { KotlinLong(value: $0) },
            targetGroupId: targetGroupId.map { KotlinLong(value: $0) },
            targetDayOfWeek: targetDayOfWeek.map { KotlinInt(value: Int32($0)) },
            targetPeriod: targetPeriod.map { KotlinInt(value: Int32($0)) },
            dayOffset: Int32(dayOffset),
            periodOffset: Int32(periodOffset)
        )
        return try await container.plannerRepository.previewSessionRelocation(request: request)
    }

    func plannerCopySessions(
        sourceSessionIds: [Int64],
        targetGroupId: Int64?,
        targetDayOfWeek: Int? = nil,
        targetPeriod: Int? = nil,
        dayOffset: Int = 0,
        periodOffset: Int = 0,
        resolution: CollisionResolution
    ) async throws -> SessionBulkResult {
        let request = SessionRelocationRequest(
            sourceSessionIds: sourceSessionIds.map { KotlinLong(value: $0) },
            targetGroupId: targetGroupId.map { KotlinLong(value: $0) },
            targetDayOfWeek: targetDayOfWeek.map { KotlinInt(value: Int32($0)) },
            targetPeriod: targetPeriod.map { KotlinInt(value: Int32($0)) },
            dayOffset: Int32(dayOffset),
            periodOffset: Int32(periodOffset)
        )
        return try await container.plannerRepository.doCopySessions(request: request, resolution: resolution)
    }

    func plannerShiftSessions(
        sourceSessionIds: [Int64],
        dayOffset: Int = 0,
        periodOffset: Int = 0,
        resolution: CollisionResolution
    ) async throws -> SessionBulkResult {
        let request = SessionRelocationRequest(
            sourceSessionIds: sourceSessionIds.map { KotlinLong(value: $0) },
            targetGroupId: nil,
            targetDayOfWeek: nil,
            targetPeriod: nil,
            dayOffset: Int32(dayOffset),
            periodOffset: Int32(periodOffset)
        )
        return try await container.plannerRepository.shiftSelectedSessions(request: request, resolution: resolution)
    }

    func plannerPreviewCascadeMove(
        sourceSessionId: Int64,
        targetWeekNumber: Int,
        targetYear: Int,
        targetDayOfWeek: Int,
        targetPeriod: Int
    ) async throws -> SessionCascadeMovePreview {
        let request = SessionCascadeMoveRequest(
            sourceSessionId: sourceSessionId,
            targetWeekNumber: Int32(targetWeekNumber),
            targetYear: Int32(targetYear),
            targetDayOfWeek: Int32(targetDayOfWeek),
            targetPeriod: Int32(targetPeriod)
        )
        return try await container.plannerRepository.previewCascadeMove(request: request)
    }

    func plannerCommitCascadeMove(
        sourceSessionId: Int64,
        targetWeekNumber: Int,
        targetYear: Int,
        targetDayOfWeek: Int,
        targetPeriod: Int
    ) async throws -> SessionCascadeMoveResult {
        let request = SessionCascadeMoveRequest(
            sourceSessionId: sourceSessionId,
            targetWeekNumber: Int32(targetWeekNumber),
            targetYear: Int32(targetYear),
            targetDayOfWeek: Int32(targetDayOfWeek),
            targetPeriod: Int32(targetPeriod)
        )
        return try await container.plannerRepository.commitCascadeMove(request: request)
    }

    func plannerRestoreCascadeMove(_ previousPlacements: [SessionPlacement]) async throws -> SessionCascadeMoveResult {
        try await container.plannerRepository.restoreCascadeMove(previousPlacements: previousPlacements)
    }

    private func rangesOverlap(startA: String, endA: String, startB: String, endB: String) -> Bool {
        guard let a0 = plannerMinutes(startA), let a1 = plannerMinutes(endA), let b0 = plannerMinutes(startB), let b1 = plannerMinutes(endB) else {
            return false
        }
        return max(a0, b0) < min(a1, b1)
    }

    private func isNonTeachingCalendarEvent(title: String, description: String?) -> Bool {
        let haystack = [title, description ?? ""]
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let markers = ["festivo", "no lectivo", "vacaciones", "puente", "holiday", "examen", "examenes", "parcial", "parciales", "global", "globales"]
        return markers.contains { haystack.contains($0) }
    }


    private func plannerMinutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }

    func date(from session: PlanningSession) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .iso8601)
        components.yearForWeekOfYear = Int(session.year)
        components.weekOfYear = Int(session.weekNumber)
        components.weekday = Int(session.dayOfWeek) + 1
        return components.date ?? Date.distantPast
    }


    func plannerTeachingUnits(for classId: Int64?) async throws -> [TeachingUnit] {
        let units = try await container.plannerRepository.listAllTeachingUnits()
        guard let classId else { return units }
        return units
            .filter {
                ($0.schoolClassId?.int64Value == classId) || ($0.groupId?.int64Value == classId)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func plannerRenameTeachingUnit(_ unit: TeachingUnit, newName: String) async throws {
        let normalized = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let renamed = TeachingUnit(
            id: unit.id,
            name: normalized,
            description: unit.description,
            colorHex: unit.colorHex,
            groupId: unit.groupId,
            schoolClassId: unit.schoolClassId,
            startDate: unit.startDate,
            endDate: unit.endDate
        )
        _ = try await container.plannerRepository.upsertTeachingUnit(unit: renamed)
    }

    func plannerDeleteTeachingUnit(_ unitId: Int64) async throws {
        let sessionsUsingUnit = try await container.plannerRepository.listAllSessions()
            .filter { $0.teachingUnitId == unitId }
        guard sessionsUsingUnit.isEmpty else {
            throw NSError(
                domain: "KmpBridge",
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: "No se puede eliminar: hay \(sessionsUsingUnit.count) sesión(es) que usan esta unidad. Elimínalas o cámbialas de unidad primero."]
            )
        }
        _ = try await container.plannerRepository.deleteTeachingUnit(unitId: unitId)
    }

    func plannerAvailableAssessmentInstruments(classId: Int64, teachingUnitId: Int64?) async throws -> [PlannerAssessmentInstrument] {
        let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
        let rubricDetails = try await container.rubricsRepository.listRubrics()
        let classUnits = try await plannerTeachingUnits(for: classId)
        let currentTeachingUnitName = teachingUnitId.flatMap { plannerTeachingUnitName(for: $0, cachedUnits: classUnits) }
        let evaluationsByRubricId = Dictionary(grouping: evaluations.compactMap { evaluation -> (Int64, Evaluation)? in
            guard let rubricId = evaluation.rubricId?.int64Value else { return nil }
            return (rubricId, evaluation)
        }, by: { $0.0 }).mapValues { pairs in
            pairs.map(\.1)
        }
        let rubricIdsFromEvaluations = Set(evaluationsByRubricId.keys)

        let evaluationInstruments = evaluations.map { evaluation in
            let groupTitle = plannerInstrumentGroupTitle(
                teachingUnitId: nil,
                evaluationDescription: evaluation.description_,
                cachedUnits: classUnits
            )
            let cleanTitle = cleanPlannerInstrumentText(evaluation.name, fallback: "Evaluación")
            let cleanType = cleanPlannerInstrumentText(evaluation.type, fallback: "Evaluación")
            let cleanDescription = cleanPlannerInstrumentText(evaluation.description_, fallback: "")
            return PlannerAssessmentInstrument(
                kind: .evaluation,
                rawId: evaluation.id,
                title: cleanTitle,
                subtitle: cleanDescription.isEmpty ? cleanType : "\(cleanType) · \(cleanDescription)",
                classId: classId,
                teachingUnitId: nil,
                evaluationId: evaluation.id,
                rubricId: evaluation.rubricId?.int64Value,
                resolvedEvaluationId: evaluation.id,
                groupTitle: groupTitle,
                isRecommendedForCurrentSA: plannerInstrumentMatchesCurrentSA(
                    teachingUnitId: nil,
                    groupTitle: groupTitle,
                    currentTeachingUnitId: teachingUnitId,
                    currentTeachingUnitName: currentTeachingUnitName
                )
            )
        }

        let rubricInstruments = rubricDetails.compactMap { detail -> PlannerAssessmentInstrument? in
            let rubric = detail.rubric
            let rubricClassId = rubric.classId?.int64Value
            let linkedEvaluations = evaluationsByRubricId[rubric.id] ?? []
            let isDirectlyForClass = rubricClassId == classId
            let isLinkedToClassEvaluation = rubricIdsFromEvaluations.contains(rubric.id)
            guard isDirectlyForClass || isLinkedToClassEvaluation else {
                return nil
            }
            let rubricTeachingUnitId = rubric.teachingUnitId?.int64Value
            let linkedEvaluationDescription = linkedEvaluations
                .compactMap { $0.description_?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            let groupTitle = plannerInstrumentGroupTitle(
                teachingUnitId: rubricTeachingUnitId,
                evaluationDescription: linkedEvaluationDescription,
                cachedUnits: classUnits
            )
            let resolvedEvaluationId = linkedEvaluations.first?.id
            let cleanTitle = cleanPlannerInstrumentText(rubric.name, fallback: "Rúbrica")
            return PlannerAssessmentInstrument(
                kind: .rubric,
                rawId: rubric.id,
                title: cleanTitle,
                subtitle: groupTitle == "Sin situación asignada" ? "Rúbrica" : cleanPlannerInstrumentText(groupTitle, fallback: "Rúbrica"),
                classId: classId,
                teachingUnitId: rubricTeachingUnitId,
                evaluationId: resolvedEvaluationId,
                rubricId: rubric.id,
                resolvedEvaluationId: resolvedEvaluationId,
                groupTitle: groupTitle,
                isRecommendedForCurrentSA: plannerInstrumentMatchesCurrentSA(
                    teachingUnitId: rubricTeachingUnitId,
                    groupTitle: groupTitle,
                    currentTeachingUnitId: teachingUnitId,
                    currentTeachingUnitName: currentTeachingUnitName
                )
            )
        }

        let prioritized = rubricInstruments.sorted { lhs, rhs in
            let lhsMatch = lhs.teachingUnitId == teachingUnitId
            let rhsMatch = rhs.teachingUnitId == teachingUnitId
            if lhsMatch != rhsMatch { return lhsMatch && !rhsMatch }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        var seenInstrumentIds = Set<String>()
        let uniqueInstruments = (evaluationInstruments + prioritized).filter { instrument in
            seenInstrumentIds.insert(instrument.id).inserted
        }

        return uniqueInstruments.sorted {
            if $0.groupTitle != $1.groupTitle {
                return $0.groupTitle.localizedCaseInsensitiveCompare($1.groupTitle) == .orderedAscending
            }
            if $0.kind != $1.kind { return $0.kind == .rubric }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    func plannerSaveSessionWithLinks(
        id: Int64,
        groupId: Int64,
        groupName: String,
        dayOfWeek: Int,
        period: Int,
        weekNumber: Int,
        year: Int,
        teachingUnitId: Int64?,
        newTeachingUnitName: String?,
        objectives: String,
        activities: String,
        teacherScheduleSlotId: Int64? = nil,
        startTime: String? = nil,
        endTime: String? = nil,
        learningSituationSessionPlanId: Int64? = nil,
        selectedInstruments: [PlannerAssessmentInstrument]
    ) async throws -> PlannerSessionSaveResult {
        let resolvedTeachingUnit = try await resolvePlannerTeachingUnit(
            classId: groupId,
            teachingUnitId: teachingUnitId,
            newTeachingUnitName: newTeachingUnitName
        )
        let linkedIds = try await resolvePlannerAssessmentLinks(
            classId: groupId,
            teachingUnit: resolvedTeachingUnit,
            selectedInstruments: selectedInstruments
        )
        let evaluationSummary = selectedInstruments.map(\.title).joined(separator: " · ")

        let sessionId = try await plannerUpsertSession(
            id: id,
            teachingUnitId: resolvedTeachingUnit.id,
            teachingUnitName: resolvedTeachingUnit.name,
            teachingUnitColor: resolvedTeachingUnit.colorHex,
            groupId: groupId,
            groupName: groupName,
            dayOfWeek: dayOfWeek,
            period: period,
            weekNumber: weekNumber,
            year: year,
            objectives: objectives,
            activities: activities,
            evaluation: evaluationSummary,
            linkedAssessmentIdsCsv: linkedIds,
            teacherScheduleSlotId: teacherScheduleSlotId,
            startTime: startTime,
            endTime: endTime,
            learningSituationSessionPlanId: learningSituationSessionPlanId,
            status: .planned
        )

        return PlannerSessionSaveResult(
            sessionId: sessionId,
            teachingUnitId: resolvedTeachingUnit.id,
            teachingUnitName: resolvedTeachingUnit.name,
            evaluationSummary: evaluationSummary,
            linkedAssessmentIdsCsv: linkedIds
        )
    }

    func createPlanning(periodName: String, unitTitle: String, sessionDescription: String) async throws {
        let current = IsoWeekHelper.shared.current()
        let weekNum = current.first?.int32Value ?? 0
        let yearNum = current.second?.int32Value ?? 0
        
        let unit = TeachingUnit(
            id: 0,
            name: unitTitle,
            description: "Periodo: \(periodName)",
            colorHex: "#4A90D9",
            groupId: nil,
            schoolClassId: nil,
            startDate: nil,
            endDate: nil
        )
        
        let unitId = try await container.plannerRepository.upsertTeachingUnit(unit: unit)

        let session = PlanningSession(
            id: 0,
            teachingUnitId: Int64(truncating: unitId),
            teachingUnitName: unitTitle,
            teachingUnitColor: "#4A90D9",
            groupId: 0,
            groupName: "",
            dayOfWeek: 1,
            period: 1,
            weekNumber: weekNum,
            year: yearNum,
            objectives: "",
            activities: sessionDescription,
            evaluation: "",
            linkedAssessmentIdsCsv: "",
            teacherScheduleSlotId: nil,
            startTime: nil,
            endTime: nil,
            learningSituationSessionPlanId: nil,
            status: SessionStatus.planned
        )
        
        try await container.plannerRepository.upsertSession(session: session)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        enqueueLocalChange(
            entity: "planning_session",
            id: "\(weekNum)-\(yearNum)-\(unitId.int64Value)-1",
            updatedAtEpochMs: nowMs,
            payload: [
                "id": NSNull(),
                "teachingUnitId": unitId.int64Value,
                "teachingUnitName": unitTitle,
                "teachingUnitColor": "#4A90D9",
                "groupId": 0,
                "groupName": "",
                "dayOfWeek": 1,
                "period": 1,
                "weekNumber": Int(weekNum),
                "year": Int(yearNum),
                "objectives": "",
                "activities": sessionDescription,
                "evaluation": "",
                "linkedAssessmentIdsCsv": "",
                "status": "PLANNED"
            ]
        )
        
        try await refreshPlanning()
    }

}
