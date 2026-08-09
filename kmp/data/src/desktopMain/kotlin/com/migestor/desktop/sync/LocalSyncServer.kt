package com.migestor.desktop.sync

import com.migestor.data.platform.getAppDataPath
import com.migestor.shared.sync.SyncAck
import com.migestor.shared.sync.SyncChange
import com.migestor.shared.sync.SyncCoordinator
import com.migestor.shared.sync.SyncPullResponse
import com.migestor.shared.sync.SyncPushRequest
import com.migestor.shared.sync.SyncStoreAdapter
import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpsConfigurator
import com.sun.net.httpserver.HttpsServer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.asn1.x509.BasicConstraints
import org.bouncycastle.asn1.x509.Extension
import org.bouncycastle.asn1.x509.KeyUsage
import org.bouncycastle.cert.X509CertificateHolder
import org.bouncycastle.cert.X509v3CertificateBuilder
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter
import org.bouncycastle.cert.jcajce.JcaX509ExtensionUtils
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder
import org.bouncycastle.jce.provider.BouncyCastleProvider
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder
import java.io.File
import java.io.InputStream
import java.math.BigInteger
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.Security
import java.security.cert.X509Certificate
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.Base64
import java.util.Date
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.prefs.Preferences
import javax.jmdns.JmDNS
import javax.jmdns.ServiceInfo
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManagerFactory

private const val HANDSHAKE_BODY_LIMIT_BYTES = 16 * 1024
private const val SYNC_BODY_LIMIT_BYTES = 2 * 1024 * 1024
private const val DOCUMENT_BODY_LIMIT_BYTES = 25 * 1024 * 1024
private const val PAIRING_PIN_TTL_MS = 10 * 60 * 1000L

internal class RequestBodyTooLargeException : IllegalArgumentException("request_body_too_large")

internal fun InputStream.readBytesLimited(maxBytes: Int): ByteArray {
    require(maxBytes >= 0)
    val output = java.io.ByteArrayOutputStream(minOf(maxBytes, DEFAULT_BUFFER_SIZE))
    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
    var total = 0
    while (true) {
        val read = read(buffer)
        if (read < 0) break
        total += read
        if (total > maxBytes) throw RequestBodyTooLargeException()
        output.write(buffer, 0, read)
    }
    return output.toByteArray()
}

internal data class PairingPinSnapshot(
    val pin: String,
    val expiresAtEpochMs: Long,
    val rotated: Boolean,
)

internal class ExpiringPairingPin(
    private val ttlMs: Long = PAIRING_PIN_TTL_MS,
    private val clock: () -> Long = System::currentTimeMillis,
    private val generator: () -> String = ::generatePairingPin,
) {
    private var pin = generator()
    private var expiresAtEpochMs = clock() + ttlMs

    @Synchronized
    fun current(): PairingPinSnapshot {
        val now = clock()
        val rotated = now >= expiresAtEpochMs
        if (rotated) rotateAt(now)
        return PairingPinSnapshot(pin, expiresAtEpochMs, rotated)
    }

    @Synchronized
    fun rotate(): PairingPinSnapshot {
        rotateAt(clock())
        return PairingPinSnapshot(pin, expiresAtEpochMs, true)
    }

    private fun rotateAt(now: Long) {
        pin = generator()
        expiresAtEpochMs = now + ttlMs
    }
}

internal class PairingAttemptLimiter(
    private val maxFailures: Int = 5,
    private val failureWindowMs: Long = 60_000L,
    private val lockoutMs: Long = 60_000L,
    private val maxTrackedOrigins: Int = 256,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private data class AttemptState(
        var windowStartedAtEpochMs: Long,
        var failures: Int = 0,
        var lockedUntilEpochMs: Long = 0,
    )

    private val states = linkedMapOf<String, AttemptState>()

    @Synchronized
    fun isAllowed(origin: String): Boolean {
        val now = clock()
        val state = states[origin] ?: return true
        if (state.lockedUntilEpochMs > now) return false
        if (now - state.windowStartedAtEpochMs >= failureWindowMs) {
            states.remove(origin)
        }
        return true
    }

    @Synchronized
    fun recordFailure(origin: String) {
        val now = clock()
        if (origin !in states && states.size >= maxTrackedOrigins) {
            states.entries.removeIf { now - it.value.windowStartedAtEpochMs >= failureWindowMs }
            if (states.size >= maxTrackedOrigins) {
                states.remove(states.keys.first())
            }
        }
        val state = states.getOrPut(origin) { AttemptState(windowStartedAtEpochMs = now) }
        if (now - state.windowStartedAtEpochMs >= failureWindowMs) {
            state.windowStartedAtEpochMs = now
            state.failures = 0
            state.lockedUntilEpochMs = 0
        }
        if (state.lockedUntilEpochMs > now) return
        state.failures += 1
        if (state.failures >= maxFailures) {
            state.lockedUntilEpochMs = now + lockoutMs
        }
    }

    @Synchronized
    fun recordSuccess(origin: String) {
        states.remove(origin)
    }
}

private val pairingPinRandom = SecureRandom()

private fun generatePairingPin(): String =
    (pairingPinRandom.nextInt(900_000) + 100_000).toString()

