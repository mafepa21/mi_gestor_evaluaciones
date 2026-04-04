package com.migestor.desktop.ui.rubrics

import com.migestor.desktop.ui.rubrics.AssignRubricToTabDialog


import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
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
import com.migestor.desktop.ui.components.OrganicGlassCard
import com.migestor.desktop.ui.system.LocalUiFeatureFlags
import com.migestor.shared.usecase.RubricImporter
import com.migestor.shared.viewmodel.RubricsViewModel
import com.migestor.shared.viewmodel.RubricUiState
import com.migestor.shared.viewmodel.RubricCriterionState
import com.migestor.shared.viewmodel.RubricLevelState
import com.migestor.shared.viewmodel.RubricMode
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.ui.text.TextStyle
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import java.io.File
import java.io.FileInputStream
import java.awt.FileDialog
import java.awt.Frame
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
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp)
    ) {
        // Top Header
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    "Banco de Rúbricas",
                    fontSize = 32.sp,
                    fontWeight = FontWeight.ExtraBold,
                    letterSpacing = (-1).sp
                )
                Text(
                    "Gestiona y organiza tus herramientas de evaluación",
                    fontSize = 16.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            
            Button(
                onClick = { viewModel.resetBuilder() },
                shape = RoundedCornerShape(12.dp),
                contentPadding = PaddingValues(horizontal = 20.dp, vertical = 12.dp)
            ) {
                Icon(Icons.Default.Add, null, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(8.dp))
                Text("Nueva Rúbrica", fontWeight = FontWeight.Bold)
            }
        }

        Spacer(modifier = Modifier.height(32.dp))

        // Filter Chips
        Row(
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            FilterChip(
                selected = state.selectedFilterClassId == null,
                onClick = { viewModel.setFilterClass(null) },
                label = { Text("Todas") },
                shape = RoundedCornerShape(20.dp)
            )
            state.allClasses.forEach { schoolClass ->
                FilterChip(
                    selected = state.selectedFilterClassId == schoolClass.id,
                    onClick = { viewModel.setFilterClass(schoolClass.id) },
                    label = { Text(schoolClass.name) },
                    shape = RoundedCornerShape(20.dp)
                )
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        // Grouped Rubrics
        val groupedRubrics = if (state.selectedFilterClassId != null) {
            val className = state.allClasses.find { it.id == state.selectedFilterClassId }?.name ?: "Sin clase"
            mapOf(className to state.savedRubrics.filter { it.rubric.id % 2 == 0L }) // Dummy filter for now
        } else {
            // Group by class if linked, otherwise "Sin clasificar"
            // For now, let's just show them in a clean list as per the request
            mapOf("Tus Rúbricas" to state.savedRubrics)
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(32.dp), // Gestalt whitespace
            contentPadding = PaddingValues(bottom = 40.dp)
        ) {
            groupedRubrics.forEach { (groupName, rubrics) ->
                item {
                    Text(
                        groupName.uppercase(),
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary,
                        letterSpacing = 1.sp
                    )
                    Spacer(Modifier.height(16.dp))
                    
                    @OptIn(ExperimentalLayoutApi::class)
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        rubrics.forEach { rubric ->
                            RubricBankCard(
                                rubric = rubric,
                                onClick = { viewModel.loadRubric(rubric) },
                                onDelete = { viewModel.deleteRubric(rubric.rubric.id) },
                                onAssign = { viewModel.startAssignRubricToClass(rubric.rubric) }
                            )
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun RubricBankCard(
    rubric: com.migestor.shared.domain.RubricDetail,
    onClick: () -> Unit,
    onDelete: () -> Unit,
    onAssign: () -> Unit
) {
    OrganicGlassCard(
        modifier = Modifier
            .width(280.dp)
            .height(120.dp)
            .clickable(onClick = onClick),
        backgroundColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.4f)
    ) {
        Box(modifier = Modifier.fillMaxSize().padding(20.dp)) {
            Column {
                Text(
                    rubric.rubric.name,
                    fontWeight = FontWeight.Bold,
                    fontSize = 16.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(Modifier.height(4.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    SuggestionChip(
                        onClick = {},
                        label = { Text("${rubric.criteria.size} criterios", fontSize = 10.sp) },
                        shape = RoundedCornerShape(8.dp)
                    )
                }
            }

            // Small discrete actions
            Row(
                modifier = Modifier.align(Alignment.TopEnd),
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                IconButton(onClick = onAssign, modifier = Modifier.size(44.dp)) {
                    Icon(Icons.Default.Output, "Asignar rúbrica", tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.85f), modifier = Modifier.size(16.dp))
                }
                IconButton(onClick = onDelete, modifier = Modifier.size(44.dp)) {
                    Icon(Icons.Default.Delete, "Eliminar rúbrica", tint = MaterialTheme.colorScheme.error.copy(alpha = 0.85f), modifier = Modifier.size(14.dp))
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
