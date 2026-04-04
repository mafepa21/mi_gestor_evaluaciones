package com.migestor.shared.usecase

import com.migestor.shared.domain.WeeklySlotTemplate
import com.migestor.shared.repository.WeeklyTemplateRepository

class SaveWeeklyTemplateUseCase(
    private val templateRepo: WeeklyTemplateRepository
) {
    suspend operator fun invoke(slots: List<WeeklySlotTemplate>) {
        slots.forEach { templateRepo.insert(it) }
    }
}
