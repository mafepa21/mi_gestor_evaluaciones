package com.migestor.desktop.ui.rubrics

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.animation.*
import androidx.compose.ui.input.key.*
import androidx.compose.ui.text.style.TextAlign
import com.migestor.desktop.ui.components.OrganicGlassCard
import com.migestor.desktop.ui.navigation.Navigator
import com.migestor.desktop.ui.navigation.Screen
import com.migestor.desktop.ui.system.LocalUiFeatureFlags
import com.migestor.shared.domain.RubricDetail
import com.migestor.shared.usecase.RubricImporter
import com.migestor.shared.viewmodel.RubricBulkEvaluationTarget
import com.migestor.shared.viewmodel.RubricsViewModel
import com.migestor.shared.viewmodel.RubricEvaluationUsage
import com.migestor.shared.viewmodel.RubricUiState
import com.migestor.shared.viewmodel.RubricCriterionState
import com.migestor.shared.viewmodel.RubricLevelState
import com.migestor.shared.viewmodel.RubricMode
import com.migestor.shared.viewmodel.RubricUsageState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.ui.text.TextStyle
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import java.io.File
import java.io.FileInputStream
import java.awt.FileDialog
import java.awt.Frame
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import org.apache.poi.ss.usermodel.DataFormatter
import org.apache.poi.xssf.usermodel.XSSFWorkbook

