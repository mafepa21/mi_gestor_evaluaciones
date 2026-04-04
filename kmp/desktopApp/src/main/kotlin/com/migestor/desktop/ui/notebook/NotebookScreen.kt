package com.migestor.desktop.ui.notebook

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.input.key.*
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import com.migestor.data.di.KmpContainer
import com.migestor.desktop.ui.components.OrganicGlassCard
import com.migestor.desktop.ui.theme.*
import com.migestor.desktop.ui.system.LocalUiFeatureFlags
import com.migestor.desktop.ui.system.toAppFeedbackState
import com.migestor.shared.domain.*
import com.migestor.shared.domain.NotebookTab as NotebookSheetTab
import com.migestor.shared.formula.FormulaEvaluator
import com.migestor.shared.viewmodel.*
import com.migestor.desktop.ui.rubrics.*
import com.migestor.desktop.ui.navigation.*
import com.migestor.desktop.ui.planner.hexToColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.focus.FocusDirection
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.datetime.Clock
import com.migestor.shared.domain.groupedRowsFor

// ─────────────────────────────────────────────────────────
// Notebook Design System (Jobs Philosophy)
// ─────────────────────────────────────────────────────────

object NotebookGeometry {
    val cardRadius = 16.dp
    val cardPadding = 8.dp
    val cellRadius = 8.dp      // R_int = R_ext - P (16 - 8)
    val headerCellRadius = 12.dp
    val screenPadding = 24.dp  // Large whitespace for "Test del Aire"
    val interElementSpace = 24.dp
    val rowHeightCompact = 36.dp
    val rowHeightComfortable = 48.dp
}

object NotebookVisualTokens {
    val dialogCorner = 20.dp
    val dialogCornerLarge = 24.dp
    val dialogWidthCompact = 360.dp
    val dialogWidthRegular = 480.dp
    val dialogWidthWide = 760.dp
    val buttonCorner = 12.dp
    val chipCorner = 8.dp
    val sectionSpacing = 16.dp
}

private val NotebookColorPalette = listOf(
    "#4A90D9",
    "#2D9CDB",
    "#27AE60",
    "#F2994A",
    "#EB5757",
    "#9B51E0",
    "#111827",
    "#F4B400"
)

private data class NotebookSurfaceTones(
    val pageTop: Color,
    val pageBottom: Color,
    val panelBackground: Color,
    val panelBorder: Color,
    val gridBase: Color,
    val gridHeader: Color,
    val gridHeaderSoft: Color,
    val groupHeader: Color,
    val rowEven: Color,
    val rowOdd: Color,
    val collapsedColumn: Color
)

@Composable
private fun rememberNotebookSurfaceTones(): NotebookSurfaceTones {
    val scheme = MaterialTheme.colorScheme
    val isDark = scheme.background.luminance() < 0.5f
    return if (isDark) {
        NotebookSurfaceTones(
            pageTop = Color(0xFF0A1B35),
            pageBottom = Color(0xFF08162D),
            panelBackground = Color(0xFF122640).copy(alpha = 0.92f),
            panelBorder = Color(0xFF324F78).copy(alpha = 0.58f),
            gridBase = Color(0xFF13263F),
            gridHeader = Color(0xFF1A3251),
            gridHeaderSoft = Color(0xFF172C47),
            groupHeader = Color(0xFF1D3553).copy(alpha = 0.78f),
            rowEven = Color(0xFF142841).copy(alpha = 0.30f),
            rowOdd = Color(0xFF102037).copy(alpha = 0.22f),
            collapsedColumn = Color(0xFF27476F).copy(alpha = 0.52f)
        )
    } else {
        NotebookSurfaceTones(
            pageTop = scheme.surface,
            pageBottom = scheme.background,
            panelBackground = scheme.surfaceVariant.copy(alpha = 0.72f),
            panelBorder = scheme.outlineVariant.copy(alpha = 0.56f),
            gridBase = scheme.surface,
            gridHeader = scheme.surfaceVariant.copy(alpha = 0.78f),
            gridHeaderSoft = scheme.surfaceVariant.copy(alpha = 0.62f),
            groupHeader = scheme.surfaceVariant.copy(alpha = 0.35f),
            rowEven = scheme.surfaceVariant.copy(alpha = 0.10f),
            rowOdd = Color.Transparent,
            collapsedColumn = scheme.outlineVariant.copy(alpha = 0.35f)
        )
    }
}

fun gradeToBackground(value: Double?): Color = when {
    value == null -> Color.Transparent
    value >= 9.0  -> GreenGlass.copy(alpha = 0.18f)
    value >= 7.0  -> BlueGlass.copy(alpha = 0.14f)
    value >= 5.0  -> Color.Transparent
    value < 5.0   -> RedGlass.copy(alpha = 0.18f)
    else          -> Color.Transparent
}

@Composable
fun StatChip(label: String, value: String, accent: Color = MaterialTheme.colorScheme.primary) {
    OrganicGlassCard(
        modifier = Modifier,
        cornerRadius = NotebookGeometry.cellRadius
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
            Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = accent)
        }
    }
}

// ─────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────

enum class NotebookDensity(val label: String, val rowHeight: Dp, val fontSize: Int) {
    COMPACT("Compacto", 36.dp, 12),
    COMFORTABLE("Cómodo", 48.dp, 14)
}

private data class NotebookGridUiModel(
    val groupedRows: List<NotebookGroupedRows>,
    val visibleColumns: List<NotebookColumnDefinition>,
    val calculatedCellValues: Map<Pair<Long, String>, Double?>,
    val rowAverageByStudentId: Map<Long, Double?>
)

private data class NotebookActions(
    val onAddTab: () -> Unit,
    val onDeleteTab: () -> Unit,
    val onAddColumn: () -> Unit,
    val onManageCategories: () -> Unit,
    val onAddStudent: () -> Unit,
    val onManageGroups: () -> Unit,
    val onDuplicateConfig: () -> Unit,
    val onImportCSV: () -> Unit,
)

private class NotebookDialogState {
    val showAddColumnDialog = mutableStateOf(false)
    val showCategoryDialog = mutableStateOf(false)
    val showFormulaDialog = mutableStateOf<NotebookColumnDefinition?>(null)
    val showAddStudentDialog = mutableStateOf(false)
    val showImportDialog = mutableStateOf(false)
    val showGroupDialog = mutableStateOf(false)
    val studentToDelete = mutableStateOf<com.migestor.shared.domain.Student?>(null)
    val showAddTabDialog = mutableStateOf(false)
    val tabToDelete = mutableStateOf<NotebookSheetTab?>(null)
    val columnToDelete = mutableStateOf<NotebookColumnDefinition?>(null)
    val showDuplicateDialog = mutableStateOf(false)
}

@Composable
private fun rememberNotebookDialogState() = remember { NotebookDialogState() }

@Composable
private fun rememberNotebookGridUiModel(
    sheet: NotebookSheet,
    visibleCols: List<NotebookColumnDefinition>,
    selectedTabId: String?,
    evaluations: List<Evaluation>,
    numericDrafts: Map<Pair<Long, String>, String>,
    formulaEvaluator: FormulaEvaluator,
): NotebookGridUiModel {
    return remember(sheet, visibleCols, selectedTabId, evaluations, numericDrafts) {
        val groupedRows = sheet.groupedRowsFor(selectedTabId)
        val calculatedValues = mutableMapOf<Pair<Long, String>, Double?>()
        val rowAverages = mutableMapOf<Long, Double?>()
        val evaluableCols = visibleCols.filter {
            it.type == NotebookColumnType.NUMERIC ||
                it.type == NotebookColumnType.RUBRIC ||
                it.type == NotebookColumnType.CALCULATED
        }
        val calculatedCols = visibleCols.filter { it.type == NotebookColumnType.CALCULATED }

        groupedRows.forEach { section ->
            section.rows.forEach { row ->
                calculatedCols.forEach { col ->
                    calculatedValues[row.student.id to col.id] = calculateColumnRealtime(
                        row = row,
                        column = col,
                        evaluations = evaluations,
                        numericDrafts = numericDrafts,
                        formulaEvaluator = formulaEvaluator
                    )
                }

                val values = evaluableCols.mapNotNull { col ->
                    if (col.type == NotebookColumnType.CALCULATED) {
                        calculatedValues[row.student.id to col.id]
                    } else {
                        numericDrafts[row.student.id to col.id]?.toDoubleOrNull()
                    }
                }
                rowAverages[row.student.id] = values.takeIf { it.isNotEmpty() }?.average()
            }
        }

        NotebookGridUiModel(
            groupedRows = groupedRows,
            visibleColumns = visibleCols.sortedWith(compareBy<NotebookColumnDefinition> { it.order }.thenBy { it.id }),
            calculatedCellValues = calculatedValues,
            rowAverageByStudentId = rowAverages
        )
    }
}

// ─────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────

