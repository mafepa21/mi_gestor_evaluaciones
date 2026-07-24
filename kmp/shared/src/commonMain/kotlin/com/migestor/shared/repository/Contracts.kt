package com.migestor.shared.repository

import com.migestor.shared.domain.*
import kotlinx.datetime.LocalDate
import kotlinx.coroutines.flow.Flow

interface StudentsRepository {
    fun observeStudents(): Flow<List<Student>>
    suspend fun listStudents(): List<Student>
    suspend fun getStudent(studentId: Long): Student? = listStudents().find { it.id == studentId }
    suspend fun getStudentProfileSnapshot(studentId: Long): StudentProfileSnapshot? =
        getStudent(studentId)?.let { student ->
            StudentProfileSnapshot(
                studentId = student.id,
                fullName = student.fullName,
                classCount = 0,
                activeEvaluationCount = 0,
                latestActivityEpochMs = null,
            )
        }
    suspend fun saveStudent(
        id: Long? = null,
        firstName: String,
        lastName: String,
        email: String? = null,
        photoPath: String? = null,
        isInjured: Boolean = false,
        sex: StudentSex = StudentSex.UNSPECIFIED,
        sexSource: StudentSexSource = StudentSexSource.UNKNOWN,
        birthDate: LocalDate? = null,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
    /**
     * Camino de sync (LWW): a diferencia de [saveStudent] -pensado para ediciones
     * locales, que siempre deben aplicarse-, descarta la escritura si el registro
     * existente tiene un `updatedAtEpochMs` mas reciente (o empate resuelto por
     * deviceId). Implementacion por defecto sin guard (delega a [saveStudent]),
     * pensada para dobles/fakes de test; [StudentsRepositorySqlDelight] la
     * sobrescribe con el guard real.
     */
    suspend fun upsertStudent(
        id: Long?,
        firstName: String,
        lastName: String,
        email: String? = null,
        photoPath: String? = null,
        isInjured: Boolean = false,
        sex: StudentSex = StudentSex.UNSPECIFIED,
        sexSource: StudentSexSource = StudentSexSource.UNKNOWN,
        birthDate: LocalDate? = null,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ) {
        saveStudent(id, firstName, lastName, email, photoPath, isInjured, sex, sexSource, birthDate, updatedAtEpochMs, deviceId, syncVersion)
    }
    suspend fun deleteStudent(studentId: Long)
}

interface ClassesRepository {
    fun observeClasses(): Flow<List<SchoolClass>>
    fun observeStudentsInClass(classId: Long): Flow<List<Student>>
    suspend fun listClasses(): List<SchoolClass>
    suspend fun listCourseOverviews(): List<CourseOverview> = listClasses().map {
        CourseOverview(
            classId = it.id,
            name = it.name,
            course = it.course,
            studentCount = 0,
            visibleColumnCount = 0,
            pendingCellCount = 0,
            averageScore = null,
        )
    }
    suspend fun listAllClasses(): List<SchoolClass> = listClasses()
    suspend fun listClassesForAcademicYear(academicYearId: Long): List<SchoolClass> =
        listAllClasses().filter { it.academicYearId == academicYearId }
    suspend fun saveClass(
        id: Long? = null,
        name: String,
        course: Int,
        description: String? = null,
        centerId: Long? = null,
        academicYearId: Long? = null,
        stageCycleId: Long? = null,
        subjectId: Long? = null,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
    suspend fun deleteClass(classId: Long)
    suspend fun addStudentToClass(classId: Long, studentId: Long)
    suspend fun promoteStudentToClass(
        sourceClassId: Long,
        targetClassId: Long,
        studentId: Long,
        promotionStatus: String = "PROMOTED",
    ) = addStudentToClass(targetClassId, studentId)
    suspend fun removeStudentFromClass(classId: Long, studentId: Long)
    suspend fun listStudentsInClass(classId: Long): List<Student>
}

interface AcademicYearsRepository {
    fun observeAcademicYears(): Flow<List<AcademicYear>>
    @Throws(Exception::class)
    suspend fun listAcademicYears(): List<AcademicYear>
    @Throws(Exception::class)
    suspend fun getActiveAcademicYear(): AcademicYear?
    @Throws(Exception::class)
    suspend fun createAcademicYear(
        name: String,
        startEpochMs: Long,
        endEpochMs: Long,
        centerId: Long? = null,
        makeActive: Boolean = true,
    ): Long
    @Throws(Exception::class)
    suspend fun upsertAcademicYear(
        id: Long,
        centerId: Long,
        name: String,
        startEpochMs: Long,
        endEpochMs: Long,
        status: String,
        isActive: Boolean,
        archivedAtEpochMs: Long? = null,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long = createAcademicYear(
        name = name,
        startEpochMs = startEpochMs,
        endEpochMs = endEpochMs,
        centerId = centerId,
        makeActive = isActive,
    )
    @Throws(Exception::class)
    suspend fun setActiveAcademicYear(academicYearId: Long)
    @Throws(Exception::class)
    suspend fun archiveAcademicYear(academicYearId: Long)
    @Throws(Exception::class)
    suspend fun trashAcademicYear(academicYearId: Long) = archiveAcademicYear(academicYearId)
    @Throws(Exception::class)
    suspend fun deleteArchivedAcademicYear(academicYearId: Long)
    @Throws(Exception::class)
    suspend fun enrollmentCount(academicYearId: Long): Long = 0
}

interface SubjectsRepository {
    fun observeSubjects(): Flow<List<Subject>>
    suspend fun listSubjects(): List<Subject>
    suspend fun saveSubject(
        id: Long? = null,
        code: String,
        name: String,
        stageCycleId: Long? = null,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
    suspend fun deleteSubject(subjectId: Long)
}

interface EvaluationsRepository {
    fun observeClassEvaluations(classId: Long): Flow<List<Evaluation>>
    suspend fun listClassEvaluations(classId: Long): List<Evaluation>
    suspend fun getPendingEvaluationsSummary(classId: Long): PendingEvaluationsSummary =
        PendingEvaluationsSummary(classId = classId)
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

data class NotebookQueuedCellDraft(
    val studentId: Long,
    val columnId: String,
    val columnType: NotebookColumnType,
    val evaluationId: Long?,
    val value: String,
)

data class CourseOverview(
    val classId: Long,
    val name: String,
    val course: Int,
    val studentCount: Int,
    val visibleColumnCount: Int,
    val pendingCellCount: Int,
    val averageScore: Double?,
)

data class NotebookSummary(
    val classId: Long,
    val studentCount: Int = 0,
    val visibleColumnCount: Int = 0,
    val pendingCellCount: Int = 0,
    val averageScore: Double? = null,
)

data class NotebookVisibleColumnSummary(
    val id: String,
    val title: String,
    val type: NotebookColumnType,
    val evaluationId: Long?,
    val categoryId: String?,
    val order: Int,
    val widthDp: Double?,
    val isPinned: Boolean,
)

data class NotebookRowPageItem(
    val studentId: Long,
    val firstName: String,
    val lastName: String,
    val isInjured: Boolean,
    val filledCellCount: Int,
    val averageScore: Double?,
) {
    val fullName: String get() = listOf(firstName, lastName).joinToString(" ").trim()
}

data class StudentProfileSnapshot(
    val studentId: Long,
    val fullName: String,
    val email: String? = null,
    val photoPath: String? = null,
    val isInjured: Boolean = false,
    val classCount: Int,
    val activeEvaluationCount: Int,
    val latestActivityEpochMs: Long?,
    val averageScore: Double? = null,
)

data class DashboardTodaySnapshot(
    val activeClassCount: Int = 0,
    val activeStudentCount: Int = 0,
    val todaySessionCount: Int = 0,
    val pendingEvaluationCount: Int = 0,
    val incidentCount: Int = 0,
)

data class PendingEvaluationsSummary(
    val classId: Long,
    val evaluationCount: Int = 0,
    val pendingCellCount: Int = 0,
    val completedCellCount: Int = 0,
    val completionPct: Int = 0,
)

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
    fun observeCellAudit(classId: Long, studentId: Long, columnId: String): Flow<List<NotebookCellAuditEvent>>
}

interface NotebookInstrumentsRepository {
    suspend fun saveTemplate(
        template: NotebookInstrumentTemplate,
        items: List<NotebookInstrumentItem>,
    )

