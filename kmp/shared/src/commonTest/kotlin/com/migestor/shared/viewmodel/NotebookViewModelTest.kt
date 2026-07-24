package com.migestor.shared.viewmodel

import com.migestor.shared.domain.Evaluation
import com.migestor.shared.domain.Grade
import com.migestor.shared.domain.NotebookCell
import com.migestor.shared.domain.NotebookAverageColumnConfig
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnCategory
import com.migestor.shared.domain.NotebookInstrumentKind
import com.migestor.shared.domain.NotebookRow
import com.migestor.shared.domain.NotebookScaleKind
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookColumnVisibility
import com.migestor.shared.domain.PersistedNotebookCell
import com.migestor.shared.domain.NotebookSheet
import com.migestor.shared.domain.NotebookWorkGroup
import com.migestor.shared.domain.NotebookTab
import com.migestor.shared.domain.SchoolClass
import com.migestor.shared.domain.Student
import com.migestor.shared.domain.visibleColumnsForTab
import com.migestor.shared.repository.ClassesRepository
import com.migestor.shared.repository.EvaluationsRepository
import com.migestor.shared.repository.GradesRepository
import com.migestor.shared.repository.NotebookRepository
import com.migestor.shared.repository.RubricsRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.advanceTimeBy
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class NotebookViewModelTest {
    @Test
    fun `column selection updates selection state without changing rows or structure states`() = runTest {
        val classId = 1L
        val column = NotebookColumnDefinition(
            id = "col_1",
            title = "Control",
            type = NotebookColumnType.NUMERIC,
        )
        val student = Student(id = 10L, firstName = "Ada", lastName = "Lovelace")
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = listOf(NotebookTab(id = "TAB_1", title = "Evaluación")),
                columns = listOf(column),
                rows = listOf(
                    NotebookRow(
                        student = student,
                        cells = listOf(NotebookCell(evaluationId = 100L, value = 7.5)),
                        weightedAverage = 7.5,
                    )
                ),
            )
        )
        val viewModel = createViewModel(repository)

        viewModel.selectClass(classId)
        advanceUntilIdle()
        val rowsBefore = viewModel.rowsState.value
        val structureBefore = viewModel.structureState.value

        viewModel.toggleColumnSelection(column.id)

        assertEquals(rowsBefore, viewModel.rowsState.value)
        assertEquals(structureBefore, viewModel.structureState.value)
        assertEquals(setOf(column.id), viewModel.selectionState.value.selectedColumnIds)
        assertTrue(viewModel.selectionState.value.isColumnSelectionMode)
    }

    @Test
    fun `addColumn assigns the selected tab to the saved column`() = runTest {
        val classId = 1L
        val tabs = listOf(
            NotebookTab(id = "TAB_1", title = "Evaluación"),
            NotebookTab(id = "TAB_2", title = "Bloques"),
        )
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = tabs,
                columns = emptyList(),
                rows = emptyList(),
            )
        )
        val viewModel = createViewModel(repository)

        viewModel.selectClass(classId)
        advanceUntilIdle()
        viewModel.setSelectedTabId("TAB_2")
        viewModel.addColumn(name = "Examen", type = NotebookColumnType.NUMERIC.name, weight = 1.0)
        advanceUntilIdle()

        val saved = repository.savedColumns.last()
        assertEquals(listOf("TAB_2"), saved.tabIds)
        assertFalse(saved.sharedAcrossTabs)
    }

    @Test
    fun `addColumn assigns the column only to the first tab when there is no active tab`() = runTest {
        val classId = 1L
        val tabs = listOf(
            NotebookTab(id = "TAB_1", title = "Evaluación"),
            NotebookTab(id = "TAB_2", title = "Bloques"),
        )
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = tabs,
                columns = emptyList(),
                rows = emptyList(),
            )
        )
        val viewModel = createViewModel(repository)

        viewModel.selectClass(classId)
        advanceUntilIdle()
        viewModel.setSelectedTabId(null)
        viewModel.addColumn(name = "Observación", type = NotebookColumnType.TEXT.name, weight = 1.0)
        advanceUntilIdle()

        val saved = repository.savedColumns.last()
        assertEquals(listOf("TAB_1"), saved.tabIds)
        assertFalse(saved.sharedAcrossTabs)
    }

    @Test
    fun `addColumn keeps rubric metadata when creating rubric columns`() = runTest {
        val classId = 1L
        val tabs = listOf(NotebookTab(id = "TAB_1", title = "Evaluación"))
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = tabs,
                columns = emptyList(),
                rows = emptyList(),
            )
        )
        val viewModel = createViewModel(repository)

        viewModel.selectClass(classId)
        advanceUntilIdle()
        viewModel.setSelectedTabId("TAB_1")
        viewModel.addColumn(
            name = "Rúbrica técnica",
            type = NotebookColumnType.RUBRIC.name,
            weight = 1.0,
            rubricId = 42L
        )
        advanceUntilIdle()

        val saved = repository.savedColumns.last()
        assertEquals(NotebookColumnType.RUBRIC, saved.type)
        assertEquals(42L, saved.rubricId)
    }

    @Test
    fun `upsertRubricGrade passes evaluation id to repository`() = runTest {
        val classId = 1L
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = emptyList(),
                columns = emptyList(),
                rows = emptyList(),
            )
        )
        val viewModel = createViewModel(repository)

        viewModel.selectClass(classId)
        advanceUntilIdle()
        viewModel.upsertRubricGrade(
            studentId = 7L,
            columnId = "",
            numericValue = 8.5,
            rubricSelections = """{"criterion_1":2}""",
            evaluationId = 123L
        )
        advanceUntilIdle()

        val call = repository.upsertGradeCalls.last()
        assertEquals("eval_123", call.columnId)
        assertEquals(123L, call.evaluationId)
        assertEquals(8.5, call.numericValue)
        assertEquals(1, repository.loadNotebookSnapshotCount)
    }

    @Test
    fun `addColumn keeps formula for calculated columns`() = runTest {
        val classId = 1L
        val tabs = listOf(NotebookTab(id = "TAB_1", title = "Evaluación"))
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = tabs,
                columns = emptyList(),
                rows = emptyList(),
            )
        )
        val viewModel = createViewModel(repository)

        viewModel.selectClass(classId)
        advanceUntilIdle()
        viewModel.addColumn(
            name = "Final",
            type = NotebookColumnType.CALCULATED.name,
            weight = 1.0,
            formula = "REDONDEAR(1+1; 2)"
        )
        advanceUntilIdle()

        val saved = repository.savedColumns.last()
        assertEquals(NotebookColumnType.CALCULATED, saved.type)
        assertEquals("REDONDEAR(1+1; 2)", saved.formula)
    }

    @Test
    fun `invalid formula column is not saved`() = runTest {
        val classId = 1L
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = emptyList(),
                columns = listOf(NotebookColumnDefinition(id = "eval_1", title = "Examen", type = NotebookColumnType.NUMERIC)),
                rows = emptyList(),
            )
        )
        val viewModel = createViewModel(repository)

        viewModel.selectClass(classId)
        advanceUntilIdle()
        viewModel.saveColumn(
            NotebookColumnDefinition(
                id = "formula_1",
                title = "Media",
                type = NotebookColumnType.CALCULATED,
                formula = "PROMEDIO([eval_1],[missing])",
            )
        )
        advanceUntilIdle()

        assertTrue(repository.savedColumns.none { it.id == "formula_1" })
    }

    @Test
    fun `circular formula column is not saved`() = runTest {
        val classId = 1L
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = emptyList(),
                columns = listOf(
                    NotebookColumnDefinition(id = "eval_1", title = "Examen", type = NotebookColumnType.NUMERIC),
                    NotebookColumnDefinition(id = "formula_b", title = "B", type = NotebookColumnType.CALCULATED, formula = "[formula_a] + 1"),
                ),
                rows = emptyList(),
            )
        )
        val viewModel = createViewModel(repository)

        viewModel.selectClass(classId)
        advanceUntilIdle()
        viewModel.saveColumn(
            NotebookColumnDefinition(
                id = "formula_a",
                title = "A",
                type = NotebookColumnType.CALCULATED,
                formula = "[formula_b] + 1",
            )
        )
        advanceUntilIdle()

        assertTrue(repository.savedColumns.none { it.id == "formula_a" })
    }

    @Test
    fun `saveColumn preserves layout metadata`() = runTest {
        val classId = 1L
        val tabs = listOf(NotebookTab(id = "TAB_1", title = "Evaluación"))
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = tabs,
                columns = emptyList(),
                rows = emptyList(),
            )
        )
        val viewModel = createViewModel(repository)

        viewModel.selectClass(classId)
        advanceUntilIdle()
        viewModel.saveColumn(
            NotebookColumnDefinition(
                id = "col_1",
                title = "Bloque",
                type = NotebookColumnType.TEXT,
                tabIds = listOf("TAB_1"),
                colorHex = "#FFAA00",
                order = 3,
                widthDp = 180.0
            )
        )
        advanceUntilIdle()

        val saved = repository.savedColumns.last()
        assertEquals(3, saved.order)
        assertEquals(180.0, saved.widthDp)
        assertEquals("#FFAA00", saved.colorHex)
    }

    @Test
    fun `visibleColumnsForTab only returns visible columns`() {
        val sheet = NotebookSheet(
            classId = 1L,
            tabs = listOf(NotebookTab(id = "TAB_1", title = "Evaluación")),
            columns = listOf(
                NotebookColumnDefinition(
                    id = "visible",
                    title = "Visible",
                    type = NotebookColumnType.NUMERIC,
                    tabIds = listOf("TAB_1"),
                    visibility = NotebookColumnVisibility.VISIBLE,
                ),
                NotebookColumnDefinition(
                    id = "hidden",
                    title = "Oculta",
                    type = NotebookColumnType.NUMERIC,
                    tabIds = listOf("TAB_1"),
                    visibility = NotebookColumnVisibility.HIDDEN,
                ),
                NotebookColumnDefinition(
                    id = "archived",
                    title = "Archivada",
                    type = NotebookColumnType.NUMERIC,
                    tabIds = listOf("TAB_1"),
                    visibility = NotebookColumnVisibility.ARCHIVED,
                    isHidden = true,
                ),
            ),
            rows = emptyList(),
        )

        assertEquals(listOf("visible"), sheet.visibleColumnsForTab("TAB_1").map { it.id })
    }

    @Test
    fun `class average uses configured weights`() {
        val viewModel = createViewModel(FakeNotebookRepository(emptyNotebookSheet()))
        val sheet = NotebookSheet(
            classId = 1L,
            tabs = emptyList(),
            columns = listOf(
                NotebookColumnDefinition(id = "eval_1", title = "Examen", type = NotebookColumnType.NUMERIC, evaluationId = 1L, weight = 40.0),
                NotebookColumnDefinition(id = "eval_2", title = "Rúbrica", type = NotebookColumnType.RUBRIC, evaluationId = 2L, weight = 60.0),
            ),
            rows = listOf(
                NotebookRow(
                    student = Student(id = 1L, firstName = "Ana", lastName = "Lopez"),
                    cells = listOf(NotebookCell(evaluationId = 1L, value = 5.0), NotebookCell(evaluationId = 2L, value = 10.0)),
                    weightedAverage = null,
                )
            )
        )

        assertEquals(8.0, viewModel.calculateClassAverage(sheet))
    }

    @Test
    fun `excluded columns do not affect class average`() {
        val viewModel = createViewModel(FakeNotebookRepository(emptyNotebookSheet()))
        val sheet = NotebookSheet(
            classId = 1L,
            tabs = emptyList(),
            columns = listOf(
                NotebookColumnDefinition(id = "eval_1", title = "Examen", type = NotebookColumnType.NUMERIC, evaluationId = 1L, weight = 100.0),
                NotebookColumnDefinition(id = "eval_2", title = "Extra", type = NotebookColumnType.NUMERIC, evaluationId = 2L, weight = 100.0, countsTowardAverage = false),
            ),
            rows = listOf(
                NotebookRow(
                    student = Student(id = 1L, firstName = "Ana", lastName = "Lopez"),
                    cells = listOf(NotebookCell(evaluationId = 1L, value = 7.0), NotebookCell(evaluationId = 2L, value = 1.0)),
                    weightedAverage = null,
                )
            )
        )

        assertEquals(7.0, viewModel.calculateClassAverage(sheet))
    }

    @Test
    fun `raw physical marks do not affect class average but scaled notes do`() {
        val viewModel = createViewModel(FakeNotebookRepository(emptyNotebookSheet()))
        val sheet = NotebookSheet(
            classId = 1L,
            tabs = emptyList(),
            columns = listOf(
                NotebookColumnDefinition(
                    id = "raw",
                    title = "Salto · marca",
                    type = NotebookColumnType.NUMERIC,
                    weight = 50.0,
                    instrumentKind = NotebookInstrumentKind.PHYSICAL_TEST,
                    scaleKind = NotebookScaleKind.DISTANCE,
                    countsTowardAverage = true,
                ),
                NotebookColumnDefinition(
                    id = "score",
                    title = "Salto · nota",
                    type = NotebookColumnType.NUMERIC,
                    weight = 50.0,
                    instrumentKind = NotebookInstrumentKind.PHYSICAL_TEST,
                    scaleKind = NotebookScaleKind.TEN_POINT,
                    countsTowardAverage = true,
                ),
            ),
            rows = listOf(
                NotebookRow(
                    student = Student(id = 1L, firstName = "Ana", lastName = "Lopez"),
                    cells = emptyList(),
                    persistedGrades = listOf(
                        Grade(id = 1L, classId = 1L, studentId = 1L, columnId = "raw", evaluationId = null, value = 180.0),
                        Grade(id = 2L, classId = 1L, studentId = 1L, columnId = "score", evaluationId = null, value = 8.5),
                    ),
                    weightedAverage = null,
                )
            )
        )

        assertEquals(8.5, viewModel.calculateClassAverage(sheet))
    }

    @Test
    fun `average column is recalculated with only the active tab columns`() = runTest {
        val classId = 1L
        val tabs = listOf(
            NotebookTab(id = "TAB_1", title = "Tema 1"),
            NotebookTab(id = "TAB_2", title = "Tema 2"),
        )
        val student = Student(id = 1L, firstName = "Ana", lastName = "Lopez")
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = tabs,
                columns = listOf(
                    NotebookColumnDefinition(
                        id = "tema_1",
                        title = "Prueba tema 1",
                        type = NotebookColumnType.NUMERIC,
                        tabIds = listOf("TAB_1"),
                        weight = 1.0,
                    ),
                    NotebookColumnDefinition(
                        id = "tema_2",
                        title = "Prueba tema 2",
                        type = NotebookColumnType.NUMERIC,
                        tabIds = listOf("TAB_2"),
                        weight = 1.0,
                    ),
                ),
                rows = listOf(
                    NotebookRow(
                        student = student,
                        cells = emptyList(),
                        weightedAverage = null,
                        persistedGrades = listOf(
                            Grade(id = 1L, classId = classId, studentId = student.id, columnId = "tema_1", evaluationId = null, value = 6.0),
                            Grade(id = 2L, classId = classId, studentId = student.id, columnId = "tema_2", evaluationId = null, value = 9.0),
                        ),
                    )
                ),
            )
        )
        val viewModel = createViewModel(repository)

        viewModel.selectClass(classId)
        advanceUntilIdle()

        var data = viewModel.state.value as NotebookUiState.Data
        assertEquals(6.0, data.sheet.rows.first().weightedAverage)
        assertEquals(listOf("tema_1"), data.sheet.rows.first().averageExplanation?.included?.map { it.columnId })

        viewModel.setSelectedTabId("TAB_2")

        data = viewModel.state.value as NotebookUiState.Data
        assertEquals(9.0, data.sheet.rows.first().weightedAverage)
        assertEquals(listOf("tema_2"), data.sheet.rows.first().averageExplanation?.included?.map { it.columnId })
    }

    @Test
    fun `saveAverageConfiguration updates average settings without saveColumn path`() = runTest {
        val classId = 1L
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = emptyList(),
                columns = listOf(
                    NotebookColumnDefinition(
                        id = "custom_numeric",
                        title = "Proyecto",
                        type = NotebookColumnType.NUMERIC,
                        evaluationId = null,
                        weight = 10.0,
                        countsTowardAverage = false,
                    )
                ),
                rows = emptyList(),
            )
        )
        val viewModel = createViewModel(repository)

        viewModel.selectClass(classId)
        advanceUntilIdle()
        viewModel.saveAverageConfiguration(
            listOf(
                NotebookAverageColumnConfig(
                    columnId = "custom_numeric",
                    countsTowardAverage = true,
                    weight = 35.0,
                )
            )
        )
        advanceUntilIdle()

        assertEquals(1, repository.savedAverageConfigurations.size)
        assertEquals(emptyList(), repository.savedColumns)
        assertEquals("custom_numeric", repository.savedAverageConfigurations.single().single().columnId)
    }

    @Test
    fun `saveWorkGroup keeps names unique within the same tab`() = runTest {
        val classId = 1L
        val tabs = listOf(NotebookTab(id = "TAB_1", title = "Evaluación"))
        val existingGroup = NotebookWorkGroup(
            id = 1L,
            classId = classId,
            tabId = "TAB_1",
            name = "Grupo 1",
            order = 0,
        )
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = tabs,
                columns = emptyList(),
                rows = emptyList(),
                workGroups = listOf(existingGroup),
            )
        )
        val viewModel = createViewModel(repository)

        viewModel.selectClass(classId)
        advanceUntilIdle()
        viewModel.saveWorkGroup(name = "Grupo 1")
        advanceUntilIdle()

        assertEquals("Grupo 1 (2)", repository.savedWorkGroups.last().name)
        assertEquals(1, repository.savedWorkGroups.size)
    }

    @Test
    fun `saveWorkGroup auto creates a default tab if none exists`() = runTest {
        val classId = 1L
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = emptyList(),
                columns = emptyList(),
                rows = emptyList(),
            )
        )
        val viewModel = createViewModel(repository)

        viewModel.selectClass(classId)
        advanceUntilIdle()
        viewModel.saveWorkGroup(name = "Grupo Auto")
        advanceUntilIdle()

        assertTrue(repository.savedTabs.isNotEmpty())
        assertEquals("Evaluación", repository.savedTabs.first().title)

        val savedGroup = repository.savedWorkGroups.single()
        assertEquals("Grupo Auto", savedGroup.name)
        assertEquals(repository.savedTabs.first().id, savedGroup.tabId)
    }

    @Test
    fun `deleteColumn by evaluation id deletes custom column id when found`() = runTest {
        val classId = 1L
        val evaluationId = 123L
        val customColumnId = "examen_1_1720000000000_2"
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = emptyList(),
                columns = listOf(
                    NotebookColumnDefinition(
                        id = customColumnId,
                        title = "Examen",
                        type = NotebookColumnType.NUMERIC,
                        evaluationId = evaluationId,
                    )
                ),
                rows = emptyList(),
            )
        )
        val viewModel = createViewModel(repository)
        viewModel.selectClass(classId)
        advanceUntilIdle()

        viewModel.deleteColumn(evaluationId)
        advanceUntilIdle()

        assertEquals(listOf(customColumnId), repository.deletedColumnIds)
        assertEquals(emptyList(), repository.deletedEvaluationIds)
    }

    @Test
    fun `deleteColumn by evaluation id falls back to eval prefix when no custom column matches`() = runTest {
        val classId = 1L
        val evaluationId = 123L
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = emptyList(),
                columns = emptyList(),
                rows = emptyList(),
            )
        )
        val viewModel = createViewModel(repository)
        viewModel.selectClass(classId)
        advanceUntilIdle()

        viewModel.deleteColumn(evaluationId)
        advanceUntilIdle()

        assertEquals(listOf("eval_123"), repository.deletedColumnIds)
        assertEquals(listOf(123L), repository.deletedEvaluationIds)
    }

    @Test
    fun `inline numeric save updates local state without reloading the full notebook`() = runTest {
        val classId = 1L
        val student = Student(id = 1L, firstName = "Ana", lastName = "Lopez")
        val column = NotebookColumnDefinition(
            id = "custom_numeric",
            title = "Proyecto",
            type = NotebookColumnType.NUMERIC,
        )
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = emptyList(),
                columns = listOf(column),
                rows = listOf(
                    NotebookRow(
                        student = student,
                        cells = emptyList(),
                        weightedAverage = null,
                        persistedGrades = listOf(
                            Grade(
                                id = 1L,
                                classId = classId,
                                studentId = student.id,
                                columnId = column.id,
                                evaluationId = null,
                                value = 5.0,
                            )
                        ),
                    )
                ),
            )
        )
        val scope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler))
        val viewModel = createViewModel(repository, scope = scope)
        try {
            viewModel.selectClass(classId)
            advanceUntilIdle()
            assertEquals(1, repository.loadNotebookSnapshotCount)

            viewModel.saveColumnGrade(student.id, column, "8,5")
            advanceUntilIdle()
            advanceTimeBy(500)
            advanceUntilIdle()

            val data = viewModel.state.value as NotebookUiState.Data
            val grade = data.sheet.rows.single().persistedGrades.single { it.columnId == column.id }
            assertEquals(8.5, grade.value)
            assertEquals(1, repository.loadNotebookSnapshotCount)
            assertEquals(1, repository.saveGradeCalls.size)
        } finally {
            scope.cancel()
        }
    }

    @Test
    fun `saveCurrentNotebook does not overwrite a grade when the draft fails to parse`() = runTest {
        // Regresion: saveCurrentNotebook llamaba a saveGrade con
        // draft.replace(",", ".").toDoubleOrNull() sin el guard que si tiene
        // internalSaveGrade; un draft no vacio que no parsea ("7,,5") se
        // convertia en null y pisaba la nota ya guardada en BD con un valor vacio.
        val classId = 1L
        val student = Student(id = 1L, firstName = "Ana", lastName = "Lopez")
        val column = NotebookColumnDefinition(
            id = "custom_numeric",
            title = "Proyecto",
            type = NotebookColumnType.NUMERIC,
        )
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = emptyList(),
                columns = listOf(column),
                rows = listOf(
                    NotebookRow(
                        student = student,
                        cells = emptyList(),
                        weightedAverage = null,
                        persistedGrades = listOf(
                            Grade(
                                id = 1L,
                                classId = classId,
                                studentId = student.id,
                                columnId = column.id,
                                evaluationId = null,
                                value = 7.5,
                            )
                        ),
                    )
                ),
            )
        )
        val scope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler))
        val viewModel = createViewModel(repository, scope = scope)
        try {
            viewModel.selectClass(classId)
            advanceUntilIdle()

            viewModel.updateDraft(student.id, column.id, NotebookColumnType.NUMERIC, "7,,5")

            val saved = viewModel.saveCurrentNotebook()
            advanceUntilIdle()

            assertEquals(true, saved)
            assertEquals(0, repository.saveGradeCalls.size, "No debe llamar a saveGrade con un draft no parseable")
        } finally {
            scope.cancel()
        }
    }

    @Test
    fun `direct evaluation grade save updates local state without observer reload`() = runTest {
        val classId = 1L
        val evaluationId = 9L
        val student = Student(id = 1L, firstName = "Ana", lastName = "Lopez")
        val column = NotebookColumnDefinition(
            id = "eval_$evaluationId",
            title = "Examen",
            type = NotebookColumnType.NUMERIC,
            evaluationId = evaluationId,
        )
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = emptyList(),
                columns = listOf(column),
                rows = listOf(
                    NotebookRow(
                        student = student,
                        cells = listOf(NotebookCell(evaluationId = evaluationId, value = 5.0)),
                        weightedAverage = null,
                    )
                ),
            )
        )
        val scope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler))
        val viewModel = createViewModel(repository, scope = scope)
        try {
            viewModel.selectClass(classId)
            advanceUntilIdle()

            viewModel.saveGrade(student.id, evaluationId, 7.5)
            advanceUntilIdle()
            advanceTimeBy(500)
            advanceUntilIdle()

            val data = viewModel.state.value as NotebookUiState.Data
            val cell = data.sheet.rows.single().cells.single { it.evaluationId == evaluationId }
            assertEquals(7.5, cell.value)
            assertEquals(1, repository.loadNotebookSnapshotCount)
            assertEquals(1, repository.saveGradeCalls.size)
        } finally {
            scope.cancel()
        }
    }

    @Test
    fun `inline text save reconciles persisted cell locally`() = runTest {
        val classId = 1L
        val student = Student(id = 1L, firstName = "Ana", lastName = "Lopez")
        val column = NotebookColumnDefinition(
            id = "notes",
            title = "Observaciones",
            type = NotebookColumnType.TEXT,
        )
        val repository = FakeNotebookRepository(
            snapshot = NotebookSheet(
                classId = classId,
                tabs = emptyList(),
                columns = listOf(column),
                rows = listOf(
                    NotebookRow(
                        student = student,
                        cells = emptyList(),
                        weightedAverage = null,
                        persistedCells = listOf(
                            PersistedNotebookCell(
                                classId = classId,
                                studentId = student.id,
                                columnId = column.id,
                                textValue = "Anterior",
                                displayValue = "Anterior",
                            )
                        ),
                    )
                ),
            )
        )
        val scope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler))
        val viewModel = createViewModel(repository, scope = scope)
        try {
            viewModel.selectClass(classId)
            advanceUntilIdle()
            viewModel.saveColumnGrade(student.id, column, "Mejora")
            advanceUntilIdle()

            val data = viewModel.state.value as NotebookUiState.Data
            val cell = data.sheet.rows.single().persistedCells.single { it.columnId == column.id }
            assertEquals("Mejora", cell.textValue)
            assertEquals("Mejora", cell.displayValue)
            assertEquals(1, repository.savedCellCalls.size)
            assertEquals(1, repository.loadNotebookSnapshotCount)
        } finally {
            scope.cancel()
        }
    }

    @Test
    fun `a slower stale reload does not clobber the state written by a faster newer reload`() = runTest {
        // Reproduce la carrera real que dejaba el Checklist "congelado" en el Cuaderno: tras
        // guardar un instrumento estructurado, `refreshCurrentNotebook` (Swift) y el bus de
        // refresco de Kotlin disparan dos `selectClass(force = true)` casi simultáneos, sin
        // cancelarse entre sí. Si la carga más VIEJA en lanzarse tarda más en responder que la
        // más NUEVA, antes de este fix la vieja ganaba igualmente por terminar la última — este
        // test fuerza justo ese orden (vieja lenta, nueva rápida) con retrasos controlados por
        // tiempo virtual y comprueba que el estado final es el de la carga más reciente.
        val classId = 1L
        val column = NotebookColumnDefinition(
            id = "checklist_col",
            title = "Checklist",
            type = NotebookColumnType.TEXT,
        )
        val student = Student(id = 10L, firstName = "Ada", lastName = "Lovelace")

        fun sheetWithDisplayValue(displayValue: String) = NotebookSheet(
            classId = classId,
            tabs = listOf(NotebookTab(id = "TAB_1", title = "Evaluación")),
            columns = listOf(column),
            rows = listOf(
                NotebookRow(
                    student = student,
                    cells = emptyList(),
                    weightedAverage = null,
                    persistedCells = listOf(
                        PersistedNotebookCell(
                            classId = classId,
                            studentId = student.id,
                            columnId = column.id,
                            displayValue = displayValue,
                        )
                    ),
                )
            ),
        )

        val initialSheet = sheetWithDisplayValue("Pendiente")
        val staleSheet = sheetWithDisplayValue("3/7")
        val freshSheet = sheetWithDisplayValue("5/7")

        val repository = FakeNotebookRepository(
            snapshot = initialSheet,
            // 1ª llamada: carga inicial de selectClass(classId). 2ª: la recarga "vieja" (lenta,
            // 500ms virtuales). 3ª: la recarga "nueva" (rápida, 50ms virtuales), lanzada después
            // de la vieja pero que debe terminar antes y ganar.
            snapshotQueue = mutableListOf(initialSheet, staleSheet, freshSheet),
            delayQueueMs = mutableListOf(0L, 500L, 50L),
        )
        val dispatcher = StandardTestDispatcher(testScheduler)
        val scope = CoroutineScope(SupervisorJob() + dispatcher)
        val viewModel = createViewModel(repository, scope = scope)

        try {
            viewModel.selectClass(classId)
            advanceUntilIdle()

            viewModel.selectClass(classId, force = true) // vieja: arranca ya, tardará 500ms
            advanceTimeBy(10) // deja que arranque sin terminar
            viewModel.selectClass(classId, force = true) // nueva: arranca después, tardará 50ms
            advanceUntilIdle()

            val finalState = viewModel.state.value
            check(finalState is NotebookUiState.Data) { "Se esperaba NotebookUiState.Data, fue $finalState" }
            val finalCell = finalState.sheet.rows.single().persistedCells.first { it.columnId == column.id }
            assertEquals("5/7", finalCell.displayValue)
        } finally {
            scope.cancel()
        }
    }

    private fun createViewModel(
        repository: FakeNotebookRepository,
        scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
    ): NotebookViewModel {
        return NotebookViewModel(
            notebookRepository = repository,
            evaluationsRepository = FakeEvaluationsRepository(),
            rubricsRepository = FakeRubricsRepository(),
            scope = scope,
        )
    }

    private fun emptyNotebookSheet(): NotebookSheet =
        NotebookSheet(classId = 1L, tabs = emptyList(), columns = emptyList(), rows = emptyList())
}

