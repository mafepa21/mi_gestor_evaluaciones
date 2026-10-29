package com.migestor.data.repository

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.platform.WipeCategory
import com.migestor.data.platform.wipeSelectiveUserData
import com.migestor.shared.domain.SupportMeasureLevel
import com.migestor.shared.evaluationsession.EvaluationKind
import com.migestor.shared.evaluationsession.EvaluationSession
import com.migestor.shared.evaluationsession.EvaluationSessionClosedException
import com.migestor.shared.evaluationsession.EvaluationSessionDuplicateException
import com.migestor.shared.evaluationsession.EvaluationSessionStudentSnapshot
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Solo datos de prueba. */
class EvaluationSessionRepositorySqlDelightTest {

    private class Entorno(
        val driver: JdbcSqliteDriver,
        val db: AppDatabase,
        val repo: EvaluationSessionRepositorySqlDelight,
        val classId: Long,
        val ana: Long,
        val blas: Long,
    )

    private suspend fun entorno(foreignKeys: Boolean): Entorno {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        if (foreignKeys) driver.execute(null, "PRAGMA foreign_keys = ON", 0)
        val db = AppDatabase(driver)
        val classId = ClassesRepositorySqlDelight(db).saveClass(name = "2 ESO B", course = 2, description = "Prueba")
        val students = StudentsRepositorySqlDelight(db)
        val ana = students.saveStudent(firstName = "Ana", lastName = "Prueba")
        val blas = students.saveStudent(firstName = "Blas", lastName = "Ejemplo")
        return Entorno(driver, db, EvaluationSessionRepositorySqlDelight(db), classId, ana, blas)
    }

    private fun junta(classId: Long, kind: EvaluationKind = EvaluationKind.FIRST, id: String = "junta-1") =
        EvaluationSession(
            id = id,
            classId = classId,
            kind = kind,
            label = kind.defaultLabel,
            dateIso = "2026-12-18",
            createdAtEpochMs = 10,
            updatedAtEpochMs = 10,
        )

    private fun snapshot(studentId: Long, average: Double?, level: SupportMeasureLevel? = null) =
        EvaluationSessionStudentSnapshot(
            studentId = studentId,
            average = average,
            ownFailed = average?.let { it < 5.0 },
            absencePercent = 12.5,
            absenceCount = 3,
            supportLevel = level,
            incidentCount = 1,
        )

    @Test
    fun `crea una junta con sus filas de alumnado y valores por defecto`() = runTest {
        val e = entorno(foreignKeys = true)
        e.repo.insertSession(junta(e.classId))
        assertEquals(2, e.repo.ensureStudents("junta-1", listOf(e.ana, e.blas, e.ana), nowEpochMs = 20))
        assertEquals(0, e.repo.ensureStudents("junta-1", listOf(e.ana, e.blas), nowEpochMs = 30))

        val sesion = assertNotNull(e.repo.getSession("junta-1"))
        assertEquals(EvaluationKind.FIRST, sesion.kind)
        assertEquals("", sesion.attendees)
        assertFalse(sesion.isClosed)
        assertNull(sesion.closedAtEpochMs)

        val filas = e.repo.listStudents("junta-1")
        // Orden por apellido: Ejemplo antes que Prueba.
        assertEquals(listOf("Blas", "Ana"), filas.map { it.firstName })
        filas.forEach {
            assertEquals(0, it.otherFailedCount)
            assertEquals("", it.agreement)
            assertFalse(it.isReviewed)
            assertNull(it.frozenAverage)
            assertNull(it.frozenSupportLevel)
        }

        e.repo.updateHeader("junta-1", "1ª evaluación", null, "2026-12-19", "Tutora, Orientación", "Acuerdo general", 40)
        e.repo.updateStudent("junta-1", e.ana, otherFailedCount = 2, agreement = "Refuerzo", isReviewed = true, nowEpochMs = 41)
        val ana = e.repo.listStudents("junta-1").first { it.studentId == e.ana }
        assertEquals(2, ana.otherFailedCount)
        assertEquals("Refuerzo", ana.agreement)
        assertTrue(ana.isReviewed)
        assertEquals("Tutora, Orientación", e.repo.getSession("junta-1")?.attendees)
    }

