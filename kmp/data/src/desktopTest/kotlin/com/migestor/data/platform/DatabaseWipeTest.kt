package com.migestor.data.platform

import com.migestor.data.di.KmpContainer
import com.migestor.data.repository.queryStrings
import com.migestor.data.repository.scalarLong
import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * El borrado total tiene que vaciar TODAS las tablas sin romper la base ni el
 * esquema: la version anterior borraba el fichero SQLite del disco con el driver
 * abierto, y eso invalidaba los descriptores del pool y abortaba el proceso.
 */
class DatabaseWipeTest {
    private lateinit var workDir: File

    @BeforeTest
    fun createWorkDir() {
        workDir = Files.createTempDirectory("migestor-wipe-test-").toFile()
    }

    @AfterTest
    fun cleanUp() {
        workDir.deleteRecursively()
    }

    private fun openDriver() =
        createSharedDesktopDriver(dbPath = File(workDir, "wipe_test.db").absolutePath)

    @Test
    fun `vacia todas las tablas de usuario`() = kotlinx.coroutines.runBlocking {
        val driver = openDriver()
        val container = KmpContainer(driver)
        container.seedDemoDataIfEmpty()

        assertTrue(container.studentsRepository.listStudents().isNotEmpty(), "la siembra debe dejar datos")

        container.wipeAllData()

        val userTables = driver
            .queryStrings("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
        assertTrue(userTables.isNotEmpty(), "el borrado no debe eliminar el esquema")
        for (table in userTables) {
            assertEquals(0L, driver.scalarLong("""SELECT COUNT(*) FROM "$table""""), "la tabla $table deberia estar vacia")
        }
        driver.close()
    }

    @Test
    fun `conserva el esquema y la version, y la base sigue usable`() = kotlinx.coroutines.runBlocking {
        val driver = openDriver()
        val container = KmpContainer(driver)
        container.seedDemoDataIfEmpty()

        val tablesBefore = driver
            .queryStrings("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
        val versionBefore = driver.scalarLong("PRAGMA user_version")

        container.wipeAllData()

        assertEquals(
            tablesBefore,
            driver.queryStrings("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"),
            "el borrado no debe cambiar el conjunto de tablas",
        )
        assertEquals(versionBefore, driver.scalarLong("PRAGMA user_version"), "user_version no debe cambiar")

        // La razon de ser del fix: tras borrar, el mismo driver sigue sirviendo.
        // Con el borrado por fichero, esta escritura fallaba con SQLITE_IOERR.
        val classId = container.saveClass(name = "Grupo tras borrado", course = 1, description = null)
        assertEquals(1L, driver.scalarLong("SELECT COUNT(*) FROM classes WHERE id = $classId"))
        driver.close()
    }

    @Test
    fun `es idempotente sobre una base ya vacia`() = kotlinx.coroutines.runBlocking {
        val driver = openDriver()
        val container = KmpContainer(driver)

        container.wipeAllData()
        container.wipeAllData()

        assertEquals(0L, driver.scalarLong("SELECT COUNT(*) FROM classes"))
        driver.close()
    }
}
