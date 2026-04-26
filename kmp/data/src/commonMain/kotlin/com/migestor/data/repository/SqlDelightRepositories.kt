package com.migestor.data.repository

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import app.cash.sqldelight.coroutines.mapToOne
import com.migestor.data.db.AppDatabase
import com.migestor.shared.domain.Attendance
import com.migestor.shared.domain.AuditTrace
import com.migestor.shared.domain.BackupEntry
import com.migestor.shared.domain.CalendarEvent
import com.migestor.shared.domain.CompetencyCriterion
import com.migestor.shared.domain.ConfigTemplate
import com.migestor.shared.domain.ConfigTemplateKind
import com.migestor.shared.domain.ConfigTemplateVersion
import com.migestor.shared.domain.DashboardStats
import com.migestor.shared.domain.Evaluation
import com.migestor.shared.domain.EvaluationCompetencyLink
import com.migestor.shared.domain.Grade
import com.migestor.shared.domain.Incident
import com.migestor.shared.domain.Period
import com.migestor.shared.domain.PersistedNotebookCell
import com.migestor.shared.domain.PlanningSession
import com.migestor.shared.domain.Rubric
import com.migestor.shared.domain.RubricAssessment
import com.migestor.shared.domain.RubricCriterion
import com.migestor.shared.domain.RubricCriterionWithLevels
import com.migestor.shared.domain.RubricDetail
import com.migestor.shared.domain.RubricLevel
import com.migestor.shared.domain.SchoolClass
import com.migestor.shared.domain.SessionStatus
import com.migestor.shared.domain.Student
import com.migestor.shared.domain.TeachingUnit
import com.migestor.shared.util.IsoWeekHelper
import com.migestor.shared.repository.AttendanceRepository
import com.migestor.shared.repository.BackupMetadataRepository
import com.migestor.shared.repository.CalendarRepository
import com.migestor.shared.repository.ClassesRepository
import com.migestor.shared.repository.CompetenciesRepository
import com.migestor.shared.repository.ConfigurationTemplateRepository
import com.migestor.shared.repository.DashboardRepository
import com.migestor.shared.repository.EvaluationsRepository
import com.migestor.shared.repository.GradesRepository
import com.migestor.shared.repository.IncidentsRepository
import com.migestor.shared.repository.NotebookCellsRepository
import com.migestor.shared.repository.PlannerRepository
import com.migestor.shared.repository.RubricsRepository
import com.migestor.shared.repository.StudentsRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

class StudentsRepositorySqlDelight(
    private val db: AppDatabase,
) : StudentsRepository {
    override fun observeStudents(): Flow<List<Student>> {
        return db.appDatabaseQueries
            .selectAllStudents()
            .asFlow()
            .mapToList(Dispatchers.Default)
            .map { rows ->
                rows.map {
                    Student(
                        id = it.id,
                        firstName = it.first_name,
                        lastName = it.last_name,
                        email = it.email,
                        photoPath = it.photo_path,
                        isInjured = it.is_injured != 0L,
                        trace = AuditTrace(
                            updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                            deviceId = it.device_id,
                            syncVersion = it.sync_version,
                        )
                    )
                }
            }
    }

    override suspend fun listStudents(): List<Student> {
        return db.appDatabaseQueries.selectAllStudents().executeAsList().map {
            Student(
                id = it.id,
                firstName = it.first_name,
                lastName = it.last_name,
                email = it.email,
                photoPath = it.photo_path,
                isInjured = it.is_injured != 0L,
                trace = AuditTrace(
                    updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                    deviceId = it.device_id,
                    syncVersion = it.sync_version,
                )
            )
        }
    }

    override suspend fun saveStudent(
        id: Long?,
        firstName: String,
        lastName: String,
        email: String?,
        photoPath: String?,
        isInjured: Boolean,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): Long {
        val now = if (updatedAtEpochMs > 0) updatedAtEpochMs else Clock.System.now().toEpochMilliseconds()
        val injured = if (isInjured) 1L else 0L
        return db.transactionWithResult {
            db.appDatabaseQueries.upsertStudent(id, firstName, lastName, email, photoPath, injured, now, deviceId, syncVersion)
            id ?: db.appDatabaseQueries.lastInsertedId().executeAsOne()
        }
    }

    override suspend fun deleteStudent(studentId: Long) {
        db.appDatabaseQueries.deleteStudent(studentId)
    }
}

class ClassesRepositorySqlDelight(
    private val db: AppDatabase,
) : ClassesRepository {
    override fun observeClasses(): Flow<List<SchoolClass>> {
        return db.appDatabaseQueries
            .selectAllClasses()
            .asFlow()
            .mapToList(Dispatchers.Default)
            .map { rows ->
                rows.map {
                    SchoolClass(
                        id = it.id,
                        name = it.name,
                        course = it.course.toInt(),
                        description = it.description,
                        trace = AuditTrace(
                            updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                            deviceId = it.device_id,
                            syncVersion = it.sync_version,
                        )
                    )
                }
            }
    }

    override suspend fun listClasses(): List<SchoolClass> {
        return db.appDatabaseQueries.selectAllClasses().executeAsList().map {
            SchoolClass(
                id = it.id,
                name = it.name,
                course = it.course.toInt(),
                description = it.description,
                trace = AuditTrace(
                    updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                    deviceId = it.device_id,
                    syncVersion = it.sync_version,
                )
            )
        }
    }

    override suspend fun saveClass(
        id: Long?,
        name: String,
        course: Int,
        description: String?,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): Long {
        val now = if (updatedAtEpochMs > 0) updatedAtEpochMs else Clock.System.now().toEpochMilliseconds()
        return db.transactionWithResult {
            db.appDatabaseQueries.upsertClass(id, name, course.toLong(), description, now, deviceId, syncVersion)
            id ?: db.appDatabaseQueries.lastInsertedId().executeAsOne()
        }
    }

    override suspend fun deleteClass(classId: Long) {
        db.appDatabaseQueries.deleteClass(classId)
    }

    override suspend fun addStudentToClass(classId: Long, studentId: Long) {
        db.appDatabaseQueries.insertClassStudent(classId, studentId)
    }

    override suspend fun removeStudentFromClass(classId: Long, studentId: Long) {
        db.appDatabaseQueries.removeClassStudent(classId, studentId)
    }

    override suspend fun listStudentsInClass(classId: Long): List<Student> {
        return db.appDatabaseQueries.selectStudentsByClass(classId).executeAsList().map {
            Student(
                id = it.id,
                firstName = it.first_name,
                lastName = it.last_name,
                email = it.email,
                photoPath = it.photo_path,
                isInjured = it.is_injured != 0L,
                trace = AuditTrace(
                    updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                    deviceId = it.device_id,
                    syncVersion = it.sync_version,
                )
            )
        }
    }

    override fun observeStudentsInClass(classId: Long): Flow<List<Student>> {
        return db.appDatabaseQueries
            .selectStudentsByClass(classId)
            .asFlow()
            .mapToList(Dispatchers.Default)
            .map { rows ->
                rows.map {
                    Student(
                        id = it.id,
                        firstName = it.first_name,
                        lastName = it.last_name,
                        email = it.email,
                        photoPath = it.photo_path,
                        isInjured = it.is_injured != 0L,
                        trace = AuditTrace(
                            updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                            deviceId = it.device_id,
                            syncVersion = it.sync_version,
                        )
                    )
                }
            }
    }
}

