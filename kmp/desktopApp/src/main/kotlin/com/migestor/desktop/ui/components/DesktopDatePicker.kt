package com.migestor.desktop.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import kotlinx.datetime.*
import com.migestor.shared.util.IsoWeekHelper

@Composable
fun DesktopDatePickerDialog(
    initialDate: LocalDate? = null,
    onDateSelected: (LocalDate) -> Unit,
    onDismiss: () -> Unit
) {
    var currentMonth by remember { 
        mutableStateOf(initialDate?.let { it.year to it.month } ?: (Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date.let { it.year to it.month })) 
    }
    
    val daysInMonth = getDaysInMonth(currentMonth.first, currentMonth.second)
    val firstDayOfWeek = LocalDate(currentMonth.first, currentMonth.second, 1).dayOfWeek.isoDayNumber // 1=Mon, 7=Sun

    Dialog(onDismissRequest = onDismiss) {
        Surface(
            shape = RoundedCornerShape(24.dp),
            color = MaterialTheme.colorScheme.surface,
            tonalElevation = 6.dp,
            modifier = Modifier.width(360.dp).wrapContentHeight()
        ) {
            Column(
                modifier = Modifier.padding(24.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                // Header (Month/Year selection)
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(onClick = {
                        val newMonth = if (currentMonth.second == Month.JANUARY) {
                            (currentMonth.first - 1) to Month.DECEMBER
                        } else {
                            currentMonth.first to Month.values()[currentMonth.second.ordinal - 1]
                        }
                        currentMonth = newMonth
                    }) {
                        Icon(Icons.Rounded.ChevronLeft, "Mes anterior")
                    }
                    
                    Text(
                        text = "${currentMonth.second.name.lowercase().replaceFirstChar { it.uppercase() }} ${currentMonth.first}",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                    
                    IconButton(onClick = {
                        val newMonth = if (currentMonth.second == Month.DECEMBER) {
                            (currentMonth.first + 1) to Month.JANUARY
                        } else {
                            currentMonth.first to Month.values()[currentMonth.second.ordinal + 1]
                        }
                        currentMonth = newMonth
                    }) {
                        Icon(Icons.Rounded.ChevronRight, "Mes siguiente")
                    }
                }

                // Days of week header
                Row(modifier = Modifier.fillMaxWidth()) {
                    listOf("L", "M", "X", "J", "V", "S", "D").forEach { day ->
                        Text(
                            text = day,
                            modifier = Modifier.weight(1f),
                            textAlign = TextAlign.Center,
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.outline,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }

                // Calendar Grid
                LazyVerticalGrid(
                    columns = GridCells.Fixed(7),
                    modifier = Modifier.height(240.dp),
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    // Empty spaces for first week
                    items(firstDayOfWeek - 1) { Spacer(Modifier.size(40.dp)) }
                    
                    // Days of month
                    items(daysInMonth) { day ->
                        val date = LocalDate(currentMonth.first, currentMonth.second, day + 1)
                        val isSelected = date == initialDate
                        val isToday = date == Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
                        
                        Box(
                            modifier = Modifier
                                .aspectRatio(1f)
                                .clip(CircleShape)
                                .background(
                                    when {
                                        isSelected -> MaterialTheme.colorScheme.primary
                                        else -> Color.Transparent
                                    }
                                )
                                .clickable { 
                                    onDateSelected(date)
                                    onDismiss()
                                },
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = (day + 1).toString(),
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = if (isSelected || isToday) FontWeight.Bold else FontWeight.Normal,
                                color = when {
                                    isSelected -> MaterialTheme.colorScheme.onPrimary
                                    isToday -> MaterialTheme.colorScheme.primary
                                    else -> MaterialTheme.colorScheme.onSurface
                                }
                            )
                        }
                    }
                }
                
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End
                ) {
                    TextButton(onClick = onDismiss) {
                        Text("Cancelar")
                    }
                }
            }
        }
    }
}

private fun getDaysInMonth(year: Int, month: Month): Int {
    return when (month) {
        Month.FEBRUARY -> if (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) 29 else 28
        Month.APRIL, Month.JUNE, Month.SEPTEMBER, Month.NOVEMBER -> 30
        else -> 31
    }
}
