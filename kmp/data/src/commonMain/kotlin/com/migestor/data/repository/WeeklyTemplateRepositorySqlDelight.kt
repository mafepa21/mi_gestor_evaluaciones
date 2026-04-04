package com.migestor.data.repository

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import com.migestor.data.db.AppDatabase
import com.migestor.shared.domain.WeeklySlotTemplate
import com.migestor.shared.repository.WeeklyTemplateRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

class WeeklyTemplateRepositorySqlDelight(
    private val db: AppDatabase
) : WeeklyTemplateRepository {
    override fun getSlotsForClass(schoolClassId: Long): List<WeeklySlotTemplate> {
        return db.plannerQueries.selectSlotsForClass(schoolClassId).executeAsList().map {
            WeeklySlotTemplate(
                id = it.id,
                schoolClassId = it.school_class_id,
                dayOfWeek = it.day_of_week.toInt(),
                startTime = it.start_time,
                endTime = it.end_time
            )
        }
    }

    override fun observeAllSlots(): Flow<List<WeeklySlotTemplate>> {
        return db.plannerQueries.selectAllWeeklySlots()
            .asFlow()
            .mapToList(Dispatchers.Default)
            .map { rows ->
                rows.map {
                    WeeklySlotTemplate(
                        id = it.id,
                        schoolClassId = it.school_class_id,
                        dayOfWeek = it.day_of_week.toInt(),
                        startTime = it.start_time,
                        endTime = it.end_time
                    )
                }
            }
    }

    override suspend fun insert(slot: WeeklySlotTemplate): Long {
        db.plannerQueries.upsertWeeklySlot(
            id = if (slot.id == 0L) null else slot.id,
            school_class_id = slot.schoolClassId,
            day_of_week = slot.dayOfWeek.toLong(),
            start_time = slot.startTime,
            end_time = slot.endTime
        )
        return if (slot.id == 0L) db.plannerQueries.lastInsertedId().executeAsOne() else slot.id
    }

    override suspend fun delete(slotId: Long) {
        db.plannerQueries.deleteWeeklySlot(slotId)
    }
}
