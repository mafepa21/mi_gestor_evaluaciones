package com.migestor.shared.usecase

import com.migestor.shared.domain.TeachingUnit
import com.migestor.shared.domain.TeachingUnitSchedule
import com.migestor.shared.domain.PlannedSession
import com.migestor.shared.repository.WeeklyTemplateRepository
import com.migestor.shared.repository.PlannedSessionRepository
import kotlinx.datetime.isoDayNumber
import kotlinx.datetime.plus
import kotlinx.datetime.DateTimeUnit

class GenerateSessionsFromUDUseCase(
    private val templateRepo: WeeklyTemplateRepository,
    private val sessionRepo: PlannedSessionRepository
) {
    suspend fun execute(ud: TeachingUnit, schedule: TeachingUnitSchedule) {
        // 1. Obtener las franjas del grupo
        val slots = templateRepo.getSlotsForClass(schedule.schoolClassId)
        
        // 2. Iterar cada día entre startDate y endDate
        var current = schedule.startDate
        while (current <= schedule.endDate) {
            val dayOfWeek = current.dayOfWeek.isoDayNumber  // 1-7
            if (dayOfWeek in 1..5) {
                val filteredSlots = slots.filter { it.dayOfWeek == dayOfWeek }
                for (slot in filteredSlots) {
                    // 3. Solo crear si no existe ya una sesión en esa fecha/hora
                    val exists = sessionRepo.existsAt(schedule.schoolClassId, current, slot.startTime)
                    if (!exists) {
                        sessionRepo.insert(PlannedSession(
                            teachingUnitId = ud.id,
                            schoolClassId = schedule.schoolClassId,
                            date = current,
                            startTime = slot.startTime,
                            endTime = slot.endTime,
                            title = ud.name  // título de la UD como base
                        ))
                    }
                }
            }
            current = current.plus(1, DateTimeUnit.DAY)
        }
    }
}
