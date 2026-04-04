package com.migestor.desktop.ui.planner

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material.icons.automirrored.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.BorderStroke
import androidx.compose.ui.window.Dialog
import com.migestor.desktop.ui.components.OrganicGlassCard
import com.migestor.desktop.ui.system.LocalUiFeatureFlags
import com.migestor.shared.domain.SchoolClass
import com.migestor.shared.viewmodel.PlannerViewModel

// ── Helpers ──────────────────────────────────────────────────────────────────

@Composable
fun CollapsibleSection(
    title: String, 
    expanded: Boolean, 
    onToggle: () -> Unit, 
    content: @Composable ColumnScope.() -> Unit
) {
    Column {
        Row(
            modifier = Modifier.fillMaxWidth().clickable { onToggle() }.padding(vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(title, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
            Icon(
                if (expanded) Icons.Rounded.KeyboardArrowUp else Icons.Rounded.KeyboardArrowDown,
                contentDescription = if (expanded) "Contraer sección" else "Expandir sección",
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        AnimatedVisibility(visible = expanded) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) { content() }
        }
    }
}

@Composable
fun SectionLabel(text: String) {
    Text(
        text = text.uppercase(),
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.outline,
        letterSpacing = 1.sp
    )
}

@Composable
fun PlannerTabs(activeTab: PlannerViewModel.PlannerTab, onTabSelected: (PlannerViewModel.PlannerTab) -> Unit) {
    val tabs = listOf(
        PlannerViewModel.PlannerTab.WEEK to "Semana", 
        PlannerViewModel.PlannerTab.TIMELINE to "Timeline",
        PlannerViewModel.PlannerTab.DAY to "Hoy"
    )
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.Start,
        verticalAlignment = Alignment.CenterVertically
    ) {
        tabs.forEach { (tab, label) ->
            val isSelected = activeTab == tab
            Surface(
                onClick = { onTabSelected(tab) },
                shape = RoundedCornerShape(16.dp),
                color = if (isSelected) MaterialTheme.colorScheme.primaryContainer else Color.Transparent,
                modifier = Modifier
                    .padding(end = 8.dp)
                    .heightIn(min = 44.dp)
            ) {
                Text(
                    text = label,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium,
                    color = if (isSelected) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.outline
                )
            }
        }
    }
}

@Composable
fun PlannerHeader(
    weekLabel: String, 
    dateRange: String,
    onPrev: () -> Unit, 
    onNext: () -> Unit, 
    onOpenUDs: () -> Unit,
    onOpenSchedule: () -> Unit
) {
    val flags = LocalUiFeatureFlags.current
    val showMoreMenu = remember { mutableStateOf(false) }
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 24.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Título de la Semana (Acción principal de contexto)
        Row(
            modifier = Modifier.weight(1f),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Start
        ) {
            Column {
                Text(
                    text = weekLabel, 
                    style = MaterialTheme.typography.headlineLarge,
                    fontWeight = FontWeight.ExtraBold,
                    letterSpacing = (-1).sp
                )
                if (dateRange.isNotEmpty()) {
                    Text(
                        text = dateRange,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(start = 2.dp)
                    )
                }
            }
            Spacer(Modifier.width(16.dp))
            IconButton(onClick = onPrev, modifier = Modifier.size(44.dp)) { Icon(Icons.Rounded.ChevronLeft, "Semana anterior") }
            IconButton(onClick = onNext, modifier = Modifier.size(44.dp)) { Icon(Icons.Rounded.ChevronRight, "Semana siguiente") }
        }
        
        // Acciones Secundarias (Sutiles, alineadas a la derecha)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(
                onClick = onOpenUDs, 
                shape = RoundedCornerShape(16.dp),
                modifier = Modifier.heightIn(min = 44.dp),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
            ) {
                Icon(Icons.AutoMirrored.Rounded.MenuBook, "Abrir unidades didácticas", modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Unidades", style = MaterialTheme.typography.labelLarge)
            }

            if (!flags.notebookToolbarSimplified) {
                OutlinedButton(
                    onClick = onOpenSchedule,
                    shape = RoundedCornerShape(16.dp),
                    modifier = Modifier.heightIn(min = 44.dp),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
                ) {
                    Icon(Icons.Rounded.CalendarMonth, "Configurar horario", modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Horario", style = MaterialTheme.typography.labelLarge)
                }
            } else {
                Box {
                    IconButton(
                        onClick = { showMoreMenu.value = true },
                        modifier = Modifier.size(44.dp)
                    ) {
                        Icon(Icons.Rounded.MoreVert, "Más acciones de planificación")
                    }
                    DropdownMenu(
                        expanded = showMoreMenu.value,
                        onDismissRequest = { showMoreMenu.value = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text("Configurar horario") },
                            leadingIcon = { Icon(Icons.Rounded.CalendarMonth, contentDescription = null) },
                            onClick = {
                                showMoreMenu.value = false
                                onOpenSchedule()
                            }
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun EmptyDetailPlaceholder() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text("Selecciona una sesión para ver los detalles", color = MaterialTheme.colorScheme.outline)
    }
}


@Composable
fun ClassSelectorDialog(
    classes: List<SchoolClass>,
    onClassSelected: (SchoolClass) -> Unit,
    onDismiss: () -> Unit
) {
    Dialog(onDismissRequest = onDismiss) {
        OrganicGlassCard(
            modifier = Modifier.width(450.dp).wrapContentHeight(),
            cornerRadius = 32.dp
        ) {
            Column(
                modifier = Modifier.padding(32.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp)
            ) {
                // ── Header ───────────────────────────────────────────────────
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = "Seleccionar Grupo", 
                        style = MaterialTheme.typography.headlineSmall, 
                        fontWeight = FontWeight.Black
                    )
                    Text(
                        text = "Escoge el grupo para configurar su horario.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.outline
                    )
                }

                // ── List ─────────────────────────────────────────────────────
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (classes.isEmpty()) {
                        Surface(
                            modifier = Modifier.fillMaxWidth(),
                            color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f),
                            shape = RoundedCornerShape(16.dp)
                        ) {
                            Text(
                                "No hay grupos disponibles.", 
                                modifier = Modifier.padding(24.dp),
                                style = MaterialTheme.typography.bodyMedium,
                                textAlign = TextAlign.Center,
                                color = MaterialTheme.colorScheme.outline
                            )
                        }
                    } else {
                        LazyColumn(
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.heightIn(max = 300.dp)
                        ) {
                            items(classes) { schoolClass ->
                                Surface(
                                    onClick = { onClassSelected(schoolClass) },
                                    shape = RoundedCornerShape(16.dp),
                                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.1f),
                                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f))
                                ) {
                                    Row(
                                        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 16.dp),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Icon(
                                            Icons.Rounded.Groups, 
                                            null, 
                                            modifier = Modifier.size(20.dp),
                                            tint = MaterialTheme.colorScheme.primary
                                        )
                                        Spacer(Modifier.width(16.dp))
                                        Text(
                                            text = schoolClass.name,
                                            style = MaterialTheme.typography.titleMedium,
                                            fontWeight = FontWeight.Bold
                                        )
                                        Spacer(Modifier.weight(1f))
                                        Icon(
                                            Icons.Rounded.ChevronRight, 
                                            null, 
                                            modifier = Modifier.size(20.dp),
                                            tint = MaterialTheme.colorScheme.outline.copy(alpha = 0.5f)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Footer ───────────────────────────────────────────────────
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = onDismiss) { 
                        Text("Cancelar", style = MaterialTheme.typography.labelLarge) 
                    }
                }
            }
        }
    }
}

// ── Color Parsing Utility ────────────────────────────────────────────────────

fun String.hexToColor(): Color {
    return try {
        val hex = this.removePrefix("#")
        if (hex.length == 6) {
            Color(hex.toLong(16) or 0xFF000000)
        } else if (hex.length == 8) {
            Color(hex.toLong(16))
        } else {
            Color.Gray
        }
    } catch (e: Exception) {
        Color.Gray
    }
}
