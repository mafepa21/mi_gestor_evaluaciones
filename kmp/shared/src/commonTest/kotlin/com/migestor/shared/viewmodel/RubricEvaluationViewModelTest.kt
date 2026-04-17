package com.migestor.shared.viewmodel

import com.migestor.shared.domain.*
import com.migestor.shared.repository.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.advanceUntilIdle
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

class RubricEvaluationViewModelTest {

    private val testRubricId = 1L
    private val testStudentId = 1L
    private val testEvalId = 100L

    @Test
    fun `calculates total score with automatic equal weights ignoring DB weights`() = runTest {
        // C1: 10 levels, DB Weight 999. C2: 2 levels, DB Weight 0.
        // Total criteria: 2. Each should contribute 5 points max.
        val criteriaWithLevels = listOf(
            RubricCriterionWithLevels(
                criterion = RubricCriterion(id = 1, rubricId = testRubricId, description = "C1", weight = 999.0, order = 0),
                levels = (1L..10L).map { lId -> RubricLevel(id = 10 + lId, criterionId = 1, name = "L1.$lId", points = 0, order = lId.toInt()) }
            ),
            RubricCriterionWithLevels(
                criterion = RubricCriterion(id = 2, rubricId = testRubricId, description = "C2", weight = 0.0, order = 1),
                levels = (1L..2L).map { lId -> RubricLevel(id = 20 + lId, criterionId = 2, name = "L2.$lId", points = 0, order = lId.toInt()) }
            )
        )
        
        val viewModel = createViewModelWithRubric(this, criteriaWithLevels)
        
        // Select Max for C1 (10/10) and Min for C2 (1/2)
        // C1 percentage = 1.0. C2 percentage = 0.5.
        // Total = (1.0 + 0.5) / 2 * 10 = 0.75 * 10 = 7.5
        viewModel.selectLevel(1, 20) // L1.10
        viewModel.selectLevel(2, 21) // L2.1
        assertEquals(7.5, viewModel.uiState.value.totalScore)

        // Select Max for both: (1.0 + 1.0) / 2 * 10 = 10.0
        viewModel.selectLevel(2, 22) // L2.2
        assertEquals(10.0, viewModel.uiState.value.totalScore)
    }

    @Test
    fun `calculates user example 3 criteria 4 levels each`() = runTest {
        // Example: 3 criteria, 4 levels each. Weight 1.0 each.
        // Total Max = 4 + 4 + 4 = 12.0
        val criteriaWithLevels = (1L..3L).map { cId ->
            RubricCriterionWithLevels(
                criterion = RubricCriterion(id = cId, rubricId = testRubricId, description = "C$cId", weight = 1.0, order = cId.toInt()),
                levels = (1L..4L).map { lId ->
                    RubricLevel(id = cId * 10 + lId, criterionId = cId, name = "L$cId.$lId", points = 0, order = lId.toInt())
                }
            )
        }

        val viewModel = createViewModelWithRubric(this, criteriaWithLevels)

        // Select top levels: 4, 4, 4. Sum = 12. Result = (12/12)*10 = 10.0
        viewModel.selectLevel(1, 14)
        viewModel.selectLevel(2, 24)
        viewModel.selectLevel(3, 34)
        assertEquals(10.0, viewModel.uiState.value.totalScore)

        // Select mid levels: 2, 3, 1. Sum = 6. Result = (6/12)*10 = 5.0
        viewModel.selectLevel(1, 12)
        viewModel.selectLevel(2, 23)
        viewModel.selectLevel(3, 31)
        assertEquals(5.0, viewModel.uiState.value.totalScore)
    }

    private suspend fun kotlinx.coroutines.test.TestScope.createViewModelWithRubric(
        scope: kotlinx.coroutines.CoroutineScope, 
        criteria: List<RubricCriterionWithLevels>
    ): RubricEvaluationViewModel {
        val rubricDetail = RubricDetail(
            rubric = Rubric(id = testRubricId, name = "Test"),
            criteria = criteria
        )
        val viewModel = RubricEvaluationViewModel(
            FakeRubricsRepository(listOf(rubricDetail)),
            FakeStudentsRepository(listOf(Student(testStudentId, "F", "L"))),
            FakeEvaluationsRepository(),
            FakeGradesRepository(),
            FakeNotebookRepository(),
            scope
        )
        viewModel.loadEvaluation(testStudentId, testEvalId, testRubricId)
        advanceUntilIdle()
        return viewModel
    }

