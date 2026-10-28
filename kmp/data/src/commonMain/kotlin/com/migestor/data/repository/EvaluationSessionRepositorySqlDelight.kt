package com.migestor.data.repository

import com.migestor.data.db.AppDatabase
import com.migestor.data.db.Evaluation_sessions
import com.migestor.data.db.SelectSessionStudents
import com.migestor.shared.domain.SupportMeasureLevel
import com.migestor.shared.evaluationsession.EvaluationKind
import com.migestor.shared.evaluationsession.EvaluationSession
import com.migestor.shared.evaluationsession.EvaluationSessionClosedException
import com.migestor.shared.evaluationsession.EvaluationSessionDuplicateException
import com.migestor.shared.evaluationsession.EvaluationSessionException
import com.migestor.shared.evaluationsession.EvaluationSessionNotFoundException
import com.migestor.shared.evaluationsession.EvaluationSessionRepository
import com.migestor.shared.evaluationsession.EvaluationSessionStudentRecord
import com.migestor.shared.evaluationsession.EvaluationSessionStudentSnapshot
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Juntas de evaluación (migración 47). Sin SyncLAN en la primera versión.
 *
 * En producción `PRAGMA foreign_keys` está apagado: las cascadas del esquema no
 * corren. Por eso el borrado es explícito y las filas se leen con INNER JOIN students.
 */
