package com.migestor.shared.evaluationsession

import kotlinx.datetime.LocalDate

/**
 * Junta de evaluación de un grupo: crear, cargar, editar, cerrar, reabrir y borrar.
 *
 * Máquina de estados: Abierta -> Cerrada (y vuelta atrás al reabrir).
 * - Abierta: Media, faltas, nivel de medida e incidencias se leen en vivo.
 * - Cerrada: se usan los valores congelados al cerrar; no se edita nada.
 *
 * Todos los métodos públicos se exponen a Swift: sin argumentos por defecto
 * (Swift no los ve) y con @Throws para que un fallo llegue como NSError.
 */
class EvaluationSessionUseCase(
    private val sessions: EvaluationSessionRepository,
    private val live: EvaluationSessionLiveDataSource,
    private val newId: () -> String,
) {

    @Throws(Throwable::class)
    suspend fun listSessions(classId: Long): List<EvaluationSession> = sessions.listSessions(classId)

    /**
     * Crea la junta y una fila por alumno matriculado en el grupo.
     * Si [label] está vacío se usa el nombre de la evaluación.
     */
    @Throws(Throwable::class)
    suspend fun createSession(
        classId: Long,
        kind: EvaluationKind,
        dateIso: String,
        label: String?,
        plannerEvaluationPeriodId: Long?,
        nowEpochMs: Long,
    ): EvaluationSession {
        val session = EvaluationSession(
            id = newId(),
            classId = classId,
            kind = kind,
            label = label?.trim().orEmpty().ifEmpty { kind.defaultLabel },
            plannerEvaluationPeriodId = plannerEvaluationPeriodId,
            dateIso = validDate(dateIso),
            createdAtEpochMs = nowEpochMs,
            updatedAtEpochMs = nowEpochMs,
        )
        sessions.insertSession(session)
        sessions.ensureStudents(session.id, live.studentIdsInClass(classId), nowEpochMs)
        return session
    }

    /**
     * Carga la junta lista para pintar. Si está abierta, añade antes las filas
     * del alumnado que haya entrado en el grupo después de crearla.
     */
    @Throws(Throwable::class)
    suspend fun loadBoard(sessionId: String, nowEpochMs: Long): EvaluationSessionBoard {
        val session = requireSession(sessionId)
        if (!session.isClosed) {
            sessions.ensureStudents(sessionId, live.studentIdsInClass(session.classId), nowEpochMs)
        }
        val records = sessions.listStudents(sessionId)
        val rows = if (session.isClosed) {
            records.map { EvaluationSessionRules.row(it, EvaluationSessionRules.frozenSnapshot(it), isFrozen = true) }
        } else {
            val data = live.snapshots(session.classId, records.map { it.studentId })
            records.map { record ->
                val snapshot = data[record.studentId] ?: EvaluationSessionRules.emptySnapshot(record.studentId)
                EvaluationSessionRules.row(record, snapshot, isFrozen = false)
            }
        }
        return EvaluationSessionBoard(session, rows, EvaluationSessionRules.summary(rows))
    }

    @Throws(Throwable::class)
    suspend fun updateHeader(
        sessionId: String,
        label: String,
        dateIso: String,
        attendees: String,
        generalAgreements: String,
        plannerEvaluationPeriodId: Long?,
        nowEpochMs: Long,
    ) {
        val session = requireOpenSession(sessionId)
        sessions.updateHeader(
            id = sessionId,
            label = label.trim().ifEmpty { session.kind.defaultLabel },
            plannerEvaluationPeriodId = plannerEvaluationPeriodId,
            dateIso = validDate(dateIso),
            attendees = attendees,
            generalAgreements = generalAgreements,
            nowEpochMs = nowEpochMs,
        )
    }

    /** Otras suspensas entre 0 y 15. */
    @Throws(Throwable::class)
    suspend fun updateStudent(
        sessionId: String,
        studentId: Long,
        otherFailedCount: Int,
        agreement: String,
        isReviewed: Boolean,
        nowEpochMs: Long,
    ) {
        EvaluationSessionRules.validateOtherFailed(otherFailedCount)
        requireOpenSession(sessionId)
        sessions.updateStudent(sessionId, studentId, otherFailedCount, agreement, isReviewed, nowEpochMs)
    }

    /** Congela Media, faltas, nivel e incidencias de cada alumno y cierra (una transacción). */
    @Throws(Throwable::class)
    suspend fun closeSession(sessionId: String, nowEpochMs: Long): EvaluationSessionBoard {
        val session = requireOpenSession(sessionId)
        sessions.ensureStudents(sessionId, live.studentIdsInClass(session.classId), nowEpochMs)
        val studentIds = sessions.listStudents(sessionId).map { it.studentId }
        val data = live.snapshots(session.classId, studentIds)
        val snapshots = studentIds.map { data[it] ?: EvaluationSessionRules.emptySnapshot(it) }
        sessions.closeSession(sessionId, snapshots, nowEpochMs)
        return loadBoard(sessionId, nowEpochMs)
    }

    /** Vuelve a abierta. Los congelados se conservan y se sobrescriben al volver a cerrar. */
    @Throws(Throwable::class)
    suspend fun reopenSession(sessionId: String, nowEpochMs: Long): EvaluationSessionBoard {
        requireSession(sessionId)
        sessions.reopenSession(sessionId, nowEpochMs)
        return loadBoard(sessionId, nowEpochMs)
    }

    @Throws(Throwable::class)
    suspend fun deleteSession(sessionId: String) = sessions.deleteSession(sessionId)

    private suspend fun requireSession(id: String): EvaluationSession =
        sessions.getSession(id) ?: throw EvaluationSessionNotFoundException(id)

    private suspend fun requireOpenSession(id: String): EvaluationSession =
        requireSession(id).also { if (it.isClosed) throw EvaluationSessionClosedException() }

    private fun validDate(iso: String): String =
        runCatching { LocalDate.parse(iso.trim()) }.getOrNull()?.toString()
            ?: throw EvaluationSessionException("La fecha «$iso» no es válida (formato aaaa-mm-dd).")
}
