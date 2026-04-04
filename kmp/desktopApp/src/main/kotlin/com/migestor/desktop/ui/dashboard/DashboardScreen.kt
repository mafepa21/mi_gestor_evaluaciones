package com.migestor.desktop.ui.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AssignmentTurnedIn
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.PhoneIphone
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Rule
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.input.pointer.pointerInput
import com.migestor.data.di.KmpContainer
import com.migestor.shared.domain.CalendarEvent
import com.migestor.shared.domain.Incident
import com.migestor.shared.domain.SchoolClass
import com.migestor.shared.domain.Grade
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.datetime.Clock
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlinx.datetime.Instant
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import kotlin.math.roundToInt

@Composable
fun DashboardScreen(
    container: KmpContainer,
    scope: CoroutineScope,
    onStatus: (String) -> Unit,
    syncPayload: String? = null,
    syncHost: String? = null,
    syncPin: String? = null,
    syncServerId: String? = null,
    syncIsPaired: Boolean = false,
    onRevokeSyncPairing: (() -> Unit)? = null,
) {
    var studentCount by remember { mutableStateOf("0") }
    var classCount by remember { mutableStateOf("0") }
    var evalCount by remember { mutableStateOf("0") }
    var rubricCount by remember { mutableStateOf("0") }
    var sessionCount by remember { mutableStateOf("0") }
    
    var upcomingClasses by remember { mutableStateOf(emptyList<CalendarEvent>()) }
    var pendingTasks by remember { mutableStateOf(emptyList<Incident>()) }
    var esoPercentage by remember { mutableStateOf(0) }
    var bachPercentage by remember { mutableStateOf(0) }
    var activityGroups by remember { mutableStateOf(emptyList<Pair<String, Double>>()) }
    var pullDistancePx by remember { mutableStateOf(0f) }
    var isPullRefreshing by remember { mutableStateOf(false) }

    fun refreshStats() {
        scope.launch {
            try {
                val stats = container.dashboardRepository.getStats()
                studentCount = stats.totalStudents.toString()
                classCount = stats.totalClasses.toString()
                evalCount = stats.totalEvaluations.toString()
                rubricCount = stats.totalRubrics.toString()
                sessionCount = stats.totalSessions.toString()

                // Upcoming classes
                val now = Clock.System.now()
                val events: List<CalendarEvent> = container.calendarRepository.listEvents()
                upcomingClasses = events.filter { event -> event.startAt > now }
                    .sortedBy { event -> event.startAt }
                    .take(3)

                // Pending tasks (simulated from incidents or upcoming sessions)
                val classes: List<SchoolClass> = container.classesRepository.listClasses()
                val allIncidents = mutableListOf<Incident>()
                for (cls in classes) {
                    allIncidents.addAll(container.incidentsRepository.listIncidents(cls.id))
                }
                pendingTasks = allIncidents.take(3)

                // Distribution
                val esoCount = classes.count { cls -> cls.course <= 4 }
                val totalC = classes.size.coerceAtLeast(1)
                esoPercentage = ((esoCount.toFloat() / totalC) * 100).roundToInt()
                bachPercentage = 100 - esoPercentage

                // Activity Chart Data (averages by class)
                val chartData = mutableListOf<Pair<String, Double>>()
                val recentClasses = classes.take(6)
                for (cls in recentClasses) {
                    val grades: List<Grade> = container.gradesRepository.listGradesForClass(cls.id)
                    val avg = if (grades.isNotEmpty()) grades.mapNotNull { g -> g.value }.average() else 0.0
                    chartData.add(cls.name to avg)
                }
                activityGroups = chartData

                onStatus("Panel actualizado: ${stats.totalStudents} alumnos")
            } catch (e: Exception) {
                onStatus("Error al cargar datos: ${e.message}")
            }
        }
    }

    LaunchedEffect(Unit) {
        refreshStats()
    }

    val scrollState = rememberScrollState()

    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(scrollState)
                .pointerInput(scrollState.value) {
                    detectVerticalDragGestures(
                        onVerticalDrag = { _, dragAmount ->
                            if (scrollState.value == 0 && dragAmount > 0f) {
                                pullDistancePx += dragAmount
                            } else if (dragAmount < 0f) {
                                pullDistancePx = 0f
                            }
                        },
                        onDragEnd = {
                            if (pullDistancePx > 140f && !isPullRefreshing) {
                                isPullRefreshing = true
                                onStatus("Pull-to-refresh: sincronizando cambios...")
                                refreshStats()
                                isPullRefreshing = false
                            }
                            pullDistancePx = 0f
                        }
                    )
                }
                .padding(40.dp),
            verticalArrangement = Arrangement.spacedBy(40.dp)
        ) {
        // Welcome and Refresh
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Bottom
        ) {
            Column {
                Text(
                    text = "Bienvenido, Mario.",
                    style = MaterialTheme.typography.headlineLarge.copy(
                        fontWeight = FontWeight.ExtraBold,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Aquí tienes el resumen de tu actividad docente para hoy.",
                    style = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurfaceVariant)
                )
            }
            Button(
                onClick = { refreshStats() },
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.secondaryContainer,
                    contentColor = MaterialTheme.colorScheme.onSecondaryContainer
                ),
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier.height(48.dp)
            ) {
                Icon(imageVector = Icons.Default.Refresh, contentDescription = "Actualizar panel", modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("Refresh", fontWeight = FontWeight.Bold)
            }
        }

        if (!syncPayload.isNullOrBlank()) {
            OrganicGlassCard(
                modifier = Modifier.fillMaxWidth(),
                backgroundColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.72f),
                borderColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.55f),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(24.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(24.dp),
                ) {
                    QrCodeCanvas(
                        content = syncPayload,
                        modifier = Modifier.size(148.dp).clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.surface)
                    )
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Icon(Icons.Default.PhoneIphone, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                            Text(
                                text = "Emparejar iOS con QR",
                                style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)
                            )
                        }
                        Text(
                            text = "Escanea este código desde iOS en Inicio → Sincronización LAN.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Text(
                            text = "Host: ${syncHost ?: "-"} · PIN: ${syncPin ?: "-"}",
                            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
                            color = MaterialTheme.colorScheme.onSurface
                        )
                        Text(
                            text = "Server ID: ${syncServerId ?: "-"} · Estado: ${if (syncIsPaired) "Vinculado" else "Esperando emparejamiento"}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        SelectionContainer {
                            Text(
                                text = syncPayload,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        if (syncIsPaired && onRevokeSyncPairing != null) {
                            Button(
                                onClick = onRevokeSyncPairing,
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = MaterialTheme.colorScheme.errorContainer,
                                    contentColor = MaterialTheme.colorScheme.onErrorContainer
                                ),
                                shape = RoundedCornerShape(10.dp)
                            ) {
                                Text("Desvincular iPad")
                            }
                        }
                    }
                }
            }
        }

        // Bento Stats Grid
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            val weightModifier = Modifier.weight(1f)
            BentoStatCard(
                title = "Alumnos",
                value = studentCount,
                icon = Icons.Default.Group,
                iconColor = MaterialTheme.colorScheme.primary,
                iconBgColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.75f),
                bottomText = "+4 nuevos",
                bottomIcon = Icons.Default.TrendingUp,
                bottomTextColor = Color(0xFF33D17A),
                modifier = weightModifier
            )
            BentoStatCard(
                title = "Clases",
                value = classCount,
                icon = Icons.Default.School,
                iconColor = MaterialTheme.colorScheme.tertiary,
                iconBgColor = MaterialTheme.colorScheme.tertiaryContainer.copy(alpha = 0.75f),
                bottomText = "Activas este trimestre",
                modifier = weightModifier
            )
            BentoStatCard(
                title = "Evaluaciones",
                value = evalCount,
                icon = Icons.Default.AssignmentTurnedIn,
                iconColor = MaterialTheme.colorScheme.secondary,
                iconBgColor = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.75f),
                bottomText = "6 pendientes",
                bottomIcon = Icons.Default.Schedule,
                bottomTextColor = MaterialTheme.colorScheme.secondary,
                modifier = weightModifier
            )
            BentoStatCard(
                title = "Rúbricas",
                value = rubricCount,
                icon = Icons.Default.Rule,
                iconColor = MaterialTheme.colorScheme.tertiary,
                iconBgColor = MaterialTheme.colorScheme.tertiaryContainer.copy(alpha = 0.75f),
                bottomText = "Modelos personalizados",
                modifier = weightModifier
            )
            BentoStatCard(
                title = "Sesiones",
                value = sessionCount,
                icon = Icons.Default.History,
                iconColor = MaterialTheme.colorScheme.error,
                iconBgColor = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.72f),
                bottomText = "Registradas este curso",
                modifier = weightModifier
            )
        }

        // Main Content Area: Charts & Lists
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(32.dp)
        ) {
            Column(modifier = Modifier.weight(2f), verticalArrangement = Arrangement.spacedBy(32.dp)) {
                // Activity Chart Placeholder
                OrganicGlassCard(
                    modifier = Modifier.fillMaxWidth(),
                    backgroundColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.72f),
                    borderColor = Color.Transparent,
                    shadowElevation = 0.dp
                ) {
                    Column(modifier = Modifier.padding(32.dp)) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Column {
                                Text("Actividad de Evaluación", style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold))
                                Text("Promedio de calificaciones por grupo", color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            // Placeholder for Select
                            Text(
                                "ÚLTIMOS 30 DÍAS",
                                style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                                modifier = Modifier
                                    .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(8.dp))
                                    .padding(horizontal = 16.dp, vertical = 8.dp)
                            )
                        }

                        Spacer(modifier = Modifier.height(32.dp))

                        // Chart bars
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(256.dp)
                                .padding(horizontal = 16.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.Bottom
                        ) {
                            if (activityGroups.isEmpty()) {
                                Text("No hay datos de evaluación suficientes", modifier = Modifier.fillMaxWidth(), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                            } else {
                                activityGroups.forEach { (name, avg) ->
                                    ChartBar(name, (avg / 10.0).toFloat(), String.format("%.1f", avg))
                                }
                            }
                        }
                    }
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(32.dp)
                ) {
                    // Próximas Clases
                    OrganicGlassCard(
                        modifier = Modifier.weight(1f),
                        backgroundColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.72f),
                        borderColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.45f)
                    ) {
                        Column(modifier = Modifier.padding(24.dp)) {
                            Text("Próximas Clases", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold))
                            if (upcomingClasses.isEmpty()) {
                                Text("No hay clases programadas", color = MaterialTheme.colorScheme.onSurfaceVariant)
                            } else {
                                upcomingClasses.forEach { event ->
                                    val localTime = event.startAt.toLocalDateTime(TimeZone.currentSystemDefault())
                                    val timeStr = "${localTime.hour.toString().padStart(2, '0')}:${localTime.minute.toString().padStart(2, '0')}"
                                    UpcomingClassItem(timeStr, event.title, event.description ?: "Sin descripción")
                                    Spacer(modifier = Modifier.height(12.dp))
                                }
                            }
                        }
                    }

                    // Tareas Pendientes
                    OrganicGlassCard(
                        modifier = Modifier.weight(1f),
                        backgroundColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.72f),
                        borderColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.45f)
                    ) {
                        Column(modifier = Modifier.padding(24.dp)) {
                            Text("Tareas Pendientes", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold))
                            if (pendingTasks.isEmpty()) {
                                TaskItem("Todos los informes al día", isCompleted = true)
                                Spacer(modifier = Modifier.height(16.dp))
                                TaskItem("Revisar incidencias (0)", isCompleted = true)
                            } else {
                                pendingTasks.forEach { incident ->
                                    TaskItem(incident.title, isCompleted = false)
                                    Spacer(modifier = Modifier.height(12.dp))
                                }
                            }
                        }
                    }
                }
            }

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(32.dp)) {
                // Distribución de Alumnos
                OrganicGlassCard(
                    modifier = Modifier.fillMaxWidth(),
                    backgroundColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.72f),
                    borderColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.55f)
                ) {
                    Column(modifier = Modifier.padding(32.dp)) {
                        Text("Distribución de Alumnos", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold))
                        Spacer(modifier = Modifier.height(24.dp))
                        Box(
                            modifier = Modifier
                                .size(192.dp)
                                .align(Alignment.CenterHorizontally),
                            contentAlignment = Alignment.Center
                        ) {
                            // Circular representation
                            Box(modifier = Modifier.fillMaxSize().border(16.dp, MaterialTheme.colorScheme.primaryContainer, CircleShape))
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text(studentCount, style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.ExtraBold))
                                Text("TOTAL", style = MaterialTheme.typography.labelSmall.copy(color = MaterialTheme.colorScheme.onSurfaceVariant))
                            }
                        }
                        Spacer(modifier = Modifier.height(24.dp))
                        DistributionRow("Educación Obligatoria", "$esoPercentage%", MaterialTheme.colorScheme.primaryContainer)
                        Spacer(modifier = Modifier.height(12.dp))
                        DistributionRow("Bachillerato", "$bachPercentage%", MaterialTheme.colorScheme.tertiaryContainer)
                    }
                }

                // Banner
                OrganicGlassCard(
                    modifier = Modifier.fillMaxWidth(),
                    backgroundColor = MaterialTheme.colorScheme.primary,
                    borderColor = Color.Transparent
                ) {
                    Box {
                        Icon(
                            imageVector = Icons.Default.AutoAwesome,
                            contentDescription = null,
                            modifier = Modifier
                                .align(Alignment.BottomEnd)
                                .padding(end = 16.dp, bottom = 16.dp)
                                .size(120.dp),
                            tint = Color.White.copy(alpha = 0.1f)
                        )
                        Column(modifier = Modifier.padding(32.dp)) {
                            Text(
                                "Actualización Disponible",
                                style = MaterialTheme.typography.titleMedium.copy(
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.onPrimary
                                )
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                "Hemos añadido IA para la generación automática de rúbricas basadas en el currículo.",
                                style = MaterialTheme.typography.bodyMedium.copy(color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.8f))
                            )
                            Spacer(modifier = Modifier.height(24.dp))
                            Button(
                                onClick = {},
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                                    contentColor = MaterialTheme.colorScheme.onSurface
                                ),
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(12.dp)
                            ) {
                                Text("Ver Novedades", fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }
            }
        }
        }

        if (pullDistancePx > 10f || isPullRefreshing) {
            val progress = (pullDistancePx / 160f).coerceIn(0f, 1f)
            Box(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 8.dp)
                    .clip(RoundedCornerShape(999.dp))
                    .background(MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.92f))
                    .border(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f), RoundedCornerShape(999.dp))
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                contentAlignment = Alignment.Center
            ) {
                val percent = (progress * 100).roundToInt()
                Text(
                    text = if (isPullRefreshing) "Sincronizando..." else "Pull para sincronizar ($percent%)",
                    style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                    color = MaterialTheme.colorScheme.onSurface
                )
            }
        }
    }
}