class EvaluationSessionRepositorySqlDelight(
    private val db: AppDatabase,
) : EvaluationSessionRepository {

    private val q get() = db.evaluationSessionQueries

    override suspend fun listSessions(classId: Long): List<EvaluationSession> = withContext(Dispatchers.Default) {
        q.selectSessionsByClass(classId).executeAsList().mapNotNull(::toSession)
    }

    override suspend fun getSession(id: String): EvaluationSession? = withContext(Dispatchers.Default) {
        q.selectSessionById(id).executeAsOneOrNull()?.let(::toSession)
    }

    override suspend fun insertSession(session: EvaluationSession) = withContext(Dispatchers.Default) {
        db.transaction {
            // Comprobación previa para dar un error claro; el índice único es la red de seguridad.
            val exists = q.selectSessionsByClass(session.classId).executeAsList()
                .any { it.evaluation_kind == session.kind.name }
            if (exists) throw EvaluationSessionDuplicateException(session.kind)
            q.insertSession(
                session.id,
                session.classId,
                session.kind.name,
                session.label,
                session.plannerEvaluationPeriodId,
                session.dateIso,
                session.attendees,
                session.generalAgreements,
                session.createdAtEpochMs,
                session.updatedAtEpochMs,
                session.deviceId,
            )
        }
    }

    override suspend fun updateHeader(
        id: String,
        label: String,
        plannerEvaluationPeriodId: Long?,
        dateIso: String,
        attendees: String,
        generalAgreements: String,
        nowEpochMs: Long,
    ) = withContext(Dispatchers.Default) {
        db.transaction {
            q.updateSessionHeader(label, plannerEvaluationPeriodId, dateIso, attendees, generalAgreements, nowEpochMs, id)
            if (changes() == 0L) throw failureFor(id)
        }
    }

    override suspend fun closeSession(
        id: String,
        snapshots: List<EvaluationSessionStudentSnapshot>,
        nowEpochMs: Long,
    ) = withContext(Dispatchers.Default) {
        db.transaction {
            val session = q.selectSessionById(id).executeAsOneOrNull() ?: throw EvaluationSessionNotFoundException(id)
            if (session.is_closed != 0L) throw EvaluationSessionClosedException()
            for (snapshot in snapshots) {
                q.freezeSessionStudent(
                    snapshot.average,
                    snapshot.ownFailed?.let { if (it) 1L else 0L },
                    snapshot.absencePercent,
                    snapshot.absenceCount?.toLong(),
                    snapshot.supportLevel?.name,
                    snapshot.incidentCount?.toLong(),
                    nowEpochMs,
                    id,
                    snapshot.studentId,
                )
            }
            q.closeSession(closedAt = nowEpochMs, id = id)
        }
    }

    override suspend fun reopenSession(id: String, nowEpochMs: Long) = withContext(Dispatchers.Default) {
        db.transaction {
            val session = q.selectSessionById(id).executeAsOneOrNull() ?: throw EvaluationSessionNotFoundException(id)
            if (session.is_closed != 0L) q.reopenSession(nowEpochMs, id)
        }
    }

    override suspend fun deleteSession(id: String) = withContext(Dispatchers.Default) {
        db.transaction {
            q.deleteSessionStudents(id)
            q.deleteSession(id)
        }
    }

    override suspend fun listStudents(sessionId: String): List<EvaluationSessionStudentRecord> =
        withContext(Dispatchers.Default) {
            q.selectSessionStudents(sessionId).executeAsList().map(::toRecord)
        }

    override suspend fun ensureStudents(sessionId: String, studentIds: List<Long>, nowEpochMs: Long): Int =
        withContext(Dispatchers.Default) {
            if (studentIds.isEmpty()) return@withContext 0
            db.transactionWithResult {
                var created = 0
                for (studentId in studentIds.distinct()) {
                    q.insertSessionStudentIfMissing(sessionId, studentId, nowEpochMs, nowEpochMs)
                    if (changes() > 0L) created++
                }
                created
            }
        }

    override suspend fun updateStudent(
        sessionId: String,
        studentId: Long,
        otherFailedCount: Int,
        agreement: String,
        isReviewed: Boolean,
        nowEpochMs: Long,
    ) = withContext(Dispatchers.Default) {
        db.transaction {
            q.updateSessionStudentEditable(
                otherFailedCount.toLong(),
                agreement,
                if (isReviewed) 1L else 0L,
                nowEpochMs,
                sessionId,
                studentId,
            )
            if (changes() == 0L) {
                val failure = failureFor(sessionId)
                throw if (failure is EvaluationSessionClosedException) failure
                else EvaluationSessionException("El alumno $studentId no está en esta junta.")
            }
        }
    }

    private fun changes(): Long = q.evaluationSessionChanges().executeAsOne()

    /** Motivo por el que una edición no ha tocado ninguna fila. */
    private fun failureFor(id: String): EvaluationSessionException {
        val session = q.selectSessionById(id).executeAsOneOrNull() ?: return EvaluationSessionNotFoundException(id)
        return if (session.is_closed != 0L) EvaluationSessionClosedException()
        else EvaluationSessionException("No se ha podido guardar la junta.")
    }

    /** `null` si la evaluación guardada ya no existe en el enum: se descarta en vez de lanzar. */
    private fun toSession(row: Evaluation_sessions): EvaluationSession? {
        val kind = runCatching { EvaluationKind.valueOf(row.evaluation_kind) }.getOrNull() ?: return null
        return EvaluationSession(
            id = row.id,
            classId = row.class_id,
            kind = kind,
            label = row.evaluation_label,
            plannerEvaluationPeriodId = row.planner_evaluation_period_id,
            dateIso = row.date_iso,
            attendees = row.attendees,
            generalAgreements = row.general_agreements,
            isClosed = row.is_closed != 0L,
            closedAtEpochMs = row.closed_at_epoch_ms,
            createdAtEpochMs = row.created_at_epoch_ms,
            updatedAtEpochMs = row.updated_at_epoch_ms,
            deviceId = row.device_id,
            syncVersion = row.sync_version,
        )
    }

    private fun toRecord(row: SelectSessionStudents): EvaluationSessionStudentRecord =
        EvaluationSessionStudentRecord(
            sessionId = row.session_id,
            studentId = row.student_id,
            firstName = row.first_name,
            lastName = row.last_name,
            otherFailedCount = row.other_failed_count.toInt(),
            agreement = row.agreement,
            isReviewed = row.is_reviewed != 0L,
            frozenAverage = row.frozen_average,
            frozenOwnFailed = row.frozen_own_failed?.let { it != 0L },
            frozenAbsencePercent = row.frozen_absence_percent,
            frozenAbsenceCount = row.frozen_absence_count?.toInt(),
            // Solo III/IV; cualquier otro valor se ignora.
            frozenSupportLevel = row.frozen_support_level?.let { level ->
                SupportMeasureLevel.entries.firstOrNull { it.name == level }
            },
            frozenIncidentCount = row.frozen_incident_count?.toInt(),
            createdAtEpochMs = row.created_at_epoch_ms,
            updatedAtEpochMs = row.updated_at_epoch_ms,
        )
}
