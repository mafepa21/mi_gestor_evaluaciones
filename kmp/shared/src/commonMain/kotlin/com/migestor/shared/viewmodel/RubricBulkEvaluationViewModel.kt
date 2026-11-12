package com.migestor.shared.viewmodel

import com.migestor.shared.domain.*
import com.migestor.shared.repository.*
import com.migestor.shared.util.NotebookRefreshBus
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

data class BulkStudentGroup(
    val group: NotebookWorkGroup? = null,
    val students: List<Student>,
    val isUngrouped: Boolean = false
)

data class BulkRubricEvaluationUiState(
    val classId: Long = 0,
    val evaluationId: Long = 0,
    val tabId: String? = null,
    val columnId: String? = null,
    val rubricDetail: RubricDetail? = null,
    val students: List<Student> = emptyList(),
    val injuredStudents: List<Student> = emptyList(),
    val groupedStudents: List<BulkStudentGroup> = emptyList(),
    // StudentId -> (CriterionId -> LevelId)
    val assessments: Map<Long, Map<Long, Long>> = emptyMap(),
    // StudentId -> Score (0.0 - 10.0)
    val scores: Map<Long, Double> = emptyMap(),
    val passingThreshold: Double = 5.0,
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val isSaveSuccessful: Boolean = false,
    val error: String? = null,
    val copiedAssessment: Map<Long, Long>? = null // Buffer for Copy/Paste
)

