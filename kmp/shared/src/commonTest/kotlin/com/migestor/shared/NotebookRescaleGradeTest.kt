package com.migestor.shared

import com.migestor.shared.domain.NotebookCellInputKind
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookScaleKind
import com.migestor.shared.domain.rescaleNumericGrade
import kotlin.test.Test
import kotlin.test.assertEquals

class NotebookRescaleGradeTest {
    private fun column(inputKind: NotebookCellInputKind) = NotebookColumnDefinition(
        id = "c",
        title = "Instrumento",
        type = NotebookColumnType.NUMERIC,
        inputKind = inputKind,
        scaleKind = NotebookScaleKind.CUSTOM,
    )

    @Test
    fun `una lista de casillas no se lee como nivel 1-4`() {
        // 2 de 5 casillas = 4,0 sobre 10; antes contaba como un 10.
        assertEquals(4.0, column(NotebookCellInputKind.STRUCTURED_CHECKLIST).rescaleNumericGrade(4.0))
    }

    @Test
    fun `una rejilla de observacion sigue reescalando el nivel 1-4`() {
        assertEquals(10.0, column(NotebookCellInputKind.STRUCTURED_OBSERVATION).rescaleNumericGrade(4.0))
    }
}
