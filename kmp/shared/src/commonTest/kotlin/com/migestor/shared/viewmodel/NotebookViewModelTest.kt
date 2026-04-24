package com.migestor.shared.viewmodel

import com.migestor.shared.domain.Evaluation
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnCategory
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookSheet
import com.migestor.shared.domain.NotebookWorkGroup
import com.migestor.shared.domain.NotebookTab
import com.migestor.shared.domain.SchoolClass
import com.migestor.shared.domain.Student
import com.migestor.shared.repository.ClassesRepository
import com.migestor.shared.repository.EvaluationsRepository
import com.migestor.shared.repository.GradesRepository
import com.migestor.shared.repository.NotebookRepository
import com.migestor.shared.repository.RubricsRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.advanceUntilIdle
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class NotebookViewModelTest {
    @Test
    fun `addColumn assigns the selected tab to the saved column`() = runTest {
        val classId = 1L
        val tabs = listOf(
            NotebookTab(id = "TAB_1", title = "Evaluación"),
            NotebookTab(id = "TAB_2", title = "Bloques"),
        )
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = tabs,
                columns = emptyList(),
                rows = emptyList(),
            )
        )
        val viewModel = createViewModel(repository)

        viewModel.selectClass(classId)
        advanceUntilIdle()
        viewModel.setSelectedTabId("TAB_2")
        viewModel.addColumn(name = "Examen", type = NotebookColumnType.NUMERIC.name, weight = 1.0)
        advanceUntilIdle()

        val saved = repository.savedColumns.last()
        assertEquals(listOf("TAB_2"), saved.tabIds)
        assertFalse(saved.sharedAcrossTabs)
    }

    @Test
    fun `addColumn spreads the column across all tabs when there is no active tab`() = runTest {
        val classId = 1L
        val tabs = listOf(
            NotebookTab(id = "TAB_1", title = "Evaluación"),
            NotebookTab(id = "TAB_2", title = "Bloques"),
        )
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = tabs,
                columns = emptyList(),
                rows = emptyList(),
            )
        )
        val viewModel = createViewModel(repository)

        viewModel.selectClass(classId)
        advanceUntilIdle()
        viewModel.setSelectedTabId(null)
        viewModel.addColumn(name = "Observación", type = NotebookColumnType.TEXT.name, weight = 1.0)
        advanceUntilIdle()

        val saved = repository.savedColumns.last()
        assertEquals(listOf("TAB_1", "TAB_2"), saved.tabIds)
        assertTrue(saved.sharedAcrossTabs)
    }

    @Test
    fun `addColumn keeps rubric metadata when creating rubric columns`() = runTest {
        val classId = 1L
        val tabs = listOf(NotebookTab(id = "TAB_1", title = "Evaluación"))
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = tabs,
                columns = emptyList(),
                rows = emptyList(),
            )
        )
        val viewModel = createViewModel(repository)

        viewModel.selectClass(classId)
        advanceUntilIdle()
        viewModel.setSelectedTabId("TAB_1")
        viewModel.addColumn(
            name = "Rúbrica técnica",
            type = NotebookColumnType.RUBRIC.name,
            weight = 1.0,
            rubricId = 42L
        )
        advanceUntilIdle()

        val saved = repository.savedColumns.last()
        assertEquals(NotebookColumnType.RUBRIC, saved.type)
        assertEquals(42L, saved.rubricId)
    }

    @Test
    fun `addColumn keeps formula for calculated columns`() = runTest {
        val classId = 1L
        val tabs = listOf(NotebookTab(id = "TAB_1", title = "Evaluación"))
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = tabs,
                columns = emptyList(),
                rows = emptyList(),
            )
        )
        val viewModel = createViewModel(repository)

        viewModel.selectClass(classId)
        advanceUntilIdle()
        viewModel.addColumn(
            name = "Final",
            type = NotebookColumnType.CALCULATED.name,
            weight = 1.0,
            formula = "ROUND((EX1*0.4)+(TA1*0.6), 2)"
        )
        advanceUntilIdle()

        val saved = repository.savedColumns.last()
        assertEquals(NotebookColumnType.CALCULATED, saved.type)
        assertEquals("ROUND((EX1*0.4)+(TA1*0.6), 2)", saved.formula)
    }

    @Test
    fun `saveColumn preserves layout metadata`() = runTest {
        val classId = 1L
        val tabs = listOf(NotebookTab(id = "TAB_1", title = "Evaluación"))
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = tabs,
                columns = emptyList(),
                rows = emptyList(),
            )
        )
        val viewModel = createViewModel(repository)

        viewModel.selectClass(classId)
        advanceUntilIdle()
        viewModel.saveColumn(
            NotebookColumnDefinition(
                id = "col_1",
                title = "Bloque",
                type = NotebookColumnType.TEXT,
                tabIds = listOf("TAB_1"),
                colorHex = "#FFAA00",
                order = 3,
                widthDp = 180.0
            )
        )
        advanceUntilIdle()

        val saved = repository.savedColumns.last()
        assertEquals(3, saved.order)
        assertEquals(180.0, saved.widthDp)
        assertEquals("#FFAA00", saved.colorHex)
    }

    @Test
    fun `saveWorkGroup keeps names unique within the same tab`() = runTest {
        val classId = 1L
        val tabs = listOf(NotebookTab(id = "TAB_1", title = "Evaluación"))
        val existingGroup = NotebookWorkGroup(
            id = 1L,
            classId = classId,
            tabId = "TAB_1",
            name = "Grupo 1",
            order = 0,
        )
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = tabs,
                columns = emptyList(),
                rows = emptyList(),
                workGroups = listOf(existingGroup),
            )
        )
        val viewModel = createViewModel(repository)

        viewModel.selectClass(classId)
        advanceUntilIdle()
        viewModel.saveWorkGroup(name = "Grupo 1")
        advanceUntilIdle()

        assertEquals("Grupo 1 (2)", repository.savedWorkGroups.last().name)
        assertEquals(1, repository.savedWorkGroups.size)
    }

    @Test
    fun `rubric drafts are numeric and save through grade repository`() = runTest {
        val classId = 1L
        val studentId = 7L
        val column = NotebookColumnDefinition(
            id = "eval_42",
            title = "Rúbrica",
            type = NotebookColumnType.RUBRIC,
            evaluationId = 42L,
            rubricId = 99L,
        )
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = emptyList(),
                columns = listOf(column),
                rows = listOf(
                    com.migestor.shared.domain.NotebookRow(
                        student = Student(id = studentId, firstName = "Ada", lastName = "Lovelace"),
                        cells = emptyList(),
                        weightedAverage = null,
                    )
                ),
            )
        )
        val viewModel = createViewModel(repository)

        viewModel.selectClass(classId)
        advanceUntilIdle()
        viewModel.saveColumnGrade(studentId, column, "8,5")
        advanceUntilIdle()

        val state = viewModel.state.value as NotebookUiState.Data
        assertEquals("8,5", state.numericDrafts[studentId to column.id])
        assertFalse(state.textDrafts.containsKey(studentId to column.id))
        assertEquals(
            FakeNotebookRepository.SavedGrade(classId, studentId, column.id, 42L, 8.5),
            repository.savedGrades.last()
        )
    }

    private fun createViewModel(repository: FakeNotebookRepository): NotebookViewModel {
        return NotebookViewModel(
            notebookRepository = repository,
            evaluationsRepository = FakeEvaluationsRepository(),
            rubricsRepository = FakeRubricsRepository(),
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
        )
    }
}

