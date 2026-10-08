import Foundation
import MiGestorKit

/// Repetidos que hay en el calendario y en los periodos de evaluación.
struct CalendarDuplicateReport {
    let eventIds: [Int64]
    let periodIds: [Int64]

    var isEmpty: Bool {
        eventIds.isEmpty && periodIds.isEmpty
    }
}

extension KmpBridge {
    /// Solo lee: calcula qué se borraría. No borra nada.
    func calendarDuplicateReport() async throws -> CalendarDuplicateReport {
        let events = try await plannerAllCalendarEvents().map { event in
            CalendarDuplicateCandidate(
                id: event.id,
                title: event.title,
                startMs: event.startAt.toEpochMilliseconds(),
                endMs: event.endAt.toEpochMilliseconds(),
                classId: event.classId?.int64Value,
                isLinked: event.externalProvider == AppleCalendarMirror.provider
            )
        }

        var periods: [EvaluationPeriodDuplicateCandidate] = []
        let schedule = try? await plannerTeacherSchedule()
        if let scheduleId = schedule?.id {
            let stored = (try? await plannerEvaluationPeriods(scheduleId: scheduleId)) ?? []
            periods = stored.map { period in
                EvaluationPeriodDuplicateCandidate(
                    id: period.id,
                    name: period.name,
                    startDateIso: period.startDateIso,
                    endDateIso: period.endDateIso,
                    scheduleId: scheduleId
                )
            }
        }

        return CalendarDuplicateReport(
            eventIds: CalendarDuplicatePlanner.eventIdsToRemove(events),
            periodIds: CalendarDuplicatePlanner.periodIdsToRemove(periods)
        )
    }

    /// Borra lo que indica el informe. Solo lo llama la acción que confirma el usuario.
    /// Los borrados de eventos pasan por la sincronización, así que se borran también en los demás aparatos.
    func removeCalendarDuplicates(_ report: CalendarDuplicateReport) async throws -> (events: Int, periods: Int) {
        for id in report.eventIds {
            try await plannerDeleteCalendarEvent(id: id)
        }
        for id in report.periodIds {
            try await plannerDeleteEvaluationPeriod(periodId: id)
        }
        return (report.eventIds.count, report.periodIds.count)
    }
}
