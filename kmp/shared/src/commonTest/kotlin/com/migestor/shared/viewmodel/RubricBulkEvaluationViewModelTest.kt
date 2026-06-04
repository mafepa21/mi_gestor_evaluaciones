package com.migestor.shared.viewmodel

import kotlin.test.Test
import kotlin.test.assertEquals

class RubricBulkEvaluationViewModelTest {
    @Test
    fun `bulk rubric evaluation state exposes default passing threshold`() {
        assertEquals(5.0, BulkRubricEvaluationUiState().passingThreshold)
    }
}