class RubricBulkEvaluationViewModel(
    private val rubricsRepository: RubricsRepository,
    private val studentsRepository: StudentsRepository,
    private val notebookRepository: NotebookRepository,
    private val gradesRepository: GradesRepository,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
) {
    private val _uiState = MutableStateFlow(BulkRubricEvaluationUiState())
    val uiState: StateFlow<BulkRubricEvaluationUiState> = _uiState.asStateFlow()

    init {
        scope.launch {
            RubricEvaluationBus.events.collect { event ->
                val current = _uiState.value
                val rubricId = current.rubricDetail?.rubric?.id ?: return@collect

                // event.rubricId no basta: una misma rubrica puede estar vinculada a mas
                // de una evaluacion/columna del cuaderno a la vez. Sin comparar tambien el
                // columnId, un guardado individual en OTRA evaluacion que comparte esta
                // rubrica se mezclaba en el estado de esta hoja masiva, y el siguiente
                // auto-save volcaba esa mezcla en la columna equivocada.
                if (event.rubricId == rubricId && event.columnId == current.columnId) {
                    val updatedAssessments = current.assessments.toMutableMap()
                    val studentAssessments = updatedAssessments[event.studentId]?.toMutableMap() ?: mutableMapOf()
                    
                    // Solo actualizar si es un cambio que no tenemos o si queremos forzar sync
                    studentAssessments.putAll(event.selectedLevels)
                    updatedAssessments[event.studentId] = studentAssessments
                    
                    val updatedScores = current.scores + (event.studentId to event.score)
                    
                    _uiState.update { it.copy(assessments = updatedAssessments, scores = updatedScores) }
                }
            }
        }
    }

    private var autoSaveJobs = mutableMapOf<Long, Job>()
    private val AUTO_SAVE_DELAY_MS = 400L

    // El guardado automático por alumno ya no recarga el Cuaderno entero cada
    // vez (con 25 alumnos eran ~25 recargas completas mientras se evaluaba):
    // se anota y se recarga una sola vez al cerrar la hoja.
    private var hasPendingNotebookRefresh = false
    private var isSheetClosed = false

    fun load(classId: Long, evaluationId: Long, rubricId: Long, columnId: String?, tabId: String? = null) {
        isSheetClosed = false
        _uiState.update { it.copy(isLoading = true, error = null, classId = classId, evaluationId = evaluationId, columnId = columnId, tabId = tabId) }
        
        scope.launch {
            try {
                // 1. Load Students in Class
                val classStudents = notebookRepository.listStudentsInClass(classId)
                val injured = classStudents.filter { it.isInjured }

                // 2. Detalle de la rúbrica: consulta directa, no todas las rúbricas.
                val rubricDetail = rubricsRepository.getRubricDetail(rubricId) ?: throw Exception("Rubric not found")

                // 3. Valoraciones existentes de todo el grupo, por lote (número fijo de lecturas).
                val (initialAssessments, initialScores) = loadInitialAssessments(
                    classId = classId,
                    students = classStudents,
                    rubricDetail = rubricDetail,
                    evaluationId = evaluationId,
                    columnId = columnId
                )

                // 4. Load Groups and Members if tabId is provided
                val workGroups = notebookRepository.listWorkGroups(classId, tabId)
                val members = notebookRepository.listWorkGroupMembers(classId, tabId)
                
                val groupedStudents = groupStudents(classStudents, workGroups, members)

                _uiState.update { state ->
                    state.copy(
                        rubricDetail = rubricDetail,
                        students = classStudents,
                        injuredStudents = injured,
                        groupedStudents = groupedStudents,
                        assessments = initialAssessments,
                        scores = initialScores,
                        isLoading = false
                    )
                }
            } catch (e: Exception) {
                _uiState.update { it.copy(isLoading = false, error = e.message) }
            }
        }
    }

    /**
     * Carga los niveles ya puestos de todos los alumnos con lecturas por lote.
     *
     * Conserva la prioridad de antes: si hay `columnId` y la nota de esa celda trae
     * `rubricSelections`, mandan esas selecciones; si no, las valoraciones de la
     * evaluación (lo que devolvía `getStudentEvaluation`).
     *
     * Equivalencias con las llamadas por alumno:
     * - `getStudentEvaluation` = valoraciones de la evaluación cuyos criterios son de esta
     *   rúbrica (une con `rubric_criteria` por `rubric_id`). Aquí: `listRubricAssessmentsForStudents`
     *   filtrado por los criterios de `rubricDetail` (salen de la misma tabla y el mismo filtro).
     *   La clave primaria (alumno, evaluación, criterio) impide duplicados.
     * - `getGradeForColumn` con columna guardada en este grupo: busca entre las notas del alumno
     *   en el grupo de la columna la primera con la evaluación de la columna y, si no hay, la de
     *   ese `columnId`. Aquí se hace igual sobre `listGradesForClass`. Si hay más de una nota
     *   candidata, "la primera" depende del orden de SQLite: para ese alumno se repite la
     *   llamada individual. Si la columna no está guardada en este grupo (columna virtual
     *   `eval_<id>` u otro grupo), no se conoce el grupo de la evaluación: se mantiene la
     *   llamada individual por alumno.
     */
    private suspend fun loadInitialAssessments(
        classId: Long,
        students: List<Student>,
        rubricDetail: RubricDetail,
        evaluationId: Long,
        columnId: String?
    ): Pair<Map<Long, Map<Long, Long>>, Map<Long, Double>> {
        val rubricId = rubricDetail.rubric.id
        val rubricCriterionIds = rubricDetail.criteria.map { it.criterion.id }.toSet()
        val studentIds = students.map { it.id }

        val evaluationAssessmentsByStudent: Map<Long, Map<Long, Long>> = if (studentIds.isEmpty()) {
            emptyMap()
        } else {
            rubricsRepository.listRubricAssessmentsForStudents(studentIds, evaluationId)
                .filter { it.evaluationId == evaluationId && it.criterionId in rubricCriterionIds }
                .groupBy { it.studentId }
                .mapValues { (_, rows) -> rows.associate { it.criterionId to it.levelId } }
        }

        val cellGradeResolver: (suspend (Long) -> Grade?)? = if (columnId != null && studentIds.isNotEmpty()) {
            resolveCellGrades(classId, columnId)
        } else {
            null
        }

        val assessments = mutableMapOf<Long, Map<Long, Long>>()
        val scores = mutableMapOf<Long, Double>()
        for (student in students) {
            val rubricSelections = cellGradeResolver?.invoke(student.id)?.rubricSelections
            val studentAssessments = if (!rubricSelections.isNullOrBlank()) {
                parseRubricSelections(rubricSelections)
            } else {
                evaluationAssessmentsByStudent[student.id].orEmpty()
            }
            if (studentAssessments.isNotEmpty()) {
                assessments[student.id] = studentAssessments
                scores[student.id] = calculateScoreForAssessment(rubricDetail, studentAssessments)
            }
        }
        return assessments to scores
    }

    /**
     * Devuelve cómo obtener la nota de la celda de cada alumno, igual que
     * `notebookRepository.getGradeForColumn(studentId, columnId)`.
     */
    private suspend fun resolveCellGrades(classId: Long, columnId: String): suspend (Long) -> Grade? {
        val column = notebookRepository.getNotebookConfig(classId).columns.firstOrNull { it.id == columnId }
            // Columna no guardada en este grupo: vía individual (ver loadInitialAssessments).
            ?: return { studentId -> notebookRepository.getGradeForColumn(studentId, columnId) }

        val gradesByStudent = gradesRepository.listGradesForClass(classId)
            .filter { it.classId == classId }
            .groupBy { it.studentId }
        val columnEvaluationId = column.evaluationId

        return { studentId ->
            val studentGrades = gradesByStudent[studentId].orEmpty()
            val byEvaluation = columnEvaluationId?.let { evalId -> studentGrades.filter { it.evaluationId == evalId } }.orEmpty()
            val byColumn = studentGrades.filter { it.columnId == columnId }
            when {
                byEvaluation.size == 1 -> byEvaluation.first()
                byEvaluation.size > 1 -> notebookRepository.getGradeForColumn(studentId, columnId)
                byColumn.size <= 1 -> byColumn.firstOrNull()
                else -> notebookRepository.getGradeForColumn(studentId, columnId)
            }
        }
    }

    fun selectLevel(studentId: Long, criterionId: Long, levelId: Long) {
        _uiState.update { state ->
            val studentAssessments = state.assessments[studentId]?.toMutableMap() ?: mutableMapOf()
            studentAssessments[criterionId] = levelId
            
            val newAssessments = state.assessments + (studentId to studentAssessments)
            val newScore = calculateScoreForAssessment(state.rubricDetail, studentAssessments)
            val newScores = state.scores + (studentId to newScore)
            
            state.copy(assessments = newAssessments, scores = newScores, isSaveSuccessful = false)
        }
        triggerAutoSave(studentId)
    }

    fun copyAssessment(studentId: Long) {
        val assessment = _uiState.value.assessments[studentId]
        _uiState.update { it.copy(copiedAssessment = assessment) }
    }

    fun pasteAssessment(studentId: Long) {
        val copied = _uiState.value.copiedAssessment ?: return
        _uiState.update { state ->
            val newAssessments = state.assessments + (studentId to copied)
            val newScore = calculateScoreForAssessment(state.rubricDetail, copied)
            val newScores = state.scores + (studentId to newScore)
            state.copy(assessments = newAssessments, scores = newScores, isSaveSuccessful = false)
        }
        triggerAutoSave(studentId)
    }

    fun toggleInjuredStatus(studentId: Long) {
        scope.launch {
            try {
                val currentStudents = _uiState.value.students
                val student = currentStudents.find { it.id == studentId } ?: return@launch
                val newStatus = !student.isInjured
                
                // 1. Update DB
                studentsRepository.saveStudent(
                    id = student.id,
                    firstName = student.firstName,
                    lastName = student.lastName,
                    email = student.email,
                    photoPath = student.photoPath,
                    isInjured = newStatus,
                    updatedAtEpochMs = student.trace.updatedAt.toEpochMilliseconds(),
                    deviceId = student.trace.deviceId,
                    syncVersion = student.trace.syncVersion
                )

                // 2. Update Local State
                val updatedStudents = currentStudents.map {
                    if (it.id == studentId) it.copy(isInjured = newStatus) else it
                }
                val injured = updatedStudents.filter { it.isInjured }

                _uiState.update { state ->
                    state.copy(
                        students = updatedStudents,
                        injuredStudents = injured
                    )
                }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = "Error updating status: ${e.message}") }
            }
        }
    }

    private fun triggerAutoSave(studentId: Long) {
        autoSaveJobs[studentId]?.cancel()
        autoSaveJobs[studentId] = scope.launch {
            delay(AUTO_SAVE_DELAY_MS)
            // Si la hoja ya se cerró, este guardado rezagado avisa él mismo.
            val refreshNow = isSheetClosed
            if (saveStudentEvaluation(studentId, emitRefresh = refreshNow) && !refreshNow) {
                hasPendingNotebookRefresh = true
            }
        }
    }

    /**
     * Llamar al cerrar la hoja: recarga el Cuaderno una vez si hubo guardados automáticos.
     *
     * Con `emitNotebookRefresh = false` no avisa: lo usa quien ya pausó la recarga reactiva
     * del Cuaderno (`NotebookViewModel.setReactiveReloadPaused`) y la reanuda al cerrar, que
     * hace ella sola la única recarga. Avisar aquí además provocaría una segunda.
     */
    fun onSheetClosed(emitNotebookRefresh: Boolean = true) {
        isSheetClosed = true
        if (hasPendingNotebookRefresh) {
            hasPendingNotebookRefresh = false
            if (emitNotebookRefresh) NotebookRefreshBus.emitRefresh()
        }
    }

    fun saveAll() {
        scope.launch {
            _uiState.update { it.copy(isSaving = true, isSaveSuccessful = false, error = null) }
            try {
                val state = _uiState.value
                autoSaveJobs.values.forEach { it.cancel() }
                autoSaveJobs.clear()
                // saveStudentEvaluation traga sus propias excepciones (para que el
                // auto-save de un alumno no tumbe la sesion de evaluacion masiva
                // de otro), asi que "Guardar todo" no puede fiarse de que una
                // excepcion aqui signifique fallo: debe comprobar el resultado de
                // cada alumno explicitamente, o marcaria exito y la hoja se
                // autocerraria (RubricBulkEvaluationSheet observa isSaveSuccessful)
                // aunque se hubiera perdido la evaluacion de algun alumno.
                val failedStudentIds = state.assessments.keys.filterNot { studentId ->
                    saveStudentEvaluation(studentId, emitRefresh = false)
                }
                if (failedStudentIds.isEmpty()) {
                    _uiState.update { it.copy(isSaving = false, isSaveSuccessful = true) }
                    hasPendingNotebookRefresh = false
                    NotebookRefreshBus.emitRefresh()
                    delay(350)
                    _uiState.update { it.copy(isSaveSuccessful = false) }
                } else {
                    _uiState.update {
                        it.copy(
                            isSaving = false,
                            isSaveSuccessful = false,
                            error = "No se pudieron guardar ${failedStudentIds.size} evaluación(es). Revisa la conexión e inténtalo de nuevo."
                        )
                    }
                }
            } catch (e: Exception) {
                _uiState.update { it.copy(isSaving = false, isSaveSuccessful = false, error = "Error al guardar todo: ${e.message}") }
            }
        }
    }

    /** @return `true` si se guardó (o no había nada que guardar), `false` si falló. */
    private suspend fun saveStudentEvaluation(studentId: Long, emitRefresh: Boolean = true): Boolean {
        val state = _uiState.value
        val studentAssessments = state.assessments[studentId] ?: return true
        val score = state.scores[studentId] ?: 0.0
        val selectionsString = studentAssessments.entries.joinToString(",") { "${it.key}:${it.value}" }

        return try {
            val effectiveColumnId = state.columnId?.takeIf { it.isNotBlank() }
                ?: notebookRepository.getColumnIdForEvaluation(state.evaluationId)
                ?: "eval_${state.evaluationId}"

            // 1. Notebook & Main Grade (NotebookRepository handles both)
            notebookRepository.upsertGrade(
                classId = state.classId,
                studentId = studentId,
                columnId = effectiveColumnId,
                evaluationId = state.evaluationId,
                numericValue = score,
                rubricSelections = selectionsString
            )

            // 2. Assessments (Individual criteria)
            for ((criterionId, levelId) in studentAssessments) {
                rubricsRepository.saveRubricAssessment(
                    studentId = studentId,
                    evaluationId = state.evaluationId,
                    criterionId = criterionId,
                    levelId = levelId
                )
            }

            // Notify notebook of changes
            if (emitRefresh) {
                NotebookRefreshBus.emitRefresh()
            }

            // NOTIFICAR AL BUS PARA SINCRONIZACIÓN REACTIVA
            RubricEvaluationBus.emit(
                RubricEvaluationSavedEvent(
                    studentId = studentId,
                    rubricId = state.rubricDetail?.rubric?.id ?: 0L,
                    selectedLevels = studentAssessments,
                    score = score,
                    columnId = effectiveColumnId
                )
            )
            true
        } catch (e: Exception) {
            _uiState.update { it.copy(error = "Auto-save error: ${e.message}") }
            false
        }
    }

    private fun groupStudents(
        students: List<Student>,
        workGroups: List<NotebookWorkGroup>,
        members: List<NotebookWorkGroupMember>
    ): List<BulkStudentGroup> {
        if (workGroups.isEmpty()) {
            return listOf(BulkStudentGroup(students = students, isUngrouped = true))
        }

        val membershipByStudentId = members.associateBy { it.studentId }
        val studentsInGroups = mutableSetOf<Long>()

        val grouped = workGroups.sortedBy { it.order }.map { group ->
            val groupStudents = students.filter { student ->
                membershipByStudentId[student.id]?.groupId == group.id
            }
            studentsInGroups += groupStudents.map { it.id }
            BulkStudentGroup(group = group, students = groupStudents)
        }

        val ungroupedStudents = students.filterNot { it.id in studentsInGroups }
        return if (ungroupedStudents.isNotEmpty()) {
            grouped + BulkStudentGroup(students = ungroupedStudents, isUngrouped = true)
        } else {
            grouped
        }
    }

    private fun calculateScoreForAssessment(rubricDetail: RubricDetail?, assessments: Map<Long, Long>): Double {
        if (rubricDetail == null) return 0.0
        val score = rubricDetail.calculateScore(assessments)
        return kotlin.math.round(score * 100) / 100.0
    }

    private fun parseRubricSelections(selectionsString: String): Map<Long, Long> {
        return try {
            selectionsString.split(",")
                .filter { it.contains(":") }
                .associate { 
                    val parts = it.split(":")
                    parts[0].toLong() to parts[1].toLong()
                }
        } catch (e: Exception) {
            emptyMap()
        }
    }
}
