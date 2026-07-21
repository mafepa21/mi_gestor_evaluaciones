package com.migestor.shared.viewmodel

import com.migestor.shared.domain.*
import com.migestor.shared.repository.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class RubricsViewModelTest {
    @Test
    fun `applyPresetLevels preserves existing descriptions by level order`() = runTest {
        val viewModel = createViewModel()

        val originalState = viewModel.uiState.value
        originalState.levels.forEachIndexed { index, level ->
            viewModel.updateLevelDescription(0, level.uid, "desc-$index")
        }

        viewModel.applyPresetLevels("Binario")
        advanceUntilIdle()

        val state = viewModel.uiState.value
        val criterion = state.criteria.first()

        assertEquals(2, state.levels.size)
        assertEquals("desc-0", criterion.levelDescriptions[state.levels[0].uid])
        assertEquals("desc-1", criterion.levelDescriptions[state.levels[1].uid])
    }

    @Test
    fun `removeCriterion recalculates equal weights`() = runTest {
        val viewModel = createViewModel()

        viewModel.removeCriterion(1)
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertEquals(2, state.criteria.size)
        assertEquals(1.0, state.totalWeight)
        assertEquals(0.5, state.criteria[0].weight)
        assertEquals(0.5, state.criteria[1].weight)
    }

    @Test
    fun `removeLevel keeps the points of the surviving levels intact`() = runTest {
        // Regresion: removeLevel reescribia points = idx + 1 para TODOS los niveles
        // supervivientes segun su nueva posicion, destruyendo cualquier escala
        // personalizada o descendente (p. ej. Excelente=4, Bien=3, Suficiente=2,
        // Insuficiente=1: borrar "Bien" dejaba Excelente=1, Suficiente=2,
        // Insuficiente=3, invertida). reorderLevels ya seguia el criterio correcto
        // (solo tocar `order`, nunca `points`); removeLevel debe hacer lo mismo.
        val viewModel = createViewModel()

        viewModel.applyPresetLevels("Estándar") // Excelente=4, Bien=3, Suficiente=2, Insuficiente=1
        advanceUntilIdle()
        val before = viewModel.uiState.value.levels
        assertEquals(listOf("Excelente", "Bien", "Suficiente", "Insuficiente"), before.map { it.name })
        assertEquals(listOf(4, 3, 2, 1), before.map { it.points })

        viewModel.removeLevel(1) // borra "Bien"
        advanceUntilIdle()

        val after = viewModel.uiState.value.levels
        assertEquals(listOf("Excelente", "Suficiente", "Insuficiente"), after.map { it.name })
        assertEquals(listOf(4, 2, 1), after.map { it.points }, "Los puntos de los niveles supervivientes no deben reescribirse por posicion")
        assertEquals(listOf(0, 1, 2), after.map { it.order })
    }

    @Test
    fun `saveRubric pairs existing levels by id, not by position, after a reorder`() = runTest {
        // Regresion: saveRubric emparejaba niveles existentes por `order` (posicion), no
        // por id. Tras reordenar (reorderLevels solo cambia `order`, cada nivel conserva
        // su propio id/points/name), guardar reescribia en sitio el nombre/puntos del
        // nivel que HABIA en esa posicion -mismo id de BD, significado distinto- lo que
        // corrompe en silencio cualquier evaluacion ya guardada que referenciara ese id.
        val criterionId = 10L
        val levelExcelenteId = 100L
        val levelInsuficienteId = 101L
        val existingLevels = listOf(
            RubricLevel(id = levelExcelenteId, criterionId = criterionId, name = "Excelente", points = 4, order = 0),
            RubricLevel(id = levelInsuficienteId, criterionId = criterionId, name = "Insuficiente", points = 1, order = 1),
        )
        val existingCriteria = listOf(
            RubricCriterion(id = criterionId, rubricId = 7L, description = "Ejecución", weight = 1.0, order = 0)
        )
        val savedLevelCalls = mutableListOf<Pair<Long?, String>>() // id pasado -> nombre

        val fakeRubrics = object : RubricsTestFakeRubricsRepository() {
            override suspend fun listCriteriaByRubric(rubricId: Long): List<RubricCriterion> = existingCriteria
            override suspend fun listLevelsByCriterion(criterionId: Long): List<RubricLevel> = existingLevels
            override suspend fun saveLevel(
                id: Long?, criterionId: Long, name: String, points: Int, description: String?,
                order: Int, updatedAtEpochMs: Long, deviceId: String?, syncVersion: Long,
            ): Long {
                savedLevelCalls += id to name
                return id ?: 999L
            }
        }

        val viewModel = createViewModel(rubricsRepository = fakeRubrics)
        viewModel.loadRubric(
            RubricDetail(rubric = Rubric(id = 7L, name = "Rubrica", classId = null), criteria = emptyList())
        )
        advanceUntilIdle()

        // El usuario reordena: "Insuficiente" (id=101) pasa a la primera posicion.
        viewModel.reorderLevels(from = 1, to = 0)
        advanceUntilIdle()

        var completed = false
        viewModel.saveRubric { completed = true }
        advanceUntilIdle()

        assertEquals(true, completed)
        // Cada nivel debe guardarse con SU PROPIO id, sin importar la nueva posicion.
        assertTrue(
            savedLevelCalls.contains(levelInsuficienteId to "Insuficiente"),
            "Insuficiente debe guardarse con su propio id (101), no con el que ocupaba su nueva posicion. Llamadas: $savedLevelCalls"
        )
        assertTrue(
            savedLevelCalls.contains(levelExcelenteId to "Excelente"),
            "Excelente debe guardarse con su propio id (100). Llamadas: $savedLevelCalls"
        )
    }

    @Test
    fun `saveRubric does not duplicate the linked evaluation on repeated saves`() = runTest {
        // Regresion: saveRubric creaba SIEMPRE una evaluacion nueva (id = null) cuando
        // habia clase seleccionada, sin comprobar si ya existia una "RUB-<id>" para esa
        // rubrica+clase. Editar una rubrica ya asignada (loadRubric fija selectedClassId
        // al de la rubrica) y guardar dos veces duplicaba la evaluacion vinculada, con
        // weight=1.0 cada una, desbalanceando la nota final de la clase.
        val classId = 10L
        val savedEvaluations = mutableListOf<Evaluation>()
        var nextEvalId = 500L

        val fakeEvaluations = object : RubricsTestFakeEvaluationsRepository() {
            override suspend fun listClassEvaluations(classId: Long): List<Evaluation> =
                savedEvaluations.filter { it.classId == classId }
            override suspend fun saveEvaluation(
                id: Long?, classId: Long, code: String, name: String, type: String, weight: Double,
                formula: String?, rubricId: Long?, description: String?, authorUserId: Long?,
                createdAtEpochMs: Long, updatedAtEpochMs: Long, associatedGroupId: Long?,
                deviceId: String?, syncVersion: Long,
            ): Long {
                val resolvedId = id ?: nextEvalId++
                savedEvaluations.removeAll { it.id == resolvedId }
                savedEvaluations += Evaluation(
                    id = resolvedId, classId = classId, code = code, name = name,
                    type = type, weight = weight, rubricId = rubricId,
                )
                return resolvedId
            }
        }

        val viewModel = createViewModel(evaluationsRepository = fakeEvaluations)
        viewModel.loadRubric(
            RubricDetail(rubric = Rubric(id = 7L, name = "Rubrica", classId = classId), criteria = emptyList())
        )
        advanceUntilIdle()

        var completedFirst = false
        viewModel.saveRubric { completedFirst = true }
        advanceUntilIdle()

        var completedSecond = false
        viewModel.saveRubric { completedSecond = true }
        advanceUntilIdle()

        assertEquals(true, completedFirst)
        assertEquals(true, completedSecond)
        val linkedEvaluations = savedEvaluations.filter { it.classId == classId && it.rubricId != null }
        assertEquals(1, linkedEvaluations.size, "Guardar la rubrica dos veces no debe duplicar su evaluacion vinculada: $linkedEvaluations")
    }

    @Test
    fun `workspace summaries reflect rubric usage and keep selection inside filter`() = runTest {
        val rubricA = sampleRubricDetail(id = 1, name = "Rúbrica A", classId = 10)
        val rubricB = sampleRubricDetail(id = 2, name = "Rúbrica B", classId = 20)
        val viewModel = createViewModel(
            rubricsRepository = RubricsTestFakeRubricsRepository(listOf(rubricA, rubricB)),
            classesRepository = RubricsTestFakeClassesRepository(
                listOf(
                    SchoolClass(id = 10, name = "1A", course = 1),
                    SchoolClass(id = 20, name = "2B", course = 2)
                )
            ),
            evaluationsRepository = RubricsTestFakeEvaluationsRepository(
                mapOf(
                    10L to listOf(Evaluation(id = 101, classId = 10, code = "R101", name = "Control 1A", type = "Rúbrica", rubricId = 1)),
                    20L to emptyList()
                )
            )
        )

        advanceUntilIdle()

        assertEquals(1L, viewModel.uiState.value.selectedWorkspaceRubricId)
        assertEquals(1, viewModel.uiState.value.usageSummaries[1L]?.evaluationCount)

        viewModel.selectWorkspaceRubric(2L)
        viewModel.setFilterClass(10L)
        advanceUntilIdle()

        assertEquals(1L, viewModel.uiState.value.selectedWorkspaceRubricId)
    }

    @Test
    fun `bulk evaluation dialog resolves navigation target with column and tab`() = runTest {
        val rubric = sampleRubricDetail(id = 5, name = "Rúbrica EF", classId = 10)
        val notebookRepository = RubricsTestFakeNotebookRepository(
            notebookConfig = NotebookConfig(
                classId = 10,
                tabs = listOf(NotebookTab(id = "tab-ef", title = "EF")),
                columns = listOf(
                    NotebookColumnDefinition(
                        id = "col-ef",
                        title = "Rúbrica EF",
                        type = NotebookColumnType.RUBRIC,
                        evaluationId = 501,
                        rubricId = 5,
                        tabIds = listOf("tab-ef")
                    )
                )
            ),
            columnIdByEvaluation = mapOf(501L to "col-ef")
        )
        val viewModel = createViewModel(
            rubricsRepository = RubricsTestFakeRubricsRepository(listOf(rubric)),
            classesRepository = RubricsTestFakeClassesRepository(
                listOf(SchoolClass(id = 10, name = "1A", course = 1))
            ),
            evaluationsRepository = RubricsTestFakeEvaluationsRepository(
                mapOf(
                    10L to listOf(
                        Evaluation(id = 501, classId = 10, code = "EV1", name = "Sprint", type = "Rúbrica", rubricId = 5),
                        Evaluation(id = 502, classId = 10, code = "EV2", name = "Cooperación", type = "Rúbrica", rubricId = 5)
                    )
                )
            ),
            notebookRepository = notebookRepository
        )

        advanceUntilIdle()

        viewModel.requestBulkEvaluationForSelectedRubric()
        advanceUntilIdle()

        val dialog = viewModel.uiState.value.bulkEvaluationContextDialog
        assertNotNull(dialog)
        assertEquals(2, dialog.options.size)

        viewModel.confirmBulkEvaluationContext(501L)
        advanceUntilIdle()

        val target = viewModel.uiState.value.pendingBulkEvaluationTarget
        assertNotNull(target)
        assertEquals("col-ef", target.columnId)
        assertEquals("tab-ef", target.tabId)
    }

    private fun createViewModel(
        rubricsRepository: RubricsRepository = RubricsTestFakeRubricsRepository(),
        classesRepository: ClassesRepository = RubricsTestFakeClassesRepository(),
        evaluationsRepository: EvaluationsRepository = RubricsTestFakeEvaluationsRepository(),
        notebookRepository: NotebookRepository = RubricsTestFakeNotebookRepository()
    ): RubricsViewModel {
        return RubricsViewModel(
            rubricsRepository = rubricsRepository,
            classesRepository = classesRepository,
            evaluationsRepository = evaluationsRepository,
            notebookRepository = notebookRepository,
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
        )
    }
}

