package com.migestor.shared.repository

import com.migestor.shared.domain.*
import kotlinx.datetime.LocalDate
import kotlinx.coroutines.flow.Flow

interface StudentsRepository {
    fun observeStudents(): Flow<List<Student>>
    @Throws(Throwable::class)
    suspend fun listStudents(): List<Student>
    @Throws(Throwable::class)
    suspend fun getStudent(studentId: Long): Student? = listStudents().find { it.id == studentId }
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun deleteStudent(studentId: Long)
}

interface ClassesRepository {
    fun observeClasses(): Flow<List<SchoolClass>>
    fun observeStudentsInClass(classId: Long): Flow<List<Student>>
    @Throws(Throwable::class)
    suspend fun listClasses(): List<SchoolClass>
    @Throws(Throwable::class)
    suspend fun latestEnrollmentUpdatedAt(classId: Long, studentId: Long): Long? = null
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun listAllClasses(): List<SchoolClass> = listClasses()
    @Throws(Throwable::class)
    suspend fun listClassesForAcademicYear(academicYearId: Long): List<SchoolClass> =
        listAllClasses().filter { it.academicYearId == academicYearId }
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun deleteClass(classId: Long)
    @Throws(Throwable::class)
    suspend fun addStudentToClass(classId: Long, studentId: Long)
    @Throws(Throwable::class)
    suspend fun promoteStudentToClass(
        sourceClassId: Long,
        targetClassId: Long,
        studentId: Long,
        promotionStatus: String = "PROMOTED",
    ) = addStudentToClass(targetClassId, studentId)
    @Throws(Throwable::class)
    suspend fun removeStudentFromClass(classId: Long, studentId: Long)
    @Throws(Throwable::class)
    suspend fun listStudentsInClass(classId: Long): List<Student>
}

interface AcademicYearsRepository {
    fun observeAcademicYears(): Flow<List<AcademicYear>>
    @Throws(Throwable::class)
    suspend fun listAcademicYears(): List<AcademicYear>
    @Throws(Throwable::class)
    suspend fun getActiveAcademicYear(): AcademicYear?
    @Throws(Throwable::class)
    suspend fun createAcademicYear(
        name: String,
        startEpochMs: Long,
        endEpochMs: Long,
        centerId: Long? = null,
        makeActive: Boolean = true,
    ): Long
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun setActiveAcademicYear(academicYearId: Long)
    @Throws(Throwable::class)
    suspend fun archiveAcademicYear(academicYearId: Long)
    @Throws(Throwable::class)
    suspend fun trashAcademicYear(academicYearId: Long) = archiveAcademicYear(academicYearId)
    @Throws(Throwable::class)
    suspend fun deleteArchivedAcademicYear(academicYearId: Long)
    @Throws(Throwable::class)
    suspend fun enrollmentCount(academicYearId: Long): Long = 0
}

interface SubjectsRepository {
    fun observeSubjects(): Flow<List<Subject>>
    @Throws(Throwable::class)
    suspend fun listSubjects(): List<Subject>
    @Throws(Throwable::class)
    suspend fun saveSubject(
        id: Long? = null,
        code: String,
        name: String,
        stageCycleId: Long? = null,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
    @Throws(Throwable::class)
    suspend fun deleteSubject(subjectId: Long)
}

interface EvaluationsRepository {
    fun observeClassEvaluations(classId: Long): Flow<List<Evaluation>>
    @Throws(Throwable::class)
    suspend fun listClassEvaluations(classId: Long): List<Evaluation>
    @Throws(Throwable::class)
    suspend fun getPendingEvaluationsSummary(classId: Long): PendingEvaluationsSummary =
        PendingEvaluationsSummary(classId = classId)
    @Throws(Throwable::class)
    suspend fun getEvaluation(evaluationId: Long): Evaluation?
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun deleteEvaluation(evaluationId: Long)
    @Throws(Throwable::class)
    suspend fun saveEvaluationCompetencyLink(
        id: Long? = null,
        evaluationId: Long,
        competencyId: Long,
        weight: Double = 1.0,
        authorUserId: Long? = null,
    ): Long
    @Throws(Throwable::class)
    suspend fun listEvaluationCompetencyLinks(evaluationId: Long): List<EvaluationCompetencyLink>
}

interface GradesRepository {
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun listGradesForClass(classId: Long): List<Grade>
    @Throws(Throwable::class)
    suspend fun listGradesForStudentInClass(studentId: Long, classId: Long): List<Grade>
    fun observeGradesForClass(classId: Long): Flow<List<Grade>>
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun listClassCells(classId: Long): List<PersistedNotebookCell>
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun saveTemplate(
        template: NotebookInstrumentTemplate,
        items: List<NotebookInstrumentItem>,
    )

