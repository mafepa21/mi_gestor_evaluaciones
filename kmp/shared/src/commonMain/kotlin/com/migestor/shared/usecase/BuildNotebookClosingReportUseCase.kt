package com.migestor.shared.usecase

import com.migestor.shared.domain.NotebookAverageExclusionReason
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookColumnVisibility
import com.migestor.shared.domain.NotebookRow
import com.migestor.shared.domain.computeAverageExplanation
import com.migestor.shared.domain.gradeValueFor

/** Tipos de aviso de «Revisar cierre», en el orden en que se muestran. */
enum class ClosingIssueKind {
    /** Nota vacía en una columna que cuenta para la Media (un aviso por columna). */
    EMPTY_GRADE,

    /** Alumno sin Media aunque el grupo tiene columnas que cuentan. */
    NO_AVERAGE,

    /** Texto escrito en una columna numérica que no se lee como número. */
    NOT_UNDERSTOOD,

    /** Columna oculta que sigue contando para la Media. */
    HIDDEN_COLUMN,

    /** Criterio de evaluación sin ninguna nota para un alumno. */
    CRITERION_WITHOUT_GRADE,
}

data class ClosingStudent(
    val id: Long,
    val name: String,
)

data class ClosingIssue(
    val kind: ClosingIssueKind,
    /** Columna a la que lleva el aviso (en criterios, la primera que lo evalúa). */
    val columnId: String?,
    /** Nombre de la columna, o código del criterio, o nombre del alumno según el tipo. */
    val title: String,
    val students: List<ClosingStudent> = emptyList(),
    val criterionId: Long? = null,
    /** Código del criterio si se conoce (p. ej. «CE 2.1»). */
    val criterionCode: String? = null,
    /** Texto escrito por el docente (solo NOT_UNDERSTOOD). */
    val text: String? = null,
    /** Peso literal en % de la columna (solo HIDDEN_COLUMN). */
    val weight: Double? = null,
    /** Número de instrumentos que evalúan el criterio (solo CRITERION_WITHOUT_GRADE). */
    val instrumentCount: Int = 0,
) {
    /** Cuántos avisos aporta: una nota vacía por alumno; el resto, uno. */
    val count: Int
        get() = if (kind == ClosingIssueKind.EMPTY_GRADE) students.size else 1
}

data class NotebookClosingReport(
    val studentCount: Int,
    /** Columnas que cuentan para la Media (visibles u ocultas). */
    val countingColumnCount: Int,
    val issues: List<ClosingIssue>,
) {
    val hasCountingColumns: Boolean get() = countingColumnCount > 0
    val totalCount: Int get() = issues.sumOf { it.count }
    val isAllClear: Boolean get() = hasCountingColumns && issues.isEmpty()

    fun issuesOf(kind: ClosingIssueKind): List<ClosingIssue> = issues.filter { it.kind == kind }
    fun countOf(kind: ClosingIssueKind): Int = issuesOf(kind).sumOf { it.count }
}

/**
 * Lógica pura de «Revisar cierre»: solo lee columnas y filas ya cargadas.
 * No cambia ninguna nota ni la Media.
 */
