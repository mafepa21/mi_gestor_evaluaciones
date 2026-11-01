package com.migestor.shared.evaluationsession

/**
 * Persistencia de las juntas de evaluación (migración 47).
 * Todo método lleva @Throws: sin él, un fallo Kotlin mata la app en Swift.
 *
 * Las operaciones de edición rechazan una junta cerrada con
 * [EvaluationSessionClosedException].
 */
interface EvaluationSessionRepository {
    /** Abiertas primero; después por fecha descendente. */
    @Throws(Throwable::class)
    suspend fun listSessions(classId: Long): List<EvaluationSession>

    @Throws(Throwable::class)
    suspend fun getSession(id: String): EvaluationSession?

    /** Lanza [EvaluationSessionDuplicateException] si el grupo ya tiene junta de esa evaluación. */
    @Throws(Throwable::class)
    suspend fun insertSession(session: EvaluationSession)

    @Throws(Throwable::class)
    suspend fun updateHeader(
        id: String,
        label: String,
        plannerEvaluationPeriodId: Long?,
        dateIso: String,
        attendees: String,
        generalAgreements: String,
        nowEpochMs: Long,
    )

    /** Congela los datos de cada alumno y cierra la junta en una sola transacción. */
    @Throws(Throwable::class)
    suspend fun closeSession(id: String, snapshots: List<EvaluationSessionStudentSnapshot>, nowEpochMs: Long)

    /** Reabre conservando los congelados (se sobrescriben al volver a cerrar). */
    @Throws(Throwable::class)
    suspend fun reopenSession(id: String, nowEpochMs: Long)

    /** Borra la junta y sus filas (explícito: en producción las FK están apagadas). */
    @Throws(Throwable::class)
    suspend fun deleteSession(id: String)

    /** Solo filas de alumnado que sigue existiendo (INNER JOIN students). */
    @Throws(Throwable::class)
    suspend fun listStudents(sessionId: String): List<EvaluationSessionStudentRecord>

    /** Crea las filas que falten (INSERT OR IGNORE). Devuelve cuántas ha creado. */
    @Throws(Throwable::class)
    suspend fun ensureStudents(sessionId: String, studentIds: List<Long>, nowEpochMs: Long): Int

    @Throws(Throwable::class)
    suspend fun updateStudent(
        sessionId: String,
        studentId: Long,
        otherFailedCount: Int,
        agreement: String,
        isReviewed: Boolean,
        nowEpochMs: Long,
    )
}
