package com.migestor.data

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.repository.StudentTutoringSessionRepositorySqlDelight
import com.migestor.data.repository.StudentsRepositorySqlDelight
import com.migestor.shared.domain.TutoringChannel
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class StudentTutoringSessionRepositoryIntegrationTest {

    private fun newDb(enforceForeignKeys: Boolean = false): AppDatabase {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        if (enforceForeignKeys) {
            driver.execute(null, "PRAGMA foreign_keys = ON", 0)
        }
        return AppDatabase(driver)
    }

    @Test
    fun `guarda, lista y borra una tutoria conservando el resto del historico`() = runTest {
        val db = newDb()
        val studentsRepo = StudentsRepositorySqlDelight(db)
        val tutoringRepo = StudentTutoringSessionRepositorySqlDelight(db)

        val studentId = studentsRepo.saveStudent(firstName = "Ana", lastName = "Garcia", email = null)

        val primera = tutoringRepo.save(
            studentId = studentId,
            dateIso = "2026-10-05",
            channel = TutoringChannel.IN_PERSON,
            attendees = "Madre y padre",
            topics = "Rendimiento en matematicas",
            agreements = "Repasar fracciones 15 min al dia",
            reviewDueIso = "2026-11-05",
        )
        tutoringRepo.save(
            studentId = studentId,
            dateIso = "2026-11-20",
            channel = TutoringChannel.PHONE,
            attendees = "Madre",
            topics = "Seguimiento",
        )

        assertTrue(primera > 0)

        val sesiones = tutoringRepo.listByStudent(studentId)
        assertEquals(2, sesiones.size)
        // Orden descendente por fecha: lo ultimo hablado es lo primero que se lee.
        assertEquals("2026-11-20", sesiones.first().date.toString())
        assertEquals(TutoringChannel.PHONE, sesiones.first().channel)
        assertEquals("Repasar fracciones 15 min al dia", sesiones.last().agreements)

        tutoringRepo.delete(primera)

        val restantes = tutoringRepo.listByStudent(studentId)
        assertEquals(1, restantes.size, "borrar una entrevista no debe llevarse las demas")
        assertEquals("2026-11-20", restantes.first().date.toString())
    }

    @Test
    fun `editar una tutoria conserva created_at e incrementa sync_version`() = runTest {
        val db = newDb()
        val studentsRepo = StudentsRepositorySqlDelight(db)
        val tutoringRepo = StudentTutoringSessionRepositorySqlDelight(db)

        val studentId = studentsRepo.saveStudent(firstName = "Marta", lastName = "Ruiz", email = null)

        val id = tutoringRepo.save(
            studentId = studentId,
            dateIso = "2026-10-05",
            attendees = "Madre",
            topics = "Convivencia",
            createdAtEpochMs = 1_000L,
            updatedAtEpochMs = 1_000L,
            syncVersion = 1,
        )

        tutoringRepo.save(
            id = id,
            studentId = studentId,
            dateIso = "2026-10-05",
            attendees = "Madre y tutor legal",
            topics = "Convivencia",
            agreements = "Reunion de seguimiento en un mes",
            reviewDueIso = "2026-11-05",
            updatedAtEpochMs = 5_000L,
        )

        val fila = db.appDatabaseQueries
            .selectTutoringSessionsByStudent(studentId)
            .executeAsList()
            .single()

        assertEquals("Madre y tutor legal", fila.attendees)
        assertEquals(5_000L, fila.updated_at_epoch_ms)
        assertEquals(2L, fila.sync_version, "sync_version debe crecer de forma monotona")

        // created_at no se expone en el SELECT del repositorio, se comprueba directo.
        val createdAt = db.appDatabaseQueries.selectTutoringSessionCreatedAt(fila.id).executeAsOne()
        assertEquals(1_000L, createdAt, "editar el acta no debe reescribir cuando se registro")
    }

    @Test
    fun `las revisiones pendientes excluyen las cerradas y las sin fecha`() = runTest {
        val db = newDb()
        val studentsRepo = StudentsRepositorySqlDelight(db)
        val tutoringRepo = StudentTutoringSessionRepositorySqlDelight(db)

        val studentId = studentsRepo.saveStudent(firstName = "Luis", lastName = "Perez", email = null)

        val vencida = tutoringRepo.save(
            studentId = studentId,
            dateIso = "2026-10-01",
            reviewDueIso = "2026-10-15",
        )
        tutoringRepo.save(
            studentId = studentId,
            dateIso = "2026-10-02",
            reviewDueIso = "2027-01-01",
        )
        tutoringRepo.save(
            studentId = studentId,
            dateIso = "2026-10-03",
            reviewDueIso = null,
        )
        val cerrada = tutoringRepo.save(
            studentId = studentId,
            dateIso = "2026-10-04",
            reviewDueIso = "2026-10-10",
            isClosed = true,
        )

        val pendientes = tutoringRepo.listPendingReviews("2026-10-31")

        assertEquals(1, pendientes.size, "solo la vencida y abierta")
        assertEquals(vencida, pendientes.first().id)
        assertTrue(pendientes.none { it.id == cerrada })
    }

    @Test
    fun `descarta filas con un canal obsoleto en vez de crashear`() = runTest {
        val db = newDb()
        val studentsRepo = StudentsRepositorySqlDelight(db)
        val tutoringRepo = StudentTutoringSessionRepositorySqlDelight(db)

        val studentId = studentsRepo.saveStudent(firstName = "Sara", lastName = "Lopez", email = null)

        tutoringRepo.save(studentId = studentId, dateIso = "2026-10-05")
        // Simula una fila persistida por una version futura o retirada de la app.
        // listByStudent no debe lanzar: un valueOf fallido cruzaria a Swift como
        // excepcion no capturada y tumbaria la ficha del alumno.
        db.appDatabaseQueries.insertTutoringSession(
            studentId, "2026-10-06", "CARTA_CERTIFICADA", "", "", "", null, 0, 0, 0, null, 0
        )

        val sesiones = tutoringRepo.listByStudent(studentId)
        assertEquals(1, sesiones.size, "la fila con canal obsoleto debe descartarse, no crashear")
        assertEquals(TutoringChannel.IN_PERSON, sesiones.first().channel)
    }

    /**
     * Verifica que el DDL declara bien la cascada. OJO: hace falta activar el
     * PRAGMA a mano porque en SQLite las claves ajenas van OFF por defecto y se
     * fijan por conexion, y **el codigo de produccion no lo activa en ningun
     * sitio** (comprobado 2026-07-22: la base local de un docente responde
     * `PRAGMA foreign_keys` = 0). Es decir, hoy borrar un alumno deja actas
     * huerfanas en la app real. Eso afecta a las 48 tablas del esquema, no solo
     * a esta, y se trata aparte; aqui solo se fija que la tabla esta bien
     * declarada para cuando el PRAGMA se active.
     */
    @Test
    fun `borrar el alumno se lleva sus tutorias por cascada`() = runTest {
        val db = newDb(enforceForeignKeys = true)
        val studentsRepo = StudentsRepositorySqlDelight(db)
        val tutoringRepo = StudentTutoringSessionRepositorySqlDelight(db)

        val studentId = studentsRepo.saveStudent(firstName = "Nuria", lastName = "Diaz", email = null)
        tutoringRepo.save(studentId = studentId, dateIso = "2026-10-05", topics = "Inicio de curso")

        assertEquals(1, tutoringRepo.listByStudent(studentId).size)

        studentsRepo.deleteStudent(studentId)

        assertEquals(
            0,
            tutoringRepo.listByStudent(studentId).size,
            "sin ON DELETE CASCADE quedarian actas huerfanas de un alumno que ya no existe",
        )
        assertNull(studentsRepo.getStudent(studentId))
    }
}
