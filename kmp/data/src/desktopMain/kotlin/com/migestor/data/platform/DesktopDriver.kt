package com.migestor.data.platform

import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import java.io.File
import java.io.RandomAccessFile
import java.nio.channels.FileChannel
import java.nio.channels.FileLock
import java.nio.file.Files
import java.nio.file.StandardCopyOption

private const val DEFAULT_DESKTOP_DB_NAME = "desktop_mi_gestor_kmp.db"
private const val SQLITE_BUSY_TIMEOUT_MS = 5_000

fun createDesktopDriver(
    dbPath: String? = null,
    dbName: String = DEFAULT_DESKTOP_DB_NAME,
): JdbcSqliteDriver {
    return openDesktopDriver(
        dbFile = resolveDesktopDatabaseFile(dbPath = dbPath, dbName = dbName),
        legacyDbName = dbName,
        acquireExclusiveLock = true,
    )
}

fun createSharedDesktopDriver(
    dbPath: String? = null,
    dbName: String = DEFAULT_DESKTOP_DB_NAME,
): JdbcSqliteDriver {
    return openDesktopDriver(
        dbFile = resolveDesktopDatabaseFile(dbPath = dbPath, dbName = dbName),
        legacyDbName = dbName,
        acquireExclusiveLock = false,
    )
}

private fun openDesktopDriver(
    dbFile: File,
    legacyDbName: String,
    acquireExclusiveLock: Boolean,
): JdbcSqliteDriver {
    ensureParentDirectory(dbFile)
    migrateLegacyDatabaseIfNeeded(legacyDbName, dbFile)
    if (acquireExclusiveLock) {
        acquireDesktopDatabaseLock(dbFile)
    }

    val driver = runCatching {
        JdbcSqliteDriver("jdbc:sqlite:${dbFile.absolutePath}")
    }.getOrElse { cause ->
        throw IllegalStateException(
            "No se pudo abrir la base de datos SQLite en ${dbFile.absolutePath}",
            cause
        )
    }

    configureDesktopSqlite(driver)

    val currentVersion = getVersion(driver)
    val latestVersion = AppDatabase.Schema.version

    if (currentVersion == 0L) {
        AppDatabase.Schema.create(driver)
        setVersion(driver, latestVersion)
    } else if (currentVersion < latestVersion) {
        AppDatabase.Schema.migrate(driver, currentVersion, latestVersion)
        setVersion(driver, latestVersion)
    }

    ensurePlannerScheduleTables(driver)

    return driver
}

private fun resolveDesktopDatabaseFile(
    dbPath: String? = null,
    dbName: String = DEFAULT_DESKTOP_DB_NAME,
): File {
    val normalizedPath = dbPath?.trim()?.takeIf { it.isNotEmpty() }
    return if (normalizedPath != null) File(normalizedPath) else File(getAppDataPath(dbName))
}

private fun configureDesktopSqlite(driver: JdbcSqliteDriver) {
    driver.execute(null, "PRAGMA journal_mode = WAL", 0)
    driver.execute(null, "PRAGMA busy_timeout = $SQLITE_BUSY_TIMEOUT_MS", 0)
}

private var desktopDbLockChannel: FileChannel? = null
private var desktopDbLock: FileLock? = null

private fun acquireDesktopDatabaseLock(dbFile: File) {
    if (desktopDbLock?.isValid == true) return

    val lockFile = File(dbFile.parentFile, "${dbFile.name}.lock")
    val channel = RandomAccessFile(lockFile, "rw").channel
    val lock = try {
        channel.tryLock()
    } catch (_: Throwable) {
        null
    }

    if (lock == null) {
        channel.close()
        throw IllegalStateException(
            "La base de datos ya está en uso. Cierra otras instancias de MiGestor y vuelve a intentarlo."
        )
    }

    desktopDbLockChannel = channel
    desktopDbLock = lock
}

fun releaseDesktopDatabaseLock() {
    runCatching { desktopDbLock?.release() }
    runCatching { desktopDbLockChannel?.close() }
    desktopDbLock = null
    desktopDbLockChannel = null
}

private fun ensureParentDirectory(dbFile: File) {
    val parent = dbFile.parentFile ?: return
    if (parent.exists()) return
    check(parent.mkdirs()) {
        "No se pudo crear el directorio de datos: ${parent.absolutePath}"
    }
}

private fun migrateLegacyDatabaseIfNeeded(dbName: String, targetDbFile: File) {
    if (targetDbFile.exists()) return
    val legacyDbFile = File(getLegacyAppDataPath(dbName))
    if (!legacyDbFile.exists()) return
    Files.copy(legacyDbFile.toPath(), targetDbFile.toPath(), StandardCopyOption.REPLACE_EXISTING)
}

private fun getVersion(driver: SqlDriver): Long {
    return driver.executeQuery(
        null,
        "PRAGMA user_version",
        { cursor ->
            val version = if (cursor.next().value) cursor.getLong(0) ?: 0L else 0L
            QueryResult.Value(version)
        },
        0
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

fun getAppDataPath(fileName: String): String {
    val os = System.getProperty("os.name").lowercase()
    val userHome = System.getProperty("user.home")
    val appName = "MiGestor"
    
    val baseDir = when {
        os.contains("mac") -> "$userHome/Library/Application Support/$appName"
        os.contains("win") -> System.getenv("APPDATA") + "\\$appName"
        else -> "$userHome/.local/share/$appName"
    }
    
    File(baseDir).mkdirs()
    return File(baseDir, fileName).absolutePath
}

private fun getLegacyAppDataPath(fileName: String): String {
    val os = System.getProperty("os.name").lowercase()
    val userHome = System.getProperty("user.home")
    val appName = "MiGestorKMP"

    val baseDir = when {
        os.contains("mac") -> "$userHome/Library/Application Support/$appName"
        os.contains("win") -> System.getenv("APPDATA") + "\\$appName"
        else -> "$userHome/.local/share/$appName"
    }

    return File(baseDir, fileName).absolutePath
}