    @Test
    fun `una segunda junta de la misma evaluacion en el grupo da un error claro`() = runTest {
        val e = entorno(foreignKeys = true)
        e.repo.insertSession(junta(e.classId))
        val error = assertFailsWith<EvaluationSessionDuplicateException> {
            e.repo.insertSession(junta(e.classId, id = "junta-2"))
        }
        assertTrue(error.message!!.contains("1ª evaluación"))
        // Otra evaluación del mismo grupo sí se puede.
        e.repo.insertSession(junta(e.classId, kind = EvaluationKind.INITIAL, id = "junta-3"))
        assertEquals(2, e.repo.listSessions(e.classId).size)
    }

    @Test
    fun `cerrar congela, editar cerrada se rechaza y reabrir conserva los congelados`() = runTest {
        val e = entorno(foreignKeys = true)
        e.repo.insertSession(junta(e.classId))
        e.repo.ensureStudents("junta-1", listOf(e.ana, e.blas), 20)

        e.repo.closeSession(
            "junta-1",
            listOf(snapshot(e.ana, 4.2, SupportMeasureLevel.IV), snapshot(e.blas, null)),
            nowEpochMs = 50,
        )
        val cerrada = assertNotNull(e.repo.getSession("junta-1"))
        assertTrue(cerrada.isClosed)
        assertEquals(50L, cerrada.closedAtEpochMs)
        val ana = e.repo.listStudents("junta-1").first { it.studentId == e.ana }
        assertEquals(4.2, ana.frozenAverage)
        assertEquals(true, ana.frozenOwnFailed)
        assertEquals(12.5, ana.frozenAbsencePercent)
        assertEquals(3, ana.frozenAbsenceCount)
        assertEquals(SupportMeasureLevel.IV, ana.frozenSupportLevel)
        assertEquals(1, ana.frozenIncidentCount)
        val blas = e.repo.listStudents("junta-1").first { it.studentId == e.blas }
        assertNull(blas.frozenAverage)
        assertNull(blas.frozenOwnFailed)
        assertNull(blas.frozenSupportLevel)

        assertFailsWith<EvaluationSessionClosedException> {
            e.repo.updateStudent("junta-1", e.ana, 1, "x", false, 60)
        }
        assertFailsWith<EvaluationSessionClosedException> {
            e.repo.updateHeader("junta-1", "x", null, "2026-12-20", "", "", 60)
        }
        assertFailsWith<EvaluationSessionClosedException> {
            e.repo.closeSession("junta-1", emptyList(), 61)
        }
        assertEquals("", e.repo.listStudents("junta-1").first { it.studentId == e.ana }.agreement)

        e.repo.reopenSession("junta-1", 70)
        val reabierta = assertNotNull(e.repo.getSession("junta-1"))
        assertFalse(reabierta.isClosed)
        assertNull(reabierta.closedAtEpochMs)
        assertEquals(4.2, e.repo.listStudents("junta-1").first { it.studentId == e.ana }.frozenAverage)

        // Al volver a cerrar, los congelados se sobrescriben.
        e.repo.updateStudent("junta-1", e.ana, 1, "Seguimiento", true, 71)
        e.repo.closeSession("junta-1", listOf(snapshot(e.ana, 6.0), snapshot(e.blas, 7.0)), 80)
        val ana2 = e.repo.listStudents("junta-1").first { it.studentId == e.ana }
        assertEquals(6.0, ana2.frozenAverage)
        assertEquals(false, ana2.frozenOwnFailed)
        assertNull(ana2.frozenSupportLevel)
        assertEquals("Seguimiento", ana2.agreement)
    }

    @Test
    fun `borrar la junta borra sus filas`() = runTest {
        val e = entorno(foreignKeys = false)
        e.repo.insertSession(junta(e.classId))
        e.repo.ensureStudents("junta-1", listOf(e.ana, e.blas), 20)
        e.repo.deleteSession("junta-1")
        assertNull(e.repo.getSession("junta-1"))
        assertEquals(0L, e.driver.scalarLong("SELECT COUNT(*) FROM evaluation_session_students"))
    }

