package com.migestor.data.service

import com.migestor.data.platform.getMacosAppDataPath
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
        val sourcePath = getMacosAppDataPath("mi_gestor_kmp.db")
        require(fileManager.fileExistsAtPath(sourcePath)) {
            "No existe la base de datos local para backup en $sourcePath"
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

        val targetPath = getMacosAppDataPath("mi_gestor_kmp.db")
        if (fileManager.fileExistsAtPath(targetPath)) {
            fileManager.removeItemAtPath(targetPath, null)
        }
        return fileManager.copyItemAtPath(backupPath, targetPath, null)
    }
}

actual fun createPlatformReportService(): ReportService = PlainTextReportService()
actual fun createPlatformXlsxImportService(): XlsxImportService = UnsupportedXlsxImportService()
actual fun createPlatformBackupService(): BackupService = MacosBackupService()
