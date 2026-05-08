package com.migestor.shared.usecase

import com.migestor.shared.domain.Evaluation
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnCategoryKind
import com.migestor.shared.domain.NotebookColumnCategory
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookCellInputKind
import com.migestor.shared.domain.NotebookInstrumentKind
import com.migestor.shared.domain.NotebookScaleKind
import com.migestor.shared.domain.NotebookWorkGroup
import com.migestor.shared.domain.NotebookWorkGroupMember
import com.migestor.shared.domain.NotebookRow
import com.migestor.shared.domain.NotebookSheet
import com.migestor.shared.domain.NotebookStudentInsight
import com.migestor.shared.domain.NotebookTab
import com.migestor.shared.domain.Student
import com.migestor.shared.domain.NotebookAverageContribution
import com.migestor.shared.domain.NotebookAverageExclusion
import com.migestor.shared.domain.NotebookAverageExclusionReason
import com.migestor.shared.domain.NotebookAverageExplanation
import com.migestor.shared.domain.NotebookColumnVisibility
import com.migestor.shared.domain.NotebookEmptyCellPolicy
import com.migestor.shared.formula.FormulaEvaluator

class BuildNotebookSheetUseCase(
    private val getNotebookUseCase: GetNotebookUseCase,
    private val formulaEvaluator: FormulaEvaluator = FormulaEvaluator(),
    private val buildNotebookInsightsUseCase: BuildNotebookInsightsUseCase = BuildNotebookInsightsUseCase(),
) {
    suspend fun build(
        classId: Long,
        evaluations: List<Evaluation>,
        students: List<Student>,
        tabs: List<NotebookTab>,
        configuredColumns: List<NotebookColumnDefinition>,
        columnCategories: List<NotebookColumnCategory> = emptyList(),
        workGroups: List<NotebookWorkGroup> = emptyList(),
        workGroupMembers: List<NotebookWorkGroupMember> = emptyList(),
        insights: List<NotebookStudentInsight> = emptyList(),
    ): NotebookSheet {
        val base = getNotebookUseCase(classId, providedStudents = students, providedEvaluations = evaluations)
        val columns = mergeColumns(evaluations, tabs, configuredColumns)
        val rows = applyCalculatedColumns(base.rows, columns, evaluations)
        val resolvedSheet = NotebookSheet(
            classId = classId,
            tabs = tabs,
            columns = columns,
            columnCategories = columnCategories,
            rows = rows,
            workGroups = workGroups,
            workGroupMembers = workGroupMembers,
            insights = insights,
        )
        return NotebookSheet(
            classId = resolvedSheet.classId,
            tabs = resolvedSheet.tabs,
            columns = resolvedSheet.columns,
            columnCategories = resolvedSheet.columnCategories,
            rows = resolvedSheet.rows,
            workGroups = resolvedSheet.workGroups,
            workGroupMembers = resolvedSheet.workGroupMembers,
            insights = if (insights.isEmpty()) buildNotebookInsightsUseCase.build(resolvedSheet) else insights,
        )
    }

    private fun mergeColumns(
        evaluations: List<Evaluation>,
        tabs: List<NotebookTab>,
        configuredColumns: List<NotebookColumnDefinition>,
    ): List<NotebookColumnDefinition> {
        val evaluationIds = evaluations.map { it.id }.toSet()
        val existingByEval = configuredColumns.mapNotNull { col ->
            col.evaluationId?.let { it to col }
        }.toMap()

        val generated = evaluations.map { evaluation ->
            val existing = existingByEval[evaluation.id]
            val isRubric = evaluation.rubricId != null
            
            existing?.copy(
                rubricId = if (isRubric) evaluation.rubricId else existing.rubricId,
                type = if (isRubric) NotebookColumnType.RUBRIC else existing.type,
                categoryKind = existing.categoryKind.takeUnless { it == NotebookColumnCategoryKind.CUSTOM }
                    ?: NotebookColumnCategoryKind.EVALUATION,
                instrumentKind = existing.instrumentKind.takeUnless { it == NotebookInstrumentKind.CUSTOM }
                    ?: if (isRubric) NotebookInstrumentKind.RUBRIC else NotebookInstrumentKind.WRITTEN_TEST,
                inputKind = existing.inputKind.takeUnless { it == NotebookCellInputKind.TEXT }
                    ?: if (isRubric) NotebookCellInputKind.RUBRIC else NotebookCellInputKind.NUMERIC_0_10,
                scaleKind = existing.scaleKind.takeUnless { it == NotebookScaleKind.CUSTOM }
                    ?: NotebookScaleKind.TEN_POINT,
                order = existing.order.takeIf { it >= 0 } ?: generatedOrderForEvaluation(evaluations, evaluation.id),
                widthDp = existing.widthDp.takeIf { it > 0.0 } ?: 132.0
            ) ?: NotebookColumnDefinition(
                id = "eval_${evaluation.id}",
                title = evaluation.name,
                type = if (isRubric) NotebookColumnType.RUBRIC else NotebookColumnType.NUMERIC,
                categoryKind = NotebookColumnCategoryKind.EVALUATION,
                instrumentKind = if (isRubric) NotebookInstrumentKind.RUBRIC else NotebookInstrumentKind.WRITTEN_TEST,
                inputKind = if (isRubric) NotebookCellInputKind.RUBRIC else NotebookCellInputKind.NUMERIC_0_10,
                evaluationId = evaluation.id,
                formula = evaluation.formula,
                weight = evaluation.weight,
                rubricId = evaluation.rubricId,
                scaleKind = NotebookScaleKind.TEN_POINT,
                tabIds = tabs.map { it.id },
                sharedAcrossTabs = true,
                order = generatedOrderForEvaluation(evaluations, evaluation.id),
                widthDp = 132.0,
            )
        }

        // Keep configured columns whose evaluation is temporarily missing from the
        // snapshot (sync race / partial pull) so they don't disappear from the UI.
        val orphanConfigured = configuredColumns.filter { column ->
            val evalId = column.evaluationId
            evalId != null && evalId !in evaluationIds
        }
        val extraConfigured = configuredColumns.filter { it.evaluationId == null }
        return (generated + orphanConfigured + extraConfigured)
            .distinctBy { it.id }
            .sortedWith(compareBy<NotebookColumnDefinition> { it.order }.thenBy { it.id })
    }

    private fun generatedOrderForEvaluation(
        evaluations: List<Evaluation>,
        evaluationId: Long,
    ): Int {
        return evaluations.indexOfFirst { it.id == evaluationId }.takeIf { it >= 0 } ?: 0
    }

    private fun applyCalculatedColumns(
        rows: List<NotebookRow>,
        columns: List<NotebookColumnDefinition>,
        evaluations: List<Evaluation>,
    ): List<NotebookRow> {
        val calculated = columns.filter { it.type == NotebookColumnType.CALCULATED && !it.formula.isNullOrBlank() }
        return rows.map { row ->
            val calculatedValuesByColumnId = mutableMapOf<String, Double>()

            if (calculated.isEmpty()) {
                val explanation = computeAverageExplanation(
                    row = row,
                    columns = columns,
                    calculatedValuesByColumnId = emptyMap(),
                )
                return@map row.copy(
                    weightedAverage = explanation?.average,
                    averageExplanation = explanation,
                    persistedCells = row.persistedCells,
                    persistedGrades = row.persistedGrades
                )
            }

            val varsByCode = evaluations.associate { evaluation ->
                val value = row.cells.firstOrNull { it.evaluationId == evaluation.id }?.value ?: 0.0
                evaluation.code to value
            }
            val varsByColumnId = columns.associate { column ->
                val value = gradeValueFor(row, column) ?: 0.0
                column.id to value
            }
            val vars = varsByCode + varsByColumnId

            calculated.forEach { column ->
                runCatching { formulaEvaluator.evaluate(column.formula!!, vars) }
                    .getOrNull()
                    ?.let { calculatedValuesByColumnId[column.id] = it }
            }
            val explanation = computeAverageExplanation(
                row = row,
                columns = columns,
                calculatedValuesByColumnId = calculatedValuesByColumnId,
            )
            row.copy(
                weightedAverage = explanation?.average,
                averageExplanation = explanation,
                persistedCells = row.persistedCells,
                persistedGrades = row.persistedGrades
            )
        }
    }

    private fun computeAverageExplanation(
        row: NotebookRow,
        columns: List<NotebookColumnDefinition>,
        calculatedValuesByColumnId: Map<String, Double>,
    ): NotebookAverageExplanation? {
        val evaluableColumns = columns.filter { it.visibility != NotebookColumnVisibility.ARCHIVED }
        if (evaluableColumns.isEmpty()) return null

        val included = mutableListOf<NotebookAverageContribution>()
        val excluded = mutableListOf<NotebookAverageExclusion>()

        evaluableColumns.forEach { column ->
            if (!countsTowardAverage(column)) {
                excluded += NotebookAverageExclusion(
                    columnId = column.id,
                    title = column.title,
                    reason = averageExclusionReason(column)
                )
                return@forEach
            }

            val value = gradeValueFor(row, column, calculatedValuesByColumnId)
            if (value != null) {
                included += NotebookAverageContribution(
                    columnId = column.id,
                    title = column.title,
                    value = value,
                    weight = column.weight,
                    weightedValue = value * column.weight
                )
            } else {
                when (column.emptyCellPolicy) {
                    NotebookEmptyCellPolicy.COUNT_AS_ZERO -> {
                        included += NotebookAverageContribution(
                            columnId = column.id,
                            title = column.title,
                            value = 0.0,
                            weight = column.weight,
                            weightedValue = 0.0
                        )
                    }
                    else -> {
                        excluded += NotebookAverageExclusion(
                            columnId = column.id,
                            title = column.title,
                            reason = NotebookAverageExclusionReason.EMPTY
                        )
                    }
                }
            }
        }

        val totalWeight = included.sumOf { it.weight }
        val average = if (totalWeight > 0.0) {
            included.sumOf { it.weightedValue } / totalWeight
        } else {
            null
        }

        return NotebookAverageExplanation(
            studentId = row.student.id,
            average = average,
            included = included,
            excluded = excluded,
            totalIncludedWeight = totalWeight,
            policy = NotebookEmptyCellPolicy.EXCLUDE_FROM_AVERAGE // Should ideally come from class config
        )
    }

    private fun gradeValueFor(
        row: NotebookRow,
        column: NotebookColumnDefinition,
        calculatedValuesByColumnId: Map<String, Double> = emptyMap(),
    ): Double? {
        calculatedValuesByColumnId[column.id]?.let { return it }
        val evaluationValue = column.evaluationId?.let { evaluationId ->
            row.cells.firstOrNull { it.evaluationId == evaluationId }?.value
        }
        if (evaluationValue != null) return evaluationValue
        val persistedGrade = row.persistedGrades.firstOrNull { it.columnId == column.id }?.value
        if (persistedGrade != null) return persistedGrade
        return row.persistedCells.firstOrNull { it.columnId == column.id }?.boolValue?.let { if (it) 10.0 else 0.0 }
    }

    private fun countsTowardAverage(column: NotebookColumnDefinition): Boolean {
        if (!column.countsTowardAverage || column.weight <= 0.0) return false
        if (column.visibility == NotebookColumnVisibility.ARCHIVED) return false
        if (column.instrumentKind == NotebookInstrumentKind.PHYSICAL_TEST && column.scaleKind in rawPhysicalScaleKinds) {
            return false
        }
        return when (column.type) {
            NotebookColumnType.NUMERIC,
            NotebookColumnType.RUBRIC,
            NotebookColumnType.CALCULATED,
            NotebookColumnType.CHECK -> true
            else -> false
        }
    }

    private fun averageExclusionReason(column: NotebookColumnDefinition): NotebookAverageExclusionReason {
        if (column.visibility == NotebookColumnVisibility.ARCHIVED) return NotebookAverageExclusionReason.LOCKED_OR_ARCHIVED
        if (column.instrumentKind == NotebookInstrumentKind.PHYSICAL_TEST && column.scaleKind in rawPhysicalScaleKinds) {
            return NotebookAverageExclusionReason.RAW_VALUE_ONLY
        }
        if (column.weight <= 0.0) return NotebookAverageExclusionReason.RAW_VALUE_ONLY
        return when (column.type) {
            NotebookColumnType.NUMERIC,
            NotebookColumnType.RUBRIC,
            NotebookColumnType.CALCULATED,
            NotebookColumnType.CHECK -> NotebookAverageExclusionReason.COLUMN_DOES_NOT_COUNT
            else -> NotebookAverageExclusionReason.NON_NUMERIC
        }
    }

    private companion object {
        val rawPhysicalScaleKinds = setOf(
            NotebookScaleKind.TIME,
            NotebookScaleKind.DISTANCE,
            NotebookScaleKind.REPETITIONS,
        )
    }
}
