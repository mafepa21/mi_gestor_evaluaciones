package com.migestor.shared.util

import com.migestor.shared.domain.RubricLevel
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class RubricTimingTest {
    private val levels = listOf(
        RubricLevel(id = 14, criterionId = 1, name = "Nivel 4", points = 4, order = 0),
        RubricLevel(id = 11, criterionId = 1, name = "Nivel 1", points = 1, order = 3),
        RubricLevel(id = 13, criterionId = 1, name = "Nivel 3", points = 3, order = 1),
        RubricLevel(id = 12, criterionId = 1, name = "Nivel 2", points = 2, order = 2),
    )

    @Test
    fun menosEsMejorPoneElNivelSegunLosCortes() {
        val timing = RubricTiming.parse("lower;10.0;12.0;15.0")!!
        assertEquals(14L, timing.levelFor(9.8, levels)?.id)
        assertEquals(13L, timing.levelFor(10.0, levels)?.id)
        assertEquals(13L, timing.levelFor(11.4, levels)?.id)
        assertEquals(12L, timing.levelFor(12.0, levels)?.id)
        assertEquals(11L, timing.levelFor(15.0, levels)?.id)
        assertEquals(11L, timing.levelFor(21.0, levels)?.id)
    }

    @Test
    fun masEsMejorInvierteElSentido() {
        val timing = RubricTiming.parse("higher;3;5;8")!!
        assertEquals(11L, timing.levelFor(2.0, levels)?.id)
        assertEquals(14L, timing.levelFor(8.0, levels)?.id)
    }

    @Test
    fun textoMalFormadoONivelesQueNoCuadranNoDanNivel() {
        assertNull(RubricTiming.parse(null))
        assertNull(RubricTiming.parse("lower"))
        assertNull(RubricTiming.parse("faster;1;2"))
        assertNull(RubricTiming.parse("lower;12;10;15"))
        assertNull(RubricTiming.parse("lower;10;12")!!.levelFor(9.0, levels))
    }

    @Test
    fun aceptaComaDecimalYSeSerializaIgual() {
        val timing = RubricTiming.parse("lower; 10,5 ;12;15")!!
        assertEquals(listOf(10.5, 12.0, 15.0), timing.cuts)
        assertEquals(timing, RubricTiming.parse(timing.serialize()))
    }
}
