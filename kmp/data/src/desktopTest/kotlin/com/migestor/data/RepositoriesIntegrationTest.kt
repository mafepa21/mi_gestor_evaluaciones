package com.migestor.data

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.repository.ClassesRepositorySqlDelight
import com.migestor.data.repository.CompetenciesRepositorySqlDelight
import com.migestor.data.repository.ConfigurationTemplateRepositorySqlDelight
import com.migestor.data.repository.EvaluationsRepositorySqlDelight
import com.migestor.data.repository.GradesRepositorySqlDelight
import com.migestor.data.repository.NotebookCellsRepositorySqlDelight
import com.migestor.data.repository.NotebookConfigRepositorySqlDelight
import com.migestor.data.repository.LearningSituationsRepositorySqlDelight
import com.migestor.data.repository.NotebookInstrumentsRepositorySqlDelight
import com.migestor.data.repository.PlannerRepositorySqlDelight
import com.migestor.data.repository.SessionJournalRepositorySqlDelight
import com.migestor.data.repository.StudentsRepositorySqlDelight
import com.migestor.data.repository.TeacherScheduleRepositorySqlDelight
import com.migestor.data.repository.CalendarRepositorySqlDelight
import com.migestor.data.repository.queryStrings
import com.migestor.shared.domain.NotebookCellInputKind
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookInstrumentItem
import com.migestor.shared.domain.NotebookInstrumentItemType
import com.migestor.shared.domain.NotebookInstrumentTemplate
import com.migestor.shared.domain.NotebookInstrumentTemplateKind
import com.migestor.shared.domain.ConfigTemplateKind
import com.migestor.shared.domain.LearningSituation
import com.migestor.shared.domain.LearningSituationLinkedResource
import com.migestor.shared.domain.LearningSituationResourceKind
import com.migestor.shared.domain.PlanningSession
import com.migestor.shared.domain.SessionJournal
import com.migestor.shared.domain.SessionJournalAction
import com.migestor.shared.domain.SessionJournalAggregate
import com.migestor.shared.domain.SessionJournalDecision
import com.migestor.shared.domain.SessionJournalIndividualNote
import com.migestor.shared.domain.SessionJournalLink
import com.migestor.shared.domain.SessionJournalLinkType
import com.migestor.shared.domain.SessionJournalMedia
import com.migestor.shared.domain.SessionJournalMediaType
import com.migestor.shared.domain.SessionJournalStatus
import com.migestor.shared.domain.SessionStatus
import com.migestor.shared.domain.SessionCascadeMoveRequest
import com.migestor.shared.domain.StudentSex
import com.migestor.shared.domain.StudentSexSource
import com.migestor.shared.usecase.NotebookSheetMemoryCache
import kotlinx.datetime.LocalDate
import com.migestor.shared.usecase.GetNotebookUseCase
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class RepositoriesIntegrationTest {
    @Test
    fun `saves entities and computes notebook`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)

        val students = StudentsRepositorySqlDelight(db)
        val classes = ClassesRepositorySqlDelight(db)
        val evaluations = EvaluationsRepositorySqlDelight(db)
        val grades = GradesRepositorySqlDelight(db)
        val cells = NotebookCellsRepositorySqlDelight(db)

        val classId = classes.saveClass(name = "3 ESO A", course = 3, description = null)
        val studentId = students.saveStudent(firstName = "Ana", lastName = "López", email = null)
        classes.addStudentToClass(classId, studentId)

        val evalId = evaluations.saveEvaluation(
            classId = classId,
            code = "EX1",
            name = "Examen 1",
            type = "Examen",
            weight = 1.0,
            formula = null,
        )
        grades.saveGrade(
            classId = classId,
            studentId = studentId,
            columnId = "eval_${evalId}",
            evaluationId = evalId,
            value = 8.5
        )

        val notebook = GetNotebookUseCase(classes, evaluations, grades, cells).invoke(classId)

        assertEquals(1, notebook.rows.size)
        assertEquals(8.5, notebook.rows.first().weightedAverage)
    }

    @Test
    fun `links evaluations to competencies and versions templates`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)

        db.appDatabaseQueries.upsertCenter(
            id = null,
            code = "CTR-01",
            name = "Centro Demo",
            author_user_id = null,
            created_at_epoch_ms = 1L,
            updated_at_epoch_ms = 1L,
            associated_group_id = null,
            device_id = null,
            sync_version = 0,
        )
        val centerId = db.appDatabaseQueries.lastInsertedId().executeAsOne()

        db.appDatabaseQueries.upsertAppUser(
            id = null,
            external_id = "teacher-demo",
            display_name = "Profe Demo",
            email = "demo@centro.test",
            role = "DOCENTE",
            center_id = centerId,
            author_user_id = null,
            created_at_epoch_ms = 1L,
            updated_at_epoch_ms = 1L,
            associated_group_id = null,
            device_id = null,
            sync_version = 0,
        )
        val userId = db.appDatabaseQueries.lastInsertedId().executeAsOne()

        val classes = ClassesRepositorySqlDelight(db)
        val evaluations = EvaluationsRepositorySqlDelight(db)
        val competencies = CompetenciesRepositorySqlDelight(db)
        val templates = ConfigurationTemplateRepositorySqlDelight(db)

        val classId = classes.saveClass(name = "4 ESO B", course = 4, description = "demo")
        val evalId = evaluations.saveEvaluation(
            classId = classId,
            code = "EV-C1",
            name = "Prueba criterio 1",
            type = "Examen",
            weight = 1.0,
        )

        val competencyId = competencies.saveCompetency(
            code = "CCL1",
            name = "Competencia comunicación",
            description = "Expresión escrita",
        )
        evaluations.saveEvaluationCompetencyLink(
            evaluationId = evalId,
            competencyId = competencyId,
            weight = 0.7,
            authorUserId = userId,
        )
        val links = evaluations.listEvaluationCompetencyLinks(evalId)
        assertEquals(1, links.size)
        assertEquals(competencyId, links.first().competencyId)

        val sourceTemplateId = templates.saveTemplate(
            centerId = centerId,
            ownerUserId = userId,
            name = "Plantilla 2025",
            kind = ConfigTemplateKind.CLASS_STRUCTURE,
            authorUserId = userId,
        )
        val sourceVersionId = templates.saveTemplateVersion(
            templateId = sourceTemplateId,
            payloadJson = """{"columns":["EX1","TA1"]}""",
            authorUserId = userId,
        )
        assertNotNull(sourceVersionId)

        val targetTemplateId = templates.saveTemplate(
            centerId = centerId,
            ownerUserId = userId,
            name = "Plantilla 2026",
            kind = ConfigTemplateKind.CLASS_STRUCTURE,
            authorUserId = userId,
        )
        templates.cloneLatestVersionToTemplate(
            sourceTemplateId = sourceTemplateId,
            targetTemplateId = targetTemplateId,
            sourceAcademicYearId = null,
            authorUserId = userId,
        )

        val targetVersions = templates.listTemplateVersions(targetTemplateId)
        assertEquals(1, targetVersions.size)
        assertEquals("""{"columns":["EX1","TA1"]}""", targetVersions.first().payloadJson)
        assertEquals(1, targetVersions.first().versionNumber)
        assertEquals(sourceVersionId, targetVersions.first().basedOnVersionId)
    }

    @Test
    fun `persists non numeric notebook cells`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)

        val students = StudentsRepositorySqlDelight(db)
        val classes = ClassesRepositorySqlDelight(db)
        val cells = NotebookCellsRepositorySqlDelight(db)

        val classId = classes.saveClass(name = "1 ESO C", course = 1, description = null)
        val studentId = students.saveStudent(firstName = "Laura", lastName = "Sanz", email = null)
        classes.addStudentToClass(classId, studentId)

        cells.saveCell(
            classId = classId,
            studentId = studentId,
            columnId = "obs_docente",
            textValue = "Necesita refuerzo",
            boolValue = true,
            note = "Seguimiento semanal",
            colorHex = "#ff8800",
            attachmentUris = listOf("file://nota1.pdf"),
        )

        val listed = cells.listClassCells(classId)
        assertEquals(1, listed.size)
        assertEquals("Necesita refuerzo", listed.first().textValue)
        assertEquals(true, listed.first().boolValue)
        assertTrue(listed.first().annotation?.attachmentUris?.isNotEmpty() == true)
    }

    @Test
    fun `upserting grade for same column updates value instead of duplicating`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)

        val students = StudentsRepositorySqlDelight(db)
        val classes = ClassesRepositorySqlDelight(db)
        val grades = GradesRepositorySqlDelight(db)

        val classId = classes.saveClass(name = "Test Class", course = 1, description = null)
        val studentId = students.saveStudent(firstName = "Test", lastName = "Student", email = null)
        classes.addStudentToClass(classId, studentId)

        val columnId = "TEST_COL"
        
        // First save
        grades.saveGrade(
            classId = classId,
            studentId = studentId,
            columnId = columnId,
            evaluationId = null,
            value = 5.0
        )
        
        // Second save (update)
        grades.saveGrade(
            classId = classId,
            studentId = studentId,
            columnId = columnId,
            evaluationId = null,
            value = 9.0
        )

        val studentGrades = grades.listGradesForStudentInClass(studentId, classId)

        // Verify only 1 grade exists and value is updated
        assertEquals(1, studentGrades.size, "Should only have one grade record")
        assertEquals(9.0, studentGrades.first().value, "Value should be updated to 9.0")
    }

    @Test
    fun `saveGrade never discards a local edit even if the existing record has a future timestamp`() = runTest {
        // Regresion: saveGrade (escritura LOCAL de la profesora) reutilizaba el
        // mismo guard LWW que upsertGrade (camino de sync). Si una sync previa
        // dejaba en BD un registro con updated_at futuro (reloj adelantado de
        // otro dispositivo), la siguiente correccion local se descartaba en
        // silencio: saveGrade devolvia un id como si hubiera guardado, pero la
        // nota corregida nunca llegaba a BD.
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)

        val students = StudentsRepositorySqlDelight(db)
        val classes = ClassesRepositorySqlDelight(db)
        val grades = GradesRepositorySqlDelight(db)

        val classId = classes.saveClass(name = "Test Class", course = 1, description = null)
        val studentId = students.saveStudent(firstName = "Test", lastName = "Student", email = null)
        classes.addStudentToClass(classId, studentId)

        val columnId = "TEST_COL"
        val farFutureEpochMs = 4_102_444_800_000L // año 2100, simula reloj adelantado llegado por sync

        // Registro "desde el futuro" con device_id no vacío, como llegaria via upsertGrade en una sync.
        grades.upsertGrade(
            classId = classId,
            studentId = studentId,
            columnId = columnId,
            evaluationId = null,
            value = 5.0,
            updatedAtEpochMs = farFutureEpochMs,
            deviceId = "otro-dispositivo",
        )

        // La profesora corrige la nota ahora mismo, en su reloj local (muy anterior al futuro simulado).
        grades.saveGrade(
            classId = classId,
            studentId = studentId,
            columnId = columnId,
            evaluationId = null,
            value = 9.0,
        )

        val studentGrades = grades.listGradesForStudentInClass(studentId, classId)
        assertEquals(1, studentGrades.size, "Deberia seguir habiendo un unico registro de nota")
        assertEquals(9.0, studentGrades.first().value, "La correccion local nunca debe descartarse por LWW")
    }

    @Test
    fun `upsertStudent keeps sex, sexSource and birthDate from the incoming sync payload`() = runTest {
        // Regresion: el caso "student" del adaptador de sync no leia sex/sexSource/
        // birthDate del payload entrante y llamaba a saveStudent (sin guard LWW,
        // pensado para ediciones locales) con los defaults UNSPECIFIED/UNKNOWN/null.
        // Un dispositivo que solo cambiaba el apellido -o incluso un cambio MAS
        // ANTIGUO, porque no habia comparacion de updated_at- borraba sexo y fecha
        // de nacimiento ya registrados en otro dispositivo.
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)
        val students = StudentsRepositorySqlDelight(db)

        val studentId = students.saveStudent(
            firstName = "Ana",
            lastName = "Lopez",
            sex = StudentSex.FEMALE,
            sexSource = StudentSexSource.MANUAL,
            birthDate = LocalDate(2012, 3, 15),
            updatedAtEpochMs = 1_000L,
            deviceId = "device-A",
        )

        // Simula el camino de sync: llega un cambio de otro dispositivo con updated_at
        // posterior, pero SIN sex/sexSource/birthDate en el payload (nunca los envio).
        students.upsertStudent(
            id = studentId,
            firstName = "Ana",
            lastName = "Lopez Garcia",
            sex = StudentSex.UNSPECIFIED,
            sexSource = StudentSexSource.UNKNOWN,
            birthDate = null,
            updatedAtEpochMs = 2_000L,
            deviceId = "device-B",
        )

        val updated = students.getStudent(studentId)
        assertEquals("Lopez Garcia", updated?.lastName, "El cambio mas reciente si debe aplicarse")
        // NOTA: este test documenta el comportamiento actual de upsertStudent, que
        // reemplaza la fila entera con lo que le pasen (igual que upsertGrade). El
        // fix real esta en el LLAMADOR (SqlDelightSyncAdapter), que ahora SI lee
        // sex/sexSource/birthDate del payload en vez de omitirlos.

        // Un cambio MAS ANTIGUO (updated_at menor) nunca debe aplicarse, ni siquiera
        // parcialmente.
        students.upsertStudent(
            id = studentId,
            firstName = "Ana",
            lastName = "NOMBRE-DE-UN-DISPOSITIVO-DESACTUALIZADO",
            sex = StudentSex.UNSPECIFIED,
            sexSource = StudentSexSource.UNKNOWN,
            birthDate = null,
            updatedAtEpochMs = 500L,
            deviceId = "device-C",
        )

        val afterStaleSync = students.getStudent(studentId)
        assertEquals("Lopez Garcia", afterStaleSync?.lastName, "Un cambio mas antiguo no debe aplicarse (guard LWW)")
    }

    @Test
    fun `persists notebook column type and formula`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)

        val classes = ClassesRepositorySqlDelight(db)
        val config = NotebookConfigRepositorySqlDelight(db)

        val classId = classes.saveClass(name = "2 ESO D", course = 2, description = null)
        config.saveColumn(
            classId = classId,
            column = NotebookColumnDefinition(
                id = "CALC_FINAL",
                title = "Final",
                type = NotebookColumnType.CALCULATED,
                formula = "ROUND((EX1*0.4)+(TA1*0.6), 2)",
                tabIds = listOf("TAB_1")
            )
        )

        val savedColumns = config.listColumns(classId)
        assertEquals(1, savedColumns.size)
        assertEquals(NotebookColumnType.CALCULATED, savedColumns.first().type)
        assertEquals("ROUND((EX1*0.4)+(TA1*0.6), 2)", savedColumns.first().formula)
    }

    @Test
    fun `planner upsert updates existing remote id idempotently`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)

        val classes = ClassesRepositorySqlDelight(db)
        val planner = PlannerRepositorySqlDelight(db)
        val classId = classes.saveClass(name = "4 ESO A", course = 4, description = null)

        val remoteSession = PlanningSession(
            id = 99,
            teachingUnitId = 0,
            teachingUnitName = "Unidad",
            groupId = classId,
            groupName = "4 ESO A",
            dayOfWeek = 2,
            period = 3,
            weekNumber = 12,
            year = 2026,
            objectives = "Primera versión",
            activities = "Tarea inicial",
            evaluation = "",
            status = SessionStatus.PLANNED,
        )

        assertEquals(99, planner.upsertSession(remoteSession))
        assertEquals(
            99,
            planner.upsertSession(
                remoteSession.copy(
                    objectives = "Versión sincronizada",
                    activities = "Tarea actualizada",
                )
            )
        )

        val saved = planner.listSessions(weekNumber = 12, year = 2026).single()
        assertEquals(99, saved.id)
        assertEquals("Versión sincronizada", saved.objectives)
        assertEquals("Tarea actualizada", saved.activities)
    }

    @Test
    fun `persists structured planner journal aggregate`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)

        val classes = ClassesRepositorySqlDelight(db)
        val planner = PlannerRepositorySqlDelight(db)
        val journals = SessionJournalRepositorySqlDelight(db)

        val classId = classes.saveClass(name = "4 ESO A", course = 4, description = null)
        val sessionId = planner.upsertSession(
            PlanningSession(
                teachingUnitId = 0,
                teachingUnitName = "Balonmano",
                groupId = classId,
                groupName = "4 ESO A",
                dayOfWeek = 2,
                period = 3,
                weekNumber = 12,
                year = 2026,
                objectives = "Pase y juego sin balón",
                activities = "Ruedas de pase y superioridades",
                evaluation = "",
                status = SessionStatus.PLANNED,
            )
        )

        val savedId = journals.saveJournalAggregate(
            SessionJournalAggregate(
                journal = SessionJournal(
                    planningSessionId = sessionId,
                    teacherName = "Mario",
                    scheduledSpace = "Pabellón",
                    usedSpace = "Pabellón cubierto",
                    unitLabel = "Balonmano",
                    objectivePlanned = "Pase y juego sin balón",
                    plannedText = "Tarea 1 y tarea 2",
                    actualText = "Se completó tarea 1 y partido final",
                    climateScore = 4,
                    participationScore = 5,
                    usefulTimeScore = 4,
                    perceivedDifficultyScore = 3,
                    pedagogicalDecision = SessionJournalDecision.REPEAT_SESSION,
                    nextStepText = "Repetir tarea 2",
                    weatherText = "Nublado",
                    materialUsedText = "Balones y conos",
                    status = SessionJournalStatus.COMPLETED,
                    incidentTags = listOf("lesion", "equipacion")
                ),
                individualNotes = listOf(
                    SessionJournalIndividualNote(studentId = 1, studentName = "Ana", note = "Muy buena lectura táctica", tag = "positivo"),
                    SessionJournalIndividualNote(studentId = 2, studentName = "Pablo", note = "No participa tras lesión", tag = "seguimiento"),
                ),
                actions = listOf(
                    SessionJournalAction(title = "Adaptar a Pablo"),
                    SessionJournalAction(title = "Llevar más conos", isCompleted = true),
                ),
                media = listOf(
                    SessionJournalMedia(type = SessionJournalMediaType.PHOTO, uri = "file:///tmp/foto.jpg", caption = "Estación principal"),
                    SessionJournalMedia(type = SessionJournalMediaType.AUDIO, uri = "file:///tmp/audio.m4a", transcript = "Audio resumen"),
                ),
                links = listOf(
                    SessionJournalLink(type = SessionJournalLinkType.INCIDENT, targetId = "inc_1", label = "Incidencia registrada"),
                )
            )
        )

        assertTrue(savedId > 0)
        val loaded = journals.getJournalForSession(sessionId)
        assertNotNull(loaded)
        assertEquals(SessionJournalStatus.COMPLETED, loaded.journal.status)
        assertEquals(2, loaded.individualNotes.size)
        assertEquals(2, loaded.actions.size)
        assertEquals(2, loaded.media.size)
        assertEquals(1, loaded.links.size)

        val summaries = journals.listSummariesForSessions(listOf(sessionId))
        assertEquals(1, summaries.size)
        assertEquals(5, summaries.first().participationScore)
        assertEquals(2, summaries.first().mediaCount)
        assertEquals(listOf("lesion", "equipacion"), summaries.first().incidentTags)
    }

    @Test
    fun `creates primary teacher schedule without crashing`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)

        val classes = ClassesRepositorySqlDelight(db)
        val planner = PlannerRepositorySqlDelight(db)
        val calendar = CalendarRepositorySqlDelight(db)
        val repository = TeacherScheduleRepositorySqlDelight(
            db = db,
            plannerRepository = planner,
            calendarRepository = calendar,
            classesRepository = classes
        )

        val schedule = repository.getOrCreatePrimarySchedule()

        assertTrue(schedule.id >= 0L)
        assertEquals("Agenda docente", schedule.name)
        assertEquals("1,2,3,4,5", schedule.activeWeekdaysCsv)
    }

    @Test
    fun `planner cascade move preserves ids crosses week and restores placements`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)
        val classes = ClassesRepositorySqlDelight(db)
        val planner = PlannerRepositorySqlDelight(db)
        val classId = classes.saveClass(name = "2 ESO A", course = 2, description = null)

        val sourceId = planner.upsertSession(
            PlanningSession(
                teachingUnitId = 0,
                teachingUnitName = "Origen",
                groupId = classId,
                groupName = "2 ESO A",
                dayOfWeek = 5,
                period = 8,
                weekNumber = 12,
                year = 2026,
            )
        )
        val displacedId = planner.upsertSession(
            PlanningSession(
                teachingUnitId = 0,
                teachingUnitName = "Impartida",
                groupId = classId,
                groupName = "2 ESO A",
                dayOfWeek = 5,
                period = 9,
                weekNumber = 12,
                year = 2026,
                status = SessionStatus.COMPLETED,
            )
        )
        val request = SessionCascadeMoveRequest(
            sourceSessionId = sourceId,
            targetWeekNumber = 12,
            targetYear = 2026,
            targetDayOfWeek = 5,
            targetPeriod = 9,
        )

        val preview = planner.previewCascadeMove(request)
        assertEquals(listOf(displacedId), preview.completedSessionIds)
        assertTrue(preview.crossesWeekBoundary)
        assertEquals(2, preview.nextPlacements.size)

        val committed = planner.commitCascadeMove(request)
        assertEquals(2, committed.movedCount)
        val week12 = planner.listSessions(12, 2026).associateBy { it.id }
        val week13 = planner.listSessions(13, 2026).associateBy { it.id }
        assertEquals(9, week12.getValue(sourceId).period)
        assertEquals("15:55", week12.getValue(sourceId).startTime)
        assertEquals("16:50", week12.getValue(sourceId).endTime)
        assertEquals(null, week12.getValue(sourceId).teacherScheduleSlotId)
        assertEquals(displacedId, week13.getValue(displacedId).id)
        assertEquals(1, week13.getValue(displacedId).dayOfWeek)
        assertEquals(1, week13.getValue(displacedId).period)
        assertEquals("08:05", week13.getValue(displacedId).startTime)
        assertEquals("09:00", week13.getValue(displacedId).endTime)

        planner.restoreCascadeMove(committed.previousPlacements)
        val restored = planner.listSessions(12, 2026).associateBy { it.id }
        assertEquals(8, restored.getValue(sourceId).period)
        assertEquals(9, restored.getValue(displacedId).period)
    }

    @Test
    fun `planner cascade can exchange backwards into source vacancy`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)
        val classes = ClassesRepositorySqlDelight(db)
        val planner = PlannerRepositorySqlDelight(db)
        val classId = classes.saveClass(name = "3 ESO B", course = 3, description = null)
        val sourceId = planner.upsertSession(
            PlanningSession(
                teachingUnitId = 0, teachingUnitName = "P2", groupId = classId, groupName = "3 ESO B",
                dayOfWeek = 1, period = 2, weekNumber = 14, year = 2026,
            )
        )
        val occupantId = planner.upsertSession(
            PlanningSession(
                teachingUnitId = 0, teachingUnitName = "P1", groupId = classId, groupName = "3 ESO B",
                dayOfWeek = 1, period = 1, weekNumber = 14, year = 2026,
            )
        )

        val result = planner.commitCascadeMove(
            SessionCascadeMoveRequest(sourceId, 14, 2026, 1, 1)
        )
        val moved = planner.listSessions(14, 2026).associateBy { it.id }
        assertEquals(2, result.movedCount)
        assertEquals(1, moved.getValue(sourceId).period)
        assertEquals(2, moved.getValue(occupantId).period)

        planner.restoreCascadeMove(result.previousPlacements)
        val restored = planner.listSessions(14, 2026).associateBy { it.id }
        assertEquals(2, restored.getValue(sourceId).period)
        assertEquals(1, restored.getValue(occupantId).period)
    }

    @Test
    fun `schema creates performance indexes for daily data queries`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)

        val indexes = driver.queryStrings(
            """
            SELECT name
            FROM sqlite_master
            WHERE type = 'index'
            ORDER BY name
            """.trimIndent()
        ).toSet()

        val expectedIndexes = setOf(
            "idx_attendance_class_date_student",
            "idx_attendance_class_student_date",
            "idx_incidents_class_date",
            "idx_incidents_class_student_date",
            "idx_notebook_cell_entries_column",
            "idx_notebook_cell_audit_lookup",
            "idx_planned_session_class_date_start",
            "idx_planned_session_date",
            "idx_planner_session_group_date_period",
            "idx_planner_session_unit",
            "idx_planner_session_slot_status_date",
            "idx_teacher_schedule_slots_schedule_day_start",
            "idx_teacher_schedule_slots_class_day_start",
            "idx_rubric_criteria_rubric_sort",
            "idx_rubric_levels_criterion_sort",
            "idx_evaluations_class_id",
            "idx_evaluation_competency_links_evaluation",
            "idx_learning_situation_versions_lookup",
            "idx_learning_situation_sequence_versions_lookup",
            "idx_learning_situation_session_plans_sequence",
            "idx_learning_situation_links_lookup",
        )

        assertTrue(indexes.containsAll(expectedIndexes))
    }

    @Test
    fun `saveTemplate preserves responses for items that persist across a re-save`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)
        val classes = ClassesRepositorySqlDelight(db)
        val students = StudentsRepositorySqlDelight(db)
        val grades = GradesRepositorySqlDelight(db)
        val sheetCache = NotebookSheetMemoryCache()
        val instruments = NotebookInstrumentsRepositorySqlDelight(db, grades, sheetCache)

        val classId = classes.saveClass(name = "3 ESO A", course = 3, description = null)
        val studentId = students.saveStudent(firstName = "Ana", lastName = "López", email = null)
        classes.addStudentToClass(classId, studentId)

        val templateId = "template_col1"
        val columnId = "col1"
        val template = NotebookInstrumentTemplate(
            id = templateId,
            classId = classId,
            columnId = columnId,
            title = "Checklist",
            kind = NotebookInstrumentTemplateKind.CHECKLIST,
            inputKind = NotebookCellInputKind.STRUCTURED_FORM,
        )
        val keptItemId = "${templateId}_item_0"
        val droppedItemId = "${templateId}_item_1"
        instruments.saveTemplate(
            template,
            listOf(
                NotebookInstrumentItem(
                    id = keptItemId, templateId = templateId, key = "a", title = "Original",
                    type = NotebookInstrumentItemType.CHECK, order = 0,
                ),
                NotebookInstrumentItem(
                    id = droppedItemId, templateId = templateId, key = "b", title = "Se elimina",
                    type = NotebookInstrumentItemType.CHECK, order = 1,
                ),
            ),
        )

        db.appDatabaseQueries.upsertInstrumentResponse(
            class_id = classId,
            student_id = studentId,
            column_id = columnId,
            item_id = keptItemId,
            value_text = null,
            value_bool = 1L,
            value_number = null,
            updated_at_epoch_ms = 1L,
            device_id = null,
            sync_version = 0,
        )

        val newItemId = "${templateId}_item_2"
        instruments.saveTemplate(
            template,
            listOf(
                NotebookInstrumentItem(
                    id = keptItemId, templateId = templateId, key = "a", title = "Actualizado",
                    type = NotebookInstrumentItemType.CHECK, order = 0,
                ),
                NotebookInstrumentItem(
                    id = newItemId, templateId = templateId, key = "c", title = "Nuevo",
                    type = NotebookInstrumentItemType.CHECK, order = 1,
                ),
            ),
        )

        val detail = instruments.getTemplateForColumn(columnId)
        assertNotNull(detail)
        assertEquals(setOf(keptItemId, newItemId), detail.items.map { it.id }.toSet())
        assertEquals("Actualizado", detail.items.first { it.id == keptItemId }.title)

        val responses = instruments.listResponsesForCell(classId, studentId, columnId)
        assertEquals(listOf(keptItemId), responses.map { it.itemId })
        assertEquals(true, responses.single().boolValue)
    }

    @Test
    fun `saveLinkedResource upserts by business key instead of duplicating rows`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)
        val classes = ClassesRepositorySqlDelight(db)
        val situations = LearningSituationsRepositorySqlDelight(db)

        val classId = classes.saveClass(name = "3 ESO A", course = 3, description = null)
        val situationId = situations.saveSituation(LearningSituation(title = "Situación demo"))

        val firstId = situations.saveLinkedResource(
            LearningSituationLinkedResource(
                learningSituationId = situationId,
                kind = LearningSituationResourceKind.EVALUATION,
                resourceId = "eval_1",
                classId = classId,
                label = "Original",
            )
        )
        val firstCreatedAt = situations.listLinkedResources(situationId).single().trace.createdAt

        val secondId = situations.saveLinkedResource(
            LearningSituationLinkedResource(
                learningSituationId = situationId,
                kind = LearningSituationResourceKind.EVALUATION,
                resourceId = "eval_1",
                classId = classId,
                label = "Actualizado",
            )
        )

        val links = situations.listLinkedResources(situationId)
        assertEquals(1, links.size)
        assertEquals(firstId, secondId)
        assertEquals("Actualizado", links.single().label)
        assertEquals(firstCreatedAt, links.single().trace.createdAt)
    }

    @Test
    fun `saveLinkedResource upserts by business key when classId is null`() = runTest {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        AppDatabase.Schema.create(driver)
        val db = AppDatabase(driver)
        val situations = LearningSituationsRepositorySqlDelight(db)

        val situationId = situations.saveSituation(LearningSituation(title = "Situación demo"))

        val firstId = situations.saveLinkedResource(
            LearningSituationLinkedResource(
                learningSituationId = situationId,
                kind = LearningSituationResourceKind.EVALUATION,
                resourceId = "eval_1",
                classId = null,
                label = "Original",
            )
        )

        val secondId = situations.saveLinkedResource(
            LearningSituationLinkedResource(
                learningSituationId = situationId,
                kind = LearningSituationResourceKind.EVALUATION,
                resourceId = "eval_1",
                classId = null,
                label = "Actualizado",
            )
        )

        val links = situations.listLinkedResources(situationId)
        assertEquals(1, links.size)
        assertEquals(firstId, secondId)
        assertEquals("Actualizado", links.single().label)
    }
}
