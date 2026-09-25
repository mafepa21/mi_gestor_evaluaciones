package com.migestor.desktop.sync

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.di.KmpContainer
import com.migestor.data.sync.SqlDelightSyncAdapter
import com.migestor.data.sync.SyncDatasetFingerprint
import com.migestor.shared.domain.PlanningSession
import com.migestor.shared.domain.SessionJournal
import com.migestor.shared.domain.SessionJournalAction
import com.migestor.shared.domain.SessionJournalAggregate
import com.migestor.shared.domain.SessionJournalIndividualNote
import com.migestor.shared.domain.SessionJournalLink
import com.migestor.shared.domain.SessionJournalLinkType
import com.migestor.shared.domain.SessionJournalMedia
import com.migestor.shared.domain.SessionJournalMediaType
import com.migestor.shared.domain.SessionJournalStatus
import com.migestor.shared.domain.SessionStatus
import com.migestor.shared.domain.TeacherScheduleSlot
import com.migestor.shared.domain.TeachingUnit
import com.migestor.shared.domain.TeachingUnitSchedule
import com.migestor.shared.domain.WeeklySlotTemplate
import com.migestor.shared.sync.SyncChange
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.LocalDate
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SqlDelightSyncAdapterPlanningSessionSyncTest {
    private val json = Json { ignoreUnknownKeys = true }

    private fun newContainer(): KmpContainer {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        return KmpContainer(driver)
    }

    private suspend fun seedClass(container: KmpContainer): Long =
        container.classesRepository.saveClass(name = "1 ESO A", course = 1)

    private suspend fun seedSession(
        container: KmpContainer,
        classId: Long,
        linkedAssessmentIdsCsv: String = "evaluation:7",
        teacherScheduleSlotId: Long? = null,
        startTime: String? = "09:00",
        endTime: String? = "10:00",
    ): Long {
        return container.plannerRepository.upsertSession(
            PlanningSession(
                teachingUnitId = 0,
                teachingUnitName = "Juegos",
                groupId = classId,
                groupName = "1 ESO A",
                dayOfWeek = 1,
                period = 2,
                weekNumber = 39,
                year = 2026,
                objectives = "Cooperar",
                linkedAssessmentIdsCsv = linkedAssessmentIdsCsv,
                teacherScheduleSlotId = teacherScheduleSlotId,
                startTime = startTime,
                endTime = endTime,
                status = SessionStatus.PLANNED,
            )
        )
    }

    @Test
    fun `el mensaje de la sesion incluye instrumentos y franja`() = runTest {
        val container = newContainer()
        val classId = seedClass(container)
        val schedule = container.teacherScheduleRepository.getOrCreatePrimarySchedule()
        val slotId = container.teacherScheduleRepository.saveScheduleSlot(
            TeacherScheduleSlot(
                teacherScheduleId = schedule.id,
                schoolClassId = classId,
                subjectLabel = "Educación Física",
                dayOfWeek = 1,
                startTime = "09:00",
                endTime = "10:00",
            )
        )
        seedSession(container, classId, teacherScheduleSlotId = slotId)

        val change = SqlDelightSyncAdapter(container, localDeviceId = "mac")
            .collectLocalChanges(0L)
            .single { it.entity == "planning_session" }
        val payload = json.parseToJsonElement(change.payload).jsonObject

        assertEquals("evaluation:7", payload["linkedAssessmentIdsCsv"]?.jsonPrimitive?.content)
        assertEquals(slotId.toString(), payload["teacherScheduleSlotId"]?.jsonPrimitive?.content)
        assertEquals("09:00", payload["startTime"]?.jsonPrimitive?.content)
        assertEquals("10:00", payload["endTime"]?.jsonPrimitive?.content)
    }

    @Test
    fun `un mensaje viejo sin instrumentos ni franja no borra lo ya guardado`() = runTest {
        val container = newContainer()
        val classId = seedClass(container)
        val sessionId = seedSession(container, classId)
        val adapter = SqlDelightSyncAdapter(container, localDeviceId = "mac")

        adapter.applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "planning_session",
                    id = sessionId.toString(),
                    updatedAtEpochMs = 500L,
                    deviceId = "ios",
                    payload = """
                        {"id":$sessionId,"teachingUnitId":0,"teachingUnitName":"Juegos","teachingUnitColor":"#4A90D9","groupId":$classId,"groupName":"1 ESO A","dayOfWeek":1,"period":2,"weekNumber":39,"year":2026,"objectives":"Cooperar","activities":"","evaluation":"","status":"PLANNED"}
                    """.trim(),
                )
            )
        )

        val kept = container.plannerRepository.listAllSessions().single()
        assertEquals("evaluation:7", kept.linkedAssessmentIdsCsv)
        assertEquals("09:00", kept.startTime)
        assertEquals("10:00", kept.endTime)
    }

    @Test
    fun `un mensaje completo puede quitar los instrumentos a proposito`() = runTest {
        val container = newContainer()
        val classId = seedClass(container)
        val sessionId = seedSession(container, classId)
        val adapter = SqlDelightSyncAdapter(container, localDeviceId = "mac")

        adapter.applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "planning_session",
                    id = sessionId.toString(),
                    updatedAtEpochMs = 500L,
                    deviceId = "ios",
                    payload = """
                        {"id":$sessionId,"teachingUnitId":0,"teachingUnitName":"Juegos","groupId":$classId,"groupName":"1 ESO A","dayOfWeek":1,"period":2,"weekNumber":39,"year":2026,"objectives":"Cooperar","activities":"","evaluation":"","linkedAssessmentIdsCsv":"","teacherScheduleSlotId":null,"startTime":null,"endTime":null,"learningSituationSessionPlanId":null,"status":"PLANNED"}
                    """.trim(),
                )
            )
        )

        val cleared = container.plannerRepository.listAllSessions().single()
        assertEquals("", cleared.linkedAssessmentIdsCsv)
        assertNull(cleared.teacherScheduleSlotId)
        assertNull(cleared.startTime)
        assertNull(cleared.endTime)
    }

    @Test
    fun `un texto nuevo del diario no borra notas ni puntuaciones`() = runTest {
        val container = newContainer()
        val classId = seedClass(container)
        val sessionId = seedSession(container, classId, linkedAssessmentIdsCsv = "")
        container.sessionJournalRepository.saveJournalAggregate(
            SessionJournalAggregate(
                journal = SessionJournal(
                    planningSessionId = sessionId,
                    actualText = "Antes",
                    climateScore = 4,
                    status = SessionJournalStatus.COMPLETED,
                ),
                individualNotes = listOf(
                    SessionJournalIndividualNote(studentName = "Ana", note = "Buena lectura", tag = "positivo")
                ),
                actions = listOf(SessionJournalAction(title = "Llevar conos", isCompleted = true)),
            )
        )

        SqlDelightSyncAdapter(container, localDeviceId = "mac").applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "session_journal",
                    id = sessionId.toString(),
                    updatedAtEpochMs = 900L,
                    deviceId = "ios",
                    payload = """{"planningSessionId":$sessionId,"actualText":"El grupo cooperó","status":"COMPLETED"}""",
                )
            )
        )

        val saved = container.sessionJournalRepository.getJournalForSession(sessionId)
        assertEquals("El grupo cooperó", saved?.journal?.actualText)
        assertEquals(4, saved?.journal?.climateScore)
        assertEquals("Buena lectura", saved?.individualNotes?.single()?.note)
        assertEquals("Llevar conos", saved?.actions?.single()?.title)
    }

    @Test
    fun `el diario viaja de un aparato a otro`() = runTest {
        val source = newContainer()
        val classId = seedClass(source)
        val sessionId = seedSession(source, classId, linkedAssessmentIdsCsv = "")
        source.sessionJournalRepository.saveJournalAggregate(
            SessionJournalAggregate(
                journal = SessionJournal(
                    planningSessionId = sessionId,
                    actualText = "El grupo cooperó",
                    familyCommunicationText = "Avisar a la familia de Ana",
                    injuriesText = "Ninguna",
                    status = SessionJournalStatus.COMPLETED,
                ),
                individualNotes = listOf(
                    SessionJournalIndividualNote(studentId = 4, studentName = "Ana", note = "Buena lectura", tag = "positivo")
                ),
                actions = listOf(SessionJournalAction(title = "Llevar conos", isCompleted = true)),
                media = listOf(
                    SessionJournalMedia(
                        type = SessionJournalMediaType.PHOTO,
                        uri = "file:///tmp/foto.jpg",
                        caption = "Estación",
                    )
                ),
                links = listOf(
                    SessionJournalLink(type = SessionJournalLinkType.INCIDENT, targetId = "inc_1", label = "Incidencia")
                ),
            )
        )

        val journalChange = SqlDelightSyncAdapter(source, localDeviceId = "mac")
            .collectLocalChanges(0L)
            .single { it.entity == "session_journal" }
        assertEquals(sessionId.toString(), journalChange.id)

        val target = newContainer()
        seedClass(target)
        seedSession(target, classId, linkedAssessmentIdsCsv = "")
        val targetSessionId = target.plannerRepository.listAllSessions().single().id
        val rewritten = journalChange.copy(
            id = targetSessionId.toString(),
            payload = journalChange.payload.replace(
                "\"planningSessionId\":$sessionId",
                "\"planningSessionId\":$targetSessionId",
            ),
        )
        SqlDelightSyncAdapter(target, localDeviceId = "ipad").applyIncomingChangesLww(listOf(rewritten))

        val arrived = target.sessionJournalRepository.getJournalForSession(targetSessionId)
        assertEquals("El grupo cooperó", arrived?.journal?.actualText)
        assertEquals("Avisar a la familia de Ana", arrived?.journal?.familyCommunicationText)
        assertEquals("Ana", arrived?.individualNotes?.single()?.studentName)
        assertEquals(true, arrived?.actions?.single()?.isCompleted)
        assertEquals("file:///tmp/foto.jpg", arrived?.media?.single()?.uri)
        assertEquals("inc_1", arrived?.links?.single()?.targetId)
    }

    @Test
    fun `un mensaje viejo de nota rapida no borra el diario`() = runTest {
        val container = newContainer()
        val classId = seedClass(container)
        val sessionId = seedSession(container, classId)
        container.sessionJournalRepository.saveJournalAggregate(
            SessionJournalAggregate(
                journal = SessionJournal(
                    planningSessionId = sessionId,
                    actualText = "Texto que debe quedarse",
                    status = SessionJournalStatus.DRAFT,
                )
            )
        )
        val ack = SqlDelightSyncAdapter(container, localDeviceId = "mac").applyIncomingChangesLww(
            listOf(
                SyncChange(
                    entity = "session_journal",
                    id = sessionId.toString(),
                    updatedAtEpochMs = 800L,
                    deviceId = "ios",
                    payload = """{"id":1,"planningSessionId":$sessionId,"studentId":4,"note":"nota suelta"}""",
                )
            )
        )

        val kept = container.sessionJournalRepository.getJournalForSession(sessionId)
        assertEquals("Texto que debe quedarse", kept?.journal?.actualText)
        assertEquals(1, ack.ignored)
    }

    @Test
    fun `la huella cambia si cambian los instrumentos`() = runTest {
        val left = newContainer()
        val right = newContainer()
        val leftClass = seedClass(left)
        val rightClass = seedClass(right)
        seedSession(left, leftClass, linkedAssessmentIdsCsv = "evaluation:7")
        seedSession(right, rightClass, linkedAssessmentIdsCsv = "evaluation:8")

        val leftFingerprint = SyncDatasetFingerprint.compute(left)
        val rightFingerprint = SyncDatasetFingerprint.compute(right)

        assertEquals(leftFingerprint.countsByEntity["planning_session"], rightFingerprint.countsByEntity["planning_session"])
        assertNotEquals(leftFingerprint.digest, rightFingerprint.digest)
    }

    @Test
    fun `generar sesiones desde una unidad escribe la tabla que usa el iPad`() = runTest {
        val container = newContainer()
        val classId = seedClass(container)
        val day = LocalDate(2026, 9, 21)
        container.weeklyTemplateRepository.insert(
            WeeklySlotTemplate(
                schoolClassId = classId,
                dayOfWeek = 1,
                startTime = "09:00",
                endTime = "10:00",
            )
        )
        val unitId = container.plannerRepository.upsertTeachingUnit(
            TeachingUnit(
                name = "Juegos",
                description = "",
                colorHex = "#4A90D9",
                groupId = classId,
                schoolClassId = classId,
                startDate = day,
                endDate = day,
            )
        )
        container.generateSessionsFromUD.execute(
            ud = TeachingUnit(
                id = unitId,
                name = "Juegos",
                description = "",
                colorHex = "#4A90D9",
                groupId = classId,
                schoolClassId = classId,
                startDate = day,
                endDate = day,
            ),
            schedule = TeachingUnitSchedule(
                teachingUnitId = unitId,
                schoolClassId = classId,
                startDate = day,
                endDate = day,
            ),
        )

        val sessions = container.plannerRepository.listAllSessions()
        assertEquals(1, sessions.size)
        assertEquals("09:00", sessions.single().startTime)
        assertEquals("10:00", sessions.single().endTime)
        assertEquals(classId, sessions.single().groupId)
        val planned = container.plannedSessionRepository.listSessionsInRange(classId, day, day)
        assertTrue(planned.isEmpty())
    }

    @Test
    fun `exportar y aplicar en una base vacia conserva instrumentos franja y horas`() = runTest {
        val source = newContainer()
        val classId = seedClass(source)
        val schedule = source.teacherScheduleRepository.getOrCreatePrimarySchedule()
        val slotId = source.teacherScheduleRepository.saveScheduleSlot(
            TeacherScheduleSlot(
                teacherScheduleId = schedule.id,
                schoolClassId = classId,
                subjectLabel = "Educación Física",
                dayOfWeek = 1,
                startTime = "09:00",
                endTime = "10:00",
            )
        )
        seedSession(
            source,
            classId,
            linkedAssessmentIdsCsv = "evaluation:7,rubric:3",
            teacherScheduleSlotId = slotId,
            startTime = "09:00",
            endTime = "10:00",
        )
        val original = source.plannerRepository.listAllSessions().single()

        val changes = SqlDelightSyncAdapter(source, localDeviceId = "mac").collectLocalChanges(0L)
        val target = newContainer()
        SqlDelightSyncAdapter(target, localDeviceId = "ipad").applyIncomingChangesLww(changes)

        val copied = target.plannerRepository.listAllSessions().single()
        assertEquals(original.linkedAssessmentIdsCsv, copied.linkedAssessmentIdsCsv)
        assertEquals(original.teacherScheduleSlotId, copied.teacherScheduleSlotId)
        assertEquals(original.startTime, copied.startTime)
        assertEquals(original.endTime, copied.endTime)
        assertEquals(original.objectives, copied.objectives)
        assertEquals(original.groupId, copied.groupId)
        assertEquals(original.dayOfWeek, copied.dayOfWeek)
        assertEquals(original.period, copied.period)
        assertEquals(original.weekNumber, copied.weekNumber)
        assertEquals(original.year, copied.year)
        assertEquals(original.status, copied.status)
    }
}
