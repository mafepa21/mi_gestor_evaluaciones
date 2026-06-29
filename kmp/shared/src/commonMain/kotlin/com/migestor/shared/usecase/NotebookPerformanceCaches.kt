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
    private val lock = Lock()
    private val entries = LinkedHashMap<NotebookSheetCacheKey, NotebookSheet>()

    fun get(key: NotebookSheetCacheKey): NotebookSheet? {
        return lock.withLock {
            entries.remove(key)?.also { entries[key] = it }
        }
    }

    fun put(key: NotebookSheetCacheKey, sheet: NotebookSheet) {
        lock.withLock {
            entries[key] = sheet
            while (entries.size > maxEntries) {
                entries.remove(entries.keys.first())
            }
        }
    }

    fun invalidate(classId: Long) {
        lock.withLock {
            val iterator = entries.iterator()
            while (iterator.hasNext()) {
                if (iterator.next().key.classId == classId) {
                    iterator.remove()
                }
            }
        }
    }

    fun clear() {
        lock.withLock {
            entries.clear()
        }
    }
}

data class AverageCacheKey(
    val studentId: Long,
    val includedColumnIdsHash: Int,
    val valuesRevision: Long,
)

class AverageCache(
    private val maxEntries: Int = 512,
) {
    private val lock = Lock()
    private val entries = LinkedHashMap<AverageCacheKey, NotebookAverageExplanation?>()

    fun getOrPut(key: AverageCacheKey, compute: () -> NotebookAverageExplanation?): NotebookAverageExplanation? {
        lock.withLock {
            entries.remove(key)?.also {
                entries[key] = it
                NotebookPerformanceDebug.event("averageCache hit")
                return it
            }
        }
        NotebookPerformanceDebug.event("averageCache miss")
        val computed = compute()
        return lock.withLock {
            entries[key] = computed
            while (entries.size > maxEntries) {
                entries.remove(entries.keys.first())
            }
            computed
        }
    }

    fun key(
        row: NotebookRow,
        columns: List<NotebookColumnDefinition>,
        calculatedValuesByColumnId: Map<String, Double>,
        numericDrafts: Map<Pair<Long, String>, String> = emptyMap(),
    ): AverageCacheKey {
        val averageColumns = columns.filter { it.visibility == NotebookColumnVisibility.VISIBLE && !it.isHidden }
        val includedColumnIdsHash = stableHashForAverage(
            averageColumns.map { column ->
                "${column.id}:${column.title}:${column.weight}:${column.countsTowardAverage}:${column.visibility.name}:${column.isHidden}:${column.emptyCellPolicy.name}:${column.type.name}:${column.inputKind.name}:${column.scaleKind.name}:${column.formula}:${column.rubricId}"
            }
        )
        val includedColumns = columns
            .filter { it.visibility == NotebookColumnVisibility.VISIBLE && !it.isHidden && it.countsTowardAverage() }
            .joinToString("|") { column ->
                val value = row.gradeValueFor(column, calculatedValuesByColumnId, numericDrafts)
                val persistedCell = row.persistedCells.firstOrNull { it.columnId == column.id }
                val persistedGrade = row.persistedGrades.firstOrNull { it.columnId == column.id }
                    ?: column.evaluationId?.let { evalId ->
                        row.persistedGrades.firstOrNull { it.evaluationId == evalId }
                    }
                "${column.id}:${column.evaluationId}:${value ?: "empty"}:${persistedCell?.displayValue}:${persistedCell?.boolValue}:${persistedCell?.textValue}:${persistedCell?.ordinalValue}:${persistedCell?.trace?.updatedAt}:${persistedGrade?.value}:${persistedGrade?.rubricSelections}:${persistedGrade?.trace?.updatedAt}"
            }
        return AverageCacheKey(
            studentId = row.student.id,
            includedColumnIdsHash = includedColumnIdsHash,
            valuesRevision = stableLongHashForAverage(listOf(includedColumns)),
        )
    }

    fun explanationsByStudent(
        rows: List<NotebookRow>,
        columns: List<NotebookColumnDefinition>,
        calculatedValuesByStudentId: Map<Long, Map<String, Double>> = emptyMap(),
        numericDrafts: Map<Pair<Long, String>, String> = emptyMap(),
        compute: (NotebookRow, Map<String, Double>) -> NotebookAverageExplanation?,
    ): Map<Long, NotebookAverageExplanation> {
        return rows.mapNotNull { row ->
            val calculatedValues = calculatedValuesByStudentId[row.student.id].orEmpty()
            val explanation = getOrPut(
                key(
                    row = row,
                    columns = columns,
                    calculatedValuesByColumnId = calculatedValues,
                    numericDrafts = numericDrafts,
                )
            ) {
                compute(row, calculatedValues)
            }
            explanation?.let { row.student.id to it }
        }.toMap()
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

private fun stableHashForAverage(parts: List<String>): Int = stableHash(parts)

private fun stableLongHashForAverage(parts: List<String>): Long {
    var result = 1125899906842597L
    parts.sorted().forEach { part ->
        result = 31L * result + part.hashCode().toLong()
    }
    return result
}
