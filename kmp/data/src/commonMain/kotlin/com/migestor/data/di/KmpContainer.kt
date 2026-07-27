package com.migestor.data.di

import app.cash.sqldelight.db.SqlDriver
import com.migestor.data.db.AppDatabase
import com.migestor.data.platform.wipeAllUserData
import com.migestor.data.repository.AttendanceRepositorySqlDelight
import com.migestor.data.repository.AIAuditRepositorySqlDelight
import com.migestor.data.repository.AcademicYearsRepositorySqlDelight
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
import com.migestor.data.repository.NotebookInstrumentsRepositorySqlDelight
import com.migestor.data.repository.RubricsRepositorySqlDelight
import com.migestor.data.repository.StudentsRepositorySqlDelight
import com.migestor.data.repository.StudentSupportMeasureRepositorySqlDelight
import com.migestor.data.repository.StudentTutoringSessionRepositorySqlDelight
import com.migestor.data.repository.MeetingRepositorySqlDelight
import com.migestor.data.repository.PlannerWeekPlanRepositorySqlDelight
import com.migestor.data.repository.SubjectsRepositorySqlDelight
import com.migestor.data.repository.NotebookRepositorySqlDelight
import com.migestor.data.repository.PlannerRepositorySqlDelight
import com.migestor.data.repository.PhysicalTestsRepositorySqlDelight
import com.migestor.data.repository.SessionJournalRepositorySqlDelight
import com.migestor.data.repository.TeacherScheduleRepositorySqlDelight
import com.migestor.data.repository.WeeklyTemplateRepositorySqlDelight
import com.migestor.data.repository.PlannedSessionRepositorySqlDelight
import com.migestor.data.repository.LearningSituationsRepositorySqlDelight
import com.migestor.data.repository.SyncTombstoneRepositorySqlDelight
import com.migestor.data.repository.AITrendsRepositorySqlDelight
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
import com.migestor.shared.usecase.SaveSubjectUseCase
import kotlinx.datetime.Clock

import com.migestor.data.repository.NotebookConfigRepositorySqlDelight
import com.migestor.shared.repository.*
import com.migestor.shared.usecase.*

class KmpContainer(val driver: SqlDriver) {
    val database = AppDatabase(driver)