private open class RubricsTestFakeRubricsRepository(
    rubrics: List<RubricDetail> = emptyList()
) : RubricsRepository {
    private val rubricsFlow = MutableStateFlow(rubrics)

    override fun observeRubrics(): Flow<List<RubricDetail>> = rubricsFlow
    override suspend fun listRubrics(): List<RubricDetail> = rubricsFlow.value
    override suspend fun saveRubric(
        id: Long?,
        name: String,
        description: String?,
        classId: Long?,
        teachingUnitId: Long?,
        createdAtEpochMs: Long,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): Long = 1L
    override suspend fun deleteRubric(rubricId: Long) {
        rubricsFlow.value = rubricsFlow.value.filterNot { it.rubric.id == rubricId }
    }
    override suspend fun saveCriterion(
        id: Long?,
        rubricId: Long,
        description: String,
        weight: Double,
        order: Int,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): Long = 1L
    override suspend fun deleteCriterion(criterionId: Long) = Unit
    override suspend fun saveLevel(
        id: Long?,
        criterionId: Long,
        name: String,
        points: Int,
        description: String?,
        order: Int,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): Long = 1L
    override suspend fun deleteLevel(levelId: Long) = Unit
    override suspend fun saveRubricAssessment(
        studentId: Long,
        evaluationId: Long,
        criterionId: Long,
        levelId: Long,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): Double? = null
    override suspend fun listRubricAssessments(studentId: Long, evaluationId: Long): List<RubricAssessment> = emptyList()
    override suspend fun getStudentEvaluation(studentId: Long, rubricId: Long, evaluationId: Long): Map<Long, Long> = emptyMap()
    override suspend fun listCriteriaByRubric(rubricId: Long): List<RubricCriterion> = emptyList()
    override suspend fun listLevelsByCriterion(criterionId: Long): List<RubricLevel> = emptyList()
}