@OptIn(ExperimentalLayoutApi::class, ExperimentalComposeUiApi::class)
@Composable
fun NotebookScreen(
    container: KmpContainer,
    scope: CoroutineScope,
    onStatus: (String) -> Unit
) {
    val notebookTones = rememberNotebookSurfaceTones()
    // ── Class management ──────────────────────────────────
    val classes by container.classesRepository.observeClasses().collectAsState(emptyList())
    // FIX: rememberSaveable mantiene el classId seleccionado entre recomposiciones
    var classId by remember { mutableStateOf<Long?>(null) }
    val selectedClass = classes.find { it.id == classId }

    // ── ViewModel Integration ─────────────────────────────
    val viewModel = remember(container) {
        NotebookViewModel(
            notebookRepository = container.notebookRepository,
            evaluationsRepository = container.evaluationsRepository,
            rubricsRepository = container.rubricsRepository,
        )
    }

    val uiState by viewModel.state.collectAsState()
    val importResultState by viewModel.importResult.collectAsState()
    val userRubrics by viewModel.userRubrics.collectAsState(emptyList())

    val evaluations by remember(classId) {
        classId?.let { container.evaluationsRepository.observeClassEvaluations(it) } ?: flowOf(emptyList())
    }.collectAsState(emptyList())

    // FIX: solo asigna classId una vez cuando llegan las clases por primera vez
    // Usa `classes.isNotEmpty() && classId == null` como condición estricta
    // sin ningún flow activo que pueda re-disparar
    LaunchedEffect(classes.isNotEmpty()) {
        if (classId == null && classes.isNotEmpty()) {
            val firstId = classes.first().id
            classId = firstId
            viewModel.setSelectedTabId(null)
            viewModel.selectClass(firstId)
        }
    }

    // ── Local UI State ────────────────────────────────────
    var selectedNotebookTab by remember { mutableStateOf("") }
    val formulaEvaluator = remember { FormulaEvaluator() }

    // Drafts and Active Cell now come from viewModel.state (NotebookUiState.Data)
    val stateData = uiState as? NotebookUiState.Data
    val numericDrafts = stateData?.numericDrafts ?: emptyMap()
    val activeCell = stateData?.activeCell

    // ── UI preferences ────────────────────────────────────
    var density by remember { mutableStateOf(NotebookDensity.COMFORTABLE) }
    val dialogState = rememberNotebookDialogState()
    var showAddColumnDialog by dialogState.showAddColumnDialog
    var showCategoryDialog by dialogState.showCategoryDialog
    var showFormulaDialog by dialogState.showFormulaDialog
    var showAddStudentDialog by dialogState.showAddStudentDialog
    var showImportDialog by dialogState.showImportDialog
    var showGroupDialog by dialogState.showGroupDialog
    var studentToDelete by dialogState.studentToDelete
    var showAddTabDialog by dialogState.showAddTabDialog
    var tabToDelete by dialogState.tabToDelete
    var columnToDelete by dialogState.columnToDelete
    var showDuplicateDialog by dialogState.showDuplicateDialog

    val onSave = {
        scope.launch {
            val saved = viewModel.saveCurrentNotebook()
            onStatus(if (saved) "Cambios guardados" else "No hay cambios pendientes")
        }
    }

    // ── Sync active tab ───────────────────────────────────
    LaunchedEffect(uiState) {
        val state = uiState
        if (state is NotebookUiState.Data) {
            if (selectedNotebookTab.isEmpty() || state.sheet.tabs.none { it.id == selectedNotebookTab }) {
                val rootTabs = state.sheet.tabs.filter { it.parentTabId == null }.sortedWith(compareBy<NotebookSheetTab> { it.order }.thenBy { it.id })
                selectedNotebookTab = rootTabs.firstOrNull()?.let { root ->
                    state.sheet.tabs.firstOrNull { it.parentTabId == root.id }?.id ?: root.id
                } ?: state.sheet.tabs.firstOrNull()?.id ?: "eval"
            }
            viewModel.setSelectedTabId(
                selectedNotebookTab.takeIf { tabId ->
                    state.sheet.tabs.any { it.id == tabId }
                }
            )
        }
    }
    // ── Content ───────────────────────────────────────────
    val saveState by viewModel.saveState.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(
                brush = Brush.verticalGradient(
                    colors = listOf(
                        notebookTones.pageTop,
                        notebookTones.pageBottom
                    )
                )
            )
            .padding(NotebookGeometry.screenPadding)
            .onKeyEvent {
                if (it.isCtrlPressed && it.key == Key.S && it.type == KeyEventType.KeyDown) {
                    onSave()
                    true
                } else false
            }
    ) {

        // 1. Context Bar (Class Selector + Save State + Density)
        NotebookTopBar(
            classes = classes,
            selectedClass = selectedClass,
            onClassSelected = { schoolClass ->
                if (schoolClass.id != classId) {
                    selectedNotebookTab = ""
                    viewModel.setSelectedTabId(null)
                    classId = schoolClass.id
                    viewModel.selectClass(schoolClass.id)
                }
            },
            saveState = saveState,
            onSave = { onSave() },
            density = density,
            onDensityToggle = { density = if (density == NotebookDensity.COMPACT) NotebookDensity.COMFORTABLE else NotebookDensity.COMPACT },
            onLoad = { classId?.let { viewModel.selectClass(it, force = true) } },
            onUndo = { /* Undo not yet implemented in ViewModel */ }
        )

        when (val state = uiState) {
            is NotebookUiState.Loading -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
            is NotebookUiState.Error -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text("Error: ${state.message}", color = MaterialTheme.colorScheme.error)
                }
            }
            is NotebookUiState.Data -> {
                val sheet = state.sheet

                // 2. Group Summary Bar (Auto-calculated stats)
                GroupSummaryBar(sheet = sheet, viewModel = viewModel)

                Spacer(Modifier.height(NotebookGeometry.interElementSpace))

                // 3. Action Bar (Tabs + Add Actions)
                val notebookActions = remember(onStatus, classId, sheet.tabs, selectedNotebookTab) {
                    NotebookActions(
                        onAddTab = { showAddTabDialog = true },
                        onDeleteTab = {
                            val selected = sheet.tabs.find { it.id == selectedNotebookTab }
                            if (selected != null) {
                                tabToDelete = selected
                            }
                        },
                        onAddColumn = { showAddColumnDialog = true },
                        onManageCategories = { showCategoryDialog = true },
                        onAddStudent = { showAddStudentDialog = true },
                        onManageGroups = { showGroupDialog = true },
                        onImportCSV = {
                            val dialog = java.awt.FileDialog(null as java.awt.Frame?, "Seleccionar CSV de Alumnos", java.awt.FileDialog.LOAD).apply {
                                file = "*.csv"
                                isVisible = true
                            }
                            val path = dialog.file?.let { dialog.directory + it }
                            if (path != null) {
                                try {
                                    val content = java.io.File(path).readText()
                                    viewModel.importStudents(content)
                                    showImportDialog = true
                                } catch (e: Exception) {
                                    onStatus("Error al leer archivo: ${e.message}")
                                }
                            }
                        },
                        onDuplicateConfig = { showDuplicateDialog = true }
                    )
                }
                ActionBar(
                    tabs = sheet.tabs,
                    selectedTabId = selectedNotebookTab,
                    onTabSelected = {
                        selectedNotebookTab = it
                        viewModel.setSelectedTabId(it)
                        viewModel.clearActiveCell()
                    },
                    actions = notebookActions
                )

                Spacer(Modifier.height(NotebookGeometry.interElementSpace))

                // 4. Main Content Area (Grid)
                val visibleCols = visibleColumnsForTab(
                    columns = sheet.columns,
                    tabs = sheet.tabs,
                    selectedTabId = selectedNotebookTab
                )
                val gridUiModel = rememberNotebookGridUiModel(
                    sheet = sheet,
                    visibleCols = visibleCols,
                    selectedTabId = selectedNotebookTab,
                    evaluations = evaluations,
                    numericDrafts = numericDrafts,
                    formulaEvaluator = formulaEvaluator
                )

                NotebookGridSection(
                    modifier = Modifier.weight(1f),
                    tones = notebookTones,
                    state = state,
                    viewModel = viewModel,
                    dataState = stateData ?: state,
                    activeCell = activeCell,
                    density = density,
                    selectedNotebookTab = selectedNotebookTab,
                    gridUiModel = gridUiModel,
                    onEditFormula = { showFormulaDialog = it },
                    onDeleteStudent = { studentToDelete = it },
                    onDeleteColumn = { viewModel.deleteColumn(it.id) },
                    onOpenRubric = { student, evalId, rubricId, columnId ->
                        viewModel.onRubricCellClicked(student.id, columnId, rubricId, evalId)
                    },
                    onBulkRubricEval = { evalId, rubricId, columnId ->
                        if (classId != null) {
                            Navigator.navigateTo(Screen.RubricBulkEvaluation(classId!!, evalId, rubricId, columnId, selectedNotebookTab))
                        }
                    },
                    onToggleColumnSelection = { viewModel.toggleColumnSelection(it) }
                )
                }
            else -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(Icons.Default.MenuBook, null, Modifier.size(72.dp), tint = MaterialTheme.colorScheme.outlineVariant)
                        Text("Selecciona una clase para cargar el cuaderno",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodyLarge,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.widthIn(max = 400.dp))
                        Spacer(Modifier.height(8.dp))
                        Text("💡  Atajos: Tab / Enter navegan entre celdas · Ctrl+Z deshace · Ctrl+S guarda",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.outline,
                            textAlign = TextAlign.Center)
                    }
                }
            }
        }
    }

    // ── Add Column Dialog ─────────────────────────────────
    if (showAddColumnDialog) {
        val sheet = (uiState as? NotebookUiState.Data)?.sheet

        AddColumnDialog(
            userRubrics      = userRubrics,
            existingTabs     = sheet?.tabs ?: emptyList(),
            existingCategories = sheet?.columnCategories
                ?.filter { it.tabId == selectedNotebookTab }
                ?.sortedWith(compareBy<NotebookColumnCategory> { it.order }.thenBy { it.id })
                ?: emptyList(),
            preselectedTabId = selectedNotebookTab,
            onDismiss        = { showAddColumnDialog = false },
            onCreateCategory = { name, id ->
                viewModel.saveColumnCategory(name = name, categoryId = id)
            },
            onConfirm        = { newCol ->
                viewModel.saveColumn(newCol)
                showAddColumnDialog = false
                onStatus("Columna '${newCol.title}' añadida")
            }
        )
    }

    if (showCategoryDialog) {
        val sheet = (uiState as? NotebookUiState.Data)?.sheet
        val categoriesForTab = sheet?.columnCategories
            ?.filter { it.tabId == selectedNotebookTab }
            ?.sortedWith(compareBy<NotebookColumnCategory> { it.order }.thenBy { it.id })
            ?: emptyList()
        val columnsForTab = sheet?.let {
            visibleColumnsForTab(
                columns = it.columns,
                tabs = it.tabs,
                selectedTabId = selectedNotebookTab
            )
        } ?: emptyList()
        ColumnCategoryManagerDialog(
            selectedTabTitle = sheet?.tabs?.firstOrNull { it.id == selectedNotebookTab }?.title ?: selectedNotebookTab,
            columns = columnsForTab,
            categories = categoriesForTab,
            onDismiss = { showCategoryDialog = false },
            onCreateCategory = { name ->
                viewModel.saveColumnCategory(name = name)
                onStatus("Categoría '$name' creada")
            },
            onRenameCategory = { categoryId, newName ->
                viewModel.saveColumnCategory(name = newName, categoryId = categoryId)
                onStatus("Categoría actualizada")
            },
            onDeleteCategory = { categoryId ->
                viewModel.deleteColumnCategory(categoryId = categoryId)
                onStatus("Categoría eliminada")
            },
            onAssignColumn = { columnId, categoryId ->
                viewModel.assignColumnToCategory(columnId = columnId, categoryId = categoryId)
            }
        )
    }

    // ── Add Tab Dialog ────────────────────────────────────
    if (showAddTabDialog) {
        AddTabDialog(
            existingTitles = (uiState as? NotebookUiState.Data)?.sheet?.tabs?.map { it.title } ?: emptyList(),
            existingTabs = (uiState as? NotebookUiState.Data)?.sheet?.tabs ?: emptyList(),
            onDismiss = { showAddTabDialog = false },
            onConfirm = { newTitle, parentId ->
                val newId = newTitle.lowercase().replace(" ", "_") + "_${Clock.System.now().toEpochMilliseconds()}"
                viewModel.saveTab(NotebookSheetTab(id = newId, title = newTitle, order = -1, parentTabId = parentId))
                selectedNotebookTab = newId
                viewModel.setSelectedTabId(newId)
                showAddTabDialog = false
                onStatus("Pestaña '$newTitle' creada")
            }
        )
    }

    // ── Delete Tab Confirmation ───────────────────────────
    val currentTabToDelete = tabToDelete
    if (currentTabToDelete != null) {
        AlertDialog(
            onDismissRequest = { tabToDelete = null },
            title = { Text("Eliminar pestaña") },
            text = { Text("¿Estás seguro de que quieres eliminar la pestaña '${currentTabToDelete.title}'? Esta acción no se puede deshacer.") },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.deleteTab(currentTabToDelete.id)
                    tabToDelete = null
                }) { Text("Eliminar", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { tabToDelete = null }) { Text("Cancelar") }
            }
        )
    }

    // ── Delete Column Confirmation ────────────────────────
    val currentColToDelete = columnToDelete
    if (currentColToDelete != null) {
        AlertDialog(
            onDismissRequest = { columnToDelete = null },
            title = { Text("Eliminar Columna") },
            text  = { Text("¿Estás seguro de que deseas eliminar la columna '${currentColToDelete.title}'?") },
            confirmButton = {
                Button(
                    onClick = { viewModel.deleteColumn(currentColToDelete.id); columnToDelete = null; onStatus("Columna eliminada") },
                    colors  = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
                ) { Text("Eliminar") }
            },
            dismissButton = { TextButton(onClick = { columnToDelete = null }) { Text("Cancelar") } }
        )
    }

    // ── Rubric Evaluation Overlay ─────────────────────────
    val rubricTarget = (uiState as? NotebookUiState.Data)?.rubricEvaluationTarget
    if (rubricTarget != null) {
        val evalViewModel = remember(container) {
            RubricEvaluationViewModel(
                rubricsRepository = container.rubricsRepository,
                studentsRepository = container.studentsRepository,
                evaluationsRepository = container.evaluationsRepository,
                gradesRepository = container.gradesRepository,
                notebookRepository = container.notebookRepository
            )
        }

        LaunchedEffect(rubricTarget) {
            evalViewModel.loadForNotebookCell(
                studentId = rubricTarget.studentId,
                columnId = rubricTarget.columnId,
                rubricId = rubricTarget.rubricId,
                evaluationId = rubricTarget.evaluationId
            )
        }

        RubricEvaluationDialog(
            viewModel = evalViewModel,
            onDismiss = { 
                viewModel.clearRubricEvaluationTarget()
                // Forzamos recarga del cuaderno para ver la nota final (aunque hay auto-save,
                // NotebookViewModel necesita refrescar su snapshot para mostrar el valor en la celda)
                classId?.let { viewModel.selectClass(it, force = true) }
            }
        )
    }

    // ── Generic Cell Editor Overlay ───────────────────────
    val activeEditor = (uiState as? NotebookUiState.Data)?.activeCellEditor
    if (activeEditor != null) {
        when (activeEditor.column.type) {
            NotebookColumnType.NUMERIC,
            NotebookColumnType.ICON,
            NotebookColumnType.ORDINAL,
            NotebookColumnType.ATTENDANCE,
            NotebookColumnType.CHECK,
            NotebookColumnType.TEXT -> {
                CellInputOverlay(
                    type = activeEditor.column.type,
                    initialValue = activeEditor.currentValue,
                    onValueChange = { newValue ->
                        viewModel.confirmAndAdvance(activeEditor.studentIndex, activeEditor.column, newValue)
                    },
                    onDismiss = { viewModel.clearActiveEditor() }
                )
            }
            else -> {
                // Para tipos desconocidos o que no deberían tener overlay si se colaran
                viewModel.clearActiveEditor()
            }
        }
    }

    // ── Duplicate Config Dialog ───────────────────────────
    if (showDuplicateDialog) {
        DuplicateConfigDialog(
            classes   = classes.filter { it.id != classId },
            onDismiss = { showDuplicateDialog = false },
            onConfirm = { targetId -> viewModel.duplicateConfigToClass(targetId); showDuplicateDialog = false; onStatus("Configuración duplicada") }
        )
    }

    // ── Formula Editor Dialog ─────────────────────────────
    val currentFormulaCol = showFormulaDialog
    if (currentFormulaCol != null) {
        FormulaEditorDialog(
            column           = currentFormulaCol,
            availableCodes   = emptyList(),
            formulaEvaluator = formulaEvaluator,
            onDismiss        = { showFormulaDialog = null },
            onSave           = { updatedFormula ->
                viewModel.saveColumn(currentFormulaCol.copy(formula = updatedFormula))
                showFormulaDialog = null
                onStatus("Fórmula actualizada")
            }
        )
    }

    // ── Add Student Dialog ────────────────────────────────
    if (showAddStudentDialog) {
        AddStudentDialog(
            onDismiss = { showAddStudentDialog = false },
            onSave    = { firstName, lastName, _, isInjured ->
                viewModel.addStudent(firstName, lastName, isInjured)
                showAddStudentDialog = false
                onStatus("Alumno añadido")
            }
        )
    }

    if (showGroupDialog) {
        val currentState = uiState as? NotebookUiState.Data
        val currentTabId = selectedNotebookTab.takeIf { it.isNotBlank() } ?: currentState?.sheet?.tabs?.firstOrNull()?.id
        val tabGroups = currentState?.sheet?.workGroups.orEmpty().filter { it.tabId == currentTabId }
        val groupedRows = currentState?.sheet?.groupedRowsFor(currentTabId).orEmpty()
        val visibleRows = groupedRows.flatMap { it.rows }
        var selectedGroupId by remember(currentTabId, tabGroups) { mutableStateOf(tabGroups.firstOrNull()?.id) }
        var newGroupName by remember(currentTabId) { mutableStateOf("") }
        var selectedStudentIds by remember(selectedGroupId, currentTabId, currentState?.sheet?.workGroupMembers) {
            mutableStateOf(
                if (selectedGroupId == null) {
                    emptySet()
                } else {
                    currentState?.sheet?.workGroupMembers
                        ?.filter { it.tabId == currentTabId && it.groupId == selectedGroupId }
                        ?.map { it.studentId }
                        ?.toSet()
                        ?: emptySet()
                }
            )
        }

        AlertDialog(
            onDismissRequest = { showGroupDialog = false },
            modifier = Modifier.width(600.dp).heightIn(max = 800.dp),
            title = { Text("Grupos de trabajo") },
            text = {
                Column(
                    modifier = Modifier.heightIn(max = 520.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                        text = "Selecciona varios alumnos y asígnalos a un grupo para la pestaña actual.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.outline
                    )

                    OutlinedTextField(
                        value = newGroupName,
                        onValueChange = { newGroupName = it },
                        label = { Text("Nuevo grupo") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )

                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = {
                                val trimmed = newGroupName.trim()
                                if (trimmed.isNotEmpty()) {
                                    viewModel.saveWorkGroup(trimmed, studentIds = selectedStudentIds.toList())
                                    newGroupName = ""
                                }
                            },
                            enabled = newGroupName.isNotBlank()
                        ) {
                            Text("Crear y asignar")
                        }

                        OutlinedButton(
                            onClick = {
                                val groupId = selectedGroupId
                                if (groupId != null) {
                                    viewModel.assignStudentsToWorkGroup(groupId, selectedStudentIds.toList())
                                }
                            },
                            enabled = selectedGroupId != null && selectedStudentIds.isNotEmpty()
                        ) {
                            Text("Asignar")
                        }

                        OutlinedButton(
                            onClick = {
                                viewModel.assignStudentsToWorkGroup(null, selectedStudentIds.toList())
                            },
                            enabled = selectedStudentIds.isNotEmpty()
                        ) {
                            Text("Quitar")
                        }
                    }

                    if (tabGroups.isNotEmpty()) {
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            tabGroups.forEach { group ->
                                FilterChip(
                                    selected = selectedGroupId == group.id,
                                    onClick = {
                                        selectedGroupId = group.id
                                        selectedStudentIds = currentState?.sheet?.workGroupMembers
                                            ?.filter { it.tabId == currentTabId && it.groupId == group.id }
                                            ?.map { it.studentId }
                                            ?.toSet()
                                            ?: emptySet()
                                    },
                                    label = { Text(group.name) }
                                )
                            }
                        }
                    } else {
                        Text("Todavía no hay grupos en esta pestaña.", color = MaterialTheme.colorScheme.outline)
                    }

                    val selectableRows = visibleRows
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TextButton(onClick = {
                            selectedStudentIds = selectableRows.map { it.student.id }.toSet()
                        }) { Text("Seleccionar todos") }
                        TextButton(onClick = { selectedStudentIds = emptySet() }) { Text("Limpiar") }
                    }

                    LazyColumn(
                        modifier = Modifier.weight(1f).fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        items(selectableRows, key = { it.student.id }) { row ->
                            val checked = selectedStudentIds.contains(row.student.id)
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        selectedStudentIds = if (checked) {
                                            selectedStudentIds - row.student.id
                                        } else {
                                            selectedStudentIds + row.student.id
                                        }
                                    }
                                    .padding(vertical = 4.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Checkbox(
                                    checked = checked,
                                    onCheckedChange = {
                                        selectedStudentIds = if (it) {
                                            selectedStudentIds + row.student.id
                                        } else {
                                            selectedStudentIds - row.student.id
                                        }
                                    }
                                )
                                Spacer(Modifier.width(8.dp))
                                Text("${row.student.lastName}, ${row.student.firstName}")
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showGroupDialog = false }) {
                    Text("Cerrar")
                }
            }
        )
    }

    // ── Import Result ─────────────────────────────────────
    if (showImportDialog) {
        val result = importResultState
        if (result != null) {
            when (result) {
                is ImportResult.Success        -> { onStatus("Importación realizada: ${result.students.size} alumnos."); viewModel.clearImportResult(); showImportDialog = false }
                is ImportResult.PartialSuccess -> { onStatus("Importación parcial: ${result.students.size} alumnos."); viewModel.clearImportResult(); showImportDialog = false }
                is ImportResult.Failure        -> { onStatus("Error: ${result.reason}"); viewModel.clearImportResult(); showImportDialog = false }
            }
        }
    }

    // ── Delete Student Confirmation ───────────────────────
    val currentStudentToDelete = studentToDelete
    if (currentStudentToDelete != null) {
        AlertDialog(
            onDismissRequest = { studentToDelete = null },
            title = { Text("Eliminar Alumno") },
            text  = { Text("¿Estás seguro de que deseas eliminar a ${currentStudentToDelete.firstName} ${currentStudentToDelete.lastName}? Esta acción no se puede deshacer.") },
            confirmButton = {
                Button(
                    onClick = { viewModel.deleteStudent(currentStudentToDelete.id); studentToDelete = null; onStatus("Alumno eliminado") },
                    colors  = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
                ) { Text("Eliminar") }
            },
            dismissButton = { TextButton(onClick = { studentToDelete = null }) { Text("Cancelar") } }
        )
    }
}

