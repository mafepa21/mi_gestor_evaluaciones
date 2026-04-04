package com.migestor.desktop.ui.planner

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import com.migestor.desktop.ui.components.OrganicGlassCard
import com.migestor.shared.domain.PlanningSession
import com.migestor.shared.domain.SchoolClass
import com.migestor.shared.domain.SessionStatus
import com.migestor.shared.domain.TeachingUnit
import com.migestor.shared.viewmodel.PlannerViewModel
import com.migestor.shared.util.IsoWeekHelper
import kotlinx.datetime.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NewSessionDialog(
    state: PlannerViewModel.NewSessionState,
    groups: List<SchoolClass>,
    teachingUnits: List<TeachingUnit>,
    onSave: (PlanningSession, PlannerViewModel.QuickAdvance) -> Unit,
    onDismiss: () -> Unit
) {
    val draftBase = state.existingSession ?: state.draftSession
    var selectedGroupId by remember(state) { mutableStateOf(draftBase?.groupId ?: groups.firstOrNull()?.id) }
    
    val sessionDate = remember(state) {
        IsoWeekHelper.daysOf(state.weekNumber, state.year).getOrNull(state.dayOfWeek - 1)
    }

    var selectedUDId by remember(state, selectedGroupId, teachingUnits) {
        mutableStateOf(
            draftBase?.teachingUnitId ?: run {
                // Si no hay sesión previa, buscamos la UD activa para este grupo y fecha
                if (sessionDate != null && selectedGroupId != null) {
                    teachingUnits.find { ud ->
                        val classMatches = ud.schoolClassId == selectedGroupId || ud.groupId == selectedGroupId
                        val start = ud.startDate
                        val end = ud.endDate
                        classMatches && start != null && end != null && sessionDate >= start && sessionDate <= end
                    }?.id
                } else null
            }
        )
    }
    
    var status by remember(state) { mutableStateOf(draftBase?.status ?: SessionStatus.PLANNED) }
    
    var objectives by remember(state) { mutableStateOf(draftBase?.objectives ?: "") }
    var activities by remember(state) { mutableStateOf(draftBase?.activities ?: "") }
    var evaluation by remember(state) { mutableStateOf(draftBase?.evaluation ?: "") }

    var expandedObj by remember { mutableStateOf(true) }
    var expandedAct by remember { mutableStateOf(false) }
    var expandedEval by remember { mutableStateOf(false) }

    Dialog(onDismissRequest = onDismiss) {
        OrganicGlassCard(
            modifier = Modifier.width(600.dp).wrapContentHeight(),
            cornerRadius = 32.dp
        ) {
            Column(
                modifier = Modifier
                    .padding(32.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(24.dp)
            ) {
                
                // ── Header ───────────────────────────────────────────────────
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = if (state.existingSession == null) "Nueva Sesión" else "Editar Sesión",
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Black
                    )
                    Text(
                        text = "Define los objetivos y actividades para este periodo.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.outline
                    )
                }
                
                // ── Contexto (Grupo y UD) ────────────────────────────────────
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                    // Grupo
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        SectionLabel("Grupo")
                        var expanded by remember { mutableStateOf(false) }
                        ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
                            val selectedGroupName = groups.find { it.id == selectedGroupId }?.name ?: "Seleccionar..."
                            OutlinedTextField(
                                value = selectedGroupName,
                                onValueChange = {},
                                readOnly = true,
                                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                                modifier = Modifier.menuAnchor().fillMaxWidth(),
                                shape = RoundedCornerShape(16.dp),
                                colors = OutlinedTextFieldDefaults.colors(
                                    unfocusedBorderColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)
                                )
                            )
                            ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                                groups.forEach { group ->
                                    DropdownMenuItem(
                                        text = { Text(group.name) },
                                        onClick = { selectedGroupId = group.id; expanded = false }
                                    )
                                }
                            }
                        }
                    }

                    // UD
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        SectionLabel("Unidad Didáctica")
                        var expanded by remember { mutableStateOf(false) }
                        ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
                            val selectedUDName = teachingUnits.find { it.id == selectedUDId }?.name ?: "Seleccionar..."
                            OutlinedTextField(
                                value = selectedUDName,
                                onValueChange = {},
                                readOnly = true,
                                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                                modifier = Modifier.menuAnchor().fillMaxWidth(),
                                shape = RoundedCornerShape(16.dp),
                                colors = OutlinedTextFieldDefaults.colors(
                                    unfocusedBorderColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)
                                )
                            )
                            ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                                teachingUnits.forEach { ud ->
                                    DropdownMenuItem(
                                        text = { Text(ud.name) },
                                        onClick = { selectedUDId = ud.id; expanded = false }
                                    )
                                }
                            }
                        }
                    }
                }

                // ── Estado ────────────────────────────────────────────────────
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SectionLabel("Estado de la sesión")
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        SessionStatus.values().forEach { s ->
                            val isSelected = status == s
                            Surface(
                                onClick = { status = s },
                                shape = RoundedCornerShape(12.dp),
                                color = if (isSelected) s.colorHex.hexToColor().copy(alpha = 0.12f) else Color.Transparent,
                                border = BorderStroke(
                                    width = 1.dp,
                                    color = if (isSelected) s.colorHex.hexToColor() else MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)
                                )
                            ) {
                                Text(
                                    text = s.label,
                                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                                    style = MaterialTheme.typography.labelLarge,
                                    color = if (isSelected) s.colorHex.hexToColor() else MaterialTheme.colorScheme.outline,
                                    fontWeight = if (isSelected) FontWeight.Black else FontWeight.Medium
                                )
                            }
                        }
                    }
                }

                // ── Secciones de Contenido ─────────────────────────────────────
                Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    CollapsibleSection("OBJETIVOS", expandedObj, { expandedObj = !expandedObj }) {
                        OutlinedTextField(
                            value = objectives,
                            onValueChange = { objectives = it },
                            modifier = Modifier.fillMaxWidth().height(100.dp),
                            placeholder = { Text("¿Qué queremos conseguir hoy?") },
                            shape = RoundedCornerShape(16.dp)
                        )
                    }

                    CollapsibleSection("ACTIVIDADES", expandedAct, { expandedAct = !expandedAct }) {
                        OutlinedTextField(
                            value = activities,
                            onValueChange = { activities = it },
                            modifier = Modifier.fillMaxWidth().height(140.dp),
                            placeholder = { Text("Calentamiento, parte principal, vuelta a la calma...") },
                            shape = RoundedCornerShape(16.dp)
                        )
                    }

                    CollapsibleSection("EVALUACIÓN", expandedEval, { expandedEval = !expandedEval }) {
                        OutlinedTextField(
                            value = evaluation,
                            onValueChange = { evaluation = it },
                            modifier = Modifier.fillMaxWidth().height(100.dp),
                            placeholder = { Text("Instrumentos, criterios...") },
                            shape = RoundedCornerShape(16.dp)
                        )
                    }
                }

                // ── Footer ───────────────────────────────────────────────────
                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
                    horizontalArrangement = Arrangement.End,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    TextButton(
                        onClick = onDismiss,
                        modifier = Modifier.padding(end = 16.dp)
                    ) {
                        Text("Cancelar", style = MaterialTheme.typography.labelLarge)
                    }
                    
                    fun save(advance: PlannerViewModel.QuickAdvance) {
                        val selectedGroup = groups.find { it.id == selectedGroupId } ?: return
                        val selectedUD = teachingUnits.find { it.id == selectedUDId } ?: return
                        onSave(
                            PlanningSession(
                                id = state.existingSession?.id ?: 0,
                                dayOfWeek = state.dayOfWeek,
                                period = state.period,
                                weekNumber = state.weekNumber,
                                year = state.year,
                                groupId = selectedGroup.id,
                                groupName = selectedGroup.name,
                                teachingUnitId = selectedUD.id,
                                teachingUnitName = selectedUD.name,
                                teachingUnitColor = selectedUD.colorHex,
                                status = status,
                                objectives = objectives,
                                activities = activities,
                                evaluation = evaluation
                            ),
                            advance
                        )
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = { save(PlannerViewModel.QuickAdvance.NONE) },
                            modifier = Modifier.height(48.dp),
                            shape = RoundedCornerShape(24.dp),
                            elevation = ButtonDefaults.buttonElevation(0.dp)
                        ) {
                            Text("Guardar", fontWeight = FontWeight.Bold)
                        }
                        OutlinedButton(
                            onClick = { save(PlannerViewModel.QuickAdvance.NEXT_SLOT) },
                            modifier = Modifier.height(48.dp),
                            shape = RoundedCornerShape(24.dp)
                        ) {
                            Text("Guardar + franja")
                        }
                        OutlinedButton(
                            onClick = { save(PlannerViewModel.QuickAdvance.NEXT_DAY) },
                            modifier = Modifier.height(48.dp),
                            shape = RoundedCornerShape(24.dp)
                        ) {
                            Text("Guardar + día")
                        }
                    }
                }
            }
        }
    }
}
