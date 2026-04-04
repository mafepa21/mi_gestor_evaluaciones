package com.migestor.shared.sync

/**
 * Representa un cambio local que debe sincronizarse con el peer.
 *
 * Campos de compatibilidad:
 *   - [op] indica la operación: "upsert" (por defecto, compatible v1) o "delete".
 *   - [schemaVersion] permite identificar la versión del payload a futuro (default 1 = v1).
 *
 * Los campos existentes ([entity], [id], [updatedAtEpochMs], [deviceId], [payload])
 * no cambian de semántica, asegurando compatibilidad total con emparejamientos previos.
 */
data class SyncChange(
    val entity: String,
    val id: String,
    val updatedAtEpochMs: Long,
    val deviceId: String,
    val payload: String,
    // Campos v2 con defaults compatibles con v1
    val op: String = "upsert",          // "upsert" | "delete"
    val schemaVersion: Int = 1,
)

data class SyncPullResponse(
    val serverEpochMs: Long,
    val changes: List<SyncChange>,
)

data class SyncPushRequest(
    val clientDeviceId: String,
    val lastKnownServerEpochMs: Long,
    val changes: List<SyncChange>,
)

data class SyncAck(
    val applied: Int,
    val conflictsResolvedByLww: Int,
    val serverEpochMs: Long,
    val ignored: Int = 0,
    val failed: Int = 0,
)

interface SyncStoreAdapter {
    suspend fun collectLocalChanges(sinceEpochMs: Long): List<SyncChange>
    suspend fun applyIncomingChangesLww(changes: List<SyncChange>): SyncAck
}

class SyncCoordinator(
    private val adapter: SyncStoreAdapter,
) {
    suspend fun pullChanges(sinceEpochMs: Long, serverNowEpochMs: Long): SyncPullResponse {
        val changes = adapter.collectLocalChanges(sinceEpochMs)
        return SyncPullResponse(
            serverEpochMs = serverNowEpochMs,
            changes = changes,
        )
    }

    suspend fun pushChanges(request: SyncPushRequest, serverNowEpochMs: Long): SyncAck {
        val ack = adapter.applyIncomingChangesLww(request.changes)
        return ack.copy(serverEpochMs = serverNowEpochMs)
    }
}
