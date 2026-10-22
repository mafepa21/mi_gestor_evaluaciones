package com.migestor.desktop.sync

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import com.migestor.data.sync.SqlDelightSyncAdapter
import com.migestor.shared.domain.NotebookColumnCategory
import com.migestor.shared.sync.SyncChange
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class NotebookColumnCategorySyncTest {
    private fun newContainer(): KmpContainer {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        return KmpContainer(driver)
    }

    @Test
    fun laCategoriaCreadaEnElIpadLlegaAlMacYSuBorradoTambien() = runTest {
        val mac = newContainer()
        val classId = mac.classesRepository.saveClass(name = "3 ESO B", course = 3, description = null)
        val adapter = SqlDelightSyncAdapter(mac, localDeviceId = "mac")
        val upsert = SyncChange(
            entity = "notebook_column_category",
            id = "cat_eval",
            updatedAtEpochMs = 1_000,
            deviceId = "ipad",
            payload = """{"id":"cat_eval","classId":$classId,"tabId":"TAB_1","name":"Evaluación","order":2,"isCollapsed":true}""",
        )
        assertEquals(1, adapter.applyIncomingChangesLww(listOf(upsert)).applied)
        val saved = mac.notebookRepository.listColumnCategories(classId).single()
        assertEquals("Evaluación", saved.name)
        assertEquals(2, saved.order)
        assertTrue(saved.isCollapsed)

        val delete = upsert.copy(updatedAtEpochMs = 2_000, op = "delete", payload = """{"id":"cat_eval","classId":$classId,"preserveColumns":true}""")
        assertEquals(1, adapter.applyIncomingChangesLww(listOf(delete)).applied)
        assertTrue(mac.notebookRepository.listColumnCategories(classId).isEmpty())
    }

    @Test
    fun elMacEnviaSusCategorias() = runTest {
        val mac = newContainer()
        val classId = mac.classesRepository.saveClass(name = "3 ESO B", course = 3, description = null)
        mac.notebookRepository.saveColumnCategory(
            classId,
            NotebookColumnCategory(id = "cat_eval", classId = classId, tabId = "TAB_1", name = "Evaluación"),
        )
        val categories = SqlDelightSyncAdapter(mac, localDeviceId = "mac").collectLocalChanges(0L)
            .filter { it.entity == "notebook_column_category" }
        assertEquals(listOf("cat_eval"), categories.map { it.id })
    }
}
