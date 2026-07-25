package com.migestor.data.migration

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.platform.createSharedDesktopDriver
import com.migestor.data.repository.queryStrings
import com.migestor.data.repository.scalarLong
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.sql.DriverManager
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Curso de una docente en miniatura: los datos que un backup, una migracion o
 * una sincronizacion NUNCA pueden perder. Incluye a proposito los casos que
 * historicamente rompen: acentos y enye, comas decimales en formulas, celdas
 * vacias, notas con value NULL pero evidencia, y tombstones de sync.
 *
 * Se usa en dos momentos:
 *  1. [insertInto] puebla la fixture versionada en resources/fixtures/upgrade.
 *  2. [assertSurvived] verifica, tras abrir esa fixture con el camino de
 *     produccion (migraciones + rescates), que cada dato sigue ahi.
 */
internal object CanonicalTeacherDataset {

    // Ruta relativa al modulo kmp/data (directorio de trabajo de los tests).
    // Vive en tests/fixtures/demo_* porque es la unica ubicacion que
    // scripts/verify_no_sensitive_files.sh permite para bases de datos
    // committeadas; el prefijo demo_ declara que los datos son inventados.
    const val FIXTURE_RELATIVE_PATH = "../../tests/fixtures/demo_canonical_teacher.db"

    fun insertInto(driver: JdbcSqliteDriver) {
        val statements = listOf(
            "INSERT INTO classes(id, name, course, description) VALUES (101, '1º ESO B – Educación Física', 1, 'Grupo bilingüe')",

            "INSERT INTO students(id, first_name, last_name, email) VALUES (1, 'Lucía', 'García Pérez', 'lucia@example.com')",
            "INSERT INTO students(id, first_name, last_name, email) VALUES (2, 'Mario', 'Fernández', NULL)",
            "INSERT INTO students(id, first_name, last_name, email) VALUES (3, 'Íñigo', 'Ñuño Ibáñez', NULL)",
            "INSERT INTO students(id, first_name, last_name, email) VALUES (4, 'Aïcha', 'Benaissa', NULL)",
            "INSERT INTO students(id, first_name, last_name, email) VALUES (5, 'Noa', 'Castro', NULL)",
            "INSERT INTO students(id, first_name, last_name, email) VALUES (6, 'Hugo', 'Domínguez', NULL)",

            "INSERT INTO class_students(class_id, student_id) VALUES (101, 1), (101, 2), (101, 3), (101, 4), (101, 5), (101, 6)",

            "INSERT INTO evaluations(id, class_id, code, name, type, weight) VALUES (501, 101, 'EV1', 'Primera Evaluación', 'TRIMESTRAL', 1.0)",

            "INSERT INTO notebook_tabs(id, class_id, title) VALUES ('tab-ev1', 101, 'Primera evaluación')",

            "INSERT INTO notebook_columns(id, class_id, title, type, evaluation_id, weight) VALUES ('col-exam', 101, 'Examen', 'NUMERIC', 501, 0.6)",
            "INSERT INTO notebook_columns(id, class_id, title, type, evaluation_id, weight) VALUES ('col-hw', 101, 'Deberes', 'NUMERIC', 501, 0.4)",
            "INSERT INTO notebook_columns(id, class_id, title, type, formula, weight) VALUES ('col-final', 101, 'Nota final', 'FORMULA', '([Examen] * 0,6) + ([Deberes] * 0,4)', 1.0)",

            "INSERT INTO grades(class_id, student_id, column_id, evaluation_id, value, created_at_epoch_ms) VALUES (101, 1, 'col-exam', 501, 7.35, 1750000000000)",
            "INSERT INTO grades(class_id, student_id, column_id, evaluation_id, value, created_at_epoch_ms) VALUES (101, 1, 'col-hw', 501, 9.0, 1750000000000)",
            "INSERT INTO grades(class_id, student_id, column_id, evaluation_id, value, created_at_epoch_ms) VALUES (101, 2, 'col-exam', 501, 4.95, 1750000000000)",
            "INSERT INTO grades(class_id, student_id, column_id, evaluation_id, value, created_at_epoch_ms) VALUES (101, 2, 'col-hw', 501, 6.5, 1750000000000)",
            "INSERT INTO grades(class_id, student_id, column_id, evaluation_id, value, created_at_epoch_ms) VALUES (101, 3, 'col-exam', 501, 10.0, 1750000000000)",
            "INSERT INTO grades(class_id, student_id, column_id, evaluation_id, value, evidence, created_at_epoch_ms) VALUES (101, 3, 'col-hw', 501, NULL, 'Recuperación pendiente', 1750000000000)",
            "INSERT INTO grades(class_id, student_id, column_id, evaluation_id, value, created_at_epoch_ms) VALUES (101, 4, 'col-exam', 501, 2.5, 1750000000000)",
            "INSERT INTO grades(class_id, student_id, column_id, evaluation_id, value, created_at_epoch_ms) VALUES (101, 4, 'col-hw', 501, 5.0, 1750000000000)",
            "INSERT INTO grades(class_id, student_id, column_id, evaluation_id, value, created_at_epoch_ms) VALUES (101, 5, 'col-exam', 501, 8.8, 1750000000000)",
            "INSERT INTO grades(class_id, student_id, column_id, evaluation_id, value, created_at_epoch_ms) VALUES (101, 6, 'col-exam', 501, 6.0, 1750000000000)",
            "INSERT INTO grades(class_id, student_id, column_id, evaluation_id, value, rubric_selections, created_at_epoch_ms) VALUES (101, 6, 'col-hw', 501, 7.75, '{\"3011\":30112}', 1750000000000)",

            "INSERT INTO notebook_cell_entries(class_id, student_id, column_id, value_text, display_value, note) VALUES (101, 1, 'col-final', '8,01', '8,0', 'Redondeo pendiente de revisión')",
            "INSERT INTO notebook_cell_entries(class_id, student_id, column_id, value_text, display_value) VALUES (101, 2, 'col-final', '5,57', '5,6')",
            "INSERT INTO notebook_cell_entries(class_id, student_id, column_id, value_text, display_value) VALUES (101, 4, 'col-final', '3,5', '3,5')",

            "INSERT INTO attendance(student_id, class_id, date_epoch_ms, status) VALUES (1, 101, 1750000000000, 'PRESENT')",
            "INSERT INTO attendance(student_id, class_id, date_epoch_ms, status) VALUES (2, 101, 1750000000000, 'PRESENT')",
            "INSERT INTO attendance(student_id, class_id, date_epoch_ms, status, note) VALUES (3, 101, 1750000000000, 'EXCUSED', 'Justificado: cita médica')",
            "INSERT INTO attendance(student_id, class_id, date_epoch_ms, status) VALUES (4, 101, 1750000000000, 'ABSENT')",
            "INSERT INTO attendance(student_id, class_id, date_epoch_ms, status) VALUES (5, 101, 1750000000000, 'LATE')",
            "INSERT INTO attendance(student_id, class_id, date_epoch_ms, status) VALUES (1, 101, 1750086400000, 'PRESENT')",
            "INSERT INTO attendance(student_id, class_id, date_epoch_ms, status) VALUES (2, 101, 1750086400000, 'ABSENT')",
            "INSERT INTO attendance(student_id, class_id, date_epoch_ms, status) VALUES (3, 101, 1750086400000, 'PRESENT')",

            "INSERT INTO rubrics(id, name, class_id) VALUES (301, 'Rúbrica de expresión corporal', 101)",
            "INSERT INTO rubric_criteria(id, rubric_id, description, weight, sort_order) VALUES (3011, 301, 'Coordinación y ritmo', 0.5, 0)",
            "INSERT INTO rubric_criteria(id, rubric_id, description, weight, sort_order) VALUES (3012, 301, 'Trabajo en equipo', 0.5, 1)",
            "INSERT INTO rubric_levels(id, criterion_id, name, points, sort_order) VALUES (30111, 3011, 'Inicial', 1, 0)",
            "INSERT INTO rubric_levels(id, criterion_id, name, points, sort_order) VALUES (30112, 3011, 'En proceso', 2, 1)",
            "INSERT INTO rubric_levels(id, criterion_id, name, points, sort_order) VALUES (30113, 3011, 'Logrado', 3, 2)",
            "INSERT INTO rubric_levels(id, criterion_id, name, points, sort_order) VALUES (30114, 3011, 'Excelente', 4, 3)",
            "INSERT INTO rubric_levels(id, criterion_id, name, points, sort_order) VALUES (30121, 3012, 'Inicial', 1, 0)",
            "INSERT INTO rubric_levels(id, criterion_id, name, points, sort_order) VALUES (30122, 3012, 'Logrado', 3, 1)",
            "INSERT INTO rubric_assessments(student_id, evaluation_id, criterion_id, level_id, created_at_epoch_ms) VALUES (6, 501, 3011, 30112, 1750000000000)",
            "INSERT INTO rubric_assessments(student_id, evaluation_id, criterion_id, level_id, created_at_epoch_ms) VALUES (6, 501, 3012, 30122, 1750000000000)",

            "INSERT INTO sync_tombstones(entity, entity_id, deleted_at_epoch_ms, device_id) VALUES ('students', '999', 1750000000000, 'ipad-aula')",
        )
        statements.forEach { driver.execute(null, it, 0) }
    }

