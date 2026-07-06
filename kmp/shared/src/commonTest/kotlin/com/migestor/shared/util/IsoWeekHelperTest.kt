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
}
