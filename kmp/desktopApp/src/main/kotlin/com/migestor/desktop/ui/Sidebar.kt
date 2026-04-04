package com.migestor.desktop.ui

import androidx.compose.animation.*
import androidx.compose.animation.core.EaseInOutCubic
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuOpen
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.migestor.desktop.AppTab
import com.migestor.desktop.ui.components.LiquidGlassFab
import com.migestor.desktop.ui.system.LocalUiFeatureFlags

@Composable
fun Sidebar(
    currentTab: AppTab,
    onTabSelected: (AppTab) -> Unit,
    onNewClass: () -> Unit,
    isExpanded: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier
) {
    val flags = LocalUiFeatureFlags.current
    val sidebarWidth by animateDpAsState(
        targetValue = if (isExpanded) 240.dp else 56.dp,
        animationSpec = tween(
            durationMillis = if (flags.reduceMotion) 0 else 300,
            easing = EaseInOutCubic
        )
    )
    val isDarkTheme = MaterialTheme.colorScheme.background.luminance() < 0.5f
    val sidebarBg = if (isDarkTheme) {
        MaterialTheme.colorScheme.surface.copy(alpha = 0.96f)
    } else {
        MaterialTheme.colorScheme.surface.copy(alpha = 0.86f)
    }

    Column(
        modifier = modifier
            .fillMaxHeight()
            .width(sidebarWidth)
            .shadow(
                elevation = 24.dp,
                ambientColor = Color(0x0A191C1E),
                spotColor = Color(0x0A191C1E)
            )
            .background(sidebarBg)
            .padding(vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Logo / Title area
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Icono de la app (siempre visible)
            Box(
                modifier = Modifier
                    .size(24.dp)
                    .background(MaterialTheme.colorScheme.primary, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    "M",
                    color = Color.White,
                    style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold)
                )
            }

            // Título solo en modo expandido
            if (flags.reduceMotion) {
                if (isExpanded) {
                    Column(verticalArrangement = Arrangement.spacedBy(0.dp)) {
                        Text(
                            text = "MiGestor KMP",
                            style = MaterialTheme.typography.titleMedium.copy(
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.primary
                            ),
                            maxLines = 1
                        )
                        Text(
                            text = "EDUCATION MANAGEMENT",
                            style = MaterialTheme.typography.labelSmall.copy(
                                fontWeight = FontWeight.SemiBold,
                                letterSpacing = 0.5.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                            ),
                            maxLines = 1
                        )
                    }
                }
            } else {
                AnimatedVisibility(
                    visible = isExpanded,
                    enter = fadeIn() + expandHorizontally(),
                    exit = fadeOut() + shrinkHorizontally()
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(0.dp)) {
                        Text(
                            text = "MiGestor KMP",
                            style = MaterialTheme.typography.titleMedium.copy(
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.primary
                            ),
                            maxLines = 1
                        )
                        Text(
                            text = "EDUCATION MANAGEMENT",
                            style = MaterialTheme.typography.labelSmall.copy(
                                fontWeight = FontWeight.SemiBold,
                                letterSpacing = 0.5.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                            ),
                            maxLines = 1
                        )
                    }
                }
            }

            if (isExpanded) {
                Spacer(modifier = Modifier.weight(1f))
            }

            // Botón toggle SIEMPRE visible en la cabecera
            IconButton(onClick = onToggle, modifier = Modifier.size(44.dp)) {
                Icon(
                    imageVector = if (isExpanded)
                        Icons.AutoMirrored.Filled.MenuOpen else Icons.Default.Menu,
                    contentDescription = "Toggle sidebar",
                    tint = MaterialTheme.colorScheme.primary
                )
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        // ── BOTÓN NUEVA CLASE ──────────────────────────
        if (isExpanded) {
            LiquidGlassFab(
                text = "Nueva Clase",
                icon = Icons.Default.Add,
                onClick = onNewClass,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp)
            )
        } else {
            // Solo el icono en modo colapsado
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primaryContainer)
                    .clickable { onNewClass() },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Default.Add,
                    contentDescription = "Nueva Clase",
                    tint = MaterialTheme.colorScheme.onPrimaryContainer,
                    modifier = Modifier.size(24.dp)
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Navigation links
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            AppTab.entries.filter { it != AppTab.Ajustes }.forEach { tab ->
                val icon = when (tab) {
                    AppTab.Dashboard -> Icons.Default.Dashboard
                    AppTab.Cursos -> Icons.Default.Groups
                    AppTab.Cuaderno -> Icons.Default.Book
                    AppTab.PaseDeLista -> Icons.Default.FactCheck
                    AppTab.Diario -> Icons.Default.MenuBook
                    AppTab.Planificacion -> Icons.Default.EventNote
                    AppTab.Evaluacion -> Icons.Default.Assessment
                    AppTab.Rubricas -> Icons.Default.Rule
                    AppTab.Informes -> Icons.Default.Assessment
                    AppTab.Biblioteca -> Icons.Default.LibraryBooks
                    AppTab.EducacionFisica -> Icons.Default.Sports
                    AppTab.Backups -> Icons.Default.Backup
                    AppTab.Ajustes -> Icons.Default.Settings
                }
                SidebarNavItem(
                    title = tab.title,
                    icon = icon,
                    isSelected = currentTab == tab,
                    isExpanded = isExpanded,
                    onClick = { onTabSelected(tab) }
                )
            }
        }

        // Bottom area: Settings & Profile
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            HorizontalDivider(
                modifier = Modifier.padding(horizontal = 16.dp),
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.1f)
            )
            
            SidebarNavItem(
                title = "Ajustes",
                icon = Icons.Default.Settings,
                isSelected = currentTab == AppTab.Ajustes,
                isExpanded = isExpanded,
                onClick = { onTabSelected(AppTab.Ajustes) }
            )
            
            SidebarUserItem(isExpanded = isExpanded)
        }
    }
}