class InMemorySyncAdapter : SyncStoreAdapter {
    private val changes = mutableListOf<SyncChange>()

    override suspend fun collectLocalChanges(sinceEpochMs: Long): List<SyncChange> {
        return changes.filter { it.updatedAtEpochMs > sinceEpochMs }
    }

    override suspend fun applyIncomingChangesLww(changes: List<SyncChange>): SyncAck {
        var conflicts = 0
        var applied = 0
        changes.forEach { incoming ->
            val idx = this.changes.indexOfFirst { it.entity == incoming.entity && it.id == incoming.id }
            if (idx < 0) {
                this.changes += incoming
                applied++
            } else {
                val local = this.changes[idx]
                val shouldReplace = incoming.updatedAtEpochMs > local.updatedAtEpochMs ||
                    (incoming.updatedAtEpochMs == local.updatedAtEpochMs && incoming.deviceId > local.deviceId)
                if (shouldReplace) {
                    this.changes[idx] = incoming
                    applied++
                    conflicts++
                }
            }
        }
        return SyncAck(applied = applied, conflictsResolvedByLww = conflicts, serverEpochMs = System.currentTimeMillis())
    }
}

internal object LanSyncJsonCodec {
    fun encodeSyncEventPayload(serverEpochMs: Long, entities: List<String>, changes: List<SyncChange>): String {
        return buildJsonObject {
            put("serverEpochMs", JsonPrimitive(serverEpochMs))
            put("entities", JsonArray(entities.map { JsonPrimitive(it) }))
            put("changes", JsonArray(changes.map(::encodeSyncChange)))
        }.toString()
    }

    private fun encodeSyncChange(change: SyncChange): JsonObject {
        return buildJsonObject {
            put("entity", JsonPrimitive(change.entity))
            put("id", JsonPrimitive(change.id))
            put("updatedAtEpochMs", JsonPrimitive(change.updatedAtEpochMs))
            put("deviceId", JsonPrimitive(change.deviceId))
            put("payload", JsonPrimitive(change.payload))
            put("op", JsonPrimitive(change.op))
            put("schemaVersion", JsonPrimitive(change.schemaVersion))
        }
    }
}

internal fun filterDesktopChangesForSse(changes: List<SyncChange>, pairedDeviceId: String?): List<SyncChange> {
    return changes.filter { change ->
        pairedDeviceId.isNullOrBlank() || change.deviceId != pairedDeviceId
    }
}

internal fun isLoopbackSyncRequest(address: InetAddress?): Boolean {
    return address?.isLoopbackAddress == true
}

internal fun parseQueryParams(rawQuery: String?): Map<String, String> {
    return rawQuery
        ?.split("&")
        ?.mapNotNull { part ->
            val kv = part.split("=", limit = 2)
            if (kv.size == 2 && kv[0].isNotBlank()) kv[0] to kv[1] else null
        }
        ?.toMap()
        .orEmpty()
}

internal fun selectPreferredLanAddress(candidates: List<Pair<String, InetAddress>>): InetAddress? {
    return candidates
        .sortedWith(
            compareBy<Pair<String, InetAddress>> { (name, _) ->
                when {
                    name == "en0" -> 0
                    name.startsWith("en") -> 1
                    name.startsWith("eth") -> 2
                    else -> 3
                }
            }.thenBy { it.first }
        )
        .firstOrNull()
        ?.second
}

