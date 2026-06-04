package com.migestor.data.repository

import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.shared.domain.NotebookColumnCategory
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookInstrumentKind
import com.migestor.shared.domain.NotebookScaleKind
import com.migestor.shared.usecase.BuildNotebookSheetUseCase
import com.migestor.shared.usecase.GetNotebookUseCase
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class NotebookRepositorySqlDelightTest {
    @Test
    fun `upsertGrade keeps same student and column isolated by class`() = runTest {
        val fixture = createFixture()
        val studentId = fixture.students.saveStudent(firstName = "Ana", lastName = "Lopez", email = null)
        val classAId = fixture.classes.saveClass(name = "3 ESO A", course = 3, description = null)
        val classBId = fixture.classes.saveClass(name = "3 ESO B", course = 3, description = null)
        fixture.classes.addStudentToClass(classAId, studentId)
        fixture.classes.addStudentToClass(classBId, studentId)

        fixture.notebook.upsertGrade(
            classId = classAId,
            studentId = studentId,
            columnId = "shared_column",
            evaluationId = null,
            numericValue = 7.0,
            rubricSelections = null,
            evidence = null,
            createdAtEpochMs = 1L,
            updatedAtEpochMs = 1L,
            deviceId = "test",
            syncVersion = 1L,
        )
        fixture.notebook.upsertGrade(
            classId = classBId,
            studentId = studentId,
            columnId = "shared_column",
            evaluationId = null,
            numericValue = 9.0,
            rubricSelections = null,
            evidence = null,
            createdAtEpochMs = 2L,
            updatedAtEpochMs = 2L,
            deviceId = "test",
            syncVersion = 1L,
        )

        assertEquals(7.0, fixture.grades.listGradesForStudentInClass(studentId, classAId).single().value)
        assertEquals(9.0, fixture.grades.listGradesForStudentInClass(studentId, classBId).single().value)
    }

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
    fun `deleteColumn removes only grades for the column class`() = runTest {
        val fixture = createFixture()
        val studentId = fixture.students.saveStudent(firstName = "Marta", lastName = "Ruiz", email = null)
        val classAId = fixture.classes.saveClass(name = "4 ESO A", course = 4, description = null)
        val classBId = fixture.classes.saveClass(name = "4 ESO B", course = 4, description = null)
        fixture.classes.addStudentToClass(classAId, studentId)
        fixture.classes.addStudentToClass(classBId, studentId)
        fixture.config.saveColumn(
            classAId,
            NotebookColumnDefinition(
                id = "shared_column",
                title = "Prueba",
                type = NotebookColumnType.NUMERIC,
            )
        )
        fixture.grades.saveGrade(
            classId = classAId,
            studentId = studentId,
            columnId = "shared_column",
            evaluationId = null,
            value = 6.0,
        )
        fixture.grades.saveGrade(
            classId = classBId,
            studentId = studentId,
            columnId = "shared_column",
            evaluationId = null,
            value = 8.0,
        )

        fixture.notebook.deleteColumn("shared_column")

        assertEquals(emptyList(), fixture.grades.listGradesForStudentInClass(studentId, classAId))
        assertEquals(8.0, fixture.grades.listGradesForStudentInClass(studentId, classBId).single().value)
    }

    @Test
    fun `previewDeleteColumn reports grades formulas average participation and locked state`() = runTest {
        val fixture = createFixture()
        val classId = fixture.classes.saveClass(name = "4 ESO C", course = 4, description = null)
        val studentId = fixture.students.saveStudent(firstName = "Pablo", lastName = "Santos", email = null)
        fixture.classes.addStudentToClass(classId, studentId)
        fixture.config.saveColumn(
            classId,
            NotebookColumnDefinition(
                id = "col_exam",
                title = "Examen",
                type = NotebookColumnType.NUMERIC,
                isLocked = true,
            )
        )
        fixture.config.saveColumn(
            classId,
            NotebookColumnDefinition(
                id = "col_formula",
                title = "Formula",
                type = NotebookColumnType.CALCULATED,
                formula = "REDONDEAR([col_exam], 2)",
            )
        )
        fixture.grades.saveGrade(
            classId = classId,
            studentId = studentId,
            columnId = "col_exam",
            evaluationId = null,
            value = 7.0,
        )

        val impact = fixture.notebook.previewDeleteColumn(classId, "col_exam")

        assertEquals("col_exam", impact.targetId)
        assertEquals("Examen", impact.targetName)
        assertEquals(1, impact.affectedColumnCount)
        assertEquals(1, impact.affectedGradeCount)
        assertEquals(1, impact.affectedFormulaColumnCount)
        assertEquals(1, impact.affectedAverageColumnCount)
        assertEquals(true, impact.hasLockedColumns)
    }

    @Test
    fun `deleteColumn skips locked columns`() = runTest {
        val fixture = createFixture()
        val classId = fixture.classes.saveClass(name = "4 ESO D", course = 4, description = null)
        fixture.config.saveColumn(
            classId,
            NotebookColumnDefinition(
                id = "locked_column",
                title = "Bloqueada",
                type = NotebookColumnType.NUMERIC,
                isLocked = true,
            )
        )

        fixture.notebook.deleteColumn("locked_column")

        assertEquals("locked_column", fixture.config.listColumns(classId).single().id)
    }

    @Test
    fun `deleteColumnCategory with preserveColumns true keeps category columns and grades`() = runTest {
        val fixture = createFixture()
        val classId = fixture.classes.saveClass(name = "2 ESO A", course = 2, description = null)
        val studentId = fixture.students.saveStudent(firstName = "Lucia", lastName = "Perez", email = null)
        fixture.classes.addStudentToClass(classId, studentId)
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
        fixture.grades.saveGrade(
            classId = classId,
            studentId = studentId,
            columnId = "col_in_category",
            evaluationId = null,
            value = 9.0,
        )

        fixture.notebook.deleteColumnCategory(classId, "cat_eval", preserveColumns = true)

        val column = fixture.config.listColumns(classId).single()
        assertEquals("col_in_category", column.id)
        assertNull(column.categoryId)
        assertEquals(9.0, fixture.grades.listGradesForStudentInClass(studentId, classId).single().value)
        assertEquals(emptyList(), fixture.config.listColumnCategories(classId))
    }

    @Test
    fun `previewDeleteColumnCategory reports category impact`() = runTest {
        val fixture = createFixture()
        val classId = fixture.classes.saveClass(name = "2 ESO B", course = 2, description = null)
        val studentId = fixture.students.saveStudent(firstName = "Mario", lastName = "Vega", email = null)
        fixture.classes.addStudentToClass(classId, studentId)
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
                id = "cat_col_1",
                title = "Prueba 1",
                type = NotebookColumnType.NUMERIC,
                categoryId = "cat_eval",
            )
        )
        fixture.config.saveColumn(
            classId,
            NotebookColumnDefinition(
                id = "cat_col_2",
                title = "Prueba 2",
                type = NotebookColumnType.RUBRIC,
                categoryId = "cat_eval",
            )
        )
        fixture.grades.saveGrade(
            classId = classId,
            studentId = studentId,
            columnId = "cat_col_1",
            evaluationId = null,
            value = 8.0,
        )

        val impact = fixture.notebook.previewDeleteColumnCategory(classId, "cat_eval")

        assertEquals("cat_eval", impact.targetId)
        assertEquals("Evaluacion", impact.targetName)
        assertEquals(2, impact.affectedColumnCount)
        assertEquals(1, impact.affectedGradeCount)
        assertEquals(2, impact.affectedAverageColumnCount)
        assertEquals(false, impact.hasLockedColumns)
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

    @Test
    fun `migration 16 scopes grade uniqueness by class and keeps newest duplicate`() {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        createLegacyGradesTable(driver)
        insertLegacyGrade(driver, id = 1, classId = 1L, studentId = 10L, columnId = "shared", value = 6.0, updatedAt = 100L)
        insertLegacyGrade(driver, id = 2, classId = 2L, studentId = 10L, columnId = "shared", value = 8.0, updatedAt = 110L)
        insertLegacyGrade(driver, id = 3, classId = 1L, studentId = 10L, columnId = "dup", value = 5.0, updatedAt = 100L)
        insertLegacyGrade(driver, id = 4, classId = 1L, studentId = 10L, columnId = "dup", value = 9.0, updatedAt = 200L)
        insertLegacyGrade(driver, id = 5, classId = 1L, studentId = 10L, columnId = "legacy_eval", evaluationId = 44L, value = 7.5, updatedAt = 120L)
        insertLegacyGrade(driver, id = 6, classId = null, studentId = 10L, columnId = "orphan", value = 4.0, updatedAt = 130L)

        AppDatabase.Schema.migrate(driver, 16, 17)
        val db = AppDatabase(driver)

        val classOneGrades = db.appDatabaseQueries.selectGradesByClass(1L).executeAsList()
        val classTwoGrades = db.appDatabaseQueries.selectGradesByClass(2L).executeAsList()

        assertEquals(3, classOneGrades.size)
        assertEquals(1, classTwoGrades.size)
        assertEquals(6.0, classOneGrades.single { it.column_id == "shared" }.value_)
        assertEquals(8.0, classTwoGrades.single { it.column_id == "shared" }.value_)
        assertEquals(9.0, classOneGrades.single { it.column_id == "dup" }.value_)
        assertEquals(44L, classOneGrades.single { it.column_id == "legacy_eval" }.evaluation_id)
        assertEquals(0, countRows(driver, "SELECT COUNT(*) FROM grades WHERE column_id = 'orphan'"))
        assertTrue(indexExists(driver, "idx_grades_class_student"))
        assertTrue(indexExists(driver, "idx_grades_class_column"))
        assertTrue(indexExists(driver, "idx_grades_evaluation"))
    }

    @Test
    fun `migration 20 creates missing notebook cell audit table`() {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        driver.execute(null, "CREATE TABLE notebook_tabs (id TEXT PRIMARY KEY)", 0)
        driver.createLegacyClassesTable()
        driver.createLegacyWorkGroupsTable()

        AppDatabase.Schema.migrate(driver, 20, AppDatabase.Schema.version)
        val db = AppDatabase(driver)

        assertTrue(tableExists(driver, "notebook_cell_audit_events"))
        assertEquals(emptyList(), db.appDatabaseQueries.selectNotebookCellAudit(1L, 1L, "missing").executeAsList())
    }

    @Test
    fun `physical raw mark is excluded from average and scaled score is included`() = runTest {
        val fixture = createFixture()
        val classId = fixture.classes.saveClass(name = "1 ESO A", course = 1, description = null)
        val studentId = fixture.students.saveStudent(firstName = "Ana", lastName = "Lopez", email = null)
        fixture.classes.addStudentToClass(classId, studentId)
        fixture.config.saveColumn(
            classId,
            NotebookColumnDefinition(
                id = "raw_col",
                title = "Velocidad 30 m · marca",
                type = NotebookColumnType.NUMERIC,
                instrumentKind = NotebookInstrumentKind.PHYSICAL_TEST,
                scaleKind = NotebookScaleKind.TIME,
                weight = 0.0,
                countsTowardAverage = false,
            )
        )
        fixture.config.saveColumn(
            classId,
            NotebookColumnDefinition(
                id = "score_col",
                title = "Velocidad 30 m · nota",
                type = NotebookColumnType.NUMERIC,
                instrumentKind = NotebookInstrumentKind.PHYSICAL_TEST,
                scaleKind = NotebookScaleKind.TEN_POINT,
                weight = 10.0,
                countsTowardAverage = true,
            )
        )

        fixture.notebook.upsertGrade(
            classId = classId,
            studentId = studentId,
            columnId = "raw_col",
            evaluationId = null,
            numericValue = 5.8,
            createdAtEpochMs = 1L,
            updatedAtEpochMs = 1L,
        )
        fixture.notebook.upsertGrade(
            classId = classId,
            studentId = studentId,
            columnId = "score_col",
            evaluationId = null,
            numericValue = 8.0,
            createdAtEpochMs = 2L,
            updatedAtEpochMs = 2L,
        )

        val row = fixture.notebook.loadNotebookSnapshot(classId).rows.single()
        assertEquals(8.0, row.weightedAverage)
        assertEquals(5.8, row.persistedGrades.single { it.columnId == "raw_col" }.value)
        assertEquals(8.0, row.persistedGrades.single { it.columnId == "score_col" }.value)
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

    private fun createLegacyGradesTable(driver: JdbcSqliteDriver) {
        driver.execute(
            identifier = null,
            sql = """
                CREATE TABLE grades (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    class_id INTEGER,
                    student_id INTEGER,
                    column_id TEXT,
                    evaluation_id INTEGER,
                    value REAL,
                    evidence TEXT,
                    evidence_path TEXT,
                    rubric_selections TEXT,
                    created_at_epoch_ms INTEGER NOT NULL,
                    updated_at_epoch_ms INTEGER NOT NULL DEFAULT 0,
                    device_id TEXT,
                    sync_version INTEGER NOT NULL DEFAULT 0
                )
            """.trimIndent(),
            parameters = 0,
        )
    }

    private fun insertLegacyGrade(
        driver: JdbcSqliteDriver,
        id: Long,
        classId: Long?,
        studentId: Long,
        columnId: String,
        evaluationId: Long? = null,
        value: Double,
        updatedAt: Long,
    ) {
        driver.execute(
            identifier = null,
            sql = """
                INSERT INTO grades(
                    id, class_id, student_id, column_id, evaluation_id, value, evidence,
                    evidence_path, rubric_selections, created_at_epoch_ms, updated_at_epoch_ms,
                    device_id, sync_version
                )
                VALUES (?, ?, ?, ?, ?, ?, NULL, NULL, NULL, ?, ?, 'test', 1)
            """.trimIndent(),
            parameters = 8,
        ) {
            bindLong(0, id)
            bindLong(1, classId)
            bindLong(2, studentId)
            bindString(3, columnId)
            bindLong(4, evaluationId)
            bindDouble(5, value)
            bindLong(6, updatedAt)
            bindLong(7, updatedAt)
        }
    }

    private fun countRows(driver: JdbcSqliteDriver, sql: String): Long {
        return driver.executeQuery(
            identifier = null,
            sql = sql,
            mapper = { cursor ->
                QueryResult.Value(if (cursor.next().value) cursor.getLong(0) ?: 0L else 0L)
            },
            parameters = 0,
        ).value
    }

    private fun indexExists(driver: JdbcSqliteDriver, indexName: String): Boolean {
        return driver.executeQuery(
            identifier = null,
            sql = "PRAGMA index_list('grades')",
            mapper = { cursor ->
                var exists = false
                while (cursor.next().value) {
                    if (cursor.getString(1) == indexName) {
                        exists = true
                    }
                }
                QueryResult.Value(exists)
            },
            parameters = 0,
        ).value
    }

    private fun tableExists(driver: JdbcSqliteDriver, tableName: String): Boolean {
        return countRows(
            driver,
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '$tableName'"
        ) == 1L
    }
}
