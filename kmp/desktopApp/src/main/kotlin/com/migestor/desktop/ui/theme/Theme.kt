package com.migestor.desktop.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.migestor.desktop.ui.settings.AppThemeMode

private val LightColors = lightColorScheme(
    primary = md_theme_light_primary,
    onPrimary = md_theme_light_onPrimary,
    primaryContainer = md_theme_light_primaryContainer,
    onPrimaryContainer = md_theme_light_onPrimaryContainer,
    secondary = md_theme_light_secondary,
    onSecondary = md_theme_light_onSecondary,
    secondaryContainer = md_theme_light_secondaryContainer,
    onSecondaryContainer = md_theme_light_onSecondaryContainer,
    tertiary = md_theme_light_tertiary,
    onTertiary = md_theme_light_onTertiary,
    tertiaryContainer = md_theme_light_tertiaryContainer,
    onTertiaryContainer = md_theme_light_onTertiaryContainer,
    error = md_theme_light_error,
    errorContainer = md_theme_light_errorContainer,
    onError = md_theme_light_onError,
    onErrorContainer = md_theme_light_onErrorContainer,
    background = md_theme_light_background,
    onBackground = md_theme_light_onBackground,
    surface = md_theme_light_surface,
    onSurface = md_theme_light_onSurface,
    surfaceVariant = md_theme_light_surfaceVariant,
    onSurfaceVariant = md_theme_light_onSurfaceVariant,
    outline = md_theme_light_outline,
    inverseOnSurface = md_theme_light_inverseOnSurface,
    inverseSurface = md_theme_light_inverseSurface,
    inversePrimary = md_theme_light_inversePrimary,
    surfaceTint = md_theme_light_surfaceTint,
    outlineVariant = md_theme_light_outlineVariant,
    scrim = md_theme_light_scrim,
)

private val DarkColors = darkColorScheme(
    primary = md_theme_dark_primary,
    onPrimary = md_theme_dark_onPrimary,
    primaryContainer = md_theme_dark_primaryContainer,
    onPrimaryContainer = md_theme_dark_onPrimaryContainer,
    secondary = md_theme_dark_secondary,
    onSecondary = md_theme_dark_onSecondary,
    secondaryContainer = md_theme_dark_secondaryContainer,
    onSecondaryContainer = md_theme_dark_onSecondaryContainer,
    tertiary = md_theme_dark_tertiary,
    onTertiary = md_theme_dark_onTertiary,
    tertiaryContainer = md_theme_dark_tertiaryContainer,
    onTertiaryContainer = md_theme_dark_onTertiaryContainer,
    error = md_theme_dark_error,
    onError = md_theme_dark_onError,
    background = md_theme_dark_background,
    onBackground = md_theme_dark_onBackground,
    surface = md_theme_dark_surface,
    onSurface = md_theme_dark_onSurface,
    surfaceVariant = md_theme_dark_surfaceVariant,
    onSurfaceVariant = md_theme_dark_onSurfaceVariant,
    outline = md_theme_dark_outline,
    inverseOnSurface = md_theme_dark_inverseOnSurface,
    inverseSurface = md_theme_dark_inverseSurface,
    inversePrimary = md_theme_dark_inversePrimary,
)

private val PremiumDarkColors = darkColorScheme(
    primary = md_theme_premium_dark_primary,
    onPrimary = md_theme_premium_dark_onPrimary,
    primaryContainer = md_theme_premium_dark_primaryContainer,
    onPrimaryContainer = md_theme_premium_dark_onPrimaryContainer,
    secondary = md_theme_premium_dark_secondary,
    onSecondary = md_theme_premium_dark_onSecondary,
    secondaryContainer = md_theme_premium_dark_secondaryContainer,
    onSecondaryContainer = md_theme_premium_dark_onSecondaryContainer,
    tertiary = md_theme_premium_dark_tertiary,
    onTertiary = md_theme_premium_dark_onTertiary,
    tertiaryContainer = md_theme_premium_dark_tertiaryContainer,
    onTertiaryContainer = md_theme_premium_dark_onTertiaryContainer,
    error = md_theme_premium_dark_error,
    onError = md_theme_premium_dark_onError,
    background = md_theme_premium_dark_background,
    onBackground = md_theme_premium_dark_onBackground,
    surface = md_theme_premium_dark_surface,
    onSurface = md_theme_premium_dark_onSurface,
    surfaceVariant = md_theme_premium_dark_surfaceVariant,
    onSurfaceVariant = md_theme_premium_dark_onSurfaceVariant,
    outline = md_theme_premium_dark_outline,
    inverseOnSurface = md_theme_premium_dark_inverseOnSurface,
    inverseSurface = md_theme_premium_dark_inverseSurface,
    inversePrimary = md_theme_premium_dark_inversePrimary,
    surfaceTint = md_theme_premium_dark_surfaceTint,
    outlineVariant = md_theme_premium_dark_outlineVariant,
)

private val AppTypography = Typography(
    displayLarge = TextStyle(fontSize = 40.sp, lineHeight = 46.sp, fontWeight = FontWeight.SemiBold),
    headlineSmall = TextStyle(fontSize = 24.sp, lineHeight = 30.sp, fontWeight = FontWeight.SemiBold),
    titleLarge = TextStyle(fontSize = 20.sp, lineHeight = 26.sp, fontWeight = FontWeight.SemiBold),
    titleMedium = TextStyle(fontSize = 17.sp, lineHeight = 23.sp, fontWeight = FontWeight.Medium),
    bodyLarge = TextStyle(fontSize = 16.sp, lineHeight = 22.sp, fontWeight = FontWeight.Normal),
    bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Normal),
    labelLarge = TextStyle(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium),
    labelSmall = TextStyle(fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Medium),
)

@Composable
fun MiGestorTheme(
    themeMode: AppThemeMode = AppThemeMode.System,
    content: @Composable () -> Unit
) {
    val darkTheme = when (themeMode) {
        AppThemeMode.System -> isSystemInDarkTheme()
        AppThemeMode.Light -> false
        AppThemeMode.DarkPremium -> true
    }
    val colors = when (themeMode) {
        AppThemeMode.Light -> LightColors
        AppThemeMode.DarkPremium -> PremiumDarkColors
        AppThemeMode.System -> if (darkTheme) PremiumDarkColors else LightColors
    }
    MaterialTheme(
        colorScheme = colors,
        typography = AppTypography,
        content = content
    )
}
