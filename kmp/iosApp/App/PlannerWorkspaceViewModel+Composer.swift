import SwiftUI
import MiGestorKit

@MainActor
extension PlannerWorkspaceViewModel {
    func openComposer(
        for session: PlanningSession? = nil,
        day: Int? = nil,
        period: Int? = nil,
        learningSituationSessionPlanId: Int64? = nil,
        initialObjectives: String? = nil,
        initialActivities: String? = nil,
        initialTeachingUnitName: String? = nil
    ) {
        if let session {
            composerDraft = PlannerComposerDraft(
                groupId: session.groupId,
                sessionId: session.id,
                teachingUnitId: session.teachingUnitId == 0 ? nil : session.teachingUnitId,
                unitTitle: session.teachingUnitName,
                objectives: session.objectives,
                activities: session.activities,
                dayOfWeek: Int(session.dayOfWeek),
                period: Int(session.period),
                teacherScheduleSlotId: session.teacherScheduleSlotId?.int64Value,
                startTime: session.startTime,
                endTime: session.endTime,
                selectedInstrumentIds: Set(session.linkedAssessmentIdsCsv.split(separator: ",").map(String.init)),
                learningSituationSessionPlanId: session.learningSituationSessionPlanId?.int64Value ?? learningSituationSessionPlanId
            )
        } else {
            let firstVisibleDay = visibleWeekdays.first ?? 1
            let firstVisiblePeriod = visibleSlots.first?.period ?? 1
            let resolvedDay = day ?? firstVisibleDay
            let resolvedPeriod = period ?? firstVisiblePeriod
            let slotMetadata = composerSlotMetadata(day: resolvedDay, period: resolvedPeriod, groupId: selectedGroupId ?? groups.first?.id)
            composerDraft = PlannerComposerDraft(
                groupId: selectedGroupId ?? groups.first?.id,
                teachingUnitId: nil,
                unitTitle: initialTeachingUnitName ?? "",
                objectives: initialObjectives ?? "",
                activities: initialActivities ?? "",
                dayOfWeek: resolvedDay,
                period: resolvedPeriod,
                teacherScheduleSlotId: slotMetadata.slotId,
                startTime: slotMetadata.startTime,
                endTime: slotMetadata.endTime,
                learningSituationSessionPlanId: learningSituationSessionPlanId
            )
        }
        composerSaveState = .idle
        Task { await refreshComposerContext() }
        showingComposer = true
    }

    @discardableResult
    func saveComposer() async -> Bool {
        guard let bridge, let groupId = composerDraft.groupId else {
            composerContextError = "Selecciona un grupo antes de guardar."
            composerSaveState = .failed(composerContextError)
            return false
        }
        let groupName = groups.first(where: { $0.id == groupId })?.name ?? "Grupo \(groupId)"
        let selectedInstruments = composerAvailableInstruments.filter { composerDraft.selectedInstrumentIds.contains($0.id) }
        let slotMetadata = composerSlotMetadata(day: composerDraft.dayOfWeek, period: composerDraft.period, groupId: groupId)
        isSavingComposer = true
        composerSaveState = .saving
        defer { isSavingComposer = false }
        do {
            let result = try await bridge.plannerSaveSessionWithLinks(
                id: composerDraft.sessionId,
                groupId: groupId,
                groupName: groupName,
                dayOfWeek: composerDraft.dayOfWeek,
                period: composerDraft.period,
                weekNumber: week,
                year: year,
                teachingUnitId: composerDraft.teachingUnitId,
                newTeachingUnitName: composerDraft.unitTitle,
                objectives: composerDraft.objectives,
                activities: composerDraft.activities,
                teacherScheduleSlotId: slotMetadata.slotId,
                startTime: slotMetadata.startTime,
                endTime: slotMetadata.endTime,
                learningSituationSessionPlanId: composerDraft.learningSituationSessionPlanId,
                selectedInstruments: selectedInstruments
            )
            composerContextError = ""
            composerSaveState = .saved(Date())
            showingComposer = false
            updateSessionFromComposerSave(result: result, groupId: groupId, groupName: groupName, slotMetadata: slotMetadata)

            // Recurrencia: guardar en semanas consecutivas si repeatWeeksCount > 1
            if composerDraft.repeatWeeksCount > 1 && composerDraft.sessionId == 0 {
                let repeatCount = composerDraft.repeatWeeksCount
                let draft = composerDraft
                let startWeek = week
                let startYear = year
                Task { [weak self] in
                    guard self != nil else { return }
                    for weekOffset in 1..<repeatCount {
                        var targetWeek = startWeek + weekOffset
                        var targetYear = startYear
                        let maxIsoWeeks = Self.isoWeeks(in: targetYear)
                        if targetWeek > maxIsoWeeks {
                            targetWeek -= maxIsoWeeks
                            targetYear += 1
                        }
                        _ = try? await bridge.plannerSaveSessionWithLinks(
                            id: 0,
                            groupId: groupId,
                            groupName: groupName,
                            dayOfWeek: draft.dayOfWeek,
                            period: draft.period,
                            weekNumber: targetWeek,
                            year: targetYear,
                            teachingUnitId: result.teachingUnitId,
                            newTeachingUnitName: draft.unitTitle,
                            objectives: draft.objectives,
                            activities: draft.activities,
                            teacherScheduleSlotId: slotMetadata.slotId,
                            startTime: slotMetadata.startTime,
                            endTime: slotMetadata.endTime,
                            learningSituationSessionPlanId: draft.learningSituationSessionPlanId,
                            selectedInstruments: selectedInstruments
                        )
                    }
                }
            }

            return true
        } catch {
            composerContextError = "No se pudo guardar la sesión: \(error.localizedDescription)"
            composerSaveState = .failed(composerContextError)
            return false
        }
    }

