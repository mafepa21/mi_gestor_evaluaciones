package com.migestor.shared.usecase

import com.migestor.shared.domain.PlanningSession
import com.migestor.shared.repository.PlannerRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

class GetWeeklyPlannerUseCase(private val repo: PlannerRepository) {

    operator fun invoke(
        weekNumber: Int,
        year: Int
    ): Flow<Map<Pair<Int, Int>, PlanningSession>> =
        repo.observeSessions(weekNumber, year)
            .map { list: List<PlanningSession> ->
                list.associateBy { session: PlanningSession ->
                    session.dayOfWeek to session.period
                }
            }
}
