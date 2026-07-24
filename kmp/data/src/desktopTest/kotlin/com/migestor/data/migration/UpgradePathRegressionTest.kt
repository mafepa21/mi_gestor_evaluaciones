package com.migestor.data.migration

import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.platform.createSharedDesktopDriver
import com.migestor.data.repository.queryStrings
import com.migestor.data.repository.scalarLong
import java.io.File
import java.nio.file.Files
import java.sql.DriverManager
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * El camino que recorre CADA usuaria real: una base de datos creada por una
 * version anterior de la app se abre con la version actual (migraciones .sqm
 * + migraciones de rescate + tablas del planner). Hasta ahora ningun test
 * cubria ese camino: todos los tests crean la base desde cero, que es el
 * camino que solo recorren las instalaciones nuevas.
 *
 * La fixture committeada en resources/fixtures/upgrade queda congelada en la
 * version de esquema del dia en que se genero. Cuando se añada la proxima
 * migracion, estos tests la ejecutaran automaticamente sobre datos realistas.
 * Regenerar la fixture (borrar + re-ejecutar tests + commit) solo debe
 * hacerse DESPUES de que la migracion nueva haya pasado en verde sobre la
 * fixture antigua.
 */
class UpgradePathRegressionTest {
    private lateinit var workDir: File

    @BeforeTest
    fun createWorkDir() {
        workDir = Files.createTempDirectory("migestor-upgrade-test-").toFile()
    }

    @AfterTest
    fun cleanUp() {
        workDir.deleteRecursively()
    }

    private fun openFixtureCopyWithProductionPath(): JdbcSqliteDriver {
        val fixture = CanonicalTeacherDataset.ensureFixture()
        val copy = File(workDir, "upgrade_probe.db")
        fixture.copyTo(copy)
        return createSharedDesktopDriver(dbPath = copy.absolutePath, dbName = copy.name)
    }

    @Test
    fun `la base de una version anterior migra sin perder ningun dato del curso`() {
        val fixture = CanonicalTeacherDataset.ensureFixture()

        val storedVersion = DriverManager.getConnection("jdbc:sqlite:${fixture.absolutePath}").use { connection ->
            connection.createStatement().use { statement ->
                statement.executeQuery("PRAGMA user_version").use { result ->
                    result.next()
                    result.getLong(1)
                }
            }
        }
        assertTrue(
            storedVersion in 1..AppDatabase.Schema.version,
            "la fixture declara la version $storedVersion, fuera del rango migrable",
        )

        val driver = openFixtureCopyWithProductionPath()
        try {
            assertEquals(
                AppDatabase.Schema.version,
                driver.scalarLong("PRAGMA user_version"),
                "tras abrir, la base debe estar en la version de esquema actual",
            )
            assertEquals(listOf("ok"), driver.queryStrings("PRAGMA integrity_check"), "integridad SQLite")
            assertEquals(
                emptyList(),
                driver.queryStrings("SELECT 'violacion en tabla ' || \"table\" FROM pragma_foreign_key_check"),
                "no puede haber claves foraneas rotas tras migrar",
            )
            CanonicalTeacherDataset.assertSurvived(driver)
        } finally {
            driver.close()
        }
    }

    @Test
    fun `instalacion nueva y instalacion migrada exponen el mismo esquema`() {
        // Si este test falla, usuarias nuevas y usuarias que actualizan tienen
        // bases de datos distintas: el bug se manifestara solo en un grupo y
        // sera casi imposible de reproducir. Suele significar que un .sqm y el
        // .sq (o una migracion de rescate) han dejado de contar la misma historia.
        val freshDb = File(workDir, "fresh_install_probe.db")
        val fresh = createSharedDesktopDriver(dbPath = freshDb.absolutePath, dbName = freshDb.name)
        val upgraded = openFixtureCopyWithProductionPath()
        try {
            assertEquals(schemaSnapshot(fresh), schemaSnapshot(upgraded))
        } finally {
            fresh.close()
            upgraded.close()
        }
    }

    /** Mapa tabla -> definicion de columnas (nombre, tipo, notnull, default, pk). */
    private fun schemaSnapshot(driver: JdbcSqliteDriver): Map<String, List<String>> {
        val tables = driver.queryStrings(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        return tables.associateWith { table ->
            driver.executeQuery(
                identifier = null,
                sql = "PRAGMA table_info(\"$table\")",
                mapper = { cursor ->
                    val columns = mutableListOf<String>()
                    while (cursor.next().value) {
                        columns.add(
                            listOf(
                                cursor.getString(1),
                                cursor.getString(2),
                                cursor.getLong(3)?.toString(),
                                cursor.getString(4) ?: "NULL",
                                cursor.getLong(5)?.toString(),
                            ).joinToString("|"),
                        )
                    }
                    QueryResult.Value(columns.sorted().toList())
                },
                parameters = 0,
            ).value
        }
    }
}
