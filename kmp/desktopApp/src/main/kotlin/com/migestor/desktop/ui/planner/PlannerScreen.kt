package com.migestor.desktop.ui.planner

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.BorderStroke
import com.migestor.desktop.ui.system.LocalUiFeatureFlags
import com.migestor.shared.domain.PlanningSession
import com.migestor.shared.domain.TeachingUnit
import com.migestor.shared.domain.SchoolClass
import com.migestor.shared.viewmodel.PlannerViewModel

@Composable
fun PlannerScreen(viewModel: PlannerViewModel) {
    val flags = LocalUiFeatureFlags.current
    val activeTab by viewModel.activeTab.collectAsState()
    val weekLabel by viewModel.weekLabel.collectAsState()
    val dateRange by viewModel.weekDateRangeLabel.collectAsState()
    val newSessionDialog by viewModel.newSessionDialog.collectAsState()
    val udManagerOpen by viewModel.udManagerOpen.collectAsState()
    val selectedSession by viewModel.selectedSession.collectAsState()
    val groups by viewModel.groups.collectAsState()
    val teachingUnits by viewModel.teachingUnits.collectAsState()
    val weeklySlots by viewModel.weeklySlots.collectAsState()
    val lastBulkOperation by viewModel.lastBulkOperation.collectAsState()

    var scheduleClassSelectorOpen by remember { mutableStateOf(false) }
    var activeScheduleClass by remember { mutableStateOf<SchoolClass?>(null) }

    Box(modifier = Modifier.fillMaxSize()) {

        Column(modifier = Modifier.fillMaxSize()) {

            // ── Header ────────────────────────────────────────────────────
            PlannerHeader(
                weekLabel = weekLabel,
                dateRange = dateRange,
                onPrev = viewModel::prevWeek,
                onNext = viewModel::nextWeek,
                onOpenUDs = viewModel::openUDManager,
                onOpenSchedule = { scheduleClassSelectorOpen = true }
            )
            lastBulkOperation?.let { result ->
                if (result.affected > 0 || result.omitted > 0) {
                    Surface(
                        modifier = Modifier.padding(horizontal = 32.dp, vertical = 8.dp),
                        shape = RoundedCornerShape(10.dp),
                        color = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.5f)
                    ) {
                        Text(
                            "Resultado acciones masivas: ${result.affected} afectadas · ${result.overwritten} sobrescritas · ${result.omitted} omitidas",
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSecondaryContainer
                        )
                    }
                }
            }

            // ── Navigation Tabs ───────────────────────────────────────────
            PlannerTabs(activeTab = activeTab, onTabSelected = viewModel::selectTab)

            // ── Content ───────────────────────────────────────────────────
            Box(modifier = Modifier.weight(1f)) {
                when (activeTab) {
                    PlannerViewModel.PlannerTab.WEEK     -> WeekGridView(viewModel)
                    PlannerViewModel.PlannerTab.TIMELINE -> TimelineViewPlaceholder()
                    PlannerViewModel.PlannerTab.DAY      -> DayViewPlaceholder()
                    PlannerViewModel.PlannerTab.DETAIL   -> selectedSession?.let {
                        SessionDetailPanel(session = it, viewModel = viewModel)
                    } ?: EmptyDetailPlaceholder()
                }
            }
        }

        // ── Dialogs / Overlays ─────────────────────────────────────────────
        newSessionDialog?.let { state ->
            NewSessionDialog(
                state = state,
                groups = groups,
                teachingUnits = teachingUnits,
                onSave = viewModel::quickCreateOrUpdateSession,
                onDismiss = viewModel::closeNewSessionDialog
            )
        }

        AnimatedVisibility(
            visible = udManagerOpen,
            enter = if (flags.reduceMotion) fadeIn() else slideInHorizontally(initialOffsetX = { it }),
            exit = if (flags.reduceMotion) fadeOut() else slideOutHorizontally(targetOffsetX = { it }),
            modifier = Modifier.align(Alignment.CenterEnd)
        ) {
            UDManagerSlideOver(
                units = teachingUnits,
                groups = groups,
                onSave = viewModel::saveTeachingUnit,
                onDelete = viewModel::deleteTeachingUnit,
                onGenerateSessions = viewModel::generateSessions,
                onClose = viewModel::closeUDManager
            )
        }

        // ── Diálogos de Horario ─────────────────────────────────────────────
        if (scheduleClassSelectorOpen) {
            ClassSelectorDialog(
                classes = groups,
                onClassSelected = { 
                    activeScheduleClass = it
                    viewModel.selectClass(it.id)
                    scheduleClassSelectorOpen = false 
                },
                onDismiss = { scheduleClassSelectorOpen = false }
            )
        }

        activeScheduleClass?.let { schoolClass ->
            WeeklyTemplateConfigDialog(
                schoolClass = schoolClass,
                slots = weeklySlots,
                onSaveSlot = viewModel::saveWeeklySlot,
                onDeleteSlot = viewModel::deleteWeeklySlot,
                onDismiss = { activeScheduleClass = null }
            )
        }
    }
}

