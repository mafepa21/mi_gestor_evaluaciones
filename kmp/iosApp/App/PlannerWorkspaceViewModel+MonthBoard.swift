import SwiftUI
import MiGestorKit

@MainActor
extension PlannerWorkspaceViewModel {
    func reloadMonthData() async {
        guard let bridge else { return }
        do {
            monthSessions = try await bridge.plannerListAllSessions()
        } catch {
            monthSessions = []
        }

        do {
            let allEvents = (try? await bridge.plannerAllCalendarEvents()) ?? []
            monthMilestones = buildMonthMilestones(from: allEvents)
        }
    }

    func previousMonth() async {
        let calendar = Calendar(identifier: .iso8601)
        if let newDate = calendar.date(byAdding: .month, value: -1, to: monthViewDate) {
            monthViewDate = newDate
        }
    }

    func nextMonth() async {
        let calendar = Calendar(identifier: .iso8601)
        if let newDate = calendar.date(byAdding: .month, value: 1, to: monthViewDate) {
            monthViewDate = newDate
        }
    }

    func goToTodayMonth() async {
        monthViewDate = Date()
    }

    func selectMonthDate(_ date: Date) {
        monthViewDate = date
    }

    func jumpToDayView(for date: Date) async {
        let calendar = Calendar(identifier: .iso8601)
        let isoWeek = calendar.component(.weekOfYear, from: date)
        let isoYear = calendar.component(.yearForWeekOfYear, from: date)
        let dayOfWeek = ((calendar.component(.weekday, from: date) + 5) % 7) + 1

        self.year = isoYear
        self.week = isoWeek
        self.dayViewSelectedDay = dayOfWeek
        self.activeSection = .day
        await self.reloadSessionsOnly(keepSelection: false)
        self.rebuildWeekRenderModel()
    }

    func jumpToWeekView(for date: Date) async {
        let calendar = Calendar(identifier: .iso8601)
        let isoWeek = calendar.component(.weekOfYear, from: date)
        let isoYear = calendar.component(.yearForWeekOfYear, from: date)

        self.year = isoYear
        self.week = isoWeek
        self.activeSection = .week
        await self.reloadSessionsOnly(keepSelection: false)
        self.rebuildWeekRenderModel()
    }

    func openComposerForDate(_ date: Date) {
        let calendar = Calendar(identifier: .iso8601)
        let isoWeek = calendar.component(.weekOfYear, from: date)
        let isoYear = calendar.component(.yearForWeekOfYear, from: date)
        let dayOfWeek = ((calendar.component(.weekday, from: date) + 5) % 7) + 1

        self.year = isoYear
        self.week = isoWeek
        self.openComposer(day: dayOfWeek, period: 1)
    }

    func buildMonthGrid() -> PlannerMonthGrid {
        let calendar = Calendar(identifier: .iso8601)
        let targetYear = calendar.component(.year, from: monthViewDate)
        let targetMonth = calendar.component(.month, from: monthViewDate)

        var firstDayComponents = DateComponents()
        firstDayComponents.year = targetYear
        firstDayComponents.month = targetMonth
        firstDayComponents.day = 1
        firstDayComponents.hour = 12
        let firstDayOfMonth = calendar.date(from: firstDayComponents) ?? monthViewDate

        let rangeOfDays = calendar.range(of: .day, in: .month, for: firstDayOfMonth) ?? 1..<31
        let numberOfDaysInMonth = rangeOfDays.count

        // ISO 8601: Lunes = 1, Domingo = 7
        let firstWeekday = ((calendar.component(.weekday, from: firstDayOfMonth) + 5) % 7) + 1
        let leadingPaddingDays = firstWeekday - 1

        var allDayDates: [(date: Date, isCurrentMonth: Bool)] = []

        // Días de relleno del mes anterior
        if leadingPaddingDays > 0 {
            for i in (1...leadingPaddingDays).reversed() {
                if let prevDate = calendar.date(byAdding: .day, value: -i, to: firstDayOfMonth) {
                    allDayDates.append((date: prevDate, isCurrentMonth: false))
                }
            }
        }

        // Días del mes actual
        for day in 1...numberOfDaysInMonth {
            if let monthDate = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                allDayDates.append((date: monthDate, isCurrentMonth: true))
            }
        }

        // Días de relleno del mes siguiente (completar múltiplos de 7, estándar 35 o 42 celdas)
        let totalSoFar = allDayDates.count
        let targetCells = totalSoFar <= 35 ? 35 : 42
        let trailingPaddingDays = max(0, targetCells - totalSoFar)

