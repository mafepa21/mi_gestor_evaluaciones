package com.migestor.shared.domain

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNull

class TeacherTermNoteKeysTest {

    @Test
    fun lasEtiquetasVisiblesDeTrimestreDanClavesEstables() {
        assertEquals("T1", TeacherTermNoteKeys.fromLabel("1er Trimestre"))
        assertEquals("T2", TeacherTermNoteKeys.fromLabel("2º Trimestre"))
        assertEquals("T3", TeacherTermNoteKeys.fromLabel("3er Trimestre"))
        // Otra redacción de la misma etiqueta no cambia la clave.
        assertEquals("T2", TeacherTermNoteKeys.fromLabel("  Trimestre 2 "))
    }

    @Test
    fun unaEtiquetaSinNumeroNoSeMezclaConLosTrimestres() {
        val clave = TeacherTermNoteKeys.fromLabel("Evaluación Final")
        assertEquals("X_evaluaciónfinal", clave)
        assertNotEquals(TeacherTermNoteKeys.FIRST, clave)
        // Sin etiqueta se usa el primer trimestre, que es el valor por defecto de la pantalla.
        assertEquals(TeacherTermNoteKeys.FIRST, TeacherTermNoteKeys.fromLabel(null))
        assertEquals(TeacherTermNoteKeys.FIRST, TeacherTermNoteKeys.fromLabel("  "))
    }

    @Test
    fun elIdDeSyncEsLaClaveNaturalYSePuedeLeerDeVuelta() {
        val id = TeacherTermNoteKeys.syncId(studentId = 12, classId = 7, termKey = "T3")
        assertEquals("12|7|T3", id)
        assertEquals(Triple(12L, 7L, "T3"), TeacherTermNoteKeys.parseSyncId(id))
        assertEquals(id, StudentTermTeacherNote(studentId = 12, classId = 7, termKey = "T3").syncId)

        assertNull(TeacherTermNoteKeys.parseSyncId("12"))
        assertNull(TeacherTermNoteKeys.parseSyncId("12|7"))
        assertNull(TeacherTermNoteKeys.parseSyncId("a|7|T1"))
        assertNull(TeacherTermNoteKeys.parseSyncId("12|7|"))
    }

    @Test
    fun elTextoSeGuardaSinEspaciosSobrantesYDentroDelTope() {
        assertEquals("Hola", TeacherTermNoteKeys.sanitize("  Hola \n"))
        assertEquals("", TeacherTermNoteKeys.sanitize("   "))
        assertEquals(
            TeacherTermNoteKeys.MAX_NOTE_LENGTH,
            TeacherTermNoteKeys.sanitize("a".repeat(TeacherTermNoteKeys.MAX_NOTE_LENGTH + 1)).length,
        )
    }
}
