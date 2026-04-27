package com.migestor.shared.viewmodel

import com.migestor.shared.domain.*
import com.migestor.shared.formula.FormulaEvaluator
import com.migestor.shared.repository.*
import com.migestor.shared.usecase.*
import com.migestor.shared.util.NotebookRefreshBus
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.datetime.Clock
import kotlin.native.ObjCName

enum class NotebookViewModelSaveState { Saved, Unsaved, Saving }

class NotebookViewModel(
    private val notebookRepository: NotebookRepository,
    private val evaluationsRepository: EvaluationsRepository,
    private val rubricsRepository: RubricsRepository,
    private val studentImporter: StudentImporter = StudentImporter(),
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
) {
    private val _numericDrafts = MutableStateFlow<Map<Pair<Long, String>, String>>(emptyMap())
    private val _textDrafts = MutableStateFlow<Map<Pair<Long, String>, String>>(emptyMap())
    private val _checkDrafts = MutableStateFlow<Map<Pair<Long, String>, Boolean>>(emptyMap())
    private val _activeCell = MutableStateFlow<ActiveCell?>(null)
    private val _selectedTabId = MutableStateFlow<String?>(null)
    private val formulaEvaluator = FormulaEvaluator()

    init {
        loadInitialData()
        observeRefreshSignals()
        observeRubricEvaluationEvents()
    }

    private val _isSyncing = MutableStateFlow(false)
    val isSyncing: StateFlow<Boolean> = _isSyncing.asStateFlow()

    private val _isDirty = MutableStateFlow(false)
    val isDirty: StateFlow<Boolean> = _isDirty.asStateFlow()
    private val _pendingInlineSaves = MutableStateFlow(0)

    val saveState: StateFlow<NotebookViewModelSaveState> = combine(_isDirty, _isSyncing) { dirty, syncing ->
        when {
            syncing -> NotebookViewModelSaveState.Saving
            dirty -> NotebookViewModelSaveState.Unsaved
            else -> NotebookViewModelSaveState.Saved
        }
    }.stateIn(scope, SharingStarted.WhileSubscribed(), NotebookViewModelSaveState.Saved)

    fun markDirty() { _isDirty.value = true }
    fun markClean() { _isDirty.value = false }
    fun setSyncing(syncing: Boolean) { _isSyncing.value = syncing }

    private fun beginInlineSave() {
        _pendingInlineSaves.update { it + 1 }
        setSyncing(true)
    }

    private fun endInlineSave(): Int {
        _pendingInlineSaves.update { current -> (current - 1).coerceAtLeast(0) }
        val remaining = _pendingInlineSaves.value
        if (remaining == 0) {
            setSyncing(false)
        }
        return remaining
    }

    private val _state = MutableStateFlow<NotebookUiState>(NotebookUiState.Loading)
    val state: StateFlow<NotebookUiState> = _state.asStateFlow()

    private val _importResult = MutableStateFlow<ImportResult?>(null)
    val importResult: StateFlow<ImportResult?> = _importResult.asStateFlow()

    val userRubrics: Flow<List<RubricDetail>> = rubricsRepository.observeRubrics()

    private var activeClassId: Long? = null
    private var observerJob: Job? = null
    private var cachedEvaluations: List<Evaluation> = emptyList()

    private fun loadInitialData() {
        // Placeholder for initial data loading if needed
    }

    private fun observeRefreshSignals() {
        scope.launch {
            NotebookRefreshBus.refreshSignal.collect {
                activeClassId?.let { selectClass(it, force = true) }
            }
        }
    }

    private fun observeRubricEvaluationEvents() {
        scope.launch {
            RubricEvaluationBus.events.collect { event ->
                val columnId = event.columnId ?: return@collect
                
                _state.update { currentState ->
                    if (currentState !is NotebookUiState.Data) return@update currentState
                    
                    // Buscar el evaluationId asociado a esa columna
                    val evalId = currentState.sheet.columns.find { it.id == columnId }?.evaluationId ?: return@update currentState

                    _numericDrafts.update { drafts ->
                        drafts + ((event.studentId to columnId) to event.score.toString())
                    }

                    val updatedRows = currentState.sheet.rows.map { row ->
                        if (row.student.id == event.studentId) {
                            val updatedCells = row.cells.map { cell ->
                                if (cell.evaluationId == evalId) {
                                    cell.copy(value = event.score)
                                } else {
                                    cell
                                }
                            }
                            row.copy(cells = updatedCells)
                        } else {
                            row
                        }
                    }
                    currentState.copy(
                        sheet = currentState.sheet.copy(rows = updatedRows),
                        numericDrafts = _numericDrafts.value
                    )
                }
            }
        }
    }

    private fun buildDataState(
        snapshot: NotebookSheet,
        evaluations: List<Evaluation>,
        previous: NotebookUiState.Data? = null,
    ): NotebookUiState.Data {
        val numDrafts = mutableMapOf<Pair<Long, String>, String>()
        val txtDrafts = mutableMapOf<Pair<Long, String>, String>()
        val chkDrafts = mutableMapOf<Pair<Long, String>, Boolean>()
        val columnIdsByEvaluationId = snapshot.columns
            .filter { it.evaluationId != null }
            .groupBy { it.evaluationId!! }
            .mapValues { (_, cols) -> cols.map { it.id } }

        snapshot.rows.forEach { row ->
            val sId = row.student.id

            row.cells.forEach { cell ->
                if (cell.evaluationId != null && cell.value != null) {
                    numDrafts[sId to "eval_${cell.evaluationId}"] = cell.value.toString()
                }
            }

            row.persistedGrades.forEach { grade ->
                grade.value?.let { numDrafts[sId to grade.columnId] = it.toString() }
                grade.evaluationId?.let { evalId ->
                    grade.value?.let { value ->
                        numDrafts[sId to "eval_$evalId"] = value.toString()
                        columnIdsByEvaluationId[evalId]?.forEach { columnId ->
                            numDrafts[sId to columnId] = value.toString()
                        }
                    }
                }
            }

            row.persistedCells.forEach { cell ->
                cell.textValue?.let { txtDrafts[sId to cell.columnId] = it }
                cell.boolValue?.let { chkDrafts[sId to cell.columnId] = it }
                cell.iconValue?.let { txtDrafts[sId to cell.columnId] = it }
                cell.ordinalValue?.let { txtDrafts[sId to cell.columnId] = it }
            }
        }

        applyCalculatedDrafts(snapshot = snapshot, evaluations = evaluations, numericDrafts = numDrafts)

        return NotebookUiState.Data(
            sheet = snapshot,
            selectedColumnIds = previous?.selectedColumnIds ?: emptySet(),
            isColumnSelectionMode = previous?.isColumnSelectionMode ?: false,
            rubricEvaluationTarget = previous?.rubricEvaluationTarget,
            activeCellEditor = previous?.activeCellEditor,
            activeCell = previous?.activeCell,
            numericDrafts = numDrafts,
            textDrafts = txtDrafts,
            checkDrafts = chkDrafts,
            workGroups = snapshot.workGroups,
            workGroupMembers = snapshot.workGroupMembers
        )
    }

    val currentClassId: Long? get() = activeClassId

    fun selectClass(classId: Long, force: Boolean = false) {
        if (!force && activeClassId == classId) return

        // Nunca emitir Loading si ya tenemos datos para esta clase.
        // Esto evita que refrescos forzados (sync, addColumn, etc.) destruyan
        // la jerarquía SwiftUI y los @State/@FocusState de las celdas en edición.
        val alreadyHasData = _state.value is NotebookUiState.Data && activeClassId == classId
        activeClassId = classId
        observerJob?.cancel()
        if (!alreadyHasData) {
            _state.value = NotebookUiState.Loading
        }

        scope.launch {
            try {
                val snapshot = notebookRepository.loadNotebookSnapshot(classId)
                val evaluations = evaluationsRepository.listClassEvaluations(classId)
                val currentData = _state.value as? NotebookUiState.Data
                cachedEvaluations = evaluations
                val freshDataState = buildDataState(snapshot, evaluations, currentData)

                // Si hay un dirty en curso (usuario editando), preservar sus drafts
                // para no pisar valores que aún no han disparado su guardado.
                if (_isDirty.value && currentData != null) {
                    val mergedNumeric = freshDataState.numericDrafts + _numericDrafts.value
                    val mergedText = freshDataState.textDrafts + _textDrafts.value
                    val mergedCheck = freshDataState.checkDrafts + _checkDrafts.value
                    _numericDrafts.value = mergedNumeric
                    _textDrafts.value = mergedText
                    _checkDrafts.value = mergedCheck
                    _state.value = freshDataState.copy(
                        numericDrafts = mergedNumeric,
                        textDrafts = mergedText,
                        checkDrafts = mergedCheck
                    )
                } else {
                    _numericDrafts.value = freshDataState.numericDrafts
                    _textDrafts.value = freshDataState.textDrafts
                    _checkDrafts.value = freshDataState.checkDrafts
                    _state.value = freshDataState
                    markClean()
                }

                _selectedTabId.value = resolveSelectedTabId((_state.value as? NotebookUiState.Data)?.sheet?.tabs ?: emptyList())

                // Verificamos si seguimos registrados en la misma clase tras el suspend
                if (activeClassId == classId) {
                    startObservingData(classId)
                }
            } catch (e: Exception) {
                if (activeClassId == classId) {
                    _state.value = NotebookUiState.Error(e.message ?: "Error al cargar el cuaderno")
                }
            }
        }
    }

    private fun startObservingData(classId: Long) {
        observerJob?.cancel()
        observerJob = combine(
            notebookRepository.observeStudentChanges(classId),
            notebookRepository.observeGradesForClass(classId)
        ) { _, _ -> }
            .drop(1)
            .debounce(400) // Evita recargas ante ráfagas de cambios (ej: escritura rápida)
            .onEach {
                val currentState = _state.value
                if (currentState is NotebookUiState.Data) {
                    try {
                        val updatedSnapshot = notebookRepository.loadNotebookSnapshot(classId)
                        val evaluations = evaluationsRepository.listClassEvaluations(classId)
                        cachedEvaluations = evaluations
                        val freshState = buildDataState(updatedSnapshot, evaluations, currentState)

                        // Preservar los drafts del usuario si está en medio de una edición.
                        // Esto evita que el eco de nuestras propias escrituras en DB pise
                        // los valores locales de las celdas antes de que el usuario confirme.
                        if (_isDirty.value) {
                            val mergedNumeric = freshState.numericDrafts + _numericDrafts.value
                            val mergedText = freshState.textDrafts + _textDrafts.value
                            val mergedCheck = freshState.checkDrafts + _checkDrafts.value
                            _numericDrafts.value = mergedNumeric
                            _textDrafts.value = mergedText
                            _checkDrafts.value = mergedCheck
                            _state.value = freshState.copy(
                                numericDrafts = mergedNumeric,
                                textDrafts = mergedText,
                                checkDrafts = mergedCheck
                            )
                        } else {
                            _numericDrafts.value = freshState.numericDrafts
                            _textDrafts.value = freshState.textDrafts
                            _checkDrafts.value = freshState.checkDrafts
                            _state.value = freshState
                        }
                    } catch (e: Exception) {
                        // Log o manejar error de actualización silenciosa
                    }
                }
            }.launchIn(scope)
    }

    fun addStudent(firstName: String, lastName: String, isInjured: Boolean = false) {
        val classId = activeClassId ?: return
        scope.launch {
            try {
                notebookRepository.addStudent(classId, firstName, lastName, isInjured)
                updateLocalStudentList()
            } catch (e: Exception) {
                // Manejar error
            }
        }
    }

    private fun updateLocalStudentList() {
        // Opcional: optimismo UI
        val currentState = _state.value
        if (currentState is NotebookUiState.Data) {
            // ... implementar lógica de optimismo si es necesario
        }
    }

    fun importStudents(content: String) {
        val classId = activeClassId ?: return
        scope.launch {
            val result = studentImporter.import(content)
            if (result is ImportResult.Success || result is ImportResult.PartialSuccess) {
                val studentsToImport = (result as? ImportResult.Success)?.students 
                    ?: (result as? ImportResult.PartialSuccess)?.students 
                    ?: emptyList()
                
                for (student in studentsToImport) {
                    notebookRepository.addStudent(classId, student.firstName, student.lastName, isInjured = false)
                }
            }
            _importResult.value = result
        }
    }

    fun deleteStudent(studentId: Long) {
        val classId = activeClassId ?: return
        scope.launch {
            try {
                notebookRepository.removeStudent(classId, studentId)
            } catch (e: Exception) {
                // Manejar error
            }
        }
    }

    fun saveGrade(studentId: Long, evaluationId: Long, value: Double?) {
        val classId = activeClassId ?: return
        scope.launch {
            try {
                notebookRepository.saveGrade(
                    classId = classId,
                    studentId = studentId,
                    columnId = "eval_$evaluationId",
                    evaluationId = evaluationId,
                    value = value
                )
                _numericDrafts.update { drafts ->
                    val key = studentId to "eval_$evaluationId"
                    if (value == null) drafts - key else drafts + (key to value.toString())
                }
                // Actualizamos localmente para feedback instantáneo
                val currentState = _state.value
                if (currentState is NotebookUiState.Data) {
                    val updatedRows = currentState.sheet.rows.map { row ->
                        if (row.student.id == studentId) {
                            val updatedCells = row.cells.map { cell ->
                                if (cell.evaluationId == evaluationId) cell.copy(value = value) else cell
                            }
                            row.copy(cells = updatedCells)
                        } else row
                    }
                    _state.value = currentState.copy(sheet = currentState.sheet.copy(rows = updatedRows))
                    markClean()
                }
            } catch (e: Exception) {
                // Manejar error
            }
        }
    }

    fun onRubricCellClicked(studentId: Long, columnId: String, rubricId: Long, evaluationId: Long) {
        val currentState = _state.value as? NotebookUiState.Data ?: return
        _state.value = currentState.copy(
            rubricEvaluationTarget = RubricEvaluationTarget(studentId, columnId, rubricId, evaluationId)
        )
    }

    fun clearRubricEvaluationTarget() {
        val currentState = _state.value as? NotebookUiState.Data ?: return
        _state.value = currentState.copy(rubricEvaluationTarget = null)
    }

    fun activateEditor(studentIndex: Int, student: com.migestor.shared.domain.Student, column: NotebookColumnDefinition, currentValue: String) {
        val currentState = _state.value as? NotebookUiState.Data ?: return
        _state.value = currentState.copy(
            activeCellEditor = ActiveCellEditor(studentIndex, student, column, currentValue)
        )
    }

    fun clearActiveEditor() {
        val currentState = _state.value as? NotebookUiState.Data ?: return
        _state.value = currentState.copy(activeCellEditor = null)
    }

    fun upsertRubricGrade(studentId: Long, columnId: String, numericValue: Double, rubricSelections: String, evaluationId: Long) {
        val classId = activeClassId ?: return
        val safeColumnId = columnId.ifBlank { "eval_$evaluationId" }
        scope.launch {
            try {
                notebookRepository.upsertGrade(
                    classId = classId,
                    studentId = studentId,
                    columnId = safeColumnId,
                    evaluationId = evaluationId,
                    numericValue = numericValue,
                    rubricSelections = rubricSelections,
                    evidence = null
                )
                _numericDrafts.update { drafts ->
                    drafts + ((studentId to safeColumnId) to numericValue.toString())
                }
                markClean()
                // Recargamos para ver la nueva nota en el cuaderno
                selectClass(classId, force = true)
            } catch (e: Exception) {
                // Manejar error
            }
        }
    }

    fun saveTab(tab: NotebookTab) {
        val classId = activeClassId ?: return
        scope.launch {
            notebookRepository.saveTab(classId, tab)
            // Aquí podríamos forzar recarga del snapshot si queremos ver el cambio reflejado
            // selectClass(classId, force = true)
        }
    }

    fun deleteTab(tabId: String) {
        val classId = activeClassId ?: return
        val currentState = _state.value as? NotebookUiState.Data ?: return
        scope.launch {
            try {
                val removedTabIds = collectTabAndDescendantIds(currentState.sheet.tabs, tabId)
                val columnsToAdjust = currentState.sheet.columns.filter { column ->
                    column.tabIds.any { it in removedTabIds } && !column.sharedAcrossTabs
                }
                columnsToAdjust.forEach { column ->
                    val remainingTabIds = column.tabIds.filterNot { it in removedTabIds }
                    if (remainingTabIds.isEmpty()) {
                        notebookRepository.deleteColumn(column.id)
                    } else {
                        notebookRepository.saveColumn(classId, column.copy(tabIds = remainingTabIds))
                    }
                }
                removedTabIds.sortedByDescending { it.length }.forEach { notebookRepository.deleteTab(it) }
                selectClass(classId, force = true)
            } catch (e: Exception) {
                // Manejar error
            }
        }
    }

    fun saveColumn(column: NotebookColumnDefinition) {
        val classId = activeClassId ?: return
        scope.launch {
            try {
                var columnToSave = column
                
                // Si es una rúbrica nueva sin evaluación asociada, la creamos
                if (column.type == NotebookColumnType.RUBRIC && column.evaluationId == null && column.rubricId != null) {
                    val evaluationId = evaluationsRepository.saveEvaluation(
                        classId = classId,
                        code = "RBC_${Clock.System.now().toEpochMilliseconds()}",
                        name = column.title,
                        type = "Rúbrica",
                        weight = column.weight,
                        rubricId = column.rubricId
                    )
                    columnToSave = column.copy(evaluationId = evaluationId)
                }

                val currentState = _state.value as? NotebookUiState.Data
                val tabs = currentState?.sheet?.tabs.orEmpty()
                val normalizedColumn = normalizeColumnPlacement(
                    column = columnToSave,
                    tabs = tabs,
                    selectedTabId = _selectedTabId.value
                )

                // Actualización optimista para reflejar color/ancho de columna al instante.
                updateDataState { state ->
                    val updatedColumns = state.sheet.columns
                        .filterNot { it.id == normalizedColumn.id }
                        .plus(normalizedColumn)
                        .sortedWith(compareBy<NotebookColumnDefinition> { it.order }.thenBy { it.id })
                    state.copy(sheet = state.sheet.copy(columns = updatedColumns))
                }

                notebookRepository.saveColumn(classId = classId, column = normalizedColumn)
                // Reconciliación silenciosa para mantener consistencia con persistencia/sync.
                selectClass(classId, force = true)
            } catch (e: Exception) {
                // Reconciliar estado en caso de error de persistencia tras optimismo.
                selectClass(classId, force = true)
            }
        }
    }

    fun reorderColumns(columnId: String, targetColumnId: String) {
        val classId = activeClassId ?: return
        val currentState = _state.value as? NotebookUiState.Data ?: return

        val sortedColumns = currentState.sheet.columns
            .sortedWith(compareBy<NotebookColumnDefinition> { it.order }.thenBy { it.id })
            .toMutableList()

        val fromIndex = sortedColumns.indexOfFirst { it.id == columnId }
        val targetIndex = sortedColumns.indexOfFirst { it.id == targetColumnId }
        if (fromIndex < 0 || targetIndex < 0 || fromIndex == targetIndex) return

        val movedColumn = sortedColumns.removeAt(fromIndex)
        val adjustedTargetIndex = if (fromIndex < targetIndex) targetIndex - 1 else targetIndex
        sortedColumns.add(adjustedTargetIndex.coerceIn(0, sortedColumns.size), movedColumn)

        val reorderedColumns = sortedColumns.mapIndexed { index, column ->
            column.copy(order = index)
        }

        updateDataState { state ->
            state.copy(sheet = state.sheet.copy(columns = reorderedColumns))
        }

        scope.launch {
            try {
                reorderedColumns.forEach { column ->
                    notebookRepository.saveColumn(classId, column)
                }
                selectClass(classId, force = true)
            } catch (e: Exception) {
                selectClass(classId, force = true)
            }
        }
    }

    @ObjCName("deleteColumnById")
    fun deleteColumn(columnId: String) {
        val classId = activeClassId ?: return
        val currentState = _state.value as? NotebookUiState.Data ?: return

        // Optimismo: eliminamos visualmente de inmediato
        val updatedColumns = currentState.sheet.columns.filter { it.id != columnId }
        _state.value = currentState.copy(sheet = currentState.sheet.copy(columns = updatedColumns))

        scope.launch {
            try {
                // Primero intentamos borrar la columna
                notebookRepository.deleteColumn(columnId)
                selectClass(classId, force = true)
            } catch (e: Exception) {
                println("Error deleting column $columnId: ${e.message}")
                // Revertir en caso de fallo crítico
                selectClass(classId, force = true)
            }
        }
    }

    fun toggleColumnSelection(columnId: String) {
        val currentState = _state.value as? NotebookUiState.Data ?: return
        val newSelection = if (currentState.selectedColumnIds.contains(columnId)) {
            currentState.selectedColumnIds - columnId
        } else {
            currentState.selectedColumnIds + columnId
        }
        _state.value = currentState.copy(
            selectedColumnIds = newSelection,
            isColumnSelectionMode = newSelection.isNotEmpty()
        )
    }

    fun deleteSelectedColumns() {
        val currentState = _state.value as? NotebookUiState.Data ?: return
        val columnIds = currentState.selectedColumnIds
        if (columnIds.isEmpty()) return

        // Optimismo
        val updatedColumns = currentState.sheet.columns.filter { !columnIds.contains(it.id) }
        _state.value = currentState.copy(
            sheet = currentState.sheet.copy(columns = updatedColumns),
            selectedColumnIds = emptySet(),
            isColumnSelectionMode = false
        )

        scope.launch {
            try {
                columnIds.forEach { columnId ->
                    notebookRepository.deleteColumn(columnId)
                }
                activeClassId?.let { selectClass(it, force = true) }
            } catch (e: Exception) {
                activeClassId?.let { selectClass(it, force = true) }
            }
        }
    }

    fun setSelectedTabId(tabId: String?) {
        _selectedTabId.value = tabId?.takeIf { it.isNotBlank() }
    }

    fun clearColumnSelection() {
        val currentState = _state.value as? NotebookUiState.Data ?: return
        _state.value = currentState.copy(
            selectedColumnIds = emptySet(),
            isColumnSelectionMode = false
        )
    }

    fun clearImportResult() {
        _importResult.value = null
    }

    fun saveColumnGrade(studentId: Long, column: NotebookColumnDefinition, value: String) {
        activeClassId ?: return
        // Optimistic update for immediate UI feedback without forcing full notebook reloads.
        updateDraft(studentId, column.id, column.type, value)
        scope.launch {
            try {
                internalSaveGrade(studentId, column, value)
                markClean()
            } catch (e: Exception) {
                println("Error saving column grade: ${e.message}")
            }
        }
    }

    private suspend fun internalSaveGrade(studentId: Long, column: NotebookColumnDefinition, value: String) {
        val classId = activeClassId ?: return
        when (column.type) {
            NotebookColumnType.NUMERIC -> {
                val raw = value.trim()
                val numericValue = raw.replace(",", ".").toDoubleOrNull()
                if (raw.isNotEmpty() && numericValue == null) return
                notebookRepository.saveGrade(
                    classId = classId,
                    studentId = studentId,
                    columnId = column.id,
                    evaluationId = column.evaluationId,
                    value = numericValue
                )
            }
            NotebookColumnType.TEXT -> {
                notebookRepository.saveCell(classId, studentId, column.id, textValue = value)
            }
            NotebookColumnType.CHECK -> {
                notebookRepository.saveCell(classId, studentId, column.id, boolValue = value.toBoolean())
            }
            NotebookColumnType.ICON -> {
                notebookRepository.saveCell(classId, studentId, column.id, iconValue = value)
            }
            NotebookColumnType.ORDINAL -> {
                notebookRepository.saveCell(classId, studentId, column.id, ordinalValue = value)
            }
            NotebookColumnType.ATTENDANCE -> {
                notebookRepository.saveCell(classId, studentId, column.id, textValue = value)
            }
            else -> {}
        }
    }

    suspend fun saveCurrentNotebook(): Boolean {
        val classId = activeClassId ?: return false
        val currentState = _state.value as? NotebookUiState.Data ?: return false

        setSyncing(true)
        return try {
            currentState.sheet.rows.forEach { row ->
                currentState.sheet.columns.forEach { column ->
                    val key = row.student.id to column.id
                    when (column.type) {
                        NotebookColumnType.NUMERIC,
                        NotebookColumnType.RUBRIC -> {
                            val draft = currentState.numericDrafts[key]
                            if (draft != null) {
                                notebookRepository.saveGrade(
                                    classId = classId,
                                    studentId = row.student.id,
                                    columnId = column.id,
                                    evaluationId = column.evaluationId,
                                    value = draft.replace(",", ".").toDoubleOrNull()
                                )
                            }
                        }
                        NotebookColumnType.ATTENDANCE -> {
                            val draft = currentState.textDrafts[key] ?: currentState.numericDrafts[key]
                            if (draft != null) {
                                notebookRepository.saveCell(
                                    classId = classId,
                                    studentId = row.student.id,
                                    columnId = column.id,
                                    textValue = draft
                                )
                            }
                        }
                        NotebookColumnType.TEXT -> {
                            val draft = currentState.textDrafts[key]
                            if (draft != null) {
                                notebookRepository.saveCell(
                                    classId = classId,
                                    studentId = row.student.id,
                                    columnId = column.id,
                                    textValue = draft
                                )
                            }
                        }
                        NotebookColumnType.ICON -> {
                            val draft = currentState.textDrafts[key]
                            if (draft != null) {
                                notebookRepository.saveCell(
                                    classId = classId,
                                    studentId = row.student.id,
                                    columnId = column.id,
                                    iconValue = draft
                                )
                            }
                        }
                        NotebookColumnType.ORDINAL -> {
                            val draft = currentState.textDrafts[key]
                            if (draft != null) {
                                notebookRepository.saveCell(
                                    classId = classId,
                                    studentId = row.student.id,
                                    columnId = column.id,
                                    ordinalValue = draft
                                )
                            }
                        }
                        NotebookColumnType.CHECK -> {
                            val draft = currentState.checkDrafts[key]
                            if (draft != null) {
                                notebookRepository.saveCell(
                                    classId = classId,
                                    studentId = row.student.id,
                                    columnId = column.id,
                                    boolValue = draft
                                )
                            }
                        }
                        else -> Unit
                    }
                }
            }

            markClean()
            NotebookRefreshBus.emitRefresh()
            true
        } catch (e: Exception) {
            false
        } finally {
            setSyncing(false)
        }
    }

    fun updateDraft(studentId: Long, columnId: String, type: NotebookColumnType, value: Any) {
        val valStr = value.toString()
        when (type) {
            NotebookColumnType.NUMERIC -> {
                _numericDrafts.update { it + ((studentId to columnId) to valStr) }
            }
            NotebookColumnType.CHECK -> {
                val boolValue = when(value) {
                    is Boolean -> value
                    is String -> value.toBoolean()
                    else -> false
                }
                _checkDrafts.update { it + ((studentId to columnId) to boolValue) }
            }
            else -> {
                _textDrafts.update { it + ((studentId to columnId) to valStr) }
            }
        }
        if (type == NotebookColumnType.NUMERIC || type == NotebookColumnType.RUBRIC) {
            recalculateCalculatedDraftsForStudent(studentId)
        }
        markDirty()
        
        // Optimismo: actualizamos también el sheet localmente si es posible
        updateDataState { currentState ->
            val updatedRows = currentState.sheet.rows.map { row ->
                if (row.student.id == studentId) {
                    val updatedCells = row.cells.map { cell ->
                        if (cell.evaluationId != null && columnId == "eval_${cell.evaluationId}") {
                            cell.copy(value = valStr.toDoubleOrNull())
                        } else cell
                    }
                    row.copy(cells = updatedCells)
                } else row
            }
            currentState.copy(
                sheet = currentState.sheet.copy(rows = updatedRows),
                numericDrafts = _numericDrafts.value,
                textDrafts = _textDrafts.value,
                checkDrafts = _checkDrafts.value
            )
        }
    }

    fun setActiveCell(studentIndex: Int, columnId: String) {
        _activeCell.value = ActiveCell(studentIndex, columnId)
        updateDataState { it.copy(activeCell = _activeCell.value) }
    }

    fun clearActiveCell() {
        _activeCell.value = null
        updateDataState { it.copy(activeCell = null) }
    }

    fun confirmAndAdvance(studentIndex: Int, column: NotebookColumnDefinition, value: String) {
        activeClassId ?: return
        val currentState = _state.value as? NotebookUiState.Data ?: return
        val row = visibleRowsFor(currentState).getOrNull(studentIndex) ?: return
        val student = row.student

        // 1. Optimistic local update
        updateDraft(student.id, column.id, column.type, value)

        // 2. Advance focus immediately
        val nextIndex = if (studentIndex < visibleRowsFor(currentState).size - 1) studentIndex + 1 else null
        _activeCell.value = nextIndex?.let { ActiveCell(it, column.id) }
        updateDataState { it.copy(
            activeCell = _activeCell.value,
            activeCellEditor = null // Cierra el editor si estaba abierto
        ) }

        // 3. Persistent save in background
        beginInlineSave()
        scope.launch {
            try {
                internalSaveGrade(student.id, column, value)
            } catch (e: Exception) {
                println("Error in confirmAndAdvance: ${e.message}")
                // In case of error, we might want to notify or revert
            } finally {
                if (endInlineSave() == 0) {
                    markClean()
                }
            }
        }
    }

    fun moveToPreviousStudent(studentIndex: Int, columnId: String) {
        if (studentIndex > 0) {
            _activeCell.value = ActiveCell(studentIndex - 1, columnId)
            updateDataState { it.copy(activeCell = _activeCell.value) }
        }
    }

    private fun updateDataState(transform: (NotebookUiState.Data) -> NotebookUiState.Data) {
        _state.update { currentState ->
            if (currentState is NotebookUiState.Data) transform(currentState) else currentState
        }
    }

    fun duplicateConfigToClass(targetClassId: Long) {
        val sourceClassId = activeClassId ?: return
        scope.launch {
            notebookRepository.duplicateConfigToClass(sourceClassId, targetClassId)
        }
    }

    // Statistics functions for GroupSummaryBar
    fun calculateClassAverage(sheet: NotebookSheet): Double {
        val rows = sheet.rows
        if (rows.isEmpty()) return 0.0
        
        val averages = rows.mapNotNull { row ->
            val values = sheet.columns.filter {
                (it.type == NotebookColumnType.NUMERIC || it.type == NotebookColumnType.RUBRIC) && it.countsTowardAverage
            }.mapNotNull { col ->
                row.cells.find { it.evaluationId == col.evaluationId }?.value
                ?: row.persistedGrades.find { it.columnId == col.id }?.value
            }
            if (values.isNotEmpty()) values.average() else null
        }
        return if (averages.isNotEmpty()) averages.average() else 0.0
    }

    fun countUnevaluatedStudents(sheet: NotebookSheet): Int {
        val evaluableCols = sheet.columns.filter {
            (it.type == NotebookColumnType.NUMERIC || it.type == NotebookColumnType.RUBRIC) && it.countsTowardAverage
        }
        if (evaluableCols.isEmpty()) return 0
        
        return sheet.rows.count { row ->
            evaluableCols.any { col ->
                row.cells.none { it.evaluationId == col.evaluationId && it.value != null } &&
                row.persistedGrades.none { it.columnId == col.id && it.value != null }
            }
        }
    }

    fun countApproved(sheet: NotebookSheet, threshold: Double = 5.0): Int {
        return sheet.rows.count { row ->
            val values = sheet.columns.filter {
                (it.type == NotebookColumnType.NUMERIC || it.type == NotebookColumnType.RUBRIC) && it.countsTowardAverage
            }.mapNotNull { col ->
                row.cells.find { it.evaluationId == col.evaluationId }?.value
                ?: row.persistedGrades.find { it.columnId == col.id }?.value
            }
            val avg = if (values.isNotEmpty()) values.average() else null
            (avg ?: 0.0) >= threshold
        }
    }

    // --- New Methods for iOS Column Management ---

    fun addColumn(
        name: String,
        type: String,
        weight: Double,
        formula: String? = null,
        rubricId: Long? = null,
        categoryId: String? = null,
        categoryKind: NotebookColumnCategoryKind = NotebookColumnCategoryKind.CUSTOM,
        instrumentKind: NotebookInstrumentKind = NotebookInstrumentKind.CUSTOM,
        inputKind: NotebookCellInputKind = NotebookCellInputKind.TEXT,
        dateEpochMs: Long? = null,
        unitOrSituation: String? = null,
        competencyCriteriaIds: List<Long> = emptyList(),
        scaleKind: NotebookScaleKind = NotebookScaleKind.CUSTOM,
        iconName: String? = null,
        countsTowardAverage: Boolean = true,
        isPinned: Boolean = false,
        isHidden: Boolean = false,
        visibility: NotebookColumnVisibility = NotebookColumnVisibility.VISIBLE,
        isLocked: Boolean = false,
        isTemplate: Boolean = false
    ) {
        val classId = activeClassId ?: return
        scope.launch {
            try {
                val columnType = try {
                    NotebookColumnType.valueOf(type.uppercase())
                } catch (e: Exception) {
                    NotebookColumnType.NUMERIC
                }

                if (columnType == NotebookColumnType.RUBRIC && rubricId == null) {
                    return@launch
                }

                val currentState = _state.value as? NotebookUiState.Data
                val tabs = currentState?.sheet?.tabs.orEmpty()
                val resolvedTabIds = resolveTabIdsForColumn(tabs, _selectedTabId.value)

                val needsEvaluation = columnType == NotebookColumnType.NUMERIC || columnType == NotebookColumnType.RUBRIC
                val evaluationId = if (needsEvaluation) {
                    evaluationsRepository.saveEvaluation(
                        classId = classId,
                        code = "COL_${Clock.System.now().toEpochMilliseconds()}",
                        name = name,
                        type = if (columnType == NotebookColumnType.RUBRIC) "Rúbrica" else "Evaluación",
                        weight = weight,
                        formula = null,
                        rubricId = rubricId
                    )
                } else {
                    null
                }

                val columnId = if (evaluationId != null) {
                    "eval_$evaluationId"
                } else {
                    "COL_${Clock.System.now().toEpochMilliseconds()}"
                }

                // 2. Create and save column definition
                val columnDef = NotebookColumnDefinition(
                    id = columnId,
                    title = name,
                    type = columnType,
                    categoryKind = categoryKind,
                    instrumentKind = instrumentKind,
                    inputKind = inputKind,
                    evaluationId = evaluationId,
                    rubricId = rubricId,
                    weight = weight,
                    formula = if (columnType == NotebookColumnType.CALCULATED) formula else null,
                    dateEpochMs = dateEpochMs,
                    unitOrSituation = unitOrSituation,
                    competencyCriteriaIds = competencyCriteriaIds,
                    scaleKind = scaleKind,
                    tabIds = resolvedTabIds,
                    sharedAcrossTabs = resolvedTabIds.isNotEmpty() && resolvedTabIds.size == tabs.size,
                    iconName = iconName,
                    order = -1,
                    widthDp = 132.0,
                    categoryId = categoryId,
                    countsTowardAverage = countsTowardAverage,
                    isPinned = isPinned,
                    isHidden = isHidden,
                    visibility = visibility,
                    isLocked = isLocked,
                    isTemplate = isTemplate
                )
                notebookRepository.saveColumn(classId, columnDef)
                selectClass(classId, force = true)
            } catch (e: Exception) {
                println("Error adding column: ${e.message}")
            }
        }
    }

    fun saveCellAnnotation(
        studentId: Long,
        columnId: String,
        note: String?,
        iconValue: String? = null,
        attachmentUris: List<String> = emptyList(),
    ) {
        val classId = activeClassId ?: return
        scope.launch {
            try {
                notebookRepository.saveCell(
                    classId = classId,
                    studentId = studentId,
                    columnId = columnId,
                    note = note,
                    iconValue = iconValue,
                    attachmentUris = attachmentUris
                )
                selectClass(classId, force = true)
            } catch (e: Exception) {
                println("Error saving notebook cell annotation: ${e.message}")
            }
        }
    }

    fun saveColumnCategory(name: String, categoryId: String? = null) {
        val classId = activeClassId ?: return
        val currentState = _state.value as? NotebookUiState.Data ?: return
        val tabId = _selectedTabId.value ?: currentState.sheet.tabs.firstOrNull()?.id ?: return
        scope.launch {
            val existing = currentState.sheet.columnCategories.firstOrNull { it.id == categoryId }
            val nextOrder = currentState.sheet.columnCategories
                .filter { it.tabId == tabId }
                .maxOfOrNull { it.order }?.plus(1) ?: 0
            val resolvedId = existing?.id ?: "cat_${Clock.System.now().toEpochMilliseconds()}"
            val baseName = name.trim().ifBlank { existing?.name ?: "Categoría ${nextOrder + 1}" }
            val resolvedName = resolveUniqueCategoryName(
                proposed = baseName,
                currentState = currentState,
                tabId = tabId,
                editingCategoryId = existing?.id
            )
            notebookRepository.saveColumnCategory(
                classId = classId,
                category = NotebookColumnCategory(
                    id = resolvedId,
                    classId = classId,
                    tabId = tabId,
                    name = resolvedName,
                    order = existing?.order ?: nextOrder,
                    isCollapsed = existing?.isCollapsed ?: false,
                    trace = existing?.trace ?: AuditTrace()
                )
            )
            selectClass(classId, force = true)
        }
    }

    fun deleteColumnCategory(categoryId: String, preserveColumns: Boolean = true) {
        val classId = activeClassId ?: return
        scope.launch {
            notebookRepository.deleteColumnCategory(classId, categoryId, preserveColumns)
            selectClass(classId, force = true)
        }
    }

    fun toggleColumnCategoryCollapsed(categoryId: String, isCollapsed: Boolean) {
        val classId = activeClassId ?: return
        scope.launch {
            notebookRepository.toggleCategoryCollapsed(classId, categoryId, isCollapsed)
            selectClass(classId, force = true)
        }
    }

    fun reorderColumnCategory(categoryId: String, targetCategoryId: String) {
        val classId = activeClassId ?: return
        val currentState = _state.value as? NotebookUiState.Data ?: return
        val tabId = _selectedTabId.value ?: currentState.sheet.tabs.firstOrNull()?.id ?: return
        scope.launch {
            notebookRepository.reorderCategory(classId, tabId, categoryId, targetCategoryId)
            selectClass(classId, force = true)
        }
    }

    fun assignColumnToCategory(columnId: String, categoryId: String?) {
        val classId = activeClassId ?: return
        val currentState = _state.value as? NotebookUiState.Data ?: return
        val tabs = currentState.sheet.tabs
        val activeTabId = _selectedTabId.value?.takeIf { selected ->
            tabs.any { it.id == selected }
        } ?: tabs.firstOrNull()?.id
        val currentColumns = currentState.sheet.columns
            .sortedWith(compareBy<NotebookColumnDefinition> { it.order }.thenBy { it.id })
            .toMutableList()

        val fromIndex = currentColumns.indexOfFirst { it.id == columnId }
        if (fromIndex < 0) return

        val moved = currentColumns.removeAt(fromIndex).copy(categoryId = categoryId)
        val destinationIndex = when {
            categoryId == null -> fromIndex.coerceIn(0, currentColumns.size)
            else -> {
                val lastSameCategoryIndex = currentColumns.indexOfLast { candidate ->
                    candidate.categoryId == categoryId &&
                        columnIsVisibleInTab(candidate, activeTabId)
                }
                if (lastSameCategoryIndex >= 0) lastSameCategoryIndex + 1 else fromIndex.coerceIn(0, currentColumns.size)
            }
        }.coerceIn(0, currentColumns.size)

        currentColumns.add(destinationIndex, moved)
        val reorderedColumns = currentColumns.mapIndexed { index, column ->
            column.copy(order = index)
        }

        updateDataState { state ->
            state.copy(sheet = state.sheet.copy(columns = reorderedColumns))
        }

        scope.launch {
            try {
                reorderedColumns.forEach { col ->
                    notebookRepository.saveColumn(classId, col)
                }
                selectClass(classId, force = true)
            } catch (e: Exception) {
                selectClass(classId, force = true)
            }
        }
    }

    @ObjCName("deleteColumnByEvaluationId")
    fun deleteColumn(columnId: Long) {
        scope.launch {
            try {
                // Delete evaluation and the associated column definition
                // We use the evaluationId because that's what's passed from the manual's UI logic
                notebookRepository.deleteEvaluation(columnId)
                
                // Also find and delete the column definition if its id is based on this evalId
                val columnIdStr = "eval_$columnId"
                notebookRepository.deleteColumn(columnIdStr)

                loadNotebookSnapshot()
            } catch (e: Exception) {
                println("Error deleting column: ${e.message}")
            }
        }
    }

    fun updateColumnWeight(columnId: Long, newWeight: Double) {
        val classId = activeClassId ?: return
        scope.launch {
            try {
                val existingEval = evaluationsRepository.getEvaluation(columnId) ?: return@launch
                
                // Update weight in evaluation
                evaluationsRepository.saveEvaluation(
                    id = existingEval.id,
                    classId = existingEval.classId,
                    code = existingEval.code,
                    name = existingEval.name,
                    type = existingEval.type,
                    weight = newWeight,
                    formula = existingEval.formula,
                    rubricId = existingEval.rubricId,
                    description = existingEval.description
                )

                // Update weight in column definition (find by evaluationId)
                val currentState = _state.value
                if (currentState is NotebookUiState.Data) {
                    val columnDef = currentState.sheet.columns.find { it.evaluationId == columnId }
                    if (columnDef != null) {
                        notebookRepository.saveColumn(classId, columnDef.copy(weight = newWeight))
                    }
                }

                loadNotebookSnapshot()
            } catch (e: Exception) {
                println("Error updating column weight: ${e.message}")
            }
        }
    }

    private fun resolveUniqueCategoryName(
        proposed: String,
        currentState: NotebookUiState.Data,
        tabId: String,
        editingCategoryId: String?
    ): String {
        val normalized = proposed.trim()
        if (normalized.isEmpty()) return proposed
        val siblingNames = currentState.sheet.columnCategories
            .filter { it.tabId == tabId && it.id != editingCategoryId }
            .map { it.name.trim().lowercase() }
            .toSet()
        if (normalized.lowercase() !in siblingNames) return normalized

        var suffix = 2
        while (true) {
            val candidate = "$normalized $suffix"
            if (candidate.lowercase() !in siblingNames) return candidate
            suffix += 1
        }
    }

    private fun loadNotebookSnapshot() {
        activeClassId?.let { selectClass(it, force = true) }
    }

    private fun resolveSelectedTabId(tabs: List<NotebookTab>): String? {
        val selectedTabId = _selectedTabId.value?.takeIf { tabId ->
            tabs.any { it.id == tabId }
        }
        if (selectedTabId != null) return selectedTabId

        val rootTabs = tabs.filter { it.parentTabId == null }.sortedWith(compareBy<NotebookTab> { it.order }.thenBy { it.id })
        val firstRoot = rootTabs.firstOrNull()
        val firstChild = firstRoot?.let { root -> tabs.firstOrNull { it.parentTabId == root.id } }
        return firstChild?.id ?: firstRoot?.id ?: tabs.firstOrNull()?.id
    }

    fun saveWorkGroup(name: String, groupId: Long? = null, studentIds: List<Long> = emptyList()) {
        val classId = activeClassId ?: return
        val currentState = _state.value as? NotebookUiState.Data ?: return
        val tabId = _selectedTabId.value ?: currentState.sheet.tabs.firstOrNull()?.id ?: return
        scope.launch {
            val existing = currentState.sheet.workGroups.firstOrNull { it.id == groupId }
            val nextOrder = currentState.sheet.workGroups.filter { it.tabId == tabId }.maxOfOrNull { it.order }?.plus(1) ?: 0
            val baseName = name.trim().ifBlank { existing?.name ?: "Grupo ${nextOrder + 1}" }
            val uniqueName = buildUniqueWorkGroupName(
                baseName = baseName,
                tabId = tabId,
                workGroups = currentState.sheet.workGroups,
                excludedGroupId = groupId,
            )
            val savedId = notebookRepository.saveWorkGroup(
                classId = classId,
                workGroup = NotebookWorkGroup(
                    id = existing?.id ?: groupId ?: 0L,
                    classId = classId,
                    tabId = tabId,
                    name = uniqueName,
                    order = existing?.order ?: nextOrder,
                    trace = existing?.trace ?: AuditTrace()
                )
            )
            if (studentIds.isNotEmpty()) {
                notebookRepository.assignStudentsToWorkGroup(classId, tabId, savedId, studentIds)
            }
            selectClass(classId, force = true)
        }
    }

    fun renameWorkGroup(groupId: Long, name: String) {
        saveWorkGroup(name = name, groupId = groupId)
    }

    fun assignStudentToWorkGroup(groupName: String?, studentId: Long) {
        val currentState = _state.value as? NotebookUiState.Data ?: return
        val tabId = _selectedTabId.value ?: currentState.sheet.tabs.firstOrNull()?.id ?: return
        val groupId = groupName?.let { name ->
            currentState.sheet.workGroups.firstOrNull { it.tabId == tabId && it.name == name }?.id
        }
        assignStudentsToWorkGroup(groupId = groupId, studentIds = listOf(studentId))
    }

    fun deleteWorkGroup(groupId: Long) {
        val classId = activeClassId ?: return
        scope.launch {
            notebookRepository.deleteWorkGroup(groupId)
            selectClass(classId, force = true)
        }
    }

    private fun buildUniqueWorkGroupName(
        baseName: String,
        tabId: String,
        workGroups: List<NotebookWorkGroup>,
        excludedGroupId: Long? = null,
    ): String {
        val existingNames = workGroups
            .asSequence()
            .filter { it.tabId == tabId && it.id != excludedGroupId }
            .map { it.name.trim().lowercase() }
            .toSet()

        var candidate = baseName.trim()
        var suffix = 2
        while (candidate.lowercase() in existingNames) {
            candidate = "$baseName ($suffix)"
            suffix++
        }
        return candidate
    }

    fun assignStudentsToWorkGroup(groupId: Long?, studentIds: List<Long>) {
        val classId = activeClassId ?: return
        val currentState = _state.value as? NotebookUiState.Data ?: return
        val tabId = _selectedTabId.value ?: currentState.sheet.tabs.firstOrNull()?.id ?: return
        scope.launch {
            if (groupId == null) {
                notebookRepository.clearStudentsFromWorkGroup(classId, tabId, studentIds)
            } else {
                notebookRepository.assignStudentsToWorkGroup(classId, tabId, groupId, studentIds)
            }
            selectClass(classId, force = true)
        }
    }

    private fun resolveTabIdsForColumn(
        tabs: List<NotebookTab>,
        selectedTabId: String?,
    ): List<String> {
        val validSelectedTabId = selectedTabId?.takeIf { tabId ->
            tabs.any { it.id == tabId }
        }

        return when {
            validSelectedTabId != null -> listOf(validSelectedTabId)
            tabs.isNotEmpty() -> tabs.map { it.id }
            else -> emptyList()
        }
    }

    private fun normalizeColumnPlacement(
        column: NotebookColumnDefinition,
        tabs: List<NotebookTab>,
        selectedTabId: String?,
    ): NotebookColumnDefinition {
        val resolvedTabIds = when {
            column.tabIds.isNotEmpty() && tabs.isNotEmpty() -> {
                column.tabIds.filter { tabId -> tabs.any { it.id == tabId } }
                    .ifEmpty { resolveTabIdsForColumn(tabs, selectedTabId) }
            }
            column.tabIds.isNotEmpty() -> column.tabIds
            else -> resolveTabIdsForColumn(tabs, selectedTabId)
        }

        val resolvedOrder = when {
            column.order >= 0 -> column.order
            tabs.isNotEmpty() -> _state.value.let { state ->
                val currentColumns = (state as? NotebookUiState.Data)?.sheet?.columns.orEmpty()
                currentColumns.maxOfOrNull { it.order }?.plus(1) ?: 0
            }
            else -> 0
        }
        val resolvedWidth = if (column.widthDp > 0.0) column.widthDp else 132.0

        return column.copy(
            tabIds = resolvedTabIds,
            sharedAcrossTabs = resolvedTabIds.isNotEmpty() && resolvedTabIds.size == tabs.size
                && tabs.isNotEmpty(),
            order = resolvedOrder,
            widthDp = resolvedWidth
        )
    }

    private fun collectTabAndDescendantIds(tabs: List<NotebookTab>, tabId: String): Set<String> {
        val childrenByParent = tabs.groupBy { it.parentTabId }
        val collected = mutableSetOf<String>()

        fun visit(currentId: String) {
            if (!collected.add(currentId)) return
            childrenByParent[currentId].orEmpty().forEach { visit(it.id) }
        }

        visit(tabId)
        return collected
    }

    private fun recalculateCalculatedDraftsForStudent(studentId: Long) {
        val currentState = _state.value as? NotebookUiState.Data ?: return
        val recalculated = _numericDrafts.value.toMutableMap()
        applyCalculatedDraftsForStudent(
            studentId = studentId,
            snapshot = currentState.sheet,
            evaluations = cachedEvaluations,
            numericDrafts = recalculated
        )
        _numericDrafts.value = recalculated
    }

    private fun applyCalculatedDrafts(
        snapshot: NotebookSheet,
        evaluations: List<Evaluation>,
        numericDrafts: MutableMap<Pair<Long, String>, String>,
    ) {
        snapshot.rows.forEach { row ->
            applyCalculatedDraftsForStudent(
                studentId = row.student.id,
                snapshot = snapshot,
                evaluations = evaluations,
                numericDrafts = numericDrafts
            )
        }
    }

    private fun applyCalculatedDraftsForStudent(
        studentId: Long,
        snapshot: NotebookSheet,
        evaluations: List<Evaluation>,
        numericDrafts: MutableMap<Pair<Long, String>, String>,
    ) {
        val row = snapshot.rows.firstOrNull { it.student.id == studentId } ?: return
        val calculatedColumns = snapshot.columns.filter {
            it.type == NotebookColumnType.CALCULATED && !it.formula.isNullOrBlank()
        }
        if (calculatedColumns.isEmpty()) return

        val varsByCode = mutableMapOf<String, Double>()
        evaluations.forEach { evaluation ->
            val value = resolveEvaluationValue(row, evaluation.id, numericDrafts) ?: 0.0
            varsByCode[evaluation.code] = value
        }

        val varsByColumnId = snapshot.columns.associate { column ->
            column.id to (resolveColumnNumericValue(row, column, numericDrafts) ?: 0.0)
        }
        val vars = varsByCode + varsByColumnId

        calculatedColumns.forEach { column ->
            val formula = column.formula ?: return@forEach
            val result = runCatching { formulaEvaluator.evaluate(formula, vars) }.getOrNull() ?: return@forEach
            numericDrafts[studentId to column.id] = result.toString()
        }
    }

    private fun resolveEvaluationValue(
        row: NotebookRow,
        evaluationId: Long,
        numericDrafts: Map<Pair<Long, String>, String>,
    ): Double? {
        val studentId = row.student.id
        val generatedColumnId = "eval_$evaluationId"
        return parseDraftNumber(numericDrafts[studentId to generatedColumnId])
            ?: row.cells.firstOrNull { it.evaluationId == evaluationId }?.value
            ?: row.persistedGrades.firstOrNull { it.evaluationId == evaluationId }?.value
            ?: row.persistedGrades.firstOrNull { it.columnId == generatedColumnId }?.value
    }

    private fun resolveColumnNumericValue(
        row: NotebookRow,
        column: NotebookColumnDefinition,
        numericDrafts: Map<Pair<Long, String>, String>,
    ): Double? {
        val studentId = row.student.id
        return parseDraftNumber(numericDrafts[studentId to column.id])
            ?: column.evaluationId?.let { evalId ->
                parseDraftNumber(numericDrafts[studentId to "eval_$evalId"])
                    ?: row.cells.firstOrNull { it.evaluationId == evalId }?.value
                    ?: row.persistedGrades.firstOrNull { it.columnId == column.id }?.value
                    ?: row.persistedGrades.firstOrNull { it.evaluationId == evalId }?.value
            }
            ?: row.persistedGrades.firstOrNull { it.columnId == column.id }?.value
    }

    private fun parseDraftNumber(raw: String?): Double? {
        return raw?.replace(",", ".")?.toDoubleOrNull()
    }

    private fun columnIsVisibleInTab(column: NotebookColumnDefinition, tabId: String?): Boolean {
        if (tabId.isNullOrBlank()) return false
        return column.tabIds.contains(tabId) || (column.sharedAcrossTabs && column.tabIds.isEmpty())
    }

    private fun visibleRowsFor(state: NotebookUiState.Data): List<NotebookRow> {
        return state.sheet.groupedRowsFor(_selectedTabId.value)
            .flatMap { it.rows }
    }
}

