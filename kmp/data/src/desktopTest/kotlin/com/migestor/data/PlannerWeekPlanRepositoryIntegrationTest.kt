package com.migestor.data

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.repository.ClassesRepositorySqlDelight
import com.migestor.data.repository.PlannerWeekPlanRepositorySqlDelight
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PlannerWeekPlanRepositoryIntegrationTest {

    private fun newDb(enforceForeignKeys: Boolean = false): AppDatabase {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        if (enforceForeignKeys) {
            driver.execute(null, "PRAGMA foreign_keys = ON", 0)
        }
        return AppDatabase(driver)
    }

    @Test
    fun `guarda y recupera el plan de una semana con sus listas`() = runTest {
        val db = newDb()
        val classesRepo = ClassesRepositorySqlDelight(db)
        val repo = PlannerWeekPlanRepositorySqlDelight(db)

        val classId = classesRepo.saveClass(name = "3 ESO A", course = 3)

        assertNull(repo.getPlan(classId, 2026, 37), "sin plan aun")

        val id = repo.save(
            classId = classId,
            year = 2026,
            week = 37,
            strategies = listOf("retrieval_practice", "dual_coding"),
            instruments = listOf("rubric", "exit_ticket"),
            notes = "Semana de repaso antes del examen.",
        )
        assertTrue(id > 0)

        val plan = repo.getPlan(classId, 2026, 37)
        assertEquals(listOf("retrieval_practice", "dual_coding"), plan?.strategies)
        assertEquals(listOf("rubric", "exit_ticket"), plan?.instruments)
        assertEquals("Semana de repaso antes del examen.", plan?.notes)
        // Otra semana del mismo grupo no comparte plan.
        assertNull(repo.getPlan(classId, 2026, 38))
    }

    @Test
    fun `editar el plan conserva created_at e incrementa sync_version`() = runTest {
        val db = newDb()
        val classesRepo = ClassesRepositorySqlDelight(db)
        val repo = PlannerWeekPlanRepositorySqlDelight(db)

        val classId = classesRepo.saveClass(name = "4 ESO B", course = 3)

        val id = repo.save(
            classId = classId,
            year = 2026,
            week = 40,
            strategies = listOf("spacing"),
            createdAtEpochMs = 1_000L,
            updatedAtEpochMs = 1_000L,
            syncVersion = 1,
        )

        repo.save(
            id = id,
            classId = classId,
            year = 2026,
            week = 40,
            strategies = listOf("spacing", "interleaving"),
            instruments = listOf("observation"),
            updatedAtEpochMs = 5_000L,
        )

        val fila = db.appDatabaseQueries.selectWeekPlan(classId, 2026, 40).executeAsOne()
        assertEquals("spacing\ninterleaving", fila.strategies)
        assertEquals("observation", fila.instruments)
        assertEquals(5_000L, fila.updated_at_epoch_ms)
        assertEquals(2L, fila.sync_version, "sync_version debe crecer de forma monotona")

        val createdAt = db.appDatabaseQueries.selectWeekPlanCreatedAt(id).executeAsOne()
        assertEquals(1_000L, createdAt, "editar el plan no debe reescribir cuando se creo")
    }

    @Test
    fun `las listas descartan entradas en blanco`() = runTest {
        val db = newDb()
        val classesRepo = ClassesRepositorySqlDelight(db)
        val repo = PlannerWeekPlanRepositorySqlDelight(db)

        val classId = classesRepo.saveClass(name = "1 ESO C", course = 3)

        repo.save(
            classId = classId,
            year = 2026,
            week = 5,
            strategies = listOf("worked_examples", "", "  "),
            instruments = emptyList(),
        )

        val plan = repo.getPlan(classId, 2026, 5)
        assertEquals(listOf("worked_examples"), plan?.strategies, "las claves vacias no deben persistir")
        assertTrue(plan?.instruments?.isEmpty() == true)
    }

    /**
     * Verifica que el DDL declara bien la cascada. Como en el resto de tests, hace
     * falta activar el PRAGMA a mano; en produccion las claves ajenas van OFF y
     * hoy no se activan, asi que la cascada no llega a ejecutarse (problema del
     * esquema, no de esta tabla). Aqui solo se fija que la tabla esta bien
     * declarada para cuando el PRAGMA se active.
     */
    @Test
    fun `borrar el grupo se lleva su plan por cascada`() = runTest {
        val db = newDb(enforceForeignKeys = true)
        val classesRepo = ClassesRepositorySqlDelight(db)
        val repo = PlannerWeekPlanRepositorySqlDelight(db)

        val classId = classesRepo.saveClass(name = "2 ESO A", course = 3)
        repo.save(classId = classId, year = 2026, week = 12, strategies = listOf("elaboration"))

        assertTrue(repo.getPlan(classId, 2026, 12) != null)

        classesRepo.deleteClass(classId)

        assertNull(
            repo.getPlan(classId, 2026, 12),
            "sin ON DELETE CASCADE quedaria un plan huerfano de un grupo que ya no existe",
        )
    }
}
