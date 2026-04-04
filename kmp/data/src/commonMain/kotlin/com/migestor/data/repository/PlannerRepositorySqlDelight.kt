package com.migestor.data.repository

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import com.migestor.data.db.AppDatabase
import com.migestor.shared.domain.*
import com.migestor.shared.repository.PlannerRepository
import com.migestor.shared.util.IsoWeekHelper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.datetime.Clock
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.LocalDate
import kotlinx.datetime.isoDayNumber
import kotlinx.datetime.plus

class PlannerRepositorySqlDelight(
    private val db: AppDatabase,
) : PlannerRepository {

    override fun observeTeachingUnits(groupId: Long?): Flow<List<TeachingUnit>> {
        return db.plannerQueries.selectTeachingUnits(groupId)
            .asFlow()
            .mapToList(Dispatchers.Default)
            .map { rows ->
                rows.map {
                    TeachingUnit(
                        id = it.id,
                        name = it.name,
                        description = it.description ?: "",
                        colorHex = it.color_hex ?: "#4A90D9",
                        groupId = it.group_id,
                        schoolClassId = it.school_class_id,
                        startDate = it.start_date?.let { LocalDate.parse(it) },
                        endDate = it.end_date?.let { LocalDate.parse(it) }
                    )
                }
            }
    }

    override suspend fun upsertTeachingUnit(unit: TeachingUnit): Long {
        val now = Clock.System.now().toEpochMilliseconds()
        return db.transactionWithResult {
            db.plannerQueries.upsertTeachingUnit(
                id = if (unit.id == 0L) null else unit.id,
                group_id = unit.groupId,
                name = unit.name,
                description = unit.description,
                color_hex = unit.colorHex,
                school_class_id = unit.schoolClassId,
                start_date = unit.startDate?.toString(),
                end_date = unit.endDate?.toString(),
                updated_at_epoch_ms = now,
                device_id = null,
                sync_version = 0L
            )
            if (unit.id == 0L) db.plannerQueries.lastInsertedId().executeAsOne() else unit.id
        }
    }

    override suspend fun deleteTeachingUnit(unitId: Long): Boolean {
        // En una implementación real, verificaríamos si hay sesiones antes de borrar
        db.plannerQueries.deleteTeachingUnit(unitId)
        return true
    }

    override fun observeSessions(weekNumber: Int, year: Int): Flow<List<PlanningSession>> {
        val days = IsoWeekHelper.daysOf(weekNumber, year)
        val startDate = days.first().toString()
        val endDate = days.last().toString()

        return db.plannerQueries.selectSessionsForWeek(startDate, endDate)
            .asFlow()
            .mapToList(Dispatchers.Default)
            .map { rows -> rows.map { mapToDomain(it) } }
    }

    override suspend fun listSessions(weekNumber: Int, year: Int): List<PlanningSession> {
        val days = IsoWeekHelper.daysOf(weekNumber, year)
        val startDate = days.first().toString()
        val endDate = days.last().toString()
        return db.plannerQueries.selectSessionsForWeek(startDate, endDate)
            .executeAsList()
            .map { mapToDomain(it) }
    }

    override suspend fun listSessionsInRange(groupId: Long?, fromDate: LocalDate, toDate: LocalDate): List<PlanningSession> {
        val all = db.plannerQueries.selectSessionsForWeek(fromDate.toString(), toDate.toString())
            .executeAsList()
            .map { mapToDomain(it) }
        return if (groupId == null) all else all.filter { it.groupId == groupId }
    }

    override suspend fun listAllSessions(): List<PlanningSession> {
        return db.plannerQueries.selectAllSessions()
            .executeAsList()
            .map { mapToDomain(it) }
    }

    override suspend fun upsertSession(session: PlanningSession): Long {
        val now = Clock.System.now().toEpochMilliseconds()
        val date = sessionDate(session).toString()
        return db.transactionWithResult {
            db.plannerQueries.upsertSession(
                id = if (session.id == 0L) null else session.id,
                date = date,
                group_id = session.groupId,
                period = session.period.toLong(),
                unit_id = if (session.teachingUnitId == 0L) null else session.teachingUnitId,
                objectives = session.objectives,
                activities = session.activities,
                evaluation = session.evaluation,
                linked_assessment_ids_csv = session.linkedAssessmentIdsCsv,
                status = session.status.name,
                updated_at_epoch_ms = now,
                device_id = null,
                sync_version = 0L
            )
            if (session.id == 0L) db.plannerQueries.lastInsertedId().executeAsOne() else session.id
        }
    }

    override suspend fun bulkUpsertSessions(sessions: List<PlanningSession>): List<Long> {
        if (sessions.isEmpty()) return emptyList()
        val ids = mutableListOf<Long>()
        db.transaction {
            sessions.forEach { session ->
                val now = Clock.System.now().toEpochMilliseconds()
                db.plannerQueries.upsertSession(
                    id = if (session.id == 0L) null else session.id,
                    date = sessionDate(session).toString(),
                    group_id = session.groupId,
                    period = session.period.toLong(),
                    unit_id = if (session.teachingUnitId == 0L) null else session.teachingUnitId,
                    objectives = session.objectives,
                    activities = session.activities,
                    evaluation = session.evaluation,
                    linked_assessment_ids_csv = session.linkedAssessmentIdsCsv,
                    status = session.status.name,
                    updated_at_epoch_ms = now,
                    device_id = null,
                    sync_version = 0L
                )
                ids += if (session.id == 0L) db.plannerQueries.lastInsertedId().executeAsOne() else session.id
            }
        }
        return ids
    }

    override suspend fun deleteSession(sessionId: Long) {
        db.plannerQueries.deleteSession(sessionId)
    }

    override suspend fun deleteSessions(sessionIds: List<Long>) {
        if (sessionIds.isEmpty()) return
        db.transaction {
            sessionIds.forEach { db.plannerQueries.deleteSession(it) }
        }
    }

    override suspend fun listAllTeachingUnits(): List<TeachingUnit> {
        return db.plannerQueries.selectAllTeachingUnits()
            .executeAsList()
            .map {
                TeachingUnit(
                    id = it.id,
                    name = it.name,
                    description = it.description ?: "",
                    colorHex = it.color_hex ?: "#4A90D9",
                    groupId = it.group_id,
                    schoolClassId = it.school_class_id,
                    startDate = it.start_date?.let(LocalDate::parse),
                    endDate = it.end_date?.let(LocalDate::parse),
                )
            }
    }

    override fun getTimeSlots(): List<TimeSlotConfig> {
        return DEFAULT_TIME_SLOTS
    }

    override suspend fun moveSessionsFromWeek(fromWeek: Int, fromYear: Int, offsetWeeks: Int) {
        if (offsetWeeks == 0) return
        val source = listSessions(fromWeek, fromYear)
        if (source.isEmpty()) return
        shiftSelectedSessions(
            request = SessionRelocationRequest(
                sourceSessionIds = source.map { it.id },
                dayOffset = offsetWeeks * 7
            ),
            resolution = CollisionResolution.SKIP
        )
    }

    override suspend fun previewSessionRelocation(request: SessionRelocationRequest): List<SessionRelocationConflict> {
        return buildRelocationPlan(request).conflicts
    }

    override suspend fun copySessions(
        request: SessionRelocationRequest,
        resolution: CollisionResolution
    ): SessionBulkResult {
        val plan = buildRelocationPlan(request)
        if (plan.relocations.isEmpty()) return SessionBulkResult(skipped = plan.conflicts.size)
        if (resolution == CollisionResolution.CANCEL && plan.conflicts.isNotEmpty()) {
            return SessionBulkResult(skipped = plan.relocations.size, failed = plan.conflicts.size)
        }

        val conflictBySource = plan.conflicts.associateBy { it.sourceSessionId }
        val sessionsToApply = when (resolution) {
            CollisionResolution.SKIP -> plan.relocations.filter { conflictBySource[it.source.id] == null }
            CollisionResolution.OVERWRITE -> plan.relocations
            CollisionResolution.CANCEL -> emptyList()
        }
        if (sessionsToApply.isEmpty()) {
            return SessionBulkResult(skipped = plan.relocations.size, failed = plan.conflicts.size)
        }

        val overwrittenIds = mutableSetOf<Long>()
        val insertedIds = mutableListOf<Long>()
        db.transaction {
            sessionsToApply.forEach { relocation ->
                val existingId = conflictBySource[relocation.source.id]?.existingSessionId
                if (resolution == CollisionResolution.OVERWRITE && existingId != null) {
                    db.plannerQueries.deleteSession(existingId)
                    overwrittenIds += existingId
                }
                insertedIds += insertPlannerSession(relocation.destination)
            }
        }

        return SessionBulkResult(
            affectedSessionIds = insertedIds,
            movedOrCopied = insertedIds.size,
            overwritten = overwrittenIds.size,
            skipped = if (resolution == CollisionResolution.SKIP) plan.conflicts.size else 0,
            failed = 0
        )
    }

    override suspend fun shiftSelectedSessions(
        request: SessionRelocationRequest,
        resolution: CollisionResolution
    ): SessionBulkResult {
        val plan = buildRelocationPlan(request)
        if (plan.relocations.isEmpty()) return SessionBulkResult(skipped = plan.conflicts.size)
        if (resolution == CollisionResolution.CANCEL && plan.conflicts.isNotEmpty()) {
            return SessionBulkResult(skipped = plan.relocations.size, failed = plan.conflicts.size)
        }

        val conflictBySource = plan.conflicts.associateBy { it.sourceSessionId }
        val sessionsToApply = when (resolution) {
            CollisionResolution.SKIP -> plan.relocations.filter { conflictBySource[it.source.id] == null }
            CollisionResolution.OVERWRITE -> plan.relocations
            CollisionResolution.CANCEL -> emptyList()
        }
        if (sessionsToApply.isEmpty()) {
            return SessionBulkResult(skipped = plan.relocations.size, failed = plan.conflicts.size)
        }

        val sourceIds = sessionsToApply.map { it.source.id }.toSet()
        val overwrittenIds = mutableSetOf<Long>()
        val insertedIds = mutableListOf<Long>()

        db.transaction {
            if (resolution == CollisionResolution.OVERWRITE) {
                sessionsToApply.forEach { relocation ->
                    val existingId = conflictBySource[relocation.source.id]?.existingSessionId
                    if (existingId != null && existingId !in sourceIds) {
                        db.plannerQueries.deleteSession(existingId)
                        overwrittenIds += existingId
                    }
                }
            }

            sourceIds.forEach { db.plannerQueries.deleteSession(it) }
            sessionsToApply.forEach { relocation ->
                insertedIds += insertPlannerSession(relocation.destination)
            }
        }

        return SessionBulkResult(
            affectedSessionIds = insertedIds,
            movedOrCopied = insertedIds.size,
            overwritten = overwrittenIds.size,
            skipped = if (resolution == CollisionResolution.SKIP) plan.conflicts.size else 0,
            failed = 0
        )
    }

    private fun sessionDate(session: PlanningSession): LocalDate {
        val days = IsoWeekHelper.daysOf(session.weekNumber, session.year)
        return days[(session.dayOfWeek - 1).coerceIn(0, days.lastIndex)]
    }

    private data class SessionRelocationItem(
        val source: PlanningSession,
        val destination: PlanningSession
    )

    private data class SessionRelocationPlan(
        val relocations: List<SessionRelocationItem>,
        val conflicts: List<SessionRelocationConflict>
    )

    private fun buildRelocationPlan(request: SessionRelocationRequest): SessionRelocationPlan {
        if (request.sourceSessionIds.isEmpty()) return SessionRelocationPlan(emptyList(), emptyList())

        val sourceRows = db.plannerQueries.selectAllSessions().executeAsList()
            .filter { request.sourceSessionIds.contains(it.id) }
        val sourceIds = sourceRows.map { it.id }.toSet()
        val conflicts = mutableListOf<SessionRelocationConflict>()
        val relocations = mutableListOf<SessionRelocationItem>()

        sourceRows.forEach { row ->
            val sourceDate = LocalDate.parse(row.date)
            val sourceSession = mapToDomain(row)
            val destinationGroupId = request.targetGroupId ?: sourceSession.groupId
            val destinationPeriod = request.targetPeriod ?: (sourceSession.period + request.periodOffset)

            if (destinationPeriod <= 0) {
                conflicts += SessionRelocationConflict(
                    sourceSessionId = sourceSession.id,
                    destinationDate = sourceDate,
                    destinationGroupId = destinationGroupId,
                    destinationPeriod = destinationPeriod,
                    reason = "Periodo fuera de rango"
                )
                return@forEach
            }

            val destinationDate = if (request.targetDayOfWeek != null) {
                val currentDay = sourceDate.dayOfWeek.isoDayNumber
                val targetDay = request.targetDayOfWeek
                sourceDate.plus(((targetDay ?: currentDay) - currentDay).toLong(), DateTimeUnit.DAY)
            } else {
                sourceDate.plus(request.dayOffset.toLong(), DateTimeUnit.DAY)
            }

            val existingAtDestination = db.plannerQueries
                .selectSessionsByDateAndGroup(destinationDate.toString(), destinationGroupId)
                .executeAsList()
                .firstOrNull { it.period.toInt() == destinationPeriod }

            if (existingAtDestination != null && existingAtDestination.id !in sourceIds) {
                conflicts += SessionRelocationConflict(
                    sourceSessionId = sourceSession.id,
                    destinationDate = destinationDate,
                    destinationGroupId = destinationGroupId,
                    destinationPeriod = destinationPeriod,
                    existingSessionId = existingAtDestination.id,
                    reason = "Destino ocupado"
                )
            }

            val destination = sourceSession.copy(
                id = 0,
                groupId = destinationGroupId,
                dayOfWeek = destinationDate.dayOfWeek.isoDayNumber,
                period = destinationPeriod,
                weekNumber = IsoWeekHelper.isoWeekOf(destinationDate),
                year = destinationDate.year
            )
            relocations += SessionRelocationItem(source = sourceSession, destination = destination)
        }

        return SessionRelocationPlan(relocations, conflicts)
    }

    private fun insertPlannerSession(session: PlanningSession): Long {
        val now = Clock.System.now().toEpochMilliseconds()
        db.plannerQueries.upsertSession(
            id = if (session.id == 0L) null else session.id,
            date = sessionDate(session).toString(),
            group_id = session.groupId,
            period = session.period.toLong(),
            unit_id = if (session.teachingUnitId == 0L) null else session.teachingUnitId,
            objectives = session.objectives,
            activities = session.activities,
            evaluation = session.evaluation,
            linked_assessment_ids_csv = session.linkedAssessmentIdsCsv,
            status = session.status.name,
            updated_at_epoch_ms = now,
            device_id = null,
            sync_version = 0L
        )
        return if (session.id == 0L) db.plannerQueries.lastInsertedId().executeAsOne() else session.id
    }

    private fun mapToDomain(row: com.migestor.data.db.SelectSessionsForWeek): PlanningSession {
        val date = LocalDate.parse(row.date)
        return PlanningSession(
            id = row.id,
            teachingUnitId = row.unit_id ?: 0,
            teachingUnitName = row.unit_name ?: "",
            teachingUnitColor = row.unit_color ?: "#4A90D9",
            groupId = row.group_id,
            groupName = row.group_name,
            dayOfWeek = date.dayOfWeek.isoDayNumber,
            period = row.period.toInt(),
            weekNumber = IsoWeekHelper.isoWeekOf(date),
            year = date.year,
            objectives = row.objectives ?: "",
            activities = row.activities ?: "",
            evaluation = row.evaluation ?: "",
            linkedAssessmentIdsCsv = row.linked_assessment_ids_csv,
            status = try { SessionStatus.valueOf(row.status ?: "PLANNED") } catch (e: Exception) { SessionStatus.PLANNED }
        )
    }

    private fun mapToDomain(row: com.migestor.data.db.SelectAllSessions): PlanningSession {
        val date = LocalDate.parse(row.date)
        return PlanningSession(
            id = row.id,
            teachingUnitId = row.unit_id ?: 0,
            teachingUnitName = row.unit_name ?: "",
            teachingUnitColor = row.unit_color ?: "#4A90D9",
            groupId = row.group_id,
            groupName = row.group_name,
            dayOfWeek = date.dayOfWeek.isoDayNumber,
            period = row.period.toInt(),
            weekNumber = IsoWeekHelper.isoWeekOf(date),
            year = date.year,
            objectives = row.objectives ?: "",
            activities = row.activities ?: "",
            evaluation = row.evaluation ?: "",
            linkedAssessmentIdsCsv = row.linked_assessment_ids_csv,
            status = try { SessionStatus.valueOf(row.status ?: "PLANNED") } catch (e: Exception) { SessionStatus.PLANNED }
        )
    }
}