@Composable
private fun QrCodeCanvas(
    content: String,
    modifier: Modifier = Modifier,
) {
    val matrix = remember(content) {
        runCatching {
            QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, 256, 256)
        }.getOrNull()
    }

    Box(modifier = modifier.wrapContentSize(Alignment.Center)) {
        if (matrix == null) {
            Text("QR no disponible")
            return@Box
        }

        Canvas(modifier = Modifier.size(140.dp)) {
            val modules = matrix.width.coerceAtLeast(1)
            val moduleSize = size.width / modules.toFloat()
            drawRect(Color.White)
            for (x in 0 until matrix.width) {
                for (y in 0 until matrix.height) {
                    if (matrix.get(x, y)) {
                        drawRect(
                            color = Color.Black,
                            topLeft = Offset(x * moduleSize, y * moduleSize),
                            size = Size(moduleSize, moduleSize)
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun OrganicGlassCard(
    modifier: Modifier = Modifier,
    backgroundColor: Color = MaterialTheme.colorScheme.surface,
    borderColor: Color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.1f),
    shadowElevation: androidx.compose.ui.unit.Dp = 2.dp,
    content: @Composable () -> Unit
) {
    com.migestor.desktop.ui.components.OrganicGlassCard(
        modifier = modifier,
        backgroundColor = backgroundColor,
        borderColor = borderColor,
        elevation = shadowElevation,
        content = content
    )
}

@Composable
fun BentoStatCard(
    title: String,
    value: String,
    icon: ImageVector,
    iconColor: Color,
    iconBgColor: Color,
    bottomText: String,
    bottomIcon: ImageVector? = null,
    bottomTextColor: Color = MaterialTheme.colorScheme.onSurfaceVariant,
    modifier: Modifier = Modifier
) {
    OrganicGlassCard(
        modifier = modifier.height(180.dp),
        backgroundColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.72f),
        borderColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.55f)
    ) {
        Column(
            modifier = Modifier.padding(24.dp),
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(iconBgColor),
                contentAlignment = Alignment.Center
            ) {
                Icon(imageVector = icon, contentDescription = null, tint = iconColor)
            }
            Column {
                Text(
                    text = title.uppercase(),
                    style = MaterialTheme.typography.labelSmall.copy(
                        letterSpacing = 1.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                )
                Text(
                    text = value,
                    style = MaterialTheme.typography.headlineLarge.copy(
                        fontWeight = FontWeight.ExtraBold,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                )
            }
            if (bottomIcon != null) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(imageVector = bottomIcon, contentDescription = null, tint = bottomTextColor, modifier = Modifier.size(16.dp))
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(bottomText, color = bottomTextColor, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold))
                }
            } else {
                Text(bottomText, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.labelSmall)
            }
        }
    }
}

@Composable
fun ChartBar(label: String, heightRatio: Float, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .width(48.dp)
                .fillMaxHeight(heightRatio)
                .clip(RoundedCornerShape(topStart = 12.dp, topEnd = 12.dp))
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.1f)) // Simulated group-hover could be primary
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(label, style = MaterialTheme.typography.labelSmall.copy(color = MaterialTheme.colorScheme.onSurfaceVariant))
    }
}

