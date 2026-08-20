import XCTest
import MiGestorKit
@testable import MiGestorKMPMac

final class PlannerGanttProjectionTests: XCTestCase {
    func testSequenceStatusesRemainDistinctAndActionable() {
        XCTAssertEqual(PlannerSequenceStatus.unlocated.label, "Pendiente de ubicar")
        XCTAssertTrue(PlannerSequenceStatus.unlocated.requiresAttention)
        XCTAssertTrue(PlannerSequenceStatus.cancelled.requiresAttention)
        XCTAssertTrue(PlannerSequenceStatus.taught.isCompleted)
        XCTAssertTrue(PlannerSequenceStatus.closed.isCompleted)
        XCTAssertFalse(PlannerSequenceStatus.planned.isCompleted)
        XCTAssertNotEqual(PlannerSequenceStatus.taught, PlannerSequenceStatus.closed)
    }

    func testSequenceWithoutScheduledSessionsStillRequiresAttention() {
        let row = PlannerSequenceRow(
            id: "plan-42",
            sessionNumber: 1,
            title: "Sesión por ubicar",
            objective: "Objetivo",
            status: .unlocated,
            planningSession: nil,
            learningSituationSessionPlanId: 42
        )
        let group = PlannerSequenceGroup(
            id: "situation-1-group-7",
            title: "Situación",
            groupName: "1º A",
            groupId: 7,
            sequenceVersionId: 3,
            totalSessionsCount: 1,
            plannedCount: 0,
            pendingCount: 1,
            completedCount: 0,
            closedCount: 0,
            taughtCount: 0,
            cancelledCount: 0,
            rows: [row]
        )

        XCTAssertTrue(group.requiresAttention)
        XCTAssertEqual(group.pendingCount, 1)
        XCTAssertNil(group.rows.first?.planningSession)
        XCTAssertEqual(group.rows.first?.learningSituationSessionPlanId, 42)
    }

    func testCancelledSequenceIsCountedAsAttentionSeparately() {
        let group = PlannerSequenceGroup(
            id: "cancelled",
            title: "Situación",
            groupName: "2º B",
            groupId: 8,
            sequenceVersionId: 4,
            totalSessionsCount: 2,
            plannedCount: 1,
            pendingCount: 0,
            completedCount: 0,
            closedCount: 0,
            taughtCount: 0,
            cancelledCount: 1,
            rows: []
        )

        XCTAssertTrue(group.requiresAttention)
        XCTAssertEqual(group.cancelledCount, 1)
        XCTAssertEqual(group.taughtCount, 0)
        XCTAssertEqual(group.closedCount, 0)
    }

    func testDensityMetricsMatchMacSpecification() {
        XCTAssertEqual(PlannerGanttMetrics(density: .standard).labelWidth, 240)
        XCTAssertEqual(PlannerGanttMetrics(density: .standard).weekWidth, 64)
        XCTAssertEqual(PlannerGanttMetrics(density: .standard).rowHeight, 48)
        XCTAssertEqual(PlannerGanttMetrics(density: .compact).labelWidth, 216)
        XCTAssertEqual(PlannerGanttMetrics(density: .compact).weekWidth, 48)
        XCTAssertEqual(PlannerGanttMetrics(density: .compact).rowHeight, 40)
    }

    func testIsoPeriodProjectionCrossesYearBoundaryWithoutRepeatingWeeks() {
        let weeks = PlannerGanttWeek.range(fromIso: "2026-12-21", toIso: "2027-01-17")

        XCTAssertEqual(weeks?.count, 4)
        XCTAssertEqual(weeks?.first, PlannerGanttWeek(year: 2026, week: 52))
        XCTAssertEqual(weeks?.last, PlannerGanttWeek(year: 2027, week: 2))
        XCTAssertEqual(Set(weeks ?? []).count, weeks?.count)
    }

    func testFallbackWindowContainsThirteenWeeks() {
        let weeks = PlannerGanttWeek.range(around: Date(timeIntervalSince1970: 1_800_000_000), before: 6, after: 6)
        XCTAssertEqual(weeks.count, 13)
    }

    func testRollingWindowCanPageAcrossIsoYearBoundary() {
        let start = PlannerGanttWeek.range(fromIso: "2026-12-21", toIso: "2027-01-17")!.first!
        let window = PlannerGanttWeek.range(startingAt: start, count: 13)

        XCTAssertEqual(window.count, 13)
        XCTAssertEqual(window.first, start)
        XCTAssertEqual(window.dropFirst().first, start.addingWeeks(1))
        XCTAssertEqual(start.addingWeeks(13), window.last?.addingWeeks(1))
        XCTAssertEqual(start.addingWeeks(13)?.year, 2027)
        XCTAssertEqual(Set(window).count, window.count)
    }

    func testSchedulePreviewRemovesExactDuplicateTeacherSlots() {
        let descriptors = [
            LearningSituationScheduleTemplateDescriptor(dayOfWeek: 5, startTime: "13:15", endTime: "14:10"),
            LearningSituationScheduleTemplateDescriptor(dayOfWeek: 5, startTime: "14:30", endTime: "15:25"),
            LearningSituationScheduleTemplateDescriptor(dayOfWeek: 5, startTime: "14:30", endTime: "15:25"),
            LearningSituationScheduleTemplateDescriptor(dayOfWeek: 1, startTime: "12:20", endTime: "13:15")
        ]

        XCTAssertEqual(
            LearningSituationScheduleProjection.uniqueTemplateIndices(for: descriptors),
            [0, 1, 3]
        )
    }

