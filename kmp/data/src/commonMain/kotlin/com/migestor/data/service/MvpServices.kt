package com.migestor.data.service

import com.migestor.shared.repository.BackupResult
import com.migestor.shared.repository.BackupService
import com.migestor.shared.repository.CsvImportService
import com.migestor.shared.repository.ImportedRubric
import com.migestor.shared.repository.ImportedRubricCriterion
import com.migestor.shared.repository.ImportedRubricLevel
import com.migestor.shared.repository.NotebookReportRequest
import com.migestor.shared.repository.ReportService
import com.migestor.shared.repository.StudentCsvRow
import com.migestor.shared.repository.XlsxImportService

class CsvImportServiceImpl : CsvImportService {
    override suspend fun parseStudents(csv: String): List<StudentCsvRow> {
        val lines = csv.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.toList()
        if (lines.isEmpty()) return emptyList()

        val rows = lines.drop(1)
        return rows.mapNotNull { row ->
            val parts = row.split(';', ',').map { it.trim() }
            if (parts.size < 2) return@mapNotNull null
            StudentCsvRow(
                firstName = parts[0],
                lastName = parts[1],
                email = parts.getOrNull(2)?.ifBlank { null },
            )
        }
    }
}

class PlainTextReportService : ReportService {
    override suspend fun exportNotebookReport(request: NotebookReportRequest): ByteArray {
        val report = buildString {
            appendLine("Informe clase: ${request.className}")
            appendLine("----------------------------------------")
            request.rows.forEach { appendLine(it) }
        }
        return report.encodeToByteArray()
    }
}

class UnsupportedXlsxImportService : XlsxImportService {
    override suspend fun parseStudents(bytes: ByteArray): List<StudentCsvRow> {
        throw UnsupportedOperationException("Importación XLSX no disponible en esta plataforma")
    }

    override suspend fun parseRubric(bytes: ByteArray, fallbackTitle: String): ImportedRubric {
        throw UnsupportedOperationException("Importación XLSX de rúbricas no disponible en esta plataforma")
    }
}

class UnsupportedBackupService : BackupService {
    override suspend fun createBackup(fileName: String): BackupResult {
        throw UnsupportedOperationException("Backup no disponible en esta plataforma")
    }

    override suspend fun restoreBackup(backupPath: String): Boolean {
        throw UnsupportedOperationException("Restore no disponible en esta plataforma")
    }
}

fun defaultRubricFromRows(
    title: String,
    levels: List<String>,
    criteriaRows: List<Pair<String, List<String>>>,
): ImportedRubric {
    val normalizedLevels = levels.mapIndexed { idx, level ->
        ImportedRubricLevel(name = level.ifBlank { "Nivel ${idx + 1}" }, points = idx + 1)
    }
    val criteria = criteriaRows.map { (name, cells) ->
        ImportedRubricCriterion(name = name, cells = cells)
    }
    return ImportedRubric(
        title = title.ifBlank { "Rúbrica importada" },
        levels = normalizedLevels,
        criteria = criteria,
    )
}
