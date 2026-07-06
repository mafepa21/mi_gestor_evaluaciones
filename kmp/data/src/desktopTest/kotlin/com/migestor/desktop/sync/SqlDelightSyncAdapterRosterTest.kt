package com.migestor.desktop.sync

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import com.migestor.shared.sync.SyncChange
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.Clock
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Cubre la protección LWW por alumno en la aplicación de "class_roster" (ver
 * SqlDelightSyncAdapter.applyIncomingChangesLww): un snapshot de roster stale
 * que llega tarde no debe borrar a un alumno añadido localmente más
 * recientemente que ese snapshot, pero una baja genuina (snapshot más nuevo
 * que la última alta/baja local del alumno) sí debe propagarse.
 */
class SqlDelightSyncAdapterRosterTest {
    private fun newContainer(): KmpContainer {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        return KmpContainer(driver)
    }

    private fun rosterPayload(classId: Long, studentIds: List<Long>): String =
        buildJsonObject {
            put("classId", classId)
            put("studentIds", JsonArray(studentIds.map { JsonPrimitive(it) }))
        }.toString()

    @Test
    fun `un snapshot de roster stale no borra una alta local mas reciente`() = runTest {
        val container = newContainer()
        val adapter = SqlDelightSyncAdapter(container, localDeviceId = "mac")

        val classId = container.classesRepository.saveClass(name = "3 ESO A", course = 3)
        val studentA = container.studentsRepository.saveStudent(firstName = "Ana", lastName = "López")
        val studentB = container.studentsRepository.saveStudent(firstName = "Bea", lastName = "Ruiz")

        container.classesRepository.addStudentToClass(classId, studentA)
        container.classesRepository.addStudentToClass(classId, studentB)
        assertEquals(
            setOf(studentA, studentB),
            container.classesRepository.listStudentsInClass(classId).map { it.id }.toSet(),
        )

        // Un iPad, offline desde antes de que se añadiera a B, empuja un snapshot
        // de roster que solo conoce a A, fechado ANTES de las altas de arriba.
        val staleTimestamp = Clock.System.now().toEpochMilliseconds() - 60_000L
        val ack = adapter.applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "class_roster",
                    id = classId.toString(),
                    updatedAtEpochMs = staleTimestamp,
                    deviceId = "ios",
                    payload = rosterPayload(classId, listOf(studentA)),
                )
            )
        )

        assertEquals(
            setOf(studentA, studentB),
            container.classesRepository.listStudentsInClass(classId).map { it.id }.toSet(),
            "B no debe desaparecer: su alta local es más reciente que el snapshot stale",
        )
        assertTrue(ack.ignored >= 1, "La baja bloqueada debe contabilizarse como ignored, no como applied")
    }

    @Test
    fun `un snapshot de roster mas reciente que la alta local propaga la baja`() = runTest {
        val container = newContainer()
        val adapter = SqlDelightSyncAdapter(container, localDeviceId = "mac")

        val classId = container.classesRepository.saveClass(name = "3 ESO A", course = 3)
        val studentA = container.studentsRepository.saveStudent(firstName = "Ana", lastName = "López")
        val studentB = container.studentsRepository.saveStudent(firstName = "Bea", lastName = "Ruiz")

        container.classesRepository.addStudentToClass(classId, studentA)
        container.classesRepository.addStudentToClass(classId, studentB)

        // Esta vez el snapshot es genuinamente posterior a la alta de B en este
        // dispositivo (p.ej. B fue dado de baja después, en el otro dispositivo).
        val freshTimestamp = Clock.System.now().toEpochMilliseconds() + 60_000L
        val ack = adapter.applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "class_roster",
                    id = classId.toString(),
                    updatedAtEpochMs = freshTimestamp,
                    deviceId = "ios",
                    payload = rosterPayload(classId, listOf(studentA)),
                )
            )
        )

        assertEquals(
            setOf(studentA),
            container.classesRepository.listStudentsInClass(classId).map { it.id }.toSet(),
            "Una baja genuina (snapshot más nuevo) sí debe propagarse",
        )
        assertTrue(ack.applied >= 1)
    }
}
