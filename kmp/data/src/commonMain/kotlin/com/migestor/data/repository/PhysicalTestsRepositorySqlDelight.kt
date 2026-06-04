package com.migestor.data.repository

import com.migestor.data.db.AppDatabase
import com.migestor.shared.domain.AuditTrace
import com.migestor.shared.domain.PhysicalCapacity
import com.migestor.shared.domain.PhysicalMeasurementKind
import com.migestor.shared.domain.PhysicalResultMode
import com.migestor.shared.domain.PhysicalScaleDirection
import com.migestor.shared.domain.PhysicalTestAssignment
import com.migestor.shared.domain.PhysicalTestAttempt
import com.migestor.shared.domain.PhysicalTestBattery
import com.migestor.shared.domain.PhysicalTestDefinition
import com.migestor.shared.domain.PhysicalTestNotebookLink
import com.migestor.shared.domain.PhysicalTestResult
import com.migestor.shared.domain.PhysicalTestScale
import com.migestor.shared.domain.PhysicalTestScaleRange
import com.migestor.shared.domain.StudentSex
import com.migestor.shared.domain.normalizedStudentSex
import com.migestor.shared.repository.PhysicalTestsRepository
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

class PhysicalTestsRepositorySqlDelight(
    private val db: AppDatabase,
) : PhysicalTestsRepository {
    override suspend fun listDefinitions(): List<PhysicalTestDefinition> {
        return db.appDatabaseQueries.selectPhysicalDefinitions().executeAsList().map { row ->
            PhysicalTestDefinition(
                id = row.id,
                name = row.name,
                capacity = enumValueOrDefault(row.capacity, PhysicalCapacity.CUSTOM),
                measurementKind = enumValueOrDefault(row.measurement_kind, PhysicalMeasurementKind.SCORE),
                unit = row.unit,
                higherIsBetter = row.higher_is_better == 1L,
                protocol = row.protocol,
                material = row.material,
                attempts = row.attempts.toInt(),
                resultMode = enumValueOrDefault(row.result_mode, PhysicalResultMode.BEST),
                trace = trace(row.created_at_epoch_ms, row.updated_at_epoch_ms, row.device_id, row.sync_version),
            )
        }
    }

    override suspend fun saveDefinition(definition: PhysicalTestDefinition) {
        db.appDatabaseQueries.upsertPhysicalDefinition(
            id = definition.id,
            name = definition.name,
            capacity = definition.capacity.name,
            measurement_kind = definition.measurementKind.name,
            unit = definition.unit,
            higher_is_better = if (definition.higherIsBetter) 1L else 0L,
            protocol = definition.protocol,
            material = definition.material,
            attempts = definition.attempts.toLong(),
            result_mode = definition.resultMode.name,
            created_at_epoch_ms = definition.trace.createdAt.toEpochMilliseconds(),
            updated_at_epoch_ms = definition.trace.updatedAt.toEpochMilliseconds(),
            device_id = definition.trace.deviceId,
            sync_version = definition.trace.syncVersion,
        )
    }

    override suspend fun listBatteries(): List<PhysicalTestBattery> {
        return db.appDatabaseQueries.selectPhysicalBatteries().executeAsList().map { row ->
            val items = db.appDatabaseQueries.selectPhysicalBatteryItems(row.id).executeAsList()
            PhysicalTestBattery(
                id = row.id,
                name = row.name,
                description = row.description,
                defaultCourse = row.default_course?.toInt(),
                defaultAgeFrom = row.default_age_from?.toInt(),
                defaultAgeTo = row.default_age_to?.toInt(),
                testIds = items.map { it.test_id },
                trace = trace(row.created_at_epoch_ms, row.updated_at_epoch_ms, row.device_id, row.sync_version),
            )
        }
    }

    override suspend fun saveBattery(battery: PhysicalTestBattery) {
        db.transaction {
            db.appDatabaseQueries.upsertPhysicalBattery(
                id = battery.id,
                name = battery.name,
                description = battery.description,
                default_course = battery.defaultCourse?.toLong(),
                default_age_from = battery.defaultAgeFrom?.toLong(),
                default_age_to = battery.defaultAgeTo?.toLong(),
                created_at_epoch_ms = battery.trace.createdAt.toEpochMilliseconds(),
                updated_at_epoch_ms = battery.trace.updatedAt.toEpochMilliseconds(),
                device_id = battery.trace.deviceId,
                sync_version = battery.trace.syncVersion,
            )
            db.appDatabaseQueries.deletePhysicalBatteryItems(battery.id)
            battery.testIds.forEachIndexed { index, testId ->
                db.appDatabaseQueries.upsertPhysicalBatteryItem(
                    battery_id = battery.id,
                    test_id = testId,
                    sort_order = index.toLong(),
                    updated_at_epoch_ms = battery.trace.updatedAt.toEpochMilliseconds(),
                    device_id = battery.trace.deviceId,
                    sync_version = battery.trace.syncVersion,
                )
            }
        }
    }

    override suspend fun assignBatteryToClass(assignment: PhysicalTestAssignment) {
        db.appDatabaseQueries.upsertPhysicalAssignment(
            id = assignment.id,
            battery_id = assignment.batteryId,
            class_id = assignment.classId,
            course = assignment.course?.toLong(),
            age_from = assignment.ageFrom?.toLong(),
            age_to = assignment.ageTo?.toLong(),
            term_label = assignment.termLabel,
            date_epoch_ms = assignment.dateEpochMs,
            raw_column_mode = if (assignment.rawColumnMode) 1L else 0L,
            score_column_mode = if (assignment.scoreColumnMode) 1L else 0L,
            created_at_epoch_ms = assignment.trace.createdAt.toEpochMilliseconds(),
            updated_at_epoch_ms = assignment.trace.updatedAt.toEpochMilliseconds(),
            device_id = assignment.trace.deviceId,
            sync_version = assignment.trace.syncVersion,
        )
    }

    override suspend fun listAssignmentsForClass(classId: Long): List<PhysicalTestAssignment> {
        return db.appDatabaseQueries.selectPhysicalAssignmentsForClass(classId).executeAsList().map { row ->
            PhysicalTestAssignment(
                id = row.id,
                batteryId = row.battery_id,
                classId = row.class_id,
                course = row.course?.toInt(),
                ageFrom = row.age_from?.toInt(),
                ageTo = row.age_to?.toInt(),
                termLabel = row.term_label,
                dateEpochMs = row.date_epoch_ms,
                rawColumnMode = row.raw_column_mode == 1L,
                scoreColumnMode = row.score_column_mode == 1L,
                trace = trace(row.created_at_epoch_ms, row.updated_at_epoch_ms, row.device_id, row.sync_version),
            )
        }
    }

    override suspend fun listScalesForTest(testId: String): List<PhysicalTestScale> {
        return db.appDatabaseQueries.selectPhysicalScalesForTest(testId).executeAsList().map { row ->
            PhysicalTestScale(
                id = row.id,
                testId = row.test_id,
                name = row.name,
                course = row.course?.toInt(),
                ageFrom = row.age_from?.toInt(),
                ageTo = row.age_to?.toInt(),
                sex = row.sex,
                batteryId = row.battery_id,
                direction = enumValueOrDefault(row.direction, PhysicalScaleDirection.HIGHER_IS_BETTER),
                ranges = db.appDatabaseQueries.selectPhysicalScaleRanges(row.id).executeAsList().map { range ->
                    PhysicalTestScaleRange(
                        id = range.id,
                        scaleId = range.scale_id,
                        minValue = range.min_value,
                        maxValue = range.max_value,
                        score = range.score,
                        label = range.label,
                        sortOrder = range.sort_order.toInt(),
                    )
                },
                trace = trace(row.created_at_epoch_ms, row.updated_at_epoch_ms, row.device_id, row.sync_version),
            )
        }
    }

    override suspend fun saveScale(scale: PhysicalTestScale) {
        db.transaction {
            db.appDatabaseQueries.upsertPhysicalScale(
                id = scale.id,
                test_id = scale.testId,
                name = scale.name,
                course = scale.course?.toLong(),
                age_from = scale.ageFrom?.toLong(),
                age_to = scale.ageTo?.toLong(),
                sex = scale.sex,
                battery_id = scale.batteryId,
                direction = scale.direction.name,
                created_at_epoch_ms = scale.trace.createdAt.toEpochMilliseconds(),
                updated_at_epoch_ms = scale.trace.updatedAt.toEpochMilliseconds(),
                device_id = scale.trace.deviceId,
                sync_version = scale.trace.syncVersion,
            )
            db.appDatabaseQueries.deletePhysicalScaleRanges(scale.id)
            scale.ranges.forEach { range ->
                db.appDatabaseQueries.upsertPhysicalScaleRange(
                    id = range.id,
                    scale_id = scale.id,
                    min_value = range.minValue,
                    max_value = range.maxValue,
                    score = range.score,
                    label = range.label,
                    sort_order = range.sortOrder.toLong(),
                    updated_at_epoch_ms = scale.trace.updatedAt.toEpochMilliseconds(),
                    device_id = scale.trace.deviceId,
                    sync_version = scale.trace.syncVersion,
                )
            }
        }
    }

    override suspend fun resolveScale(
        testId: String,
        course: Int?,
        age: Int?,
        sex: String?,
        batteryId: String?,
    ): PhysicalTestScale? {
        val scales = listScalesForTest(testId)
        val requestedSex = normalizedStudentSex(sex)
        val sexMatches: (PhysicalTestScale) -> Boolean = { scale ->
            scale.sex == null || (requestedSex != StudentSex.UNSPECIFIED && normalizedStudentSex(scale.sex) == requestedSex)
        }
        fun PhysicalTestScale.ageMatches(): Boolean {
            if (age == null) return false
            val minOk = ageFrom?.let { age >= it } ?: true
            val maxOk = ageTo?.let { age <= it } ?: true
            return (ageFrom != null || ageTo != null) && minOk && maxOk
        }
        fun List<PhysicalTestScale>.bestSexMatch(): PhysicalTestScale? {
            return firstOrNull { scale ->
                requestedSex != StudentSex.UNSPECIFIED && normalizedStudentSex(scale.sex) == requestedSex
            }
                ?: firstOrNull()
        }
        return scales.filter { scale ->
            scale.testId == testId &&
                scale.batteryId == batteryId &&
                scale.course == course &&
                scale.ageMatches() &&
                sexMatches(scale)
        }.bestSexMatch() ?: scales.filter { scale ->
            scale.testId == testId &&
                scale.batteryId == batteryId &&
                scale.course == course &&
                sexMatches(scale)
        }.bestSexMatch() ?: scales.filter { scale ->
            scale.testId == testId &&
                scale.batteryId == batteryId &&
                scale.ageMatches() &&
                sexMatches(scale)
        }.bestSexMatch() ?: scales.filter { scale ->
            scale.testId == testId &&
                scale.course == course &&
                sexMatches(scale)
        }.bestSexMatch() ?: scales.filter { scale ->
            scale.testId == testId &&
                scale.ageMatches() &&
                sexMatches(scale)
        }.bestSexMatch() ?: scales.filter { scale ->
            scale.testId == testId &&
                scale.batteryId == null &&
                scale.course == null &&
                scale.ageFrom == null &&
                scale.ageTo == null &&
                sexMatches(scale)
        }.bestSexMatch()
    }

    override suspend fun saveNotebookLink(link: PhysicalTestNotebookLink) {
        db.appDatabaseQueries.upsertPhysicalNotebookLink(
            assignment_id = link.assignmentId,
            test_id = link.testId,
            raw_column_id = link.rawColumnId,
            score_column_id = link.scoreColumnId,
            updated_at_epoch_ms = link.trace.updatedAt.toEpochMilliseconds(),
            device_id = link.trace.deviceId,
            sync_version = link.trace.syncVersion,
        )
    }

    override suspend fun listNotebookLinksForAssignment(assignmentId: String): List<PhysicalTestNotebookLink> {
        return db.appDatabaseQueries.selectPhysicalNotebookLinksForAssignment(assignmentId).executeAsList().map { row ->
            PhysicalTestNotebookLink(
                assignmentId = row.assignment_id,
                testId = row.test_id,
                rawColumnId = row.raw_column_id,
                scoreColumnId = row.score_column_id,
                trace = AuditTrace(
                    updatedAt = Instant.fromEpochMilliseconds(row.updated_at_epoch_ms),
                    deviceId = row.device_id,
                    syncVersion = row.sync_version,
                ),
            )
        }
    }

    override suspend fun saveResult(result: PhysicalTestResult, attempts: List<PhysicalTestAttempt>) {
        db.transaction {
            db.appDatabaseQueries.upsertPhysicalResult(
                id = result.id,
                assignment_id = result.assignmentId,
                test_id = result.testId,
                class_id = result.classId,
                student_id = result.studentId,
                raw_value = result.rawValue,
                raw_text = result.rawText,
                score = result.score,
                scale_id = result.scaleId,
                observed_at_epoch_ms = result.observedAtEpochMs,
                raw_column_id = result.rawColumnId,
                score_column_id = result.scoreColumnId,
                created_at_epoch_ms = result.trace.createdAt.toEpochMilliseconds(),
                updated_at_epoch_ms = result.trace.updatedAt.toEpochMilliseconds(),
                device_id = result.trace.deviceId,
                sync_version = result.trace.syncVersion,
            )
            db.appDatabaseQueries.deletePhysicalAttemptsForResult(result.id)
            attempts.forEach { attempt ->
                db.appDatabaseQueries.upsertPhysicalAttempt(
                    id = attempt.id,
                    result_id = result.id,
                    attempt_number = attempt.attemptNumber.toLong(),
                    raw_value = attempt.rawValue,
                    raw_text = attempt.rawText,
                    updated_at_epoch_ms = result.trace.updatedAt.toEpochMilliseconds(),
                    device_id = result.trace.deviceId,
                    sync_version = result.trace.syncVersion,
                )
            }
        }
    }

    override suspend fun listResultsForAssignment(assignmentId: String): List<PhysicalTestResult> {
        return db.appDatabaseQueries.selectPhysicalResultsForAssignment(assignmentId).executeAsList().map { row ->
            PhysicalTestResult(
                id = row.id,
                assignmentId = row.assignment_id,
                testId = row.test_id,
                classId = row.class_id,
                studentId = row.student_id,
                rawValue = row.raw_value,
                rawText = row.raw_text,
                score = row.score,
                scaleId = row.scale_id,
                observedAtEpochMs = row.observed_at_epoch_ms,
                rawColumnId = row.raw_column_id,
                scoreColumnId = row.score_column_id,
                trace = trace(row.created_at_epoch_ms, row.updated_at_epoch_ms, row.device_id, row.sync_version),
            )
        }
    }

    override suspend fun listResultsForStudent(studentId: Long, testId: String): List<PhysicalTestResult> {
        return db.appDatabaseQueries.selectPhysicalResultsForStudentAndTest(studentId, testId).executeAsList().map { row ->
            PhysicalTestResult(
                id = row.id,
                assignmentId = row.assignment_id,
                testId = row.test_id,
                classId = row.class_id,
                studentId = row.student_id,
                rawValue = row.raw_value,
                rawText = row.raw_text,
                score = row.score,
                scaleId = row.scale_id,
                observedAtEpochMs = row.observed_at_epoch_ms,
                rawColumnId = row.raw_column_id,
                scoreColumnId = row.score_column_id,
                trace = trace(row.created_at_epoch_ms, row.updated_at_epoch_ms, row.device_id, row.sync_version),
            )
        }
    }

    private fun trace(
        createdAtEpochMs: Long = 0,
        updatedAtEpochMs: Long = 0,
        deviceId: String? = null,
        syncVersion: Long = 0,
    ): AuditTrace {
        val createdAt = if (createdAtEpochMs > 0) Instant.fromEpochMilliseconds(createdAtEpochMs) else Clock.System.now()
        val updatedAt = if (updatedAtEpochMs > 0) Instant.fromEpochMilliseconds(updatedAtEpochMs) else createdAt
        return AuditTrace(createdAt = createdAt, updatedAt = updatedAt, deviceId = deviceId, syncVersion = syncVersion)
    }

    private inline fun <reified T : Enum<T>> enumValueOrDefault(value: String, default: T): T {
        return runCatching { enumValueOf<T>(value) }.getOrDefault(default)
    }
}
