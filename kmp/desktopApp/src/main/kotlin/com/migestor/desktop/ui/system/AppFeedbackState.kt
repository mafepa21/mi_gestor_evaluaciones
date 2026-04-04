package com.migestor.desktop.ui.system

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudDone
import androidx.compose.material.icons.filled.CloudQueue
import androidx.compose.material.icons.filled.CloudSync
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import com.migestor.desktop.ui.theme.GreenGlass
import com.migestor.shared.viewmodel.NotebookViewModelSaveState

data class AppFeedbackState(
    val label: String,
    val icon: ImageVector,
    val color: Color,
    val actionable: Boolean,
)

fun NotebookViewModelSaveState.toAppFeedbackState(errorColor: Color, neutralColor: Color): AppFeedbackState =
    when (this) {
        NotebookViewModelSaveState.Saved -> AppFeedbackState(
            label = "Guardado",
            icon = Icons.Default.CloudDone,
            color = GreenGlass,
            actionable = false,
        )
        NotebookViewModelSaveState.Unsaved -> AppFeedbackState(
            label = "Cambios pendientes",
            icon = Icons.Default.CloudQueue,
            color = errorColor,
            actionable = true,
        )
        NotebookViewModelSaveState.Saving -> AppFeedbackState(
            label = "Guardando…",
            icon = Icons.Default.CloudSync,
            color = neutralColor,
            actionable = false,
        )
    }