class EvaluationsRepositorySqlDelight(
    private val db: AppDatabase,
) : EvaluationsRepository {
    override fun observeClassEvaluations(classId: Long): Flow<List<Evaluation>> {
        return db.appDatabaseQueries
            .selectEvaluationsByClass(classId)
            .asFlow()
            .mapToList(Dispatchers.Default)
            .map { rows ->
                rows.map {
                    Evaluation(
                        id = it.id,
                        classId = it.class_id,
                        code = it.code,
                        name = it.name,
                        type = it.type,
                        weight = it.weight,
                        formula = it.formula,
                        rubricId = it.rubric_id,
                        description = it.description,
                        trace = AuditTrace(
                            authorUserId = it.author_user_id,
                            createdAt = Instant.fromEpochMilliseconds(it.created_at_epoch_ms),
                            updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                            deviceId = it.device_id,
                            syncVersion = it.sync_version,
                            associatedGroupId = it.associated_group_id,
                        )
                    )
                }
            }
    }

    override suspend fun listClassEvaluations(classId: Long): List<Evaluation> {
        return db.appDatabaseQueries.selectEvaluationsByClass(classId).executeAsList().map {
            Evaluation(
                id = it.id,
                classId = it.class_id,
                code = it.code,
                name = it.name,
                type = it.type,
                weight = it.weight,
                formula = it.formula,
                rubricId = it.rubric_id,
                description = it.description,
                trace = AuditTrace(
                    authorUserId = it.author_user_id,
                    createdAt = Instant.fromEpochMilliseconds(it.created_at_epoch_ms),
                    updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                    deviceId = it.device_id,
                    syncVersion = it.sync_version,
                    associatedGroupId = it.associated_group_id,
                )
            )
        }
    }

    override suspend fun getEvaluation(evaluationId: Long): Evaluation? {
        return db.appDatabaseQueries.selectEvaluationById(evaluationId).executeAsOneOrNull()?.let {
            Evaluation(
                id = it.id,
                classId = it.class_id,
                code = it.code,
                name = it.name,
                type = it.type,
                weight = it.weight,
                formula = it.formula,
                rubricId = it.rubric_id,
                description = it.description,
                trace = AuditTrace(
                    authorUserId = it.author_user_id,
                    createdAt = Instant.fromEpochMilliseconds(it.created_at_epoch_ms),
                    updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                    deviceId = it.device_id,
                    syncVersion = it.sync_version,
                    associatedGroupId = it.associated_group_id,
                )
            )
        }
    }

    override suspend fun saveEvaluation(
        id: Long?,
        classId: Long,
        code: String,
        name: String,
        type: String,
        weight: Double,
        formula: String?,
        rubricId: Long?,
        description: String?,
        authorUserId: Long?,
        createdAtEpochMs: Long,
        updatedAtEpochMs: Long,
        associatedGroupId: Long?,
        deviceId: String?,
        syncVersion: Long,
    ): Long {
        val now = if (updatedAtEpochMs > 0) updatedAtEpochMs else Clock.System.now().toEpochMilliseconds()
        val created = if (createdAtEpochMs > 0) createdAtEpochMs else now
        return db.transactionWithResult {
            db.appDatabaseQueries.upsertEvaluation(
                id, classId, code, name, type, weight, formula, rubricId, description, 
                authorUserId, created, now, associatedGroupId, deviceId, syncVersion
            )
            id ?: db.appDatabaseQueries.lastInsertedId().executeAsOne()
        }
    }

    override suspend fun deleteEvaluation(evaluationId: Long) {
        db.appDatabaseQueries.deleteEvaluation(evaluationId)
    }

    override suspend fun saveEvaluationCompetencyLink(
        id: Long?,
        evaluationId: Long,
        competencyId: Long,
        weight: Double,
        authorUserId: Long?,
    ): Long {
        val now = Clock.System.now().toEpochMilliseconds()
        return db.transactionWithResult {
            db.appDatabaseQueries.upsertEvaluationCompetencyLink(
                id,
                evaluationId,
                competencyId,
                weight,
                authorUserId,
                now,
                now,
                null, // associatedGroupId
                null, // deviceId
                0,    // syncVersion
            )
            id ?: db.appDatabaseQueries.lastInsertedId().executeAsOne()
        }
    }

    override suspend fun listEvaluationCompetencyLinks(evaluationId: Long): List<EvaluationCompetencyLink> {
        return db.appDatabaseQueries.selectEvaluationCompetencyLinks(evaluationId).executeAsList().map {
            EvaluationCompetencyLink(
                id = it.id,
                evaluationId = it.evaluation_id,
                competencyId = it.competency_id,
                weight = it.weight,
                trace = AuditTrace(
                    authorUserId = it.author_user_id,
                    createdAt = Instant.fromEpochMilliseconds(it.created_at_epoch_ms),
                    updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                    associatedGroupId = it.associated_group_id,
                    deviceId = it.device_id,
                    syncVersion = it.sync_version,
                ),
            )
        }
    }
}

