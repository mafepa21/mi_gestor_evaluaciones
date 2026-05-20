package com.migestor.shared

import com.migestor.shared.domain.Attendance
import com.migestor.shared.domain.Grade
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookRow
import com.migestor.shared.domain.NotebookSheet
import com.migestor.shared.domain.RadarPriority
import com.migestor.shared.domain.Student
import com.migestor.shared.domain.usecase.BuildTeacherRadarUseCase
import kotlinx.datetime.Clock
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class BuildTeacherRadarUseCaseTest {
    @Test
    fun highRiskCombinesLowAverageAndLowAttendance() {
        val student = Student(id = 1, firstName = "Laura", lastName = "Paz")
        val sheet = notebookSheet(
            rows = listOf(
                NotebookRow(
                    student = student,
                    cells = emptyList(),
                    weightedAverage = 4.8,
                )
            )
        )
        val attendance = listOf(
            attendance(student.id, "PRESENTE"),
            attendance(student.id, "AUSENTE"),
            attendance(student.id, "AUSENTE"),
            attendance(student.id, "AUSENTE"),
        )

        val insights = BuildTeacherRadarUseCase().build(sheet, attendance)

        assertTrue(insights.any { it.priority == RadarPriority.HIGH && it.studentId == student.id })
        assertTrue(insights.any { it.title.contains("media < 5") })
    }

    @Test
    fun positiveProgressUsesPreviousAverage() {
        val student = Student(id = 2, firstName = "Itoda", lastName = "Sol")
        val sheet = notebookSheet(
            rows = listOf(
                NotebookRow(
                    student = student,
                    cells = emptyList(),
                    weightedAverage = 6.6,
                    persistedGrades = listOf(Grade(id = 1, classId = 1, studentId = student.id, columnId = "ev1", evaluationId = 1, value = 6.6, evidence = "Observación"))
                )
            )
        )

        val insights = BuildTeacherRadarUseCase().build(sheet, previousAveragesByStudentId = mapOf(student.id to 5.2))

        assertEquals(RadarPriority.POSITIVE, insights.first { it.studentId == student.id && it.id.endsWith("positive-progress") }.priority)
    }

    @Test
    fun groupInsightDetectsIncompleteRubrics() {
        val rubricColumn = NotebookColumnDefinition(
            id = "rubric-1",
            title = "Juego sin balón",
            type = NotebookColumnType.RUBRIC,
            evaluationId = 10,
            rubricId = 20,
        )
        val sheet = notebookSheet(
            columns = listOf(rubricColumn),
            rows = listOf(
                NotebookRow(student = Student(1, "Marcos", "Rio"), cells = emptyList(), weightedAverage = 7.0),
                NotebookRow(student = Student(2, "Nora", "Luz"), cells = emptyList(), weightedAverage = 8.0),
            )
        )

        val insights = BuildTeacherRadarUseCase().build(sheet)

        assertTrue(insights.any { it.studentId == null && it.priority == RadarPriority.HIGH && it.title.contains("2 alumnos") })
    }

    private fun notebookSheet(
        columns: List<NotebookColumnDefinition> = emptyList(),
        rows: List<NotebookRow>,
    ): NotebookSheet = NotebookSheet(
        classId = 1,
        tabs = emptyList(),
        columns = columns,
        rows = rows,
    )

    private fun attendance(studentId: Long, status: String): Attendance = Attendance(
        id = studentId,
        studentId = studentId,
        classId = 1,
        date = Clock.System.now(),
        status = status,
    )
}
