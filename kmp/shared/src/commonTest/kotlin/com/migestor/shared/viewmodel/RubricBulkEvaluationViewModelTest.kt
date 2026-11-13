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

    @Test
    fun `bus events for a different notebook column sharing the same rubric are ignored`() = runTest {
        // Regresion: el colector de RubricEvaluationBus filtraba solo por rubricId. Una
        // misma rubrica vinculada a mas de una evaluacion/columna del cuaderno a la vez
        // hacia que un guardado individual en OTRA evaluacion (misma rubrica) se
        // mezclara en el estado de esta hoja masiva, y el siguiente auto-save volcara
        // esa mezcla en la columna equivocada.
        val testRubricId = 1L
        val studentId = 1L
        val rubricDetail = RubricDetail(rubric = Rubric(id = testRubricId, name = "Rubrica compartida"), criteria = emptyList())

        val fakeNotebook = object : FakeRubricEvalNotebookRepository() {
            override suspend fun listStudentsInClass(classId: Long): List<Student> =
                listOf(Student(id = studentId, firstName = "Ana", lastName = "Lopez"))
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

        // Esta hoja masiva esta evaluando la columna "col_eval1".
        viewModel.load(classId = 100L, evaluationId = 1L, rubricId = testRubricId, columnId = "col_eval1")
        advanceUntilIdle()

        // Llega un guardado individual de la MISMA rubrica pero en OTRA evaluacion/columna
        // ("col_eval2"), p. ej. desde el cuaderno de otra clase o pestana.
        RubricEvaluationBus.emit(
            RubricEvaluationSavedEvent(
                studentId = studentId,
                rubricId = testRubricId,
                selectedLevels = mapOf(99L to 999L),
                score = 7.0,
                columnId = "col_eval2",
            )
        )
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertTrue(
            state.assessments[studentId].isNullOrEmpty(),
            "Un evento de otra columna/evaluacion no debe mezclarse en el estado de esta hoja"
        )
    }

    @Test
    fun `load uses batch reads, keeps cell selections priority and does not grow with students`() = runTest {
        val rubricId = 1L
        val evaluationId = 10L
        val classId = 100L
        val columnId = "col_rubrica"
        val rubricDetail = RubricDetail(
            rubric = Rubric(id = rubricId, name = "Rubrica"),
            criteria = listOf(
                RubricCriterionWithLevels(
                    criterion = RubricCriterion(id = 1, rubricId = rubricId, description = "C1", weight = 1.0, order = 0),
                    levels = listOf(
                        RubricLevel(id = 11, criterionId = 1, name = "L1.1", points = 1, order = 1),
                        RubricLevel(id = 12, criterionId = 1, name = "L1.2", points = 4, order = 2)
                    )
                ),
                RubricCriterionWithLevels(
                    criterion = RubricCriterion(id = 2, rubricId = rubricId, description = "C2", weight = 1.0, order = 1),
                    levels = listOf(
                        RubricLevel(id = 21, criterionId = 2, name = "L2.1", points = 1, order = 1),
                        RubricLevel(id = 22, criterionId = 2, name = "L2.2", points = 4, order = 2)
                    )
                )
            )
        )

        // Alumno 1: la celda trae selecciones (mandan sobre las valoraciones).
        // Alumno 2: sin selecciones en la celda; solo valoraciones de la evaluación.
        // Alumno 3: nada (solo una valoración de otra evaluación, que no cuenta).
        val grades = listOf(
            Grade(id = 1, classId = classId, studentId = 1, columnId = columnId, evaluationId = evaluationId, value = 10.0, rubricSelections = "1:12,2:22"),
            Grade(id = 2, classId = classId, studentId = 2, columnId = columnId, evaluationId = evaluationId, value = null, rubricSelections = ""),
            Grade(id = 3, classId = classId, studentId = 3, columnId = "otra", evaluationId = 99, value = 5.0, rubricSelections = "1:11"),
        )
        val assessments = listOf(
            RubricAssessment(studentId = 1, evaluationId = evaluationId, criterionId = 1, levelId = 11),
            RubricAssessment(studentId = 2, evaluationId = evaluationId, criterionId = 1, levelId = 11),
            RubricAssessment(studentId = 2, evaluationId = evaluationId, criterionId = 2, levelId = 21),
            // Criterio de otra rúbrica en la misma evaluación: getStudentEvaluation no lo devolvía.
            RubricAssessment(studentId = 2, evaluationId = evaluationId, criterionId = 99, levelId = 991),
            RubricAssessment(studentId = 3, evaluationId = 77, criterionId = 1, levelId = 12),
        )
        val column = NotebookColumnDefinition(
            id = columnId,
            title = "Rubrica",
            type = NotebookColumnType.RUBRIC,
            evaluationId = evaluationId,
            rubricId = rubricId
        )

        suspend fun loadWith(studentCount: Int): Pair<BulkRubricEvaluationUiState, Map<String, Int>> {
            val calls = mutableMapOf<String, Int>()
            fun count(name: String) { calls[name] = (calls[name] ?: 0) + 1 }
            val students = (1L..studentCount.toLong()).map { Student(id = it, firstName = "A$it", lastName = "B$it") }

            val notebook = object : FakeRubricEvalNotebookRepository() {
                override suspend fun listStudentsInClass(classId: Long): List<Student> { count("listStudentsInClass"); return students }
                override suspend fun getNotebookConfig(classId: Long): NotebookConfig {
                    count("getNotebookConfig"); return NotebookConfig(classId, emptyList(), listOf(column))
                }
                override suspend fun getGradeForColumn(studentId: Long, columnId: String): Grade? { count("getGradeForColumn"); return null }
                override suspend fun listWorkGroups(classId: Long, tabId: String?): List<NotebookWorkGroup> { count("listWorkGroups"); return emptyList() }
                override suspend fun listWorkGroupMembers(classId: Long, tabId: String?): List<NotebookWorkGroupMember> { count("listWorkGroupMembers"); return emptyList() }
            }
            val rubrics = object : FakeRubricEvalRubricsRepository() {
                override suspend fun listRubrics(): List<RubricDetail> { count("listRubrics"); return listOf(rubricDetail) }
                override suspend fun getRubricDetail(rubricId: Long): RubricDetail? { count("getRubricDetail"); return rubricDetail }
                override suspend fun listRubricAssessments(studentId: Long, evaluationId: Long): List<RubricAssessment> {
                    count("listRubricAssessments"); return assessments.filter { it.studentId == studentId && it.evaluationId == evaluationId }
                }
                override suspend fun listRubricAssessmentsForStudents(studentIds: List<Long>, evaluationId: Long): List<RubricAssessment> {
                    count("listRubricAssessmentsForStudents"); return assessments.filter { it.studentId in studentIds && it.evaluationId == evaluationId }
                }
                override suspend fun getStudentEvaluation(studentId: Long, rubricId: Long, evaluationId: Long): Map<Long, Long> {
                    count("getStudentEvaluation"); return emptyMap()
                }
            }
            val gradesRepository = object : FakeRubricEvalGradesRepository() {
                override suspend fun listGradesForClass(classId: Long): List<Grade> { count("listGradesForClass"); return grades }
            }
            val viewModel = RubricBulkEvaluationViewModel(
                rubricsRepository = rubrics,
                studentsRepository = FakeRubricEvalStudentsRepository(),
                notebookRepository = notebook,
                gradesRepository = gradesRepository,
                scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
            )
            viewModel.load(classId = classId, evaluationId = evaluationId, rubricId = rubricId, columnId = columnId)
            advanceUntilIdle()
            return viewModel.uiState.value to calls
        }

        val (state, callsFor3) = loadWith(3)
        assertEquals(null, state.error)
        assertEquals(
            mapOf(1L to mapOf(1L to 12L, 2L to 22L), 2L to mapOf(1L to 11L, 2L to 21L)),
            state.assessments
        )
        fun expectedScore(levels: Map<Long, Long>) = kotlin.math.round(rubricDetail.calculateScore(levels) * 100) / 100.0
        assertEquals(
            mapOf(1L to expectedScore(mapOf(1L to 12L, 2L to 22L)), 2L to expectedScore(mapOf(1L to 11L, 2L to 21L))),
            state.scores
        )

        // Ninguna lectura por alumno y el mismo número de lecturas con 3 que con 30 alumnos.
        assertEquals(null, callsFor3["getGradeForColumn"])
        assertEquals(null, callsFor3["getStudentEvaluation"])
        assertEquals(null, callsFor3["listRubricAssessments"])
        assertEquals(null, callsFor3["listRubrics"])
        val (_, callsFor30) = loadWith(30)
        assertEquals(callsFor3, callsFor30)
    }
}