private class RubricsTestFakeClassesRepository(
    classes: List<SchoolClass> = emptyList()
) : ClassesRepository {
    private val classesFlow = MutableStateFlow(classes)

    override fun observeClasses(): Flow<List<SchoolClass>> = classesFlow
    override fun observeStudentsInClass(classId: Long): Flow<List<Student>> = flowOf(emptyList())
    override suspend fun listClasses(): List<SchoolClass> = classesFlow.value
    override suspend fun saveClass(
        id: Long?,
        name: String,
        course: Int,
        description: String?,
        centerId: Long?,
        academicYearId: Long?,
        stageCycleId: Long?,
        subjectId: Long?,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): Long = 1L
    override suspend fun deleteClass(classId: Long) = Unit
    override suspend fun addStudentToClass(classId: Long, studentId: Long) = Unit
    override suspend fun removeStudentFromClass(classId: Long, studentId: Long) = Unit
    override suspend fun listStudentsInClass(classId: Long): List<Student> = emptyList()
}

private open class RubricsTestFakeEvaluationsRepository(
    private val evaluationsByClass: Map<Long, List<Evaluation>> = emptyMap()
) : EvaluationsRepository {
    override fun observeClassEvaluations(classId: Long): Flow<List<Evaluation>> = flowOf(emptyList())
    override suspend fun listClassEvaluations(classId: Long): List<Evaluation> = evaluationsByClass[classId].orEmpty()
    override suspend fun getEvaluation(evaluationId: Long): Evaluation? = null
    override suspend fun saveEvaluation(
        id: Long?,
        classId: Long,
        code: String,
        name: String,
        type: String,
        weight: Double,
        formula: String?,
        rubricId: Long?,
        description: String?,
        authorUserId: Long?,
        createdAtEpochMs: Long,
        updatedAtEpochMs: Long,
        associatedGroupId: Long?,
        deviceId: String?,
        syncVersion: Long,
    ): Long = 1L
    override suspend fun deleteEvaluation(evaluationId: Long) = Unit
    override suspend fun saveEvaluationCompetencyLink(
        id: Long?,
        evaluationId: Long,
        competencyId: Long,
        weight: Double,
        authorUserId: Long?,
    ): Long = 1L
    override suspend fun listEvaluationCompetencyLinks(evaluationId: Long): List<EvaluationCompetencyLink> = emptyList()
}

