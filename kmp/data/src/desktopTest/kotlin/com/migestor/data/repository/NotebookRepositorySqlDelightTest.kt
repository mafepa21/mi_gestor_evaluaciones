package com.migestor.data.repository

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.shared.domain.NotebookColumnCategory
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.usecase.BuildNotebookSheetUseCase
import com.migestor.shared.usecase.GetNotebookUseCase
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class NotebookRepositorySqlDelightTest {
    @Test
    fun `upsertGrade treats zero evaluation id as missing and resolves from column`() = runTest {
        val fixture = createFixture()
        val classId = fixture.classes.saveClass(name = "3 ESO A", course = 3, description = null)
        val studentId = fixture.students.saveStudent(firstName = "Ana", lastName = "Lopez", email = null)
        fixture.classes.addStudentToClass(classId, studentId)
        val evaluationId = fixture.evaluations.saveEvaluation(
            classId = classId,
            code = "RUB1",
            name = "Rubrica 1",
            type = "Rubrica",
            weight = 1.0,
        )
        fixture.config.saveColumn(
            classId,
            NotebookColumnDefinition(
                id = "rubric_column",
                title = "Rubrica",
                type = NotebookColumnType.RUBRIC,
                evaluationId = evaluationId,
            )
        )

        fixture.notebook.upsertGrade(
            classId = classId,
            studentId = studentId,
            columnId = "rubric_column",
            evaluationId = 0L,
            numericValue = 8.0,
            rubricSelections = null,
            evidence = null,
            createdAtEpochMs = 1L,
            updatedAtEpochMs = 1L,
            deviceId = "test",
            syncVersion = 1L,
        )

        val grade = fixture.grades.listGradesForStudentInClass(studentId, classId).single()
        assertEquals(evaluationId, grade.evaluationId)
    }

    @Test
    fun `deleteColumnCategory with preserveColumns false removes category columns`() = runTest {
        val fixture = createFixture()
        val classId = fixture.classes.saveClass(name = "3 ESO B", course = 3, description = null)
        fixture.config.saveColumnCategory(
            classId,
            NotebookColumnCategory(
                id = "cat_eval",
                classId = classId,
                tabId = "TAB_1",
                name = "Evaluacion",
            )
        )
        fixture.config.saveColumn(
            classId,
            NotebookColumnDefinition(
                id = "col_in_category",
                title = "Dentro",
                type = NotebookColumnType.NUMERIC,
                categoryId = "cat_eval",
            )
        )
        fixture.config.saveColumn(
            classId,
            NotebookColumnDefinition(
                id = "col_outside",
                title = "Fuera",
                type = NotebookColumnType.NUMERIC,
            )
        )

        fixture.notebook.deleteColumnCategory(classId, "cat_eval", preserveColumns = false)

        val columns = fixture.config.listColumns(classId)
        assertNull(columns.firstOrNull { it.id == "col_in_category" })
        assertEquals("col_outside", columns.single().id)
        assertEquals(emptyList(), fixture.config.listColumnCategories(classId))
    }

    @Test
    fun `getGradeForColumn prefers evaluation id grade and falls back to legacy column id`() = runTest {
        val fixture = createFixture()
        val classId = fixture.classes.saveClass(name = "3 ESO C", course = 3, description = null)
        val studentId = fixture.students.saveStudent(firstName = "Luis", lastName = "Garcia", email = null)
        fixture.classes.addStudentToClass(classId, studentId)

        val evaluationId = fixture.evaluations.saveEvaluation(
            classId = classId,
            code = "EV1",
            name = "Evaluacion 1",
            type = "Examen",
            weight = 1.0,
        )
        fixture.config.saveColumn(
            classId,
            NotebookColumnDefinition(
                id = "configured_eval",
                title = "Configurada",
                type = NotebookColumnType.NUMERIC,
                evaluationId = evaluationId,
            )
        )
        fixture.grades.saveGrade(
            classId = classId,
            studentId = studentId,
            columnId = "configured_eval",
            evaluationId = null,
            value = 5.0,
        )
        fixture.grades.saveGrade(
            classId = classId,
            studentId = studentId,
            columnId = "eval_$evaluationId",
            evaluationId = evaluationId,
            value = 9.0,
        )

        val preferred = fixture.notebook.getGradeForColumn(studentId, "configured_eval")
        assertEquals(9.0, preferred?.value)
        assertEquals(evaluationId, preferred?.evaluationId)

        val legacyEvaluationId = fixture.evaluations.saveEvaluation(
            classId = classId,
            code = "EV2",
            name = "Evaluacion 2",
            type = "Examen",
            weight = 1.0,
        )
        fixture.config.saveColumn(
            classId,
            NotebookColumnDefinition(
                id = "legacy_configured_eval",
                title = "Legacy",
                type = NotebookColumnType.NUMERIC,
                evaluationId = legacyEvaluationId,
            )
        )
        fixture.grades.saveGrade(
            classId = classId,
            studentId = studentId,
            columnId = "legacy_configured_eval",
            evaluationId = null,
            value = 6.0,
        )

        val fallback = fixture.notebook.getGradeForColumn(studentId, "legacy_configured_eval")
        assertEquals(6.0, fallback?.value)
        assertNull(fallback?.evaluationId)
    }

    private fun createFixture(): Fixture {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)
        val students = StudentsRepositorySqlDelight(db)
        val classes = ClassesRepositorySqlDelight(db)
        val evaluations = EvaluationsRepositorySqlDelight(db)
        val config = NotebookConfigRepositorySqlDelight(db)
        val grades = GradesRepositorySqlDelight(db)
        val cells = NotebookCellsRepositorySqlDelight(db)
        val notebook = NotebookRepositorySqlDelight(
            db = db,
            studentsRepository = students,
            classesRepository = classes,
            evaluationsRepository = evaluations,
            notebookConfigRepository = config,
            buildNotebookSheetUseCase = BuildNotebookSheetUseCase(
                GetNotebookUseCase(classes, evaluations, grades, cells)
            ),
            gradesRepository = grades,
            notebookCellsRepository = cells,
        )
        return Fixture(students, classes, evaluations, config, grades, notebook)
    }

    private data class Fixture(
        val students: StudentsRepositorySqlDelight,
        val classes: ClassesRepositorySqlDelight,
        val evaluations: EvaluationsRepositorySqlDelight,
        val config: NotebookConfigRepositorySqlDelight,
        val grades: GradesRepositorySqlDelight,
        val notebook: NotebookRepositorySqlDelight,
    )
}
