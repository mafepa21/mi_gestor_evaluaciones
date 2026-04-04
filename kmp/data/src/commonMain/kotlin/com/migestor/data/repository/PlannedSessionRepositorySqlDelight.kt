package com.migestor.data.repository

import com.migestor.data.db.AppDatabase
import com.migestor.shared.domain.PlannedSession
import com.migestor.shared.repository.PlannedSessionRepository
import kotlinx.datetime.LocalDate
import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

class PlannedSessionRepositorySqlDelight(
    private val db: AppDatabase
) : PlannedSessionRepository {

    override fun observeSessionsForClass(
        schoolClassId: Long,
        startDate: LocalDate,
        endDate: LocalDate
    ): Flow<List<PlannedSession>> {
        return db.plannerQueries.selectPlannedSessionsForClass(
            school_class_id = schoolClassId,
            date = startDate.toString(),
            date_ = endDate.toString()
        ).asFlow().mapToList(Dispatchers.Default).map { list ->
            list.map { it.toDomain() }
        }
    }

    override fun observeAllSessions(startDate: LocalDate, endDate: LocalDate): Flow<List<PlannedSession>> {
        return db.plannerQueries.selectPlannedSessionsForRange(
            date = startDate.toString(),
            date_ = endDate.toString()
        ).asFlow().mapToList(Dispatchers.Default).map { list ->
            list.map { it.toDomain() }
        }
    }

    override suspend fun getSessionsForClass(
        schoolClassId: Long,
        startDate: LocalDate,
        endDate: LocalDate
    ): List<PlannedSession> {
        return db.plannerQueries.selectPlannedSessionsForClass(
            school_class_id = schoolClassId,
            date = startDate.toString(),
            date_ = endDate.toString()
        ).executeAsList().map { it.toDomain() }
    }

    override suspend fun getAllSessions(startDate: LocalDate, endDate: LocalDate): List<PlannedSession> {
        return db.plannerQueries.selectPlannedSessionsForRange(
            date = startDate.toString(),
            date_ = endDate.toString()
        ).executeAsList().map { it.toDomain() }
    }

    override suspend fun listSessionsInRange(
        schoolClassId: Long?,
        startDate: LocalDate,
        endDate: LocalDate
    ): List<PlannedSession> {
        return if (schoolClassId != null) {
            getSessionsForClass(schoolClassId, startDate, endDate)
        } else {
            getAllSessions(startDate, endDate)
        }
    }

    private fun com.migestor.data.db.Planned_session.toDomain() = PlannedSession(
        id = id,
        teachingUnitId = teaching_unit_id,
        schoolClassId = school_class_id,
        date = LocalDate.parse(date),
        startTime = start_time,
        endTime = end_time,
        title = title,
        objectives = objectives,
        resources = resources,
        notes = notes
    )

    override suspend fun existsAt(schoolClassId: Long, date: LocalDate, startTime: String): Boolean {
        return db.plannerQueries.existsPlannedSession(schoolClassId, date.toString(), startTime).executeAsOne()
    }

    override suspend fun insert(session: PlannedSession): Long {
        db.plannerQueries.insertPlannedSession(
            teaching_unit_id = session.teachingUnitId,
            school_class_id = session.schoolClassId,
            date = session.date.toString(),
            start_time = session.startTime,
            end_time = session.endTime,
            title = session.title,
            objectives = session.objectives,
            resources = session.resources,
            notes = session.notes
        )
        return db.plannerQueries.lastInsertedId().executeAsOne()
    }

    override suspend fun update(session: PlannedSession) {
        db.plannerQueries.updatePlannedSession(
            title = session.title,
            objectives = session.objectives,
            resources = session.resources,
            notes = session.notes,
            id = session.id
        )
    }

    override suspend fun delete(sessionId: Long) {
        db.plannerQueries.deletePlannedSession(sessionId)
    }

    override suspend fun deleteSessions(sessionIds: List<Long>) {
        if (sessionIds.isEmpty()) return
        db.transaction {
            sessionIds.forEach { db.plannerQueries.deletePlannedSession(it) }
        }
    }

    override suspend fun bulkUpsertOrReplacePlannedSessions(sessions: List<PlannedSession>): List<Long> {
        if (sessions.isEmpty()) return emptyList()
        val groupedByClass = sessions.groupBy { it.schoolClassId }
        val insertedIds = mutableListOf<Long>()
        db.transaction {
            groupedByClass.forEach { (classId, classSessions) ->
                val minDate = classSessions.minOf { it.date }
                val maxDate = classSessions.maxOf { it.date }
                val existing = db.plannerQueries.selectPlannedSessionsForClass(
                    school_class_id = classId,
                    date = minDate.toString(),
                    date_ = maxDate.toString()
                ).executeAsList().map { it.toDomain() }
                val existingByKey = existing.associateBy { Triple(it.schoolClassId, it.date, it.startTime) }
                classSessions.forEach { session ->
                    val key = Triple(session.schoolClassId, session.date, session.startTime)
                    existingByKey[key]?.let { db.plannerQueries.deletePlannedSession(it.id) }
                    db.plannerQueries.insertPlannedSession(
                        teaching_unit_id = session.teachingUnitId,
                        school_class_id = session.schoolClassId,
                        date = session.date.toString(),
                        start_time = session.startTime,
                        end_time = session.endTime,
                        title = session.title,
                        objectives = session.objectives,
                        resources = session.resources,
                        notes = session.notes
                    )
                    insertedIds += db.plannerQueries.lastInsertedId().executeAsOne()
                }
            }
        }
        return insertedIds
    }
}
