package com.migestor.desktop.sync

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import com.migestor.data.sync.SchoolRecordsSync
import com.migestor.data.sync.SqlDelightSyncAdapter
import com.migestor.shared.domain.SupportMeasureLevel
import com.migestor.shared.domain.SupportMeasureType
import com.migestor.shared.sync.SyncChange
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SchoolRecordsSyncTest {
    private fun newContainer(): KmpContainer {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        return KmpContainer(driver)
    }

    private fun change(entity: String, id: Long, updatedAt: Long, payload: String, op: String = "upsert") =
        SyncChange(entity = entity, id = id.toString(), updatedAtEpochMs = updatedAt, deviceId = "ipad", payload = payload, op = op)

    // Payloads tal cual los manda hoy la app Apple (sin "id" dentro).
    private val ipadMeeting = """{"title":"Claustro","dateIso":"2026-10-20","type":"CLAUSTRO","location":"","attendees":"Todos","summary":"Acta","isClosed":false}"""
    private val ipadAgreement = """{"meetingId":7,"description":"Revisar horarios","responsible":"Jefatura","dueIso":null,"isDone":false}"""

    @Test
    fun elMacYaNoIgnoraLasReunionesQueLlegabanDelIpad() = runTest {
        val mac = newContainer()
        val ack = SqlDelightSyncAdapter(mac, localDeviceId = "mac").applyIncomingChangesLww(
            listOf(
                // El acuerdo llega antes que su reunión: se aplica igual.
                change("meeting_agreements", 3, 1_000, ipadAgreement),
                change("meetings", 7, 1_000, ipadMeeting),
            ),
        )
        assertEquals(2, ack.applied)
        assertEquals(0, ack.ignored)
        assertEquals(0, ack.failed)
        val meeting = assertNotNull(mac.meetingRepository.getById(7))
        assertEquals("Claustro", meeting.title)
        assertEquals("Revisar horarios", meeting.agreements.single().description)
        assertEquals(3, meeting.agreements.single().id)
    }

    @Test
    fun unCambioMasViejoNoPisaLoQueYaHay() = runTest {
        val mac = newContainer()
        val sync = SchoolRecordsSync(mac, localDeviceId = "mac")
        sync.applyAll(listOf(change("meetings", 7, 2_000, ipadMeeting)))
        val ack = sync.applyAll(listOf(change("meetings", 7, 1_000, ipadMeeting.replace("Claustro", "Viejo"))))
        assertEquals(1, ack.conflictsResolvedByLww)
        assertEquals("Claustro", mac.meetingRepository.getById(7)?.title)
    }

    @Test
    fun editarUnaReunionNoBorraSusAcuerdos() = runTest {
        val mac = newContainer()
        val sync = SchoolRecordsSync(mac, localDeviceId = "mac")
        sync.applyAll(listOf(change("meetings", 7, 1_000, ipadMeeting), change("meeting_agreements", 3, 1_000, ipadAgreement)))
        sync.applyAll(listOf(change("meetings", 7, 2_000, ipadMeeting.replace("Acta", "Acta corregida"))))
        val meeting = assertNotNull(mac.meetingRepository.getById(7))
        assertEquals("Acta corregida", meeting.summary)
        assertEquals(1, meeting.agreements.size)
    }

    @Test
    fun retirarUnaMedidaSoloConSuFechaDeFinLaRetira() = runTest {
        val mac = newContainer()
        val studentId = mac.studentsRepository.saveStudent(firstName = "Ana", lastName = "López")
        val sync = SchoolRecordsSync(mac, localDeviceId = "mac")
        val full = """{"studentId":$studentId,"level":"${SupportMeasureLevel.III.name}","measureType":"${SupportMeasureType.entries.first().name}","startDateIso":"2026-09-15","responsible":"","intensity":null,"followUpNotes":"Notas","documentRef":"","reviewDueIso":null,"isActive":true}"""
        sync.applyAll(listOf(change("student_support_measures", 11, 1_000, full)))
        assertTrue(mac.studentSupportMeasureRepository.listByStudent(studentId).single().isActive)

        sync.applyAll(listOf(change("student_support_measures", 11, 2_000, """{"id":11,"endDateIso":"2026-10-01","isActive":false}""")))
        val retired = mac.studentSupportMeasureRepository.listByStudent(studentId).single()
        assertFalse(retired.isActive)
        assertEquals("2026-10-01", retired.endDate.toString())
        assertEquals("Notas", retired.followUpNotes)
    }

    @Test
    fun loQueTieneElMacLlegaIgualAlIpad() = runTest {
        val mac = newContainer()
        val studentId = mac.studentsRepository.saveStudent(firstName = "Ana", lastName = "López")
        mac.meetingRepository.saveMeeting(title = "CCP", dateIso = "2026-10-21", updatedAtEpochMs = 5_000)
        mac.studentTutoringSessionRepository.save(studentId = studentId, dateIso = "2026-10-22", topics = "Faltas", updatedAtEpochMs = 5_000)
        mac.subjectsRepository.saveSubject(code = "EF", name = "Educación Física", updatedAtEpochMs = 5_000)

        val collected = SchoolRecordsSync(mac, localDeviceId = "mac").collect(0L)
        assertEquals(setOf("meetings", "student_tutoring_sessions", "subject"), collected.changes.map { it.entity }.toSet())

        val ipad = newContainer()
        ipad.studentsRepository.saveStudent(firstName = "Ana", lastName = "López")
        val ack = SchoolRecordsSync(ipad, localDeviceId = "ipad").applyAll(collected.changes)
        assertEquals(3, ack.applied)
        assertEquals("CCP", ipad.meetingRepository.listAll().single().title)
        assertEquals("Faltas", ipad.studentTutoringSessionRepository.listByStudent(studentId).single().topics)
        assertEquals("Educación Física", ipad.subjectsRepository.listSubjects().single { it.code == "EF" }.name)
    }

    @Test
    fun unBorradoNoResucitaConUnCambioAnterior() = runTest {
        val mac = newContainer()
        val sync = SchoolRecordsSync(mac, localDeviceId = "mac")
        sync.applyAll(listOf(change("meetings", 7, 1_000, ipadMeeting)))
        sync.applyAll(listOf(change("meetings", 7, 3_000, """{"id":7}""", op = "delete")))
        assertNull(mac.meetingRepository.getById(7))

        val ack = sync.applyAll(listOf(change("meetings", 7, 2_000, ipadMeeting)))
        assertEquals(1, ack.ignored)
        assertNull(mac.meetingRepository.getById(7))
    }

    @Test
    fun elMacAvisaDelBorradoDeUnaReunionEnElSiguientePull() = runTest {
        val mac = newContainer()
        val meetingId = mac.meetingRepository.saveMeeting(title = "CCP", dateIso = "2026-10-21", updatedAtEpochMs = 5_000)
        val adapter = SqlDelightSyncAdapter(mac, localDeviceId = "mac")
        adapter.collectLocalChanges(0L)
        mac.meetingRepository.deleteMeeting(meetingId)
        val deletes = adapter.collectLocalChanges(0L).filter { it.entity == "meetings" && it.op == "delete" }
        assertEquals(listOf(meetingId.toString()), deletes.map { it.id })
    }
}
