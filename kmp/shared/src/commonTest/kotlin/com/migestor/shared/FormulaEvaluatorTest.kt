package com.migestor.shared

import com.migestor.shared.formula.FormulaEvaluator
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class FormulaEvaluatorTest {
    private val evaluator = FormulaEvaluator()

    @Test
    fun `evaluates arithmetic with variables`() {
        val result = evaluator.evaluate("(EX1 * 0.4) + (EX2 * 0.6)", mapOf("EX1" to 8.0, "EX2" to 6.0))
        assertEquals(6.8, result)
    }

    @Test
    fun `throws when missing variable`() {
        assertFailsWith<IllegalStateException> {
            evaluator.evaluate("EX1 + EX2", mapOf("EX1" to 5.0))
        }
    }

    @Test
    fun `supports IF with comparisons`() {
        val result = evaluator.evaluate("IF(EX1 >= 5, 10, 0)", mapOf("EX1" to 7.0))
        assertEquals(10.0, result)
    }

    @Test
    fun `supports AND OR functions`() {
        val result = evaluator.evaluate(
            "IF(AND(EX1 >= 5, OR(EX2 >= 5, EX3 >= 5)), 1, 0)",
            mapOf("EX1" to 6.0, "EX2" to 4.0, "EX3" to 8.0),
        )
        assertEquals(1.0, result)
    }

    @Test
    fun `supports aggregation helpers`() {
        val result = evaluator.evaluate("ROUND(AVG(EX1, EX2, EX3), 2)", mapOf("EX1" to 6.0, "EX2" to 7.0, "EX3" to 8.0))
        assertEquals(7.0, result)
    }
}
