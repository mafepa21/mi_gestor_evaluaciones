package com.migestor.data.platform

import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.db.SqlDriver

/**
 * Red de seguridad idempotente compartida por desktop y Apple: repara
 * instalaciones que arrancaron con un esquema distinto al que produce
 * Schema.create() + la cadena .sqm (drift historico entre .sq/.sqm que
 * quedo parcheado aqui en vez de corregirse en una migracion real).
 *
 * No sustituye a las migraciones .sqm: cada gap que cubre debiera acabar
 * tambien respaldado por una migracion .sqm propia (ver 34.sqm). Vive en
 * commonMain para que desktop y Apple no puedan volver a divergir entre si.
 */
internal fun runRescueMigrations(driver: SqlDriver) {
    ensureColumns(
        driver = driver,
        tableName = "notebook_tabs",
        columnDefinitions = listOf(
            "fixed_column_width REAL",
        )
    )
    ensureColumns(
        driver = driver,
        tableName = "notebook_columns",
        columnDefinitions = listOf(
            "category_kind TEXT NOT NULL DEFAULT 'CUSTOM'",
            "instrument_kind TEXT NOT NULL DEFAULT 'CUSTOM'",
            "input_kind TEXT NOT NULL DEFAULT 'TEXT'",
            "date_epoch_ms INTEGER",
            "unit_name TEXT",
            "competency_criteria_ids_csv TEXT NOT NULL DEFAULT ''",
            "scale_kind TEXT NOT NULL DEFAULT 'CUSTOM'",
            "tab_ids_csv TEXT NOT NULL DEFAULT ''",
            "shared_across_tabs INTEGER NOT NULL DEFAULT 0",
            "color_hex TEXT NOT NULL DEFAULT '#FFFFFF'",
            "icon_name TEXT",
            "sort_order INTEGER NOT NULL DEFAULT 0",
            "width_dp REAL NOT NULL DEFAULT 132.0",
            "category_id TEXT",
            "visibility TEXT NOT NULL DEFAULT 'VISIBLE'",
            "is_locked INTEGER NOT NULL DEFAULT 0",
            "counts_toward_average INTEGER NOT NULL DEFAULT 1",
            "is_pinned INTEGER NOT NULL DEFAULT 0",
            "is_hidden INTEGER NOT NULL DEFAULT 0",
            "is_template INTEGER NOT NULL DEFAULT 0",
            "empty_cell_policy TEXT NOT NULL DEFAULT 'EXCLUDE_FROM_AVERAGE'",
            "updated_at_epoch_ms INTEGER NOT NULL DEFAULT 0",
            "device_id TEXT",
            "sync_version INTEGER NOT NULL DEFAULT 0",
        )
    )
    ensureStructuredInstrumentTables(driver)
    ensurePrerequisiteTables(driver)
    ensurePlannerScheduleTables(driver)
    ensurePhysicalScaleScoringColumns(driver)
}

private fun ensurePhysicalScaleScoringColumns(driver: SqlDriver) {
    ensureColumns(
        driver = driver,
        tableName = "physical_test_scales",
        columnDefinitions = listOf(
            "scoring_mode TEXT NOT NULL DEFAULT 'STEP'",
            "score_round_to REAL",
        )
    )
}

private fun ensureStructuredInstrumentTables(driver: SqlDriver) {
    driver.execute(null, """
        CREATE TABLE IF NOT EXISTS notebook_instrument_templates (
            id TEXT NOT NULL PRIMARY KEY,
            class_id INTEGER NOT NULL,
            column_id TEXT NOT NULL UNIQUE,
            evaluation_id INTEGER,
            title TEXT NOT NULL,
            kind TEXT NOT NULL,
            input_kind TEXT NOT NULL,
            source TEXT,
            created_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
            updated_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
            device_id TEXT,
            sync_version INTEGER NOT NULL DEFAULT 0
        )
    """.trimIndent(), 0)
    driver.execute(null, "CREATE INDEX IF NOT EXISTS idx_notebook_instrument_templates_class ON notebook_instrument_templates(class_id)", 0)
    driver.execute(null, "CREATE INDEX IF NOT EXISTS idx_notebook_instrument_templates_column ON notebook_instrument_templates(column_id)", 0)
    driver.execute(null, """
        CREATE TABLE IF NOT EXISTS notebook_instrument_items (
            id TEXT NOT NULL PRIMARY KEY,
            template_id TEXT NOT NULL,
            item_key TEXT NOT NULL,
            title TEXT NOT NULL,
            item_type TEXT NOT NULL,
            options_csv TEXT NOT NULL DEFAULT '',
            required INTEGER NOT NULL DEFAULT 1,
            sort_order INTEGER NOT NULL DEFAULT 0,
            help_text TEXT,
            updated_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
            device_id TEXT,
            sync_version INTEGER NOT NULL DEFAULT 0
        )
    """.trimIndent(), 0)
    driver.execute(null, "CREATE INDEX IF NOT EXISTS idx_notebook_instrument_items_template ON notebook_instrument_items(template_id, sort_order, id)", 0)
    driver.execute(null, """
        CREATE TABLE IF NOT EXISTS notebook_instrument_responses (
            class_id INTEGER NOT NULL,
            student_id INTEGER NOT NULL,
            column_id TEXT NOT NULL,
            item_id TEXT NOT NULL,
            value_text TEXT,
            value_bool INTEGER,
            value_number REAL,
            updated_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
            device_id TEXT,
            sync_version INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (class_id, student_id, column_id, item_id)
        )
    """.trimIndent(), 0)
    driver.execute(null, "CREATE INDEX IF NOT EXISTS idx_notebook_instrument_responses_cell ON notebook_instrument_responses(class_id, student_id, column_id)", 0)
    driver.execute(null, "CREATE INDEX IF NOT EXISTS idx_notebook_instrument_responses_item ON notebook_instrument_responses(item_id)", 0)
}

