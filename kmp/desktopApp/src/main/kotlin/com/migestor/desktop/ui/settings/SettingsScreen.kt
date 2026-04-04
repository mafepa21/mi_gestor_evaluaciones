package com.migestor.desktop.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoMode
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.migestor.desktop.ui.system.UiFeatureFlags

@Composable
fun SettingsScreen(
    settings: AppSettings,
    onSettingsChange: (AppSettings) -> Unit,
    featureFlags: UiFeatureFlags,
) {
    val isPremiumDark = settings.themeMode == AppThemeMode.DarkPremium
    val pageGradient = if (isPremiumDark) {
        Brush.verticalGradient(
            colors = listOf(
                Color(0xFF050B16),
                Color(0xFF071022),
                Color(0xFF091528),
            )
        )
    } else {
        Brush.verticalGradient(
            colors = listOf(
                MaterialTheme.colorScheme.background,
                MaterialTheme.colorScheme.surface,
            )
        )
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(pageGradient)
            .padding(24.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            SettingsHeader()
            AppearanceSection(
                selectedMode = settings.themeMode,
                onModeSelected = { mode -> onSettingsChange(settings.copy(themeMode = mode)) }
            )
            ExperienceSection(
                settings = settings,
                onSettingsChange = onSettingsChange
            )
            FeatureFlagsSection(flags = featureFlags)
        }
    }
}

@Composable
private fun SettingsHeader() {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        tonalElevation = 0.dp,
        shadowElevation = 0.dp,
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.84f),
        border = androidx.compose.foundation.BorderStroke(
            1.dp,
            MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.45f)
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.18f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Settings,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
            }
            Column {
                Text(
                    text = "Ajustes",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "Personaliza apariencia, comportamiento y accesibilidad.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun AppearanceSection(
    selectedMode: AppThemeMode,
    onModeSelected: (AppThemeMode) -> Unit,
) {
    SettingsSectionCard(
        title = "Apariencia",
        subtitle = "Tema global de la app"
    ) {
        ThemeModeOption(
            title = "Según el sistema",
            description = "Se adapta automáticamente al modo del sistema operativo.",
            icon = Icons.Default.AutoMode,
            isSelected = selectedMode == AppThemeMode.System,
            onClick = { onModeSelected(AppThemeMode.System) }
        )
        ThemeModeOption(
            title = "Claro",
            description = "Superficies luminosas y lectura de alto contraste.",
            icon = Icons.Default.LightMode,
            isSelected = selectedMode == AppThemeMode.Light,
            onClick = { onModeSelected(AppThemeMode.Light) }
        )
        ThemeModeOption(
            title = "Oscuro premium",
            description = "Paleta profunda con acentos eléctricos y sensación Apple-like.",
            icon = Icons.Default.DarkMode,
            isSelected = selectedMode == AppThemeMode.DarkPremium,
            onClick = { onModeSelected(AppThemeMode.DarkPremium) }
        )
    }
}

@Composable
private fun ExperienceSection(
    settings: AppSettings,
    onSettingsChange: (AppSettings) -> Unit,
) {
    SettingsSectionCard(
        title = "Experiencia",
        subtitle = "Comportamiento inicial de la interfaz"
    ) {
        LabeledSwitch(
            title = "Mostrar inspector al iniciar",
            description = "Abre el panel inspector al entrar en el shell principal.",
            checked = settings.showInspectorByDefault,
            onCheckedChange = { onSettingsChange(settings.copy(showInspectorByDefault = it)) }
        )
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f))
        LabeledSwitch(
            title = "Iniciar con barra lateral compacta",
            description = "Arranca con la sidebar colapsada para ganar espacio de trabajo.",
            checked = settings.startWithCollapsedSidebar,
            onCheckedChange = { onSettingsChange(settings.copy(startWithCollapsedSidebar = it)) }
        )
    }
}

@Composable
private fun FeatureFlagsSection(flags: UiFeatureFlags) {
    SettingsSectionCard(
        title = "Estado UX",
        subtitle = "Flags activos de la versión actual"
    ) {
        FlagRow("Nuevo App Shell", flags.newShell)
        FlagRow("Toolbar Cuaderno simplificada", flags.notebookToolbarSimplified)
        FlagRow("Fallback de superficies sólidas", flags.accessibilitySurfaceFallback)
        FlagRow("Reduce Motion", flags.reduceMotion)
    }
}

@Composable
private fun SettingsSectionCard(
    title: String,
    subtitle: String,
    content: @Composable ColumnScope.() -> Unit,
) {
    Card(
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.84f)
        ),
        border = androidx.compose.foundation.BorderStroke(
            1.dp,
            MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.45f)
        ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
            content = {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f))
                content()
            }
        )
    }
}

@Composable
private fun ThemeModeOption(
    title: String,
    description: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    isSelected: Boolean,
    onClick: () -> Unit,
) {
    val borderColor = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant
    val backgroundColor = if (isSelected) {
        MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
    } else {
        MaterialTheme.colorScheme.surface.copy(alpha = 0.42f)
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(backgroundColor)
            .border(1.dp, borderColor.copy(alpha = 0.6f), RoundedCornerShape(14.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.7f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary
            )
        }
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(start = 12.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        RadioButton(selected = isSelected, onClick = onClick)
    }
}

@Composable
private fun LabeledSwitch(
    title: String,
    description: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(text = title, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Spacer(modifier = Modifier.width(12.dp))
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@Composable
private fun FlagRow(label: String, enabled: Boolean) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = Icons.Default.CheckCircle,
                contentDescription = null,
                tint = if (enabled) Color(0xFF33D17A) else MaterialTheme.colorScheme.outline
            )
            Spacer(modifier = Modifier.width(6.dp))
            Text(
                text = if (enabled) "Activo" else "Inactivo",
                style = MaterialTheme.typography.labelMedium,
                color = if (enabled) Color(0xFF33D17A) else MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
