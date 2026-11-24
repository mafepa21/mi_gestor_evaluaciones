package com.migestor.data

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import com.migestor.data.sync.ModuleRecordsSync
import com.migestor.data.sync.SqlDelightSyncAdapter
import com.migestor.shared.domain.AuditTrace
import com.migestor.shared.domain.NotebookTab
import com.migestor.shared.domain.QuickNotePhrase
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Migración 50: peso de bloque en las pestañas y fichas propias de «Valoración rápida». */
class EvaluationTabAndQuickNotePhraseTest {

    private fun newContainer(enforceForeignKeys: Boolean = false): KmpContainer {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        if (enforceForeignKeys) driver.execute(null, "PRAGMA foreign_keys = ON", 0)
        return KmpContainer(driver)
    }

    private fun at(ms: Long) = AuditTrace(updatedAt = Instant.fromEpochMilliseconds(ms))

    @Test
    fun guardaYLeeElPesoDelBloque() = runTest {
        val c = newContainer()
        val classId = c.classesRepository.saveClass(name = "2º ESO B (inventado)", course = 2)
        val repo = c.notebookConfigRepository
        repo.saveTab(classId, NotebookTab(id = "ev1", title = "1.ª Evaluación", order = 0, trace = at(1_000)))
        repo.saveTab(classId, NotebookTab(id = "hockey", title = "Hockey", order = 0, parentTabId = "ev1", weight = 60.0, trace = at(1_000)))
        repo.saveTab(classId, NotebookTab(id = "ultimate", title = "Ultimate", order = 1, parentTabId = "ev1", trace = at(1_000)))

        val tabs = repo.listTabs(classId).associateBy { it.id }
        assertEquals(60.0, tabs.getValue("hockey").weight)
        assertNull(tabs.getValue("ultimate").weight)
    }

    @Test
    fun guardarLaEvaluacionNoBorraSusBloquesAunConClavesAjenas() = runTest {
        // Con REPLACE y las claves ajenas activas, guardar el padre arrastraba a las hijas.
        val c = newContainer(enforceForeignKeys = true)
        val classId = c.classesRepository.saveClass(name = "2º ESO B (inventado)", course = 2)
        val repo = c.notebookConfigRepository
        repo.saveTab(classId, NotebookTab(id = "ev1", title = "1.ª Evaluación", order = 0, trace = at(1_000)))
        repo.saveTab(classId, NotebookTab(id = "hockey", title = "Hockey", order = 0, parentTabId = "ev1", weight = 60.0, trace = at(1_000)))

        repo.saveTab(classId, NotebookTab(id = "ev1", title = "1.ª Evaluación (renombrada)", order = 0, trace = at(2_000)))

        val tabs = repo.listTabs(classId).associateBy { it.id }
        assertEquals("1.ª Evaluación (renombrada)", tabs.getValue("ev1").title)
        assertEquals("ev1", tabs.getValue("hockey").parentTabId)
    }

    @Test
    fun borrarLaEvaluacionSueltaSusBloques() = runTest {
        val c = newContainer(enforceForeignKeys = true)
        val classId = c.classesRepository.saveClass(name = "2º ESO B (inventado)", course = 2)
        val repo = c.notebookConfigRepository
        repo.saveTab(classId, NotebookTab(id = "ev1", title = "1.ª Evaluación", order = 0, trace = at(1_000)))
        repo.saveTab(classId, NotebookTab(id = "hockey", title = "Hockey", order = 0, parentTabId = "ev1", weight = 60.0, trace = at(1_000)))

        repo.deleteTab("ev1")

        val tabs = repo.listTabs(classId)
        assertEquals(listOf("hockey"), tabs.map { it.id })
        assertNull(tabs.single().parentTabId)
        assertNull(tabs.single().weight)
        assertTrue(tabs.single().trace.updatedAt.toEpochMilliseconds() > 1_000)
    }

