package com.migestor.shared.viewmodel

import com.migestor.shared.domain.Rubric
import com.migestor.shared.domain.RubricCriterion
import com.migestor.shared.domain.RubricLevel
import com.migestor.shared.domain.RubricDetail
import com.migestor.shared.domain.RubricCriterionWithLevels
import com.migestor.shared.domain.SchoolClass
import com.migestor.shared.repository.RubricsRepository
import com.migestor.shared.repository.ClassesRepository
import com.migestor.shared.repository.EvaluationsRepository
import com.migestor.shared.repository.NotebookRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.util.NotebookRefreshBus
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlin.random.Random

enum class RubricMode { BANK, BUILDER }

data class AssignRubricDialogState(
    val rubricId: Long,
    val rubricName: String,
    val selectedClassId: Long? = null,
    val availableTabs: List<String> = emptyList(),
    val selectedTab: String? = null,
    val createNewTab: Boolean = false,
    val newTabName: String = ""
)

data class RubricUiState(
    val mode: RubricMode = RubricMode.BANK,
    val rubricName: String = "",
    val levels: List<RubricLevelState> = emptyList(),
    val criteria: List<RubricCriterionState> = emptyList(),
    val instructions: String = "",
    val autoSave: Boolean = true,
    val allowDecimals: Boolean = false,
    val selectedClassId: Long? = null,
    val selectedFilterClassId: Long? = null, // Filter for Bank Mode
    val allClasses: List<SchoolClass> = emptyList(),
    val totalWeight: Double = 0.0,
    val isSaving: Boolean = false,
    val savedRubrics: List<RubricDetail> = emptyList(),
    val isBankVisible: Boolean = true,
    val isConfigVisible: Boolean = false,
    val assignDialogState: AssignRubricDialogState? = null,
    val lastSavedTime: Instant? = null
)

data class RubricCriterionState(
    val id: Long? = null,
    val description: String = "",
    val weight: Double = 0.0,
    val order: Int = 0,
    val levelDescriptions: Map<String, String> = emptyMap() // Map level uid to description
)

data class RubricLevelState(
    val id: Long? = null,
    val uid: String = Random.nextLong().toString(),
    val name: String = "",
    val points: Int = 0,
    val order: Int = 0
)