    @Throws(Throwable::class)
    suspend fun getTemplateForColumn(columnId: String): NotebookInstrumentDetail?

    @Throws(Throwable::class)
    suspend fun listResponsesForCell(
        classId: Long,
        studentId: Long,
        columnId: String,
    ): List<NotebookInstrumentResponse>

    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun loadNotebookSnapshot(classId: Long): NotebookSheet
    @Throws(Throwable::class)
    suspend fun loadNotebookSummary(classId: Long): NotebookSummary = NotebookSummary(classId = classId)
    @Throws(Throwable::class)
    suspend fun listNotebookVisibleColumns(classId: Long, tabId: String? = null): List<NotebookVisibleColumnSummary> =
        emptyList()
    @Throws(Throwable::class)
    suspend fun listNotebookRowsPage(classId: Long, limit: Long, offset: Long): List<NotebookRowPageItem> =
        emptyList()
    fun observeStudentChanges(classId: Long): Flow<List<Student>>
    fun observeGradesForClass(classId: Long): Flow<List<Grade>>
    @Throws(Throwable::class)
    suspend fun addStudent(
        classId: Long, firstName: String, lastName: String, isInjured: Boolean): Student
    @Throws(Throwable::class)
    suspend fun removeStudent(classId: Long, studentId: Long)
    @Throws(Throwable::class)
    suspend fun listStudentsInClass(classId: Long): List<Student>
    @Throws(Throwable::class)
    suspend fun saveGrade(classId: Long, studentId: Long, columnId: String, evaluationId: Long?, value: Double?): Long
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun saveTab(classId: Long, tab: NotebookTab)
    @Throws(Throwable::class)
    suspend fun deleteTab(tabId: String)
    @Throws(Throwable::class)
    suspend fun saveColumn(classId: Long, column: NotebookColumnDefinition)
    @Throws(Throwable::class)
    suspend fun saveAverageConfiguration(classId: Long, updates: List<NotebookAverageColumnConfig>)
    @Throws(Throwable::class)
    suspend fun previewDeleteColumn(classId: Long, columnId: String): NotebookDeletionImpact
    @Throws(Throwable::class)
    suspend fun deleteColumn(columnId: String)
    @Throws(Throwable::class)
    suspend fun listColumnCategories(classId: Long, tabId: String? = null): List<NotebookColumnCategory>
    @Throws(Throwable::class)
    suspend fun saveColumnCategory(classId: Long, category: NotebookColumnCategory)
    @Throws(Throwable::class)
    suspend fun previewDeleteColumnCategory(classId: Long, categoryId: String): NotebookDeletionImpact
    @Throws(Throwable::class)
    suspend fun deleteColumnCategory(classId: Long, categoryId: String, preserveColumns: Boolean = true)
    @Throws(Throwable::class)
    suspend fun toggleCategoryCollapsed(classId: Long, categoryId: String, isCollapsed: Boolean)
    @Throws(Throwable::class)
    suspend fun reorderCategory(classId: Long, tabId: String, categoryId: String, targetCategoryId: String)
    @Throws(Throwable::class)
    suspend fun assignColumnToCategory(classId: Long, columnId: String, categoryId: String?)
    @Throws(Throwable::class)
    suspend fun deleteEvaluation(evaluationId: Long)
    @Throws(Throwable::class)
    suspend fun duplicateConfigToClass(sourceClassId: Long, targetClassId: Long)
    @Throws(Throwable::class)
    suspend fun listWorkGroups(classId: Long, tabId: String? = null): List<NotebookWorkGroup>
    @Throws(Throwable::class)
    suspend fun saveWorkGroup(classId: Long, workGroup: NotebookWorkGroup): Long
    @Throws(Throwable::class)
    suspend fun deleteWorkGroup(groupId: Long)
    @Throws(Throwable::class)
    suspend fun listWorkGroupMembers(classId: Long, tabId: String? = null): List<NotebookWorkGroupMember>
    @Throws(Throwable::class)
    suspend fun assignStudentsToWorkGroup(
        classId: Long,
        tabId: String,
        groupId: Long,
        studentIds: List<Long>,
    )
    @Throws(Throwable::class)
    suspend fun clearStudentsFromWorkGroup(
        classId: Long,
        tabId: String,
        studentIds: List<Long>,
    )
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun getTabNamesForClass(classId: Long): List<String>
    @Throws(Throwable::class)
    suspend fun createTab(classId: Long, tabName: String): String
    @Throws(Throwable::class)
    suspend fun addColumnToTab(classId: Long, tabName: String, columnName: String, columnType: NotebookColumnType, rubricId: Long? = null): String