class GradesRepositorySqlDelight(
    private val db: AppDatabase,
) : GradesRepository {
    private fun shouldApplyIncomingChange(
        existingUpdatedAtEpochMs: Long?,
        existingDeviceId: String?,
        incomingUpdatedAtEpochMs: Long,
        incomingDeviceId: String?,
    ): Boolean {
        val existingUpdatedAt = existingUpdatedAtEpochMs ?: return true
        if (incomingUpdatedAtEpochMs > existingUpdatedAt) return true
        if (incomingUpdatedAtEpochMs < existingUpdatedAt) return false
        val incoming = incomingDeviceId ?: ""
        val existing = existingDeviceId ?: ""
        return incoming >= existing
    }

    override suspend fun saveGrade(
        id: Long?,
        classId: Long,
        studentId: Long,
        columnId: String,
        evaluationId: Long?,
        value: Double?,
        evidence: String?,
        evidencePath: String?,
        rubricSelections: String?,
        createdAtEpochMs: Long,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): Long {
        val now = if (updatedAtEpochMs > 0) updatedAtEpochMs else Clock.System.now().toEpochMilliseconds()
        val created = if (createdAtEpochMs > 0) createdAtEpochMs else now
        val existing = db.appDatabaseQueries.selectGradeByStudentClassAndColumn(classId, studentId, columnId).executeAsOneOrNull()
        val canApply = shouldApplyIncomingChange(
            existingUpdatedAtEpochMs = existing?.updated_at_epoch_ms,
            existingDeviceId = existing?.device_id,
            incomingUpdatedAtEpochMs = now,
            incomingDeviceId = deviceId
        )
        if (!canApply) {
            return id ?: 0L
        }

        return db.transactionWithResult {
            db.appDatabaseQueries.upsertGrade(
                class_id = classId,
                student_id = studentId,
                column_id = columnId,
                evaluation_id = evaluationId,
                value_ = value,
                evidence = evidence,
                evidence_path = evidencePath,
                rubric_selections = rubricSelections,
                created_at_epoch_ms = created,
                updated_at_epoch_ms = now,
                device_id = deviceId,
                sync_version = syncVersion
            )
            id ?: db.appDatabaseQueries.lastInsertedId().executeAsOne()
        }
    }

    override fun observeGradesForClass(classId: Long): Flow<List<Grade>> {
        return db.appDatabaseQueries.selectGradesByClass(classId) { id, classIdDb, studentIdDb, columnId, evaluationId, value, evidence, evidencePath, rubric_selections, createdAt, updatedAt, device_id, sync_version ->
            Grade(
                id = id,
                classId = classIdDb,
                studentId = studentIdDb,
                columnId = columnId,
                evaluationId = evaluationId,
                value = value,
                evidence = evidence,
                evidencePath = evidencePath,
                rubricSelections = rubric_selections,
                trace = AuditTrace(
                    createdAt = Instant.fromEpochMilliseconds(createdAt),
                    updatedAt = Instant.fromEpochMilliseconds(updatedAt),
                    deviceId = device_id,
                    syncVersion = sync_version,
                )
            )
        }.asFlow().mapToList(Dispatchers.Default)
    }

    override suspend fun upsertGrade(
        classId: Long,
        studentId: Long,
        columnId: String,
        evaluationId: Long?,
        value: Double?,
        evidence: String?,
        evidencePath: String?,
        rubricSelections: String?,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ) {
        val now = if (updatedAtEpochMs > 0) updatedAtEpochMs else Clock.System.now().toEpochMilliseconds()
        val existing = db.appDatabaseQueries.selectGradeByStudentClassAndColumn(classId, studentId, columnId).executeAsOneOrNull()
        val canApply = shouldApplyIncomingChange(
            existingUpdatedAtEpochMs = existing?.updated_at_epoch_ms,
            existingDeviceId = existing?.device_id,
            incomingUpdatedAtEpochMs = now,
            incomingDeviceId = deviceId
        )
        if (!canApply) return

        db.appDatabaseQueries.upsertGrade(
            class_id = classId,
            student_id = studentId,
            column_id = columnId,
            evaluation_id = evaluationId,
            value_ = value,
            evidence = evidence,
            evidence_path = evidencePath,
            rubric_selections = rubricSelections,
            created_at_epoch_ms = now,
            updated_at_epoch_ms = now,
            device_id = deviceId,
            sync_version = syncVersion
        )
    }

    override suspend fun listGradesForClass(classId: Long): List<Grade> {
        return db.appDatabaseQueries.selectGradesByClass(classId) { id, classIdDb, studentId, columnId, evaluationId, value, evidence, evidencePath, rubric_selections, createdAt, updatedAt, device_id, sync_version ->
            Grade(
                id = id,
                classId = classIdDb,
                studentId = studentId,
                columnId = columnId,
                evaluationId = evaluationId,
                value = value,
                evidence = evidence,
                evidencePath = evidencePath,
                rubricSelections = rubric_selections,
                trace = AuditTrace(
                    createdAt = Instant.fromEpochMilliseconds(createdAt),
                    updatedAt = Instant.fromEpochMilliseconds(updatedAt),
                    deviceId = device_id,
                    syncVersion = sync_version,
                )
            )
        }.executeAsList()
    }

    override suspend fun listGradesForStudentInClass(studentId: Long, classId: Long): List<Grade> {
        return db.appDatabaseQueries.selectGradesByStudentAndClass(studentId, classId) { id, classIdDb, studentIdDb, columnId, evaluationId, value, evidence, evidencePath, rubric_selections, createdAt, updatedAt, device_id, sync_version ->
            Grade(
                id = id,
                classId = classIdDb,
                studentId = studentIdDb,
                columnId = columnId,
                evaluationId = evaluationId,
                value = value,
                evidence = evidence,
                evidencePath = evidencePath,
                rubricSelections = rubric_selections,
                trace = AuditTrace(
                    createdAt = Instant.fromEpochMilliseconds(createdAt),
                    updatedAt = Instant.fromEpochMilliseconds(updatedAt),
                    deviceId = device_id,
                    syncVersion = sync_version,
                )
            )
        }.executeAsList()
    }
}

