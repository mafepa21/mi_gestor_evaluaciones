package com.migestor.shared.viewmodel

import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * Event bus singleton to synchronize rubric evaluation state
 * between RubricBulkEvaluationViewModel, RubricEvaluationViewModel, and NotebookViewModel.
 */
data class RubricEvaluationSavedEvent(
    val studentId: Long,
    val rubricId: Long,
    val selectedLevels: Map<Long, Long>,   // criterionId -> levelId
    val score: Double,
    val columnId: String? = null           // null if not from notebook context
)

object RubricEvaluationBus {
    private val _events = MutableSharedFlow<RubricEvaluationSavedEvent>(
        replay = 0,
        extraBufferCapacity = 64,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    val events = _events.asSharedFlow()

    suspend fun emit(event: RubricEvaluationSavedEvent) {
        _events.emit(event)
    }
}
