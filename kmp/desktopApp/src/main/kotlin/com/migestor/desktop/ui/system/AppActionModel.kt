package com.migestor.desktop.ui.system

import androidx.compose.ui.graphics.vector.ImageVector

enum class AppActionPlacement {
    Toolbar,
    Overflow,
    Context,
}

enum class AppActionEmphasis {
    Primary,
    Secondary,
    Destructive,
}

data class AppActionModel(
    val id: String,
    val label: String,
    val icon: ImageVector,
    val placement: AppActionPlacement = AppActionPlacement.Toolbar,
    val emphasis: AppActionEmphasis = AppActionEmphasis.Secondary,
    val enabled: Boolean = true,
    val onClick: () -> Unit,
)

