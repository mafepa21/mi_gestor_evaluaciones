import SwiftUI
import MiGestorKit

@MainActor
extension PlannerWorkspaceViewModel {
    func timeLabel(for period: Int) -> String {
        if let slot = visibleSlots.first(where: { $0.period == period }) {
            return slot.label
        }
        if let slot = timeSlots.first(where: { Int($0.period) == period }) {
            return "\(slot.startTime)-\(slot.endTime)"
        }
        return "P\(period)"
    }

    func summary(for sessionId: Int64) -> SessionJournalSummary? {
        journalSummaryBySessionId[sessionId]
    }

    func sessionPlan(for session: PlanningSession) -> LearningSituationSessionPlan? {
        guard let planId = session.learningSituationSessionPlanId?.int64Value else { return nil }
        return sessionPlansById[planId]
    }

    func sessionGlance(for session: PlanningSession) -> PlannerSessionGlanceData {
        let plan = sessionPlan(for: session)
        let situationTitle = session.teachingUnitName.nilIfBlank ?? "Situación sin título"
        let sessionTitle = plan?.title.nilIfBlank ?? situationTitle
        let objective = plan?.objective.nilIfBlank ?? session.objectives.nilIfBlank
        let activity = firstDevelopmentPreview(from: plan?.developmentJson) ?? session.activities.nilIfBlank
        let material = plan?.material.nilIfBlank

        var badges: [String] = []
        if let plan {
            badges.append("Sesión \(plan.sessionNumber)")
            if let sessionType = plan.sessionType.nilIfBlank {
                badges.append(sessionType)
            }
            if plan.effectiveMinutes > 0 {
                badges.append("\(plan.effectiveMinutes) min")
            }
        }

        return PlannerSessionGlanceData(
            situationTitle: situationTitle,
            sessionTitle: sessionTitle,
            badges: badges,
            objective: objective,
            activity: activity,
            material: material
        )
    }

    private func firstDevelopmentPreview(from json: String?) -> String? {
        guard let json, let data = json.data(using: .utf8),
              let sections = try? JSONDecoder().decode([LearningSituationSessionSectionDraft].self, from: data) else {
            return nil
        }

        let ignoredPrefixes = ["evidencia", "evidence", "objetivo", "objectives", "criterio", "criteria", "material", "materials"]
        for section in sections {
            let title = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedTitle = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            guard !ignoredPrefixes.contains(where: { normalizedTitle.hasPrefix($0) }) else { continue }
            if let line = section.lines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                return line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    func situationProgress(for session: PlanningSession?) -> PlannerSituationProgress? {
        guard let session else { return nil }
        let situationTitle = normalizedSituationTitle(session.teachingUnitName)
        let relatedSessions = sessions.filter {
            normalizedSituationTitle($0.teachingUnitName) == situationTitle
                && $0.groupId == session.groupId
        }
        guard !relatedSessions.isEmpty else { return nil }

        let completed = relatedSessions.count { candidate in
            candidate.status == .completed || summary(for: candidate.id)?.status == .completed
        }
        let review = relatedSessions.count { candidate in
            guard let summary = summary(for: candidate.id) else { return false }
            return summary.status == .draft || !summary.incidentTags.isEmpty
        }

        return PlannerSituationProgress(
            title: session.teachingUnitName.nilIfBlank ?? "Situación sin título",
            total: relatedSessions.count,
            completed: completed,
            pending: max(relatedSessions.count - completed, 0),
            review: review
        )
    }

    func sessionStateLabel(for session: PlanningSession) -> String {
        if isPendingConfirmation(session) { return "Confirmar impartida" }
        return sessionStateLabel(sessionStatus: session.status, journalStatus: summary(for: session.id)?.status)
    }

    func sessionStateIcon(for session: PlanningSession) -> String {
        if isPendingConfirmation(session) { return "clock.badge.exclamationmark.fill" }
        return sessionStateIcon(sessionStatus: session.status, journalStatus: summary(for: session.id)?.status)
    }

    func sessionStateTint(for session: PlanningSession) -> Color {
        if isPendingConfirmation(session) { return IOSAppStyle.warning }
        return sessionStateTint(sessionStatus: session.status, journalStatus: summary(for: session.id)?.status)
    }

    func sessionStateLabel(sessionStatus: SessionStatus?, journalStatus: SessionJournalStatus?) -> String {
        if journalStatus == .completed { return "Cerrada" }
        if journalStatus == .draft { return "Borrador" }
        if sessionStatus == .completed { return "Diario pendiente" }
        return "Planificada"
    }

    func sessionStateIcon(sessionStatus: SessionStatus?, journalStatus: SessionJournalStatus?) -> String {
        if journalStatus == .completed { return "checkmark.seal.fill" }
        if journalStatus == .draft { return "doc.text.fill" }
        if sessionStatus == .completed { return "checkmark.circle.fill" }
        return "calendar"
    }

    func sessionStateTint(sessionStatus: SessionStatus?, journalStatus: SessionJournalStatus?) -> Color {
        if journalStatus == .completed { return EvaluationDesign.success }
        if journalStatus == .draft { return EvaluationDesign.accent }
        if sessionStatus == .completed { return IOSAppStyle.warning }
        return .secondary
    }

    func classColorHex(for classId: Int64) -> String {
        classColorHexById[classId] ?? bridge?.plannerCourseColor(for: classId) ?? EvaluationDesign.plannerCoursePalette[0]
    }

    func dayLabel(for day: Int) -> String {
        switch day {
        case 1: return "Lun"
        case 2: return "Mar"
        case 3: return "Mié"
        case 4: return "Jue"
        case 5: return "Vie"
        case 6: return "Sáb"
        case 7: return "Dom"
        default: return "D\(day)"
        }
    }

    func dayHeaderLabel(for day: Int) -> String {
        let days = IsoWeekHelper.shared.daysOf(isoWeek: Int32(week), year: Int32(year))
        guard day >= 1 && day <= days.count else { return dayLabel(for: day) }
        let date = days[day - 1]
        let dayName = dayLabel(for: day)
        return "\(dayName) \(date.dayOfMonth)/\(date.monthNumber)"
    }
}
