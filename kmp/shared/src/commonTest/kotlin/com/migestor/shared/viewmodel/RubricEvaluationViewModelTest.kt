package com.migestor.shared.viewmodel

import com.migestor.shared.domain.*
import com.migestor.shared.repository.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull


@OptIn(ExperimentalCoroutinesApi::class)
class RubricEvaluationViewModelTest {

    private val testRubricId = 1L

    @Test
    fun `calculates total score with criterion weights when provided`() = runTest {
        val rubricDetail = RubricDetail(
            rubric = Rubric(id = testRubricId, name = "Test"),
            criteria = listOf(
                RubricCriterionWithLevels(
                    criterion = RubricCriterion(id = 1, rubricId = testRubricId, description = "C1", weight = 3.0, order = 0),
                    levels = (1L..10L).map { levelId ->
                        RubricLevel(id = 10 + levelId, criterionId = 1, name = "L1.$levelId", points = 0, order = levelId.toInt())
                    }
                ),
                RubricCriterionWithLevels(
                    criterion = RubricCriterion(id = 2, rubricId = testRubricId, description = "C2", weight = 1.0, order = 1),
                    levels = (1L..2L).map { levelId ->
                        RubricLevel(id = 20 + levelId, criterionId = 2, name = "L2.$levelId", points = 0, order = levelId.toInt())
                    }
                )
            )
        )

        assertEquals(8.75, rubricDetail.calculateScore(mapOf(1L to 20L, 2L to 21L)))
        assertEquals(10.0, rubricDetail.calculateScore(mapOf(1L to 20L, 2L to 22L)))
    }

    @Test
    fun `partial rubric score is scaled over evaluated criteria only`() = runTest {
        val rubricDetail = RubricDetail(
            rubric = Rubric(id = testRubricId, name = "Test"),
            criteria = (1L..4L).map { criterionId ->
                RubricCriterionWithLevels(
                    criterion = RubricCriterion(id = criterionId, rubricId = testRubricId, description = "C$criterionId", weight = 1.0, order = criterionId.toInt()),
                    levels = listOf(
                        RubricLevel(id = criterionId * 10 + 1, criterionId = criterionId, name = "Inicial", points = 1, order = 1),
                        RubricLevel(id = criterionId * 10 + 2, criterionId = criterionId, name = "Excelente", points = 4, order = 2)
                    )
                )
            }
        )

        assertEquals(10.0, rubricDetail.calculateScore(mapOf(1L to 12L, 2L to 22L, 3L to 32L)))
    }

    @Test
    fun `calculates user example 3 criteria 4 levels each`() = runTest {
        val rubricDetail = RubricDetail(
            rubric = Rubric(id = testRubricId, name = "Test"),
            criteria = (1L..3L).map { criterionId ->
                RubricCriterionWithLevels(
                    criterion = RubricCriterion(id = criterionId, rubricId = testRubricId, description = "C$criterionId", weight = 1.0, order = criterionId.toInt()),
                    levels = (1L..4L).map { levelId ->
                        RubricLevel(id = criterionId * 10 + levelId, criterionId = criterionId, name = "L$criterionId.$levelId", points = 0, order = levelId.toInt())
                    }
                )
            }
        )

        assertEquals(10.0, rubricDetail.calculateScore(mapOf(1L to 14L, 2L to 24L, 3L to 34L)))
        assertEquals(5.0, rubricDetail.calculateScore(mapOf(1L to 12L, 2L to 23L, 3L to 31L)))
    }

    @Test
    fun `loadForNotebookCell loads state successfully and calculates score`() = runTest {
        val rubricDetail = RubricDetail(
            rubric = Rubric(id = testRubricId, name = "Test Rubric"),
            criteria = listOf(
                RubricCriterionWithLevels(
                    criterion = RubricCriterion(id = 1, rubricId = testRubricId, description = "C1", weight = 1.0, order = 0),
                    levels = listOf(
                        RubricLevel(id = 11, criterionId = 1, name = "L1.1", points = 1, order = 1),
                        RubricLevel(id = 12, criterionId = 1, name = "L1.2", points = 4, order = 2)
                    )
                )
            )
        )

        val fakeRubrics = object : FakeRubricEvalRubricsRepository() {
            override suspend fun getRubricDetail(rubricId: Long): RubricDetail? = rubricDetail
            override suspend fun listRubricAssessments(studentId: Long, evaluationId: Long): List<RubricAssessment> = emptyList()
        }

        val fakeStudents = object : FakeRubricEvalStudentsRepository() {
            override suspend fun getStudent(studentId: Long): Student? = Student(id = studentId, firstName = "Juan", lastName = "Perez")
        }

        val fakeEvaluations = object : FakeRubricEvalEvaluationsRepository() {
            override suspend fun getEvaluation(evaluationId: Long): Evaluation? = Evaluation(id = evaluationId, classId = 100L, code = "E1", name = "Eval 1", type = "RUBRIC", weight = 1.0)
        }

        val fakeNotebook = object : FakeRubricEvalNotebookRepository() {
            override suspend fun getGradeForColumn(studentId: Long, columnId: String): Grade? = Grade(
                id = 1L, classId = 100L, studentId = studentId, columnId = columnId, evaluationId = 1L,
                value = 4.0, rubricSelections = "1:12"
            )
        }

        val viewModel = RubricEvaluationViewModel(
            rubricsRepository = fakeRubrics,
            studentsRepository = fakeStudents,
            evaluationsRepository = fakeEvaluations,
            gradesRepository = FakeRubricEvalGradesRepository(),
            notebookRepository = fakeNotebook,
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        )

        viewModel.loadForNotebookCell(studentId = 5L, columnId = "col_1", rubricId = testRubricId, evaluationId = 2L)
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertEquals("Juan Perez", state.studentName)
        assertEquals("Test Rubric", state.rubricName)
        assertNotNull(state.rubricDetail)
        assertEquals(10.0, state.totalScore)
        assertEquals(12L, state.selectedLevels[1L])
    }
}

