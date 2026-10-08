package com.migestor.shared.sync

import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class SyncCoordinatorChangeTokenTest {

    private class FakeAdapter(var token: String?) : SyncStoreAdapter {
        var collectCalls = 0
        var nextChanges: List<SyncChange> = emptyList()

        override suspend fun collectLocalChanges(sinceEpochMs: Long): List<SyncChange> {
            collectCalls += 1
            return nextChanges
        }

        override suspend fun applyIncomingChangesLww(changes: List<SyncChange>): SyncAck =
            SyncAck(applied = 0, conflictsResolvedByLww = 0, serverEpochMs = 0)

        override suspend fun currentChangeToken(): String? = token
    }

    private val change = SyncChange(
        entity = "grade",
        id = "1",
        updatedAtEpochMs = 100,
        deviceId = "mac",
        payload = "{}",
    )

    @Test
    fun `sin escrituras y con cursor al dia no recorre la base`() = runTest {
        val adapter = FakeAdapter(token = "5:1").apply { nextChanges = listOf(change) }
        val coordinator = SyncCoordinator(adapter)

        val first = coordinator.pullChanges(sinceEpochMs = 50, serverNowEpochMs = 1_000)
        assertEquals(listOf(change), first.changes)

        val second = coordinator.pullChanges(sinceEpochMs = 1_000, serverNowEpochMs = 2_000)
        assertTrue(second.changes.isEmpty())
        assertEquals(2_000, second.serverEpochMs)
        assertEquals(1, adapter.collectCalls)
    }

    @Test
    fun `una escritura nueva obliga a recorrer`() = runTest {
        val adapter = FakeAdapter(token = "5:1")
        val coordinator = SyncCoordinator(adapter)
        coordinator.pullChanges(sinceEpochMs = 50, serverNowEpochMs = 1_000)

        adapter.token = "6:1"
        adapter.nextChanges = listOf(change)
        val result = coordinator.pullChanges(sinceEpochMs = 1_000, serverNowEpochMs = 2_000)

        assertEquals(listOf(change), result.changes)
        assertEquals(2, adapter.collectCalls)
    }

    @Test
    fun `un cliente atrasado recibe el recorrido completo`() = runTest {
        val adapter = FakeAdapter(token = "5:1")
        val coordinator = SyncCoordinator(adapter)
        coordinator.pullChanges(sinceEpochMs = 50, serverNowEpochMs = 1_000)

        adapter.nextChanges = listOf(change)
        val result = coordinator.pullChanges(sinceEpochMs = 900, serverNowEpochMs = 2_000)

        assertEquals(listOf(change), result.changes)
        assertEquals(2, adapter.collectCalls)
    }

    @Test
    fun `pull completo desde cero nunca usa el atajo`() = runTest {
        val adapter = FakeAdapter(token = "5:1")
        val coordinator = SyncCoordinator(adapter)
        coordinator.pullChanges(sinceEpochMs = 50, serverNowEpochMs = 1_000)
        coordinator.pullChanges(sinceEpochMs = 0, serverNowEpochMs = 2_000)

        assertEquals(2, adapter.collectCalls)
    }

    @Test
    fun `sin marca disponible siempre recorre`() = runTest {
        val adapter = FakeAdapter(token = null)
        val coordinator = SyncCoordinator(adapter)
        coordinator.pullChanges(sinceEpochMs = 50, serverNowEpochMs = 1_000)
        coordinator.pullChanges(sinceEpochMs = 1_000, serverNowEpochMs = 2_000)

        assertEquals(2, adapter.collectCalls)
    }
}