    private class FakeRubricsRepository(val rubrics: List<RubricDetail> = emptyList()) : RubricsRepository {
        override fun observeRubrics(): Flow<List<RubricDetail>> = flowOf(rubrics)
        override suspend fun listRubrics(): List<RubricDetail> = rubrics
        override suspend fun saveRubric(id: Long?, name: String, description: String?, classId: Long?, teachingUnitId: Long?, createdAtEpochMs: Long, updatedAtEpochMs: Long, deviceId: String?, syncVersion: Long): Long = 1
        override suspend fun deleteRubric(rubricId: Long) = Unit
        override suspend fun saveCriterion(id: Long?, rubricId: Long, description: String, weight: Double, order: Int, updatedAtEpochMs: Long, deviceId: String?, syncVersion: Long): Long = 1
        override suspend fun deleteCriterion(criterionId: Long) = Unit
        override suspend fun saveLevel(id: Long?, criterionId: Long, name: String, points: Int, description: String?, order: Int, updatedAtEpochMs: Long, deviceId: String?, syncVersion: Long): Long = 1
        override suspend fun deleteLevel(levelId: Long) = Unit
        override suspend fun saveRubricAssessment(studentId: Long, evaluationId: Long, criterionId: Long, levelId: Long, updatedAtEpochMs: Long, deviceId: String?, syncVersion: Long): Double? = 0.0
        override suspend fun listRubricAssessments(studentId: Long, evaluationId: Long): List<RubricAssessment> = emptyList()
        override suspend fun getStudentEvaluation(studentId: Long, rubricId: Long, evaluationId: Long): Map<Long, Long> = emptyMap()
        override suspend fun listCriteriaByRubric(rubricId: Long): List<RubricCriterion> = emptyMap<Long, Long>().let { emptyList() }
        override suspend fun listLevelsByCriterion(criterionId: Long): List<RubricLevel> = emptyList()
    }

    private class FakeStudentsRepository(val students: List<Student> = emptyList()) : StudentsRepository {
        override fun observeStudents(): Flow<List<Student>> = flowOf(students)
        override suspend fun listStudents(): List<Student> = students
        suspend fun getStudent(id: Long): Student? = students.find { it.id == id }
        override suspend fun saveStudent(id: Long?, firstName: String, lastName: String, email: String?, photoPath: String?, isInjured: Boolean, updatedAtEpochMs: Long, deviceId: String?, syncVersion: Long): Long = 1
        override suspend fun deleteStudent(studentId: Long) = Unit
    }

    private class FakeEvaluationsRepository : EvaluationsRepository {
        override fun observeClassEvaluations(classId: Long): Flow<List<Evaluation>> = flowOf(emptyList())
        override suspend fun listClassEvaluations(classId: Long): List<Evaluation> = emptyList()
        override suspend fun getEvaluation(evaluationId: Long): Evaluation? = Evaluation(evaluationId, 1, "EVAL", "Eval", "RBC", 1.0, rubricId = 1)
        override suspend fun saveEvaluation(id: Long?, classId: Long, code: String, name: String, type: String, weight: Double, formula: String?, rubricId: Long?, description: String?, authorUserId: Long?, createdAtEpochMs: Long, updatedAtEpochMs: Long, associatedGroupId: Long?, deviceId: String?, syncVersion: Long): Long = 1
        override suspend fun deleteEvaluation(evaluationId: Long) = Unit
        override suspend fun saveEvaluationCompetencyLink(id: Long?, evaluationId: Long, competencyId: Long, weight: Double, authorUserId: Long?): Long = 1
        override suspend fun listEvaluationCompetencyLinks(evaluationId: Long): List<EvaluationCompetencyLink> = emptyList()
    }

    private class FakeGradesRepository : GradesRepository {
        override suspend fun saveGrade(
            id: Long?,
            classId: Long,
            studentId: Long,
            columnId: String,
            evaluationId: Long?,
            value: Double?,
            evidence: String?,
            evidencePath: String?,
            rubricSelections: String?,
            createdAtEpochMs: Long,
            updatedAtEpochMs: Long,
            deviceId: String?,
            syncVersion: Long,
        ): Long = 1
        override suspend fun listGradesForClass(classId: Long): List<Grade> = emptyList()
        override suspend fun listGradesForStudentInClass(studentId: Long, classId: Long): List<Grade> = emptyList()
        override fun observeGradesForClass(classId: Long): Flow<List<Grade>> = flowOf(emptyList())
        override suspend fun upsertGrade(
            classId: Long,
            studentId: Long,
            columnId: String,
            evaluationId: Long?,
            value: Double?,
            evidence: String?,
            evidencePath: String?,
            rubricSelections: String?,
            updatedAtEpochMs: Long,
            deviceId: String?,
            syncVersion: Long,
        ) = Unit
    }

    private class FakeNotebookRepository : NotebookRepository {
        override suspend fun loadNotebookSnapshot(classId: Long): NotebookSheet = NotebookSheet(
            classId = classId,
            tabs = emptyList(),
            columns = emptyList(),
            rows = emptyList()
        )
        override fun observeStudentChanges(classId: Long): Flow<List<Student>> = flowOf(emptyList())
        override fun observeGradesForClass(classId: Long): Flow<List<Grade>> = flowOf(emptyList())
        override suspend fun addStudent(classId: Long, firstName: String, lastName: String, isInjured: Boolean): Student = Student(1, firstName, lastName, isInjured = isInjured)
        override suspend fun removeStudent(classId: Long, studentId: Long) = Unit
        override suspend fun listStudentsInClass(classId: Long): List<Student> = emptyList()
        override suspend fun saveGrade(classId: Long, studentId: Long, columnId: String, evaluationId: Long?, value: Double?): Long = 1
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
        override suspend fun saveWorkGroup(classId: Long, workGroup: NotebookWorkGroup): Long = 1
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
        override suspend fun createTab(classId: Long, tabName: String): String = ""
        override suspend fun addColumnToTab(classId: Long, tabName: String, columnName: String, columnType: NotebookColumnType, rubricId: Long?): String = ""
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
}
