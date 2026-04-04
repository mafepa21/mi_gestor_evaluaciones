package com.migestor.data.service

import com.migestor.shared.repository.BackupService
import com.migestor.shared.repository.ReportService
import com.migestor.shared.repository.XlsxImportService

actual fun createPlatformReportService(): ReportService = PlainTextReportService()
actual fun createPlatformXlsxImportService(): XlsxImportService = UnsupportedXlsxImportService()
actual fun createPlatformBackupService(): BackupService = UnsupportedBackupService()
