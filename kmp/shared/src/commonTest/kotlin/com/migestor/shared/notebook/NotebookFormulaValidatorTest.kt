package com.migestor.shared.notebook

import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class NotebookFormulaValidatorTest {
    private val exam = NotebookColumnDefinition(id = "eval_1", title = "Examen", type = NotebookColumnType.NUMERIC)
    private val rubric = NotebookColumnDefinition(id = "rubric_1", title = "Rúbrica", type = NotebookColumnType.RUBRIC)

    @Test
    fun `valid formula returns referenced columns and preview`() {
        val result = validateFormula(
            formula = "REDONDEAR(PROMEDIO([eval_1];[rubric_1]);2)",
            targetColumnId = "media",
            availableColumns = listOf(exam, rubric),
            formulaColumns = emptyList(),
        )

        assertTrue(result.isValid)
        assertEquals(listOf("eval_1", "rubric_1"), result.referencedColumnIds)
        assertEquals(1.0, result.previewValue)
    }

    @Test
    fun `unknown column is rejected`() {
        val result = validateFormula(
            formula = "PROMEDIO([eval_1],[missing])",
            targetColumnId = "media",
            availableColumns = listOf(exam),
            formulaColumns = emptyList(),
        )

        assertFalse(result.isValid)
        assertEquals(NotebookFormulaErrorKind.UNKNOWN_COLUMN, result.errors.single().kind)
    }

    @Test
    fun `direct circular reference is rejected`() {
        val result = validateFormula(
            formula = "[media] + 1",
            targetColumnId = "media",
            availableColumns = listOf(exam, NotebookColumnDefinition(id = "media", title = "Media", type = NotebookColumnType.CALCULATED)),
            formulaColumns = emptyList(),
        )

        assertFalse(result.isValid)
        assertEquals(NotebookFormulaErrorKind.CIRCULAR_REFERENCE, result.errors.single().kind)
    }

    @Test
    fun `indirect circular reference is rejected`() {
        val formulaB = NotebookColumnDefinition(
            id = "formula_b",
            title = "B",
            type = NotebookColumnType.CALCULATED,
            formula = "[formula_a] + 1",
        )

        val result = validateFormula(
            formula = "[formula_b] + 1",
            targetColumnId = "formula_a",
            availableColumns = listOf(exam, formulaB),
            formulaColumns = listOf(formulaB),
        )

        assertFalse(result.isValid)
        assertEquals(NotebookFormulaErrorKind.CIRCULAR_REFERENCE, result.errors.single().kind)
    }

    @Test
    fun `unsupported function is rejected`() {
        val result = validateFormula(
            formula = "ROUND([eval_1], 2)",
            targetColumnId = "media",
            availableColumns = listOf(exam),
            formulaColumns = emptyList(),
        )

        assertFalse(result.isValid)
        assertEquals(NotebookFormulaErrorKind.UNSUPPORTED_FUNCTION, result.errors.single().kind)
    }

    @Test
    fun `division by zero is rejected`() {
        val result = validateFormula(
            formula = "[eval_1] / 0",
            targetColumnId = "media",
            availableColumns = listOf(exam),
            formulaColumns = emptyList(),
        )

        assertFalse(result.isValid)
        assertEquals(NotebookFormulaErrorKind.DIVISION_BY_ZERO, result.errors.single().kind)
    }
}
