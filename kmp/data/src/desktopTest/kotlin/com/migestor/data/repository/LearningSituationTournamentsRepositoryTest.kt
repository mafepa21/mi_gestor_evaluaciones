package com.migestor.data.repository

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.shared.domain.LearningSituation
import com.migestor.shared.domain.LearningSituationTournament
import com.migestor.shared.domain.AuditTrace
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.Instant
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
    fun `un torneo puede ser solo de un curso, sin situacion`() = runTest {
        val (_, repo, classes) = nuevoEntorno()
        val claseB = classes.saveClass(name = "2 ESO B", course = 2, description = "EF")
        val claseC = classes.saveClass(name = "2 ESO C", course = 2, description = "EF")
        val sda = repo.saveSituation(situacion("SdA con torneo"))

        repo.saveTournament(
            LearningSituationTournament(id = "solo-curso", classId = claseB, name = "Torneo antiguo", format = "league")
        )
        repo.saveTournament(
            LearningSituationTournament(
                id = "con-sda", learningSituationId = sda, classId = claseB, name = "Torneo SdA", format = "knockout",
            )
        )
        repo.saveTournament(
            LearningSituationTournament(id = "otro-curso", classId = claseC, name = "Torneo C", format = "league")
        )

        val sinSda = assertNotNull(repo.getTournament("solo-curso"))
        assertNull(sinSda.learningSituationId)
        assertEquals(setOf("solo-curso", "con-sda"), repo.listTournamentsByClass(claseB).map { it.id }.toSet())
        assertEquals(listOf("otro-curso"), repo.listTournamentsByClass(claseC).map { it.id })
        assertEquals(setOf("solo-curso", "otro-curso"), repo.listTournamentsWithoutSituation().map { it.id }.toSet())
        // Las consultas por situacion no devuelven los torneos sin situacion.
        assertEquals(listOf("con-sda"), repo.listTournaments(sda).map { it.id })

        // Borrar la situacion no toca los torneos de solo curso.
        repo.deleteSituation(sda)
        assertEquals(setOf("solo-curso", "otro-curso"), repo.listAllTournaments().map { it.id }.toSet())
    }

    @Test
    fun `el guardado de sync conserva updatedAt y createdAt entrantes y el local usa ahora`() = runTest {
        val (_, repo, classes) = nuevoEntorno()
        val clase = classes.saveClass(name = "2 ESO B", course = 2, description = "EF")
        val creado = Instant.fromEpochMilliseconds(1_000_000)
        val remoto = Instant.fromEpochMilliseconds(2_000_000)

        repo.saveTournamentFromSync(
            LearningSituationTournament(
                id = "sync-1", classId = clase, name = "Remoto", format = "league",
                trace = AuditTrace(createdAt = creado, updatedAt = remoto, deviceId = "otro", syncVersion = 1),
            )
        )
        val guardado = assertNotNull(repo.getTournament("sync-1"))
        assertEquals(2_000_000L, guardado.trace.updatedAt.toEpochMilliseconds())
        assertEquals(1_000_000L, guardado.trace.createdAt.toEpochMilliseconds())

        // Un segundo cambio de sync mantiene la creacion original y fija el nuevo updatedAt.
        repo.saveTournamentFromSync(
            LearningSituationTournament(
                id = "sync-1", classId = clase, name = "Remoto 2", format = "league",
                trace = AuditTrace(createdAt = remoto, updatedAt = Instant.fromEpochMilliseconds(3_000_000)),
            )
        )
        val segundo = assertNotNull(repo.getTournament("sync-1"))
        assertEquals(3_000_000L, segundo.trace.updatedAt.toEpochMilliseconds())
        assertEquals(1_000_000L, segundo.trace.createdAt.toEpochMilliseconds())

        // Guardado local: updatedAt es "ahora" (muy posterior a 3_000_000) y se respeta createdAt.
        repo.saveTournament(segundo.copy(name = "Local"))
        val local = assertNotNull(repo.getTournament("sync-1"))
        assertTrue(local.trace.updatedAt.toEpochMilliseconds() > 3_000_000L)
        assertEquals(1_000_000L, local.trace.createdAt.toEpochMilliseconds())

        // Un torneo nuevo guardado en local usa el createdAt recibido (p. ej. migrado).
        repo.saveTournament(
            LearningSituationTournament(
                id = "migrado", classId = clase, name = "Migrado", format = "league",
                trace = AuditTrace(createdAt = creado, updatedAt = creado),
            )
        )
        assertEquals(1_000_000L, assertNotNull(repo.getTournament("migrado")).trace.createdAt.toEpochMilliseconds())
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