    suspend fun getTemplateForColumn(columnId: String): NotebookInstrumentDetail?

    suspend fun listResponsesForCell(
        classId: Long,
        studentId: Long,
        columnId: String,
    ): List<NotebookInstrumentResponse>

    suspend fun saveResponses(
        classId: Long,
        studentId: Long,
        columnId: String,
        responses: List<NotebookInstrumentResponse>,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): NotebookInstrumentCellSummary
}

interface NotebookRepository {
    suspend fun loadNotebookSnapshot(classId: Long): NotebookSheet
    suspend fun loadNotebookSummary(classId: Long): NotebookSummary = NotebookSummary(classId = classId)
    suspend fun listNotebookVisibleColumns(classId: Long, tabId: String? = null): List<NotebookVisibleColumnSummary> =
        emptyList()
    suspend fun listNotebookRowsPage(classId: Long, limit: Long, offset: Long): List<NotebookRowPageItem> =
        emptyList()
    fun observeStudentChanges(classId: Long): Flow<List<Student>>
    fun observeGradesForClass(classId: Long): Flow<List<Grade>>
    suspend fun addStudent(
        classId: Long, firstName: String, lastName: String, isInjured: Boolean): Student
    suspend fun removeStudent(classId: Long, studentId: Long)
    suspend fun listStudentsInClass(classId: Long): List<Student>
    suspend fun saveGrade(classId: Long, studentId: Long, columnId: String, evaluationId: Long?, value: Double?): Long
    suspend fun saveQueuedCellDrafts(classId: Long, drafts: List<NotebookQueuedCellDraft>) {
        drafts.forEach { draft ->
            when (draft.columnType) {
                NotebookColumnType.NUMERIC -> {
                    val raw = draft.value.trim()
                    val numericValue = raw.replace(",", ".").toDoubleOrNull()
                    if (raw.isEmpty() || numericValue != null) {
                        saveGrade(classId, draft.studentId, draft.columnId, draft.evaluationId, numericValue)
                    }
                }
                NotebookColumnType.TEXT -> saveCell(classId, draft.studentId, draft.columnId, textValue = draft.value)
                NotebookColumnType.CHECK -> saveCell(classId, draft.studentId, draft.columnId, boolValue = draft.value.toBoolean())
                NotebookColumnType.ICON -> saveCell(classId, draft.studentId, draft.columnId, iconValue = draft.value)
                NotebookColumnType.ORDINAL -> saveCell(classId, draft.studentId, draft.columnId, ordinalValue = draft.value)
                NotebookColumnType.ATTENDANCE -> saveCell(classId, draft.studentId, draft.columnId, textValue = draft.value)
                else -> Unit
            }
        }
    }
    suspend fun saveTab(classId: Long, tab: NotebookTab)
    suspend fun deleteTab(tabId: String)
    suspend fun saveColumn(classId: Long, column: NotebookColumnDefinition)
    suspend fun saveAverageConfiguration(classId: Long, updates: List<NotebookAverageColumnConfig>)
    suspend fun previewDeleteColumn(classId: Long, columnId: String): NotebookDeletionImpact
    suspend fun deleteColumn(columnId: String)
    suspend fun listColumnCategories(classId: Long, tabId: String? = null): List<NotebookColumnCategory>
    suspend fun saveColumnCategory(classId: Long, category: NotebookColumnCategory)
    suspend fun previewDeleteColumnCategory(classId: Long, categoryId: String): NotebookDeletionImpact
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
        evaluationId: Long?,
        numericValue: Double,
        rubricSelections: String? = null,
        evidence: String? = null,
        createdAtEpochMs: Long = 0,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    )
    fun observeCellAudit(classId: Long, studentId: Long, columnId: String): Flow<List<NotebookCellAuditEvent>>
}

interface PhysicalTestsRepository {
    suspend fun listDefinitions(): List<PhysicalTestDefinition>
    suspend fun saveDefinition(definition: PhysicalTestDefinition)

