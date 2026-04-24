package com.migestor.shared.repository

import com.migestor.shared.domain.*
import kotlinx.datetime.LocalDate
import kotlinx.coroutines.flow.Flow

interface StudentsRepository {
    fun observeStudents(): Flow<List<Student>>
    suspend fun listStudents(): List<Student>
    suspend fun saveStudent(
        id: Long? = null,
        firstName: String,
        lastName: String,
        email: String? = null,
        photoPath: String? = null,
        isInjured: Boolean = false,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
    suspend fun deleteStudent(studentId: Long)
}

interface ClassesRepository {
    fun observeClasses(): Flow<List<SchoolClass>>
    fun observeStudentsInClass(classId: Long): Flow<List<Student>>
    suspend fun listClasses(): List<SchoolClass>
    suspend fun saveClass(
        id: Long? = null,
        name: String,
        course: Int,
        description: String? = null,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
    suspend fun deleteClass(classId: Long)
    suspend fun addStudentToClass(classId: Long, studentId: Long)
    suspend fun removeStudentFromClass(classId: Long, studentId: Long)
    suspend fun listStudentsInClass(classId: Long): List<Student>
}

interface EvaluationsRepository {
    fun observeClassEvaluations(classId: Long): Flow<List<Evaluation>>
    suspend fun listClassEvaluations(classId: Long): List<Evaluation>
    suspend fun getEvaluation(evaluationId: Long): Evaluation?
    suspend fun saveEvaluation(
        id: Long? = null,
        classId: Long,
        code: String,
        name: String,
        type: String,
        weight: Double,
        formula: String? = null,
        rubricId: Long? = null,
        description: String? = null,
        authorUserId: Long? = null,
        createdAtEpochMs: Long = 0,
        updatedAtEpochMs: Long = 0,
        associatedGroupId: Long? = null,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
    suspend fun deleteEvaluation(evaluationId: Long)
    suspend fun saveEvaluationCompetencyLink(
        id: Long? = null,
        evaluationId: Long,
        competencyId: Long,
        weight: Double = 1.0,
        authorUserId: Long? = null,
    ): Long
    suspend fun listEvaluationCompetencyLinks(evaluationId: Long): List<EvaluationCompetencyLink>
}

interface GradesRepository {
    suspend fun saveGrade(
        id: Long? = null,
        classId: Long,
        studentId: Long,
        columnId: String,
        evaluationId: Long?,
        value: Double?,
        evidence: String? = null,
        evidencePath: String? = null,
        rubricSelections: String? = null,
        createdAtEpochMs: Long = 0,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
    suspend fun listGradesForClass(classId: Long): List<Grade>
    suspend fun listGradesForStudentInClass(studentId: Long, classId: Long): List<Grade>
    fun observeGradesForClass(classId: Long): Flow<List<Grade>>
    suspend fun upsertGrade(
        classId: Long,
        studentId: Long,
        columnId: String,
        evaluationId: Long?,
        value: Double?,
        evidence: String? = null,
        evidencePath: String? = null,
        rubricSelections: String? = null,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    )
}

interface NotebookCellsRepository {
    fun observeClassCells(classId: Long): Flow<List<PersistedNotebookCell>>
    suspend fun listClassCells(classId: Long): List<PersistedNotebookCell>
    suspend fun saveCell(
        classId: Long,
        studentId: Long,
        columnId: String,
        textValue: String? = null,
        boolValue: Boolean? = null,
        iconValue: String? = null,
        ordinalValue: String? = null,
        note: String? = null,
        colorHex: String? = null,
        attachmentUris: List<String> = emptyList(),
        authorUserId: Long? = null,
        associatedGroupId: Long? = null,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    )
}

interface NotebookRepository {
    suspend fun loadNotebookSnapshot(classId: Long): NotebookSheet
    fun observeStudentChanges(classId: Long): Flow<List<Student>>
    fun observeGradesForClass(classId: Long): Flow<List<Grade>>
    suspend fun addStudent(
        classId: Long, firstName: String, lastName: String, isInjured: Boolean): Student
    suspend fun removeStudent(classId: Long, studentId: Long)
    suspend fun listStudentsInClass(classId: Long): List<Student>
    suspend fun saveGrade(classId: Long, studentId: Long, columnId: String, evaluationId: Long?, value: Double?): Long
    suspend fun saveTab(classId: Long, tab: NotebookTab)
    suspend fun deleteTab(tabId: String)
    suspend fun saveColumn(classId: Long, column: NotebookColumnDefinition)
    suspend fun deleteColumn(columnId: String)
    suspend fun listColumnCategories(classId: Long, tabId: String? = null): List<NotebookColumnCategory>
    suspend fun saveColumnCategory(classId: Long, category: NotebookColumnCategory)
    suspend fun deleteColumnCategory(classId: Long, categoryId: String, preserveColumns: Boolean = true)
    suspend fun toggleCategoryCollapsed(classId: Long, categoryId: String, isCollapsed: Boolean)
    suspend fun reorderCategory(classId: Long, tabId: String, categoryId: String, targetCategoryId: String)
    suspend fun assignColumnToCategory(classId: Long, columnId: String, categoryId: String?)
    suspend fun deleteEvaluation(evaluationId: Long)
    suspend fun duplicateConfigToClass(sourceClassId: Long, targetClassId: Long)
    suspend fun listWorkGroups(classId: Long, tabId: String? = null): List<NotebookWorkGroup>
    suspend fun saveWorkGroup(classId: Long, workGroup: NotebookWorkGroup): Long
    suspend fun deleteWorkGroup(groupId: Long)
    suspend fun listWorkGroupMembers(classId: Long, tabId: String? = null): List<NotebookWorkGroupMember>
    suspend fun assignStudentsToWorkGroup(
        classId: Long,
        tabId: String,
        groupId: Long,
        studentIds: List<Long>,
    )
    suspend fun clearStudentsFromWorkGroup(
        classId: Long,
        tabId: String,
        studentIds: List<Long>,
    )
    suspend fun saveCell(
        classId: Long,
        studentId: Long,
        columnId: String,
        textValue: String? = null,
        boolValue: Boolean? = null,
        iconValue: String? = null,
        ordinalValue: String? = null,
        note: String? = null,
        colorHex: String? = null,
        attachmentUris: List<String> = emptyList(),
        authorUserId: Long? = null,
        associatedGroupId: Long? = null,
    )