class RubricsViewModel(
    private val rubricsRepository: RubricsRepository,
    private val classesRepository: ClassesRepository,
    private val evaluationsRepository: EvaluationsRepository,
    private val notebookRepository: NotebookRepository,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
) {
    private val _uiState = MutableStateFlow(RubricUiState())
    val uiState: StateFlow<RubricUiState> = _uiState.asStateFlow()

    init {
        scope.launch {
            classesRepository.observeClasses().collect { classes ->
                _uiState.update { it.copy(allClasses = classes) }
            }
        }
        scope.launch {
            rubricsRepository.observeRubrics().collect { rubrics ->
                _uiState.update { it.copy(savedRubrics = rubrics) }
            }
        }
        // Initialize with 3 dummy criteria and 3 levels each as per the design
        resetBuilder()
    }

    fun resetBuilder() {
        val defaultLevels = listOf(
            RubricLevelState(name = "Insuficiente", points = 1, order = 0),
            RubricLevelState(name = "Suficiente", points = 2, order = 1),
            RubricLevelState(name = "Notable", points = 3, order = 2),
            RubricLevelState(name = "Excelente", points = 4, order = 3)
        )
        
        val defaultCriteria = listOf(
            RubricCriterionState(
                description = "Técnica y Ejecución", 
                weight = 0.4, 
                order = 0,
                levelDescriptions = defaultLevels.associate { it.uid to "" }
            ),
            RubricCriterionState(
                description = "Puntualidad", 
                weight = 0.2, 
                order = 1,
                levelDescriptions = defaultLevels.associate { it.uid to "" }
            ),
            RubricCriterionState(
                description = "Creatividad", 
                weight = 0.4, 
                order = 2,
                levelDescriptions = defaultLevels.associate { it.uid to "" }
            )
        )
        
        _uiState.update { it.copy(
            mode = RubricMode.BUILDER,
            rubricName = "",
            levels = defaultLevels,
            criteria = defaultCriteria,
            totalWeight = 1.0,
            instructions = "",
            selectedClassId = null
        ) }
    }

    fun setMode(mode: RubricMode) {
        _uiState.update { it.copy(mode = mode) }
    }

    fun setFilterClass(classId: Long?) {
        _uiState.update { it.copy(selectedFilterClassId = classId) }
    }

    fun updateRubricName(name: String) {
        _uiState.update { it.copy(rubricName = name) }
    }

    fun updateInstructions(text: String) {
        _uiState.update { it.copy(instructions = text) }
    }

    fun updateAutoSave(enabled: Boolean) {
        _uiState.update { it.copy(autoSave = enabled) }
    }

    fun updateAllowDecimals(enabled: Boolean) {
        _uiState.update { it.copy(allowDecimals = enabled) }
    }

    fun selectClass(classId: Long?) {
        _uiState.update { it.copy(selectedClassId = classId) }
    }

    fun updateCriterionDescription(index: Int, description: String) {
        _uiState.update { state ->
            val newCriteria = state.criteria.toMutableList()
            newCriteria[index] = newCriteria[index].copy(description = description)
            state.copy(criteria = newCriteria)
        }
    }

    fun updateCriterionWeight(index: Int, weight: Double) {
        _uiState.update { state ->
            val newCriteria = state.criteria.toMutableList()
            newCriteria[index] = newCriteria[index].copy(weight = weight)
            val newTotal = newCriteria.sumOf { it.weight }
            state.copy(criteria = newCriteria, totalWeight = newTotal)
        }
    }

    fun updateLevelName(index: Int, name: String) {
        _uiState.update { state ->
            val newLevels = state.levels.toMutableList()
            newLevels[index] = newLevels[index].copy(name = name)
            state.copy(levels = newLevels)
        }
    }

    fun updateLevelPoints(index: Int, points: Int) {
        _uiState.update { state ->
            val newLevels = state.levels.toMutableList()
            newLevels[index] = newLevels[index].copy(points = points)
            state.copy(levels = newLevels)
        }
    }

    fun updateLevelDescription(criterionIndex: Int, levelUid: String, description: String) {
        _uiState.update { state ->
            val newCriteria = state.criteria.toMutableList()
            val currentCriterion = newCriteria[criterionIndex]
            val newLevelDescriptions = currentCriterion.levelDescriptions.toMutableMap()
            newLevelDescriptions[levelUid] = description
            newCriteria[criterionIndex] = currentCriterion.copy(levelDescriptions = newLevelDescriptions)
            state.copy(criteria = newCriteria)
        }
    }

    fun addLevel() {
        _uiState.update { state ->
            val newIndex = state.levels.size
            val newLevel = RubricLevelState(
                name = "Nivel ${newIndex + 1}",
                points = newIndex + 1,
                order = newIndex
            )
            val newCriteria = state.criteria.map { c ->
                val newDesc = c.levelDescriptions.toMutableMap()
                newDesc[newLevel.uid] = ""
                c.copy(levelDescriptions = newDesc)
            }
            state.copy(levels = state.levels + newLevel, criteria = newCriteria)
        }
        recalculateEqualWeights()
    }

    fun removeLevel(index: Int) {
        _uiState.update { state ->
            val levelToRemove = state.levels.getOrNull(index) ?: return@update state
            val newLevels = state.levels.toMutableList().apply { removeAt(index) }
                .mapIndexed { idx, level -> 
                    level.copy(
                        order = idx,
                        points = idx + 1
                    ) 
                }
            
            val newCriteria = state.criteria.map { criterion ->
                val newDesc = criterion.levelDescriptions.toMutableMap()
                newDesc.remove(levelToRemove.uid)
                criterion.copy(levelDescriptions = newDesc)
            }
            state.copy(levels = newLevels, criteria = newCriteria)
        }
    }

    fun reorderLevels(from: Int, to: Int) {
        _uiState.update { state ->
            val newLevels = state.levels.toMutableList().apply {
                val item = removeAt(from)
                add(to, item)
            }.mapIndexed { idx, level -> level.copy(order = idx) }

            // With UIDs, we don't need to update criterion.levelDescriptions!
            state.copy(levels = newLevels)
        }
    }

    fun addCriterion() {
        _uiState.update { state ->
            val newC = RubricCriterionState(
                description = "Nuevo Criterio", 
                weight = 0.0, 
                order = state.criteria.size
            )
            state.copy(criteria = state.criteria + newC)
        }
        recalculateEqualWeights()
    }

    fun removeCriterion(index: Int) {
        _uiState.update { state ->
            val newCriteria = state.criteria.toMutableList().apply { removeAt(index) }
                .mapIndexed { idx, c -> c.copy(order = idx) }
            state.copy(criteria = newCriteria)
        }
        recalculateEqualWeights()
    }

    fun recalculateEqualWeights() {
        _uiState.update { state ->
            if (state.criteria.isEmpty()) return@update state
            val count = state.criteria.size
            val equalWeight = 1.0 / count
            
            // Redondear a 2 decimales para evitar problemas de coma flotante visuales (.33333...)
            // Pero asegurar que el último criterio ajusta el total a 1.0 exactamente
            val roundedWeight = (kotlin.math.round(equalWeight * 100) / 100.0)
            
            val newCriteria = state.criteria.mapIndexed { index, criterion ->
                if (index == count - 1) {
                    criterion.copy(weight = 1.0 - (roundedWeight * (count - 1)))
                } else {
                    criterion.copy(weight = roundedWeight)
                }
            }
            state.copy(criteria = newCriteria, totalWeight = 1.0)
        }
    }

    fun applyPresetLevels(preset: String) {
        val currentLevels = _uiState.value.levels
        val levels = when (preset) {
            "Estándar" -> listOf(
                RubricLevelState(name = "Excelente", points = 4, order = 0),
                RubricLevelState(name = "Bien", points = 3, order = 1),
                RubricLevelState(name = "Suficiente", points = 2, order = 2),
                RubricLevelState(name = "Insuficiente", points = 1, order = 3)
            )
            "Binario" -> listOf(
                RubricLevelState(name = "Conseguido", points = 1, order = 0),
                RubricLevelState(name = "No conseguido", points = 0, order = 1)
            )
            "Numérico" -> listOf(
                RubricLevelState(name = "10", points = 10, order = 0),
                RubricLevelState(name = "5", points = 5, order = 1),
                RubricLevelState(name = "0", points = 0, order = 2)
            )
            else -> return
        }
        
        _uiState.update { state ->
            val newCriteria = state.criteria.map { c ->
                val newDesc = levels.mapIndexed { idx, level ->
                    val previousLevel = currentLevels.getOrNull(idx)
                    val previousValue = previousLevel?.let { c.levelDescriptions[it.uid] }.orEmpty()
                    level.uid to previousValue
                }.toMap()
                c.copy(levelDescriptions = newDesc)
            }
            state.copy(levels = levels, criteria = newCriteria)
        }
    }

    fun loadImportedRubric(importedState: RubricUiState) {
        _uiState.update { state ->
            state.copy(
                rubricName = importedState.rubricName,
                levels = importedState.levels,
                criteria = importedState.criteria,
                totalWeight = 0.0, 
                instructions = importedState.instructions,
                selectedClassId = null // Reset selection on import
            )
        }
        recalculateEqualWeights()
    }

    fun loadRubric(rubricDetail: RubricDetail) {
        val rubric = rubricDetail.rubric
        
        // Fetch fresh data from DB to avoid stale combine emissions
        scope.launch {
            try {
                val freshCriteria = rubricsRepository.listCriteriaByRubric(rubric.id)
                val freshCriteriaWithLevels = freshCriteria.map { criterion ->
                    val levels = rubricsRepository.listLevelsByCriterion(criterion.id)
                    RubricCriterionWithLevels(criterion = criterion, levels = levels)
                }
                
                // Use a consistent mapping between DB levels and state levels
                val firstCriterionLevels = freshCriteriaWithLevels.firstOrNull()?.levels?.sortedBy { it.order } ?: emptyList()
                
                val stateLevels = firstCriterionLevels.map { dbLevel ->
                    RubricLevelState(
                        id = dbLevel.id,
                        name = dbLevel.name,
                        points = dbLevel.points,
                        order = dbLevel.order
                    )
                }

                val stateCriteria = freshCriteriaWithLevels.map { cwl ->
                    val dbCriterion = cwl.criterion
                    val dbLevels = cwl.levels
                    
                    val descriptions = mutableMapOf<String, String>()
                    dbLevels.forEach { dbLevel ->
                        val stateLevel = stateLevels.find { it.order == dbLevel.order }
                        if (stateLevel != null) {
                            descriptions[stateLevel.uid] = dbLevel.description ?: ""
                        }
                    }

                    RubricCriterionState(
                        id = dbCriterion.id,
                        description = dbCriterion.description,
                        weight = dbCriterion.weight,
                        order = dbCriterion.order,
                        levelDescriptions = descriptions
                    )
                }

                _uiState.update { state ->
                    state.copy(
                        rubricName = rubric.name,
                        instructions = rubric.description ?: "",
                        levels = stateLevels,
                        criteria = stateCriteria,
                        totalWeight = stateCriteria.sumOf { it.weight },
                        selectedClassId = null,
                        mode = RubricMode.BUILDER
                    )
                }
                recalculateEqualWeights()
            } catch (e: Exception) {
                // Fallback: use the data from the RubricDetail directly
                loadRubricFromDetail(rubricDetail)
            }
        }
    }
    
    private fun loadRubricFromDetail(rubricDetail: RubricDetail) {
        val rubric = rubricDetail.rubric
        val criteriaWithLevels = rubricDetail.criteria
        
        val firstCriterionLevels = criteriaWithLevels.firstOrNull()?.levels?.sortedBy { it.order } ?: emptyList()
        
        val stateLevels = firstCriterionLevels.map { dbLevel ->
            RubricLevelState(
                id = dbLevel.id,
                name = dbLevel.name,
                points = dbLevel.points,
                order = dbLevel.order
            )
        }

        val stateCriteria = criteriaWithLevels.map { cwl ->
            val dbCriterion = cwl.criterion
            val dbLevels = cwl.levels
            
            val descriptions = mutableMapOf<String, String>()
            dbLevels.forEach { dbLevel ->
                val stateLevel = stateLevels.find { it.order == dbLevel.order }
                if (stateLevel != null) {
                    descriptions[stateLevel.uid] = dbLevel.description ?: ""
                }
            }

            RubricCriterionState(
                id = dbCriterion.id,
                description = dbCriterion.description,
                weight = dbCriterion.weight,
                order = dbCriterion.order,
                levelDescriptions = descriptions
            )
        }

        _uiState.update { state ->
            state.copy(
                rubricName = rubric.name,
                instructions = rubric.description ?: "",
                levels = stateLevels,
                criteria = stateCriteria,
                totalWeight = stateCriteria.sumOf { it.weight },
                selectedClassId = null,
                mode = RubricMode.BUILDER
            )
        }
        recalculateEqualWeights()
    }

    fun deleteRubric(rubricId: Long) {
        scope.launch {
            try {
                rubricsRepository.deleteRubric(rubricId)
            } catch (e: Exception) {
                // Handle error
            }
        }
    }

    fun saveRubric(onComplete: (Boolean) -> Unit) {
        val state = _uiState.value
        _uiState.update { it.copy(isSaving = true) }
        
        scope.launch {
            try {
                val rubricId = rubricsRepository.saveRubric(
                    name = state.rubricName,
                    description = state.instructions.takeIf { it.isNotBlank() },
                    classId = state.selectedClassId?.toLong()
                )
                
                state.criteria.forEach { c ->
                    val criterionId = rubricsRepository.saveCriterion(
                        rubricId = rubricId,
                        description = c.description,
                        weight = c.weight,
                        order = c.order
                    )
                    
                    state.levels.forEach { levelDef ->
                        rubricsRepository.saveLevel(
                            criterionId = criterionId,
                            name = levelDef.name,
                            points = levelDef.points,
                            description = c.levelDescriptions[levelDef.uid],
                            order = levelDef.order
                        )
                    }
                }

                // Refresh saved rubrics using a direct query (not the combine flow)
                // This avoids race conditions from intermediate combine emissions
                val freshRubrics = rubricsRepository.listRubrics()
                _uiState.update { it.copy(savedRubrics = freshRubrics) }

                // If a class is selected, create an evaluation linked to this rubric
                state.selectedClassId?.let { classId ->
                    evaluationsRepository.saveEvaluation(
                        id = null,
                        classId = classId,
                        code = "RUB-${rubricId}",
                        name = state.rubricName,
                        type = "Rúbrica",
                        weight = 1.0,
                        formula = null,
                        rubricId = rubricId,
                        description = state.instructions.takeIf { it.isNotBlank() }
                    )
                }
                
                _uiState.update { it.copy(isSaving = false, lastSavedTime = Clock.System.now()) }
                onComplete(true)
            } catch (e: Exception) {
                _uiState.update { it.copy(isSaving = false) }
                onComplete(false)
            }
        }
    }

    // --- Métodos para asignación de rúbrica a pestaña ---
    fun startAssignRubricToClass(rubric: Rubric) {
        _uiState.update { it.copy(
            assignDialogState = AssignRubricDialogState(
                rubricId = rubric.id,
                rubricName = rubric.name,
                selectedClassId = null
            )
        ) }
    }

    fun onAssignClassSelected(classId: Long) {
        scope.launch {
            try {
                val tabs = notebookRepository.getTabNamesForClass(classId)
                _uiState.update { it.copy(
                    assignDialogState = it.assignDialogState?.copy(
                        selectedClassId = classId,
                        availableTabs = tabs,
                        selectedTab = tabs.firstOrNull()
                    )
                ) }
            } catch (e: Exception) {
                // Ignore
            }
        }
    }

    fun onAssignTabSelected(tabName: String) {
        _uiState.update { it.copy(
            assignDialogState = it.assignDialogState?.copy(
                selectedTab = tabName,
                createNewTab = false
            )
        ) }
    }

    fun onToggleCreateNewTab(create: Boolean) {
        _uiState.update { it.copy(
            assignDialogState = it.assignDialogState?.copy(createNewTab = create)
        ) }
    }

    fun onNewTabNameChanged(name: String) {
        _uiState.update { it.copy(
            assignDialogState = it.assignDialogState?.copy(newTabName = name)
        ) }
    }

    fun confirmAssignRubric() {
        val state = _uiState.value.assignDialogState ?: return
        scope.launch {
            try {
                val requestedNewTabName = state.newTabName.trim().ifBlank { "Rúbricas" }
                val finalTabName = if (state.createNewTab) {
                    val classId = state.selectedClassId ?: throw Exception("No class selected")
                    notebookRepository.createTab(classId, requestedNewTabName)
                    requestedNewTabName
                } else {
                    state.selectedTab
                        ?: state.availableTabs.firstOrNull()
                        ?: requestedNewTabName.also {
                            val classId = state.selectedClassId ?: throw Exception("No class selected")
                            notebookRepository.createTab(classId, it)
                        }
                }

                val classId = state.selectedClassId ?: throw Exception("No class selected")
                notebookRepository.addColumnToTab(
                    classId = classId,
                    tabName = finalTabName,
                    columnName = state.rubricName,
                    columnType = NotebookColumnType.RUBRIC,
                    rubricId = state.rubricId
                )

                // Force notebook views to reload configuration (tabs/columns) and reflect
                // rubric assignments immediately, even if only config changed.
                NotebookRefreshBus.emitRefresh()
                
                dismissAssignDialog()
            } catch (e: Exception) {
                // Log error
            }
        }
    }

    fun dismissAssignDialog() {
        _uiState.update { it.copy(assignDialogState = null) }
    }

    fun toggleBank() {
        _uiState.update { it.copy(isBankVisible = !it.isBankVisible) }
    }

    fun toggleConfig() {
        _uiState.update { it.copy(isConfigVisible = !it.isConfigVisible) }
    }
}
