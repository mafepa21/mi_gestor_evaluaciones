package com.migestor.shared.sync

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

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

    /**
     * Marca barata que cambia con cualquier escritura en la base local (propia o
     * de otro proceso). `null` si el adaptador no sabe calcularla: entonces cada
     * pull recorre la base como siempre.
     */
    suspend fun currentChangeToken(): String? = null
}

class SyncCoordinator(
    private val adapter: SyncStoreAdapter,
) {
    private val pullMutex = Mutex()
    private var lastFullCollectToken: String? = null
    private var lastFullCollectServerNowEpochMs: Long = Long.MAX_VALUE

    suspend fun pullChanges(sinceEpochMs: Long, serverNowEpochMs: Long): SyncPullResponse = pullMutex.withLock {
        // Cada iPad pide cambios cada 15-30 s y recorrer la base entera es caro.
        // Si la base no ha cambiado desde el último recorrido completo y el
        // cliente ya recibió una respuesta posterior a ese recorrido, no hay
        // nada nuevo que mandarle.
        val token = adapter.currentChangeToken()
        if (
            token != null &&
            sinceEpochMs > 0L &&
            token == lastFullCollectToken &&
            sinceEpochMs >= lastFullCollectServerNowEpochMs
        ) {
            return@withLock SyncPullResponse(serverEpochMs = serverNowEpochMs, changes = emptyList())
        }
        // La marca se lee ANTES de recorrer: una escritura durante el recorrido
        // deja la marca desfasada y fuerza otro recorrido en el siguiente pull.
        val changes = adapter.collectLocalChanges(sinceEpochMs)
        if (token != lastFullCollectToken) {
            lastFullCollectToken = token
            lastFullCollectServerNowEpochMs = serverNowEpochMs
        }
        SyncPullResponse(
            serverEpochMs = serverNowEpochMs,
            changes = changes,
        )
    }

    suspend fun pushChanges(request: SyncPushRequest, serverNowEpochMs: Long): SyncAck {
        val ack = adapter.applyIncomingChangesLww(request.changes)
        return ack.copy(serverEpochMs = serverNowEpochMs)
    }
}