// ─────────────────────────────────────────────────────────
// Toolbar
// ─────────────────────────────────────────────────────────

@Composable
private fun NotebookTopBar(
    classes: List<SchoolClass>,
    selectedClass: SchoolClass?,
    onClassSelected: (SchoolClass) -> Unit,
    saveState: NotebookViewModelSaveState,
    onSave: () -> Unit,
    density: NotebookDensity,
    onDensityToggle: () -> Unit,
    onLoad: () -> Unit,
    onUndo: () -> Unit
) {
    ContextBar(
        classes = classes,
        selectedClass = selectedClass,
        onClassSelected = onClassSelected,
        saveState = saveState,
        onSave = onSave,
        density = density,
        onDensityToggle = onDensityToggle,
        onLoad = onLoad,
        onUndo = onUndo
    )
}

@Composable
private fun NotebookGridSection(
    modifier: Modifier = Modifier,
    tones: NotebookSurfaceTones,
    state: NotebookUiState.Data,
    viewModel: NotebookViewModel,
    dataState: NotebookUiState.Data,
    activeCell: ActiveCell?,
    density: NotebookDensity,
    selectedNotebookTab: String,
    gridUiModel: NotebookGridUiModel,
    onEditFormula: (NotebookColumnDefinition) -> Unit,
    onDeleteStudent: (com.migestor.shared.domain.Student) -> Unit,
    onDeleteColumn: (NotebookColumnDefinition) -> Unit,
    onOpenRubric: (com.migestor.shared.domain.Student, Long, Long, String) -> Unit,
    onBulkRubricEval: (Long, Long, String) -> Unit,
    onToggleColumnSelection: (String) -> Unit,
) {
    Box(modifier) {
        OrganicGlassCard(
            modifier = Modifier.fillMaxSize(),
            cornerRadius = NotebookGeometry.cardRadius,
            backgroundColor = tones.panelBackground,
            borderColor = tones.panelBorder
        ) {
            Box(Modifier.padding(NotebookGeometry.cardPadding)) {
                NotebookGrid(
                    sheet = state.sheet,
                    viewModel = viewModel,
                    dataState = dataState,
                    uiModel = gridUiModel,
                    activeCell = activeCell,
                    selectedTabId = selectedNotebookTab,
                    density = density,
                    isSelectionMode = state.isColumnSelectionMode,
                    selectedColumnIds = state.selectedColumnIds,
                    onEditFormula = onEditFormula,
                    onDeleteStudent = onDeleteStudent,
                    onDeleteColumn = onDeleteColumn,
                    onOpenRubric = onOpenRubric,
                    onBulkRubricEval = onBulkRubricEval,
                    onToggleColumnSelection = onToggleColumnSelection
                )
            }
        }

        if (state.isColumnSelectionMode && state.selectedColumnIds.isNotEmpty()) {
            BulkActionBar(
                modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 16.dp),
                selectedCount = state.selectedColumnIds.size,
                onDelete = { viewModel.deleteSelectedColumns() },
                onClear = { viewModel.clearColumnSelection() }
            )
        }
    }
}

@Composable
fun GroupSummaryBar(
    sheet: NotebookSheet,
    viewModel: NotebookViewModel
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = NotebookGeometry.cardPadding),
        horizontalArrangement = Arrangement.spacedBy(NotebookGeometry.interElementSpace)
    ) {
        val avg = viewModel.calculateClassAverage(sheet)
        val pending = viewModel.countUnevaluatedStudents(sheet)
        val approved = viewModel.countApproved(sheet)
        
        StatChip("Media de Clase", "%.2f".format(avg), if (avg >= 5) GreenGlass else RedGlass)
        StatChip("Pendientes", pending.toString(), if (pending > 0) OrangeGlass else BlueGlass)
        StatChip("Aprobados", "$approved/${sheet.rows.size}", BlueGlass)
    }
}

@Composable
fun ContextBar(
    classes: List<SchoolClass>,
    selectedClass: SchoolClass?,
    onClassSelected: (SchoolClass) -> Unit,
    saveState: NotebookViewModelSaveState,
    onSave: () -> Unit,
    density: NotebookDensity,
    onDensityToggle: () -> Unit,
    onLoad: () -> Unit,
    onUndo: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // 1. Class Selector
        ClassSelectorChip(classes, selectedClass, onClassSelected)
        
        Spacer(Modifier.width(16.dp))
        
        // 2. Save State Indicator (Interactive)
        SaveStateIndicator(saveState, onSave)
        
        Spacer(Modifier.weight(1f))
        
        // 3. Toolbar Actions (Density, Reload, Undo)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            IconButton(onClick = onUndo, modifier = Modifier.size(44.dp)) {
                Icon(Icons.Default.Undo, "Deshacer", tint = MaterialTheme.colorScheme.primary)
            }
            IconButton(onClick = onLoad, modifier = Modifier.size(44.dp)) {
                Icon(Icons.Default.Refresh, "Recargar")
            }
            IconButton(onClick = onDensityToggle, modifier = Modifier.size(44.dp)) {
                Icon(
                    if (density == NotebookDensity.COMPACT) Icons.Default.ViewHeadline else Icons.Default.ViewStream,
                    "Cambiar densidad"
                )
            }
        }
    }
}

@Composable
private fun ActionBar(
    tabs: List<NotebookSheetTab>,
    selectedTabId: String,
    onTabSelected: (String) -> Unit,
    actions: NotebookActions,
) {
    val rootTabs = tabs.filter { it.parentTabId == null }.sortedWith(compareBy<NotebookSheetTab> { it.order }.thenBy { it.id })
    val selectedTab = tabs.firstOrNull { it.id == selectedTabId }
    val selectedRootId = when {
        selectedTab?.parentTabId != null -> selectedTab.parentTabId
        rootTabs.any { it.id == selectedTabId } -> selectedTabId
        else -> rootTabs.firstOrNull()?.id
    }
    val childTabs = tabs.filter { it.parentTabId == selectedRootId }.sortedWith(compareBy<NotebookSheetTab> { it.order }.thenBy { it.id })
    var overflowExpanded by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            ScrollableTabRow(
                selectedTabIndex = rootTabs.indexOfFirst { it.id == selectedRootId }.coerceAtLeast(0),
                edgePadding = 0.dp,
                divider = {},
                containerColor = Color.Transparent,
                modifier = Modifier.weight(1f)
            ) {
                rootTabs.forEach { tab ->
                    Tab(
                        selected = tab.id == selectedRootId,
                        onClick = {
                            val children = tabs.filter { it.parentTabId == tab.id }.sortedWith(compareBy<NotebookSheetTab> { it.order }.thenBy { it.id })
                            onTabSelected(children.firstOrNull()?.id ?: tab.id)
                        },
                        text = { Text(tab.title, style = MaterialTheme.typography.labelLarge) }
                    )
                }

                IconButton(onClick = actions.onAddTab, modifier = Modifier.size(44.dp)) {
                    Icon(Icons.Default.Add, "Nueva Pestaña", Modifier.size(20.dp))
                }
            }

            Spacer(Modifier.width(16.dp))

            Button(
                onClick = actions.onAddColumn,
                shape = RoundedCornerShape(NotebookVisualTokens.chipCorner),
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                modifier = Modifier.height(44.dp)
            ) {
                Icon(Icons.Default.AddBox, null, Modifier.size(16.dp))
                Spacer(Modifier.width(4.dp))
                Text("Columna", fontSize = 13.sp)
            }

            Spacer(Modifier.width(8.dp))

            IconButton(onClick = actions.onAddStudent, modifier = Modifier.size(44.dp)) {
                Icon(Icons.Default.PersonAdd, "Nuevo Alumno", Modifier.size(20.dp))
            }

            Box {
                IconButton(onClick = { overflowExpanded = true }, modifier = Modifier.size(44.dp)) {
                    Icon(Icons.Default.MoreVert, "Más acciones")
                }
                DropdownMenu(expanded = overflowExpanded, onDismissRequest = { overflowExpanded = false }) {
                    DropdownMenuItem(
                        text = { Text("Nueva pestaña") },
                        leadingIcon = { Icon(Icons.Default.Add, contentDescription = null) },
                        onClick = {
                            overflowExpanded = false
                            actions.onAddTab()
                        }
                    )
                    if (tabs.size > 1 && selectedTab != null) {
                        DropdownMenuItem(
                            text = { Text("Eliminar pestaña", color = MaterialTheme.colorScheme.error) },
                            leadingIcon = {
                                Icon(
                                    Icons.Default.Close,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.error
                                )
                            },
                            onClick = {
                                overflowExpanded = false
                                actions.onDeleteTab()
                            }
                        )
                    }
                    DropdownMenuItem(
                        text = { Text("Gestionar categorías") },
                        leadingIcon = { Icon(Icons.Default.ViewColumn, contentDescription = null) },
                        onClick = {
                            overflowExpanded = false
                            actions.onManageCategories()
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Gestionar grupos") },
                        leadingIcon = { Icon(Icons.Default.Groups, contentDescription = null) },
                        onClick = {
                            overflowExpanded = false
                            actions.onManageGroups()
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Importar CSV") },
                        leadingIcon = { Icon(Icons.Default.FileUpload, contentDescription = null) },
                        onClick = {
                            overflowExpanded = false
                            actions.onImportCSV()
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Duplicar estructura") },
                        leadingIcon = { Icon(Icons.Default.CopyAll, contentDescription = null) },
                        onClick = {
                            overflowExpanded = false
                            actions.onDuplicateConfig()
                        }
                    )
                }
            }
        }

        if (childTabs.isNotEmpty()) {
            ScrollableTabRow(
                selectedTabIndex = childTabs.indexOfFirst { it.id == selectedTabId }.coerceAtLeast(0),
                edgePadding = 0.dp,
                divider = {},
                containerColor = Color.Transparent
            ) {
                childTabs.forEach { tab ->
                    Tab(
                        selected = tab.id == selectedTabId,
                        onClick = { onTabSelected(tab.id) },
                        text = { Text(tab.title, style = MaterialTheme.typography.labelMedium) }
                    )
                }
            }
        }
    }
}

@Composable
fun SaveStateIndicator(state: NotebookViewModelSaveState, onSave: () -> Unit) {
    val feedback = state.toAppFeedbackState(
        errorColor = MaterialTheme.colorScheme.error,
        neutralColor = MaterialTheme.colorScheme.outline
    )
    
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .clip(RoundedCornerShape(NotebookGeometry.cellRadius))
            .background(feedback.color.copy(alpha = 0.08f))
            .then(if (feedback.actionable) Modifier.clickable { onSave() } else Modifier)
            .padding(horizontal = 12.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Icon(feedback.icon, null, Modifier.size(16.dp), tint = feedback.color)
        Text(feedback.label, style = MaterialTheme.typography.labelMedium, color = feedback.color)
        if (feedback.actionable) {
            Icon(Icons.Default.Save, null, Modifier.size(14.dp), tint = feedback.color)
        }
    }
}

@Composable
fun ClassSelectorChip(
    classes: List<SchoolClass>,
    selectedClass: SchoolClass?,
    onClassSelected: (SchoolClass) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    
    Box {
        OrganicGlassCard(
            modifier = Modifier.clickable { expanded = true },
            cornerRadius = 8.dp
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    selectedClass?.let { "${it.course}º - ${it.name}" } ?: "Seleccionar Clase",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                Icon(Icons.Default.KeyboardArrowDown, null, Modifier.size(18.dp))
            }
        }
        
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            classes.forEach { schoolClass ->
                DropdownMenuItem(
                    text = {
                        Column {
                            Text("${schoolClass.course}º - ${schoolClass.name}", fontWeight = FontWeight.Bold)
                            schoolClass.description?.let {
                                Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
                            }
                        }
                    },
                    onClick = {
                        onClassSelected(schoolClass)
                        expanded = false
                    }
                )
            }
        }
    }
}