        if let lastDayOfMonth = calendar.date(byAdding: .day, value: numberOfDaysInMonth - 1, to: firstDayOfMonth) {
            for i in 1...trailingPaddingDays {
                if let nextDate = calendar.date(byAdding: .day, value: i, to: lastDayOfMonth) {
                    allDayDates.append((date: nextDate, isCurrentMonth: false))
                }
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.calendar = calendar

        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "es_ES")
        monthFormatter.dateFormat = "MMMM yyyy"
        let monthName = monthFormatter.string(from: firstDayOfMonth).capitalized

        let milestonesByDateIso = Dictionary(grouping: monthMilestones, by: { $0.dateIso })

        var totalMonthSessions = 0
        var allDays: [PlannerMonthDay] = []

        for item in allDayDates {
            let dayDate = item.date
            let dateIso = dateFormatter.string(from: dayDate)
            let dayNum = calendar.component(.day, from: dayDate)
            let monthNum = calendar.component(.month, from: dayDate)
            let yearNum = calendar.component(.year, from: dayDate)
            let dayOfWeek = ((calendar.component(.weekday, from: dayDate) + 5) % 7) + 1
            let isToday = calendar.isDateInToday(dayDate)
            let isWeekend = dayOfWeek == 6 || dayOfWeek == 7

            let isoWeek = calendar.component(.weekOfYear, from: dayDate)
            let isoYear = calendar.component(.yearForWeekOfYear, from: dayDate)

            // Filtrar sesiones del día
            let daySessions = monthSessions.filter { session in
                let matchDate = Int(session.year) == isoYear
                    && Int(session.weekNumber) == isoWeek
                    && Int(session.dayOfWeek) == dayOfWeek
                guard matchDate else { return false }
                if let selectedGroupId {
                    return session.groupId == selectedGroupId
                }
                return true
            }.sorted { s1, s2 in
                if s1.period != s2.period {
                    return s1.period < s2.period
                }
                return (s1.startTime ?? "") < (s2.startTime ?? "")
            }

            if item.isCurrentMonth {
                totalMonthSessions += daySessions.count
            }

            let dayMilestones = milestonesByDateIso[dateIso] ?? []

            allDays.append(
                PlannerMonthDay(
                    date: dayDate,
                    dateIso: dateIso,
                    dayNumber: dayNum,
                    month: monthNum,
                    year: yearNum,
                    dayOfWeek: dayOfWeek,
                    isCurrentMonth: item.isCurrentMonth,
                    isToday: isToday,
                    isWeekend: isWeekend,
                    milestones: dayMilestones,
                    sessions: daySessions
                )
            )
        }

        // Dividir en semanas de 7 días
        var weeks: [[PlannerMonthDay]] = []
        for chunkIndex in stride(from: 0, to: allDays.count, by: 7) {
            let endIndex = min(chunkIndex + 7, allDays.count)
            weeks.append(Array(allDays[chunkIndex..<endIndex]))
        }

        return PlannerMonthGrid(
            year: targetYear,
            month: targetMonth,
            monthName: monthName,
            weeks: weeks,
            totalSessionsCount: totalMonthSessions
        )
    }

    private func buildMonthMilestones(from events: [CalendarEvent]) -> [PlannerDayMilestone] {
        var milestones: [PlannerDayMilestone] = []
        let calendar = Calendar(identifier: .iso8601)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.calendar = calendar

        let groupsById = Dictionary(groups.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        for event in events {
            let startDate = Date(timeIntervalSince1970: Double(event.startAt.toEpochMilliseconds()) / 1000.0)
            let endDate = Date(timeIntervalSince1970: Double(event.endAt.toEpochMilliseconds()) / 1000.0)

            let titleLower = event.title.lowercased()
            let descLower = (event.description_ ?? "").lowercased()
            let haystack = "\(titleLower) \(descLower)"

            let category: PlannerMilestoneCategory
            if haystack.contains("examen") || haystack.contains("parcial") || haystack.contains("global") {
                category = .exam
            } else if event.classId != nil || haystack.contains("viaje") || haystack.contains("salida") || haystack.contains("excursion") || haystack.contains("excursión") {
                category = .trip
            } else if haystack.contains("evaluacion") || haystack.contains("evaluación") || haystack.contains("trimestre") {
                category = .evaluation
            } else if haystack.contains("reunión") || haystack.contains("notas") || haystack.contains("graduación") || haystack.contains("claustro") {
                category = .milestone
            } else {
                category = .holiday
            }

            let isBlocking = haystack.contains("no lectivo") ||
                haystack.contains("festivo") ||
                haystack.contains("vacaciones") ||
                haystack.contains("puente") ||
                haystack.contains("examen") ||
                haystack.contains("parcial") ||
                haystack.contains("global")

            let className = event.classId.flatMap { groupsById[$0.int64Value] }

            var cursor = calendar.startOfDay(for: startDate)
            let endDay = calendar.startOfDay(for: endDate)

            while cursor <= endDay {
                let dateIso = dateFormatter.string(from: cursor)
                let dayOfWeek = ((calendar.component(.weekday, from: cursor) + 5) % 7) + 1

                milestones.append(
                    PlannerDayMilestone(
                        id: "month-evt-\(event.id)-\(dateIso)",
                        title: event.title,
                        subtitle: event.description_,
                        category: category,
                        dayOfWeek: dayOfWeek,
                        dateIso: dateIso,
                        classId: event.classId?.int64Value,
                        className: className,
                        isBlocking: isBlocking
                    )
                )

                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }

        return milestones
    }
}
