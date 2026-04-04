package com.migestor.data.repository

import com.migestor.data.db.AppDatabase
import com.migestor.shared.domain.AcademicYear
import com.migestor.shared.domain.AppUser
import com.migestor.shared.domain.AuditTrace
import com.migestor.shared.domain.PlannerEvaluationPeriod
import com.migestor.shared.domain.PlannerSessionForecast
import com.migestor.shared.domain.TeacherSchedule
import com.migestor.shared.domain.TeacherScheduleSlot
import com.migestor.shared.domain.UserRole
import com.migestor.shared.repository.CalendarRepository
import com.migestor.shared.repository.ClassesRepository
import com.migestor.shared.repository.PlannerRepository
import com.migestor.shared.repository.TeacherScheduleRepository
import kotlinx.datetime.Clock
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.isoDayNumber
import kotlinx.datetime.minus
import kotlinx.datetime.plus
import kotlinx.datetime.toLocalDateTime

class TeacherScheduleRepositorySqlDelight(
    private val db: AppDatabase,
    private val plannerRepository: PlannerRepository,
    private val calendarRepository: CalendarRepository,
    private val classesRepository: ClassesRepository,
) : TeacherScheduleRepository {

    override suspend fun getOrCreatePrimarySchedule(): TeacherSchedule {
        return runCatching {
            val teacher = ensureTeacher()
            val academicYear = ensureAcademicYear(centerId = teacher.centerId ?: ensureCenterId())
            val existing = db.appDatabaseQueries.selectAllTeacherSchedules().executeAsList().firstOrNull {
                it.owner_user_id == teacher.id && it.academic_year_id == academicYear.id
            }
            if (existing != null) {
                return@runCatching TeacherSchedule(
                    id = existing.id,
                    ownerUserId = existing.owner_user_id,
                    academicYearId = existing.academic_year_id,
                    name = existing.name,
                    startDateIso = existing.start_date,
                    endDateIso = existing.end_date,
                    activeWeekdaysCsv = existing.active_weekdays,
                    trace = AuditTrace(
                        authorUserId = existing.author_user_id,
                        createdAt = Instant.fromEpochMilliseconds(existing.created_at_epoch_ms),
                        updatedAt = Instant.fromEpochMilliseconds(existing.updated_at_epoch_ms),
                        associatedGroupId = existing.associated_group_id,
                        deviceId = existing.device_id,
                        syncVersion = existing.sync_version
                    )
                )
            }

            val now = Clock.System.now().toEpochMilliseconds()
            val created = TeacherSchedule(
                ownerUserId = teacher.id,
                academicYearId = academicYear.id,
                name = "Agenda docente",
                startDateIso = academicYear.startAt.toLocalDateTime(TimeZone.currentSystemDefault()).date.toString(),
                endDateIso = academicYear.endAt.toLocalDateTime(TimeZone.currentSystemDefault()).date.toString(),
                activeWeekdaysCsv = "1,2,3,4,5",
                trace = AuditTrace(
                    authorUserId = teacher.id,
                    createdAt = Instant.fromEpochMilliseconds(now),
                    updatedAt = Instant.fromEpochMilliseconds(now)
                )
            )
            val id = saveSchedule(created)
            created.copy(id = id)
        }.getOrElse { throwable ->
            println("TeacherScheduleRepositorySqlDelight.getOrCreatePrimarySchedule failed: ${throwable.message}")
            fallbackSchedule()
        }
    }

    override suspend fun saveSchedule(schedule: TeacherSchedule): Long {
        return runCatching {
            val now = Clock.System.now().toEpochMilliseconds()
            db.appDatabaseQueries.upsertTeacherSchedule(
                id = schedule.id.takeIf { it != 0L },
                owner_user_id = schedule.ownerUserId,
                academic_year_id = schedule.academicYearId,
                name = schedule.name,
                start_date = schedule.startDateIso,
                end_date = schedule.endDateIso,
                active_weekdays = schedule.activeWeekdaysCsv,
                author_user_id = schedule.trace.authorUserId,
                created_at_epoch_ms = schedule.trace.createdAt.toEpochMilliseconds().takeIf { it > 0 } ?: now,
                updated_at_epoch_ms = now,
                associated_group_id = schedule.trace.associatedGroupId,
                device_id = schedule.trace.deviceId,
                sync_version = schedule.trace.syncVersion
            )
            if (schedule.id == 0L) db.plannerQueries.lastInsertedId().executeAsOne() else schedule.id
        }.getOrElse { throwable ->
            println("TeacherScheduleRepositorySqlDelight.saveSchedule failed: ${throwable.message}")
            schedule.id
        }
    }

    override suspend fun listScheduleSlots(scheduleId: Long): List<TeacherScheduleSlot> {
        return runCatching {
            db.appDatabaseQueries.selectTeacherScheduleSlots(scheduleId).executeAsList().map { row ->
                TeacherScheduleSlot(
                    id = row.id,
                    teacherScheduleId = row.teacher_schedule_id,
                    schoolClassId = row.school_class_id,
                    subjectLabel = row.subject_label,
                    unitLabel = row.unit_label,
                    dayOfWeek = row.day_of_week.toInt(),
                    startTime = row.start_time,
                    endTime = row.end_time,
                    weeklyTemplateId = row.weekly_template_id
                )
            }
        }.getOrElse { throwable ->
            println("TeacherScheduleRepositorySqlDelight.listScheduleSlots failed: ${throwable.message}")
            emptyList()
        }
    }

    override suspend fun getScheduleSlot(slotId: Long): TeacherScheduleSlot? {
        return runCatching {
            db.appDatabaseQueries.selectTeacherScheduleSlotById(slotId).executeAsOneOrNull()?.let { row ->
                TeacherScheduleSlot(
                    id = row.id,
                    teacherScheduleId = row.teacher_schedule_id,
                    schoolClassId = row.school_class_id,
                    subjectLabel = row.subject_label,
                    unitLabel = row.unit_label,
                    dayOfWeek = row.day_of_week.toInt(),
                    startTime = row.start_time,
                    endTime = row.end_time,
                    weeklyTemplateId = row.weekly_template_id
                )
            }
        }.getOrElse { throwable ->
            println("TeacherScheduleRepositorySqlDelight.getScheduleSlot failed: ${throwable.message}")
            null
        }
    }

    override suspend fun saveScheduleSlot(slot: TeacherScheduleSlot): Long {
        return runCatching {
            db.appDatabaseQueries.upsertTeacherScheduleSlot(
                id = slot.id.takeIf { it != 0L },
                teacher_schedule_id = slot.teacherScheduleId,
                school_class_id = slot.schoolClassId,
                subject_label = slot.subjectLabel,
                unit_label = slot.unitLabel,
                day_of_week = slot.dayOfWeek.toLong(),
                start_time = slot.startTime,
                end_time = slot.endTime,
                weekly_template_id = slot.weeklyTemplateId
            )
            if (slot.id == 0L) db.plannerQueries.lastInsertedId().executeAsOne() else slot.id
        }.getOrElse { throwable ->
            println("TeacherScheduleRepositorySqlDelight.saveScheduleSlot failed: ${throwable.message}")
            slot.id
        }
    }

    override suspend fun deleteScheduleSlot(slotId: Long) {
        runCatching {
            db.appDatabaseQueries.deleteTeacherScheduleSlot(slotId)
        }.onFailure { throwable ->
            println("TeacherScheduleRepositorySqlDelight.deleteScheduleSlot failed: ${throwable.message}")
        }
    }

    override suspend fun listEvaluationPeriods(scheduleId: Long): List<PlannerEvaluationPeriod> {
        return runCatching {
            db.appDatabaseQueries.selectPlannerEvaluationPeriods(scheduleId).executeAsList().map { row ->
                PlannerEvaluationPeriod(
                    id = row.id,
                    teacherScheduleId = row.teacher_schedule_id,
                    name = row.name,
                    startDateIso = row.start_date,
                    endDateIso = row.end_date,
                    sortOrder = row.sort_order.toInt()
                )
            }
        }.getOrElse { throwable ->
            println("TeacherScheduleRepositorySqlDelight.listEvaluationPeriods failed: ${throwable.message}")
            emptyList()
        }
    }

    override suspend fun saveEvaluationPeriod(period: PlannerEvaluationPeriod): Long {
        return runCatching {
            db.appDatabaseQueries.upsertPlannerEvaluationPeriod(
                id = period.id.takeIf { it != 0L },
                teacher_schedule_id = period.teacherScheduleId,
                name = period.name,
                start_date = period.startDateIso,
                end_date = period.endDateIso,
                sort_order = period.sortOrder.toLong()
            )
            if (period.id == 0L) db.plannerQueries.lastInsertedId().executeAsOne() else period.id
        }.getOrElse { throwable ->
            println("TeacherScheduleRepositorySqlDelight.saveEvaluationPeriod failed: ${throwable.message}")
            period.id
        }
    }

    override suspend fun deleteEvaluationPeriod(periodId: Long) {
        runCatching {
            db.appDatabaseQueries.deletePlannerEvaluationPeriod(periodId)
        }.onFailure { throwable ->
            println("TeacherScheduleRepositorySqlDelight.deleteEvaluationPeriod failed: ${throwable.message}")
        }
    }

    override suspend fun buildForecasts(scheduleId: Long, classId: Long?): List<PlannerSessionForecast> {
        return runCatching {
            val schedule = getOrCreatePrimarySchedule().takeIf { it.id == scheduleId }
                ?: db.appDatabaseQueries.selectAllTeacherSchedules().executeAsList().firstOrNull { it.id == scheduleId }?.let { row ->
                    TeacherSchedule(
                        id = row.id,
                        ownerUserId = row.owner_user_id,
                        academicYearId = row.academic_year_id,
                        name = row.name,
                        startDateIso = row.start_date,
                        endDateIso = row.end_date,
                        activeWeekdaysCsv = row.active_weekdays,
                        trace = AuditTrace(
                            authorUserId = row.author_user_id,
                            createdAt = Instant.fromEpochMilliseconds(row.created_at_epoch_ms),
                            updatedAt = Instant.fromEpochMilliseconds(row.updated_at_epoch_ms),
                            associatedGroupId = row.associated_group_id,
                            deviceId = row.device_id,
                            syncVersion = row.sync_version
                        )
                    )
                }
                ?: return@runCatching emptyList()

            val periods = listEvaluationPeriods(schedule.id)
            if (periods.isEmpty()) return@runCatching emptyList()

            val scheduleStart = LocalDate.parse(schedule.startDateIso)
            val scheduleEnd = LocalDate.parse(schedule.endDateIso)
            val activeWeekdays = schedule.activeWeekdaysCsv.split(",").mapNotNull { it.trim().toIntOrNull() }.toSet()
            val slots = listScheduleSlots(schedule.id).filter { slot ->
                (classId == null || slot.schoolClassId == classId) && activeWeekdays.contains(slot.dayOfWeek)
            }
            if (slots.isEmpty()) return@runCatching emptyList()

            val classesById = classesRepository.listClasses().associateBy { it.id }
            val calendarEvents = calendarRepository.listEvents(classId = null)
            val sessionsByClass = plannerRepository.listSessionsInRange(
                groupId = classId,
                fromDate = scheduleStart,
                toDate = scheduleEnd
            ).groupBy { it.groupId }

            return@runCatching periods.flatMap { period ->
                val periodStart = maxOf(scheduleStart, LocalDate.parse(period.startDateIso))
                val periodEnd = minOf(scheduleEnd, LocalDate.parse(period.endDateIso))
                if (periodEnd < periodStart) {
                    emptyList()
                } else {
                    val periodSlots = slots.groupBy { it.schoolClassId }
                    periodSlots.map { (schoolClassId, classSlots) ->
                        val expected = classSlots.sumOf { slot: TeacherScheduleSlot ->
                            countExpectedSessions(
                                start = periodStart,
                                end = periodEnd,
                                slot = slot,
                                calendarEvents = calendarEvents
                            )
                        }
                        val planned = sessionsByClass[schoolClassId].orEmpty().count { session ->
                            val sessionDate = isoWeekDate(year = session.year.toInt(), week = session.weekNumber.toInt(), dayOfWeek = session.dayOfWeek.toInt())
                            sessionDate != null && sessionDate >= periodStart && sessionDate <= periodEnd
                        }
                        PlannerSessionForecast(
                            periodId = period.id,
                            periodName = period.name,
                            schoolClassId = schoolClassId,
                            className = classesById[schoolClassId]?.name ?: "Grupo $schoolClassId",
                            expectedSessions = expected,
                            plannedSessions = planned,
                            remainingSessions = expected - planned
                        )
                    }
                }
            }
        }.getOrElse { throwable ->
            println("TeacherScheduleRepositorySqlDelight.buildForecasts failed: ${throwable.message}")
            emptyList()
        }
    }

    private fun fallbackSchedule(): TeacherSchedule {
        val now = Clock.System.now()
        val today = now.toLocalDateTime(TimeZone.currentSystemDefault()).date
        val startYear = if (today.monthNumber >= 8) today.year else today.year - 1
        val endYear = startYear + 1
        return TeacherSchedule(
            id = 0L,
            ownerUserId = 1L,
            academicYearId = 1L,
            name = "Agenda docente",
            startDateIso = LocalDate(startYear, 9, 1).toString(),
            endDateIso = LocalDate(endYear, 6, 30).toString(),
            activeWeekdaysCsv = "1,2,3,4,5",
            trace = AuditTrace(
                authorUserId = 1L,
                createdAt = now,
                updatedAt = now
            )
        )
    }

    private suspend fun ensureCenterId(): Long {
        val existing = db.appDatabaseQueries.selectAllCenters().executeAsList().firstOrNull()
        if (existing != null) return existing.id
        val now = Clock.System.now().toEpochMilliseconds()
        db.appDatabaseQueries.upsertCenter(
            id = 1L,
            code = "DEFAULT",
            name = "Centro MiGestor",
            author_user_id = null,
            created_at_epoch_ms = now,
            updated_at_epoch_ms = now,
            associated_group_id = null,
            device_id = null,
            sync_version = 0L
        )
        return 1L
    }

    private suspend fun ensureTeacher(): AppUser {
        val existing = db.appDatabaseQueries.selectAllAppUsers().executeAsList().firstOrNull { it.role == UserRole.DOCENTE.name }
        if (existing != null) {
            return AppUser(
                id = existing.id,
                externalId = existing.external_id,
                displayName = existing.display_name,
                email = existing.email,
                role = runCatching { UserRole.valueOf(existing.role) }.getOrDefault(UserRole.DOCENTE),
                centerId = existing.center_id,
                trace = AuditTrace(
                    authorUserId = existing.author_user_id,
                    createdAt = Instant.fromEpochMilliseconds(existing.created_at_epoch_ms),
                    updatedAt = Instant.fromEpochMilliseconds(existing.updated_at_epoch_ms),
                    associatedGroupId = existing.associated_group_id,
                    deviceId = existing.device_id,
                    syncVersion = existing.sync_version
                )
            )
        }

        val centerId = ensureCenterId()
        val now = Clock.System.now().toEpochMilliseconds()
        db.appDatabaseQueries.upsertAppUser(
            id = 1L,
            external_id = null,
            display_name = "Profesor/a",
            email = null,
            role = UserRole.DOCENTE.name,
            center_id = centerId,
            author_user_id = 1L,
            created_at_epoch_ms = now,
            updated_at_epoch_ms = now,
            associated_group_id = null,
            device_id = null,
            sync_version = 0L
        )
        return AppUser(id = 1L, displayName = "Profesor/a", role = UserRole.DOCENTE, centerId = centerId)
    }

    private suspend fun ensureAcademicYear(centerId: Long): AcademicYear {
        val existing = db.appDatabaseQueries.selectAllAcademicYears().executeAsList().firstOrNull()
        if (existing != null) {
            return AcademicYear(
                id = existing.id,
                centerId = existing.center_id,
                name = existing.name,
                startAt = Instant.fromEpochMilliseconds(existing.start_epoch_ms),
                endAt = Instant.fromEpochMilliseconds(existing.end_epoch_ms),
                trace = AuditTrace(
                    authorUserId = existing.author_user_id,
                    createdAt = Instant.fromEpochMilliseconds(existing.created_at_epoch_ms),
                    updatedAt = Instant.fromEpochMilliseconds(existing.updated_at_epoch_ms),
                    associatedGroupId = existing.associated_group_id,
                    deviceId = existing.device_id,
                    syncVersion = existing.sync_version
                )
            )
        }

        val today = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
        val startYear = if (today.monthNumber >= 8) today.year else today.year - 1
        val endYear = startYear + 1
        val startDate = LocalDate(startYear, 9, 1)
        val endDate = LocalDate(endYear, 6, 30)
        val now = Clock.System.now().toEpochMilliseconds()
        db.appDatabaseQueries.upsertAcademicYear(
            id = 1L,
            center_id = centerId,
            name = "${startYear}/${endYear}",
            start_epoch_ms = startDate.atStartOfDayIn(TimeZone.currentSystemDefault()).toEpochMilliseconds(),
            end_epoch_ms = endDate.atStartOfDayIn(TimeZone.currentSystemDefault()).toEpochMilliseconds(),
            author_user_id = 1L,
            created_at_epoch_ms = now,
            updated_at_epoch_ms = now,
            associated_group_id = null,
            device_id = null,
            sync_version = 0L
        )
        return AcademicYear(
            id = 1L,
            centerId = centerId,
            name = "${startYear}/${endYear}",
            startAt = startDate.atStartOfDayIn(TimeZone.currentSystemDefault()),
            endAt = endDate.atStartOfDayIn(TimeZone.currentSystemDefault())
        )
    }

    private fun countExpectedSessions(
        start: LocalDate,
        end: LocalDate,
        slot: TeacherScheduleSlot,
        calendarEvents: List<com.migestor.shared.domain.CalendarEvent>
    ): Int {
        var count = 0
        var cursor = start
        while (cursor <= end) {
            if (cursor.dayOfWeek.isoDayNumber == slot.dayOfWeek && !isBlockedDate(cursor, slot.schoolClassId, calendarEvents)) {
                count += 1
            }
            cursor = cursor.plus(1, DateTimeUnit.DAY)
        }
        return count
    }

    private fun isBlockedDate(
        date: LocalDate,
        schoolClassId: Long,
        calendarEvents: List<com.migestor.shared.domain.CalendarEvent>
    ): Boolean {
        return calendarEvents.any { event ->
            val eventDate = event.startAt.toLocalDateTime(TimeZone.currentSystemDefault()).date
            val matchesScope = event.classId == null || event.classId == schoolClassId
            matchesScope && eventDate == date && isNonTeachingEvent(event.title, event.description)
        }
    }

    private fun isNonTeachingEvent(title: String, description: String?): Boolean {
        val haystack = listOf(title, description.orEmpty()).joinToString(" ").lowercase()
        return listOf("festivo", "no lectivo", "vacaciones", "puente", "holiday").any { haystack.contains(it) }
    }

    private fun isoWeekDate(year: Int, week: Int, dayOfWeek: Int): LocalDate? {
        val januaryFourth = LocalDate(year, 1, 4)
        val firstMonday = januaryFourth.minus((januaryFourth.dayOfWeek.isoDayNumber - 1).toLong(), DateTimeUnit.DAY)
        return firstMonday.plus(((week - 1) * 7L) + (dayOfWeek - 1L), DateTimeUnit.DAY)
    }
}
