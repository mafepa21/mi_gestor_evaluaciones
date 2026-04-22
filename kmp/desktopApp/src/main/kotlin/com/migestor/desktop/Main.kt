package com.migestor.desktop

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Backup
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.key
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import com.migestor.desktop.ui.rubrics.RubricsScreen
import com.migestor.desktop.ui.rubrics.RubricEvaluationScreen
import com.migestor.desktop.ui.rubrics.RubricBulkEvaluationScreen
import com.migestor.shared.viewmodel.*
import com.migestor.shared.usecase.*
import com.migestor.desktop.ui.navigation.*
import com.migestor.data.di.KmpContainer
import com.migestor.data.platform.createDesktopDriver
import com.migestor.data.platform.getAppDataPath
import com.migestor.data.platform.releaseDesktopDatabaseLock
import com.migestor.desktop.viewmodel.AppLayoutViewModel
import com.migestor.desktop.sync.LocalSyncServer
import com.migestor.desktop.sync.SqlDelightSyncAdapter
import com.migestor.desktop.ui.system.AppActionEmphasis
import com.migestor.desktop.ui.system.AppActionModel
import com.migestor.desktop.ui.system.AppActionPlacement
import com.migestor.desktop.ui.system.AppShellScaffold
import com.migestor.desktop.ui.system.AppToolbar
import com.migestor.desktop.ui.system.LocalUiFeatureFlags
import com.migestor.desktop.ui.system.ToolbarSearchResult
import com.migestor.desktop.ui.system.rememberUiFeatureFlags
import com.migestor.desktop.ui.settings.AppSettings
import com.migestor.desktop.ui.settings.SettingsScreen
import com.migestor.desktop.ui.settings.rememberAppSettingsState
import com.migestor.shared.sync.SyncCoordinator
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.input.key.*
import com.migestor.shared.domain.ConfigTemplate
import com.migestor.shared.domain.ConfigTemplateKind
import com.migestor.shared.domain.Incident
import com.migestor.shared.domain.PlanningSession
import com.migestor.shared.domain.SchoolClass
import com.migestor.shared.domain.SessionJournalStatus
import com.migestor.shared.domain.Student
import java.io.File

private sealed interface DesktopInitState {
    data class Loading(val message: String) : DesktopInitState
    data class Ready(val container: KmpContainer) : DesktopInitState
    data class Failed(val message: String, val details: String? = null) : DesktopInitState
}

enum class AppTab(val title: String) {
    Dashboard("Dashboard"),
    Cursos("Cursos"),
    Cuaderno("Cuaderno"),
    PaseDeLista("Asistencia"),
    Diario("Diario"),
    Planificacion("Planificación"),
    Evaluacion("Evaluación"),
    Rubricas("Rúbricas"),
    Informes("Informes"),
    Biblioteca("Biblioteca"),
    EducacionFisica("Educación Física"),
    Backups("Backups"),
    Ajustes("Ajustes"),
}