    func toggleComposerInstrument(_ instrumentId: String) {
        if composerDraft.selectedInstrumentIds.contains(instrumentId) {
            composerDraft.selectedInstrumentIds.remove(instrumentId)
        } else {
            composerDraft.selectedInstrumentIds.insert(instrumentId)
        }
    }

    func refreshComposerContext() async {
        guard let bridge, let groupId = composerDraft.groupId else {
            composerTeachingUnits = []
            composerAvailableInstruments = []
            composerContextError = ""
            return
        }
        await composerStore.reloadContext(bridge: bridge, groupId: groupId, teachingUnitId: composerDraft.teachingUnitId)
        composerTeachingUnits = composerStore.teachingUnits
        composerAvailableInstruments = composerStore.availableInstruments
        composerContextError = composerStore.contextError
        await loadSessionTemplates()
    }

    func loadSessionTemplates() async {
        guard let bridge else { return }
        sessionTemplates = (try? await bridge.plannerListSessionTemplates()) ?? []
    }

    func applyTemplate(_ template: PlannerSessionTemplate) {
        if !template.objectives.isEmpty { composerDraft.objectives = template.objectives }
        if !template.activities.isEmpty { composerDraft.activities = template.activities }
        if composerDraft.unitTitle.isEmpty && !template.title.isEmpty {
            composerDraft.unitTitle = template.title
        }
    }

    func saveCurrentDraftAsTemplate(title: String, category: String = "GENERAL") async -> Bool {
        guard let bridge else { return false }
        let templateTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !templateTitle.isEmpty else { return false }
        do {
            _ = try await bridge.plannerSaveSessionTemplate(
                id: 0,
                title: templateTitle,
                category: category,
                objectives: composerDraft.objectives,
                activities: composerDraft.activities,
                evaluation: ""
            )
            await loadSessionTemplates()
            return true
        } catch {
            return false
        }
    }

    func deleteSessionTemplate(_ template: PlannerSessionTemplate) async {
        guard let bridge else { return }
        _ = try? await bridge.plannerDeleteSessionTemplate(id: template.id)
        await loadSessionTemplates()
    }

    private func updateSessionFromComposerSave(
        result: PlannerSessionSaveResult,
        groupId: Int64,
        groupName: String,
        slotMetadata: (slotId: Int64?, startTime: String?, endTime: String?)
    ) {
        let previous = sessions.first(where: { $0.id == result.sessionId || $0.id == composerDraft.sessionId })
        let updated = PlanningSession(
            id: result.sessionId,
            teachingUnitId: result.teachingUnitId,
            teachingUnitName: result.teachingUnitName,
            teachingUnitColor: previous?.teachingUnitColor ?? EvaluationDesign.plannerCoursePalette.first ?? "#2563EB",
            groupId: groupId,
            groupName: groupName,
            dayOfWeek: Int32(composerDraft.dayOfWeek),
            period: Int32(composerDraft.period),
            weekNumber: Int32(week),
            year: Int32(year),
            objectives: composerDraft.objectives,
            activities: composerDraft.activities,
            evaluation: result.evaluationSummary,
            linkedAssessmentIdsCsv: result.linkedAssessmentIdsCsv,
            teacherScheduleSlotId: slotMetadata.slotId.map { KotlinLong(value: $0) },
            startTime: slotMetadata.startTime,
            endTime: slotMetadata.endTime,
            learningSituationSessionPlanId: previous?.learningSituationSessionPlanId ?? composerDraft.learningSituationSessionPlanId.map { KotlinLong(value: $0) },
            status: previous?.status ?? .planned
        )
        sessionStore.upsertLocal(updated)
        sessions = sessionStore.sessions
        applySearch()
        selectedSession = updated
        selectedGroupId = groupId
        rebuildVisiblePlannerStructure()
    }

    func updateLocalSession(_ session: PlanningSession, status: SessionStatus) {
        let updated = PlanningSession(
            id: session.id,
            teachingUnitId: session.teachingUnitId,
            teachingUnitName: session.teachingUnitName,
            teachingUnitColor: session.teachingUnitColor,
            groupId: session.groupId,
            groupName: session.groupName,
            dayOfWeek: session.dayOfWeek,
            period: session.period,
            weekNumber: session.weekNumber,
            year: session.year,
            objectives: session.objectives,
            activities: session.activities,
            evaluation: session.evaluation,
            linkedAssessmentIdsCsv: session.linkedAssessmentIdsCsv,
            teacherScheduleSlotId: session.teacherScheduleSlotId,
            startTime: session.startTime,
            endTime: session.endTime,
            learningSituationSessionPlanId: session.learningSituationSessionPlanId,
            status: status
        )
        sessionStore.upsertLocal(updated)
        sessions = sessionStore.sessions
        applySearch()
        if selectedSession?.id == session.id {
            selectedSession = updated
        }
        rebuildVisiblePlannerStructure()
    }

    private func composerSlotMetadata(day: Int, period: Int, groupId: Int64?) -> (slotId: Int64?, startTime: String?, endTime: String?) {
        let visibleSlot = visibleSlots.first(where: { $0.period == period })
        let scheduleSlot = teacherScheduleSlots.first { slot in
            guard Int(slot.dayOfWeek) == day else { return false }
            if let groupId, slot.schoolClassId != groupId { return false }
            if let visibleSlot {
                return slot.startTime == visibleSlot.startTime && slot.endTime == visibleSlot.endTime
            }
            return false
        }
        return (
            scheduleSlot?.id,
            scheduleSlot?.startTime ?? visibleSlot?.startTime,
            scheduleSlot?.endTime ?? visibleSlot?.endTime
        )
    }

}
