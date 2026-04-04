package com.migestor.shared.util

import kotlinx.datetime.*

object IsoWeekHelper {
    /**
     * Returns the 5 work days (Mon-Fri) of the given ISO week and year.
     */
    fun daysOf(isoWeek: Int, year: Int): List<LocalDate> {
        // Find the first Monday of the year (ISO week 1 starts with the week containing Jan 4th)
        val jan4th = LocalDate(year, 1, 4)
        val jan4thDayOfWeek = jan4th.dayOfWeek.isoDayNumber
        val firstMondayOfYear = jan4th.minus((jan4thDayOfWeek - 1).toLong(), DateTimeUnit.DAY)
        
        // Add (isoWeek - 1) weeks to the first Monday
        val startOfWeek = firstMondayOfYear.plus(((isoWeek - 1) * 7).toLong(), DateTimeUnit.DAY)
        
        return (0..4).map { 
            startOfWeek.plus(it.toLong(), DateTimeUnit.DAY)
        }
    }

    /**
     * Returns the ISO week number for a given date.
     */
    fun isoWeekOf(date: LocalDate): Int {
        val jan4th = LocalDate(date.year, 1, 4)
        val firstMonday = jan4th.minus((jan4th.dayOfWeek.isoDayNumber - 1).toLong(), DateTimeUnit.DAY)
        
        val daysSinceFirstMonday = date.toEpochDays() - firstMonday.toEpochDays()
        if (daysSinceFirstMonday < 0) {
            // It belongs to previous year's last week
            return isoWeekOf(LocalDate(date.year - 1, 12, 31))
        }
        
        return (daysSinceFirstMonday / 7) + 1
    }

    /**
     * Returns a pair of (isoWeek, year) for the current date.
     */
    fun current(): Pair<Int, Int> {
        val now = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
        return isoWeekOf(now) to now.year
    }
}
