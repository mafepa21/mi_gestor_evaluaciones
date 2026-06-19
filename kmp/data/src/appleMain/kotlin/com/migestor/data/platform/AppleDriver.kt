package com.migestor.data.platform

import app.cash.sqldelight.db.AfterVersion
import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.db.SqlSchema
import app.cash.sqldelight.driver.native.NativeSqliteDriver
import co.touchlab.sqliter.DatabaseConfiguration
import com.migestor.data.db.AppDatabase
import kotlinx.cinterop.ExperimentalForeignApi
import platform.Foundation.NSFileManager
import platform.Foundation.NSApplicationSupportDirectory
import platform.Foundation.NSUserDomainMask

@OptIn(ExperimentalForeignApi::class)
internal fun createAppleDriver(
    appSupportDirectoryName: String,
    databaseName: String,
    legacySourcePaths: List<String> = emptyList(),
): SqlDriver {
    val basePath = appleAppSupportPath(
        appSupportDirectoryName = appSupportDirectoryName,
        fileName = null,
    )
    val databasePath = "$basePath/$databaseName"

    migrateAppleDatabaseIfNeeded(
        targetDatabasePath = databasePath,
        legacySourcePaths = legacySourcePaths,
    )

    val driver = NativeSqliteDriver(
        schema = AppleAppDatabaseSchema,
        name = databaseName,
        onConfiguration = { config ->
            config.copy(
                extendedConfig = DatabaseConfiguration.Extended(basePath = basePath)
            )
        },
    )

    val currentVersion = getVersion(driver)
    val latestVersion = AppDatabase.Schema.version

    if (currentVersion == 0L) {
        AppleAppDatabaseSchema.create(driver)
        setVersion(driver, latestVersion)
    } else if (currentVersion < latestVersion) {
        AppleAppDatabaseSchema.migrate(driver, currentVersion, latestVersion)
        setVersion(driver, latestVersion)
    }

    runRescueMigrations(driver)
    ensurePrerequisiteTables(driver)
    ensurePlannerScheduleTables(driver)

    return driver
}

private fun runRescueMigrations(driver: SqlDriver) {
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

private fun tableColumns(driver: SqlDriver, tableName: String): Set<String> {
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

private object AppleAppDatabaseSchema : SqlSchema<QueryResult.Value<Unit>> {
    override val version: Long = AppDatabase.Schema.version

    override fun create(driver: SqlDriver): QueryResult.Value<Unit> {
        return AppDatabase.Schema.create(driver)
    }

    override fun migrate(
        driver: SqlDriver,
        oldVersion: Long,
        newVersion: Long,
        vararg callbacks: AfterVersion,
    ): QueryResult.Value<Unit> {
        if (
            oldVersion == 22L &&
            newVersion == version &&
            "fixed_column_width" in tableColumns(driver, "notebook_tabs")
        ) {
            callbacks
                .filter { it.afterVersion in (oldVersion + 1)..newVersion }
                .forEach { it.block(driver) }
            return QueryResult.Value(Unit)
        }

        return AppDatabase.Schema.migrate(
            driver = driver,
            oldVersion = oldVersion,
            newVersion = newVersion,
            callbacks = callbacks,
        )
    }
}

@OptIn(ExperimentalForeignApi::class)
internal fun appleAppSupportPath(
    appSupportDirectoryName: String,
    fileName: String?,
): String {
    val fileManager = NSFileManager.defaultManager
    val applicationSupportUrl = fileManager.URLForDirectory(
        directory = NSApplicationSupportDirectory,
        inDomain = NSUserDomainMask,
        appropriateForURL = null,
        create = true,
        error = null,
    ) ?: error("No se pudo resolver Application Support para Apple")

    val applicationSupportPath = applicationSupportUrl.path
        ?: error("No se pudo resolver la ruta base de Application Support")
    val appDirectoryPath = "$applicationSupportPath/$appSupportDirectoryName"

    fileManager.createDirectoryAtPath(appDirectoryPath, true, null, null)

    return if (fileName.isNullOrBlank()) appDirectoryPath else "$appDirectoryPath/$fileName"
}

@OptIn(ExperimentalForeignApi::class)
internal fun migrateAppleDatabaseIfNeeded(
    targetDatabasePath: String,
    legacySourcePaths: List<String>,
) {
    val fileManager = NSFileManager.defaultManager
    if (fileManager.fileExistsAtPath(targetDatabasePath)) return

    val sourcePath = legacySourcePaths.firstOrNull { candidate ->
        candidate.isNotBlank() && fileManager.fileExistsAtPath(candidate)
    } ?: return

    fileManager.copyItemAtPath(sourcePath, targetDatabasePath, null)
}

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
}

private fun getVersion(driver: SqlDriver): Long {
    return driver.executeQuery(
        identifier = null,
        sql = "PRAGMA user_version",
        mapper = { cursor ->
            val version = if (cursor.next().value) cursor.getLong(0) ?: 0L else 0L
            QueryResult.Value(version)
        },
        parameters = 0
    ).value
}

private fun setVersion(driver: SqlDriver, version: Long) {
    driver.execute(null, "PRAGMA user_version = $version", 0)
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
