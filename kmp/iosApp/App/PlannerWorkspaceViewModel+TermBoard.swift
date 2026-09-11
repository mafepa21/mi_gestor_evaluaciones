import Foundation
import SwiftUI
import MiGestorKit

struct TermSimulationPlanItem: Equatable {
    let planId: Int64?
    let sessionNumber: Int
    let title: String
    let objective: String
    let hasEvaluation: Bool

    init(
        planId: Int64? = nil,
        sessionNumber: Int,
        title: String,
        objective: String = "",
        hasEvaluation: Bool = false
    ) {
        self.planId = planId
        self.sessionNumber = sessionNumber
        self.title = title
        self.objective = objective
        self.hasEvaluation = hasEvaluation
    }
}

enum TermBoardProjectionEngine {
    static func project(
        periodName: String,
        startDateIso: String,
        endDateIso: String,
        deadlineDateIso: String? = nil,
        classId: Int64,
        scheduleSlots: [TeacherScheduleSlot],
        nonTeachingEvents: [CalendarEvent],
        existingSessions: [PlanningSession],
        simulationPlans: [TermSimulationPlanItem]? = nil,
        simulationSituationTitle: String? = nil,
        defaultTimeSlots: [PlannerVisibleSlot] = []
    ) -> (slots: [TermClassSlot], metrics: TermCapacityMetrics) {
        let calendar = Calendar(identifier: .iso8601)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.calendar = calendar

        guard let startDate = dateFormatter.date(from: startDateIso),
              let endDate = dateFormatter.date(from: endDateIso) else {
            return (
                [],
                TermCapacityMetrics(
                    totalLectivas: 0,
                    totalFestivos: 0,
                    totalOcupadas: 0,
                    totalLibres: 0,
                    evaluationPeriodName: periodName,
                    startDate: Date(),
                    endDate: Date()
                )
            )
        }

        let deadlineDate = deadlineDateIso.flatMap { dateFormatter.date(from: $0) }

        // Filter schedule slots for this class
        let classSlots = scheduleSlots
            .filter { $0.schoolClassId == classId }
            .sorted {
                if $0.dayOfWeek != $1.dayOfWeek { return $0.dayOfWeek < $1.dayOfWeek }
                return $0.startTime < $1.startTime
            }

        // Build dictionary of non-teaching events by dateIso ("yyyy-MM-dd")
        var nonTeachingMap: [String: String] = [:]
        for event in nonTeachingEvents {
            let eventStart = Date(timeIntervalSince1970: Double(event.startAt.toEpochMilliseconds()) / 1000.0)
            let eventEnd = Date(timeIntervalSince1970: Double(event.endAt.toEpochMilliseconds()) / 1000.0)
            var cursor = calendar.startOfDay(for: eventStart)
            let endDay = calendar.startOfDay(for: eventEnd)
            while cursor <= endDay {
                let iso = dateFormatter.string(from: cursor)
                if nonTeachingMap[iso] == nil {
                    nonTeachingMap[iso] = event.title
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }

        // Index existing sessions for this class:
        // Key: "(year)-(week)-(dayOfWeek)-(period)"
        var sessionMap: [String: PlanningSession] = [:]
        for session in existingSessions where session.groupId == classId {
            let key = "\(session.year)-\(session.weekNumber)-\(session.dayOfWeek)-\(session.period)"
            sessionMap[key] = session
        }

        var resultSlots: [TermClassSlot] = []
        var lessonCounter = 0
        var totalFestivosCount = 0
        var totalOcupadasCount = 0
        var totalLibresCount = 0

        var pendingSimPlans = simulationPlans ?? []
        var placedSimPlansCount = 0

        // Iterate day-by-day from startDate to endDate
        var cursor = calendar.startOfDay(for: startDate)
        let normalizedEnd = calendar.startOfDay(for: endDate)

        while cursor <= normalizedEnd {
            let dayOfWeek = ((calendar.component(.weekday, from: cursor) + 5) % 7) + 1 // 1=Mon ... 7=Sun
            let dayDateIso = dateFormatter.string(from: cursor)
            let year = calendar.component(.yearForWeekOfYear, from: cursor)
            let week = calendar.component(.weekOfYear, from: cursor)

            // Find schedule slots for this day of week
            let matchingSlots = classSlots.filter { Int($0.dayOfWeek) == dayOfWeek }

            for slot in matchingSlots {
                let period: Int = {
                    if let match = defaultTimeSlots.first(where: { $0.startTime == slot.startTime && $0.endTime == slot.endTime }) {
                        return match.period
                    }
                    return 1
                }()

                let slotId = "\(dayDateIso)-slot-\(slot.id)"
                let isPastDeadline: Bool = {
                    if let deadline = deadlineDate {
                        return cursor > calendar.startOfDay(for: deadline)
                    }
                    return false
                }()

                // Check if holiday / non-teaching
                if let holidayReason = nonTeachingMap[dayDateIso] {
                    totalFestivosCount += 1
                    resultSlots.append(
                        TermClassSlot(
                            id: slotId,
                            date: cursor,
                            dateIso: dayDateIso,
                            dayOfWeek: dayOfWeek,
                            period: period,
                            startTime: slot.startTime,
                            endTime: slot.endTime,
                            teacherScheduleSlotId: slot.id,
                            lessonIndex: nil,
                            kind: .holiday(name: holidayReason),
                            isAfterEvaluationDeadline: isPastDeadline
                        )
                    )
                } else {
                    lessonCounter += 1
                    let sessionKey = "\(year)-\(week)-\(dayOfWeek)-\(period)"

                    if let existing = sessionMap[sessionKey] {
                        totalOcupadasCount += 1
                        resultSlots.append(
                            TermClassSlot(
                                id: slotId,
                                date: cursor,
                                dateIso: dayDateIso,
                                dayOfWeek: dayOfWeek,
                                period: period,
                                startTime: slot.startTime,
                                endTime: slot.endTime,
                                teacherScheduleSlotId: slot.id,
                                lessonIndex: lessonCounter,
                                kind: .occupied(session: existing),
                                isAfterEvaluationDeadline: isPastDeadline
                            )
                        )
                    } else {
                        // Slot is free!
                        totalLibresCount += 1

                        if !pendingSimPlans.isEmpty {
                            let simPlan = pendingSimPlans.removeFirst()
                            placedSimPlansCount += 1
                            resultSlots.append(
                                TermClassSlot(
                                    id: slotId,
                                    date: cursor,
                                    dateIso: dayDateIso,
                                    dayOfWeek: dayOfWeek,
                                    period: period,
                                    startTime: slot.startTime,
                                    endTime: slot.endTime,
                                    teacherScheduleSlotId: slot.id,
                                    lessonIndex: lessonCounter,
                                    kind: .preview(
                                        sessionNumber: simPlan.sessionNumber,
                                        title: simPlan.title,
                                        objective: simPlan.objective,
                                        hasEvaluation: simPlan.hasEvaluation,
                                        planId: simPlan.planId
                                    ),
                                    isAfterEvaluationDeadline: isPastDeadline
                                )
                            )
                        } else {
                            resultSlots.append(
                                TermClassSlot(
                                    id: slotId,
                                    date: cursor,
                                    dateIso: dayDateIso,
                                    dayOfWeek: dayOfWeek,
                                    period: period,
                                    startTime: slot.startTime,
                                    endTime: slot.endTime,
                                    teacherScheduleSlotId: slot.id,
                                    lessonIndex: lessonCounter,
                                    kind: .free,
                                    isAfterEvaluationDeadline: isPastDeadline
                                )
                            )
                        }
                    }
                }
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        let totalSimCount = simulationPlans?.count ?? 0
        let overflowCount: Int = {
            guard totalSimCount > 0 else { return 0 }
            let notPlaced = pendingSimPlans.count
            let placedAfterDeadline = resultSlots.filter { slot in
                if case .preview = slot.kind {
                    return slot.isAfterEvaluationDeadline
                }
                return false
            }.count
            return notPlaced + placedAfterDeadline
        }()

        let remainingFreeCount = max(0, totalLibresCount - totalSimCount)

        let metrics = TermCapacityMetrics(
            totalLectivas: lessonCounter,
            totalFestivos: totalFestivosCount,
            totalOcupadas: totalOcupadasCount,
            totalLibres: totalLibresCount,
            evaluationPeriodName: periodName,
            startDate: startDate,
            endDate: endDate,
            deadlineDate: deadlineDate,
            simulationActive: totalSimCount > 0,
            simulationSituationTitle: simulationSituationTitle,
            simulationSessionCount: totalSimCount,
            simulationOverflowCount: overflowCount,
            simulationRemainingFreeCount: remainingFreeCount
        )

        return (resultSlots, metrics)
    }
}

// MARK: - ViewModel Extension

@MainActor
extension PlannerWorkspaceViewModel {
    func loadTermBoard(classId: Int64? = nil, periodId: Int64? = nil) async {
        guard let bridge else { return }

        let resolvedGroupId = classId ?? selectedGroupId ?? groups.first?.id
        guard let resolvedGroupId else {
            termBoardErrorMessage = "Selecciona un grupo para cargar el tablero de evaluación."
            return
        }

        isTermBoardLoading = true
        termBoardErrorMessage = nil
        defer { isTermBoardLoading = false }

        do {
            // 1. Ensure schedule and evaluation periods are loaded
            if teacherSchedule == nil {
                await reloadScheduleOnly()
            }

            // 2. Select period
            let resolvedPeriod: PlannerEvaluationPeriod? = {
                if let periodId {
                    return evaluationPeriods.first(where: { $0.id == periodId })
                }
                if let selectedTermPeriodId {
                    return evaluationPeriods.first(where: { $0.id == selectedTermPeriodId })
                }
                let cal = Calendar(identifier: .iso8601)
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                df.calendar = cal
                let nowIso = df.string(from: Date())
                if let current = evaluationPeriods.first(where: { $0.startDateIso <= nowIso && nowIso <= $0.endDateIso }) {
                    return current
                }
                return evaluationPeriods.sorted(by: { ($0.sortOrder, $0.startDateIso) < ($1.sortOrder, $1.startDateIso) }).first
            }()

            guard let period = resolvedPeriod else {
                termBoardErrorMessage = "No hay periodos de evaluación configurados en Ajustes de agenda."
                termBoardSlots = []
                termCapacityMetrics = nil
                return
            }

            selectedTermPeriodId = period.id

            // 3. Load non-teaching calendar events
            let globalEvents = try await bridge.plannerNonTeachingCalendarEvents(classId: nil)
            let classEvents = try await bridge.plannerNonTeachingCalendarEvents(classId: resolvedGroupId)
            let allNonTeaching = globalEvents + classEvents

            // 4. Load all sessions
            let allSessions = try await bridge.plannerListAllSessions()

            // 5. If simulatedSituationId is set, load its plans
            var simPlans: [TermSimulationPlanItem]? = nil
            var simTitle: String? = nil

            if let simId = simulatedSituationId {
                let situations = try await bridge.learningSituations()
                if let situation = situations.first(where: { $0.id == simId }) {
                    simTitle = situation.title
                    let versions = try await bridge.learningSituationSessionSequenceVersionsAll()
                    let sitVersions = versions.filter { $0.learningSituationId == simId }
                    if let latestVersion = sitVersions.max(by: { $0.versionNumber < $1.versionNumber }) {
                        let allPlans = try await bridge.learningSituationSessionPlansAll()
                        let plans = allPlans
                            .filter { $0.sequenceVersionId == latestVersion.id }
                            .sorted { $0.sessionNumber < $1.sessionNumber }

                        simPlans = plans.map { plan in
                            let hasEvidence = !plan.developmentJson.isEmpty && plan.developmentJson.contains("evidence")
                            return TermSimulationPlanItem(
                                planId: plan.id,
                                sessionNumber: Int(plan.sessionNumber),
                                title: plan.title,
                                objective: plan.objective,
                                hasEvaluation: hasEvidence
                            )
                        }
                    }
                }
            }

            // 6. Run projection engine
            let projection = TermBoardProjectionEngine.project(
                periodName: period.name,
                startDateIso: period.startDateIso,
                endDateIso: period.endDateIso,
                deadlineDateIso: nil,
                classId: resolvedGroupId,
                scheduleSlots: teacherScheduleSlots,
                nonTeachingEvents: allNonTeaching,
                existingSessions: allSessions,
                simulationPlans: simPlans,
                simulationSituationTitle: simTitle,
                defaultTimeSlots: visibleSlots
            )

            self.termBoardSlots = projection.slots
            self.termCapacityMetrics = projection.metrics
        } catch {
            termBoardErrorMessage = error.localizedDescription
        }
    }

    func simulateSituation(_ situationId: Int64?) async {
        simulatedSituationId = situationId
        await loadTermBoard(classId: selectedGroupId, periodId: selectedTermPeriodId)
    }

    func clearSimulation() async {
        simulatedSituationId = nil
        await loadTermBoard(classId: selectedGroupId, periodId: selectedTermPeriodId)
    }

    func applySimulatedSituation() async -> Bool {
        guard let bridge, let classId = selectedGroupId, let simId = simulatedSituationId else { return false }
        let groupName = groups.first(where: { $0.id == classId })?.name ?? "Grupo \(classId)"

        let situations = (try? await bridge.learningSituations()) ?? []
        guard let situation = situations.first(where: { $0.id == simId }) else { return false }

        isApplyingSimulation = true
        defer { isApplyingSimulation = false }

        let calendar = Calendar(identifier: .iso8601)

        do {
            for slot in termBoardSlots {
                if case .preview(let sessionNumber, let title, let objective, _, let planId) = slot.kind {
                    let year = calendar.component(.yearForWeekOfYear, from: slot.date)
                    let week = calendar.component(.weekOfYear, from: slot.date)

                    _ = try await bridge.plannerSaveSessionWithLinks(
                        id: 0,
                        groupId: classId,
                        groupName: groupName,
                        dayOfWeek: slot.dayOfWeek,
                        period: slot.period,
                        weekNumber: week,
                        year: year,
                        teachingUnitId: situation.id,
                        newTeachingUnitName: situation.title,
                        objectives: title,
                        activities: objective,
                        teacherScheduleSlotId: slot.teacherScheduleSlotId,
                        startTime: slot.startTime,
                        endTime: slot.endTime,
                        learningSituationSessionPlanId: planId,
                        selectedInstruments: []
                    )
                }
            }

            simulatedSituationId = nil
            await reloadAll()
            await loadTermBoard(classId: classId, periodId: selectedTermPeriodId)
            return true
        } catch {
            termBoardErrorMessage = "Error al aplicar simulación: \(error.localizedDescription)"
            return false
        }
    }

    func addExtraSession(at slot: TermClassSlot) {
        let calendar = Calendar(identifier: .iso8601)
        let week = calendar.component(.weekOfYear, from: slot.date)
        let year = calendar.component(.yearForWeekOfYear, from: slot.date)

        self.week = week
        self.year = year
        self.selectedGroupId = selectedGroupId

        openComposer(
            day: slot.dayOfWeek,
            period: slot.period,
            initialObjectives: "Sesión complementaria",
            initialActivities: ""
        )
    }
}
