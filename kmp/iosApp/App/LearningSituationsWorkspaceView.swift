import SwiftUI
import UniformTypeIdentifiers
import MiGestorKit

extension LearningSituation: @retroactive Identifiable {}

struct LearningSituationScheduledDestination: Hashable {
    let period: Int
    let teacherScheduleSlotId: Int64?
    let startTime: String
    let endTime: String
}

struct LearningSituationScheduledSlot: Identifiable {
    let id = UUID()
    let date: Date
    let period: Int
    let teacherScheduleSlotId: Int64?
    let startTime: String
    let endTime: String
    let planSessionNumber: Int?
    let blockKind: String?
    let occupiedPeriods: [Int]
    let occupiedScheduleSlots: [LearningSituationScheduledDestination]
    var isSelected = true

    init(
        date: Date,
        period: Int,
        teacherScheduleSlotId: Int64?,
        startTime: String,
        endTime: String,
        planSessionNumber: Int? = nil,
        blockKind: String? = nil,
        occupiedPeriods: [Int] = [],
        occupiedScheduleSlots: [LearningSituationScheduledDestination] = [],
        isSelected: Bool = true
    ) {
        self.date = date
        self.period = period
        self.teacherScheduleSlotId = teacherScheduleSlotId
        self.startTime = startTime
        self.endTime = endTime
        self.planSessionNumber = planSessionNumber
        self.blockKind = blockKind
        self.occupiedPeriods = occupiedPeriods
        self.occupiedScheduleSlots = occupiedScheduleSlots
        self.isSelected = isSelected
    }

    var label: String {
        let planLabel = planSessionNumber.map { "Sesión \($0) · " } ?? ""
        let blockLabel = blockKind.map { "\($0) · " } ?? ""
        return "\(planLabel)\(blockLabel)\(date.formatted(date: .abbreviated, time: .omitted)) · \(startTime)-\(endTime)"
    }

    var destinationPeriods: [Int] {
        destinationSlots.map(\.period)
    }

    var destinationSlots: [LearningSituationScheduledDestination] {
        if !occupiedScheduleSlots.isEmpty {
            return occupiedScheduleSlots
        }
        let periods = occupiedPeriods.isEmpty ? [period] : occupiedPeriods
        return periods.map {
            LearningSituationScheduledDestination(
                period: $0,
                teacherScheduleSlotId: $0 == period ? teacherScheduleSlotId : nil,
                startTime: $0 == period ? startTime : "",
                endTime: $0 == period ? endTime : ""
            )
        }
    }
}

struct LearningSituationScheduleTemplateDescriptor: Hashable {
    let dayOfWeek: Int
    let startTime: String
    let endTime: String
}

struct LearningSituationScheduleProjectionResult {
    let slots: [LearningSituationScheduledSlot]
    let warnings: [String]
    let route: LearningSituationWeeklySequenceRoute?
}

enum LearningSituationSessionSequenceKind: Equatable {
    case canonicalWeekly
    case legacyWeekly
    case routeAware
    case linear
}

enum LearningSituationScheduleProjection {
    static func canonicalBlockCount(forAnnualSessionCount annualSessionCount: Int) -> Int {
        guard annualSessionCount > 0 else { return 0 }
        return ((annualSessionCount + 1) / 2) * 2
    }

    static func targetSessionCount(
        plans: [LearningSituationSessionPlanDraft],
        annualSessionCount: Int,
        sequenceKind: LearningSituationSessionSequenceKind
    ) -> Int {
        guard !plans.isEmpty else { return max(annualSessionCount, 1) }
        guard sequenceKind == .canonicalWeekly, annualSessionCount > 0 else { return plans.count }
        return annualSessionCount
    }

    static func hasExpectedCanonicalBlockCount(
        plans: [LearningSituationSessionPlanDraft],
        annualSessionCount: Int
    ) -> Bool {
        guard annualSessionCount > 0 else { return true }
        return plans.count == canonicalBlockCount(forAnnualSessionCount: annualSessionCount)
    }

    static func sequenceKind(
        for plans: [LearningSituationSessionPlanDraft]
    ) -> LearningSituationSessionSequenceKind {
        guard !plans.isEmpty else { return .linear }
        let routeAware = plans.allSatisfy {
            $0.sequenceRoute != nil && $0.blockRole != nil && ($0.sequenceFormat?.hasPrefix("route-aware-") == true)
        }
        if routeAware { return .routeAware }
        let canonical = plans.allSatisfy {
            $0.blockRole != nil && $0.cycleIndex != nil && $0.weekKey != nil && $0.sequenceFormat != nil
        }
        if canonical { return .canonicalWeekly }
        return plans.contains(where: isWeeklyBlockPlan) ? .legacyWeekly : .linear
    }

    static func uniqueTemplateIndices(
        for descriptors: [LearningSituationScheduleTemplateDescriptor]
    ) -> [Int] {
        var seen = Set<LearningSituationScheduleTemplateDescriptor>()
        return descriptors.indices.filter { seen.insert(descriptors[$0]).inserted }
    }

