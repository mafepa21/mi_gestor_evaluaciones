package com.migestor.data.service

import com.migestor.data.platform.getAppDataPath
import kotlinx.coroutines.test.runTest
import java.io.File
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class DesktopBackupServiceTest {
    @Test
    fun `create and restore backup round trip uses fixture database`() = runTest {
        val previousUserHome = System.getProperty("user.home")
        val tempHome = Files.createTempDirectory("migestor-backup-test-").toFile()

        try {
            System.setProperty("user.home", tempHome.absolutePath)
            val database = File(getAppDataPath("desktop_mi_gestor_kmp.db"))
            database.parentFile.mkdirs()
            database.writeText("fixture-before")

            val service = DesktopBackupService()
            val backup = service.createBackup("fixture.sqlite")
            assertTrue(File(backup.path).exists())
            assertEquals("fixture-before".length.toLong(), backup.sizeBytes)

            database.writeText("fixture-after")
            assertTrue(service.restoreBackup(backup.path))

            assertEquals("fixture-before", database.readText())
        } finally {
            System.setProperty("user.home", previousUserHome)
            tempHome.deleteRecursively()
        }
    }
}