class NotebookCellsRepositorySqlDelight(
    private val db: AppDatabase,
) : NotebookCellsRepository {
    override fun observeClassCells(classId: Long): Flow<List<PersistedNotebookCell>> {
        return db.appDatabaseQueries
            .selectNotebookCellsByClass(classId) { classIdDb, studentId, columnId, valueText, valueBool, valueIcon, valueOrdinal, displayValue, observedAtEpochMs, competencyCriteriaIdsCsv, effectiveWeight, countsTowardAverage, note, colorHex, attachmentUrisCsv, authorUserId, createdAt, updatedAt, associatedGroupId, device_id, sync_version ->
                PersistedNotebookCell(
                    classId = classIdDb,
                    studentId = studentId,
                    columnId = columnId,
                    textValue = valueText,
                    boolValue = valueBool?.let { it != 0L },
                    iconValue = valueIcon,
                    ordinalValue = valueOrdinal,
                    displayValue = displayValue,
                    observedAtEpochMs = observedAtEpochMs,
                    competencyCriteriaIds = competencyCriteriaIdsCsv?.split(",")?.mapNotNull { it.trim().toLongOrNull() } ?: emptyList(),
                    effectiveWeight = effectiveWeight,
                    countsTowardAverage = countsTowardAverage?.let { it != 0L },
                    annotation = com.migestor.shared.domain.NotebookCellAnnotation(
                        note = note,
                        colorHex = colorHex,
                        attachmentUris = attachmentUrisCsv?.split("|")?.filter { it.isNotBlank() } ?: emptyList(),
                    ),
                    trace = AuditTrace(
                        authorUserId = authorUserId,
                        createdAt = Instant.fromEpochMilliseconds(createdAt),
                        updatedAt = Instant.fromEpochMilliseconds(updatedAt),
                        associatedGroupId = associatedGroupId,
                        deviceId = device_id,
                        syncVersion = sync_version,
                    ),
                )
            }
            .asFlow()
            .mapToList(Dispatchers.Default)
    }

    override suspend fun listClassCells(classId: Long): List<PersistedNotebookCell> {
        return db.appDatabaseQueries.selectNotebookCellsByClass(classId) { classIdDb, studentId, columnId, valueText, valueBool, valueIcon, valueOrdinal, displayValue, observedAtEpochMs, competencyCriteriaIdsCsv, effectiveWeight, countsTowardAverage, note, colorHex, attachmentUrisCsv, authorUserId, createdAt, updatedAt, associatedGroupId, device_id, sync_version ->
            PersistedNotebookCell(
                classId = classIdDb,
                studentId = studentId,
                columnId = columnId,
                textValue = valueText,
                boolValue = valueBool?.let { it != 0L },
                iconValue = valueIcon,
                ordinalValue = valueOrdinal,
                displayValue = displayValue,
                observedAtEpochMs = observedAtEpochMs,
                competencyCriteriaIds = competencyCriteriaIdsCsv?.split(",")?.mapNotNull { it.trim().toLongOrNull() } ?: emptyList(),
                effectiveWeight = effectiveWeight,
                countsTowardAverage = countsTowardAverage?.let { it != 0L },
                annotation = com.migestor.shared.domain.NotebookCellAnnotation(
                    note = note,
                    colorHex = colorHex,
                    attachmentUris = attachmentUrisCsv?.split("|")?.filter { it.isNotBlank() } ?: emptyList(),
                ),
                trace = AuditTrace(
                    authorUserId = authorUserId,
                    createdAt = Instant.fromEpochMilliseconds(createdAt),
                    updatedAt = Instant.fromEpochMilliseconds(updatedAt),
                    associatedGroupId = associatedGroupId,
                    deviceId = device_id,
                    syncVersion = sync_version,
                ),
            )
        }.executeAsList()
    }

    override suspend fun saveCell(
        classId: Long,
        studentId: Long,
        columnId: String,
        textValue: String?,
        boolValue: Boolean?,
        iconValue: String?,
        ordinalValue: String?,
        note: String?,
        colorHex: String?,
        attachmentUris: List<String>,
        authorUserId: Long?,
        associatedGroupId: Long?,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ) {
        val now = if (updatedAtEpochMs > 0) updatedAtEpochMs else Clock.System.now().toEpochMilliseconds()
        val existing = db.appDatabaseQueries.selectNotebookCellEntry(classId, studentId, columnId).executeAsOneOrNull()
        db.appDatabaseQueries.upsertNotebookCellEntry(
            class_id = classId,
            student_id = studentId,
            column_id = columnId,
            value_text = textValue ?: existing?.value_text,
            value_bool = boolValue?.let { if (it) 1L else 0L } ?: existing?.value_bool,
            value_icon = iconValue ?: existing?.value_icon,
            value_ordinal = ordinalValue ?: existing?.value_ordinal,
            display_value = existing?.display_value,
            observed_at_epoch_ms = existing?.observed_at_epoch_ms,
            competency_criteria_ids_csv = existing?.competency_criteria_ids_csv ?: "",
            effective_weight = existing?.effective_weight,
            counts_toward_average = existing?.counts_toward_average,
            note = note ?: existing?.note,
            color_hex = colorHex ?: existing?.color_hex,
            attachment_uris_csv = attachmentUris.takeIf { it.isNotEmpty() }?.joinToString("|") ?: existing?.attachment_uris_csv,
            author_user_id = authorUserId ?: existing?.author_user_id,
            created_at_epoch_ms = existing?.created_at_epoch_ms ?: now,
            updated_at_epoch_ms = now,
            associated_group_id = associatedGroupId ?: existing?.associated_group_id,
            device_id = deviceId,
            sync_version = syncVersion,
        )
    }
}