data class ActiveCellEditor(
    val studentIndex: Int,
    val student: com.migestor.shared.domain.Student,
    val column: NotebookColumnDefinition,
    val currentValue: String
)

data class RubricEvaluationTarget(
    val studentId: Long,
    val columnId: String,
    val rubricId: Long,
    val evaluationId: Long
)

data class ActiveCell(
    val studentIndex: Int,
    val columnId: String
)

sealed interface NotebookUiState {
    data object Loading : NotebookUiState
    data class Data(
        val sheet: NotebookSheet,
        val selectedColumnIds: Set<String> = emptySet(),
        val isColumnSelectionMode: Boolean = false,
        val rubricEvaluationTarget: RubricEvaluationTarget? = null,
        val activeCellEditor: ActiveCellEditor? = null,
        val activeCell: ActiveCell? = null,
        val numericDrafts: Map<Pair<Long, String>, String> = emptyMap(),
        val textDrafts: Map<Pair<Long, String>, String> = emptyMap(),
        val checkDrafts: Map<Pair<Long, String>, Boolean> = emptyMap(),
        val workGroups: List<NotebookWorkGroup> = emptyList(),
        val workGroupMembers: List<NotebookWorkGroupMember> = emptyList(),
    ) : NotebookUiState
    data class Error(val message: String) : NotebookUiState
}
