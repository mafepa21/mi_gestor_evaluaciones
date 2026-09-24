package com.migestor.shared.usecase

import com.migestor.shared.domain.SchoolClass
import com.migestor.shared.domain.Student
import com.migestor.shared.domain.StudentSex
import com.migestor.shared.domain.StudentSexSource
import com.migestor.shared.repository.ClassesRepository
import com.migestor.shared.repository.StudentsRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DeleteStudentUseCaseTest {
    @Test
    fun conCursoSoloQuitaDeEseCurso() = runTest {
        val students = FakeStudents()
        val classes = FakeClasses()
        students.students[7] = Student(id = 7, firstName = "Ana", lastName = "López")
        classes.members += 1L to 7L
        classes.members += 2L to 7L
        val useCase = DeleteStudentUseCase(students, classes)

        val result = useCase.execute(studentId = 7, classId = 1)

        assertTrue(result.isSuccess)
        assertEquals(listOf(1L to 7L), classes.removed)
        assertEquals(0, students.deleteCount)
        assertEquals(setOf(2L to 7L), classes.members)
        assertEquals("Ana", students.students[7]?.firstName)
    }

    @Test
    fun sinCursoNiOrdenNoBorraLaFicha() = runTest {
        val students = FakeStudents()
        val classes = FakeClasses()
        students.students[7] = Student(id = 7, firstName = "Ana", lastName = "López")
        val useCase = DeleteStudentUseCase(students, classes)

        val result = useCase.execute(studentId = 7)

        assertTrue(result.isFailure)
        assertEquals(0, students.deleteCount)
        assertEquals(emptyList(), classes.removed)
        assertEquals("Ana", students.students[7]?.firstName)
    }

    @Test
    fun ordenExplicitaBorraLaFicha() = runTest {
        val students = FakeStudents()
        val classes = FakeClasses()
        students.students[7] = Student(id = 7, firstName = "Ana", lastName = "López")
        val useCase = DeleteStudentUseCase(students, classes)

        val result = useCase.execute(studentId = 7, deleteEverywhere = true)

        assertTrue(result.isSuccess)
        assertEquals(1, students.deleteCount)
        assertNull(students.students[7])
        assertEquals(emptyList(), classes.removed)
    }
}

private class FakeStudents : StudentsRepository {
    val students = mutableMapOf<Long, Student>()
    var deleteCount = 0

    override fun observeStudents(): Flow<List<Student>> = emptyFlow()

    override suspend fun listStudents(): List<Student> = students.values.toList()

    override suspend fun saveStudent(
        id: Long?,
        firstName: String,
        lastName: String,
        email: String?,
        photoPath: String?,
        isInjured: Boolean,
        sex: StudentSex,
        sexSource: StudentSexSource,
        birthDate: LocalDate?,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): Long = error("no usado")

    override suspend fun deleteStudent(studentId: Long) {
        deleteCount += 1
        students.remove(studentId)
    }
}

private class FakeClasses : ClassesRepository {
    val members = mutableSetOf<Pair<Long, Long>>()
    val removed = mutableListOf<Pair<Long, Long>>()

    override fun observeClasses(): Flow<List<SchoolClass>> = emptyFlow()

    override fun observeStudentsInClass(classId: Long): Flow<List<Student>> = emptyFlow()

    override suspend fun listClasses(): List<SchoolClass> = emptyList()

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
    ): Long = error("no usado")

    override suspend fun deleteClass(classId: Long) = Unit

    override suspend fun addStudentToClass(classId: Long, studentId: Long) {
        members += classId to studentId
    }

    override suspend fun removeStudentFromClass(classId: Long, studentId: Long) {
        removed += classId to studentId
        members.remove(classId to studentId)
    }

    override suspend fun listStudentsInClass(classId: Long): List<Student> = emptyList()
}