class RubricsRepositorySqlDelight(
    private val db: AppDatabase,
) : RubricsRepository {
    private fun shouldApplyIncomingChange(
        existingUpdatedAtEpochMs: Long?,
        existingDeviceId: String?,
        incomingUpdatedAtEpochMs: Long,
        incomingDeviceId: String?,
    ): Boolean {
        val existingUpdatedAt = existingUpdatedAtEpochMs ?: return true
        if (incomingUpdatedAtEpochMs > existingUpdatedAt) return true
        if (incomingUpdatedAtEpochMs < existingUpdatedAt) return false
        val incoming = incomingDeviceId ?: ""
        val existing = existingDeviceId ?: ""
        return incoming >= existing
    }

    override fun observeRubrics(): Flow<List<RubricDetail>> {
        val rubricsFlow = db.appDatabaseQueries.selectAllRubrics().asFlow().mapToList(Dispatchers.Default)
        val criteriaFlow = db.appDatabaseQueries.selectAllCriteria().asFlow().mapToList(Dispatchers.Default)
        val levelsFlow = db.appDatabaseQueries.selectAllLevels().asFlow().mapToList(Dispatchers.Default)

        return combine(rubricsFlow, criteriaFlow, levelsFlow) { rubricRows, criterionRows, levelRows ->
            val rubrics = rubricRows.map { 
                Rubric(
                    id = it.id, 
                    name = it.name, 
                    description = it.description,
                    classId = it.class_id,
                    teachingUnitId = it.teaching_unit_id,
                    trace = AuditTrace(
                        updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                        deviceId = it.device_id,
                        syncVersion = it.sync_version,
                    )
                ) 
            }
            val criteria = criterionRows.map {
                RubricCriterion(
                    id = it.id,
                    rubricId = it.rubric_id,
                    description = it.description,
                    weight = it.weight,
                    order = it.sort_order.toInt(),
                    trace = AuditTrace(
                        updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                        deviceId = it.device_id,
                        syncVersion = it.sync_version,
                    )
                )
            }
            val levels = levelRows.map {
                RubricLevel(
                    id = it.id,
                    criterionId = it.criterion_id,
                    name = it.name,
                    points = it.points.toInt(),
                    description = it.description,
                    order = it.sort_order.toInt(),
                    trace = AuditTrace(
                        updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                        deviceId = it.device_id,
                        syncVersion = it.sync_version,
                    )
                )
            }
            buildRubrics(rubrics, criteria, levels)
        }
    }

    override suspend fun listRubrics(): List<RubricDetail> {
        val rubrics = db.appDatabaseQueries.selectAllRubrics().executeAsList().map { 
            Rubric(
                id = it.id, 
                name = it.name, 
                description = it.description,
                classId = it.class_id,
                teachingUnitId = it.teaching_unit_id,
                trace = AuditTrace(
                    updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                    deviceId = it.device_id,
                    syncVersion = it.sync_version,
                )
            ) 
        }
        val criteria = db.appDatabaseQueries.selectAllCriteria().executeAsList().map {
            RubricCriterion(
                id = it.id,
                rubricId = it.rubric_id,
                description = it.description,
                weight = it.weight,
                order = it.sort_order.toInt(),
                trace = AuditTrace(
                    updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                    deviceId = it.device_id,
                    syncVersion = it.sync_version,
                )
            )
        }
        val levels = db.appDatabaseQueries.selectAllLevels().executeAsList().map {
            RubricLevel(
                id = it.id,
                criterionId = it.criterion_id,
                name = it.name,
                points = it.points.toInt(),
                description = it.description,
                order = it.sort_order.toInt(),
                trace = AuditTrace(
                    updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                    deviceId = it.device_id,
                    syncVersion = it.sync_version,
                )
            )
        }
        return buildRubrics(rubrics, criteria, levels)
    }

    override suspend fun saveRubric(
        id: Long?,
        name: String,
        description: String?,
        classId: Long?,
        teachingUnitId: Long?,
        createdAtEpochMs: Long,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): Long {
        val now = Clock.System.now().toEpochMilliseconds()
        val created = if (createdAtEpochMs == 0L) now else createdAtEpochMs
        val updated = if (updatedAtEpochMs == 0L) now else updatedAtEpochMs
        
        return db.transactionWithResult {
            db.appDatabaseQueries.upsertRubric(
                id, 
                name, 
                description, 
                classId,
                teachingUnitId,
                created, 
                updated, 
                deviceId, 
                syncVersion
            )
            id ?: db.appDatabaseQueries.lastInsertedId().executeAsOne()
        }
    }

    override suspend fun deleteRubric(rubricId: Long) {
        db.appDatabaseQueries.deleteRubric(rubricId)
    }

    override suspend fun saveCriterion(
        id: Long?,
        rubricId: Long,
        description: String,
        weight: Double,
        order: Int,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): Long {
        val now = if (updatedAtEpochMs > 0) updatedAtEpochMs else Clock.System.now().toEpochMilliseconds()
        return db.transactionWithResult {
            db.appDatabaseQueries.upsertCriterion(id, rubricId, description, weight, order.toLong(), now, deviceId, syncVersion)
            id ?: db.appDatabaseQueries.lastInsertedId().executeAsOne()
        }
    }

    override suspend fun deleteCriterion(criterionId: Long) {
        db.appDatabaseQueries.deleteCriterion(criterionId)
    }

    override suspend fun saveLevel(
        id: Long?,
        criterionId: Long,
        name: String,
        points: Int,
        description: String?,
        order: Int,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): Long {
        val now = if (updatedAtEpochMs > 0) updatedAtEpochMs else Clock.System.now().toEpochMilliseconds()
        return db.transactionWithResult {
            db.appDatabaseQueries.upsertLevel(id, criterionId, name, points.toLong(), description, order.toLong(), now, deviceId, syncVersion)
            id ?: db.appDatabaseQueries.lastInsertedId().executeAsOne()
        }
    }

    override suspend fun deleteLevel(levelId: Long) {
        db.appDatabaseQueries.deleteLevel(levelId)
    }

    override suspend fun saveRubricAssessment(
        studentId: Long,
        evaluationId: Long,
        criterionId: Long,
        levelId: Long,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): Double? {
        val now = if (updatedAtEpochMs > 0) updatedAtEpochMs else Clock.System.now().toEpochMilliseconds()
        val existing = db.appDatabaseQueries
            .selectRubricAssessmentByKey(studentId, evaluationId, criterionId)
            .executeAsOneOrNull()
        val canApply = shouldApplyIncomingChange(
            existingUpdatedAtEpochMs = existing?.updated_at_epoch_ms,
            existingDeviceId = existing?.device_id,
            incomingUpdatedAtEpochMs = now,
            incomingDeviceId = deviceId
        )
        if (!canApply) {
            return db.appDatabaseQueries.selectWeightedRubricScore(studentId, evaluationId).executeAsOneOrNull()?.score
        }

        db.appDatabaseQueries.upsertRubricAssessment(
            studentId,
            evaluationId,
            criterionId,
            levelId,
            now,
            now,
            deviceId,
            syncVersion,
        )
        return db.appDatabaseQueries.selectWeightedRubricScore(studentId, evaluationId).executeAsOneOrNull()?.score
    }

    override suspend fun listRubricAssessments(studentId: Long, evaluationId: Long): List<RubricAssessment> {
        return db.appDatabaseQueries.selectRubricAssessments(studentId, evaluationId).executeAsList().map {
            RubricAssessment(
                studentId = it.student_id,
                evaluationId = it.evaluation_id,
                criterionId = it.criterion_id,
                levelId = it.level_id,
                trace = AuditTrace(
                    createdAt = Instant.fromEpochMilliseconds(it.created_at_epoch_ms),
                    updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                    deviceId = it.device_id,
                    syncVersion = it.sync_version,
                ),
            )
        }
    }

    override suspend fun getStudentEvaluation(studentId: Long, rubricId: Long, evaluationId: Long): Map<Long, Long> {
        return db.appDatabaseQueries.selectStudentEvaluation(studentId, rubricId, evaluationId).executeAsList()
            .associate { it.criterion_id to it.level_id }
    }

    override suspend fun listCriteriaByRubric(rubricId: Long): List<RubricCriterion> {
        return db.appDatabaseQueries.selectCriteriaByRubric(rubricId).executeAsList().map {
            RubricCriterion(
                id = it.id,
                rubricId = it.rubric_id,
                description = it.description,
                weight = it.weight,
                order = it.sort_order.toInt(),
                trace = AuditTrace(
                    updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                    deviceId = it.device_id,
                    syncVersion = it.sync_version,
                )
            )
        }
    }

    override suspend fun listLevelsByCriterion(criterionId: Long): List<RubricLevel> {
        return db.appDatabaseQueries.selectLevelsByCriterion(criterionId).executeAsList().map {
            RubricLevel(
                id = it.id,
                criterionId = it.criterion_id,
                name = it.name,
                points = it.points.toInt(),
                description = it.description,
                order = it.sort_order.toInt(),
                trace = AuditTrace(
                    updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                    deviceId = it.device_id,
                    syncVersion = it.sync_version,
                )
            )
        }
    }
}