private class RubricsTestFakeNotebookRepository(
    private val notebookConfig: NotebookConfig = NotebookConfig(1, emptyList(), emptyList()),
    private val columnIdByEvaluation: Map<Long, String> = emptyMap()
) : NotebookRepository {
    override suspend fun loadNotebookSnapshot(classId: Long): NotebookSheet = NotebookSheet(
        classId = classId,
        tabs = emptyList(),
        columns = emptyList(),
        rows = emptyList(),
    )
    override fun observeStudentChanges(classId: Long): Flow<List<Student>> = flowOf(emptyList())
    override fun observeGradesForClass(classId: Long): Flow<List<Grade>> = flowOf(emptyList())
    override suspend fun addStudent(classId: Long, firstName: String, lastName: String, isInjured: Boolean): Student =
        Student(id = 1, firstName = firstName, lastName = lastName, isInjured = isInjured)
    override suspend fun removeStudent(classId: Long, studentId: Long) = Unit
    override suspend fun listStudentsInClass(classId: Long): List<Student> = emptyList()
    override suspend fun saveGrade(classId: Long, studentId: Long, columnId: String, evaluationId: Long?, value: Double?): Long = 1L
    override suspend fun saveTab(classId: Long, tab: NotebookTab) = Unit
    override suspend fun deleteTab(tabId: String) = Unit
    override suspend fun saveColumn(classId: Long, column: NotebookColumnDefinition) = Unit
    override suspend fun saveAverageConfiguration(classId: Long, updates: List<NotebookAverageColumnConfig>) = Unit
    override suspend fun previewDeleteColumn(classId: Long, columnId: String): NotebookDeletionImpact =
        NotebookDeletionImpact(columnId, columnId, NotebookDeletionTargetKind.COLUMN, 1, 0, 0, 0, false)
    override suspend fun deleteColumn(columnId: String) = Unit
    override suspend fun listColumnCategories(classId: Long, tabId: String?): List<NotebookColumnCategory> = emptyList()
    override suspend fun saveColumnCategory(classId: Long, category: NotebookColumnCategory) = Unit
    override suspend fun previewDeleteColumnCategory(classId: Long, categoryId: String): NotebookDeletionImpact =
        NotebookDeletionImpact(categoryId, categoryId, NotebookDeletionTargetKind.CATEGORY, 0, 0, 0, 0, false)
    override suspend fun deleteColumnCategory(classId: Long, categoryId: String, preserveColumns: Boolean) = Unit
    override suspend fun toggleCategoryCollapsed(classId: Long, categoryId: String, isCollapsed: Boolean) = Unit
    override suspend fun reorderCategory(classId: Long, tabId: String, categoryId: String, targetCategoryId: String) = Unit
    override suspend fun assignColumnToCategory(classId: Long, columnId: String, categoryId: String?) = Unit
    override suspend fun deleteEvaluation(evaluationId: Long) = Unit
    override suspend fun duplicateConfigToClass(sourceClassId: Long, targetClassId: Long) = Unit
    override suspend fun listWorkGroups(classId: Long, tabId: String?): List<NotebookWorkGroup> = emptyList()
    override suspend fun saveWorkGroup(classId: Long, workGroup: NotebookWorkGroup): Long = 1L
    override suspend fun deleteWorkGroup(groupId: Long) = Unit
    override suspend fun listWorkGroupMembers(classId: Long, tabId: String?): List<NotebookWorkGroupMember> = emptyList()
    override suspend fun assignStudentsToWorkGroup(classId: Long, tabId: String, groupId: Long, studentIds: List<Long>) = Unit
    override suspend fun clearStudentsFromWorkGroup(classId: Long, tabId: String, studentIds: List<Long>) = Unit
    override suspend fun saveCell(
        classId: Long,
        studentId: Long,
        columnId: String,
        textValue: String?,
        boolValue: Boolean?,
        iconValue: String?,
        ordinalValue: String?,
        note: String?,
        colorHex: String?,
        attachmentUris: List<String>,
        authorUserId: Long?,
        associatedGroupId: Long?,
    ) = Unit
    override suspend fun getTabNamesForClass(classId: Long): List<String> = emptyList()
    override suspend fun createTab(classId: Long, tabName: String): String = tabName
    override suspend fun addColumnToTab(classId: Long, tabName: String, columnName: String, columnType: NotebookColumnType, rubricId: Long?): String = columnName
    override suspend fun getNotebookConfig(classId: Long): NotebookConfig = notebookConfig
    override suspend fun getGradeForColumn(studentId: Long, columnId: String): Grade? = null
    override suspend fun getColumnIdForEvaluation(evaluationId: Long): String? = columnIdByEvaluation[evaluationId]
    override suspend fun upsertGrade(
        classId: Long,
        studentId: Long,
        columnId: String,
        evaluationId: Long?,
        numericValue: Double,
        rubricSelections: String?,
        evidence: String?,
        createdAtEpochMs: Long,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ) = Unit

    override fun observeCellAudit(
        classId: Long,
        studentId: Long,
        columnId: String,
    ): Flow<List<com.migestor.shared.domain.NotebookCellAuditEvent>> = flowOf(emptyList())
}

private fun sampleRubricDetail(id: Long, name: String, classId: Long?): RubricDetail = RubricDetail(
    rubric = Rubric(id = id, name = name, classId = classId),
    criteria = listOf(
        RubricCriterionWithLevels(
            criterion = RubricCriterion(id = id * 10, rubricId = id, description = "Ejecución", weight = 1.0, order = 0),
            levels = listOf(
                RubricLevel(id = id * 100, criterionId = id * 10, name = "Bien", points = 3, order = 0),
                RubricLevel(id = id * 100 + 1, criterionId = id * 10, name = "Muy bien", points = 4, order = 1)
            )
        )
    )
)
