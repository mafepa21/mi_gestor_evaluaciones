package com.migestor.shared.viewmodel

import com.migestor.shared.domain.*
import com.migestor.shared.repository.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals

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

    private fun createViewModel(): RubricsViewModel {
        return RubricsViewModel(
            rubricsRepository = RubricsTestFakeRubricsRepository(),
            classesRepository = RubricsTestFakeClassesRepository(),
            evaluationsRepository = RubricsTestFakeEvaluationsRepository(),
            notebookRepository = RubricsTestFakeNotebookRepository(),
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
        )
    }
}

private class RubricsTestFakeRubricsRepository : RubricsRepository {
    override fun observeRubrics(): Flow<List<RubricDetail>> = flowOf(emptyList())
    override suspend fun listRubrics(): List<RubricDetail> = emptyList()
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

private class RubricsTestFakeClassesRepository : ClassesRepository {
    override fun observeClasses(): Flow<List<SchoolClass>> = flowOf(emptyList())
    override fun observeStudentsInClass(classId: Long): Flow<List<Student>> = flowOf(emptyList())
    override suspend fun listClasses(): List<SchoolClass> = emptyList()
    override suspend fun saveClass(
        id: Long?,
        name: String,
        course: Int,
        description: String?,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): Long = 1L
    override suspend fun deleteClass(classId: Long) = Unit
    override suspend fun addStudentToClass(classId: Long, studentId: Long) = Unit
    override suspend fun removeStudentFromClass(classId: Long, studentId: Long) = Unit
    override suspend fun listStudentsInClass(classId: Long): List<Student> = emptyList()
}

private class RubricsTestFakeEvaluationsRepository : EvaluationsRepository {
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

private class RubricsTestFakeNotebookRepository : NotebookRepository {
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
    override suspend fun deleteColumn(columnId: String) = Unit
    override suspend fun listColumnCategories(classId: Long, tabId: String?): List<NotebookColumnCategory> = emptyList()
    override suspend fun saveColumnCategory(classId: Long, category: NotebookColumnCategory) = Unit
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
    override suspend fun getNotebookConfig(classId: Long): NotebookConfig = NotebookConfig(classId, emptyList(), emptyList())
    override suspend fun getGradeForColumn(studentId: Long, columnId: String): Grade? = null
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