class AttendanceRepositorySqlDelight(
    private val db: AppDatabase,
) : AttendanceRepository {
    override fun observeAttendance(classId: Long): Flow<List<Attendance>> {
        return db.appDatabaseQueries
            .selectAttendanceByClass(classId)
            .asFlow()
            .mapToList(Dispatchers.Default)
            .map { rows ->
                rows.map {
                    Attendance(
                        id = it.id,
                        studentId = it.student_id,
                        classId = it.class_id,
                        date = Instant.fromEpochMilliseconds(it.date_epoch_ms),
                        status = it.status,
                        note = it.note,
                        hasIncident = it.has_incident != 0L,
                        followUpRequired = it.follow_up_required != 0L,
                        sessionId = it.session_id,
                        trace = AuditTrace(
                            updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                            deviceId = it.device_id,
                            syncVersion = it.sync_version
                        )
                    )
                }
            }
    }

    override fun observeAttendanceByDate(classId: Long, dateEpochMs: Long): Flow<List<Attendance>> {
        return db.appDatabaseQueries
            .selectAttendanceByClassAndDate(classId, dateEpochMs)
            .asFlow()
            .mapToList(Dispatchers.Default)
            .map { rows ->
                rows.map {
                    Attendance(
                        id = it.id,
                        studentId = it.student_id,
                        classId = it.class_id,
                        date = Instant.fromEpochMilliseconds(it.date_epoch_ms),
                        status = it.status,
                        note = it.note,
                        hasIncident = it.has_incident != 0L,
                        followUpRequired = it.follow_up_required != 0L,
                        sessionId = it.session_id,
                        trace = AuditTrace(
                            updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                            deviceId = it.device_id,
                            syncVersion = it.sync_version
                        )
                    )
                }
            }
    }

    override suspend fun listAttendance(classId: Long): List<Attendance> {
        return db.appDatabaseQueries.selectAttendanceByClass(classId).executeAsList().map {
            Attendance(
                id = it.id,
                studentId = it.student_id,
                classId = it.class_id,
                date = Instant.fromEpochMilliseconds(it.date_epoch_ms),
                status = it.status,
                note = it.note,
                hasIncident = it.has_incident != 0L,
                followUpRequired = it.follow_up_required != 0L,
                sessionId = it.session_id,
                trace = AuditTrace(
                    updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                    deviceId = it.device_id,
                    syncVersion = it.sync_version
                )
            )
        }
    }

    override suspend fun listAttendanceByDate(classId: Long, dateEpochMs: Long): List<Attendance> {
        return db.appDatabaseQueries.selectAttendanceByClassAndDate(classId, dateEpochMs).executeAsList().map {
            Attendance(
                id = it.id,
                studentId = it.student_id,
                classId = it.class_id,
                date = Instant.fromEpochMilliseconds(it.date_epoch_ms),
                status = it.status,
                trace = AuditTrace(
                    updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                    deviceId = it.device_id,
                    syncVersion = it.sync_version
                )
            )
        }
    }

    override suspend fun saveAttendance(
        id: Long?,
        studentId: Long,
        classId: Long,
        dateEpochMs: Long,
        status: String,
        note: String,
        hasIncident: Boolean,
        followUpRequired: Boolean,
        sessionId: Long?,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): Long {
        return db.transactionWithResult {
            db.appDatabaseQueries.upsertAttendance(
                id,
                studentId,
                classId,
                dateEpochMs,
                status,
                note,
                if (hasIncident) 1 else 0,
                if (followUpRequired) 1 else 0,
                sessionId,
                updatedAtEpochMs,
                deviceId,
                syncVersion
            )
            id ?: db.appDatabaseQueries.lastInsertedId().executeAsOne()
        }
    }

    override suspend fun getAttendanceForClassBetweenDates(classId: Long, startDateMs: Long, endDateMs: Long): List<Attendance> {
        return db.appDatabaseQueries.selectAttendanceForClassBetweenDates(classId, startDateMs, endDateMs).executeAsList().map {
            Attendance(
                id = it.id,
                studentId = it.student_id,
                classId = it.class_id,
                date = Instant.fromEpochMilliseconds(it.date_epoch_ms),
                status = it.status,
                note = it.note,
                hasIncident = it.has_incident != 0L,
                followUpRequired = it.follow_up_required != 0L,
                sessionId = it.session_id,
                trace = AuditTrace(
                    updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                    deviceId = it.device_id,
                    syncVersion = it.sync_version
                )
            )
        }
    }
}

class CompetenciesRepositorySqlDelight(
    private val db: AppDatabase,
) : CompetenciesRepository {
    override fun observeCompetencies(): Flow<List<CompetencyCriterion>> {
        return db.appDatabaseQueries
            .selectAllCompetencies()
            .asFlow()
            .mapToList(Dispatchers.Default)
            .map { rows ->
                rows.map {
                    CompetencyCriterion(
                        id = it.id,
                        code = it.code,
                        name = it.name,
                        description = it.description,
                        stageCycleId = it.stage_cycle_id,
                        trace = AuditTrace(
                            authorUserId = it.author_user_id,
                            createdAt = Instant.fromEpochMilliseconds(it.created_at_epoch_ms),
                            updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                            associatedGroupId = it.associated_group_id,
                            deviceId = it.device_id,
                            syncVersion = it.sync_version
                        ),
                    )
                }
            }
    }

    override suspend fun listCompetencies(): List<CompetencyCriterion> {
        return db.appDatabaseQueries.selectAllCompetencies().executeAsList().map {
            CompetencyCriterion(
                id = it.id,
                code = it.code,
                name = it.name,
                description = it.description,
                stageCycleId = it.stage_cycle_id,
                trace = AuditTrace(
                    authorUserId = it.author_user_id,
                    createdAt = Instant.fromEpochMilliseconds(it.created_at_epoch_ms),
                    updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                    associatedGroupId = it.associated_group_id,
                    deviceId = it.device_id,
                    syncVersion = it.sync_version
                ),
            )
        }
    }

    override suspend fun saveCompetency(
        id: Long?,
        code: String,
        name: String,
        description: String?,
        stageCycleId: Long?,
        authorUserId: Long?,
        associatedGroupId: Long?,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): Long {
        val now = if (updatedAtEpochMs > 0) updatedAtEpochMs else Clock.System.now().toEpochMilliseconds()
        return db.transactionWithResult {
            db.appDatabaseQueries.upsertCompetency(
                id,
                code,
                name,
                description,
                stageCycleId,
                authorUserId,
                now,
                now,
                associatedGroupId,
                deviceId,
                syncVersion,
            )
            id ?: db.appDatabaseQueries.lastInsertedId().executeAsOne()
        }
    }
}

class IncidentsRepositorySqlDelight(
    private val db: AppDatabase,
) : IncidentsRepository {
    override fun observeIncidents(classId: Long): Flow<List<Incident>> {
        return db.appDatabaseQueries
            .selectIncidentsByClass(classId)
            .asFlow()
            .mapToList(Dispatchers.Default)
            .map { rows ->
                rows.map {
                    Incident(
                        id = it.id,
                        classId = it.class_id,
                        studentId = it.student_id,
                        title = it.title,
                        detail = it.detail,
                        severity = it.severity,
                        date = Instant.fromEpochMilliseconds(it.date_epoch_ms),
                        trace = AuditTrace(
                            authorUserId = it.author_user_id,
                            createdAt = Instant.fromEpochMilliseconds(it.created_at_epoch_ms),
                            updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                            associatedGroupId = it.associated_group_id,
                            deviceId = it.device_id,
                            syncVersion = it.sync_version,
                        ),
                    )
                }
            }
    }

    override suspend fun listIncidents(classId: Long): List<Incident> {
        return db.appDatabaseQueries.selectIncidentsByClass(classId).executeAsList().map {
            Incident(
                id = it.id,
                classId = it.class_id,
                studentId = it.student_id,
                title = it.title,
                detail = it.detail,
                severity = it.severity,
                date = Instant.fromEpochMilliseconds(it.date_epoch_ms),
                trace = AuditTrace(
                    authorUserId = it.author_user_id,
                    createdAt = Instant.fromEpochMilliseconds(it.created_at_epoch_ms),
                    updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                    associatedGroupId = it.associated_group_id,
                    deviceId = it.device_id,
                    syncVersion = it.sync_version,
                ),
            )
        }
    }

    override suspend fun saveIncident(
        id: Long?,
        classId: Long,
        studentId: Long?,
        title: String,
        detail: String?,
        severity: String,
        dateEpochMs: Long,
        authorUserId: Long?,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): Long {
        val now = if (updatedAtEpochMs > 0) updatedAtEpochMs else Clock.System.now().toEpochMilliseconds()
        return db.transactionWithResult {
            db.appDatabaseQueries.upsertIncident(
                id,
                classId,
                studentId,
                title,
                detail,
                severity,
                dateEpochMs,
                authorUserId,
                now,
                now,
                classId,
                deviceId,
                syncVersion,
            )
            id ?: db.appDatabaseQueries.lastInsertedId().executeAsOne()
        }
    }
}

