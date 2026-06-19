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
import com.migestor.shared.domain.Grade
import com.migestor.shared.domain.PersistedNotebookCell
import com.migestor.shared.domain.gradeValueFor
import com.migestor.shared.domain.computeAverageExplanation
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
        persistedGrades: List<Grade>? = null,
        persistedCells: List<PersistedNotebookCell>? = null,
    ): NotebookSheet {
        return NotebookPerformanceDebug.measure("buildSheet classId=$classId") {
            val base = getNotebookUseCase(
                classId,
                providedStudents = students,
                providedEvaluations = evaluations,
                providedGrades = persistedGrades,
                providedCells = persistedCells,
            )
            val columns = NotebookPerformanceDebug.measure("mergeColumns") {
                mergeColumns(evaluations, tabs, configuredColumns)
            }
            val rows = NotebookPerformanceDebug.measure("recalculateAverages rows=${base.rows.size}") {
                applyCalculatedColumns(
                    rows = base.rows,
                    columns = columns,
                    evaluations = evaluations,
                    averageCache = AverageCache(),
                )
            }
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
            NotebookSheet(
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
            val rubricId = evaluation.rubricId?.takeIf { it > 0L }
            val isRubric = rubricId != null
            val resolvedType = if (isRubric) NotebookColumnType.RUBRIC else existing?.type ?: NotebookColumnType.NUMERIC
            
            existing?.copy(
                rubricId = rubricId,
                type = resolvedType,
                categoryKind = existing.categoryKind.takeUnless { it == NotebookColumnCategoryKind.CUSTOM }
                    ?: NotebookColumnCategoryKind.EVALUATION,
                instrumentKind = existing.instrumentKind.takeUnless { it == NotebookInstrumentKind.CUSTOM }
                    ?: defaultInstrumentKindFor(resolvedType),
                inputKind = existing.inputKind.takeUnless { it == NotebookCellInputKind.TEXT && resolvedType != NotebookColumnType.TEXT }
                    ?: defaultInputKindFor(resolvedType),
                scaleKind = existing.scaleKind.takeUnless { it == NotebookScaleKind.CUSTOM }
                    ?: defaultScaleKindFor(resolvedType),
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
                rubricId = rubricId,
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

    private fun defaultInstrumentKindFor(type: NotebookColumnType): NotebookInstrumentKind {
        return when (type) {
            NotebookColumnType.RUBRIC -> NotebookInstrumentKind.RUBRIC
            NotebookColumnType.CHECK -> NotebookInstrumentKind.CHECKLIST
            NotebookColumnType.ORDINAL -> NotebookInstrumentKind.OBSERVATION_SCALE
            NotebookColumnType.TEXT -> NotebookInstrumentKind.SYSTEMATIC_OBSERVATION
            else -> NotebookInstrumentKind.WRITTEN_TEST
        }
    }

    private fun defaultInputKindFor(type: NotebookColumnType): NotebookCellInputKind {
        return when (type) {
            NotebookColumnType.RUBRIC -> NotebookCellInputKind.RUBRIC
            NotebookColumnType.CHECK -> NotebookCellInputKind.CHECK
            NotebookColumnType.ORDINAL -> NotebookCellInputKind.NUMERIC_1_4
            NotebookColumnType.TEXT -> NotebookCellInputKind.TEXT
            else -> NotebookCellInputKind.NUMERIC_0_10
        }
    }

    private fun defaultScaleKindFor(type: NotebookColumnType): NotebookScaleKind {
        return when (type) {
            NotebookColumnType.RUBRIC,
            NotebookColumnType.NUMERIC,
            NotebookColumnType.CALCULATED -> NotebookScaleKind.TEN_POINT
            NotebookColumnType.ORDINAL -> NotebookScaleKind.FOUR_LEVEL
            else -> NotebookScaleKind.CUSTOM
        }
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
        averageCache: AverageCache,
    ): List<NotebookRow> {
        val calculated = columns.filter { it.type == NotebookColumnType.CALCULATED && !it.formula.isNullOrBlank() }
        val calculatedValuesByStudentId = mutableMapOf<Long, Map<String, Double>>()

        if (calculated.isNotEmpty()) {
            rows.forEach { row ->
                val calculatedValuesByColumnId = mutableMapOf<String, Double>()

                // Do not default missing values to 0.0! Only put in variables map if value is not null.
                val varsByCode = evaluations.mapNotNull { evaluation ->
                    val value = row.cells.firstOrNull { it.evaluationId == evaluation.id }?.value
                    value?.let { evaluation.code to it }
                }.toMap()

                val varsByColumnId = columns.mapNotNull { column ->
                    val value = row.gradeValueFor(column)
                    value?.let { column.id to it }
                }.toMap()

                val vars = varsByCode + varsByColumnId

                calculated.forEach { column ->
                    runCatching { formulaEvaluator.evaluate(column.formula!!, vars) }
                        .getOrNull()
                        ?.let { calculatedValuesByColumnId[column.id] = it }
                }
                calculatedValuesByStudentId[row.student.id] = calculatedValuesByColumnId
            }
        }

        val explanationsByStudentId = averageCache.explanationsByStudent(
            rows = rows,
            columns = columns,
            calculatedValuesByStudentId = calculatedValuesByStudentId,
        ) { row, calculatedValuesByColumnId ->
            row.computeAverageExplanation(
                columns = columns,
                calculatedValuesByColumnId = calculatedValuesByColumnId,
            )
        }

        return rows.map { row ->
            val explanation = explanationsByStudentId[row.student.id]
            row.copy(
                weightedAverage = explanation?.average,
                averageExplanation = explanation,
                persistedCells = row.persistedCells,
                persistedGrades = row.persistedGrades
            )
        }
    }
}
