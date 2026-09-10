package com.migestor.desktop.sync

import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import com.migestor.data.platform.getAppDataPath
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
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class LocalSyncServerAdoptionTest {

    private lateinit var tempDbFile: File
    private lateinit var driver: JdbcSqliteDriver
    private lateinit var container: KmpContainer
    private lateinit var server: LocalSyncServer
    private var port: Int = 0
    private lateinit var sslContext: SSLContext
    private lateinit var token: String

    @Before
    fun setUp() {
        tempDbFile = File.createTempFile("test_desktop_db_", ".db")
        driver = JdbcSqliteDriver("jdbc:sqlite:${tempDbFile.absolutePath}")
        AppDatabase.Schema.create(driver)
        driver.execute(null, "PRAGMA user_version = ${AppDatabase.Schema.version}", 0)

        container = KmpContainer(driver)

        // Limpiar posibles archivos de staging previos
        File(getAppDataPath("pending_adopt.db")).delete()
        File(getAppDataPath("pending_adopt.json")).delete()
        File(getAppDataPath("last_adoption.json")).delete()

        port = ServerSocket(0).use { it.localPort }
        server = LocalSyncServer(
            port = port,
            container = container,
        )
        server.start()
        server.revokePairing()

        sslContext = trustAllSslContext()

        // Realizar handshake para obtener token de autorización
        val conn = openHttpsConnection("/sync/handshake", "POST")
        conn.doOutput = true
        conn.outputStream.use {
            it.write("""{"pin":"${server.currentPin()}","deviceId":"test-device"}""".toByteArray())
        }
        val code = conn.responseCode
        if (code != 200) {
            val err = conn.errorStream?.bufferedReader()?.readText()
            println("Handshake failed with code $code: $err")
        }
        assertEquals(200, code)
        val responseBody = conn.inputStream.bufferedReader().readText()
        val json = Json.parseToJsonElement(responseBody).jsonObject
        token = json["token"]!!.jsonPrimitive.content
    }

    @After
    fun tearDown() {
        server.stop()
        driver.close()
        tempDbFile.delete()
        File(getAppDataPath("pending_adopt.db")).delete()
        File(getAppDataPath("pending_adopt.json")).delete()
        File(getAppDataPath("last_adoption.json")).delete()
    }

    private fun openHttpsConnection(path: String, method: String): HttpsURLConnection {
        val url = URL("https://127.0.0.1:$port$path")
        val conn = url.openConnection() as HttpsURLConnection
        conn.sslSocketFactory = sslContext.socketFactory
        conn.hostnameVerifier = HostnameVerifier { _, _ -> true }
        conn.requestMethod = method
        return conn
    }

    private fun trustAllSslContext(): SSLContext {
        val trustAll = arrayOf<TrustManager>(object : X509TrustManager {
            override fun getAcceptedIssuers(): Array<X509Certificate>? = null
            override fun checkClientTrusted(certs: Array<X509Certificate>?, authType: String?) {}
            override fun checkServerTrusted(certs: Array<X509Certificate>?, authType: String?) {}
        })
        val sc = SSLContext.getInstance("TLS")
        sc.init(null, trustAll, SecureRandom())
        return sc
    }

    @Test
    fun getFingerprintReturnsValidJsonAndDigest() {
        val conn = openHttpsConnection("/sync/fingerprint", "GET")
        conn.setRequestProperty("Authorization", "Bearer $token")
        assertEquals(200, conn.responseCode)

        val body = conn.inputStream.bufferedReader().readText()
        val json = Json.parseToJsonElement(body).jsonObject

        assertNotNull(json["digest"]?.jsonPrimitive?.content)
        assertEquals(AppDatabase.Schema.version.toString(), json["schemaVersion"]?.jsonPrimitive?.content)
        assertNotNull(json["countsByEntity"]?.jsonObject)
    }

    @Test
    fun getSnapshotDbExportsConsistentSqliteDatabase() {
        val conn = openHttpsConnection("/sync/snapshot/db", "GET")
        conn.setRequestProperty("Authorization", "Bearer $token")
        assertEquals(200, conn.responseCode)
        assertEquals(AppDatabase.Schema.version.toString(), conn.getHeaderField("X-Schema-Version"))
        assertNotNull(conn.getHeaderField("X-Dataset-Digest"))

        val bytes = conn.inputStream.use { it.readBytes() }
        assertTrue(bytes.size >= 16)
        val magic = bytes.sliceArray(0 until 16).toString(Charsets.US_ASCII)
        assertEquals("SQLite format 3\u0000", magic)

        val tempExport = File.createTempFile("verify_export_", ".db")
        try {
            tempExport.writeBytes(bytes)
            val testDriver = JdbcSqliteDriver("jdbc:sqlite:${tempExport.absolutePath}")
            val userVersion = testDriver.executeQuery(
                null,
                "PRAGMA user_version",
                { cursor -> QueryResult.Value(if (cursor.next().value) cursor.getLong(0) ?: 0L else 0L) },
                0
            ).value
            testDriver.close()
            assertEquals(AppDatabase.Schema.version, userVersion)
        } finally {
            tempExport.delete()
        }
    }

    @Test
    fun postSnapshotDbRejectsSchemaMismatch() {
        val conn = openHttpsConnection("/sync/snapshot/db", "POST")
        conn.setRequestProperty("Authorization", "Bearer $token")
        conn.setRequestProperty("X-Schema-Version", "999999")
        conn.doOutput = true
        conn.outputStream.use { it.write("fake-body".toByteArray()) }

        assertEquals(409, conn.responseCode)
        assertFalse(File(getAppDataPath("pending_adopt.json")).exists())
    }

    @Test
    fun postSnapshotDbRejectsNonSqlitePayload() {
        val conn = openHttpsConnection("/sync/snapshot/db", "POST")
        conn.setRequestProperty("Authorization", "Bearer $token")
        conn.setRequestProperty("X-Schema-Version", AppDatabase.Schema.version.toString())
        conn.doOutput = true
        conn.outputStream.use { it.write("this is definitely not a sqlite database file".toByteArray()) }

        assertEquals(422, conn.responseCode)
        assertFalse(File(getAppDataPath("pending_adopt.json")).exists())
        assertFalse(File(getAppDataPath("pending_adopt.db")).exists())
    }

    @Test
    fun postSnapshotDbValidStagesDatabaseAndUpdatesStatus() {
        // 1. Obtener snapshot válido del GET
        val getConn = openHttpsConnection("/sync/snapshot/db", "GET")
        getConn.setRequestProperty("Authorization", "Bearer $token")
        val validBytes = getConn.inputStream.use { it.readBytes() }

        // 2. POST con el snapshot válido
        val postConn = openHttpsConnection("/sync/snapshot/db", "POST")
        postConn.setRequestProperty("Authorization", "Bearer $token")
        postConn.setRequestProperty("X-Schema-Version", AppDatabase.Schema.version.toString())
        postConn.setRequestProperty("X-Dataset-Digest", "test-valid-digest")
        postConn.doOutput = true
        postConn.outputStream.use { it.write(validBytes) }

        assertEquals(200, postConn.responseCode)

        val pendingMarker = File(getAppDataPath("pending_adopt.json"))
        val pendingDb = File(getAppDataPath("pending_adopt.db"))

        assertTrue(pendingMarker.exists())
        assertTrue(pendingDb.exists())

        val markerJson = Json.parseToJsonElement(pendingMarker.readText()).jsonObject
        assertEquals("test-device", markerJson["sourceDeviceId"]?.jsonPrimitive?.content)
        assertEquals("test-valid-digest", markerJson["digest"]?.jsonPrimitive?.content)
        assertEquals(AppDatabase.Schema.version.toString(), markerJson["schemaVersion"]?.jsonPrimitive?.content)

        // 3. Comprobar /sync/snapshot/status
        val statusConn = openHttpsConnection("/sync/snapshot/status", "GET")
        statusConn.setRequestProperty("Authorization", "Bearer $token")
        assertEquals(200, statusConn.responseCode)
        val statusJson = Json.parseToJsonElement(statusConn.inputStream.bufferedReader().readText()).jsonObject
        assertEquals("staged", statusJson["status"]?.jsonPrimitive?.content)
    }
}
