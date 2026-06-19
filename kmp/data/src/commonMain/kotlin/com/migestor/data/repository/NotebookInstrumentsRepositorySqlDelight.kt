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
import com.migestor.shared.repository.NotebookInstrumentsRepository
import com.migestor.shared.util.NotebookRefreshBus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

class NotebookInstrumentsRepositorySqlDelight(
    private val db: AppDatabase,
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
            ?: return@withContext NotebookInstrumentCellSummary(0, 0, "Pendiente", false)
        val now = if (updatedAtEpochMs > 0) updatedAtEpochMs else Clock.System.now().toEpochMilliseconds()
        val existingCell = db.appDatabaseQueries.selectNotebookCellEntry(classId, studentId, columnId).executeAsOneOrNull()
        val responsesByItem = responses.associateBy { it.itemId }
        val summary = summarize(detail.items, responsesByItem)

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
        NotebookRefreshBus.emitRefresh()
        summary
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