class CalendarRepositorySqlDelight(
    private val db: AppDatabase,
) : CalendarRepository {
    override fun observeEvents(classId: Long?): Flow<List<CalendarEvent>> {
        return if (classId == null) {
            db.appDatabaseQueries.selectAllEvents().asFlow().mapToList(Dispatchers.Default).map { rows ->
                rows.map {
                    CalendarEvent(
                        id = it.id,
                        classId = it.class_id,
                        title = it.title,
                        description = it.description,
                        startAt = Instant.fromEpochMilliseconds(it.start_epoch_ms),
                        endAt = Instant.fromEpochMilliseconds(it.end_epoch_ms),
                        externalProvider = it.external_provider,
                        externalId = it.external_id,
                        trace = AuditTrace(
                            authorUserId = it.author_user_id,
                            createdAt = Instant.fromEpochMilliseconds(it.created_at_epoch_ms),
                            updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                            associatedGroupId = it.associated_group_id,
                        ),
                    )
                }
            }
        } else {
            db.appDatabaseQueries.selectEventsByClass(classId).asFlow().mapToList(Dispatchers.Default).map { rows ->
                rows.map {
                    CalendarEvent(
                        id = it.id,
                        classId = it.class_id,
                        title = it.title,
                        description = it.description,
                        startAt = Instant.fromEpochMilliseconds(it.start_epoch_ms),
                        endAt = Instant.fromEpochMilliseconds(it.end_epoch_ms),
                        externalProvider = it.external_provider,
                        externalId = it.external_id,
                        trace = AuditTrace(
                            authorUserId = it.author_user_id,
                            createdAt = Instant.fromEpochMilliseconds(it.created_at_epoch_ms),
                            updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                            associatedGroupId = it.associated_group_id,
                            deviceId = it.device_id,
                            syncVersion = it.sync_version
                        ),
                    )
                }
            }
        }
    }

    override suspend fun listEvents(classId: Long?): List<CalendarEvent> {
        return if (classId == null) {
            db.appDatabaseQueries.selectAllEvents().executeAsList().map {
                CalendarEvent(
                    id = it.id,
                    classId = it.class_id,
                    title = it.title,
                    description = it.description,
                    startAt = Instant.fromEpochMilliseconds(it.start_epoch_ms),
                    endAt = Instant.fromEpochMilliseconds(it.end_epoch_ms),
                    externalProvider = it.external_provider,
                    externalId = it.external_id,
                    trace = AuditTrace(
                        authorUserId = it.author_user_id,
                        createdAt = Instant.fromEpochMilliseconds(it.created_at_epoch_ms),
                        updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                        associatedGroupId = it.associated_group_id,
                        deviceId = it.device_id,
                        syncVersion = it.sync_version
                    ),
                )
            }
        } else {
            db.appDatabaseQueries.selectEventsByClass(classId).executeAsList().map {
                CalendarEvent(
                    id = it.id,
                    classId = it.class_id,
                    title = it.title,
                    description = it.description,
                    startAt = Instant.fromEpochMilliseconds(it.start_epoch_ms),
                    endAt = Instant.fromEpochMilliseconds(it.end_epoch_ms),
                    externalProvider = it.external_provider,
                    externalId = it.external_id,
                    trace = AuditTrace(
                        authorUserId = it.author_user_id,
                        createdAt = Instant.fromEpochMilliseconds(it.created_at_epoch_ms),
                        updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                        associatedGroupId = it.associated_group_id,
                        deviceId = it.device_id,
                        syncVersion = it.sync_version
                    ),
                )
            }
        }
    }

    override suspend fun saveEvent(
        id: Long?,
        classId: Long?,
        title: String,
        description: String?,
        startEpochMs: Long,
        endEpochMs: Long,
        externalProvider: String?,
        externalId: String?,
        authorUserId: Long?,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): Long {
        val now = if (updatedAtEpochMs > 0) updatedAtEpochMs else Clock.System.now().toEpochMilliseconds()
        return db.transactionWithResult {
            db.appDatabaseQueries.upsertEvent(
                id,
                classId,
                title,
                description,
                startEpochMs,
                endEpochMs,
                externalProvider,
                externalId,
                authorUserId,
                now,
                now,
                classId,
                deviceId,
                syncVersion,
            )
            id ?: db.appDatabaseQueries.lastInsertedId().executeAsOne()
        }
    }
}