    suspend fun listBatteries(): List<PhysicalTestBattery>
    suspend fun saveBattery(battery: PhysicalTestBattery)

    suspend fun assignBatteryToClass(assignment: PhysicalTestAssignment)
    suspend fun listAssignmentsForClass(classId: Long): List<PhysicalTestAssignment>

    suspend fun listScalesForTest(testId: String): List<PhysicalTestScale>
    suspend fun saveScale(scale: PhysicalTestScale)

    suspend fun resolveScale(
        testId: String,
        course: Int?,
        age: Int?,
        sex: String?,
        batteryId: String?,
    ): PhysicalTestScale?

    suspend fun saveNotebookLink(link: PhysicalTestNotebookLink)
    suspend fun listNotebookLinksForAssignment(assignmentId: String): List<PhysicalTestNotebookLink>

    suspend fun saveResult(result: PhysicalTestResult, attempts: List<PhysicalTestAttempt>)
    suspend fun listResultsForAssignment(assignmentId: String): List<PhysicalTestResult>
    suspend fun listResultsForStudent(studentId: Long, testId: String): List<PhysicalTestResult>
    suspend fun listPhysicalTestHistoryForStudent(studentId: Long): List<PhysicalTestHistoryPoint> = emptyList()
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
    suspend fun deleteFutureSessionsGeneratedFromScheduleSlot(slotId: Long, fromDate: LocalDate): Int = 0
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
    suspend fun previewCascadeMove(request: SessionCascadeMoveRequest): SessionCascadeMovePreview =
        SessionCascadeMovePreview()
    suspend fun commitCascadeMove(request: SessionCascadeMoveRequest): SessionCascadeMoveResult =
        SessionCascadeMoveResult()
    suspend fun restoreCascadeMove(previousPlacements: List<SessionPlacement>): SessionCascadeMoveResult =
        SessionCascadeMoveResult()
    @Throws(Exception::class)
    suspend fun listSessionTemplates(): List<PlannerSessionTemplate> = emptyList()
    @Throws(Exception::class)
    suspend fun saveSessionTemplate(template: PlannerSessionTemplate): Long = 0
    @Throws(Exception::class)
    suspend fun deleteSessionTemplate(templateId: Long): Boolean = false
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
    suspend fun getRubricDetail(rubricId: Long): RubricDetail? = listRubrics().find { it.rubric.id == rubricId }
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

interface StudentSupportMeasureRepository {
    suspend fun listByStudent(studentId: Long): List<StudentSupportMeasure>
    suspend fun listActiveStudentIds(): Set<Long>
    suspend fun save(
        id: Long? = null,
        studentId: Long,
        level: SupportMeasureLevel,
        measureType: SupportMeasureType,
        startDateIso: String,
        endDateIso: String? = null,
        responsible: String? = null,
        intensity: SupportMeasureIntensity? = null,
        followUpNotes: String = "",
        documentRef: String? = null,
        reviewDueIso: String? = null,
        isActive: Boolean = true,
        createdAtEpochMs: Long = 0,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
    suspend fun retire(id: Long, endDateIso: String, updatedAtEpochMs: Long = 0, deviceId: String? = null)
    suspend fun delete(id: Long)
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
    suspend fun deleteIncident(id: Long)
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

interface LearningSituationsRepository {
    fun observeSituations(): Flow<List<LearningSituation>>
    suspend fun listSituations(): List<LearningSituation>
    suspend fun getSituation(id: Long): LearningSituation?
    suspend fun saveSituation(situation: LearningSituation): Long
    suspend fun saveVersion(version: LearningSituationVersion): Long
    suspend fun listVersions(learningSituationId: Long): List<LearningSituationVersion>
    suspend fun saveSessionSequenceVersion(version: LearningSituationSessionSequenceVersion): Long
    suspend fun listSessionSequenceVersions(learningSituationId: Long): List<LearningSituationSessionSequenceVersion>
    suspend fun saveSessionPlan(plan: LearningSituationSessionPlan): Long
    suspend fun listSessionPlans(sequenceVersionId: Long): List<LearningSituationSessionPlan>
    suspend fun getSessionPlan(id: Long): LearningSituationSessionPlan?
    suspend fun replaceClassLinks(learningSituationId: Long, classIds: List<Long>)
    suspend fun listClassLinks(learningSituationId: Long): List<LearningSituationClassLink>
    suspend fun saveLinkedResource(resource: LearningSituationLinkedResource): Long
    suspend fun listLinkedResources(learningSituationId: Long): List<LearningSituationLinkedResource>
    suspend fun deleteSituation(id: Long)
}


interface DashboardRepository {
    fun observeStats(): Flow<DashboardStats>
    suspend fun getStats(): DashboardStats
    suspend fun getTodaySnapshot(dayStartEpochMs: Long, dayEndEpochMs: Long): DashboardTodaySnapshot =
        DashboardTodaySnapshot()
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
    suspend fun deleteScheduleSlotAndGeneratedPlannerSessions(slotId: Long)
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

interface AITrendsRepository {
    suspend fun getStudentGradesHistory(classId: Long, studentId: Long): List<StudentGradeHistoryPoint>
    suspend fun getStudentAttendanceStats(classId: Long, studentId: Long): StudentAttendanceStats
    suspend fun getStudentIncidentsHistory(classId: Long, studentId: Long): List<StudentIncidentPoint>
    suspend fun getCompetencyCoverage(classId: Long): List<CompetencyCoveragePoint>
}

data class StudentGradeHistoryPoint(
    val columnId: String,
    val columnTitle: String,
    val dateEpochMs: Long?,
    val score: Double
)

data class StudentAttendanceStats(
    val absentCount: Long,
    val lateCount: Long,
    val totalRecords: Long
)

data class StudentIncidentPoint(
    val id: Long,
    val title: String,
    val detail: String?,
    val severity: String,
    val dateEpochMs: Long
)

data class CompetencyCoveragePoint(
    val id: Long,
    val code: String,
    val name: String,
    val columnsCount: Long
)

data class PhysicalTestHistoryPoint(
    val resultId: String,
    val testId: String,
    val testName: String,
    val classId: Long,
    val rawValue: Double?,
    val rawText: String,
    val score: Double?,
    val observedAtEpochMs: Long,
)
