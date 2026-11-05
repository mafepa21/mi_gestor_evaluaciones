package com.migestor.desktop.sync

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import com.migestor.data.sync.SqlDelightSyncAdapter
import com.migestor.shared.domain.PlanningSession
import com.migestor.shared.domain.SessionStatus
import com.migestor.shared.domain.TeachingUnit
import com.migestor.shared.sync.SyncChange
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Verifica que el Smart Merge (Last-Write-Wins por registro y apartado) conserve
 * la última modificación de cada dispositivo sin machacar cambios más recientes
 * de otros apartados al sincronizar o emparejar.
 */
class SqlDelightSyncAdapterSmartMergeTest {

    private fun newContainer(): KmpContainer {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        return KmpContainer(driver)
    }

    @Test
    fun `smart merge conserva cuaderno reciente del Mac y asistencia e incidencias recientes del iPad`() = runTest {
        val mac = newContainer()
        val ipad = newContainer()

        // Estado base compartido en t = 1000 en ambos dispositivos
        val macClassId = mac.classesRepository.saveClass(
            id = 1L,
            name = "1 ESO A",
            course = 1,
            updatedAtEpochMs = 1_000L,
            deviceId = "mac",
            syncVersion = 1,
        )
        ipad.classesRepository.saveClass(
            id = macClassId,
            name = "1 ESO A",
            course = 1,
            updatedAtEpochMs = 1_000L,
            deviceId = "mac",
            syncVersion = 1,
        )

        val studentId = mac.studentsRepository.saveStudent(
            id = 10L,
            firstName = "Lucía",
            lastName = "Gómez",
            updatedAtEpochMs = 1_000L,
            deviceId = "mac",
            syncVersion = 1,
        )
        ipad.studentsRepository.saveStudent(
            id = studentId,
            firstName = "Lucía",
            lastName = "Gómez",
            updatedAtEpochMs = 1_000L,
            deviceId = "mac",
            syncVersion = 1,
        )

        // En t = 1000 ambos tienen Nota = 6.0 y Asistencia = PRESENT
        mac.gradesRepository.upsertGrade(
            classId = macClassId,
            studentId = studentId,
            columnId = "eval_1",
            evaluationId = null,
            value = 6.0,
            evidence = "Inicial",
            updatedAtEpochMs = 1_000L,
            deviceId = "mac",
            syncVersion = 1,
        )
        ipad.gradesRepository.upsertGrade(
            classId = macClassId,
            studentId = studentId,
            columnId = "eval_1",
            evaluationId = null,
            value = 6.0,
            evidence = "Inicial",
            updatedAtEpochMs = 1_000L,
            deviceId = "mac",
            syncVersion = 1,
        )

        val dayEpochMs = 1_700_000_000_000L
        mac.attendanceRepository.saveAttendance(
            id = 100L,
            studentId = studentId,
            classId = macClassId,
            dateEpochMs = dayEpochMs,
            status = "PRESENT",
            note = "A tiempo",
            hasIncident = false,
            followUpRequired = false,
            sessionId = null,
            updatedAtEpochMs = 1_000L,
            deviceId = "mac",
            syncVersion = 1,
        )
        ipad.attendanceRepository.saveAttendance(
            id = 100L,
            studentId = studentId,
            classId = macClassId,
            dateEpochMs = dayEpochMs,
            status = "PRESENT",
            note = "A tiempo",
            hasIncident = false,
            followUpRequired = false,
            sessionId = null,
            updatedAtEpochMs = 1_000L,
            deviceId = "mac",
            syncVersion = 1,
        )

        // 1. El docente modifica el Cuaderno en el Mac en t = 5_000 (Nota = 9.5)
        mac.gradesRepository.upsertGrade(
            classId = macClassId,
            studentId = studentId,
            columnId = "eval_1",
            evaluationId = null,
            value = 9.5,
            evidence = "Subida en Mac",
            updatedAtEpochMs = 5_000L,
            deviceId = "mac",
            syncVersion = 2,
        )

        // 2. El docente modifica la Asistencia y una Incidencia en el iPad en t = 8_000
        ipad.attendanceRepository.saveAttendance(
            id = 100L,
            studentId = studentId,
            classId = macClassId,
            dateEpochMs = dayEpochMs,
            status = "ABSENT",
            note = "Falta justificada en iPad",
            hasIncident = true,
            followUpRequired = true,
            sessionId = null,
            updatedAtEpochMs = 8_000L,
            deviceId = "ipad",
            syncVersion = 2,
        )
        ipad.incidentsRepository.saveIncident(
            id = 200L,
            classId = macClassId,
            studentId = studentId,
            title = "Olvido de material",
            detail = "Registrado en iPad",
            severity = "medium",
            dateEpochMs = dayEpochMs,
            authorUserId = null,
            updatedAtEpochMs = 8_500L,
            deviceId = "ipad",
            syncVersion = 1,
        )

        val macAdapter = SqlDelightSyncAdapter(mac, localDeviceId = "mac")
        val ipadAdapter = SqlDelightSyncAdapter(ipad, localDeviceId = "ipad")

        // Sincronización completa bidireccional (since = 0L, como al emparejar o igualar con Smart Merge)
        val ipadChanges = ipadAdapter.collectLocalChanges(0L)
        macAdapter.applyIncomingChangesLww(ipadChanges)

        val macChanges = macAdapter.collectLocalChanges(0L)
        ipadAdapter.applyIncomingChangesLww(macChanges)

        // Ambos dispositivos deben tener la nota 9.5 del Mac y la asistencia ABSENT + incidencia del iPad
        val macGrade = mac.gradesRepository.listGradesForStudentInClass(studentId, macClassId).single { it.columnId == "eval_1" }
        val ipadGrade = ipad.gradesRepository.listGradesForStudentInClass(studentId, macClassId).single { it.columnId == "eval_1" }
        assertEquals(9.5, macGrade.value)
        assertEquals("Subida en Mac", macGrade.evidence)
        assertEquals(9.5, ipadGrade.value)
        assertEquals("Subida en Mac", ipadGrade.evidence)

        val macAttendance = mac.attendanceRepository.listAttendanceByDate(macClassId, dayEpochMs).single()
        val ipadAttendance = ipad.attendanceRepository.listAttendanceByDate(macClassId, dayEpochMs).single()
        assertEquals("ABSENT", macAttendance.status)
        assertEquals("Falta justificada en iPad", macAttendance.note)
        assertEquals("ABSENT", ipadAttendance.status)
        assertEquals("Falta justificada en iPad", ipadAttendance.note)

        val macIncident = mac.incidentsRepository.listIncidents(macClassId).single()
        val ipadIncident = ipad.incidentsRepository.listIncidents(macClassId).single()
        assertEquals("Olvido de material", macIncident.title)
        assertEquals("Olvido de material", ipadIncident.title)
    }

