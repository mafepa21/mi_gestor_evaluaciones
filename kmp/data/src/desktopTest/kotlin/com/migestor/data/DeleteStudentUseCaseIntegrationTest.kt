package com.migestor.data

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DeleteStudentUseCaseIntegrationTest {
    private fun newContainer(): KmpContainer {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        return KmpContainer(driver)
    }

    @Test
    fun quitarDeUnCursoConservaLaFichaYElOtroCurso() = runTest {
        val container = newContainer()
        val studentId = container.studentsRepository.saveStudent(firstName = "Ana", lastName = "López")
        val classA = container.classesRepository.saveClass(name = "1º A", course = 1)
        val classB = container.classesRepository.saveClass(name = "1º B", course = 1)
        container.classesRepository.addStudentToClass(classA, studentId)
        container.classesRepository.addStudentToClass(classB, studentId)

        val result = container.deleteStudent.execute(studentId, classId = classA)

        assertTrue(result.isSuccess)
        assertNotNull(container.studentsRepository.getStudent(studentId))
        assertEquals(emptyList(), container.classesRepository.listStudentsInClass(classA).map { it.id })
        assertEquals(listOf(studentId), container.classesRepository.listStudentsInClass(classB).map { it.id })
    }

    @Test
    fun sinCursoNiOrdenExplicitaNoBorraLaFicha() = runTest {
        val container = newContainer()
        val studentId = container.studentsRepository.saveStudent(firstName = "Ana", lastName = "López")

        val result = container.deleteStudent.execute(studentId)

        assertTrue(result.isFailure)
        assertNotNull(container.studentsRepository.getStudent(studentId))
    }

    @Test
    fun ordenExplicitaBorraLaFicha() = runTest {
        val container = newContainer()
        val studentId = container.studentsRepository.saveStudent(firstName = "Ana", lastName = "López")

        val result = container.deleteStudent.execute(studentId, deleteEverywhere = true)

        assertTrue(result.isSuccess)
        assertNull(container.studentsRepository.getStudent(studentId))
    }
}