    @Throws(Throwable::class)
    suspend fun getNotebookConfig(classId: Long): NotebookConfig
    @Throws(Throwable::class)
    suspend fun getGradeForColumn(studentId: Long, columnId: String): Grade?
    @Throws(Throwable::class)
    suspend fun getColumnIdForEvaluation(evaluationId: Long): String?
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun listDefinitions(): List<PhysicalTestDefinition>
    @Throws(Throwable::class)
    suspend fun saveDefinition(definition: PhysicalTestDefinition)

    @Throws(Throwable::class)
    suspend fun listBatteries(): List<PhysicalTestBattery>
    @Throws(Throwable::class)
    suspend fun saveBattery(battery: PhysicalTestBattery)

    @Throws(Throwable::class)
    suspend fun assignBatteryToClass(assignment: PhysicalTestAssignment)
    @Throws(Throwable::class)
    suspend fun listAssignmentsForClass(classId: Long): List<PhysicalTestAssignment>

    @Throws(Throwable::class)
    suspend fun listScalesForTest(testId: String): List<PhysicalTestScale>
    @Throws(Throwable::class)
    suspend fun saveScale(scale: PhysicalTestScale)

    @Throws(Throwable::class)
    suspend fun resolveScale(
        testId: String,
        course: Int?,
        age: Int?,
        sex: String?,
        batteryId: String?,
    ): PhysicalTestScale?

    @Throws(Throwable::class)
    suspend fun saveNotebookLink(link: PhysicalTestNotebookLink)
    @Throws(Throwable::class)
    suspend fun listNotebookLinksForAssignment(assignmentId: String): List<PhysicalTestNotebookLink>