class LocalSyncServer(
    private val port: Int = 8765,
    private val syncCoordinator: SyncCoordinator = SyncCoordinator(InMemorySyncAdapter()),
    private val stateListener: ((CommandCenterSnapshot) -> Unit)? = null,
) {
    private val learningSituationDocumentsDirectory = File(getAppDataPath("learning-situations")).apply { mkdirs() }
    private val json = Json { ignoreUnknownKeys = true }
    private val sseConnections = java.util.concurrent.CopyOnWriteArrayList<HttpExchange>()
    private var server: HttpsServer? = null
    private var jmDns: JmDNS? = null
    private var serviceInfo: ServiceInfo? = null
    private var networkMonitor: ScheduledExecutorService? = null
    private var dbMonitor: ScheduledExecutorService? = null
    @Volatile
    private var lastCheckedDbTimestamp: Long = System.currentTimeMillis()
    @Volatile
    private var advertisedLanAddress: InetAddress? = null

    private val secureStore = DesktopSecureStore(serviceName = "com.migestor.sync.desktop")
    private val tlsIdentity = DesktopTlsIdentity(secureStore)
    private val pairingPinState = ExpiringPairingPin()
    private val pairingAttemptLimiter = PairingAttemptLimiter()

    @Volatile
    private var hostHint: String = "localhost"
    @Volatile
    private var networkErrorMessage: String? = "No se pudo resolver una IP LAN válida para este Mac."
    @Volatile
    private var pairedDeviceId: String? = secureStore.get("paired-device-id")
    @Volatile
    private var activeToken: String? = secureStore.get("paired-token")

    private val serverId: String = secureStore.get("server-id") ?: run {
        val generated = "mac-${UUID.randomUUID().toString().replace("-", "").take(16)}"
        secureStore.put("server-id", generated)
        generated
    }

    private val certFingerprintSha256: String by lazy { tlsIdentity.certificateFingerprintSha256() }

    private val _status = MutableStateFlow(createStatus())
    val status: StateFlow<SyncServerStatus> = _status.asStateFlow()

    private fun createStatus(): SyncServerStatus {
        val snapshot = currentSnapshot()
        return SyncServerStatus(
            isPaired = isPaired(),
            pairedDeviceId = pairedDeviceId,
            pin = pairingPinState.current().pin,
            serverId = serverId,
            pairingPayload = snapshot.pairingPayload.orEmpty(),
            host = snapshot.host ?: "",
        )
    }

    private fun notifyStatusChanged() {
        _status.value = createStatus()
        stateListener?.invoke(currentSnapshot())
    }


    fun currentPin(): String = pairingPinState.current().pin
    fun currentHostHint(): String = hostHint
    fun currentServerId(): String = serverId
    fun currentFingerprint(): String = certFingerprintSha256
    fun isPaired(): Boolean = !pairedDeviceId.isNullOrBlank() && !activeToken.isNullOrBlank()

    fun currentPairingPayload(): String {
        return currentSnapshot().pairingPayload.orEmpty()
    }

    fun currentSnapshot(): CommandCenterSnapshot {
        val validHost = sanitizeLanHost(hostHint)
        return CommandCenterSnapshot(
            host = validHost,
            port = port,
            pin = pairingPinState.current().pin,
            serverId = serverId,
            fingerprint = certFingerprintSha256,
            pairedDeviceId = pairedDeviceId,
            isPaired = isPaired(),
            networkErrorMessage = if (validHost == null) {
                networkErrorMessage ?: "No se pudo resolver una IP LAN válida para este Mac."
            } else {
                null
            },
        )
    }

    fun start() {
        if (server != null) return

        val https = HttpsServer.create(InetSocketAddress(port), 0)
        https.executor = Executors.newCachedThreadPool()
        val sslContext = tlsIdentity.sslContext()
        https.httpsConfigurator = HttpsConfigurator(sslContext)

        https.createContext("/sync/handshake") { ex ->
            if (ex.requestMethod != "POST") {
                ex.respond(405, """{"error":"method_not_allowed"}""")
                return@createContext
            }
            val origin = ex.remoteAddress?.address?.hostAddress ?: "unknown"
            if (!pairingAttemptLimiter.isAllowed(origin)) {
                ex.respond(429, """{"error":"pairing_temporarily_unavailable"}""")
                return@createContext
            }
            val body = ex.readBodyOrReject(HANDSHAKE_BODY_LIMIT_BYTES) ?: return@createContext
            val obj = runCatching { json.parseToJsonElement(body).jsonObject }.getOrNull()
            val pin = obj?.get("pin")?.jsonPrimitive?.contentOrNull
            val deviceId = obj?.get("deviceId")?.jsonPrimitive?.contentOrNull ?: "ios"
            val activePin = pairingPinState.current()
            if (activePin.rotated) {
                notifyStatusChanged()
            }

            if (pin == null || pin != activePin.pin) {
                pairingAttemptLimiter.recordFailure(origin)
                println("❌ Handshake LAN rechazado por credenciales no válidas.")
                ex.respond(401, """{"error":"invalid_pin"}""")
                return@createContext
            }

            if (!pairedDeviceId.isNullOrBlank() && pairedDeviceId != deviceId) {
                println("❌ Handshake LAN rechazado: el servidor ya está vinculado.")
                ex.respond(409, """{"error":"already_paired"}""")
                return@createContext
            }

            val token = activeToken ?: UUID.randomUUID().toString().also { newToken ->
                activeToken = newToken
                secureStore.put("paired-token", newToken)
            }
            pairedDeviceId = deviceId
            secureStore.put("paired-device-id", deviceId)
            pairingAttemptLimiter.recordSuccess(origin)
            pairingPinState.rotate()

            println("✅ Handshake LAN completado. Credenciales rotadas.")
            notifyStatusChanged()
            refreshBonjourService()

            ex.respond(200, buildJsonObject {
                put("token", JsonPrimitive(token))
                put("deviceId", JsonPrimitive(deviceId))
                put("serverId", JsonPrimitive(serverId))
                put("certificateFingerprint", JsonPrimitive(certFingerprintSha256))
                put("protocol", JsonPrimitive("https"))
                put("serverEpochMs", JsonPrimitive(System.currentTimeMillis()))
            }.toString())
        }

        https.createContext("/sync/pull") { ex ->
            if (ex.requestMethod != "GET") {
                ex.respond(405, """{"error":"method_not_allowed"}""")
                return@createContext
            }
            if (!isAuthorized(ex)) return@createContext
            val query = parseQueryParams(ex.requestURI.query)
            val since = query["since"]?.toLongOrNull() ?: 0L
            val requestingDeviceId = query["deviceId"]
            val response = kotlinx.coroutines.runBlocking {
                println("📥 Recibida solicitud de PULL (desde epoch: $since)")
                syncCoordinator.pullChanges(sinceEpochMs = since, serverNowEpochMs = System.currentTimeMillis())
            }
            // Un dispositivo nunca necesita que le devuelvan sus propios cambios: ya
            // los tiene aplicados localmente. Sin este filtro, cada pull re-descarga
            // y re-aplica (de forma redonda pero costosa) todo lo que el propio
            // dispositivo acaba de empujar, incluido el full-pull periódico.
            val filteredChanges = filterDesktopChangesForSse(response.changes, requestingDeviceId)
            ex.respond(200, encodePullResponse(response.copy(changes = filteredChanges)))
        }

        https.createContext("/sync/events") { ex ->
            if (ex.requestMethod != "GET") {
                ex.respond(405, """{"error":"method_not_allowed"}""")
                return@createContext
            }
            if (!isAuthorized(ex)) return@createContext

            ex.responseHeaders.add("Content-Type", "text/event-stream")
            ex.responseHeaders.add("Cache-Control", "no-cache")
            ex.responseHeaders.add("Connection", "keep-alive")
            ex.sendResponseHeaders(200, 0)

            val out = ex.responseBody
            sseConnections.add(ex)
            println("📡 Conexión SSE abierta.")

            try {
                // `ex` también es el lock usado por broadcastSseEvent para esta misma
                // conexión: sin esto, un evento de sync y el keep-alive pueden escribir
                // al mismo tiempo en el stream y entrelazar sus bytes, corrompiendo el
                // frame SSE que lee el cliente.
                synchronized(ex) {
                    out.write(": ok\n\n".toByteArray())
                    out.flush()
                }
            } catch (e: Exception) {
                sseConnections.remove(ex)
                runCatching { ex.close() }
                return@createContext
            }

            try {
                while (server != null && sseConnections.contains(ex)) {
                    Thread.sleep(15000)
                    try {
                        synchronized(ex) {
                            out.write(": keep-alive\n\n".toByteArray())
                            out.flush()
                        }
                    } catch (e: Exception) {
                        break
                    }
                }
            } catch (e: InterruptedException) {
                // Interrupted
            } finally {
                sseConnections.remove(ex)
                runCatching { ex.close() }
                println("📡 Conexión SSE cerrada.")
            }
        }

        https.createContext("/sync/push") { ex ->
            if (ex.requestMethod != "POST") {
                ex.respond(405, """{"error":"method_not_allowed"}""")
                return@createContext
            }
            if (!isAuthorized(ex)) return@createContext
            val body = ex.readBodyOrReject(SYNC_BODY_LIMIT_BYTES) ?: return@createContext
            val req = decodePushRequest(body)
            val ack = kotlinx.coroutines.runBlocking {
                println("📤 Recibida solicitud de PUSH (${req.changes.size} cambios)")
                syncCoordinator.pushChanges(req, serverNowEpochMs = System.currentTimeMillis())
            }
            ex.respond(200, encodeAck(ack))

            if (req.changes.isNotEmpty()) {
                broadcastSseEvent(req.changes, ack.serverEpochMs)
            }
        }

        https.createContext("/sync/local-changes") { ex ->
            if (ex.requestMethod != "POST") {
                ex.respond(405, """{"error":"method_not_allowed"}""")
                return@createContext
            }
            if (!isLoopbackSyncRequest(ex.remoteAddress?.address)) {
                ex.respond(403, """{"error":"loopback_only"}""")
                return@createContext
            }

            val body = ex.readBodyOrReject(SYNC_BODY_LIMIT_BYTES) ?: return@createContext
            val changes = decodeLocalChangesRequest(body)
            val desktopChanges = filterDesktopChangesForSse(changes, pairedDeviceId)
            if (desktopChanges.isNotEmpty()) {
                broadcastSseEvent(desktopChanges, System.currentTimeMillis())
            }
            ex.respond(200, buildJsonObject {
                put("accepted", JsonPrimitive(changes.size))
                put("broadcast", JsonPrimitive(desktopChanges.size))
            }.toString())
        }

        https.createContext("/sync/documents") { ex ->
            if (!isAuthorized(ex)) return@createContext
            val hash = ex.requestURI.path.substringAfterLast('/').lowercase()
            if (!hash.matches(Regex("[a-f0-9]{64}"))) {
                ex.respond(400, """{"error":"invalid_hash"}""")
                return@createContext
            }
            val target = File(learningSituationDocumentsDirectory, "$hash.docx")
            when (ex.requestMethod) {
                "HEAD" -> {
                    if (target.exists()) ex.respondEmpty(200) else ex.respondEmpty(404)
                }
                "GET" -> {
                    if (!target.exists()) {
                        ex.respond(404, """{"error":"not_found"}""")
                    } else {
                        ex.respondBinary(200, target.readBytes(), "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
                    }
                }
                "PUT" -> {
                    val bytes = ex.readBytesOrReject(DOCUMENT_BODY_LIMIT_BYTES) ?: return@createContext
                    val actualHash = MessageDigest.getInstance("SHA-256")
                        .digest(bytes)
                        .joinToString("") { "%02x".format(it) }
                    if (actualHash != hash) {
                        ex.respond(409, """{"error":"hash_mismatch"}""")
                    } else {
                        target.writeBytes(bytes)
                        ex.respond(200, """{"ok":true}""")
                    }
                }
                else -> ex.respond(405, """{"error":"method_not_allowed"}""")
            }
        }

        https.createContext("/sync/unpair") { ex ->
            if (ex.requestMethod != "POST") {
                ex.respond(405, """{"error":"method_not_allowed"}""")
                return@createContext
            }
            if (!isAuthorized(ex)) return@createContext
            revokePairingInternal()
            ex.respond(200, """{"ok":true}""")
        }

        https.start()
        server = https
        publishBonjour()
        startNetworkMonitor()
        startDbMonitor()
        notifyStatusChanged()
    }

    fun revokePairing() {
        revokePairingInternal()
    }

    fun stop() {
        stopNetworkMonitor()
        stopDbMonitor()
        server?.stop(0)
        server = null

        val connections = sseConnections.toList()
        sseConnections.clear()
        connections.forEach { runCatching { it.close() } }

        serviceInfo?.let { jmDns?.unregisterService(it) }
        serviceInfo = null
        jmDns?.close()
        jmDns = null
        advertisedLanAddress = null
        networkErrorMessage = null
        notifyStatusChanged()
    }

    private fun revokePairingInternal() {
        pairedDeviceId = null
        activeToken = null
        secureStore.delete("paired-device-id")
        secureStore.delete("paired-token")
        pairingPinState.rotate()
        notifyStatusChanged()
        refreshBonjourService()
    }

    private fun publishBonjour() {
        val localAddress = resolveLanAddressOrNull()
        if (localAddress == null) {
            advertisedLanAddress = null
            hostHint = "localhost"
            networkErrorMessage = "No se pudo resolver una IP LAN válida para este Mac."
            notifyStatusChanged()
            return
        }

        runCatching {
            hostHint = localAddress.hostAddress ?: hostHint
            advertisedLanAddress = localAddress
            networkErrorMessage = null
            notifyStatusChanged()
            jmDns = JmDNS.create(localAddress)
            serviceInfo = ServiceInfo.create(
                "_migestor-sync._tcp.local.",
                "MiGestorDesktop-$serverId",
                port,
                0,
                0,
                buildBonjourTxtMap()
            )
            jmDns?.registerService(serviceInfo)
        }.onFailure {
            advertisedLanAddress = null
            networkErrorMessage = "No se pudo publicar el servicio LAN en esta red."
            notifyStatusChanged()
        }
    }

    private fun startNetworkMonitor() {
        if (networkMonitor != null) return
        networkMonitor = Executors.newSingleThreadScheduledExecutor().also { scheduler ->
            scheduler.scheduleAtFixedRate(
                { refreshNetworkBindingIfNeeded() },
                8L,
                8L,
                TimeUnit.SECONDS
            )
        }
    }

    private fun stopNetworkMonitor() {
        networkMonitor?.shutdownNow()
        networkMonitor = null
    }

    private fun startDbMonitor() {
        if (dbMonitor != null) return
        lastCheckedDbTimestamp = System.currentTimeMillis()
        dbMonitor = Executors.newSingleThreadScheduledExecutor().also { scheduler ->
            scheduler.scheduleAtFixedRate(
                {
                    runCatching {
                        kotlinx.coroutines.runBlocking {
                            val now = System.currentTimeMillis()
                            val response = syncCoordinator.pullChanges(sinceEpochMs = lastCheckedDbTimestamp, serverNowEpochMs = now)
                            val changes = filterDesktopChangesForSse(response.changes, pairedDeviceId)
                            if (changes.isNotEmpty()) {
                                println("📡 DB Monitor: Encontrados ${changes.size} cambios locales. Retransmitiendo...")
                                broadcastSseEvent(changes, now)
                            }
                            lastCheckedDbTimestamp = now
                        }
                    }.onFailure { e ->
                        println("❌ Error en DB Monitor: ${e.message}")
                    }
                },
                3L,
                3L,
                TimeUnit.SECONDS
            )
        }
    }

    private fun stopDbMonitor() {
        dbMonitor?.shutdownNow()
        dbMonitor = null
    }

    private fun refreshNetworkBindingIfNeeded() {
        if (pairingPinState.current().rotated) {
            notifyStatusChanged()
        }
        val resolved = resolveLanAddressOrNull()
        if (resolved == null) {
            advertisedLanAddress = null
            hostHint = "localhost"
            networkErrorMessage = "No se pudo resolver una IP LAN válida para este Mac."
            notifyStatusChanged()
            return
        }

        runCatching {
            val previousHost = advertisedLanAddress?.hostAddress
            val currentHost = resolved.hostAddress
            if (currentHost.isNullOrBlank()) {
                networkErrorMessage = "No se pudo resolver una IP LAN válida para este Mac."
                notifyStatusChanged()
                return
            }
            if (currentHost == previousHost) return

            hostHint = currentHost
            networkErrorMessage = null
            notifyStatusChanged()
            republishBonjourOn(resolved)
        }.onFailure {
            networkErrorMessage = "No se pudo republicar el servicio LAN en esta red."
            notifyStatusChanged()
        }
    }

    private fun republishBonjourOn(address: InetAddress) {
        runCatching {
            serviceInfo?.let { jmDns?.unregisterService(it) }
            serviceInfo = null
            jmDns?.close()
            jmDns = JmDNS.create(address)
            advertisedLanAddress = address
            serviceInfo = ServiceInfo.create(
                "_migestor-sync._tcp.local.",
                "MiGestorDesktop-$serverId",
                port,
                0,
                0,
                buildBonjourTxtMap()
            )
            serviceInfo?.let { jmDns?.registerService(it) }
            networkErrorMessage = null
            notifyStatusChanged()
        }.onFailure {
            networkErrorMessage = "No se pudo republicar el servicio LAN en esta red."
            notifyStatusChanged()
        }
    }

    private fun refreshBonjourService() {
        runCatching {
            val service = serviceInfo
            val dns = jmDns
            if (service != null && dns != null) {
                dns.unregisterService(service)
                serviceInfo = ServiceInfo.create(
                    "_migestor-sync._tcp.local.",
                    "MiGestorDesktop-$serverId",
                    port,
                    0,
                    0,
                    buildBonjourTxtMap()
                )
                serviceInfo?.let { dns.registerService(it) }
            }
        }
    }

    private fun buildBonjourTxtMap(): Map<String, String> {
        // El PIN NUNCA debe publicarse por Bonjour: el registro TXT es legible por
        // cualquier dispositivo de la red local sin necesidad de ver el QR/pantalla
        // del Mac, lo que anularía por completo la protección del PIN de emparejamiento.
        // El cliente iOS ya no lo lee de aquí (ver LanSyncDiscovery.emitHosts).
        return mapOf(
            "sid" to serverId,
            "proto" to "https",
            "fp" to certFingerprintSha256,
            "paired" to if (isPaired()) "1" else "0",
        )
    }

    private fun resolveLanAddressOrNull(): InetAddress? {
        val candidates = NetworkInterface.getNetworkInterfaces()
            ?.toList()
            .orEmpty()
            .asSequence()
            .filter { it.isUp && !it.isLoopback && !it.isVirtual }
            .flatMap { networkInterface ->
                networkInterface.inetAddresses.toList().asSequence()
                    .filter { address ->
                        !address.isLoopbackAddress &&
                            !address.isLinkLocalAddress &&
                            address.hostAddress?.contains(":") == false
                    }
                    .map { address -> networkInterface.name to address }
            }
            .toList()

        return selectPreferredLanAddress(candidates)
    }

    private fun sanitizeLanHost(host: String?): String? {
        val normalized = host?.trim().orEmpty()
        if (normalized.isEmpty()) return null
        if (normalized == "localhost" || normalized == "127.0.0.1") return null
        return normalized
    }

    private fun isAuthorized(ex: HttpExchange): Boolean {
        if (ex.remoteAddress.address.isLoopbackAddress) {
            return true
        }
        val auth = ex.requestHeaders.getFirst("Authorization")
        val token = auth?.removePrefix("Bearer ")?.trim()
        val authorized = token != null && token == activeToken
        if (!authorized) {
            ex.respond(401, """{"error":"unauthorized"}""")
        }
        return authorized
    }

    private fun decodePushRequest(body: String): SyncPushRequest {
        val root = runCatching { json.parseToJsonElement(body).jsonObject }.getOrElse { JsonObject(emptyMap()) }
        val deviceId = root["clientDeviceId"]?.jsonPrimitive?.contentOrNull ?: "ios"
        val known = root["lastKnownServerEpochMs"]?.jsonPrimitive?.contentOrNull?.toLongOrNull() ?: 0L
        val changesArray = root["changes"]?.jsonArray ?: JsonArray(emptyList())
        val changes = changesArray.mapNotNull { element -> decodeSyncChange(element.jsonObject, deviceId) }
        return SyncPushRequest(
            clientDeviceId = deviceId,
            lastKnownServerEpochMs = known,
            changes = changes
        )
    }

    private fun decodeLocalChangesRequest(body: String): List<SyncChange> {
        val root = runCatching { json.parseToJsonElement(body) }.getOrNull() ?: return emptyList()
        val changesArray = when (root) {
            is JsonArray -> root
            is JsonObject -> root["changes"]?.jsonArray ?: JsonArray(emptyList())
            else -> JsonArray(emptyList())
        }
        return changesArray.mapNotNull { element ->
            runCatching { decodeSyncChange(element.jsonObject, "desktop") }.getOrNull()
        }
    }

    private fun decodeSyncChange(obj: JsonObject, fallbackDeviceId: String): SyncChange? {
        val entity = obj["entity"]?.jsonPrimitive?.contentOrNull ?: return null
        val id = obj["id"]?.jsonPrimitive?.contentOrNull ?: return null
        val updatedAt = obj["updatedAtEpochMs"]?.jsonPrimitive?.contentOrNull?.toLongOrNull() ?: 0L
        val sourceDevice = obj["deviceId"]?.jsonPrimitive?.contentOrNull ?: fallbackDeviceId
        val payload = obj["payload"]?.jsonPrimitive?.contentOrNull ?: "{}"
        val op = obj["op"]?.jsonPrimitive?.contentOrNull ?: "upsert"
        val schemaVersion = obj["schemaVersion"]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: 1
        return SyncChange(entity, id, updatedAt, sourceDevice, payload, op, schemaVersion)
    }

    private fun encodePullResponse(response: SyncPullResponse): String {
        val changes = response.changes.map { change ->
            buildJsonObject {
                put("entity", JsonPrimitive(change.entity))
                put("id", JsonPrimitive(change.id))
                put("updatedAtEpochMs", JsonPrimitive(change.updatedAtEpochMs))
                put("deviceId", JsonPrimitive(change.deviceId))
                put("payload", JsonPrimitive(change.payload))
                put("op", JsonPrimitive(change.op))
                put("schemaVersion", JsonPrimitive(change.schemaVersion))
            }
        }
        return buildJsonObject {
            put("serverEpochMs", JsonPrimitive(response.serverEpochMs))
            put("changes", JsonArray(changes))
        }.toString()
    }

    private fun encodeAck(ack: SyncAck): String {
        return buildJsonObject {
            put("applied", JsonPrimitive(ack.applied))
            put("conflictsResolvedByLww", JsonPrimitive(ack.conflictsResolvedByLww))
            put("serverEpochMs", JsonPrimitive(ack.serverEpochMs))
            put("ignored", JsonPrimitive(ack.ignored))
            put("failed", JsonPrimitive(ack.failed))
        }.toString()
    }

    private fun HttpExchange.readBodyOrReject(maxBytes: Int): String? {
        return readBytesOrReject(maxBytes)?.toString(Charsets.UTF_8)
    }

    private fun HttpExchange.readBytesOrReject(maxBytes: Int): ByteArray? {
        val declaredLength = requestHeaders.getFirst("Content-Length")?.toLongOrNull()
        if (declaredLength != null && declaredLength > maxBytes) {
            respond(413, """{"error":"request_too_large"}""")
            return null
        }
        return try {
            requestBody.use { it.readBytesLimited(maxBytes) }
        } catch (_: RequestBodyTooLargeException) {
            respond(413, """{"error":"request_too_large"}""")
            null
        }
    }

    private fun HttpExchange.respond(status: Int, body: String) {
        responseHeaders.add("Content-Type", "application/json; charset=utf-8")
        val bytes = body.toByteArray()
        sendResponseHeaders(status, bytes.size.toLong())
        responseBody.use { it.write(bytes) }
    }

    private fun HttpExchange.respondEmpty(status: Int) {
        sendResponseHeaders(status, -1)
        close()
    }

    private fun HttpExchange.respondBinary(status: Int, bytes: ByteArray, contentType: String) {
        responseHeaders.add("Content-Type", contentType)
        sendResponseHeaders(status, bytes.size.toLong())
        responseBody.use { it.write(bytes) }
    }

    private fun broadcastSseEvent(changes: List<SyncChange>, serverEpochMs: Long) {
        if (sseConnections.isEmpty()) return

        val entities = changes.map { it.entity }.distinct()

        val eventJson = LanSyncJsonCodec.encodeSyncEventPayload(serverEpochMs, entities, changes)

        val ssePayload = "data: $eventJson\n\n"
        val bytes = ssePayload.toByteArray()

        println("📡 Transmitiendo evento SSE a ${sseConnections.size} clientes...")
        val disconnected = mutableListOf<HttpExchange>()
        for (conn in sseConnections) {
            try {
                synchronized(conn) {
                    val out = conn.responseBody
                    out.write(bytes)
                    out.flush()
                }
            } catch (e: Exception) {
                disconnected.add(conn)
            }
        }
        if (disconnected.isNotEmpty()) {
            sseConnections.removeAll(disconnected)
            disconnected.forEach { runCatching { it.close() } }
        }
    }
}

private class DesktopTlsIdentity(
    private val secureStore: DesktopSecureStore,
) {
    private val keystorePasswordKey = "tls-keystore-password"
    private val keystoreFile = File(getAppDataPath("sync_tls_identity.p12"))
    private val keyAlias = "migestor-sync"

    init {
        if (Security.getProvider("BC") == null) {
            Security.addProvider(BouncyCastleProvider())
        }
    }

    fun sslContext(): SSLContext {
        val password = ensureIdentityReady()
        val keyStore = loadKeyStore(password)

        val kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm())
        kmf.init(keyStore, password.toCharArray())

        val tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
        tmf.init(keyStore)

        return SSLContext.getInstance("TLS").apply {
            init(kmf.keyManagers, tmf.trustManagers, SecureRandom())
        }
    }

    fun certificateFingerprintSha256(): String {
        val cert = loadCertificate()
        val digest = MessageDigest.getInstance("SHA-256").digest(cert.encoded)
        return digest.joinToString("") { "%02x".format(it) }
    }

    private fun loadCertificate(): X509Certificate {
        val password = ensureIdentityReady()
        val keyStore = loadKeyStore(password)
        return keyStore.getCertificate(keyAlias) as X509Certificate
    }

    private fun ensureIdentity(password: String) {
        if (keystoreFile.exists()) return
        keystoreFile.parentFile?.mkdirs()

        val keyPair = KeyPairGenerator.getInstance("RSA").apply {
            initialize(2048)
        }.generateKeyPair()

        val now = Instant.now()
        val notBefore = Date.from(now.minus(1, ChronoUnit.DAYS))
        val notAfter = Date.from(now.plus(3650, ChronoUnit.DAYS))

        val subject = X500Name("CN=MiGestor Sync, O=MiGestor, C=ES")
        val serial = BigInteger(128, SecureRandom())
        val certBuilder: X509v3CertificateBuilder = JcaX509v3CertificateBuilder(
            subject,
            serial,
            notBefore,
            notAfter,
            subject,
            keyPair.public
        )

        val extUtils = JcaX509ExtensionUtils()
        certBuilder.addExtension(Extension.basicConstraints, true, BasicConstraints(false))
        certBuilder.addExtension(
            Extension.keyUsage,
            true,
            KeyUsage(KeyUsage.digitalSignature or KeyUsage.keyEncipherment)
        )
        certBuilder.addExtension(Extension.subjectKeyIdentifier, false, extUtils.createSubjectKeyIdentifier(keyPair.public))

        val signer = JcaContentSignerBuilder("SHA256withRSA")
            .setProvider("BC")
            .build(keyPair.private)

        val certHolder: X509CertificateHolder = certBuilder.build(signer)
        val cert = JcaX509CertificateConverter()
            .setProvider("BC")
            .getCertificate(certHolder)

        val keyStore = KeyStore.getInstance("PKCS12")
        keyStore.load(null, null)
        keyStore.setKeyEntry(keyAlias, keyPair.private, password.toCharArray(), arrayOf(cert))
        keystoreFile.outputStream().use { output ->
            keyStore.store(output, password.toCharArray())
        }
    }

    private fun randomSecret(): String {
        val random = ByteArray(24)
        SecureRandom().nextBytes(random)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(random)
    }

    private fun ensureKeystorePassword(): String {
        return secureStore.get(keystorePasswordKey) ?: randomSecret().also {
            secureStore.put(keystorePasswordKey, it)
        }
    }

    private fun ensureIdentityReady(): String {
        var password = ensureKeystorePassword()
        ensureIdentity(password)

        val isReadable = runCatching {
            loadKeyStore(password)
        }.isSuccess
        if (isReadable) {
            return password
        }

        runCatching { keystoreFile.delete() }
        ensureIdentity(password)
        return password
    }

    private fun loadKeyStore(password: String): KeyStore {
        val keyStore = KeyStore.getInstance("PKCS12")
        keystoreFile.inputStream().use { input ->
            keyStore.load(input, password.toCharArray())
        }
        return keyStore
    }
}