    func testScheduleProjectionRejectsTwoSessionsForSameDestination() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let slots = [
            LearningSituationScheduledSlot(
                date: date,
                period: 6,
                teacherScheduleSlotId: 19,
                startTime: "14:30",
                endTime: "15:25"
            ),
            LearningSituationScheduledSlot(
                date: date,
                period: 6,
                teacherScheduleSlotId: 20,
                startTime: "14:30",
                endTime: "15:25"
            )
        ]

        XCTAssertTrue(LearningSituationScheduleProjection.hasDuplicateDestinations(slots))
    }

    func testScheduleProjectionMapsLongAndShortPlansToTheirOwnWeekdayPattern() {
        let calendar = Calendar(identifier: .iso8601)
        let monday = calendar.date(from: DateComponents(year: 2026, month: 3, day: 23))!
        let scheduleSlots = [
            TeacherScheduleSlot(id: 1, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 1, startTime: "09:00", endTime: "09:55", weeklyTemplateId: nil),
            TeacherScheduleSlot(id: 2, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 1, startTime: "10:10", endTime: "11:05", weeklyTemplateId: nil),
            TeacherScheduleSlot(id: 3, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 5, startTime: "12:00", endTime: "12:30", weeklyTemplateId: nil)
        ]
        let plans = [
            LearningSituationSessionPlanDraft(
                sessionNumber: 1,
                sourceLabel: "WEEK 1 · LONG BLOCK",
                title: "Long block",
                sessionType: "Long block",
                effectiveMinutes: 90,
                objective: "Objective",
                criteria: [],
                material: "",
                development: [],
                adaptations: []
            ),
            LearningSituationSessionPlanDraft(
                sessionNumber: 2,
                sourceLabel: "WEEK 1 · SHORT BLOCK",
                title: "Short block",
                sessionType: "Short block",
                effectiveMinutes: 30,
                objective: "Objective",
                criteria: [],
                material: "",
                development: [],
                adaptations: []
            )
        ]

        let projection = LearningSituationScheduleProjection.planAwareSlots(
            plans: plans,
            startDate: monday,
            template: scheduleSlots,
            periodForSlot: { slot in Int(slot.id) }
        )

        XCTAssertTrue(projection.warnings.isEmpty)
        XCTAssertEqual(projection.slots.map { $0.planSessionNumber }, [1, 2])
        XCTAssertEqual(projection.slots[0].occupiedPeriods, [1, 2])
        XCTAssertEqual(projection.slots[0].destinationSlots.map(\.teacherScheduleSlotId), [1, 2])
        XCTAssertEqual(projection.slots[0].destinationSlots.map(\.startTime), ["09:00", "10:10"])
        XCTAssertEqual(projection.slots[0].destinationSlots.map(\.endTime), ["09:55", "11:05"])
        XCTAssertEqual(projection.slots[0].startTime, "09:00")
        XCTAssertEqual(projection.slots[0].endTime, "11:05")
        XCTAssertEqual(projection.slots[1].occupiedPeriods, [3])
        XCTAssertFalse(LearningSituationScheduleProjection.hasDuplicateDestinations(projection.slots))
    }

    func testScheduleProjectionAcceptsTwentyMinuteLegalTransitionGap() {
        let calendar = Calendar(identifier: .iso8601)
        let monday = calendar.date(from: DateComponents(year: 2026, month: 3, day: 23))!
        let scheduleSlots = [
            TeacherScheduleSlot(id: 11, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 1, startTime: "09:00", endTime: "09:55", weeklyTemplateId: nil),
            TeacherScheduleSlot(id: 12, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 1, startTime: "10:15", endTime: "11:10", weeklyTemplateId: nil)
        ]
        let plans = [
            LearningSituationSessionPlanDraft(
                sessionNumber: 1,
                sourceLabel: "WEEK 1 · LONG BLOCK",
                title: "Long block",
                sessionType: "Long block",
                effectiveMinutes: 90,
                objective: "Objective",
                criteria: [],
                material: "",
                development: [],
                adaptations: []
            )
        ]

        let projection = LearningSituationScheduleProjection.planAwareSlots(
            plans: plans,
            startDate: monday,
            template: scheduleSlots,
            periodForSlot: { slot in Int(slot.id) }
        )

        XCTAssertTrue(projection.warnings.isEmpty)
        XCTAssertEqual(projection.slots.first?.occupiedPeriods, [11, 12])
        XCTAssertEqual(projection.slots.first?.endTime, "11:10")
    }

    func testIdenticalSequenceHashesShareOneGanttProjection() {
        let equivalent = PlannerSequenceVersionProjection.equivalentVersionIds(
            latestSha256: "same-document",
            versions: [
                (id: 1, sha256: "same-document"),
                (id: 2, sha256: "same-document"),
                (id: 3, sha256: "new-document")
            ]
        )

        XCTAssertEqual(equivalent, [1, 2])
        XCTAssertFalse(equivalent.contains(3))
    }
}
