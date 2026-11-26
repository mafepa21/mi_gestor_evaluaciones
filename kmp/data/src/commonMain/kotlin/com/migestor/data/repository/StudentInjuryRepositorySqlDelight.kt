package com.migestor.data.repository

import com.migestor.data.db.AppDatabase
import com.migestor.data.db.Student_injuries
import com.migestor.shared.domain.AuditTrace
import com.migestor.shared.injury.InjuryRole
import com.migestor.shared.injury.StudentInjury
import com.migestor.shared.injury.StudentInjuryRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate

/**
 * Lesiones con fecha (migración 51). Viajan por Sync LAN con `SchoolRecordsSync`.
 * Una fila con una fecha ilegible se salta al leer en vez de romper la lista entera.
 */
class StudentInjuryRepositorySqlDelight(
    private val db: AppDatabase,
) : StudentInjuryRepository {

    private val q get() = db.studentInjuryQueries

    override suspend fun listAll(): List<StudentInjury> = withContext(Dispatchers.Default) {
        q.selectAllInjuries().executeAsList().mapNotNull(::toInjury)
    }

    override suspend fun listByStudent(studentId: Long): List<StudentInjury> = withContext(Dispatchers.Default) {
        q.selectInjuriesByStudent(studentId).executeAsList().mapNotNull(::toInjury)
    }

    override suspend fun get(id: String): StudentInjury? = withContext(Dispatchers.Default) {
        q.selectInjury(id).executeAsOneOrNull()?.let(::toInjury)
    }

    override suspend fun save(injury: StudentInjury) = withContext(Dispatchers.Default) {
        q.upsertInjury(
            id = injury.id,
            student_id = injury.studentId,
            starts_on = injury.startsOn.toString(),
            ends_on = injury.endsOn?.toString(),
            alternate_role = injury.role.name,
            note = injury.note,
            proof_delivered = if (injury.proofDelivered) 1L else 0L,
            is_deleted = if (injury.isDeleted) 1L else 0L,
            created_at_epoch_ms = injury.trace.createdAt.toEpochMilliseconds(),
            updated_at_epoch_ms = injury.trace.updatedAt.toEpochMilliseconds(),
            device_id = injury.trace.deviceId,
            sync_version = injury.trace.syncVersion,
        )
    }

    override suspend fun hardDelete(id: String) = withContext(Dispatchers.Default) {
        q.deleteInjury(id)
        Unit
    }

    override suspend fun listFlaggedStudentIds(): Set<Long> = withContext(Dispatchers.Default) {
        q.selectFlaggedStudentIds().executeAsList().toSet()
    }

    override suspend fun setInjuredFlag(studentId: Long, isInjured: Boolean) = withContext(Dispatchers.Default) {
        q.setStudentInjuredFlag(if (isInjured) 1L else 0L, studentId)
        Unit
    }

    private fun toInjury(row: Student_injuries): StudentInjury? {
        val startsOn = runCatching { LocalDate.parse(row.starts_on) }.getOrNull() ?: return null
        val endsOn = row.ends_on?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
        return StudentInjury(
            id = row.id,
            studentId = row.student_id,
            startsOn = startsOn,
            endsOn = endsOn,
            role = InjuryRole.fromStorage(row.alternate_role),
            note = row.note,
            proofDelivered = row.proof_delivered != 0L,
            isDeleted = row.is_deleted != 0L,
            trace = AuditTrace(
                createdAt = Instant.fromEpochMilliseconds(row.created_at_epoch_ms),
                updatedAt = Instant.fromEpochMilliseconds(row.updated_at_epoch_ms),
                deviceId = row.device_id,
                syncVersion = row.sync_version,
            ),
        )
    }
}
