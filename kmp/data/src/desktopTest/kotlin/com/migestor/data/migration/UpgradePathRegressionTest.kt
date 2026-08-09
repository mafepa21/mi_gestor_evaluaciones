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

    private fun openFixtureCopyWithCanonicalMigrationsOnly(): JdbcSqliteDriver {
        val fixture = CanonicalTeacherDataset.ensureFixture()
        val copy = File(workDir, "canonical_migrations_probe.db")
        fixture.copyTo(copy)
        val driver = JdbcSqliteDriver("jdbc:sqlite:${copy.absolutePath}")
        val currentVersion = driver.scalarLong("PRAGMA user_version")
        if (currentVersion < AppDatabase.Schema.version) {
            AppDatabase.Schema.migrate(driver, currentVersion, AppDatabase.Schema.version)
            driver.execute(null, "PRAGMA user_version = ${AppDatabase.Schema.version}", 0)
        }
        return driver
    }

    private fun openFreshDatabaseWithCanonicalSchemaOnly(): JdbcSqliteDriver {
        val freshDb = File(workDir, "fresh_without_rescue_comparison.db")
        val driver = JdbcSqliteDriver("jdbc:sqlite:${freshDb.absolutePath}")
        AppDatabase.Schema.create(driver)
        driver.execute(null, "PRAGMA user_version = ${AppDatabase.Schema.version}", 0)
        return driver
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

    @Test
    fun `la fixture soportada alcanza el esquema actual sin depender de rescue migrations`() {
        // Esta ruta omite deliberadamente createSharedDesktopDriver, por lo que no
        // ejecuta runRescueMigrations. Protege contra volver a introducir un gap en
        // la cadena canónica .sqm a partir de la fixture mínima soportada (v34).
        val fresh = openFreshDatabaseWithCanonicalSchemaOnly()
        val migratedOnly = openFixtureCopyWithCanonicalMigrationsOnly()
        try {
            assertEquals(AppDatabase.Schema.version, migratedOnly.scalarLong("PRAGMA user_version"))
            assertEquals(schemaSnapshot(fresh), schemaSnapshot(migratedOnly))
            assertEquals(listOf("ok"), migratedOnly.queryStrings("PRAGMA integrity_check"))
            assertEquals(
                emptyList(),
                migratedOnly.queryStrings("SELECT 'violacion en tabla ' || \"table\" FROM pragma_foreign_key_check"),
            )
            CanonicalTeacherDataset.assertSurvived(migratedOnly)
        } finally {
            fresh.close()
            migratedOnly.close()
        }
    }

    private data class TableSchemaSnapshot(
        val columns: List<String>,
        val indexes: List<String>,
        val foreignKeys: List<String>,
    )

    /**
     * Mapa tabla -> columnas + índices + claves foráneas. Comparar solo columnas
     * dejaba pasar drift de rendimiento o cascadas distintas entre fresh/upgrade.
     */
    private fun schemaSnapshot(driver: JdbcSqliteDriver): Map<String, TableSchemaSnapshot> {
        val tables = driver.queryStrings(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        return tables.associateWith { table ->
            val columns = driver.executeQuery(
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
            val indexes = driver.executeQuery(
                identifier = null,
                sql = "PRAGMA index_list(\"$table\")",
                mapper = { cursor ->
                    val values = mutableListOf<String>()
                    while (cursor.next().value) {
                        values.add(
                            listOf(
                                cursor.getString(1),
                                cursor.getLong(2)?.toString(),
                                cursor.getString(3),
                                cursor.getLong(4)?.toString(),
                            ).joinToString("|"),
                        )
                    }
                    QueryResult.Value(values.sorted())
                },
                parameters = 0,
            ).value
            val foreignKeys = driver.executeQuery(
                identifier = null,
                sql = "PRAGMA foreign_key_list(\"$table\")",
                mapper = { cursor ->
                    val values = mutableListOf<String>()
                    while (cursor.next().value) {
                        values.add(
                            listOf(
                                cursor.getLong(0)?.toString(),
                                cursor.getLong(1)?.toString(),
                                cursor.getString(2),
                                cursor.getString(3),
                                cursor.getString(4),
                                cursor.getString(5),
                                cursor.getString(6),
                                cursor.getString(7),
                            ).joinToString("|"),
                        )
                    }
                    QueryResult.Value(values.sorted())
                },
                parameters = 0,
            ).value
            TableSchemaSnapshot(columns, indexes, foreignKeys)
        }
    }
}
