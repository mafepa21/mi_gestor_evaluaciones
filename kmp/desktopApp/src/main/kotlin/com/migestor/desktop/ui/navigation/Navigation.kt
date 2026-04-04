package com.migestor.desktop.ui.navigation

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

sealed class Screen {
    object Main : Screen()
    data class RubricEvaluation(
        val studentId: Long,
        val evaluationId: Long,
        val rubricId: Long,
        val columnId: String? = null
    ) : Screen()
    data class RubricBulkEvaluation(
        val classId: Long,
        val evaluationId: Long,
        val rubricId: Long,
        val columnId: String? = null,
        val tabId: String? = null
    ) : Screen()
}

object Navigator {
    var currentScreen by mutableStateOf<Screen>(Screen.Main)
        private set

    fun navigateTo(screen: Screen) {
        currentScreen = screen
    }

    fun goBack() {
        currentScreen = Screen.Main
    }
}
