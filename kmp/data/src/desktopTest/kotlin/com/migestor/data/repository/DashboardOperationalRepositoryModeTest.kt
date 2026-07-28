package com.migestor.data.repository

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.shared.domain.DashboardFilters
import com.migestor.shared.domain.DashboardMode
import com.migestor.shared.domain.DashboardSessionContextStatus
import com.migestor.shared.domain.TeacherScheduleSlot
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.Clock
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.isoDayNumber
import kotlinx.datetime.toLocalDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * El modo del dashboard era decorativo: `getSnapshot` recibía `DashboardMode` y
 * solo lo copiaba al snapshot devuelto, así que Clase y Despacho producían
 * exactamente los mismos datos. Estas pruebas fijan la diferencia real: alcance
 * (cuántos grupos) y horizonte (cuánto trabajo acumulado).
 */
class DashboardOperationalRepositoryModeTest {

    private class Fixture(
        val repository: DashboardOperationalRepositoryDefault,
        val classAId: Long,
        val classBId: Long,
    )

    private suspend fun buildFixture(): Fixture {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)

        val classes = ClassesRepositorySqlDelight(db)
        val students = StudentsRepositorySqlDelight(db)
        val attendance = AttendanceRepositorySqlDelight(db)
        val evaluations = EvaluationsRepositorySqlDelight(db)
        val grades = GradesRepositorySqlDelight(db)
        val notebookConfig = NotebookConfigRepositorySqlDelight(db)
        val incidents = IncidentsRepositorySqlDelight(db)
        val calendar = CalendarRepositorySqlDelight(db)
        val planner = PlannerRepositorySqlDelight(db)
        val rubrics = RubricsRepositorySqlDelight(db)
        val journals = SessionJournalRepositorySqlDelight(db)
        val teacherSchedule = TeacherScheduleRepositorySqlDelight(
            db = db,
            plannerRepository = planner,
            calendarRepository = calendar,
            classesRepository = classes,
        )

        val classAId = classes.saveClass(name = "3 ESO A", course = 3, description = null)
        val classBId = classes.saveClass(name = "4 ESO B", course = 4, description = null)

        // Un alumno con faltas suficientes en cada grupo: genera una alerta de
        // severidad alta por grupo, que es lo que permite comprobar el alcance.
        val nowMs = Clock.System.now().toEpochMilliseconds()
        listOf(classAId, classBId).forEachIndexed { index, classId ->
            val studentId = students.saveStudent(
                firstName = "Alumno$index",
                lastName = "Faltas",
                email = null,
            )
            classes.addStudentToClass(classId, studentId)
            repeat(4) { day ->
                attendance.saveAttendance(
                    studentId = studentId,
                    classId = classId,
                    dateEpochMs = nowMs - day * 24L * 60L * 60L * 1000L,
                    status = "ausente",
                    updatedAtEpochMs = nowMs,
                )
            }
        }

        // Horario del profesor con una franja de todo el día en el grupo A, para
        // que el contexto resuelva "clase en curso" sea cual sea la hora a la
        // que se ejecute la prueba.
        val today = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
        val baseSchedule = teacherSchedule.getOrCreatePrimarySchedule()
        val scheduleId = teacherSchedule.saveSchedule(
            baseSchedule.copy(
                startDateIso = today.minusYearsIso(1),
                endDateIso = today.plusYearsIso(1),
                activeWeekdaysCsv = "1,2,3,4,5,6,7",
            )
        )
        teacherSchedule.saveScheduleSlot(
            TeacherScheduleSlot(
                teacherScheduleId = scheduleId,
                schoolClassId = classAId,
                subjectLabel = "Educación Física",
                dayOfWeek = today.dayOfWeekIso(),
                startTime = "00:00",
                endTime = "23:59",
            )
        )

        return Fixture(
            repository = DashboardOperationalRepositoryDefault(
                classesRepository = classes,
                attendanceRepository = attendance,
                evaluationsRepository = evaluations,
                gradesRepository = grades,
                notebookConfigRepository = notebookConfig,
                incidentsRepository = incidents,
                calendarRepository = calendar,
                plannerRepository = planner,
                rubricsRepository = rubrics,
                teacherScheduleRepository = teacherSchedule,
                sessionJournalRepository = journals,
            ),
            classAId = classAId,
            classBId = classBId,
        )
    }

    private fun today(): LocalDate =
        Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date

    @Test
    fun `el contexto resuelve la clase en curso desde el horario del profesor`() = runTest {
        val fixture = buildFixture()

        val snapshot = fixture.repository.getSnapshot(
            date = today(),
            mode = DashboardMode.OFFICE,
            filters = DashboardFilters(),
        )

        val context = assertNotNull(snapshot.currentContext)
        assertEquals(DashboardSessionContextStatus.ACTIVE, context.status)
        assertEquals(fixture.classAId, context.classId)
        assertEquals("3 ESO A", context.className)
    }

    @Test
    fun `modo Clase se limita al grupo que se esta impartiendo`() = runTest {
        val fixture = buildFixture()

        val classroom = fixture.repository.getSnapshot(
            date = today(),
            mode = DashboardMode.CLASSROOM,
            filters = DashboardFilters(),
        )

        assertTrue(classroom.alerts.isNotEmpty(), "Clase debe conservar los avisos del grupo en curso")
        assertTrue(
            classroom.alerts.all { it.classId == fixture.classAId },
            "Clase no puede mezclar avisos de otros grupos: ${classroom.alerts.map { it.classId }}"
        )
    }

    @Test
    fun `modo Despacho abarca todos los grupos y modo Clase no`() = runTest {
        val fixture = buildFixture()

        val office = fixture.repository.getSnapshot(
            date = today(),
            mode = DashboardMode.OFFICE,
            filters = DashboardFilters(),
        )
        val classroom = fixture.repository.getSnapshot(
            date = today(),
            mode = DashboardMode.CLASSROOM,
            filters = DashboardFilters(),
        )

        assertEquals(
            setOf(fixture.classAId, fixture.classBId),
            office.alerts.mapNotNull { it.classId }.toSet(),
            "Despacho debe seguir viendo los dos grupos"
        )
        assertEquals(2, office.groupSummaries.size, "Despacho conserva el resumen por grupo")
        assertTrue(classroom.groupSummaries.isEmpty(), "Clase no calcula el resumen por grupo")
        assertTrue(
            office.alerts.size > classroom.alerts.size,
            "Los dos modos ya no pueden devolver lo mismo: ${office.alerts.size} vs ${classroom.alerts.size}"
        )
    }

    @Test
    fun `modo Clase deja fuera los avisos que no son urgentes`() = runTest {
        val fixture = buildFixture()

        val classroom = fixture.repository.getSnapshot(
            date = today(),
            mode = DashboardMode.CLASSROOM,
            filters = DashboardFilters(),
        )

        assertTrue(
            classroom.alerts.all { it.severity.equals("high", true) || it.priority.equals("high", true) },
            "Clase solo admite lo urgente: ${classroom.alerts.map { it.severity to it.priority }}"
        )
    }
}

private fun LocalDate.dayOfWeekIso(): Int = dayOfWeek.isoDayNumber

private fun LocalDate.minusYearsIso(years: Int): String = "${year - years}-01-01"

private fun LocalDate.plusYearsIso(years: Int): String = "${year + years}-12-31"