    val studentsRepository: StudentsRepository = StudentsRepositorySqlDelight(database)
    val academicYearsRepository: AcademicYearsRepository = AcademicYearsRepositorySqlDelight(database)
    val classesRepository: ClassesRepository = ClassesRepositorySqlDelight(database)
    val subjectsRepository: SubjectsRepository = SubjectsRepositorySqlDelight(database)
    val notebookConfigRepository: NotebookConfigRepository = NotebookConfigRepositorySqlDelight(database)
    val evaluationsRepository: EvaluationsRepository = EvaluationsRepositorySqlDelight(database)
    val gradesRepository: GradesRepository = GradesRepositorySqlDelight(database)
    val notebookCellsRepository: NotebookCellsRepository = NotebookCellsRepositorySqlDelight(database)
    // Compartida entre NotebookRepositorySqlDelight y NotebookInstrumentsRepositorySqlDelight
    // para que guardar respuestas estructuradas (checklist/observación/quiz) invalide el mismo
    // caché de NotebookSheet que usan los guardados de nota normales, y el Cuaderno refleje el
    // cambio de inmediato en vez de servir una hoja cacheada desactualizada.
    val notebookSheetCache = NotebookSheetMemoryCache()
    val notebookInstrumentsRepository: NotebookInstrumentsRepository = NotebookInstrumentsRepositorySqlDelight(database, gradesRepository, notebookSheetCache)
    val rubricsRepository: RubricsRepository = RubricsRepositorySqlDelight(database)
    val attendanceRepository: AttendanceRepository = AttendanceRepositorySqlDelight(database)
    val studentSupportMeasureRepository: StudentSupportMeasureRepository = StudentSupportMeasureRepositorySqlDelight(database)
    val studentTutoringSessionRepository: StudentTutoringSessionRepository = StudentTutoringSessionRepositorySqlDelight(database)
    val meetingRepository: MeetingRepository = MeetingRepositorySqlDelight(database)
    val plannerWeekPlanRepository: PlannerWeekPlanRepository = PlannerWeekPlanRepositorySqlDelight(database)
    val aiAuditRepository: AIAuditRepository = AIAuditRepositorySqlDelight(database)
    val competenciesRepository: CompetenciesRepository = CompetenciesRepositorySqlDelight(database)
    val incidentsRepository: IncidentsRepository = IncidentsRepositorySqlDelight(database)
    val calendarRepository: CalendarRepository = CalendarRepositorySqlDelight(database)
    val configurationTemplateRepository: ConfigurationTemplateRepository = ConfigurationTemplateRepositorySqlDelight(database)
    val dashboardRepository: DashboardRepository = DashboardRepositorySqlDelight(database)
    val backupMetadataRepository: BackupMetadataRepository = BackupMetadataRepositorySqlDelight(database)
    val plannerRepository: PlannerRepository = PlannerRepositorySqlDelight(database)
    val physicalTestsRepository: PhysicalTestsRepository = PhysicalTestsRepositorySqlDelight(database)
    val sessionJournalRepository: SessionJournalRepository = SessionJournalRepositorySqlDelight(database)
    val weeklyTemplateRepository: WeeklyTemplateRepository = WeeklyTemplateRepositorySqlDelight(database)
    val plannedSessionRepository: PlannedSessionRepository = PlannedSessionRepositorySqlDelight(database)
    val learningSituationsRepository: LearningSituationsRepository = LearningSituationsRepositorySqlDelight(database)
    val syncTombstoneRepository = SyncTombstoneRepositorySqlDelight(database)
    val aiTrendsRepository: AITrendsRepository = AITrendsRepositorySqlDelight(database)
    val teacherScheduleRepository: TeacherScheduleRepository = TeacherScheduleRepositorySqlDelight(
        db = database,
        plannerRepository = plannerRepository,
        calendarRepository = calendarRepository,
        classesRepository = classesRepository
    )
    val dashboardOperationalRepository: DashboardOperationalRepository = DashboardOperationalRepositoryDefault(
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
    
    val csvImportService: CsvImportService = CsvImportServiceImpl()
    val xlsxImportService: XlsxImportService = createPlatformXlsxImportService()
    val reportService: ReportService = createPlatformReportService()
    val backupService: BackupService = createPlatformBackupService()

    val saveStudent = SaveStudentUseCase(studentsRepository)
    val saveClass = SaveClassUseCase(classesRepository)
    val saveSubject = SaveSubjectUseCase(subjectsRepository)
    val saveEvaluation = SaveEvaluationUseCase(evaluationsRepository)
    val recordGrade = RecordGradeUseCase(gradesRepository)
    val saveRubric = SaveRubricUseCase(rubricsRepository)
    val saveCriterion = SaveCriterionUseCase(rubricsRepository)
    val saveLevel = SaveLevelUseCase(rubricsRepository)
    val saveAttendance = SaveAttendanceUseCase(attendanceRepository)
    val saveStudentSupportMeasure = SaveStudentSupportMeasureUseCase(studentSupportMeasureRepository)
    val retireStudentSupportMeasure = RetireStudentSupportMeasureUseCase(studentSupportMeasureRepository)
    val listStudentSupportMeasures = ListStudentSupportMeasuresUseCase(studentSupportMeasureRepository)
    val listActiveSupportMeasureStudentIds = ListActiveSupportMeasureStudentIdsUseCase(studentSupportMeasureRepository)
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
    val getAITrendsAndMetrics = GetAITrendsAndMetricsUseCase(aiTrendsRepository)

    val notebookRepository = NotebookRepositorySqlDelight(
        db = database,
        studentsRepository = studentsRepository,
        classesRepository = classesRepository,
        evaluationsRepository = evaluationsRepository,
        notebookConfigRepository = notebookConfigRepository,
        buildNotebookSheetUseCase = buildNotebookSheet,
        gradesRepository = gradesRepository,
        notebookCellsRepository = notebookCellsRepository,
        sheetCache = notebookSheetCache
    )
    val preloadClassWorkspace = PreloadClassWorkspaceUseCase(
        dashboardOperationalRepository = dashboardOperationalRepository,
        notebookRepository = notebookRepository,
        classesRepository = classesRepository,
        attendanceRepository = attendanceRepository,
    )

    /**
     * Borrado total: vacia todas las tablas por SQL, con la conexion que ya esta abierta.
     *
     * La capa Swift llamaba antes a esto borrando el fichero SQLite del disco, lo que
     * invalidaba los descriptores del driver y acababa abortando el proceso
     * (ver `wipeAllUserData` en DatabaseWipe.kt). Los adjuntos y las copias de seguridad
     * los sigue borrando Swift: son ficheros que nadie tiene abiertos.
     *
     * Los `Flow` ya suscritos no se re-emiten (el borrado no pasa por las queries
     * generadas de SQLDelight, asi que sus listeners no se notifican). No es un problema
     * porque el borrado exige reinicio de la app en ambas plataformas, pero es la razon
     * por la que no basta con llamar a esto y seguir usando la sesion actual.
     */
    @Throws(Throwable::class)
    fun wipeAllData() {
        wipeAllUserData(driver, database)
    }

    @Throws(Throwable::class)
    fun wipeSelectiveData(categories: Set<com.migestor.data.platform.WipeCategory>) {
        com.migestor.data.platform.wipeSelectiveUserData(driver, database, categories)
    }

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