private class DesktopSecureStore(
    private val serviceName: String,
) {
    private val prefs = Preferences.userRoot().node("com.migestor.sync.desktop.fallback")

    fun get(key: String): String? {
        return readFromMacKeychain(key) ?: prefs.get(key, null)
    }

    fun put(key: String, value: String) {
        if (!writeToMacKeychain(key, value)) {
            prefs.put(key, value)
            prefs.flushSafely()
        }
    }

    fun delete(key: String) {
        if (!deleteFromMacKeychain(key)) {
            prefs.remove(key)
            prefs.flushSafely()
        }
    }

    private fun readFromMacKeychain(account: String): String? {
        if (!isMac()) return null
        return runCatching {
            val process = ProcessBuilder(
                "security", "find-generic-password",
                "-a", account,
                "-s", serviceName,
                "-w"
            ).start()
            val output = process.inputStream.bufferedReader().readText().trim()
            val code = process.waitFor()
            if (code == 0 && output.isNotBlank()) output else null
        }.getOrNull()
    }

    private fun writeToMacKeychain(account: String, value: String): Boolean {
        if (!isMac()) return false
        return runCatching {
            val process = ProcessBuilder(
                "security", "add-generic-password",
                "-a", account,
                "-s", serviceName,
                "-w", value,
                "-U"
            ).start()
            process.waitFor() == 0
        }.getOrDefault(false)
    }

    private fun deleteFromMacKeychain(account: String): Boolean {
        if (!isMac()) return false
        return runCatching {
            val process = ProcessBuilder(
                "security", "delete-generic-password",
                "-a", account,
                "-s", serviceName
            ).start()
            process.waitFor() == 0
        }.getOrDefault(false)
    }

    private fun isMac(): Boolean =
        System.getProperty("os.name")?.lowercase()?.contains("mac") == true
}

private fun Preferences.flushSafely() {
    runCatching { flush() }
}

data class SyncServerStatus(
    val isPaired: Boolean,
    val pairedDeviceId: String?,
    val pin: String,
    val serverId: String,
    val pairingPayload: String,
    val host: String
)

data class CommandCenterSnapshot(
    val host: String?,
    val port: Int,
    val pin: String,
    val serverId: String,
    val fingerprint: String,
    val pairedDeviceId: String?,
    val isPaired: Boolean,
    val networkErrorMessage: String?,
) {
    val pairingPayload: String?
        get() {
            val resolvedHost = host ?: return null
            return "migestor://pair?host=$resolvedHost&port=$port&pin=$pin&sid=$serverId&fp=$fingerprint"
        }
}
