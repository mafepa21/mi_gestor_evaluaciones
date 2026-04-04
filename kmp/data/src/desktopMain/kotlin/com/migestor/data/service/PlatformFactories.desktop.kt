package com.migestor.data.service

import com.migestor.shared.repository.BackupService
import com.migestor.shared.repository.ReportService
import com.migestor.shared.repository.XlsxImportService

actual fun createPlatformReportService(): ReportService = DesktopPdfReportService()
actual fun createPlatformXlsxImportService(): XlsxImportService = DesktopXlsxImportService()
actual fun createPlatformBackupService(): BackupService = DesktopBackupService()
