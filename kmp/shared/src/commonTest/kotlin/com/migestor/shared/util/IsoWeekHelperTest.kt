package com.migestor.shared.util

import kotlinx.datetime.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals

class IsoWeekHelperTest {
    @Test
    fun `late december can belong to iso week 1 of next year`() {
        // 31 dic 2024 (martes) cae en la semana ISO 1 de 2025, no en la 53 de 2024.
        assertEquals(1 to 2025, IsoWeekHelper.of(LocalDate(2024, 12, 31)))
    }

    @Test
    fun `early january can belong to the last iso week of previous year`() {
        // 1 ene 2023 (domingo) cierra la semana ISO 52 de 2022.
        assertEquals(52 to 2022, IsoWeekHelper.of(LocalDate(2023, 1, 1)))
    }

    @Test
    fun `mid year date keeps calendar year as iso year`() {
        assertEquals(23 to 2024, IsoWeekHelper.of(LocalDate(2024, 6, 5)))
    }

    @Test
    fun `daysOf round trips with the iso week and year it reports`() {
        val (week, year) = IsoWeekHelper.of(LocalDate(2024, 12, 31))
        val days = IsoWeekHelper.daysOf(week, year)
        assertEquals(LocalDate(2024, 12, 30), days.first())
    }

    @Test
    fun `school year runs from september through june`() {
        assertEquals(
            LocalDate(2026, 9, 1) to LocalDate(2027, 6, 30),
            IsoWeekHelper.schoolYearBounds(LocalDate(2026, 9, 25)),
        )
        assertEquals(
            LocalDate(2025, 9, 1) to LocalDate(2026, 6, 30),
            IsoWeekHelper.schoolYearBounds(LocalDate(2026, 1, 15)),
        )
    }

    @Test
    fun `2026 has 53 iso weeks and navigation does not skip the last one`() {
        assertEquals(53, IsoWeekHelper.weeksIn(2026))
        assertEquals(52, IsoWeekHelper.weeksIn(2025))
        assertEquals(1 to 2027, IsoWeekHelper.shiftWeek(53, 2026, 1))
        assertEquals(53 to 2026, IsoWeekHelper.shiftWeek(1, 2027, -1))
        assertEquals(1 to 2026, IsoWeekHelper.shiftWeek(52, 2025, 1))
    }
}
