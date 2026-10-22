package com.migestor.data.sync

import com.migestor.data.di.KmpContainer
import com.migestor.shared.domain.AuditTrace
import com.migestor.shared.domain.PhysicalCapacity
import com.migestor.shared.domain.PhysicalMeasurementKind
import com.migestor.shared.domain.PhysicalResultMode
import com.migestor.shared.domain.PhysicalScaleDirection
import com.migestor.shared.domain.PhysicalScaleScoringMode
import com.migestor.shared.domain.PhysicalTestAssignment
import com.migestor.shared.domain.PhysicalTestAttempt
import com.migestor.shared.domain.PhysicalTestBattery
import com.migestor.shared.domain.PhysicalTestDefinition
import com.migestor.shared.domain.PhysicalTestNotebookLink
import com.migestor.shared.domain.PhysicalTestResult
import com.migestor.shared.domain.PhysicalTestScale
import com.migestor.shared.domain.PhysicalTestScaleRange
import com.migestor.shared.inclusion.InclusionPhase
import com.migestor.shared.sync.SyncAck
import com.migestor.shared.sync.SyncChange
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

/**
 * Sync LAN del plan semanal del Planner, del Manual de Inclusión (tareas y fecha de
 * evaluación inicial por grupo) y de las pruebas físicas de EF.
 *
 * Igual que [SchoolRecordsSync], lo usan el helper del Mac (vía el adapter) y la app
 * Apple. Diferencias:
 * - Plan semanal, tareas y ajustes de Inclusión se identifican por su **clave
 *   natural** (grupo + año + semana; alumno + curso + plantilla o fecha de alta;
 *   grupo + curso), no por el id autoincremental: las tareas del manual las genera
 *   cada dispositivo por su cuenta y los ids no coinciden.
 * - En Apple casi ninguna de estas escrituras pasa por `enqueueLocalChange` (algunas
 *   las hace Kotlin solo, como generar las tareas del manual). Por eso el iPad las
 *   recoge con [collect] en cada sync, igual que el Mac, en vez de encolarlas.
 * - Las pruebas físicas no se borran desde la app: solo viajan altas y cambios.
 */