// ─────────────────────────────────────────────────────────
// Grid
// ─────────────────────────────────────────────────────────

// ── Speed Entry Components ──────────────────────────────────────────

@Composable
fun SpeedEntryCellFactory(
    studentIndex: Int,
    column: NotebookColumnDefinition,
    value: String,
    isActive: Boolean,
    onValueChange: (String) -> Unit,
    onConfirm: (String) -> Unit,
    onBack: () -> Unit
) {
    val contract = remember(column) { column.toSpeedContract() }

    when (contract) {
        is SpeedEntryContract.TextInput -> {
            TextInputCell(
                value = value,
                isActive = isActive,
                isNumeric = column.type == NotebookColumnType.NUMERIC,
                onValueChange = onValueChange,
                onConfirm = onConfirm,
                onBack = onBack
            )
        }
        is SpeedEntryContract.CycleOptions -> {
            CycleOptionsCell(
                current = value,
                options = contract.options,
                isActive = isActive,
                displayIcon = { if (contract.isAttendance) attendanceIcon(it) else iconNameToVector(it) },
                displayText = { if (contract.isAttendance) attendanceLabel(it) else it },
                onValueChange = onValueChange,
                onSelect = onConfirm
            )
        }
        is SpeedEntryContract.InstantToggle -> {
            InstantToggleCell(
                checked = value.toBoolean(),
                isActive = isActive,
                onToggle = { onConfirm((!value.toBoolean()).toString()) }
            )
        }
        is SpeedEntryContract.ModalAction -> {
            ModalActionCell(value = value, isActive = isActive)
        }
        is SpeedEntryContract.ReadOnly -> {
            CellContainer(isActive = isActive) {
                Text(
                    text = value.ifBlank { "—" },
                    style = cellTextStyle(),
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f)
                )
            }
        }
    }
}

@Composable
fun CellContainer(
    isActive: Boolean,
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit
) {
    val backgroundColor by animateColorAsState(
        if (isActive) MaterialTheme.colorScheme.primary.copy(alpha = 0.08f)
        else Color.Transparent
    )
    val borderColor = if (isActive) MaterialTheme.colorScheme.primary else Color.Transparent

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(backgroundColor)
            .border(width = if (isActive) 1.5.dp else 0.dp, color = borderColor)
            .padding(horizontal = 8.dp),
        contentAlignment = Alignment.CenterStart,
        content = content
    )
}

@Composable
fun TextInputCell(
    value: String,
    isActive: Boolean,
    isNumeric: Boolean,
    onValueChange: (String) -> Unit,
    onConfirm: (String) -> Unit,
    onBack: () -> Unit
) {
    CellContainer(isActive = isActive) {
        val focusRequester = remember { FocusRequester() }
        androidx.compose.foundation.text.BasicTextField(
            value = value,
            onValueChange = onValueChange,
            textStyle = cellTextStyle().copy(
                textAlign = if (isNumeric) TextAlign.End else TextAlign.Start,
                color = MaterialTheme.colorScheme.onSurface
            ),
            cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
            modifier = Modifier
                .fillMaxWidth()
                .focusRequester(focusRequester)
                .onKeyEvent { keyEvent ->
                    if (keyEvent.type == KeyEventType.KeyDown) {
                        when (keyEvent.key) {
                            Key.Enter, Key.Tab -> {
                                onConfirm(value)
                                true
                            }
                            Key.Backspace -> {
                                if (value.isEmpty()) {
                                    onBack()
                                    true
                                } else false
                            }
                            else -> false
                        }
                    } else false
                },
            singleLine = true,
            decorationBox = { innerTextField ->
                if (value.isEmpty() && !isActive) {
                    Text("—", style = cellTextStyle(), color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f))
                }
                innerTextField()
            }
        )

        // Auto-focus logic
        if (isActive) {
            LaunchedEffect(Unit) {
                focusRequester.requestFocus()
            }
        }
    }
}

