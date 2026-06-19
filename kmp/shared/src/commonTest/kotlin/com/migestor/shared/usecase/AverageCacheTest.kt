package com.migestor.shared.usecase

import com.migestor.shared.domain.Grade
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookRow
import com.migestor.shared.domain.Student
import com.migestor.shared.domain.computeAverageExplanation
import kotlin.test.Test
import kotlin.test.assertEquals

class AverageCacheTest {
    @Test
    fun `reuses average explanations until student values or average config change`() {
        val cache = AverageCache()
        var computeCount = 0
        val columns = listOf(
            NotebookColumnDefinition(
                id = "eval_1",
                title = "Examen",
                type = NotebookColumnType.NUMERIC,
                evaluationId = 1L,
                weight = 1.0,
            )
        )
        val firstRow = row(studentId = 1L, columnId = "eval_1", evaluationId = 1L, value = 8.0)
        val secondRow = row(studentId = 2L, columnId = "eval_1", evaluationId = 1L, value = 9.0)

        fun build(rows: List<NotebookRow>, activeColumns: List<NotebookColumnDefinition> = columns) {
            cache.explanationsByStudent(rows = rows, columns = activeColumns) { row, calculatedValues ->
                computeCount += 1
                row.computeAverageExplanation(
                    columns = activeColumns,
                    calculatedValuesByColumnId = calculatedValues,
                )
            }
        }

        build(listOf(firstRow, secondRow))
        assertEquals(2, computeCount)

        build(listOf(firstRow, secondRow))
        assertEquals(2, computeCount)

        build(listOf(firstRow.copyWithValue(7.0), secondRow))
        assertEquals(3, computeCount)

        build(listOf(firstRow.copyWithValue(7.0), secondRow), columns.map { it.copy(weight = 0.5) })
        assertEquals(5, computeCount)

        build(listOf(firstRow.copyWithValue(7.0), secondRow), columns.map { it.copy(countsTowardAverage = false) })
        assertEquals(7, computeCount)
    }

    private fun row(
        studentId: Long,
        columnId: String,
        evaluationId: Long,
        value: Double,
    ): NotebookRow {
        return NotebookRow(
            student = Student(id = studentId, firstName = "Alumno", lastName = studentId.toString()),
            cells = emptyList(),
            weightedAverage = null,
            persistedGrades = listOf(
                Grade(
                    id = studentId,
                    classId = 1L,
                    studentId = studentId,
                    columnId = columnId,
                    evaluationId = evaluationId,
                    value = value,
                )
            ),
        )
    }

    private fun NotebookRow.copyWithValue(value: Double): NotebookRow {
        return copy(
            persistedGrades = persistedGrades.map { grade ->
                grade.copy(value = value)
            }
        )
    }
}