@Composable
fun UpcomingClassItem(time: String, title: String, subtitle: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.66f))
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = time,
            modifier = Modifier
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.1f), RoundedCornerShape(4.dp))
                .padding(horizontal = 8.dp, vertical = 4.dp),
            color = MaterialTheme.colorScheme.primary,
            style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold)
        )
        Spacer(modifier = Modifier.width(16.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold))
            Text(subtitle, style = MaterialTheme.typography.labelSmall.copy(color = MaterialTheme.colorScheme.onSurfaceVariant))
        }
        Icon(imageVector = Icons.Default.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha=0.5f))
    }
}

@Composable
fun TaskItem(title: String, isCompleted: Boolean) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier
                .size(20.dp)
                .border(2.dp, if (isCompleted) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.primary.copy(alpha = 0.3f), RoundedCornerShape(4.dp))
                .background(if (isCompleted) MaterialTheme.colorScheme.primary else Color.Transparent),
            contentAlignment = Alignment.Center
        ) {
            if (isCompleted) {
                Icon(imageVector = Icons.Default.Check, contentDescription = null, tint = Color.White, modifier = Modifier.size(14.dp))
            }
        }
        Spacer(modifier = Modifier.width(12.dp))
        Text(
            title,
            style = MaterialTheme.typography.bodyMedium,
            color = if (isCompleted) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
            textDecoration = if (isCompleted) androidx.compose.ui.text.style.TextDecoration.LineThrough else null
        )
    }
}

@Composable
fun DistributionRow(label: String, percentage: String, color: Color) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(modifier = Modifier.size(12.dp).clip(CircleShape).background(color))
            Spacer(modifier = Modifier.width(8.dp))
            Text(label, style = MaterialTheme.typography.bodySmall.copy(color = MaterialTheme.colorScheme.onSurfaceVariant))
        }
        Text(percentage, style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold))
    }
}
