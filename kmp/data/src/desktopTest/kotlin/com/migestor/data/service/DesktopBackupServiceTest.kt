package com.migestor.data.service

import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.platform.createSharedDesktopDriver
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

    @Test
    fun `createBackup flushes the WAL so recently committed rows are not lost`() = runTest {
        // Regresion: en modo WAL (activo desde createDesktopDriver) un commit
        // reciente puede vivir solo en el fichero -wal hasta el siguiente
        // checkpoint. createBackup copiaba solo el .db principal con
        // Files.copy: el backup "con exito" podia no contener esas ultimas
        // notas si nunca hubo un checkpoint previo.
        val previousUserHome = System.getProperty("user.home")
        val tempHome = Files.createTempDirectory("migestor-backup-wal-test-").toFile()

        try {
            System.setProperty("user.home", tempHome.absolutePath)

            val driver = createSharedDesktopDriver()
            driver.execute(null, "CREATE TABLE t (v TEXT)", 0)
            driver.execute(null, "INSERT INTO t (v) VALUES ('nota-reciente')", 0)
            // Sin checkpoint explicito a proposito: este commit solo vive en el -wal.

            val service = DesktopBackupService()
            val backup = service.createBackup("fixture.sqlite")

            val verifyDriver = JdbcSqliteDriver("jdbc:sqlite:${backup.path}")
            val rows = verifyDriver.executeQuery(
                identifier = null,
                sql = "SELECT v FROM t",
                mapper = { cursor ->
                    val values = mutableListOf<String>()
                    while (cursor.next().value) {
                        cursor.getString(0)?.let(values::add)
                    }
                    QueryResult.Value(values)
                },
                parameters = 0,
            ).value
            verifyDriver.close()
            driver.close()

            assertEquals(listOf("nota-reciente"), rows)
        } finally {
            System.setProperty("user.home", previousUserHome)
            tempHome.deleteRecursively()
        }
    }
}
