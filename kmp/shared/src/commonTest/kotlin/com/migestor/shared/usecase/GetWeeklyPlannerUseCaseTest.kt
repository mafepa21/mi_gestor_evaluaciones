package com.migestor.shared.usecase

import com.migestor.shared.domain.PlanningSession
import com.migestor.shared.domain.SessionStatus
import kotlin.test.Test
import kotlin.test.assertEquals

class GetWeeklyPlannerUseCaseTest {
    @Test
    fun `dos grupos en el mismo dia y periodo no se pisan`() {
        val first = session(groupId = 1, groupName = "1 ESO A")
        val second = session(groupId = 2, groupName = "1 ESO B")

        val indexed = GetWeeklyPlannerUseCase.indexBySlot(listOf(first, second))

        assertEquals(2, indexed.size)
        assertEquals("1 ESO A", indexed[Triple(1L, 1, 2)]?.groupName)
        assertEquals("1 ESO B", indexed[Triple(2L, 1, 2)]?.groupName)
    }

    private fun session(groupId: Long, groupName: String) = PlanningSession(
        teachingUnitId = 0,
        teachingUnitName = "Juegos",
        groupId = groupId,
        groupName = groupName,
        dayOfWeek = 1,
        period = 2,
        weekNumber = 39,
        year = 2026,
        status = SessionStatus.PLANNED,
    )
}
