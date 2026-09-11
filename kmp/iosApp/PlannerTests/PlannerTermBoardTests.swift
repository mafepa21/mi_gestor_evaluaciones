import XCTest
@testable import MiGestorKMPMac
import MiGestorKit

@MainActor
final class PlannerTermBoardTests: XCTestCase {
    func testPlannerWorkspaceSectionIncludesTerm() {
        XCTAssertTrue(PlannerWorkspaceSection.allCases.contains(.term))
        XCTAssertEqual(PlannerWorkspaceSection.term.rawValue, "Evaluación")
        XCTAssertEqual(PlannerWorkspaceSection.term.systemImage, "calendar.badge.checkmark")
    }

    func testTermBoardProjection_GeneratesOnlyClassSlots() {
        let classId: Int64 = 101

        // Martes (2) de 09:00 a 10:00 y Jueves (4) de 11:30 a 12:30
        let scheduleSlots = [
            TeacherScheduleSlot(
                id: 1,
                teacherScheduleId: 1,
                schoolClassId: classId,
                subjectLabel: "Educación Física",
                unitLabel: "1º ESO B",
                dayOfWeek: 2,
                startTime: "09:00",
                endTime: "10:00",
                weeklyTemplateId: nil
            ),
            TeacherScheduleSlot(
                id: 2,
                teacherScheduleId: 1,
                schoolClassId: classId,
                subjectLabel: "Educación Física",
                unitLabel: "1º ESO B",
                dayOfWeek: 4,
                startTime: "11:30",
                endTime: "12:30",
                weeklyTemplateId: nil
            )
        ]

        // Periodo de 2 semanas: del lunes 14 de septiembre al domingo 27 de septiembre de 2026
        let (slots, metrics) = TermBoardProjectionEngine.project(
            periodName: "1ª Evaluación",
            startDateIso: "2026-09-14",
            endDateIso: "2026-09-27",
            classId: classId,
            scheduleSlots: scheduleSlots,
            nonTeachingEvents: [],
            existingSessions: []
        )

        // En 2 semanas hay 2 martes y 2 jueves = 4 clases
        XCTAssertEqual(slots.count, 4)
        XCTAssertEqual(metrics.totalLectivas, 4)
        XCTAssertEqual(metrics.totalFestivos, 0)
        XCTAssertEqual(metrics.totalOcupadas, 0)
        XCTAssertEqual(metrics.totalLibres, 4)

        for (index, slot) in slots.enumerated() {
            XCTAssertEqual(slot.lessonIndex, index + 1)
            XCTAssertEqual(slot.kind, TermSlotKind.free)
        }
    }

