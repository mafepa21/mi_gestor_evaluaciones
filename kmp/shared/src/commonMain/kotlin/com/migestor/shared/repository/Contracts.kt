package com.migestor.shared.repository

import com.migestor.shared.domain.*
import kotlinx.datetime.LocalDate
import kotlinx.coroutines.flow.Flow

interface StudentsRepository {
    fun observeStudents(): Flow<List<Student>>
    @Throws(Exception::class)
    suspend fun listStudents(): List<Student>
    @Throws(Exception::class)
    suspend fun getStudent(studentId: Long): Student? = listStudents().find { it.id == studentId }
    @Throws(Exception::class)
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
    @Throws(Exception::class)
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
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun deleteStudent(studentId: Long)
}

interface ClassesRepository {
    fun observeClasses(): Flow<List<SchoolClass>>
    fun observeStudentsInClass(classId: Long): Flow<List<Student>>
    @Throws(Exception::class)
    suspend fun listClasses(): List<SchoolClass>
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun listAllClasses(): List<SchoolClass> = listClasses()
    @Throws(Exception::class)
    suspend fun listClassesForAcademicYear(academicYearId: Long): List<SchoolClass> =
        listAllClasses().filter { it.academicYearId == academicYearId }
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun deleteClass(classId: Long)
    @Throws(Exception::class)
    suspend fun addStudentToClass(classId: Long, studentId: Long)
    @Throws(Exception::class)
    suspend fun promoteStudentToClass(
        sourceClassId: Long,
        targetClassId: Long,
        studentId: Long,
        promotionStatus: String = "PROMOTED",
    ) = addStudentToClass(targetClassId, studentId)
    @Throws(Exception::class)
    suspend fun removeStudentFromClass(classId: Long, studentId: Long)
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun listSubjects(): List<Subject>
    @Throws(Exception::class)
    suspend fun saveSubject(
        id: Long? = null,
        code: String,
        name: String,
        stageCycleId: Long? = null,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Long
    @Throws(Exception::class)
    suspend fun deleteSubject(subjectId: Long)
}

interface EvaluationsRepository {
    fun observeClassEvaluations(classId: Long): Flow<List<Evaluation>>
    @Throws(Exception::class)
    suspend fun listClassEvaluations(classId: Long): List<Evaluation>
    @Throws(Exception::class)
    suspend fun getPendingEvaluationsSummary(classId: Long): PendingEvaluationsSummary =
        PendingEvaluationsSummary(classId = classId)
    @Throws(Exception::class)
    suspend fun getEvaluation(evaluationId: Long): Evaluation?
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun deleteEvaluation(evaluationId: Long)
    @Throws(Exception::class)
    suspend fun saveEvaluationCompetencyLink(
        id: Long? = null,
        evaluationId: Long,
        competencyId: Long,
        weight: Double = 1.0,
        authorUserId: Long? = null,
    ): Long
    @Throws(Exception::class)
    suspend fun listEvaluationCompetencyLinks(evaluationId: Long): List<EvaluationCompetencyLink>
}

interface GradesRepository {
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun listGradesForClass(classId: Long): List<Grade>
    @Throws(Exception::class)
    suspend fun listGradesForStudentInClass(studentId: Long, classId: Long): List<Grade>
    fun observeGradesForClass(classId: Long): Flow<List<Grade>>
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun listClassCells(classId: Long): List<PersistedNotebookCell>
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun saveTemplate(
        template: NotebookInstrumentTemplate,
        items: List<NotebookInstrumentItem>,
    )

    @Throws(Exception::class)
    suspend fun getTemplateForColumn(columnId: String): NotebookInstrumentDetail?

