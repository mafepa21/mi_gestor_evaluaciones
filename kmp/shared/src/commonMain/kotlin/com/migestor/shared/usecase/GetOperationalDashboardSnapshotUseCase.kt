package com.migestor.shared.usecase

import com.migestor.shared.domain.DashboardFilters
import com.migestor.shared.domain.DashboardMode
import com.migestor.shared.domain.DashboardSnapshot
import com.migestor.shared.repository.DashboardOperationalRepository
import kotlinx.datetime.Clock
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

class GetOperationalDashboardSnapshotUseCase(
    private val repository: DashboardOperationalRepository,
) {
    suspend operator fun invoke(
        mode: DashboardMode,
        filters: DashboardFilters = DashboardFilters(),
    ): DashboardSnapshot {
        val today = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
        return repository.getSnapshot(date = today, mode = mode, filters = filters)
    }

    suspend operator fun invoke(
        date: kotlinx.datetime.LocalDate,
        mode: DashboardMode,
        filters: DashboardFilters = DashboardFilters(),
    ): DashboardSnapshot = repository.getSnapshot(date = date, mode = mode, filters = filters)
}