    @Test
    fun `con claves ajenas apagadas los repositorios de alumnado y grupos limpian las juntas`() = runTest {
        val e = entorno(foreignKeys = false)
        e.repo.insertSession(junta(e.classId))
        e.repo.ensureStudents("junta-1", listOf(e.ana, e.blas), 20)

        StudentsRepositorySqlDelight(e.db).deleteStudent(e.ana)
        assertEquals(1L, e.driver.scalarLong("SELECT COUNT(*) FROM evaluation_session_students"))
        assertEquals(1L, e.driver.scalarLong("SELECT COUNT(*) FROM evaluation_sessions"))

        ClassesRepositorySqlDelight(e.db).deleteClass(e.classId)
        assertEquals(0L, e.driver.scalarLong("SELECT COUNT(*) FROM evaluation_sessions"))
        assertEquals(0L, e.driver.scalarLong("SELECT COUNT(*) FROM evaluation_session_students"))
    }

    @Test
    fun `con claves ajenas activas borrar grupo o alumno borra sus filas`() = runTest {
        val e = entorno(foreignKeys = true)
        e.repo.insertSession(junta(e.classId))
        e.repo.ensureStudents("junta-1", listOf(e.ana, e.blas), 20)

        e.driver.execute(null, "DELETE FROM students WHERE id = ${e.ana}", 0)
        assertEquals(1L, e.driver.scalarLong("SELECT COUNT(*) FROM evaluation_session_students"))

        e.driver.execute(null, "DELETE FROM classes WHERE id = ${e.classId}", 0)
        assertEquals(0L, e.driver.scalarLong("SELECT COUNT(*) FROM evaluation_sessions"))
        assertEquals(0L, e.driver.scalarLong("SELECT COUNT(*) FROM evaluation_session_students"))
    }

    @Test
    fun `con claves ajenas apagadas las filas huerfanas no se ven`() = runTest {
        val e = entorno(foreignKeys = false)
        e.repo.insertSession(junta(e.classId))
        e.repo.ensureStudents("junta-1", listOf(e.ana, e.blas), 20)

        e.driver.execute(null, "DELETE FROM students WHERE id = ${e.ana}", 0)
        // La fila sigue en disco (sin cascada), pero no se lee.
        assertEquals(2L, e.driver.scalarLong("SELECT COUNT(*) FROM evaluation_session_students"))
        assertEquals(listOf(e.blas), e.repo.listStudents("junta-1").map { it.studentId })
    }

    @Test
    fun `el borrado selectivo de cursos deja las tablas de juntas vacias`() = runTest {
        val e = entorno(foreignKeys = false)
        e.repo.insertSession(junta(e.classId))
        e.repo.ensureStudents("junta-1", listOf(e.ana, e.blas), 20)

        wipeSelectiveUserData(e.driver, e.db, setOf(WipeCategory.CLASSES))

        assertEquals(0L, e.driver.scalarLong("SELECT COUNT(*) FROM evaluation_sessions"))
        assertEquals(0L, e.driver.scalarLong("SELECT COUNT(*) FROM evaluation_session_students"))
        assertTrue("evaluation_session_students" in WipeCategory.STUDENTS.tableNames)
    }

    @Test
    fun `la migracion 47 crea las tablas de juntas de forma idempotente`() {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        driver.execute(null, "DROP TABLE evaluation_session_students", 0)
        driver.execute(null, "DROP TABLE evaluation_sessions", 0)
        assertEquals(0L, driver.scalarLong("SELECT COUNT(*) FROM sqlite_master WHERE name LIKE 'evaluation_session%'"))

        AppDatabase.Schema.migrate(driver, 47, 48)
        AppDatabase.Schema.migrate(driver, 47, 48) // repetirla no debe fallar

        assertEquals(
            listOf("evaluation_session_students", "evaluation_sessions"),
            driver.queryStrings(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'evaluation_session%' ORDER BY name",
            ),
        )
        assertEquals(
            listOf("idx_evaluation_session_students_student", "idx_evaluation_sessions_class_kind"),
            driver.queryStrings(
                "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_evaluation_session%' ORDER BY name",
            ),
        )
        assertEquals(48L, AppDatabase.Schema.version)
    }
}