class ModuleRecordsSync(
    private val container: KmpContainer,
    private val localDeviceId: String,
) {
    data class Collected(
        val changes: List<SyncChange>,
        /** Claves vivas de las entidades cuyo borrado se detecta por diferencia. */
        val liveKeysByEntity: Map<String, Set<String>>,
    )

    private enum class Outcome { APPLIED, STALE, SKIPPED }

    private val json = Json { ignoreUnknownKeys = true }
    private val queries get() = container.database.appDatabaseQueries
    private val physical get() = container.physicalTestsRepository

    /**
     * La fecha de evaluación inicial no guarda cuándo cambió. Se recuerda su valor en
     * cada recogida y, si cambia, se fecha con la hora actual. Tras reiniciar el proceso
     * se parte de cero (fecha 0): una fecha 0 solo rellena huecos al aplicarse, nunca
     * pisa un valor que ya existe.
     */
    private val groupSettingSeen = mutableMapOf<String, Pair<String, Long>>()

    // ---------------------------------------------------------------------------
    // COLLECT
    // ---------------------------------------------------------------------------

    @Throws(Exception::class)
    suspend fun collect(sinceEpochMs: Long): Collected {
        val changes = mutableListOf<SyncChange>()
        val live = mutableMapOf(WEEK_PLAN to mutableSetOf<String>(), INCLUSION_TASK to mutableSetOf())
        fun emit(entity: String, key: String, updatedAt: Long, deviceId: String?, payload: JsonObjectBuilder.() -> Unit) {
            if (sinceEpochMs != 0L && updatedAt <= sinceEpochMs) return
            changes += SyncChange(
                entity = entity,
                id = key,
                updatedAtEpochMs = updatedAt,
                deviceId = deviceId ?: localDeviceId,
                payload = buildJsonObject(payload).toString(),
            )
        }

        queries.selectAllWeekPlanKeys().executeAsList().forEach { row ->
            val plan = container.plannerWeekPlanRepository.getPlan(row.class_id, row.year.toInt(), row.week.toInt()) ?: return@forEach
            val key = weekPlanKey(plan.classId, plan.year, plan.week)
            live.getValue(WEEK_PLAN) += key
            emit(WEEK_PLAN, key, plan.trace.updatedAt.toEpochMilliseconds(), plan.trace.deviceId) {
                put("classId", JsonPrimitive(plan.classId))
                put("year", JsonPrimitive(plan.year))
                put("week", JsonPrimitive(plan.week))
                put("strategies", stringArray(plan.strategies))
                put("instruments", stringArray(plan.instruments))
                put("notes", JsonPrimitive(plan.notes))
            }
        }

        queries.selectAllInclusionTasks().executeAsList().forEach { task ->
            val key = inclusionTaskKey(task.student_id, task.school_year, task.template_key, task.created_at)
            live.getValue(INCLUSION_TASK) += key
            emit(INCLUSION_TASK, key, task.updated_at, null) {
                put("studentId", JsonPrimitive(task.student_id))
                put("measureId", task.measure_id?.let(::JsonPrimitive) ?: JsonNull)
                put("templateKey", task.template_key?.let(::JsonPrimitive) ?: JsonNull)
                put("title", JsonPrimitive(task.title))
                put("phase", JsonPrimitive(task.phase))
                put("dueDateIso", JsonPrimitive(task.due_date_iso))
                put("dueIsCustom", JsonPrimitive(task.due_is_custom == 1L))
                put("doneAtIso", task.done_at_iso?.let(::JsonPrimitive) ?: JsonNull)
                put("notes", JsonPrimitive(task.notes))
                put("schoolYear", JsonPrimitive(task.school_year))
                put("createdAtEpochMs", JsonPrimitive(task.created_at))
            }
        }

        queries.selectAllInclusionGroupSettings().executeAsList().forEach { row ->
            val key = groupSettingKey(row.class_id, row.school_year)
            val previous = groupSettingSeen[key]
            val stamp = when {
                previous == null -> 0L
                previous.first != row.initial_eval_date_iso -> Clock.System.now().toEpochMilliseconds()
                else -> previous.second
            }
            groupSettingSeen[key] = row.initial_eval_date_iso to stamp
            emit(INCLUSION_GROUP_SETTING, key, stamp, null) {
                put("classId", JsonPrimitive(row.class_id))
                put("schoolYear", JsonPrimitive(row.school_year))
                put("initialEvalDateIso", JsonPrimitive(row.initial_eval_date_iso))
            }
        }

        val definitions = physical.listDefinitions()
        definitions.forEach { definition ->
            emit(PE_DEFINITION, definition.id, definition.trace.updatedAt.toEpochMilliseconds(), definition.trace.deviceId) {
                definitionPayload(definition)
            }
            physical.listScalesForTest(definition.id).forEach { scale ->
                emit(PE_SCALE, scale.id, scale.trace.updatedAt.toEpochMilliseconds(), scale.trace.deviceId) {
                    scalePayload(scale)
                }
            }
        }
        physical.listBatteries().forEach { battery ->
            emit(PE_BATTERY, battery.id, battery.trace.updatedAt.toEpochMilliseconds(), battery.trace.deviceId) {
                put("id", JsonPrimitive(battery.id))
                put("name", JsonPrimitive(battery.name))
                put("description", JsonPrimitive(battery.description))
                put("defaultCourse", battery.defaultCourse?.let(::JsonPrimitive) ?: JsonNull)
                put("defaultAgeFrom", battery.defaultAgeFrom?.let(::JsonPrimitive) ?: JsonNull)
                put("defaultAgeTo", battery.defaultAgeTo?.let(::JsonPrimitive) ?: JsonNull)
                put("testIds", stringArray(battery.testIds))
                put("createdAtEpochMs", JsonPrimitive(battery.trace.createdAt.toEpochMilliseconds()))
            }
        }
        container.classesRepository.listClasses().forEach { schoolClass ->
            physical.listAssignmentsForClass(schoolClass.id).forEach { assignment ->
                emit(PE_ASSIGNMENT, assignment.id, assignment.trace.updatedAt.toEpochMilliseconds(), assignment.trace.deviceId) {
                    assignmentPayload(assignment)
                }
                physical.listNotebookLinksForAssignment(assignment.id).forEach { link ->
                    emit(PE_NOTEBOOK_LINK, notebookLinkKey(link.assignmentId, link.testId), link.trace.updatedAt.toEpochMilliseconds(), link.trace.deviceId) {
                        put("assignmentId", JsonPrimitive(link.assignmentId))
                        put("testId", JsonPrimitive(link.testId))
                        put("rawColumnId", link.rawColumnId?.let(::JsonPrimitive) ?: JsonNull)
                        put("scoreColumnId", link.scoreColumnId?.let(::JsonPrimitive) ?: JsonNull)
                    }
                }
                physical.listResultsForAssignment(assignment.id).forEach { result ->
                    emit(PE_RESULT, result.id, result.trace.updatedAt.toEpochMilliseconds(), result.trace.deviceId) {
                        resultPayload(result)
                    }
                }
            }
        }

        return Collected(changes, live)
    }

    private fun JsonObjectBuilder.definitionPayload(definition: PhysicalTestDefinition) {
        put("id", JsonPrimitive(definition.id))
        put("name", JsonPrimitive(definition.name))
        put("capacity", JsonPrimitive(definition.capacity.name))
        put("measurementKind", JsonPrimitive(definition.measurementKind.name))
        put("unit", JsonPrimitive(definition.unit))
        put("higherIsBetter", JsonPrimitive(definition.higherIsBetter))
        put("protocol", JsonPrimitive(definition.protocol))
        put("material", JsonPrimitive(definition.material))
        put("attempts", JsonPrimitive(definition.attempts))
        put("resultMode", JsonPrimitive(definition.resultMode.name))
        put("createdAtEpochMs", JsonPrimitive(definition.trace.createdAt.toEpochMilliseconds()))
    }

    private fun JsonObjectBuilder.scalePayload(scale: PhysicalTestScale) {
        put("id", JsonPrimitive(scale.id))
        put("testId", JsonPrimitive(scale.testId))
        put("name", JsonPrimitive(scale.name))
        put("course", scale.course?.let(::JsonPrimitive) ?: JsonNull)
        put("ageFrom", scale.ageFrom?.let(::JsonPrimitive) ?: JsonNull)
        put("ageTo", scale.ageTo?.let(::JsonPrimitive) ?: JsonNull)
        put("sex", scale.sex?.let(::JsonPrimitive) ?: JsonNull)
        put("batteryId", scale.batteryId?.let(::JsonPrimitive) ?: JsonNull)
        put("direction", JsonPrimitive(scale.direction.name))
        put("scoringMode", JsonPrimitive(scale.scoringMode.name))
        put("scoreRoundTo", scale.scoreRoundTo?.let(::JsonPrimitive) ?: JsonNull)
        put("createdAtEpochMs", JsonPrimitive(scale.trace.createdAt.toEpochMilliseconds()))
        put("ranges", buildJsonArray {
            scale.ranges.forEach { range ->
                add(buildJsonObject {
                    put("id", JsonPrimitive(range.id))
                    put("minValue", range.minValue?.let(::JsonPrimitive) ?: JsonNull)
                    put("maxValue", range.maxValue?.let(::JsonPrimitive) ?: JsonNull)
                    put("score", JsonPrimitive(range.score))
                    put("label", range.label?.let(::JsonPrimitive) ?: JsonNull)
                    put("sortOrder", JsonPrimitive(range.sortOrder))
                })
            }
        })
    }

    private fun JsonObjectBuilder.assignmentPayload(assignment: PhysicalTestAssignment) {
        put("id", JsonPrimitive(assignment.id))
        put("batteryId", JsonPrimitive(assignment.batteryId))
        put("classId", JsonPrimitive(assignment.classId))
        put("course", assignment.course?.let(::JsonPrimitive) ?: JsonNull)
        put("ageFrom", assignment.ageFrom?.let(::JsonPrimitive) ?: JsonNull)
        put("ageTo", assignment.ageTo?.let(::JsonPrimitive) ?: JsonNull)
        put("termLabel", assignment.termLabel?.let(::JsonPrimitive) ?: JsonNull)
        put("dateEpochMs", JsonPrimitive(assignment.dateEpochMs))
        put("rawColumnMode", JsonPrimitive(assignment.rawColumnMode))
        put("scoreColumnMode", JsonPrimitive(assignment.scoreColumnMode))
        put("createdAtEpochMs", JsonPrimitive(assignment.trace.createdAt.toEpochMilliseconds()))
    }

    private fun JsonObjectBuilder.resultPayload(result: PhysicalTestResult) {
        put("id", JsonPrimitive(result.id))
        put("assignmentId", JsonPrimitive(result.assignmentId))
        put("testId", JsonPrimitive(result.testId))
        put("classId", JsonPrimitive(result.classId))
        put("studentId", JsonPrimitive(result.studentId))
        put("rawValue", result.rawValue?.let(::JsonPrimitive) ?: JsonNull)
        put("rawText", JsonPrimitive(result.rawText))
        put("score", result.score?.let(::JsonPrimitive) ?: JsonNull)
        put("scaleId", result.scaleId?.let(::JsonPrimitive) ?: JsonNull)
        put("observedAtEpochMs", JsonPrimitive(result.observedAtEpochMs))
        put("rawColumnId", result.rawColumnId?.let(::JsonPrimitive) ?: JsonNull)
        put("scoreColumnId", result.scoreColumnId?.let(::JsonPrimitive) ?: JsonNull)
        put("createdAtEpochMs", JsonPrimitive(result.trace.createdAt.toEpochMilliseconds()))
        put("attempts", buildJsonArray {
            queries.selectPhysicalAttemptsForResult(result.id).executeAsList().forEach { attempt ->
                add(buildJsonObject {
                    put("id", JsonPrimitive(attempt.id))
                    put("attemptNumber", JsonPrimitive(attempt.attempt_number))
                    put("rawValue", attempt.raw_value?.let(::JsonPrimitive) ?: JsonNull)
                    put("rawText", JsonPrimitive(attempt.raw_text))
                })
            }
        })
    }

    // ---------------------------------------------------------------------------
    // APPLY
    // ---------------------------------------------------------------------------

    @Throws(Exception::class)
    suspend fun applyAll(changes: List<SyncChange>): SyncAck {
        var applied = 0
        var conflicts = 0
        var ignored = 0
        var failed = 0
        val cache = ApplyCache()
        sortedForApply(changes.filter { handles(it.entity) }).forEach { change ->
            runCatching {
                if (change.op == "delete") {
                    if (delete(change)) applied++ else ignored++
                    return@runCatching
                }
                when (apply(change, cache)) {
                    Outcome.APPLIED -> applied++
                    Outcome.STALE -> conflicts++
                    Outcome.SKIPPED -> ignored++
                }
            }.onFailure { failed++ }
        }
        return SyncAck(
            applied = applied,
            conflictsResolvedByLww = conflicts,
            serverEpochMs = Clock.System.now().toEpochMilliseconds(),
            ignored = ignored,
            failed = failed,
        )
    }

    /** Lecturas de un lote: las pruebas físicas no tienen consulta por id. */
    private inner class ApplyCache {
        private var definitionsById: Map<String, PhysicalTestDefinition>? = null
        private var batteriesById: Map<String, PhysicalTestBattery>? = null
        suspend fun definitions() = definitionsById ?: physical.listDefinitions().associateBy { it.id }.also { definitionsById = it }
        suspend fun batteries() = batteriesById ?: physical.listBatteries().associateBy { it.id }.also { batteriesById = it }
        val scalesByTest = mutableMapOf<String, Map<String, PhysicalTestScale>>()
        val assignmentsByClass = mutableMapOf<Long, Map<String, PhysicalTestAssignment>>()
        val linksByAssignment = mutableMapOf<String, Map<String, PhysicalTestNotebookLink>>()
        val resultsByAssignment = mutableMapOf<String, Map<String, PhysicalTestResult>>()
    }

    private suspend fun apply(change: SyncChange, cache: ApplyCache): Outcome {
        val payload = runCatching { json.parseToJsonElement(change.payload).jsonObject }.getOrNull()
            ?: error("payload ilegible: ${change.entity} ${change.id}")
        val updatedAt = change.updatedAtEpochMs
        val deviceId = change.deviceId
        fun isStale(localUpdatedAt: Long?) = localUpdatedAt != null && localUpdatedAt >= updatedAt
        fun trace(createdAtKey: String = "createdAtEpochMs") = AuditTrace(
            createdAt = Instant.fromEpochMilliseconds(payload.long(createdAtKey)?.takeIf { it > 0 } ?: updatedAt),
            updatedAt = Instant.fromEpochMilliseconds(updatedAt),
            deviceId = deviceId,
            syncVersion = 1,
        )

        return when (change.entity) {
            WEEK_PLAN -> {
                val classId = payload.long("classId") ?: return Outcome.SKIPPED
                val year = payload.int("year") ?: return Outcome.SKIPPED
                val week = payload.int("week") ?: return Outcome.SKIPPED
                val existing = container.plannerWeekPlanRepository.getPlan(classId, year, week)
                if (isStale(existing?.trace?.updatedAt?.toEpochMilliseconds())) return Outcome.STALE
                container.plannerWeekPlanRepository.save(
                    id = existing?.id,
                    classId = classId,
                    year = year,
                    week = week,
                    strategies = payload.stringList("strategies") ?: existing?.strategies.orEmpty(),
                    instruments = payload.stringList("instruments") ?: existing?.instruments.orEmpty(),
                    notes = payload.text("notes") ?: existing?.notes.orEmpty(),
                    createdAtEpochMs = updatedAt,
                    updatedAtEpochMs = updatedAt,
                    deviceId = deviceId,
                    syncVersion = 1,
                )
                Outcome.APPLIED
            }

            INCLUSION_TASK -> {
                val studentId = payload.long("studentId") ?: return Outcome.SKIPPED
                val schoolYear = payload.text("schoolYear") ?: return Outcome.SKIPPED
                val templateKey = payload.text("templateKey")?.takeIf { it.isNotEmpty() }
                val createdAt = payload.long("createdAtEpochMs") ?: return Outcome.SKIPPED
                val key = inclusionTaskKey(studentId, schoolYear, templateKey, createdAt)
                val existing = findInclusionTask(studentId, schoolYear, key)
                if (isStale(existing?.updatedAtEpochMs)) return Outcome.STALE
                val title = payload.text("title") ?: existing?.title ?: return Outcome.SKIPPED
                val phase = payload.text("phase")?.let { name -> InclusionPhase.entries.firstOrNull { it.name == name } }
                    ?: existing?.phase ?: return Outcome.SKIPPED
                val dueDateIso = payload.text("dueDateIso") ?: existing?.dueDate?.toString() ?: return Outcome.SKIPPED
                val taskId = existing?.id ?: run {
                    val repo = container.inclusionTaskRepository
                    if (templateKey != null) {
                        repo.insertTemplateIfAbsent(
                            studentId = studentId,
                            measureId = payload.long("measureId"),
                            templateKey = templateKey,
                            title = title,
                            phase = phase,
                            dueDateIso = dueDateIso,
                            schoolYear = schoolYear,
                            nowEpochMs = createdAt,
                        )
                        findInclusionTask(studentId, schoolYear, key)?.id ?: return Outcome.SKIPPED
                    } else {
                        repo.insertFreeTask(
                            studentId = studentId,
                            title = title,
                            phase = phase,
                            dueDateIso = dueDateIso,
                            notes = payload.text("notes").orEmpty(),
                            schoolYear = schoolYear,
                            nowEpochMs = createdAt,
                        )
                    }
                }
                // Fecha y estado al final, con la hora del cambio: así la fila queda
                // fechada igual que en el otro dispositivo (LWW).
                container.inclusionTaskRepository.setDue(taskId, dueDateIso, payload.bool("dueIsCustom") ?: existing?.dueIsCustom ?: false, updatedAt)
                container.inclusionTaskRepository.setDone(taskId, payload.textOrNull("doneAtIso", existing?.doneAt?.toString()), updatedAt)
                Outcome.APPLIED
            }

            INCLUSION_GROUP_SETTING -> {
                val classId = payload.long("classId") ?: return Outcome.SKIPPED
                val schoolYear = payload.text("schoolYear") ?: return Outcome.SKIPPED
                val date = payload.text("initialEvalDateIso") ?: return Outcome.SKIPPED
                val current = container.inclusionTaskRepository.getInitialEvaluationDate(classId, schoolYear)
                if (current == date) return Outcome.STALE
                // Sin fecha de cambio conocida (0) solo se rellena lo que falta.
                if (updatedAt <= 0L && current != null) return Outcome.STALE
                container.inclusionTaskRepository.setInitialEvaluationDate(classId, schoolYear, date)
                groupSettingSeen[groupSettingKey(classId, schoolYear)] = date to updatedAt
                Outcome.APPLIED
            }

            PE_DEFINITION -> {
                val id = payload.text("id") ?: change.id
                if (isStale(cache.definitions()[id]?.trace?.updatedAt?.toEpochMilliseconds())) return Outcome.STALE
                physical.saveDefinition(
                    PhysicalTestDefinition(
                        id = id,
                        name = payload.text("name") ?: return Outcome.SKIPPED,
                        capacity = payload.enumOf("capacity", PhysicalCapacity.entries) ?: PhysicalCapacity.CUSTOM,
                        measurementKind = payload.enumOf("measurementKind", PhysicalMeasurementKind.entries) ?: PhysicalMeasurementKind.SCORE,
                        unit = payload.text("unit").orEmpty(),
                        higherIsBetter = payload.bool("higherIsBetter") ?: true,
                        protocol = payload.text("protocol").orEmpty(),
                        material = payload.text("material").orEmpty(),
                        attempts = payload.int("attempts") ?: 1,
                        resultMode = payload.enumOf("resultMode", PhysicalResultMode.entries) ?: PhysicalResultMode.BEST,
                        trace = trace(),
                    ),
                )
                Outcome.APPLIED
            }

            PE_BATTERY -> {
                val id = payload.text("id") ?: change.id
                if (isStale(cache.batteries()[id]?.trace?.updatedAt?.toEpochMilliseconds())) return Outcome.STALE
                physical.saveBattery(
                    PhysicalTestBattery(
                        id = id,
                        name = payload.text("name") ?: return Outcome.SKIPPED,
                        description = payload.text("description").orEmpty(),
                        defaultCourse = payload.int("defaultCourse"),
                        defaultAgeFrom = payload.int("defaultAgeFrom"),
                        defaultAgeTo = payload.int("defaultAgeTo"),
                        testIds = payload.stringList("testIds").orEmpty(),
                        trace = trace(),
                    ),
                )
                Outcome.APPLIED
            }

            PE_SCALE -> {
                val id = payload.text("id") ?: change.id
                val testId = payload.text("testId") ?: return Outcome.SKIPPED
                val existing = cache.scalesByTest.getOrPut(testId) { physical.listScalesForTest(testId).associateBy { it.id } }[id]
                if (isStale(existing?.trace?.updatedAt?.toEpochMilliseconds())) return Outcome.STALE
                val ranges = payload["ranges"]?.takeIf { it !is JsonNull }?.jsonArray.orEmpty().mapNotNull { element ->
                    val range = element.jsonObject
                    PhysicalTestScaleRange(
                        id = range.text("id") ?: return@mapNotNull null,
                        scaleId = id,
                        minValue = range.double("minValue"),
                        maxValue = range.double("maxValue"),
                        score = range.double("score") ?: return@mapNotNull null,
                        label = range.text("label"),
                        sortOrder = range.int("sortOrder") ?: 0,
                    )
                }
                physical.saveScale(
                    PhysicalTestScale(
                        id = id,
                        testId = testId,
                        name = payload.text("name") ?: return Outcome.SKIPPED,
                        course = payload.int("course"),
                        ageFrom = payload.int("ageFrom"),
                        ageTo = payload.int("ageTo"),
                        sex = payload.text("sex"),
                        batteryId = payload.text("batteryId"),
                        direction = payload.enumOf("direction", PhysicalScaleDirection.entries) ?: PhysicalScaleDirection.HIGHER_IS_BETTER,
                        ranges = ranges,
                        scoringMode = payload.enumOf("scoringMode", PhysicalScaleScoringMode.entries) ?: PhysicalScaleScoringMode.STEP,
                        scoreRoundTo = payload.double("scoreRoundTo"),
                        trace = trace(),
                    ),
                )
                Outcome.APPLIED
            }

            PE_ASSIGNMENT -> {
                val id = payload.text("id") ?: change.id
                val classId = payload.long("classId") ?: return Outcome.SKIPPED
                val existing = cache.assignmentsByClass.getOrPut(classId) { physical.listAssignmentsForClass(classId).associateBy { it.id } }[id]
                if (isStale(existing?.trace?.updatedAt?.toEpochMilliseconds())) return Outcome.STALE
                physical.assignBatteryToClass(
                    PhysicalTestAssignment(
                        id = id,
                        batteryId = payload.text("batteryId") ?: return Outcome.SKIPPED,
                        classId = classId,
                        course = payload.int("course"),
                        ageFrom = payload.int("ageFrom"),
                        ageTo = payload.int("ageTo"),
                        termLabel = payload.text("termLabel"),
                        dateEpochMs = payload.long("dateEpochMs") ?: return Outcome.SKIPPED,
                        rawColumnMode = payload.bool("rawColumnMode") ?: true,
                        scoreColumnMode = payload.bool("scoreColumnMode") ?: true,
                        trace = trace(),
                    ),
                )
                Outcome.APPLIED
            }

            PE_NOTEBOOK_LINK -> {
                val assignmentId = payload.text("assignmentId") ?: return Outcome.SKIPPED
                val testId = payload.text("testId") ?: return Outcome.SKIPPED
                val existing = cache.linksByAssignment.getOrPut(assignmentId) {
                    physical.listNotebookLinksForAssignment(assignmentId).associateBy { it.testId }
                }[testId]
                if (isStale(existing?.trace?.updatedAt?.toEpochMilliseconds())) return Outcome.STALE
                physical.saveNotebookLink(
                    PhysicalTestNotebookLink(
                        assignmentId = assignmentId,
                        testId = testId,
                        rawColumnId = payload.text("rawColumnId"),
                        scoreColumnId = payload.text("scoreColumnId"),
                        trace = trace(),
                    ),
                )
                Outcome.APPLIED
            }

            PE_RESULT -> {
                val id = payload.text("id") ?: change.id
                val assignmentId = payload.text("assignmentId") ?: return Outcome.SKIPPED
                val existing = cache.resultsByAssignment.getOrPut(assignmentId) {
                    physical.listResultsForAssignment(assignmentId).associateBy { it.id }
                }[id]
                if (isStale(existing?.trace?.updatedAt?.toEpochMilliseconds())) return Outcome.STALE
                val attempts = payload["attempts"]?.takeIf { it !is JsonNull }?.jsonArray.orEmpty().mapNotNull { element ->
                    val attempt = element.jsonObject
                    PhysicalTestAttempt(
                        id = attempt.text("id") ?: return@mapNotNull null,
                        resultId = id,
                        attemptNumber = attempt.int("attemptNumber") ?: return@mapNotNull null,
                        rawValue = attempt.double("rawValue"),
                        rawText = attempt.text("rawText").orEmpty(),
                    )
                }
                physical.saveResult(
                    PhysicalTestResult(
                        id = id,
                        assignmentId = assignmentId,
                        testId = payload.text("testId") ?: return Outcome.SKIPPED,
                        classId = payload.long("classId") ?: return Outcome.SKIPPED,
                        studentId = payload.long("studentId") ?: return Outcome.SKIPPED,
                        rawValue = payload.double("rawValue"),
                        rawText = payload.text("rawText").orEmpty(),
                        score = payload.double("score"),
                        scaleId = payload.text("scaleId"),
                        observedAtEpochMs = payload.long("observedAtEpochMs") ?: updatedAt,
                        rawColumnId = payload.text("rawColumnId"),
                        scoreColumnId = payload.text("scoreColumnId"),
                        trace = trace(),
                    ),
                    attempts,
                )
                Outcome.APPLIED
            }

            else -> Outcome.SKIPPED
        }
    }

    private suspend fun findInclusionTask(studentId: Long, schoolYear: String, key: String) =
        container.inclusionTaskRepository.listByStudents(listOf(studentId), schoolYear)
            .firstOrNull { inclusionTaskKey(it.studentId, it.schoolYear, it.templateKey, it.createdAtEpochMs) == key }

    private suspend fun delete(change: SyncChange): Boolean {
        return when (change.entity) {
            WEEK_PLAN -> {
                val parts = change.id.split("|")
                val plan = container.plannerWeekPlanRepository.getPlan(
                    parts.getOrNull(0)?.toLongOrNull() ?: return false,
                    parts.getOrNull(1)?.toIntOrNull() ?: return false,
                    parts.getOrNull(2)?.toIntOrNull() ?: return false,
                ) ?: return false
                container.plannerWeekPlanRepository.delete(plan.id)
                true
            }
            INCLUSION_TASK -> {
                val parts = change.id.split("|")
                val studentId = parts.getOrNull(1)?.toLongOrNull() ?: return false
                val schoolYear = parts.getOrNull(2) ?: return false
                val task = findInclusionTask(studentId, schoolYear, change.id) ?: return false
                container.inclusionTaskRepository.delete(task.id)
                true
            }
            else -> false
        }
    }

    companion object {
        const val WEEK_PLAN = "planner_week_plan"
        const val INCLUSION_TASK = "inclusion_task"
        const val INCLUSION_GROUP_SETTING = "inclusion_group_setting"
        const val PE_DEFINITION = "physical_test_definition"
        const val PE_BATTERY = "physical_test_battery"
        const val PE_SCALE = "physical_test_scale"
        const val PE_ASSIGNMENT = "physical_test_assignment"
        const val PE_NOTEBOOK_LINK = "physical_test_notebook_link"
        const val PE_RESULT = "physical_test_result"

        /** En orden de aplicación: padres antes que hijos. */
        val ENTITIES: List<String> = listOf(
            WEEK_PLAN, INCLUSION_GROUP_SETTING, INCLUSION_TASK,
            PE_DEFINITION, PE_BATTERY, PE_SCALE, PE_ASSIGNMENT, PE_NOTEBOOK_LINK, PE_RESULT,
        )

        fun handles(entity: String): Boolean = entity in ENTITIES

        fun sortedForApply(changes: List<SyncChange>): List<SyncChange> {
            val (deletes, upserts) = changes.partition { it.op == "delete" }
            return upserts.sortedBy { ENTITIES.indexOf(it.entity) } +
                deletes.sortedByDescending { ENTITIES.indexOf(it.entity) }
        }

        fun weekPlanKey(classId: Long, year: Int, week: Int) = "$classId|$year|$week"

        /** Plantilla: alumno + curso + clave del manual. Libre: alumno + curso + fecha de alta. */
        fun inclusionTaskKey(studentId: Long, schoolYear: String, templateKey: String?, createdAtEpochMs: Long) =
            if (templateKey != null) "t|$studentId|$schoolYear|$templateKey" else "f|$studentId|$schoolYear|$createdAtEpochMs"

        fun groupSettingKey(classId: Long, schoolYear: String) = "$classId|$schoolYear"

        fun notebookLinkKey(assignmentId: String, testId: String) = "$assignmentId|$testId"
    }
}

