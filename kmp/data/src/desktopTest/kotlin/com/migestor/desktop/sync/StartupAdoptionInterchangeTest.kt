package com.migestor.desktop.sync

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Before
import org.junit.Test
import java.io.File
import java.nio.file.Files
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class StartupAdoptionInterchangeTest {

    private lateinit var tempDir: File

    @Before
    fun setUp() {
        tempDir = Files.createTempDirectory("startup_adoption_test_").toFile()
    }

    @After
    fun tearDown() {
        tempDir.deleteRecursively()
    }

    /**
     * Implementación idéntica a la lógica ejecutada en applyPendingAdoptionIfNeeded
     * adaptada a File / I/O para verificación unitaria reproducible.
     */
    private fun applyPendingAdoption(baseDir: File, dbName: String, simulateMoveFailure: Boolean = false): Boolean {
        val pendingMarker = File(baseDir, "pending_adopt.json")
        val pendingDb = File(baseDir, "pending_adopt.db")
        val activeDb = File(baseDir, dbName)

        if (!pendingMarker.exists()) return false

        if (!pendingDb.exists()) {
            pendingMarker.delete()
            return false
        }

        val backupsDir = File(baseDir, "backups").apply { mkdirs() }
        val epoch = System.currentTimeMillis() / 1000
        val backupPath = File(backupsDir, "${epoch}_pre_adopt_$dbName")
        val dbExists = activeDb.exists()

        try {
            if (dbExists) {
                activeDb.copyTo(backupPath, overwrite = true)
                for (suffix in listOf("-wal", "-shm")) {
                    val sidecar = File(baseDir, "$dbName$suffix")
                    if (sidecar.exists()) {
                        sidecar.copyTo(File(backupsDir, "${backupPath.name}$suffix"), overwrite = true)
                    }
                }
            }

            if (simulateMoveFailure) {
                throw IllegalStateException("Simulated disk error during adoption move")
            }

            // 1. Borrar DB activa y sidecars
            if (activeDb.exists()) activeDb.delete()
            for (suffix in listOf("-wal", "-shm")) {
                val sidecar = File(baseDir, "$dbName$suffix")
                if (sidecar.exists()) sidecar.delete()
            }

            // 2. Mover pendingDb a activeDb
            val moved = pendingDb.renameTo(activeDb)
            if (!moved) {
                // Fallback copy + delete
                pendingDb.copyTo(activeDb, overwrite = true)
                pendingDb.delete()
            }

            // 3. Eliminar marcador
            pendingMarker.delete()

            // 4. Escribir last_adoption.json
            val successJson = """{"status":"applied","backupPath":"${backupPath.absolutePath.replace("\\", "/")}","appliedAtEpochMs":${epoch * 1000}}"""
            File(baseDir, "last_adoption.json").writeText(successJson)
            return true
        } catch (e: Throwable) {
            // Rollback defensivo
            if (dbExists && backupPath.exists()) {
                if (activeDb.exists()) activeDb.delete()
                backupPath.copyTo(activeDb, overwrite = true)
                for (suffix in listOf("-wal", "-shm")) {
                    val backupSidecar = File(backupsDir, "${backupPath.name}$suffix")
                    val sidecar = File(baseDir, "$dbName$suffix")
                    if (backupSidecar.exists()) {
                        if (sidecar.exists()) sidecar.delete()
                        backupSidecar.copyTo(sidecar, overwrite = true)
                    }
                }
            }
            val failJson = """{"status":"failed","error":"${e.message}","backupPath":"${backupPath.absolutePath.replace("\\", "/")}","failedAtEpochMs":${epoch * 1000}}"""
            File(baseDir, "last_adoption.json").writeText(failJson)
            pendingMarker.delete()
            return false
        }
    }

    @Test
    fun noOpWhenNoPendingMarkerExists() {
        val activeDb = File(tempDir, "mi_gestor_kmp.db")
        activeDb.writeText("original database content")

        val applied = applyPendingAdoption(tempDir, "mi_gestor_kmp.db")

        assertFalse(applied)
        assertEquals("original database content", activeDb.readText())
        assertFalse(File(tempDir, "last_adoption.json").exists())
        assertFalse(File(tempDir, "backups").exists())
    }

    @Test
    fun cleansOrphanMarkerWhenPendingDbIsMissing() {
        val marker = File(tempDir, "pending_adopt.json")
        marker.writeText("""{"sourceDeviceId":"test"}""")

        val applied = applyPendingAdoption(tempDir, "mi_gestor_kmp.db")

        assertFalse(applied)
        assertFalse(marker.exists())
    }

    @Test
    fun successfulAdoptionReplacesDatabaseCreatesBackupAndWritesMarker() {
        val activeDb = File(tempDir, "mi_gestor_kmp.db")
        activeDb.writeText("initial data before adopt")
        val activeWal = File(tempDir, "mi_gestor_kmp.db-wal")
        activeWal.writeText("initial wal data")

        val pendingDb = File(tempDir, "pending_adopt.db")
        pendingDb.writeText("new data adopted from ipad")
        val marker = File(tempDir, "pending_adopt.json")
        marker.writeText("""{"sourceDeviceId":"ipad-123","schemaVersion":25}""")

        val applied = applyPendingAdoption(tempDir, "mi_gestor_kmp.db")

        assertTrue(applied)
        // La DB activa ahora contiene los datos adoptados
        assertEquals("new data adopted from ipad", activeDb.readText())
        assertFalse(activeWal.exists(), "Sidecar WAL original debe haber sido eliminado")
        assertFalse(pendingDb.exists(), "pending_adopt.db debe haber sido movido")
        assertFalse(marker.exists(), "pending_adopt.json debe haber sido eliminado")

        // El backup existe en backups/
        val backupsDir = File(tempDir, "backups")
        assertTrue(backupsDir.exists())
        val backupFiles = backupsDir.listFiles() ?: emptyArray()
        val dbBackup = backupFiles.firstOrNull { it.name.contains("_pre_adopt_mi_gestor_kmp.db") && !it.name.endsWith("-wal") }
        val walBackup = backupFiles.firstOrNull { it.name.endsWith("-wal") }

        assertNotNull(dbBackup)
        assertEquals("initial data before adopt", dbBackup.readText())
        assertNotNull(walBackup)
        assertEquals("initial wal data", walBackup.readText())

        // last_adoption.json indica status = applied
        val lastJsonFile = File(tempDir, "last_adoption.json")
        assertTrue(lastJsonFile.exists())
        val json = Json.parseToJsonElement(lastJsonFile.readText()).jsonObject
        assertEquals("applied", json["status"]?.jsonPrimitive?.content)
    }

    @Test
    fun failureDuringAdoptionRollsBackOriginalDataAndRecordsFailedStatus() {
        val activeDb = File(tempDir, "mi_gestor_kmp.db")
        activeDb.writeText("initial data to preserve")
        val activeWal = File(tempDir, "mi_gestor_kmp.db-wal")
        activeWal.writeText("wal data to preserve")

        val pendingDb = File(tempDir, "pending_adopt.db")
        pendingDb.writeText("corrupt or failing incoming data")
        val marker = File(tempDir, "pending_adopt.json")
        marker.writeText("""{"sourceDeviceId":"ipad-123"}""")

        val applied = applyPendingAdoption(tempDir, "mi_gestor_kmp.db", simulateMoveFailure = true)

        assertFalse(applied)
        // La DB activa y el WAL han sido restaurados desde el backup
        assertEquals("initial data to preserve", activeDb.readText())
        assertEquals("wal data to preserve", activeWal.readText())

        // last_adoption.json debe registrar failure
        val lastJsonFile = File(tempDir, "last_adoption.json")
        assertTrue(lastJsonFile.exists())
        val json = Json.parseToJsonElement(lastJsonFile.readText()).jsonObject
        assertEquals("failed", json["status"]?.jsonPrimitive?.content)
        assertNotNull(json["error"]?.jsonPrimitive?.content)
    }
}
