package com.migestor.shared

import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookColumnVisibility
import com.migestor.shared.domain.NotebookEmptyCellPolicy
import com.migestor.shared.domain.NotebookRow
import com.migestor.shared.domain.PersistedNotebookCell
import com.migestor.shared.domain.Student
import com.migestor.shared.domain.computeAverageExplanation
import com.migestor.shared.usecase.BuildNotebookClosingReportUseCase
import com.migestor.shared.usecase.ClosingIssueKind
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class BuildNotebookClosingReportUseCaseTest {
    private val useCase = BuildNotebookClosingReportUseCase()

    private fun numeric(
        id: String,
        weight: Double = 1.0,
        hidden: Boolean = false,
        criteria: List<Long> = emptyList(),
    ) = NotebookColumnDefinition(
        id = id,
        title = "Col $id",
        type = NotebookColumnType.NUMERIC,
        weight = weight,
        isHidden = hidden,
        visibility = if (hidden) NotebookColumnVisibility.HIDDEN else NotebookColumnVisibility.VISIBLE,
        competencyCriteriaIds = criteria,
    )

    private fun student(id: Long, name: String) = Student(id = id, firstName = name, lastName = "Prueba")

    /** Fila de prueba: `grades` son notas por columna; `texts` son textos escritos por columna. */
    private fun row(
        columns: List<NotebookColumnDefinition>,
        student: Student,
        grades: Map<String, Double> = emptyMap(),
        texts: Map<String, String> = emptyMap(),
        calculated: Map<String, Double> = emptyMap(),
    ): NotebookRow {
        val persisted = texts.map { (columnId, text) ->
            PersistedNotebookCell(classId = 1, studentId = student.id, columnId = columnId, textValue = text)
        }
        val base = NotebookRow(
            student = student,
            cells = emptyList(),
            weightedAverage = null,
            persistedCells = persisted,
            persistedGrades = grades.map { (columnId, value) ->
                com.migestor.shared.domain.Grade(
                    id = student.id * 100 + columnId.hashCode().toLong().and(0xFF),
                    classId = 1,
                    studentId = student.id,
                    columnId = columnId,
                    evaluationId = null,
                    value = value,
                )
            },
        )
        val explanation = base.computeAverageExplanation(columns, calculatedValuesByColumnId = calculated)
        return base.copy(weightedAverage = explanation?.average, averageExplanation = explanation)
    }

    @Test
    fun `grupo sin columnas que cuenten no genera avisos`() {
        val columns = listOf(numeric("a", weight = 0.0))
        val report = useCase.build(columns, listOf(row(columns, student(1, "Ana"))))
        assertFalse(report.hasCountingColumns)
        assertTrue(report.issues.isEmpty())
        assertFalse(report.isAllClear)
    }

    @Test
    fun `grupo completo queda todo listo`() {
        val columns = listOf(numeric("a"), numeric("b"))
        val rows = listOf(
            row(columns, student(1, "Ana"), grades = mapOf("a" to 7.0, "b" to 6.0)),
            row(columns, student(2, "Luis"), grades = mapOf("a" to 5.0, "b" to 9.0)),
        )
        val report = useCase.build(columns, rows)
        assertTrue(report.isAllClear)
        assertEquals(0, report.totalCount)
    }

    @Test
    fun `notas vacias se agrupan por columna con recuento`() {
        val columns = listOf(numeric("a"), numeric("b"))
        val rows = listOf(
            row(columns, student(1, "Ana"), grades = mapOf("a" to 7.0)),
            row(columns, student(2, "Luis"), grades = mapOf("a" to 5.0)),
            row(columns, student(3, "Marta"), grades = mapOf("a" to 6.0, "b" to 8.0)),
        )
        val report = useCase.build(columns, rows)
        val empty = report.issuesOf(ClosingIssueKind.EMPTY_GRADE)
        assertEquals(1, empty.size)
        assertEquals("b", empty[0].columnId)
        assertEquals(listOf(1L, 2L), empty[0].students.map { it.id })
        assertEquals(2, report.countOf(ClosingIssueKind.EMPTY_GRADE))
    }

    @Test
    fun `alumno sin ninguna nota sale sin Media`() {
        val columns = listOf(numeric("a"))
        val rows = listOf(
            row(columns, student(1, "Ana"), grades = mapOf("a" to 7.0)),
            row(columns, student(2, "Pablo")),
        )
        val report = useCase.build(columns, rows)
        val noAverage = report.issuesOf(ClosingIssueKind.NO_AVERAGE)
        assertEquals(1, noAverage.size)
        assertEquals(2L, noAverage[0].students.single().id)
    }

    @Test
    fun `texto no numerico sale como nota que no se entiende y no como vacia`() {
        val columns = listOf(numeric("a"))
        val rows = listOf(
            row(columns, student(1, "Jorge"), texts = mapOf("a" to "8,5a")),
            row(columns, student(2, "Ana"), texts = mapOf("a" to "7,5"), grades = mapOf("a" to 7.5)),
        )
        val report = useCase.build(columns, rows)
        val bad = report.issuesOf(ClosingIssueKind.NOT_UNDERSTOOD)
        assertEquals(1, bad.size)
        assertEquals("8,5a", bad[0].text)
        assertEquals("a", bad[0].columnId)
        assertTrue(report.issuesOf(ClosingIssueKind.EMPTY_GRADE).isEmpty())
    }

    @Test
    fun `columna oculta que cuenta sale con su peso`() {
        val columns = listOf(numeric("a"), numeric("h", weight = 10.0, hidden = true))
        val rows = listOf(row(columns, student(1, "Ana"), grades = mapOf("a" to 7.0, "h" to 5.0)))
        val hidden = useCase.build(columns, rows).issuesOf(ClosingIssueKind.HIDDEN_COLUMN)
        assertEquals(1, hidden.size)
        assertEquals("h", hidden[0].columnId)
        assertEquals(10.0, hidden[0].weight)
    }

    @Test
    fun `columna archivada no cuenta ni avisa`() {
        val archived = numeric("z").copy(visibility = NotebookColumnVisibility.ARCHIVED)
        val columns = listOf(numeric("a"), archived)
        val rows = listOf(row(columns, student(1, "Ana"), grades = mapOf("a" to 7.0)))
        assertTrue(useCase.build(columns, rows).issues.isEmpty())
    }

    @Test
    fun `criterio sin nota en ninguno de sus instrumentos avisa con codigo`() {
        val columns = listOf(
            numeric("a", criteria = listOf(21L)),
            numeric("b", criteria = listOf(21L)),
            numeric("c"),
        )
        val rows = listOf(
            row(columns, student(1, "Ana"), grades = mapOf("a" to 7.0)),
            row(columns, student(2, "Lucía"), grades = mapOf("c" to 6.0)),
        )
        val report = useCase.build(columns, rows, criterionCodes = mapOf(21L to "CE 2.1"))
        val criteria = report.issuesOf(ClosingIssueKind.CRITERION_WITHOUT_GRADE)
        assertEquals(1, criteria.size)
        assertEquals("CE 2.1", criteria[0].criterionCode)
        assertEquals(2, criteria[0].instrumentCount)
        assertEquals(2L, criteria[0].students.single().id)
    }

    @Test
    fun `criterio sin codigo conocido usa texto de reserva`() {
        val columns = listOf(numeric("a", criteria = listOf(5L)), numeric("c"))
        val rows = listOf(row(columns, student(1, "Ana"), grades = mapOf("c" to 6.0)))
        val issue = useCase.build(columns, rows).issuesOf(ClosingIssueKind.CRITERION_WITHOUT_GRADE).single()
        assertNull(issue.criterionCode)
        assertEquals("Criterio 5", issue.title)
    }

    @Test
    fun `los avisos salen en el orden de la hoja y el total no suma criterios`() {
        val columns = listOf(
            numeric("a", criteria = listOf(1L)),
            numeric("h", hidden = true, criteria = listOf(2L)),
            numeric("c"),
        )
        val rows = listOf(
            row(columns, student(1, "Ana"), grades = mapOf("a" to 7.0, "h" to 5.0, "c" to 6.0)),
            row(columns, student(2, "Pablo")),
            row(columns, student(3, "Luis"), grades = mapOf("a" to 4.0, "c" to 6.0)),
        )
        val report = useCase.build(columns, rows)
        assertEquals(
            listOf(
                ClosingIssueKind.EMPTY_GRADE,
                ClosingIssueKind.NO_AVERAGE,
                ClosingIssueKind.HIDDEN_COLUMN,
                ClosingIssueKind.CRITERION_WITHOUT_GRADE,
            ),
            report.issues.map { it.kind },
        )
        // Luis en «h» + Pablo sin Media + columna oculta; el criterio de Luis no suma.
        assertEquals(3, report.totalCount)
    }

    @Test
    fun `quien no tiene Media no se repite en notas vacias ni en criterios`() {
        val columns = listOf(numeric("a", criteria = listOf(1L)), numeric("b"))
        val rows = listOf(
            row(columns, student(1, "Ana"), grades = mapOf("a" to 7.0, "b" to 6.0)),
            row(columns, student(2, "Pablo")),
        )
        val report = useCase.build(columns, rows)
        assertEquals(1, report.countOf(ClosingIssueKind.NO_AVERAGE))
        assertTrue(report.issuesOf(ClosingIssueKind.EMPTY_GRADE).isEmpty())
        assertTrue(report.issuesOf(ClosingIssueKind.CRITERION_WITHOUT_GRADE).isEmpty())
        assertEquals(1, report.totalCount)
    }

    @Test
    fun `columna calculada con valor no da falso positivo de criterio`() {
        val calc = NotebookColumnDefinition(
            id = "calc",
            title = "Calculada",
            type = NotebookColumnType.CALCULATED,
            competencyCriteriaIds = listOf(9L),
        )
        val columns = listOf(numeric("a"), calc)
        val rows = listOf(
            row(columns, student(1, "Ana"), grades = mapOf("a" to 7.0), calculated = mapOf("calc" to 6.0)),
        )
        val report = useCase.build(columns, rows)
        assertTrue(report.issuesOf(ClosingIssueKind.CRITERION_WITHOUT_GRADE).isEmpty())
        assertTrue(report.issuesOf(ClosingIssueKind.EMPTY_GRADE).isEmpty())
    }

    @Test
    fun `vacio que cuenta como cero sigue siendo un hueco`() {
        val zero = numeric("z").copy(emptyCellPolicy = NotebookEmptyCellPolicy.COUNT_AS_ZERO)
        val columns = listOf(numeric("a"), zero)
        val rows = listOf(
            row(columns, student(1, "Ana"), grades = mapOf("a" to 7.0)),
            row(columns, student(2, "Luis"), grades = mapOf("a" to 5.0, "z" to 0.0)),
        )
        val empty = useCase.build(columns, rows).issuesOf(ClosingIssueKind.EMPTY_GRADE)
        assertEquals(1, empty.size)
        assertEquals("z", empty[0].columnId)
        assertEquals(listOf(1L), empty[0].students.map { it.id })
    }
}
