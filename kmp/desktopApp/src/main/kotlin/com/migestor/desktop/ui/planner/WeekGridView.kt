package com.migestor.desktop.ui.planner

import kotlinx.datetime.Clock
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.text.style.TextAlign
import com.migestor.desktop.ui.components.OrganicGlassCard
import com.migestor.shared.domain.PlanningSession
import com.migestor.shared.domain.SessionStatus
import com.migestor.shared.domain.TimeSlotConfig
import com.migestor.shared.domain.SchoolClass
import com.migestor.shared.util.IsoWeekHelper
import com.migestor.shared.viewmodel.PlannerViewModel

@Composable
fun WeekGridView(viewModel: PlannerViewModel) {
    val sessionsByCell by viewModel.sessionsByCell.collectAsState()
    val timeSlots = viewModel.timeSlots
    val currentWeek by viewModel.currentWeek.collectAsState()
    val currentYear by viewModel.currentYear.collectAsState()
    val selectedClass by viewModel.selectedClass.collectAsState()
    val groups by viewModel.groups.collectAsState()
    val activeUnit by viewModel.activeUnitForSelectedClass.collectAsState()
    var selectionMode by remember { mutableStateOf(false) }
    val selectedSlots = remember { mutableStateMapOf<Pair<Int, Int>, Boolean>() }
    var showCopyDialog by remember { mutableStateOf(false) }
    var shiftOffset by remember { mutableStateOf(1) }
    val fullScroll = rememberScrollState()
    
    val today = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
    
    // Obtenemos los días reales de la semana para los headers
    val daysOfCurrentWeek = IsoWeekHelper.daysOf(currentWeek, currentYear)
    val dayNames = listOf("lun", "mar", "mié", "jue", "vie")
    val accent = MaterialTheme.colorScheme.primary
    val lineColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.55f)
    val mutedText = MaterialTheme.colorScheme.onSurfaceVariant
    val todayColumnColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.08f)
    val panelColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.72f)
    val selectedSlotKeys = selectedSlots.filterValues { it }.keys

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surface)
            .verticalScroll(fullScroll)
    ) {
        // ── Título Superior (Estilo iDoceo) ────────────────────────────────
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 40.dp, vertical = 32.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (selectedClass != null) {
                    // Tarjeta del Curso Seleccionado (Status iDoceo)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Surface(
                            color = accent.copy(alpha = 0.16f),
                            shape = RoundedCornerShape(12.dp),
                            border = BorderStroke(1.dp, accent.copy(alpha = 0.35f))
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    Icons.Rounded.Groups, 
                                    null, 
                                    modifier = Modifier.size(18.dp), 
                                    tint = accent
                                )
                                Spacer(Modifier.width(8.dp))
                                Text(
                                    text = selectedClass!!.name,
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Black,
                                    color = accent
                                )
                            }
                        }
                        
                        if (activeUnit != null) {
                            Spacer(Modifier.width(12.dp))
                            Surface(
                                color = activeUnit!!.colorHex.hexToColor().copy(alpha = 0.1f),
                                shape = RoundedCornerShape(12.dp),
                                border = BorderStroke(1.dp, activeUnit!!.colorHex.hexToColor().copy(alpha = 0.4f))
                            ) {
                                Row(
                                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Box(
                                        Modifier
                                            .size(6.dp)
                                            .clip(CircleShape)
                                            .background(activeUnit!!.colorHex.hexToColor())
                                    )
                                    Spacer(Modifier.width(8.dp))
                                    Text(
                                        text = activeUnit!!.name,
                                        style = MaterialTheme.typography.labelLarge,
                                        fontWeight = FontWeight.Bold,
                                        color = activeUnit!!.colorHex.hexToColor()
                                    )
                                    Spacer(Modifier.width(8.dp))
                                    Text(
                                        text = "ACTIVA",
                                        style = MaterialTheme.typography.labelSmall.copy(fontSize = 9.sp),
                                        fontWeight = FontWeight.Black,
                                        color = activeUnit!!.colorHex.hexToColor()
                                    )
                                }
                            }
                        }
                    }
                } else {
                    Text(
                        text = "Planner General",
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.ExtraBold,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                }
                
                Text(
                    text = "$currentYear • Semana $currentWeek", 
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = mutedText
                )
            }
            
            // Toggle Día/Semana (Visual iDoceo)
            Surface(
                color = panelColor,
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier.padding(bottom = 4.dp)
            ) {
                Row(modifier = Modifier.padding(4.dp)) {
                    Text(
                        "Día", 
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp), 
                        style = MaterialTheme.typography.labelLarge,
                        color = mutedText
                    )
                    Surface(
                        color = MaterialTheme.colorScheme.surface, 
                        shape = RoundedCornerShape(8.dp), 
                        shadowElevation = 2.dp
                    ) {
                        Text(
                            "Semana", 
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp), 
                            style = MaterialTheme.typography.labelLarge, 
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                    }
                }
            }
        }

        if (selectionMode) {
            Surface(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 8.dp),
                shape = RoundedCornerShape(12.dp),
                color = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.6f)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        "Seleccionadas: ${selectedSlotKeys.size}",
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.Bold
                    )
                    Spacer(Modifier.weight(1f))
                    OutlinedButton(
                        onClick = { showCopyDialog = true },
                        enabled = selectedClass != null
                    ) { Text("Copiar a grupo…") }
                    OutlinedButton(
                        onClick = {
                            val rangeStart = daysOfCurrentWeek.firstOrNull() ?: return@OutlinedButton
                            val rangeEnd = daysOfCurrentWeek.lastOrNull() ?: return@OutlinedButton
                            val classId = selectedClass?.id ?: return@OutlinedButton
                            viewModel.shiftSessionsWithinGroup(
                                PlannerViewModel.ShiftSessionsCommand(
                                    groupId = classId,
                                    fromDate = rangeStart,
                                    toDate = rangeEnd,
                                    offsetSlots = shiftOffset,
                                    selectedSlots = selectedSlotKeys
                                )
                            )
                            selectedSlots.clear()
                        }
                    ) { Text("Mover +$shiftOffset") }
                    OutlinedButton(
                        onClick = {
                            val rangeStart = daysOfCurrentWeek.firstOrNull() ?: return@OutlinedButton
                            val rangeEnd = daysOfCurrentWeek.lastOrNull() ?: return@OutlinedButton
                            val classId = selectedClass?.id ?: return@OutlinedButton
                            viewModel.shiftSessionsWithinGroup(
                                PlannerViewModel.ShiftSessionsCommand(
                                    groupId = classId,
                                    fromDate = rangeStart,
                                    toDate = rangeEnd,
                                    offsetSlots = -shiftOffset,
                                    selectedSlots = selectedSlotKeys
                                )
                            )
                            selectedSlots.clear()
                        }
                    ) { Text("Mover -$shiftOffset") }
                    IconButton(onClick = { shiftOffset = (shiftOffset + 1).coerceAtMost(6) }) {
                        Icon(Icons.Rounded.KeyboardArrowUp, "Incrementar desplazamiento")
                    }
                    IconButton(onClick = { shiftOffset = (shiftOffset - 1).coerceAtLeast(1) }) {
                        Icon(Icons.Rounded.KeyboardArrowDown, "Reducir desplazamiento")
                    }
                    TextButton(
                        onClick = {
                            selectionMode = false
                            selectedSlots.clear()
                        }
                    ) { Text("Salir selección") }
                }
            }
        } else {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 32.dp),
                horizontalArrangement = Arrangement.End
            ) {
                OutlinedButton(onClick = { selectionMode = true }) {
                    Icon(Icons.Rounded.DoneAll, null)
                    Spacer(Modifier.width(6.dp))
                    Text("Seleccionar bloque")
                }
            }
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 32.dp, vertical = 8.dp)
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            FilterChip(
                selected = selectedClass == null,
                onClick = { viewModel.selectClass(null) },
                label = { Text("Todos") }
            )
            groups.forEach { group ->
                FilterChip(
                    selected = selectedClass?.id == group.id,
                    onClick = { viewModel.selectClass(group.id) },
                    label = { Text(group.name) }
                )
            }
        }

        // ── Cabeceras de Días ─────────────────────────────────────────────
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .drawBehind {
                    // Línea inferior de la cabecera
                    drawLine(lineColor, Offset(0f, size.height), Offset(size.width, size.height), strokeWidth = 1.dp.toPx())
                }
        ) {
            Spacer(modifier = Modifier.width(80.dp)) // Eje lateral más ancho para horas
            daysOfCurrentWeek.forEachIndexed { index, date ->
                val isToday = date == today
                val columnColor = if (isToday) todayColumnColor else Color.Transparent
                
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .background(columnColor)
                        .padding(vertical = 12.dp)
                        .drawBehind {
                            // Divisores verticales punteados
                            if (index > 0) {
                                drawLine(
                                    color = lineColor,
                                    start = Offset(0f, 0f),
                                    end = Offset(0f, size.height),
                                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(5f, 5f), 0f),
                                    strokeWidth = 1.dp.toPx()
                                )
                            }
                        },
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = date.dayOfMonth.toString(),
                        style = MaterialTheme.typography.displaySmall,
                        fontWeight = FontWeight.Bold,
                        color = if (isToday) accent else mutedText.copy(alpha = 0.85f)
                    )
                    Text(
                        text = "${dayNames[index]} ${date.dayOfMonth} ${date.month.name.lowercase().take(3)}",
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = if (isToday) accent else mutedText
                    )
                }
            }
        }

        // ── Grid de Periodos ──────────────────────────────────────────────
        Column(modifier = Modifier.fillMaxWidth()) {
            timeSlots.forEach { slot ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(220.dp)
                        .drawBehind {
                            drawLine(lineColor, Offset(0f, size.height), Offset(size.width, size.height), strokeWidth = 1.dp.toPx())
                        }
                ) {
                    Box(
                        modifier = Modifier
                            .width(80.dp)
                            .fillMaxHeight()
                            .drawBehind {
                                // Línea vertical derecha del eje temporal (sutil)
                                drawLine(lineColor.copy(alpha = 0.7f), Offset(size.width, 0f), Offset(size.width, size.height), strokeWidth = 1.dp.toPx())
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                text = slot.startTime,
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onSurface
                            )
                            Spacer(Modifier.height(4.dp))
                            Text(
                                text = slot.endTime,
                                style = MaterialTheme.typography.labelSmall,
                                color = mutedText
                            )
                            Spacer(Modifier.height(8.dp))
                            Surface(
                                color = panelColor,
                                shape = RoundedCornerShape(4.dp)
                            ) {
                                Text(
                                    text = "P${slot.period}",
                                    modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp),
                                    style = MaterialTheme.typography.labelSmall.copy(fontSize = 10.sp),
                                    fontWeight = FontWeight.Black,
                                    color = mutedText
                                )
                            }
                        }
                    }

                    // Celdas del día
                    Row(modifier = Modifier.weight(1f).fillMaxHeight()) {
                        for (day in 1..5) {
                            val cellSessions = sessionsByCell
                                .filterKeys { it.dayOfWeek == day && it.period == slot.period }
                                .values
                                .filter { selectedClass == null || it.groupId == selectedClass!!.id }
                                .sortedBy { it.groupName }
                            val isToday = daysOfCurrentWeek.getOrNull(day - 1) == today
                            
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .fillMaxHeight()
                                    .background(if (isToday) todayColumnColor.copy(alpha = 0.6f) else Color.Transparent)
                                    .drawBehind {
                                        // Divisores verticales punteados
                                        drawLine(
                                            color = lineColor,
                                            start = Offset(size.width, 0f),
                                            end = Offset(size.width, size.height),
                                            pathEffect = PathEffect.dashPathEffect(floatArrayOf(5f, 5f), 0f),
                                            strokeWidth = 1.dp.toPx()
                                        )
                                    }
                                    .padding(8.dp) // Respiro visual entre celdas
                                    .clickable { 
                                        val key = day to slot.period
                                        if (selectionMode) {
                                            selectedSlots[key] = !(selectedSlots[key] ?: false)
                                        } else {
                                            if (cellSessions.isNotEmpty()) {
                                                val session = cellSessions.first()
                                                viewModel.selectClass(session.groupId)
                                                viewModel.openNewSessionDialog(day, slot.period, session)
                                            } else {
                                                viewModel.openNewSessionDialog(day, slot.period)
                                            }
                                        }
                                    }
                            ) {
                                if (selectionMode && cellSessions.isNotEmpty()) {
                                    Checkbox(
                                        checked = selectedSlots[day to slot.period] == true,
                                        onCheckedChange = {
                                            selectedSlots[day to slot.period] = it
                                        },
                                        modifier = Modifier.align(Alignment.TopEnd)
                                    )
                                }
                                if (cellSessions.isNotEmpty()) {
                                    Column(
                                        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()),
                                        verticalArrangement = Arrangement.spacedBy(6.dp)
                                    ) {
                                        cellSessions.forEach { session ->
                                            SessionItemMinimal(
                                                session = session,
                                                startTime = slot.startTime,
                                                endTime = slot.endTime,
                                                onClick = {
                                                    viewModel.selectClass(session.groupId)
                                                    viewModel.openNewSessionDialog(day, slot.period, session)
                                                }
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (showCopyDialog && selectedClass != null) {
        CopyToGroupDialog(
            groups = groups,
            sourceGroupId = selectedClass!!.id,
            onDismiss = { showCopyDialog = false },
            onConfirm = { targetGroupId ->
                val rangeStart = daysOfCurrentWeek.firstOrNull() ?: return@CopyToGroupDialog
                val rangeEnd = daysOfCurrentWeek.lastOrNull() ?: return@CopyToGroupDialog
                viewModel.copySessionsBetweenGroups(
                    PlannerViewModel.CopySessionsCommand(
                        sourceGroupId = selectedClass!!.id,
                        targetGroupId = targetGroupId,
                        fromDate = rangeStart,
                        toDate = rangeEnd,
                        selectedSlots = selectedSlotKeys
                    )
                )
                selectedSlots.clear()
                showCopyDialog = false
            }
        )
    }
}

@Composable
private fun CopyToGroupDialog(
    groups: List<SchoolClass>,
    sourceGroupId: Long,
    onDismiss: () -> Unit,
    onConfirm: (Long) -> Unit
) {
    var selectedTargetId by remember(sourceGroupId, groups) {
        mutableStateOf(groups.firstOrNull { it.id != sourceGroupId }?.id)
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Copiar sesiones a otro grupo") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Selecciona el grupo destino. Se sobrescribirán sesiones en conflicto.")
                groups.filter { it.id != sourceGroupId }.forEach { group ->
                    Row(
                        modifier = Modifier.fillMaxWidth().clickable { selectedTargetId = group.id }.padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        RadioButton(
                            selected = selectedTargetId == group.id,
                            onClick = { selectedTargetId = group.id }
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(group.name)
                    }
                }
            }
        },
        confirmButton = {
            Button(
                onClick = { selectedTargetId?.let(onConfirm) },
                enabled = selectedTargetId != null
            ) { Text("Copiar") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancelar") }
        }
    )
}

@Composable
fun SessionItemMinimal(session: PlanningSession, startTime: String, endTime: String, onClick: () -> Unit = {}) {
    val slotColor = session.teachingUnitColor.hexToColor()
    val statusColor = session.status.colorHex.hexToColor()
    
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.78f),
        shape = RoundedCornerShape(12.dp), // Radio de Jobs
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)),
        shadowElevation = 2.dp,
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick
    ) {
        Row(modifier = Modifier.height(IntrinsicSize.Min)) {
            // Barra lateral de color (Concéntrica)
            Box(Modifier.width(6.dp).fillMaxHeight().background(slotColor))
            
            Column(modifier = Modifier.padding(12.dp)) {
                // Cabecera: Grupo e Icono de Estado
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(8.dp).clip(CircleShape).background(slotColor))
                        Spacer(Modifier.width(8.dp))
                        Text(
                            text = session.groupName,
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.Black,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                    }
                    
                    // Badge de Estado (Jobs simple)
                    Box(
                        Modifier
                            .size(8.dp)
                            .clip(CircleShape)
                            .background(statusColor)
                    )
                }

                Text(
                    text = "$startTime - $endTime",
                    style = MaterialTheme.typography.labelSmall.copy(fontSize = 11.sp),
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(top = 2.dp)
                )
                
                if (session.teachingUnitName.isNotBlank()) {
                    Text(
                        text = session.teachingUnitName,
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(top = 4.dp)
                    )
                }

                // ── Snippets (Respirando) ──────────────────────────────────
                if (session.objectives.isNotBlank()) {
                    Spacer(Modifier.height(8.dp))
                    Text(
                        text = session.objectives,
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 10.sp, lineHeight = 14.sp),
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.8f),
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                if (session.activities.isNotBlank()) {
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = session.activities,
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 10.sp, fontStyle = androidx.compose.ui.text.font.FontStyle.Italic),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}
