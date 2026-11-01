package com.migestor.shared.evaluationsession

import com.migestor.shared.domain.SupportMeasureLevel

/**
 * Evaluación a la que corresponde la junta. Una junta por evaluación y grupo
 * (índice único en `evaluation_sessions`).
 */
enum class EvaluationKind {
    INITIAL,
    FIRST,
    SECOND,
    THIRD,
    FINAL;

    /** Nombre por defecto de la junta si el docente no escribe otro. */
    val defaultLabel: String
        get() = when (this) {
            INITIAL -> "Evaluación inicial"
            FIRST -> "1ª evaluación"
            SECOND -> "2ª evaluación"
            THIRD -> "3ª evaluación"
            FINAL -> "Evaluación final"
        }
}

/** Cabecera de una junta de evaluación (migración 47). Fecha en ISO (yyyy-MM-dd). */
data class EvaluationSession(
    val id: String,
    val classId: Long,
    val kind: EvaluationKind,
    val label: String,
    val plannerEvaluationPeriodId: Long? = null,
    val dateIso: String,
    val attendees: String = "",
    val generalAgreements: String = "",
    val isClosed: Boolean = false,
    val closedAtEpochMs: Long? = null,
    val createdAtEpochMs: Long = 0,
    val updatedAtEpochMs: Long = 0,
    val deviceId: String? = null,
    val syncVersion: Long = 0,
)

/**
 * Fila guardada de un alumno en una junta: lo anotado a mano más los datos
 * congelados al cerrar (nulos mientras no se haya cerrado nunca).
 */
data class EvaluationSessionStudentRecord(
    val sessionId: String,
    val studentId: Long,
    val firstName: String,
    val lastName: String,
    val otherFailedCount: Int = 0,
    val agreement: String = "",
    val isReviewed: Boolean = false,
    val frozenAverage: Double? = null,
    val frozenOwnFailed: Boolean? = null,
    val frozenAbsencePercent: Double? = null,
    val frozenAbsenceCount: Int? = null,
    /** Solo el nivel (III/IV). Nunca el tipo de medida ni las notas de seguimiento. */
    val frozenSupportLevel: SupportMeasureLevel? = null,
    val frozenIncidentCount: Int? = null,
    val createdAtEpochMs: Long = 0,
    val updatedAtEpochMs: Long = 0,
)

/**
 * Datos de un alumno que se copian al cerrar la junta. También es la forma de
 * los datos «en vivo» mientras la junta está abierta.
 *
 * Sin datos clínicos: de las medidas de apoyo solo viaja el nivel.
 */
data class EvaluationSessionStudentSnapshot(
    val studentId: Long,
    val average: Double?,
    /** `null` si no hay Media; `true` si la Media es menor que 5. */
    val ownFailed: Boolean?,
    val absencePercent: Double?,
    val absenceCount: Int?,
    val supportLevel: SupportMeasureLevel?,
    val incidentCount: Int?,
)

/** Fila lista para pintar: guardado + en vivo (abierta) o congelado (cerrada). */
data class EvaluationSessionStudentRow(
    val studentId: Long,
    val firstName: String,
    val lastName: String,
    val average: Double?,
    val ownFailed: Boolean?,
    val absencePercent: Double?,
    val absenceCount: Int?,
    val supportLevel: SupportMeasureLevel?,
    val incidentCount: Int?,
    val otherFailedCount: Int,
    /** Otras suspensas + 1 si suspende la materia propia (Media < 5). */
    val totalFailed: Int,
    val agreement: String,
    val isReviewed: Boolean,
    /** `true` si los datos salen de lo congelado al cerrar. */
    val isFrozen: Boolean,
) {
    val fullName: String get() = listOf(firstName, lastName).joinToString(" ").trim()
}

data class EvaluationSessionSummary(
    val studentCount: Int,
    val passAllCount: Int,
    val oneOrTwoFailedCount: Int,
    val threeOrMoreFailedCount: Int,
    /** Alumnado con Media ≥ 5 en la materia propia. Sin Media no cuenta. */
    val passedOwnSubjectCount: Int,
    val reviewedCount: Int,
)

data class EvaluationSessionBoard(
    val session: EvaluationSession,
    val students: List<EvaluationSessionStudentRow>,
    val summary: EvaluationSessionSummary,
)

/** Error con mensaje claro para el docente (llega a Swift como `NSError`). */
open class EvaluationSessionException(message: String) : IllegalStateException(message)

class EvaluationSessionDuplicateException(kind: EvaluationKind) :
    EvaluationSessionException("Este grupo ya tiene una junta de «${kind.defaultLabel}».")

class EvaluationSessionClosedException :
    EvaluationSessionException("La junta está cerrada. Reábrela para editarla.")

class EvaluationSessionNotFoundException(id: String) :
    EvaluationSessionException("No se encuentra la junta $id.")
