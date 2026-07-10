package com.migestor.data.repository

import com.migestor.data.db.AppDatabase
import com.migestor.shared.domain.AuditTrace
import com.migestor.shared.domain.NotebookInstrumentCellSummary
import com.migestor.shared.domain.NotebookInstrumentDetail
import com.migestor.shared.domain.NotebookInstrumentItem
import com.migestor.shared.domain.NotebookInstrumentItemType
import com.migestor.shared.domain.NotebookInstrumentResponse
import com.migestor.shared.domain.NotebookInstrumentTemplate
import com.migestor.shared.domain.NotebookInstrumentTemplateKind
import com.migestor.shared.domain.NotebookCellInputKind
import com.migestor.shared.repository.GradesRepository
import com.migestor.shared.repository.NotebookInstrumentsRepository
import com.migestor.shared.usecase.NotebookSheetMemoryCache
import com.migestor.shared.util.NotebookRefreshBus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

class NotebookInstrumentsRepositorySqlDelight(
    private val db: AppDatabase,
    private val gradesRepository: GradesRepository,
    private val sheetCache: NotebookSheetMemoryCache,
) : NotebookInstrumentsRepository {

    override suspend fun saveTemplate(
        template: NotebookInstrumentTemplate,
        items: List<NotebookInstrumentItem>,
    ) = withContext(Dispatchers.Default) {
        val now = template.trace.updatedAt.toEpochMilliseconds().takeIf { it > 0 }
            ?: Clock.System.now().toEpochMilliseconds()
        db.transaction {
            db.appDatabaseQueries.upsertInstrumentTemplate(
                id = template.id,
                class_id = template.classId,
                column_id = template.columnId,
                evaluation_id = template.evaluationId,
                title = template.title,
                kind = template.kind.name,
                input_kind = template.inputKind.name,
                source = template.source,
                created_at_epoch_ms = template.trace.createdAt.toEpochMilliseconds().takeIf { it > 0 } ?: now,
                updated_at_epoch_ms = now,
                device_id = template.trace.deviceId,
                sync_version = template.trace.syncVersion,
            )
            db.appDatabaseQueries.deleteInstrumentItemsByTemplate(template.id)
            items.forEachIndexed { index, item ->
                db.appDatabaseQueries.upsertInstrumentItem(
                    id = item.id,
                    template_id = template.id,
                    item_key = item.key,
                    title = item.title,
                    item_type = item.type.name,
                    options_csv = item.options.joinToString("|"),
                    required = if (item.required) 1L else 0L,
                    sort_order = item.order.takeIf { it >= 0 }?.toLong() ?: index.toLong(),
                    help_text = item.helpText,
                    updated_at_epoch_ms = item.trace.updatedAt.toEpochMilliseconds().takeIf { it > 0 } ?: now,
                    device_id = item.trace.deviceId,
                    sync_version = item.trace.syncVersion,
                )
            }
        }
        NotebookRefreshBus.emitRefresh()
    }

    override suspend fun getTemplateForColumn(columnId: String): NotebookInstrumentDetail? = withContext(Dispatchers.Default) {
        val templateRow = db.appDatabaseQueries.selectInstrumentTemplateByColumn(columnId).executeAsOneOrNull()
            ?: return@withContext null
        val template = NotebookInstrumentTemplate(
            id = templateRow.id,
            classId = templateRow.class_id,
            columnId = templateRow.column_id,
            evaluationId = templateRow.evaluation_id,
            title = templateRow.title,
            kind = templateKind(templateRow.kind),
            inputKind = inputKind(templateRow.input_kind),
            source = templateRow.source,
            trace = AuditTrace(
                createdAt = Instant.fromEpochMilliseconds(templateRow.created_at_epoch_ms),
                updatedAt = Instant.fromEpochMilliseconds(templateRow.updated_at_epoch_ms),
                deviceId = templateRow.device_id,
                syncVersion = templateRow.sync_version,
            ),
        )
        val items = db.appDatabaseQueries.selectInstrumentItemsByTemplate(template.id).executeAsList().map { row ->
            NotebookInstrumentItem(
                id = row.id,
                templateId = row.template_id,
                key = row.item_key,
                title = row.title,
                type = itemType(row.item_type),
                options = row.options_csv.split("|").filter { it.isNotBlank() },
                required = row.required != 0L,
                order = row.sort_order.toInt(),
                helpText = row.help_text,
                trace = AuditTrace(
                    updatedAt = Instant.fromEpochMilliseconds(row.updated_at_epoch_ms),
                    deviceId = row.device_id,
                    syncVersion = row.sync_version,
                ),
            )
        }
        NotebookInstrumentDetail(template = template, items = items)
    }

    override suspend fun listResponsesForCell(
        classId: Long,
        studentId: Long,
        columnId: String,
    ): List<NotebookInstrumentResponse> = withContext(Dispatchers.Default) {
        db.appDatabaseQueries.selectInstrumentResponsesForCell(classId, studentId, columnId).executeAsList().map { row ->
            NotebookInstrumentResponse(
                classId = row.class_id,
                studentId = row.student_id,
                columnId = row.column_id,
                itemId = row.item_id,
                textValue = row.value_text,
                boolValue = row.value_bool?.let { it != 0L },
                numberValue = row.value_number,
                trace = AuditTrace(
                    updatedAt = Instant.fromEpochMilliseconds(row.updated_at_epoch_ms),
                    deviceId = row.device_id,
                    syncVersion = row.sync_version,
                ),
            )
        }
    }

    override suspend fun saveResponses(
        classId: Long,
        studentId: Long,
        columnId: String,
        responses: List<NotebookInstrumentResponse>,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): NotebookInstrumentCellSummary = withContext(Dispatchers.Default) {
        val detail = getTemplateForColumn(columnId)
            ?: run {
                println("[CHECKLIST-DEBUG] saveResponses: sin plantilla para columnId=$columnId classId=$classId studentId=$studentId")
                return@withContext NotebookInstrumentCellSummary(0, 0, "Pendiente", false)
            }
        val now = if (updatedAtEpochMs > 0) updatedAtEpochMs else Clock.System.now().toEpochMilliseconds()
        val existingCell = db.appDatabaseQueries.selectNotebookCellEntry(classId, studentId, columnId).executeAsOneOrNull()
        val responsesByItem = responses.associateBy { it.itemId }
        val summary = summarize(detail.items, responsesByItem)
        println("[CHECKLIST-DEBUG] saveResponses: columnId=$columnId title=${detail.template.title} itemCount=${detail.items.size} responseCount=${responses.size} requiredCount=${detail.items.count { it.required }} display=${summary.displayValue}")

        db.transaction {
            responses.forEach { response ->
                db.appDatabaseQueries.upsertInstrumentResponse(
                    class_id = classId,
                    student_id = studentId,
                    column_id = columnId,
                    item_id = response.itemId,
                    value_text = response.textValue?.trim()?.takeIf { it.isNotEmpty() },
                    value_bool = response.boolValue?.let { if (it) 1L else 0L },
                    value_number = response.numberValue,
                    updated_at_epoch_ms = now,
                    device_id = deviceId ?: response.trace.deviceId,
                    sync_version = syncVersion,
                )
            }
            db.appDatabaseQueries.upsertNotebookCellEntry(
                class_id = classId,
                student_id = studentId,
                column_id = columnId,
                value_text = existingCell?.value_text,
                value_bool = existingCell?.value_bool,
                value_icon = existingCell?.value_icon,
                value_ordinal = existingCell?.value_ordinal,
                display_value = summary.displayValue,
                observed_at_epoch_ms = existingCell?.observed_at_epoch_ms ?: now,
                competency_criteria_ids_csv = existingCell?.competency_criteria_ids_csv ?: "",
                effective_weight = existingCell?.effective_weight,
                counts_toward_average = existingCell?.counts_toward_average,
                note = existingCell?.note,
                color_hex = existingCell?.color_hex,
                attachment_uris_csv = existingCell?.attachment_uris_csv,
                author_user_id = existingCell?.author_user_id,
                created_at_epoch_ms = existingCell?.created_at_epoch_ms ?: now,
                updated_at_epoch_ms = now,
                associated_group_id = existingCell?.associated_group_id,
                device_id = deviceId,
                sync_version = syncVersion,
            )
        }
        deriveObservationGridScore(detail.items, responsesByItem)?.let { derivedScore ->
            gradesRepository.saveGrade(
                classId = classId,
                studentId = studentId,
                columnId = columnId,
                evaluationId = null,
                value = derivedScore,
                updatedAtEpochMs = now,
                deviceId = deviceId,
                syncVersion = syncVersion,
            )
        }

        // Guardar respuestas estructuradas no pasaba por NotebookRepositorySqlDelight (dueño
        // original del caché de NotebookSheet), así que nunca lo invalidaba: el Cuaderno podía
        // seguir sirviendo una hoja cacheada sin el `display_value`/nota recién guardados hasta
        // la siguiente mutación "normal". Invalidar aquí también para que cualquier instrumento
        // estructurado (checklist, quiz, observación) se refleje de inmediato al guardar.
        sheetCache.invalidate(classId)
        val persistedAfter = db.appDatabaseQueries.selectNotebookCellEntry(classId, studentId, columnId).executeAsOneOrNull()
        println("[CHECKLIST-DEBUG] saveResponses: post-write columnId=$columnId display_value=${persistedAfter?.display_value}")

        NotebookRefreshBus.emitRefresh()
        summary
    }

    /// Traduce las respuestas 1-4 de una rejilla de observación "sesión × indicador"
    /// (items con key `obs_s<sesión>_i<indicador>`, ver LearningSituationAssessmentInstrumentsImportService.swift
    /// en el cliente Apple) en una nota numérica: media de indicadores respondidos por
    /// sesión, y luego media de las sesiones con al menos un indicador respondido.
    /// Devuelve `null` si el instrumento no sigue esta convención (checklists, quizzes,
    /// formularios genéricos) — no afecta a ningún otro tipo de instrumento.
    private fun deriveObservationGridScore(
        items: List<NotebookInstrumentItem>,
        responsesByItem: Map<String, NotebookInstrumentResponse>,
    ): Double? {
        val sessionKeyPattern = Regex("""^obs_s(\d+)_i(\d+)$""")
        val valuesBySession = items
            .mapNotNull { item ->
                val match = sessionKeyPattern.matchEntire(item.key) ?: return@mapNotNull null
                if (item.type != NotebookInstrumentItemType.SCALE_1_4) return@mapNotNull null
                val value = responsesByItem[item.id]?.numberValue ?: return@mapNotNull null
                match.groupValues[1].toInt() to value
            }
            .groupBy({ it.first }, { it.second })
        if (valuesBySession.isEmpty()) return null
        val sessionAverages = valuesBySession.values.map { it.average() }
        return sessionAverages.average()
    }

    private fun summarize(
        items: List<NotebookInstrumentItem>,
        responsesByItem: Map<String, NotebookInstrumentResponse>,
    ): NotebookInstrumentCellSummary {
        val requiredItems = items.filter { it.required }
        val total = requiredItems.size
        val completed = requiredItems.count { item ->
            val response = responsesByItem[item.id] ?: return@count false
            when (item.type) {
                NotebookInstrumentItemType.CHECK -> response.boolValue == true
                NotebookInstrumentItemType.TEXT,
                NotebookInstrumentItemType.CHOICE -> !response.textValue.isNullOrBlank()
                NotebookInstrumentItemType.NUMBER,
                NotebookInstrumentItemType.SCALE_1_4 -> response.numberValue != null
            }
        }
        val complete = total > 0 && completed == total
        val display = when {
            total == 0 -> "Pendiente"
            complete -> "Completo"
            completed == 0 -> "0/$total"
            else -> "$completed/$total"
        }
        return NotebookInstrumentCellSummary(
            completedCount = completed,
            totalCount = total,
            displayValue = display,
            isComplete = complete,
        )
    }

    private fun templateKind(raw: String): NotebookInstrumentTemplateKind =
        runCatching { NotebookInstrumentTemplateKind.valueOf(raw) }.getOrDefault(NotebookInstrumentTemplateKind.FORM)

    private fun itemType(raw: String): NotebookInstrumentItemType =
        runCatching { NotebookInstrumentItemType.valueOf(raw) }.getOrDefault(NotebookInstrumentItemType.TEXT)

    private fun inputKind(raw: String): NotebookCellInputKind =
        runCatching { NotebookCellInputKind.valueOf(raw) }.getOrDefault(NotebookCellInputKind.STRUCTURED_FORM)
}
