package com.migestor.data.platform

import app.cash.sqldelight.TransacterImpl
import app.cash.sqldelight.db.AfterVersion
import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.db.SqlSchema
import app.cash.sqldelight.driver.native.NativeSqliteDriver
import co.touchlab.sqliter.DatabaseConfiguration
import com.migestor.data.db.AppDatabase
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.usePinned
import platform.Foundation.NSFileManager
import platform.Foundation.NSString
import platform.Foundation.NSUTF8StringEncoding
import platform.Foundation.stringWithContentsOfFile
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

    val adoptionBackupPath = applyPendingAdoptionIfNeeded(
        basePath = basePath,
        databasePath = databasePath,
        databaseName = databaseName,
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
            val rescuedBackupPath = rescueUnreadableDatabase(databasePath, secondError)
            try {
                openAndValidate()
            } catch (thirdError: Throwable) {
                // Ni siquiera se puede crear una base nueva (disco lleno, permisos rotos en
                // Application Support...). Lanzar aquí cierra la app en cada arranque sin
                // explicación, porque Swift no puede capturar excepciones de Kotlin. Se
                // arranca con una base en memoria y se deja el marcador para que la docente
                // vea el aviso de rescate.
                println("[AppleDriver] Error initializing NativeSqliteDriver (intento 3/3): ${thirdError.message}")
                writeRescueMarker(
                    markerPath = "$databasePath.rescue_marker",
                    backupPath = rescuedBackupPath ?: databasePath,
                    timestampEpochSeconds = platform.posix.time(null),
                    reason = "No se pudo crear una base nueva (${thirdError.message ?: thirdError.toString()}). " +
                        "La app funciona con una base temporal: los cambios de esta sesión no se guardarán.",
                )
                openInMemoryFallback(databaseName)
            }
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

    configureAppleSqlite(driver)

    if (adoptionBackupPath != null) {
        carryOverWebFormsAfterAdoption(driver = driver, backupPath = adoptionBackupPath, basePath = basePath)
    }

    return driver
}

private fun openInMemoryFallback(databaseName: String): NativeSqliteDriver =
    NativeSqliteDriver(
        schema = AppleAppDatabaseSchema,
        name = "fallback_$databaseName",
        onConfiguration = { config -> config.copy(inMemory = true) },
    )

private fun configureAppleSqlite(driver: SqlDriver) {
    // Algunos PRAGMA de asignación devuelven una fila (mmap_size, por ejemplo) y
    // sqliter rechaza ejecutarlos con `execute`. Con `executeQuery` funcionan todos,
    // devuelvan fila o no. Cada uno va por separado para que un fallo no salte el resto.
    listOf(
        "PRAGMA synchronous = NORMAL",
        "PRAGMA cache_size = -64000",
        "PRAGMA mmap_size = 268435456",
        "PRAGMA temp_store = MEMORY",
    ).forEach { pragma ->
        try {
            // `next()` hace el step: sin él el PRAGMA no llega a ejecutarse.
            driver.executeQuery(null, pragma, { cursor -> cursor.next(); QueryResult.Unit }, 0)
        } catch (e: Throwable) {
            println("[AppleDriver] Warning applying '$pragma': ${e.message}")
        }
    }
}

/**
 * La base de datos no se pudo abrir tras dos intentos. En vez de perderla, se renombra
 * a un fichero `.backup_<epoch>` junto al original y se deja un marcador en disco para
 * que la capa SwiftUI avise a la docente en el proximo arranque y le ofrezca reintentar
 * o restaurar, en lugar de seguir en silencio con una base vacia (ver docs/QUALITY_NORTH_STAR.md, I3).
 */
