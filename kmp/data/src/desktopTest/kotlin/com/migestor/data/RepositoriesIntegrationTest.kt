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
import com.migestor.data.repository.PlannerRepositorySqlDelight
import com.migestor.data.repository.SessionJournalRepositorySqlDelight
import com.migestor.data.repository.StudentsRepositorySqlDelight
import com.migestor.data.repository.TeacherScheduleRepositorySqlDelight
import com.migestor.data.repository.CalendarRepositorySqlDelight
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.ConfigTemplateKind
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
}
