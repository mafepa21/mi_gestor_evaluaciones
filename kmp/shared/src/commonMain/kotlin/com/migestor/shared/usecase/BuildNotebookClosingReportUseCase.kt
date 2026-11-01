package com.migestor.shared.usecase

import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookColumnVisibility
import com.migestor.shared.domain.NotebookEmptyCellPolicy
import com.migestor.shared.domain.NotebookRow
import com.migestor.shared.domain.PersistedNotebookCell

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
    /**
     * Avisos distintos: huecos únicos (alumno + columna) más sin Media, notas que no se
     * entienden y columnas ocultas. «Criterios sin nota» es otra vista de los mismos huecos
     * y no suma.
     */
    val totalCount: Int
        get() = issues.filter { it.kind != ClosingIssueKind.CRITERION_WITHOUT_GRADE }.sumOf { it.count }
    val isAllClear: Boolean get() = hasCountingColumns && issues.isEmpty()

    fun issuesOf(kind: ClosingIssueKind): List<ClosingIssue> = issues.filter { it.kind == kind }
    fun countOf(kind: ClosingIssueKind): Int = issuesOf(kind).sumOf { it.count }
}

/**
 * Lógica pura de «Revisar cierre»: solo lee columnas y filas ya cargadas.
 * No cambia ninguna nota ni la Media.
 *
 * Una celda de una columna que cuenta está «rellena» si tiene un valor real guardado
 * (nota persistida, celda persistida con contenido) o un valor calculado que entra en la
 * Media. Con la política «vacío cuenta como 0» la celda vacía entra en la Media como 0,
 * pero sigue siendo un hueco.
 */
class BuildNotebookClosingReportUseCase {
    /** Datos de una fila indexados por columna, para no recorrer listas dentro de los bucles. */
    private class RowIndex(row: NotebookRow) {
        val included: Map<String, Double> =
            row.averageExplanation?.included?.associate { it.columnId to it.value }.orEmpty()
        val cellsByColumn: Map<String, PersistedNotebookCell> =
            row.persistedCells.groupBy { it.columnId }.mapValues { it.value.first() }
        val gradeColumns: Set<String> =
            row.persistedGrades.filter { it.value != null }.map { it.columnId }.toSet()
        val gradeEvaluations: Set<Long> =
            row.persistedGrades.filter { it.value != null }.mapNotNull { it.evaluationId }.toSet()
        val cellEvaluations: Set<Long> =
            row.cells.filter { it.value != null }.map { it.evaluationId }.toSet()
    }

    fun build(
        columns: List<NotebookColumnDefinition>,
        rows: List<NotebookRow>,
        criterionCodes: Map<Long, String> = emptyMap(),
    ): NotebookClosingReport {
        val countingColumns = columns.filter { it.countsTowardAverage() }
        if (countingColumns.isEmpty()) {
            return NotebookClosingReport(studentCount = rows.size, countingColumnCount = 0, issues = emptyList())
        }
        val issues = mutableListOf<ClosingIssue>()
        val indexes = rows.associate { it.student.id to RowIndex(it) }
        val withoutAverage = rows.filter { row ->
            row.weightedAverage == null && row.averageExplanation?.included.isNullOrEmpty()
        }.map { it.student.id }.toSet()

        // 1 y 3. Notas vacías y notas que no se entienden, por columna.
        val emptyByColumn = linkedMapOf<String, MutableList<ClosingStudent>>()
        val notUnderstood = mutableListOf<ClosingIssue>()
        rows.forEach { row ->
            val index = indexes.getValue(row.student.id)
            val student = ClosingStudent(row.student.id, row.student.fullName)
            countingColumns.forEach { column ->
                if (index.isFilled(column)) return@forEach
                val text = index.unreadableText(column)
                if (text != null) {
                    notUnderstood += ClosingIssue(
                        kind = ClosingIssueKind.NOT_UNDERSTOOD,
                        columnId = column.id,
                        title = column.title,
                        students = listOf(student),
                        text = text,
                    )
                } else if (row.student.id !in withoutAverage) {
                    // Quien no tiene Media sale solo en «Sin Media», no en cada columna vacía.
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
        rows.filter { it.student.id in withoutAverage }.forEach { row ->
            issues += ClosingIssue(
                kind = ClosingIssueKind.NO_AVERAGE,
                columnId = null,
                title = row.student.fullName,
                students = listOf(ClosingStudent(row.student.id, row.student.fullName)),
            )
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

        // 5. Criterios sin nota (vista por criterio; no suma al total).
        val columnsByCriterion = linkedMapOf<Long, MutableList<NotebookColumnDefinition>>()
        countingColumns.forEach { column ->
            column.competencyCriteriaIds.distinct().forEach { criterionId ->
                columnsByCriterion.getOrPut(criterionId) { mutableListOf() } += column
            }
        }
        columnsByCriterion.forEach { (criterionId, criterionColumns) ->
            val code = criterionCodes[criterionId]?.takeIf { it.isNotBlank() }
            rows.forEach { row ->
                if (row.student.id in withoutAverage) return@forEach
                val index = indexes.getValue(row.student.id)
                if (criterionColumns.none { index.isFilled(it) || index.hasAnyContent(it) }) {
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

    /** Hay un valor real guardado en la celda (nota, celda con contenido o nota de evaluación). */
    private fun RowIndex.hasStoredValue(column: NotebookColumnDefinition): Boolean =
        column.id in gradeColumns ||
            (column.evaluationId?.let { it in gradeEvaluations || it in cellEvaluations } == true) ||
            hasAnyContent(column)

    /** La celda persistida tiene texto, ordinal, icono, casilla o valor mostrado. */
    private fun RowIndex.hasAnyContent(column: NotebookColumnDefinition): Boolean {
        val cell = cellsByColumn[column.id] ?: return false
        return !cell.textValue.isNullOrBlank() ||
            !cell.displayValue.isNullOrBlank() ||
            !cell.ordinalValue.isNullOrBlank() ||
            !cell.iconValue.isNullOrBlank() ||
            cell.boolValue != null
    }

    /**
     * La celda tiene nota: valor guardado, o valor que entra en la Media (p. ej. calculado).
     * Con «vacío cuenta como 0» el 0 de relleno no cuenta como nota.
     */
    private fun RowIndex.isFilled(column: NotebookColumnDefinition): Boolean {
        if (hasStoredValue(column)) {
            // Un texto no numérico en una columna numérica no es una nota.
            return unreadableText(column) == null
        }
        val value = included[column.id] ?: return false
        if (column.emptyCellPolicy != NotebookEmptyCellPolicy.COUNT_AS_ZERO) return true
        return column.type == NotebookColumnType.CALCULATED && value != 0.0
    }

    /** Texto escrito en una columna numérica que no se lee como número, o null. */
    private fun RowIndex.unreadableText(column: NotebookColumnDefinition): String? {
        if (column.type != NotebookColumnType.NUMERIC) return null
        if (column.id in gradeColumns) return null
        if (column.evaluationId?.let { it in gradeEvaluations || it in cellEvaluations } == true) return null
        val text = cellsByColumn[column.id]?.textValue?.trim()
        if (text.isNullOrEmpty()) return null
        return if (text.replace(",", ".").toDoubleOrNull() == null) text else null
    }
}
