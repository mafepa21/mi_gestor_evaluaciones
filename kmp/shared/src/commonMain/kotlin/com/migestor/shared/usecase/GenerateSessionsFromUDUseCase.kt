package com.migestor.shared.usecase

import com.migestor.shared.domain.PlanningSession
import com.migestor.shared.domain.SessionStatus
import com.migestor.shared.domain.TeachingUnit
import com.migestor.shared.domain.TeachingUnitSchedule
import com.migestor.shared.repository.PlannerRepository
import com.migestor.shared.repository.WeeklyTemplateRepository
import com.migestor.shared.util.IsoWeekHelper
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.isoDayNumber
import kotlinx.datetime.plus

/**
 * Las sesiones generadas al guardar una unidad se escriben en `planner_session`,
 * la misma tabla que lee el iPad y que viaja en el sync.
 * La tabla antigua `planned_session` se deja como está y no recibe filas nuevas.
 */
class GenerateSessionsFromUDUseCase(
    private val templateRepo: WeeklyTemplateRepository,
    private val plannerRepo: PlannerRepository,
) {
    suspend fun execute(ud: TeachingUnit, schedule: TeachingUnitSchedule) {
        val slots = templateRepo.getSlotsForClass(schedule.schoolClassId)
        val periods = plannerRepo.getTimeSlots()
        var current = schedule.startDate
        while (current <= schedule.endDate) {
            val dayOfWeek = current.dayOfWeek.isoDayNumber
            if (dayOfWeek in 1..5) {
                val daySlots = slots.filter { it.dayOfWeek == dayOfWeek }.sortedBy { it.startTime }
                val existing = plannerRepo.listSessionsInRange(schedule.schoolClassId, current, current)
                daySlots.forEachIndexed { index, slot ->
                    val period = periods.firstOrNull { it.startTime == slot.startTime }?.period ?: (index + 1)
                    if (existing.any { it.period == period }) return@forEachIndexed
                    plannerRepo.upsertSession(
                        PlanningSession(
                            teachingUnitId = ud.id,
                            teachingUnitName = ud.name,
                            teachingUnitColor = ud.colorHex,
                            groupId = schedule.schoolClassId,
                            groupName = "",
                            dayOfWeek = dayOfWeek,
                            period = period,
                            weekNumber = IsoWeekHelper.isoWeekOf(current),
                            year = current.year,
                            startTime = slot.startTime,
                            endTime = slot.endTime,
                            status = SessionStatus.PLANNED,
                        )
                    )
                }
            }
            current = current.plus(1, DateTimeUnit.DAY)
        }
    }
}
