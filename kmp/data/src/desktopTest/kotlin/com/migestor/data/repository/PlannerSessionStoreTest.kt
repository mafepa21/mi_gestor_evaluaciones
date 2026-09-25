package com.migestor.data.repository

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.platform.runRescueMigrations
import com.migestor.shared.domain.PlannedSession
import com.migestor.shared.domain.PlanningSession
import com.migestor.shared.domain.SessionCascadeMoveRequest
import com.migestor.shared.domain.SessionStatus
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertTrue

class PlannerSessionStoreTest {
    @Test
    fun `actualizar por id no pisa la sesion del hueco ocupado`() = runTest {
        val planner = planner()
        val classId = planner.classes.saveClass(name = "1 ESO A", course = 1, description = null)
        val first = planner.repo.upsertSession(session(classId, period = 1, objectives = "Primera"))
        val second = planner.repo.upsertSession(session(classId, period = 2, objectives = "Segunda"))

        assertFails {
            planner.repo.upsertSession(
                session(classId, period = 2, objectives = "Robo").copy(id = first)
            )
        }

        val saved = planner.repo.listSessions(weekNumber = 12, year = 2026).associateBy { it.id }
        assertEquals(1, saved.getValue(first).period)
        assertEquals("Primera", saved.getValue(first).objectives)
        assertEquals(2, saved.getValue(second).period)
        assertEquals("Segunda", saved.getValue(second).objectives)
    }

    @Test
    fun `una sesion nueva en un hueco ocupado actualiza esa fila`() = runTest {
        val planner = planner()
        val classId = planner.classes.saveClass(name = "1 ESO B", course = 1, description = null)
        val existing = planner.repo.upsertSession(session(classId, period = 2, objectives = "Vieja"))

        val savedId = planner.repo.upsertSession(session(classId, period = 2, objectives = "Fusionada"))

        assertEquals(existing, savedId)
        val saved = planner.repo.listSessions(weekNumber = 12, year = 2026).single()
        assertEquals(existing, saved.id)
        assertEquals("Fusionada", saved.objectives)
        assertEquals(SessionStatus.PLANNED, saved.status)
    }

    @Test
    fun `la migracion pasa PENDING a PLANNED y copia solo las horas conocidas`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)
        val classes = ClassesRepositorySqlDelight(db)
        val planned = PlannedSessionRepositorySqlDelight(db)
        val classId = classes.saveClass(name = "2 ESO A", course = 2, description = null)

        driver.execute(
            null,
            """
            INSERT INTO planner_session(
                date, group_id, period, objectives, activities, evaluation, status, linked_assessment_ids_csv
            ) VALUES
                ('2026-04-07', $classId, 2, 'Ya escrito', 'lleno', 'lleno', 'PENDING', ''),
                ('2026-04-08', $classId, 1, 'Sigue', '', '', 'PENDING', '')
            """.trimIndent(),
            0,
        )
        planned.insert(
            PlannedSession(
                teachingUnitId = null,
                schoolClassId = classId,
                date = LocalDate.parse("2026-04-07"),
                startTime = "09:00",
                endTime = "10:00",
                title = "Titulo",
                objectives = "Otra",
                resources = "Balones",
                notes = "Nota vieja",
            )
        )
        planned.insert(
            PlannedSession(
                teachingUnitId = null,
                schoolClassId = classId,
                date = LocalDate.parse("2026-04-09"),
                startTime = "09:00",
                endTime = "10:00",
                title = "Titulo nuevo",
                objectives = "Desde UD",
                resources = "Conos",
                notes = "Nueva",
            )
        )
        planned.insert(
            PlannedSession(
                teachingUnitId = null,
                schoolClassId = classId,
                date = LocalDate.parse("2026-04-10"),
                startTime = "07:15",
                endTime = "08:00",
                title = "Hora rara",
                objectives = "No encaja",
            )
        )

        val latest = AppDatabase.Schema.version
        AppDatabase.Schema.migrate(driver, latest - 1, latest)
        runRescueMigrations(driver)

        assertEquals(
            "'PLANNED'",
            driver.queryStrings(
                "SELECT dflt_value FROM pragma_table_info('planner_session') WHERE name = 'status'"
            ).single(),
        )
        val sessions = PlannerRepositorySqlDelight(db)
            .listSessionsInRange(classId, LocalDate.parse("2026-04-07"), LocalDate.parse("2026-04-10"))
            .associateBy { it.dayOfWeek to it.period }
        val occupied = sessions.getValue(2 to 2)
        assertEquals("Ya escrito", occupied.objectives)
        assertEquals("lleno", occupied.activities)
        assertEquals("lleno", occupied.evaluation)
        assertEquals(SessionStatus.PLANNED, occupied.status)
        assertEquals(SessionStatus.PLANNED, sessions.getValue(3 to 1).status)
        assertEquals("Sigue", sessions.getValue(3 to 1).objectives)
        val copied = sessions.getValue(4 to 2)
        assertEquals("Desde UD", copied.objectives)
        assertEquals("Nueva", copied.activities)
        assertEquals("Conos", copied.evaluation)
        assertEquals(SessionStatus.PLANNED, copied.status)
        assertTrue(sessions.none { it.value.objectives == "No encaja" })

        val leftovers = planned.listSessionsInRange(classId, LocalDate.parse("2026-04-07"), LocalDate.parse("2026-04-10"))
        assertEquals(listOf("07:15"), leftovers.map { it.startTime })
    }

    @Test
    fun `la cascada no mueve una sesion cancelada salvo que se fuerce`() = runTest {
        val planner = planner()
        val classId = planner.classes.saveClass(name = "3 ESO A", course = 3, description = null)
        val sourceId = planner.repo.upsertSession(session(classId, period = 1, objectives = "Origen"))
        val cancelledId = planner.repo.upsertSession(
            session(classId, period = 2, objectives = "Cancelada").copy(status = SessionStatus.CANCELLED)
        )
        val request = SessionCascadeMoveRequest(
            sourceSessionId = sourceId,
            targetWeekNumber = 12,
            targetYear = 2026,
            targetDayOfWeek = 2,
            targetPeriod = 2,
        )

        val preview = planner.repo.previewCascadeMove(request)
        assertEquals(listOf(cancelledId), preview.cancelledSessionIds)
        assertTrue(preview.nextPlacements.isEmpty())
        assertEquals(0, planner.repo.commitCascadeMove(request).movedCount)

        val forced = planner.repo.commitCascadeMove(request.copy(forceTerminalSessions = true))
        assertTrue(forced.movedCount >= 2)
        val moved = planner.repo.listSessions(weekNumber = 12, year = 2026).associateBy { it.id }
        assertEquals(2, moved.getValue(sourceId).period)
        assertTrue(moved.getValue(cancelledId).period != 2)
        assertEquals(SessionStatus.CANCELLED, moved.getValue(cancelledId).status)
    }

    private fun planner(): OpenPlanner {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)
        return OpenPlanner(ClassesRepositorySqlDelight(db), PlannerRepositorySqlDelight(db))
    }

    private fun session(classId: Long, period: Int, objectives: String) = PlanningSession(
        teachingUnitId = 0,
        teachingUnitName = "Unidad",
        groupId = classId,
        groupName = "Grupo",
        dayOfWeek = 2,
        period = period,
        weekNumber = 12,
        year = 2026,
        objectives = objectives,
        status = SessionStatus.PLANNED,
    )

    private data class OpenPlanner(
        val classes: ClassesRepositorySqlDelight,
        val repo: PlannerRepositorySqlDelight,
    )
}
