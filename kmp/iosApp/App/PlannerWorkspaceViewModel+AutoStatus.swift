import Foundation
import MiGestorKit

@MainActor
extension PlannerWorkspaceViewModel {
    /// Sesión `PLANNED` cuya franja horaria ya ha terminado. Es una etiqueta derivada
    /// de presentación, nunca escribe `COMPLETED` en BD en automático: marcar impartida
    /// sigue exigiendo confirmación del profesor para no generar falsos positivos
    /// (ausencias, cambios de horario, clase suspendida de palabra).
    func isPendingConfirmation(_ session: PlanningSession, now: Date = Date()) -> Bool {
        guard session.status == .planned else { return false }
        guard let end = sessionEndDate(for: session) else { return false }
        return now > end
    }

    private func sessionEndDate(for session: PlanningSession) -> Date? {
        guard let endMinutes = endMinutesOfDay(for: session) else { return nil }
        let calendar = Calendar(identifier: .iso8601)
        var components = DateComponents()
        components.calendar = calendar
        components.yearForWeekOfYear = Int(session.year)
        components.weekOfYear = Int(session.weekNumber)
        components.weekday = Int(session.dayOfWeek) + 1
        guard let day = components.date else { return nil }
        return calendar.date(byAdding: .minute, value: endMinutes, to: calendar.startOfDay(for: day))
    }

    private func endMinutesOfDay(for session: PlanningSession) -> Int? {
        if let endTime = session.endTime, let minutes = minutesFromTimeString(endTime) {
            return minutes
        }
        if let slot = timeSlots.first(where: { Int($0.period) == Int(session.period) }) {
            return minutesFromTimeString(slot.endTime)
        }
        return nil
    }

    private func minutesFromTimeString(_ value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return hour * 60 + minute
    }
}