    static func hasDuplicateDestinations(_ slots: [LearningSituationScheduledSlot]) -> Bool {
        let calendar = Calendar(identifier: .iso8601)
        var seen = Set<ScheduledDestination>()
        for slot in slots {
            for period in slot.destinationPeriods {
                let destination = ScheduledDestination(
                    date: calendar.startOfDay(for: slot.date),
                    period: period
                )
                if !seen.insert(destination).inserted {
                    return true
                }
            }
        }
        return false
    }

    static func planAwareSlots(
        plans: [LearningSituationSessionPlanDraft],
        startDate: Date,
        template: [TeacherScheduleSlot],
        periodForSlot: (TeacherScheduleSlot) -> Int,
        targetSessionCount: Int? = nil,
        excludedDates: Set<Date> = []
    ) -> LearningSituationScheduleProjectionResult {
        let orderedPlans = plans.sorted {
            if $0.sessionNumber != $1.sessionNumber { return $0.sessionNumber < $1.sessionNumber }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard !orderedPlans.isEmpty, !template.isEmpty else {
            return LearningSituationScheduleProjectionResult(slots: [], warnings: [], route: nil)
        }
        let calendar = Calendar(identifier: .iso8601)
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedExcludedDates = Set(excludedDates.map { calendar.startOfDay(for: $0) })
        let sortedTemplate = template.sorted {
            Int($0.dayOfWeek) == Int($1.dayOfWeek) ? $0.startTime < $1.startTime : $0.dayOfWeek < $1.dayOfWeek
        }
        let requestedCount = max(targetSessionCount ?? orderedPlans.count, 0)
        let targetCount = min(requestedCount, orderedPlans.count)

        let weeklyPlans = sequenceKind(for: orderedPlans) != .linear
        guard weeklyPlans else {
            var sequential: [LearningSituationScheduledSlot] = []
            var date = normalizedStart
            while sequential.count < targetCount {
                if normalizedExcludedDates.contains(calendar.startOfDay(for: date)) {
                    guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
                    date = nextDate
                    continue
                }
                let weekday = ((calendar.component(.weekday, from: date) + 5) % 7) + 1
                for slot in sortedTemplate where Int(slot.dayOfWeek) == weekday {
                    let period = periodForSlot(slot)
                    sequential.append(LearningSituationScheduledSlot(
                        date: date,
                        period: period,
                        teacherScheduleSlotId: slot.id,
                        startTime: slot.startTime,
                        endTime: slot.endTime,
                        planSessionNumber: orderedPlans[sequential.count].sessionNumber,
                        blockKind: orderedPlans[sequential.count].sessionType,
                        occupiedPeriods: [period],
                        occupiedScheduleSlots: [LearningSituationScheduledDestination(
                            period: period,
                            teacherScheduleSlotId: slot.id,
                            startTime: slot.startTime,
                            endTime: slot.endTime
                        )]
                    ))
                    if sequential.count == targetCount { break }
                }
                guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
                date = nextDate
            }
            return LearningSituationScheduleProjectionResult(
                slots: sequential,
                warnings: sequential.count == targetCount ? [] : ["No hay suficientes franjas para todas las sesiones importadas."],
                route: nil
            )
        }

        var assignments: [LearningSituationScheduledSlot] = []
        var warnings: [String] = []
        var usedDestinations = Set<ScheduledDestination>()
        var previousAssignment: LearningSituationScheduledSlot?
        var route: LearningSituationWeeklySequenceRoute?
        if sequenceKind(for: orderedPlans) == .routeAware {
            for plan in orderedPlans.prefix(targetCount) {
                let role = blockRole(for: plan)
                guard let candidate = nextCandidate(
                    for: role,
                    startDate: normalizedStart,
                    after: previousAssignment,
                    sortedTemplate: sortedTemplate,
                    periodForSlot: periodForSlot,
                    usedDestinations: usedDestinations,
                    searchDays: max(orderedPlans.count * 14 + 14, 84),
                    excludedDates: normalizedExcludedDates
                ) else {
                    let requirement = requirementLabel(for: role)
                    warnings.append("La sesión \(plan.sessionNumber) requiere un \(requirement), pero no hay una franja compatible desde la fecha de inicio.")
                    continue
                }
                let assigned = withPlan(candidate, plan: plan)
                assignments.append(assigned)
                addDestinations(assigned, to: &usedDestinations)
                previousAssignment = assigned
                route = plan.sequenceRoute
            }
            return LearningSituationScheduleProjectionResult(slots: assignments, warnings: warnings, route: route)
        }
        let searchDays = max(orderedPlans.count * 14 + 14, 84)
        let cycleGroups = Dictionary(grouping: orderedPlans) { cycleIndex(for: $0) }

        // The document order (usually LONG session 1, SHORT session 2) is not a
        // calendar order. Each cycle is therefore resolved independently from the
        // next real compatible opportunities, which also handles a partial first
        // week and lets a valid SHORT opportunity precede the first LONG one.
        for cycleIndex in cycleGroups.keys.sorted() {
            var pending = cycleGroups[cycleIndex, default: []]
                .sorted { $0.sessionNumber < $1.sessionNumber }
                .map { WeeklyPendingPlan(plan: $0, role: blockRole(for: $0)) }

            while !pending.isEmpty && assignments.count < targetCount {
                let candidates = pending.compactMap { pendingPlan -> WeeklyCandidate? in
                    guard let candidate = nextCandidate(
                        for: pendingPlan.role,
                        startDate: normalizedStart,
                        after: previousAssignment,
                        sortedTemplate: sortedTemplate,
                        periodForSlot: periodForSlot,
                        usedDestinations: usedDestinations,
                        searchDays: searchDays,
                        excludedDates: normalizedExcludedDates
                    ) else { return nil }
                    return WeeklyCandidate(pendingPlan: pendingPlan, slot: candidate)
                }

                guard let next = candidates.min(by: { isChronologicallyBefore($0.slot, $1.slot) }) else {
                    for pendingPlan in pending {
                        let requirement = requirementLabel(for: pendingPlan.role)
                        warnings.append("La sesión \(pendingPlan.plan.sessionNumber) requiere un \(requirement), pero no hay una franja compatible desde la fecha de inicio.")
                    }
                    break
                }

                let assigned = withPlan(next.slot, plan: next.pendingPlan.plan)
                assignments.append(assigned)
                addDestinations(assigned, to: &usedDestinations)
                previousAssignment = assigned
                if route == nil {
                    route = next.pendingPlan.role == .short ? .shortFirst : .longFirst
                }
                pending.removeAll { $0.plan.id == next.pendingPlan.plan.id }
            }

            if assignments.count == targetCount { break }
        }

        let orderedAssignments = assignments.sorted(by: isChronologicallyBefore)
        return LearningSituationScheduleProjectionResult(slots: orderedAssignments, warnings: warnings, route: route)
    }

    private struct WeeklyPendingPlan {
        let plan: LearningSituationSessionPlanDraft
        let role: LearningSituationWeeklyBlockRole
    }

    private struct WeeklyCandidate {
        let pendingPlan: WeeklyPendingPlan
        let slot: LearningSituationScheduledSlot
    }

    static func inferRouteForFirstBlock(
        startDate: Date,
        template: [TeacherScheduleSlot],
        periodForSlot: (TeacherScheduleSlot) -> Int,
        excludedDates: Set<Date> = []
    ) -> LearningSituationWeeklySequenceRoute? {
        let calendar = Calendar(identifier: .iso8601)
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedExcludedDates = Set(excludedDates.map { calendar.startOfDay(for: $0) })
        let sortedTemplate = template.sorted {
            Int($0.dayOfWeek) == Int($1.dayOfWeek) ? $0.startTime < $1.startTime : $0.dayOfWeek < $1.dayOfWeek
        }
        var firstShort: LearningSituationScheduledSlot?
        var firstLong: LearningSituationScheduledSlot?
        for dayOffset in 0...84 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: normalizedStart),
                  !normalizedExcludedDates.contains(calendar.startOfDay(for: date)) else { continue }
            let weekday = ((calendar.component(.weekday, from: date) + 5) % 7) + 1
            let daySlots = sortedTemplate.filter { Int($0.dayOfWeek) == weekday }
            if firstLong == nil {
                firstLong = longCandidates(on: date, slots: daySlots, periodForSlot: periodForSlot).first
            }
            if firstShort == nil {
                firstShort = shortOnlyCandidates(on: date, slots: daySlots, periodForSlot: periodForSlot).first
            }
            if firstShort != nil || firstLong != nil {
                // A first slot that can start a long block wins ties: that is the only
                // deterministic interpretation when two consecutive periods are available.
                break
            }
        }
        guard let firstShort, let firstLong else {
            if firstLong != nil { return .longFirst }
            if firstShort != nil { return .shortFirst }
            return nil
        }
        let sameStart = firstLong.date == firstShort.date && firstLong.startTime == firstShort.startTime
        return sameStart || isChronologicallyBefore(firstLong, firstShort) ? .longFirst : .shortFirst
    }

    private struct ScheduledDestination: Hashable {
        let date: Date
        let period: Int
    }

    private static func nextCandidate(
        for role: LearningSituationWeeklyBlockRole,
        startDate: Date,
        after previous: LearningSituationScheduledSlot?,
        sortedTemplate: [TeacherScheduleSlot],
        periodForSlot: (TeacherScheduleSlot) -> Int,
        usedDestinations: Set<ScheduledDestination>,
        searchDays: Int,
        excludedDates: Set<Date>
    ) -> LearningSituationScheduledSlot? {
        let calendar = Calendar(identifier: .iso8601)
        let normalizedStart = calendar.startOfDay(for: startDate)
        for dayOffset in 0...searchDays {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: normalizedStart) else { continue }
            guard !excludedDates.contains(calendar.startOfDay(for: date)) else { continue }
            let weekday = ((calendar.component(.weekday, from: date) + 5) % 7) + 1
            let daySlots = sortedTemplate.filter { Int($0.dayOfWeek) == weekday }
            let candidates: [LearningSituationScheduledSlot]
            switch role {
            case .long:
                candidates = longCandidates(on: date, slots: daySlots, periodForSlot: periodForSlot)
            case .short:
                candidates = shortCandidates(on: date, slots: daySlots, periodForSlot: periodForSlot)
            case .longPart1:
                candidates = longPartCandidates(on: date, slots: daySlots, periodForSlot: periodForSlot)
            }
            for candidate in candidates {
                guard !collides(candidate, with: usedDestinations), follows(candidate, after: previous) else { continue }
                return candidate
            }
        }
        return nil
    }

    private static func follows(_ slot: LearningSituationScheduledSlot, after previous: LearningSituationScheduledSlot?) -> Bool {
        guard let previous else { return true }
        let calendar = Calendar(identifier: .iso8601)
        let currentDate = calendar.startOfDay(for: slot.date)
        let previousDate = calendar.startOfDay(for: previous.date)
        guard currentDate >= previousDate else { return false }
        guard currentDate == previousDate else { return true }
        guard let previousEnd = minutes(previous.endTime), let currentStart = minutes(slot.startTime) else { return false }
        return currentStart >= previousEnd
    }

    private static func isChronologicallyBefore(_ lhs: LearningSituationScheduledSlot, _ rhs: LearningSituationScheduledSlot) -> Bool {
        let calendar = Calendar(identifier: .iso8601)
        let lhsDate = calendar.startOfDay(for: lhs.date)
        let rhsDate = calendar.startOfDay(for: rhs.date)
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        let lhsStart = minutes(lhs.startTime) ?? .max
        let rhsStart = minutes(rhs.startTime) ?? .max
        if lhsStart != rhsStart { return lhsStart < rhsStart }
        return (lhs.planSessionNumber ?? .max) < (rhs.planSessionNumber ?? .max)
    }

    private static func cycleIndex(for plan: LearningSituationSessionPlanDraft) -> Int {
        if let cycleIndex = plan.cycleIndex, cycleIndex > 0 { return cycleIndex }
        if let weekKey = plan.weekKey, let parsed = Int(weekKey.filter { $0.isNumber }), parsed > 0 { return parsed }
        return max((plan.sessionNumber + 1) / 2, 1)
    }

    private static func blockRole(for plan: LearningSituationSessionPlanDraft) -> LearningSituationWeeklyBlockRole {
        if let blockRole = plan.blockRole { return blockRole }
        let value = plan.sessionType.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if value.contains("long_part_1") || value.contains("long part 1") { return .longPart1 }
        if isLongPlan(plan) && !isShortPlan(plan) { return .long }
        if isShortPlan(plan) && !isLongPlan(plan) { return .short }
        return plan.sessionNumber.isMultiple(of: 2) ? .short : .long
    }

    private static func isLongPlan(_ plan: LearningSituationSessionPlanDraft) -> Bool {
        if plan.blockRole == .longPart1 { return false }
        if plan.blockRole == .long { return true }
        if plan.blockRole == .short { return false }
        let value = plan.sessionType.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return value.contains("long") || value.contains("largo") || value.contains("double") || value.contains("doble") || plan.effectiveMinutes >= 75
    }

    private static func isWeeklyBlockPlan(_ plan: LearningSituationSessionPlanDraft) -> Bool {
        if plan.blockRole != nil || plan.cycleIndex != nil || plan.weekKey != nil || plan.sequenceFormat != nil { return true }
        let value = "\(plan.sessionType) \(plan.sourceLabel)".folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if value.contains("long block") || value.contains("short block") || value.contains("bloque largo") || value.contains("bloque corto") {
            return true
        }
        let hasWeekMarker = value.contains("week") || value.contains("semana")
        return hasWeekMarker && (value.contains("simple") || value.contains("double") || value.contains("doble") || value.contains("long") || value.contains("short"))
    }

    private static func isShortPlan(_ plan: LearningSituationSessionPlanDraft) -> Bool {
        if plan.blockRole == .longPart1 { return false }
        if plan.blockRole == .short { return true }
        if plan.blockRole == .long { return false }
        let value = plan.sessionType.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return value.contains("short") || value.contains("corto") || value.contains("simple") || plan.effectiveMinutes > 0 && plan.effectiveMinutes < 75
    }

    private static func minutes(_ value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return hour * 60 + minute
    }

    private static func longCandidates(
        on date: Date,
        slots: [TeacherScheduleSlot],
        periodForSlot: (TeacherScheduleSlot) -> Int
    ) -> [LearningSituationScheduledSlot] {
        let ordered = slots.sorted { $0.startTime < $1.startTime }
        var candidates: [LearningSituationScheduledSlot] = []
        for slot in ordered {
            guard let start = minutes(slot.startTime), let end = minutes(slot.endTime), end - start >= 75 else { continue }
            let period = periodForSlot(slot)
            candidates.append(LearningSituationScheduledSlot(
                date: date, period: period, teacherScheduleSlotId: slot.id,
                startTime: slot.startTime, endTime: slot.endTime,
                occupiedPeriods: [period],
                occupiedScheduleSlots: [LearningSituationScheduledDestination(
                    period: period,
                    teacherScheduleSlotId: slot.id,
                    startTime: slot.startTime,
                    endTime: slot.endTime
                )]
            ))
        }
        // A legal transition/recess can separate two consecutive timetable periods.
        // Treat up to 20 minutes as one continuous long-block opportunity.
        let maximumTransitionMinutes = 20
        for pair in zip(ordered, ordered.dropFirst()) {
            guard let start = minutes(pair.0.startTime), let firstEnd = minutes(pair.0.endTime),
                  let secondStart = minutes(pair.1.startTime), let end = minutes(pair.1.endTime),
                  secondStart >= firstEnd,
                  secondStart - firstEnd <= maximumTransitionMinutes,
                  end - start >= 75 else { continue }
            let firstPeriod = periodForSlot(pair.0)
            let secondPeriod = periodForSlot(pair.1)
            candidates.append(LearningSituationScheduledSlot(
                date: date, period: firstPeriod, teacherScheduleSlotId: pair.0.id,
                startTime: pair.0.startTime, endTime: pair.1.endTime,
                occupiedPeriods: [firstPeriod, secondPeriod],
                occupiedScheduleSlots: [
                    LearningSituationScheduledDestination(
                        period: firstPeriod,
                        teacherScheduleSlotId: pair.0.id,
                        startTime: pair.0.startTime,
                        endTime: pair.0.endTime
                    ),
                    LearningSituationScheduledDestination(
                        period: secondPeriod,
                        teacherScheduleSlotId: pair.1.id,
                        startTime: pair.1.startTime,
                        endTime: pair.1.endTime
                    )
                ]
            ))
        }
        return candidates.sorted(by: isChronologicallyBefore)
    }

    private static func shortCandidates(
        on date: Date,
        slots: [TeacherScheduleSlot],
        periodForSlot: (TeacherScheduleSlot) -> Int
    ) -> [LearningSituationScheduledSlot] {
        return slots.sorted { $0.startTime < $1.startTime }.compactMap { slot in
            let period = periodForSlot(slot)
            return LearningSituationScheduledSlot(
                date: date, period: period, teacherScheduleSlotId: slot.id,
                startTime: slot.startTime, endTime: slot.endTime,
                occupiedPeriods: [period],
                occupiedScheduleSlots: [LearningSituationScheduledDestination(
                    period: period,
                    teacherScheduleSlotId: slot.id,
                    startTime: slot.startTime,
                    endTime: slot.endTime
                )]
            )
        }
    }

    private static func shortOnlyCandidates(
        on date: Date,
        slots: [TeacherScheduleSlot],
        periodForSlot: (TeacherScheduleSlot) -> Int
    ) -> [LearningSituationScheduledSlot] {
        shortCandidates(on: date, slots: slots, periodForSlot: periodForSlot).filter {
            guard let start = minutes($0.startTime), let end = minutes($0.endTime) else { return false }
            return end - start < 75
        }
    }

    /// Una frontera LONG_PART_1 es un único encuentro activo de unos 40 minutos. No debe
    /// consumir dos franjas como un LONG completo ni competir con una franja SHORT de 30′.
    private static func longPartCandidates(
        on date: Date,
        slots: [TeacherScheduleSlot],
        periodForSlot: (TeacherScheduleSlot) -> Int
    ) -> [LearningSituationScheduledSlot] {
        shortCandidates(on: date, slots: slots, periodForSlot: periodForSlot).filter {
            guard let start = minutes($0.startTime), let end = minutes($0.endTime) else { return false }
            let duration = end - start
            return duration >= 35 && duration < 75
        }
    }

    private static func requirementLabel(for role: LearningSituationWeeklyBlockRole) -> String {
        switch role {
        case .long: return "bloque largo"
        case .short: return "bloque corto"
        case .longPart1: return "franja parcial de 40 minutos"
        }
    }

    private static func collides(_ slot: LearningSituationScheduledSlot, with destinations: Set<ScheduledDestination>) -> Bool {
        let date = Calendar(identifier: .iso8601).startOfDay(for: slot.date)
        return slot.destinationPeriods.contains { destinations.contains(ScheduledDestination(date: date, period: $0)) }
    }

    private static func addDestinations(_ slot: LearningSituationScheduledSlot, to destinations: inout Set<ScheduledDestination>) {
        let date = Calendar(identifier: .iso8601).startOfDay(for: slot.date)
        slot.destinationPeriods.forEach { destinations.insert(ScheduledDestination(date: date, period: $0)) }
    }

    private static func withPlan(_ slot: LearningSituationScheduledSlot, plan: LearningSituationSessionPlanDraft) -> LearningSituationScheduledSlot {
        LearningSituationScheduledSlot(
            date: slot.date,
            period: slot.period,
            teacherScheduleSlotId: slot.teacherScheduleSlotId,
            startTime: slot.startTime,
            endTime: slot.endTime,
            planSessionNumber: plan.sessionNumber,
            blockKind: plan.sessionType,
            occupiedPeriods: slot.destinationPeriods,
            occupiedScheduleSlots: slot.destinationSlots
        )
    }

}

