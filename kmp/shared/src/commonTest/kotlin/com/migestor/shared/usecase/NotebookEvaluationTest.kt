package com.migestor.shared.usecase

import com.migestor.shared.domain.Grade
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookEmptyCellPolicy
import com.migestor.shared.domain.NotebookRow
import com.migestor.shared.domain.NotebookTab
import com.migestor.shared.domain.Student
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Nota de evaluación por bloques: el ejemplo del docente (Hockey 60 %, Ultimate 40 %). */
class NotebookEvaluationTest {
    private val ana = Student(id = 1, firstName = "Ana", lastName = "Ejemplo")

    private val evaluation = NotebookTab(id = "ev1", title = "1.ª Evaluación", order = 0)
    private val hockey = NotebookTab(id = "hockey", title = "Hockey", order = 0, parentTabId = "ev1", weight = 60.0)
    private val ultimate = NotebookTab(id = "ultimate", title = "Ultimate", order = 1, parentTabId = "ev1", weight = 40.0)
    private val loose = NotebookTab(id = "asistencia", title = "Asistencia", order = 1)
    private val tabs = listOf(evaluation, hockey, ultimate, loose)

    private fun numeric(id: String, tab: String, weight: Double, policy: NotebookEmptyCellPolicy = NotebookEmptyCellPolicy.EXCLUDE_FROM_AVERAGE) =
        NotebookColumnDefinition(
            id = id,
            title = id,
            type = NotebookColumnType.NUMERIC,
            weight = weight,
            tabIds = listOf(tab),
            emptyCellPolicy = policy,
        )

    private val columns = listOf(
        numeric("conduccion", "hockey", 33.0),
        numeric("pase", "hockey", 33.0),
        numeric("partido", "hockey", 33.0),
        numeric("lanzamiento", "ultimate", 30.0),
        numeric("recepcion", "ultimate", 30.0),
        numeric("tactica", "ultimate", 30.0),
        numeric("actitud", "ultimate", 10.0),
    )

    private fun row(grades: Map<String, Double>) = NotebookRow(
        student = ana,
        cells = emptyList(),
        weightedAverage = null,
        persistedGrades = grades.entries.mapIndexed { index, (columnId, value) ->
            Grade(id = index.toLong() + 1, classId = 1, studentId = ana.id, columnId = columnId, evaluationId = null, value = value)
        },
    )

    private fun assertClose(expected: Double, actual: Double?) {
        assertTrue(actual != null && abs(expected - actual) < 0.001, "esperaba $expected y salió $actual")
    }

    @Test
    fun laNotaCombinaPesosDeNotaYDeBloque() {
        val explanation = NotebookEvaluation.explain(
            row = row(mapOf(
                "conduccion" to 8.0, "pase" to 7.0, "partido" to 7.5,
                "lanzamiento" to 6.0, "recepcion" to 6.0, "tactica" to 5.0, "actitud" to 9.0,
            )),
            tabs = tabs,
            columns = columns,
            evaluationTabId = "ev1",
        )!!
        // Hockey 7,5 (33/33/33); Ultimate 6,0 (30/30/30/10); 0,6 × 7,5 + 0,4 × 6,0 = 6,9.
        assertClose(7.5, explanation.blocks[0].average)
        assertClose(6.0, explanation.blocks[1].average)
        assertClose(6.9, explanation.average)
        assertEquals(listOf(60.0, 40.0), explanation.blocks.map { it.weightPercent })
        assertFalse(explanation.isPartial)
    }

    @Test
    fun unBloqueSinNotasNoCuentaComoCero() {
        val explanation = NotebookEvaluation.explain(
            row = row(mapOf("conduccion" to 8.0, "pase" to 7.0, "partido" to 7.5)),
            tabs = tabs,
            columns = columns,
            evaluationTabId = "ev1",
        )!!
        assertClose(7.5, explanation.average)
        assertTrue(explanation.isPartial)
        assertEquals(listOf("Ultimate"), explanation.blocksWithoutGrades.map { it.title })
    }

    @Test
    fun sinNingunaNotaNoHayNota() {
        val explanation = NotebookEvaluation.explain(row(emptyMap()), tabs, columns, "ev1")!!
        assertNull(explanation.average)
        assertFalse(explanation.isPartial)
    }

    @Test
    fun losPesosSeRepartenEnProporcion() {
        val sixtySixty = listOf(hockey.copy(weight = 60.0), ultimate.copy(weight = 60.0))
        assertEquals(mapOf("hockey" to 50.0, "ultimate" to 50.0), NotebookEvaluation.weightPercents(sixtySixty))
        val noWeights = listOf(hockey.copy(weight = null), ultimate.copy(weight = null))
        assertEquals(mapOf("hockey" to 50.0, "ultimate" to 50.0), NotebookEvaluation.weightPercents(noWeights))
        val allZero = listOf(hockey.copy(weight = 0.0), ultimate.copy(weight = 0.0))
        assertEquals(mapOf("hockey" to 50.0, "ultimate" to 50.0), NotebookEvaluation.weightPercents(allZero))
    }

    @Test
    fun unaCeldaVaciaQueCuentaComoCeroBajaSuBloque() {
        val strict = columns.map { if (it.id == "partido") it.copy(emptyCellPolicy = NotebookEmptyCellPolicy.COUNT_AS_ZERO) else it }
        val explanation = NotebookEvaluation.explain(
            row = row(mapOf("conduccion" to 9.0, "pase" to 9.0, "lanzamiento" to 5.0)),
            tabs = tabs,
            columns = strict,
            evaluationTabId = "ev1",
        )!!
        assertClose(6.0, explanation.blocks[0].average)
        assertClose(0.6 * 6.0 + 0.4 * 5.0, explanation.average)
    }

    @Test
    fun reconoceEvaluacionesBloquesYPestanasSueltas() {
        assertTrue(NotebookEvaluation.isEvaluationTab(tabs, "ev1"))
        assertFalse(NotebookEvaluation.isEvaluationTab(tabs, "hockey"))
        assertFalse(NotebookEvaluation.isEvaluationTab(tabs, "asistencia"))
        assertEquals("ev1", NotebookEvaluation.evaluationTabId(tabs, "hockey"))
        assertEquals("ev1", NotebookEvaluation.evaluationTabId(tabs, "ev1"))
        assertNull(NotebookEvaluation.evaluationTabId(tabs, "asistencia"))
        assertEquals(7, NotebookEvaluation.columnsForEvaluation(tabs, columns, "ev1").size)
        assertEquals(
            listOf("evalblock:hockey" to "Hockey · 60 %", "evalblock:ultimate" to "Ultimate · 40 %"),
            NotebookEvaluation.blockCategories(1, tabs, "ev1").map { it.id to it.name },
        )
        assertEquals("33,3 %", NotebookEvaluation.formatPercent(100.0 / 3))
    }
}
