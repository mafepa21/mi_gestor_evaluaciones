package com.migestor.data.service
 
import com.migestor.data.platform.getAppDataPath

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.lowagie.text.Document
import com.lowagie.text.Paragraph
import com.lowagie.text.pdf.PdfWriter
import com.migestor.shared.repository.BackupResult
import com.migestor.shared.repository.BackupService
import com.migestor.shared.repository.ImportedRubric
import com.migestor.shared.repository.NotebookReportRequest
import com.migestor.shared.repository.ReportService
import com.migestor.shared.repository.StudentCsvRow
import com.migestor.shared.repository.XlsxImportService
import org.apache.poi.ss.usermodel.CellType
import org.apache.poi.ss.usermodel.Row
import org.apache.poi.xssf.usermodel.XSSFWorkbook
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.Instant
import java.time.format.DateTimeFormatter

class DesktopPdfReportService : ReportService {
    override suspend fun exportNotebookReport(request: NotebookReportRequest): ByteArray {
        val output = ByteArrayOutputStream()
        val document = Document()
        PdfWriter.getInstance(document, output)
        document.open()
        document.add(Paragraph("Informe clase: ${request.className}"))
        document.add(Paragraph(" "))
        request.rows.forEach { row -> document.add(Paragraph(row)) }
        document.close()
        return output.toByteArray()
    }
}

class DesktopXlsxImportService : XlsxImportService {
    override suspend fun parseStudents(bytes: ByteArray): List<StudentCsvRow> {
        XSSFWorkbook(ByteArrayInputStream(bytes)).use { workbook ->
            val sheet = workbook.getSheetAt(0)
            val rows = mutableListOf<StudentCsvRow>()

            for (i in 1..sheet.lastRowNum) {
                val row = sheet.getRow(i) ?: continue
                val firstName = row.getCellText(0)
                val lastName = row.getCellText(1)
                val email = row.getCellText(2).ifBlank { null }
                if (firstName.isBlank() || lastName.isBlank()) continue
                rows += StudentCsvRow(firstName = firstName, lastName = lastName, email = email)
            }
            return rows
        }
    }

    override suspend fun parseRubric(bytes: ByteArray, fallbackTitle: String): ImportedRubric {
        XSSFWorkbook(ByteArrayInputStream(bytes)).use { workbook ->
            val sheet = workbook.getSheetAt(0)
            val title = sheet.getRow(0)?.getCellText(0)?.ifBlank { fallbackTitle } ?: fallbackTitle
            val header = sheet.getRow(1)
            val levels = mutableListOf<String>()
            if (header != null) {
                for (i in 1 until header.lastCellNum.toInt()) {
                    val cell = header.getCellText(i)
                    if (cell.isNotBlank()) levels += cell
                }
            }

            val criteriaRows = mutableListOf<Pair<String, List<String>>>()
            for (i in 2..sheet.lastRowNum) {
                val row = sheet.getRow(i) ?: continue
                val name = row.getCellText(0)
                if (name.isBlank()) continue
                val cells = levels.indices.map { index -> row.getCellText(index + 1) }
                criteriaRows += name to cells
            }

            return defaultRubricFromRows(title = title, levels = levels, criteriaRows = criteriaRows)
        }
    }

    private fun Row.getCellText(index: Int): String {
        val cell = getCell(index) ?: return ""
        return when (cell.cellType) {
            CellType.STRING -> cell.stringCellValue.trim()
            CellType.NUMERIC -> {
                val value = cell.numericCellValue
                if (value % 1.0 == 0.0) value.toInt().toString() else value.toString()
            }
            CellType.BOOLEAN -> cell.booleanCellValue.toString()
            CellType.FORMULA -> cell.toString().trim()
            else -> ""
        }
    }
}

private const val BACKUP_CHECKPOINT_BUSY_TIMEOUT_MS = 5_000

class DesktopBackupService : BackupService {
    override suspend fun createBackup(fileName: String): BackupResult {
        // Use the same DB name as in createDesktopDriver
        val sourcePath = getAppDataPath("desktop_mi_gestor_kmp.db")
        val source = File(sourcePath)
        require(source.exists()) { "No existe la base de datos local para backup en $sourcePath" }

        // La BD vive en modo WAL (createDesktopDriver activa journal_mode=WAL):
        // las transacciones confirmadas mas recientes pueden vivir solo en el
        // -wal hasta el siguiente checkpoint. Sin este paso, un backup podia
        // "tener exito" sin contener las ultimas notas de la sesion.
        checkpointWal(source)

        val backupDirPath = getAppDataPath("backups")
        val backupDir = File(backupDirPath).also { it.mkdirs() }

        val timestamp = DateTimeFormatter.ISO_INSTANT.format(Instant.now()).replace(':', '-')
        val target = File(backupDir, "${timestamp}_$fileName")
        Files.copy(source.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)

        return BackupResult(path = target.absolutePath, sizeBytes = target.length())
    }

    override suspend fun restoreBackup(backupPath: String): Boolean {
        val source = File(backupPath)
        if (!source.exists()) return false

        val targetPath = getAppDataPath("desktop_mi_gestor_kmp.db")
        val target = File(targetPath)
        Files.copy(source.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)

        // Descarta el WAL/SHM del fichero anterior: aunque SQLite deberia
        // ignorar un WAL cuyo "salt" no coincide con la cabecera del .db recien
        // restaurado, no dependemos de esa deteccion implicita -se borran para
        // garantizar que la siguiente apertura parte de un estado limpio, en
        // vez de arrastrar paginas cacheadas de la BD sustituida.
        File(target.parentFile, "${target.name}-wal").delete()
        File(target.parentFile, "${target.name}-shm").delete()

        return true
    }

    /**
     * Vuelca el WAL al fichero principal antes de copiarlo. Abre una conexion
     * corta independiente sobre el mismo fichero -SQLite soporta multiples
     * conexiones a una misma BD en modo WAL- para no depender de tener acceso
     * a la conexion viva de la app.
     */
    private fun checkpointWal(dbFile: File) {
        val driver = runCatching { JdbcSqliteDriver("jdbc:sqlite:${dbFile.absolutePath}") }.getOrNull() ?: return
        try {
            driver.execute(null, "PRAGMA busy_timeout = $BACKUP_CHECKPOINT_BUSY_TIMEOUT_MS", 0)
            driver.execute(null, "PRAGMA wal_checkpoint(TRUNCATE)", 0)
        } catch (_: Exception) {
            // Best-effort: si el checkpoint no se puede completar (p. ej. la app
            // tiene un lector activo justo en ese instante), seguimos con la
            // copia tal cual estuviera el .db; es el mismo comportamiento previo
            // a este fix, no una regresion.
        } finally {
            driver.close()
        }
    }
}