    func testTermBoardProjection_SkipsHolidaysAndDoesNotConsumeLessonIndex() {
        let classId: Int64 = 101

        let scheduleSlots = [
            TeacherScheduleSlot(
                id: 1,
                teacherScheduleId: 1,
                schoolClassId: classId,
                subjectLabel: "Educación Física",
                unitLabel: "1º ESO B",
                dayOfWeek: 2,
                startTime: "09:00",
                endTime: "10:00",
                weeklyTemplateId: nil
            ),
            TeacherScheduleSlot(
                id: 2,
                teacherScheduleId: 1,
                schoolClassId: classId,
                subjectLabel: "Educación Física",
                unitLabel: "1º ESO B",
                dayOfWeek: 4,
                startTime: "11:30",
                endTime: "12:30",
                weeklyTemplateId: nil
            )
        ]

        // Jueves 17 de septiembre es festivo local
        let calendar = Calendar(identifier: .iso8601)
        var comp = DateComponents()
        comp.year = 2026; comp.month = 9; comp.day = 17
        let holidayDate = calendar.date(from: comp)!
        let holidayEpochMs = Int64(holidayDate.timeIntervalSince1970 * 1000)

        let holidayEvent = CalendarEvent(
            id: 99,
            classId: nil,
            title: "Fiesta Patronal",
            description: "No lectivo",
            startAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: holidayEpochMs),
            endAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: holidayEpochMs),
            externalProvider: nil,
            externalId: nil,
            trace: AuditTrace(
                authorUserId: nil,
                createdAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: 0),
                updatedAt: Instant.companion.fromEpochMilliseconds(epochMilliseconds: 0),
                associatedGroupId: nil,
                deviceId: nil,
                syncVersion: 0
            )
        )

        let (slots, metrics) = TermBoardProjectionEngine.project(
            periodName: "1ª Evaluación",
            startDateIso: "2026-09-14",
            endDateIso: "2026-09-27",
            classId: classId,
            scheduleSlots: scheduleSlots,
            nonTeachingEvents: [holidayEvent],
            existingSessions: []
        )

        XCTAssertEqual(slots.count, 4)
        XCTAssertEqual(metrics.totalLectivas, 3) // 4 días de horario - 1 festivo = 3 lectivas
        XCTAssertEqual(metrics.totalFestivos, 1)
        XCTAssertEqual(metrics.totalLibres, 3)

        // Slot 0: Martes 15 sep -> Clase 1
        XCTAssertEqual(slots[0].lessonIndex, 1)
        XCTAssertEqual(slots[0].kind, TermSlotKind.free)

        // Slot 1: Jueves 17 sep -> Festivo (no consume índice lectivo)
        XCTAssertNil(slots[1].lessonIndex)
        XCTAssertEqual(slots[1].kind, TermSlotKind.holiday(name: "Fiesta Patronal"))

        // Slot 2: Martes 22 sep -> Clase 2
        XCTAssertEqual(slots[2].lessonIndex, 2)
        XCTAssertEqual(slots[2].kind, TermSlotKind.free)

        // Slot 3: Jueves 24 sep -> Clase 3
        XCTAssertEqual(slots[3].lessonIndex, 3)
        XCTAssertEqual(slots[3].kind, TermSlotKind.free)
    }

    func testTermBoardProjection_RecognizesExistingSessions() {
        let classId: Int64 = 101

        let scheduleSlots = [
            TeacherScheduleSlot(
                id: 1,
                teacherScheduleId: 1,
                schoolClassId: classId,
                subjectLabel: "EF",
                unitLabel: "1B",
                dayOfWeek: 2,
                startTime: "09:00",
                endTime: "10:00",
                weeklyTemplateId: nil
            )
        ]

        // 2026-09-15 es martes de la semana ISO 38 de 2026
        let session = PlanningSession(
            id: 501,
            teachingUnitId: 10,
            teachingUnitName: "SA 1: Atletismo",
            teachingUnitColor: "#4A90D9",
            groupId: classId,
            groupName: "1º ESO B",
            dayOfWeek: 2,
            period: 1,
            weekNumber: 38,
            year: 2026,
            objectives: "Presentación y activación",
            activities: "Juegos de velocidad",
            evaluation: "",
            linkedAssessmentIdsCsv: "",
            teacherScheduleSlotId: 1,
            startTime: "09:00",
            endTime: "10:00",
            learningSituationSessionPlanId: nil,
            status: .planned
        )

        let (slots, metrics) = TermBoardProjectionEngine.project(
            periodName: "1ª Evaluación",
            startDateIso: "2026-09-14",
            endDateIso: "2026-09-27",
            classId: classId,
            scheduleSlots: scheduleSlots,
            nonTeachingEvents: [],
            existingSessions: [session]
        )

        XCTAssertEqual(slots.count, 2)
        XCTAssertEqual(metrics.totalLectivas, 2)
        XCTAssertEqual(metrics.totalOcupadas, 1)
        XCTAssertEqual(metrics.totalLibres, 1)

        XCTAssertEqual(slots[0].kind, TermSlotKind.occupied(session: session))
        XCTAssertEqual(slots[1].kind, TermSlotKind.free)
    }

    func testTermBoardProjection_SimulationReplacesFreeSlots() {
        let classId: Int64 = 101

        let scheduleSlots = [
            TeacherScheduleSlot(
                id: 1,
                teacherScheduleId: 1,
                schoolClassId: classId,
                subjectLabel: "EF",
                unitLabel: "1B",
                dayOfWeek: 2,
                startTime: "09:00",
                endTime: "10:00",
                weeklyTemplateId: nil
            )
        ]

        // 3 semanas = 3 clases
        let simPlans = [
            TermSimulationPlanItem(planId: 1, sessionNumber: 1, title: "Inicio SA 2", objective: "Reto"),
            TermSimulationPlanItem(planId: 2, sessionNumber: 2, title: "Desarrollo SA 2", objective: "Práctica")
        ]

        let (slots, metrics) = TermBoardProjectionEngine.project(
            periodName: "1ª Evaluación",
            startDateIso: "2026-09-14",
            endDateIso: "2026-10-04",
            classId: classId,
            scheduleSlots: scheduleSlots,
            nonTeachingEvents: [],
            existingSessions: [],
            simulationPlans: simPlans,
            simulationSituationTitle: "SA 2: Acrosport"
        )

        XCTAssertEqual(slots.count, 3)
        XCTAssertEqual(metrics.totalLectivas, 3)
        XCTAssertTrue(metrics.simulationActive)
        XCTAssertEqual(metrics.simulationSessionCount, 2)
        XCTAssertEqual(metrics.simulationRemainingFreeCount, 1) // 3 lectivas - 2 de SA = 1 libre restante
        XCTAssertEqual(metrics.simulationOverflowCount, 0)

        // Las dos primeras clases deben ser preview
        if case .preview(let num, let title, _, _, _) = slots[0].kind {
            XCTAssertEqual(num, 1)
            XCTAssertEqual(title, "Inicio SA 2")
        } else {
            XCTFail("Se esperaba .preview en el slot 0")
        }

        if case .preview(let num, let title, _, _, _) = slots[1].kind {
            XCTAssertEqual(num, 2)
            XCTAssertEqual(title, "Desarrollo SA 2")
        } else {
            XCTFail("Se esperaba .preview en el slot 1")
        }

        // La tercera clase queda libre
        XCTAssertEqual(slots[2].kind, TermSlotKind.free)
    }

    func testTermBoardProjection_DetectsDeadlineOverflow() {
        let classId: Int64 = 101

        let scheduleSlots = [
            TeacherScheduleSlot(
                id: 1,
                teacherScheduleId: 1,
                schoolClassId: classId,
                subjectLabel: "EF",
                unitLabel: "1B",
                dayOfWeek: 2,
                startTime: "09:00",
                endTime: "10:00",
                weeklyTemplateId: nil
            )
        ]

        // 3 semanas (mar 15 sep, mar 22 sep, mar 29 sep)
        // Pero la fecha límite de evaluación (junta de notas) es el 20 de septiembre
        let simPlans = [
            TermSimulationPlanItem(planId: 1, sessionNumber: 1, title: "S1"),
            TermSimulationPlanItem(planId: 2, sessionNumber: 2, title: "S2"),
            TermSimulationPlanItem(planId: 3, sessionNumber: 3, title: "S3")
        ]

        let (slots, metrics) = TermBoardProjectionEngine.project(
            periodName: "1ª Evaluación",
            startDateIso: "2026-09-14",
            endDateIso: "2026-10-04",
            deadlineDateIso: "2026-09-20", // Límite: antes del 22 sep
            classId: classId,
            scheduleSlots: scheduleSlots,
            nonTeachingEvents: [],
            existingSessions: [],
            simulationPlans: simPlans
        )

        XCTAssertEqual(slots.count, 3)
        // La clase del 15 sep está antes de la fecha límite (false)
        XCTAssertFalse(slots[0].isAfterEvaluationDeadline)
        // Las clases del 22 y 29 sep caen DESPUÉS de la fecha límite (true)
        XCTAssertTrue(slots[1].isAfterEvaluationDeadline)
        XCTAssertTrue(slots[2].isAfterEvaluationDeadline)

        // 2 sesiones caen fuera de plazo
        XCTAssertEqual(metrics.simulationOverflowCount, 2)
    }
}