    @Test
    fun `un cambio antiguo de unidad didactica sesion u horario no pisa uno mas reciente`() = runTest {
        val container = newContainer()
        val adapter = SqlDelightSyncAdapter(container, localDeviceId = "mac")

        val classId = container.classesRepository.saveClass(
            id = 1L,
            name = "2 ESO B",
            course = 2,
            updatedAtEpochMs = 2_000L,
            deviceId = "mac",
            syncVersion = 1,
        )

        // Aplicamos una unidad didáctica y sesión con fecha 10_000L
        adapter.applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "teaching_unit",
                    id = "1",
                    updatedAtEpochMs = 10_000L,
                    deviceId = "mac",
                    payload = """{"id":1,"name":"Acrosport Avanzado","description":"Versión nueva","colorHex":"#112233","groupId":$classId,"schoolClassId":$classId}""",
                ),
                SyncChange(
                    entity = "planning_session",
                    id = "1",
                    updatedAtEpochMs = 10_000L,
                    deviceId = "mac",
                    payload = """{"id":1,"teachingUnitId":1,"teachingUnitName":"Acrosport Avanzado","groupId":$classId,"groupName":"2 ESO B","dayOfWeek":1,"period":1,"weekNumber":40,"year":2026,"objectives":"Pirámides seguras","activities":"Trabajo cooperativo","evaluation":"Rúbrica","status":"COMPLETED"}""",
                ),
            )
        )

        // Llega un snapshot antiguo (t = 3_000L) de otro dispositivo
        val staleAck = adapter.applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "teaching_unit",
                    id = "1",
                    updatedAtEpochMs = 3_000L,
                    deviceId = "ipad",
                    payload = """{"id":1,"name":"Acrosport Borrador","description":"Versión vieja","colorHex":"#4A90D9","groupId":$classId,"schoolClassId":$classId}""",
                ),
                SyncChange(
                    entity = "planning_session",
                    id = "1",
                    updatedAtEpochMs = 3_000L,
                    deviceId = "ipad",
                    payload = """{"id":1,"teachingUnitId":1,"teachingUnitName":"Acrosport Borrador","groupId":$classId,"groupName":"2 ESO B","dayOfWeek":1,"period":1,"weekNumber":40,"year":2026,"objectives":"Objetivo viejo","activities":"","evaluation":"","status":"PLANNED"}""",
                ),
                SyncChange(
                    entity = "planning_session",
                    id = "1",
                    updatedAtEpochMs = 4_000L,
                    deviceId = "ipad",
                    payload = """{"id":1}""",
                    op = "delete",
                ),
            )
        )

        assertEquals(0, staleAck.applied)
        assertEquals(2, staleAck.conflictsResolvedByLww)
        assertEquals(1, staleAck.ignored)

        val unit = container.plannerRepository.listAllTeachingUnits().single()
        assertEquals("Acrosport Avanzado", unit.name)
        assertEquals("Versión nueva", unit.description)

        val session = container.plannerRepository.listAllSessions().single()
        assertEquals("Pirámides seguras", session.objectives)
        assertEquals(SessionStatus.COMPLETED, session.status)
    }
}
