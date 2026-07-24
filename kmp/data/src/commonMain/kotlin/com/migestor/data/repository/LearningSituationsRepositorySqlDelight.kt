package com.migestor.data.repository

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import com.migestor.data.db.AppDatabase
import com.migestor.data.db.Learning_situations
import com.migestor.shared.domain.AuditTrace
import com.migestor.shared.domain.LearningSituation
import com.migestor.shared.domain.LearningSituationClassLink
import com.migestor.shared.domain.LearningSituationLinkedResource
import com.migestor.shared.domain.LearningSituationResourceKind
import com.migestor.shared.domain.LearningSituationSessionPlan
import com.migestor.shared.domain.LearningSituationSessionSequenceVersion
import com.migestor.shared.domain.LearningSituationStatus
import com.migestor.shared.domain.LearningSituationVersion
import com.migestor.shared.repository.LearningSituationsRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

class LearningSituationsRepositorySqlDelight(
    private val db: AppDatabase,
) : LearningSituationsRepository {
    override fun observeSituations(): Flow<List<LearningSituation>> =
        db.appDatabaseQueries.selectAllLearningSituations()
            .asFlow()
            .mapToList(Dispatchers.Default)
            .map { rows -> rows.map(::toSituation) }

    override suspend fun listSituations(): List<LearningSituation> = withContext(Dispatchers.Default) {
        db.appDatabaseQueries.selectAllLearningSituations().executeAsList().map(::toSituation)
    }

    override suspend fun getSituation(id: Long): LearningSituation? = withContext(Dispatchers.Default) {
        db.appDatabaseQueries.selectLearningSituationById(id).executeAsOneOrNull()?.let(::toSituation)
    }

    override suspend fun saveSituation(situation: LearningSituation): Long = withContext(Dispatchers.Default) {
        val now = Clock.System.now().toEpochMilliseconds()
        val createdAt = if (situation.id == 0L) now else situation.trace.createdAt.toEpochMilliseconds()
        db.transactionWithResult {
            db.appDatabaseQueries.upsertLearningSituation(
                if (situation.id == 0L) null else situation.id,
                situation.title,
                situation.stageLabel,
                situation.courseLabel,
                situation.subjectLabel,
                situation.termLabel,
                situation.centerLabel,
                situation.sessionCount.toLong(),
                situation.challenge,
                situation.finalProduct,
                situation.payloadJson,
                situation.status.name,
                createdAt,
                now,
                situation.trace.deviceId,
                situation.trace.syncVersion,
            )
            if (situation.id == 0L) db.appDatabaseQueries.lastInsertedId().executeAsOne() else situation.id
        }
    }

    override suspend fun saveVersion(version: LearningSituationVersion): Long = withContext(Dispatchers.Default) {
        val now = Clock.System.now().toEpochMilliseconds()
        val nextVersion = if (version.id == 0L && version.versionNumber == 0) {
            db.appDatabaseQueries.nextLearningSituationVersion(version.learningSituationId).executeAsOne().toInt()
        } else {
            version.versionNumber
        }
        db.transactionWithResult {
            db.appDatabaseQueries.upsertLearningSituationVersion(
                if (version.id == 0L) null else version.id,
                version.learningSituationId,
                nextVersion.toLong(),
                version.originalFileName,
                version.sha256,
                version.localPath,
                version.sizeBytes,
                version.payloadJson,
                version.warningsJson,
                if (version.id == 0L) now else version.trace.createdAt.toEpochMilliseconds(),
                now,
                version.trace.deviceId,
                version.trace.syncVersion,
            )
            if (version.id == 0L) db.appDatabaseQueries.lastInsertedId().executeAsOne() else version.id
        }
    }

    override suspend fun listVersions(learningSituationId: Long): List<LearningSituationVersion> = withContext(Dispatchers.Default) {
        db.appDatabaseQueries.selectLearningSituationVersions(learningSituationId).executeAsList().map { row ->
            LearningSituationVersion(
                id = row.id,
                learningSituationId = row.learning_situation_id,
                versionNumber = row.version_number.toInt(),
                originalFileName = row.original_file_name,
                sha256 = row.sha256,
                localPath = row.local_path,
                sizeBytes = row.size_bytes,
                payloadJson = row.payload_json,
                warningsJson = row.warnings_json,
                trace = trace(row.created_at_epoch_ms, row.updated_at_epoch_ms, row.device_id, row.sync_version),
            )
        }
    }

    override suspend fun saveSessionSequenceVersion(version: LearningSituationSessionSequenceVersion): Long = withContext(Dispatchers.Default) {
        val now = Clock.System.now().toEpochMilliseconds()
        val nextVersion = if (version.id == 0L && version.versionNumber == 0) {
            db.appDatabaseQueries.nextLearningSituationSequenceVersion(version.learningSituationId).executeAsOne().toInt()
        } else {
            version.versionNumber
        }
        db.transactionWithResult {
            db.appDatabaseQueries.upsertLearningSituationSequenceVersion(
                if (version.id == 0L) null else version.id,
                version.learningSituationId,
                nextVersion.toLong(),
                version.originalFileName,
                version.sha256,
                version.localPath,
                version.sizeBytes,
                version.payloadJson,
                version.warningsJson,
                if (version.id == 0L) now else version.trace.createdAt.toEpochMilliseconds(),
                now,
                version.trace.deviceId,
                version.trace.syncVersion,
            )
            if (version.id == 0L) db.appDatabaseQueries.lastInsertedId().executeAsOne() else version.id
        }
    }

    override suspend fun listSessionSequenceVersions(learningSituationId: Long): List<LearningSituationSessionSequenceVersion> =
        withContext(Dispatchers.Default) {
            db.appDatabaseQueries.selectLearningSituationSequenceVersions(learningSituationId).executeAsList().map { row ->
                LearningSituationSessionSequenceVersion(
                    id = row.id,
                    learningSituationId = row.learning_situation_id,
                    versionNumber = row.version_number.toInt(),
                    originalFileName = row.original_file_name,
                    sha256 = row.sha256,
                    localPath = row.local_path,
                    sizeBytes = row.size_bytes,
                    payloadJson = row.payload_json,
                    warningsJson = row.warnings_json,
                    trace = trace(row.created_at_epoch_ms, row.updated_at_epoch_ms, row.device_id, row.sync_version),
                )
            }
        }

    override suspend fun saveSessionPlan(plan: LearningSituationSessionPlan): Long = withContext(Dispatchers.Default) {
        val now = Clock.System.now().toEpochMilliseconds()
        db.transactionWithResult {
            db.appDatabaseQueries.upsertLearningSituationSessionPlan(
                if (plan.id == 0L) null else plan.id,
                plan.learningSituationId,
                plan.sequenceVersionId,
                plan.sessionNumber.toLong(),
                plan.sourceLabel,
                plan.title,
                plan.sessionType,
                plan.effectiveMinutes.toLong(),
                plan.objective,
                plan.criteriaJson,
                plan.material,
                plan.developmentJson,
                plan.adaptationsJson,
                if (plan.id == 0L) now else plan.trace.createdAt.toEpochMilliseconds(),
                now,
                plan.trace.deviceId,
                plan.trace.syncVersion,
            )
            if (plan.id == 0L) db.appDatabaseQueries.lastInsertedId().executeAsOne() else plan.id
        }
    }

    override suspend fun listSessionPlans(sequenceVersionId: Long): List<LearningSituationSessionPlan> = withContext(Dispatchers.Default) {
        db.appDatabaseQueries.selectLearningSituationSessionPlans(sequenceVersionId).executeAsList().map(::toSessionPlan)
    }

    override suspend fun getSessionPlan(id: Long): LearningSituationSessionPlan? = withContext(Dispatchers.Default) {
        db.appDatabaseQueries.selectLearningSituationSessionPlanById(id).executeAsOneOrNull()?.let(::toSessionPlan)
    }

    override suspend fun replaceClassLinks(learningSituationId: Long, classIds: List<Long>) = withContext(Dispatchers.Default) {
        val now = Clock.System.now().toEpochMilliseconds()
        db.transaction {
            db.appDatabaseQueries.deleteLearningSituationClassLinks(learningSituationId)
            classIds.distinct().forEach { classId ->
                db.appDatabaseQueries.upsertLearningSituationClassLink(
                    learningSituationId,
                    classId,
                    now,
                    now,
                    null,
                    0,
                )
            }
        }
    }

    override suspend fun listClassLinks(learningSituationId: Long): List<LearningSituationClassLink> = withContext(Dispatchers.Default) {
        db.appDatabaseQueries.selectLearningSituationClassLinks(learningSituationId).executeAsList().map { row ->
            LearningSituationClassLink(
                learningSituationId = row.learning_situation_id,
                classId = row.class_id,
                trace = trace(row.created_at_epoch_ms, row.updated_at_epoch_ms, row.device_id, row.sync_version),
            )
        }
    }

    override suspend fun saveLinkedResource(resource: LearningSituationLinkedResource): Long = withContext(Dispatchers.Default) {
        val now = Clock.System.now().toEpochMilliseconds()
        db.transactionWithResult {
            // class_id es nullable y SQLite no considera dos NULL iguales a efectos de un
            // UNIQUE/ON CONFLICT, así que el upsert por clave de negocio se resuelve aquí
            // (select-then-insert-or-update) en vez de delegarlo a un ON CONFLICT en SQL:
            // con class_id NULL, un ON CONFLICT nunca dispara y cada guardado insertaría
            // una fila duplicada.
            val existingId = if (resource.id != 0L) {
                resource.id
            } else {
                db.appDatabaseQueries.selectLearningSituationLinkId(
                    resource.learningSituationId,
                    resource.kind.name,
                    resource.resourceId,
                    resource.classId,
                ).executeAsOneOrNull()
            }
            if (existingId != null) {
                db.appDatabaseQueries.updateLearningSituationLink(
                    resource.label,
                    now,
                    resource.trace.deviceId,
                    existingId,
                )
                existingId
            } else {
                db.appDatabaseQueries.upsertLearningSituationLink(
                    null,
                    resource.learningSituationId,
                    resource.kind.name,
                    resource.resourceId,
                    resource.classId,
                    resource.label,
                    now,
                    now,
                    resource.trace.deviceId,
                    resource.trace.syncVersion,
                )
                db.appDatabaseQueries.lastInsertedId().executeAsOne()
            }
        }
    }

    override suspend fun listLinkedResources(learningSituationId: Long): List<LearningSituationLinkedResource> = withContext(Dispatchers.Default) {
        db.appDatabaseQueries.selectLearningSituationLinks(learningSituationId).executeAsList().map { row ->
            LearningSituationLinkedResource(
                id = row.id,
                learningSituationId = row.learning_situation_id,
                kind = runCatching { LearningSituationResourceKind.valueOf(row.resource_kind) }.getOrDefault(LearningSituationResourceKind.TEACHING_UNIT),
                resourceId = row.resource_id,
                classId = row.class_id,
                label = row.label,
                trace = trace(row.created_at_epoch_ms, row.updated_at_epoch_ms, row.device_id, row.sync_version),
            )
        }
    }

    override suspend fun deleteSituation(id: Long) = withContext(Dispatchers.Default) {
        db.appDatabaseQueries.deleteLearningSituation(id)
    }

    private fun toSituation(row: Learning_situations): LearningSituation =


        LearningSituation(
            id = row.id,
            title = row.title,
            stageLabel = row.stage_label,
            courseLabel = row.course_label,
            subjectLabel = row.subject_label,
            termLabel = row.term_label,
            centerLabel = row.center_label,
            sessionCount = row.session_count.toInt(),
            challenge = row.challenge,
            finalProduct = row.final_product,
            payloadJson = row.payload_json,
            status = runCatching { LearningSituationStatus.valueOf(row.status) }.getOrDefault(LearningSituationStatus.DRAFT),
            trace = trace(row.created_at_epoch_ms, row.updated_at_epoch_ms, row.device_id, row.sync_version),
        )

    private fun toSessionPlan(row: com.migestor.data.db.Learning_situation_session_plans): LearningSituationSessionPlan =
        LearningSituationSessionPlan(
            id = row.id,
            learningSituationId = row.learning_situation_id,
            sequenceVersionId = row.sequence_version_id,
            sessionNumber = row.session_number.toInt(),
            sourceLabel = row.source_label,
            title = row.title,
            sessionType = row.session_type,
            effectiveMinutes = row.effective_minutes.toInt(),
            objective = row.objective,
            criteriaJson = row.criteria_json,
            material = row.material,
            developmentJson = row.development_json,
            adaptationsJson = row.adaptations_json,
            trace = trace(row.created_at_epoch_ms, row.updated_at_epoch_ms, row.device_id, row.sync_version),
        )

    private fun trace(createdAt: Long, updatedAt: Long, deviceId: String?, syncVersion: Long) = AuditTrace(
        createdAt = Instant.fromEpochMilliseconds(createdAt),
        updatedAt = Instant.fromEpochMilliseconds(updatedAt),
        deviceId = deviceId,
        syncVersion = syncVersion,
    )
}