class BuildNotebookClosingReportUseCase {
    fun build(
        columns: List<NotebookColumnDefinition>,
        rows: List<NotebookRow>,
        criterionCodes: Map<Long, String> = emptyMap(),
    ): NotebookClosingReport {
        val countingColumns = columns.filter { it.countsTowardAverage() }
        if (countingColumns.isEmpty()) {
            return NotebookClosingReport(studentCount = rows.size, countingColumnCount = 0, issues = emptyList())
        }
        val countingById = countingColumns.associateBy { it.id }
        val issues = mutableListOf<ClosingIssue>()

        // 1 y 3. Notas vacías y notas que no se entienden, por columna.
        val emptyByColumn = linkedMapOf<String, MutableList<ClosingStudent>>()
        val notUnderstood = mutableListOf<ClosingIssue>()
        rows.forEach { row ->
            val explanation = row.averageExplanation ?: row.computeAverageExplanation(columns)
            val student = ClosingStudent(row.student.id, row.student.fullName)
            explanation?.excluded
                ?.filter { it.reason == NotebookAverageExclusionReason.EMPTY }
                ?.forEach { pending ->
                    val column = countingById[pending.columnId] ?: return@forEach
                    val text = row.unreadableTextFor(column)
                    if (text != null) {
                        notUnderstood += ClosingIssue(
                            kind = ClosingIssueKind.NOT_UNDERSTOOD,
                            columnId = column.id,
                            title = column.title,
                            students = listOf(student),
                            text = text,
                        )
                    } else {
                        emptyByColumn.getOrPut(column.id) { mutableListOf() } += student
                    }
                }
        }
        countingColumns.forEach { column ->
            val students = emptyByColumn[column.id] ?: return@forEach
            issues += ClosingIssue(
                kind = ClosingIssueKind.EMPTY_GRADE,
                columnId = column.id,
                title = column.title,
                students = students,
            )
        }

        // 2. Alumnado sin Media.
        rows.forEach { row ->
            val hasIncluded = row.averageExplanation?.included?.isNotEmpty() == true
            if (row.weightedAverage == null && !hasIncluded) {
                issues += ClosingIssue(
                    kind = ClosingIssueKind.NO_AVERAGE,
                    columnId = null,
                    title = row.student.fullName,
                    students = listOf(ClosingStudent(row.student.id, row.student.fullName)),
                )
            }
        }

        issues += notUnderstood

        // 4. Columnas ocultas que cuentan.
        countingColumns
            .filter { it.isHidden || it.visibility == NotebookColumnVisibility.HIDDEN }
            .forEach { column ->
                issues += ClosingIssue(
                    kind = ClosingIssueKind.HIDDEN_COLUMN,
                    columnId = column.id,
                    title = column.title,
                    weight = column.weight,
                )
            }

        // 5. Criterios sin nota.
        val columnsByCriterion = linkedMapOf<Long, MutableList<NotebookColumnDefinition>>()
        countingColumns.forEach { column ->
            column.competencyCriteriaIds.distinct().forEach { criterionId ->
                columnsByCriterion.getOrPut(criterionId) { mutableListOf() } += column
            }
        }
        columnsByCriterion.forEach { (criterionId, criterionColumns) ->
            val code = criterionCodes[criterionId]?.takeIf { it.isNotBlank() }
            rows.forEach { row ->
                if (criterionColumns.none { row.hasAnyGradeIn(it) }) {
                    issues += ClosingIssue(
                        kind = ClosingIssueKind.CRITERION_WITHOUT_GRADE,
                        columnId = criterionColumns.first().id,
                        title = code ?: "Criterio $criterionId",
                        students = listOf(ClosingStudent(row.student.id, row.student.fullName)),
                        criterionId = criterionId,
                        criterionCode = code,
                        instrumentCount = criterionColumns.size,
                    )
                }
            }
        }

        val order = ClosingIssueKind.entries.withIndex().associate { it.value to it.index }
        return NotebookClosingReport(
            studentCount = rows.size,
            countingColumnCount = countingColumns.size,
            issues = issues.sortedBy { order.getValue(it.kind) },
        )
    }

    /** Texto escrito en una columna numérica que no se lee como número, o null. */
    private fun NotebookRow.unreadableTextFor(column: NotebookColumnDefinition): String? {
        if (column.type != NotebookColumnType.NUMERIC) return null
        val text = persistedCells.firstOrNull { it.columnId == column.id }?.textValue?.trim()
        if (text.isNullOrEmpty()) return null
        return if (text.replace(",", ".").toDoubleOrNull() == null) text else null
    }

    private fun NotebookRow.hasAnyGradeIn(column: NotebookColumnDefinition): Boolean {
        if (gradeValueFor(column) != null) return true
        val cell = persistedCells.firstOrNull { it.columnId == column.id } ?: return false
        return !cell.textValue.isNullOrBlank() ||
            !cell.displayValue.isNullOrBlank() ||
            !cell.ordinalValue.isNullOrBlank() ||
            !cell.iconValue.isNullOrBlank() ||
            cell.boolValue != null
    }
}
