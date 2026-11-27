package com.migestor.shared.attention

import kotlinx.datetime.DatePeriod
import kotlinx.datetime.LocalDate
import kotlinx.datetime.daysUntil
import kotlinx.datetime.plus

/**
 * Reglas puras de «Alumnos invisibles» (ticket 2026-11-27).
 * Ventana: 14 días sin contar los no lectivos del calendario docente.
 */
object UnseenStudentsRules {
    const val WINDOW_DAYS = 14

    /** Días naturales de `from` a `to` (0 si es el mismo día). */
    fun naturalDays(from: LocalDate, to: LocalDate): Int = from.daysUntil(to).coerceAtLeast(0)

    /** Días de `from` (excluido) a `to` (incluido) que no son no lectivos. */
    fun countedDays(from: LocalDate, to: LocalDate, nonTeaching: Set<LocalDate>): Int {
        if (to <= from) return 0
        var count = 0
        var day = from.plus(DatePeriod(days = 1))
        while (day <= to) {
            if (day !in nonTeaching) count++
            day = day.plus(DatePeriod(days = 1))
        }
        return count
    }

    /** El registro más reciente de una lista (a igualdad de día, el primero). */
    fun latest(records: List<ContactRecord>): ContactRecord? = records.maxByOrNull { it.date }

    /**
     * ¿Está sin mirar? Con registro: si desde él han pasado [WINDOW_DAYS] días contados.
     * Sin registro: si lleva en el grupo al menos ese plazo (o no se sabe cuándo entró).
     */
    fun isUnseen(
        last: ContactRecord?,
        enrolledOn: LocalDate?,
        today: LocalDate,
        nonTeaching: Set<LocalDate>,
    ): Boolean {
        if (last != null) return countedDays(last.date, today, nonTeaching) >= WINDOW_DAYS
        if (enrolledOn == null) return true
        return countedDays(enrolledOn, today, nonTeaching) >= WINDOW_DAYS
    }

    /** Orden de la lista: primero con medida, luego sin ningún registro, luego más días. */
    val order: Comparator<UnseenStudent> =
        compareByDescending<UnseenStudent> { it.hasSupportMeasure }
            .thenByDescending { it.daysSinceLast == -1 }
            .thenByDescending { it.daysSinceLast }
            .thenBy { it.name }
}
