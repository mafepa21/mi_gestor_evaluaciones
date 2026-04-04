package com.migestor.shared

import com.migestor.shared.domain.Evaluation
import com.migestor.shared.domain.Grade
import com.migestor.shared.domain.SchoolClass
import com.migestor.shared.domain.Student
import com.migestor.shared.domain.PersistedNotebookCell
import com.migestor.shared.repository.ClassesRepository
import com.migestor.shared.repository.EvaluationsRepository
import com.migestor.shared.repository.GradesRepository
import com.migestor.shared.repository.NotebookCellsRepository
import com.migestor.shared.usecase.GetNotebookUseCase
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals

class NotebookUseCaseTest {
    @Test
    fun `computes weighted average per student`() = runTest {
        val classId = 1L
        val student = Student(id = 7, firstName = "Ana", lastName = "López")
        val evaluations = listOf(
            Evaluation(id = 10, classId = classId, code = "EX1", name = "Examen 1", type = "Examen", weight = 0.4),
            Evaluation(id = 11, classId = classId, code = "EX2", name = "Examen 2", type = "Examen", weight = 0.6),
        )
        val grades = listOf(
            Grade(id = 1, classId = classId, studentId = student.id, columnId = "eval_10", evaluationId = 10, value = 8.0),
            Grade(id = 2, classId = classId, studentId = student.id, columnId = "eval_11", evaluationId = 11, value = 6.0),
        )

        val useCase = GetNotebookUseCase(
            classesRepository = FakeClassesRepository(student, classId),
            evaluationsRepository = FakeEvaluationsRepository(evaluations),
            gradesRepository = FakeGradesRepository(grades),
            notebookCellsRepository = FakeNotebookCellsRepository()
        )

        val result = useCase.invoke(classId)
        assertEquals(1, result.rows.size)
        assertEquals(6.8, result.rows.first().weightedAverage)
    }
}

private class FakeClassesRepository(
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

    override suspend fun listStudentsInClass(classId: Long): List<Student> {
        if (classId == this.classId) return listOf(student)
        return emptyList()
    }
}

private class FakeEvaluationsRepository(
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

private class FakeGradesRepository(
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

private class FakeNotebookCellsRepository : NotebookCellsRepository {
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
