package com.migestor.data.repository

import com.migestor.data.db.AppDatabase
import com.migestor.data.db.Student_group_marks
import com.migestor.shared.domain.AuditTrace
import com.migestor.shared.workgroup.StudentGroupMark
import com.migestor.shared.workgroup.StudentGroupMarkRepository
import com.migestor.shared.workgroup.WorkGroupMark
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.datetime.Instant

/** Marcas Fuerte / Necesita apoyo (migración 52). Viajan por Sync LAN con `SchoolRecordsSync`. */
class StudentGroupMarkRepositorySqlDelight(
    private val db: AppDatabase,
) : StudentGroupMarkRepository {

    private val q get() = db.studentGroupMarkQueries

    override suspend fun listAll(): List<StudentGroupMark> = withContext(Dispatchers.Default) {
        q.selectAllGroupMarks().executeAsList().map(::toMark)
    }

    override suspend fun listByClass(classId: Long): List<StudentGroupMark> = withContext(Dispatchers.Default) {
        q.selectGroupMarksByClass(classId).executeAsList().map(::toMark)
    }

    override suspend fun get(studentId: Long, classId: Long): StudentGroupMark? = withContext(Dispatchers.Default) {
        q.selectGroupMark(studentId, classId).executeAsOneOrNull()?.let(::toMark)
    }

    override suspend fun save(
        studentId: Long,
        classId: Long,
        mark: WorkGroupMark,
        updatedAtEpochMs: Long,
        deviceId: String?,
    ): StudentGroupMark = withContext(Dispatchers.Default) {
        // Escritura y relectura en la misma transacción: se devuelve lo que quedó guardado.
        db.transactionWithResult {
            q.upsertGroupMark(studentId, classId, mark.name, updatedAtEpochMs, updatedAtEpochMs, deviceId)
            toMark(q.selectGroupMark(studentId, classId).executeAsOne())
        }
    }

    override suspend fun delete(studentId: Long, classId: Long) = withContext(Dispatchers.Default) {
        q.deleteGroupMark(studentId, classId)
        Unit
    }

    private fun toMark(row: Student_group_marks) = StudentGroupMark(
        studentId = row.student_id,
        classId = row.class_id,
        mark = WorkGroupMark.fromStorage(row.mark),
        trace = AuditTrace(
            createdAt = Instant.fromEpochMilliseconds(row.created_at_epoch_ms),
            updatedAt = Instant.fromEpochMilliseconds(row.updated_at_epoch_ms),
            deviceId = row.device_id,
            syncVersion = row.sync_version,
        ),
    )
}
