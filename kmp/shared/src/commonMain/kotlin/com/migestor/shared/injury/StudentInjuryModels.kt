package com.migestor.shared.injury

import com.migestor.shared.domain.AuditTrace
import kotlinx.datetime.LocalDate

/**
 * Papel que hace en clase el alumno lesionado. Se guarda por su `name`, así que
 * no se renombran: un nombre desconocido (de una versión más nueva) se lee como [NONE].
 */
enum class InjuryRole {
    NONE,
    REFEREE,
    TIMEKEEPER,
    EQUIPMENT_HELPER,
    THEORY_SHEET,
    OTHER;

    companion object {
        fun fromStorage(value: String?): InjuryRole =
            entries.firstOrNull { it.name == value } ?: NONE
    }
}

/**
 * Lesión de un alumno con fechas. Sin diagnóstico: solo lo que el docente necesita
 * para la clase. `endsOn == null` significa «sin fecha de fin».
 * El borrado es lógico ([isDeleted]) para que viaje por Sync LAN como un cambio más.
 */
data class StudentInjury(
    val id: String,
    val studentId: Long,
    val startsOn: LocalDate,
    val endsOn: LocalDate? = null,
    val role: InjuryRole = InjuryRole.NONE,
    val note: String = "",
    val proofDelivered: Boolean = false,
    val isDeleted: Boolean = false,
    val trace: AuditTrace = AuditTrace(),
)

/** Lo que el docente rellena en la hoja «Lesión». `id == null` crea una nueva. */
data class StudentInjuryDraft(
    val id: String? = null,
    val studentId: Long,
    val startsOn: LocalDate,
    val endsOn: LocalDate? = null,
    val role: InjuryRole = InjuryRole.NONE,
    val note: String = "",
    val proofDelivered: Boolean = false,
)

/** Motivo por el que una lesión no se puede guardar. */
enum class StudentInjuryValidationError {
    ENDS_BEFORE_START,
    NOTE_TOO_LONG,
}

class StudentInjuryValidationException(val error: StudentInjuryValidationError) :
    IllegalArgumentException(
        when (error) {
            StudentInjuryValidationError.ENDS_BEFORE_START -> "«Hasta» no puede ser antes de «Desde»."
            StudentInjuryValidationError.NOTE_TOO_LONG -> "La nota no puede pasar de ${StudentInjuryRules.NOTE_MAX_LENGTH} caracteres."
        },
    )