    @Test
    fun elPesoViajaPorSyncYUnDispositivoAntiguoNoLoBorra() = runTest {
        val mac = newContainer()
        val ipad = newContainer()
        val classId = mac.classesRepository.saveClass(name = "2º ESO B (inventado)", course = 2)
        ipad.classesRepository.saveClass(name = "2º ESO B (inventado)", course = 2)
        mac.notebookConfigRepository.saveTab(classId, NotebookTab(id = "ev1", title = "1.ª Evaluación", order = 0, trace = at(1_000)))
        mac.notebookConfigRepository.saveTab(classId, NotebookTab(id = "hockey", title = "Hockey", order = 0, parentTabId = "ev1", weight = 60.0, trace = at(1_000)))

        val changes = SqlDelightSyncAdapter(mac, "mac").collectLocalChanges(0).filter { it.entity == "notebook_tab" }
        assertTrue(changes.any { it.id == "hockey" && "\"weight\":60.0" in it.payload })
        SqlDelightSyncAdapter(ipad, "ipad").applyIncomingChangesLww(changes)
        assertEquals(60.0, ipad.notebookConfigRepository.listTabs(classId).single { it.id == "hockey" }.weight)

        // Un dispositivo antiguo reenvía la pestaña sin la clave «weight»: el peso se conserva.
        val old = changes.single { it.id == "hockey" }
        val withoutWeight = old.copy(
            updatedAtEpochMs = 5_000,
            payload = old.payload.replace(",\"weight\":60.0", ""),
        )
        assertTrue("weight" !in withoutWeight.payload)
        SqlDelightSyncAdapter(ipad, "ipad").applyIncomingChangesLww(listOf(withoutWeight))
        assertEquals(60.0, ipad.notebookConfigRepository.listTabs(classId).single { it.id == "hockey" }.weight)
    }

    @Test
    fun lasFichasPropiasSeSincronizanTambienAlBorrarlas() = runTest {
        val mac = newContainer()
        val ipad = newContainer()
        mac.quickNotePhraseRepository.save(QuickNotePhrase(id = "f1", group = "strength", text = "Liderazgo en el juego", trace = at(1_000)))

        var collected = ModuleRecordsSync(mac, "mac").collect(0)
        ModuleRecordsSync(ipad, "ipad").applyAll(collected.changes)
        assertEquals("Liderazgo en el juego", ipad.quickNotePhraseRepository.get("f1")?.text)

        // Borrado lógico en el Mac: llega como un cambio más.
        mac.quickNotePhraseRepository.save(
            mac.quickNotePhraseRepository.get("f1")!!.copy(isDeleted = true, trace = at(2_000)),
        )
        collected = ModuleRecordsSync(mac, "mac").collect(1_500)
        assertEquals(1, collected.changes.count { it.entity == ModuleRecordsSync.QUICK_NOTE_PHRASE })
        ModuleRecordsSync(ipad, "ipad").applyAll(collected.changes)
        assertEquals(true, ipad.quickNotePhraseRepository.get("f1")?.isDeleted)

        // Un cambio más viejo no pisa lo que ya hay.
        val stale = collected.changes.single().copy(updatedAtEpochMs = 500, payload = collected.changes.single().payload.replace("true", "false"))
        val ack = ModuleRecordsSync(ipad, "ipad").applyAll(listOf(stale))
        assertEquals(1, ack.conflictsResolvedByLww)
        assertEquals(true, ipad.quickNotePhraseRepository.get("f1")?.isDeleted)
    }

    @Test
    fun laMigracion50AnadeElPesoYLaTablaDeFichas() {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        fun columns(table: String): List<String> = driver.executeQuery(null, "PRAGMA table_info($table)", { cursor ->
            val names = mutableListOf<String>()
            while (cursor.next().value) names += cursor.getString(1)!!
            app.cash.sqldelight.db.QueryResult.Value(names)
        }, 0).value
        assertTrue("weight" in columns("notebook_tabs"))
        assertEquals(
            listOf("id", "group_key", "text", "sort_order", "is_deleted", "updated_at_epoch_ms", "device_id", "sync_version"),
            columns("quick_note_phrases"),
        )
    }
}
