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
                
                if (event.rubricId == rubricId) {
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
    private val AUTO_SAVE_DELAY_MS = 1000L

    fun load(classId: Long, evaluationId: Long, rubricId: Long, columnId: String?, tabId: String? = null) {
        _uiState.update { it.copy(isLoading = true, error = null, classId = classId, evaluationId = evaluationId, columnId = columnId, tabId = tabId) }
        
        scope.launch {
            try {
                // 1. Load Students in Class
                val classStudents = notebookRepository.listStudentsInClass(classId)
                val injured = classStudents.filter { it.isInjured }

                // 2. Load Rubric Detail
                val allRubrics = rubricsRepository.listRubrics()
                val rubricDetail = allRubrics.find { it.rubric.id == rubricId } ?: throw Exception("Rubric not found")

                // 3. Load Existing Assessments for all students
                val initialAssessments = mutableMapOf<Long, Map<Long, Long>>()
                val initialScores = mutableMapOf<Long, Double>()

                for (student in classStudents) {
                    val studentAssessments = if (columnId != null) {
                        val grade = notebookRepository.getGradeForColumn(student.id, columnId)
                        val rubricSelections = grade?.rubricSelections
                        if (!rubricSelections.isNullOrBlank()) {
                            parseRubricSelections(rubricSelections)
                        } else {
                            rubricsRepository.getStudentEvaluation(student.id, rubricId, evaluationId)
                        }
                    } else {
                        rubricsRepository.getStudentEvaluation(student.id, rubricId, evaluationId)
                    }
                    
                    if (studentAssessments.isNotEmpty()) {
                        initialAssessments[student.id] = studentAssessments
                        initialScores[student.id] = calculateScoreForAssessment(rubricDetail, studentAssessments)
                    }
                }

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
            saveStudentEvaluation(studentId)
        }
    }

    fun saveAll() {
        scope.launch {
            _uiState.update { it.copy(isSaving = true, isSaveSuccessful = false) }
            try {
                val state = _uiState.value
                for (student in state.students) {
                    saveStudentEvaluation(student.id)
                }
                _uiState.update { it.copy(isSaving = false, isSaveSuccessful = true) }
                NotebookRefreshBus.emitRefresh()
                delay(3000) // Give UI time to show success
                _uiState.update { it.copy(isSaveSuccessful = false) }
            } catch (e: Exception) {
                _uiState.update { it.copy(isSaving = false, error = "Error al guardar todo: ${e.message}") }
            }
        }
    }

    private suspend fun saveStudentEvaluation(studentId: Long) {
        val state = _uiState.value
        val studentAssessments = state.assessments[studentId] ?: return
        val score = state.scores[studentId] ?: 0.0
        val selectionsString = studentAssessments.entries.joinToString(",") { "${it.key}:${it.value}" }

        try {
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
            NotebookRefreshBus.emitRefresh()
            
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
        } catch (e: Exception) {
            _uiState.update { it.copy(error = "Auto-save error: ${e.message}") }
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
