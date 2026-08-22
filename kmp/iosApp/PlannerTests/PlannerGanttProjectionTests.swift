import XCTest
import MiGestorKit
@testable import MiGestorKMPMac

final class PlannerGanttProjectionTests: XCTestCase {
    func testCanonicalWeeklyCountsKeepOddTerminalAlternativeOutOfScheduledTotal() {
        let plans = [
            weeklyPlan(1, role: .long, cycleIndex: 1),
            weeklyPlan(2, role: .short, cycleIndex: 1),
            weeklyPlan(3, role: .long, cycleIndex: 2),
            weeklyPlan(4, role: .short, cycleIndex: 2)
        ]

        XCTAssertEqual(
            LearningSituationScheduleProjection.canonicalBlockCount(forAnnualSessionCount: 3),
            4
        )
        XCTAssertEqual(
            LearningSituationScheduleProjection.targetSessionCount(
                plans: plans,
                annualSessionCount: 3,
                sequenceKind: .canonicalWeekly
            ),
            3
        )
        XCTAssertEqual(
            LearningSituationScheduleProjection.canonicalBlockCount(forAnnualSessionCount: 10),
            10
        )
        XCTAssertTrue(
            LearningSituationScheduleProjection.hasExpectedCanonicalBlockCount(
                plans: plans,
                annualSessionCount: 3
            )
        )
        XCTAssertFalse(
            LearningSituationScheduleProjection.hasExpectedCanonicalBlockCount(
                plans: Array(plans.dropLast()),
                annualSessionCount: 3
            )
        )
        XCTAssertTrue(
            LearningSituationScheduleProjection.hasExpectedCanonicalBlockCount(
                plans: plans,
                annualSessionCount: 0
            )
        )
        XCTAssertEqual(
            LearningSituationScheduleProjection.targetSessionCount(
                plans: plans,
                annualSessionCount: 0,
                sequenceKind: .canonicalWeekly
            ),
            plans.count
        )
        XCTAssertEqual(LearningSituationScheduleProjection.sequenceKind(for: plans), .canonicalWeekly)
    }

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
        XCTAssertEqual(projection.route, .longFirst)
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
        XCTAssertEqual(projection.route, .longFirst)
        XCTAssertEqual(projection.slots.first?.occupiedPeriods, [11, 12])
        XCTAssertEqual(projection.slots.first?.endTime, "11:10")
    }

    func testWeeklyBlockProjectionCarriesSequenceAcrossPartialStartWeek() {
        let calendar = Calendar(identifier: .iso8601)
        let friday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25))!
        let scheduleSlots = [
            TeacherScheduleSlot(id: 3, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 3, startTime: "12:20", endTime: "13:15", weeklyTemplateId: nil),
            TeacherScheduleSlot(id: 6, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 5, startTime: "13:15", endTime: "14:10", weeklyTemplateId: nil),
            TeacherScheduleSlot(id: 7, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 5, startTime: "14:25", endTime: "15:20", weeklyTemplateId: nil)
        ]
        let plans = [
            LearningSituationSessionPlanDraft(
                sessionNumber: 1,
                sourceLabel: "WEEK 1 · LONG BLOCK",
                title: "Long block 1",
                sessionType: "Long block",
                effectiveMinutes: 90,
                objective: "Objective",
                criteria: [],
                material: "",
                development: [],
                activities: [],
                adaptations: []
            ),
            LearningSituationSessionPlanDraft(
                sessionNumber: 2,
                sourceLabel: "WEEK 1 · SHORT BLOCK",
                title: "Short block 1",
                sessionType: "Short block",
                effectiveMinutes: 30,
                objective: "Objective",
                criteria: [],
                material: "",
                development: [],
                activities: [],
                adaptations: []
            ),
            LearningSituationSessionPlanDraft(
                sessionNumber: 3,
                sourceLabel: "WEEK 2 · LONG BLOCK",
                title: "Long block 2",
                sessionType: "Long block",
                effectiveMinutes: 90,
                objective: "Objective",
                criteria: [],
                material: "",
                development: [],
                activities: [],
                adaptations: []
            ),
            LearningSituationSessionPlanDraft(
                sessionNumber: 4,
                sourceLabel: "WEEK 2 · SHORT BLOCK",
                title: "Short block 2",
                sessionType: "Short block",
                effectiveMinutes: 30,
                objective: "Objective",
                criteria: [],
                material: "",
                development: [],
                activities: [],
                adaptations: []
            )
        ]

        let projection = LearningSituationScheduleProjection.planAwareSlots(
            plans: plans,
            startDate: friday,
            template: scheduleSlots,
            periodForSlot: { Int($0.id) }
        )

        XCTAssertTrue(projection.warnings.isEmpty)
        XCTAssertEqual(projection.slots.map { $0.planSessionNumber }, [1, 2, 3, 4])
        XCTAssertEqual(projection.slots.map { calendar.component(.day, from: $0.date) }, [25, 30, 2, 7])
        XCTAssertEqual(projection.slots.map { $0.occupiedPeriods }, [[6, 7], [3], [6, 7], [3]])
        XCTAssertEqual(projection.slots.map { $0.startTime }, ["13:15", "12:20", "13:15", "12:20"])
    }

    func testWeeklyRouteChoosesShortFirstWhenShortOpportunityPrecedesLongFromFriday() {
        let calendar = Calendar(identifier: .iso8601)
        let friday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25))!
        let scheduleSlots = [
            TeacherScheduleSlot(id: 1, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 1, startTime: "09:00", endTime: "09:55", weeklyTemplateId: nil),
            TeacherScheduleSlot(id: 2, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 1, startTime: "10:15", endTime: "11:10", weeklyTemplateId: nil),
            TeacherScheduleSlot(id: 5, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 5, startTime: "13:15", endTime: "14:10", weeklyTemplateId: nil)
        ]

        let projection = LearningSituationScheduleProjection.planAwareSlots(
            plans: [weeklyPlan(1, role: .long), weeklyPlan(2, role: .short)],
            startDate: friday,
            template: scheduleSlots,
            periodForSlot: { Int($0.id) }
        )

        XCTAssertTrue(projection.warnings.isEmpty)
        XCTAssertEqual(projection.route, .shortFirst)
        XCTAssertEqual(projection.slots.map { $0.planSessionNumber }, [2, 1])
        XCTAssertEqual(projection.slots.map { calendar.component(.day, from: $0.date) }, [25, 28])
        XCTAssertEqual(projection.slots.map(\.occupiedPeriods), [[5], [1, 2]])
    }

    func testWeeklyRouteChoosesLongFirstWhenLongOpportunityPrecedesShortFromFriday() {
        let calendar = Calendar(identifier: .iso8601)
        let friday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25))!
        let scheduleSlots = [
            TeacherScheduleSlot(id: 3, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 3, startTime: "12:20", endTime: "13:15", weeklyTemplateId: nil),
            TeacherScheduleSlot(id: 6, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 5, startTime: "13:15", endTime: "14:10", weeklyTemplateId: nil),
            TeacherScheduleSlot(id: 7, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 5, startTime: "14:25", endTime: "15:20", weeklyTemplateId: nil)
        ]

        let projection = LearningSituationScheduleProjection.planAwareSlots(
            plans: [weeklyPlan(1, role: .long), weeklyPlan(2, role: .short)],
            startDate: friday,
            template: scheduleSlots,
            periodForSlot: { Int($0.id) }
        )

        XCTAssertTrue(projection.warnings.isEmpty)
        XCTAssertEqual(projection.route, .longFirst)
        XCTAssertEqual(projection.slots.map { $0.planSessionNumber }, [1, 2])
        XCTAssertEqual(projection.slots.map { calendar.component(.day, from: $0.date) }, [25, 30])
        XCTAssertEqual(projection.slots.map(\.occupiedPeriods), [[6, 7], [3]])
    }

    func testThreeSessionsFollowShortFirstRouteAndStopAtNextChronologicalRole() {
        let calendar = Calendar(identifier: .iso8601)
        let friday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25))!
        let scheduleSlots = [
            TeacherScheduleSlot(id: 1, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 1, startTime: "09:00", endTime: "09:55", weeklyTemplateId: nil),
            TeacherScheduleSlot(id: 2, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 1, startTime: "10:15", endTime: "11:10", weeklyTemplateId: nil),
            TeacherScheduleSlot(id: 5, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 5, startTime: "13:15", endTime: "14:10", weeklyTemplateId: nil)
        ]

        let projection = LearningSituationScheduleProjection.planAwareSlots(
            plans: [
                weeklyPlan(1, role: .long, cycleIndex: 1),
                weeklyPlan(2, role: .short, cycleIndex: 1),
                weeklyPlan(3, role: .long, cycleIndex: 2),
                weeklyPlan(4, role: .short, cycleIndex: 2)
            ],
            startDate: friday,
            template: scheduleSlots,
            periodForSlot: { Int($0.id) },
            targetSessionCount: 3
        )

        XCTAssertTrue(projection.warnings.isEmpty)
        XCTAssertEqual(projection.route, .shortFirst)
        XCTAssertEqual(projection.slots.map { $0.planSessionNumber }, [2, 1, 4])
        XCTAssertEqual(projection.slots.map { calendar.component(.day, from: $0.date) }, [25, 28, 2])
        XCTAssertEqual(projection.slots.map { $0.blockKind }, ["Short block", "Long block", "Short block"])
    }

    func testThreeSessionsFollowLongFirstRouteAndStopAtNextChronologicalRole() {
        let calendar = Calendar(identifier: .iso8601)
        let friday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25))!
        let scheduleSlots = [
            TeacherScheduleSlot(id: 3, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 3, startTime: "12:20", endTime: "13:15", weeklyTemplateId: nil),
            TeacherScheduleSlot(id: 6, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 5, startTime: "13:15", endTime: "14:10", weeklyTemplateId: nil),
            TeacherScheduleSlot(id: 7, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 5, startTime: "14:25", endTime: "15:20", weeklyTemplateId: nil)
        ]

        let projection = LearningSituationScheduleProjection.planAwareSlots(
            plans: [
                weeklyPlan(1, role: .long, cycleIndex: 1),
                weeklyPlan(2, role: .short, cycleIndex: 1),
                weeklyPlan(3, role: .long, cycleIndex: 2),
                weeklyPlan(4, role: .short, cycleIndex: 2)
            ],
            startDate: friday,
            template: scheduleSlots,
            periodForSlot: { Int($0.id) },
            targetSessionCount: 3
        )

        XCTAssertTrue(projection.warnings.isEmpty)
        XCTAssertEqual(projection.route, .longFirst)
        XCTAssertEqual(projection.slots.map { $0.planSessionNumber }, [1, 2, 3])
        XCTAssertEqual(projection.slots.map { calendar.component(.day, from: $0.date) }, [25, 30, 2])
        XCTAssertEqual(projection.slots.map { $0.blockKind }, ["Long block", "Short block", "Long block"])
    }

    func testWeeklyProjectionAcceptsFifteenAndTwentyMinuteGapsButRejectsTwentyOne() {
        let calendar = Calendar(identifier: .iso8601)
        let monday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28))!

        for (gap, expectedPeriods) in [(15, [1, 2]), (20, [1, 2]), (21, [])] {
            let secondStart = 9 * 60 + 55 + gap
            let secondHour = secondStart / 60
            let secondMinute = secondStart % 60
            let secondEnd = secondStart + 55
            let scheduleSlots = [
                TeacherScheduleSlot(id: 1, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 1, startTime: "09:00", endTime: "09:55", weeklyTemplateId: nil),
                TeacherScheduleSlot(id: 2, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 1, startTime: String(format: "%02d:%02d", secondHour, secondMinute), endTime: String(format: "%02d:%02d", secondEnd / 60, secondEnd % 60), weeklyTemplateId: nil)
            ]
            let projection = LearningSituationScheduleProjection.planAwareSlots(
                plans: [weeklyPlan(1, role: .long)],
                startDate: monday,
                template: scheduleSlots,
                periodForSlot: { Int($0.id) }
            )

            XCTAssertEqual(projection.slots.first?.occupiedPeriods ?? [], expectedPeriods, "gap \(gap)")
            if gap < 21 {
                XCTAssertTrue(projection.warnings.isEmpty, "gap \(gap)")
            } else {
                XCTAssertFalse(projection.warnings.isEmpty, "gap \(gap)")
            }
        }
    }

    func testWeeklyProjectionSkipsExplicitHolidayAndKeepsPartialWeekChronology() {
        let calendar = Calendar(identifier: .iso8601)
        let mondayHoliday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28))!
        let scheduleSlots = [
            TeacherScheduleSlot(id: 1, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 1, startTime: "09:00", endTime: "09:55", weeklyTemplateId: nil),
            TeacherScheduleSlot(id: 2, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 2, startTime: "12:00", endTime: "12:55", weeklyTemplateId: nil),
            TeacherScheduleSlot(id: 3, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 3, startTime: "09:00", endTime: "09:55", weeklyTemplateId: nil),
            TeacherScheduleSlot(id: 4, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 3, startTime: "10:15", endTime: "11:10", weeklyTemplateId: nil)
        ]

        let projection = LearningSituationScheduleProjection.planAwareSlots(
            plans: [weeklyPlan(1, role: .long), weeklyPlan(2, role: .short)],
            startDate: mondayHoliday,
            template: scheduleSlots,
            periodForSlot: { Int($0.id) },
            excludedDates: [mondayHoliday]
        )

        XCTAssertTrue(projection.warnings.isEmpty)
        XCTAssertEqual(projection.route, .shortFirst)
        XCTAssertEqual(projection.slots.map { $0.planSessionNumber }, [2, 1])
        XCTAssertEqual(projection.slots.map { calendar.component(.day, from: $0.date) }, [29, 30])
        XCTAssertEqual(projection.slots.map(\.occupiedPeriods), [[2], [3, 4]])
    }

    func testLongProjectionTriesLaterOverlappingWindowAfterShortUsesFirstPeriod() {
        let calendar = Calendar(identifier: .iso8601)
        let friday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25))!
        let scheduleSlots = [
            TeacherScheduleSlot(id: 1, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 5, startTime: "13:00", endTime: "13:55", weeklyTemplateId: nil),
            TeacherScheduleSlot(id: 2, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 5, startTime: "14:10", endTime: "15:05", weeklyTemplateId: nil),
            TeacherScheduleSlot(id: 3, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 5, startTime: "15:20", endTime: "16:15", weeklyTemplateId: nil)
        ]
        let plans = [
            weeklyPlan(2, role: .short, cycleIndex: 1),
            weeklyPlan(3, role: .long, cycleIndex: 2)
        ]

        let projection = LearningSituationScheduleProjection.planAwareSlots(
            plans: plans,
            startDate: friday,
            template: scheduleSlots,
            periodForSlot: { Int($0.id) }
        )

        XCTAssertTrue(projection.warnings.isEmpty)
        XCTAssertEqual(projection.route, .shortFirst)
        XCTAssertEqual(projection.slots.map(\.planSessionNumber), [2, 3])
        XCTAssertEqual(projection.slots.map(\.occupiedPeriods), [[1], [2, 3]])
    }

    func testLegacyWeeklyPlansInferOddEvenPairsWithoutMetadata() {
        let calendar = Calendar(identifier: .iso8601)
        let friday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25))!
        let scheduleSlots = [
            TeacherScheduleSlot(id: 1, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 1, startTime: "09:00", endTime: "09:55", weeklyTemplateId: nil),
            TeacherScheduleSlot(id: 2, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 1, startTime: "10:15", endTime: "11:10", weeklyTemplateId: nil),
            TeacherScheduleSlot(id: 5, teacherScheduleId: 10, schoolClassId: 20, subjectLabel: "PE", unitLabel: nil, dayOfWeek: 5, startTime: "13:15", endTime: "14:10", weeklyTemplateId: nil)
        ]
        let plans = [
            legacyWeeklyPlan(1, type: "Doble", minutes: 90),
            legacyWeeklyPlan(2, type: "Simple", minutes: 30)
        ]

        let projection = LearningSituationScheduleProjection.planAwareSlots(
            plans: plans,
            startDate: friday,
            template: scheduleSlots,
            periodForSlot: { Int($0.id) }
        )

        XCTAssertTrue(projection.warnings.isEmpty)
        XCTAssertEqual(projection.route, .shortFirst)
        XCTAssertEqual(projection.slots.map { $0.planSessionNumber }, [2, 1])
        XCTAssertNil(plans[0].blockRole)
        XCTAssertNil(plans[0].cycleIndex)
        XCTAssertEqual(LearningSituationScheduleProjection.sequenceKind(for: plans), .legacyWeekly)
        XCTAssertEqual(
            LearningSituationScheduleProjection.targetSessionCount(
                plans: plans + [legacyWeeklyPlan(3, type: "Doble", minutes: 90), legacyWeeklyPlan(4, type: "Simple", minutes: 30)],
                annualSessionCount: 3,
                sequenceKind: .legacyWeekly
            ),
            4
        )
    }

    private func weeklyPlan(
        _ sessionNumber: Int,
        role: LearningSituationWeeklyBlockRole,
        cycleIndex: Int? = nil
    ) -> LearningSituationSessionPlanDraft {
        let cycle = cycleIndex ?? max((sessionNumber + 1) / 2, 1)
        let isLong = role == .long
        return LearningSituationSessionPlanDraft(
            sessionNumber: sessionNumber,
            sourceLabel: "WEEK \(cycle) · \(isLong ? "LONG BLOCK" : "SHORT BLOCK")",
            title: isLong ? "Long block \(cycle)" : "Short block \(cycle)",
            sessionType: isLong ? "Long block" : "Short block",
            effectiveMinutes: isLong ? 90 : 30,
            objective: "Objective",
            criteria: [],
            material: "",
            development: [],
            adaptations: [],
            cycleIndex: cycleIndex,
            weekKey: cycleIndex.map { "week-\($0)" },
            blockRole: cycleIndex == nil ? nil : role,
            sequenceFormat: cycleIndex == nil ? nil : "weekly-long-short-v1"
        )
    }

    private func legacyWeeklyPlan(_ sessionNumber: Int, type: String, minutes: Int) -> LearningSituationSessionPlanDraft {
        LearningSituationSessionPlanDraft(
            sessionNumber: sessionNumber,
            sourceLabel: "WEEK 1",
            title: "Legacy \(sessionNumber)",
            sessionType: type,
            effectiveMinutes: minutes,
            objective: "Objective",
            criteria: [],
            material: "",
            development: [],
            adaptations: []
        )
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