private class FakeNotebookRepository(
    private val snapshot: NotebookSheet,
) : NotebookRepository {
    val savedColumns = mutableListOf<NotebookColumnDefinition>()
    val savedWorkGroups = mutableListOf<NotebookWorkGroup>()
    val savedGrades = mutableListOf<SavedGrade>()

    data class SavedGrade(
        val classId: Long,
        val studentId: Long,
        val columnId: String,
        val evaluationId: Long?,
        val value: Double?,
    )

    override suspend fun loadNotebookSnapshot(classId: Long): NotebookSheet = snapshot
    override fun observeStudentChanges(classId: Long): Flow<List<Student>> = flowOf(emptyList())
    override fun observeGradesForClass(classId: Long): Flow<List<com.migestor.shared.domain.Grade>> = flowOf(emptyList())
    override suspend fun addStudent(classId: Long, firstName: String, lastName: String, isInjured: Boolean): Student = Student(id = 1, firstName = firstName, lastName = lastName, isInjured = isInjured)
    override suspend fun removeStudent(classId: Long, studentId: Long) = Unit
    override suspend fun listStudentsInClass(classId: Long): List<Student> = emptyList()
    override suspend fun saveGrade(classId: Long, studentId: Long, columnId: String, evaluationId: Long?, value: Double?): Long {
        savedGrades += SavedGrade(classId, studentId, columnId, evaluationId, value)
        return savedGrades.size.toLong()
    }
    override suspend fun saveTab(classId: Long, tab: NotebookTab) = Unit
    override suspend fun deleteTab(tabId: String) = Unit
    override suspend fun saveColumn(classId: Long, column: NotebookColumnDefinition) {
        savedColumns += column
    }
    override suspend fun deleteColumn(columnId: String) = Unit
    override suspend fun listColumnCategories(classId: Long, tabId: String?) = emptyList<NotebookColumnCategory>()
    override suspend fun saveColumnCategory(classId: Long, category: NotebookColumnCategory) = Unit
    override suspend fun deleteColumnCategory(classId: Long, categoryId: String, preserveColumns: Boolean) = Unit
    override suspend fun toggleCategoryCollapsed(classId: Long, categoryId: String, isCollapsed: Boolean) = Unit
    override suspend fun reorderCategory(classId: Long, tabId: String, categoryId: String, targetCategoryId: String) = Unit
    override suspend fun assignColumnToCategory(classId: Long, columnId: String, categoryId: String?) = Unit
    override suspend fun deleteEvaluation(evaluationId: Long) = Unit
    override suspend fun duplicateConfigToClass(sourceClassId: Long, targetClassId: Long) = Unit
    override suspend fun listWorkGroups(classId: Long, tabId: String?): List<com.migestor.shared.domain.NotebookWorkGroup> = emptyList()
    override suspend fun saveWorkGroup(classId: Long, workGroup: com.migestor.shared.domain.NotebookWorkGroup): Long {
        savedWorkGroups += workGroup
        return savedWorkGroups.size.toLong()
    }
    override suspend fun deleteWorkGroup(groupId: Long) = Unit
    override suspend fun listWorkGroupMembers(classId: Long, tabId: String?): List<com.migestor.shared.domain.NotebookWorkGroupMember> = emptyList()
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
    override suspend fun createTab(classId: Long, tabName: String): String = ""
    override suspend fun addColumnToTab(classId: Long, tabName: String, columnName: String, columnType: NotebookColumnType, rubricId: Long?): String = ""
    override suspend fun getNotebookConfig(classId: Long) = com.migestor.shared.domain.NotebookConfig(classId, emptyList(), emptyList())
    override suspend fun getGradeForColumn(studentId: Long, columnId: String): com.migestor.shared.domain.Grade? = null
    override suspend fun getColumnIdForEvaluation(evaluationId: Long): String? = null
    override suspend fun upsertGrade(
        classId: Long,
        studentId: Long,
        columnId: String,
        numericValue: Double,
        rubricSelections: String?,
        evidence: String?,
        createdAtEpochMs: Long,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ) = Unit
}

