package com.migestor.shared.viewmodel

import com.migestor.shared.domain.NotebookColumnDefinition
import kotlinx.coroutines.flow.MutableStateFlow

internal data class CellKey(
    val studentId: Long,
    val columnId: String,
)

internal data class CellDraft(
    val column: NotebookColumnDefinition,
    val value: String,
)

internal class NotebookSaveQueue {
    private val pending = MutableStateFlow<Map<CellKey, CellDraft>>(emptyMap())

    fun enqueue(studentId: Long, column: NotebookColumnDefinition, value: String) {
        pending.value = pending.value + (CellKey(studentId, column.id) to CellDraft(column, value))
    }

    fun drainAll(): List<Pair<CellKey, CellDraft>> {
        val snapshot = pending.value
        pending.value = emptyMap()
        return snapshot.toList()
    }

    fun drain(studentId: Long, columnId: String? = null): List<Pair<CellKey, CellDraft>> {
        val (matched, retained) = pending.value.entries.partition { entry ->
            entry.key.studentId == studentId && (columnId == null || entry.key.columnId == columnId)
        }
        pending.value = retained.associate { it.key to it.value }
        return matched.map { it.key to it.value }
    }
}