    // New methods for Feature 2 & 3
    suspend fun getTabNamesForClass(classId: Long): List<String>
    suspend fun createTab(classId: Long, tabName: String): String
    suspend fun addColumnToTab(classId: Long, tabName: String, columnName: String, columnType: NotebookColumnType, rubricId: Long? = null): String

    suspend fun getNotebookConfig(classId: Long): NotebookConfig
    suspend fun getGradeForColumn(studentId: Long, columnId: String): Grade?
    suspend fun getColumnIdForEvaluation(evaluationId: Long): String?
    suspend fun upsertGrade(
        classId: Long,
        studentId: Long,
        columnId: String,
        numericValue: Double,
        rubricSelections: String? = null,
        evidence: String? = null,
        createdAtEpochMs: Long = 0,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    )
}

interface PlannerRepository {
    fun observeSessions(weekNumber: Int, year: Int): Flow<List<PlanningSession>>
    suspend fun listSessions(weekNumber: Int, year: Int): List<PlanningSession>
    suspend fun listAllSessions(): List<PlanningSession> = emptyList()
    suspend fun listSessionsInRange(groupId: Long? = null, fromDate: LocalDate, toDate: LocalDate): List<PlanningSession> = emptyList()
    @Throws(Exception::class)
    suspend fun upsertSession(session: PlanningSession): Long
    suspend fun bulkUpsertSessions(sessions: List<PlanningSession>): List<Long> = sessions.map { upsertSession(it) }
    suspend fun deleteSession(sessionId: Long)
    suspend fun deleteSessions(sessionIds: List<Long>) {
        sessionIds.forEach { deleteSession(it) }
    }
    fun observeTeachingUnits(groupId: Long? = null): Flow<List<TeachingUnit>>
    suspend fun listAllTeachingUnits(): List<TeachingUnit> = emptyList()
    suspend fun upsertTeachingUnit(unit: TeachingUnit): Long
    suspend fun deleteTeachingUnit(unitId: Long): Boolean
    fun getTimeSlots(): List<TimeSlotConfig>
    suspend fun moveSessionsFromWeek(fromWeek: Int, fromYear: Int, offsetWeeks: Int)
    suspend fun previewSessionRelocation(request: SessionRelocationRequest): List<SessionRelocationConflict> = emptyList()
    suspend fun copySessions(
        request: SessionRelocationRequest,
        resolution: CollisionResolution
    ): SessionBulkResult = SessionBulkResult()
    suspend fun shiftSelectedSessions(
        request: SessionRelocationRequest,
        resolution: CollisionResolution
    ): SessionBulkResult = SessionBulkResult()
}

interface SessionJournalRepository {
    suspend fun getOrCreateJournal(session: PlanningSession): SessionJournalAggregate
    suspend fun getJournalForSession(planningSessionId: Long): SessionJournalAggregate?
    suspend fun listSummariesForSessions(planningSessionIds: List<Long>): List<SessionJournalSummary>
    suspend fun saveJournalAggregate(aggregate: SessionJournalAggregate): Long
    suspend fun deleteJournalForSession(planningSessionId: Long)
}

data class ConflictPreview(
    val session: PlanningSession,
    val newDate: LocalDate,
    val isConflict: Boolean
)

interface RubricsRepository {
    fun observeRubrics(): Flow<List<RubricDetail>>
    suspend fun listRubrics(): List<RubricDetail>
    suspend fun saveRubric(
        id: Long? = null, 
        name: String, 
        description: String? = null,
        classId: Long? = null,
        teachingUnitId: Long? = null,
        createdAtEpochMs: Long = 0,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
    suspend fun deleteRubric(rubricId: Long)
    suspend fun saveCriterion(
        id: Long? = null,
        rubricId: Long,
        description: String,
        weight: Double,
        order: Int,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
    suspend fun deleteCriterion(criterionId: Long)
    suspend fun saveLevel(
        id: Long? = null,
        criterionId: Long,
        name: String,
        points: Int,
        description: String? = null,
        order: Int,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
    suspend fun deleteLevel(levelId: Long)
    suspend fun saveRubricAssessment(
        studentId: Long,
        evaluationId: Long,
        criterionId: Long,
        levelId: Long,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Double?
    suspend fun listRubricAssessments(studentId: Long, evaluationId: Long): List<RubricAssessment>
    suspend fun getStudentEvaluation(studentId: Long, rubricId: Long, evaluationId: Long): Map<Long, Long>
    suspend fun listCriteriaByRubric(rubricId: Long): List<RubricCriterion>
    suspend fun listLevelsByCriterion(criterionId: Long): List<RubricLevel>
}

interface AttendanceRepository {
    fun observeAttendance(classId: Long): Flow<List<Attendance>>
    fun observeAttendanceByDate(classId: Long, dateEpochMs: Long): Flow<List<Attendance>>
    suspend fun listAttendance(classId: Long): List<Attendance>
    suspend fun listAttendanceByDate(classId: Long, dateEpochMs: Long): List<Attendance>
    suspend fun saveAttendance(
        id: Long? = null,
        studentId: Long,
        classId: Long,
        dateEpochMs: Long,
        status: String,
        note: String = "",
        hasIncident: Boolean = false,
        followUpRequired: Boolean = false,
        sessionId: Long? = null,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
    suspend fun getAttendanceForClassBetweenDates(classId: Long, startDateMs: Long, endDateMs: Long): List<Attendance>
}

interface CompetenciesRepository {
    fun observeCompetencies(): Flow<List<CompetencyCriterion>>
    suspend fun listCompetencies(): List<CompetencyCriterion>
    suspend fun saveCompetency(
        id: Long? = null,
        code: String,
        name: String,
        description: String? = null,
        stageCycleId: Long? = null,
        authorUserId: Long? = null,
        associatedGroupId: Long? = null,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
}

interface IncidentsRepository {
    fun observeIncidents(classId: Long): Flow<List<Incident>>
    suspend fun listIncidents(classId: Long): List<Incident>
    suspend fun saveIncident(
        id: Long? = null,
        classId: Long,
        studentId: Long? = null,
        title: String,
        detail: String? = null,
        severity: String = "low",
        dateEpochMs: Long,
        authorUserId: Long? = null,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
}

interface CalendarRepository {
    fun observeEvents(classId: Long? = null): Flow<List<CalendarEvent>>
    suspend fun listEvents(classId: Long? = null): List<CalendarEvent>
    suspend fun saveEvent(
        id: Long? = null,
        classId: Long? = null,
        title: String,
        description: String? = null,
        startEpochMs: Long,
        endEpochMs: Long,
        externalProvider: String? = null,
        externalId: String? = null,
        authorUserId: Long? = null,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
}

interface ConfigurationTemplateRepository {
    fun observeTemplates(): Flow<List<ConfigTemplate>>
    suspend fun listTemplates(kind: ConfigTemplateKind? = null): List<ConfigTemplate>
    suspend fun saveTemplate(
        id: Long? = null,
        centerId: Long? = null,
        ownerUserId: Long,
        name: String,
        kind: ConfigTemplateKind,
        authorUserId: Long? = null,
        associatedGroupId: Long? = null,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
    suspend fun saveTemplateVersion(
        id: Long? = null,
        templateId: Long,
        payloadJson: String,
        basedOnVersionId: Long? = null,
        sourceAcademicYearId: Long? = null,
        authorUserId: Long? = null,
        associatedGroupId: Long? = null,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
    suspend fun listTemplateVersions(templateId: Long): List<ConfigTemplateVersion>
    suspend fun cloneLatestVersionToTemplate(
        sourceTemplateId: Long,
        targetTemplateId: Long,
        sourceAcademicYearId: Long? = null,
        authorUserId: Long? = null,
    ): Long
}

interface DashboardRepository {
    fun observeStats(): Flow<DashboardStats>
    suspend fun getStats(): DashboardStats
}

interface DashboardOperationalRepository {
    suspend fun getSnapshot(
        date: LocalDate,
        mode: DashboardMode,
        filters: DashboardFilters = DashboardFilters(),
    ): DashboardSnapshot

    suspend fun executeQuickAction(command: QuickActionCommand): QuickActionResult
}

interface BackupMetadataRepository {
    fun observeBackups(): Flow<List<BackupEntry>>
    suspend fun listBackups(): List<BackupEntry>
    suspend fun saveBackup(path: String, createdAtEpochMs: Long, platform: String, sizeBytes: Long): Long
    suspend fun deleteBackup(id: Long)
}

interface AIAuditRepository {
    suspend fun recordEvent(event: AIAuditEvent)
    suspend fun recentEvents(limit: Long = 50): List<AIAuditEvent>
    suspend fun recentFailures(limit: Long = 20): List<AIAuditEvent>
    suspend fun latestEvent(): AIAuditEvent?
    suspend fun totalsByUseCase(): List<AIAuditUseCaseTotal>
    suspend fun recentAvailabilityTotals(): List<AIAuditAvailabilityTotal>
}

interface CsvImportService {
    suspend fun parseStudents(csv: String): List<StudentCsvRow>
}

interface XlsxImportService {
    suspend fun parseStudents(bytes: ByteArray): List<StudentCsvRow>
    suspend fun parseRubric(bytes: ByteArray, fallbackTitle: String = "Rúbrica importada"): ImportedRubric
}

interface ReportService {
    suspend fun exportNotebookReport(request: NotebookReportRequest): ByteArray
}

interface BackupService {
    suspend fun createBackup(fileName: String = "mi_gestor_backup.sqlite"): BackupResult
    suspend fun restoreBackup(backupPath: String): Boolean
}

data class StudentCsvRow(
    val firstName: String,
    val lastName: String,
    val email: String? = null,
)

data class NotebookReportRequest(
    val className: String,
    val rows: List<String>,
)

data class ImportedRubric(
    val title: String,
    val levels: List<ImportedRubricLevel>,
    val criteria: List<ImportedRubricCriterion>,
)

data class ImportedRubricLevel(
    val name: String,
    val points: Int,
)

data class ImportedRubricCriterion(
    val name: String,
    val cells: List<String>,
)

data class BackupResult(
    val path: String,
    val sizeBytes: Long,
)

interface WeeklyTemplateRepository {
    fun getSlotsForClass(schoolClassId: Long): List<WeeklySlotTemplate>
    fun observeAllSlots(): Flow<List<WeeklySlotTemplate>>
    suspend fun insert(slot: WeeklySlotTemplate): Long
    suspend fun delete(slotId: Long)
}

interface TeacherScheduleRepository {
    @Throws(Exception::class)
    suspend fun getOrCreatePrimarySchedule(): TeacherSchedule
    @Throws(Exception::class)
    suspend fun saveSchedule(schedule: TeacherSchedule): Long
    @Throws(Exception::class)
    suspend fun listScheduleSlots(scheduleId: Long): List<TeacherScheduleSlot>
    @Throws(Exception::class)
    suspend fun getScheduleSlot(slotId: Long): TeacherScheduleSlot?
    @Throws(Exception::class)
    suspend fun saveScheduleSlot(slot: TeacherScheduleSlot): Long
    @Throws(Exception::class)
    suspend fun deleteScheduleSlot(slotId: Long)
    @Throws(Exception::class)
    suspend fun listEvaluationPeriods(scheduleId: Long): List<PlannerEvaluationPeriod>
    @Throws(Exception::class)
    suspend fun saveEvaluationPeriod(period: PlannerEvaluationPeriod): Long
    @Throws(Exception::class)
    suspend fun deleteEvaluationPeriod(periodId: Long)
    @Throws(Exception::class)
    suspend fun buildForecasts(scheduleId: Long, classId: Long? = null): List<PlannerSessionForecast>
}

interface PlannedSessionRepository {
    suspend fun getSessionsForClass(schoolClassId: Long, startDate: LocalDate, endDate: LocalDate): List<PlannedSession>
    fun observeSessionsForClass(schoolClassId: Long, startDate: LocalDate, endDate: LocalDate): Flow<List<PlannedSession>>
    fun observeAllSessions(startDate: LocalDate, endDate: LocalDate): Flow<List<PlannedSession>>
    suspend fun getAllSessions(startDate: LocalDate, endDate: LocalDate): List<PlannedSession>
    suspend fun existsAt(schoolClassId: Long, date: LocalDate, startTime: String): Boolean
    suspend fun insert(session: PlannedSession): Long
    suspend fun update(session: PlannedSession)
    suspend fun delete(sessionId: Long)
    suspend fun listSessionsInRange(schoolClassId: Long? = null, startDate: LocalDate, endDate: LocalDate): List<PlannedSession> =
        if (schoolClassId != null) getSessionsForClass(schoolClassId, startDate, endDate) else getAllSessions(startDate, endDate)
    suspend fun deleteSessions(sessionIds: List<Long>) {
        sessionIds.forEach { delete(it) }
    }
    suspend fun bulkUpsertOrReplacePlannedSessions(sessions: List<PlannedSession>): List<Long> = sessions.map { insert(it) }
}