open class FakeRubricEvalRubricsRepository : RubricsRepository {
    override fun observeRubrics(): Flow<List<RubricDetail>> = flowOf(emptyList())
    override suspend fun listRubrics(): List<RubricDetail> = emptyList()
    override suspend fun saveRubric(id: Long?, name: String, description: String?, classId: Long?, teachingUnitId: Long?, createdAtEpochMs: Long, updatedAtEpochMs: Long, deviceId: String?, syncVersion: Long): Long = 0L
    override suspend fun deleteRubric(rubricId: Long) = Unit
    override suspend fun saveCriterion(id: Long?, rubricId: Long, description: String, weight: Double, order: Int, updatedAtEpochMs: Long, deviceId: String?, syncVersion: Long): Long = 0L
    override suspend fun deleteCriterion(criterionId: Long) = Unit
    override suspend fun saveLevel(id: Long?, criterionId: Long, name: String, points: Int, description: String?, order: Int, updatedAtEpochMs: Long, deviceId: String?, syncVersion: Long): Long = 0L
    override suspend fun deleteLevel(levelId: Long) = Unit
    override suspend fun saveRubricAssessment(studentId: Long, evaluationId: Long, criterionId: Long, levelId: Long, updatedAtEpochMs: Long, deviceId: String?, syncVersion: Long): Double? = null
    override suspend fun listRubricAssessments(studentId: Long, evaluationId: Long): List<RubricAssessment> = emptyList()
    override suspend fun getStudentEvaluation(studentId: Long, rubricId: Long, evaluationId: Long): Map<Long, Long> = emptyMap()
    override suspend fun listCriteriaByRubric(rubricId: Long): List<RubricCriterion> = emptyList()
    override suspend fun listLevelsByCriterion(criterionId: Long): List<RubricLevel> = emptyList()
}

open class FakeRubricEvalStudentsRepository : StudentsRepository {
    override fun observeStudents(): Flow<List<Student>> = flowOf(emptyList())
    override suspend fun listStudents(): List<Student> = emptyList()
    override suspend fun getStudent(studentId: Long): Student? = null
    override suspend fun saveStudent(id: Long?, firstName: String, lastName: String, email: String?, photoPath: String?, isInjured: Boolean, sex: StudentSex, sexSource: StudentSexSource, birthDate: LocalDate?, updatedAtEpochMs: Long, deviceId: String?, syncVersion: Long): Long = 0L
    override suspend fun deleteStudent(studentId: Long) = Unit
}

open class FakeRubricEvalEvaluationsRepository : EvaluationsRepository {
    override fun observeClassEvaluations(classId: Long): Flow<List<Evaluation>> = flowOf(emptyList())
    override suspend fun listClassEvaluations(classId: Long): List<Evaluation> = emptyList()
    override suspend fun getEvaluation(evaluationId: Long): Evaluation? = null
    override suspend fun saveEvaluation(id: Long?, classId: Long, code: String, name: String, type: String, weight: Double, formula: String?, rubricId: Long?, description: String?, authorUserId: Long?, createdAtEpochMs: Long, updatedAtEpochMs: Long, associatedGroupId: Long?, deviceId: String?, syncVersion: Long): Long = 0L
    override suspend fun deleteEvaluation(evaluationId: Long) = Unit
    override suspend fun saveEvaluationCompetencyLink(id: Long?, evaluationId: Long, competencyId: Long, weight: Double, authorUserId: Long?): Long = 0L
    override suspend fun listEvaluationCompetencyLinks(evaluationId: Long): List<EvaluationCompetencyLink> = emptyList()
}

open class FakeRubricEvalGradesRepository : GradesRepository {
    override fun observeGradesForClass(classId: Long): Flow<List<Grade>> = flowOf(emptyList())
    override suspend fun listGradesForClass(classId: Long): List<Grade> = emptyList()
    override suspend fun listGradesForStudentInClass(studentId: Long, classId: Long): List<Grade> = emptyList()
    override suspend fun saveGrade(id: Long?, classId: Long, studentId: Long, columnId: String, evaluationId: Long?, value: Double?, evidence: String?, evidencePath: String?, rubricSelections: String?, createdAtEpochMs: Long, updatedAtEpochMs: Long, deviceId: String?, syncVersion: Long): Long = 0L
    override suspend fun upsertGrade(classId: Long, studentId: Long, columnId: String, evaluationId: Long?, value: Double?, evidence: String?, evidencePath: String?, rubricSelections: String?, updatedAtEpochMs: Long, deviceId: String?, syncVersion: Long) = Unit
}