    @Throws(Exception::class)
    suspend fun listResponsesForCell(
        classId: Long,
        studentId: Long,
        columnId: String,
    ): List<NotebookInstrumentResponse>

    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun loadNotebookSnapshot(classId: Long): NotebookSheet
    @Throws(Exception::class)
    suspend fun loadNotebookSummary(classId: Long): NotebookSummary = NotebookSummary(classId = classId)
    @Throws(Exception::class)
    suspend fun listNotebookVisibleColumns(classId: Long, tabId: String? = null): List<NotebookVisibleColumnSummary> =
        emptyList()
    @Throws(Exception::class)
    suspend fun listNotebookRowsPage(classId: Long, limit: Long, offset: Long): List<NotebookRowPageItem> =
        emptyList()
    fun observeStudentChanges(classId: Long): Flow<List<Student>>
    fun observeGradesForClass(classId: Long): Flow<List<Grade>>
    @Throws(Exception::class)
    suspend fun addStudent(
        classId: Long, firstName: String, lastName: String, isInjured: Boolean): Student
    @Throws(Exception::class)
    suspend fun removeStudent(classId: Long, studentId: Long)
    @Throws(Exception::class)
    suspend fun listStudentsInClass(classId: Long): List<Student>
    @Throws(Exception::class)
    suspend fun saveGrade(classId: Long, studentId: Long, columnId: String, evaluationId: Long?, value: Double?): Long
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun saveTab(classId: Long, tab: NotebookTab)
    @Throws(Exception::class)
    suspend fun deleteTab(tabId: String)
    @Throws(Exception::class)
    suspend fun saveColumn(classId: Long, column: NotebookColumnDefinition)
    @Throws(Exception::class)
    suspend fun saveAverageConfiguration(classId: Long, updates: List<NotebookAverageColumnConfig>)
    @Throws(Exception::class)
    suspend fun previewDeleteColumn(classId: Long, columnId: String): NotebookDeletionImpact
    @Throws(Exception::class)
    suspend fun deleteColumn(columnId: String)
    @Throws(Exception::class)
    suspend fun listColumnCategories(classId: Long, tabId: String? = null): List<NotebookColumnCategory>
    @Throws(Exception::class)
    suspend fun saveColumnCategory(classId: Long, category: NotebookColumnCategory)
    @Throws(Exception::class)
    suspend fun previewDeleteColumnCategory(classId: Long, categoryId: String): NotebookDeletionImpact
    @Throws(Exception::class)
    suspend fun deleteColumnCategory(classId: Long, categoryId: String, preserveColumns: Boolean = true)
    @Throws(Exception::class)
    suspend fun toggleCategoryCollapsed(classId: Long, categoryId: String, isCollapsed: Boolean)
    @Throws(Exception::class)
    suspend fun reorderCategory(classId: Long, tabId: String, categoryId: String, targetCategoryId: String)
    @Throws(Exception::class)
    suspend fun assignColumnToCategory(classId: Long, columnId: String, categoryId: String?)
    @Throws(Exception::class)
    suspend fun deleteEvaluation(evaluationId: Long)
    @Throws(Exception::class)
    suspend fun duplicateConfigToClass(sourceClassId: Long, targetClassId: Long)
    @Throws(Exception::class)
    suspend fun listWorkGroups(classId: Long, tabId: String? = null): List<NotebookWorkGroup>
    @Throws(Exception::class)
    suspend fun saveWorkGroup(classId: Long, workGroup: NotebookWorkGroup): Long
    @Throws(Exception::class)
    suspend fun deleteWorkGroup(groupId: Long)
    @Throws(Exception::class)
    suspend fun listWorkGroupMembers(classId: Long, tabId: String? = null): List<NotebookWorkGroupMember>
    @Throws(Exception::class)
    suspend fun assignStudentsToWorkGroup(
        classId: Long,
        tabId: String,
        groupId: Long,
        studentIds: List<Long>,
    )
    @Throws(Exception::class)
    suspend fun clearStudentsFromWorkGroup(
        classId: Long,
        tabId: String,
        studentIds: List<Long>,
    )
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun getTabNamesForClass(classId: Long): List<String>
    @Throws(Exception::class)
    suspend fun createTab(classId: Long, tabName: String): String
    @Throws(Exception::class)
    suspend fun addColumnToTab(classId: Long, tabName: String, columnName: String, columnType: NotebookColumnType, rubricId: Long? = null): String

    @Throws(Exception::class)
    suspend fun getNotebookConfig(classId: Long): NotebookConfig
    @Throws(Exception::class)
    suspend fun getGradeForColumn(studentId: Long, columnId: String): Grade?
    @Throws(Exception::class)
    suspend fun getColumnIdForEvaluation(evaluationId: Long): String?
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun listDefinitions(): List<PhysicalTestDefinition>
    @Throws(Exception::class)
    suspend fun saveDefinition(definition: PhysicalTestDefinition)

