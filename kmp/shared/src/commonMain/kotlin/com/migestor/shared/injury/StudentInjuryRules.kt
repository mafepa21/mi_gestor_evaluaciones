package com.migestor.shared.injury

import kotlinx.datetime.DatePeriod
import kotlinx.datetime.LocalDate
import kotlinx.datetime.minus

/**
 * Reglas puras de fechas de las lesiones. Sin repositorios: se prueban solas.
 * Las fechas son de calendario (sin hora): «hasta el 12» incluye todo el día 12.
 */
object StudentInjuryRules {
    const val NOTE_MAX_LENGTH = 140

    /** Activa ese día: no borrada, ya empezada y sin terminar (el «hasta» cuenta). */
    fun isActiveOn(injury: StudentInjury, date: LocalDate): Boolean =
        !injury.isDeleted &&
            injury.startsOn <= date &&
            (injury.endsOn == null || date <= injury.endsOn)

    /** La lesión activa del alumno ese día; si hay varias, la que empezó más tarde. */
    fun activeOn(injuries: List<StudentInjury>, date: LocalDate): StudentInjury? =
        injuries.filter { isActiveOn(it, date) }.maxByOrNull { it.startsOn }

    /** Alumnos con alguna lesión activa ese día. */
    fun injuredStudentIds(injuries: List<StudentInjury>, date: LocalDate): Set<Long> =
        injuries.filter { isActiveOn(it, date) }.mapTo(mutableSetOf()) { it.studentId }

    /**
     * Lesiones que terminaron ayer de alumnos que hoy ya no tienen ninguna activa:
     * son los que «vuelven hoy». Una por alumno (la que terminó, la más reciente).
     */
    fun returningOn(injuries: List<StudentInjury>, date: LocalDate): List<StudentInjury> {
        val yesterday = date.minus(DatePeriod(days = 1))
        val stillInjured = injuredStudentIds(injuries, date)
        return injuries
            .filter { !it.isDeleted && it.endsOn == yesterday && it.studentId !in stillInjured }
            .groupBy { it.studentId }
            .map { (_, list) -> list.maxBy { it.startsOn } }
            .sortedBy { it.studentId }
    }

    /** Recorta espacios; `null` si todo está bien, o el motivo si no se puede guardar. */
    fun validate(draft: StudentInjuryDraft): StudentInjuryValidationError? {
        if (draft.endsOn != null && draft.endsOn < draft.startsOn) return StudentInjuryValidationError.ENDS_BEFORE_START
        if (draft.note.trim().length > NOTE_MAX_LENGTH) return StudentInjuryValidationError.NOTE_TOO_LONG
        return null
    }

    /**
     * «Ha vuelto» hoy: la lesión termina ayer, así hoy ya no cuenta.
     * Si empezó hoy o después, no hay un «ayer» válido: se borra (casi seguro fue un error).
     */
    fun returnedToday(injury: StudentInjury, today: LocalDate): StudentInjury {
        val yesterday = today.minus(DatePeriod(days = 1))
        return if (injury.startsOn > yesterday) {
            injury.copy(isDeleted = true)
        } else {
            injury.copy(endsOn = if (injury.endsOn == null || injury.endsOn > yesterday) yesterday else injury.endsOn)
        }
    }
}