    fun assertSurvived(driver: JdbcSqliteDriver) {
        val expectedCounts = mapOf(
            "classes" to 1L,
            "students" to 6L,
            "class_students" to 6L,
            "evaluations" to 1L,
            "notebook_tabs" to 1L,
            "notebook_columns" to 3L,
            "grades" to 11L,
            "notebook_cell_entries" to 3L,
            "attendance" to 8L,
            "rubrics" to 1L,
            "rubric_criteria" to 2L,
            "rubric_levels" to 6L,
            "rubric_assessments" to 2L,
            "sync_tombstones" to 1L,
        )
        expectedCounts.forEach { (table, expected) ->
            assertEquals(expected, driver.scalarLong("SELECT COUNT(*) FROM $table"), "recuento de $table")
        }

        // Valores exactos: una nota que cambia de 7.35 a 7.3 tambien es perdida de datos.
        assertEquals(
            listOf("7.35"),
            driver.queryStrings("SELECT CAST(value AS TEXT) FROM grades WHERE student_id = 1 AND column_id = 'col-exam'"),
            "la nota de examen de Lucía debe conservar sus decimales",
        )
        assertEquals(
            listOf("4.95"),
            driver.queryStrings("SELECT CAST(value AS TEXT) FROM grades WHERE student_id = 2 AND column_id = 'col-exam'"),
        )
        assertEquals(
            0L,
            driver.scalarLong("SELECT COUNT(*) FROM grades WHERE student_id = 5 AND column_id = 'col-hw'"),
            "la celda vacía de Noa debe seguir vacía, no convertirse en 0",
        )
        assertEquals(
            listOf("Recuperación pendiente"),
            driver.queryStrings("SELECT evidence FROM grades WHERE student_id = 3 AND column_id = 'col-hw' AND value IS NULL"),
            "una nota sin valor pero con evidencia no puede desaparecer",
        )
        assertEquals(
            listOf("Ñuño Ibáñez"),
            driver.queryStrings("SELECT last_name FROM students WHERE id = 3"),
            "los apellidos con eñe y tilde deben sobrevivir intactos",
        )
        assertEquals(
            listOf("([Examen] * 0,6) + ([Deberes] * 0,4)"),
            driver.queryStrings("SELECT formula FROM notebook_columns WHERE id = 'col-final'"),
            "la fórmula con comas decimales debe sobrevivir byte a byte",
        )
        assertEquals(
            listOf("Justificado: cita médica"),
            driver.queryStrings("SELECT note FROM attendance WHERE student_id = 3 AND status = 'EXCUSED'"),
        )
        assertEquals(
            listOf("{\"3011\":30112}"),
            driver.queryStrings("SELECT rubric_selections FROM grades WHERE student_id = 6 AND column_id = 'col-hw'"),
        )
    }

