package com.migestor.shared

import com.migestor.shared.domain.Evaluation
import com.migestor.shared.domain.Grade
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookTab
import com.migestor.shared.domain.SchoolClass
import com.migestor.shared.domain.Student
import com.migestor.shared.domain.PersistedNotebookCell
import com.migestor.shared.repository.ClassesRepository
import com.migestor.shared.repository.EvaluationsRepository
import com.migestor.shared.repository.GradesRepository
import com.migestor.shared.repository.NotebookCellsRepository
import com.migestor.shared.usecase.BuildNotebookSheetUseCase
import com.migestor.shared.usecase.GetNotebookUseCase
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

class BuildNotebookSheetUseCaseTest {
    @Test
    fun `applies calculated columns and preserves tabs`() = runTest {
        val classId = 1L
        val student = Student(id = 1, firstName = "Ana", lastName = "López")
        val evaluations = listOf(
            Evaluation(id = 11, classId = classId, code = "EX1", name = "Examen", type = "EX", weight = 0.5),
            Evaluation(id = 12, classId = classId, code = "TA1", name = "Tarea", type = "HW", weight = 0.5),
        )
        val grades = listOf(
            Grade(id = 1, classId = classId, studentId = 1, columnId = "eval_11", evaluationId = 11, value = 6.0),
            Grade(id = 2, classId = classId, studentId = 1, columnId = "eval_12", evaluationId = 12, value = 8.0),
        )

        val getNotebook = GetNotebookUseCase(
            classesRepository = FakeClassesRepository2(student, classId),
            evaluationsRepository = FakeEvaluationsRepository2(evaluations),
            gradesRepository = FakeGradesRepository2(grades),
            notebookCellsRepository = FakeNotebookCellsRepository2()
        )
        val useCase = BuildNotebookSheetUseCase(getNotebook)

        val tabs = listOf(
            NotebookTab(id = "eval", title = "Evaluación", order = 0),
            NotebookTab(id = "contenido", title = "Bloques", order = 1),
        )
        val columns = listOf(
            NotebookColumnDefinition(
                id = "calc_final",
                title = "Final",
                type = NotebookColumnType.CALCULATED,
                formula = "ROUND((EX1 * 0.4) + (TA1 * 0.6), 2)",
                tabIds = listOf("eval"),
                order = 2,
                widthDp = 160.0,
            ),
            NotebookColumnDefinition(
                id = "notes",
                title = "Notas",
                type = NotebookColumnType.TEXT,
                tabIds = listOf("contenido"),
                order = 4,
                widthDp = 180.0,
            ),
        )

        val sheet = useCase.build(classId, evaluations, listOf(student), tabs, columns)

        assertEquals(2, sheet.tabs.size)
        assertEquals("Evaluación", sheet.tabs.first().title)
        assertEquals(4, sheet.columns.size)
        assertEquals("notes", sheet.columns.last().id)
        assertEquals(180.0, sheet.columns.last().widthDp)
        assertNotNull(sheet.rows.first().weightedAverage)
        assertEquals(7.2, sheet.rows.first().weightedAverage)
    }

    @Test
    fun `keeps configured evaluation columns when evaluation is missing from snapshot`() = runTest {
        val classId = 1L
        val student = Student(id = 1, firstName = "Ana", lastName = "Lopez")
        val evaluations = emptyList<Evaluation>()

        val getNotebook = GetNotebookUseCase(
            classesRepository = FakeClassesRepository2(student, classId),
            evaluationsRepository = FakeEvaluationsRepository2(evaluations),
            gradesRepository = FakeGradesRepository2(emptyList()),
            notebookCellsRepository = FakeNotebookCellsRepository2()
        )
        val useCase = BuildNotebookSheetUseCase(getNotebook)

        val tabs = listOf(
            NotebookTab(id = "tab_1", title = "Evaluacion", order = 0),
        )
        val configuredColumns = listOf(
            NotebookColumnDefinition(
                id = "eval_99",
                title = "Examen remoto",
                type = NotebookColumnType.NUMERIC,
                evaluationId = 99L,
                tabIds = listOf("tab_1"),
            ),
        )

        val sheet = useCase.build(classId, evaluations, listOf(student), tabs, configuredColumns)
        assertEquals(1, sheet.columns.size)
        assertEquals("eval_99", sheet.columns.first().id)
        assertEquals(99L, sheet.columns.first().evaluationId)
    }