@Composable
fun CycleOptionsCell(
    current: String,
    options: List<String>,
    isActive: Boolean,
    displayIcon: (String) -> ImageVector?,
    displayText: (String) -> String,
    onValueChange: (String) -> Unit,
    onSelect: (String) -> Unit
) {
    val currentIndex = remember(current, options) { options.indexOf(current).coerceAtLeast(0) }
    val focusRequester = remember { FocusRequester() }
    
    LaunchedEffect(isActive) {
        if (isActive) focusRequester.requestFocus()
    }

    CellContainer(
        isActive = isActive,
        modifier = Modifier
            .focusRequester(focusRequester)
            .focusable()
            .onKeyEvent { keyEvent ->
                if (isActive && keyEvent.type == KeyEventType.KeyDown) {
                    when (keyEvent.key) {
                        Key.DirectionUp, Key.DirectionLeft -> {
                            val prev = if (currentIndex > 0) currentIndex - 1 else options.size - 1
                            val newValue = options[prev]
                            onValueChange(newValue)
                            onSelect(newValue)
                            true
                        }
                        Key.DirectionDown, Key.DirectionRight -> {
                            val next = if (currentIndex < options.size - 1) currentIndex + 1 else 0
                            val newValue = options[next]
                            onValueChange(newValue)
                            onSelect(newValue)
                            true
                        }
                        Key.Enter, Key.Tab -> {
                            onSelect(current)
                            true
                        }
                        Key.P -> { if (options.contains("P")) { onSelect("P"); true } else false }
                        Key.A -> { if (options.contains("A")) { onSelect("A"); true } else false }
                        Key.R -> { if (options.contains("R")) { onSelect("R"); true } else false }
                        Key.J -> { if (options.contains("J")) { onSelect("J"); true } else false }
                        Key.T -> { if (options.contains("T")) { onSelect("T"); true } else false }
                        else -> false
                    }
                } else false
            }
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            val icon = displayIcon(current)
            if (icon != null) {
                Icon(icon, contentDescription = null, modifier = Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
            }
            Text(
                text = if (current.isEmpty()) "—" else displayText(current),
                style = cellTextStyle(),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
fun InstantToggleCell(
    checked: Boolean,
    isActive: Boolean,
    onToggle: () -> Unit
) {
    CellContainer(
        isActive = isActive,
        modifier = Modifier.onKeyEvent { keyEvent ->
            if (isActive && keyEvent.type == KeyEventType.KeyDown) {
                when (keyEvent.key) {
                    Key.Spacebar, Key.Enter -> {
                        onToggle()
                        true
                    }
                    else -> false
                }
            } else false
        }.focusable()
    ) {
        Checkbox(
            checked = checked,
            onCheckedChange = { onToggle() },
            modifier = Modifier.size(20.dp)
        )
    }
}

@Composable
fun ModalActionCell(
    value: String,
    isActive: Boolean
) {
    CellContainer(isActive = isActive) {
        Box(contentAlignment = Alignment.CenterStart, modifier = Modifier.fillMaxSize()) {
            Text(
                text = value.ifBlank { "Evaluar..." },
                style = cellTextStyle(),
                color = if (value.isBlank()) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun cellTextStyle() = MaterialTheme.typography.bodySmall.copy(
    fontSize = 12.sp,
    fontWeight = FontWeight.Medium
)

// ── Mappings ────────────────────────────────────────────────────────

fun iconNameToVector(name: String): ImageVector? {
    return when (name) {
        "star" -> Icons.Default.Star
        "heart" -> Icons.Default.Favorite
        "thumb_up" -> Icons.Default.ThumbUp
        "warning" -> Icons.Default.Warning
        else -> null
    }
}

fun attendanceLabel(code: String): String {
    return when (code) {
        "P" -> "Presente"
        "A" -> "Ausente"
        "R" -> "Retraso"
        "J" -> "Justificado"
        "T" -> "Tarea"
        else -> code
    }
}

fun attendanceIcon(code: String): ImageVector? {
    return when (code) {
        "P" -> Icons.Default.CheckCircle
        "A" -> Icons.Default.Cancel
        "R" -> Icons.Default.Schedule
        "J" -> Icons.Default.Description
        "T" -> Icons.Default.Edit
        else -> null
    }
}

@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun NotebookGrid(
    sheet: NotebookSheet,
    uiModel: NotebookGridUiModel,
    viewModel: NotebookViewModel,
    dataState: NotebookUiState.Data,
    activeCell: ActiveCell?,
    selectedTabId: String?,
    density: NotebookDensity,
    isSelectionMode: Boolean,
    selectedColumnIds: Set<String>,
    onEditFormula: (NotebookColumnDefinition) -> Unit,
    onDeleteStudent: (com.migestor.shared.domain.Student) -> Unit,
    onDeleteColumn: (NotebookColumnDefinition) -> Unit,
    onOpenRubric: (com.migestor.shared.domain.Student, Long, Long, String) -> Unit,
    onBulkRubricEval: (Long, Long, String) -> Unit,
    onToggleColumnSelection: (String) -> Unit,
) {
    val notebookTones = rememberNotebookSurfaceTones()
    val horizontalScroll = rememberScrollState()
    val composeDensity = androidx.compose.ui.platform.LocalDensity.current
    val data = dataState
    
    val STUDENT_COL_W    = 208.dp
    val DATA_COL_W       = 144.dp
    val AVG_COL_W        = 90.dp
    val MIN_DATA_COL_W   = 96.dp
    val COLLAPSED_COL_W  = 18.dp

    val widthOverrides = remember { mutableStateMapOf<String, Dp>() }
    val headerBounds = remember { mutableStateMapOf<String, Rect>() }
    var draggingColumnId by remember { mutableStateOf<String?>(null) }
    var dragPointerPosition by remember { mutableStateOf<Offset?>(null) }
    var resizingColumnId by remember { mutableStateOf<String?>(null) }
    var resizeStartWidth by remember { mutableStateOf<Dp?>(null) }
    var resizePreviewWidth by remember { mutableStateOf<Dp?>(null) }
    var menuColumnId by remember { mutableStateOf<String?>(null) }
    data class CategoryHeaderSegment(
        val category: NotebookColumnCategory?,
        val columns: List<NotebookColumnDefinition>,
    )

    fun resolvedWidthFor(column: NotebookColumnDefinition): Dp {
        val override = widthOverrides[column.id]
        if (override != null) return override.coerceAtLeast(MIN_DATA_COL_W)
        return (column.widthDp.takeIf { it > 0.0 }?.toFloat()?.dp ?: DATA_COL_W).coerceAtLeast(MIN_DATA_COL_W)
    }
    fun isColumnCollapsed(column: NotebookColumnDefinition): Boolean {
        val category = column.categoryId?.let { id ->
            sheet.columnCategories.firstOrNull { it.id == id && it.tabId == selectedTabId }
        }
        return category?.isCollapsed == true
    }
    fun targetWidthFor(column: NotebookColumnDefinition): Dp {
        return if (isColumnCollapsed(column)) COLLAPSED_COL_W else resolvedWidthFor(column)
    }

    val dropTargetId = dragPointerPosition?.let { pointer ->
        headerBounds.entries.firstOrNull { (columnId, bounds) ->
            columnId != draggingColumnId && bounds.contains(pointer)
        }?.key
    }

    val visibleColumnsSorted = uiModel.visibleColumns
    val categoriesById = remember(sheet.columnCategories, selectedTabId) {
        sheet.columnCategories
            .filter { it.tabId == selectedTabId }
            .associateBy { it.id }
    }
    val displayedVisibleCols = visibleColumnsSorted
    val headerSegments = remember(visibleColumnsSorted, categoriesById) {
        val segments = mutableListOf<CategoryHeaderSegment>()
        visibleColumnsSorted.forEach { column ->
            val category = column.categoryId?.let { categoriesById[it] }
            val last = segments.lastOrNull()
            if (last != null && last.category?.id == category?.id) {
                segments[segments.lastIndex] = last.copy(columns = last.columns + column)
            } else {
                segments += CategoryHeaderSegment(category = category, columns = listOf(column))
            }
        }
        segments
    }

    LaunchedEffect(displayedVisibleCols.map { it.id to it.widthDp }) {
        displayedVisibleCols.forEach { column ->
            val override = widthOverrides[column.id] ?: return@forEach
            val modelWidth = (column.widthDp.takeIf { it > 0.0 }?.toFloat()?.dp ?: DATA_COL_W).coerceAtLeast(MIN_DATA_COL_W)
            if (kotlin.math.abs(override.value - modelWidth.value) < 0.5f) {
                widthOverrides.remove(column.id)
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(notebookTones.gridBase)
    ) {
        if (headerSegments.any { it.category != null }) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Spacer(modifier = Modifier.width(STUDENT_COL_W + 1.dp))
                Row(
                    modifier = Modifier
                        .horizontalScroll(horizontalScroll)
                        .weight(1f)
                        .animateContentSize(),
                    horizontalArrangement = Arrangement.spacedBy(0.dp)
                ) {
                    headerSegments.forEach { segment ->
                        val category = segment.category ?: run {
                            val spacerWidth = segment.columns.fold(0.dp) { acc, col -> acc + targetWidthFor(col) }
                            Spacer(modifier = Modifier.width(spacerWidth))
                            return@forEach
                        }
                        val isCollapsed = category.isCollapsed
                        val expandedWidth = segment.columns.fold(0.dp) { acc, col -> acc + resolvedWidthFor(col) }.coerceAtLeast(112.dp)
                        val collapsedWidth = segment.columns.fold(0.dp) { acc, _ -> acc + COLLAPSED_COL_W }.coerceAtLeast(72.dp)
                        val targetWidth = if (isCollapsed) collapsedWidth else expandedWidth
                        val rotation by animateFloatAsState(if (isCollapsed) -90f else 0f)
                        Surface(
                            onClick = { viewModel.toggleColumnCategoryCollapsed(category.id, !isCollapsed) },
                            shape = RoundedCornerShape(10.dp),
                            color = notebookTones.gridHeaderSoft.copy(alpha = 0.82f),
                            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.65f)),
                            modifier = Modifier
                                .width(targetWidth)
                                .height(30.dp)
                                .animateContentSize()
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .padding(horizontal = 8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    imageVector = Icons.Default.ExpandMore,
                                    contentDescription = null,
                                    modifier = Modifier.size(14.dp).graphicsLayer { rotationZ = rotation },
                                    tint = MaterialTheme.colorScheme.primary
                                )
                                Spacer(Modifier.width(4.dp))
                                if (!isCollapsed) {
                                    Text(
                                        category.name,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                        fontSize = 11.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        modifier = Modifier.weight(1f)
                                    )
                                } else {
                                    Spacer(Modifier.weight(1f))
                                }
                                AnimatedVisibility(
                                    visible = isCollapsed,
                                    enter = fadeIn() + expandHorizontally(),
                                    exit = fadeOut() + shrinkHorizontally()
                                ) {
                                    Text(
                                        text = "+${segment.columns.size}",
                                        fontSize = 10.sp,
                                        color = MaterialTheme.colorScheme.outline
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            HeaderCell("Alumno", STUDENT_COL_W)
            
            VerticalDivider(
                thickness = 1.dp, 
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
                modifier = Modifier.height(76.dp)
            )

            Row(modifier = Modifier.horizontalScroll(horizontalScroll).weight(1f)) {
                displayedVisibleCols.forEach { col ->
                    val isCollapsedCol = isColumnCollapsed(col)
                    val columnWidth by animateDpAsState(targetWidthFor(col))
                    val isDragging = draggingColumnId == col.id
                    val isDropTarget = dropTargetId == col.id
                    val isResizing = resizingColumnId == col.id
                    val currentColor = col.colorHex?.hexToColor()

                    Box(
                        modifier = Modifier
                            .width(columnWidth)
                            .height(76.dp)
                            .onGloballyPositioned { coordinates ->
                                headerBounds[col.id] = coordinates.boundsInRoot()
                            }
                            .border(
                                width = if (isDropTarget) 2.dp else if (isDragging || isResizing) 1.dp else 0.dp,
                                color = when {
                                    isDropTarget -> MaterialTheme.colorScheme.primary
                                    isDragging -> MaterialTheme.colorScheme.primary.copy(alpha = 0.8f)
                                    isResizing -> MaterialTheme.colorScheme.secondary.copy(alpha = 0.8f)
                                    else -> Color.Transparent
                                },
                                shape = RoundedCornerShape(NotebookVisualTokens.buttonCorner)
                            )
                            .clip(RoundedCornerShape(NotebookVisualTokens.buttonCorner))
                            .background(Color.Transparent)
                            .then(
                                if (!isCollapsedCol) {
                                    Modifier.pointerInput(col.id) {
                                        detectTapGestures(onLongPress = { menuColumnId = col.id })
                                    }
                                } else Modifier
                            )
                    ) {
                        if (isCollapsedCol) {
                            Box(
                                modifier = Modifier
                                    .fillMaxHeight()
                                    .padding(vertical = 6.dp, horizontal = 3.dp)
                                    .clip(RoundedCornerShape(NotebookVisualTokens.chipCorner))
                                    .background(currentColor?.copy(alpha = 0.35f) ?: notebookTones.collapsedColumn)
                            )
                        } else {
                            HeaderCell(
                                text              = col.title,
                                width             = columnWidth,
                                subtitle          = "${col.type.label()} · ${columnWidth.value.toInt()}dp",
                                isFormula         = col.type == NotebookColumnType.CALCULATED,
                                onFormulaClick    = if (col.type == NotebookColumnType.CALCULATED) { { onEditFormula(col) } } else null,
                                onDelete          = { onDeleteColumn(col) },
                                onBulkEval        = if (col.type == NotebookColumnType.RUBRIC && col.rubricId != null && col.evaluationId != null) { { onBulkRubricEval(col.evaluationId!!, col.rubricId!!, col.id) } } else null,
                                isSelected        = selectedColumnIds.contains(col.id),
                                isSelectionMode   = isSelectionMode,
                                accentColor       = currentColor,
                                onToggleSelection = { onToggleColumnSelection(col.id) }
                            )

                            Box(
                                modifier = Modifier
                                    .align(Alignment.TopStart)
                                    .fillMaxWidth()
                                    .height(28.dp)
                                    .padding(start = 8.dp, top = 4.dp, end = 28.dp)
                            ) {
                                Row(
                                    modifier = Modifier
                                        .align(Alignment.CenterStart)
                                        .pointerInput(col.id) {
                                            detectDragGestures(
                                                onDragStart = {
                                                    draggingColumnId = col.id
                                                    dragPointerPosition = headerBounds[col.id]?.center
                                                    menuColumnId = null
                                                },
                                                onDrag = { _, dragAmount ->
                                                    dragPointerPosition = (dragPointerPosition ?: headerBounds[col.id]?.center ?: Offset.Zero) + dragAmount
                                                },
                                                onDragEnd = {
                                                    val targetId = dropTargetId
                                                    if (targetId != null && targetId != col.id) {
                                                        viewModel.reorderColumns(col.id, targetId)
                                                    }
                                                    draggingColumnId = null
                                                    dragPointerPosition = null
                                                },
                                                onDragCancel = {
                                                    draggingColumnId = null
                                                    dragPointerPosition = null
                                                }
                                            )
                                        }
                                        .padding(horizontal = 4.dp, vertical = 2.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text("⋮⋮", fontSize = 12.sp, color = MaterialTheme.colorScheme.outline.copy(alpha = 0.7f))
                                }

                                Box(
                                    modifier = Modifier
                                        .align(Alignment.BottomEnd)
                                        .size(18.dp)
                                        .pointerInput(col.id) {
                                            detectDragGestures(
                                                onDragStart = {
                                                    resizingColumnId = col.id
                                                    resizeStartWidth = columnWidth
                                                    resizePreviewWidth = columnWidth
                                                    widthOverrides[col.id] = columnWidth
                                                    menuColumnId = null
                                                },
                                                onDrag = { _, dragAmount ->
                                                    val baseWidth = resizeStartWidth ?: columnWidth
                                                    val deltaWidth = with(composeDensity) { dragAmount.x.toDp() }
                                                    val newWidth = (baseWidth + deltaWidth).coerceAtLeast(MIN_DATA_COL_W)
                                                    resizePreviewWidth = newWidth
                                                    widthOverrides[col.id] = newWidth
                                                },
                                                onDragEnd = {
                                                    val finalWidth = resizePreviewWidth ?: widthOverrides[col.id] ?: columnWidth
                                                    widthOverrides[col.id] = finalWidth
                                                    viewModel.saveColumn(col.copy(widthDp = finalWidth.value.toDouble()))
                                                    resizingColumnId = null
                                                    resizeStartWidth = null
                                                    resizePreviewWidth = null
                                                },
                                                onDragCancel = {
                                                    widthOverrides[col.id] = columnWidth
                                                    resizingColumnId = null
                                                    resizeStartWidth = null
                                                    resizePreviewWidth = null
                                                }
                                            )
                                        },
                                    contentAlignment = Alignment.BottomEnd
                                ) {
                                    Text("◢", fontSize = 10.sp, color = MaterialTheme.colorScheme.outline.copy(alpha = 0.6f))
                                }
                            }

                            DropdownMenu(
                                expanded = menuColumnId == col.id,
                                onDismissRequest = { if (menuColumnId == col.id) menuColumnId = null }
                            ) {
                                NotebookColorPalette.forEach { hex ->
                                    DropdownMenuItem(
                                        text = {
                                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                                Box(
                                                    modifier = Modifier
                                                        .size(14.dp)
                                                        .clip(CircleShape)
                                                        .background(hex.hexToColor())
                                                )
                                                Text("Color $hex")
                                            }
                                        },
                                        onClick = {
                                            menuColumnId = null
                                            viewModel.saveColumn(col.copy(colorHex = hex))
                                        }
                                    )
                                }

                                HorizontalDivider()

                                if (col.type == NotebookColumnType.CALCULATED) {
                                    DropdownMenuItem(
                                        text = { Text("Editar fórmula") },
                                        onClick = {
                                            menuColumnId = null
                                            onEditFormula(col)
                                        }
                                    )
                                }

                                DropdownMenuItem(
                                    text = { Text("Eliminar columna", color = MaterialTheme.colorScheme.error) },
                                    onClick = {
                                        menuColumnId = null
                                        onDeleteColumn(col)
                                    }
                                )
                            }
                        }
                    }
                }
                HeaderCell("Media", AVG_COL_W)
            }
        }

        HorizontalDivider(thickness = 1.dp, color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.85f))

        val lazyState = rememberLazyListState()
    val groupedRows = uiModel.groupedRows
        LazyColumn(state = lazyState, modifier = Modifier.fillMaxSize()) {
            var visibleRowIndex = 0
            groupedRows.forEach { section ->
                val group = section.group
                if (group != null) {
                    item(key = "group_${group.id}") {
                        GroupSectionHeader(
                            title = group.name,
                            subtitle = "${section.rows.size} alumno${if (section.rows.size == 1) "" else "s"}",
                            backgroundColor = notebookTones.groupHeader
                        )
                    }
                } else if (section.isUngrouped) {
                    item(key = "ungrouped_header") {
                        GroupSectionHeader(
                            title = "Sin grupo",
                            subtitle = "${section.rows.size} alumno${if (section.rows.size == 1) "" else "s"}",
                            backgroundColor = notebookTones.groupHeader
                        )
                    }
                }

                itemsIndexed(section.rows, key = { _, row -> row.student.id }) { _, row ->
                    val rowIdx = visibleRowIndex++
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(density.rowHeight)
                                .background(if (rowIdx % 2 == 0) notebookTones.rowEven else notebookTones.rowOdd),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(
                                modifier = Modifier.width(STUDENT_COL_W).fillMaxHeight().padding(horizontal = 12.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                IconButton(onClick = { onDeleteStudent(row.student) }, modifier = Modifier.size(24.dp)) {
                                    Icon(Icons.Default.Delete, "Eliminar",
                                        tint = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                                        modifier = Modifier.size(14.dp))
                                }
                                Spacer(Modifier.width(8.dp))
                                Text(
                                    "${row.student.lastName}, ${row.student.firstName}",
                                    fontWeight = FontWeight.Medium,
                                    fontSize   = density.fontSize.sp,
                                    maxLines   = 1,
                                    overflow   = TextOverflow.Ellipsis,
                                    modifier   = Modifier.weight(1f),
                                    color = MaterialTheme.colorScheme.onSurface
                                )
                            }
                            
                            VerticalDivider(
                                thickness = 1.dp, 
                                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.2f),
                                modifier = Modifier.height(density.rowHeight)
                            )

                            Row(
                                modifier = Modifier.horizontalScroll(horizontalScroll).weight(1f).fillMaxHeight(),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                displayedVisibleCols.forEach { col ->
                                    val isCollapsedCol = isColumnCollapsed(col)
                                    val columnWidth = targetWidthFor(col)
                                    val isActive = activeCell?.studentIndex == rowIdx && activeCell.columnId == col.id
                                    val currentValue = data.getDraftValue(row.student.id, col)
                                    val calculatedValue = uiModel.calculatedCellValues[row.student.id to col.id]

                                    Box(
                                        Modifier
                                            .width(columnWidth)
                                            .fillMaxHeight()
                                            .padding(vertical = 2.dp, horizontal = 4.dp)
                                            .clip(RoundedCornerShape(NotebookGeometry.cellRadius))
                                            .background(
                                                if (isCollapsedCol) {
                                                    notebookTones.collapsedColumn.copy(alpha = 0.62f)
                                                } else if (col.type == NotebookColumnType.CALCULATED) {
                                                    gradeToBackground(calculatedValue)
                                                } else {
                                                    val valNum = currentValue.toDoubleOrNull()
                                                    gradeToBackground(valNum)
                                                }
                                            )
                                            .clickable(enabled = !isCollapsedCol && col.type != NotebookColumnType.CALCULATED) {
                                                viewModel.setActiveCell(rowIdx, col.id)
                                            }
                                    ) {
                                        if (isCollapsedCol) {
                                            // Columna contraída: reservamos espacio visual tipo acordeón
                                            Box(Modifier.fillMaxSize())
                                        } else if (col.type == NotebookColumnType.CALCULATED) {
                                            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                                Text(
                                                    text       = calculatedValue?.let { "%.2f".format(it) } ?: "—",
                                                    fontWeight = FontWeight.Bold,
                                                    fontSize   = density.fontSize.sp,
                                                    color      = if ((calculatedValue ?: 0.0) >= 5.0) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error
                                                )
                                            }
                                        } else {
                                            SpeedEntryCellFactory(
                                                studentIndex = rowIdx,
                                                column = col,
                                                value = currentValue,
                                                isActive = isActive,
                                                onValueChange = { newValue ->
                                                    viewModel.updateDraft(row.student.id, col.id, col.type, newValue)
                                                },
                                                onConfirm = { finalValue ->
                                                    viewModel.confirmAndAdvance(rowIdx, col, finalValue)
                                                },
                                                onBack = {
                                                    viewModel.moveToPreviousStudent(rowIdx, col.id)
                                                }
                                            )

                                            if (isActive) {
                                                LaunchedEffect(isActive) {
                                                    if (col.type == NotebookColumnType.RUBRIC) {
                                                        col.rubricId?.let { rId ->
                                                            col.evaluationId?.let { eId ->
                                                                onOpenRubric(row.student, eId, rId, col.id)
                                                            }
                                                        }
                                                    } else if (col.type != NotebookColumnType.CALCULATED) {
                                                        viewModel.activateEditor(rowIdx, row.student, col, currentValue)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                val manualAvg = uiModel.rowAverageByStudentId[row.student.id]
                                Box(
                                    Modifier.width(AVG_COL_W).fillMaxHeight(),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        "%.2f".format(manualAvg ?: 0.0),
                                        fontWeight = FontWeight.Bold,
                                        fontSize = density.fontSize.sp,
                                        color = MaterialTheme.colorScheme.primary
                                    )
                                }
                            }
                        }
                    HorizontalDivider(thickness = 0.5.dp, color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
                }
            }
        }
    }
}

@Composable
private fun GroupSectionHeader(
    title: String,
    subtitle: String,
    backgroundColor: Color? = null
) {
    val resolvedBackground = backgroundColor ?: MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(resolvedBackground)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
        Spacer(Modifier.width(8.dp))
        Text(subtitle, fontSize = 11.sp, color = MaterialTheme.colorScheme.outline)
    }
}

// ─────────────────────────────────────────────────────────
// Header cell
// ─────────────────────────────────────────────────────────
@Composable
private fun HeaderCell(
    text: String,
    width: Dp,
    subtitle: String? = null,
    isFormula: Boolean = false,
    onFormulaClick: (() -> Unit)? = null,
    onDelete: (() -> Unit)? = null,
    onBulkEval: (() -> Unit)? = null,
    isSelected: Boolean = false,
    isSelectionMode: Boolean = false,
    accentColor: Color? = null,
    onToggleSelection: () -> Unit = {}
) {
    val notebookTones = rememberNotebookSurfaceTones()
    val headerBase = notebookTones.gridHeaderSoft.copy(alpha = 0.88f)
    val headerBottom = notebookTones.gridHeader
    Box(
        modifier = Modifier
            .width(width)
            .height(76.dp)
            .background(
                brush = Brush.verticalGradient(
                    colors = listOf(
                        accentColor?.copy(alpha = 0.20f) ?: headerBase,
                        headerBottom
                    )
                )
            )
            .then(if (onFormulaClick != null) Modifier.clickable { onFormulaClick() } else Modifier)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        contentAlignment = Alignment.CenterStart
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxSize()) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
            if (isSelectionMode) {
                Checkbox(
                    checked = isSelected,
                    onCheckedChange = { onToggleSelection() },
                    modifier = Modifier.size(20.dp)
                )
            }
                Text(
                    text = text,
                    fontWeight = FontWeight.Bold,
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                if (isFormula) {
                    Icon(
                        Icons.Default.Functions,
                        null,
                        Modifier.size(12.dp),
                        tint = MaterialTheme.colorScheme.primary
                    )
                }
                if (accentColor != null) {
                    Box(
                        modifier = Modifier
                            .size(10.dp)
                            .background(accentColor, CircleShape)
                    )
                }
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                if (subtitle != null) {
                    Text(
                        subtitle,
                        fontSize = 10.sp,
                        color = MaterialTheme.colorScheme.outline,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f)
                    )
                } else {
                    Spacer(Modifier.weight(1f))
                }
                if (onBulkEval != null && !isSelectionMode) {
                    IconButton(onClick = onBulkEval, modifier = Modifier.size(24.dp)) {
                        Icon(
                            Icons.Default.FactCheck,
                            contentDescription = "Evaluación Masiva",
                            modifier = Modifier.size(14.dp),
                            tint = MaterialTheme.colorScheme.primary
                        )
                    }
                }

                if (onDelete != null && !isSelectionMode) {
                    IconButton(onClick = onDelete, modifier = Modifier.size(24.dp)) {
                        Icon(
                            Icons.Default.Close,
                            contentDescription = "Eliminar Columna",
                            modifier = Modifier.size(14.dp),
                            tint = MaterialTheme.colorScheme.error
                        )
                    }
                }
            }
        }
    }
}

private fun visibleColumnsForTab(
    columns: List<NotebookColumnDefinition>,
    tabs: List<NotebookSheetTab>,
    selectedTabId: String,
): List<NotebookColumnDefinition> {
    return columns.filter { column ->
        when {
            selectedTabId.isNotBlank() && column.tabIds.contains(selectedTabId) -> true
            column.sharedAcrossTabs || column.tabIds.isEmpty() -> true
            else -> false
        }
    }
}

// ─────────────────────────────────────────────────────────
// Column Preset model
// ─────────────────────────────────────────────────────────

data class ColumnPreset(
    val label: String,
    val type: NotebookColumnType,
    val icon: androidx.compose.ui.graphics.vector.ImageVector,
    val hint: String,
    val defaultTitle: String,
)

// ─────────────────────────────────────────────────────────
// Add Column Dialog
// ─────────────────────────────────────────────────────────

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AddColumnDialog(
    userRubrics: List<RubricDetail>,
    existingTabs: List<NotebookSheetTab>,
    existingCategories: List<NotebookColumnCategory>,
    preselectedTabId: String = existingTabs.firstOrNull()?.id ?: "",
    onDismiss: () -> Unit,
    onCreateCategory: (String, String) -> Unit,
    onConfirm: (NotebookColumnDefinition) -> Unit
) {
    var selectedPreset by remember { mutableStateOf<ColumnPreset?>(null) }
    var selectedRubric by remember { mutableStateOf<RubricDetail?>(null) }
    var showRubricPicker by remember { mutableStateOf(false) }
    var title          by remember { mutableStateOf("") }
    var formula        by remember { mutableStateOf("") }
    var weightStr      by remember { mutableStateOf("1.0") }
    var widthStr       by remember { mutableStateOf("144") }
    var orderStr       by remember { mutableStateOf("-1") }
    var colorHex       by remember { mutableStateOf("#4A90D9") }
    var tabIds         by remember { mutableStateOf(listOfNotNull(preselectedTabId.ifBlank { existingTabs.firstOrNull()?.id })) }
    var selectedCategoryId by remember { mutableStateOf<String?>(existingCategories.firstOrNull()?.id) }
    var newCategoryName by remember { mutableStateOf("") }

    val presets = listOf(
        ColumnPreset("Nota Numérica",  NotebookColumnType.NUMERIC,    Icons.Default.Grade,        "p.ej. 40%",                    "Examen"),
        ColumnPreset("Rúbrica",        NotebookColumnType.RUBRIC,     Icons.Default.Grading,      "Evalúa con rúbricas",          "Rúbrica"),
        ColumnPreset("Fórmula",        NotebookColumnType.CALCULATED, Icons.Default.Functions,    "p.ej. (EX1*0.4)+(TA1*0.6)",    "Final"),
        ColumnPreset("Texto libre",    NotebookColumnType.TEXT,       Icons.Default.Notes,        "Observaciones, comentarios",   "Observación"),
        ColumnPreset("Seguimiento ✓",  NotebookColumnType.CHECK,      Icons.Default.CheckBox,     "Asistencia o tarea entregada", "Seguimiento"),
        ColumnPreset("Estado / Icono", NotebookColumnType.ICON,       Icons.Default.EmojiSymbols, "🟢 🟡 🔴 o emojis",           "Estado"),
        ColumnPreset("Asistencia",     NotebookColumnType.ATTENDANCE, Icons.Default.HowToReg,     "% asistencia calculado",       "Asistencia"),
    )

    Dialog(onDismissRequest = onDismiss) {
        Surface(
            shape = RoundedCornerShape(NotebookVisualTokens.dialogCornerLarge),
            tonalElevation = 8.dp,
            modifier = Modifier.width(520.dp).heightIn(max = 760.dp)
        ) {
            Column(modifier = Modifier.fillMaxWidth()) {
                // Header
                Text(
                    text = "Añadir columna",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(start = 32.dp, top = 32.dp, end = 32.dp, bottom = 16.dp)
                )

                // Scrollable Content
                Column(
                    modifier = Modifier
                        .weight(1f, fill = false)
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 32.dp),
                    verticalArrangement = Arrangement.spacedBy(24.dp)
                ) {
                    // Type Selection
                    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        Text("Tipo de evaluación", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(16.dp),
                            verticalArrangement = Arrangement.spacedBy(16.dp)
                        ) {
                            presets.forEach { preset ->
                                val selected = selectedPreset?.label == preset.label
                                Surface(
                                    onClick = { selectedPreset = preset; if (title.isEmpty()) title = preset.defaultTitle },
                                    shape = RoundedCornerShape(16.dp),
                                    color = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                                    border = BorderStroke(1.dp, if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.5f) else Color.Transparent),
                                    modifier = Modifier.width(220.dp)
                                ) {
                                    Row(
                                        Modifier.padding(16.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                                    ) {
                                        Icon(preset.icon, null, Modifier.size(24.dp), tint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                                        Column {
                                            Text(preset.label, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, color = if (selected) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface)
                                            Text(preset.hint, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, lineHeight = 14.sp)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Configuration
                    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        Text("Configuración principal", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                        OutlinedTextField(
                            value = title, onValueChange = { title = it },
                            label = { Text("Nombre de la columna") },
                            modifier = Modifier.fillMaxWidth(),
                            singleLine = true,
                            shape = RoundedCornerShape(NotebookVisualTokens.buttonCorner)
                        )

                        if (selectedPreset?.type == NotebookColumnType.RUBRIC) {
                            Surface(
                                onClick = { showRubricPicker = true },
                                shape = RoundedCornerShape(NotebookVisualTokens.buttonCorner),
                                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                                color = MaterialTheme.colorScheme.surface
                            ) {
                                Row(
                                    Modifier.padding(16.dp).fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Column(Modifier.weight(1f)) {
                                        Text("Rúbrica seleccionada", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                                        Text(selectedRubric?.rubric?.name ?: "Toca para seleccionar rúbrica...", fontWeight = FontWeight.Medium)
                                    }
                                    Icon(Icons.Default.ArrowForwardIos, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.outline)
                                }
                            }
                        }

                        if (selectedPreset?.type == NotebookColumnType.CALCULATED) {
                            OutlinedTextField(
                                value = formula, onValueChange = { formula = it },
                                label = { Text("Fórmula (ej: (EX1*0.4)+(TA1*0.6))") },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = true, shape = RoundedCornerShape(NotebookVisualTokens.buttonCorner)
                            )
                        }

                        // Row config
                        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                            if (selectedPreset?.type in listOf(NotebookColumnType.NUMERIC, NotebookColumnType.RUBRIC)) {
                                OutlinedTextField(
                                    value = weightStr, onValueChange = { weightStr = it },
                                    label = { Text("Peso (ej: 0.5)") },
                                    modifier = Modifier.weight(1f),
                                    singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                    shape = RoundedCornerShape(NotebookVisualTokens.buttonCorner)
                                )
                            }
                            OutlinedTextField(
                                value = widthStr, onValueChange = { widthStr = it },
                                label = { Text("Ancho (dp)") },
                                modifier = Modifier.weight(1f),
                                singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                shape = RoundedCornerShape(NotebookVisualTokens.buttonCorner)
                            )
                            OutlinedTextField(
                                value = orderStr, onValueChange = { orderStr = it },
                                label = { Text("Orden") },
                                modifier = Modifier.weight(1f),
                                singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                                shape = RoundedCornerShape(NotebookVisualTokens.buttonCorner)
                            )
                        }
                    }

                    // Apariencia y Ubicación
                    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                         Text("Apariencia y Ubicación", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                         Text("Color de cabecera", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
                         FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            listOf("#4A90D9", "#2D9CDB", "#27AE60", "#F2994A", "#EB5757", "#9B51E0", "#111827", "#F4B400").forEach { hex ->
                                Surface(
                                    onClick = { colorHex = hex },
                                    shape = CircleShape,
                                    border = BorderStroke(2.dp, if (colorHex == hex) MaterialTheme.colorScheme.primary else Color.Transparent),
                                    color = hex.hexToColor(),
                                    modifier = Modifier.size(32.dp)
                                ) {}
                            }
                        }

                        Spacer(Modifier.height(8.dp))
                        Text("Pestañas asociadas", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            existingTabs.forEach { tab ->
                                val selected = tabIds.contains(tab.id)
                                FilterChip(
                                    selected = selected,
                                    onClick = { tabIds = if (selected) tabIds - tab.id else tabIds + tab.id },
                                    label = { Text(tab.title) },
                                    shape = RoundedCornerShape(NotebookVisualTokens.chipCorner)
                                )
                            }
                        }

                        Spacer(Modifier.height(4.dp))
                        Text("Categoría de columnas", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            FilterChip(
                                selected = selectedCategoryId == null,
                                onClick = { selectedCategoryId = null },
                                label = { Text("Sin categoría") },
                                shape = RoundedCornerShape(NotebookVisualTokens.chipCorner)
                            )
                            existingCategories.forEach { category ->
                                FilterChip(
                                    selected = selectedCategoryId == category.id,
                                    onClick = { selectedCategoryId = category.id },
                                    label = { Text(category.name) },
                                    shape = RoundedCornerShape(NotebookVisualTokens.chipCorner)
                                )
                            }
                        }

                        OutlinedTextField(
                            value = newCategoryName,
                            onValueChange = { newCategoryName = it },
                            label = { Text("Nueva categoría (opcional)") },
                            modifier = Modifier.fillMaxWidth(),
                            singleLine = true,
                            shape = RoundedCornerShape(NotebookVisualTokens.buttonCorner),
                            trailingIcon = {
                                IconButton(
                                    onClick = {
                                        val trimmed = newCategoryName.trim()
                                        if (trimmed.isNotEmpty()) {
                                            val generatedId = "cat_${Clock.System.now().toEpochMilliseconds()}"
                                            onCreateCategory(trimmed, generatedId)
                                            selectedCategoryId = generatedId
                                            newCategoryName = ""
                                        }
                                    }
                                ) {
                                    Icon(Icons.Default.Add, contentDescription = "Crear categoría")
                                }
                            }
                        )
                    }
                    Spacer(Modifier.height(8.dp))
                }

                // Footer Fixed
                Surface(
                    color = MaterialTheme.colorScheme.surface,
                    tonalElevation = 0.dp,
                    contentColor = MaterialTheme.colorScheme.onSurface
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 32.dp, vertical = 24.dp),
                        horizontalArrangement = Arrangement.End,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        TextButton(onClick = onDismiss) {
                            Text("Cancelar", style = MaterialTheme.typography.labelLarge)
                        }
                        Spacer(Modifier.width(16.dp))
                        Button(
                            onClick = {
                                val preset = selectedPreset ?: return@Button
                                if (title.isBlank()) return@Button
                                val id = title.lowercase().replace(" ", "_") + "_${System.currentTimeMillis()}"
                                onConfirm(NotebookColumnDefinition(
                                    id = id, title = title, type = preset.type,
                                    evaluationId = null,
                                    rubricId = selectedRubric?.rubric?.id,
                                    formula = if (preset.type == NotebookColumnType.CALCULATED) formula else null,
                                    weight = weightStr.toDoubleOrNull() ?: 1.0,
                                    tabIds = tabIds,
                                    sharedAcrossTabs = tabIds.size == existingTabs.size && existingTabs.isNotEmpty(),
                                    colorHex = colorHex,
                                    order = orderStr.toIntOrNull() ?: -1,
                                    widthDp = widthStr.toDoubleOrNull() ?: 144.0,
                                    categoryId = selectedCategoryId
                                ))
                            },
                            shape = RoundedCornerShape(NotebookVisualTokens.buttonCorner),
                            enabled = selectedPreset != null && title.isNotBlank() && (selectedPreset?.type != NotebookColumnType.RUBRIC || selectedRubric != null),
                            contentPadding = PaddingValues(horizontal = 24.dp, vertical = 12.dp)
                        ) {
                            Text("Añadir columna", fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        }
    }

    if (showRubricPicker) {
        RubricPickerDialog(
            rubrics = userRubrics,
            onDismiss = { showRubricPicker = false },
            onSelect = { 
                selectedRubric = it
                showRubricPicker = false
                if (title.isEmpty()) title = it.rubric.name
            }
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ColumnCategoryManagerDialog(
    selectedTabTitle: String,
    columns: List<NotebookColumnDefinition>,
    categories: List<NotebookColumnCategory>,
    onDismiss: () -> Unit,
    onCreateCategory: (String) -> Unit,
    onRenameCategory: (String, String) -> Unit,
    onDeleteCategory: (String) -> Unit,
    onAssignColumn: (String, String?) -> Unit,
) {
    var newCategoryName by remember { mutableStateOf("") }
    val renameDrafts = remember(categories.map { it.id to it.name }) {
        mutableStateMapOf<String, String>().apply {
            categories.forEach { put(it.id, it.name) }
        }
    }

    Dialog(onDismissRequest = onDismiss) {
        Surface(
            shape = RoundedCornerShape(NotebookVisualTokens.dialogCornerLarge),
            tonalElevation = 8.dp,
            modifier = Modifier.width(760.dp).heightIn(max = 760.dp)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Text("Categorías de columnas", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Text("Pestaña: $selectedTabTitle", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.outline)

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(
                        value = newCategoryName,
                        onValueChange = { newCategoryName = it },
                        label = { Text("Nueva categoría") },
                        modifier = Modifier.weight(1f),
                        singleLine = true,
                        shape = RoundedCornerShape(NotebookVisualTokens.buttonCorner)
                    )
                    Button(
                        onClick = {
                            val trimmed = newCategoryName.trim()
                            if (trimmed.isNotEmpty()) {
                                onCreateCategory(trimmed)
                                newCategoryName = ""
                            }
                        },
                        enabled = newCategoryName.trim().isNotEmpty()
                    ) {
                        Icon(Icons.Default.Add, null)
                        Spacer(Modifier.width(6.dp))
                        Text("Crear")
                    }
                }

                Text("Categorías existentes", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 180.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(categories, key = { it.id }) { category ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            OutlinedTextField(
                                value = renameDrafts[category.id] ?: category.name,
                                onValueChange = { renameDrafts[category.id] = it },
                                modifier = Modifier.weight(1f),
                                singleLine = true,
                                shape = RoundedCornerShape(10.dp),
                                label = { Text("Nombre") }
                            )
                            IconButton(onClick = {
                                val next = (renameDrafts[category.id] ?: category.name).trim()
                                if (next.isNotEmpty()) onRenameCategory(category.id, next)
                            }) {
                                Icon(Icons.Default.Check, contentDescription = "Guardar nombre")
                            }
                            IconButton(onClick = { onDeleteCategory(category.id) }) {
                                Icon(Icons.Default.Delete, contentDescription = "Eliminar categoría", tint = MaterialTheme.colorScheme.error)
                            }
                        }
                    }
                }

                HorizontalDivider()
                Text("Asignar columnas a categoría", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f, fill = false),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    items(columns.sortedWith(compareBy<NotebookColumnDefinition> { it.order }.thenBy { it.id }), key = { it.id }) { column ->
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.25f), RoundedCornerShape(NotebookVisualTokens.buttonCorner))
                                .padding(12.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Text(column.title, fontWeight = FontWeight.SemiBold)
                            FlowRow(
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                FilterChip(
                                    selected = column.categoryId == null,
                                    onClick = { onAssignColumn(column.id, null) },
                                    label = { Text("Sin categoría") },
                                    shape = RoundedCornerShape(NotebookVisualTokens.chipCorner)
                                )
                                categories.forEach { category ->
                                    FilterChip(
                                        selected = column.categoryId == category.id,
                                        onClick = { onAssignColumn(column.id, category.id) },
                                        label = { Text(category.name) },
                                        shape = RoundedCornerShape(NotebookVisualTokens.chipCorner)
                                    )
                                }
                            }
                        }
                    }
                }

                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = onDismiss) { Text("Cerrar") }
                }
            }
        }
    }
}

@Composable
fun RubricPickerDialog(
    rubrics: List<RubricDetail>,
    onDismiss: () -> Unit,
    onSelect: (RubricDetail) -> Unit
) {
    Dialog(onDismissRequest = onDismiss) {
        Surface(
            shape = RoundedCornerShape(NotebookVisualTokens.dialogCornerLarge),
            tonalElevation = 8.dp,
            modifier = Modifier.width(420.dp).heightIn(max = 500.dp)
        ) {
            Column(Modifier.padding(24.dp)) {
                Text("Seleccionar Rúbrica", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(16.dp))
                
                if (rubrics.isEmpty()) {
                    Box(Modifier.fillMaxWidth().height(200.dp), contentAlignment = Alignment.Center) {
                        Text("No tienes rúbricas creadas", color = MaterialTheme.colorScheme.outline)
                    }
                } else {
                    LazyColumn(
                        modifier = Modifier.weight(1f, fill = false),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(rubrics) { detail ->
                            Surface(
                                onClick = { onSelect(detail) },
                                shape = RoundedCornerShape(NotebookVisualTokens.buttonCorner),
                                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
                            ) {
                                Row(
                                    Modifier.padding(16.dp).fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Icon(
                                        Icons.Default.Grading,
                                        null,
                                        Modifier.size(24.dp),
                                        tint = MaterialTheme.colorScheme.primary
                                    )
                                    Spacer(Modifier.width(12.dp))
                                    Column {
                                        Text(detail.rubric.name, fontWeight = FontWeight.SemiBold)
                                        val description = detail.rubric.description
                                        if (!description.isNullOrBlank()) {
                                            Text(
                                                description,
                                                fontSize = 12.sp,
                                                color = MaterialTheme.colorScheme.outline,
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis
                                            )
                                        }
                                        Text(
                                            "${detail.criteria.size} criterios",
                                            fontSize = 11.sp,
                                            color = MaterialTheme.colorScheme.primary
                                        )
                                    }
                                }
                            }
                        }
                    } // cierra LazyColumn
                } // cierra else
                
                Spacer(Modifier.height(16.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = onDismiss) { Text("Cerrar") }
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────
// Formula Editor Dialog
// ─────────────────────────────────────────────────────────

@Composable
fun FormulaEditorDialog(
    column: NotebookColumnDefinition,
    availableCodes: List<String>,
    formulaEvaluator: FormulaEvaluator,
    onDismiss: () -> Unit,
    onSave: (String) -> Unit
) {
    var formulaText by remember { mutableStateOf(column.formula ?: "") }
    val previewResult = remember(formulaText) {
        if (formulaText.isBlank()) return@remember null
        runCatching { formulaEvaluator.evaluate(formulaText, availableCodes.associateWith { 5.0 }) }.getOrNull()
    }

    Dialog(onDismissRequest = onDismiss) {
        Surface(shape = RoundedCornerShape(NotebookVisualTokens.dialogCorner), tonalElevation = 4.dp, modifier = Modifier.width(480.dp)) {
            Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Functions, null, tint = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.width(8.dp))
                    Text("Editor de fórmula — ${column.title}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                }

                if (availableCodes.isNotEmpty()) {
                    Text("Variables disponibles:", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.horizontalScroll(rememberScrollState())) {
                        availableCodes.forEach { code ->
                            Surface(shape = RoundedCornerShape(6.dp), color = MaterialTheme.colorScheme.secondaryContainer, onClick = { formulaText += code }) {
                                Text(code, Modifier.padding(horizontal = 8.dp, vertical = 4.dp), fontSize = 12.sp, fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.onSecondaryContainer)
                            }
                        }
                    }
                }

                OutlinedTextField(value = formulaText, onValueChange = { formulaText = it }, label = { Text("Fórmula") },
                    placeholder = { Text("Ej: ROUND((EX1 * 0.4) + (TA1 * 0.6), 2)") },
                    modifier = Modifier.fillMaxWidth(), minLines = 2, maxLines = 4, shape = RoundedCornerShape(NotebookVisualTokens.buttonCorner))

                Surface(color = if (previewResult != null) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant,
                    shape = RoundedCornerShape(10.dp)) {
                    Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(if (previewResult != null) Icons.Default.CheckCircle else Icons.Default.Info, null, Modifier.size(16.dp),
                            tint = if (previewResult != null) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.width(8.dp))
                        Text(if (previewResult != null) "Vista previa (con notas=5.0): ${String.format("%.2f", previewResult)}"
                             else if (formulaText.isBlank()) "Escribe una fórmula arriba" else "Fórmula no válida",
                            style = MaterialTheme.typography.bodySmall)
                    }
                }

                Text("Funciones disponibles: ROUND, IF, SUM, AVG, MIN, MAX, ABS",
                    style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)

                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = onDismiss) { Text("Cancelar") }
                    Spacer(Modifier.width(8.dp))
                    Button(onClick = { onSave(formulaText) }, enabled = formulaText.isNotBlank()) { Text("Guardar fórmula") }
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────

private fun NotebookColumnType.label(): String = when (this) {
    NotebookColumnType.NUMERIC    -> "Nota"
    NotebookColumnType.TEXT       -> "Texto"
    NotebookColumnType.ICON       -> "Icono"
    NotebookColumnType.CHECK      -> "Check"
    NotebookColumnType.ORDINAL    -> "Ordinal"
    NotebookColumnType.RUBRIC     -> "Rúbrica"
    NotebookColumnType.ATTENDANCE -> "Asistencia"
    NotebookColumnType.CALCULATED -> "Fórmula"
}

private suspend fun saveAllDrafts(
    container: KmpContainer,
    sheet: NotebookSheet,
    classId: Long,
    numericDrafts: Map<Pair<Long, String>, String>,
    textDrafts: Map<Pair<Long, String>, String>,
    checkDrafts: Map<Pair<Long, String>, Boolean>
) {
    for (row in sheet.rows) {
        for (col in sheet.columns) {
            val key = row.student.id to col.id
            when (col.type) {
                NotebookColumnType.NUMERIC,
                NotebookColumnType.RUBRIC -> {
                    val draft = numericDrafts[key] ?: continue
                    val numeric = draft.replace(",", ".").toDoubleOrNull()
                    container.notebookRepository.saveGrade(
                        classId = classId,
                        studentId = row.student.id,
                        columnId = col.id,
                        evaluationId = col.evaluationId, // Now correctly handles null for NUMERIC
                        value = numeric
                    )
                }
                NotebookColumnType.ATTENDANCE -> {
                    val v = numericDrafts[key] ?: textDrafts[key] ?: continue
                    container.notebookRepository.saveCell(classId, row.student.id, col.id, textValue = v)
                }
                NotebookColumnType.TEXT -> {
                    val v = textDrafts[key] ?: continue
                    container.notebookRepository.saveCell(classId, row.student.id, col.id, textValue = v)
                }
                NotebookColumnType.ICON -> {
                    val v = textDrafts[key] ?: continue
                    container.notebookRepository.saveCell(classId, row.student.id, col.id, iconValue = v)
                }
                NotebookColumnType.ORDINAL -> {
                    val v = textDrafts[key] ?: continue
                    container.notebookRepository.saveCell(classId, row.student.id, col.id, ordinalValue = v)
                }
                NotebookColumnType.CHECK -> {
                    val v = checkDrafts[key] ?: continue
                    container.notebookRepository.saveCell(classId, row.student.id, col.id, boolValue = v)
                }
                else -> Unit
            }
        }
    }
}

private fun calculateColumnRealtime(
    row: NotebookRow,
    column: NotebookColumnDefinition,
    evaluations: List<Evaluation>,
    numericDrafts: Map<Pair<Long, String>, String>,
    formulaEvaluator: FormulaEvaluator,
): Double? {
    val formula = column.formula ?: return null
    val variables = mutableMapOf<String, Double>()
    evaluations.forEach { eval ->
        val key = row.student.id to eval.id.toString()
        numericDrafts[key]?.toDoubleOrNull()?.let { variables[eval.code] = it }
    }
    return runCatching { formulaEvaluator.evaluate(formula, variables) }.getOrNull()
}

private fun rowRealtimeAverage(
    row: NotebookRow,
    columns: List<NotebookColumnDefinition>,
    evaluations: List<Evaluation>,
    numericDrafts: Map<Pair<Long, String>, String>,
    formulaEvaluator: FormulaEvaluator,
): Double? {
    val values = columns.mapNotNull { col ->
        when (col.type) {
            NotebookColumnType.NUMERIC, NotebookColumnType.RUBRIC ->
                numericDrafts[row.student.id to col.id]?.toDoubleOrNull()
            NotebookColumnType.CALCULATED ->
                calculateColumnRealtime(row, col, evaluations, numericDrafts, formulaEvaluator)
            else -> null
        }
    }
    return if (values.isNotEmpty()) values.average() else null
}

// ── Helper Extensions ───────────────────────────────────────────────

private fun NotebookUiState.Data.getDraftValue(studentId: Long, column: NotebookColumnDefinition): String {
    return when (column.type) {
        NotebookColumnType.NUMERIC,
        NotebookColumnType.RUBRIC, 
        NotebookColumnType.ATTENDANCE -> numericDrafts[studentId to column.id]
            ?: textDrafts[studentId to column.id]
            ?: ""
        NotebookColumnType.TEXT,
        NotebookColumnType.ICON,
        NotebookColumnType.ORDINAL -> textDrafts[studentId to column.id] ?: ""
        NotebookColumnType.CHECK -> checkDrafts[studentId to column.id]?.toString() ?: ""
        else -> ""
    }
}

private fun calculateManualAverage(
    row: NotebookRow,
    columns: List<NotebookColumnDefinition>,
    evaluations: List<Evaluation>,
    numericDrafts: Map<Pair<Long, String>, String>,
    formulaEvaluator: FormulaEvaluator,
): Double? {
    val evaluableCols = columns.filter { 
        it.type == NotebookColumnType.NUMERIC || 
        it.type == NotebookColumnType.RUBRIC || 
        it.type == NotebookColumnType.CALCULATED 
    }
    if (evaluableCols.isEmpty()) return null
    
    val values = evaluableCols.mapNotNull { col ->
        if (col.type == NotebookColumnType.CALCULATED) {
            calculateColumnRealtime(row, col, evaluations, numericDrafts, formulaEvaluator)
        } else {
            numericDrafts[row.student.id to col.id]?.toDoubleOrNull()
        }
    }
    return if (values.isNotEmpty()) values.average() else null
}

// ─────────────────────────────────────────────────────────
// Student Dialogs
// ─────────────────────────────────────────────────────────

@Composable
private fun AddStudentDialog(
    onDismiss: () -> Unit,
    onSave: (firstName: String, lastName: String, email: String?, isInjured: Boolean) -> Unit
) {
    var firstName by remember { mutableStateOf("") }
    var lastName  by remember { mutableStateOf("") }
    var email     by remember { mutableStateOf("") }
    var isInjured by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Añadir Alumno Manualmente") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                OutlinedTextField(value = firstName, onValueChange = { firstName = it }, label = { Text("Nombre") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = lastName, onValueChange = { lastName = it }, label = { Text("Apellidos") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = email, onValueChange = { email = it }, label = { Text("Email (Opcional)") }, modifier = Modifier.fillMaxWidth())
                
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(checked = isInjured, onCheckedChange = { isInjured = it })
                    Spacer(Modifier.width(8.dp))
                    Text("Marcar como lesionado")
                }
            }
        },
        confirmButton = {
            Button(
                onClick  = { 
                    if (firstName.isNotBlank() && lastName.isNotBlank()) {
                        onSave(firstName, lastName, email.ifBlank { null }, isInjured)
                    }
                },
                enabled  = firstName.isNotBlank() && lastName.isNotBlank()
            ) { Text("Guardar") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancelar") } }
    )
}

@Composable
private fun ImportPreviewDialog(
    candidates: List<com.migestor.shared.usecase.StudentCandidate>,
    onDismiss: () -> Unit,
    onConfirm: (List<com.migestor.shared.usecase.StudentCandidate>) -> Unit
) {
    var selectedIds by remember { mutableStateOf(candidates.indices.toSet()) }

    AlertDialog(
        onDismissRequest = onDismiss,
        modifier = Modifier.width(600.dp).heightIn(max = 800.dp),
        title = { Text("Vista Previa de Importación") },
        text = {
            Column {
                Text("Se han detectado ${candidates.size} alumnos. Selecciona los que quieras importar:",
                    style = MaterialTheme.typography.bodyMedium)
                Spacer(Modifier.height(16.dp))
                OrganicGlassCard(modifier = Modifier.weight(1f, fill = false)) {
                    LazyColumn(modifier = Modifier.heightIn(max = 400.dp)) {
                        itemsIndexed(candidates) { index, candidate ->
                            Row(
                                modifier = Modifier.fillMaxWidth()
                                    .clickable { selectedIds = if (selectedIds.contains(index)) selectedIds - index else selectedIds + index }
                                    .padding(12.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Checkbox(checked = selectedIds.contains(index), onCheckedChange = null)
                                Spacer(Modifier.width(12.dp))
                                Column {
                                    Text(candidate.fullName, fontWeight = FontWeight.Bold)
                                    Text("Detectado como: ${candidate.firstName} ${candidate.lastName}",
                                        style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                                }
                            }
                            if (index < candidates.size - 1) HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp))
                        }
                    }
                }
            }
        },
        confirmButton = {
            Button(
                onClick  = { onConfirm(candidates.filterIndexed { index, _ -> selectedIds.contains(index) }) },
                enabled  = selectedIds.isNotEmpty()
            ) { Text("Importar Seleccionados") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancelar") } }
    )
}

@Composable
private fun HorizontalDivider(modifier: Modifier = Modifier) {
    androidx.compose.material3.HorizontalDivider(
        modifier = modifier,
        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.1f)
    )
}

// ─────────────────────────────────────────────────────────
// Add Tab Dialog
// ─────────────────────────────────────────────────────────

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AddTabDialog(
    existingTitles: List<String>,
    existingTabs: List<NotebookSheetTab> = emptyList(),
    onDismiss: () -> Unit,
    onConfirm: (String, String?) -> Unit,
) {
    var tabTitle by remember { mutableStateOf("") }
    var selectedParentId by remember { mutableStateOf<String?>(null) }
    val isValid = tabTitle.isNotBlank() && !existingTitles.any { it.equals(tabTitle.trim(), ignoreCase = true) }

    Dialog(onDismissRequest = onDismiss) {
        Surface(shape = RoundedCornerShape(NotebookVisualTokens.dialogCorner), tonalElevation = 4.dp, modifier = Modifier.width(360.dp)) {
            Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text("Nueva pestaña", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                OutlinedTextField(
                    value = tabTitle, onValueChange = { tabTitle = it },
                    label = { Text("Nombre de la pestaña") },
                    placeholder = { Text("ej. Trimestre 1, Pruebas...") },
                    modifier = Modifier.fillMaxWidth(), singleLine = true,
                    isError = tabTitle.isNotBlank() && !isValid,
                    supportingText = if (tabTitle.isNotBlank() && !isValid) { { Text("Ya existe una pestaña con ese nombre") } } else null,
                    shape = RoundedCornerShape(NotebookVisualTokens.buttonCorner)
                )
                Text("Pestaña padre", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        selected = selectedParentId == null,
                        onClick = { selectedParentId = null },
                        label = { Text("Raíz") }
                    )
                    existingTabs.filter { it.parentTabId == null }.forEach { tab ->
                        FilterChip(
                            selected = selectedParentId == tab.id,
                            onClick = { selectedParentId = tab.id },
                            label = { Text(tab.title) }
                        )
                    }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = onDismiss) { Text("Cancelar") }
                    Spacer(Modifier.width(8.dp))
                    Button(onClick = { if (isValid) onConfirm(tabTitle.trim(), selectedParentId) }, enabled = isValid) {
                        Icon(Icons.Default.Add, null, Modifier.size(16.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("Crear pestaña")
                    }
                }
            }
        }
    }
}

@Composable
fun DuplicateConfigDialog(
    classes: List<SchoolClass>,
    onDismiss: () -> Unit,
    onConfirm: (Long) -> Unit
) {
    var selectedClassId by remember { mutableStateOf<Long?>(null) }

    Dialog(onDismissRequest = onDismiss) {
        Card(shape = RoundedCornerShape(16.dp), modifier = Modifier.width(400.dp).padding(16.dp), elevation = CardDefaults.cardElevation(8.dp)) {
            Column(modifier = Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text("Duplicar Configuración", style = MaterialTheme.typography.headlineSmall, color = MaterialTheme.colorScheme.primary)
                Text("Selecciona el curso al que deseas copiar las pestañas y columnas del curso actual.",
                    style = MaterialTheme.typography.bodyMedium)
                LazyColumn(modifier = Modifier.heightIn(max = 300.dp)) {
                    items(classes) { schoolClass ->
                        Row(
                            modifier = Modifier.fillMaxWidth()
                                .clickable { selectedClassId = schoolClass.id }
                                .background(
                                    if (selectedClassId == schoolClass.id) MaterialTheme.colorScheme.primaryContainer else Color.Transparent,
                                    RoundedCornerShape(NotebookVisualTokens.chipCorner)
                                )
                                .padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            RadioButton(selected = selectedClassId == schoolClass.id, onClick = { selectedClassId = schoolClass.id })
                            Spacer(Modifier.width(8.dp))
                            Text(schoolClass.name)
                        }
                    }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = onDismiss) { Text("Cancelar") }
                    Spacer(Modifier.width(8.dp))
                    Button(onClick = { selectedClassId?.let { onConfirm(it) } }, enabled = selectedClassId != null) {
                        Icon(Icons.Default.CopyAll, null, Modifier.size(16.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("Duplicar")
                    }
                }
            }
        }
    }
}
@Composable
private fun BulkActionBar(
    modifier: Modifier = Modifier,
    selectedCount: Int,
    onDelete: () -> Unit,
    onClear: () -> Unit
) {
    Surface(
        modifier = modifier
            .padding(bottom = 32.dp)
            .height(56.dp)
            .width(360.dp),
        shape = RoundedCornerShape(28.dp),
        color = MaterialTheme.colorScheme.secondaryContainer,
        shadowElevation = 8.dp
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 24.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                "$selectedCount seleccionados", 
                fontWeight = FontWeight.Bold, 
                color = MaterialTheme.colorScheme.onSecondaryContainer
            )
            Spacer(Modifier.weight(1f))
            TextButton(onClick = onClear) {
                Text("Cancelar")
            }
            Button(
                onClick = onDelete,
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
            ) {
                Icon(Icons.Default.Delete, null, Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Eliminar")
            }
        }
    }
}
