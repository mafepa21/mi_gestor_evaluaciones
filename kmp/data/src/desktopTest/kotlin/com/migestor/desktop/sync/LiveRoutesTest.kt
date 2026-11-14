package com.migestor.desktop.sync

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Before
import org.junit.Test
import java.io.File
import java.net.ServerSocket
import java.net.URL
import java.security.SecureRandom
import java.security.cert.X509Certificate
import javax.net.ssl.HostnameVerifier
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Rutas del canal en directo (`/live`) del helper (canal en directo de torneos), contra un servidor real en loopback. */
class LiveRoutesTest {
    private val localToken = "mac-app-local-live-test-token"
    private lateinit var tempDbFile: File
    private lateinit var driver: JdbcSqliteDriver
    private lateinit var server: LocalSyncServer
    private var port = 0
    private lateinit var sslContext: SSLContext
    private lateinit var pairedToken: String

    // Hora real: el helper rechaza horas a más de 24 h de la suya.
    private val validBody get() = """
        {"v":1,"sessionId":"s-live","tournamentId":"t1","seq":SEQ,"sentAtMs":${System.currentTimeMillis()},"status":"running",
         "scene":"auto","scores":{"11111111-2222-3333-4444-555555555555":[1,2]}}
    """.trimIndent()

    @Before
    fun setUp() {
        tempDbFile = File.createTempFile("test_live_db_", ".db")
        driver = JdbcSqliteDriver("jdbc:sqlite:${tempDbFile.absolutePath}")
        AppDatabase.Schema.create(driver)
        driver.execute(null, "PRAGMA user_version = ${AppDatabase.Schema.version}", 0)
        port = ServerSocket(0).use { it.localPort }
        server = LocalSyncServer(
            port = port,
            container = KmpContainer(driver),
            secureStoreServiceName = "com.migestor.sync.test",
            localClientToken = localToken,
        )
        server.start()
        server.revokePairing()
        sslContext = SSLContext.getInstance("TLS").apply {
            init(null, arrayOf<TrustManager>(object : X509TrustManager {
                override fun getAcceptedIssuers(): Array<X509Certificate>? = null
                override fun checkClientTrusted(certs: Array<X509Certificate>?, authType: String?) {}
                override fun checkServerTrusted(certs: Array<X509Certificate>?, authType: String?) {}
            }), SecureRandom())
        }
        val conn = open("/sync/handshake", "POST")
        conn.doOutput = true
        conn.outputStream.use { it.write("""{"pin":"${server.currentPin()}","deviceId":"ipad-test"}""".toByteArray()) }
        assertEquals(200, conn.responseCode)
        pairedToken = Json.parseToJsonElement(conn.inputStream.bufferedReader().readText())
            .jsonObject["token"]!!.jsonPrimitive.content
    }

    @After
    fun tearDown() {
        server.revokePairing()
        server.stop()
        driver.close()
        tempDbFile.delete()
    }

    private fun open(path: String, method: String, token: String? = null): HttpsURLConnection {
        val conn = URL("https://127.0.0.1:$port$path").openConnection() as HttpsURLConnection
        conn.sslSocketFactory = sslContext.socketFactory
        conn.hostnameVerifier = HostnameVerifier { _, _ -> true }
        conn.requestMethod = method
        conn.connectTimeout = 5_000
        conn.readTimeout = 5_000
        if (token != null) conn.setRequestProperty("Authorization", "Bearer $token")
        return conn
    }

    private fun post(path: String, body: String, token: String? = pairedToken): HttpsURLConnection {
        val conn = open(path, "POST", token)
        conn.doOutput = true
        conn.outputStream.use { it.write(body.toByteArray()) }
        return conn
    }

    @Test
    fun postSinTokenDa401() {
        assertEquals(401, post("/live/state", validBody.replace("SEQ", "1"), token = null).responseCode)
        assertEquals(401, open("/live/events", "GET").responseCode)
    }

    @Test
    fun rutasParecidasDan404() {
        assertEquals(404, open("/live/otra", "GET", pairedToken).responseCode)
        assertEquals(404, open("/liveXYZ", "GET", pairedToken).responseCode)
        assertEquals(404, open("/live", "GET", pairedToken).responseCode)
    }

    @Test
    fun postValidoAceptaYElViejoNo() {
        val first = post("/live/state", validBody.replace("SEQ", "1"))
        assertEquals(200, first.responseCode)
        val json = Json.parseToJsonElement(first.inputStream.bufferedReader().readText()).jsonObject
        assertEquals("true", json["accepted"]!!.jsonPrimitive.content)
        assertEquals("0", json["listeners"]!!.jsonPrimitive.content)

        val again = post("/live/state", validBody.replace("SEQ", "1"))
        assertEquals(200, again.responseCode)
        assertEquals("false", Json.parseToJsonElement(again.inputStream.bufferedReader().readText())
            .jsonObject["accepted"]!!.jsonPrimitive.content)
    }

    @Test
    fun invalidoDa400YGrandeDa413() {
        assertEquals(400, post("/live/state", """{"v":1}""").responseCode)
        assertEquals(413, post("/live/state", "x".repeat(LIVE_BODY_LIMIT_BYTES + 1)).responseCode)
    }

    @Test
    fun getDiagnosticoYSse() {
        assertEquals(204, open("/live/state", "GET", localToken).responseCode)
        assertEquals(200, post("/live/state", validBody.replace("SEQ", "1")).responseCode)

        val get = open("/live/state", "GET", localToken)
        assertEquals(200, get.responseCode)
        assertEquals("s-live", Json.parseToJsonElement(get.inputStream.bufferedReader().readText())
            .jsonObject["sessionId"]!!.jsonPrimitive.content)

        val sse = open("/live/events", "GET", localToken)
        assertEquals(200, sse.responseCode)
        val reader = sse.inputStream.bufferedReader()
        assertEquals(": ok", reader.readLine())
        reader.readLine() // línea en blanco tras ": ok"
        val first = reader.readLine()
        assertTrue(first.startsWith("data: {"), first)
        reader.readLine()

        val second = post("/live/state", validBody.replace("SEQ", "2"))
        val listeners = Json.parseToJsonElement(second.inputStream.bufferedReader().readText())
            .jsonObject["listeners"]!!.jsonPrimitive.content
        assertEquals("1", listeners)
        val line = reader.readLine()
        assertTrue(line.startsWith("data: {") && line.contains("\"seq\":2"), line)
        sse.disconnect()
    }
}
