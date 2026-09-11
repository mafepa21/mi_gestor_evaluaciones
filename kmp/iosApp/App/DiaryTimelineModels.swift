import SwiftUI
import MiGestorKit

enum DiaryViewMode: String, CaseIterable, Identifiable {
    case week = "Semanal"
    case timeline = "Bitácora continua"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .week: return "calendar.badge.clock"
        case .timeline: return "list.bullet.indent"
        }
    }
}

enum DiaryTimelineQuarter: String, CaseIterable, Identifiable {
    case all = "Todo el curso"
    case q1 = "1.er Trimestre"
    case q2 = "2.º Trimestre"
    case q3 = "3.er Trimestre"

    var id: String { rawValue }

    func matches(date: Date) -> Bool {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)

        switch self {
        case .all:
            return true
        case .q1:
            // Septiembre a 22 de Diciembre
            if month == 9 || month == 10 || month == 11 { return true }
            if month == 12 && day <= 22 { return true }
            return false
        case .q2:
            // 7 de Enero a 31 de Marzo
            if month == 1 && day >= 7 { return true }
            if month == 2 || month == 3 { return true }
            return false
        case .q3:
            // Abril a Junio
            if month == 4 || month == 5 || month == 6 { return true }
            return false
        }
    }
}

extension SessionJournalDecision {
    var label: String {
        switch self {
        case .none: return ""
        case .repeatSession: return "Repetir sesión"
        case .reinforce: return "Reforzar contenidos"
        case .advance: return "Avanzar en programación"
        default: return ""
        }
    }
}

struct DiaryTimelineEntry: Identifiable {
    let id: Int64
    let session: PlanningSession
    let date: Date
    let sessionIndex: Int
    let summary: SessionJournalSummary?

    var hasJournal: Bool {
        guard let summary else { return false }
        return summary.status != .empty
    }

    var isCompleted: Bool {
        summary?.status == .completed
    }

    var hasIncidents: Bool {
        !(summary?.incidentTags.isEmpty ?? true)
    }

    var statusColor: Color {
        switch summary?.status ?? .empty {
        case .completed: return AppleDesignSystem.success
        case .draft: return AppleDesignSystem.warning
        default: return Color.secondary.opacity(0.3)
        }
    }

    static func dateFor(session: PlanningSession) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2 // Lunes
        var components = DateComponents()
        components.yearForWeekOfYear = Int(session.year)
        components.weekOfYear = Int(session.weekNumber)
        // PlanningSession.dayOfWeek: 1 = Lunes ... 5 = Viernes
        // En Calendar (Sunday=1, Monday=2): weekday = dayOfWeek + 1
        components.weekday = Int(session.dayOfWeek) + 1
        components.hour = 9
        components.minute = 0
        return calendar.date(from: components) ?? Date()
    }
}

struct DiaryTimelineMonthSection: Identifiable {
    let id: String
    let monthName: String
    let entries: [DiaryTimelineEntry]
}
