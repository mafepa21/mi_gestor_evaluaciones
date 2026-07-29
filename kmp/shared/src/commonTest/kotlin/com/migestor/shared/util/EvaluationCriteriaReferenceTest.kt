package com.migestor.shared.util

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class EvaluationCriteriaReferenceTest {
    @Test
    fun `known instrument title resolves to the official criterion statement`() {
        val statement = EvaluationCriteriaReference.criterionStatement(
            "Rejilla de observación sistemática de fair play, roles e inclusión"
        )
        assertEquals(
            "Practicar diversas actividades motrices adoptando un comportamiento personal y social respetuoso y responsable, mostrando actitudes de empatía e inclusión ante la diversidad y autorregulando las emociones.",
            statement
        )
    }

    @Test
    fun `instrument with two criteria joins both statements with their code`() {
        val statement = EvaluationCriteriaReference.criterionStatement(
            "Rejilla de observación sistemática de proceso"
        )
        assertTrue(statement != null && statement.startsWith("Criterio 1.2:"))
        assertTrue(statement != null && statement.contains("Criterio 1.4:"))
    }

    @Test
    fun `title matching is case and accent insensitive`() {
        val statement = EvaluationCriteriaReference.criterionStatement(
            "  rubrica DE organizacion SOSTENIBLE del torneo  "
        )
        assertEquals(
            "Diseñar y participar en eventos recreativos y deportivos aplicando políticas sostenibles de gestión y uso de materiales e instalaciones.",
            statement
        )
    }

    @Test
    fun `unknown title returns null instead of throwing`() {
        assertNull(EvaluationCriteriaReference.criterionStatement("Instrumento de otra materia"))
    }
}
