package com.migestor.desktop.ui.settings

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import java.util.prefs.Preferences

enum class AppThemeMode(val key: String, val label: String) {
    System("system", "Según el sistema"),
    Light("light", "Claro"),
    DarkPremium("dark_premium", "Oscuro premium");

    companion object {
        fun fromKey(value: String?): AppThemeMode =
            entries.firstOrNull { it.key == value } ?: System
    }
}

data class AppSettings(
    val themeMode: AppThemeMode = AppThemeMode.System,
    val showInspectorByDefault: Boolean = false,
    val startWithCollapsedSidebar: Boolean = false,
)

private const val PREF_NODE = "com.migestor.desktop.ui.settings"
private const val KEY_THEME_MODE = "theme_mode"
private const val KEY_DEFAULT_INSPECTOR = "default_inspector"
private const val KEY_START_COLLAPSED_SIDEBAR = "start_collapsed_sidebar"

private fun loadSettings(prefs: Preferences): AppSettings = AppSettings(
    themeMode = AppThemeMode.fromKey(prefs.get(KEY_THEME_MODE, AppThemeMode.System.key)),
    showInspectorByDefault = prefs.getBoolean(KEY_DEFAULT_INSPECTOR, false),
    startWithCollapsedSidebar = prefs.getBoolean(KEY_START_COLLAPSED_SIDEBAR, false),
)

private fun saveSettings(prefs: Preferences, settings: AppSettings) {
    prefs.put(KEY_THEME_MODE, settings.themeMode.key)
    prefs.putBoolean(KEY_DEFAULT_INSPECTOR, settings.showInspectorByDefault)
    prefs.putBoolean(KEY_START_COLLAPSED_SIDEBAR, settings.startWithCollapsedSidebar)
    runCatching { prefs.flush() }
}

@Composable
fun rememberAppSettingsState(): MutableState<AppSettings> {
    val prefs = remember { Preferences.userRoot().node(PREF_NODE) }
    val state = remember { mutableStateOf(loadSettings(prefs)) }
    LaunchedEffect(state.value) {
        saveSettings(prefs, state.value)
    }
    return state
}
