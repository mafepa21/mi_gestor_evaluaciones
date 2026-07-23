package com.migestor.data

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.repository.MeetingRepositorySqlDelight
import com.migestor.shared.domain.MeetingType
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MeetingRepositoryIntegrationTest {

    private fun newDb(enforceForeignKeys: Boolean = false): AppDatabase {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        if (enforceForeignKeys) {
            driver.execute(null, "PRAGMA foreign_keys = ON", 0)
        }
        return AppDatabase(driver)
    }

    @Test
    fun `guarda, lista y borra una reunion con sus acuerdos`() = runTest {
        val db = newDb()
        val repo = MeetingRepositorySqlDelight(db)

        val claustro = repo.saveMeeting(
            title = "Claustro de inicio de curso",
            dateIso = "2026-09-01",
            type = MeetingType.CLAUSTRO,
            location = "Salon de actos",
            attendees = "Todo el profesorado",
            summary = "Se presenta la PGA y el calendario de evaluaciones.",
        )
        repo.saveAgreement(
            meetingId = claustro,
            description = "Entregar las programaciones didacticas",
            responsible = "Jefes de departamento",
            dueIso = "2026-09-30",
        )
        repo.saveAgreement(
            meetingId = claustro,
            description = "Revisar el plan de convivencia",
            responsible = "Comision de convivencia",
        )
        // Una segunda reunion para comprobar que el borrado no se lleva las demas.
        repo.saveMeeting(
            title = "Reunion de departamento",
            dateIso = "2026-09-15",
            type = MeetingType.DEPARTAMENTO,
        )

        assertTrue(claustro > 0)

        val reuniones = repo.listAll()
        assertEquals(2, reuniones.size)
        // Orden descendente por fecha: lo ultimo reunido es lo primero que se lee.
        assertEquals("2026-09-15", reuniones.first().date.toString())

        val cargado = reuniones.single { it.id == claustro }
        assertEquals(MeetingType.CLAUSTRO, cargado.type)
        assertEquals(2, cargado.agreements.size)
        // Los acuerdos conservan el orden en que se anotaron.
        assertEquals("Entregar las programaciones didacticas", cargado.agreements.first().description)
        assertEquals("2026-09-30", cargado.agreements.first().due.toString())
        assertNull(cargado.agreements.last().due, "el segundo acuerdo no tiene fecha limite")

        repo.deleteMeeting(claustro)

        val restantes = repo.listAll()
        assertEquals(1, restantes.size, "borrar una reunion no debe llevarse las demas")
        assertEquals("Reunion de departamento", restantes.first().title)
    }

    @Test
    fun `editar una reunion conserva created_at e incrementa sync_version`() = runTest {
        val db = newDb()
        val repo = MeetingRepositorySqlDelight(db)

        val id = repo.saveMeeting(
            title = "CCP",
            dateIso = "2026-10-05",
            type = MeetingType.CCP,
            createdAtEpochMs = 1_000L,
            updatedAtEpochMs = 1_000L,
            syncVersion = 1,
        )

        repo.saveMeeting(
            id = id,
            title = "CCP (acta corregida)",
            dateIso = "2026-10-05",
            type = MeetingType.CCP,
            summary = "Se anade el punto sobre la evaluacion de diagnostico.",
            updatedAtEpochMs = 5_000L,
        )

        val fila = db.appDatabaseQueries.selectMeetingById(id).executeAsOne()
        assertEquals("CCP (acta corregida)", fila.title)
        assertEquals(5_000L, fila.updated_at_epoch_ms)
        assertEquals(2L, fila.sync_version, "sync_version debe crecer de forma monotona")

        val createdAt = db.appDatabaseQueries.selectMeetingCreatedAt(id).executeAsOne()
        assertEquals(1_000L, createdAt, "editar el acta no debe reescribir cuando se creo la reunion")
    }

    @Test
    fun `los acuerdos pendientes excluyen los cumplidos y los sin fecha`() = runTest {
        val db = newDb()
        val repo = MeetingRepositorySqlDelight(db)

        val id = repo.saveMeeting(title = "Equipo docente", dateIso = "2026-10-01", type = MeetingType.EQUIPO_DOCENTE)

        val vencido = repo.saveAgreement(
            meetingId = id,
            description = "Coordinar la recuperacion de septiembre",
            dueIso = "2026-10-15",
        )
        repo.saveAgreement(
            meetingId = id,
            description = "Preparar la reunion de familias del segundo trimestre",
            dueIso = "2027-01-20",
        )
        repo.saveAgreement(
            meetingId = id,
            description = "Tarea sin fecha",
            dueIso = null,
        )
        val cumplido = repo.saveAgreement(
            meetingId = id,
            description = "Enviar el acta anterior",
            dueIso = "2026-10-10",
            isDone = true,
        )

        val pendientes = repo.listPendingAgreements("2026-10-31")

        assertEquals(1, pendientes.size, "solo el vencido y sin cumplir")
        assertEquals(vencido, pendientes.first().id)
        assertTrue(pendientes.none { it.id == cumplido })
    }

    @Test
    fun `descarta reuniones con un tipo obsoleto en vez de crashear`() = runTest {
        val db = newDb()
        val repo = MeetingRepositorySqlDelight(db)

        repo.saveMeeting(title = "Reunion valida", dateIso = "2026-10-05", type = MeetingType.OTRA)
        // Simula una fila persistida por una version futura o retirada de la app.
        // listAll no debe lanzar: un valueOf fallido cruzaria a Swift como
        // excepcion no capturada y tumbaria el modulo de reuniones.
        db.appDatabaseQueries.insertMeeting(
            "Reunion con tipo desaparecido", "2026-10-06", "CONSEJO_ESCOLAR", "", "", "", 0, 0, 0, null, 0
        )

        val reuniones = repo.listAll()
        assertEquals(1, reuniones.size, "la fila con tipo obsoleto debe descartarse, no crashear")
        assertEquals(MeetingType.OTRA, reuniones.first().type)
    }

    /**
     * Verifica que el DDL declara bien la cascada. OJO: hace falta activar el
     * PRAGMA a mano porque en SQLite las claves ajenas van OFF por defecto y se
     * fijan por conexion, y **el codigo de produccion no lo activa en ningun
     * sitio** (mismo problema documentado en el test de tutorias). Es decir, hoy
     * borrar una reunion en la app real dejaria sus acuerdos huerfanos. Afecta a
     * todo el esquema y se trata aparte; aqui solo se fija que la tabla esta bien
     * declarada para cuando el PRAGMA se active.
     */
    @Test
    fun `borrar la reunion se lleva sus acuerdos por cascada`() = runTest {
        val db = newDb(enforceForeignKeys = true)
        val repo = MeetingRepositorySqlDelight(db)

        val id = repo.saveMeeting(title = "Reunion con acuerdos", dateIso = "2026-10-05")
        repo.saveAgreement(meetingId = id, description = "Acuerdo 1")
        repo.saveAgreement(meetingId = id, description = "Acuerdo 2", dueIso = "2026-11-01")

        assertEquals(2, repo.getById(id)?.agreements?.size)

        repo.deleteMeeting(id)

        assertNull(repo.getById(id))
        val huerfanos = db.appDatabaseQueries.selectPendingAgreements("2100-01-01").executeAsList()
        assertTrue(
            huerfanos.none { it.meeting_id == id },
            "sin ON DELETE CASCADE quedarian acuerdos huerfanos de una reunion que ya no existe",
        )
    }
}
