package com.migestor.desktop.ui.planner

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.BorderStroke
import androidx.compose.ui.window.Dialog
import com.migestor.desktop.ui.components.OrganicGlassCard
import com.migestor.desktop.ui.components.DesktopDatePickerDialog
import com.migestor.shared.domain.SchoolClass
import com.migestor.shared.domain.TeachingUnit
import com.migestor.shared.domain.TeachingUnitSchedule
import kotlinx.datetime.*

@Composable
fun UDManagerSlideOver(
    units: List<TeachingUnit>,
    groups: List<SchoolClass>,
    onSave: (TeachingUnit) -> Unit,
    onDelete: (Long) -> Unit,
    onGenerateSessions: (TeachingUnit, TeachingUnitSchedule) -> Unit,
    onClose: () -> Unit
) {
    var searchQuery by remember { mutableStateOf("") }
    val filteredUnits = units.filter { it.name.contains(searchQuery, ignoreCase = true) }
    var unitToGenerate by remember { mutableStateOf<TeachingUnit?>(null) }

    Surface(
        modifier = Modifier
            .fillMaxHeight()
            .width(520.dp),
        color = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(topStart = 32.dp, bottomStart = 32.dp),
        tonalElevation = 8.dp,
        shadowElevation = 24.dp
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(40.dp),
            verticalArrangement = Arrangement.spacedBy(48.dp)
        ) {
            // ── Header ───────────────────────────────────────────────────────
            item {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            text = "Planificación", 
                            style = MaterialTheme.typography.labelSmall, 
                            fontWeight = FontWeight.Black,
                            color = MaterialTheme.colorScheme.primary,
                            letterSpacing = 1.2.sp
                        )
                        Text(
                            text = "Unidades Didácticas", 
                            style = MaterialTheme.typography.headlineMedium, 
                            fontWeight = FontWeight.Black,
                            letterSpacing = (-0.5).sp
                        )
                    }
                    IconButton(
                        onClick = onClose,
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
                    ) { 
                        Icon(Icons.Rounded.Close, null, modifier = Modifier.size(20.dp)) 
                    }
                }
            }

            // ── Formulario de Nueva UD ───────────────────────────────────────
            item {
                UDForm(groups = groups, onSave = onSave)
            }

            // ── Buscador y Lista ─────────────────────────────────────────────
            item {
                Column(verticalArrangement = Arrangement.spacedBy(24.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.Bottom
                    ) {
                        Text(
                            text = "MIS UNIDADES", 
                            style = MaterialTheme.typography.labelSmall, 
                            fontWeight = FontWeight.Black,
                            color = MaterialTheme.colorScheme.outline,
                            letterSpacing = 1.sp
                        )
                        Text(
                            text = "${units.size} total",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.6f)
                        )
                    }
                    
                    OutlinedTextField(
                        value = searchQuery,
                        onValueChange = { searchQuery = it },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("Buscar unidad por nombre...") },
                        leadingIcon = { Icon(Icons.Rounded.Search, null, modifier = Modifier.size(20.dp)) },
                        shape = RoundedCornerShape(20.dp),
                        colors = OutlinedTextFieldDefaults.colors(
                            unfocusedBorderColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f),
                            focusedBorderColor = MaterialTheme.colorScheme.primary
                        )
                    )
                }
            }

            if (filteredUnits.isEmpty()) {
                item {
                    Box(Modifier.fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) {
                        Text(
                            "No se encontraron unidades", 
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.outline
                        )
                    }
                }
            } else {
                items(filteredUnits) { unit ->
                    UDListItem(
                        unit = unit, 
                        onDelete = { onDelete(unit.id) },
                        onGenerateRequest = { unitToGenerate = unit }
                    )
                }
            }
            
            // Espacio final para que el scroll no quede pegado abajo
            item { Spacer(Modifier.height(40.dp)) }
        }

        unitToGenerate?.let { unit ->
            GenSessionsDialog(
                unit = unit,
                groups = groups,
                onConfirm = { schedule ->
                    onGenerateSessions(unit, schedule)
                    unitToGenerate = null
                },
                onDismiss = { unitToGenerate = null }
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UDForm(groups: List<SchoolClass>, onSave: (TeachingUnit) -> Unit) {
    var name by remember { mutableStateOf("") }
    var color by remember { mutableStateOf("#4A90D9") }
    var selectedGroupId by remember { mutableStateOf<Long?>(null) }
    var startDateStr by remember { mutableStateOf("") }
    var endDateStr by remember { mutableStateOf("") }
    
    var showStartDatePicker by remember { mutableStateOf(false) }
    var showEndDatePicker by remember { mutableStateOf(false) }
    
    val colors = listOf("#4A90D9", "#E67E22", "#27AE60", "#9B59B6", "#E74C3C", "#F1C40F")

    // Contenedor principal del formulario con radio concéntrico (32dp exterior -> 24dp interno)
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.15f),
        shape = RoundedCornerShape(24.dp),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.2f))
    ) {
        Column(modifier = Modifier.padding(32.dp), verticalArrangement = Arrangement.spacedBy(32.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    "NUEVA UNIDAD", 
                    style = MaterialTheme.typography.labelSmall, 
                    fontWeight = FontWeight.Black,
                    color = MaterialTheme.colorScheme.primary,
                    letterSpacing = 0.5.sp
                )
                
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    placeholder = { Text("Nombre de la Unidad (ej: Atletismo)") },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(16.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        unfocusedBorderColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f),
                        unfocusedContainerColor = MaterialTheme.colorScheme.surface,
                        focusedContainerColor = MaterialTheme.colorScheme.surface
                    )
                )
            }

            // Planificación Automática (Opcional)
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text(
                    "CONFIGURACIÓN DE GRUPO", 
                    style = MaterialTheme.typography.labelSmall, 
                    fontWeight = FontWeight.Black,
                    color = MaterialTheme.colorScheme.outline
                )
                
                // Selector de Grupo
                var expanded by remember { mutableStateOf(false) }
                ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
                    val selectedGroupName = groups.find { it.id == selectedGroupId }?.name ?: "Vincular a un grupo..."
                    OutlinedTextField(
                        value = selectedGroupName,
                        onValueChange = {},
                        readOnly = true,
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                        modifier = Modifier.menuAnchor().fillMaxWidth(),
                        shape = RoundedCornerShape(16.dp),
                        colors = OutlinedTextFieldDefaults.colors(
                            unfocusedBorderColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f),
                            unfocusedContainerColor = MaterialTheme.colorScheme.surface,
                            focusedContainerColor = MaterialTheme.colorScheme.surface
                        )
                    )
                    ExposedDropdownMenu(
                        expanded = expanded, 
                        onDismissRequest = { expanded = false },
                        modifier = Modifier.background(MaterialTheme.colorScheme.surface)
                    ) {
                        DropdownMenuItem(
                            text = { Text("Ninguno (General)") },
                            onClick = { selectedGroupId = null; expanded = false }
                        )
                        groups.forEach { group ->
                            DropdownMenuItem(
                                text = { Text(group.name) },
                                onClick = { selectedGroupId = group.id; expanded = false }
                            )
                        }
                    }
                }

                // Rango de Fechas
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    OutlinedTextField(
                        value = startDateStr,
                        onValueChange = { },
                        readOnly = true,
                        label = { Text("Inicio") },
                        placeholder = { Text("YYYY-MM-DD") },
                        modifier = Modifier.weight(1f).clickable { showStartDatePicker = true },
                        shape = RoundedCornerShape(16.dp),
                        colors = OutlinedTextFieldDefaults.colors(
                            unfocusedBorderColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f),
                            unfocusedContainerColor = MaterialTheme.colorScheme.surface,
                            focusedContainerColor = MaterialTheme.colorScheme.surface
                        ),
                        interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
                            .also { interactionSource ->
                                LaunchedEffect(interactionSource) {
                                    interactionSource.interactions.collect {
                                        if (it is androidx.compose.foundation.interaction.PressInteraction.Release) {
                                            showStartDatePicker = true
                                        }
                                    }
                                }
                            }
                    )
                    OutlinedTextField(
                        value = endDateStr,
                        onValueChange = { },
                        readOnly = true,
                        label = { Text("Fin") },
                        placeholder = { Text("YYYY-MM-DD") },
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(16.dp),
                        colors = OutlinedTextFieldDefaults.colors(
                            unfocusedBorderColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f),
                            unfocusedContainerColor = MaterialTheme.colorScheme.surface,
                            focusedContainerColor = MaterialTheme.colorScheme.surface
                        ),
                        interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
                            .also { interactionSource ->
                                LaunchedEffect(interactionSource) {
                                    interactionSource.interactions.collect {
                                        if (it is androidx.compose.foundation.interaction.PressInteraction.Release) {
                                            showEndDatePicker = true
                                        }
                                    }
                                }
                            }
                    )
                }
            }

            if (showStartDatePicker) {
                DesktopDatePickerDialog(
                    initialDate = try { LocalDate.parse(startDateStr) } catch (e: Exception) { null },
                    onDateSelected = { startDateStr = it.toString() },
                    onDismiss = { showStartDatePicker = false }
                )
            }

            if (showEndDatePicker) {
                DesktopDatePickerDialog(
                    initialDate = try { LocalDate.parse(endDateStr) } catch (e: Exception) { null },
                    onDateSelected = { endDateStr = it.toString() },
                    onDismiss = { showEndDatePicker = false }
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    "COLOR DISTINTIVO", 
                    style = MaterialTheme.typography.labelSmall, 
                    fontWeight = FontWeight.Black,
                    color = MaterialTheme.colorScheme.outline
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(12.dp), 
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    colors.forEach { hex ->
                        val isSelected = color == hex
                        Box(
                            modifier = Modifier
                                .size(32.dp)
                                .clip(CircleShape)
                                .background(hex.hexToColor())
                                .border(
                                    width = if (isSelected) 3.dp else 0.dp, 
                                    color = MaterialTheme.colorScheme.surface, 
                                    shape = CircleShape
                                )
                                .border(
                                    width = if (isSelected) 4.dp else 0.dp, 
                                    color = hex.hexToColor(), 
                                    shape = CircleShape
                                )
                                .clickable { color = hex }
                        )
                    }
                }
            }

            Button(
                onClick = {
                    if (name.isNotBlank()) {
                        val start = try { LocalDate.parse(startDateStr) } catch(e: Exception) { null }
                        val end = try { LocalDate.parse(endDateStr) } catch(e: Exception) { null }
                        
                        onSave(TeachingUnit(
                            name = name, 
                            colorHex = color,
                            schoolClassId = selectedGroupId,
                            groupId = selectedGroupId,
                            startDate = start,
                            endDate = end
                        ))
                        name = ""
                        startDateStr = ""
                        endDateStr = ""
                        selectedGroupId = null
                    }
                },
                modifier = Modifier.fillMaxWidth().height(56.dp),
                shape = RoundedCornerShape(28.dp),
                elevation = ButtonDefaults.buttonElevation(0.dp),
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary)
            ) {
                Icon(Icons.Rounded.Add, null, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(12.dp))
                Text("Crear Unidad Didáctica", fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
fun UDListItem(unit: TeachingUnit, onDelete: () -> Unit, onGenerateRequest: () -> Unit) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.05f),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.2f))
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 20.dp), 
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                Modifier
                    .size(12.dp)
                    .clip(CircleShape)
                    .background(unit.colorHex.hexToColor())
            )
            Spacer(Modifier.width(20.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = unit.name, 
                        style = MaterialTheme.typography.titleMedium, 
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    
                    // Badge de Activa
                    val today = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
                    val start = unit.startDate
                    val end = unit.endDate
                    val isActive = start != null && end != null && 
                                  today >= start && today <= end
                    
                    if (isActive) {
                        Spacer(Modifier.width(12.dp))
                        Surface(
                            color = Color(0xFF27AE60).copy(alpha = 0.1f),
                            shape = RoundedCornerShape(8.dp),
                            border = BorderStroke(1.dp, Color(0xFF27AE60).copy(alpha = 0.2f))
                        ) {
                            Text(
                                text = "ACTIVA",
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                                style = MaterialTheme.typography.labelSmall.copy(fontSize = 9.sp),
                                fontWeight = FontWeight.Black,
                                color = Color(0xFF27AE60)
                            )
                        }
                    }
                }
                Text(
                    text = if (unit.schoolClassId != null) "Vinculada a grupo" else "Unidad General", 
                    style = MaterialTheme.typography.labelSmall, 
                    color = MaterialTheme.colorScheme.outline
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onGenerateRequest) {
                    Icon(
                        imageVector = Icons.Rounded.AutoFixHigh, 
                        contentDescription = "Generar", 
                        modifier = Modifier.size(20.dp), 
                        tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.8f)
                    )
                }
                Spacer(Modifier.width(4.dp))
                IconButton(onClick = onDelete) { 
                    Icon(
                        imageVector = Icons.Rounded.DeleteOutline, 
                        contentDescription = "Eliminar", 
                        modifier = Modifier.size(20.dp), 
                        tint = MaterialTheme.colorScheme.error.copy(alpha = 0.4f)
                    ) 
                }
            }
        }
    }
}