private fun stringArray(items: List<String>): JsonArray = buildJsonArray { items.forEach { add(JsonPrimitive(it)) } }

private fun JsonObject.present(key: String): JsonElement? = this[key]?.takeIf { it !is JsonNull }

private fun JsonObject.text(key: String): String? = present(key)?.jsonPrimitive?.contentOrNull

private fun JsonObject.textOrNull(key: String, keep: String?): String? =
    if (!containsKey(key)) keep else text(key)?.takeIf { it.isNotEmpty() }

private fun JsonObject.long(key: String): Long? = present(key)?.jsonPrimitive?.longOrNull

private fun JsonObject.int(key: String): Int? = present(key)?.jsonPrimitive?.intOrNull

private fun JsonObject.double(key: String): Double? = present(key)?.jsonPrimitive?.doubleOrNull

private fun JsonObject.bool(key: String): Boolean? = present(key)?.jsonPrimitive?.booleanOrNull

/** Lista de textos como array JSON o, si llega de una versión antigua, separada por comas. */
private fun JsonObject.stringList(key: String): List<String>? {
    val element = present(key) ?: return null
    return if (element is JsonArray) {
        element.mapNotNull { it.jsonPrimitive.contentOrNull?.takeIf(String::isNotBlank) }
    } else {
        element.jsonPrimitive.contentOrNull?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() }
    }
}

private fun <T : Enum<T>> JsonObject.enumOf(key: String, entries: List<T>): T? =
    text(key)?.let { name -> entries.firstOrNull { it.name == name } }
