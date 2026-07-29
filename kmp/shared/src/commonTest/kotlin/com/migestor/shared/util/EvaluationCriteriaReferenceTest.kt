package com.migestor.shared.util

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class EvaluationCriteriaReferenceTest {
    @Test
    fun `known instrument title resolves to its criterion code and statement`() {
        val statements = EvaluationCriteriaReference.criterionStatements(
            "Rejilla de observación sistemática de fair play, roles e inclusión"
        )
        assertEquals(1, statements.size)
        assertEquals("3.2", statements.single().code)
        assertEquals(
            "Practicar diversas actividades motrices adoptando un comportamiento personal y social respetuoso y responsable, mostrando actitudes de empatía e inclusión ante la diversidad y autorregulando las emociones.",
            statements.single().statement
        )
    }

    @Test
    fun `instrument with two criteria returns both, in document order`() {
        val statements = EvaluationCriteriaReference.criterionStatements(
            "Rejilla de observación sistemática de proceso"
        )
        assertEquals(listOf("1.2", "1.4"), statements.map { it.code })
        assertTrue(statements.all { it.statement.isNotBlank() })
    }

    @Test
    fun `title matching is case and accent insensitive`() {
        val statements = EvaluationCriteriaReference.criterionStatements(
            "  rubrica DE organizacion SOSTENIBLE del torneo  "
        )
        assertEquals("2.2", statements.single().code)
    }

    @Test
    fun `unknown title resolves to no criteria`() {
        assertTrue(EvaluationCriteriaReference.criterionStatements("Instrumento de otra materia").isEmpty())
        assertNull(EvaluationCriteriaReference.criterionStatement("Instrumento de otra materia"))
    }

    @Test
    fun `flat text always prefixes the criterion code, single or multiple`() {
        val single = EvaluationCriteriaReference.criterionStatement(
            "Rúbrica de organización sostenible del torneo"
        )
        assertEquals(true, single?.startsWith("Criterio 2.2:"))

        val multiple = EvaluationCriteriaReference.criterionStatement(
            "Rejilla de observación sistemática de proceso"
        )
        assertTrue(multiple?.startsWith("Criterio 1.2:") == true)
        assertTrue(multiple?.contains("Criterio 1.4:") == true)
    }
}
