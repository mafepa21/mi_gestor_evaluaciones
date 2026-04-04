package com.migestor.desktop.ui.system

import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.remember

data class UiFeatureFlags(
    val newShell: Boolean,
    val notebookToolbarSimplified: Boolean,
    val accessibilitySurfaceFallback: Boolean,
    val reduceMotion: Boolean,
)

private fun readFlag(name: String, default: Boolean): Boolean {
    val value = System.getProperty(name)?.lowercase() ?: return default
    return when (value) {
        "1", "true", "yes", "on" -> true
        "0", "false", "no", "off" -> false
        else -> default
    }
}

fun desktopUiFeatureFlagsFromSystem(): UiFeatureFlags =
    UiFeatureFlags(
        newShell = readFlag("migestor.ui.newShell", default = true),
        notebookToolbarSimplified = readFlag("migestor.ui.notebookToolbarSimplified", default = true),
        accessibilitySurfaceFallback = readFlag("migestor.ui.accessibilitySurfaceFallback", default = false),
        reduceMotion = readFlag("migestor.ui.reduceMotion", default = false),
    )

val LocalUiFeatureFlags = staticCompositionLocalOf { desktopUiFeatureFlagsFromSystem() }

@Composable
fun rememberUiFeatureFlags(): UiFeatureFlags = remember { desktopUiFeatureFlagsFromSystem() }