class ConfigurationTemplateRepositorySqlDelight(
    private val db: AppDatabase,
) : ConfigurationTemplateRepository {
    override fun observeTemplates(): Flow<List<ConfigTemplate>> {
        return db.appDatabaseQueries.selectAllConfigTemplates()
            .asFlow()
            .mapToList(Dispatchers.Default)
            .map { rows ->
                rows.map {
                    ConfigTemplate(
                        id = it.id,
                        centerId = it.center_id,
                        ownerUserId = it.owner_user_id,
                        name = it.name,
                        kind = ConfigTemplateKind.valueOf(it.kind),
                        trace = AuditTrace(
                            authorUserId = it.author_user_id,
                            createdAt = Instant.fromEpochMilliseconds(it.created_at_epoch_ms),
                            updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                            associatedGroupId = it.associated_group_id,
                            deviceId = it.device_id,
                            syncVersion = it.sync_version,
                        ),
                    )
                }
            }
    }

    override suspend fun listTemplates(kind: ConfigTemplateKind?): List<ConfigTemplate> {
        val rows = if (kind == null) {
            db.appDatabaseQueries.selectAllConfigTemplates().executeAsList()
        } else {
            db.appDatabaseQueries.selectTemplatesByKind(kind.name).executeAsList()
        }
        return rows.map {
            ConfigTemplate(
                id = it.id,
                centerId = it.center_id,
                ownerUserId = it.owner_user_id,
                name = it.name,
                kind = ConfigTemplateKind.valueOf(it.kind),
                trace = AuditTrace(
                    authorUserId = it.author_user_id,
                    createdAt = Instant.fromEpochMilliseconds(it.created_at_epoch_ms),
                    updatedAt = Instant.fromEpochMilliseconds(it.updated_at_epoch_ms),
                    associatedGroupId = it.associated_group_id,
                    deviceId = it.device_id,
                    syncVersion = it.sync_version,
                ),
            )
        }
    }

    override suspend fun saveTemplate(
        id: Long?,
        centerId: Long?,
        ownerUserId: Long,
        name: String,
        kind: ConfigTemplateKind,
        authorUserId: Long?,
        associatedGroupId: Long?,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): Long {
        val now = if (updatedAtEpochMs > 0) updatedAtEpochMs else Clock.System.now().toEpochMilliseconds()
        return db.transactionWithResult {
            db.appDatabaseQueries.upsertConfigTemplate(
                id,
                centerId,
                ownerUserId,
                name,
                kind.name,
                authorUserId,
                now,
                now,
                associatedGroupId,
                deviceId,
                syncVersion,
            )
            id ?: db.appDatabaseQueries.lastInsertedId().executeAsOne()
        }
    }

    override suspend fun saveTemplateVersion(
        id: Long?,
        templateId: Long,
        payloadJson: String,
        basedOnVersionId: Long?,
        sourceAcademicYearId: Long?,
        authorUserId: Long?,
        associatedGroupId: Long?,
        updatedAtEpochMs: Long,
        deviceId: String?,
        syncVersion: Long,
    ): Long {
        val now = if (updatedAtEpochMs > 0) updatedAtEpochMs else Clock.System.now().toEpochMilliseconds()
        val nextVersion = db.appDatabaseQueries.nextConfigTemplateVersion(templateId).executeAsOne().toInt()
        return db.transactionWithResult {
            db.appDatabaseQueries.upsertConfigTemplateVersion(
                id,
                templateId,
                nextVersion.toLong(),
                payloadJson,
                basedOnVersionId,
                sourceAcademicYearId,
                authorUserId,
                now,
                now,
                associatedGroupId,
                deviceId,
                syncVersion,
            )
            id ?: db.appDatabaseQueries.lastInsertedId().executeAsOne()
        }
    }

    override suspend fun listTemplateVersions(templateId: Long): List<ConfigTemplateVersion> {
        return db.appDatabaseQueries.selectConfigTemplateVersions(templateId).executeAsList().map { row ->
            ConfigTemplateVersion(
                id = row.id,
                templateId = row.template_id,
                versionNumber = row.version_number.toInt(),
                payloadJson = row.payload_json,
                basedOnVersionId = row.based_on_version_id,
                sourceAcademicYearId = row.source_academic_year_id,
                trace = AuditTrace(
                    authorUserId = row.author_user_id,
                    createdAt = Instant.fromEpochMilliseconds(row.created_at_epoch_ms),
                    updatedAt = Instant.fromEpochMilliseconds(row.updated_at_epoch_ms),
                    associatedGroupId = row.associated_group_id,
                    deviceId = row.device_id,
                    syncVersion = row.sync_version,
                ),
            )
        }
    }

    override suspend fun cloneLatestVersionToTemplate(
        sourceTemplateId: Long,
        targetTemplateId: Long,
        sourceAcademicYearId: Long?,
        authorUserId: Long?,
    ): Long {
        val latest = db.appDatabaseQueries.selectLatestConfigTemplateVersion(sourceTemplateId).executeAsOne()
        return saveTemplateVersion(
            templateId = targetTemplateId,
            payloadJson = latest.payload_json,
            basedOnVersionId = latest.id,
            sourceAcademicYearId = sourceAcademicYearId ?: latest.source_academic_year_id,
            authorUserId = authorUserId,
            associatedGroupId = latest.associated_group_id,
        )
    }
}

class DashboardRepositorySqlDelight(
    private val db: AppDatabase,
) : DashboardRepository {
    override fun observeStats(): Flow<DashboardStats> {
        return db.appDatabaseQueries
            .selectDashboardStats()
            .asFlow()
            .mapToOne(Dispatchers.Default)
            .map {
                DashboardStats(
                    totalStudents = it.total_students.toInt(),
                    totalClasses = it.total_classes.toInt(),
                    totalEvaluations = it.total_evaluations.toInt(),
                    totalRubrics = it.total_rubrics.toInt(),
                    totalSessions = it.total_sessions.toInt(),
                )
            }
    }

    override suspend fun getStats(): DashboardStats {
        val row = db.appDatabaseQueries.selectDashboardStats().executeAsOne()
        return DashboardStats(
            totalStudents = row.total_students.toInt(),
            totalClasses = row.total_classes.toInt(),
            totalEvaluations = row.total_evaluations.toInt(),
            totalRubrics = row.total_rubrics.toInt(),
            totalSessions = row.total_sessions.toInt(),
        )
    }
}

class BackupMetadataRepositorySqlDelight(
    private val db: AppDatabase,
) : BackupMetadataRepository {
    override fun observeBackups(): Flow<List<BackupEntry>> {
        return db.appDatabaseQueries
            .selectBackupEntries()
            .asFlow()
            .mapToList(Dispatchers.Default)
            .map { rows ->
                rows.map {
                    BackupEntry(
                        id = it.id,
                        path = it.path,
                        createdAt = Instant.fromEpochMilliseconds(it.created_at_epoch_ms),
                        platform = it.platform,
                        sizeBytes = it.size_bytes,
                    )
                }
            }
    }

    override suspend fun listBackups(): List<BackupEntry> {
        return db.appDatabaseQueries.selectBackupEntries().executeAsList().map {
            BackupEntry(
                id = it.id,
                path = it.path,
                createdAt = Instant.fromEpochMilliseconds(it.created_at_epoch_ms),
                platform = it.platform,
                sizeBytes = it.size_bytes,
            )
        }
    }

    override suspend fun saveBackup(path: String, createdAtEpochMs: Long, platform: String, sizeBytes: Long): Long {
        return db.transactionWithResult {
            db.appDatabaseQueries.insertBackupEntry(path, createdAtEpochMs, platform, sizeBytes)
            db.appDatabaseQueries.lastInsertedId().executeAsOne()
        }
    }

    override suspend fun deleteBackup(id: Long) {
        db.appDatabaseQueries.deleteBackupEntry(id)
    }
}


private fun buildRubrics(
    rubrics: List<Rubric>,
    criteria: List<RubricCriterion>,
    levels: List<RubricLevel>,
): List<RubricDetail> {
    val levelsByCriterion = levels.groupBy { it.criterionId }
    val criteriaByRubric = criteria.groupBy { it.rubricId }

    return rubrics.map { rubric ->
        RubricDetail(
            rubric = rubric,
            criteria = criteriaByRubric[rubric.id].orEmpty().map { criterion ->
                RubricCriterionWithLevels(
                    criterion = criterion,
                    levels = levelsByCriterion[criterion.id].orEmpty(),
                )
            },
        )
    }
}
