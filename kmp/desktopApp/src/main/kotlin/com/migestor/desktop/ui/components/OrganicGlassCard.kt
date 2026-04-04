package com.migestor.desktop.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.migestor.desktop.ui.system.LocalUiFeatureFlags

@Composable
fun OrganicGlassCard(
    modifier: Modifier = Modifier,
    backgroundColor: Color? = null,
    borderColor: Color? = null,
    borderWidth: Dp = 1.dp,
    cornerRadius: Dp = 24.dp,
    elevation: Dp = 2.dp,
    content: @Composable () -> Unit
) {
    val flags = LocalUiFeatureFlags.current
    val isDarkTheme = MaterialTheme.colorScheme.background.luminance() < 0.5f
    val defaultBackground = if (isDarkTheme) {
        MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.72f)
    } else {
        MaterialTheme.colorScheme.surface.copy(alpha = 0.86f)
    }
    val defaultBorder = if (isDarkTheme) {
        MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.72f)
    } else {
        MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)
    }
    val resolvedBackground = if (flags.accessibilitySurfaceFallback) {
        MaterialTheme.colorScheme.surface
    } else {
        backgroundColor ?: defaultBackground
    }
    val resolvedBorder = if (flags.accessibilitySurfaceFallback) {
        MaterialTheme.colorScheme.outline.copy(alpha = 0.28f)
    } else {
        borderColor ?: defaultBorder
    }

    Surface(
        modifier = modifier
            .shadow(
                elevation = elevation,
                shape = RoundedCornerShape(cornerRadius),
                ambientColor = Color(0x0A191C1E),
                spotColor = Color(0x0A191C1E)
            )
            .clip(RoundedCornerShape(cornerRadius))
            .background(resolvedBackground)
            .border(
                width = borderWidth,
                color = resolvedBorder,
                shape = RoundedCornerShape(cornerRadius)
            ),
        color = Color.Transparent,
        content = content
    )
}
