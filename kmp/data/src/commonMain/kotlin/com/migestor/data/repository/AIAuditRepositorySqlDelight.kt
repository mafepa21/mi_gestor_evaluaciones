package com.migestor.data.repository

import com.migestor.data.db.AppDatabase
import com.migestor.shared.domain.AIAuditAvailabilityTotal
import com.migestor.shared.domain.AIAuditEvent
import com.migestor.shared.domain.AIAuditUseCaseTotal
import com.migestor.shared.repository.AIAuditRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class AIAuditRepositorySqlDelight(
    private val db: AppDatabase,
) : AIAuditRepository {

    override suspend fun recordEvent(event: AIAuditEvent) = withContext(Dispatchers.Default) {
        db.appDatabaseQueries.insertAiAuditEvent(
            created_at_epoch_ms = event.createdAtEpochMs,
            service = event.service,
            use_case = event.useCase,
            report_kind = event.reportKind,
            class_id = event.classId,
            student_hash = event.studentHash,
            availability = event.availability,
            model_available = if (event.modelAvailable) 1 else 0,
            success = if (event.success) 1 else 0,
            duration_ms = event.durationMs,
            error_kind = event.errorKind,
            error_message = event.errorMessage,
        )
    }

    override suspend fun recentEvents(limit: Long): List<AIAuditEvent> = withContext(Dispatchers.Default) {
        db.appDatabaseQueries.selectAiAuditEvents(limit, ::mapEvent).executeAsList()
    }

    override suspend fun recentFailures(limit: Long): List<AIAuditEvent> = withContext(Dispatchers.Default) {
        db.appDatabaseQueries.selectRecentAiAuditFailures(limit, ::mapEvent).executeAsList()
    }

    override suspend fun latestEvent(): AIAuditEvent? = withContext(Dispatchers.Default) {
        db.appDatabaseQueries.selectLatestAiAuditEvent(::mapEvent).executeAsOneOrNull()
    }

    override suspend fun totalsByUseCase(): List<AIAuditUseCaseTotal> = withContext(Dispatchers.Default) {
        db.appDatabaseQueries.selectAiAuditTotalsByUseCase { useCase, totalCount, successCount, lastCreatedAtEpochMs ->
            AIAuditUseCaseTotal(
                useCase = useCase,
                totalCount = totalCount,
                successCount = successCount ?: 0,
                lastCreatedAtEpochMs = lastCreatedAtEpochMs ?: 0,
            )
        }.executeAsList()
    }

    override suspend fun recentAvailabilityTotals(): List<AIAuditAvailabilityTotal> = withContext(Dispatchers.Default) {
        db.appDatabaseQueries.selectRecentAiAuditAvailability { availability, totalCount, lastCreatedAtEpochMs ->
            AIAuditAvailabilityTotal(
                availability = availability,
                totalCount = totalCount,
                lastCreatedAtEpochMs = lastCreatedAtEpochMs ?: 0,
            )
        }.executeAsList()
    }

    private fun mapEvent(
        id: Long,
        createdAtEpochMs: Long,
        service: String,
        useCase: String,
        reportKind: String?,
        classId: Long?,
        studentHash: String?,
        availability: String,
        modelAvailable: Long,
        success: Long,
        durationMs: Long,
        errorKind: String?,
        errorMessage: String?,
    ): AIAuditEvent = AIAuditEvent(
        id = id,
        createdAtEpochMs = createdAtEpochMs,
        service = service,
        useCase = useCase,
        reportKind = reportKind,
        classId = classId,
        studentHash = studentHash,
        availability = availability,
        modelAvailable = modelAvailable != 0L,
        success = success != 0L,
        durationMs = durationMs,
        errorKind = errorKind,
        errorMessage = errorMessage,
    )
}
