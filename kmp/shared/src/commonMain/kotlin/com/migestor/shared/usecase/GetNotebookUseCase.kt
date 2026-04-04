package com.migestor.shared.usecase

import com.migestor.shared.domain.NotebookCell
import com.migestor.shared.domain.NotebookRow
import com.migestor.shared.formula.FormulaEvaluator
import com.migestor.shared.repository.ClassesRepository
import com.migestor.shared.repository.EvaluationsRepository
import com.migestor.shared.repository.GradesRepository
import com.migestor.shared.repository.NotebookCellsRepository

class GetNotebookUseCase(
    private val classesRepository: ClassesRepository,
    private val evaluationsRepository: EvaluationsRepository,
    private val gradesRepository: GradesRepository,
    private val notebookCellsRepository: NotebookCellsRepository,
    private val formulaEvaluator: FormulaEvaluator = FormulaEvaluator(),
) {
    suspend operator fun invoke(
        classId: Long,
        providedStudents: List<com.migestor.shared.domain.Student>? = null,
        providedEvaluations: List<com.migestor.shared.domain.Evaluation>? = null,
    ): NotebookResult {
        require(classId > 0) { "ClassId inválido" }

        val students = providedStudents ?: classesRepository.listStudentsInClass(classId)
        val evaluations = providedEvaluations ?: evaluationsRepository.listClassEvaluations(classId)

        val allPersistedCells = notebookCellsRepository.listClassCells(classId)
        val cellsByStudent = allPersistedCells.groupBy { it.studentId }

        val rows = students.map { student ->
            val grades = gradesRepository.listGradesForStudentInClass(student.id, classId)
            val cells = evaluations.map { evaluation ->
                val value = grades.firstOrNull {
                    it.evaluationId == evaluation.id || it.columnId == "eval_${evaluation.id}"
                }?.value

                NotebookCell(
                    evaluationId = evaluation.id,
                    value = value,
                )
            }

            val average = computeFinalAverage(cells = cells, evaluations = evaluations)

            NotebookRow(
                student = student,
                cells = cells,
                weightedAverage = average,
                persistedCells = cellsByStudent[student.id] ?: emptyList(),
                persistedGrades = grades
            )
        }

        return NotebookResult(evaluations.map { it.id }, rows)
    }

    private fun computeFinalAverage(
        cells: List<NotebookCell>,
        evaluations: List<com.migestor.shared.domain.Evaluation>,
    ): Double? {
        if (evaluations.isEmpty()) return null

        val weightedSum = evaluations.sumOf { evaluation ->
            val grade = cells.firstOrNull { it.evaluationId == evaluation.id }?.value ?: 0.0
            grade * evaluation.weight
        }
        val totalWeight = evaluations.sumOf { it.weight }.takeIf { it > 0.0 } ?: return null

        val formulaEvaluation = evaluations.firstOrNull { !it.formula.isNullOrBlank() }
        if (formulaEvaluation?.formula != null) {
            val variables = evaluations.associate { evaluation ->
                val v = cells.firstOrNull { it.evaluationId == evaluation.id }?.value ?: 0.0
                evaluation.code to v
            }
            return formulaEvaluator.evaluate(formulaEvaluation.formula, variables)
        }

        return weightedSum / totalWeight
    }
}

data class NotebookResult(
    val evaluationIds: List<Long>,
    val rows: List<NotebookRow>,
)
