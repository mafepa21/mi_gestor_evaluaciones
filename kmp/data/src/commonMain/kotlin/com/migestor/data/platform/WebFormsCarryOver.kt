package com.migestor.data.platform

import app.cash.sqldelight.Transacter
import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.db.SqlDriver

/**
 * Devuelve a la base recién adoptada las entregas web que este equipo tenía antes.
 *
 * Igualar dispositivos sustituye la base entera por la del otro equipo. Las tablas
 * `web_*` no viajan por Sync LAN a propósito (ver 39.sqm): cada formulario se abre
 * con una clave privada que solo vive en el llavero del equipo que lo publicó. Sin
 * este traspaso, igualar borraba las entregas de este equipo y los enlaces que ya
 * tenía el alumnado dejaban de llegar al Cuaderno (incidente real del 31/10/2026).
 *
 * Reglas:
 *  - Lo que trae la base adoptada manda: solo se añade lo que falta (`INSERT OR IGNORE`).
 *  - En producción `foreign_keys` está apagado, así que las referencias se comprueban
 *    a mano: un formulario sin su grupo o su columna, un alias sin su alumno o un
 *    apartado sin su ítem no se traen.
 *  - Solo se copian las columnas que existen en las dos bases: la copia previa puede
 *    ser de un esquema anterior.
 *
 * [source] es la copia previa a la adopción; [target], la base ya abierta y migrada.
 */
internal data class WebFormsCarryOverResult(
    val restoredForms: Int,
    val skippedForms: Int,
)

internal fun carryOverLocalOnlyWebForms(
    source: SqlDriver,
    target: SqlDriver,
    transacter: Transacter,
): WebFormsCarryOverResult {
    if (!hasTable(source, "web_form_instances") || !hasTable(target, "web_form_instances")) {
        return WebFormsCarryOverResult(restoredForms = 0, skippedForms = 0)
    }

    val sourceFormIds = queryStrings(source, "SELECT form_instance_id FROM web_form_instances")
    val missingFormIds = sourceFormIds.filter { formId ->
        queryLong(target, "SELECT count(*) FROM web_form_instances WHERE form_instance_id = ${sqlText(formId)}") == 0L
    }
    if (missingFormIds.isEmpty()) {
        return WebFormsCarryOverResult(restoredForms = 0, skippedForms = 0)
    }

    val restored = mutableListOf<String>()
    transacter.transaction {
        for (formId in missingFormIds) {
            copyRows(
                source = source,
                target = target,
                table = "web_form_instances",
                where = "form_instance_id = ${sqlText(formId)}",
                requires = listOf("classes" to "class_id", "notebook_columns" to "column_id"),
            )
            val ok = queryLong(target, "SELECT count(*) FROM web_form_instances WHERE form_instance_id = ${sqlText(formId)}") > 0
            if (!ok) continue
            restored += formId
            val byForm = "form_instance_id = ${sqlText(formId)}"
            copyRows(source, target, "web_participant_aliases", byForm, listOf("students" to "student_id"))
            copyRows(source, target, "web_item_map", byForm, listOf("notebook_instrument_items" to "item_id"))
            copyRows(source, target, "web_peer_targets", byForm, listOf("students" to "target_student_id"))
            copyRows(source, target, "web_submission_ledger", byForm, emptyList())
        }
    }

    return WebFormsCarryOverResult(
        restoredForms = restored.size,
        skippedForms = missingFormIds.size - restored.size,
    )
}

/**
 * Copia las filas de [table] que cumplen [where] en [source]. Cada fila se inserta solo
 * si en [target] existe la fila padre de cada par (tabla padre, columna con su `id`).
 *
 * Los valores viajan como literales generados por el `quote()` de SQLite en la base de
 * origen, así que conservan su tipo (texto, número, blob o NULL) y llegan escapados.
 */
private fun copyRows(
    source: SqlDriver,
    target: SqlDriver,
    table: String,
    where: String,
    requires: List<Pair<String, String>>,
) {
    if (!hasTable(source, table) || !hasTable(target, table)) return
    val targetColumns = columnNames(target, table).toSet()
    val columns = columnNames(source, table).filter { it in targetColumns }
    if (columns.isEmpty()) return
    val requiredColumns = requires.map { it.second }
    if (!columns.containsAll(requiredColumns)) return

    val rowSelect = columns.joinToString(" || ',' || ") { "quote(\"$it\")" }
    val keySelect = requiredColumns.joinToString("") { ", quote(\"$it\")" }
    val rows = source.executeQuery(
        identifier = null,
        sql = "SELECT $rowSelect$keySelect FROM \"$table\" WHERE $where",
        mapper = { cursor ->
            val result = mutableListOf<Pair<String, List<String>>>()
            while (cursor.next().value) {
                val literals = cursor.getString(0) ?: continue
                val keys = requiredColumns.indices.map { cursor.getString(it + 1) ?: "NULL" }
                result += literals to keys
            }
            QueryResult.Value(result)
        },
        parameters = 0,
    ).value

    val columnList = columns.joinToString(", ") { "\"$it\"" }
    for ((literals, keys) in rows) {
        val conditions = requires.mapIndexed { index, (parent, _) ->
            "EXISTS (SELECT 1 FROM \"$parent\" WHERE id = ${keys[index]})"
        }
        val guard = if (conditions.isEmpty()) "" else " WHERE " + conditions.joinToString(" AND ")
        target.execute(null, "INSERT OR IGNORE INTO \"$table\" ($columnList) SELECT $literals$guard", 0)
    }
}

private fun hasTable(driver: SqlDriver, table: String): Boolean =
    queryLong(driver, "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = ${sqlText(table)}") > 0

private fun columnNames(driver: SqlDriver, table: String): List<String> =
    queryStrings(driver, "SELECT name FROM pragma_table_info(${sqlText(table)})")

private fun queryStrings(driver: SqlDriver, sql: String): List<String> = driver.executeQuery(
    identifier = null,
    sql = sql,
    mapper = { cursor ->
        val values = mutableListOf<String>()
        while (cursor.next().value) {
            cursor.getString(0)?.let(values::add)
        }
        QueryResult.Value(values)
    },
    parameters = 0,
).value

private fun queryLong(driver: SqlDriver, sql: String): Long = driver.executeQuery(
    identifier = null,
    sql = sql,
    mapper = { cursor -> QueryResult.Value(if (cursor.next().value) cursor.getLong(0) ?: 0L else 0L) },
    parameters = 0,
).value

private fun sqlText(value: String): String = "'" + value.replace("'", "''") + "'"