/// Petición de borrado: una sola confirmación para una situación o para un lote.
struct LearningSituationDeleteRequest: Identifiable {
    let ids: [Int64]
    let titles: [String]

    var id: String { ids.map(String.init).joined(separator: "-") }
    var isBatch: Bool { ids.count > 1 }

    var title: String {
        isBatch ? "¿Eliminar \(ids.count) situaciones?" : "¿Eliminar «\(titles.first ?? "esta situación")»?"
    }

    var message: String {
        guard isBatch else { return "Se borrarán sus datos relacionados. No se puede deshacer." }
        let shown = titles.prefix(3).joined(separator: ", ")
        let rest = titles.count > 3 ? " y \(titles.count - 3) más" : ""
        return "\(shown)\(rest). No se puede deshacer."
    }
}

struct LearningSituationsWorkspaceView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void

    @State var situations: [LearningSituation] = []
    @State var selectedSituationId: Int64?
    @State var searchText = ""
    @State var subjectFilter = ""
    @State var termFilter = ""
    @State var classFilter: Int64?
    @State var showsArchived = false
    @State var classIdsBySituation: [Int64: Set<Int64>] = [:]
    @State var isImporterPresented = false
    @State var importTargetId: Int64?
    @State var importDraft: LearningSituationImportDraft?
    @State var batchImport: LearningSituationBatchImportPresentation?
    @State var versions: [LearningSituationVersion] = []
    @State var classLinks: [LearningSituationClassLink] = []
    @State var loadedDetailSituationId: Int64?
    @State var resources: [LearningSituationLinkedResource] = []
    @State var scheduleSituation: LearningSituation?
    @State var evaluationSituation: LearningSituation?
    @State var duplicateSituation: LearningSituation?
    @State var errorMessage = ""
    @State var isSelectionMode = false
    @State var selectedSituationIds = Set<Int64>()
    @State var deleteRequest: LearningSituationDeleteRequest?
    // Estados de carga y errores en línea (no alertas) de la lista y del detalle.
    @State var isLoadingList = true
    @State var listErrorMessage: String?
    @State var isLoadingDetail = false
    @State var detailErrorMessage: String?
    // Disposición adaptativa: ancho medido del módulo y pila en ancho compacto.
    @State var containerWidth: CGFloat = 0
    @State var isCompactDetailVisible = false
    @State var expandedCurriculumSections: Set<String> = ["criterios"]
    @ScaledMetric(relativeTo: .body) var minimumTapSize: CGFloat = 44

    /// Por debajo de este ancho la lista y el detalle se apilan (iPhone, iPad en multitarea).
    static let compactLayoutThreshold: CGFloat = 640

    var usesCompactLayout: Bool {
        containerWidth > 0 && containerWidth < Self.compactLayoutThreshold
    }

    var listColumnWidth: CGFloat {
        min(360, max(280, containerWidth * 0.34))
    }

    var selectedSituation: LearningSituation? {
        situations.first(where: { $0.id == selectedSituationId })
    }

    var selectedDraft: LearningSituationImportDraft? {
        selectedSituation.flatMap {
            try? JSONDecoder().decode(LearningSituationImportDraft.self, from: Data($0.payloadJson.utf8))
        }
    }

    var availableSubjects: [String] {
        Array(Set(situations.map(\.subjectLabel).filter { !$0.isEmpty })).sorted()
    }

    var availableTerms: [String] {
        Array(Set(situations.map(\.termLabel).filter { !$0.isEmpty })).sorted()
    }

    var archivedCount: Int {
        situations.filter { $0.status == .archived }.count
    }

    var hasActiveFilters: Bool {
        !subjectFilter.isEmpty || !termFilter.isEmpty || classFilter != nil
    }

    var hasActiveQuery: Bool {
        hasActiveFilters || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var filteredSituations: [LearningSituation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return situations.filter { situation in
            let matchesText = query.isEmpty
                || situation.title.localizedCaseInsensitiveContains(query)
                || situation.subjectLabel.localizedCaseInsensitiveContains(query)
                || situation.termLabel.localizedCaseInsensitiveContains(query)
            let matchesSubject = subjectFilter.isEmpty || situation.subjectLabel == subjectFilter
            let matchesTerm = termFilter.isEmpty || situation.termLabel == termFilter
            let matchesClass = classFilter.map { classIdsBySituation[situation.id, default: []].contains($0) } ?? true
            let matchesArchive = showsArchived || situation.status != .archived
            return matchesText && matchesSubject && matchesTerm && matchesClass && matchesArchive
        }
    }

    var body: some View {
        Group {
            if usesCompactLayout {
                compactLayout
            } else {
                regularLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(appPageBackground(for: colorScheme))
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            guard abs(containerWidth - newWidth) > 1 else { return }
            containerWidth = newWidth
        }
        .task { await reload() }
        .appOnChange(of: selectedSituationId) { _ in
            Task { await reloadDetail() }
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.docx], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                handleDocumentSelection(urls)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $importDraft) { draft in
            LearningSituationImportPreviewSheet(draft: draft, classes: bridge.classes) { accepted in
                Task { await confirmImport(accepted) }
            }
        }
        .sheet(item: $batchImport) { batch in
            LearningSituationBatchImportPreviewSheet(
                drafts: batch.drafts,
                failures: batch.failures,
                classes: bridge.classes
            ) { accepted in
                Task {
                    await confirmImportBatch(accepted, initialFailures: batch.failures)
                }
            }
        }
        .sheet(item: $scheduleSituation) { situation in
            LearningSituationScheduleSheet(situation: situation, bridge: bridge, initialClassId: selectedClassId) {
                Task {
                    await reload()
                    scheduleSituation = nil
                }
            }
        }
        .sheet(item: $evaluationSituation) { situation in
            LearningSituationEvaluationSheet(situation: situation, bridge: bridge, initialClassId: selectedClassId) {
                Task {
                    await reload()
                    evaluationSituation = nil
                }
            }
        }
        .sheet(item: $duplicateSituation) { situation in
            LearningSituationDuplicateSheet(
                situation: situation,
                classes: bridge.classes,
                initialClassIds: duplicateInitialClassIds(for: situation)
            ) { classIds in
                Task { await duplicate(situation, classIds: classIds) }
            }
        }
        .alert("Situaciones", isPresented: Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })) {
            Button("Cerrar", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .confirmationDialog(
            deleteRequest?.title ?? "Eliminar",
            isPresented: Binding(get: { deleteRequest != nil }, set: { if !$0 { deleteRequest = nil } }),
            titleVisibility: .visible,
            presenting: deleteRequest
        ) { request in
            Button(request.isBatch ? "Eliminar \(request.ids.count)" : "Eliminar", role: .destructive) {
                Task { await performDelete(request) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { request in
            Text(request.message)
        }
    }

    // MARK: - Disposición adaptativa

    /// iPad y Mac: lista y detalle lado a lado. La vista ya vive dentro de la columna de
    /// detalle del `NavigationSplitView` del shell, así que no se anida otro split view.
    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            listColumn
                .frame(width: listColumnWidth)
                .frame(maxHeight: .infinity, alignment: .top)
            Divider()
            detailColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// iPhone o ventana estrecha: pila. La fila abre el detalle y «Situaciones» vuelve.
    @ViewBuilder
    private var compactLayout: some View {
        if isCompactDetailVisible, !isSelectionMode, let situation = selectedSituation {
            VStack(spacing: 0) {
                compactDetailBar(for: situation)
                Divider()
                detailColumn
            }
            .transition(.move(edge: .trailing))
        } else {
            listColumn
                .transition(.move(edge: .leading))
        }
    }

    private func compactDetailBar(for situation: LearningSituation) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.snappy) { isCompactDetailVisible = false }
            } label: {
                Label("Situaciones", systemImage: "chevron.backward")
                    .frame(minHeight: minimumTapSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Volver a Situaciones")
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .background(appCardBackground(for: colorScheme))
    }

    func openSituation(_ situation: LearningSituation) {
        selectedSituationId = situation.id
        if usesCompactLayout {
            withAnimation(.snappy) { isCompactDetailVisible = true }
        }
    }

    func duplicateInitialClassIds(for situation: LearningSituation) -> Set<Int64> {
        if let linked = classIdsBySituation[situation.id], !linked.isEmpty {
            return linked
        }
        return selectedClassId.map { [$0] } ?? []
    }

    func requestDelete(_ situations: [LearningSituation]) {
        guard !situations.isEmpty else { return }
        deleteRequest = LearningSituationDeleteRequest(ids: situations.map(\.id), titles: situations.map(\.title))
    }

    func clearSituationFilters() {
        searchText = ""
        showsArchived = false
        subjectFilter = ""
        termFilter = ""
        classFilter = nil
    }

    func draft(for situation: LearningSituation) -> LearningSituationImportDraft? {
        guard var decoded = try? JSONDecoder().decode(LearningSituationImportDraft.self, from: Data(situation.payloadJson.utf8)) else {
            errorMessage = "No se pudo abrir esta situación para editarla."
            return nil
        }
        decoded.title = situation.title
        decoded.courseLabel = situation.courseLabel
        decoded.subjectLabel = situation.subjectLabel
        decoded.termLabel = situation.termLabel
        decoded.sessionCount = Int(situation.sessionCount)
        if let liveClassIds = classIdsBySituation[situation.id], !liveClassIds.isEmpty {
            decoded.selectedClassIds = liveClassIds
        }
        return decoded
    }

    @MainActor
    func reload() async {
        defer { isLoadingList = false }
        do {
            situations = try await bridge.learningSituations()
            let links = try await bridge.learningSituationClassLinksAll()
            let updatedClassIds = Dictionary(grouping: links, by: \.learningSituationId)
                .mapValues { Set($0.map(\.classId)) }
            classIdsBySituation = updatedClassIds
            listErrorMessage = nil
            if selectedSituationId == nil { selectedSituationId = situations.first?.id }
            await reloadDetail()
        } catch {
            // Aviso en línea: se mantiene la lista que ya se ve.
            listErrorMessage = "No se pudo actualizar la lista. Se mantiene lo que ya ves."
        }
    }

    @MainActor
    func reloadDetail() async {
        guard let id = selectedSituationId else {
            versions = []; classLinks = []; resources = []
            detailErrorMessage = nil
            isLoadingDetail = false
            return
        }
        let sameSituation = loadedDetailSituationId == id
        // Solo se enseña el esqueleto al cambiar de situación; al recargar la misma se
        // mantiene lo que ya se ve.
        isLoadingDetail = !sameSituation
        defer { if selectedSituationId == id { isLoadingDetail = false } }
        let loadedVersions = try? await bridge.learningSituationVersions(id: id)
        let loadedLinks = try? await bridge.learningSituationClassLinks(id: id)
        let loadedResources = try? await bridge.learningSituationResources(id: id)
        guard selectedSituationId == id else { return }
        if loadedVersions == nil || loadedLinks == nil || loadedResources == nil {
            detailErrorMessage = SituationDetailReload.failure
        } else {
            detailErrorMessage = nil
        }
        versions = ProfileReloadKeep.list(loaded: loadedVersions, previous: versions, samePerson: sameSituation)
        classLinks = ProfileReloadKeep.list(loaded: loadedLinks, previous: classLinks, samePerson: sameSituation)
        resources = ProfileReloadKeep.list(loaded: loadedResources, previous: resources, samePerson: sameSituation)
        if loadedVersions != nil || loadedLinks != nil || loadedResources != nil {
            loadedDetailSituationId = id
        }
    }

    func handleDocumentSelection(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        if urls.count == 1 {
            do {
                importDraft = try LearningSituationDocumentImportService().preview(from: urls[0])
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        // Una selección múltiple siempre crea situaciones nuevas. La importación de una versión
        // sigue siendo intencionadamente unitaria para no aplicar varios documentos sobre el
        // mismo registro por accidente.
        importTargetId = nil
        let batch = LearningSituationDocumentImportService().preview(from: urls)
        guard !batch.drafts.isEmpty else {
            errorMessage = batchFailureMessage(batch.failures)
            return
        }
        batchImport = LearningSituationBatchImportPresentation(
            drafts: batch.drafts,
            failures: batch.failures
        )
    }

    func batchFailureMessage(_ failures: [LearningSituationDocumentImportFailure]) -> String {
        guard !failures.isEmpty else { return "No se ha podido leer ningún documento seleccionado." }
        let details = failures.map { "• \($0.fileName): \($0.message)" }.joined(separator: "\n")
        return "No se ha podido leer ningún documento seleccionado:\n\n\(details)"
    }

    @MainActor
    func confirmImport(_ draft: LearningSituationImportDraft) async {
        do {
            let savedId = try await bridge.confirmLearningSituationImport(draft: draft, existingSituationId: importTargetId)
            importDraft = nil
            importTargetId = nil
            selectedSituationId = savedId
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func confirmImportBatch(
        _ drafts: [LearningSituationImportDraft],
        initialFailures: [LearningSituationDocumentImportFailure]
    ) async {
        batchImport = nil
        importTargetId = nil

        var savedIds: [Int64] = []
        var failures = initialFailures
        for draft in drafts {
            do {
                let savedId = try await bridge.confirmLearningSituationImport(
                    draft: draft,
                    existingSituationId: nil
                )
                savedIds.append(savedId)
            } catch {
                failures.append(
                    LearningSituationDocumentImportFailure(
                        fileName: draft.sourceFileName,
                        message: error.localizedDescription
                    )
                )
            }
        }

        if let savedId = savedIds.last {
            selectedSituationId = savedId
        }
        await reload()

        guard !failures.isEmpty else { return }
        let importedSummary = savedIds.isEmpty
            ? "No se ha importado ninguna situación."
            : "Se han importado \(savedIds.count) situaciones."
        let details = failures.map { "• \($0.fileName): \($0.message)" }.joined(separator: "\n")
        errorMessage = "\(importedSummary)\n\nNo se pudieron gestionar estos documentos:\n\n\(details)"
    }

    @MainActor
    func duplicate(_ situation: LearningSituation, classIds: [Int64]) async {
        do {
            selectedSituationId = try await bridge.duplicateLearningSituation(situation, classIds: classIds)
            duplicateSituation = nil
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Borra una situación o un lote tras la confirmación única.
    @MainActor
    func performDelete(_ request: LearningSituationDeleteRequest) async {
        deleteRequest = nil
        do {
            for situationId in request.ids {
                try await bridge.deleteLearningSituation(id: situationId)
            }
            if let selectedId = selectedSituationId, request.ids.contains(selectedId) {
                selectedSituationId = nil
                isCompactDetailVisible = false
            }
            if request.isBatch || isSelectionMode {
                selectedSituationIds.subtract(request.ids)
                isSelectionMode = false
            }
            await reload()
        } catch {
            errorMessage = error.localizedDescription
            await reload()
        }
    }

    /// Archiva las situaciones elegidas en modo selección.
    @MainActor
    func performBatchArchive() async {
        let ids = selectedSituationIds
        do {
            for situationId in ids {
                try await bridge.updateLearningSituationStatus(id: situationId, status: .archived)
            }
            selectedSituationIds.removeAll()
            isSelectionMode = false
            await reload()
        } catch {
            errorMessage = error.localizedDescription
            await reload()
        }
    }

    @MainActor
    func updateStatus(_ situation: LearningSituation, to status: LearningSituationStatus) async {
        do {
            try await bridge.updateLearningSituationStatus(id: situation.id, status: status)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