@OptIn(ExperimentalForeignApi::class)
private fun rescueUnreadableDatabase(databasePath: String, error: Throwable): String? {
    val fileManager = NSFileManager.defaultManager
    if (!fileManager.fileExistsAtPath(databasePath)) return null

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
    return backupPath
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

    // Se copian también -wal y -shm: el WAL guarda transacciones confirmadas que aún
    // no están en el .db. Si la copia falla, se borra lo copiado a medias para que el
    // siguiente arranque lo reintente en vez de quedarse con una base vacía.
    val copied = fileManager.copyItemAtPath(sourcePath, targetDatabasePath, null)
    val sidecarsCopied = copied && listOf("-wal", "-shm").all { suffix ->
        val sidecar = "$sourcePath$suffix"
        !fileManager.fileExistsAtPath(sidecar) ||
            fileManager.copyItemAtPath(sidecar, "$targetDatabasePath$suffix", null)
    }
    if (!sidecarsCopied) {
        println("[AppleDriver] No se pudo copiar la base antigua $sourcePath; se reintentará en el próximo arranque")
        for (path in listOf(targetDatabasePath, "$targetDatabasePath-wal", "$targetDatabasePath-shm")) {
            if (fileManager.fileExistsAtPath(path)) fileManager.removeItemAtPath(path, null)
        }
    }
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

@OptIn(ExperimentalForeignApi::class)
/**
 * Aplica la base que dejó preparada «Igualar dispositivos». Devuelve la ruta de la copia
 * previa si la adopción se aplicó y había base anterior; `null` en cualquier otro caso.
 */
internal fun applyPendingAdoptionIfNeeded(
    basePath: String,
    databasePath: String,
    databaseName: String,
): String? {
    val fileManager = NSFileManager.defaultManager
    val pendingMarkerPath = "$basePath/pending_adopt.json"
    val pendingDbPath = "$basePath/pending_adopt.db"

    if (!fileManager.fileExistsAtPath(pendingMarkerPath)) {
        return null
    }

    if (!fileManager.fileExistsAtPath(pendingDbPath)) {
        println("[AppleDriver] Encontrado pending_adopt.json pero falta pending_adopt.db. Limpiando marcador huérfano.")
        fileManager.removeItemAtPath(pendingMarkerPath, null)
        return null
    }

    val epoch = platform.posix.time(null)

    // Se valida antes de tocar la base activa: un cuerpo vacío, una página de error o
    // una base de una versión más nueva de la app dejarían a la docente con la app vacía.
    val invalidReason = adoptionCandidateProblem(pendingDbPath)
    if (invalidReason != null) {
        println("[AppleDriver] Adopción rechazada: $invalidReason")
        val rejectJson = """{"status":"failed","error":"${jsonEscape(invalidReason)}","failedAtEpochMs":${epoch * 1000L}}"""
        val f = platform.posix.fopen("$basePath/last_adoption.json", "w")
        if (f != null) {
            platform.posix.fputs(rejectJson, f)
            platform.posix.fclose(f)
        }
        fileManager.removeItemAtPath(pendingDbPath, null)
        fileManager.removeItemAtPath(pendingMarkerPath, null)
        return null
    }

    val backupsDir = "$basePath/backups"
    fileManager.createDirectoryAtPath(backupsDir, true, null, null)

    val backupPath = "$backupsDir/${epoch}_pre_adopt_$databaseName"
    val dbExists = fileManager.fileExistsAtPath(databasePath)

    try {
        if (dbExists) {
            println("[AppleDriver] Creando backup de seguridad previo a adopción en $backupPath")
            fileManager.copyItemAtPath(databasePath, backupPath, null)
            for (suffix in listOf("-wal", "-shm")) {
                val sidecar = "$databasePath$suffix"
                if (fileManager.fileExistsAtPath(sidecar)) {
                    fileManager.copyItemAtPath(sidecar, "$backupPath$suffix", null)
                }
            }
        }

        // 1. Borrar base de datos actual y sus sidecars
        if (fileManager.fileExistsAtPath(databasePath)) {
            fileManager.removeItemAtPath(databasePath, null)
        }
        for (suffix in listOf("-wal", "-shm")) {
            val sidecar = "$databasePath$suffix"
            if (fileManager.fileExistsAtPath(sidecar)) {
                fileManager.removeItemAtPath(sidecar, null)
            }
        }

        // 2. Mover pending_adopt.db a databasePath
        val moved = fileManager.moveItemAtPath(pendingDbPath, databasePath, null)
        if (!moved && !fileManager.fileExistsAtPath(databasePath)) {
            throw IllegalStateException("No se pudo mover $pendingDbPath a $databasePath")
        }

        // 3. Eliminar marcador de staging
        fileManager.removeItemAtPath(pendingMarkerPath, null)

        // 4. Escribir last_adoption.json con éxito
        val lastAdoptionJson = """{"status":"applied","backupPath":"${jsonEscape(backupPath)}","appliedAtEpochMs":${epoch * 1000L}}"""
        val lastAdoptionPath = "$basePath/last_adoption.json"
        val f = platform.posix.fopen(lastAdoptionPath, "w")
        if (f != null) {
            platform.posix.fputs(lastAdoptionJson, f)
            platform.posix.fclose(f)
        }
        println("[AppleDriver] Adopción de dataset aplicada correctamente. Backup guardado en $backupPath")
        pruneOldPreAdoptBackups(backupsDir = backupsDir, databaseName = databaseName, maxBackups = 5)
        return if (dbExists) backupPath else null
    } catch (e: Throwable) {
        println("[AppleDriver] Error al aplicar adopción: ${e.message}. Ejecutando restauración de emergencia...")
        if (dbExists && fileManager.fileExistsAtPath(backupPath)) {
            fileManager.removeItemAtPath(databasePath, null)
            fileManager.copyItemAtPath(backupPath, databasePath, null)
            for (suffix in listOf("-wal", "-shm")) {
                val backupSidecar = "$backupPath$suffix"
                val sidecar = "$databasePath$suffix"
                if (fileManager.fileExistsAtPath(backupSidecar)) {
                    fileManager.removeItemAtPath(sidecar, null)
                    fileManager.copyItemAtPath(backupSidecar, sidecar, null)
                }
            }
        }
        val failJson = """{"status":"failed","error":"${jsonEscape(e.message ?: e.toString())}","backupPath":"${jsonEscape(backupPath)}","failedAtEpochMs":${epoch * 1000L}}"""
        val lastAdoptionPath = "$basePath/last_adoption.json"
        val f = platform.posix.fopen(lastAdoptionPath, "w")
        if (f != null) {
            platform.posix.fputs(failJson, f)
            platform.posix.fclose(f)
        }
        fileManager.removeItemAtPath(pendingMarkerPath, null)
        return null
    }
}

/**
 * Tras igualar, devuelve a la base nueva las entregas web que este equipo tenía
 * (ver [carryOverLocalOnlyWebForms]). Se lee de una copia temporal de la copia previa
 * para no tocar esta, que sigue siendo la red de seguridad de la docente. Un fallo
 * aquí no deshace la adopción: se anota en `last_adoption.json` y la app arranca.
 */
@OptIn(ExperimentalForeignApi::class)
private fun carryOverWebFormsAfterAdoption(driver: SqlDriver, backupPath: String, basePath: String) {
    val fileManager = NSFileManager.defaultManager
    val backupsDir = backupPath.substringBeforeLast('/')
    val sourceName = "carry_over_source.db"
    val sourcePath = "$backupsDir/$sourceName"
    val suffixes = listOf("", "-wal", "-shm")
    fun removeSource() = suffixes.forEach { fileManager.removeItemAtPath("$sourcePath$it", null) }

    val note = try {
        removeSource()
        for (suffix in suffixes) {
            if (fileManager.fileExistsAtPath("$backupPath$suffix")) {
                fileManager.copyItemAtPath("$backupPath$suffix", "$sourcePath$suffix", null)
            }
        }
        val source = NativeSqliteDriver(
            schema = ExistingDatabaseSchema,
            name = sourceName,
            onConfiguration = { config ->
                config.copy(extendedConfig = DatabaseConfiguration.Extended(basePath = backupsDir))
            },
        )
        val result = try {
            carryOverLocalOnlyWebForms(source = source, target = driver, transacter = object : TransacterImpl(driver) {})
        } finally {
            source.close()
        }
        println("[AppleDriver] Entregas web conservadas tras igualar: ${result.restoredForms}, saltadas: ${result.skippedForms}")
        "\"webFormsRestored\":${result.restoredForms},\"webFormsSkipped\":${result.skippedForms}"
    } catch (e: Throwable) {
        println("[AppleDriver] No se pudieron conservar las entregas web tras igualar: ${e.message}")
        "\"webFormsError\":\"${jsonEscape(e.message ?: e.toString())}\""
    } finally {
        removeSource()
    }

    val lastAdoptionPath = "$basePath/last_adoption.json"
    val previous = NSString.stringWithContentsOfFile(lastAdoptionPath, NSUTF8StringEncoding, null)?.trim()
    if (previous != null && previous.endsWith("}")) {
        val updated = previous.dropLast(1) + ",$note}"
        val f = platform.posix.fopen(lastAdoptionPath, "w")
        if (f != null) {
            platform.posix.fputs(updated, f)
            platform.posix.fclose(f)
        }
    }
}

/** Abre una base que ya existe tal cual está: ni la crea ni la migra. */
private object ExistingDatabaseSchema : SqlSchema<QueryResult.Value<Unit>> {
    override val version: Long = AppDatabase.Schema.version

    override fun create(driver: SqlDriver): QueryResult.Value<Unit> = QueryResult.Value(Unit)

    override fun migrate(
        driver: SqlDriver,
        oldVersion: Long,
        newVersion: Long,
        vararg callbacks: AfterVersion,
    ): QueryResult.Value<Unit> = QueryResult.Value(Unit)
}

/**
 * Devuelve el motivo por el que [path] no es una base adoptable, o `null` si lo es.
 * Lee la cabecera SQLite (100 bytes): la firma y `user_version` (offset 60, big endian).
 */
@OptIn(ExperimentalForeignApi::class)
internal fun adoptionCandidateProblem(path: String): String? {
    val header = ByteArray(100)
    val file = platform.posix.fopen(path, "rb") ?: return "no se pudo leer la base recibida"
    val read = try {
        header.usePinned { pinned -> platform.posix.fread(pinned.addressOf(0), 1u, 100u, file).toInt() }
    } finally {
        platform.posix.fclose(file)
    }
    if (read < 100) return "la base recibida está vacía o incompleta"
    val signature = "SQLite format 3\u0000".encodeToByteArray()
    if (!header.copyOfRange(0, 16).contentEquals(signature)) {
        return "el archivo recibido no es una base de datos"
    }
    val userVersion = (60 until 64).fold(0L) { acc, i -> (acc shl 8) or (header[i].toLong() and 0xFF) }
    if (userVersion > AppDatabase.Schema.version) {
        return "la base recibida es de una versión más nueva de la app ($userVersion > ${AppDatabase.Schema.version}); actualiza la app en este dispositivo"
    }
    return null
}

@OptIn(ExperimentalForeignApi::class)
private fun pruneOldPreAdoptBackups(backupsDir: String, databaseName: String, maxBackups: Int = 5) {
    val fileManager = NSFileManager.defaultManager
    @Suppress("UNCHECKED_CAST")
    val items = fileManager.contentsOfDirectoryAtPath(backupsDir, null) as? List<String> ?: return
    val preAdoptFiles = items
        .filter { it.contains("_pre_adopt_$databaseName") && !it.endsWith("-wal") && !it.endsWith("-shm") }
        .sortedDescending()

    if (preAdoptFiles.size > maxBackups) {
        val toDelete = preAdoptFiles.drop(maxBackups)
        for (fileName in toDelete) {
            val mainPath = "$backupsDir/$fileName"
            fileManager.removeItemAtPath(mainPath, null)
            for (suffix in listOf("-wal", "-shm")) {
                fileManager.removeItemAtPath("$mainPath$suffix", null)
            }
            println("[AppleDriver] Rotación de backup pre-adopción: purgado $fileName")
        }
    }
}
