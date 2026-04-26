package com.migestor.data.di

import app.cash.sqldelight.db.SqlDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.repository.AttendanceRepositorySqlDelight
import com.migestor.data.repository.AIAuditRepositorySqlDelight
import com.migestor.data.repository.BackupMetadataRepositorySqlDelight
import com.migestor.data.repository.CalendarRepositorySqlDelight
import com.migestor.data.repository.ClassesRepositorySqlDelight
import com.migestor.data.repository.CompetenciesRepositorySqlDelight
import com.migestor.data.repository.ConfigurationTemplateRepositorySqlDelight
import com.migestor.data.repository.DashboardRepositorySqlDelight
import com.migestor.data.repository.DashboardOperationalRepositoryDefault
import com.migestor.data.repository.EvaluationsRepositorySqlDelight
import com.migestor.data.repository.GradesRepositorySqlDelight
import com.migestor.data.repository.IncidentsRepositorySqlDelight
import com.migestor.data.repository.NotebookCellsRepositorySqlDelight
import com.migestor.data.repository.RubricsRepositorySqlDelight
import com.migestor.data.repository.StudentsRepositorySqlDelight
import com.migestor.data.repository.NotebookRepositorySqlDelight
import com.migestor.data.repository.PlannerRepositorySqlDelight
import com.migestor.data.repository.SessionJournalRepositorySqlDelight
import com.migestor.data.repository.TeacherScheduleRepositorySqlDelight
import com.migestor.data.repository.WeeklyTemplateRepositorySqlDelight
import com.migestor.data.repository.PlannedSessionRepositorySqlDelight
import com.migestor.data.service.CsvImportServiceImpl
import com.migestor.data.service.createPlatformBackupService
import com.migestor.data.service.createPlatformReportService
import com.migestor.data.service.createPlatformXlsxImportService
import com.migestor.shared.usecase.GetNotebookUseCase
import com.migestor.shared.usecase.GetNotebookConfigUseCase
import com.migestor.shared.usecase.BuildNotebookSheetUseCase
import com.migestor.shared.usecase.RecordGradeUseCase
import com.migestor.shared.usecase.SaveAttendanceUseCase
import com.migestor.shared.usecase.SaveClassUseCase
import com.migestor.shared.usecase.SaveCriterionUseCase
import com.migestor.shared.usecase.SaveEvaluationUseCase
import com.migestor.shared.usecase.SaveLevelUseCase
import com.migestor.shared.usecase.SaveRubricUseCase
import com.migestor.shared.usecase.SaveSessionUseCase
import com.migestor.shared.usecase.SaveStudentUseCase
import kotlinx.datetime.Clock

import com.migestor.data.repository.NotebookConfigRepositorySqlDelight
import com.migestor.shared.usecase.*

class KmpContainer(val driver: SqlDriver) {
    val database = AppDatabase(driver)

    val studentsRepository = StudentsRepositorySqlDelight(database)
    val classesRepository = ClassesRepositorySqlDelight(database)
    val notebookConfigRepository = NotebookConfigRepositorySqlDelight(database)
    val evaluationsRepository = EvaluationsRepositorySqlDelight(database)
    val gradesRepository = GradesRepositorySqlDelight(database)
    val notebookCellsRepository = NotebookCellsRepositorySqlDelight(database)
    val rubricsRepository = RubricsRepositorySqlDelight(database)
    val attendanceRepository = AttendanceRepositorySqlDelight(database)
    val aiAuditRepository = AIAuditRepositorySqlDelight(database)
    val competenciesRepository = CompetenciesRepositorySqlDelight(database)
    val incidentsRepository = IncidentsRepositorySqlDelight(database)
    val calendarRepository = CalendarRepositorySqlDelight(database)
    val configurationTemplateRepository = ConfigurationTemplateRepositorySqlDelight(database)
    val dashboardRepository = DashboardRepositorySqlDelight(database)
    val backupMetadataRepository = BackupMetadataRepositorySqlDelight(database)
    val plannerRepository = PlannerRepositorySqlDelight(database)
    val sessionJournalRepository = SessionJournalRepositorySqlDelight(database)
    val weeklyTemplateRepository = WeeklyTemplateRepositorySqlDelight(database)
    val plannedSessionRepository = PlannedSessionRepositorySqlDelight(database)
    val teacherScheduleRepository = TeacherScheduleRepositorySqlDelight(
        db = database,
        plannerRepository = plannerRepository,
        calendarRepository = calendarRepository,
        classesRepository = classesRepository
    )
    val dashboardOperationalRepository = DashboardOperationalRepositoryDefault(
        classesRepository = classesRepository,
        attendanceRepository = attendanceRepository,
        evaluationsRepository = evaluationsRepository,
        gradesRepository = gradesRepository,
        notebookConfigRepository = notebookConfigRepository,
        incidentsRepository = incidentsRepository,
        calendarRepository = calendarRepository,
        plannerRepository = plannerRepository,
        rubricsRepository = rubricsRepository,
    )
    
    val csvImportService = CsvImportServiceImpl()
    val xlsxImportService = createPlatformXlsxImportService()
    val reportService = createPlatformReportService()
    val backupService = createPlatformBackupService()