fun main() = application {
    val appSettingsState = rememberAppSettingsState()
    var initState by remember {
        mutableStateOf<DesktopInitState>(DesktopInitState.Loading("Abriendo base de datos local…"))
    }
    var syncServer by remember { mutableStateOf<LocalSyncServer?>(null) }
    var syncRefreshTick by remember { mutableStateOf(0L) }
    val syncStatus = syncServer?.status?.collectAsState()?.value

    LaunchedEffect(Unit) {
        initState = DesktopInitState.Loading("Inicializando base de datos local…")
        runCatching {
            withTimeout(20_000) {
                withContext(Dispatchers.IO) {
                    println("[desktop] Opening SQLite database at ${getAppDataPath("desktop_mi_gestor_kmp.db")}")
                    val driver = createDesktopDriver("desktop_mi_gestor_kmp.db")
                    println("[desktop] SQLite driver ready")
                    KmpContainer(driver).also {
                        println("[desktop] KmpContainer ready")
                    }
                }
            }
        }.onSuccess { createdContainer ->
            initState = DesktopInitState.Ready(createdContainer)
            launch(Dispatchers.IO) {
                runCatching {
                    val adapter = SqlDelightSyncAdapter(createdContainer)
                    LocalSyncServer(
                        syncCoordinator = SyncCoordinator(adapter),
                        dataChangeListener = { entities ->
                            CoroutineScope(Dispatchers.Main).launch {
                                syncRefreshTick++
                                println("[desktop] Sync remoto aplicado: ${entities.joinToString(",")}")
                            }
                        },
                    ).also { server ->
                        server.start()
                    }
                }.onSuccess { server ->
                    withContext(Dispatchers.Main) {
                        syncServer = server
                    }
                }.onFailure { error ->
                    error.printStackTrace()
                }
            }
        }.onFailure { error ->
            error.printStackTrace()
            initState = DesktopInitState.Failed(
                message = "No se pudo iniciar la base de datos local.",
                details = error.message
            )
        }
    }

    val appLayoutViewModel = remember {
        AppLayoutViewModel(initialExpanded = !appSettingsState.value.startWithCollapsedSidebar)
    }

    Window(
        onCloseRequest = {
            syncServer?.stop()
            releaseDesktopDatabaseLock()
            exitApplication()
        },
        title = "MiGestor KMP Desktop",
        onKeyEvent = { event ->
            if (event.isMetaPressed && event.key == Key.Backslash && event.type == KeyEventType.KeyDown) {
                appLayoutViewModel.toggleSidebar()
                true
            } else false
        }
    ) {
        MaterialTheme {
            val featureFlags = rememberUiFeatureFlags()
            when (val state = initState) {
                is DesktopInitState.Ready -> {
                    CompositionLocalProvider(LocalUiFeatureFlags provides featureFlags) {
                        DesktopApp(
                            container = state.container,
                            appLayoutViewModel = appLayoutViewModel,
                            appSettings = appSettingsState.value,
                            onAppSettingsChange = { appSettingsState.value = it },
                            syncPairingPayload = syncStatus?.pairingPayload,
                            syncHost = syncStatus?.host,
                            syncPin = syncStatus?.pin,
                            syncServerId = syncStatus?.serverId,
                            syncIsPaired = syncStatus?.isPaired ?: false,
                            syncRefreshTick = syncRefreshTick,
                            onRevokeSyncPairing = {
                                syncServer?.revokePairing()
                            }
                        )
                    }
                }
                is DesktopInitState.Loading -> {
                    Column(
                        modifier = Modifier.fillMaxSize().padding(16.dp),
                        verticalArrangement = Arrangement.Center
                    ) {
                        Text(state.message, style = MaterialTheme.typography.headlineSmall)
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            "Ubicación: ${getAppDataPath("desktop_mi_gestor_kmp.db")}",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
                is DesktopInitState.Failed -> {
                    val errorDetails = state.details
                    Column(
                        modifier = Modifier.fillMaxSize().padding(16.dp),
                        verticalArrangement = Arrangement.Center
                    ) {
                        Text(state.message, style = MaterialTheme.typography.headlineSmall)
                        Spacer(modifier = Modifier.height(8.dp))
                        if (errorDetails != null) {
                            Text(
                                errorDetails,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.error
                            )
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            "Base de datos: ${getAppDataPath("desktop_mi_gestor_kmp.db")}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun DesktopApp(
    container: KmpContainer,
    appLayoutViewModel: AppLayoutViewModel,
    appSettings: AppSettings,
    onAppSettingsChange: (AppSettings) -> Unit,
    syncPairingPayload: String?,
    syncHost: String?,
    syncPin: String?,
    syncServerId: String?,
    syncIsPaired: Boolean,
    syncRefreshTick: Long,
    onRevokeSyncPairing: () -> Unit,
) {
    val scope = remember { CoroutineScope(Dispatchers.Main) }
    var currentTab by remember { mutableStateOf(AppTab.Dashboard) }
    var status by remember { mutableStateOf("Listo") }
    var searchQuery by remember { mutableStateOf("") }
    var inspectorVisible by remember(appSettings.showInspectorByDefault) {
        mutableStateOf(appSettings.showInspectorByDefault)
    }
    val isSidebarExpanded by appLayoutViewModel.isSidebarExpanded.collectAsState()
    val rubricsViewModel = remember { RubricsViewModel(container.rubricsRepository, container.classesRepository, container.evaluationsRepository, container.notebookRepository) }
    val rubricEvaluationViewModel = remember { 
        RubricEvaluationViewModel(
            container.rubricsRepository, 
            container.studentsRepository, 
            container.evaluationsRepository, 
            container.gradesRepository,
            container.notebookRepository
        ) 
    }
    val rubricBulkEvaluationViewModel = remember {
        RubricBulkEvaluationViewModel(
            container.rubricsRepository,
            container.studentsRepository,
            container.notebookRepository,
            container.gradesRepository
        )
    }
    
    val plannerViewModel = remember {
        PlannerViewModel(
            plannerRepo = container.plannerRepository,
            classRepo = container.classesRepository,
            weeklyTemplateRepo = container.weeklyTemplateRepository,
            plannedSessionRepo = container.plannedSessionRepository,
            generateSessionsFromUD = container.generateSessionsFromUD
        )
    }
    
    val currentScreen = Navigator.currentScreen
    val featureFlags = LocalUiFeatureFlags.current
    // New Class Dialog State
    var showNewClassDialog by remember { mutableStateOf(false) }
    var newClassName by remember { mutableStateOf("") }
    var newClassCourse by remember { mutableStateOf("") }

    LaunchedEffect(Unit) {
        runCatching { container.seedDemoDataIfEmpty() }
            .onFailure { status = it.message ?: "No se pudo sembrar demo" }
    }

    LaunchedEffect(appSettings.startWithCollapsedSidebar) {
        appLayoutViewModel.setSidebarExpanded(!appSettings.startWithCollapsedSidebar)
    }

    com.migestor.desktop.ui.theme.MiGestorTheme(themeMode = appSettings.themeMode) {
        androidx.compose.material3.Surface(
            modifier = Modifier.fillMaxSize(),
            color = androidx.compose.material3.MaterialTheme.colorScheme.background
        ) {
            when (val screen = currentScreen) {
                is Screen.RubricEvaluation -> {
                    LaunchedEffect(screen) {
                        if (screen.columnId != null) {
                            rubricEvaluationViewModel.loadForNotebookCell(
                                studentId = screen.studentId,
                                columnId = screen.columnId,
                                rubricId = screen.rubricId,
                                evaluationId = screen.evaluationId
                            )
                        } else {
                            rubricEvaluationViewModel.loadEvaluation(
                                studentId = screen.studentId,
                                evaluationId = screen.evaluationId,
                                rubricId = screen.rubricId
                            )
                        }
                    }
                    RubricEvaluationScreen(rubricEvaluationViewModel)
                }
                is Screen.RubricBulkEvaluation -> {
                    LaunchedEffect(screen) {
                        rubricBulkEvaluationViewModel.load(
                            classId = screen.classId,
                            evaluationId = screen.evaluationId,
                            rubricId = screen.rubricId,
                            columnId = screen.columnId,
                            tabId = screen.tabId
                        )
                    }
                    RubricBulkEvaluationScreen(rubricBulkEvaluationViewModel)
                }
                Screen.Main -> {
                    val actions = buildList {
                        add(
                            AppActionModel(
                                id = "refresh",
                                label = "Recargar",
                                icon = Icons.Default.Refresh,
                                placement = AppActionPlacement.Toolbar,
                                emphasis = AppActionEmphasis.Secondary,
                                onClick = {
                                    status = "Refrescando…"
                                },
                            )
                        )
                        if (currentTab == AppTab.Cuaderno) {
                            add(
                                AppActionModel(
                                    id = "save-notebook",
                                    label = "Guardar",
                                    icon = Icons.Default.Save,
                                    placement = AppActionPlacement.Toolbar,
                                    emphasis = AppActionEmphasis.Primary,
                                    onClick = { status = "Usa Ctrl+S para guardar cambios del cuaderno" },
                                )
                            )
                            add(
                                AppActionModel(
                                    id = "notebook-help",
                                    label = "Atajos de cuaderno",
                                    icon = Icons.AutoMirrored.Filled.MenuBook,
                                    placement = AppActionPlacement.Overflow,
                                    onClick = {
                                        status = "Atajos: Ctrl+S guarda · Tab/Enter avanzan · Escape cierra overlays"
                                    },
                                )
                            )
                        } else if (currentTab != AppTab.Ajustes) {
                            add(
                                AppActionModel(
                                    id = "new-class",
                                    label = "Nueva clase",
                                    icon = Icons.Default.Add,
                                    placement = AppActionPlacement.Toolbar,
                                    emphasis = AppActionEmphasis.Primary,
                                    onClick = { showNewClassDialog = true },
                                )
                            )
                        }
                    }
                    val searchItems = listOf(
                        ToolbarSearchResult("tab-dashboard", "Dashboard", "Abrir módulo"),
                        ToolbarSearchResult("tab-cursos", "Cursos", "Abrir módulo"),
                        ToolbarSearchResult("tab-cuaderno", "Cuaderno", "Abrir módulo"),
                        ToolbarSearchResult("tab-pase-lista", "Asistencia", "Abrir módulo"),
                        ToolbarSearchResult("tab-diario", "Diario", "Abrir módulo"),
                        ToolbarSearchResult("tab-planificacion", "Planificación", "Abrir módulo"),
                        ToolbarSearchResult("tab-evaluacion", "Evaluación", "Abrir módulo"),
                        ToolbarSearchResult("tab-rubricas", "Rúbricas", "Abrir módulo"),
                        ToolbarSearchResult("tab-informes", "Informes", "Abrir módulo"),
                        ToolbarSearchResult("tab-biblioteca", "Biblioteca", "Abrir módulo"),
                        ToolbarSearchResult("tab-ef", "Educación Física", "Abrir módulo"),
                        ToolbarSearchResult("tab-backups", "Backups", "Abrir módulo"),
                        ToolbarSearchResult("tab-ajustes", "Ajustes", "Abrir módulo"),
                        ToolbarSearchResult("action-new-class", "Nueva clase", "Acción global"),
                        ToolbarSearchResult("action-refresh", "Recargar vista", "Acción global"),
                        ToolbarSearchResult("action-notebook-save", "Guardar cuaderno", "Acción del módulo Cuaderno"),
                    )
                    val filteredSearch = searchItems.filter {
                        it.label.contains(searchQuery, ignoreCase = true) ||
                            it.subtitle.contains(searchQuery, ignoreCase = true)
                    }.take(8)

                    fun applySearchResult(result: ToolbarSearchResult) {
                        when (result.id) {
                            "tab-dashboard" -> currentTab = AppTab.Dashboard
                            "tab-cursos" -> currentTab = AppTab.Cursos
                            "tab-cuaderno" -> currentTab = AppTab.Cuaderno
                            "tab-pase-lista" -> currentTab = AppTab.PaseDeLista
                            "tab-diario" -> currentTab = AppTab.Diario
                            "tab-planificacion" -> currentTab = AppTab.Planificacion
                            "tab-evaluacion" -> currentTab = AppTab.Evaluacion
                            "tab-rubricas" -> currentTab = AppTab.Rubricas
                            "tab-informes" -> currentTab = AppTab.Informes
                            "tab-biblioteca" -> currentTab = AppTab.Biblioteca
                            "tab-ef" -> currentTab = AppTab.EducacionFisica
                            "tab-backups" -> currentTab = AppTab.Backups
                            "tab-ajustes" -> currentTab = AppTab.Ajustes
                            "action-new-class" -> showNewClassDialog = true
                            "action-refresh" -> status = "Refrescando…"
                            "action-notebook-save" -> status = "Usa Ctrl+S para guardar en Cuaderno"
                        }
                        searchQuery = ""
                    }

                    val screenContent: @Composable () -> Unit = {
                        when (currentTab) {
                            AppTab.Dashboard -> com.migestor.desktop.ui.dashboard.DashboardScreen(
                                container = container,
                                scope = scope,
                                onStatus = { status = it },
                                syncPayload = syncPairingPayload,
                                syncHost = syncHost,
                                syncPin = syncPin,
                                syncServerId = syncServerId,
                                syncIsPaired = syncIsPaired,
                                onRevokeSyncPairing = onRevokeSyncPairing,
                            )
                            AppTab.Cursos -> CoursesTab(container, onStatus = { status = it })
                            AppTab.Cuaderno -> com.migestor.desktop.ui.notebook.NotebookScreen(container, scope, onStatus = { status = it })
                            AppTab.PaseDeLista -> com.migestor.desktop.ui.attendance.AttendanceScreen(container, scope, onStatus = { status = it })
                            AppTab.Diario -> DiaryTab(container, onStatus = { status = it })
                            AppTab.Planificacion -> com.migestor.desktop.ui.planner.PlannerScreen(plannerViewModel)
                            AppTab.Evaluacion -> EvaluationOverviewTab(container, onStatus = { status = it })
                            AppTab.Rubricas -> RubricsScreen(rubricsViewModel, onStatus = { status = it })
                            AppTab.Informes -> ReportsTab(container, scope, onStatus = { status = it })
                            AppTab.Biblioteca -> LibraryTab(container, onStatus = { status = it })
                            AppTab.EducacionFisica -> PEHubTab(container, onStatus = { status = it })
                            AppTab.Backups -> BackupsTab(container, scope, onStatus = { status = it })
                            AppTab.Ajustes -> SettingsScreen(
                                settings = appSettings,
                                onSettingsChange = {
                                    onAppSettingsChange(it)
                                    status = "Ajustes actualizados"
                                    appLayoutViewModel.setSidebarExpanded(!it.startWithCollapsedSidebar)
                                },
                                featureFlags = featureFlags
                            )
                        }
                    }

                    if (featureFlags.newShell) {
                        AppShellScaffold(
                            sidebar = {
                                com.migestor.desktop.ui.Sidebar(
                                    currentTab = currentTab,
                                    onTabSelected = { currentTab = it },
                                    onNewClass = { showNewClassDialog = true },
                                    isExpanded = isSidebarExpanded,
                                    onToggle = { appLayoutViewModel.toggleSidebar() }
                                )
                            },
                            toolbar = {
                                AppToolbar(
                                    title = currentTab.title,
                                    subtitle = currentTab.sectionLabel(),
                                    searchQuery = searchQuery,
                                    onSearchQueryChange = { searchQuery = it },
                                    searchResults = filteredSearch,
                                    onSearchResultSelected = { applySearchResult(it) },
                                    onSearchSubmit = { query ->
                                        filteredSearch.firstOrNull()?.let(::applySearchResult)
                                            ?: run { status = "Sin resultados para \"$query\"" }
                                    },
                                    actions = actions,
                                    onToggleInspector = { inspectorVisible = !inspectorVisible },
                                )
                            },
                            content = {
                                Column(modifier = Modifier.fillMaxSize()) {
                                    Box(modifier = Modifier.weight(1f)) {
                                        key(currentTab, syncRefreshTick) { screenContent() }
                                    }
                                    Text(
                                        text = "Estado: $status",
                                        style = MaterialTheme.typography.bodySmall,
                                        modifier = Modifier.padding(16.dp),
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            },
                            inspectorVisible = inspectorVisible,
                            inspector = {
                                DesktopInspector(currentTab = currentTab, status = status)
                            }
                        )
                    } else {
                        Row(modifier = Modifier.fillMaxSize()) {
                            com.migestor.desktop.ui.Sidebar(
                                currentTab = currentTab,
                                onTabSelected = { currentTab = it },
                                onNewClass = { showNewClassDialog = true },
                                isExpanded = isSidebarExpanded,
                                onToggle = { appLayoutViewModel.toggleSidebar() }
                            )
                            Column(modifier = Modifier.weight(1f)) {
                                com.migestor.desktop.ui.TopHeader(
                                    title = currentTab.title,
                                    subtitle = currentTab.sectionLabel()
                                )
                                Box(modifier = Modifier.weight(1f)) {
                                    key(currentTab, syncRefreshTick) { screenContent() }
                                }
                            }
                        }
                    }
                }
            }

            // New Class Dialog
            if (showNewClassDialog) {
                androidx.compose.material3.AlertDialog(
                    onDismissRequest = { showNewClassDialog = false },
                    title = { Text("Nueva Clase") },
                    text = {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedTextField(
                                value = newClassName,
                                onValueChange = { newClassName = it },
                                label = { Text("Nombre de la clase (ej. 1º ESO A)") },
                                modifier = Modifier.fillMaxWidth()
                            )
                            OutlinedTextField(
                                value = newClassCourse,
                                onValueChange = { newClassCourse = it },
                                label = { Text("Curso (número)") },
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                    },
                    confirmButton = {
                        Button(
                            onClick = {
                                val courseInt = newClassCourse.toIntOrNull()
                                if (newClassName.isBlank() || courseInt == null) {
                                    status = "Datos inválidos"
                                    return@Button
                                }
                                scope.launch {
                                    runCatching { 
                                        container.saveClass(name = newClassName, course = courseInt, description = null)
                                    }.onSuccess { 
                                        status = "Clase creada"
                                        showNewClassDialog = false
                                        newClassName = ""
                                        newClassCourse = ""
                                    }.onFailure { 
                                        status = "Error: ${it.message}"
                                    }
                                }
                            }
                        ) { Text("Crear") }
                    },
                    dismissButton = {
                        TextButton(onClick = { showNewClassDialog = false }) { Text("Cancelar") }
                    }
                )
            }
        }
    }
}


@Composable
private fun DesktopInspector(currentTab: AppTab, status: String) {
    val moduleNotes = when (currentTab) {
        AppTab.Dashboard -> "Resumen operativo del día y accesos rápidos."
        AppTab.Cursos -> "Controla roster, incidencias y accesos a cuaderno, diario e informes."
        AppTab.Cuaderno -> "Inspector centrado en columnas, celdas y navegación evaluativa."
        AppTab.PaseDeLista -> "Asistencia rápida con histórico, incidencias y contexto de sesión."
        AppTab.Diario -> "Sesiones, borradores y estado del journal en una vista operativa."
        AppTab.Planificacion -> "Diseño previo de unidades y sesiones."
        AppTab.Evaluacion -> "Panorámica de instrumentos, corrección pendiente y rúbricas vinculadas."
        AppTab.Rubricas -> "Banco de rúbricas y constructor con asignación a clase."
        AppTab.Informes -> "Generación y salida operativa de informes."
        AppTab.Biblioteca -> "Plantillas reutilizables de cuaderno, rúbricas y unidades."
        AppTab.EducacionFisica -> "Hub EF con sesiones, incidencias y pruebas físicas."
        AppTab.Backups -> "Gestión de copias y restauración local."
        AppTab.Ajustes -> "Preferencias, flags y comportamiento global."
    }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Inspector", style = MaterialTheme.typography.titleMedium)
        Text("Módulo: ${currentTab.title}", style = MaterialTheme.typography.bodyMedium)
        Text("Estado actual: $status", style = MaterialTheme.typography.bodySmall)
        Text(
            moduleNotes,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun ReportsTab(container: KmpContainer, scope: CoroutineScope, onStatus: (String) -> Unit) {
    var contexts by remember { mutableStateOf(emptyList<ReportContext>()) }
    var selectedClassId by remember { mutableStateOf<Long?>(null) }
    var selectedKind by remember { mutableStateOf(ReportKind.Group) }
    var reportPath by remember { mutableStateOf("(sin generar)") }
    var reportMenuExpanded by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        runCatching {
            container.classesRepository.listClasses().map { schoolClass ->
                val notebook = container.getNotebook(schoolClass.id)
                val evaluations = container.evaluationsRepository.listClassEvaluations(schoolClass.id)
                val incidents = container.incidentsRepository.listIncidents(schoolClass.id)
                val averages = notebook.rows.mapNotNull { it.weightedAverage }
                val topStudent = notebook.rows.maxByOrNull { it.weightedAverage ?: Double.MIN_VALUE }?.student?.fullName
                ReportContext(
                    schoolClass = schoolClass,
                    studentCount = notebook.rows.size,
                    evaluationsCount = evaluations.size,
                    incidentsCount = incidents.size,
                    average = if (averages.isEmpty()) 0.0 else averages.average(),
                    topStudent = topStudent,
                )
            }
        }.onSuccess {
            contexts = it
            selectedClassId = selectedClassId ?: it.firstOrNull()?.schoolClass?.id
            onStatus("Informes listos")
        }.onFailure { onStatus(it.message ?: "Error cargando informes") }
    }

    val selected = contexts.firstOrNull { it.schoolClass.id == selectedClassId } ?: contexts.firstOrNull()

    TwoPaneWorkspace(
        leftTitle = "Contextos de informe",
        left = {
            if (contexts.isEmpty()) {
                EmptyWorkspaceState("No hay grupos para generar informes.")
            } else {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(contexts) { context ->
                        WorkspaceListItem(
                            title = context.schoolClass.name,
                            subtitle = "Curso ${context.schoolClass.course} · ${context.studentCount} alumnos",
                            selected = selected?.schoolClass?.id == context.schoolClass.id,
                            supporting = "${context.evaluationsCount} instrumentos · ${context.incidentsCount} incidencias",
                            onClick = { selectedClassId = context.schoolClass.id }
                        )
                    }
                }
            }
        },
        rightTitle = selected?.schoolClass?.name ?: "Informe",
        right = {
            if (selected == null) {
                EmptyWorkspaceState("Selecciona un grupo para previsualizar el informe.")
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    MetricsRow(
                        "Alumnado" to selected.studentCount.toString(),
                        "Instrumentos" to selected.evaluationsCount.toString(),
                        "Incidencias" to selected.incidentsCount.toString(),
                        "Media" to String.format("%.2f", selected.average),
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                        Box(modifier = Modifier.weight(1f)) {
                            Button(onClick = { reportMenuExpanded = true }, modifier = Modifier.fillMaxWidth().height(44.dp)) {
                                Text(selectedKind.label)
                            }
                            DropdownMenu(
                                expanded = reportMenuExpanded,
                                onDismissRequest = { reportMenuExpanded = false }
                            ) {
                                ReportKind.entries.forEach { kind ->
                                    DropdownMenuItem(
                                        text = { Text(kind.label) },
                                        onClick = {
                                            selectedKind = kind
                                            reportMenuExpanded = false
                                        }
                                    )
                                }
                                DropdownMenuItem(
                                    text = { Text("Limpiar ruta") },
                                    leadingIcon = { Icon(Icons.Default.FolderOpen, contentDescription = null) },
                                    onClick = {
                                        reportMenuExpanded = false
                                        reportPath = "(sin generar)"
                                    }
                                )
                            }
                        }
                        Button(
                            onClick = {
                                scope.launch {
                                    runCatching {
                                        val notebook = container.getNotebook(selected.schoolClass.id)
                                        val evaluations = container.evaluationsRepository.listClassEvaluations(selected.schoolClass.id)
                                        val rows = when (selectedKind) {
                                            ReportKind.Group -> notebook.rows.map {
                                                "${it.student.lastName}, ${it.student.firstName}: ${it.weightedAverage ?: 0.0}"
                                            }
                                            ReportKind.Individual -> notebook.rows.map {
                                                "${it.student.fullName}: seguimiento individual ${it.weightedAverage ?: 0.0}"
                                            }
                                            ReportKind.Evaluation -> evaluations.map { evaluation ->
                                                "${evaluation.code} · ${evaluation.name} · peso ${evaluation.weight}"
                                            }
                                            ReportKind.Operational -> buildList {
                                                add("Asistencia registrada: ${selected.studentCount} alumnos")
                                                add("Incidencias activas: ${selected.incidentsCount}")
                                                add("Media del grupo: ${String.format("%.2f", selected.average)}")
                                                selected.topStudent?.let { add("Alumno/a destacado/a: $it") }
                                            }
                                        }
                                        val bytes = container.reportService.exportNotebookReport(
                                            com.migestor.shared.repository.NotebookReportRequest(
                                                className = "${selected.schoolClass.name} · ${selectedKind.label}",
                                                rows = rows,
                                            )
                                        )
                                        val reportsDirPath = getAppDataPath("reports")
                                        val reportsDir = File(reportsDirPath).also { it.mkdirs() }
                                        val slug = selectedKind.name.lowercase()
                                        val file = File(reportsDir, "informe_${slug}_${selected.schoolClass.id}.pdf")
                                        file.writeBytes(bytes)
                                        reportPath = file.absolutePath
                                        file.absolutePath
                                    }.onSuccess { onStatus("Informe generado") }
                                        .onFailure { onStatus(it.message ?: "Error informe") }
                                }
                            },
                            modifier = Modifier.height(44.dp)
                        ) { Text("Generar") }
                    }
                    Text("Preview", style = MaterialTheme.typography.titleSmall)
                    Text("Tipo: ${selectedKind.label}")
                    Text("Grupo: ${selected.schoolClass.name}")
                    Text("Mejor referencia actual: ${selected.topStudent ?: "Sin datos suficientes"}")
                    Text("Ruta: $reportPath", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    )
}

private data class CourseDesktopSnapshot(
    val schoolClass: SchoolClass,
    val students: List<Student>,
    val evaluationsCount: Int,
    val incidentsCount: Int,
    val attendanceCount: Int,
)

private enum class ReportKind(val label: String) {
    Group("Informe de grupo"),
    Individual("Informe individual"),
    Evaluation("Informe de evaluación"),
    Operational("Resumen operativo"),
}

private data class ReportContext(
    val schoolClass: SchoolClass,
    val studentCount: Int,
    val evaluationsCount: Int,
    val incidentsCount: Int,
    val average: Double,
    val topStudent: String?,
)

@Composable
private fun CoursesTab(container: KmpContainer, onStatus: (String) -> Unit) {
    var snapshots by remember { mutableStateOf(emptyList<CourseDesktopSnapshot>()) }
    var selectedClassId by remember { mutableStateOf<Long?>(null) }

    LaunchedEffect(Unit) {
        runCatching {
            container.classesRepository.listClasses().map { schoolClass ->
                CourseDesktopSnapshot(
                    schoolClass = schoolClass,
                    students = container.classesRepository.listStudentsInClass(schoolClass.id),
                    evaluationsCount = container.evaluationsRepository.listClassEvaluations(schoolClass.id).size,
                    incidentsCount = container.incidentsRepository.listIncidents(schoolClass.id).size,
                    attendanceCount = container.attendanceRepository.listAttendance(schoolClass.id).size,
                )
            }.sortedBy { it.schoolClass.course }
        }.onSuccess {
            snapshots = it
            selectedClassId = selectedClassId ?: it.firstOrNull()?.schoolClass?.id
            onStatus("Cursos cargados")
        }.onFailure { onStatus(it.message ?: "Error cargando cursos") }
    }

    val selected = snapshots.firstOrNull { it.schoolClass.id == selectedClassId } ?: snapshots.firstOrNull()

    TwoPaneWorkspace(
        leftTitle = "Grupos",
        left = {
            if (snapshots.isEmpty()) {
                EmptyWorkspaceState("No hay cursos todavía.")
            } else {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(snapshots) { snapshot ->
                        WorkspaceListItem(
                            title = snapshot.schoolClass.name,
                            subtitle = "Curso ${snapshot.schoolClass.course} · ${snapshot.students.size} alumnos",
                            selected = selected?.schoolClass?.id == snapshot.schoolClass.id,
                            supporting = "${snapshot.evaluationsCount} evaluaciones · ${snapshot.incidentsCount} incidencias",
                            onClick = { selectedClassId = snapshot.schoolClass.id }
                        )
                    }
                }
            }
        },
        rightTitle = selected?.schoolClass?.name ?: "Detalle del curso",
        right = {
            if (selected == null) {
                EmptyWorkspaceState("Selecciona un curso para ver su contexto.")
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    MetricsRow(
                        "Alumnado" to selected.students.size.toString(),
                        "Evaluaciones" to selected.evaluationsCount.toString(),
                        "Asistencias" to selected.attendanceCount.toString(),
                        "Incidencias" to selected.incidentsCount.toString(),
                    )
                    Text(
                        selected.schoolClass.description ?: "Sin descripción docente todavía.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    HorizontalDivider()
                    Text("Roster rápido", style = MaterialTheme.typography.titleSmall)
                    if (selected.students.isEmpty()) {
                        EmptyWorkspaceState("Este grupo no tiene alumnado asignado.")
                    } else {
                        selected.students.take(12).forEach { student ->
                            Text(
                                "• ${student.fullName}" + if (student.isInjured) " · lesionado/a" else "",
                                style = MaterialTheme.typography.bodyMedium
                            )
                        }
                    }
                }
            }
        }
    )
}

private data class DiaryDesktopSnapshot(
    val session: PlanningSession,
    val summaryStatus: SessionJournalStatus,
    val incidentTags: List<String>,
    val usedSpace: String,
)

@Composable
private fun DiaryTab(container: KmpContainer, onStatus: (String) -> Unit) {
    var sessions by remember { mutableStateOf(emptyList<DiaryDesktopSnapshot>()) }
    var selectedSessionId by remember { mutableStateOf<Long?>(null) }

    LaunchedEffect(Unit) {
        runCatching {
            val allSessions = container.plannerRepository.listAllSessions()
            val summaries = container.sessionJournalRepository
                .listSummariesForSessions(allSessions.map { it.id })
                .associateBy { it.planningSessionId }
            allSessions.map { session ->
                val summary = summaries[session.id]
                DiaryDesktopSnapshot(
                    session = session,
                    summaryStatus = summary?.status ?: SessionJournalStatus.EMPTY,
                    incidentTags = summary?.incidentTags ?: emptyList(),
                    usedSpace = summary?.usedSpace ?: "",
                )
            }.sortedWith(
                compareByDescending<DiaryDesktopSnapshot> { it.session.year }
                    .thenByDescending { it.session.weekNumber }
                    .thenByDescending { it.session.dayOfWeek }
                    .thenByDescending { it.session.period }
            )
        }.onSuccess {
            sessions = it
            selectedSessionId = selectedSessionId ?: it.firstOrNull()?.session?.id
            onStatus("Diario cargado")
        }.onFailure { onStatus(it.message ?: "Error cargando diario") }
    }

    val selected = sessions.firstOrNull { it.session.id == selectedSessionId } ?: sessions.firstOrNull()

    TwoPaneWorkspace(
        leftTitle = "Sesiones",
        left = {
            if (sessions.isEmpty()) {
                EmptyWorkspaceState("No hay sesiones en el diario todavía.")
            } else {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(sessions) { snapshot ->
                        WorkspaceListItem(
                            title = snapshot.session.teachingUnitName,
                            subtitle = "${snapshot.session.groupName} · Semana ${snapshot.session.weekNumber}",
                            selected = selected?.session?.id == snapshot.session.id,
                            supporting = "${snapshot.summaryStatus.name} · Periodo ${snapshot.session.period}",
                            onClick = { selectedSessionId = snapshot.session.id }
                        )
                    }
                }
            }
        },
        rightTitle = selected?.session?.teachingUnitName ?: "Detalle de sesión",
        right = {
            if (selected == null) {
                EmptyWorkspaceState("Selecciona una sesión.")
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    MetricsRow(
                        "Grupo" to selected.session.groupName,
                        "Semana" to selected.session.weekNumber.toString(),
                        "Periodo" to selected.session.period.toString(),
                        "Estado" to selected.summaryStatus.name,
                    )
                    Text("Objetivos", style = MaterialTheme.typography.titleSmall)
                    Text(selected.session.objectives.ifBlank { "Sin objetivos registrados." })
                    Text("Actividades", style = MaterialTheme.typography.titleSmall)
                    Text(selected.session.activities.ifBlank { "Sin actividades registradas." })
                    if (selected.usedSpace.isNotBlank()) {
                        HorizontalDivider()
                        Text("Espacio usado: ${selected.usedSpace}")
                    }
                    if (selected.incidentTags.isNotEmpty()) {
                        Text("Etiquetas: ${selected.incidentTags.joinToString()}")
                    }
                }
            }
        }
    )
}

@Composable
private fun EvaluationOverviewTab(container: KmpContainer, onStatus: (String) -> Unit) {
    data class EvaluationOverview(
        val schoolClass: SchoolClass,
        val evaluations: Int,
        val rubricsLinked: Int,
        val grades: Int,
    )

    var items by remember { mutableStateOf(emptyList<EvaluationOverview>()) }
    var selectedClassId by remember { mutableStateOf<Long?>(null) }

    LaunchedEffect(Unit) {
        runCatching {
            container.classesRepository.listClasses().map { schoolClass ->
                val evaluations = container.evaluationsRepository.listClassEvaluations(schoolClass.id)
                EvaluationOverview(
                    schoolClass = schoolClass,
                    evaluations = evaluations.size,
                    rubricsLinked = evaluations.count { it.rubricId != null },
                    grades = container.gradesRepository.listGradesForClass(schoolClass.id).size,
                )
            }
        }.onSuccess {
            items = it
            selectedClassId = selectedClassId ?: it.firstOrNull()?.schoolClass?.id
            onStatus("Evaluación cargada")
        }.onFailure { onStatus(it.message ?: "Error cargando evaluación") }
    }

    val selected = items.firstOrNull { it.schoolClass.id == selectedClassId } ?: items.firstOrNull()

    TwoPaneWorkspace(
        leftTitle = "Clases evaluativas",
        left = {
            if (items.isEmpty()) {
                EmptyWorkspaceState("No hay clases con evaluación todavía.")
            } else {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(items) { item ->
                        WorkspaceListItem(
                            title = item.schoolClass.name,
                            subtitle = "Curso ${item.schoolClass.course}",
                            selected = selected?.schoolClass?.id == item.schoolClass.id,
                            supporting = "${item.evaluations} instrumentos · ${item.rubricsLinked} con rúbrica",
                            onClick = { selectedClassId = item.schoolClass.id }
                        )
                    }
                }
            }
        },
        rightTitle = selected?.schoolClass?.name ?: "Vista evaluativa",
        right = {
            if (selected == null) {
                EmptyWorkspaceState("Selecciona una clase.")
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    MetricsRow(
                        "Instrumentos" to selected.evaluations.toString(),
                        "Rúbricas" to selected.rubricsLinked.toString(),
                        "Registros" to selected.grades.toString(),
                    )
                    Text(
                        "Esta vista resume la carga evaluativa por grupo y sirve de puente hacia Cuaderno y Rúbricas.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    )
}

@Composable
private fun LibraryTab(container: KmpContainer, onStatus: (String) -> Unit) {
    data class LibrarySnapshot(
        val template: ConfigTemplate,
        val versions: Int,
    )

    var items by remember { mutableStateOf(emptyList<LibrarySnapshot>()) }
    var selectedTemplateId by remember { mutableStateOf<Long?>(null) }
    var search by remember { mutableStateOf("") }
    var kindFilter by remember { mutableStateOf<ConfigTemplateKind?>(null) }
    var filterExpanded by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        runCatching {
            container.configurationTemplateRepository.listTemplates().map { template ->
                LibrarySnapshot(
                    template = template,
                    versions = container.configurationTemplateRepository.listTemplateVersions(template.id).size,
                )
            }
        }.onSuccess {
            items = it
            selectedTemplateId = selectedTemplateId ?: it.firstOrNull()?.template?.id
            onStatus("Biblioteca cargada")
        }.onFailure { onStatus(it.message ?: "Error cargando biblioteca") }
    }

    val selected = items.firstOrNull { it.template.id == selectedTemplateId } ?: items.firstOrNull()
    val filteredItems = items.filter { item ->
        val matchesSearch = search.isBlank() || item.template.name.contains(search, ignoreCase = true)
        val matchesKind = kindFilter == null || item.template.kind == kindFilter
        matchesSearch && matchesKind
    }

    TwoPaneWorkspace(
        leftTitle = "Plantillas",
        left = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = search,
                    onValueChange = { search = it },
                    label = { Text("Buscar plantilla") },
                    modifier = Modifier.fillMaxWidth()
                )
                Box {
                    Button(onClick = { filterExpanded = true }, modifier = Modifier.fillMaxWidth().height(44.dp)) {
                        Text(kindFilter?.toReadableLabel() ?: "Todos los tipos")
                    }
                    DropdownMenu(
                        expanded = filterExpanded,
                        onDismissRequest = { filterExpanded = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text("Todos los tipos") },
                            onClick = {
                                kindFilter = null
                                filterExpanded = false
                            }
                        )
                        ConfigTemplateKind.entries.forEach { kind ->
                            DropdownMenuItem(
                                text = { Text(kind.toReadableLabel()) },
                                onClick = {
                                    kindFilter = kind
                                    filterExpanded = false
                                }
                            )
                        }
                    }
                }
            }
            if (filteredItems.isEmpty()) {
                EmptyWorkspaceState("No hay plantillas guardadas todavía.")
            } else {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(filteredItems) { item ->
                        WorkspaceListItem(
                            title = item.template.name,
                            subtitle = item.template.kind.toReadableLabel(),
                            selected = selected?.template?.id == item.template.id,
                            supporting = "${item.versions} versiones",
                            onClick = { selectedTemplateId = item.template.id }
                        )
                    }
                }
            }
        },
        rightTitle = selected?.template?.name ?: "Detalle de plantilla",
        right = {
            if (selected == null) {
                EmptyWorkspaceState("Selecciona una plantilla.")
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    MetricsRow(
                        "Tipo" to selected.template.kind.toReadableLabel(),
                        "Versiones" to selected.versions.toString(),
                    )
                    Text("Ámbito", style = MaterialTheme.typography.titleSmall)
                    Text(
                        when (selected.template.kind) {
                            ConfigTemplateKind.NOTEBOOK_COLUMNS -> "Lista para reaplicar configuraciones de columnas y vistas del cuaderno."
                            ConfigTemplateKind.RUBRIC -> "Disponible para reusar en evaluación y EF sin reconstruir criterios."
                            ConfigTemplateKind.UNIT_TEMPLATE -> "Reaprovecha estructura de unidad, diario o secuencia."
                            ConfigTemplateKind.CLASS_STRUCTURE -> "Sirve para clonar estructura base de grupo y organización."
                        },
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        "La biblioteca unifica reutilización de columnas, rúbricas y estructuras de clase.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    )
}

@Composable
private fun PEHubTab(container: KmpContainer, onStatus: (String) -> Unit) {
    data class PEHubSnapshot(
        val sessions: List<PlanningSession>,
        val incidents: List<Incident>,
        val physicalTests: Int,
        val materialSessions: Int,
        val sessionsWithMaterial: List<PlanningSession>,
        val criticalIncidents: List<Incident>,
    )

    var snapshot by remember { mutableStateOf<PEHubSnapshot?>(null) }

    LaunchedEffect(Unit) {
        runCatching {
            val classes = container.classesRepository.listClasses()
            val sessions = container.plannerRepository.listAllSessions()
            val incidents = classes.flatMap { schoolClass ->
                container.incidentsRepository.listIncidents(schoolClass.id)
            }
            val physicalTests = classes.sumOf { schoolClass ->
                container.evaluationsRepository.listClassEvaluations(schoolClass.id).count {
                    val label = "${it.type} ${it.name} ${it.description.orEmpty()}".lowercase()
                    "fis" in label || "resistencia" in label || "velocidad" in label || "test" in label
                }
            }
            val materialSessions = sessions.count { session ->
                container.sessionJournalRepository.getJournalForSession(session.id)?.journal?.let { journal ->
                    journal.materialToPrepareText.isNotBlank() || journal.materialUsedText.isNotBlank()
                } ?: false
            }
            val sessionsWithMaterial = sessions.filter { session ->
                container.sessionJournalRepository.getJournalForSession(session.id)?.journal?.let { journal ->
                    journal.materialToPrepareText.isNotBlank() || journal.materialUsedText.isNotBlank()
                } ?: false
            }
            PEHubSnapshot(
                sessions = sessions,
                incidents = incidents,
                physicalTests = physicalTests,
                materialSessions = materialSessions,
                sessionsWithMaterial = sessionsWithMaterial,
                criticalIncidents = incidents.filter { it.severity.equals("high", ignoreCase = true) || it.severity.equals("critical", ignoreCase = true) },
            )
        }.onSuccess {
            snapshot = it
            onStatus("Hub EF cargado")
        }.onFailure { onStatus(it.message ?: "Error cargando EF") }
    }

    val data = snapshot
    if (data == null) {
        EmptyWorkspaceState("Cargando contexto EF…")
        return
    }

    Column(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        MetricsRow(
            "Sesiones" to data.sessions.size.toString(),
            "Incidencias" to data.incidents.size.toString(),
            "Pruebas físicas" to data.physicalTests.toString(),
            "Material" to data.materialSessions.toString(),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp), modifier = Modifier.fillMaxWidth()) {
            WorkspacePanel(title = "Operativa", modifier = Modifier.weight(1f)) {
                Text("La shell desktop ya expone un hub EF con datos reales del planner y del diario.")
                Spacer(modifier = Modifier.height(8.dp))
                Text("• Sesiones activas y planificadas")
                Text("• Incidencias físicas o de seguridad")
                Text("• Pruebas físicas detectadas por instrumento")
                if (data.sessionsWithMaterial.isNotEmpty()) {
                    HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                    Text("Sesiones con logística", style = MaterialTheme.typography.titleSmall)
                    data.sessionsWithMaterial.take(4).forEach { session ->
                        Text("• ${session.groupName} · ${session.teachingUnitName} · Semana ${session.weekNumber}")
                    }
                }
            }
            WorkspacePanel(title = "Últimas incidencias", modifier = Modifier.weight(1f)) {
                if (data.incidents.isEmpty()) {
                    EmptyWorkspaceState("Sin incidencias EF registradas.")
                } else {
                    data.incidents.take(6).forEach { incident ->
                        Text("• ${incident.title} · ${incident.severity}")
                    }
                }
                if (data.criticalIncidents.isNotEmpty()) {
                    HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                    Text("Críticas", style = MaterialTheme.typography.titleSmall)
                    data.criticalIncidents.take(3).forEach { incident ->
                        Text("• ${incident.title}")
                    }
                }
            }
        }
    }
}

@Composable
private fun TwoPaneWorkspace(
    leftTitle: String,
    left: @Composable () -> Unit,
    rightTitle: String,
    right: @Composable () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        WorkspacePanel(title = leftTitle, modifier = Modifier.weight(0.42f)) {
            left()
        }
        WorkspacePanel(title = rightTitle, modifier = Modifier.weight(0.58f)) {
            right()
        }
    }
}

@Composable
private fun WorkspacePanel(
    title: String,
    modifier: Modifier = Modifier,
    content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit,
) {
    Surface(
        modifier = modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.28f),
        tonalElevation = 1.dp,
        shape = MaterialTheme.shapes.large,
    ) {
        Column(
            modifier = Modifier.fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            content()
        }
    }
}

@Composable
private fun WorkspaceListItem(
    title: String,
    subtitle: String,
    selected: Boolean,
    supporting: String,
    onClick: () -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        color = if (selected) {
            MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
        } else {
            MaterialTheme.colorScheme.surface.copy(alpha = 0.65f)
        },
        shape = MaterialTheme.shapes.medium,
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(supporting, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun MetricsRow(vararg metrics: Pair<String, String>) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        metrics.forEach { (label, value) ->
            MetricCard(label = label, value = value, modifier = Modifier.weight(1f))
        }
    }
}

@Composable
private fun RowScope.MetricCard(label: String, value: String, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier,
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.72f),
        shape = MaterialTheme.shapes.medium,
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.titleMedium)
        }
    }
}

@Composable
private fun EmptyWorkspaceState(message: String) {
    Text(
        text = message,
        style = MaterialTheme.typography.bodyMedium.copy(fontStyle = FontStyle.Italic),
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

private fun ConfigTemplateKind.toReadableLabel(): String = when (this) {
    ConfigTemplateKind.NOTEBOOK_COLUMNS -> "Columnas de cuaderno"
    ConfigTemplateKind.RUBRIC -> "Rúbrica"
    ConfigTemplateKind.UNIT_TEMPLATE -> "Unidad / diario"
    ConfigTemplateKind.CLASS_STRUCTURE -> "Estructura de clase"
}

private fun AppTab.sectionLabel(): String = when (this) {
    AppTab.Dashboard -> "Visión global"
    AppTab.Cursos -> "Académico"
    AppTab.Cuaderno -> "Evaluación"
    AppTab.PaseDeLista -> "Operativa"
    AppTab.Diario -> "Operativa"
    AppTab.Planificacion -> "Académico"
    AppTab.Evaluacion -> "Evaluación"
    AppTab.Rubricas -> "Evaluación"
    AppTab.Informes -> "Salida docente"
    AppTab.Biblioteca -> "Reutilización"
    AppTab.EducacionFisica -> "Educación Física"
    AppTab.Backups -> "Sistema"
    AppTab.Ajustes -> "Sistema"
}

@Composable
private fun BackupsTab(container: KmpContainer, scope: CoroutineScope, onStatus: (String) -> Unit) {
    var backups by remember { mutableStateOf(listOf<String>()) }
    var backupMenuExpanded by remember { mutableStateOf(false) }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = {
                scope.launch {
                    runCatching {
                        val created = container.backupService.createBackup()
                        container.backupMetadataRepository.saveBackup(
                            path = created.path,
                            createdAtEpochMs = kotlinx.datetime.Clock.System.now().toEpochMilliseconds(),
                            platform = "desktop",
                            sizeBytes = created.sizeBytes,
                        )
                    }.onSuccess { onStatus("Backup creado") }
                        .onFailure { onStatus(it.message ?: "Error backup") }
                }
            }, modifier = Modifier.height(44.dp)) {
                Icon(Icons.Default.Backup, contentDescription = null)
                Text(" Crear backup")
            }

            Box {
                IconButton(onClick = { backupMenuExpanded = true }, modifier = Modifier.size(44.dp)) {
                    Icon(Icons.Default.MoreVert, "Más acciones de backups")
                }
                DropdownMenu(
                    expanded = backupMenuExpanded,
                    onDismissRequest = { backupMenuExpanded = false }
                ) {
                    DropdownMenuItem(
                        text = { Text("Restaurar último") },
                        leadingIcon = { Icon(Icons.Default.Restore, contentDescription = null) },
                        onClick = {
                            backupMenuExpanded = false
                            scope.launch {
                                runCatching {
                                    val latest = container.backupMetadataRepository.listBackups().firstOrNull()
                                    if (latest != null) {
                                        container.backupService.restoreBackup(latest.path)
                                    }
                                }.onSuccess { onStatus("Restore ejecutado") }
                                    .onFailure { onStatus(it.message ?: "Error restore") }
                            }
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Cargar backups") },
                        leadingIcon = { Icon(Icons.Default.FolderOpen, contentDescription = null) },
                        onClick = {
                            backupMenuExpanded = false
                            scope.launch {
                                runCatching {
                                    container.backupMetadataRepository.listBackups().map {
                                        "${it.createdAt} · ${it.path} (${it.sizeBytes} bytes)"
                                    }
                                }.onSuccess {
                                    backups = it
                                    onStatus("Backups cargados")
                                }.onFailure {
                                    onStatus(it.message ?: "Error listando backups")
                                }
                            }
                        }
                    )
                }
            }
        }

        LazyColumn { items(backups) { Text(it) } }
    }
}
