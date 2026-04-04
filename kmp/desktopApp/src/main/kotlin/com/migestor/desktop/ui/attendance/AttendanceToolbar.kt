package com.migestor.desktop.ui.attendance

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.History
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.migestor.shared.domain.SchoolClass
import kotlinx.datetime.LocalDate
import kotlinx.datetime.plus
import kotlinx.datetime.minus
import com.migestor.desktop.ui.components.OrganicGlassCard

@Composable
fun AttendanceToolbar(
    classes: List<SchoolClass>,
    selectedClass: SchoolClass?,
    onClassSelected: (Long) -> Unit,
    currentDate: LocalDate,
    onDateChanged: (LocalDate) -> Unit,
    showHistory: Boolean,
    onToggleHistory: () -> Unit,
    onMarkAllPresent: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 16.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Selector de Clase
        OrganicGlassCard(
            cornerRadius = 12.dp,
            elevation = 0.dp,
            modifier = Modifier.width(280.dp)
        ) {
            Box(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                var expanded by remember { mutableStateOf(false) }
                Text(
                    text = selectedClass?.name ?: "Seleccionar clase",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { expanded = true }
                )
                DropdownMenu(
                    expanded = expanded,
                    onDismissRequest = { expanded = false }
                ) {
                    classes.forEach { schoolClass ->
                        DropdownMenuItem(
                            text = { Text(schoolClass.name) },
                            onClick = {
                                onClassSelected(schoolClass.id)
                                expanded = false
                            }
                        )
                    }
                }
            }
        }

        // Selector de Fecha (Navegador)
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(horizontal = 16.dp)
        ) {
            IconButton(onClick = { onDateChanged(currentDate.minus(1, kotlinx.datetime.DateTimeUnit.DAY)) }) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Día anterior")
            }
            
            OrganicGlassCard(
                cornerRadius = 12.dp,
                elevation = 0.dp,
                modifier = Modifier.padding(horizontal = 8.dp)
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        Icons.Default.CalendarToday,
                        contentDescription = "Fecha seleccionada",
                        modifier = Modifier.size(18.dp),
                        tint = MaterialTheme.colorScheme.primary
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = currentDate.toString(), // TODO: Format date nicely
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium
                    )
                }
            }

            IconButton(onClick = { onDateChanged(currentDate.plus(1, kotlinx.datetime.DateTimeUnit.DAY)) }) {
                Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = "Día siguiente")
            }
        }

        // Botón Marcar Todos (Jobs Philosophy: Acceso rápido y obvio)
        TextButton(
            onClick = onMarkAllPresent,
            modifier = Modifier.padding(horizontal = 8.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Default.Check,
                    contentDescription = "Marcar todos presentes",
                    modifier = Modifier.size(18.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text("Presentes", fontWeight = FontWeight.SemiBold)
            }
        }

        // Botón Historial
        IconButton(
            onClick = onToggleHistory,
            modifier = Modifier.padding(end = 8.dp)
        ) {
            Icon(
                Icons.Default.History,
                contentDescription = "Ver historial",
                tint = if (showHistory) MaterialTheme.colorScheme.primary else LocalContentColor.current
            )
        }
    }
}