@Composable
fun RubricsScreen(viewModel: RubricsViewModel, onStatus: (String) -> Unit) {
    val uiState by viewModel.uiState.collectAsState()

    // NEW: Assign Dialog integration
    AssignRubricToTabDialog(viewModel)

    Crossfade(targetState = uiState.mode) { mode ->
        when (mode) {
            RubricMode.BANK -> RubricsBankMode(uiState, viewModel, onStatus)
            RubricMode.BUILDER -> RubricsBuilderMode(uiState, viewModel, onStatus)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RubricsBankMode(state: RubricUiState, viewModel: RubricsViewModel, onStatus: (String) -> Unit) {
    val filteredRubrics = remember(state.savedRubrics, state.selectedFilterClassId) {
        state.savedRubrics.filter { rubric ->
            state.selectedFilterClassId == null || rubric.rubric.classId == state.selectedFilterClassId
        }
    }
    val selectedRubric = filteredRubrics.firstOrNull { it.rubric.id == state.selectedWorkspaceRubricId }
        ?: filteredRubrics.firstOrNull()
    val usageSummary = selectedRubric?.let { state.usageSummaries[it.rubric.id] }
    val canOpenBulkEvaluation = usageSummary?.evaluationCount ?: 0 > 0

    LaunchedEffect(state.pendingBulkEvaluationTarget) {
        val target = state.pendingBulkEvaluationTarget ?: return@LaunchedEffect
        openBulkEvaluationTarget(target)
        viewModel.consumePendingBulkEvaluationTarget()
    }

    BulkEvaluationContextDialog(state, viewModel)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    "Rúbricas",
                    fontSize = 30.sp,
                    fontWeight = FontWeight.ExtraBold,
                    letterSpacing = (-1).sp
                )
                Text(
                    "Workspace de evaluación con tabla, detalle e impacto evaluativo",
                    fontSize = 15.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            FilledTonalButton(onClick = { viewModel.resetBuilder() }) {
                Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Nueva rúbrica", fontWeight = FontWeight.Bold)
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            FilterChip(
                selected = state.selectedFilterClassId == null,
                onClick = { viewModel.setFilterClass(null) },
                label = { Text("Todas") }
            )
            state.allClasses.forEach { schoolClass ->
                FilterChip(
                    selected = state.selectedFilterClassId == schoolClass.id,
                    onClick = { viewModel.setFilterClass(schoolClass.id) },
                    label = { Text(schoolClass.name) }
                )
            }
        }

        Row(
            modifier = Modifier.fillMaxSize(),
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            WorkspaceCard(
                title = "Banco",
                modifier = Modifier.weight(0.48f)
            ) {
                RubricsTable(
                    rubrics = filteredRubrics,
                    state = state,
                    onSelect = viewModel::selectWorkspaceRubric
                )
            }

            WorkspaceCard(
                title = selectedRubric?.rubric?.name ?: "Detalle",
                modifier = Modifier.weight(0.52f)
            ) {
                if (selectedRubric == null) {
                    EmptyWorkspaceState("No hay rúbricas disponibles con este filtro.")
                } else {
                    RubricDetailPanel(
                        rubric = selectedRubric,
                        state = state,
                        canOpenBulkEvaluation = canOpenBulkEvaluation,
                        onOpenBulkEvaluation = {
                            if (canOpenBulkEvaluation) {
                                viewModel.requestBulkEvaluationForSelectedRubric()
                            } else {
                                onStatus("Esta rúbrica todavía no tiene evaluaciones vinculadas.")
                            }
                        },
                        onEdit = { viewModel.loadRubric(selectedRubric) },
                        onAssign = { viewModel.startAssignRubricToClass(selectedRubric.rubric) },
                        onDelete = { viewModel.deleteRubric(selectedRubric.rubric.id) }
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun RubricsBuilderMode(state: RubricUiState, viewModel: RubricsViewModel, onStatus: (String) -> Unit) {
    Row(modifier = Modifier.fillMaxSize()) {
        // Mini Rail (Collapsed Bank)
        RubricsBankRail(viewModel)
        
        // Main Builder
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxHeight()
                .padding(24.dp)
        ) {
            BuilderHeader(state, viewModel, onStatus)
            Spacer(modifier = Modifier.height(24.dp))
            RubricBuilderGrid(state, viewModel, modifier = Modifier.weight(1f))
            Spacer(modifier = Modifier.height(16.dp))
            AddCriterionButton(viewModel)
        }
    }
}

@Composable
private fun RubricsBankRail(viewModel: RubricsViewModel) {
    Surface(
        modifier = Modifier.width(64.dp).fillMaxHeight(),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.3f),
        border = BorderStroke(0.5.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f))
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(vertical = 24.dp)
        ) {
            IconButton(onClick = { viewModel.setMode(RubricMode.BANK) }) {
                Icon(Icons.Default.ArrowBack, "Volver al banco", tint = MaterialTheme.colorScheme.primary)
            }
            Spacer(Modifier.height(24.dp))
            Icon(Icons.Default.AccountBalance, null, tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.5f), modifier = Modifier.size(20.dp))
        }
    }
}

@Composable
private fun WorkspaceCard(
    title: String,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit
) {
    Surface(
        modifier = modifier.fillMaxHeight(),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.32f),
        tonalElevation = 1.dp,
        shape = RoundedCornerShape(28.dp)
    ) {
        Column(
            modifier = Modifier.fillMaxSize().padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
            content = {
                Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                content()
            }
        )
    }
}

@Composable
private fun EmptyWorkspaceState(message: String) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun RubricsTable(
    rubrics: List<RubricDetail>,
    state: RubricUiState,
    onSelect: (Long) -> Unit
) {
    val headerStyle = MaterialTheme.typography.labelSmall.copy(
        fontWeight = FontWeight.Bold,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )

    if (rubrics.isEmpty()) {
        EmptyWorkspaceState("No hay rúbricas para este filtro.")
        return
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text("Nombre", modifier = Modifier.weight(0.34f), style = headerStyle)
            Text("Criterios", modifier = Modifier.weight(0.11f), style = headerStyle)
            Text("Curso", modifier = Modifier.weight(0.20f), style = headerStyle)
            Text("Última edición", modifier = Modifier.weight(0.17f), style = headerStyle)
            Text("Estado", modifier = Modifier.weight(0.18f), style = headerStyle)
        }

        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            contentPadding = PaddingValues(vertical = 10.dp)
        ) {
            items(rubrics, key = { it.rubric.id }) { rubric ->
                val className = state.allClasses.firstOrNull { it.id == rubric.rubric.classId }?.name ?: "Sin clase"
                val usageSummary = state.usageSummaries[rubric.rubric.id]
                val stateLabel = usageLabel(usageSummary?.usageState)
                val selected = state.selectedWorkspaceRubricId == rubric.rubric.id

                Surface(
                    modifier = Modifier.fillMaxWidth().clickable { onSelect(rubric.rubric.id) },
                    color = if (selected) {
                        MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
                    } else {
                        MaterialTheme.colorScheme.surface.copy(alpha = 0.74f)
                    },
                    shape = RoundedCornerShape(18.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 14.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            rubric.rubric.name,
                            modifier = Modifier.weight(0.34f),
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text("${rubric.criteria.size}", modifier = Modifier.weight(0.11f))
                        Text(className, modifier = Modifier.weight(0.20f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(formatRubricDate(rubric), modifier = Modifier.weight(0.17f))
                        SuggestionChip(
                            onClick = { onSelect(rubric.rubric.id) },
                            label = { Text(stateLabel, maxLines = 1) },
                            modifier = Modifier.weight(0.18f)
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RubricDetailPanel(
    rubric: RubricDetail,
    state: RubricUiState,
    canOpenBulkEvaluation: Boolean,
    onOpenBulkEvaluation: () -> Unit,
    onEdit: () -> Unit,
    onAssign: () -> Unit,
    onDelete: () -> Unit
) {
    val linkedClass = state.allClasses.firstOrNull { it.id == rubric.rubric.classId }?.name ?: "Sin clase asociada"
    val usageSummary = state.usageSummaries[rubric.rubric.id]
    val usageCount = usageSummary?.evaluationCount ?: 0
    val linkedClasses = usageSummary?.linkedClassNames.orEmpty()
    val maxLevels = rubric.criteria.maxOfOrNull { it.levels.size } ?: 0

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        contentPadding = PaddingValues(bottom = 8.dp)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(rubric.rubric.name, fontSize = 26.sp, fontWeight = FontWeight.ExtraBold)
                Text(
                    "Curso: $linkedClass · Última edición: ${formatRubricDate(rubric)}",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                if (!rubric.rubric.description.isNullOrBlank()) {
                    Text(
                        rubric.rubric.description!!,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        item {
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                DetailMetricCard("Criterios", "${rubric.criteria.size}", Icons.Default.Checklist)
                DetailMetricCard("Niveles", "$maxLevels", Icons.Default.LinearScale)
                DetailMetricCard("Evaluaciones", "$usageCount", Icons.Default.Grading)
                DetailMetricCard("Estado", usageLabel(usageSummary?.usageState), Icons.Default.Timeline)
            }
        }

        item {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = onOpenBulkEvaluation, enabled = canOpenBulkEvaluation) {
                    Icon(Icons.Default.ViewModule, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Evaluación masiva")
                }
                OutlinedButton(onClick = onEdit) {
                    Icon(Icons.Default.Edit, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Abrir vista de edición")
                }
                OutlinedButton(onClick = onAssign) {
                    Icon(Icons.Default.Output, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Asignar a clase")
                }
                IconButton(onClick = onDelete) {
                    Icon(Icons.Default.Delete, contentDescription = "Eliminar rúbrica")
                }
            }
        }

        item {
            Text("Impacto evaluativo", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(8.dp))
            if (usageCount == 0) {
                SupportingBlock("Todavía no hay evaluaciones activas enlazadas a esta rúbrica.")
            } else {
                SupportingBlock(
                    "Esta rúbrica está vinculada a $usageCount evaluación(es) en ${linkedClasses.size} clase(s)."
                )
                if (linkedClasses.isNotEmpty()) {
                    Spacer(Modifier.height(10.dp))
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        linkedClasses.forEach { className ->
                            AssistChip(onClick = {}, label = { Text(className) })
                        }
                    }
                }
                Spacer(Modifier.height(12.dp))
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    usageSummary?.evaluationUsages?.take(6)?.forEach { usage ->
                        EvaluationUsageRow(usage)
                    }
                }
            }
        }

        item {
            Text("Criterios y niveles", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        }

        items(rubric.criteria, key = { it.criterion.id }) { criterion ->
            Surface(
                color = MaterialTheme.colorScheme.surface.copy(alpha = 0.7f),
                shape = RoundedCornerShape(18.dp)
            ) {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            criterion.criterion.description,
                            modifier = Modifier.weight(1f),
                            fontWeight = FontWeight.Bold
                        )
                        AssistChip(
                            onClick = {},
                            label = { Text("Peso ${(criterion.criterion.weight * 100).toInt()}%") }
                        )
                    }

                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        criterion.levels.sortedBy { it.order }.forEach { level ->
                            FilterChip(
                                selected = false,
                                onClick = {},
                                label = { Text("${level.name} · ${level.points}") }
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DetailMetricCard(label: String, value: String, icon: androidx.compose.ui.graphics.vector.ImageVector) {
    Surface(
        modifier = Modifier.widthIn(min = 160.dp),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.72f),
        shape = RoundedCornerShape(18.dp)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Column {
                Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun SupportingBlock(text: String) {
    Surface(
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.68f),
        shape = RoundedCornerShape(16.dp)
    ) {
        Text(
            text = text,
            modifier = Modifier.fillMaxWidth().padding(14.dp),
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun EvaluationUsageRow(usage: RubricEvaluationUsage) {
    Surface(
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.7f),
        shape = RoundedCornerShape(16.dp)
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(usage.evaluationName, fontWeight = FontWeight.Bold)
            Text(
                "${usage.className} · ${usage.evaluationType} · Peso ${String.format("%.1f", usage.weight)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun BulkEvaluationContextDialog(state: RubricUiState, viewModel: RubricsViewModel) {
    val dialog = state.bulkEvaluationContextDialog ?: return
    var selectedEvaluationId by remember(dialog) { mutableStateOf(dialog.options.firstOrNull()?.evaluationId) }

    AlertDialog(
        onDismissRequest = viewModel::dismissBulkEvaluationContextDialog,
        title = { Text("Elegir evaluación masiva") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Selecciona la clase y evaluación que quieres abrir para ${dialog.rubricName}.")
                dialog.options.forEach { option ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(14.dp))
                            .clickable { selectedEvaluationId = option.evaluationId }
                            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.7f))
                            .padding(12.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        RadioButton(
                            selected = selectedEvaluationId == option.evaluationId,
                            onClick = { selectedEvaluationId = option.evaluationId }
                        )
                        Column {
                            Text(option.evaluationName, fontWeight = FontWeight.Bold)
                            Text(
                                "${option.className} · ${option.evaluationType}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    selectedEvaluationId?.let(viewModel::confirmBulkEvaluationContext)
                },
                enabled = selectedEvaluationId != null
            ) {
                Text("Abrir")
            }
        },
        dismissButton = {
            TextButton(onClick = viewModel::dismissBulkEvaluationContextDialog) {
                Text("Cancelar")
            }
        }
    )
}

private fun openBulkEvaluationTarget(target: RubricBulkEvaluationTarget) {
    Navigator.navigateTo(
        Screen.RubricBulkEvaluation(
            classId = target.classId,
            evaluationId = target.evaluationId,
            rubricId = target.rubricId,
            columnId = target.columnId,
            tabId = target.tabId
        )
    )
}

private fun usageLabel(state: RubricUsageState?): String = when (state) {
    RubricUsageState.UNUSED, null -> "Sin uso"
    RubricUsageState.SINGLE -> "1 evaluación"
    RubricUsageState.MULTIPLE -> "En uso"
}

private fun formatRubricDate(rubric: RubricDetail): String {
    val formatter = DateTimeFormatter.ofPattern("dd MMM yyyy").withZone(ZoneId.systemDefault())
    return formatter.format(Instant.ofEpochMilli(rubric.rubric.trace.updatedAt.toEpochMilliseconds()))
}

@Composable
private fun BuilderHeader(state: RubricUiState, viewModel: RubricsViewModel, onStatus: (String) -> Unit) {
    val flags = LocalUiFeatureFlags.current
    var showMoreMenu by remember { mutableStateOf(false) }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(modifier = Modifier.weight(1f)) {
            BasicTextField(
                value = state.rubricName,
                onValueChange = { viewModel.updateRubricName(it) },
                textStyle = TextStyle(
                    fontSize = 32.sp,
                    fontWeight = FontWeight.ExtraBold,
                    color = MaterialTheme.colorScheme.onSurface
                ),
                decorationBox = { innerTextField ->
                    if (state.rubricName.isEmpty()) {
                        Text("¿Cómo se llama esta rúbrica?", fontSize = 32.sp, fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f))
                    }
                    innerTextField()
                }
            )
            
            Spacer(Modifier.height(8.dp))
            
            Row(verticalAlignment = Alignment.CenterVertically) {
                // Class Selector Chip
                ClassAssignmentChip(state, viewModel)
                
                Spacer(Modifier.width(16.dp))
                
                // Achievement Presets
                Text("Niveles:", style = MaterialTheme.typography.labelMedium)
                Spacer(Modifier.width(8.dp))
                listOf("Estándar", "Binario", "Numérico").forEach { preset ->
                    AssistChip(
                        onClick = { viewModel.applyPresetLevels(preset) },
                        label = { Text(preset, fontSize = 11.sp) },
                        shape = RoundedCornerShape(8.dp)
                    )
                    Spacer(Modifier.width(4.dp))
                }

                Spacer(Modifier.weight(1f))

                // Weight Indicator
                val weightPercent = (state.totalWeight * 100).toInt()
                val weightColor = if (state.totalWeight == 1.0) Color(0xFF4CAF50) else MaterialTheme.colorScheme.error
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        if (state.totalWeight == 1.0) Icons.Default.CheckCircle else Icons.Default.Warning,
                        null,
                        tint = weightColor.copy(alpha = 0.8f),
                        modifier = Modifier.size(14.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(
                        "Peso: $weightPercent%",
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = weightColor
                    )
                }
            }
        }

        // Auto-save feedback & Manual Save
        Column(horizontalAlignment = Alignment.End) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (state.isSaving) {
                    CircularProgressIndicator(modifier = Modifier.size(12.dp), strokeWidth = 2.dp)
                } else {
                    Icon(Icons.Default.Check, "Guardado", modifier = Modifier.size(14.dp), tint = Color(0xFF4CAF50))
                }
                Spacer(Modifier.width(8.dp))
                Text(
                    if (state.isSaving) "Guardando..." else "Guardado",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            
            Spacer(Modifier.height(12.dp))
            
            Row(verticalAlignment = Alignment.CenterVertically) {
                fun importRubric() {
                    val dialog = FileDialog(null as Frame?, "Seleccionar Rúbrica (CSV o XLSX)", FileDialog.LOAD)
                    dialog.isVisible = true
                    val file = dialog.file ?: return
                    val path = dialog.directory + file
                    
                    try {
                        val rows = mutableListOf<List<String>>()
                        if (file.endsWith(".xlsx", true)) {
                            FileInputStream(path).use { fis ->
                                val workbook = XSSFWorkbook(fis)
                                val sheet = workbook.getSheetAt(0)
                                val formatter = DataFormatter()
                                for (i in 0..sheet.lastRowNum) {
                                    val row = sheet.getRow(i) ?: continue
                                    val rowData = mutableListOf<String>()
                                    for (j in 0 until row.lastCellNum.toInt()) {
                                        rowData.add(formatter.formatCellValue(row.getCell(j)))
                                    }
                                    rows.add(rowData)
                                }
                            }
                        } else if (file.endsWith(".csv", true)) {
                            File(path).readLines().forEach { line ->
                                rows.add(line.split(';', ',').map { it.trim().removeSurrounding("\"") })
                            }
                        }
                        
                        val importer = RubricImporter()
                        val imported = importer.parse(rows)
                        if (imported != null) {
                            viewModel.loadImportedRubric(imported)
                            onStatus("Rúbrica importada exitosamente")
                        } else {
                            onStatus("Error: Formato de archivo no válido")
                        }
                    } catch (e: Exception) {
                        onStatus("Error al importar: ${e.message}")
                    }
                }

                if (!flags.notebookToolbarSimplified) {
                    IconButton(onClick = { importRubric() }, modifier = Modifier.size(44.dp)) {
                        Icon(Icons.Default.UploadFile, "Importar rúbrica", modifier = Modifier.size(20.dp), tint = MaterialTheme.colorScheme.primary)
                    }
                } else {
                    Box {
                        IconButton(onClick = { showMoreMenu = true }, modifier = Modifier.size(44.dp)) {
                            Icon(Icons.Default.MoreVert, "Más acciones de rúbrica", modifier = Modifier.size(20.dp))
                        }
                        DropdownMenu(
                            expanded = showMoreMenu,
                            onDismissRequest = { showMoreMenu = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text("Importar rúbrica") },
                                leadingIcon = { Icon(Icons.Default.UploadFile, contentDescription = null) },
                                onClick = {
                                    showMoreMenu = false
                                    importRubric()
                                }
                            )
                        }
                    }
                }
                
                Spacer(Modifier.width(8.dp))
                
                Button(
                    onClick = { 
                        viewModel.saveRubric { success ->
                            onStatus(if (success) "Rúbrica guardada correctamente" else "Error al guardar")
                        }
                    },
                    shape = RoundedCornerShape(12.dp),
                    contentPadding = PaddingValues(horizontal = 20.dp, vertical = 10.dp),
                    elevation = ButtonDefaults.buttonElevation(defaultElevation = 0.dp, pressedElevation = 2.dp)
                ) {
                    Icon(Icons.Default.Save, "Guardar rúbrica", modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Guardar Rúbrica", fontSize = 14.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
private fun ClassAssignmentChip(state: RubricUiState, viewModel: RubricsViewModel) {
    var expanded by remember { mutableStateOf(false) }
    val selectedClass = state.allClasses.find { it.id == state.selectedClassId }

    Box {
        InputChip(
            selected = selectedClass != null,
            onClick = { expanded = true },
            label = { Text(selectedClass?.name ?: "+ Asignar clase") },
            trailingIcon = { Icon(Icons.Default.ArrowDropDown, null, modifier = Modifier.size(14.dp)) },
            shape = RoundedCornerShape(8.dp)
        )
        
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text("Ninguna") }, onClick = { viewModel.selectClass(null); expanded = false })
            state.allClasses.forEach { schoolClass ->
                DropdownMenuItem(text = { Text(schoolClass.name) }, onClick = { viewModel.selectClass(schoolClass.id); expanded = false })
            }
        }
    }
}



@Composable
private fun RubricBuilderGrid(state: RubricUiState, viewModel: RubricsViewModel, modifier: Modifier = Modifier) {
    val scrollState = rememberScrollState()
    val totalWidth = 260.dp + (200.dp * state.levels.size) + 120.dp
    
    Column(
        modifier = modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.fillMaxSize().horizontalScroll(scrollState)) {
            // Table Header (Levels)
            Row(
                modifier = Modifier.width(totalWidth)
                    .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.1f))
                    .padding(horizontal = 24.dp, vertical = 16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.width(260.dp).padding(end = 16.dp)) {
                    Text("Criterio / Niveles", fontWeight = FontWeight.ExtraBold, fontSize = 14.sp, color = MaterialTheme.colorScheme.primary)
                }
                
                state.levels.forEachIndexed { idx, level ->
                    Column(
                        modifier = Modifier.width(200.dp).padding(horizontal = 8.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            BasicTextField(
                                value = level.name,
                                onValueChange = { viewModel.updateLevelName(idx, it) },
                                textStyle = MaterialTheme.typography.bodySmall.copy(
                                    fontWeight = FontWeight.Bold,
                                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                                    color = MaterialTheme.colorScheme.onSurface
                                ),
                                modifier = Modifier.weight(1f)
                            )
            IconButton(
                onClick = { viewModel.removeLevel(idx) },
                modifier = Modifier.size(44.dp)
            ) {
                Icon(Icons.Default.Close, contentDescription = "Eliminar nivel", modifier = Modifier.size(14.dp), tint = MaterialTheme.colorScheme.error.copy(alpha = 0.85f))
            }
                        }
                    }
                }
                
                IconButton(
                    onClick = { viewModel.addLevel() },
                    modifier = Modifier.padding(start = 8.dp)
                ) {
                    Icon(Icons.Default.AddCircle, contentDescription = "Añadir Nivel", tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(24.dp))
                }
            }

            // Table Body (Criteria rows)
            LazyColumn(
                modifier = Modifier.fillMaxHeight().width(totalWidth),
                contentPadding = PaddingValues(bottom = 24.dp)
            ) {
                itemsIndexed(state.criteria) { idx, criterion ->
                    CriterionRow(idx, criterion, state.levels, viewModel)
                    // Spacer for Gestalt whitespace instead of heavy dividers
                    Spacer(Modifier.height(16.dp))
                }
            }
        }
    }
}

@Composable
private fun CriterionRow(
    index: Int, 
    criterion: RubricCriterionState, 
    levels: List<RubricLevelState>,
    viewModel: RubricsViewModel
) {
    Row(
        modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp),
        verticalAlignment = Alignment.Top
    ) {
        // Criterion Detail
        Column(modifier = Modifier.width(260.dp).padding(end = 16.dp)) {
            BasicTextField(
                value = criterion.description,
                onValueChange = { viewModel.updateCriterionDescription(index, it) },
                textStyle = MaterialTheme.typography.bodyMedium.copy(
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(8.dp))
                    .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.3f))
                    .padding(12.dp),
                decorationBox = { innerTextField ->
                    if (criterion.description.isEmpty()) {
                        Text("Nombre del criterio", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f))
                    }
                    innerTextField()
                }
            )
            Spacer(modifier = Modifier.height(8.dp))
            
            // Weight visual indicator (ultra-fine bar)
            val weightPercent = (criterion.weight * 100).toInt()
            LinearProgressIndicator(
                progress = criterion.weight.toFloat(),
                modifier = Modifier.fillMaxWidth().height(2.dp).clip(RoundedCornerShape(1.dp)),
                color = MaterialTheme.colorScheme.primary,
                trackColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.1f)
            )
            Text("${weightPercent}%", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
        }

        // Level Descriptions
        levels.forEach { level ->
            Box(modifier = Modifier.width(200.dp).padding(horizontal = 8.dp)) {
                BasicTextField(
                    value = criterion.levelDescriptions[level.uid] ?: "",
                    onValueChange = { viewModel.updateLevelDescription(index, level.uid, it) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(120.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.2f))
                        .padding(12.dp),
                    textStyle = MaterialTheme.typography.bodySmall.copy(color = MaterialTheme.colorScheme.onSurface),
                    decorationBox = { innerTextField ->
                        if ((criterion.levelDescriptions[level.uid] ?: "").isEmpty()) {
                            Text("Logro esperado...", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f))
                        }
                        innerTextField()
                    }
                )
            }
        }

        // Row Actions
        IconButton(
            onClick = { viewModel.removeCriterion(index) },
            modifier = Modifier.padding(start = 8.dp).size(44.dp)
        ) {
            Icon(Icons.Default.Delete, contentDescription = "Eliminar criterio", tint = MaterialTheme.colorScheme.error.copy(alpha = 0.85f), modifier = Modifier.size(18.dp))
        }
    }
}

@Composable
private fun AddCriterionButton(viewModel: RubricsViewModel) {
    Button(
        onClick = { viewModel.addCriterion() },
        modifier = Modifier.padding(vertical = 16.dp),
        shape = RoundedCornerShape(12.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.1f),
            contentColor = MaterialTheme.colorScheme.primary
        ),
        elevation = ButtonDefaults.buttonElevation(0.dp)
    ) {
        Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(18.dp))
        Spacer(modifier = Modifier.width(8.dp))
        Text("Añadir Nuevo Criterio", fontWeight = FontWeight.Bold)
    }
}
