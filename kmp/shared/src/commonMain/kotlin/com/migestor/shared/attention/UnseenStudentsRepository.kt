package com.migestor.shared.attention

import kotlinx.datetime.LocalDate

/** Lecturas por lotes de grupo para «Alumnos invisibles» (`Attention.sq`). Solo lectura. */
interface UnseenStudentsRepository {
    /** Último registro de cada tipo y alumno del grupo (como mucho uno por tipo y alumno). */
    suspend fun lastContacts(classId: Long): List<ContactRecord>

    /** Día en que cada alumno entró al grupo (si se sabe). */
    suspend fun enrollmentStarts(classId: Long): Map<Long, LocalDate>

    /** Alumnado del grupo con medida activa de nivel III o IV. */
    suspend fun studentsWithSupportMeasure(classId: Long): Set<Long>

    /** Alumnado del grupo. */
    suspend fun students(classId: Long): List<AttentionStudent>
}