    @Throws(Exception::class)
    suspend fun listBatteries(): List<PhysicalTestBattery>
    @Throws(Exception::class)
    suspend fun saveBattery(battery: PhysicalTestBattery)

    @Throws(Exception::class)
    suspend fun assignBatteryToClass(assignment: PhysicalTestAssignment)
    @Throws(Exception::class)
    suspend fun listAssignmentsForClass(classId: Long): List<PhysicalTestAssignment>

    @Throws(Exception::class)
    suspend fun listScalesForTest(testId: String): List<PhysicalTestScale>
    @Throws(Exception::class)
    suspend fun saveScale(scale: PhysicalTestScale)

    @Throws(Exception::class)
    suspend fun resolveScale(
        testId: String,
        course: Int?,
        age: Int?,
        sex: String?,
        batteryId: String?,
    ): PhysicalTestScale?

    @Throws(Exception::class)
    suspend fun saveNotebookLink(link: PhysicalTestNotebookLink)
    @Throws(Exception::class)
    suspend fun listNotebookLinksForAssignment(assignmentId: String): List<PhysicalTestNotebookLink>

    @Throws(Exception::class)
    suspend fun saveResult(result: PhysicalTestResult, attempts: List<PhysicalTestAttempt>)
    @Throws(Exception::class)
    suspend fun listResultsForAssignment(assignmentId: String): List<PhysicalTestResult>
    @Throws(Exception::class)
    suspend fun listResultsForStudent(studentId: Long, testId: String): List<PhysicalTestResult>
    @Throws(Exception::class)
    suspend fun listPhysicalTestHistoryForStudent(studentId: Long): List<PhysicalTestHistoryPoint> = emptyList()
}

interface PlannerRepository {
    fun observeSessions(weekNumber: Int, year: Int): Flow<List<PlanningSession>>
    @Throws(Exception::class)
    suspend fun listSessions(weekNumber: Int, year: Int): List<PlanningSession>
    @Throws(Exception::class)
    suspend fun listAllSessions(): List<PlanningSession> = emptyList()
    @Throws(Exception::class)
    suspend fun listSessionsInRange(groupId: Long? = null, fromDate: LocalDate, toDate: LocalDate): List<PlanningSession> = emptyList()
    @Throws(Exception::class)
    suspend fun upsertSession(session: PlanningSession): Long
    @Throws(Exception::class)
    suspend fun bulkUpsertSessions(sessions: List<PlanningSession>): List<Long> = sessions.map { upsertSession(it) }
    @Throws(Exception::class)
    suspend fun deleteSession(sessionId: Long)
    @Throws(Exception::class)
    suspend fun deleteSessions(sessionIds: List<Long>) {
        sessionIds.forEach { deleteSession(it) }
    }
    @Throws(Exception::class)
    suspend fun deleteFutureSessionsGeneratedFromScheduleSlot(slotId: Long, fromDate: LocalDate): Int = 0
    fun observeTeachingUnits(groupId: Long? = null): Flow<List<TeachingUnit>>
    @Throws(Exception::class)
    suspend fun listAllTeachingUnits(): List<TeachingUnit> = emptyList()
    @Throws(Exception::class)
    suspend fun upsertTeachingUnit(unit: TeachingUnit): Long
    @Throws(Exception::class)
    suspend fun deleteTeachingUnit(unitId: Long): Boolean
    fun getTimeSlots(): List<TimeSlotConfig>
    @Throws(Exception::class)
    suspend fun moveSessionsFromWeek(fromWeek: Int, fromYear: Int, offsetWeeks: Int)
    @Throws(Exception::class)
    suspend fun previewSessionRelocation(request: SessionRelocationRequest): List<SessionRelocationConflict> = emptyList()
    @Throws(Exception::class)
    suspend fun copySessions(
        request: SessionRelocationRequest,
        resolution: CollisionResolution
    ): SessionBulkResult = SessionBulkResult()
    @Throws(Exception::class)
    suspend fun shiftSelectedSessions(
        request: SessionRelocationRequest,
        resolution: CollisionResolution
    ): SessionBulkResult = SessionBulkResult()
    @Throws(Exception::class)
    suspend fun previewCascadeMove(request: SessionCascadeMoveRequest): SessionCascadeMovePreview =
        SessionCascadeMovePreview()
    @Throws(Exception::class)
    suspend fun commitCascadeMove(request: SessionCascadeMoveRequest): SessionCascadeMoveResult =
        SessionCascadeMoveResult()
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun getOrCreateJournal(session: PlanningSession): SessionJournalAggregate
    @Throws(Exception::class)
    suspend fun getJournalForSession(planningSessionId: Long): SessionJournalAggregate?
    @Throws(Exception::class)
    suspend fun listSummariesForSessions(planningSessionIds: List<Long>): List<SessionJournalSummary>
    @Throws(Exception::class)
    suspend fun saveJournalAggregate(aggregate: SessionJournalAggregate): Long
    @Throws(Exception::class)
    suspend fun deleteJournalForSession(planningSessionId: Long)
}

data class ConflictPreview(
    val session: PlanningSession,
    val newDate: LocalDate,
    val isConflict: Boolean
)

interface RubricsRepository {
    fun observeRubrics(): Flow<List<RubricDetail>>
    @Throws(Exception::class)
    suspend fun listRubrics(): List<RubricDetail>
    @Throws(Exception::class)
    suspend fun getRubricDetail(rubricId: Long): RubricDetail? = listRubrics().find { it.rubric.id == rubricId }
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun deleteRubric(rubricId: Long)
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun deleteCriterion(criterionId: Long)
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun deleteLevel(levelId: Long)
    @Throws(Exception::class)
    suspend fun saveRubricAssessment(
        studentId: Long,
        evaluationId: Long,
        criterionId: Long,
        levelId: Long,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): Double?
    @Throws(Exception::class)
    suspend fun listRubricAssessments(studentId: Long, evaluationId: Long): List<RubricAssessment>
    @Throws(Exception::class)
    suspend fun getStudentEvaluation(studentId: Long, rubricId: Long, evaluationId: Long): Map<Long, Long>
    @Throws(Exception::class)
    suspend fun listCriteriaByRubric(rubricId: Long): List<RubricCriterion>
    @Throws(Exception::class)
    suspend fun listLevelsByCriterion(criterionId: Long): List<RubricLevel>
}

interface AttendanceRepository {
    fun observeAttendance(classId: Long): Flow<List<Attendance>>
    fun observeAttendanceByDate(classId: Long, dateEpochMs: Long): Flow<List<Attendance>>
    @Throws(Exception::class)
    suspend fun listAttendance(classId: Long): List<Attendance>
    @Throws(Exception::class)
    suspend fun listAttendanceByDate(classId: Long, dateEpochMs: Long): List<Attendance>
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun getAttendanceForClassBetweenDates(classId: Long, startDateMs: Long, endDateMs: Long): List<Attendance>
}

interface StudentSupportMeasureRepository {
    @Throws(Exception::class)
    suspend fun listByStudent(studentId: Long): List<StudentSupportMeasure>
    @Throws(Exception::class)
    suspend fun listActiveStudentIds(): Set<Long>
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun retire(id: Long, endDateIso: String, updatedAtEpochMs: Long = 0, deviceId: String? = null)
    @Throws(Exception::class)
    suspend fun delete(id: Long)
}

interface StudentTutoringSessionRepository {
    @Throws(Exception::class)
    suspend fun listByStudent(studentId: Long): List<StudentTutoringSession>
    /** Seguimientos abiertos cuya revision vence en o antes de `onOrBeforeIso`. */
    @Throws(Exception::class)
    suspend fun listPendingReviews(onOrBeforeIso: String): List<StudentTutoringSession>
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun delete(id: Long)
}

interface MeetingRepository {
    /** Todas las reuniones, de la mas reciente a la mas antigua, con sus acuerdos ya cargados. */
    @Throws(Exception::class)
    suspend fun listAll(): List<Meeting>
    @Throws(Exception::class)
    suspend fun getById(id: Long): Meeting?
    /** Acuerdos sin cerrar cuya fecha limite vence en o antes de `onOrBeforeIso`. */
    @Throws(Exception::class)
    suspend fun listPendingAgreements(onOrBeforeIso: String): List<MeetingAgreement>
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun deleteMeeting(id: Long)
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun deleteAgreement(id: Long)
}

interface PlannerWeekPlanRepository {
    /** El plan de un grupo en una semana ISO concreta, o `null` si aun no existe. */
    @Throws(Exception::class)
    suspend fun getPlan(classId: Long, year: Int, week: Int): PlannerWeekPlan?
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun delete(id: Long)
}

interface CompetenciesRepository {
    fun observeCompetencies(): Flow<List<CompetencyCriterion>>
    @Throws(Exception::class)
    suspend fun listCompetencies(): List<CompetencyCriterion>
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun listIncidents(classId: Long): List<Incident>
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun deleteIncident(id: Long)
}

interface CalendarRepository {
    fun observeEvents(classId: Long? = null): Flow<List<CalendarEvent>>
    @Throws(Exception::class)
    suspend fun listEvents(classId: Long? = null): List<CalendarEvent>
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun listTemplates(kind: ConfigTemplateKind? = null): List<ConfigTemplate>
    @Throws(Exception::class)
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
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun listTemplateVersions(templateId: Long): List<ConfigTemplateVersion>
    @Throws(Exception::class)
    suspend fun cloneLatestVersionToTemplate(
        sourceTemplateId: Long,
        targetTemplateId: Long,
        sourceAcademicYearId: Long? = null,
        authorUserId: Long? = null,
    ): Long
}

interface LearningSituationsRepository {
    fun observeSituations(): Flow<List<LearningSituation>>
    @Throws(Exception::class)
    suspend fun listSituations(): List<LearningSituation>
    @Throws(Exception::class)
    suspend fun getSituation(id: Long): LearningSituation?
    @Throws(Exception::class)
    suspend fun saveSituation(situation: LearningSituation): Long
    @Throws(Exception::class)
    suspend fun saveVersion(version: LearningSituationVersion): Long
    @Throws(Exception::class)
    suspend fun listVersions(learningSituationId: Long): List<LearningSituationVersion>
    @Throws(Exception::class)
    suspend fun saveSessionSequenceVersion(version: LearningSituationSessionSequenceVersion): Long
    @Throws(Exception::class)
    suspend fun listSessionSequenceVersions(learningSituationId: Long): List<LearningSituationSessionSequenceVersion>
    @Throws(Exception::class)
    suspend fun saveSessionPlan(plan: LearningSituationSessionPlan): Long
    @Throws(Exception::class)
    suspend fun listSessionPlans(sequenceVersionId: Long): List<LearningSituationSessionPlan>
    @Throws(Exception::class)
    suspend fun getSessionPlan(id: Long): LearningSituationSessionPlan?
    @Throws(Exception::class)
    suspend fun replaceClassLinks(learningSituationId: Long, classIds: List<Long>)
    @Throws(Exception::class)
    suspend fun listClassLinks(learningSituationId: Long): List<LearningSituationClassLink>
    @Throws(Exception::class)
    suspend fun saveLinkedResource(resource: LearningSituationLinkedResource): Long
    @Throws(Exception::class)
    suspend fun listLinkedResources(learningSituationId: Long): List<LearningSituationLinkedResource>
    @Throws(Exception::class)
    suspend fun deleteSituation(id: Long)
}


interface DashboardRepository {
    fun observeStats(): Flow<DashboardStats>
    @Throws(Exception::class)
    suspend fun getStats(): DashboardStats
    @Throws(Exception::class)
    suspend fun getTodaySnapshot(dayStartEpochMs: Long, dayEndEpochMs: Long): DashboardTodaySnapshot =
        DashboardTodaySnapshot()
}

interface DashboardOperationalRepository {
    @Throws(Exception::class)
    suspend fun getSnapshot(
        date: LocalDate,
        mode: DashboardMode,
        filters: DashboardFilters = DashboardFilters(),
    ): DashboardSnapshot

