package com.migestor.shared

import com.migestor.shared.domain.Grade
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookColumnVisibility
import com.migestor.shared.domain.NotebookRow
import com.migestor.shared.domain.Rubric
import com.migestor.shared.domain.RubricAssessment
import com.migestor.shared.domain.RubricCriterion
import com.migestor.shared.domain.RubricCriterionWithLevels
import com.migestor.shared.domain.RubricDetail
import com.migestor.shared.domain.RubricLevel
import com.migestor.shared.domain.Student
import com.migestor.shared.domain.computeAverageExplanation
import com.migestor.shared.usecase.BuildStudentGradeReportsUseCase
import com.migestor.shared.usecase.GradeLevel
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class BuildStudentGradeReportsUseCaseTest {
    private val useCase = BuildStudentGradeReportsUseCase()

    private fun column(
        id: String,
        weight: Double,
        type: NotebookColumnType = NotebookColumnType.NUMERIC,
        hidden: Boolean = false,
        criteria: List<Long> = emptyList(),
    ) = NotebookColumnDefinition(
        id = id,
        title = "Col $id",
        type = type,
        weight = weight,
        isHidden = hidden,
        visibility = if (hidden) NotebookColumnVisibility.HIDDEN else NotebookColumnVisibility.VISIBLE,
        competencyCriteriaIds = criteria,
    )

    private fun row(
        columns: List<NotebookColumnDefinition>,
        student: Student,
        grades: Map<String, Double>,
    ): NotebookRow {
        val base = NotebookRow(
            student = student,
            cells = emptyList(),
            weightedAverage = null,
            persistedGrades = grades.map { (columnId, value) ->
                Grade(
                    id = student.id * 100 + columnId.hashCode().toLong().and(0xFF),
                    classId = 1,
                    studentId = student.id,
                    columnId = columnId,
                    evaluationId = null,
                    value = value,
                )
            },
        )
        val explanation = base.computeAverageExplanation(columns)
        return base.copy(weightedAverage = explanation?.average, averageExplanation = explanation)
    }

    private val lucia = Student(id = 1, firstName = "Lucía", lastName = "Prueba", email = " lucia@example.test ")
    private val hugo = Student(id = 2, firstName = "Hugo", lastName = "Prueba", email = "  ")

    @Test
    fun laNotaFinalCoincideConLaMediaYLosPesosSumanCien() {
        val columns = listOf(column("a", 30.0), column("b", 25.0), column("c", 20.0), column("d", 15.0), column("e", 10.0))
        val rows = listOf(row(columns, lucia, mapOf("a" to 6.5, "b" to 8.0, "c" to 7.0, "d" to 9.0, "e" to 8.0)))

        val report = useCase.build(columns, rows).single()

        assertEquals(rows.single().weightedAverage, report.finalGrade)
        assertEquals(7.5, report.finalGrade!!, 0.0001)
        assertEquals(GradeLevel.NOTABLE, report.finalLevel)
        assertEquals(100.0, report.instruments.sumOf { it.weightPercent }, 0.0001)
        assertEquals(30.0, report.instruments.first { it.columnId == "a" }.weightPercent, 0.0001)
        assertEquals(GradeLevel.BIEN, report.instruments.first { it.columnId == "a" }.level)
        assertEquals("d", report.bestInstrument?.columnId)
        assertEquals("a", report.weakestInstrument?.columnId)
    }

    @Test
    fun soloEntraLoQueCuentaEnLaMediaYLasVaciasSalenComoPendientes() {
        val columns = listOf(
            column("a", 1.0),
            column("fuera", 1.0, hidden = true).copy(countsTowardAverage = false),
            column("vacia", 1.0),
        )
        val rows = listOf(row(columns, lucia, mapOf("a" to 8.0, "fuera" to 2.0)))

        val report = useCase.build(columns, rows).single()

        assertEquals(listOf("a"), report.instruments.map { it.columnId })
        assertEquals(listOf("Col vacia"), report.pendingTitles)
        assertEquals(8.0, report.finalGrade!!, 0.0001)
    }

    @Test
    fun elCorreoSeLimpiaYSinCorreoNoSePuedeEnviar() {
        val columns = listOf(column("a", 1.0))
        val reports = useCase.build(columns, listOf(row(columns, lucia, mapOf("a" to 5.0)), row(columns, hugo, mapOf("a" to 4.0))))

        assertEquals("lucia@example.test", reports[0].email)
        assertTrue(reports[0].hasEmail)
        assertNull(reports[1].email)
        assertFalse(reports[1].hasEmail)
        assertEquals(GradeLevel.INSUFICIENTE, reports[1].finalLevel)
    }

    @Test
    fun sinNotasNoHayNotaFinal() {
        val columns = listOf(column("a", 1.0))
        val report = useCase.build(columns, listOf(row(columns, lucia, emptyMap()))).single()

        assertNull(report.finalGrade)
        assertFalse(report.hasGrades)
    }

    @Test
    fun losCodigosDeCriterioSalenEnCadaInstrumento() {
        val columns = listOf(column("a", 1.0, criteria = listOf(10, 11, 10, 99)))
        val report = useCase.build(
            columns,
            listOf(row(columns, lucia, mapOf("a" to 7.0))),
            criterionCodes = mapOf(10L to "CE 1.2", 11L to "CE 1.3", 99L to " "),
        ).single()

        assertEquals(listOf("CE 1.2", "CE 1.3"), report.instruments.single().criterionCodes)
    }

    @Test
    fun laRubricaMuestraElNivelRealDeCadaCriterioOrdenadoPorPuntos() {
        val columns = listOf(column("r", 1.0, type = NotebookColumnType.RUBRIC))
        val rubric = RubricDetail(
            rubric = Rubric(id = 5, name = "Expresión"),
            criteria = listOf(
                RubricCriterionWithLevels(
                    criterion = RubricCriterion(id = 50, rubricId = 5, description = "Trabajo en grupo", weight = 1.0, order = 2),
                    // Orden de edición al revés: el nivel con más puntos va primero.
                    levels = listOf(
                        RubricLevel(id = 504, criterionId = 50, name = "Excelente", points = 4, description = "Ayuda al grupo", order = 0),
                        RubricLevel(id = 501, criterionId = 50, name = "Inicial", points = 1, order = 3),
                        RubricLevel(id = 503, criterionId = 50, name = "Logrado", points = 3, order = 1),
                        RubricLevel(id = 502, criterionId = 50, name = "En proceso", points = 2, order = 2),
                    ),
                ),
                RubricCriterionWithLevels(
                    criterion = RubricCriterion(id = 40, rubricId = 5, description = "Comunica con el cuerpo", weight = 1.0, order = 1),
                    levels = listOf(
                        RubricLevel(id = 401, criterionId = 40, name = "Inicial", points = 1, order = 0),
                        RubricLevel(id = 402, criterionId = 40, name = "Logrado", points = 2, description = "Se entiende", order = 1),
                    ),
                ),
                RubricCriterionWithLevels(
                    criterion = RubricCriterion(id = 30, rubricId = 5, description = "Sin valorar", weight = 1.0, order = 3),
                    levels = listOf(RubricLevel(id = 301, criterionId = 30, name = "Inicial", points = 1, order = 0)),
                ),
            ),
        )
        val assessments = listOf(
            RubricAssessment(studentId = 1, evaluationId = 9, criterionId = 50, levelId = 503),
            RubricAssessment(studentId = 1, evaluationId = 9, criterionId = 40, levelId = 402),
            RubricAssessment(studentId = 2, evaluationId = 9, criterionId = 30, levelId = 301),
        )

        val report = useCase.build(
            columns,
            listOf(row(columns, lucia, mapOf("r" to 8.0))),
            rubricsByColumn = mapOf("r" to rubric),
            assessmentsByColumn = mapOf("r" to assessments),
        ).single()

        val criteria = report.rubrics.single().criteria
        assertEquals(listOf("Comunica con el cuerpo", "Trabajo en grupo"), criteria.map { it.name })
        assertEquals("Logrado", criteria[1].levelName)
        assertEquals(3, criteria[1].levelPosition)
        assertEquals(4, criteria[1].levelCount)
        assertEquals("Se entiende", criteria[0].levelDescription)
        assertNull(criteria[1].levelDescription)
    }

    @Test
    fun sinValoracionesNoHayBloqueDeRubrica() {
        val columns = listOf(column("r", 1.0, type = NotebookColumnType.RUBRIC))
        val rubric = RubricDetail(rubric = Rubric(id = 5, name = "R"), criteria = emptyList())
        val report = useCase.build(
            columns,
            listOf(row(columns, lucia, mapOf("r" to 8.0))),
            rubricsByColumn = mapOf("r" to rubric),
        ).single()

        assertTrue(report.rubrics.isEmpty())
    }

    @Test
    fun lasBandasDeNivelSonLasDeLaLomloe() {
        assertEquals(GradeLevel.INSUFICIENTE, GradeLevel.of(4.99))
        assertEquals(GradeLevel.SUFICIENTE, GradeLevel.of(5.0))
        assertEquals(GradeLevel.BIEN, GradeLevel.of(6.0))
        assertEquals(GradeLevel.NOTABLE, GradeLevel.of(7.0))
        assertEquals(GradeLevel.SOBRESALIENTE, GradeLevel.of(9.0))
    }
}
