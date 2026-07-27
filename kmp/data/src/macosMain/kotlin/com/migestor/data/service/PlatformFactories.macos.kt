package com.migestor.data.service

import com.migestor.data.platform.getMacosAppDataPath
import com.migestor.data.platform.getMacosDatabasePath
import com.migestor.shared.repository.BackupResult
import com.migestor.shared.repository.BackupService
import com.migestor.shared.repository.ReportService
import com.migestor.shared.repository.XlsxImportService
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.datetime.Clock
import platform.Foundation.NSFileManager

private class MacosBackupService : BackupService {
    @OptIn(ExperimentalForeignApi::class)
    override suspend fun createBackup(fileName: String): BackupResult {
        val fileManager = NSFileManager.defaultManager
        val sourcePath = getMacosDatabasePath()
        require(fileManager.fileExistsAtPath(sourcePath)) {
            "No existe la base de datos local para backup en $sourcePath"
        }
        // Un fichero existente pero vacío no es una base de datos: copiarlo produciría
        // un backup de 0 bytes reportado como correcto, que es exactamente el fallo que
        // dejó a macOS sin copias utilizables durante meses.
        require(sqliteFileSizeBytes(sourcePath) > 0L) {
            "La base de datos en $sourcePath está vacía; no se genera un backup inservible"
        }

        val backupDirectory = getMacosAppDataPath("backups")
        if (!fileManager.fileExistsAtPath(backupDirectory)) {
            fileManager.createDirectoryAtPath(backupDirectory, true, null, null)
        }

        val timestamp = Clock.System.now().toEpochMilliseconds()
        val targetPath = "$backupDirectory/${timestamp}_$fileName"
        if (fileManager.fileExistsAtPath(targetPath)) {
            fileManager.removeItemAtPath(targetPath, null)
        }
        check(fileManager.copyItemAtPath(sourcePath, targetPath, null)) {
            "No se pudo crear el backup en $targetPath"
        }

        val attributes = fileManager.attributesOfItemAtPath(targetPath, null)
        val sizeBytes = (attributes?.get("NSFileSize") as? Number)?.toLong() ?: 0L
        return BackupResult(path = targetPath, sizeBytes = sizeBytes)
    }

    @OptIn(ExperimentalForeignApi::class)
    override suspend fun restoreBackup(backupPath: String): Boolean {
        val fileManager = NSFileManager.defaultManager
        if (!fileManager.fileExistsAtPath(backupPath)) return false
        // Restaurar un backup vacío deja al usuario sin datos y sin aviso.
        if (sqliteFileSizeBytes(backupPath) <= 0L) return false

        val targetPath = getMacosDatabasePath()
        if (fileManager.fileExistsAtPath(targetPath)) {
            fileManager.removeItemAtPath(targetPath, null)
        }
        // Los sidecars del destino pertenecen a la base de datos que estamos sustituyendo:
        // dejarlos haría que SQLite recuperase transacciones de la DB anterior sobre la nueva.
        for (suffix in listOf("-wal", "-shm")) {
            val sidecarPath = "$targetPath$suffix"
            if (fileManager.fileExistsAtPath(sidecarPath)) {
                fileManager.removeItemAtPath(sidecarPath, null)
            }
        }
        return fileManager.copyItemAtPath(backupPath, targetPath, null)
    }
}

@OptIn(ExperimentalForeignApi::class)
private fun sqliteFileSizeBytes(path: String): Long {
    val attributes = NSFileManager.defaultManager.attributesOfItemAtPath(path, null)
    return (attributes?.get("NSFileSize") as? Number)?.toLong() ?: 0L
}

actual fun createPlatformReportService(): ReportService = PlainTextReportService()
actual fun createPlatformXlsxImportService(): XlsxImportService = UnsupportedXlsxImportService()
actual fun createPlatformBackupService(): BackupService = MacosBackupService()
