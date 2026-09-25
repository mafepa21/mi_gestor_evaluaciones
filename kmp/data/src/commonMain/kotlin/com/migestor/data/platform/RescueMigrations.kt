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
    copyLegacyPlannedSessions(driver)
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

private fun copyLegacyPlannedSessions(driver: SqlDriver) {
    val plannedColumns = tableColumns(driver, "planned_session")
    val required = setOf(
        "teaching_unit_id",
        "school_class_id",
        "date",
        "start_time",
        "end_time",
        "title",
        "objectives",
        "resources",
        "notes",
    )
    if (!required.all { it in plannedColumns }) return
    if ("period" !in tableColumns(driver, "planner_session")) return

    driver.execute(
        null,
        """
        CREATE TABLE IF NOT EXISTS schedule_slot (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            day_of_week INTEGER NOT NULL,
            period INTEGER NOT NULL,
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL,
            group_id INTEGER NOT NULL,
            classroom TEXT DEFAULT '',
            FOREIGN KEY (group_id) REFERENCES classes(id) ON DELETE CASCADE
        )
        """.trimIndent(),
        0,
    )
    driver.execute(
        null,
        """
        CREATE TABLE IF NOT EXISTS weekly_slot_template (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            school_class_id INTEGER NOT NULL,
            day_of_week INTEGER NOT NULL,
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL,
            UNIQUE(school_class_id, day_of_week, start_time),
            FOREIGN KEY (school_class_id) REFERENCES classes(id) ON DELETE CASCADE
        )
        """.trimIndent(),
        0,
    )

    driver.execute(null, "DROP TABLE IF EXISTS planned_session_migration_v44", 0)
    driver.execute(
        null,
        """
        CREATE TABLE planned_session_migration_v44 (
            planned_id INTEGER PRIMARY KEY,
            date TEXT NOT NULL,
            school_class_id INTEGER NOT NULL,
            period INTEGER,
            teaching_unit_id INTEGER,
            objectives TEXT NOT NULL,
            activities TEXT NOT NULL,
            resources TEXT NOT NULL,
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL
        )
        """.trimIndent(),
        0,
    )
    driver.execute(
        null,
        """
        INSERT INTO planned_session_migration_v44 (
            planned_id, date, school_class_id, period, teaching_unit_id,
            objectives, activities, resources, start_time, end_time
        )
        SELECT
            ps.id,
            ps.date,
            ps.school_class_id,
            COALESCE(
                CASE TRIM(ps.start_time)
                    WHEN '08:05' THEN 1
                    WHEN '09:00' THEN 2
                    WHEN '10:00' THEN 3
                    WHEN '11:25' THEN 4
                    WHEN '12:20' THEN 5
                    WHEN '13:15' THEN 6
                    WHEN '14:25' THEN 7
                    WHEN '15:00' THEN 8
                    WHEN '15:55' THEN 9
                    ELSE NULL
                END,
                (
                    SELECT ss.period
                    FROM schedule_slot ss
                    WHERE ss.group_id = ps.school_class_id
                      AND ss.start_time = TRIM(ps.start_time)
                      AND ss.day_of_week = CASE CAST(strftime('%w', ps.date) AS INTEGER)
                          WHEN 0 THEN 7
                          ELSE CAST(strftime('%w', ps.date) AS INTEGER)
                      END
                    ORDER BY ss.id
                    LIMIT 1
                ),
                (
                    SELECT CASE
                        WHEN EXISTS (
                            SELECT 1
                            FROM teacher_schedule_slots exact
                            WHERE exact.school_class_id = ps.school_class_id
                              AND exact.start_time = TRIM(ps.start_time)
                              AND exact.day_of_week = CASE CAST(strftime('%w', ps.date) AS INTEGER)
                                  WHEN 0 THEN 7
                                  ELSE CAST(strftime('%w', ps.date) AS INTEGER)
                              END
                        )
                        THEN (
                            SELECT COUNT(DISTINCT slot.start_time)
                            FROM teacher_schedule_slots slot
                            WHERE slot.school_class_id = ps.school_class_id
                              AND slot.day_of_week = CASE CAST(strftime('%w', ps.date) AS INTEGER)
                                  WHEN 0 THEN 7
                                  ELSE CAST(strftime('%w', ps.date) AS INTEGER)
                              END
                              AND slot.start_time <= TRIM(ps.start_time)
                        )
                        ELSE NULL
                    END
                ),
                (
                    SELECT CASE
                        WHEN EXISTS (
                            SELECT 1
                            FROM weekly_slot_template exact
                            WHERE exact.school_class_id = ps.school_class_id
                              AND exact.start_time = TRIM(ps.start_time)
                              AND exact.day_of_week = CASE CAST(strftime('%w', ps.date) AS INTEGER)
                                  WHEN 0 THEN 7
                                  ELSE CAST(strftime('%w', ps.date) AS INTEGER)
                              END
                        )
                        THEN (
                            SELECT COUNT(DISTINCT slot.start_time)
                            FROM weekly_slot_template slot
                            WHERE slot.school_class_id = ps.school_class_id
                              AND slot.day_of_week = CASE CAST(strftime('%w', ps.date) AS INTEGER)
                                  WHEN 0 THEN 7
                                  ELSE CAST(strftime('%w', ps.date) AS INTEGER)
                              END
                              AND slot.start_time <= TRIM(ps.start_time)
                        )
                        ELSE NULL
                    END
                )
            ),
            ps.teaching_unit_id,
            COALESCE(ps.objectives, ''),
            CASE
                WHEN TRIM(COALESCE(ps.notes, '')) != '' THEN ps.notes
                ELSE COALESCE(ps.title, '')
            END,
            COALESCE(ps.resources, ''),
            TRIM(ps.start_time),
            ps.end_time
        FROM planned_session ps
        """.trimIndent(),
        0,
    )
    driver.execute(
        null,
        """
        UPDATE planner_session
        SET
            unit_id = COALESCE(planner_session.unit_id, src.teaching_unit_id),
            objectives = CASE
                WHEN TRIM(COALESCE(planner_session.objectives, '')) = '' THEN src.objectives
                ELSE planner_session.objectives
            END,
            activities = CASE
                WHEN TRIM(COALESCE(planner_session.activities, '')) = '' THEN src.activities
                ELSE planner_session.activities
            END,
            evaluation = CASE
                WHEN TRIM(COALESCE(planner_session.evaluation, '')) = '' THEN src.resources
                ELSE planner_session.evaluation
            END,
            start_time = CASE
                WHEN planner_session.start_time IS NULL OR TRIM(planner_session.start_time) = '' THEN src.start_time
                ELSE planner_session.start_time
            END,
            end_time = CASE
                WHEN planner_session.end_time IS NULL OR TRIM(planner_session.end_time) = '' THEN src.end_time
                ELSE planner_session.end_time
            END
        FROM planned_session_migration_v44 AS src
        WHERE src.period IS NOT NULL
          AND planner_session.date = src.date
          AND planner_session.group_id = src.school_class_id
          AND planner_session.period = src.period
        """.trimIndent(),
        0,
    )
    driver.execute(
        null,
        """
        INSERT INTO planner_session (
            date, group_id, period, unit_id, objectives, activities, evaluation,
            linked_assessment_ids_csv, start_time, end_time, status,
            updated_at_epoch_ms, sync_version
        )
        SELECT
            src.date, src.school_class_id, src.period, src.teaching_unit_id,
            src.objectives, src.activities, src.resources, '',
            src.start_time, src.end_time, 'PLANNED',
            CAST(strftime('%s', 'now') AS INTEGER) * 1000, 0
        FROM planned_session_migration_v44 AS src
        WHERE src.period IS NOT NULL
          AND src.planned_id = (
              SELECT MIN(other.planned_id)
              FROM planned_session_migration_v44 AS other
              WHERE other.date = src.date
                AND other.school_class_id = src.school_class_id
                AND other.period = src.period
                AND other.period IS NOT NULL
          )
          AND NOT EXISTS (
              SELECT 1
              FROM planner_session existing
              WHERE existing.date = src.date
                AND existing.group_id = src.school_class_id
                AND existing.period = src.period
          )
        """.trimIndent(),
        0,
    )
    driver.execute(
        null,
        """
        DELETE FROM planned_session
        WHERE id IN (
            SELECT planned_id
            FROM planned_session_migration_v44
            WHERE period IS NOT NULL
        )
        """.trimIndent(),
        0,
    )
    driver.execute(null, "DROP TABLE planned_session_migration_v44", 0)
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
