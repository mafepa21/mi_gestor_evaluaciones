package com.migestor.desktop.sync

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class SqlDelightSyncAdapterOutgoingDeleteTest {
    private fun newContainer(): KmpContainer {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        return KmpContainer(driver)
    }

    private fun studentDeletes(changes: List<com.migestor.shared.sync.SyncChange>, studentId: Long) =
        changes.filter { it.entity == "student" && it.op == "delete" && it.id == studentId.toString() }

    @Test
    fun unBorradoLocalSigueSaliendoTrasReiniciarElAdaptador() = runTest {
        val container = newContainer()
        val studentId = container.studentsRepository.saveStudent(firstName = "Ana", lastName = "López")
        val adapter = SqlDelightSyncAdapter(container, localDeviceId = "mac")
        adapter.collectLocalChanges(0L)

        container.studentsRepository.deleteStudent(studentId)
        val emitted = studentDeletes(adapter.collectLocalChanges(0L), studentId)
        assertEquals(1, emitted.size)
        assertEquals(studentId, Json.parseToJsonElement(emitted.single().payload).jsonObject["id"]?.jsonPrimitive?.longOrNull)

        val stored = container.database.appDatabaseQueries
            .selectSyncTombstone("student", studentId.toString())
            .executeAsOne()
        assertEquals("mac", stored.device_id)

        val restarted = SqlDelightSyncAdapter(container, localDeviceId = "mac")
        val replayed = studentDeletes(restarted.collectLocalChanges(0L), studentId)
        assertEquals(1, replayed.size)
        assertEquals(studentId, Json.parseToJsonElement(replayed.single().payload).jsonObject["id"]?.jsonPrimitive?.longOrNull)

        assertTrue(studentDeletes(restarted.collectLocalChanges(Long.MAX_VALUE), studentId).isEmpty())
    }

    @Test
    fun noReenviaElBorradoSiElAlumnoVuelveAExistir() = runTest {
        val container = newContainer()
        val studentId = container.studentsRepository.saveStudent(firstName = "Ana", lastName = "López")
        val adapter = SqlDelightSyncAdapter(container, localDeviceId = "mac")
        adapter.collectLocalChanges(0L)
        container.studentsRepository.deleteStudent(studentId)
        adapter.collectLocalChanges(0L)

        container.studentsRepository.upsertStudent(
            id = studentId,
            firstName = "Ana",
            lastName = "López",
            updatedAtEpochMs = 5_000L,
            deviceId = "mac",
            syncVersion = 1,
        )
        val restarted = SqlDelightSyncAdapter(container, localDeviceId = "mac")
        assertTrue(studentDeletes(restarted.collectLocalChanges(0L), studentId).isEmpty())
    }

    @Test
    fun noReenviaBorradosQueVinieronDeOtroDispositivo() = runTest {
        val container = newContainer()
        container.syncTombstoneRepository.recordTombstone(
            entity = "student",
            entityId = "999",
            deletedAtEpochMs = 1_000L,
            deviceId = "ipad",
        )
        val adapter = SqlDelightSyncAdapter(container, localDeviceId = "mac")
        val changes = adapter.collectLocalChanges(0L)
        assertTrue(changes.none { it.op == "delete" && it.entity == "student" && it.id == "999" })
    }
}