    @Throws(Exception::class)
    suspend fun executeQuickAction(command: QuickActionCommand): QuickActionResult
}

interface BackupMetadataRepository {
    fun observeBackups(): Flow<List<BackupEntry>>
    @Throws(Exception::class)
    suspend fun listBackups(): List<BackupEntry>
    @Throws(Exception::class)
    suspend fun saveBackup(path: String, createdAtEpochMs: Long, platform: String, sizeBytes: Long): Long
    @Throws(Exception::class)
    suspend fun deleteBackup(id: Long)
}

interface AIAuditRepository {
    @Throws(Exception::class)
    suspend fun recordEvent(event: AIAuditEvent)
    @Throws(Exception::class)
    suspend fun recentEvents(limit: Long = 50): List<AIAuditEvent>
    @Throws(Exception::class)
    suspend fun recentFailures(limit: Long = 20): List<AIAuditEvent>
    @Throws(Exception::class)
    suspend fun latestEvent(): AIAuditEvent?
    @Throws(Exception::class)
    suspend fun totalsByUseCase(): List<AIAuditUseCaseTotal>
    @Throws(Exception::class)
    suspend fun recentAvailabilityTotals(): List<AIAuditAvailabilityTotal>
}

interface CsvImportService {
    @Throws(Exception::class)
    suspend fun parseStudents(csv: String): List<StudentCsvRow>
}

interface XlsxImportService {
    @Throws(Exception::class)
    suspend fun parseStudents(bytes: ByteArray): List<StudentCsvRow>
    @Throws(Exception::class)
    suspend fun parseRubric(bytes: ByteArray, fallbackTitle: String = "Rúbrica importada"): ImportedRubric
}

interface ReportService {
    @Throws(Exception::class)
    suspend fun exportNotebookReport(request: NotebookReportRequest): ByteArray
}

interface BackupService {
    @Throws(Exception::class)
    suspend fun createBackup(fileName: String = "mi_gestor_backup.sqlite"): BackupResult
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun insert(slot: WeeklySlotTemplate): Long
    @Throws(Exception::class)
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
    @Throws(Exception::class)
    suspend fun getSessionsForClass(schoolClassId: Long, startDate: LocalDate, endDate: LocalDate): List<PlannedSession>
    fun observeSessionsForClass(schoolClassId: Long, startDate: LocalDate, endDate: LocalDate): Flow<List<PlannedSession>>
    fun observeAllSessions(startDate: LocalDate, endDate: LocalDate): Flow<List<PlannedSession>>
    @Throws(Exception::class)
    suspend fun getAllSessions(startDate: LocalDate, endDate: LocalDate): List<PlannedSession>
    @Throws(Exception::class)
    suspend fun existsAt(schoolClassId: Long, date: LocalDate, startTime: String): Boolean
    @Throws(Exception::class)
    suspend fun insert(session: PlannedSession): Long
    @Throws(Exception::class)
    suspend fun update(session: PlannedSession)
    @Throws(Exception::class)
    suspend fun delete(sessionId: Long)
    @Throws(Exception::class)
    suspend fun listSessionsInRange(schoolClassId: Long? = null, startDate: LocalDate, endDate: LocalDate): List<PlannedSession> =
        if (schoolClassId != null) getSessionsForClass(schoolClassId, startDate, endDate) else getAllSessions(startDate, endDate)
    @Throws(Exception::class)
    suspend fun deleteSessions(sessionIds: List<Long>) {
        sessionIds.forEach { delete(it) }
    }
    @Throws(Exception::class)
    suspend fun bulkUpsertOrReplacePlannedSessions(sessions: List<PlannedSession>): List<Long> = sessions.map { insert(it) }
}

interface AITrendsRepository {
    @Throws(Exception::class)
    suspend fun getStudentGradesHistory(classId: Long, studentId: Long): List<StudentGradeHistoryPoint>
    @Throws(Exception::class)
    suspend fun getStudentAttendanceStats(classId: Long, studentId: Long): StudentAttendanceStats
    @Throws(Exception::class)
    suspend fun getStudentIncidentsHistory(classId: Long, studentId: Long): List<StudentIncidentPoint>
    @Throws(Exception::class)
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
