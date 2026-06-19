package com.migestor.shared.usecase

import com.migestor.shared.domain.Grade
import com.migestor.shared.domain.NotebookAverageExplanation
import com.migestor.shared.domain.NotebookColumnCategory
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnVisibility
import com.migestor.shared.domain.NotebookRow
import com.migestor.shared.domain.NotebookSheet
import com.migestor.shared.domain.NotebookTab
import com.migestor.shared.domain.NotebookWorkGroup
import com.migestor.shared.domain.NotebookWorkGroupMember
import com.migestor.shared.domain.PersistedNotebookCell
import com.migestor.shared.domain.Student
import com.migestor.shared.domain.gradeValueFor
import kotlin.time.TimeSource

object NotebookPerformanceDebug {
    var enabled: Boolean = false

    inline fun <T> measure(label: String, block: () -> T): T {
        if (!enabled) return block()
        val mark = TimeSource.Monotonic.markNow()
        return block().also {
            println("NotebookPerf $label ${mark.elapsedNow().inWholeMilliseconds}ms")
        }
    }

    fun event(label: String, details: String = "") {
        if (enabled) {
            println("NotebookPerf $label${details.takeIf { it.isNotBlank() }?.let { " $it" } ?: ""}")
        }
    }
}

data class NotebookSheetCacheKey(
    val classId: Long,
    val configVersion: Int,
    val studentsVersion: Int,
    val columnsVersion: Int,
    val cellsVersion: Int,
    val rubricsVersion: Int,
)

class NotebookSheetMemoryCache(
    private val maxEntries: Int = 4,
) {
    private val entries = LinkedHashMap<NotebookSheetCacheKey, NotebookSheet>()

    fun get(key: NotebookSheetCacheKey): NotebookSheet? {
        return entries.remove(key)?.also { entries[key] = it }
    }

    fun put(key: NotebookSheetCacheKey, sheet: NotebookSheet) {
        entries[key] = sheet
        while (entries.size > maxEntries) {
            entries.remove(entries.keys.first())
        }
    }

    fun invalidate(classId: Long) {
        val toRemove = entries.keys.filter { it.classId == classId }
        toRemove.forEach { entries.remove(it) }
    }

    fun clear() {
        entries.clear()
    }
}

class AverageCache(
    private val maxEntries: Int = 512,
) {
    private val entries = LinkedHashMap<String, NotebookAverageExplanation?>()

    fun getOrPut(key: String, compute: () -> NotebookAverageExplanation?): NotebookAverageExplanation? {
        entries.remove(key)?.also {
            entries[key] = it
            NotebookPerformanceDebug.event("averageCache hit")
            return it
        }
        NotebookPerformanceDebug.event("averageCache miss")
        return compute().also { value ->
            entries[key] = value
            while (entries.size > maxEntries) {
                entries.remove(entries.keys.first())
            }
        }
    }

    fun key(
        row: NotebookRow,
        columns: List<NotebookColumnDefinition>,
        calculatedValuesByColumnId: Map<String, Double>,
    ): String {
        val includedColumns = columns
            .filter { it.visibility == NotebookColumnVisibility.VISIBLE && !it.isHidden && it.countsTowardAverage() }
            .joinToString("|") { column ->
                val value = row.gradeValueFor(column, calculatedValuesByColumnId)
                "${column.id}:${column.weight}:${column.emptyCellPolicy.name}:${column.type.name}:${column.inputKind.name}:${column.scaleKind.name}:${value ?: "empty"}"
            }
        return "${row.student.id}|$includedColumns"
    }
}

fun notebookSheetCacheKey(
    classId: Long,
    students: List<Student>,
    tabs: List<NotebookTab>,
    columns: List<NotebookColumnDefinition>,
    categories: List<NotebookColumnCategory>,
    groups: List<NotebookWorkGroup>,
    members: List<NotebookWorkGroupMember>,
    grades: List<Grade>,
    cells: List<PersistedNotebookCell>,
): NotebookSheetCacheKey {
    val configVersion = stableHash(
        tabs.map { "${it.id}:${it.parentTabId}:${it.order}:${it.fixedColumnWidth}" } +
            categories.map { "${it.id}:${it.tabId}:${it.order}:${it.isCollapsed}:${it.trace.updatedAt}" } +
            groups.map { "${it.id}:${it.tabId}:${it.order}:${it.learningSituationId}:${it.trace.updatedAt}" } +
            members.map { "${it.tabId}:${it.groupId}:${it.studentId}:${it.trace.updatedAt}" }
    )
    return NotebookSheetCacheKey(
        classId = classId,
        configVersion = configVersion,
        studentsVersion = stableHash(students.map { "${it.id}:${it.firstName}:${it.lastName}:${it.trace.updatedAt}" }),
        columnsVersion = stableHash(columns.map { "${it.id}:${it.order}:${it.weight}:${it.countsTowardAverage}:${it.visibility}:${it.updatedVersionString()}" }),
        cellsVersion = stableHash(cells.map { "${it.studentId}:${it.columnId}:${it.displayValue}:${it.boolValue}:${it.textValue}:${it.trace.updatedAt}" }),
        rubricsVersion = stableHash(grades.map { "${it.studentId}:${it.columnId}:${it.evaluationId}:${it.value}:${it.rubricSelections}:${it.trace.updatedAt}" }),
    )
}

private fun NotebookColumnDefinition.updatedVersionString(): String =
    "${title}:${type.name}:${categoryId}:${categoryKind.name}:${formula}:${rubricId}:${tabIds.joinToString(",")}:${sharedAcrossTabs}:${isPinned}:${isHidden}:${emptyCellPolicy.name}"

private fun stableHash(parts: List<String>): Int {
    var result = 1
    parts.sorted().forEach { part ->
        result = 31 * result + part.hashCode()
    }
    return result
}
