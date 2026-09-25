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

    func testCalendarLoadFailureDoesNotInventHolidays() {
        XCTAssertEqual(
            PlannerCalendarLoad.holidayReadFailure,
            "No se pudo leer el calendario. El festivo no ha cambiado."
        )
        XCTAssertEqual(
            PlannerCalendarLoad.monthFailure,
            "No se pudo cargar el calendario. Se mantienen los días que ya ves."
        )
    }

    func testCalendarRangeOverlapKeepsVisibleWindowOnly() {
        // Ventana visible: día 10 (ms relativos arbitarios).
        let rangeStart: Int64 = 1_000
        let rangeEnd: Int64 = 2_000

        XCTAssertTrue(
            PlannerCalendarRange.overlaps(
                eventStartMs: 500,
                eventEndMs: 1_500,
                rangeStartMs: rangeStart,
                rangeEndMs: rangeEnd
            ),
            "Un evento que empieza antes y cruza el inicio debe verse"
        )
        XCTAssertTrue(
            PlannerCalendarRange.overlaps(
                eventStartMs: 1_500,
                eventEndMs: 2_500,
                rangeStartMs: rangeStart,
                rangeEndMs: rangeEnd
            ),
            "Un evento que cruza el final debe verse"
        )
        XCTAssertTrue(
            PlannerCalendarRange.overlaps(
                eventStartMs: 1_200,
                eventEndMs: 1_800,
                rangeStartMs: rangeStart,
                rangeEndMs: rangeEnd
            ),
            "Un evento interior debe verse"
        )
        XCTAssertFalse(
            PlannerCalendarRange.overlaps(
                eventStartMs: 100,
                eventEndMs: 900,
                rangeStartMs: rangeStart,
                rangeEndMs: rangeEnd
            ),
            "Un evento completamente anterior no debe verse"
        )
        XCTAssertFalse(
            PlannerCalendarRange.overlaps(
                eventStartMs: 2_100,
                eventEndMs: 3_000,
                rangeStartMs: rangeStart,
                rangeEndMs: rangeEnd
            ),
            "Un evento completamente posterior no debe verse"
        )
        XCTAssertTrue(
            PlannerCalendarRange.overlaps(
                eventStartMs: 2_000,
                eventEndMs: 2_500,
                rangeStartMs: rangeStart,
                rangeEndMs: rangeEnd
            ),
            "El borde inclusivo del final debe verse"
        )
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

    func testSearchKeepsTheWeekBoardWhileFilteringTheList() {
        let vm = PlannerWorkspaceViewModel()
        let fitness = PlanningSession(
            id: 101,
            teachingUnitId: 1,
            teachingUnitName: "Condición Física",
            teachingUnitColor: "#4A90D9",
            groupId: 1,
            groupName: "1º ESO A",
            dayOfWeek: 1,
            period: 1,
            weekNumber: 39,
            year: 2026,
            objectives: "Resistencia",
            activities: "Course Navette",
            evaluation: "",
            linkedAssessmentIdsCsv: "",
            teacherScheduleSlotId: nil,
            startTime: "08:05",
            endTime: "09:00",
            learningSituationSessionPlanId: nil,
            status: .planned
        )
        let basketball = PlanningSession(
            id: 102,
            teachingUnitId: 2,
            teachingUnitName: "Baloncesto",
            teachingUnitColor: "#F5A623",
            groupId: 2,
            groupName: "2º Bach B",
            dayOfWeek: 1,
            period: 2,
            weekNumber: 39,
            year: 2026,
            objectives: "Tiro",
            activities: "Rueda de tiro",
            evaluation: "",
            linkedAssessmentIdsCsv: "",
            teacherScheduleSlotId: nil,
            startTime: "09:00",
            endTime: "09:55",
            learningSituationSessionPlanId: nil,
            status: .planned
        )
        vm.sessions = [fitness, basketball]
        vm.visibleWeekdays = [1]
        vm.visibleSlots = [PlannerVisibleSlot(period: 1, startTime: "08:05", endTime: "09:00"), PlannerVisibleSlot(period: 2, startTime: "09:00", endTime: "09:55")]
        vm.rebuildWeekRenderModel()
        let boardBeforeSearch = vm.weekBoard.weekRenderModel

        vm.searchText = "baloncesto"
        vm.applySearch()

        XCTAssertEqual(vm.weekBoard.weekRenderModel, boardBeforeSearch)
        XCTAssertEqual(vm.filteredSessions.map(\.id), [basketball.id])
    }

    func testTypingAGradeDoesNotSnapshotTheWholeClass() {
        XCTAssertTrue(NotebookSyncScope.sendsOnlyEditedCell(.numeric))
        XCTAssertTrue(NotebookSyncScope.sendsOnlyEditedCell(.text))
        XCTAssertFalse(NotebookSyncScope.sendsOnlyEditedCell(.rubric))
        XCTAssertFalse(NotebookSyncScope.sendsOnlyEditedCell(.calculated))
    }

    func testWipeStopsWhenTheSafetyCopyFails() {
        XCTAssertEqual(
            SelectiveWipeCopy.backupBlocked,
            "No se pudo crear la copia previa. No se ha borrado nada."
        )
    }

    func testBackupCreateFailureKeepsTheSheetOpen() {
        XCTAssertEqual(
            CreateBackupCopy.failure,
            "No se pudo crear la copia. Sigue en esta pantalla."
        )
    }

    func testCascadeUndoFailureSaysTheSessionsStayed() {
        XCTAssertEqual(
            CascadeUndoCopy.failure("red ocupada"),
            "No se pudo deshacer el movimiento. red ocupada"
        )
    }

    func testInlineGradeFailureShowsTheSaveBadge() {
        XCTAssertTrue(NotebookSaveBadge.showsFailure(splitFailed: false, inlineFailed: true))
        XCTAssertFalse(NotebookSaveBadge.showsFailure(splitFailed: false, inlineFailed: false))
    }

    func testAttendanceSyncDoesNotReloadTheWholePlanner() {
        let plan = LanSyncRefreshPlan.steps(entities: ["attendance"])
        XCTAssertFalse(plan.classes)
        XCTAssertFalse(plan.students)
        XCTAssertFalse(plan.rubrics)
        XCTAssertFalse(plan.planning)
        let planner = LanSyncRefreshPlan.steps(entities: ["planning_session"])
        XCTAssertTrue(planner.planning)
        XCTAssertFalse(planner.students)
    }

    func testFailedReloadKeepsThePreviousList() {
        let previous = ["diario-a"]
        XCTAssertEqual(
            PlannerReloadPolicy.value(previous: previous, next: nil as [String]?, failed: true),
            previous
        )
        XCTAssertEqual(
            PlannerReloadPolicy.value(previous: previous, next: ["diario-b"], failed: false),
            ["diario-b"]
        )
    }

    func testNotebookGridIgnoresAPartialSearchUntilItSettles() {
        XCTAssertEqual(
            NotebookGridSearch.queryForGrid(liveText: "mar", settledText: ""),
            ""
        )
        XCTAssertEqual(
            NotebookGridSearch.queryForGrid(liveText: "mar", settledText: " mar "),
            "mar"
        )
    }

    func testNotebookNoteSaveWaitsForSettledKeystrokes() {
        XCTAssertFalse(NotebookColumnGradeSave.shouldPersistNow(.keystroke))
        XCTAssertTrue(NotebookColumnGradeSave.shouldPersistNow(.confirmOrBlur))
        XCTAssertEqual(NotebookColumnGradeSave.debounceNanoseconds, 250_000_000)
    }

    func testNotebookNoteSaveFlushesBeforeLeavingTheCell() {
        XCTAssertTrue(NotebookColumnGradeSave.shouldPersistNow(.confirmOrBlur))
        XCTAssertTrue(NotebookColumnGradeSave.shouldPersistNow(.enterBackground))
        XCTAssertTrue(NotebookColumnGradeSave.shouldPersistNow(.groupOrClassChange))
    }

    func testPlanningSessionSyncDoesNotMoveTheCell() {
        XCTAssertEqual(
            PlanningSessionSyncMerge.placement(previous: 3, incoming: nil, keyPresent: false),
            3
        )
        XCTAssertEqual(
            PlanningSessionSyncMerge.placement(previous: 3, incoming: 5, keyPresent: true),
            5
        )
    }

    func testSessionPlanSyncKeepsTheObjective() {
        XCTAssertEqual(
            TeachingUnitSyncMerge.text(previous: "Cruzar el río", incoming: nil, keyPresent: false),
            "Cruzar el río"
        )
        XCTAssertEqual(
            SituationVersionSyncMerge.number(previous: 45, incoming: nil, keyPresent: false),
            45
        )
    }

    func testSituationVersionSyncReusesTheExistingCopy() {
        XCTAssertEqual(SituationVersionSyncMerge.keptId(incoming: 0, matched: 4), 4)
        XCTAssertEqual(SituationVersionSyncMerge.number(previous: 2, incoming: nil, keyPresent: false), 2)
        XCTAssertEqual(SituationVersionSyncMerge.number(previous: 2, incoming: 3, keyPresent: true), 3)
    }

    func testSituationSyncDoesNotActivateOrWipeTheDocument() {
        XCTAssertTrue(LearningSituationSyncMerge.staysDraft(previousIsDraft: true, incoming: nil, keyPresent: false))
        XCTAssertFalse(LearningSituationSyncMerge.staysDraft(previousIsDraft: true, incoming: "ACTIVE", keyPresent: true))
        XCTAssertEqual(
            TeachingUnitSyncMerge.text(previous: "{\"sesiones\":3}", incoming: nil, keyPresent: false),
            "{\"sesiones\":3}"
        )
    }

    func testTeachingUnitSyncKeepsDatesWhenTheNameArrivesAlone() {
        XCTAssertEqual(
            TeachingUnitSyncMerge.text(previous: "Juegos de invasión", incoming: nil, keyPresent: false),
            "Juegos de invasión"
        )
        XCTAssertEqual(
            TeachingUnitSyncMerge.text(previous: "Antes", incoming: "Después", keyPresent: true),
            "Después"
        )
    }

    func testTeacherScheduleSyncKeepsCourseDatesWhenKeysAreMissing() {
        XCTAssertEqual(
            TeacherScheduleSyncMerge.dates(
                previous: "2026-09-01",
                incoming: nil,
                keyPresent: false
            ),
            "2026-09-01"
        )
        XCTAssertEqual(
            TeacherScheduleSyncMerge.dates(
                previous: "2027-06-30",
                incoming: nil,
                keyPresent: false
            ),
            "2027-06-30"
        )
        XCTAssertEqual(
            TeacherScheduleSyncMerge.text(
                previous: "1,2,3,4,5",
                incoming: nil,
                keyPresent: false
            ),
            "1,2,3,4,5"
        )
        XCTAssertEqual(
            TeacherScheduleSyncMerge.longId(previous: 42, incoming: nil, keyPresent: false),
            42
        )
        XCTAssertEqual(
            TeacherScheduleSyncMerge.dates(
                previous: "2026-09-01",
                incoming: "2026-10-01",
                keyPresent: true
            ),
            "2026-10-01"
        )
        XCTAssertEqual(
            TeacherScheduleSyncMerge.longId(previous: 42, incoming: 7, keyPresent: true),
            7
        )
    }

    func testEvaluationPeriodSyncKeepsDatesWhenNameArrivesAlone() {
        XCTAssertEqual(
            PlannerEvaluationPeriodSyncMerge.dates(
                previous: "2026-09-01",
                incoming: nil,
                keyPresent: false
            ),
            "2026-09-01"
        )
        XCTAssertEqual(
            PlannerEvaluationPeriodSyncMerge.dates(
                previous: "2026-12-20",
                incoming: nil,
                keyPresent: false
            ),
            "2026-12-20"
        )
        XCTAssertEqual(
            PlannerEvaluationPeriodSyncMerge.text(
                previous: "1ª evaluación",
                incoming: "Primera",
                keyPresent: true
            ),
            "Primera"
        )
        XCTAssertEqual(
            PlannerEvaluationPeriodSyncMerge.sortOrder(
                previous: 2,
                incoming: nil,
                keyPresent: false
            ),
            2
        )
        XCTAssertEqual(
            PlannerEvaluationPeriodSyncMerge.dates(
                previous: "2026-09-01",
                incoming: "2026-10-01",
                keyPresent: true
            ),
            "2026-10-01"
        )
    }

    func testLearningSituationLinkSyncKeepsLabelAndReusesExisting() {
        XCTAssertEqual(
            LearningSituationLinkSyncMerge.label(
                previous: "Rúbrica · Saltos",
                incoming: nil,
                keyPresent: false
            ),
            "Rúbrica · Saltos"
        )
        XCTAssertEqual(
            LearningSituationLinkSyncMerge.label(
                previous: "Antes",
                incoming: "Después",
                keyPresent: true
            ),
            "Después"
        )
        XCTAssertEqual(
            LearningSituationLinkSyncMerge.keptId(incoming: 0, matched: 12),
            12
        )
        XCTAssertEqual(
            LearningSituationLinkSyncMerge.keptId(incoming: 0, matched: nil),
            0
        )
    }

    func testWeeklySlotSyncReusesExistingByIdOrSchedule() {
        let existing = [
            WeeklySlotSyncMerge.ExistingSlot(
                id: 5,
                dayOfWeek: 1,
                startTime: "09:00",
                endTime: "10:00"
            )
        ]
        XCTAssertEqual(
            WeeklySlotSyncMerge.matchedId(
                incomingId: 5,
                dayOfWeek: 2,
                startTime: "11:00",
                endTime: "12:00",
                existing: existing
            ),
            5
        )
        XCTAssertEqual(
            WeeklySlotSyncMerge.matchedId(
                incomingId: 99,
                dayOfWeek: 1,
                startTime: "09:00",
                endTime: "10:00",
                existing: existing
            ),
            5
        )
        XCTAssertEqual(
            WeeklySlotSyncMerge.keptId(incoming: 99, matched: 5),
            5
        )
        XCTAssertNil(
            WeeklySlotSyncMerge.matchedId(
                incomingId: 0,
                dayOfWeek: 3,
                startTime: "12:00",
                endTime: "13:00",
                existing: existing
            )
        )
        XCTAssertEqual(
            WeeklySlotSyncMerge.keptId(incoming: 0, matched: nil),
            0
        )
    }

    func testGradeSyncKeepsTheMarkWhenValueKeyIsMissing() {
        XCTAssertEqual(
            GradeSyncMerge.optionalDouble(previous: 7.5, incoming: nil, keyPresent: false),
            7.5
        )
        XCTAssertEqual(
            GradeSyncMerge.optionalText(previous: "foto del salto", incoming: nil, keyPresent: false),
            "foto del salto"
        )
        XCTAssertEqual(
            GradeSyncMerge.optionalDouble(previous: 7.5, incoming: 8.5, keyPresent: true),
            8.5
        )
        XCTAssertNil(
            GradeSyncMerge.optionalDouble(previous: 7.5, incoming: nil, keyPresent: true)
        )
        XCTAssertEqual(
            GradeSyncMerge.optionalText(previous: "foto del salto", incoming: "vídeo", keyPresent: true),
            "vídeo"
        )
    }

    func testAttendanceSyncKeepsNoteAndFlagsWhenKeysAreMissing() {
        XCTAssertEqual(
            AttendanceSyncMerge.text(previous: "Llegó tarde", incoming: nil, keyPresent: false),
            "Llegó tarde"
        )
        XCTAssertTrue(
            AttendanceSyncMerge.flag(previous: true, incoming: nil, keyPresent: false)
        )
        XCTAssertTrue(
            AttendanceSyncMerge.flag(previous: true, incoming: false, keyPresent: false)
        )
        XCTAssertEqual(
            AttendanceSyncMerge.text(previous: "Llegó tarde", incoming: "Justificado", keyPresent: true),
            "Justificado"
        )
        XCTAssertFalse(
            AttendanceSyncMerge.flag(previous: true, incoming: false, keyPresent: true)
        )
        XCTAssertEqual(
            AttendanceSyncMerge.text(previous: "Llegó tarde", incoming: nil, keyPresent: true),
            ""
        )
    }

    func testIncidentSyncKeepsDetailAndSeverityWhenKeysAreMissing() {
        XCTAssertEqual(
            IncidentSyncMerge.optionalText(
                previous: "Se torció el tobillo",
                incoming: nil,
                keyPresent: false
            ),
            "Se torció el tobillo"
        )
        XCTAssertEqual(
            IncidentSyncMerge.severity(
                previous: "high",
                incoming: nil,
                keyPresent: false
            ),
            "high"
        )
        XCTAssertEqual(
            IncidentSyncMerge.optionalText(
                previous: "Se torció el tobillo",
                incoming: "Actualizado",
                keyPresent: true
            ),
            "Actualizado"
        )
        XCTAssertEqual(
            IncidentSyncMerge.severity(
                previous: "high",
                incoming: "low",
                keyPresent: true
            ),
            "low"
        )
        XCTAssertNil(
            IncidentSyncMerge.optionalText(
                previous: "Se torció el tobillo",
                incoming: nil,
                keyPresent: true
            )
        )
        XCTAssertEqual(
            IncidentSyncMerge.severity(
                previous: "high",
                incoming: nil,
                keyPresent: true
            ),
            "high"
        )
    }

    func testCalendarEventSyncKeepsDescriptionAndClassWhenKeysAreMissing() {
        XCTAssertEqual(
            CalendarEventSyncMerge.optionalText(
                previous: "Excursión al museo",
                incoming: nil,
                keyPresent: false
            ),
            "Excursión al museo"
        )
        XCTAssertEqual(
            CalendarEventSyncMerge.optionalClassId(
                previous: 12,
                incoming: nil,
                keyPresent: false
            ),
            12
        )
        XCTAssertEqual(
            CalendarEventSyncMerge.optionalText(
                previous: "Excursión al museo",
                incoming: "Actualizado",
                keyPresent: true
            ),
            "Actualizado"
        )
        XCTAssertEqual(
            CalendarEventSyncMerge.optionalClassId(
                previous: 12,
                incoming: 7,
                keyPresent: true
            ),
            7
        )
        XCTAssertNil(
            CalendarEventSyncMerge.optionalText(
                previous: "Excursión al museo",
                incoming: nil,
                keyPresent: true
            )
        )
        XCTAssertNil(
            CalendarEventSyncMerge.optionalClassId(
                previous: 12,
                incoming: 0,
                keyPresent: true
            )
        )
    }

    func testEvaluationSyncKeepsWeightFormulaRubricAndDescriptionWhenKeysAreMissing() {
        XCTAssertEqual(
            EvaluationSyncMerge.weight(previous: 2.5, incoming: nil, keyPresent: false),
            2.5
        )
        XCTAssertEqual(
            EvaluationSyncMerge.optionalText(
                previous: "media(a,b)",
                incoming: nil,
                keyPresent: false
            ),
            "media(a,b)"
        )
        XCTAssertEqual(
            EvaluationSyncMerge.optionalLong(previous: 42, incoming: nil, keyPresent: false),
            42
        )
        XCTAssertEqual(
            EvaluationSyncMerge.optionalText(
                previous: "Prueba escrita",
                incoming: nil,
                keyPresent: false
            ),
            "Prueba escrita"
        )
        XCTAssertEqual(
            EvaluationSyncMerge.weight(previous: 2.5, incoming: 1.0, keyPresent: true),
            1.0
        )
        XCTAssertEqual(
            EvaluationSyncMerge.optionalText(
                previous: "media(a,b)",
                incoming: "suma(a)",
                keyPresent: true
            ),
            "suma(a)"
        )
        XCTAssertEqual(
            EvaluationSyncMerge.optionalLong(previous: 42, incoming: 7, keyPresent: true),
            7
        )
        XCTAssertNil(
            EvaluationSyncMerge.optionalLong(previous: 42, incoming: nil, keyPresent: true)
        )
        XCTAssertNil(
            EvaluationSyncMerge.optionalText(
                previous: "Prueba escrita",
                incoming: nil,
                keyPresent: true
            )
        )
    }

    func testRubricBundleSyncKeepsClassAndCriterionWeightWhenKeysAreMissing() {
        XCTAssertEqual(
            RubricBundleSyncMerge.optionalText(
                previous: "Rúbrica de juegos",
                incoming: nil,
                keyPresent: false
            ),
            "Rúbrica de juegos"
        )
        XCTAssertEqual(
            RubricBundleSyncMerge.optionalLong(previous: 12, incoming: nil, keyPresent: false),
            12
        )
        XCTAssertEqual(
            RubricBundleSyncMerge.optionalLong(previous: 7, incoming: nil, keyPresent: false),
            7
        )
        XCTAssertEqual(
            RubricBundleSyncMerge.weight(previous: 2.5, incoming: nil, keyPresent: false),
            2.5
        )
        XCTAssertEqual(
            RubricBundleSyncMerge.order(previous: 3, incoming: nil, keyPresent: false),
            3
        )
        XCTAssertEqual(
            RubricBundleSyncMerge.text(
                previous: "Colabora en el grupo",
                incoming: nil,
                keyPresent: false
            ),
            "Colabora en el grupo"
        )
        XCTAssertEqual(
            RubricBundleSyncMerge.optionalText(
                previous: "Rúbrica de juegos",
                incoming: "Nueva descripción",
                keyPresent: true
            ),
            "Nueva descripción"
        )
        XCTAssertEqual(
            RubricBundleSyncMerge.optionalLong(previous: 12, incoming: 9, keyPresent: true),
            9
        )
        XCTAssertNil(
            RubricBundleSyncMerge.optionalLong(previous: 12, incoming: nil, keyPresent: true)
        )
        XCTAssertEqual(
            RubricBundleSyncMerge.weight(previous: 2.5, incoming: 1.0, keyPresent: true),
            1.0
        )
        XCTAssertEqual(
            RubricBundleSyncMerge.order(previous: 3, incoming: 8, keyPresent: true),
            8
        )
        XCTAssertEqual(
            RubricBundleSyncMerge.text(
                previous: "Colabora en el grupo",
                incoming: "Participa",
                keyPresent: true
            ),
            "Participa"
        )
    }

    func testAcademicYearSyncKeepsActiveStatusCenterAndDatesWhenKeysAreMissing() {
        XCTAssertTrue(
            AcademicYearSyncMerge.flag(previous: true, incoming: nil, keyPresent: false)
        )
        XCTAssertFalse(
            AcademicYearSyncMerge.flag(previous: true, incoming: false, keyPresent: true)
        )
        XCTAssertEqual(
            AcademicYearSyncMerge.status(
                previous: "ACTIVE",
                incoming: nil,
                keyPresent: false
            ),
            "ACTIVE"
        )
        XCTAssertEqual(
            AcademicYearSyncMerge.status(
                previous: "ACTIVE",
                incoming: "ARCHIVED",
                keyPresent: true
            ),
            "ARCHIVED"
        )
        XCTAssertEqual(
            AcademicYearSyncMerge.centerId(previous: 7, incoming: nil, keyPresent: false),
            7
        )
        XCTAssertEqual(
            AcademicYearSyncMerge.centerId(previous: 7, incoming: 3, keyPresent: true),
            3
        )
        XCTAssertEqual(
            AcademicYearSyncMerge.epochMs(
                previous: 1_720_000_000_000,
                incoming: nil,
                keyPresent: false
            ),
            1_720_000_000_000
        )
        XCTAssertEqual(
            AcademicYearSyncMerge.epochMs(
                previous: 1_720_000_000_000,
                incoming: 1_730_000_000_000,
                keyPresent: true
            ),
            1_730_000_000_000
        )
        XCTAssertEqual(
            AcademicYearSyncMerge.optionalEpochMs(
                previous: 1_740_000_000_000,
                incoming: nil,
                keyPresent: false
            ),
            1_740_000_000_000
        )
        XCTAssertNil(
            AcademicYearSyncMerge.optionalEpochMs(
                previous: 1_740_000_000_000,
                incoming: nil,
                keyPresent: true
            )
        )
    }

    func testClassSyncKeepsDescriptionCenterAndYearWhenKeysAreMissing() {
        XCTAssertEqual(
            ClassSyncMerge.optionalText(
                previous: "Nota de la clase",
                incoming: nil,
                keyPresent: false
            ),
            "Nota de la clase"
        )
        XCTAssertEqual(
            ClassSyncMerge.optionalLong(previous: 7, incoming: nil, keyPresent: false),
            7
        )
        XCTAssertEqual(
            ClassSyncMerge.optionalLong(previous: 12, incoming: nil, keyPresent: false),
            12
        )
        XCTAssertEqual(
            ClassSyncMerge.optionalLong(previous: 3, incoming: nil, keyPresent: false),
            3
        )
        XCTAssertEqual(
            ClassSyncMerge.optionalLong(previous: 9, incoming: nil, keyPresent: false),
            9
        )
        XCTAssertEqual(
            ClassSyncMerge.optionalText(
                previous: "Nota de la clase",
                incoming: "Otra nota",
                keyPresent: true
            ),
            "Otra nota"
        )
        XCTAssertNil(
            ClassSyncMerge.optionalText(
                previous: "Nota de la clase",
                incoming: nil,
                keyPresent: true
            )
        )
        XCTAssertEqual(
            ClassSyncMerge.optionalLong(previous: 7, incoming: 4, keyPresent: true),
            4
        )
        XCTAssertNil(
            ClassSyncMerge.optionalLong(previous: 7, incoming: nil, keyPresent: true)
        )
    }

    func testRubricBundleSyncKeepsLevelPointsWhenKeyIsMissing() {
        XCTAssertEqual(
            RubricBundleSyncMerge.points(previous: 4, incoming: nil, keyPresent: false),
            4
        )
        XCTAssertEqual(
            RubricBundleSyncMerge.order(previous: 2, incoming: nil, keyPresent: false),
            2
        )
        XCTAssertEqual(
            RubricBundleSyncMerge.optionalText(
                previous: "Cumple casi todo",
                incoming: nil,
                keyPresent: false
            ),
            "Cumple casi todo"
        )
        XCTAssertEqual(
            RubricBundleSyncMerge.points(previous: 4, incoming: 0, keyPresent: true),
            0
        )
        XCTAssertEqual(
            RubricBundleSyncMerge.points(previous: 4, incoming: 3, keyPresent: true),
            3
        )
        XCTAssertEqual(
            RubricBundleSyncMerge.order(previous: 2, incoming: 5, keyPresent: true),
            5
        )
        XCTAssertEqual(
            RubricBundleSyncMerge.optionalText(
                previous: "Cumple casi todo",
                incoming: "Excelente",
                keyPresent: true
            ),
            "Excelente"
        )
        XCTAssertNil(
            RubricBundleSyncMerge.optionalText(
                previous: "Cumple casi todo",
                incoming: nil,
                keyPresent: true
            )
        )
    }

    func testNotebookTabSyncKeepsOrderParentAndDescriptionWhenKeysAreMissing() {
        XCTAssertEqual(
            NotebookTabSyncMerge.order(previous: 5, incoming: nil, keyPresent: false),
            5
        )
        XCTAssertEqual(
            NotebookTabSyncMerge.optionalText(
                previous: "curso",
                incoming: nil,
                keyPresent: false
            ),
            "curso"
        )
        XCTAssertEqual(
            NotebookTabSyncMerge.optionalText(
                previous: "Pestaña de evaluación",
                incoming: nil,
                keyPresent: false
            ),
            "Pestaña de evaluación"
        )
        XCTAssertEqual(
            NotebookTabSyncMerge.order(previous: 5, incoming: 1, keyPresent: true),
            1
        )
        XCTAssertEqual(
            NotebookTabSyncMerge.optionalText(
                previous: "curso",
                incoming: "trimestre",
                keyPresent: true
            ),
            "trimestre"
        )
        XCTAssertNil(
            NotebookTabSyncMerge.optionalText(
                previous: "curso",
                incoming: nil,
                keyPresent: true
            )
        )
        XCTAssertEqual(
            NotebookTabSyncMerge.optionalText(
                previous: "Pestaña de evaluación",
                incoming: "Otra descripción",
                keyPresent: true
            ),
            "Otra descripción"
        )
    }

    func testNotebookGroupSyncKeepsOrderAndLearningSituationWhenKeysAreMissing() {
        XCTAssertEqual(
            NotebookGroupSyncMerge.order(previous: 3, incoming: nil, keyPresent: false),
            3
        )
        XCTAssertEqual(
            NotebookGroupSyncMerge.optionalLong(previous: 42, incoming: nil, keyPresent: false),
            42
        )
        XCTAssertEqual(
            NotebookGroupSyncMerge.order(previous: 3, incoming: 1, keyPresent: true),
            1
        )
        XCTAssertEqual(
            NotebookGroupSyncMerge.optionalLong(previous: 42, incoming: 7, keyPresent: true),
            7
        )
        XCTAssertNil(
            NotebookGroupSyncMerge.optionalLong(previous: 42, incoming: nil, keyPresent: true)
        )
    }

    func testSessionJournalSyncKeepsTextAndScoreWhenKeysAreMissing() {
        XCTAssertEqual(
            SessionJournalSyncMerge.text(
                previous: "Calentamiento en circuitos",
                incoming: nil,
                keyPresent: false
            ),
            "Calentamiento en circuitos"
        )
        XCTAssertEqual(
            SessionJournalSyncMerge.score(previous: 4, incoming: nil, keyPresent: false),
            4
        )
        XCTAssertEqual(
            SessionJournalSyncMerge.text(
                previous: "Calentamiento en circuitos",
                incoming: "Partido reducido",
                keyPresent: true
            ),
            "Partido reducido"
        )
        XCTAssertEqual(
            SessionJournalSyncMerge.score(previous: 4, incoming: 2, keyPresent: true),
            2
        )
        XCTAssertEqual(
            SessionJournalSyncMerge.text(
                previous: "Calentamiento en circuitos",
                incoming: nil,
                keyPresent: true
            ),
            ""
        )
        XCTAssertEqual(
            SessionJournalSyncMerge.score(previous: 4, incoming: nil, keyPresent: true),
            4
        )
    }

    func testNotebookColumnSyncKeepsAverageAndLayoutWhenKeysAreMissing() {
        XCTAssertEqual(
            NotebookColumnSyncMerge.optionalText(
                previous: "media(a,b)",
                incoming: nil,
                keyPresent: false
            ),
            "media(a,b)"
        )
        XCTAssertEqual(
            NotebookColumnSyncMerge.weight(previous: 2.0, incoming: nil, keyPresent: false),
            2.0
        )
        XCTAssertFalse(
            NotebookColumnSyncMerge.flag(previous: false, incoming: true, keyPresent: false)
        )
        XCTAssertTrue(
            NotebookColumnSyncMerge.flag(previous: true, incoming: false, keyPresent: false)
        )
        XCTAssertTrue(
            NotebookColumnSyncMerge.flag(previous: true, incoming: false, keyPresent: false)
        )
        XCTAssertEqual(
            NotebookColumnSyncMerge.order(previous: 4, incoming: nil, keyPresent: false),
            4
        )
        XCTAssertEqual(
            NotebookColumnSyncMerge.typeValue(
                previous: "CALCULATED",
                incoming: "NUMERIC" as String?,
                keyPresent: false
            ),
            "CALCULATED"
        )
        XCTAssertEqual(
            NotebookColumnSyncMerge.optionalText(
                previous: "media(a,b)",
                incoming: "suma(a,b)",
                keyPresent: true
            ),
            "suma(a,b)"
        )
        XCTAssertEqual(
            NotebookColumnSyncMerge.weight(previous: 2.0, incoming: 1.5, keyPresent: true),
            1.5
        )
        XCTAssertFalse(
            NotebookColumnSyncMerge.flag(previous: true, incoming: false, keyPresent: true)
        )
        XCTAssertEqual(
            NotebookColumnSyncMerge.order(previous: 4, incoming: 9, keyPresent: true),
            9
        )
        XCTAssertEqual(
            NotebookColumnSyncMerge.typeValue(
                previous: "CALCULATED",
                incoming: "NUMERIC" as String?,
                keyPresent: true
            ),
            "NUMERIC"
        )
        XCTAssertNil(
            NotebookColumnSyncMerge.optionalText(
                previous: "media(a,b)",
                incoming: nil,
                keyPresent: true
            )
        )
    }

    func testStudentSyncKeepsFieldsWhenKeysAreMissing() {
        XCTAssertEqual(
            StudentSyncMerge.optionalText(
                previous: "ana@colegio.es",
                incoming: nil,
                keyPresent: false
            ),
            "ana@colegio.es"
        )
        XCTAssertTrue(
            StudentSyncMerge.flag(previous: true, incoming: nil, keyPresent: false)
        )
        XCTAssertEqual(
            StudentSyncMerge.value(previous: "MALE", incoming: "FEMALE", keyPresent: false),
            "MALE"
        )
        XCTAssertEqual(
            StudentSyncMerge.optionalValue(
                previous: "2012-03-14" as String?,
                incoming: nil,
                keyPresent: false
            ),
            "2012-03-14"
        )
        XCTAssertEqual(
            StudentSyncMerge.optionalText(
                previous: "ana@colegio.es",
                incoming: "nueva@colegio.es",
                keyPresent: true
            ),
            "nueva@colegio.es"
        )
        XCTAssertFalse(
            StudentSyncMerge.flag(previous: true, incoming: false, keyPresent: true)
        )
        XCTAssertNil(
            StudentSyncMerge.optionalText(
                previous: "ana@colegio.es",
                incoming: nil,
                keyPresent: true
            )
        )
        XCTAssertEqual(
            StudentSyncMerge.value(previous: "MALE", incoming: "FEMALE", keyPresent: true),
            "FEMALE"
        )
        XCTAssertNil(
            StudentSyncMerge.optionalValue(
                previous: "2012-03-14" as String?,
                incoming: nil as String?,
                keyPresent: true
            )
        )
    }

    func testNotebookCellSyncKeepsFieldsWhenKeysAreMissing() {
        XCTAssertEqual(
            NotebookCellSyncMerge.optionalText(
                previous: "nota previa",
                incoming: nil,
                keyPresent: false
            ),
            "nota previa"
        )
        XCTAssertEqual(
            NotebookCellSyncMerge.optionalText(
                previous: "icono",
                incoming: "nuevo",
                keyPresent: true
            ),
            "nuevo"
        )
        XCTAssertNil(
            NotebookCellSyncMerge.optionalText(
                previous: "nota previa",
                incoming: nil,
                keyPresent: true
            )
        )
        XCTAssertEqual(
            NotebookCellSyncMerge.optionalBool(
                previous: true,
                incoming: nil,
                keyPresent: false
            ),
            true
        )
        XCTAssertEqual(
            NotebookCellSyncMerge.optionalBool(
                previous: true,
                incoming: false,
                keyPresent: true
            ),
            false
        )
        XCTAssertNil(
            NotebookCellSyncMerge.optionalBool(
                previous: true,
                incoming: nil,
                keyPresent: true
            )
        )
        XCTAssertEqual(
            NotebookCellSyncMerge.attachmentUris(
                previous: ["foto://a", "foto://b"],
                incoming: nil,
                keyPresent: false
            ),
            ["foto://a", "foto://b"]
        )
        XCTAssertEqual(
            NotebookCellSyncMerge.attachmentUris(
                previous: ["foto://a"],
                incoming: ["foto://nuevo"],
                keyPresent: true
            ),
            ["foto://nuevo"]
        )
        XCTAssertEqual(
            NotebookCellSyncMerge.attachmentUris(
                previous: ["foto://a"],
                incoming: [],
                keyPresent: true
            ),
            []
        )
    }

    func testTeacherScheduleSlotSyncKeepsDayAndSubjectWhenKeysAreMissing() {
        XCTAssertEqual(
            TeacherScheduleSlotSyncMerge.dayOfWeek(
                previous: 3,
                incoming: nil,
                keyPresent: false
            ),
            3
        )
        XCTAssertEqual(
            TeacherScheduleSlotSyncMerge.text(
                previous: "Educación Física",
                incoming: nil,
                keyPresent: false
            ),
            "Educación Física"
        )
        XCTAssertEqual(
            TeacherScheduleSlotSyncMerge.optionalText(
                previous: "Unidad 2",
                incoming: nil,
                keyPresent: false
            ),
            "Unidad 2"
        )
        XCTAssertEqual(
            TeacherScheduleSlotSyncMerge.longId(
                previous: 20,
                incoming: nil,
                keyPresent: false
            ),
            20
        )
        XCTAssertEqual(
            TeacherScheduleSlotSyncMerge.optionalLongId(
                previous: 99,
                incoming: nil,
                keyPresent: false
            ),
            99
        )
        XCTAssertEqual(
            TeacherScheduleSlotSyncMerge.dayOfWeek(
                previous: 3,
                incoming: 5,
                keyPresent: true
            ),
            5
        )
        XCTAssertEqual(
            TeacherScheduleSlotSyncMerge.text(
                previous: "Educación Física",
                incoming: "EF",
                keyPresent: true
            ),
            "EF"
        )
        XCTAssertEqual(
            TeacherScheduleSlotSyncMerge.optionalLongId(
                previous: 99,
                incoming: 0,
                keyPresent: true
            ),
            nil
        )
    }

    func testSupportOverviewDoesNotCallAFailedStudentUnsupported() {
        XCTAssertFalse(
            SupportGroupOverviewReload.includeInWithoutList(loadFailed: true, hadPrevious: false, isEmpty: true)
        )
        XCTAssertTrue(
            SupportGroupOverviewReload.includeInWithoutList(loadFailed: false, hadPrevious: true, isEmpty: true)
        )
        XCTAssertEqual(
            SupportGroupOverviewReload.failure,
            "No se pudieron leer algunas medidas. Esos alumnos no se muestran como si no tuvieran."
        )
    }

    func testPhysicalResultsStayWhenTheLoadFails() {
        XCTAssertEqual(
            PhysicalTestsReload.failure,
            "No se pudieron cargar las pruebas físicas. Se mantiene lo que ya ves."
        )
        XCTAssertEqual(
            ProfileReloadKeep.list(loaded: nil as [String]?, previous: ["Ana 8,2"], samePerson: true),
            ["Ana 8,2"]
        )
    }

    func testSituationDetailStaysWhenTheLoadFails() {
        XCTAssertEqual(
            SituationDetailReload.failure,
            "No se pudo cargar la situación. Se mantiene lo que ya ves."
        )
        XCTAssertEqual(
            ProfileReloadKeep.list(loaded: nil as [Int]?, previous: [3], samePerson: true),
            [3]
        )
    }

    func testPeerFormIsNotPublishedWhenGroupsFailToLoad() {
        XCTAssertEqual(
            WebPeerPublishGuard.groupsFailure,
            "No se pudieron leer los grupos. No se ha publicado la coevaluación para no dejarla sin equipos."
        )
        let failed = KmpBridge.WebPeerDetectionResult(
            learningSituationId: nil,
            learningSituationTitle: nil,
            groups: [],
            assignedStudentCount: 0,
            unassignedStudentCount: 0,
            totalStudents: 12,
            loadFailed: true
        )
        XCTAssertTrue(failed.loadFailed)
        XCTAssertTrue(failed.groups.isEmpty)
    }

    func testPhysicalColumnsAreNotCreatedWhenExistingLinksAreUnknown() {
        XCTAssertEqual(
            PhysicalColumnCreateGuard.linksFailure,
            "No se pudieron leer las columnas ya creadas. No se ha creado ninguna para no duplicarlas."
        )
    }

    func testInstrumentItemKeepsTheScaleWhenTheTitleArrivesAlone() {
        XCTAssertEqual(InstrumentItemMerge.options(previous: ["1", "2", "3", "4"], incoming: nil), ["1", "2", "3", "4"])
        XCTAssertEqual(InstrumentItemMerge.options(previous: ["1"], incoming: ["sí", "no"]), ["sí", "no"])
        XCTAssertFalse(InstrumentItemMerge.flag(previous: false, incoming: nil))
        XCTAssertEqual(InstrumentItemMerge.order(previous: 2, incoming: nil), 2)
    }

    func testInstrumentSyncDoesNotWipeSiblingAnswers() {
        XCTAssertNil(
            InstrumentResponseMerge.replacing(existing: nil as [String]?, removeWhere: { $0 == "a" }, incoming: "a2")
        )
        XCTAssertEqual(
            InstrumentResponseMerge.replacing(existing: ["a", "b"], removeWhere: { $0 == "a" }, incoming: "a2"),
            ["b", "a2"]
        )
        XCTAssertNil(InstrumentResponseMerge.removing(existing: nil as [String]?, removeWhere: { $0 == "a" }))
        XCTAssertEqual(
            InstrumentResponseMerge.removing(existing: ["a", "b"], removeWhere: { $0 == "a" }),
            ["b"]
        )
    }

    func testSupportImportDoesNotDuplicateWhenExistingMeasuresAreUnknown() {
        XCTAssertFalse(SupportMeasureImportGuard.shouldSave(alreadyKnown: nil as Set<String>?, measure: "lectura"))
        XCTAssertFalse(SupportMeasureImportGuard.shouldSave(alreadyKnown: ["lectura"], measure: "lectura"))
        XCTAssertTrue(SupportMeasureImportGuard.shouldSave(alreadyKnown: ["otra"], measure: "lectura"))
        XCTAssertEqual(
            SupportMeasureImportGuard.existingLoadFailure,
            "No se pudieron leer las medidas ya guardadas. No se ha importado nada para no duplicarlas."
        )
    }

    func testSituationScheduleDoesNotInventSessions() {
        XCTAssertEqual(
            LearningSituationScheduleLoad.linksFailure,
            "No se pudieron cargar las clases de la situación. No se ha colocado en ningún grupo."
        )
        XCTAssertEqual(
            LearningSituationScheduleLoad.sequenceFailure,
            "No se pudo cargar la secuencia. No se han inventado sesiones."
        )
    }

    func testTeachingUnitsStayWhenTheLoadFails() {
        XCTAssertEqual(
            TeachingUnitReload.failureMessage,
            "No se pudieron cargar las unidades. Se mantiene la lista anterior."
        )
        XCTAssertEqual(
            ProfileReloadKeep.list(loaded: nil as [String]?, previous: ["Juegos"], samePerson: true),
            ["Juegos"]
        )
    }

    func testDataManagementKeepsTheListWhenTheLoadFails() {
        XCTAssertEqual(
            DataManagementReload.notebookFailure,
            "No se pudo cargar el cuaderno. Se mantiene la lista anterior."
        )
        XCTAssertEqual(
            DataManagementReload.situationsFailure,
            "No se pudieron cargar las situaciones. Se mantiene la lista anterior."
        )
    }

    func testNotebookSignalsStayWhenTheReloadFails() {
        XCTAssertEqual(
            NotebookSignalsReload.map(loaded: nil as [Int: String]?, previous: [4: "PRESENTE"], sameClass: true),
            [4: "PRESENTE"]
        )
        XCTAssertEqual(
            NotebookSignalsReload.map(loaded: nil as [Int: String]?, previous: [4: "PRESENTE"], sameClass: false),
            [:]
        )
        XCTAssertEqual(
            NotebookSignalsReload.ids(loaded: nil as Set<Int>?, previous: [7], sameClass: true),
            [7]
        )
    }

    func testEvaluationReloadKeepsTheSameClass() {
        XCTAssertEqual(
            EvaluationHubView.reloadFailureMessage,
            "No se pudieron cargar las evaluaciones. Se mantiene lo que ya ves."
        )
        XCTAssertEqual(
            ProfileReloadKeep.list(loaded: nil as [String]?, previous: ["Examen"], samePerson: true),
            ["Examen"]
        )
        XCTAssertEqual(
            ProfileReloadKeep.list(loaded: nil as [String]?, previous: ["Examen"], samePerson: false),
            []
        )
    }

    func testProfileReloadKeepsTheSameStudentAndClearsAnother() {
        XCTAssertEqual(
            ProfileReloadKeep.list(loaded: nil as [String]?, previous: ["Lectura"], samePerson: true),
            ["Lectura"]
        )
        XCTAssertEqual(
            ProfileReloadKeep.list(loaded: nil as [String]?, previous: ["Lectura"], samePerson: false),
            []
        )
        XCTAssertEqual(ProfileReloadKeep.snapshot(loaded: nil as String?, previous: "Ana", samePerson: true), "Ana")
        XCTAssertNil(ProfileReloadKeep.snapshot(loaded: nil as String?, previous: "Ana", samePerson: false))
    }

    func testInjurySaveFailureDoesNotPretendTheStateChanged() {
        XCTAssertEqual(
            StudentProfile360Sheet.injurySaveFailureMessage,
            "No se pudo guardar la lesión. El estado no ha cambiado."
        )
    }

    func testAttendanceReloadFailureKeepsVisibleMarks() {
        XCTAssertEqual(
            AttendanceLogic.reloadFailureMessage,
            "No se pudo cargar la asistencia. Se mantienen las marcas que ya ves."
        )
        XCTAssertEqual(
            AttendanceLogic.listAfterFailedReload(nil as [String]?, previous: ["Ana"]),
            ["Ana"]
        )
        XCTAssertEqual(
            AttendanceLogic.listAfterFailedReload(["Luis"], previous: ["Ana"]),
            ["Luis"]
        )
    }

    func testAttendanceMatrixSearchFiltersNamesAndCountsEagerCells() {
        XCTAssertTrue(AttendanceMatrixSearch.nameMatches("Ana Ruiz", query: "ana"))
        XCTAssertTrue(AttendanceMatrixSearch.nameMatches("Ana Ruiz", query: "  "))
        XCTAssertFalse(AttendanceMatrixSearch.nameMatches("Ana Ruiz", query: "luis"))
        XCTAssertEqual(
            AttendanceMatrixSearch.filteredFullNames(["Ana Ruiz", "Luis Pérez", "María Ana"], query: "ana"),
            ["Ana Ruiz", "María Ana"]
        )
        XCTAssertEqual(
            AttendanceMatrixSearch.eagerCellCount(studentCount: 30, dateCount: 100),
            3000
        )
        XCTAssertEqual(
            AttendanceMatrixSearch.eagerCellCount(studentCount: 0, dateCount: 40),
            0
        )
    }

    func testPhysicalTestsHistoryFiltersAndCountsEagerRows() {
        let rows: [(definitionId: String?, recordedCount: Int, resultCount: Int)] = [
            ("navette", 20, 25),
            ("jump", 25, 25),
            ("speed", 0, 25),
            ("navette", 10, 10),
        ]
        XCTAssertTrue(
            PhysicalTestsHistoryList.matches(
                definitionId: "jump",
                recordedCount: 25,
                resultCount: 25,
                definitionFilter: nil,
                completion: .completed
            )
        )
        XCTAssertFalse(
            PhysicalTestsHistoryList.matches(
                definitionId: "jump",
                recordedCount: 10,
                resultCount: 25,
                definitionFilter: nil,
                completion: .completed
            )
        )
        XCTAssertEqual(
            PhysicalTestsHistoryList.filteredProgressCounts(
                rows: rows,
                definitionFilter: "navette",
                completion: .all
            ),
            2
        )
        XCTAssertEqual(
            PhysicalTestsHistoryList.filteredProgressCounts(
                rows: rows,
                definitionFilter: nil,
                completion: .pending
            ),
            2
        )
        XCTAssertEqual(
            PhysicalTestsHistoryList.eagerRowCount(filteredTestCount: 40),
            40
        )
        XCTAssertEqual(
            PhysicalTestsHistoryList.eagerRowCount(filteredTestCount: -3),
            0
        )
    }

    func testOperationalSaveFailureStaysOnScreen() {
        XCTAssertEqual(
            EditPESessionOperationalSheet.saveFailureMessage,
            "No se pudo guardar la operativa de la sesión. Los datos siguen en esta pantalla."
        )
    }

    func testSchoolYearBoundsStayInsideOneCourse() {
        let autumn = DiaryContinuousTimelineView.schoolYearIsoBounds(year: 2026, month: 9)
        XCTAssertEqual(autumn.start, "2026-09-01")
        XCTAssertEqual(autumn.end, "2027-06-30")
        let winter = DiaryContinuousTimelineView.schoolYearIsoBounds(year: 2026, month: 1)
        XCTAssertEqual(winter.start, "2025-09-01")
        XCTAssertEqual(winter.end, "2026-06-30")
    }

    func testDiarySearchUsesSettledTextNotLiveKeystrokes() {
        XCTAssertEqual(
            DiaryTimelineSearch.queryForFeed(liveText: "calent", settledText: "cal"),
            "cal"
        )
        XCTAssertEqual(
            DiaryTimelineSearch.queryForFeed(liveText: "  salto  ", settledText: "  salto  "),
            "salto"
        )
        XCTAssertEqual(DiaryTimelineSearch.debounceNanoseconds, 200_000_000)
    }

    func testStudentListSearchUsesSettledTextNotLiveKeystrokes() {
        XCTAssertEqual(
            StudentListSearch.queryForList(liveText: "mar", settledText: ""),
            ""
        )
        XCTAssertEqual(
            StudentListSearch.queryForList(liveText: "mar", settledText: " mar "),
            "mar"
        )
        XCTAssertEqual(StudentListSearch.debounceNanoseconds, 200_000_000)
    }

    func testStudentEditorSaveKeepsSheetOpenOnFailure() {
        XCTAssertFalse(StudentEditorSaveGate.shouldDismiss(succeeded: false))
        XCTAssertTrue(StudentEditorSaveGate.shouldDismiss(succeeded: true))
        XCTAssertEqual(
            StudentEditorSaveGate.saveFailureMessage,
            "No se pudo guardar los datos del alumno. Los cambios siguen en esta pantalla."
        )
        XCTAssertTrue(
            StudentEditorSaveGate.failureMessage(detail: "disco lleno")
                .contains("disco lleno")
        )
        XCTAssertEqual(
            StudentEditorSaveGate.failureMessage(detail: "  "),
            StudentEditorSaveGate.saveFailureMessage
        )
    }

    func testAssignRubricSaveKeepsSheetOpenOnFailure() {
        XCTAssertFalse(AssignRubricSaveGate.shouldDismiss(succeeded: false))
        XCTAssertTrue(AssignRubricSaveGate.shouldDismiss(succeeded: true))
        XCTAssertEqual(
            AssignRubricSaveGate.saveFailureMessage,
            "No se pudo asignar la rúbrica al cuaderno. Los datos siguen en esta pantalla."
        )
        XCTAssertTrue(
            AssignRubricSaveGate.failureMessage(detail: "pestaña no encontrada")
                .contains("pestaña no encontrada")
        )
        XCTAssertEqual(
            AssignRubricSaveGate.failureMessage(detail: "  "),
            AssignRubricSaveGate.saveFailureMessage
        )
    }

    func testAttendanceMatrixSaveShowsFailureInSpanish() {
        XCTAssertEqual(
            AttendanceMatrixSaveGate.saveFailureMessage,
            "No se pudo guardar la asistencia. Pulsa otra vez para reintentar."
        )
        XCTAssertTrue(
            AttendanceMatrixSaveGate.failureMessage(detail: "disco lleno")
                .contains("disco lleno")
        )
        XCTAssertEqual(
            AttendanceMatrixSaveGate.failureMessage(detail: "  "),
            AttendanceMatrixSaveGate.saveFailureMessage
        )
    }

    func testNotebookFollowUpSaveShowsFailureInSpanish() {
        XCTAssertEqual(
            NotebookFollowUpSaveGate.saveFailureMessage,
            "No se pudo crear el seguimiento. Pulsa otra vez para reintentar."
        )
        XCTAssertTrue(
            NotebookFollowUpSaveGate.failureMessage(detail: "disco lleno")
                .contains("disco lleno")
        )
        XCTAssertEqual(
            NotebookFollowUpSaveGate.failureMessage(detail: "  "),
            NotebookFollowUpSaveGate.saveFailureMessage
        )
    }

    func testNotebookColumnDeleteShowsFailureInSpanish() {
        XCTAssertEqual(
            NotebookColumnDeleteGate.toastMessage(succeeded: true),
            "Columna eliminada"
        )
        XCTAssertEqual(
            NotebookColumnDeleteGate.toastMessage(succeeded: false),
            NotebookColumnDeleteGate.saveFailureMessage
        )
        XCTAssertEqual(
            NotebookColumnDeleteGate.saveFailureMessage,
            "No se pudo eliminar la columna. Pulsa otra vez para reintentar."
        )
        XCTAssertTrue(
            NotebookColumnDeleteGate.failureMessage(detail: "disco lleno")
                .contains("disco lleno")
        )
        XCTAssertEqual(
            NotebookColumnDeleteGate.failureMessage(detail: "  "),
            NotebookColumnDeleteGate.saveFailureMessage
        )
    }

    func testNotebookColumnsBulkDeleteOutcomeMessages() {
        XCTAssertEqual(
            NotebookColumnDeleteGate.bulkOutcome(succeeded: 3, failed: 0),
            .success(deleted: 3)
        )
        XCTAssertEqual(
            NotebookColumnDeleteGate.bulkToastMessage(.success(deleted: 3)),
            "3 columnas eliminadas"
        )
        XCTAssertEqual(
            NotebookColumnDeleteGate.bulkToastMessage(.success(deleted: 1)),
            "Columna eliminada"
        )

        XCTAssertEqual(
            NotebookColumnDeleteGate.bulkOutcome(succeeded: 2, failed: 1),
            .partial(deleted: 2, failed: 1)
        )
        let partial = NotebookColumnDeleteGate.bulkToastMessage(.partial(deleted: 2, failed: 1))
        XCTAssertTrue(partial.contains("2"))
        XCTAssertTrue(partial.contains("1"))
        XCTAssertTrue(partial.contains("siguen en pantalla"))
        XCTAssertFalse(partial.contains("3 columnas eliminadas"))

        XCTAssertEqual(
            NotebookColumnDeleteGate.bulkOutcome(succeeded: 0, failed: 4),
            .failure(failed: 4)
        )
        XCTAssertEqual(
            NotebookColumnDeleteGate.bulkToastMessage(.failure(failed: 4)),
            NotebookColumnDeleteGate.bulkFailureMessage
        )
        XCTAssertEqual(
            NotebookColumnDeleteGate.bulkFailureMessage,
            "No se pudieron eliminar las columnas. Pulsa otra vez para reintentar."
        )
    }

    func testSyncLanCancelAffordancesOfferOnlyWhileSyncing() {
        XCTAssertTrue(
            SyncLanCancelAffordances.shouldOfferCancel(statusMessage: "Sincronizando…")
        )
        XCTAssertTrue(
            SyncLanCancelAffordances.shouldOfferCancel(statusMessage: "  sincronizando con el Mac  ")
        )
        XCTAssertTrue(
            SyncLanCancelAffordances.shouldOfferCancel(statusMessage: "Sincronizando 3 de 12")
        )
        XCTAssertFalse(
            SyncLanCancelAffordances.shouldOfferCancel(statusMessage: "Sincronización cancelada")
        )
        XCTAssertFalse(
            SyncLanCancelAffordances.shouldOfferCancel(statusMessage: "Pull OK (3 cambios)")
        )
        XCTAssertEqual(
            SyncLanCancelAffordances.cancelledStatusMessage,
            "Sincronización cancelada"
        )
        XCTAssertEqual(SyncLanCancelAffordances.buttonTitle, "Cancelar")
    }

    func testSyncLanApplyProgressCopyShowsIndexOfTotal() {
        XCTAssertEqual(
            SyncLanApplyProgressCopy.statusMessage(hechos: 0, total: 0),
            "Sincronizando…"
        )
        XCTAssertEqual(
            SyncLanApplyProgressCopy.statusMessage(hechos: 3, total: 12),
            "Sincronizando 3 de 12"
        )
        XCTAssertEqual(
            SyncLanApplyProgressCopy.statusMessage(hechos: 1, total: 1),
            "Sincronizando 1 de 1"
        )
    }

    func testSyncLanApplyProgressCopyPublishesFirstLastAndEveryTenth() {
        XCTAssertTrue(SyncLanApplyProgressCopy.shouldPublishProgress(hechos: 1, total: 12))
        XCTAssertFalse(SyncLanApplyProgressCopy.shouldPublishProgress(hechos: 3, total: 12))
        XCTAssertTrue(SyncLanApplyProgressCopy.shouldPublishProgress(hechos: 10, total: 12))
        XCTAssertTrue(SyncLanApplyProgressCopy.shouldPublishProgress(hechos: 12, total: 12))
        XCTAssertTrue(SyncLanApplyProgressCopy.shouldPublishProgress(hechos: 1, total: 1))
        XCTAssertFalse(SyncLanApplyProgressCopy.shouldPublishProgress(hechos: 0, total: 12))
        XCTAssertFalse(SyncLanApplyProgressCopy.shouldPublishProgress(hechos: 1, total: 0))
    }

    func testSyncLanApplyCloseIsNotSuccessWhenAnyChangeFailed() {
        XCTAssertTrue(SyncLanApplyCloseCopy.isSuccessfulClose(failedCount: 0))
        XCTAssertFalse(SyncLanApplyCloseCopy.isSuccessfulClose(failedCount: 1))
        XCTAssertFalse(SyncLanApplyCloseCopy.isSuccessfulClose(failedCount: 3))

        let oneFailed = SyncLanApplyCloseCopy.failureStatusMessage(failedCount: 1, total: 12)
        XCTAssertTrue(oneFailed.contains("1 de 12"))
        XCTAssertTrue(oneFailed.contains("Fallo al aplicar"))
        XCTAssertTrue(oneFailed.contains("El resto sí se guardó"))
        XCTAssertFalse(oneFailed.contains("Pull OK"))
        XCTAssertFalse(oneFailed.contains("Sincronizado"))

        let severalFailed = SyncLanApplyCloseCopy.failureStatusMessage(failedCount: 3, total: 12)
        XCTAssertTrue(severalFailed.contains("3 de 12"))
        XCTAssertTrue(severalFailed.contains("Fallo al aplicar"))

        let hero = SyncLanHeroCopy.snapshot(
            isPaired: true,
            pendingChanges: 0,
            statusMessage: severalFailed
        )
        XCTAssertEqual(hero.kind, .error)
        XCTAssertEqual(hero.title, "Fallo al sincronizar")
        XCTAssertNotEqual(hero.title, "Sincronizado")
        XCTAssertNotEqual(hero.detail, "Al día con el Mac.")
    }

    func testSyncLanPushPendingKeepsFailedSentChanges() {
        XCTAssertTrue(
            SyncLanPushPendingPolicy.shouldClearSentPending(failed: 0, desktopAuthoritative: false)
        )
        XCTAssertFalse(
            SyncLanPushPendingPolicy.shouldClearSentPending(failed: 1, desktopAuthoritative: false)
        )
        XCTAssertFalse(
            SyncLanPushPendingPolicy.shouldClearSentPending(failed: 3, desktopAuthoritative: false)
        )
        XCTAssertTrue(
            SyncLanPushPendingPolicy.shouldClearSentPending(failed: 2, desktopAuthoritative: true)
        )
    }

    func testSyncLanPushCloseIsNotSuccessWhenAckReportsFailures() {
        let ok = SyncLanPushCloseCopy.statusMessage(
            applied: 4,
            failed: 0,
            sentTotal: 4,
            desktopAuthoritative: false
        )
        XCTAssertEqual(ok, "Push OK (4 aplicados)")

        let oneFailed = SyncLanPushCloseCopy.statusMessage(
            applied: 11,
            failed: 1,
            sentTotal: 12,
            desktopAuthoritative: false
        )
        XCTAssertEqual(
            oneFailed,
            SyncLanApplyCloseCopy.failureStatusMessage(failedCount: 1, total: 12)
        )
        XCTAssertFalse(oneFailed.contains("Push OK"))
        XCTAssertFalse(oneFailed.contains("Sincronizado"))

        let severalFailed = SyncLanPushCloseCopy.statusMessage(
            applied: 9,
            failed: 3,
            sentTotal: 12,
            desktopAuthoritative: false
        )
        XCTAssertTrue(severalFailed.contains("Fallo al aplicar"))
        XCTAssertFalse(severalFailed.contains("Push OK"))

        let hero = SyncLanHeroCopy.snapshot(
            isPaired: true,
            pendingChanges: 0,
            statusMessage: severalFailed
        )
        XCTAssertEqual(hero.kind, .error)
        XCTAssertEqual(hero.title, "Fallo al sincronizar")
        XCTAssertNotEqual(hero.title, "Sincronizado")
        XCTAssertNotEqual(hero.detail, "Al día con el Mac.")

        let authoritative = SyncLanPushCloseCopy.statusMessage(
            applied: 0,
            failed: 2,
            sentTotal: 2,
            desktopAuthoritative: true
        )
        XCTAssertEqual(authoritative, "macOS prevalece; cambios locales descartados")
    }

    func testSyncLanHeroDoesNotDisguiseErrorsAsSyncedOrMuteUnpaired() {
        let unpairedIdle = SyncLanHeroCopy.snapshot(
            isPaired: false,
            pendingChanges: 0,
            statusMessage: ""
        )
        XCTAssertEqual(unpairedIdle.kind, .unpaired)
        XCTAssertEqual(unpairedIdle.title, "Sin enlace con Mac")
        XCTAssertEqual(unpairedIdle.detail, SyncLanHeroCopy.unpairedIdleDetail)

        let pairError = SyncLanHeroCopy.snapshot(
            isPaired: false,
            pendingChanges: 0,
            statusMessage: "Error emparejando: red local"
        )
        XCTAssertEqual(pairError.kind, .error)
        XCTAssertEqual(pairError.title, "No se pudo enlazar")
        XCTAssertTrue(pairError.detail.contains("Error emparejando"))

        let syncError = SyncLanHeroCopy.snapshot(
            isPaired: true,
            pendingChanges: 0,
            statusMessage: "Error push: timeout"
        )
        XCTAssertEqual(syncError.kind, .error)
        XCTAssertEqual(syncError.title, "Fallo al sincronizar")
        XCTAssertNotEqual(syncError.title, "Sincronizado")

        let syncing = SyncLanHeroCopy.snapshot(
            isPaired: true,
            pendingChanges: 0,
            statusMessage: "Sincronizando…"
        )
        XCTAssertEqual(syncing.kind, .syncing)
        XCTAssertEqual(syncing.title, "Sincronizando…")

        let pending = SyncLanHeroCopy.snapshot(
            isPaired: true,
            pendingChanges: 3,
            statusMessage: ""
        )
        XCTAssertEqual(pending.kind, .pending)
        XCTAssertEqual(pending.title, "Cambios pendientes")
        XCTAssertTrue(pending.detail.contains("3 cambios"))

        let synced = SyncLanHeroCopy.snapshot(
            isPaired: true,
            pendingChanges: 0,
            statusMessage: ""
        )
        XCTAssertEqual(synced.kind, .synced)
        XCTAssertEqual(synced.title, "Sincronizado")
        XCTAssertEqual(synced.detail, "Al día con el Mac.")
    }

    func testRepeatSaveSummaryShowsCreatedAndFailed() {
        XCTAssertEqual(
            PlannerWorkspaceViewModel.repeatSaveSummary(created: 1, failed: 2),
            "Creadas 1 / fallidas 2"
        )
    }

    func testTemplateSaveFailureKeepsComposerVisible() {
        XCTAssertEqual(
            PlannerWorkspaceViewModel.templateSaveFailureMessage,
            "No se pudo guardar la plantilla. Sigue en esta pantalla."
        )
    }

    func testSessionJournalQuickNoteKeepsTextOnFailure() {
        XCTAssertFalse(SessionJournalQuickNoteSaveGate.shouldClearDraft(succeeded: false))
        XCTAssertTrue(SessionJournalQuickNoteSaveGate.shouldClearDraft(succeeded: true))
        XCTAssertEqual(
            SessionJournalQuickNoteSaveGate.saveFailureMessage,
            "No se pudo guardar la nota del diario. El texto sigue en esta pantalla."
        )
        XCTAssertTrue(
            SessionJournalQuickNoteSaveGate.failureMessage(detail: "disco lleno")
                .contains("disco lleno")
        )
        XCTAssertEqual(
            SessionJournalQuickNoteSaveGate.failureMessage(detail: "  "),
            SessionJournalQuickNoteSaveGate.saveFailureMessage
        )
    }

    func testStudentEnrollmentKeepsSheetOpenOnFailure() {
        XCTAssertFalse(StudentEnrollmentSaveGate.shouldDismiss(succeeded: false))
        XCTAssertTrue(StudentEnrollmentSaveGate.shouldDismiss(succeeded: true))
        XCTAssertEqual(
            StudentEnrollmentSaveGate.saveFailureMessage,
            "No se pudo matricular al alumno en el grupo. Sigue sin asignar."
        )
        XCTAssertTrue(
            StudentEnrollmentSaveGate.failureMessage(detail: "disco lleno")
                .contains("disco lleno")
        )
        XCTAssertEqual(
            StudentEnrollmentSaveGate.failureMessage(detail: "  "),
            StudentEnrollmentSaveGate.saveFailureMessage
        )
    }

    func testPEIncidentSaveKeepsSheetOpenOnFailure() {
        XCTAssertFalse(PEIncidentSaveGate.shouldDismiss(succeeded: false))
        XCTAssertTrue(PEIncidentSaveGate.shouldDismiss(succeeded: true))
        XCTAssertEqual(
            PEIncidentSaveGate.saveFailureMessage,
            "No se pudo guardar la incidencia. Los datos siguen en esta pantalla."
        )
        XCTAssertTrue(
            PEIncidentSaveGate.failureMessage(detail: "disco lleno")
                .contains("disco lleno")
        )
        XCTAssertEqual(
            PEIncidentSaveGate.failureMessage(detail: "  "),
            PEIncidentSaveGate.saveFailureMessage
        )
    }

    func testRepeatTargetKeepsWeek53Of2026() {
        let next = PlannerWorkspaceViewModel.repeatTarget(startWeek: 52, startYear: 2026, offset: 1)
        XCTAssertEqual(next.week, 53)
        XCTAssertEqual(next.year, 2026)
        let afterLast = PlannerWorkspaceViewModel.repeatTarget(startWeek: 53, startYear: 2026, offset: 1)
        XCTAssertEqual(afterLast.week, 1)
        XCTAssertEqual(afterLast.year, 2027)
    }

    func testClassroomCaptureQueryUsesLocalCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 25
        components.hour = 15
        components.minute = 30
        let date = calendar.date(from: components)!
        XCTAssertEqual(ClassroomCaptureQuery.dayIso(for: date, calendar: calendar), "2026-09-25")
    }

    func testLanLocalNotifyRequiresBearerAndShowsFailureCopy() {
        XCTAssertFalse(LanLocalNotifyPolicy.shouldAttachBearer(token: nil))
        XCTAssertFalse(LanLocalNotifyPolicy.shouldAttachBearer(token: ""))
        XCTAssertTrue(LanLocalNotifyPolicy.shouldAttachBearer(token: "paired-secret"))
        XCTAssertEqual(
            LanLocalNotifyPolicy.authorizationHeaderValue(token: "paired-secret"),
            "Bearer paired-secret"
        )
        XCTAssertEqual(
            LanLocalNotifyPolicy.failureStatusMessage,
            "Aviso local LAN fallido. El iPad puede no enterarse al momento."
        )
    }

    func testLanSyncPayloadParserDictionaryFromJsonString() {
        let object = LanSyncPayloadParser.dictionary(from: #"{"id":7,"name":"Grupo A"}"#)
        XCTAssertEqual((object["id"] as? NSNumber)?.intValue, 7)
        XCTAssertEqual(object["name"] as? String, "Grupo A")
        XCTAssertTrue(LanSyncPayloadParser.dictionary(from: "no-es-json").isEmpty)
        XCTAssertTrue(LanSyncPayloadParser.dictionary(from: "[1,2]").isEmpty)
    }
}