// ── Placeholders ─────────────────────────────────────────────────────────────

@Composable
fun TimelineViewPlaceholder() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text("Timeline View (Próximamente)", color = MaterialTheme.colorScheme.outline)
    }
}

@Composable
fun DayViewPlaceholder() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text("Day View (Próximamente)", color = MaterialTheme.colorScheme.outline)
    }
}

@Composable
fun SessionDetailPanel(session: PlanningSession, viewModel: PlannerViewModel) {
    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 48.dp, vertical = 32.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp)
    ) {
        // Título de Sección
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                text = "Detalle de la Sesión", 
                style = MaterialTheme.typography.displaySmall, 
                fontWeight = FontWeight.Black,
                color = MaterialTheme.colorScheme.onSurface
            )
            Text(
                text = "${session.teachingUnitName} • ${session.groupName}",
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.Bold
            )
        }

        // Estado (Badge prominente pero sutil)
        val statusColor = session.status.colorHex.hexToColor()
        Surface(
            color = statusColor.copy(alpha = 0.08f),
            shape = RoundedCornerShape(12.dp),
            border = BorderStroke(1.dp, statusColor.copy(alpha = 0.2f))
        ) {
            Text(
                text = session.status.label,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                style = MaterialTheme.typography.labelLarge,
                color = statusColor,
                fontWeight = FontWeight.Black
            )
        }
        
        // Bloques de Contenido con Whitespace
        Column(verticalArrangement = Arrangement.spacedBy(32.dp)) {
            if (session.objectives.isNotEmpty()) {
                DetailSection(title = "Objetivos", content = session.objectives)
            }
            
            if (session.activities.isNotEmpty()) {
                DetailSection(title = "Actividades", content = session.activities)
            }
            
            if (session.evaluation.isNotEmpty()) {
                DetailSection(title = "Evaluación", content = session.evaluation)
            }
        }
        
        Spacer(Modifier.weight(1f))
        
        // Acción Primaria (Grande, Flotante en concepto)
        Button(
            onClick = { viewModel.openNewSessionDialog(session.dayOfWeek, session.period, session) },
            modifier = Modifier.height(56.dp).fillMaxWidth(0.3f),
            shape = RoundedCornerShape(28.dp),
            colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary),
            elevation = ButtonDefaults.buttonElevation(defaultElevation = 0.dp, pressedElevation = 0.dp)
        ) {
            Icon(Icons.Rounded.Edit, null, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(12.dp))
            Text("Editar Sesión", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun DetailSection(title: String, content: String) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = title.uppercase(), 
            style = MaterialTheme.typography.labelSmall, 
            fontWeight = FontWeight.Black,
            color = MaterialTheme.colorScheme.outline,
            letterSpacing = 1.sp
        )
        Text(
            text = content,
            style = MaterialTheme.typography.bodyLarge,
            lineHeight = 24.sp,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.8f)
        )
    }
}
