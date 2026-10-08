package com.migestor.data

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.repository.InclusionTaskRepositorySqlDelight
import com.migestor.data.repository.StudentsRepositorySqlDelight
import com.migestor.shared.inclusion.InclusionPhase
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class InclusionTaskRepositoryIntegrationTest {
    @Test
    fun `la UNIQUE evita duplicar plantillas pero admite varias tareas libres`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)
        val studentId = StudentsRepositorySqlDelight(db).saveStudent(firstName = "Ana", lastName = "Garcia", email = null)
        val repo = InclusionTaskRepositorySqlDelight(db)

        assertTrue(repo.insertTemplateIfAbsent(studentId, null, "carpeta_roja", "Carpeta", InclusionPhase.SEPTIEMBRE, "2026-09-15", "2026-2027", 1))
        assertFalse(repo.insertTemplateIfAbsent(studentId, null, "carpeta_roja", "Carpeta", InclusionPhase.SEPTIEMBRE, "2026-09-15", "2026-2027", 2))
        // Otro curso: sí se crea.
        assertTrue(repo.insertTemplateIfAbsent(studentId, null, "carpeta_roja", "Carpeta", InclusionPhase.SEPTIEMBRE, "2027-09-15", "2027-2028", 3))

        val free1 = repo.insertFreeTask(studentId, "Llamar", InclusionPhase.OBSERVAR, "2026-10-01", "", "2026-2027", 4)
        val free2 = repo.insertFreeTask(studentId, "Revisar", InclusionPhase.OBSERVAR, "2026-10-02", "", "2026-2027", 5)
        assertTrue(free1 > 0 && free2 > free1)

        val list = repo.listByStudents(listOf(studentId), "2026-2027")
        assertEquals(3, list.size)

        val template = list.first { it.templateKey == "carpeta_roja" }
        repo.setDue(template.id, "2026-09-20", isCustom = true, nowEpochMs = 6)
        assertFalse(repo.updateDueIfNotCustom(template.id, "2026-09-30", 7))
        assertEquals("2026-09-20", repo.getById(template.id)!!.dueDate.toString())

        repo.setDone(free1, "2026-10-01", 8)
        assertEquals("2026-10-01", repo.getById(free1)!!.doneAt.toString())
        repo.setDone(free1, null, 9)
        assertNull(repo.getById(free1)!!.doneAt)

        assertNull(repo.getInitialEvaluationDate(1, "2026-2027"))
        // Sin FK enforcement en este driver basta el id; con FK activas, el grupo debe existir.
        driver.execute(null, "PRAGMA foreign_keys = OFF", 0)
        repo.setInitialEvaluationDate(1, "2026-2027", "2026-10-22")
        repo.setInitialEvaluationDate(1, "2026-2027", "2026-10-29")
        assertEquals("2026-10-29", repo.getInitialEvaluationDate(1, "2026-2027"))
    }
}
