package com.migestor.data.repository

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.shared.domain.NotebookAverageColumnConfig
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookEmptyCellPolicy
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookColumnVisibility
import com.migestor.shared.domain.NotebookWorkGroup
import com.migestor.shared.domain.NotebookTab
import com.migestor.shared.util.NotebookRefreshBus
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlin.test.Test
import kotlin.test.assertEquals

@OptIn(ExperimentalCoroutinesApi::class)
class NotebookConfigRepositorySqlDelightTest {
    @Test
    fun `saveTab emits a refresh signal and persists the tab`() = runTest {
        val db = createDatabase()
        val classesRepository = ClassesRepositorySqlDelight(db)
        val repository = NotebookConfigRepositorySqlDelight(db)
        val classId = classesRepository.saveClass(name = "3 ESO A", course = 3, description = null)

        val refresh = async { NotebookRefreshBus.refreshSignal.first() }
        runCurrent()

        repository.saveTab(classId, NotebookTab(id = "TAB_1", title = "Evaluación", order = 0))

        withTimeout(1_000) {
            refresh.await()
        }

        val tabs = repository.listTabs(classId)
        assertEquals(1, tabs.size)
        assertEquals("TAB_1", tabs.first().id)
    }

    @Test
    fun `saveColumn emits a refresh signal and persists the column`() = runTest {
        val db = createDatabase()
        val classesRepository = ClassesRepositorySqlDelight(db)
        val repository = NotebookConfigRepositorySqlDelight(db)
        val classId = classesRepository.saveClass(name = "3 ESO B", course = 3, description = null)

        val refresh = async { NotebookRefreshBus.refreshSignal.first() }
        runCurrent()

        repository.saveColumn(
            classId,
            NotebookColumnDefinition(
                id = "COL_1",
                title = "Examen",
                type = NotebookColumnType.NUMERIC,
                tabIds = listOf("TAB_1"),
            )
        )

        withTimeout(1_000) {
            refresh.await()
        }

        val columns = repository.listColumns(classId)
        assertEquals(1, columns.size)
        assertEquals("COL_1", columns.first().id)
    }

    @Test
    fun `saveColumn preserves explicit archived visibility`() = runTest {
        val db = createDatabase()
        val classesRepository = ClassesRepositorySqlDelight(db)
        val repository = NotebookConfigRepositorySqlDelight(db)
        val classId = classesRepository.saveClass(name = "3 ESO C", course = 3, description = null)

        repository.saveColumn(
            classId,
            NotebookColumnDefinition(
                id = "COL_ARCHIVED",
                title = "Archivada",
                type = NotebookColumnType.NUMERIC,
                isHidden = false,
                visibility = NotebookColumnVisibility.ARCHIVED,
            )
        )

        val column = repository.listColumns(classId).single()
        assertEquals(NotebookColumnVisibility.ARCHIVED, column.visibility)
        assertEquals(true, column.isHidden)
    }

    @Test
    fun `saveAverageConfiguration persists only average settings`() = runTest {
        val db = createDatabase()
        val classesRepository = ClassesRepositorySqlDelight(db)
        val repository = NotebookConfigRepositorySqlDelight(db)
        val classId = classesRepository.saveClass(name = "3 ESO D", course = 3, description = null)

        repository.saveColumn(
            classId,
            NotebookColumnDefinition(
                id = "COL_AVG",
                title = "Proyecto",
                type = NotebookColumnType.NUMERIC,
                weight = 10.0,
                visibility = NotebookColumnVisibility.HIDDEN,
                isHidden = true,
            )
        )
        repository.saveAverageConfiguration(
            classId,
            listOf(
                NotebookAverageColumnConfig(
                    columnId = "COL_AVG",
                    countsTowardAverage = true,
                    weight = 35.0,
                    emptyCellPolicy = NotebookEmptyCellPolicy.COUNT_AS_ZERO,
                )
            )
        )

        val column = repository.listColumns(classId).single()
        assertEquals("Proyecto", column.title)
        assertEquals(35.0, column.weight)
        assertEquals(true, column.countsTowardAverage)
        assertEquals(NotebookEmptyCellPolicy.COUNT_AS_ZERO, column.emptyCellPolicy)
        assertEquals(NotebookColumnVisibility.HIDDEN, column.visibility)
    }

    @Test
    fun `saveWorkGroup inserts multiple groups in the same tab without replacing previous ones`() = runTest {
        val db = createDatabase()
        val classesRepository = ClassesRepositorySqlDelight(db)
        val notebookConfigRepository = NotebookConfigRepositorySqlDelight(db)
        val classId = classesRepository.saveClass(name = "4 ESO A", course = 4, description = null)

        notebookConfigRepository.saveTab(
            classId,
            NotebookTab(id = "TAB_1", title = "Evaluación", order = 0),
        )

        val firstId = notebookConfigRepository.saveWorkGroup(
            classId,
            NotebookWorkGroup(
                id = 0L,
                classId = classId,
                tabId = "TAB_1",
                name = "Grupo 1",
            ),
        )
        val secondId = notebookConfigRepository.saveWorkGroup(
            classId,
            NotebookWorkGroup(
                id = 0L,
                classId = classId,
                tabId = "TAB_1",
                name = "Grupo 2",
            ),
        )

        val groups = notebookConfigRepository.listWorkGroups(classId, "TAB_1")
        assertEquals(2, groups.size)
        assertEquals(setOf(firstId, secondId), groups.map { it.id }.toSet())
    }

    private fun createDatabase(): AppDatabase {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        return AppDatabase(driver)
    }
}