    /**
     * Devuelve la fixture versionada, generandola si no existe todavia.
     * Nunca sobreescribe: para regenerarla (solo tras verificar a mano una
     * nueva migracion), borra el fichero, vuelve a ejecutar los tests y
     * commitea el resultado. Ver el README junto a la fixture.
     */
    fun ensureFixture(): File {
        val fixture = File(FIXTURE_RELATIVE_PATH)
        if (fixture.exists()) return fixture

        check(File("src/desktopTest").isDirectory) {
            "Ejecuta los tests desde el modulo kmp/data (directorio actual: ${File(".").absolutePath})"
        }
        fixture.parentFile.mkdirs()

        val staging = Files.createTempDirectory("migestor-fixture-gen-").toFile()
        try {
            val stagingDb = File(staging, "canonical_teacher_fixture.db")
            val driver = createSharedDesktopDriver(
                dbPath = stagingDb.absolutePath,
                dbName = stagingDb.name,
            )
            try {
                insertInto(driver)
            } finally {
                driver.close()
            }
            // Consolida el WAL para que la fixture sea un unico fichero .db.
            DriverManager.getConnection("jdbc:sqlite:${stagingDb.absolutePath}").use { connection ->
                connection.createStatement().use { it.execute("PRAGMA wal_checkpoint(TRUNCATE)") }
            }
            assertTrue(
                !File("${stagingDb.absolutePath}-wal").exists() || File("${stagingDb.absolutePath}-wal").length() == 0L,
                "la fixture no debe depender de un fichero -wal",
            )
            Files.copy(stagingDb.toPath(), fixture.toPath(), StandardCopyOption.REPLACE_EXISTING)
            println(
                "[CanonicalTeacherDataset] Fixture generada en ${fixture.path}. " +
                    "Commitea este fichero: es la base de datos 'antigua' que protege las futuras migraciones.",
            )
        } finally {
            staging.deleteRecursively()
        }
        return fixture
    }
}
