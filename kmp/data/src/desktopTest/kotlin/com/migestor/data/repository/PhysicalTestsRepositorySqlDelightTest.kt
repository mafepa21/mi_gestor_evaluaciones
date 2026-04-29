package com.migestor.data.repository

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.shared.domain.AuditTrace
import com.migestor.shared.domain.PhysicalCapacity
import com.migestor.shared.domain.PhysicalMeasurementKind
import com.migestor.shared.domain.PhysicalResultMode
import com.migestor.shared.domain.PhysicalScaleDirection
import com.migestor.shared.domain.PhysicalTestAssignment
import com.migestor.shared.domain.PhysicalTestAttempt
import com.migestor.shared.domain.PhysicalTestBattery
import com.migestor.shared.domain.PhysicalTestDefinition
import com.migestor.shared.domain.PhysicalTestNotebookLink
import com.migestor.shared.domain.PhysicalTestResult
import com.migestor.shared.domain.PhysicalTestScale
import com.migestor.shared.domain.PhysicalTestScaleRange
import com.migestor.shared.domain.resolvedPhysicalResult
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

class PhysicalTestsRepositorySqlDelightTest {
    @Test
    fun `resolvedPhysicalResult handles direction and result modes`() {
        assertEquals(5.8, resolvedPhysicalResult(listOf(5.8, 6.1), PhysicalScaleDirection.LOWER_IS_BETTER, PhysicalResultMode.BEST))
        assertEquals(6.1, resolvedPhysicalResult(listOf(5.8, 6.1), PhysicalScaleDirection.HIGHER_IS_BETTER, PhysicalResultMode.BEST))
        assertEquals(5.95, resolvedPhysicalResult(listOf(5.8, 6.1), PhysicalScaleDirection.HIGHER_IS_BETTER, PhysicalResultMode.AVERAGE)!!, 0.0001)
        assertEquals(6.1, resolvedPhysicalResult(listOf(5.8, 6.1), PhysicalScaleDirection.LOWER_IS_BETTER, PhysicalResultMode.LAST))
    }

    @Test
    fun `resolveScale uses exact match before fallback`() = runTest {
        val fixture = createFixture()
        fixture.seedDefinitionAndBattery()
        val generic = scale("generic", course = null, ageFrom = null, ageTo = null, batteryId = null)
        val course = scale("course", course = 1, ageFrom = null, ageTo = null, batteryId = null)
        val exact = scale("exact", course = 1, ageFrom = 12, ageTo = 13, batteryId = "battery")
        fixture.physical.saveScale(generic)
        fixture.physical.saveScale(course)
        fixture.physical.saveScale(exact)

        assertEquals("exact", fixture.physical.resolveScale("speed_30m", 1, 12, null, "battery")?.id)
        assertEquals("course", fixture.physical.resolveScale("speed_30m", 1, null, null, null)?.id)
        assertEquals("generic", fixture.physical.resolveScale("speed_30m", 2, null, null, null)?.id)
    }

    @Test
    fun `saveResult persists attempts and notebook links`() = runTest {
        val fixture = createFixture()
        val classId = fixture.classes.saveClass(name = "1 ESO A", course = 1, description = null)
        val studentId = fixture.students.saveStudent(firstName = "Ana", lastName = "Lopez", email = null)
        fixture.classes.addStudentToClass(classId, studentId)
        fixture.seedDefinitionAndBattery()
        fixture.physical.assignBatteryToClass(
            PhysicalTestAssignment(
                id = "assignment",
                batteryId = "battery",
                classId = classId,
                course = 1,
                ageFrom = 12,
                ageTo = 13,
                termLabel = "Inicial",
                dateEpochMs = 1_000,
                trace = trace(),
            )
        )
        fixture.physical.saveNotebookLink(
            PhysicalTestNotebookLink(
                assignmentId = "assignment",
                testId = "speed_30m",
                rawColumnId = "raw_col",
                scoreColumnId = "score_col",
                trace = trace(),
            )
        )
        fixture.physical.saveResult(
            PhysicalTestResult(
                id = "result",
                assignmentId = "assignment",
                testId = "speed_30m",
                classId = classId,
                studentId = studentId,
                rawValue = 5.8,
                rawText = "5,8",
                score = 8.0,
                scaleId = null,
                observedAtEpochMs = 2_000,
                rawColumnId = "raw_col",
                scoreColumnId = "score_col",
                trace = trace(),
            ),
            attempts = listOf(
                PhysicalTestAttempt("a1", "result", 1, 6.1, "6,1"),
                PhysicalTestAttempt("a2", "result", 2, 5.8, "5,8"),
            )
        )

        val result = fixture.physical.listResultsForAssignment("assignment").single()
        assertEquals(5.8, result.rawValue)
        assertEquals(8.0, result.score)
        assertEquals(studentId, fixture.physical.listResultsForStudent(studentId, "speed_30m").single().studentId)

        val link = fixture.physical.listNotebookLinksForAssignment("assignment").single()
        assertEquals("raw_col", link.rawColumnId)
        assertEquals("score_col", link.scoreColumnId)

        val attempts = fixture.db.appDatabaseQueries
            .selectPhysicalAttemptsForResult("result")
            .executeAsList()
        assertEquals(2, attempts.size)
        assertNotNull(attempts.single { it.attempt_number == 2L })
    }

    private fun createFixture(): Fixture {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)
        return Fixture(
            db = db,
            students = StudentsRepositorySqlDelight(db),
            classes = ClassesRepositorySqlDelight(db),
            physical = PhysicalTestsRepositorySqlDelight(db),
        )
    }

    private fun scale(id: String, course: Int?, ageFrom: Int?, ageTo: Int?, batteryId: String?): PhysicalTestScale {
        return PhysicalTestScale(
            id = id,
            testId = "speed_30m",
            name = id,
            course = course,
            ageFrom = ageFrom,
            ageTo = ageTo,
            batteryId = batteryId,
            direction = PhysicalScaleDirection.LOWER_IS_BETTER,
            ranges = listOf(PhysicalTestScaleRange("${id}_range", id, null, 6.0, 10.0)),
            trace = trace(),
        )
    }

    private suspend fun Fixture.seedDefinitionAndBattery() {
        physical.saveDefinition(
            PhysicalTestDefinition(
                id = "speed_30m",
                name = "Velocidad 30 m",
                capacity = PhysicalCapacity.SPEED,
                measurementKind = PhysicalMeasurementKind.TIME,
                unit = "s",
                higherIsBetter = false,
                attempts = 2,
                resultMode = PhysicalResultMode.BEST,
                trace = trace(),
            )
        )
        physical.saveBattery(
            PhysicalTestBattery(
                id = "battery",
                name = "Condición física inicial",
                defaultCourse = 1,
                defaultAgeFrom = 12,
                defaultAgeTo = 13,
                testIds = listOf("speed_30m"),
                trace = trace(),
            )
        )
    }

    private fun trace(): AuditTrace {
        val now = Instant.fromEpochMilliseconds(1_000)
        return AuditTrace(createdAt = now, updatedAt = now, deviceId = "test", syncVersion = 1)
    }

    private data class Fixture(
        val db: AppDatabase,
        val students: StudentsRepositorySqlDelight,
        val classes: ClassesRepositorySqlDelight,
        val physical: PhysicalTestsRepositorySqlDelight,
    )
}
