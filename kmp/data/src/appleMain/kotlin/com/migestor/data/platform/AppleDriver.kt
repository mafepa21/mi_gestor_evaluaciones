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

    fun openAndValidate(): NativeSqliteDriver {
        val d = NativeSqliteDriver(
            schema = AppleAppDatabaseSchema,
            name = databaseName,
            onConfiguration = { config ->
                config.copy(
                    extendedConfig = DatabaseConfiguration.Extended(basePath = basePath)
                )
            },
        )
        try {
            getVersion(d)
        } catch (e: Throwable) {
            try {
                d.close()
            } catch (closeEx: Throwable) {
                println("[AppleDriver] Error closing failed driver: ${closeEx.message}")
            }
            throw e
        }
        return d
    }

    val driver = try {
        openAndValidate()
    } catch (firstError: Throwable) {
        println("[AppleDriver] Error initializing NativeSqliteDriver (intento 1/2): ${firstError.message}")
        // La mayoria de fallos de apertura son transitorios (bloqueo de fichero,
        // disco lleno momentaneamente): un segundo intento evita renombrar y vaciar
        // una base de datos sana por un error que ya se ha resuelto solo.
        platform.posix.usleep(300_000u)
        try {
            openAndValidate()
        } catch (secondError: Throwable) {
            println("[AppleDriver] Error initializing NativeSqliteDriver (intento 2/2): ${secondError.message}")
            rescueUnreadableDatabase(databasePath, secondError)
            openAndValidate()
        }
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

/**
 * La base de datos no se pudo abrir tras dos intentos. En vez de perderla, se renombra
 * a un fichero `.backup_<epoch>` junto al original y se deja un marcador en disco para
 * que la capa SwiftUI avise a la docente en el proximo arranque y le ofrezca reintentar
 * o restaurar, en lugar de seguir en silencio con una base vacia (ver docs/QUALITY_NORTH_STAR.md, I3).
 */
@OptIn(ExperimentalForeignApi::class)
private fun rescueUnreadableDatabase(databasePath: String, error: Throwable) {
    val fileManager = NSFileManager.defaultManager
    if (!fileManager.fileExistsAtPath(databasePath)) return

    val timestamp = platform.posix.time(null)
    val backupPath = "$databasePath.backup_$timestamp"
    println("[AppleDriver] Renaming database $databasePath -> $backupPath to recover")
    fileManager.moveItemAtPath(databasePath, backupPath, null)

    // El WAL contiene transacciones ya confirmadas que aún no se han volcado al fichero
    // principal. Borrarlo destruye datos reales del usuario y deja el .db en cuarentena
    // incompleto e irrecuperable. Se mueven junto al .db para que la cuarentena sea
    // restaurable tal cual.
    for (suffix in listOf("-wal", "-shm")) {
        val sidecarPath = "$databasePath$suffix"
        if (fileManager.fileExistsAtPath(sidecarPath)) {
            fileManager.moveItemAtPath(sidecarPath, "$backupPath$suffix", null)
        }
    }

    writeRescueMarker(
        markerPath = "$databasePath.rescue_marker",
        backupPath = backupPath,
        timestampEpochSeconds = timestamp,
        reason = error.message ?: error.toString(),
    )
}

@OptIn(ExperimentalForeignApi::class)
private fun writeRescueMarker(
    markerPath: String,
    backupPath: String,
    timestampEpochSeconds: Long,
    reason: String,
) {
    val json = """{"backupPath":"${jsonEscape(backupPath)}","timestampEpochSeconds":$timestampEpochSeconds,"reason":"${jsonEscape(reason)}"}"""
    val file = platform.posix.fopen(markerPath, "w")
    if (file == null) {
        println("[AppleDriver] No se pudo escribir el marcador de rescate en $markerPath")
        return
    }
    platform.posix.fputs(json, file)
    platform.posix.fclose(file)
}

private fun jsonEscape(value: String): String {
    val escaped = value
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", " ")
        .replace("\r", " ")
        .replace("\t", " ")
    // Cualquier otro caracter de control roto el JSON si se cuela sin escapar
    // (p.ej. en un mensaje de excepcion arbitrario); se sustituye por espacio.
    return escaped.map { if (it.code < 0x20) ' ' else it }.joinToString("")
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
