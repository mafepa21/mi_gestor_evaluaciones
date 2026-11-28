package com.migestor.data.repository

import com.migestor.data.db.AppDatabase
import com.migestor.shared.attention.AttentionStudent
import com.migestor.shared.attention.ContactKind
import com.migestor.shared.attention.ContactRecord
import com.migestor.shared.attention.UnseenStudentsRepository
import com.migestor.shared.repository.ClassesRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

/**
 * Lecturas de «Alumnos invisibles» (`Attention.sq`). Solo lectura y por lotes de
 * grupo: unas diez consultas por grupo, nunca una por alumno.
 */
class UnseenStudentsRepositorySqlDelight(
    private val db: AppDatabase,
    private val classes: ClassesRepository,
    private val timeZone: () -> TimeZone = { TimeZone.currentSystemDefault() },
) : UnseenStudentsRepository {

    private val q get() = db.attentionQueries

    override suspend fun lastContacts(classId: Long): List<ContactRecord> = withContext(Dispatchers.Default) {
        val out = mutableListOf<ContactRecord>()
        fun add(studentId: Long?, atMs: Long?, kind: ContactKind, label: String?) {
            if (studentId == null || atMs == null || atMs <= 0) return
            out += ContactRecord(studentId, kind, day(atMs), label?.takeIf { it.isNotBlank() })
        }
        fun addIso(studentId: Long?, iso: String?, kind: ContactKind) {
            if (studentId == null || iso == null) return
            val date = runCatching { LocalDate.parse(iso.take(10)) }.getOrNull() ?: return
            out += ContactRecord(studentId, kind, date, null)
        }
        q.lastGradeByStudent(classId).executeAsList().forEach { add(it.student_id, it.at_ms, ContactKind.GRADE, it.label) }
        q.lastCellEntryByStudent(classId).executeAsList().forEach { add(it.student_id, it.at_ms, ContactKind.CELL_ENTRY, it.label) }
        q.lastRubricByStudent(classId).executeAsList().forEach { add(it.student_id, it.at_ms, ContactKind.RUBRIC, it.label) }
        q.lastPhysicalTestByStudent(classId).executeAsList().forEach { add(it.student_id, it.at_ms, ContactKind.PHYSICAL_TEST, it.label) }
        q.lastIncidentByStudent(classId).executeAsList().forEach {
            val isObservation = it.label?.trim()?.equals("Observación", ignoreCase = true) == true
            add(
                it.student_id,
                it.at_ms,
                if (isObservation) ContactKind.OBSERVATION else ContactKind.INCIDENT,
                if (isObservation) null else it.label,
            )
        }
        q.lastAttendanceNoteByStudent(classId).executeAsList().forEach { add(it.student_id, it.at_ms, ContactKind.ATTENDANCE_NOTE, null) }
        q.lastTermNoteByStudent(classId).executeAsList().forEach { add(it.student_id, it.at_ms, ContactKind.TERM_NOTE, null) }
        q.lastJournalNoteByStudent(classId).executeAsList().forEach { addIso(it.student_id, it.date_iso, ContactKind.JOURNAL_NOTE) }
        q.lastTutoringByStudent(classId).executeAsList().forEach { addIso(it.student_id, it.date_iso, ContactKind.FAMILY_MEETING) }
        out
    }

    override suspend fun enrollmentStarts(classId: Long): Map<Long, LocalDate> = withContext(Dispatchers.Default) {
        q.enrollmentStartByStudent(classId).executeAsList()
            .mapNotNull { row -> row.at_ms?.takeIf { it > 0 }?.let { row.student_id to day(it) } }
            .toMap()
    }

    override suspend fun studentsWithSupportMeasure(classId: Long): Set<Long> = withContext(Dispatchers.Default) {
        q.studentsWithSupportMeasure(classId).executeAsList().toSet()
    }

    override suspend fun students(classId: Long): List<AttentionStudent> =
        classes.listStudentsInClass(classId).map { student ->
            AttentionStudent(id = student.id, name = "${student.firstName} ${student.lastName}".trim())
        }

    private fun day(epochMs: Long): LocalDate =
        Instant.fromEpochMilliseconds(epochMs).toLocalDateTime(timeZone()).date
}
