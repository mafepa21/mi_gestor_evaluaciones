package com.migestor.shared.viewmodel

import com.migestor.shared.domain.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class RubricBulkEvaluationViewModelTest {
    @Test
    fun `bulk rubric evaluation state exposes default passing threshold`() {
        assertEquals(5.0, BulkRubricEvaluationUiState().passingThreshold)
    }

    @Test
    fun `saveAll never reports success when a student's write fails`() = runTest {
        // Regresion: saveStudentEvaluation traga toda excepcion (solo pone
        // state.error), asi que saveAll no puede saber si algo fallo por una
        // excepcion propia; antes del fix marcaba isSaveSuccessful=true sin mas,
        // y RubricBulkEvaluationSheet observa isSaveSuccessful para autocerrarse
        // -la hoja se cerraria como si todo se hubiera guardado aunque un alumno
        // se hubiera perdido en silencio.
        val testRubricId = 1L
        val failingStudentId = 2L
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

        val fakeNotebook = object : FakeRubricEvalNotebookRepository() {
            override suspend fun listStudentsInClass(classId: Long): List<Student> = listOf(
                Student(id = 1L, firstName = "Ana", lastName = "Lopez"),
                Student(id = failingStudentId, firstName = "Luis", lastName = "Ruiz"),
            )
            override suspend fun getColumnIdForEvaluation(evaluationId: Long): String? = "col_1"
            override suspend fun upsertGrade(
                classId: Long, studentId: Long, columnId: String, evaluationId: Long?,
                numericValue: Double, rubricSelections: String?, evidence: String?,
                createdAtEpochMs: Long, updatedAtEpochMs: Long, deviceId: String?, syncVersion: Long
            ) {
                if (studentId == failingStudentId) throw Exception("disco lleno")
            }
        }
        val fakeRubrics = object : FakeRubricEvalRubricsRepository() {
            override suspend fun listRubrics(): List<RubricDetail> = listOf(rubricDetail)
        }

        val viewModel = RubricBulkEvaluationViewModel(
            rubricsRepository = fakeRubrics,
            studentsRepository = FakeRubricEvalStudentsRepository(),
            notebookRepository = fakeNotebook,
            gradesRepository = FakeRubricEvalGradesRepository(),
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        )

        viewModel.load(classId = 100L, evaluationId = 10L, rubricId = testRubricId, columnId = "col_1")
        advanceUntilIdle()

        viewModel.selectLevel(1L, criterionId = 1L, levelId = 12L)
        viewModel.selectLevel(failingStudentId, criterionId = 1L, levelId = 12L)

        viewModel.saveAll()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertEquals(false, state.isSaveSuccessful, "No debe reportar exito si algun alumno no se guardo")
        assertEquals(false, state.isSaving)
        assertNotNull(state.error, "Debe surgir un error explicando el fallo parcial")
        assertTrue(state.error!!.contains("1"), "El error debe indicar cuantos alumnos fallaron")
    }
}