@Composable
fun GenSessionsDialog(
    unit: TeachingUnit,
    groups: List<SchoolClass>,
    onConfirm: (TeachingUnitSchedule) -> Unit,
    onDismiss: () -> Unit
) {
    var selectedGroupId by remember(unit) { mutableStateOf(unit.schoolClassId ?: groups.firstOrNull()?.id ?: 0L) }
    var startDate by remember(unit) { 
        mutableStateOf(unit.startDate ?: Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date) 
    }
    var endDate by remember(unit) { 
        mutableStateOf(unit.endDate ?: startDate.plus(1, DateTimeUnit.MONTH)) 
    }

    // Asegurar que la fecha de fin no sea anterior a la de inicio
    LaunchedEffect(startDate) {
        if (endDate < startDate) {
            endDate = startDate.plus(1, DateTimeUnit.MONTH)
        }
    }

    var showStartDatePicker by remember { mutableStateOf(false) }
    var showEndDatePicker by remember { mutableStateOf(false) }

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
                        text = "Generar Sesiones", 
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Black
                    )
                    Text(
                        text = unit.name,
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.Bold
                    )
                }
                
                // ── Selector de Grupo ────────────────────────────────────────
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        "GRUPO DESTINO", 
                        style = MaterialTheme.typography.labelSmall, 
                        fontWeight = FontWeight.Black,
                        color = MaterialTheme.colorScheme.outline
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        groups.forEach { g ->
                            val isSelected = selectedGroupId == g.id
                            Surface(
                                onClick = { selectedGroupId = g.id },
                                shape = RoundedCornerShape(12.dp),
                                color = if (isSelected) MaterialTheme.colorScheme.primary.copy(alpha = 0.1f) else Color.Transparent,
                                border = BorderStroke(
                                    width = 1.dp,
                                    color = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)
                                )
                            ) {
                                Text(
                                    text = g.name,
                                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                                    style = MaterialTheme.typography.labelLarge,
                                    color = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline,
                                    fontWeight = if (isSelected) FontWeight.Black else FontWeight.Medium
                                )
                            }
                        }
                    }
                }

                // ── Rango de Fechas ──────────────────────────────────────────
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    OutlinedTextField(
                        value = startDate.toString(),
                        onValueChange = { },
                        readOnly = true,
                        label = { Text("Fecha Inicio") },
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(12.dp),
                        placeholder = { Text("YYYY-MM-DD") },
                        interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
                            .also { interactionSource ->
                                LaunchedEffect(interactionSource) {
                                    interactionSource.interactions.collect {
                                        if (it is androidx.compose.foundation.interaction.PressInteraction.Release) {
                                            showStartDatePicker = true
                                        }
                                    }
                                }
                            }
                    )

                    OutlinedTextField(
                        value = endDate.toString(),
                        onValueChange = { },
                        readOnly = true,
                        label = { Text("Fecha Fin") },
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(12.dp),
                        placeholder = { Text("YYYY-MM-DD") },
                        interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
                            .also { interactionSource ->
                                LaunchedEffect(interactionSource) {
                                    interactionSource.interactions.collect {
                                        if (it is androidx.compose.foundation.interaction.PressInteraction.Release) {
                                            showEndDatePicker = true
                                        }
                                    }
                                }
                            }
                    )
                }

                if (showStartDatePicker) {
                    DesktopDatePickerDialog(
                        initialDate = startDate,
                        onDateSelected = { startDate = it },
                        onDismiss = { showStartDatePicker = false }
                    )
                }

                if (showEndDatePicker) {
                    DesktopDatePickerDialog(
                        initialDate = endDate,
                        onDateSelected = { endDate = it },
                        onDismiss = { showEndDatePicker = false }
                    )
                }
                
                Surface(
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f),
                    shape = RoundedCornerShape(16.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        text = "Se crearán sesiones automáticas según el horario de este grupo.",
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.padding(16.dp),
                        color = MaterialTheme.colorScheme.outline
                    )
                }

                // ── Footer ───────────────────────────────────────────────────
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    TextButton(onClick = onDismiss) { 
                        Text("Cancelar", style = MaterialTheme.typography.labelLarge) 
                    }
                    Spacer(Modifier.width(16.dp))
                    Button(
                        onClick = {
                            onConfirm(TeachingUnitSchedule(
                                teachingUnitId = unit.id,
                                schoolClassId = selectedGroupId,
                                startDate = startDate,
                                endDate = endDate
                            ))
                        },
                        modifier = Modifier.height(48.dp),
                        shape = RoundedCornerShape(24.dp),
                        elevation = ButtonDefaults.buttonElevation(0.dp)
                    ) { 
                        Text("Generar Sesiones", fontWeight = FontWeight.Bold) 
                    }
                }
            }
        }
    }
}
