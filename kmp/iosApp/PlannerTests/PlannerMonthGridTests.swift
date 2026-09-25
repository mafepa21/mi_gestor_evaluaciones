import XCTest
@testable import MiGestorKMPMac
import MiGestorKit

@MainActor
final class PlannerMonthGridTests: XCTestCase {
    func testPlannerWorkspaceSectionIncludesMonth() {
        XCTAssertTrue(PlannerWorkspaceSection.allCases.contains(.month))
        XCTAssertEqual(PlannerWorkspaceSection.month.rawValue, "Mes")
        XCTAssertEqual(PlannerWorkspaceSection.month.systemImage, "calendar")
    }

    func testMonthGridBuildsCorrectStructureForSeptember2026() {
        let vm = PlannerWorkspaceViewModel()

        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 15
        components.hour = 12
        let calendar = Calendar(identifier: .iso8601)
        let testDate = calendar.date(from: components)!

        vm.monthViewDate = testDate
        let grid = vm.buildMonthGrid()

        XCTAssertEqual(grid.year, 2026)
        XCTAssertEqual(grid.month, 9)
        XCTAssertTrue(grid.monthName.contains("2026"))

        // Septiembre 2026 tiene 30 días, empieza en martes (1 día de relleno previo) y termina en miércoles (4 de relleno posterior) -> 35 celdas = 5 semanas de 7 días
        XCTAssertEqual(grid.weeks.count, 5)
        for week in grid.weeks {
            XCTAssertEqual(week.count, 7)
        }

        let allDays = grid.weeks.flatMap { $0 }
        XCTAssertEqual(allDays.count, 35)

        // El primer día debe ser el 31 de agosto (no del mes actual)
        XCTAssertFalse(allDays.first!.isCurrentMonth)
        XCTAssertEqual(allDays.first!.dayNumber, 31)
        XCTAssertEqual(allDays.first!.dayOfWeek, 1) // Lunes

        // El segundo día debe ser el 1 de septiembre
        XCTAssertTrue(allDays[1].isCurrentMonth)
        XCTAssertEqual(allDays[1].dayNumber, 1)
        XCTAssertEqual(allDays[1].dayOfWeek, 2) // Martes

        // El día 30 de septiembre está en el índice 30
        XCTAssertTrue(allDays[30].isCurrentMonth)
        XCTAssertEqual(allDays[30].dayNumber, 30)

        // El día 1 de octubre está en el índice 31 y no es del mes actual
        XCTAssertFalse(allDays[31].isCurrentMonth)
        XCTAssertEqual(allDays[31].dayNumber, 1)
    }

    func testMonthGridFiltersSessionsByGroup() {
        let vm = PlannerWorkspaceViewModel()

        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 15
        components.hour = 12
        let calendar = Calendar(identifier: .iso8601)
        let testDate = calendar.date(from: components)!
        vm.monthViewDate = testDate

        let isoWeek = calendar.component(.weekOfYear, from: testDate)
        let isoYear = calendar.component(.yearForWeekOfYear, from: testDate)
        let dayOfWeek = ((calendar.component(.weekday, from: testDate) + 5) % 7) + 1

        let session1 = PlanningSession(
            id: 101,
            teachingUnitId: 1,
            teachingUnitName: "Condición Física",
            teachingUnitColor: "#4A90D9",
            groupId: 1,
            groupName: "1º ESO A",
            dayOfWeek: Int32(dayOfWeek),
            period: 1,
            weekNumber: Int32(isoWeek),
            year: Int32(isoYear),
            objectives: "Test de resistencia",
            activities: "Course Navette",
            evaluation: "",
            linkedAssessmentIdsCsv: "",
            teacherScheduleSlotId: nil,
            startTime: "08:05",
            endTime: "09:00",
            learningSituationSessionPlanId: nil,
            status: .planned
        )

        let session2 = PlanningSession(
            id: 102,
            teachingUnitId: 2,
            teachingUnitName: "Baloncesto",
            teachingUnitColor: "#F5A623",
            groupId: 2,
            groupName: "2º Bach B",
            dayOfWeek: Int32(dayOfWeek),
            period: 2,
            weekNumber: Int32(isoWeek),
            year: Int32(isoYear),
            objectives: "Tiro en suspensión",
            activities: "Rueda de tiro",
            evaluation: "",
            linkedAssessmentIdsCsv: "",
            teacherScheduleSlotId: nil,
            startTime: "09:00",
            endTime: "09:55",
            learningSituationSessionPlanId: nil,
            status: .planned
        )

        vm.monthSessions = [session1, session2]

        // Sin filtro de grupo: 2 sesiones en total
        vm.selectedGroupId = nil
        let gridAll = vm.buildMonthGrid()
        XCTAssertEqual(gridAll.totalSessionsCount, 2)

        // Con filtro para grupo 1 (1º ESO A): 1 sesión
        vm.selectedGroupId = 1
        let gridGroup1 = vm.buildMonthGrid()
        XCTAssertEqual(gridGroup1.totalSessionsCount, 1)

        // Con filtro para grupo 999 (inexistente): 0 sesiones
        vm.selectedGroupId = 999
        let gridGroupNone = vm.buildMonthGrid()
        XCTAssertEqual(gridGroupNone.totalSessionsCount, 0)
    }
}