open class FakeRubricEvalNotebookRepository : NotebookRepository {
    override suspend fun loadNotebookSnapshot(classId: Long): NotebookSheet = NotebookSheet(classId = classId, tabs = emptyList(), columns = emptyList(), rows = emptyList())
    override fun observeStudentChanges(classId: Long): Flow<List<Student>> = flowOf(emptyList())
    override fun observeGradesForClass(classId: Long): Flow<List<Grade>> = flowOf(emptyList())
    override suspend fun addStudent(classId: Long, firstName: String, lastName: String, isInjured: Boolean): Student = Student(0L, firstName, lastName, isInjured = isInjured)
    override suspend fun removeStudent(classId: Long, studentId: Long) = Unit
    override suspend fun listStudentsInClass(classId: Long): List<Student> = emptyList()
    override suspend fun saveGrade(classId: Long, studentId: Long, columnId: String, evaluationId: Long?, value: Double?): Long = 0L
    override suspend fun saveTab(classId: Long, tab: NotebookTab) = Unit
    override suspend fun deleteTab(tabId: String) = Unit
    override suspend fun saveColumn(classId: Long, column: NotebookColumnDefinition) = Unit
    override suspend fun saveAverageConfiguration(classId: Long, updates: List<NotebookAverageColumnConfig>) = Unit
    override suspend fun previewDeleteColumn(classId: Long, columnId: String): NotebookDeletionImpact = NotebookDeletionImpact(columnId, columnId, NotebookDeletionTargetKind.COLUMN, 0, 0, 0, 0, false)
    override suspend fun deleteColumn(columnId: String) = Unit
    override suspend fun listColumnCategories(classId: Long, tabId: String?): List<NotebookColumnCategory> = emptyList()
    override suspend fun saveColumnCategory(classId: Long, category: NotebookColumnCategory) = Unit
    override suspend fun previewDeleteColumnCategory(classId: Long, categoryId: String): NotebookDeletionImpact = NotebookDeletionImpact(categoryId, categoryId, NotebookDeletionTargetKind.CATEGORY, 0, 0, 0, 0, false)
    override suspend fun deleteColumnCategory(classId: Long, categoryId: String, preserveColumns: Boolean) = Unit
    override suspend fun toggleCategoryCollapsed(classId: Long, categoryId: String, isCollapsed: Boolean) = Unit
    override suspend fun reorderCategory(classId: Long, tabId: String, categoryId: String, targetCategoryId: String) = Unit
    override suspend fun assignColumnToCategory(classId: Long, columnId: String, categoryId: String?) = Unit
    override suspend fun deleteEvaluation(evaluationId: Long) = Unit
    override suspend fun duplicateConfigToClass(sourceClassId: Long, targetClassId: Long) = Unit
    override suspend fun listWorkGroups(classId: Long, tabId: String?): List<NotebookWorkGroup> = emptyList()
    override suspend fun saveWorkGroup(classId: Long, workGroup: NotebookWorkGroup): Long = 0L
    override suspend fun deleteWorkGroup(groupId: Long) = Unit
    override suspend fun listWorkGroupMembers(classId: Long, tabId: String?): List<NotebookWorkGroupMember> = emptyList()
    override suspend fun assignStudentsToWorkGroup(classId: Long, tabId: String, groupId: Long, studentIds: List<Long>) = Unit
    override suspend fun clearStudentsFromWorkGroup(classId: Long, tabId: String, studentIds: List<Long>) = Unit
    override suspend fun saveCell(classId: Long, studentId: Long, columnId: String, textValue: String?, boolValue: Boolean?, iconValue: String?, ordinalValue: String?, note: String?, colorHex: String?, attachmentUris: List<String>, authorUserId: Long?, associatedGroupId: Long?) = Unit
    override suspend fun getTabNamesForClass(classId: Long): List<String> = emptyList()
    override suspend fun createTab(classId: Long, tabName: String): String = ""
    override suspend fun addColumnToTab(classId: Long, tabName: String, columnName: String, columnType: NotebookColumnType, rubricId: Long?): String = ""
    override suspend fun getNotebookConfig(classId: Long): NotebookConfig = NotebookConfig(classId, emptyList(), emptyList())
    override suspend fun getGradeForColumn(studentId: Long, columnId: String): Grade? = null
    override suspend fun getColumnIdForEvaluation(evaluationId: Long): String? = null
    override suspend fun upsertGrade(classId: Long, studentId: Long, columnId: String, evaluationId: Long?, numericValue: Double, rubricSelections: String?, evidence: String?, createdAtEpochMs: Long, updatedAtEpochMs: Long, deviceId: String?, syncVersion: Long) = Unit
    override fun observeCellAudit(classId: Long, studentId: Long, columnId: String): Flow<List<NotebookCellAuditEvent>> = flowOf(emptyList())
}