    val saveStudent = SaveStudentUseCase(studentsRepository)
    val saveClass = SaveClassUseCase(classesRepository)
    val saveEvaluation = SaveEvaluationUseCase(evaluationsRepository)
    val recordGrade = RecordGradeUseCase(gradesRepository)
    val saveRubric = SaveRubricUseCase(rubricsRepository)
    val saveCriterion = SaveCriterionUseCase(rubricsRepository)
    val saveLevel = SaveLevelUseCase(rubricsRepository)
    val saveAttendance = SaveAttendanceUseCase(attendanceRepository)
    val saveWeeklyTemplate = SaveWeeklyTemplateUseCase(weeklyTemplateRepository)
    val generateSessionsFromUD = GenerateSessionsFromUDUseCase(weeklyTemplateRepository, plannedSessionRepository)
    val deleteStudent = DeleteStudentUseCase(studentsRepository, classesRepository)
    val getNotebook = GetNotebookUseCase(
        classesRepository = classesRepository,
        evaluationsRepository = evaluationsRepository,
        gradesRepository = gradesRepository,
        notebookCellsRepository = notebookCellsRepository,
    )
    val buildNotebookSheet = BuildNotebookSheetUseCase(getNotebook)
    val getNotebookConfig = GetNotebookConfigUseCase(notebookConfigRepository)
    val getOperationalDashboardSnapshot = GetOperationalDashboardSnapshotUseCase(dashboardOperationalRepository)

    val notebookRepository = NotebookRepositorySqlDelight(
        db = database,
        studentsRepository = studentsRepository,
        classesRepository = classesRepository,
        evaluationsRepository = evaluationsRepository,
        notebookConfigRepository = notebookConfigRepository,
        buildNotebookSheetUseCase = buildNotebookSheet,
        gradesRepository = gradesRepository,
        notebookCellsRepository = notebookCellsRepository
    )

    suspend fun seedDemoDataIfEmpty() {
        val now = Clock.System.now().toEpochMilliseconds()
        if (studentsRepository.listStudents().isNotEmpty()) return

        val classId = saveClass(name = "3 ESO A", course = 3, description = "Clase demo")
        val studentA = saveStudent(firstName = "Ana", lastName = "López", email = null)
        val studentB = saveStudent(firstName = "Pablo", lastName = "García", email = null)
        classesRepository.addStudentToClass(classId, studentA)
        classesRepository.addStudentToClass(classId, studentB)

        val examId = saveEvaluation(
            classId = classId,
            code = "EX1",
            name = "Examen 1",
            type = "Examen",
            weight = 0.6,
            formula = null,
            rubricId = null,
            description = "Prueba escrita",
        )
        val taskId = saveEvaluation(
            classId = classId,
            code = "TA1",
            name = "Tarea 1",
            type = "Tarea",
            weight = 0.4,
            formula = null,
            rubricId = null,
            description = "Actividad práctica",
        )

        recordGrade(classId = classId, studentId = studentA, evaluationId = examId, value = 8.0)
        recordGrade(classId = classId, studentId = studentA, evaluationId = taskId, value = 9.0)
        recordGrade(classId = classId, studentId = studentB, evaluationId = examId, value = 6.5)
        recordGrade(classId = classId, studentId = studentB, evaluationId = taskId, value = 7.0)

        // Seed Planner Data
        val unitId = plannerRepository.upsertTeachingUnit(
            com.migestor.shared.domain.TeachingUnit(
                name = "Condición Física",
                description = "Mejorar resistencia y fuerza",
                colorHex = "#4A90D9",
                groupId = classId
            )
        )
        
        val currentWeek = com.migestor.shared.util.IsoWeekHelper.current()
        plannerRepository.upsertSession(
            com.migestor.shared.domain.PlanningSession(
                teachingUnitId = unitId,
                teachingUnitName = "Condición Física",
                groupId = classId,
                groupName = "3 ESO A",
                dayOfWeek = 1,
                period = 1,
                weekNumber = currentWeek.first,
                year = currentWeek.second,
                objectives = "Introducción a la sesión",
                activities = "Calentamiento y tests",
                status = com.migestor.shared.domain.SessionStatus.PLANNED
            )
        )

        val rubricId = saveRubric(name = "Rúbrica expresión corporal", description = "Demo")
        val criterionId = saveCriterion(
            rubricId = rubricId,
            description = "Coordinación",
            weight = 1.0,
            order = 0,
        )
        saveLevel(
            criterionId = criterionId,
            name = "Excelente",
            points = 10,
            description = "Dominio completo",
            order = 0,
        )

        saveAttendance(
            studentId = studentA,
            classId = classId,
            dateEpochMs = now,
            status = "presente",
        )
    }

    suspend fun createRubricBundle(
        name: String,
        criterion: String,
        level: String,
        points: Int,
    ): String? {
        return try {
            val rubricId = saveRubric(name = name, description = null)
            val criterionId = saveCriterion(
                rubricId = rubricId,
                description = criterion,
                weight = 1.0,
                order = 0,
            )
            saveLevel(
                criterionId = criterionId,
                name = level,
                points = points,
                description = null,
                order = 0,
            )
            null
        } catch (t: Throwable) {
            t.message ?: "No se pudo crear la rúbrica"
        }
    }
}
