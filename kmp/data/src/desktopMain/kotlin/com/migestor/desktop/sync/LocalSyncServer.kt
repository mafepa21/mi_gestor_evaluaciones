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
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import java.util.prefs.Preferences
import javax.jmdns.JmDNS
import javax.jmdns.ServiceInfo
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManagerFactory

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

class LocalSyncServer(
    private val port: Int = 8765,
    private val syncCoordinator: SyncCoordinator = SyncCoordinator(InMemorySyncAdapter()),
    private val stateListener: ((CommandCenterSnapshot) -> Unit)? = null,
    private val dataChangeListener: ((Set<String>) -> Unit)? = null,
) {
    private companion object {
        const val DESKTOP_AUTHORITATIVE_DIFF_THRESHOLD = 20
    }

    private val json = Json { ignoreUnknownKeys = true }
    private var server: HttpsServer? = null
    private var jmDns: JmDNS? = null
    private var serviceInfo: ServiceInfo? = null
    private var networkMonitor: ScheduledExecutorService? = null
    private var desktopChangeScanner: ScheduledExecutorService? = null
    private val sseClients = CopyOnWriteArrayList<HttpExchange>()
    private val lastDesktopChangeCursorMs = AtomicLong(0L)
    @Volatile
    private var advertisedLanAddress: InetAddress? = null

    private val secureStore = DesktopSecureStore(serviceName = "com.migestor.sync.desktop")
    private val tlsIdentity = DesktopTlsIdentity(secureStore)

    @Volatile
    private var pairingPin: String = (100000..999999).random().toString()
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
            pin = pairingPin,
            serverId = serverId,
            pairingPayload = snapshot.pairingPayload.orEmpty(),
            host = snapshot.host ?: "",
        )
    }

    private fun notifyStatusChanged() {
        _status.value = createStatus()
        stateListener?.invoke(currentSnapshot())
    }


    fun currentPin(): String = pairingPin
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
            pin = pairingPin,
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
            val body = ex.readBody()
            val obj = runCatching { json.parseToJsonElement(body).jsonObject }.getOrNull()
            val pin = obj?.get("pin")?.jsonPrimitive?.contentOrNull
            val deviceId = obj?.get("deviceId")?.jsonPrimitive?.contentOrNull ?: "ios"

            println("🔗 Recibida solicitud de handshake LAN desde $deviceId con PIN: $pin")

            if (pin == null || pin != pairingPin) {
                println("❌ Handshake fallido: PIN incorrecto (Recibido: $pin, Esperado: $pairingPin)")
                ex.respond(401, """{"error":"invalid_pin"}""")
                return@createContext
            }

            if (!pairedDeviceId.isNullOrBlank() && pairedDeviceId != deviceId) {
                println("❌ Handshake fallido: Servidor ya vinculado a '$pairedDeviceId'. Solicitud desde '$deviceId'")
                ex.respond(409, """{"error":"already_paired"}""")
                return@createContext
            }

            val token = activeToken ?: UUID.randomUUID().toString().also { newToken ->
                activeToken = newToken
                secureStore.put("paired-token", newToken)
            }
            pairedDeviceId = deviceId
            lastDesktopChangeCursorMs.set(0L)
            secureStore.put("paired-device-id", deviceId)

            println("✅ Handshake exitoso para '$deviceId'. Token emitido.")
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
            val since = ex.requestURI.query
                ?.split("&")
                ?.mapNotNull { part ->
                    val kv = part.split("=")
                    if (kv.size == 2 && kv[0] == "since") kv[1].toLongOrNull() else null
                }
                ?.firstOrNull() ?: 0L
            val response = kotlinx.coroutines.runBlocking {
                println("📥 Recibida solicitud de PULL (desde epoch: $since)")
                syncCoordinator.pullChanges(sinceEpochMs = since, serverNowEpochMs = System.currentTimeMillis())
            }
            ex.respond(200, encodePullResponse(response))
        }

        https.createContext("/sync/push") { ex ->
            if (ex.requestMethod != "POST") {
                ex.respond(405, """{"error":"method_not_allowed"}""")
                return@createContext
            }
            if (!isAuthorized(ex)) return@createContext
            val req = decodePushRequest(ex.readBody())
            val serverNow = System.currentTimeMillis()
            val desktopWins = shouldPreferDesktopState(req, serverNow)
            val ack = if (desktopWins) {
                println("🛡️ PUSH descartado: divergencia grande; prevalece el estado de macOS (${req.changes.size} cambios iOS)")
                SyncAck(
                    applied = 0,
                    conflictsResolvedByLww = 0,
                    serverEpochMs = serverNow,
                    ignored = req.changes.size,
                    failed = 0,
                )
            } else {
                kotlinx.coroutines.runBlocking {
                    println("📤 Recibida solicitud de PUSH (${req.changes.size} cambios)")
                    syncCoordinator.pushChanges(req, serverNowEpochMs = serverNow)
                }
            }
            if (!desktopWins && ack.applied > 0) {
                dataChangeListener?.invoke(req.changes.map { it.entity }.toSet())
            }
            ex.respond(200, encodeAck(ack, desktopAuthoritative = desktopWins))
        }

        https.createContext("/sync/events") { ex ->
            if (ex.requestMethod != "GET") {
                ex.respond(405, """{"error":"method_not_allowed"}""")
                return@createContext
            }
            if (!isAuthorized(ex)) return@createContext

            ex.responseHeaders.add("Content-Type", "text/event-stream; charset=utf-8")
            ex.responseHeaders.add("Cache-Control", "no-cache")
            ex.responseHeaders.add("Connection", "keep-alive")
            ex.sendResponseHeaders(200, 0)
            sseClients.add(ex)
            writeSseFrame(ex, ": connected\n\n")
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
        startDesktopChangeScanner()
        notifyStatusChanged()
    }

    fun revokePairing() {
        revokePairingInternal()
    }

    fun stop() {
        stopNetworkMonitor()
        stopDesktopChangeScanner()
        closeSseClients()
        server?.stop(0)
        server = null
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
        pairingPin = (100000..999999).random().toString()
        lastDesktopChangeCursorMs.set(0L)
        closeSseClients()
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

    private fun startDesktopChangeScanner() {
        if (desktopChangeScanner != null) return
        desktopChangeScanner = Executors.newSingleThreadScheduledExecutor().also { scheduler ->
            scheduler.execute {
                scanDesktopChanges(notifyClients = false)
            }
            scheduler.scheduleAtFixedRate(
                { scanDesktopChanges(notifyClients = true) },
                1L,
                1L,
                TimeUnit.SECONDS
            )
            scheduler.scheduleAtFixedRate(
                { broadcastSseKeepAlive() },
                15L,
                15L,
                TimeUnit.SECONDS
            )
        }
    }

    private fun stopDesktopChangeScanner() {
        desktopChangeScanner?.shutdownNow()
        desktopChangeScanner = null
    }

    private fun scanDesktopChanges(notifyClients: Boolean) {
        if (!isPaired()) return
        val cursor = lastDesktopChangeCursorMs.get()
        runCatching {
            kotlinx.coroutines.runBlocking {
                syncCoordinator.pullChanges(
                    sinceEpochMs = cursor,
                    serverNowEpochMs = System.currentTimeMillis(),
                )
            }
        }.onSuccess { response ->
            lastDesktopChangeCursorMs.set(response.serverEpochMs)
            val iosDeviceId = pairedDeviceId
            val desktopChanges = response.changes.filter { change ->
                iosDeviceId.isNullOrBlank() || change.deviceId != iosDeviceId
            }
            if (notifyClients && cursor > 0L && desktopChanges.isNotEmpty()) {
                notifyDataChanged(
                    entities = desktopChanges.map { it.entity }.distinct(),
                    serverEpochMs = response.serverEpochMs,
                )
            }
        }.onFailure { error ->
            println("⚠️ No se pudieron escanear cambios locales para SSE: ${error.message}")
        }
    }

    private fun shouldPreferDesktopState(req: SyncPushRequest, serverNowEpochMs: Long): Boolean {
        if (req.changes.size < DESKTOP_AUTHORITATIVE_DIFF_THRESHOLD) return false
        if (req.lastKnownServerEpochMs <= 0L) return true
        val iosDeviceId = pairedDeviceId
        val desktopChanges = runCatching {
            kotlinx.coroutines.runBlocking {
                syncCoordinator.pullChanges(
                    sinceEpochMs = req.lastKnownServerEpochMs,
                    serverNowEpochMs = serverNowEpochMs,
                )
            }.changes.filter { change ->
                iosDeviceId.isNullOrBlank() || change.deviceId != iosDeviceId
            }
        }.getOrDefault(emptyList())
        return desktopChanges.isNotEmpty()
    }

    private fun notifyDataChanged(entities: List<String>, serverEpochMs: Long = System.currentTimeMillis()) {
        if (entities.isEmpty()) return
        val payload = buildJsonObject {
            put("serverEpochMs", JsonPrimitive(serverEpochMs))
            put("entities", JsonArray(entities.map { JsonPrimitive(it) }))
        }.toString()
        val frame = "event: syncChanged\nid: $serverEpochMs\ndata: $payload\n\n"
        broadcastSseFrame(frame)
    }

    private fun broadcastSseKeepAlive() {
        broadcastSseFrame(": keepalive\n\n")
    }

    private fun broadcastSseFrame(frame: String) {
        sseClients.removeIf { client ->
            !writeSseFrame(client, frame)
        }
    }

    private fun writeSseFrame(client: HttpExchange, frame: String): Boolean {
        return runCatching {
            client.responseBody.write(frame.toByteArray(Charsets.UTF_8))
            client.responseBody.flush()
            true
        }.getOrElse {
            runCatching { client.close() }
            false
        }
    }

    private fun closeSseClients() {
        sseClients.forEach { client ->
            runCatching { client.close() }
        }
        sseClients.clear()
    }

    private fun refreshNetworkBindingIfNeeded() {
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
        return mapOf(
            "sid" to serverId,
            "proto" to "https",
            "fp" to certFingerprintSha256,
            "paired" to if (isPaired()) "1" else "0",
            "pin" to pairingPin
        )
    }

    private fun resolveLanAddressOrNull(): InetAddress? {
        return NetworkInterface.getNetworkInterfaces()
            ?.toList()
            ?.asSequence()
            ?.filter { it.isUp && !it.isLoopback && !it.isVirtual }
            ?.flatMap { it.inetAddresses.toList().asSequence() }
            ?.firstOrNull { !it.isLoopbackAddress && !it.isLinkLocalAddress && it.hostAddress?.contains(":") == false }
    }

    private fun sanitizeLanHost(host: String?): String? {
        val normalized = host?.trim().orEmpty()
        if (normalized.isEmpty()) return null
        if (normalized == "localhost" || normalized == "127.0.0.1") return null
        return normalized
    }

    private fun isAuthorized(ex: HttpExchange): Boolean {
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
        val changes = changesArray.mapNotNull { element ->
            val obj = element.jsonObject
            val entity = obj["entity"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            val id = obj["id"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            val updatedAt = obj["updatedAtEpochMs"]?.jsonPrimitive?.contentOrNull?.toLongOrNull() ?: 0L
            val sourceDevice = obj["deviceId"]?.jsonPrimitive?.contentOrNull ?: deviceId
            val payload = obj["payload"]?.jsonPrimitive?.contentOrNull ?: "{}"
            val op = obj["op"]?.jsonPrimitive?.contentOrNull ?: "upsert"
            val schemaVersion = obj["schemaVersion"]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: 1
            SyncChange(entity, id, updatedAt, sourceDevice, payload, op, schemaVersion)
        }
        return SyncPushRequest(
            clientDeviceId = deviceId,
            lastKnownServerEpochMs = known,
            changes = changes
        )
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

    private fun encodeAck(ack: SyncAck, desktopAuthoritative: Boolean = false): String {
        return buildJsonObject {
            put("applied", JsonPrimitive(ack.applied))
            put("conflictsResolvedByLww", JsonPrimitive(ack.conflictsResolvedByLww))
            put("serverEpochMs", JsonPrimitive(ack.serverEpochMs))
            put("ignored", JsonPrimitive(ack.ignored))
            put("failed", JsonPrimitive(ack.failed))
            put("desktopAuthoritative", JsonPrimitive(desktopAuthoritative))
        }.toString()
    }

    private fun HttpExchange.readBody(): String {
        return requestBody.bufferedReader().use { it.readText() }
    }

    private fun HttpExchange.respond(status: Int, body: String) {
        responseHeaders.add("Content-Type", "application/json; charset=utf-8")
        val bytes = body.toByteArray()
        sendResponseHeaders(status, bytes.size.toLong())
        responseBody.use { it.write(bytes) }
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
