package com.migestor.data.platform

import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.native.NativeSqliteDriver
import co.touchlab.sqliter.DatabaseConfiguration
import com.migestor.data.db.AppDatabase
import kotlinx.cinterop.ExperimentalForeignApi
import platform.Foundation.NSApplicationSupportDirectory
import platform.Foundation.NSFileManager
import platform.Foundation.NSUserDomainMask

private const val IOS_DB_NAME = "mi_gestor_kmp.db"
private const val IOS_APP_SUPPORT_DIR = "MiGestorKMP"

@OptIn(ExperimentalForeignApi::class)
fun createIosDriver(): SqlDriver {
    val basePath = iosDatabaseBasePath()

    val driver = NativeSqliteDriver(
        schema = AppDatabase.Schema,
        name = IOS_DB_NAME,
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

private fun ensurePrerequisiteTables(driver: SqlDriver) {
    // These tables are referenced by teacher_schedules via foreign keys
    // and used by ensureTeacher()/ensureAcademicYear() in getOrCreatePrimarySchedule().
    // They exist in the base schema (AppDatabase.sq) but no migration creates them
    // for databases that were created before they were added.
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

@OptIn(ExperimentalForeignApi::class)
private fun iosDatabaseBasePath(): String {
    val fileManager = NSFileManager.defaultManager
    val applicationSupportUrl = fileManager.URLForDirectory(
        directory = NSApplicationSupportDirectory,
        inDomain = NSUserDomainMask,
        appropriateForURL = null,
        create = true,
        error = null,
    ) ?: error("No se pudo resolver Application Support en iOS")

    val appDirectoryPath = applicationSupportUrl.path
        ?: error("No se pudo resolver la ruta del directorio de la base de datos")
    val databaseDirectoryPath = "$appDirectoryPath/$IOS_APP_SUPPORT_DIR"

    fileManager.createDirectoryAtPath(databaseDirectoryPath, true, null, null)

    return databaseDirectoryPath
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