private class FakeEvaluationsRepository : EvaluationsRepository {
    override fun observeClassEvaluations(classId: Long): Flow<List<Evaluation>> = flowOf(emptyList())
    override suspend fun listClassEvaluations(classId: Long): List<Evaluation> = emptyList()
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
    ): Long = 1
    override suspend fun deleteEvaluation(evaluationId: Long) = Unit
    override suspend fun saveEvaluationCompetencyLink(
        id: Long?,
        evaluationId: Long,
        competencyId: Long,
        weight: Double,
        authorUserId: Long?,
    ): Long = 1
    override suspend fun listEvaluationCompetencyLinks(evaluationId: Long) = emptyList<com.migestor.shared.domain.EvaluationCompetencyLink>()
}

private class FakeRubricsRepository : RubricsRepository {
    override fun observeRubrics() = flowOf(emptyList<com.migestor.shared.domain.RubricDetail>())
    override suspend fun listRubrics() = emptyList<com.migestor.shared.domain.RubricDetail>()
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
    ) = 1L
    override suspend fun deleteRubric(rubricId: Long) = Unit
    override suspend fun saveCriterion(
        id: Long?,
        rubricId: Long,
        description: String,
        weight: Double,
        order: Int,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ) = 1L
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
    ) = 1L
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
    override suspend fun listRubricAssessments(studentId: Long, evaluationId: Long) = emptyList<com.migestor.shared.domain.RubricAssessment>()
    override suspend fun getStudentEvaluation(studentId: Long, rubricId: Long, evaluationId: Long) = emptyMap<Long, Long>()
    override suspend fun listCriteriaByRubric(rubricId: Long) = emptyList<com.migestor.shared.domain.RubricCriterion>()
    override suspend fun listLevelsByCriterion(criterionId: Long) = emptyList<com.migestor.shared.domain.RubricLevel>()
}