/**
 * centers/academic_years/app_users/stage_cycles/subjects: la estructura
 * multi-centro. app_users, stage_cycles y subjects nunca tuvieron CREATE
 * TABLE en ninguna .sqm (a diferencia de sus hermanas centers/academic_years
 * en 31.sqm), asi que cualquier instalacion que solo migro por la cadena
 * .sqm se quedaba sin ellas. 34.sqm ya lo corrige; esto queda como respaldo.
 */
private fun ensurePrerequisiteTables(driver: SqlDriver) {
    driver.execute(null, """
        CREATE TABLE IF NOT EXISTS centers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            author_user_id INTEGER,
            created_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
            updated_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
            associated_group_id INTEGER,
            device_id TEXT,
            sync_version INTEGER NOT NULL DEFAULT 0
        )
    """.trimIndent(), 0)
    driver.execute(null, """
        CREATE TABLE IF NOT EXISTS academic_years (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            center_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            start_epoch_ms INTEGER NOT NULL,
            end_epoch_ms INTEGER NOT NULL,
            author_user_id INTEGER,
            created_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
            updated_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
            associated_group_id INTEGER,
            device_id TEXT,
            sync_version INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (center_id) REFERENCES centers(id) ON DELETE CASCADE
        )
    """.trimIndent(), 0)
    driver.execute(null, """
        CREATE TABLE IF NOT EXISTS app_users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            external_id TEXT,
            display_name TEXT NOT NULL,
            email TEXT,
            role TEXT NOT NULL,
            center_id INTEGER,
            author_user_id INTEGER,
            created_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
            updated_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
            associated_group_id INTEGER,
            device_id TEXT,
            sync_version INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (center_id) REFERENCES centers(id) ON DELETE SET NULL
        )
    """.trimIndent(), 0)
    driver.execute(null, """
        CREATE TABLE IF NOT EXISTS stage_cycles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            center_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            level TEXT,
            author_user_id INTEGER,
            created_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
            updated_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
            associated_group_id INTEGER,
            device_id TEXT,
            sync_version INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (center_id) REFERENCES centers(id) ON DELETE CASCADE
        )
    """.trimIndent(), 0)
    driver.execute(null, """
        CREATE TABLE IF NOT EXISTS subjects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT NOT NULL,
            name TEXT NOT NULL,
            stage_cycle_id INTEGER,
            author_user_id INTEGER,
            created_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
            updated_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
            associated_group_id INTEGER,
            device_id TEXT,
            sync_version INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (stage_cycle_id) REFERENCES stage_cycles(id) ON DELETE SET NULL
        )
    """.trimIndent(), 0)
}

private fun ensurePlannerScheduleTables(driver: SqlDriver) {
    driver.execute(null, """
        CREATE TABLE IF NOT EXISTS teacher_schedules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            owner_user_id INTEGER NOT NULL,
            academic_year_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            start_date TEXT NOT NULL,
            end_date TEXT NOT NULL,
            active_weekdays TEXT NOT NULL DEFAULT '1,2,3,4,5',
            author_user_id INTEGER,
            created_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
            updated_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
            associated_group_id INTEGER,
            device_id TEXT,
            sync_version INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (owner_user_id) REFERENCES app_users(id) ON DELETE CASCADE,
            FOREIGN KEY (academic_year_id) REFERENCES academic_years(id) ON DELETE CASCADE
        )
    """.trimIndent(), 0)
    driver.execute(null, """
        CREATE TABLE IF NOT EXISTS teacher_schedule_slots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            teacher_schedule_id INTEGER NOT NULL,
            school_class_id INTEGER NOT NULL,
            subject_label TEXT NOT NULL DEFAULT '',
            unit_label TEXT,
            day_of_week INTEGER NOT NULL,
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL,
            weekly_template_id INTEGER,
            FOREIGN KEY (teacher_schedule_id) REFERENCES teacher_schedules(id) ON DELETE CASCADE,
            FOREIGN KEY (school_class_id) REFERENCES classes(id) ON DELETE CASCADE,
            FOREIGN KEY (weekly_template_id) REFERENCES weekly_slot_template(id) ON DELETE SET NULL
        )
    """.trimIndent(), 0)
    driver.execute(null, """
        CREATE TABLE IF NOT EXISTS planner_evaluation_periods (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            teacher_schedule_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            start_date TEXT NOT NULL,
            end_date TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (teacher_schedule_id) REFERENCES teacher_schedules(id) ON DELETE CASCADE
        )
    """.trimIndent(), 0)
}

private fun ensureColumns(
    driver: SqlDriver,
    tableName: String,
    columnDefinitions: List<String>,
) {
    val existingColumns = tableColumns(driver, tableName)
    if (existingColumns.isEmpty()) return

    for (columnDef in columnDefinitions) {
        val columnName = columnDef.substringBefore(" ")
        if (columnName in existingColumns) continue
        driver.execute(null, "ALTER TABLE $tableName ADD COLUMN $columnDef", 0)
        println("[RescueMigration] Added column $columnName to $tableName")
    }
}

internal fun tableColumns(driver: SqlDriver, tableName: String): Set<String> {
    return driver.executeQuery(
        identifier = null,
        sql = "PRAGMA table_info($tableName)",
        mapper = { cursor ->
            val columns = mutableSetOf<String>()
            while (cursor.next().value) {
                cursor.getString(1)?.let(columns::add)
            }
            QueryResult.Value(columns)
        },
        parameters = 0,
    ).value
}
