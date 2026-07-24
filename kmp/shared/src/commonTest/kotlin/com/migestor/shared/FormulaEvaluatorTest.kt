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
    fun `evaluates bracketed column references`() {
        val result = evaluator.evaluate(
            "REDONDEAR((([eval_1]*0.6)+([rubric_1]*0.4));2)",
            mapOf("eval_1" to 8.0, "rubric_1" to 6.0),
        )

        assertEquals(7.2, result)
    }

    @Test
    fun `throws when missing variable`() {
        assertFailsWith<IllegalStateException> {
            evaluator.evaluate("EX1 + EX2", mapOf("EX1" to 5.0))
        }
    }

    @Test
    fun `supports IF with comparisons`() {
        val result = evaluator.evaluate("IF(EX1 >= 5; 10; 0)", mapOf("EX1" to 7.0))
        assertEquals(10.0, result)
    }

    @Test
    fun `supports AND OR functions`() {
        val result = evaluator.evaluate(
            "IF(AND(EX1 >= 5; OR(EX2 >= 5; EX3 >= 5)); 1; 0)",
            mapOf("EX1" to 6.0, "EX2" to 4.0, "EX3" to 8.0),
        )
        assertEquals(1.0, result)
    }

    @Test
    fun `supports aggregation helpers`() {
        val result = evaluator.evaluate("ROUND(AVG(EX1; EX2; EX3); 2)", mapOf("EX1" to 6.0, "EX2" to 7.0, "EX3" to 8.0))
        assertEquals(7.0, result)
    }

    @Test
    fun `supports leading equals and bracket column references`() {
        val result = evaluator.evaluate(
            "=ROUND(AVG([eval_1]; [COL_2]); 2)",
            mapOf("eval_1" to 8.0, "COL_2" to 6.0),
        )
        assertEquals(7.0, result)
    }

    @Test
    fun `supports equality comparison with bracket references`() {
        val result = evaluator.evaluate(
            "SI([col_1]=5; 10; 0)",
            mapOf("col_1" to 5.0),
        )
        assertEquals(10.0, result)
    }

    @Test
    fun `treats comma as decimal separator instead of argument separator`() {
        val result = evaluator.evaluate("[Nota1]*1,5", mapOf("Nota1" to 4.0))
        assertEquals(6.0, result)
    }

    @Test
    fun `semicolon still separates arguments when a decimal comma is present`() {
        val result = evaluator.evaluate("REDONDEAR([Nota1]*1,5;1)", mapOf("Nota1" to 4.0))
        assertEquals(6.0, result)
    }

    @Test
    fun `comma still separates arguments for formulas stored before the syntax change`() {
        val result = evaluator.evaluate(
            "REDONDEAR(PROMEDIO([eval_1],[rubric_1]),2)",
            mapOf("eval_1" to 6.0, "rubric_1" to 8.0),
        )
        assertEquals(7.0, result)
    }

    @Test
    fun `comma after a closing parenthesis separates arguments`() {
        val result = evaluator.evaluate("REDONDEAR(1+1, 2)", emptyMap())
        assertEquals(2.0, result)
    }

    @Test
    fun `rounds exact half up, not to the nearest even number`() {
        // Regresion: kotlin.math.round hace "banker's rounding" (mitad al par):
        // 7,5 sube a 8 (8 es par) pero 8,5 TAMBIEN baja a 8 (8 es par) en vez de
        // subir a 9. La convencion docente esperada es "mitad siempre hacia
        // arriba": un alumno con media exacta 8,5 debe recibir un 9, no un 8.
        assertEquals(9.0, evaluator.evaluate("REDONDEAR(8,5;0)", emptyMap()))
        assertEquals(8.0, evaluator.evaluate("REDONDEAR(7,5;0)", emptyMap()))
        assertEquals(3.0, evaluator.evaluate("REDONDEAR(2,5;0)", emptyMap()))
        assertEquals(1.0, evaluator.evaluate("REDONDEAR(0,5;0)", emptyMap()))
    }

    @Test
    fun `rounds exact half up when the value comes from a weighted average, not just a literal`() {
        // Misma regresion que el test anterior, pero con la media calculada a partir
        // de notas reales (0,4/0,6) en vez de un literal "8,5" ya escrito en la
        // formula, para cubrir el caso realista de una columna Media.
        val result = evaluator.evaluate(
            "REDONDEAR(([EX1]*0.5)+([EX2]*0.5);0)",
            mapOf("EX1" to 8.0, "EX2" to 9.0), // media = 8.5
        )
        assertEquals(9.0, result)
    }

    @Test
    fun `rounds exact half up with decimal digits`() {
        assertEquals(8.25, evaluator.evaluate("REDONDEAR(8,245;2)", emptyMap()))
        assertEquals(-9.0, evaluator.evaluate("REDONDEAR(-8,5;0)", emptyMap()))
    }
}
