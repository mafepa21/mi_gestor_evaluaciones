package com.migestor.data.platform

import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.db.SqlDriver
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
        schema = AppDatabase.Schema,
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
        AppDatabase.Schema.create(driver)
        setVersion(driver, latestVersion)
    } else if (currentVersion < latestVersion) {
        AppDatabase.Schema.migrate(driver, currentVersion, latestVersion)
        setVersion(driver, latestVersion)
    }

    ensurePrerequisiteTables(driver)
    ensurePlannerScheduleTables(driver)

    return driver
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
