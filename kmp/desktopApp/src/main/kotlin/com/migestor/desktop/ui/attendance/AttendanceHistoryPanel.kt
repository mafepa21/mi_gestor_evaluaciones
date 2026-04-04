package com.migestor.desktop.ui.attendance

import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.migestor.shared.domain.Attendance
import com.migestor.shared.domain.Student
import com.migestor.desktop.ui.system.LocalUiFeatureFlags
import kotlinx.datetime.*
import com.migestor.desktop.ui.components.OrganicGlassCard

@Composable
fun AttendanceHistoryPanel(
    isVisible: Boolean,
    onClose: () -> Unit,
    students: List<Student>,
    history: List<Attendance>
) {
    val flags = LocalUiFeatureFlags.current
    val daysOfMonth = remember {
        val today = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
        val firstDay = LocalDate(today.year, today.month, 1)
        val lastDay = firstDay.plus(1, DateTimeUnit.MONTH).minus(1, DateTimeUnit.DAY)
        (0 until lastDay.dayOfMonth).map { firstDay.plus(it, DateTimeUnit.DAY) }
    }

    AnimatedVisibility(
        visible = isVisible,
        enter = if (flags.reduceMotion) fadeIn() else slideInHorizontally(initialOffsetX = { it }, animationSpec = tween(300)) + fadeIn(),
        exit = if (flags.reduceMotion) fadeOut() else slideOutHorizontally(targetOffsetX = { it }, animationSpec = tween(300)) + fadeOut(),
        modifier = Modifier.fillMaxHeight().fillMaxWidth(0.9f) // Mas ancho para acomodar el mes
    ) {
        // Fondo más sólido (Jobs Philosophy: formas básicas y legibilidad radical)
        OrganicGlassCard(
            cornerRadius = 0.dp,
            elevation = 16.dp, // Sombra más profunda para separación
            backgroundColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.98f), // Mucho más opaco
            borderColor = Color.Transparent, // Eliminamos borde para simplicidad
            modifier = Modifier.fillMaxSize()
        ) {
            Column(modifier = Modifier.padding(32.dp)) { // Espacio generoso (Jobs Philosophy)
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Historial del Mes",
                        fontSize = 24.sp,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary
                    )
                    IconButton(onClick = onClose) {
                        Icon(Icons.Default.Close, contentDescription = "Cerrar", tint = Color.Gray)
                    }
                }

                Spacer(modifier = Modifier.height(32.dp))

                val scrollState = rememberScrollState()

                Box(modifier = Modifier.fillMaxSize()) {
                    Column {
                        // Table Header (Dates) - Scrolleable
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .horizontalScroll(scrollState)
                                .padding(bottom = 16.dp)
                        ) {
                            Spacer(modifier = Modifier.width(180.dp)) // Espacio para nombre más ancho
                            daysOfMonth.forEach { date ->
                                Column(
                                    modifier = Modifier.width(40.dp),
                                    horizontalAlignment = Alignment.CenterHorizontally
                                ) {
                                    Text(
                                        text = date.dayOfMonth.toString(),
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = if (date.dayOfWeek == DayOfWeek.SUNDAY || date.dayOfWeek == DayOfWeek.SATURDAY) Color.Red.copy(alpha = 0.6f) else LocalContentColor.current
                                    )
                                    Text(
                                        text = date.dayOfWeek.name.take(3),
                                        fontSize = 10.sp,
                                        color = Color.Gray
                                    )
                                }
                            }
                        }

                        // No more Divider here as per Jobs Philosophy (Hierarchy through layout)
                        Spacer(modifier = Modifier.height(8.dp))

                        LazyColumn(modifier = Modifier.fillMaxSize()) {
                            items(students) { student ->
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .horizontalScroll(scrollState)
                                        .padding(vertical = 8.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(
                                        text = "${student.lastName}, ${student.firstName}",
                                        fontSize = 14.sp,
                                        modifier = Modifier.width(180.dp),
                                        maxLines = 1,
                                        fontWeight = FontWeight.Medium
                                    )

                                    daysOfMonth.forEach { date ->
                                        val record = history.find { 
                                            it.studentId == student.id && 
                                            it.date.toLocalDateTime(TimeZone.currentSystemDefault()).date == date 
                                        }
                                        Box(
                                            modifier = Modifier.width(40.dp),
                                            contentAlignment = Alignment.Center
                                        ) {
                                            if (record != null) {
                                                val status = AttendanceStatus.fromCode(record.status)
                                                Box(
                                                    modifier = Modifier
                                                        .size(28.dp)
                                                        .clip(CircleShape)
                                                        .background(status.color.copy(alpha = 0.15f)),
                                                    contentAlignment = Alignment.Center
                                                ) {
                                                    Text(
                                                        text = status.shortLabel,
                                                        fontSize = 12.sp,
                                                        fontWeight = FontWeight.ExtraBold,
                                                        color = status.color
                                                    )
                                                }
                                            } else {
                                                Box(
                                                    modifier = Modifier
                                                        .size(4.dp)
                                                        .clip(CircleShape)
                                                        .background(Color.LightGray.copy(alpha = 0.3f))
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
    }
}