    @Test
    fun `ignores columns that do not count toward average`() = runTest {
        val classId = 1L
        val student = Student(id = 1, firstName = "Ana", lastName = "López")
        val evaluations = listOf(
            Evaluation(id = 11, classId = classId, code = "EX1", name = "Examen", type = "EX", weight = 0.5),
            Evaluation(id = 12, classId = classId, code = "TA1", name = "Tarea", type = "HW", weight = 0.5),
        )
        val grades = listOf(
            Grade(id = 1, classId = classId, studentId = 1, columnId = "eval_11", evaluationId = 11, value = 6.0),
            Grade(id = 2, classId = classId, studentId = 1, columnId = "eval_12", evaluationId = 12, value = 8.0),
        )

        val getNotebook = GetNotebookUseCase(
            classesRepository = FakeClassesRepository2(student, classId),
            evaluationsRepository = FakeEvaluationsRepository2(evaluations),
            gradesRepository = FakeGradesRepository2(grades),
            notebookCellsRepository = FakeNotebookCellsRepository2()
        )
        val useCase = BuildNotebookSheetUseCase(getNotebook)

        val tabs = listOf(NotebookTab(id = "eval", title = "Evaluación", order = 0))
        val configuredColumns = listOf(
            NotebookColumnDefinition(
                id = "eval_11",
                title = "Examen",
                type = NotebookColumnType.NUMERIC,
                evaluationId = 11L,
                tabIds = listOf("eval"),
                countsTowardAverage = false,
            ),
            NotebookColumnDefinition(
                id = "eval_12",
                title = "Tarea",
                type = NotebookColumnType.NUMERIC,
                evaluationId = 12L,
                tabIds = listOf("eval"),
                countsTowardAverage = true,
            ),
        )

        val sheet = useCase.build(classId, evaluations, listOf(student), tabs, configuredColumns)

        assertEquals(8.0, sheet.rows.first().weightedAverage)
    }
}

private class FakeClassesRepository2(
    private val student: Student,
    private val classId: Long,
) : ClassesRepository {
    override fun observeClasses(): Flow<List<SchoolClass>> = flowOf(emptyList())
    override fun observeStudentsInClass(classId: Long): Flow<List<Student>> {
        if (classId == this.classId) return flowOf(listOf(student))
        return flowOf(emptyList())
    }
    override suspend fun listClasses(): List<SchoolClass> = emptyList()
    override suspend fun saveClass(id: Long?, name: String, course: Int, description: String?, updatedAtEpochMs: Long, deviceId: String?, syncVersion: Long): Long = 1
    override suspend fun deleteClass(classId: Long) = Unit
    override suspend fun addStudentToClass(classId: Long, studentId: Long) = Unit
    override suspend fun removeStudentFromClass(classId: Long, studentId: Long) = Unit
    override suspend fun listStudentsInClass(classId: Long): List<Student> = if (classId == this.classId) listOf(student) else emptyList()
}

private class FakeEvaluationsRepository2(
    private val evaluations: List<Evaluation>,
) : EvaluationsRepository {
    override fun observeClassEvaluations(classId: Long): Flow<List<Evaluation>> = flowOf(evaluations)
    override suspend fun listClassEvaluations(classId: Long): List<Evaluation> = evaluations
    override suspend fun getEvaluation(evaluationId: Long): Evaluation? = evaluations.find { it.id == evaluationId }
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

private class FakeGradesRepository2(
    private val grades: List<Grade>,
) : GradesRepository {
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

    override suspend fun listGradesForClass(classId: Long): List<Grade> = grades

    override suspend fun listGradesForStudentInClass(studentId: Long, classId: Long): List<Grade> {
        return grades.filter { it.studentId == studentId }
    }
    override fun observeGradesForClass(classId: Long): Flow<List<Grade>> = flowOf(grades)
    
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

private class FakeNotebookCellsRepository2 : NotebookCellsRepository {
    override fun observeClassCells(classId: Long): Flow<List<PersistedNotebookCell>> = flowOf(emptyList())
    override suspend fun listClassCells(classId: Long): List<PersistedNotebookCell> = emptyList()
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
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ) = Unit
}