    @Throws(Throwable::class)
    suspend fun saveResult(result: PhysicalTestResult, attempts: List<PhysicalTestAttempt>)
    @Throws(Throwable::class)
    suspend fun listResultsForAssignment(assignmentId: String): List<PhysicalTestResult>
    @Throws(Throwable::class)
    suspend fun listResultsForStudent(studentId: Long, testId: String): List<PhysicalTestResult>
    @Throws(Throwable::class)
    suspend fun listPhysicalTestHistoryForStudent(studentId: Long): List<PhysicalTestHistoryPoint> = emptyList()
}

interface PlannerRepository {
    fun observeSessions(weekNumber: Int, year: Int): Flow<List<PlanningSession>>
    @Throws(Throwable::class)
    suspend fun listSessions(weekNumber: Int, year: Int): List<PlanningSession>
    @Throws(Throwable::class)
    suspend fun listAllSessions(): List<PlanningSession> = emptyList()
    @Throws(Throwable::class)
    suspend fun listSessionsInRange(groupId: Long? = null, fromDate: LocalDate, toDate: LocalDate): List<PlanningSession> = emptyList()
    @Throws(Throwable::class)
    suspend fun upsertSession(session: PlanningSession): Long
    @Throws(Throwable::class)
    suspend fun bulkUpsertSessions(sessions: List<PlanningSession>): List<Long> = sessions.map { upsertSession(it) }
    @Throws(Throwable::class)
    suspend fun deleteSession(sessionId: Long)
    @Throws(Throwable::class)
    suspend fun deleteSessions(sessionIds: List<Long>) {
        sessionIds.forEach { deleteSession(it) }
    }
    @Throws(Throwable::class)
    suspend fun deleteFutureSessionsGeneratedFromScheduleSlot(slotId: Long, fromDate: LocalDate): Int = 0
    fun observeTeachingUnits(groupId: Long? = null): Flow<List<TeachingUnit>>
    @Throws(Throwable::class)
    suspend fun listAllTeachingUnits(): List<TeachingUnit> = emptyList()
    @Throws(Throwable::class)
    suspend fun upsertTeachingUnit(unit: TeachingUnit): Long
    @Throws(Throwable::class)
    suspend fun deleteTeachingUnit(unitId: Long): Boolean
    fun getTimeSlots(): List<TimeSlotConfig>
    @Throws(Throwable::class)
    suspend fun moveSessionsFromWeek(fromWeek: Int, fromYear: Int, offsetWeeks: Int)
    @Throws(Throwable::class)
    suspend fun previewSessionRelocation(request: SessionRelocationRequest): List<SessionRelocationConflict> = emptyList()
    @Throws(Throwable::class)
    suspend fun copySessions(
        request: SessionRelocationRequest,
        resolution: CollisionResolution
    ): SessionBulkResult = SessionBulkResult()
    @Throws(Throwable::class)
    suspend fun shiftSelectedSessions(
        request: SessionRelocationRequest,
        resolution: CollisionResolution
    ): SessionBulkResult = SessionBulkResult()
    @Throws(Throwable::class)
    suspend fun previewCascadeMove(request: SessionCascadeMoveRequest): SessionCascadeMovePreview =
        SessionCascadeMovePreview()
    @Throws(Throwable::class)
    suspend fun commitCascadeMove(request: SessionCascadeMoveRequest): SessionCascadeMoveResult =
        SessionCascadeMoveResult()
    @Throws(Throwable::class)
    suspend fun restoreCascadeMove(previousPlacements: List<SessionPlacement>): SessionCascadeMoveResult =
        SessionCascadeMoveResult()
    @Throws(Throwable::class)
    suspend fun listSessionTemplates(): List<PlannerSessionTemplate> = emptyList()
    @Throws(Throwable::class)
    suspend fun saveSessionTemplate(template: PlannerSessionTemplate): Long = 0
    @Throws(Throwable::class)
    suspend fun deleteSessionTemplate(templateId: Long): Boolean = false
}

interface SessionJournalRepository {
    @Throws(Throwable::class)
    suspend fun getOrCreateJournal(session: PlanningSession): SessionJournalAggregate
    @Throws(Throwable::class)
    suspend fun getJournalForSession(planningSessionId: Long): SessionJournalAggregate?
    @Throws(Throwable::class)
    suspend fun listSummariesForSessions(planningSessionIds: List<Long>): List<SessionJournalSummary>
    @Throws(Throwable::class)
    suspend fun saveJournalAggregate(aggregate: SessionJournalAggregate): Long
    @Throws(Throwable::class)
    suspend fun deleteJournalForSession(planningSessionId: Long)
}

data class ConflictPreview(
    val session: PlanningSession,
    val newDate: LocalDate,
    val isConflict: Boolean
)

interface RubricsRepository {
    fun observeRubrics(): Flow<List<RubricDetail>>
    @Throws(Throwable::class)
    suspend fun listRubrics(): List<RubricDetail>
    @Throws(Throwable::class)
    suspend fun getRubricDetail(rubricId: Long): RubricDetail? = listRubrics().find { it.rubric.id == rubricId }
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun deleteRubric(rubricId: Long)
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun deleteCriterion(criterionId: Long)
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun deleteLevel(levelId: Long)
    @Throws(Throwable::class)
    suspend fun saveRubricAssessment(
        studentId: Long,
        evaluationId: Long,
        criterionId: Long,
        levelId: Long,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Double?
    @Throws(Throwable::class)
    suspend fun listRubricAssessments(studentId: Long, evaluationId: Long): List<RubricAssessment>
    @Throws(Throwable::class)
    suspend fun getStudentEvaluation(studentId: Long, rubricId: Long, evaluationId: Long): Map<Long, Long>
    @Throws(Throwable::class)
    suspend fun listCriteriaByRubric(rubricId: Long): List<RubricCriterion>
    @Throws(Throwable::class)
    suspend fun listLevelsByCriterion(criterionId: Long): List<RubricLevel>
}

interface AttendanceRepository {
    fun observeAttendance(classId: Long): Flow<List<Attendance>>
    fun observeAttendanceByDate(classId: Long, dateEpochMs: Long): Flow<List<Attendance>>
    @Throws(Throwable::class)
    suspend fun listAttendance(classId: Long): List<Attendance>
    @Throws(Throwable::class)
    suspend fun listAttendanceByDate(classId: Long, dateEpochMs: Long): List<Attendance>
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun getAttendanceForClassBetweenDates(classId: Long, startDateMs: Long, endDateMs: Long): List<Attendance>
}

interface StudentSupportMeasureRepository {
    @Throws(Throwable::class)
    suspend fun listByStudent(studentId: Long): List<StudentSupportMeasure>
    @Throws(Throwable::class)
    suspend fun listActiveStudentIds(): Set<Long>
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun retire(id: Long, endDateIso: String, updatedAtEpochMs: Long = 0, deviceId: String? = null)
    @Throws(Throwable::class)
    suspend fun delete(id: Long)
}

interface StudentTutoringSessionRepository {
    @Throws(Throwable::class)
    suspend fun listByStudent(studentId: Long): List<StudentTutoringSession>
    /** Seguimientos abiertos cuya revision vence en o antes de `onOrBeforeIso`. */
    @Throws(Throwable::class)
    suspend fun listPendingReviews(onOrBeforeIso: String): List<StudentTutoringSession>
    @Throws(Throwable::class)
    suspend fun save(
        id: Long? = null,
        studentId: Long,
        dateIso: String,
        channel: TutoringChannel = TutoringChannel.IN_PERSON,
        attendees: String = "",
        topics: String = "",
        agreements: String = "",
        reviewDueIso: String? = null,
        isClosed: Boolean = false,
        createdAtEpochMs: Long = 0,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
    @Throws(Throwable::class)
    suspend fun delete(id: Long)
}

interface MeetingRepository {
    /** Todas las reuniones, de la mas reciente a la mas antigua, con sus acuerdos ya cargados. */
    @Throws(Throwable::class)
    suspend fun listAll(): List<Meeting>
    @Throws(Throwable::class)
    suspend fun getById(id: Long): Meeting?
    /** Acuerdos sin cerrar cuya fecha limite vence en o antes de `onOrBeforeIso`. */
    @Throws(Throwable::class)
    suspend fun listPendingAgreements(onOrBeforeIso: String): List<MeetingAgreement>
    @Throws(Throwable::class)
    suspend fun saveMeeting(
        id: Long? = null,
        title: String,
        dateIso: String,
        type: MeetingType = MeetingType.OTRA,
        location: String = "",
        attendees: String = "",
        summary: String = "",
        isClosed: Boolean = false,
        createdAtEpochMs: Long = 0,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
    /** Borra la reunion; sus acuerdos caen por la cascada del esquema. */
    @Throws(Throwable::class)
    suspend fun deleteMeeting(id: Long)
    @Throws(Throwable::class)
    suspend fun saveAgreement(
        id: Long? = null,
        meetingId: Long,
        description: String,
        responsible: String = "",
        dueIso: String? = null,
        isDone: Boolean = false,
        createdAtEpochMs: Long = 0,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
    @Throws(Throwable::class)
    suspend fun deleteAgreement(id: Long)
}

interface PlannerWeekPlanRepository {
    /** El plan de un grupo en una semana ISO concreta, o `null` si aun no existe. */
    @Throws(Throwable::class)
    suspend fun getPlan(classId: Long, year: Int, week: Int): PlannerWeekPlan?
    @Throws(Throwable::class)
    suspend fun save(
        id: Long? = null,
        classId: Long,
        year: Int,
        week: Int,
        strategies: List<String> = emptyList(),
        instruments: List<String> = emptyList(),
        notes: String = "",
        createdAtEpochMs: Long = 0,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
    @Throws(Throwable::class)
    suspend fun delete(id: Long)
}

interface CompetenciesRepository {
    fun observeCompetencies(): Flow<List<CompetencyCriterion>>
    @Throws(Throwable::class)
    suspend fun listCompetencies(): List<CompetencyCriterion>
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun listIncidents(classId: Long): List<Incident>
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun deleteIncident(id: Long)
}

interface CalendarRepository {
    fun observeEvents(classId: Long? = null): Flow<List<CalendarEvent>>
    @Throws(Throwable::class)
    suspend fun listEvents(classId: Long? = null): List<CalendarEvent>
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun listTemplates(kind: ConfigTemplateKind? = null): List<ConfigTemplate>
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun listTemplateVersions(templateId: Long): List<ConfigTemplateVersion>
    @Throws(Throwable::class)
    suspend fun cloneLatestVersionToTemplate(
        sourceTemplateId: Long,
        targetTemplateId: Long,
        sourceAcademicYearId: Long? = null,
        authorUserId: Long? = null,
    ): Long
}

interface LearningSituationsRepository {
    fun observeSituations(): Flow<List<LearningSituation>>
    @Throws(Throwable::class)
    suspend fun listSituations(): List<LearningSituation>
    @Throws(Throwable::class)
    suspend fun getSituation(id: Long): LearningSituation?
    @Throws(Throwable::class)
    suspend fun saveSituation(situation: LearningSituation): Long
    @Throws(Throwable::class)
    suspend fun saveVersion(version: LearningSituationVersion): Long
    @Throws(Throwable::class)
    suspend fun listVersions(learningSituationId: Long): List<LearningSituationVersion>
    @Throws(Throwable::class)
    suspend fun saveSessionSequenceVersion(version: LearningSituationSessionSequenceVersion): Long
    @Throws(Throwable::class)
    suspend fun listSessionSequenceVersions(learningSituationId: Long): List<LearningSituationSessionSequenceVersion>
    @Throws(Throwable::class)
    suspend fun saveSessionPlan(plan: LearningSituationSessionPlan): Long
    @Throws(Throwable::class)
    suspend fun listSessionPlans(sequenceVersionId: Long): List<LearningSituationSessionPlan>
    @Throws(Throwable::class)
    suspend fun getSessionPlan(id: Long): LearningSituationSessionPlan?
    @Throws(Throwable::class)
    suspend fun replaceClassLinks(learningSituationId: Long, classIds: List<Long>)
    @Throws(Throwable::class)
    suspend fun listClassLinks(learningSituationId: Long): List<LearningSituationClassLink>
    @Throws(Throwable::class)
    suspend fun saveLinkedResource(resource: LearningSituationLinkedResource): Long
    @Throws(Throwable::class)
    suspend fun listLinkedResources(learningSituationId: Long): List<LearningSituationLinkedResource>
    @Throws(Throwable::class)
    suspend fun deleteSituation(id: Long)
}


interface DashboardRepository {
    fun observeStats(): Flow<DashboardStats>
    @Throws(Throwable::class)
    suspend fun getStats(): DashboardStats
    @Throws(Throwable::class)
    suspend fun getTodaySnapshot(dayStartEpochMs: Long, dayEndEpochMs: Long): DashboardTodaySnapshot =
        DashboardTodaySnapshot()
}

interface DashboardOperationalRepository {
    @Throws(Throwable::class)
    suspend fun getSnapshot(
        date: LocalDate,
        mode: DashboardMode,
        filters: DashboardFilters = DashboardFilters(),
    ): DashboardSnapshot

    @Throws(Throwable::class)
    suspend fun executeQuickAction(command: QuickActionCommand): QuickActionResult
}

interface BackupMetadataRepository {
    fun observeBackups(): Flow<List<BackupEntry>>
    @Throws(Throwable::class)
    suspend fun listBackups(): List<BackupEntry>
    @Throws(Throwable::class)
    suspend fun saveBackup(path: String, createdAtEpochMs: Long, platform: String, sizeBytes: Long): Long
    @Throws(Throwable::class)
    suspend fun deleteBackup(id: Long)
}

interface AIAuditRepository {
    @Throws(Throwable::class)
    suspend fun recordEvent(event: AIAuditEvent)
    @Throws(Throwable::class)
    suspend fun recentEvents(limit: Long = 50): List<AIAuditEvent>
    @Throws(Throwable::class)
    suspend fun recentFailures(limit: Long = 20): List<AIAuditEvent>
    @Throws(Throwable::class)
    suspend fun latestEvent(): AIAuditEvent?
    @Throws(Throwable::class)
    suspend fun totalsByUseCase(): List<AIAuditUseCaseTotal>
    @Throws(Throwable::class)
    suspend fun recentAvailabilityTotals(): List<AIAuditAvailabilityTotal>
}

interface CsvImportService {
    @Throws(Throwable::class)
    suspend fun parseStudents(csv: String): List<StudentCsvRow>
}

interface XlsxImportService {
    @Throws(Throwable::class)
    suspend fun parseStudents(bytes: ByteArray): List<StudentCsvRow>
    @Throws(Throwable::class)
    suspend fun parseRubric(bytes: ByteArray, fallbackTitle: String = "Rúbrica importada"): ImportedRubric
}

interface ReportService {
    @Throws(Throwable::class)
    suspend fun exportNotebookReport(request: NotebookReportRequest): ByteArray
}

interface BackupService {
    @Throws(Throwable::class)
    suspend fun createBackup(fileName: String = "mi_gestor_backup.sqlite"): BackupResult
    @Throws(Throwable::class)
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
    @Throws(Throwable::class)
    suspend fun insert(slot: WeeklySlotTemplate): Long
    @Throws(Throwable::class)
    suspend fun delete(slotId: Long)
}

interface TeacherScheduleRepository {
    @Throws(Throwable::class)
    suspend fun getOrCreatePrimarySchedule(): TeacherSchedule
    @Throws(Throwable::class)
    suspend fun saveSchedule(schedule: TeacherSchedule): Long
    @Throws(Throwable::class)
    suspend fun listScheduleSlots(scheduleId: Long): List<TeacherScheduleSlot>
    @Throws(Throwable::class)
    suspend fun getScheduleSlot(slotId: Long): TeacherScheduleSlot?
    @Throws(Throwable::class)
    suspend fun saveScheduleSlot(slot: TeacherScheduleSlot): Long
    @Throws(Throwable::class)
    suspend fun deleteScheduleSlot(slotId: Long)
    @Throws(Throwable::class)
    suspend fun deleteScheduleSlotAndGeneratedPlannerSessions(slotId: Long)
    @Throws(Throwable::class)
    suspend fun listEvaluationPeriods(scheduleId: Long): List<PlannerEvaluationPeriod>
    @Throws(Throwable::class)
    suspend fun saveEvaluationPeriod(period: PlannerEvaluationPeriod): Long
    @Throws(Throwable::class)
    suspend fun deleteEvaluationPeriod(periodId: Long)
    @Throws(Throwable::class)
    suspend fun buildForecasts(scheduleId: Long, classId: Long? = null): List<PlannerSessionForecast>
}

interface PlannedSessionRepository {
    @Throws(Throwable::class)
    suspend fun getSessionsForClass(schoolClassId: Long, startDate: LocalDate, endDate: LocalDate): List<PlannedSession>
    fun observeSessionsForClass(schoolClassId: Long, startDate: LocalDate, endDate: LocalDate): Flow<List<PlannedSession>>
    fun observeAllSessions(startDate: LocalDate, endDate: LocalDate): Flow<List<PlannedSession>>
    @Throws(Throwable::class)
    suspend fun getAllSessions(startDate: LocalDate, endDate: LocalDate): List<PlannedSession>
    @Throws(Throwable::class)
    suspend fun existsAt(schoolClassId: Long, date: LocalDate, startTime: String): Boolean
    @Throws(Throwable::class)
    suspend fun insert(session: PlannedSession): Long
    @Throws(Throwable::class)
    suspend fun update(session: PlannedSession)
    @Throws(Throwable::class)
    suspend fun delete(sessionId: Long)
    @Throws(Throwable::class)
    suspend fun listSessionsInRange(schoolClassId: Long? = null, startDate: LocalDate, endDate: LocalDate): List<PlannedSession> =
        if (schoolClassId != null) getSessionsForClass(schoolClassId, startDate, endDate) else getAllSessions(startDate, endDate)
    @Throws(Throwable::class)
    suspend fun deleteSessions(sessionIds: List<Long>) {
        sessionIds.forEach { delete(it) }
    }
    @Throws(Throwable::class)
    suspend fun bulkUpsertOrReplacePlannedSessions(sessions: List<PlannedSession>): List<Long> = sessions.map { insert(it) }
}

interface AITrendsRepository {
    @Throws(Throwable::class)
    suspend fun getStudentGradesHistory(classId: Long, studentId: Long): List<StudentGradeHistoryPoint>
    @Throws(Throwable::class)
    suspend fun getStudentAttendanceStats(classId: Long, studentId: Long): StudentAttendanceStats
    @Throws(Throwable::class)
    suspend fun getStudentIncidentsHistory(classId: Long, studentId: Long): List<StudentIncidentPoint>
    @Throws(Throwable::class)
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
