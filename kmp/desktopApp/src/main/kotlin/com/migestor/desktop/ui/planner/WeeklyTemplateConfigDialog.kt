package com.migestor.desktop.ui.planner

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.migestor.shared.domain.WeeklySlotTemplate
import com.migestor.shared.domain.SchoolClass

import androidx.compose.ui.window.Dialog
import com.migestor.desktop.ui.components.OrganicGlassCard
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.BorderStroke

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WeeklyTemplateConfigDialog(
    schoolClass: SchoolClass,
    slots: List<WeeklySlotTemplate>,
    onSaveSlot: (WeeklySlotTemplate) -> Unit,
    onDeleteSlot: (Long) -> Unit,
    onDismiss: () -> Unit
) {
    var showAddSlot by remember { mutableStateOf(false) }

    Dialog(onDismissRequest = onDismiss) {
        OrganicGlassCard(
            modifier = Modifier.width(550.dp).wrapContentHeight(),
            cornerRadius = 32.dp
        ) {
            Column(
                modifier = Modifier.padding(32.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp)
            ) {
                // ── Header ───────────────────────────────────────────────────
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = "Horario Semanal",
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Black
                    )
                    Text(
                        text = schoolClass.name,
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.Bold
                    )
                }

                // ── Content ──────────────────────────────────────────────────
                Column(
                    modifier = Modifier.weight(1f, fill = false),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    if (slots.isEmpty() && !showAddSlot) {
                        Surface(
                            modifier = Modifier.fillMaxWidth(),
                            color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f),
                            shape = RoundedCornerShape(16.dp)
                        ) {
                            Text(
                                "No hay franjas configuradas para este grupo.", 
                                style = MaterialTheme.typography.bodyMedium,
                                modifier = Modifier.padding(24.dp),
                                color = MaterialTheme.colorScheme.outline
                            )
                        }
                    } else {
                        LazyColumn(
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                            modifier = Modifier.heightIn(max = 400.dp)
                        ) {
                            items(slots.sortedBy { it.dayOfWeek * 10000 + (it.startTime.replace(":", "").trim().toIntOrNull() ?: 0) }) { slot ->
                                SlotItem(slot, onDeleteSlot)
                            }
                        }
                    }

                    if (showAddSlot) {
                        AddSlotForm(
                            schoolClassId = schoolClass.id,
                            existingSlots = slots,
                            onAdd = { 
                                onSaveSlot(it)
                                showAddSlot = false
                            },
                            onCancel = { showAddSlot = false }
                        )
                    } else {
                        Button(
                            onClick = { showAddSlot = true },
                            modifier = Modifier.height(48.dp).fillMaxWidth(),
                            shape = RoundedCornerShape(24.dp),
                            elevation = ButtonDefaults.buttonElevation(0.dp)
                        ) {
                            Icon(Icons.Rounded.Add, null, modifier = Modifier.size(20.dp))
                            Spacer(Modifier.width(12.dp))
                            Text("Añadir Franja Horaria", fontWeight = FontWeight.Bold)
                        }
                    }
                }

                // ── Footer ───────────────────────────────────────────────────
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TextButton(
                        onClick = onDismiss,
                        shape = RoundedCornerShape(12.dp)
                    ) { 
                        Text("Cerrar", style = MaterialTheme.typography.labelLarge) 
                    }
                }
            }
        }
    }
}

@Composable
fun SlotItem(slot: WeeklySlotTemplate, onDelete: (Long) -> Unit) {
    val days = listOf("Lunes", "Martes", "Miércoles", "Jueves", "Viernes")
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.2f),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f))
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = days.getOrElse(slot.dayOfWeek - 1) { "Día ${slot.dayOfWeek}" }, 
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Black
                )
                Text(
                    text = "${slot.startTime} - ${slot.endTime}", 
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Medium
                )
            }
            IconButton(
                onClick = { onDelete(slot.id) },
                colors = IconButtonDefaults.iconButtonColors(
                    contentColor = MaterialTheme.colorScheme.error.copy(alpha = 0.7f)
                )
            ) {
                Icon(Icons.Rounded.Delete, null, modifier = Modifier.size(20.dp))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddSlotForm(schoolClassId: Long, onAdd: (WeeklySlotTemplate) -> Unit, onCancel: () -> Unit) {
    AddSlotForm(
        schoolClassId = schoolClassId,
        existingSlots = emptyList(),
        onAdd = onAdd,
        onCancel = onCancel
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddSlotForm(
    schoolClassId: Long,
    existingSlots: List<WeeklySlotTemplate>,
    onAdd: (WeeklySlotTemplate) -> Unit,
    onCancel: () -> Unit
) {
    var dayOfWeek by remember { mutableStateOf(1) }
    var startTime by remember { mutableStateOf("08:00") }
    var endTime by remember { mutableStateOf("09:00") }
    val hhmmRegex = remember { Regex("^([01]\\d|2[0-3]):[0-5]\\d$") }
    val duplicate = remember(dayOfWeek, startTime, existingSlots) {
        existingSlots.any { it.dayOfWeek == dayOfWeek && it.startTime == startTime.trim() }
    }
    val isTimeValid = hhmmRegex.matches(startTime.trim()) && hhmmRegex.matches(endTime.trim())
    val isRangeValid = startTime.trim() < endTime.trim()
    val canSave = isTimeValid && isRangeValid && !duplicate

    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.1f),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.2f))
    ) {
        Column(modifier = Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Text("Nueva Franja", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Día de la semana", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.outline)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    (1..5).forEach { d ->
                        val isSelected = dayOfWeek == d
                        Surface(
                            onClick = { dayOfWeek = d },
                            shape = RoundedCornerShape(10.dp),
                            color = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surface,
                            border = BorderStroke(1.dp, if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant)
                        ) {
                            Box(modifier = Modifier.size(40.dp), contentAlignment = Alignment.Center) {
                                Text(
                                    text = d.toDayInitial(),
                                    color = if (isSelected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface,
                                    fontWeight = if (isSelected) FontWeight.Black else FontWeight.Medium
                                )
                            }
                        }
                    }
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                OutlinedTextField(
                    value = startTime, 
                    onValueChange = { startTime = it }, 
                    label = { Text("Inicio") },
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(12.dp),
                    placeholder = { Text("08:00") }
                )
                OutlinedTextField(
                    value = endTime, 
                    onValueChange = { endTime = it }, 
                    label = { Text("Fin") },
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(12.dp),
                    placeholder = { Text("09:00") }
                )
            }

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.align(Alignment.End)) {
                TextButton(onClick = onCancel) { Text("Cancelar") }
                Button(
                    onClick = {
                        onAdd(WeeklySlotTemplate(
                            schoolClassId = schoolClassId,
                            dayOfWeek = dayOfWeek,
                            startTime = startTime.trim(),
                            endTime = endTime.trim()
                        ))
                    },
                    shape = RoundedCornerShape(16.dp),
                    enabled = canSave
                ) { Text("Guardar Franja") }
            }
            if (!isTimeValid) {
                Text("Formato inválido. Usa HH:MM.", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelSmall)
            } else if (!isRangeValid) {
                Text("La hora de fin debe ser mayor que inicio.", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelSmall)
            } else if (duplicate) {
                Text("Ya existe una franja para ese día y hora de inicio.", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelSmall)
            }
        }
    }
}

private fun Int.toDayInitial() = when(this) {
    1 -> "L"
    2 -> "M"
    3 -> "X"
    4 -> "J"
    5 -> "V"
    else -> "?"
}
