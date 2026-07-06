package com.migestor.shared.util

import kotlinx.datetime.*

object IsoWeekHelper {
    private fun firstMondayOfIsoYear(year: Int): LocalDate {
        val jan4th = LocalDate(year, 1, 4)
        return jan4th.minus((jan4th.dayOfWeek.isoDayNumber - 1).toLong(), DateTimeUnit.DAY)
    }

    /**
     * Returns the 5 work days (Mon-Fri) of the given ISO week and year.
     */
    fun daysOf(isoWeek: Int, year: Int): List<LocalDate> {
        val startOfWeek = firstMondayOfIsoYear(year).plus(((isoWeek - 1) * 7).toLong(), DateTimeUnit.DAY)
        return (0..4).map {
            startOfWeek.plus(it.toLong(), DateTimeUnit.DAY)
        }
    }

    // El año ISO de una fecha es el año de su jueves (regla ISO-8601): evita que
    // los últimos/primeros días de diciembre/enero se cuenten con el año natural
    // equivocado cuando la semana ISO cruza el límite de año.
    private fun isoYearOf(date: LocalDate): Int {
        val thursdayOfWeek = date.plus((4 - date.dayOfWeek.isoDayNumber).toLong(), DateTimeUnit.DAY)
        return thursdayOfWeek.year
    }

    /**
     * Returns the ISO week number for a given date.
     */
    fun isoWeekOf(date: LocalDate): Int {
        val firstMonday = firstMondayOfIsoYear(isoYearOf(date))
        val daysSinceFirstMonday = date.toEpochDays() - firstMonday.toEpochDays()
        return (daysSinceFirstMonday / 7) + 1
    }

    /**
     * Returns a pair of (isoWeek, isoYear) for the given date.
     */
    fun of(date: LocalDate): Pair<Int, Int> = isoWeekOf(date) to isoYearOf(date)

    /**
     * Returns a pair of (isoWeek, isoYear) for the current date.
     */
    fun current(): Pair<Int, Int> {
        val now = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
        return of(now)
    }
}
