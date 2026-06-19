package com.migestor.shared

import com.migestor.shared.domain.AssessmentInstrumentScoreStrategy
import com.migestor.shared.domain.AssessmentInstrumentSourceKind
import com.migestor.shared.domain.AssessmentInstrumentSpec
import com.migestor.shared.domain.NotebookCellInputKind
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookInstrumentKind
import com.migestor.shared.domain.NotebookScaleKind
import com.migestor.shared.domain.validationIssues
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AssessmentInstrumentSpecTest {
    @Test
    fun `checklist proportional is explicit but not materializable as average yet`() {
        val spec = baseSpec(
            sourceKind = AssessmentInstrumentSourceKind.CHECKLIST,
            columnType = NotebookColumnType.TEXT,
            instrumentKind = NotebookInstrumentKind.CHECKLIST,
            inputKind = NotebookCellInputKind.STRUCTURED_CHECKLIST,
            scaleKind = NotebookScaleKind.CUSTOM,
            scoreStrategy = AssessmentInstrumentScoreStrategy.CHECKLIST_PROPORTIONAL,
        )

        assertFalse(spec.canMaterializeAverage())
        assertTrue(spec.validationIssues().any { it.blocksMaterialization })
    }

    @Test
    fun `observation scale must declare four level scale to count`() {
        val invalid = baseSpec(
            sourceKind = AssessmentInstrumentSourceKind.OBSERVATION_GRID,
            columnType = NotebookColumnType.NUMERIC,
            instrumentKind = NotebookInstrumentKind.SYSTEMATIC_OBSERVATION,
            inputKind = NotebookCellInputKind.NUMERIC_1_4,
            scaleKind = NotebookScaleKind.CUSTOM,
            scoreStrategy = AssessmentInstrumentScoreStrategy.OBSERVATION_SCALE_1_TO_4,
        )
        val valid = invalid.copy(scaleKind = NotebookScaleKind.FOUR_LEVEL)

        assertTrue(invalid.validationIssues().any { it.blocksMaterialization })
        assertTrue(valid.validationIssues().none { it.blocksMaterialization })
        assertTrue(valid.canMaterializeAverage())
    }

    private fun baseSpec(
        sourceKind: AssessmentInstrumentSourceKind,
        columnType: NotebookColumnType,
        instrumentKind: NotebookInstrumentKind,
        inputKind: NotebookCellInputKind,
        scaleKind: NotebookScaleKind,
        scoreStrategy: AssessmentInstrumentScoreStrategy,
    ): AssessmentInstrumentSpec =
        AssessmentInstrumentSpec(
            title = "Instrumento",
            sourceKind = sourceKind,
            columnType = columnType,
            instrumentKind = instrumentKind,
            inputKind = inputKind,
            scaleKind = scaleKind,
            weightPercent = 10.0,
            countsTowardAverage = true,
            scoreStrategy = scoreStrategy,
        )
}
