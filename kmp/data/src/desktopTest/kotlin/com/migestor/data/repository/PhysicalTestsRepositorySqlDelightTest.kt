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
import com.migestor.shared.domain.StudentSex
import com.migestor.shared.domain.StudentSexSource
import com.migestor.shared.domain.resolvedPhysicalResult
import com.migestor.shared.domain.scoreFor
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class PhysicalTestsRepositorySqlDelightTest {
    @Test
    fun `resolvedPhysicalResult handles direction and result modes`() {
        assertEquals(5.8, resolvedPhysicalResult(listOf(5.8, 6.1), PhysicalScaleDirection.LOWER_IS_BETTER, PhysicalResultMode.BEST))
        assertEquals(6.1, resolvedPhysicalResult(listOf(5.8, 6.1), PhysicalScaleDirection.HIGHER_IS_BETTER, PhysicalResultMode.BEST))
        assertEquals(5.95, resolvedPhysicalResult(listOf(5.8, 6.1), PhysicalScaleDirection.HIGHER_IS_BETTER, PhysicalResultMode.AVERAGE)!!, 0.0001)
        assertEquals(6.1, resolvedPhysicalResult(listOf(5.8, 6.1), PhysicalScaleDirection.LOWER_IS_BETTER, PhysicalResultMode.LAST))
    }

    @Test
    fun `scoreFor resolves horizontal jump ranges`() {
        val scale = scoreScale(
            id = "jump_scale",
            testId = "horizontal_jump",
            direction = PhysicalScaleDirection.HIGHER_IS_BETTER,
            ranges = listOf(
                PhysicalTestScaleRange("jump_5", "jump_scale", minValue = 1.40, maxValue = 1.59, score = 5.0),
                PhysicalTestScaleRange("jump_7", "jump_scale", minValue = 1.60, maxValue = 1.79, score = 7.0),
                PhysicalTestScaleRange("jump_10", "jump_scale", minValue = 1.80, maxValue = null, score = 12.0),
            ),
        )

        assertEquals(7.0, scale.scoreFor(1.72))
        assertEquals(10.0, scale.scoreFor(1.90))
        assertNull(scale.scoreFor(1.20))
    }

    @Test
    fun `scoreFor resolves 30 meter speed ranges with lower values`() {
        val scale = scoreScale(
            id = "speed_scale",
            testId = "speed_30m",
            direction = PhysicalScaleDirection.LOWER_IS_BETTER,
            ranges = listOf(
                PhysicalTestScaleRange("speed_10", "speed_scale", minValue = null, maxValue = 4.90, score = 10.0),
                PhysicalTestScaleRange("speed_8", "speed_scale", minValue = 4.91, maxValue = 5.40, score = 8.0),
                PhysicalTestScaleRange("speed_5", "speed_scale", minValue = 5.41, maxValue = 6.20, score = 5.0),
            ),
        )

        assertEquals(10.0, scale.scoreFor(4.85))
        assertEquals(8.0, scale.scoreFor(5.12))
        assertEquals(5.0, scale.scoreFor(6.20))
    }

    @Test
    fun `scoreFor resolves Course Navette level ranges`() {
        val scale = scoreScale(
            id = "navette_scale",
            testId = "course_navette",
            direction = PhysicalScaleDirection.HIGHER_IS_BETTER,
            ranges = listOf(
                PhysicalTestScaleRange("navette_4", "navette_scale", minValue = null, maxValue = 4.5, score = 4.0),
                PhysicalTestScaleRange("navette_6", "navette_scale", minValue = 5.0, maxValue = 7.5, score = 6.0),
                PhysicalTestScaleRange("navette_9", "navette_scale", minValue = 8.0, maxValue = null, score = 9.0),
            ),
        )

        assertEquals(4.0, scale.scoreFor(4.0))
        assertEquals(6.0, scale.scoreFor(6.5))
        assertEquals(9.0, scale.scoreFor(9.0))
    }

    @Test
    fun `resolvedPhysicalResult selects best attempt for higher and lower directions`() {
        assertEquals(
            1.82,
            resolvedPhysicalResult(listOf(1.68, 1.82, 1.76), PhysicalScaleDirection.HIGHER_IS_BETTER, PhysicalResultMode.BEST),
        )
        assertEquals(
            5.21,
            resolvedPhysicalResult(listOf(5.44, 5.21, 5.38), PhysicalScaleDirection.LOWER_IS_BETTER, PhysicalResultMode.BEST),
        )
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
    fun `resolveScale does not select sex specific scale when sex is null`() = runTest {
        val fixture = createFixture()
        fixture.seedDefinitionAndBattery()
        fixture.physical.saveScale(scale("female", course = 1, ageFrom = null, ageTo = null, batteryId = null, sex = "F"))
        fixture.physical.saveScale(scale("neutral", course = 1, ageFrom = null, ageTo = null, batteryId = null, sex = null))

        assertEquals("neutral", fixture.physical.resolveScale("speed_30m", 1, null, null, null)?.id)
        assertEquals("female", fixture.physical.resolveScale("speed_30m", 1, null, "f", null)?.id)
    }

    @Test
    fun `resolveScale normalizes legacy sex labels and falls back to neutral`() = runTest {
        val fixture = createFixture()
        fixture.seedDefinitionAndBattery()
        fixture.physical.saveScale(scale("male", course = 1, ageFrom = null, ageTo = null, batteryId = null, sex = "Hombre"))
        fixture.physical.saveScale(scale("neutral", course = 1, ageFrom = null, ageTo = null, batteryId = null, sex = null))

        assertEquals("male", fixture.physical.resolveScale("speed_30m", 1, null, "male", null)?.id)
        assertEquals("neutral", fixture.physical.resolveScale("speed_30m", 1, null, "female", null)?.id)
        assertEquals("neutral", fixture.physical.resolveScale("speed_30m", 1, null, "UNSPECIFIED", null)?.id)
    }

    @Test
    fun `students persist physical sex metadata`() = runTest {
        val fixture = createFixture()
        val studentId = fixture.students.saveStudent(
            firstName = "Pablo",
            lastName = "Garcia",
            sex = StudentSex.MALE,
            sexSource = StudentSexSource.MANUAL,
            birthDate = LocalDate(2010, 4, 12),
        )

        val student = fixture.students.listStudents().single { it.id == studentId }
        assertEquals(StudentSex.MALE, student.sex)
        assertEquals(StudentSexSource.MANUAL, student.sexSource)
        assertEquals(LocalDate(2010, 4, 12), student.birthDate)
    }

    @Test
    fun `migration defaults existing students physical metadata`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        driver.execute(
            null,
            """
            CREATE TABLE students (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                first_name TEXT NOT NULL,
                last_name TEXT NOT NULL,
                email TEXT,
                photo_path TEXT,
                is_injured INTEGER NOT NULL DEFAULT 0,
                updated_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
                device_id TEXT,
                sync_version INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent(),
            0,
        )
        driver.execute(
            null,
            "INSERT INTO students(id, first_name, last_name, email, photo_path, is_injured, updated_at_epoch_ms, device_id, sync_version) VALUES (1, 'Ana', 'Lopez', NULL, NULL, 0, 1000, NULL, 0)",
            0,
        )

        AppDatabase.Schema.migrate(driver, 18, AppDatabase.Schema.version)
        val student = StudentsRepositorySqlDelight(AppDatabase(driver)).listStudents().single()

        assertEquals(StudentSex.UNSPECIFIED, student.sex)
        assertEquals(StudentSexSource.UNKNOWN, student.sexSource)
        assertNull(student.birthDate)
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

    private fun scale(
        id: String,
        course: Int?,
        ageFrom: Int?,
        ageTo: Int?,
        batteryId: String?,
        sex: String? = null,
    ): PhysicalTestScale {
        return PhysicalTestScale(
            id = id,
            testId = "speed_30m",
            name = id,
            course = course,
            ageFrom = ageFrom,
            ageTo = ageTo,
            sex = sex,
            batteryId = batteryId,
            direction = PhysicalScaleDirection.LOWER_IS_BETTER,
            ranges = listOf(PhysicalTestScaleRange("${id}_range", id, null, 6.0, 10.0)),
            trace = trace(),
        )
    }

    private fun scoreScale(
        id: String,
        testId: String,
        direction: PhysicalScaleDirection,
        ranges: List<PhysicalTestScaleRange>,
    ): PhysicalTestScale {
        return PhysicalTestScale(
            id = id,
            testId = testId,
            name = id,
            direction = direction,
            ranges = ranges,
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