@Composable
fun SidebarNavItem(
    title: String,
    icon: ImageVector,
    isSelected: Boolean,
    isExpanded: Boolean,
    onClick: () -> Unit
) {
    val flags = LocalUiFeatureFlags.current
    val bgColor = if (isSelected) MaterialTheme.colorScheme.primary.copy(alpha = 0.1f) else Color.Transparent
    val contentColor =
        if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(bgColor)
            .clickable(onClick = onClick)
            .heightIn(min = 44.dp)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = if (isExpanded) Arrangement.Start else Arrangement.Center
    ) {
        Icon(
            imageVector = icon,
            contentDescription = title,
            tint = contentColor,
            modifier = Modifier.size(20.dp)
        )
        
        if (flags.reduceMotion) {
            if (isExpanded) {
                Text(
                    text = title,
                    modifier = Modifier.padding(start = 12.dp),
                    style = MaterialTheme.typography.bodyMedium.copy(
                        fontWeight = if (isSelected) FontWeight.Bold else FontWeight.SemiBold,
                        color = contentColor
                    ),
                    maxLines = 1
                )
            }
        } else {
            AnimatedVisibility(
                visible = isExpanded,
                enter = fadeIn() + expandHorizontally(),
                exit = fadeOut() + shrinkHorizontally()
            ) {
                Text(
                    text = title,
                    modifier = Modifier.padding(start = 12.dp),
                    style = MaterialTheme.typography.bodyMedium.copy(
                        fontWeight = if (isSelected) FontWeight.Bold else FontWeight.SemiBold,
                        color = contentColor
                    ),
                    maxLines = 1
                )
            }
        }
    }
}

@Composable
fun SidebarUserItem(isExpanded: Boolean) {
    val flags = LocalUiFeatureFlags.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = if (isExpanded) Arrangement.Start else Arrangement.Center,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 8.dp)
    ) {
        Box(
            modifier = Modifier
                .size(32.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.surfaceVariant),
            contentAlignment = Alignment.Center
        ) {
            Text(
                "MF",
                style = MaterialTheme.typography.labelSmall.copy(
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Bold
                )
            )
        }

        if (flags.reduceMotion) {
            if (isExpanded) {
                Column(modifier = Modifier.padding(start = 12.dp)) {
                    Text(
                        text = "Prof. Mario F.",
                        style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold),
                        maxLines = 1
                    )
                    Text(
                        text = "Docente Senior",
                        style = MaterialTheme.typography.labelSmall.copy(
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontSize = 10.sp
                        ),
                        maxLines = 1
                    )
                }
            }
        } else {
            AnimatedVisibility(
                visible = isExpanded,
                enter = fadeIn() + expandHorizontally(),
                exit = fadeOut() + shrinkHorizontally()
            ) {
                Column(modifier = Modifier.padding(start = 12.dp)) {
                    Text(
                        text = "Prof. Mario F.",
                        style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold),
                        maxLines = 1
                    )
                    Text(
                        text = "Docente Senior",
                        style = MaterialTheme.typography.labelSmall.copy(
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontSize = 10.sp
                        ),
                        maxLines = 1
                    )
                }
            }
        }
    }
}
