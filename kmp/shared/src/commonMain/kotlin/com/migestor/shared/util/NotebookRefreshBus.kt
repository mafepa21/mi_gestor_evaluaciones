package com.migestor.shared.util

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * A shared event bus to signal when the notebook data should be refreshed.
 * This helps decouple ViewModels (e.g., RubricBulkEvaluation -> Notebook).
 */
object NotebookRefreshBus {
    private val _refreshSignal = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    
    /**
     * Flow of refresh signals. Collect this in ViewModels that need to stay in sync.
     */
    val refreshSignal = _refreshSignal.asSharedFlow()

    /**
     * Emits a refresh signal to all collectors.
     */
    fun emitRefresh() {
        _refreshSignal.tryEmit(Unit)
    }
}
