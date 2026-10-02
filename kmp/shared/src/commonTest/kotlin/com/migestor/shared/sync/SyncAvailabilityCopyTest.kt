package com.migestor.shared.sync

import kotlin.test.Test
import kotlin.test.assertEquals

class SyncAvailabilityCopyTest {
    @Test
    fun unFalloDeArranqueNoSePresentaComoEsperaDeEmparejamiento() {
        assertEquals(
            "El enlace local no arrancó. puerto ocupado",
            SyncAvailabilityCopy.status(startError = "puerto ocupado", isPaired = false),
        )
        assertEquals("Esperando emparejamiento", SyncAvailabilityCopy.status(startError = null, isPaired = false))
        assertEquals("Vinculado", SyncAvailabilityCopy.status(startError = null, isPaired = true))
    }
}
