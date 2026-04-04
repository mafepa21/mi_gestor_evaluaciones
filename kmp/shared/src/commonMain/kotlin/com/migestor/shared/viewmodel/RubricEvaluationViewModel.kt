package com.migestor.shared.viewmodel

import com.migestor.shared.domain.*
import com.migestor.shared.repository.*
import com.migestor.shared.util.NotebookRefreshBus
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

data class RubricEvaluationUiState(
    val studentName: String = "",
    val rubricName: String = "",
    val rubricDetail: RubricDetail? = null,
    val selectedLevels: Map<Long, Long> = emptyMap(), // CriterionId -> LevelId
    val totalScore: Double = 0.0,
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val isSaveSuccessful: Boolean = false, // Para feedback visual (check verde)
    val shouldDismissDialog: Boolean = false, // Para cerrar diálogo (solo en guardado manual)
    val error: String? = null,
    val classId: Long = 0,
    val studentId: Long = 0,
    val evaluationId: Long = 0,
    val columnId: String? = null,
    val notes: String = ""
) {
    companion object {
        fun default() = RubricEvaluationUiState()
    }
}

class RubricEvaluationViewModel(
    private val rubricsRepository: RubricsRepository,
    private val studentsRepository: StudentsRepository,
    private val evaluationsRepository: EvaluationsRepository,
    private val gradesRepository: GradesRepository,
    private val notebookRepository: NotebookRepository,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
) {
    private val _uiState = MutableStateFlow(RubricEvaluationUiState())
    val uiState: StateFlow<RubricEvaluationUiState> = _uiState.asStateFlow()

    init {
        scope.launch {
            RubricEvaluationBus.events.collect { event ->
                val current = _uiState.value
                val rubricId = current.rubricDetail?.rubric?.id ?: return@collect
                if (event.studentId == current.studentId && event.rubricId == rubricId) {
                    // Actualizar en memoria sin re-fetch de DB (fast path)
                    _uiState.update { it.copy(selectedLevels = event.selectedLevels) }
                    calculateScore()
                }
            }
        }
    }


    fun loadEvaluation(studentId: Long, evaluationId: Long, rubricId: Long) {
        _uiState.update { it.copy(isLoading = true, error = null, studentId = studentId, evaluationId = evaluationId, columnId = null) }
        scope.launch {
            try {
                val evaluation = evaluationsRepository.getEvaluation(evaluationId)
                val classId = evaluation?.classId ?: 0L
                
                val students = studentsRepository.listStudents()
                val student = students.find { it.id == studentId }
                
                val rubrics = rubricsRepository.listRubrics()
                val rubricDetail = rubrics.find { it.rubric.id == rubricId }
                
                val initialAssessments = rubricsRepository.listRubricAssessments(studentId, evaluationId)
                val initialSelectedLevels = initialAssessments.associate { it.criterionId to it.levelId }
                
                _uiState.update { state ->
                    state.copy(
                        studentName = student?.fullName ?: "Alumno",
                        rubricName = rubricDetail?.rubric?.name ?: "Rúbrica",
                        rubricDetail = rubricDetail,
                        selectedLevels = initialSelectedLevels,
                        classId = classId,
                        isLoading = false
                    )
                }
                calculateScore()
            } catch (e: Exception) {
                _uiState.update { it.copy(isLoading = false, error = e.message) }
            }
        }
    }

    fun loadForNotebookCell(studentId: Long, columnId: String, rubricId: Long, evaluationId: Long) {
        _uiState.update { it.copy(
            isLoading = true, 
            error = null,
            studentId = studentId, 
            evaluationId = evaluationId,
            columnId = columnId
        ) }
        
        scope.launch {
            try {
                val evaluation = evaluationsRepository.getEvaluation(evaluationId)
                val classId = evaluation?.classId ?: 0L

                val students = studentsRepository.listStudents()
                val student = students.find { it.id == studentId }
                
                val rubrics = rubricsRepository.listRubrics()
                val rubricDetail = rubrics.find { it.rubric.id == rubricId }
                
                // Intentar cargar evaluación previa desde Grades (sistema Cuaderno)
                val previousGrade = notebookRepository.getGradeForColumn(studentId, columnId)
                
                // Si hay rubricSelections (JSON/String), parsearlo
                val initialSelectedLevels = if (!previousGrade?.rubricSelections.isNullOrBlank()) {
                    parseRubricSelections(previousGrade!!.rubricSelections!!)
                } else {
                    // Fallback a evaluaciones clásicas si no hay en el Cuaderno
                    val initialAssessments = rubricsRepository.listRubricAssessments(studentId, evaluationId)
                    initialAssessments.associate { it.criterionId to it.levelId }
                }

                _uiState.update { state ->
                    state.copy(
                        studentName = student?.fullName ?: "Alumno",
                        rubricName = rubricDetail?.rubric?.name ?: "Rúbrica",
                        rubricDetail = rubricDetail,
                        selectedLevels = initialSelectedLevels,
                        notes = previousGrade?.evidence ?: "",
                        classId = classId,
                        isLoading = false
                    )
                }
                calculateScore()
            } catch (e: Exception) {
                _uiState.update { it.copy(isLoading = false, error = e.message) }
            }
        }
    }

    fun selectLevel(criterionId: Long, levelId: Long) {
        _uiState.update { state ->
            val newSelected = state.selectedLevels + (criterionId to levelId)
            state.copy(selectedLevels = newSelected, isSaveSuccessful = false, shouldDismissDialog = false)
        }
        try {
            calculateScore()
        } catch (e: Exception) {
            // Log error but don't crash
            _uiState.update { it.copy(error = "Error al calcular nota: ${e.message}") }
        }
    }

    fun updateNotes(notes: String) {
        _uiState.update { it.copy(notes = notes, isSaveSuccessful = false, shouldDismissDialog = false) }
    }


    internal fun calculateScore() {
        _uiState.update { state ->
            val rubricDetail = state.rubricDetail ?: return@update state
            val selectedLevels = state.selectedLevels
            
            if (selectedLevels.isEmpty()) {
                return@update state.copy(totalScore = 0.0)
            }

            val score = rubricDetail.calculateScore(selectedLevels)
            state.copy(totalScore = kotlin.math.round(score * 100) / 100.0)
        }
    }

    fun save(manual: Boolean = true, onSuccess: () -> Unit) {
        val state = _uiState.value
        if (state.isSaving) return
        
        _uiState.update { it.copy(isSaving = true, error = null) }
        
        scope.launch {
            try {
                val computedScore = state.rubricDetail
                    ?.calculateScore(state.selectedLevels)
                    ?.let { kotlin.math.round(it * 100) / 100.0 }
                    ?: state.totalScore

                // Serializar selecciones a String (formato simple id:id,id:id)
                val selectionsString = state.selectedLevels.entries.joinToString(",") { "${it.key}:${it.value}" }
                val classId = if (state.classId > 0) {
                    state.classId
                } else {
                    evaluationsRepository.getEvaluation(state.evaluationId)?.classId ?: 0L
                }
                require(classId > 0) { "No se pudo resolver la clase de la evaluación ${state.evaluationId}" }

                val explicitColumnId = state.columnId?.takeIf { it.isNotBlank() }
                val canonicalColumnId = notebookRepository.getColumnIdForEvaluation(state.evaluationId)
                    ?: "eval_${state.evaluationId}"
                val effectiveColumnId = explicitColumnId ?: canonicalColumnId

                notebookRepository.upsertGrade(
                    classId = classId,
                    studentId = state.studentId,
                    columnId = effectiveColumnId,
                    numericValue = computedScore,
                    rubricSelections = selectionsString,
                    evidence = state.notes.takeIf { it.isNotBlank() }
                )

                // 2. Guardar evaluaciones individuales (RubricAssessments) 
                state.selectedLevels.forEach { (criterionId, levelId) ->
                    rubricsRepository.saveRubricAssessment(
                        studentId = state.studentId,
                        evaluationId = state.evaluationId,
                        criterionId = criterionId,
                        levelId = levelId
                    )
                }
                
                // 3. Ya no es necesario llamar por separado a gradesRepository.saveGrade 
                // ya que notebookRepository.upsertGrade lo hace internamente.
                // Sin embargo, para mantener compatibilidad con flujos de evaluación que NO son del cuaderno,
                // nos aseguramos de que el columnId esté bien formado.

                // 4. Sincronización de UI y Notificaciones
                // No llamamos a notebookRepository.upsertGrade de nuevo si state.columnId es redundante con effectiveColumnId
                
                // NOTIFICAR REFRESH
                NotebookRefreshBus.emitRefresh()
                
                // NOTIFICAR AL BUS PARA SINCRONIZACIÓN REACTIVA
                RubricEvaluationBus.emit(
                    RubricEvaluationSavedEvent(
                        studentId = state.studentId,
                        rubricId = state.rubricDetail?.rubric?.id ?: 0L,
                        selectedLevels = state.selectedLevels,
                        score = computedScore,
                        columnId = effectiveColumnId
                    )
                )

                _uiState.update { 
                    it.copy(
                        totalScore = computedScore,
                        isSaving = false, 
                        isSaveSuccessful = true,
                        shouldDismissDialog = manual
                    ) 
                }
                
                if (manual) {
                    onSuccess()
                }
            } catch (e: Exception) {
                _uiState.update { it.copy(isSaving = false, isSaveSuccessful = false, error = "Error al guardar: ${e.message}") }
            }
        }
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
