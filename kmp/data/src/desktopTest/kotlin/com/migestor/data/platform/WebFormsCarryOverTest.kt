package com.migestor.data.platform

import app.cash.sqldelight.TransacterImpl
import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Igualar dispositivos sustituye la base entera por la del otro equipo, pero las
 * entregas web no viajan por la sync: son de este equipo (su llave está en su
 * llavero). Estos tests fijan que la copia previa las devuelve.
 */
class WebFormsCarryOverTest {

    private fun newDb(): SqlDriver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY).also {
        AppDatabase.Schema.create(it)
    }

    /** Lo que comparten las dos bases: el grupo, sus alumnos y la columna con su instrumento. */
    private fun seedSharedNotebook(db: SqlDriver) {
        db.execute(null, "INSERT INTO classes(id, name, course) VALUES (10, 'Grupo prueba', 1)", 0)
        db.execute(null, "INSERT INTO students(id, first_name, last_name) VALUES (1, 'Ana', 'Prueba'), (2, 'Leo', 'Prueba')", 0)
        db.execute(null, "INSERT INTO notebook_columns(id, class_id, title, type) VALUES ('eval_1', 10, 'Pasaporte', 'RUBRIC')", 0)
        db.execute(
            null,
            "INSERT INTO notebook_instrument_items(id, template_id, item_key, title, item_type) VALUES ('item_1', 'tpl', 'k1', 'Apartado', 'SCALE')",
            0,
        )
    }

    private fun seedWebForm(db: SqlDriver, formId: String, columnId: String = "eval_1", studentId: Long = 1) {
        db.execute(
            null,
            """
            INSERT INTO web_form_instances(form_instance_id, class_id, column_id, title, recipient_public_key, private_key_ref, mode)
            VALUES ('$formId', 10, '$columnId', 'Pasaporte', 'pub', 'llavero://entregas-web/$formId', 'passport')
            """.trimIndent(),
            0,
        )
        db.execute(null, "INSERT INTO web_participant_aliases(form_instance_id, alias, student_id) VALUES ('$formId', 'a$studentId', $studentId)", 0)
        db.execute(null, "INSERT INTO web_item_map(form_instance_id, web_item_id, item_id, item_type) VALUES ('$formId', 'w1', 'item_1', 'SCALE')", 0)
        db.execute(
            null,
            "INSERT INTO web_submission_ledger(submission_id, form_instance_id, alias, student_id, status, answer_count) VALUES ('sub-$formId', '$formId', 'a$studentId', $studentId, 'imported', 1)",
            0,
        )
    }

    private fun count(db: SqlDriver, sql: String): Long = db.executeQuery(
        identifier = null,
        sql = sql,
        mapper = { cursor -> QueryResult.Value(if (cursor.next().value) cursor.getLong(0) ?: 0 else 0) },
        parameters = 0,
    ).value

    private fun carryOver(previous: SqlDriver, adopted: SqlDriver) =
        carryOverLocalOnlyWebForms(source = previous, target = adopted, transacter = object : TransacterImpl(adopted) {})

    @Test
    fun igualarConUnaBaseSinEntregasConservaLaEntregaLocal() {
        val previous = newDb().also { seedSharedNotebook(it); seedWebForm(it, "F1") }
        val adopted = newDb().also(::seedSharedNotebook)

        val result = carryOver(previous, adopted)

        assertEquals(1, result.restoredForms)
        assertEquals(0, result.skippedForms)
        assertEquals(1, count(adopted, "SELECT count(*) FROM web_form_instances WHERE form_instance_id = 'F1' AND mode = 'passport'"))
        assertEquals(1, count(adopted, "SELECT count(*) FROM web_participant_aliases WHERE form_instance_id = 'F1'"))
        assertEquals(1, count(adopted, "SELECT count(*) FROM web_item_map WHERE form_instance_id = 'F1'"))
        // Lo ya importado sigue marcado: no se vuelve a importar dos veces.
        assertEquals(1, count(adopted, "SELECT count(*) FROM web_submission_ledger WHERE submission_id = 'sub-F1'"))
    }

    @Test
    fun loQueLlegaDelOtroEquipoMandaYNoSeDuplica() {
        val previous = newDb().also { seedSharedNotebook(it); seedWebForm(it, "F1") }
        val adopted = newDb().also { seedSharedNotebook(it); seedWebForm(it, "F1") }
        adopted.execute(null, "UPDATE web_form_instances SET title = 'Del otro equipo' WHERE form_instance_id = 'F1'", 0)

        val result = carryOver(previous, adopted)

        assertEquals(0, result.restoredForms)
        assertEquals(1, count(adopted, "SELECT count(*) FROM web_form_instances WHERE title = 'Del otro equipo'"))
        assertEquals(1, count(adopted, "SELECT count(*) FROM web_participant_aliases"))
    }

    @Test
    fun unaEntregaSinColumnaEnLaBaseNuevaSeSaltaSinRomperNada() {
        val previous = newDb().also {
            seedSharedNotebook(it)
            it.execute(null, "INSERT INTO notebook_columns(id, class_id, title, type) VALUES ('eval_borrada', 10, 'Vieja', 'RUBRIC')", 0)
            seedWebForm(it, "F1")
            seedWebForm(it, "F2", columnId = "eval_borrada")
        }
        val adopted = newDb().also(::seedSharedNotebook)

        val result = carryOver(previous, adopted)

        assertEquals(1, result.restoredForms)
        assertEquals(1, result.skippedForms)
        assertEquals(0, count(adopted, "SELECT count(*) FROM web_form_instances WHERE form_instance_id = 'F2'"))
        assertEquals(0, count(adopted, "SELECT count(*) FROM web_submission_ledger WHERE form_instance_id = 'F2'"))
    }

    @Test
    fun noSeTraeUnAliasDeUnAlumnoQueYaNoExiste() {
        val previous = newDb().also {
            seedSharedNotebook(it)
            it.execute(null, "INSERT INTO students(id, first_name, last_name) VALUES (3, 'Ivo', 'Prueba')", 0)
            seedWebForm(it, "F1")
            it.execute(null, "INSERT INTO web_participant_aliases(form_instance_id, alias, student_id) VALUES ('F1', 'a3', 3)", 0)
        }
        val adopted = newDb().also(::seedSharedNotebook)

        carryOver(previous, adopted)

        assertEquals(1, count(adopted, "SELECT count(*) FROM web_participant_aliases WHERE form_instance_id = 'F1'"))
    }

    @Test
    fun siLaEntregaYaEstabaSeCompletaSuRegistroDeEnviosImportados() {
        val previous = newDb().also { seedSharedNotebook(it); seedWebForm(it, "F1") }
        val adopted = newDb().also { seedSharedNotebook(it); seedWebForm(it, "F1") }
        adopted.execute(null, "DELETE FROM web_submission_ledger", 0)

        carryOver(previous, adopted)

        assertEquals(1, count(adopted, "SELECT count(*) FROM web_submission_ledger WHERE submission_id = 'sub-F1'"))
    }

    @Test
    fun unaEntregaSinSusApartadosEnLaBaseNuevaSeSaltaEntera() {
        val previous = newDb().also {
            seedSharedNotebook(it)
            seedWebForm(it, "F1")
            it.execute(
                null,
                "INSERT INTO notebook_instrument_items(id, template_id, item_key, title, item_type) VALUES ('item_viejo', 'tpl', 'k2', 'Viejo', 'SCALE')",
                0,
            )
            it.execute(null, "INSERT INTO web_item_map(form_instance_id, web_item_id, item_id, item_type) VALUES ('F1', 'w2', 'item_viejo', 'SCALE')", 0)
        }
        val adopted = newDb().also(::seedSharedNotebook)

        val result = carryOver(previous, adopted)

        assertEquals(0, result.restoredForms)
        assertEquals(1, result.skippedForms)
        assertEquals(0, count(adopted, "SELECT count(*) FROM web_form_instances"))
        assertEquals(0, count(adopted, "SELECT count(*) FROM web_participant_aliases"))
        assertEquals(0, count(adopted, "SELECT count(*) FROM web_item_map"))
    }

    @Test
    fun sinEntregasLocalesNoHaceNada() {
        val previous = newDb().also(::seedSharedNotebook)
        val adopted = newDb().also(::seedSharedNotebook)

        val result = carryOver(previous, adopted)

        assertEquals(0, result.restoredForms)
        assertEquals(0, result.skippedForms)
    }
}
