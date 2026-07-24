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

    var firstAttemptDriver: NativeSqliteDriver? = null
    val driver = try {
        val d = NativeSqliteDriver(
            schema = AppleAppDatabaseSchema,
            name = databaseName,
            onConfiguration = { config ->
                config.copy(
                    extendedConfig = DatabaseConfiguration.Extended(basePath = basePath)
                )
            },
        )
        firstAttemptDriver = d
        getVersion(d)
        d
    } catch (e: Throwable) {
        println("[AppleDriver] Error initializing NativeSqliteDriver: ${e.message}")
        try {
            firstAttemptDriver?.close()
        } catch (closeEx: Throwable) {
            println("[AppleDriver] Error closing failed driver: ${closeEx.message}")
        }

        val fileManager = NSFileManager.defaultManager
        if (fileManager.fileExistsAtPath(databasePath)) {
            val timestamp = platform.posix.time(null)
            val backupPath = "$databasePath.backup_$timestamp"
            println("[AppleDriver] Renaming database $databasePath -> $backupPath to recover")
            fileManager.moveItemAtPath(databasePath, backupPath, null)

            val walPath = "$databasePath-wal"
            if (fileManager.fileExistsAtPath(walPath)) {
                fileManager.removeItemAtPath(walPath, null)
            }
            val shmPath = "$databasePath-shm"
            if (fileManager.fileExistsAtPath(shmPath)) {
                fileManager.removeItemAtPath(shmPath, null)
            }
        }

        NativeSqliteDriver(
            schema = AppleAppDatabaseSchema,
            name = databaseName,
            onConfiguration = { config ->
                config.copy(
                    extendedConfig = DatabaseConfiguration.Extended(basePath = basePath)
                )
            },
        )
    }

    val currentVersion = getVersion(driver)
    val latestVersion = AppDatabase.Schema.version

    if (currentVersion == 0L) {
        AppleAppDatabaseSchema.create(driver)
        setVersion(driver, latestVersion)
    } else if (currentVersion < latestVersion) {
        AppleAppDatabaseSchema.migrate(driver, currentVersion, latestVersion)
        setVersion(driver, latestVersion)
    }

    // Red de seguridad idempotente compartida con desktop (commonMain):
    // ver com.migestor.data.platform.runRescueMigrations en RescueMigrations.kt.
    // Cubre columnas de notebook_columns/notebook_tabs, las tablas de
    // instrumentos estructurados, las tablas prerequisito multi-centro y las
    // tablas del planner, para que Apple y desktop no puedan divergir.
    runRescueMigrations(driver)

    return driver
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
