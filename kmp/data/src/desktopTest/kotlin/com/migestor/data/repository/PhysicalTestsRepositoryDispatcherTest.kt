package com.migestor.data.repository

import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.db.SqlCursor
import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.db.SqlPreparedStatement
import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.shared.domain.AuditTrace
import com.migestor.shared.domain.PhysicalCapacity
import com.migestor.shared.domain.PhysicalMeasurementKind
import com.migestor.shared.domain.PhysicalScaleDirection
import com.migestor.shared.domain.PhysicalTestAssignment
import com.migestor.shared.domain.PhysicalTestAttempt
import com.migestor.shared.domain.PhysicalTestBattery
import com.migestor.shared.domain.PhysicalTestDefinition
import com.migestor.shared.domain.PhysicalTestNotebookLink
import com.migestor.shared.domain.PhysicalTestResult
import com.migestor.shared.domain.PhysicalTestScale
import com.migestor.shared.domain.PhysicalTestScaleRange
import kotlinx.coroutines.runBlocking
import kotlinx.datetime.Instant
import java.util.Collections
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Swift llama a estas funciones desde el hilo principal. Si el repositorio no salta a
 * `Dispatchers.Default`, la consulta corre en ese hilo y la pantalla de EF se congela.
 */
class PhysicalTestsRepositoryDispatcherTest {
    @Test
    fun `todas las lecturas y escrituras corren fuera del hilo que llama`() = runBlocking {
        val driver = ThreadRecordingDriver(JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY))
        AppDatabase.Schema.create(driver)
        driver.threads.clear()
        val repository = PhysicalTestsRepositorySqlDelight(AppDatabase(driver))
        val callerThread = Thread.currentThread().name
        val trace = AuditTrace(
            createdAt = Instant.fromEpochMilliseconds(1_000),
            updatedAt = Instant.fromEpochMilliseconds(1_000),
            deviceId = "test",
            syncVersion = 1,
        )

        val calls = mutableListOf<String>()
        suspend fun call(name: String, block: suspend () -> Unit) {
            driver.threads.clear()
            block()
            calls += name
            assertTrue(driver.threads.isNotEmpty(), "$name no llegó a la base de datos")
            assertTrue(
                driver.threads.none { it == callerThread },
                "$name consultó la base en el hilo que llama ($callerThread)",
            )
        }

        call("saveDefinition") {
            repository.saveDefinition(
                PhysicalTestDefinition(
                    id = "speed_30m",
                    name = "Velocidad 30 m",
                    capacity = PhysicalCapacity.SPEED,
                    measurementKind = PhysicalMeasurementKind.TIME,
                    unit = "s",
                    higherIsBetter = false,
                    trace = trace,
                )
            )
        }
        call("listDefinitions") { repository.listDefinitions() }
        call("saveBattery") {
            repository.saveBattery(
                PhysicalTestBattery(id = "battery", name = "Inicial", testIds = listOf("speed_30m"), trace = trace)
            )
        }
        call("listBatteries") { repository.listBatteries() }
        call("assignBatteryToClass") {
            repository.assignBatteryToClass(
                PhysicalTestAssignment(
                    id = "assignment",
                    batteryId = "battery",
                    classId = 1,
                    course = 1,
                    ageFrom = 12,
                    ageTo = 13,
                    termLabel = null,
                    dateEpochMs = 1_000,
                    trace = trace,
                )
            )
        }
        call("listAssignmentsForClass") { repository.listAssignmentsForClass(1) }
        call("saveScale") {
            repository.saveScale(
                PhysicalTestScale(
                    id = "scale",
                    testId = "speed_30m",
                    name = "Escala",
                    direction = PhysicalScaleDirection.LOWER_IS_BETTER,
                    ranges = listOf(PhysicalTestScaleRange("range", "scale", null, 6.0, 10.0)),
                    trace = trace,
                )
            )
        }
        call("listScalesForTest") { repository.listScalesForTest("speed_30m") }
        call("resolveScale") { repository.resolveScale("speed_30m", course = 1, age = 12, sex = null, batteryId = null) }
        call("saveNotebookLink") {
            repository.saveNotebookLink(
                PhysicalTestNotebookLink("assignment", "speed_30m", rawColumnId = "raw", scoreColumnId = "score", trace = trace)
            )
        }
        call("listNotebookLinksForAssignment") { repository.listNotebookLinksForAssignment("assignment") }
        call("saveResult") {
            repository.saveResult(
                PhysicalTestResult(
                    id = "result",
                    assignmentId = "assignment",
                    testId = "speed_30m",
                    classId = 1,
                    studentId = 1,
                    rawValue = 5.8,
                    rawText = "5,8",
                    score = 10.0,
                    scaleId = "scale",
                    observedAtEpochMs = 1_000,
                    rawColumnId = "raw",
                    scoreColumnId = "score",
                    trace = trace,
                ),
                listOf(PhysicalTestAttempt("attempt", "result", 1, 5.8, "5,8")),
            )
        }
        call("listResultsForAssignment") { repository.listResultsForAssignment("assignment") }
        call("listResultsForStudent") { repository.listResultsForStudent(1, "speed_30m") }
        call("listPhysicalTestHistoryForStudent") { repository.listPhysicalTestHistoryForStudent(1) }

        assertEquals(15, calls.size)
    }
}

/** Apunta en qué hilo se ejecuta cada sentencia SQL. */
private class ThreadRecordingDriver(private val inner: SqlDriver) : SqlDriver by inner {
    val threads: MutableList<String> = Collections.synchronizedList(mutableListOf())

    override fun <R> executeQuery(
        identifier: Int?,
        sql: String,
        mapper: (SqlCursor) -> QueryResult<R>,
        parameters: Int,
        binders: (SqlPreparedStatement.() -> Unit)?,
    ): QueryResult<R> {
        threads += Thread.currentThread().name
        return inner.executeQuery(identifier, sql, mapper, parameters, binders)
    }

    override fun execute(
        identifier: Int?,
        sql: String,
        parameters: Int,
        binders: (SqlPreparedStatement.() -> Unit)?,
    ): QueryResult<Long> {
        threads += Thread.currentThread().name
        return inner.execute(identifier, sql, parameters, binders)
    }
}