private class FakeNotebookRepository(
    private val snapshot: NotebookSheet,
    // Permiten reproducir en test la carrera real entre recargas concurrentes de
    // `NotebookViewModel.selectClass`/`startObservingData`: cada llamada a `loadNotebookSnapshot`
    // consume el siguiente retraso/snapshot de la cola en vez de devolver siempre el mismo valor
    // al instante, para poder forzar que una carga "vieja" tarde más que una "nueva".
    private val snapshotQueue: MutableList<NotebookSheet>? = null,
    private val delayQueueMs: MutableList<Long>? = null,
) : NotebookRepository {
    private val studentChanges = MutableStateFlow<List<Student>>(emptyList())
    private val gradeChanges = MutableStateFlow<List<Grade>>(emptyList())

    val savedColumns = mutableListOf<NotebookColumnDefinition>()
    val savedAverageConfigurations = mutableListOf<List<NotebookAverageColumnConfig>>()
    val savedWorkGroups = mutableListOf<NotebookWorkGroup>()
    val upsertGradeCalls = mutableListOf<UpsertGradeCall>()
    val saveGradeCalls = mutableListOf<SaveGradeCall>()
    val savedCellCalls = mutableListOf<SaveCellCall>()
    val savedTabs = mutableListOf<NotebookTab>()
    var loadNotebookSnapshotCount = 0

    val deletedColumnIds = mutableListOf<String>()
    val deletedEvaluationIds = mutableListOf<Long>()

    override suspend fun loadNotebookSnapshot(classId: Long): NotebookSheet {
        loadNotebookSnapshotCount += 1
        // Se capturan retraso Y snapshot juntos, de forma síncrona, en el momento de la
        // LLAMADA (antes de suspender en el delay). Si se leyeran por separado (retraso ahora,
        // snapshot tras el delay), el orden de FINALIZACIÓN decidiría qué snapshot recibe cada
        // llamada en vez del orden de LANZAMIENTO, invalidando el propósito del test de carrera.
        val delayMs = delayQueueMs?.removeFirstOrNull()
        val nextSnapshot = snapshotQueue?.removeFirstOrNull() ?: snapshot
        if (delayMs != null && delayMs > 0) {
            kotlinx.coroutines.delay(delayMs)
        }
        return nextSnapshot
    }
    override fun observeStudentChanges(classId: Long): Flow<List<Student>> = studentChanges
    override fun observeGradesForClass(classId: Long): Flow<List<com.migestor.shared.domain.Grade>> = gradeChanges
    override suspend fun addStudent(classId: Long, firstName: String, lastName: String, isInjured: Boolean): Student = Student(id = 1, firstName = firstName, lastName = lastName, isInjured = isInjured)
    override suspend fun removeStudent(classId: Long, studentId: Long) = Unit
    override suspend fun listStudentsInClass(classId: Long): List<Student> = emptyList()
    override suspend fun saveGrade(classId: Long, studentId: Long, columnId: String, evaluationId: Long?, value: Double?): Long {
        saveGradeCalls += SaveGradeCall(classId, studentId, columnId, evaluationId, value)
        gradeChanges.value = listOf(Grade(id = 1L, classId = classId, studentId = studentId, columnId = columnId, evaluationId = evaluationId, value = value))
        return 1
    }
    override suspend fun saveTab(classId: Long, tab: NotebookTab) {
        savedTabs += tab
    }
    override suspend fun deleteTab(tabId: String) = Unit
    override suspend fun saveColumn(classId: Long, column: NotebookColumnDefinition) {
        savedColumns += column
    }
    override suspend fun saveAverageConfiguration(classId: Long, updates: List<NotebookAverageColumnConfig>) {
        savedAverageConfigurations += updates
    }
    override suspend fun previewDeleteColumn(classId: Long, columnId: String): com.migestor.shared.domain.NotebookDeletionImpact =
        com.migestor.shared.domain.NotebookDeletionImpact(
            targetId = columnId,
            targetName = columnId,
            targetKind = com.migestor.shared.domain.NotebookDeletionTargetKind.COLUMN,
            affectedColumnCount = 1,
            affectedGradeCount = 0,
            affectedFormulaColumnCount = 0,
            affectedAverageColumnCount = 0,
            hasLockedColumns = false,
        )
    override suspend fun deleteColumn(columnId: String) {
        deletedColumnIds += columnId
    }
    override suspend fun listColumnCategories(classId: Long, tabId: String?) = emptyList<NotebookColumnCategory>()
    override suspend fun saveColumnCategory(classId: Long, category: NotebookColumnCategory) = Unit
    override suspend fun previewDeleteColumnCategory(classId: Long, categoryId: String): com.migestor.shared.domain.NotebookDeletionImpact =
        com.migestor.shared.domain.NotebookDeletionImpact(
            targetId = categoryId,
            targetName = categoryId,
            targetKind = com.migestor.shared.domain.NotebookDeletionTargetKind.CATEGORY,
            affectedColumnCount = 0,
            affectedGradeCount = 0,
            affectedFormulaColumnCount = 0,
            affectedAverageColumnCount = 0,
            hasLockedColumns = false,
        )
    override suspend fun deleteColumnCategory(classId: Long, categoryId: String, preserveColumns: Boolean) = Unit
    override suspend fun toggleCategoryCollapsed(classId: Long, categoryId: String, isCollapsed: Boolean) = Unit
    override suspend fun reorderCategory(classId: Long, tabId: String, categoryId: String, targetCategoryId: String) = Unit
    override suspend fun assignColumnToCategory(classId: Long, columnId: String, categoryId: String?) = Unit
    override suspend fun deleteEvaluation(evaluationId: Long) {
        deletedEvaluationIds += evaluationId
    }
    override suspend fun duplicateConfigToClass(sourceClassId: Long, targetClassId: Long) = Unit
    override suspend fun listWorkGroups(classId: Long, tabId: String?): List<com.migestor.shared.domain.NotebookWorkGroup> = emptyList()
    override suspend fun saveWorkGroup(classId: Long, workGroup: com.migestor.shared.domain.NotebookWorkGroup): Long {
        savedWorkGroups += workGroup
        return savedWorkGroups.size.toLong()
    }
    override suspend fun deleteWorkGroup(groupId: Long) = Unit
    override suspend fun listWorkGroupMembers(classId: Long, tabId: String?): List<com.migestor.shared.domain.NotebookWorkGroupMember> = emptyList()
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
    ) {
        savedCellCalls += SaveCellCall(
            classId = classId,
            studentId = studentId,
            columnId = columnId,
            textValue = textValue,
            boolValue = boolValue,
            iconValue = iconValue,
            ordinalValue = ordinalValue,
        )
    }
    override suspend fun getTabNamesForClass(classId: Long): List<String> = emptyList()
    override suspend fun createTab(classId: Long, tabName: String): String = ""
    override suspend fun addColumnToTab(classId: Long, tabName: String, columnName: String, columnType: NotebookColumnType, rubricId: Long?): String = ""
    override suspend fun getNotebookConfig(classId: Long) = com.migestor.shared.domain.NotebookConfig(
        classId = classId,
        tabs = snapshot.tabs,
        columns = snapshot.columns
    )
    override suspend fun getGradeForColumn(studentId: Long, columnId: String): com.migestor.shared.domain.Grade? = null
    override suspend fun getColumnIdForEvaluation(evaluationId: Long): String? = null
    override suspend fun upsertGrade(
        classId: Long,
        studentId: Long,
        columnId: String,
        evaluationId: Long?,
        numericValue: Double,
        rubricSelections: String?,
        evidence: String?,
        createdAtEpochMs: Long,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ) {
        upsertGradeCalls += UpsertGradeCall(
            classId = classId,
            studentId = studentId,
            columnId = columnId,
            evaluationId = evaluationId,
            numericValue = numericValue,
            rubricSelections = rubricSelections,
            evidence = evidence,
        )
    }

    override fun observeCellAudit(
        classId: Long,
        studentId: Long,
        columnId: String,
    ): Flow<List<com.migestor.shared.domain.NotebookCellAuditEvent>> = flowOf(emptyList())
}

