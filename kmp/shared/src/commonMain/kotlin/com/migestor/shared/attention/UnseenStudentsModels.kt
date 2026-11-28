package com.migestor.shared.attention

import kotlinx.datetime.LocalDate

/** Qué tipo de registro del docente cuenta como «mirar» a un alumno. */
enum class ContactKind {
    GRADE,
    CELL_ENTRY,
    RUBRIC,
    PHYSICAL_TEST,
    OBSERVATION,
    INCIDENT,
    ATTENDANCE_NOTE,
    TERM_NOTE,
    JOURNAL_NOTE,
    FAMILY_MEETING,
}

/** Último registro de un tipo para un alumno en un grupo. */
data class ContactRecord(
    val studentId: Long,
    val kind: ContactKind,
    val date: LocalDate,
    /** Columna, rúbrica o prueba, si se sabe («Hockey»). */
    val label: String? = null,
)

/** Alumno del grupo para el cálculo (sin depender del modelo de dominio entero). */
data class AttentionStudent(
    val id: Long,
    val name: String,
)

/**
 * Alumno sin mirar en un grupo. Pensado para Swift: sin enteros opcionales.
 * `daysSinceLast == -1` y `lastKind == null` cuando no hay ningún registro.
 */
data class UnseenStudent(
    val studentId: Long,
    val name: String,
    val hasSupportMeasure: Boolean,
    val daysSinceLast: Int,
    val lastKind: ContactKind?,
    val lastLabel: String,
    val lastDateIso: String,
)

/** Resultado de un grupo: los que faltan por mirar y el total del grupo. */
data class UnseenReport(
    val classId: Long,
    val totalStudents: Int,
    val unseen: List<UnseenStudent>,
)

/** Último registro de un alumno en un grupo, para la ficha. `daysSince == -1`: ninguno. */
data class LastContactSummary(
    val studentId: Long,
    val classId: Long,
    val daysSince: Int,
    val isOverdue: Boolean,
    val kind: ContactKind?,
    val label: String,
    val dateIso: String,
)
