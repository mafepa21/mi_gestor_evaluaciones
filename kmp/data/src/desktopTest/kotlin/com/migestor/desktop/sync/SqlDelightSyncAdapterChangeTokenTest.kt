package com.migestor.desktop.sync

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import com.migestor.shared.sync.SyncCoordinator
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class SqlDelightSyncAdapterChangeTokenTest {
    private fun newContainer(): KmpContainer {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        return KmpContainer(driver)
    }

    @Test
    fun laMarcaCambiaTrasUnaEscrituraYNoSinElla() = runTest {
        val container = newContainer()
        val adapter = SqlDelightSyncAdapter(container, localDeviceId = "mac")

        val before = adapter.currentChangeToken()
        assertNotNull(before)
        assertEquals(before, adapter.currentChangeToken())

        container.studentsRepository.saveStudent(firstName = "Ana", lastName = "López")
        assertNotEquals(before, adapter.currentChangeToken())
    }

    @Test
    fun unAlumnoNuevoLlegaAunqueElPullAnteriorFueraVacio() = runTest {
        val container = newContainer()
        val coordinator = SyncCoordinator(SqlDelightSyncAdapter(container, localDeviceId = "mac"))

        val first = coordinator.pullChanges(sinceEpochMs = 1L, serverNowEpochMs = 1_000L)
        val idle = coordinator.pullChanges(sinceEpochMs = first.serverEpochMs, serverNowEpochMs = 2_000L)
        assertTrue(idle.changes.isEmpty())

        val studentId = container.studentsRepository.saveStudent(firstName = "Ana", lastName = "López")
        val afterWrite = coordinator.pullChanges(sinceEpochMs = 1L, serverNowEpochMs = 3_000L)
        assertTrue(afterWrite.changes.any { it.entity == "student" && it.id == studentId.toString() })
    }
}