private data class SaveGradeCall(
    val classId: Long,
    val studentId: Long,
    val columnId: String,
    val evaluationId: Long?,
    val value: Double?,
)

private data class SaveCellCall(
    val classId: Long,
    val studentId: Long,
    val columnId: String,
    val textValue: String?,
    val boolValue: Boolean?,
    val iconValue: String?,
    val ordinalValue: String?,
)

private data class UpsertGradeCall(
    val classId: Long,
    val studentId: Long,
    val columnId: String,
    val evaluationId: Long?,
    val numericValue: Double,
    val rubricSelections: String?,
    val evidence: String?,
)

private class FakeEvaluationsRepository : EvaluationsRepository {
    override fun observeClassEvaluations(classId: Long): Flow<List<Evaluation>> = flowOf(emptyList())
    override suspend fun listClassEvaluations(classId: Long): List<Evaluation> = emptyList()
    override suspend fun getEvaluation(evaluationId: Long): Evaluation? = null
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

private class FakeRubricsRepository : RubricsRepository {
    override fun observeRubrics() = flowOf(emptyList<com.migestor.shared.domain.RubricDetail>())
    override suspend fun listRubrics() = emptyList<com.migestor.shared.domain.RubricDetail>()
    override suspend fun saveRubric(
        id: Long?,
        name: String,
        description: String?,
        classId: Long?,
        teachingUnitId: Long?,
        createdAtEpochMs: Long,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ) = 1L
    override suspend fun deleteRubric(rubricId: Long) = Unit
    override suspend fun saveCriterion(
        id: Long?,
        rubricId: Long,
        description: String,
        weight: Double,
        order: Int,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ) = 1L
    override suspend fun deleteCriterion(criterionId: Long) = Unit
    override suspend fun saveLevel(
        id: Long?,
        criterionId: Long,
        name: String,
        points: Int,
        description: String?,
        order: Int,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ) = 1L
    override suspend fun deleteLevel(levelId: Long) = Unit
    override suspend fun saveRubricAssessment(
        studentId: Long,
        evaluationId: Long,
        criterionId: Long,
        levelId: Long,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): Double? = null
    override suspend fun listRubricAssessments(studentId: Long, evaluationId: Long) = emptyList<com.migestor.shared.domain.RubricAssessment>()
    override suspend fun getStudentEvaluation(studentId: Long, rubricId: Long, evaluationId: Long) = emptyMap<Long, Long>()
    override suspend fun listCriteriaByRubric(rubricId: Long) = emptyList<com.migestor.shared.domain.RubricCriterion>()
    override suspend fun listLevelsByCriterion(criterionId: Long) = emptyList<com.migestor.shared.domain.RubricLevel>()
}
