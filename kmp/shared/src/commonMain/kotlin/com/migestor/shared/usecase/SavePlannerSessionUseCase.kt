package com.migestor.shared.usecase

import com.migestor.shared.domain.PlanningSession
import com.migestor.shared.repository.PlannerRepository

class SavePlannerSessionUseCase(private val repo: PlannerRepository) {
    suspend operator fun invoke(session: PlanningSession): Long =
        repo.upsertSession(session)
}
