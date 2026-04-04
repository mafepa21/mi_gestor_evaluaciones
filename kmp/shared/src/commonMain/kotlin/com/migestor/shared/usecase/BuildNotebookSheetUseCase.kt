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
import com.migestor.shared.domain.NotebookTab
import com.migestor.shared.domain.Student
import com.migestor.shared.formula.FormulaEvaluator

class BuildNotebookSheetUseCase(
    private val getNotebookUseCase: GetNotebookUseCase,
    private val formulaEvaluator: FormulaEvaluator = FormulaEvaluator(),
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
    ): NotebookSheet {
        val base = getNotebookUseCase(classId, providedStudents = students, providedEvaluations = evaluations)
        val columns = mergeColumns(evaluations, tabs, configuredColumns)
        val rows = applyCalculatedColumns(base.rows, columns, evaluations)
        return NotebookSheet(
            classId = classId,
            tabs = tabs,
            columns = columns,
            columnCategories = columnCategories,
            rows = rows,
            workGroups = workGroups,
            workGroupMembers = workGroupMembers,
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
        val evaluableColumnsByEvalId = columns
            .filter { it.countsTowardAverage }
            .associateBy { it.evaluationId }

        return rows.map { row ->
            val baseAverage = runCatching {
                val relevantEvaluations = evaluations.filter { evaluation ->
                    evaluableColumnsByEvalId[evaluation.id]?.countsTowardAverage != false
                }
                if (relevantEvaluations.isEmpty()) return@runCatching row.weightedAverage

                val weightedSum = relevantEvaluations.sumOf { evaluation ->
                    val grade = row.cells.firstOrNull { it.evaluationId == evaluation.id }?.value ?: 0.0
                    grade * evaluation.weight
                }
                val totalWeight = relevantEvaluations.sumOf { it.weight }.takeIf { it > 0.0 } ?: return@runCatching row.weightedAverage
                weightedSum / totalWeight
            }.getOrNull() ?: row.weightedAverage
            if (calculated.isEmpty()) {
                return@map row.copy(
                    weightedAverage = baseAverage,
                    persistedCells = row.persistedCells,
                    persistedGrades = row.persistedGrades
                )
            }

            val varsByCode = evaluations.associate { evaluation ->
                val value = row.cells.firstOrNull { it.evaluationId == evaluation.id }?.value ?: 0.0
                evaluation.code to value
            }
            val varsByColumnId = columns.associate { column ->
                val value = column.evaluationId?.let { evalId ->
                    row.cells.firstOrNull { it.evaluationId == evalId }?.value ?: 0.0
                } ?: 0.0
                column.id to value
            }
            val vars = varsByCode + varsByColumnId

            val calculatedValues = calculated.mapNotNull { column ->
                runCatching { formulaEvaluator.evaluate(column.formula!!, vars) }
                    .getOrNull()
            }
            val calculatedAverage = calculatedValues.takeIf { it.isNotEmpty() }?.average()
            row.copy(
                weightedAverage = calculatedAverage ?: baseAverage,
                persistedCells = row.persistedCells,
                persistedGrades = row.persistedGrades
            )
        }
    }
}
