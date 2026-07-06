package com.migestor.desktop.sync

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import com.migestor.shared.sync.SyncChange
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Cubre el mecanismo de tombstones (ver sync_tombstones en AppDatabase.sq): un
 * upsert entrante fechado antes de un borrado ya aplicado no debe resucitar la
 * entidad, pero uno fechado después sí debe prevalecer (LWW normal).
 */
class SqlDelightSyncAdapterTombstoneTest {
    private fun newContainer(): KmpContainer {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        return KmpContainer(driver)
    }

    private fun studentPayload(id: Long, firstName: String = "Ana", lastName: String = "López") =
        buildJsonObject {
            put("id", id)
            put("firstName", firstName)
            put("lastName", lastName)
        }.toString()

    @Test
    fun `un upsert mas antiguo que el borrado no resucita la entidad`() = runTest {
        val container = newContainer()
        val adapter = SqlDelightSyncAdapter(container, localDeviceId = "mac")

        val studentId = container.studentsRepository.saveStudent(firstName = "Ana", lastName = "López")
        assertEquals("Ana", container.studentsRepository.getStudent(studentId)?.firstName)

        // El Mac borra al alumno en t=200.
        adapter.applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "student",
                    id = studentId.toString(),
                    updatedAtEpochMs = 200L,
                    deviceId = "mac",
                    payload = studentPayload(studentId),
                    op = "delete",
                )
            )
        )
        assertNull(container.studentsRepository.getStudent(studentId))

        // Un iPad que estaba offline en t=100 empuja tarde una edición previa al borrado.
        val ack = adapter.applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "student",
                    id = studentId.toString(),
                    updatedAtEpochMs = 100L,
                    deviceId = "ios",
                    payload = studentPayload(studentId, firstName = "Ana (offline edit)"),
                )
            )
        )

        assertNull(
            container.studentsRepository.getStudent(studentId),
            "Un upsert anterior al borrado no debe resucitar al alumno",
        )
        assertEquals(1, ack.ignored)
        assertEquals(0, ack.applied)
    }

    @Test
    fun `un upsert mas reciente que el borrado gana LWW y limpia el tombstone`() = runTest {
        val container = newContainer()
        val adapter = SqlDelightSyncAdapter(container, localDeviceId = "mac")

        val studentId = container.studentsRepository.saveStudent(firstName = "Ana", lastName = "López")

        adapter.applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "student",
                    id = studentId.toString(),
                    updatedAtEpochMs = 200L,
                    deviceId = "mac",
                    payload = studentPayload(studentId),
                    op = "delete",
                )
            )
        )
        assertNull(container.studentsRepository.getStudent(studentId))

        // El iPad editó al alumno DESPUÉS del borrado (p.ej. no se había enterado
        // todavía, pero su reloj/edición es más reciente): debe prevalecer.
        val ack = adapter.applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "student",
                    id = studentId.toString(),
                    updatedAtEpochMs = 300L,
                    deviceId = "ios",
                    payload = studentPayload(studentId, firstName = "Ana (resucitada)"),
                )
            )
        )

        assertEquals(
            "Ana (resucitada)",
            container.studentsRepository.getStudent(studentId)?.firstName,
            "Un upsert posterior al borrado debe ganar LWW y recrear la entidad",
        )
        assertEquals(1, ack.applied)
        assertEquals(0, ack.ignored)
    }
}
