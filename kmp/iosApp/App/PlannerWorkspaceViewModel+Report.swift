import SwiftUI
import MiGestorKit

@MainActor
extension PlannerWorkspaceViewModel {
    /// Resuelve sesiones + resúmenes de diario para el rango pedido (semana en curso,
    /// mes natural o una evaluación), usado tanto por el Resumen conmutable como por
    /// el informe PDF. La semana usa los datos ya cargados; mes/evaluación piden todas
    /// las sesiones al bridge y filtran por semana ISO, ya que solo la semana en curso
    /// se mantiene precargada en el ViewModel.
    func loadRangeData(_ range: PlannerReportRange, groupId: Int64?) async -> PlannerRangeData {
        switch range {
        case .week:
            // Se ignora el texto de búsqueda (irrelevante para un resumen agregado) y se
            // aplica el filtro de grupo del selector, igual que en Semana/Secuencia.
            let weekSessions = filteredPlannerSessions().filter { groupId == nil || $0.groupId == groupId }
            return PlannerRangeData(
                range: range,
                rangeLabel: "\(weekLabel) · \(dateRangeLabel)",
                sessions: weekSessions,
                journalSummaryBySessionId: journalSummaryBySessionId,
                weeks: [PlannerGanttWeek(year: year, week: week)]
            )
        case .month:
            return await loadRangeData(weeks: monthWeeks(), label: monthLabel(), range: range, groupId: groupId)
        case .evaluationPeriod(let periodId):
            guard let period = evaluationPeriods.first(where: { $0.id == periodId }),
                  let weeks = PlannerGanttWeek.range(fromIso: period.startDateIso, toIso: period.endDateIso) else {
                return .empty
            }
            return await loadRangeData(weeks: weeks, label: period.name, range: range, groupId: groupId)
        }
    }

    private func loadRangeData(
        weeks: [PlannerGanttWeek],
        label: String,
        range: PlannerReportRange,
        groupId: Int64?
    ) async -> PlannerRangeData {
        guard let bridge else {
            return PlannerRangeData(range: range, rangeLabel: label, sessions: [], journalSummaryBySessionId: [:], weeks: weeks)
        }
        let weekSet = Set(weeks)
        let allSessions = (try? await bridge.plannerListAllSessions()) ?? []
        let matching = allSessions.filter { session in
            weekSet.contains(PlannerGanttWeek(year: Int(session.year), week: Int(session.weekNumber)))
                && (groupId == nil || session.groupId == groupId)
        }
        let summaries = (try? await bridge.plannerJournalSummaries(sessionIds: matching.map(\.id))) ?? []
        let summaryById = Dictionary(uniqueKeysWithValues: summaries.map { ($0.planningSessionId, $0) })
        return PlannerRangeData(
            range: range,
            rangeLabel: label,
            sessions: matching,
            journalSummaryBySessionId: summaryById,
            weeks: weeks
        )
    }

    private func monthWeeks() -> [PlannerGanttWeek] {
        let calendar = Calendar(identifier: .iso8601)
        let now = Date()
        guard let interval = calendar.dateInterval(of: .month, for: now) else {
            return [PlannerGanttWeek(date: now)]
        }
        var weeks: [PlannerGanttWeek] = []
        var cursor = interval.start
        while cursor < interval.end && weeks.count < 6 {
            weeks.append(PlannerGanttWeek(date: cursor))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        return weeks
    }

    private func monthLabel() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: Date()).capitalized
    }
}
