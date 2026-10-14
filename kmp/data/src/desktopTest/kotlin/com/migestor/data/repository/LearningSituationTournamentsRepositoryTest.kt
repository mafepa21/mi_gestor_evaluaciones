package com.migestor.data.repository

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.shared.domain.LearningSituation
import com.migestor.shared.domain.LearningSituationTournament
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LearningSituationTournamentsRepositoryTest {
    private fun nuevoEntorno(): Triple<JdbcSqliteDriver, LearningSituationsRepositorySqlDelight, ClassesRepositorySqlDelight> {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        driver.execute(null, "PRAGMA foreign_keys = ON", 0)
        val db = AppDatabase(driver)
        return Triple(driver, LearningSituationsRepositorySqlDelight(db), ClassesRepositorySqlDelight(db))
    }

    private fun situacion(titulo: String) = LearningSituation(
        title = titulo,
        stageLabel = "ESO",
        courseLabel = "2 ESO",
        subjectLabel = "Educacion Fisica",
        termLabel = "1",
        centerLabel = "IES Demo",
        sessionCount = 6,
    )

    @Test
    fun `guarda, lista, actualiza y borra torneos de una situacion`() = runTest {
        val (_, repo, classes) = nuevoEntorno()
        val classId = classes.saveClass(name = "2 ESO B", course = 2, description = "EF")
        val sdaA = repo.saveSituation(situacion("Torneo de balonmano"))
        val sdaB = repo.saveSituation(situacion("Otra SdA"))

        repo.saveTournament(
            LearningSituationTournament(
                id = "11111111-1111-1111-1111-111111111111",
                learningSituationId = sdaA,
                classId = classId,
                tabId = null,
                name = "Liga de clase",
                format = "league",
                configJson = """{"rounds":2}""",
                teamSnapshotJson = """[{"id":"a","name":"Rojos"}]""",
            )
        )
        repo.saveTournament(
            LearningSituationTournament(
                id = "22222222-2222-2222-2222-222222222222",
                learningSituationId = sdaB,
                classId = classId,
                name = "Torneo ajeno",
                format = "knockout",
            )
        )

        val deA = repo.listTournaments(sdaA)
        assertEquals(1, deA.size)
        val creado = deA.single()
        assertEquals("Liga de clase", creado.name)
        assertEquals("draft", creado.status)
        assertEquals("{}", creado.resultsJson)
        assertEquals("[]", creado.scheduleJson)
        assertNull(creado.tabId)
        assertEquals(2, repo.listAllTournaments().size)

        // Upsert: mismo id, contenido nuevo; la fecha de creacion se conserva.
        repo.saveTournament(
            creado.copy(status = "running", resultsJson = """{"m1":[3,2]}""", tabId = "tab-1")
        )
        val actualizado = assertNotNull(repo.getTournament(creado.id))
        assertEquals("running", actualizado.status)
        assertEquals("""{"m1":[3,2]}""", actualizado.resultsJson)
        assertEquals("tab-1", actualizado.tabId)
        assertEquals(creado.trace.createdAt, actualizado.trace.createdAt)
        assertEquals(1, repo.listTournaments(sdaA).size)

        repo.deleteTournament(creado.id)
        assertNull(repo.getTournament(creado.id))
        assertTrue(repo.listTournaments(sdaA).isEmpty())
        assertEquals(1, repo.listAllTournaments().size)
    }

    @Test
    fun `borrar la situacion o el grupo elimina sus torneos en cascada`() = runTest {
        val (_, repo, classes) = nuevoEntorno()
        val classId = classes.saveClass(name = "2 ESO B", course = 2, description = "EF")
        val sda = repo.saveSituation(situacion("SdA con torneo"))
        repo.saveTournament(
            LearningSituationTournament(
                id = "t-1", learningSituationId = sda, classId = classId, name = "T1", format = "league",
            )
        )
        repo.deleteSituation(sda)
        assertTrue(repo.listAllTournaments().isEmpty())
    }

    @Test
    fun `la migracion 46 crea la tabla de torneos de forma idempotente`() {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        driver.execute(null, "DROP TABLE learning_situation_tournaments", 0)
        assertEquals(0L, driver.scalarLong("SELECT COUNT(*) FROM sqlite_master WHERE name = 'learning_situation_tournaments'"))

        AppDatabase.Schema.migrate(driver, 46, 47)
        AppDatabase.Schema.migrate(driver, 46, 47) // repetirla no debe fallar

        assertEquals(1L, driver.scalarLong("SELECT COUNT(*) FROM sqlite_master WHERE name = 'learning_situation_tournaments'"))
        assertEquals(
            1L,
            driver.scalarLong("SELECT COUNT(*) FROM sqlite_master WHERE name = 'idx_learning_situation_tournaments_situation'"),
        )
        assertEquals(47L, AppDatabase.Schema.version)
    }
}
