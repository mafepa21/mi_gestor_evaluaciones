package com.migestor.data.service

import com.migestor.shared.repository.BackupService
import com.migestor.shared.repository.ReportService
import com.migestor.shared.repository.XlsxImportService

expect fun createPlatformReportService(): ReportService
expect fun createPlatformXlsxImportService(): XlsxImportService
expect fun createPlatformBackupService(): BackupService
