package com.migestor.data.sync

import com.migestor.data.di.KmpContainer
import com.migestor.shared.domain.AuditTrace
import com.migestor.shared.domain.LearningSituation
import com.migestor.shared.domain.LearningSituationLinkedResource
import com.migestor.shared.domain.LearningSituationResourceKind
import com.migestor.shared.domain.LearningSituationSessionPlan
import com.migestor.shared.domain.LearningSituationSessionSequenceVersion
import com.migestor.shared.domain.LearningSituationStatus
import com.migestor.shared.domain.LearningSituationVersion
import com.migestor.shared.domain.NotebookColumnCategoryKind
import com.migestor.shared.domain.NotebookInstrumentKind
import com.migestor.shared.domain.NotebookCellInputKind
import com.migestor.shared.domain.NotebookScaleKind
import com.migestor.shared.domain.NotebookColumnVisibility
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookTab
import com.migestor.shared.domain.PlannerEvaluationPeriod
import com.migestor.shared.domain.PlanningSession
import com.migestor.shared.domain.SessionStatus
import com.migestor.shared.domain.StudentSex
import com.migestor.shared.domain.StudentSexSource
import com.migestor.shared.domain.TeacherSchedule
import com.migestor.shared.domain.TeacherScheduleSlot
import com.migestor.shared.domain.TeachingUnit
import com.migestor.shared.domain.WeeklySlotTemplate
import com.migestor.shared.sync.SyncAck
import com.migestor.shared.sync.SyncChange
import com.migestor.shared.sync.SyncStoreAdapter
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
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

class SqlDelightSyncAdapter(
    private val container: KmpContainer,
    private val localDeviceId: String = "desktop",
) : SyncStoreAdapter {
    private val json = Json { ignoreUnknownKeys = true }
    private val syncIdSnapshotByScope = mutableMapOf<String, Set<String>>()
    private val syncSignatureSnapshotByScope = mutableMapOf<String, Map<String, String>>()
    private val syncSyntheticUpdatedAtByScope = mutableMapOf<String, MutableMap<String, Long>>()
    private val outgoingDeletesByEntity = mutableMapOf<String, MutableMap<String, SyncChange>>()
    private val liveIdsByEntityThisCollect = mutableMapOf<String, MutableSet<String>>()
    private var outgoingDeletesSeeded = false
    private val rosterSnapshotByClass = mutableMapOf<Long, Set<Long>>()

    // ---------------------------------------------------------------------------
    // COLLECT LOCAL CHANGES
    // ---------------------------------------------------------------------------

    override suspend fun collectLocalChanges(sinceEpochMs: Long): List<SyncChange> {
        liveIdsByEntityThisCollect.clear()
        seedOutgoingDeletesIfNeeded()
        val changes = mutableListOf<SyncChange>()
        container.academicYearsRepository.listAcademicYears().forEach { year ->
            val updatedAt = year.trace.updatedAt.toEpochMilliseconds()
            if (sinceEpochMs == 0L || updatedAt > sinceEpochMs) {
                changes += SyncChange(
                    entity = "academic_year",
                    id = year.id.toString(),
                    updatedAtEpochMs = updatedAt,
                    deviceId = year.trace.deviceId ?: localDeviceId,
                    payload = buildJsonObject {
                        put("id", JsonPrimitive(year.id))
                        put("centerId", JsonPrimitive(year.centerId))
                        put("name", JsonPrimitive(year.name))
                        put("startEpochMs", JsonPrimitive(year.startAt.toEpochMilliseconds()))
                        put("endEpochMs", JsonPrimitive(year.endAt.toEpochMilliseconds()))
                        put("status", JsonPrimitive(year.status.name))
                        put("isActive", JsonPrimitive(year.isActive))
                        put("archivedAtEpochMs", year.archivedAt?.toEpochMilliseconds()?.let(::JsonPrimitive) ?: JsonPrimitive(0L))
                    }.toString(),
                )
            }
        }
        val classes = container.classesRepository.listClasses()
        if (classes.isEmpty()) {
            listOf(
                "weekly_slot",
                "notebook_tab",
                "notebook_group",
                "notebook_group_member",
                "notebook_column",
            ).forEach { entity ->
                liveIdsByEntityThisCollect.getOrPut(entity) { mutableSetOf() }
            }
        }

        // ── Entidades vinculadas a clase ──────────────────────────────────────
        classes.forEach { schoolClass ->
            val classUpdatedAt = schoolClass.trace.updatedAt.toEpochMilliseconds()
            if (classUpdatedAt > sinceEpochMs) {
                changes += SyncChange(
                    entity = "class",
                    id = schoolClass.id.toString(),
                    updatedAtEpochMs = classUpdatedAt,
                    deviceId = schoolClass.trace.deviceId ?: localDeviceId,
                    payload = buildJsonObject {
                        put("id", JsonPrimitive(schoolClass.id))
                        put("name", JsonPrimitive(schoolClass.name))
                        put("course", JsonPrimitive(schoolClass.course))
                        put("description", schoolClass.description?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                        put("centerId", schoolClass.centerId?.let(::JsonPrimitive) ?: JsonPrimitive(0L))
                        put("academicYearId", schoolClass.academicYearId?.let(::JsonPrimitive) ?: JsonPrimitive(0L))
                        put("stageCycleId", schoolClass.stageCycleId?.let(::JsonPrimitive) ?: JsonPrimitive(0L))
                        put("subjectId", schoolClass.subjectId?.let(::JsonPrimitive) ?: JsonPrimitive(0L))
                    }.toString(),
                )
            }

            // class_roster: se envía en full pull o cuando cambia la composición del grupo.
            val classStudents = container.classesRepository.listStudentsInClass(schoolClass.id)
            val currentRosterIds = classStudents.map { it.id }.toSet()
            val previousRosterIds = rosterSnapshotByClass[schoolClass.id]
            val rosterChanged = previousRosterIds == null || previousRosterIds != currentRosterIds
            val shouldSendRoster = sinceEpochMs == 0L || rosterChanged || classUpdatedAt > sinceEpochMs
            if (shouldSendRoster) {
                val rosterUpdatedAt = if (rosterChanged) {
                    Clock.System.now().toEpochMilliseconds()
                } else {
                    classUpdatedAt
                }
                changes += SyncChange(
                    entity = "class_roster",
                    id = schoolClass.id.toString(),
                    updatedAtEpochMs = rosterUpdatedAt,
                    deviceId = localDeviceId,
                    payload = buildJsonObject {
                        put("classId", JsonPrimitive(schoolClass.id))
                        put(
                            "studentIds",
                            buildJsonArray {
                                classStudents.forEach { add(JsonPrimitive(it.id)) }
                            },
                        )
                    }.toString(),
                )
            }
            rosterSnapshotByClass[schoolClass.id] = currentRosterIds

            val weeklySlots = container.weeklyTemplateRepository.getSlotsForClass(schoolClass.id)
            val currentWeeklySlotIds = weeklySlots.map { it.id.toString() }.toSet()
            val weeklySlotScope = "class:${schoolClass.id}:weekly_slot"
            val currentWeeklySlotSignatures = weeklySlots.associate { slot ->
                slot.id.toString() to "${slot.schoolClassId}|${slot.dayOfWeek}|${slot.startTime}|${slot.endTime}"
            }
            weeklySlots.forEach { slot ->
                val updatedAt = syntheticUpdatedAt(
                    scope = weeklySlotScope,
                    id = slot.id.toString(),
                    signature = currentWeeklySlotSignatures.getValue(slot.id.toString()),
                )
                val shouldSendWeeklySlot = sinceEpochMs == 0L || updatedAt > sinceEpochMs
                if (shouldSendWeeklySlot) {
                    changes += SyncChange(
                        entity = "weekly_slot",
                        id = slot.id.toString(),
                        updatedAtEpochMs = updatedAt.takeIf { it > 0L } ?: Clock.System.now().toEpochMilliseconds(),
                        deviceId = localDeviceId,
                        payload = buildJsonObject {
                            put("id", JsonPrimitive(slot.id))
                            put("schoolClassId", JsonPrimitive(slot.schoolClassId))
                            put("dayOfWeek", JsonPrimitive(slot.dayOfWeek))
                            put("startTime", JsonPrimitive(slot.startTime))
                            put("endTime", JsonPrimitive(slot.endTime))
                        }.toString(),
                    )
                }
            }
            appendDeletesByScope(
                scope = weeklySlotScope,
                entity = "weekly_slot",
                currentIds = currentWeeklySlotIds,
            ) { deletedId ->
                buildJsonObject {
                    put("id", JsonPrimitive(deletedId.toLongOrNull() ?: 0L))
                    put("schoolClassId", JsonPrimitive(schoolClass.id))
                }
            }
            syncSignatureSnapshotByScope[weeklySlotScope] = currentWeeklySlotSignatures

            // evaluations
            container.evaluationsRepository.listClassEvaluations(schoolClass.id)
                .forEach { evaluation ->
                    val evalUpdatedAt = evaluation.trace.updatedAt.toEpochMilliseconds()
                    if (evalUpdatedAt > sinceEpochMs) {
                        changes += SyncChange(
                            entity = "evaluation",
                            id = evaluation.id.toString(),
                            updatedAtEpochMs = evalUpdatedAt,
                            deviceId = evaluation.trace.deviceId ?: localDeviceId,
                            payload = buildJsonObject {
                                put("id", JsonPrimitive(evaluation.id))
                                put("classId", JsonPrimitive(evaluation.classId))
                                put("code", JsonPrimitive(evaluation.code))
                                put("name", JsonPrimitive(evaluation.name))
                                put("type", JsonPrimitive(evaluation.type))
                                put("weight", JsonPrimitive(evaluation.weight))
                                put("formula", evaluation.formula?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                                put("rubricId", evaluation.rubricId?.let(::JsonPrimitive) ?: JsonPrimitive(0))
                                put("description", evaluation.description?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                            }.toString(),
                        )
                    }
                }

            // grades — incluye columnId real (FIX)
            container.gradesRepository.listGradesForClass(schoolClass.id).forEach { grade ->
                val gradeUpdatedAt = grade.trace.updatedAt.toEpochMilliseconds()
                if (gradeUpdatedAt > sinceEpochMs) {
                    changes += SyncChange(
                        entity = "grade",
                        id = "${grade.classId}-${grade.studentId}-${grade.columnId}",
                        updatedAtEpochMs = gradeUpdatedAt,
                        deviceId = grade.trace.deviceId ?: localDeviceId,
                        payload = buildJsonObject {
                            put("classId", JsonPrimitive(grade.classId))
                            put("studentId", JsonPrimitive(grade.studentId))
                            put("columnId", JsonPrimitive(grade.columnId))
                            put("evaluationId", JsonPrimitive(grade.evaluationId ?: 0L))
                            put("value", grade.value?.let(::JsonPrimitive) ?: JsonPrimitive(0.0))
                            put("evidence", grade.evidence?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                            put("evidencePath", grade.evidencePath?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                            put("rubricSelections", grade.rubricSelections?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                        }.toString(),
                    )
                }
            }

            // notebook tabs
            val currentTabIds = mutableSetOf<String>()
            container.notebookConfigRepository.listTabs(schoolClass.id).forEach { tab ->
                currentTabIds += tab.id
                val tabUpdatedAt = tab.trace.updatedAt.toEpochMilliseconds()
                if (tabUpdatedAt > sinceEpochMs) {
                    changes += SyncChange(
                        entity = "notebook_tab",
                        id = tab.id,
                        updatedAtEpochMs = tabUpdatedAt,
                        deviceId = tab.trace.deviceId ?: localDeviceId,
                        payload = buildJsonObject {
                            put("id", JsonPrimitive(tab.id))
                            put("classId", JsonPrimitive(schoolClass.id))
                            put("title", JsonPrimitive(tab.title))
                            put("description", tab.description?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                            put("order", JsonPrimitive(tab.order))
                            put("parentTabId", tab.parentTabId?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                        }.toString(),
                    )
                }
            }
            appendDeletesByScope(
                scope = "class:${schoolClass.id}:notebook_tab",
                entity = "notebook_tab",
                currentIds = currentTabIds,
            ) { deletedId ->
                buildJsonObject {
                    put("id", JsonPrimitive(deletedId))
                    put("classId", JsonPrimitive(schoolClass.id))
                }
            }

            // notebook work groups
            val currentWorkGroupIds = mutableSetOf<String>()
            container.notebookConfigRepository.listWorkGroups(schoolClass.id).forEach { group ->
                val groupUpdatedAt = group.trace.updatedAt.toEpochMilliseconds()
                currentWorkGroupIds += group.id.toString()
                if (groupUpdatedAt > sinceEpochMs) {
                    changes += SyncChange(
                        entity = "notebook_group",
                        id = group.id.toString(),
                        updatedAtEpochMs = groupUpdatedAt,
                        deviceId = group.trace.deviceId ?: localDeviceId,
                        payload = buildJsonObject {
                            put("id", JsonPrimitive(group.id))
                            put("classId", JsonPrimitive(group.classId))
                            put("tabId", JsonPrimitive(group.tabId))
                            put("name", JsonPrimitive(group.name))
                            put("order", JsonPrimitive(group.order))
                            group.learningSituationId?.let { put("learningSituationId", JsonPrimitive(it)) }
                        }.toString(),
                    )
                }
            }
            appendDeletesByScope(
                scope = "class:${schoolClass.id}:notebook_group",
                entity = "notebook_group",
                currentIds = currentWorkGroupIds,
            ) { deletedId ->
                buildJsonObject {
                    put("id", JsonPrimitive(deletedId.toLongOrNull() ?: 0L))
                }
            }

            val currentWorkGroupMemberIds = mutableSetOf<String>()
            container.notebookConfigRepository.listWorkGroupMembers(schoolClass.id).forEach { member ->
                val memberUpdatedAt = member.trace.updatedAt.toEpochMilliseconds()
                val memberId = "${member.classId}|${member.tabId}|${member.groupId}|${member.studentId}"
                currentWorkGroupMemberIds += memberId
                if (memberUpdatedAt > sinceEpochMs) {
                    changes += SyncChange(
                        entity = "notebook_group_member",
                        id = memberId,
                        updatedAtEpochMs = memberUpdatedAt,
                        deviceId = member.trace.deviceId ?: localDeviceId,
                        payload = buildJsonObject {
                            put("classId", JsonPrimitive(member.classId))
                            put("tabId", JsonPrimitive(member.tabId))
                            put("groupId", JsonPrimitive(member.groupId))
                            put("studentId", JsonPrimitive(member.studentId))
                        }.toString(),
                    )
                }
            }
            appendDeletesByScope(
                scope = "class:${schoolClass.id}:notebook_group_member",
                entity = "notebook_group_member",
                currentIds = currentWorkGroupMemberIds,
            ) { deletedId ->
                val parts = deletedId.split("|")
                buildJsonObject {
                    put("classId", JsonPrimitive(parts.getOrNull(0)?.toLongOrNull() ?: 0L))
                    put("tabId", JsonPrimitive(parts.getOrNull(1) ?: ""))
                    put("groupId", JsonPrimitive(parts.getOrNull(2)?.toLongOrNull() ?: 0L))
                    put("studentId", JsonPrimitive(parts.getOrNull(3)?.toLongOrNull() ?: 0L))
                }
            }

            // notebook columns
            val tabs = container.notebookConfigRepository.listTabs(schoolClass.id)
            val tabTitleMap = tabs.associate { it.id to it.title }
            val currentColumnIds = mutableSetOf<String>()

            container.notebookConfigRepository.listColumns(schoolClass.id).forEach { column ->
                val columnUpdatedAt = column.trace.updatedAt.toEpochMilliseconds()
                if (columnUpdatedAt > sinceEpochMs) {
                    val standardizedId = column.evaluationId?.let { "eval_$it" } ?: column.id
                    currentColumnIds += standardizedId
                    val colTabTitles = column.tabIds.mapNotNull { tabTitleMap[it] }
                    
                    changes += SyncChange(
                        entity = "notebook_column",
                        id = standardizedId,
                        updatedAtEpochMs = columnUpdatedAt,
                        deviceId = column.trace.deviceId ?: localDeviceId,
                        payload = buildJsonObject {
                            put("id", JsonPrimitive(standardizedId))
                            put("classId", JsonPrimitive(schoolClass.id))
                            put("title", JsonPrimitive(column.title))
                            put("type", JsonPrimitive(column.type.name))
                            put("column_type", JsonPrimitive(column.type.name))
                            put("evaluationId", column.evaluationId?.let(::JsonPrimitive) ?: JsonPrimitive(0))
                            put("rubricId", column.rubricId?.let(::JsonPrimitive) ?: JsonPrimitive(0))
                            put("formula", column.formula?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                            put("weight", JsonPrimitive(column.weight))
                            put("tabIdsCsv", JsonPrimitive(column.tabIds.joinToString(",")))
                            put("tab_ids_csv", JsonPrimitive(column.tabIds.joinToString(",")))
                            put("tabTitlesCsv", JsonPrimitive(colTabTitles.joinToString(",")))
                            put("tab_titles_csv", JsonPrimitive(colTabTitles.joinToString(",")))
                            put("sharedAcrossTabs", JsonPrimitive(column.sharedAcrossTabs))
                            put("shared_across_tabs", JsonPrimitive(column.sharedAcrossTabs))
                            put("colorHex", column.colorHex?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                            put("categoryKind", JsonPrimitive(column.categoryKind.name))
                            put("instrumentKind", JsonPrimitive(column.instrumentKind.name))
                            put("inputKind", JsonPrimitive(column.inputKind.name))
                            put("scaleKind", JsonPrimitive(column.scaleKind.name))
                            put("dateEpochMs", column.dateEpochMs?.let(::JsonPrimitive) ?: JsonPrimitive(0))
                            put("unitOrSituation", JsonPrimitive(column.unitOrSituation ?: ""))
                            put("competencyCriteriaIds", JsonPrimitive(column.competencyCriteriaIds.joinToString(",")))
                            put("iconName", JsonPrimitive(column.iconName ?: ""))
                            put("order", JsonPrimitive(column.order))
                            put("widthDp", JsonPrimitive(column.widthDp))
                            put("categoryId", JsonPrimitive(column.categoryId ?: ""))
                            put("countsTowardAverage", JsonPrimitive(column.countsTowardAverage))
                            put("isPinned", JsonPrimitive(column.isPinned))
                            put("isHidden", JsonPrimitive(column.isHidden))
                            put("visibility", JsonPrimitive(column.visibility.name))
                            put("isLocked", JsonPrimitive(column.isLocked))
                            put("isTemplate", JsonPrimitive(column.isTemplate))
                        }.toString(),
                    )
                }
                if (columnUpdatedAt <= sinceEpochMs) {
                    val standardizedId = column.evaluationId?.let { "eval_$it" } ?: column.id
                    currentColumnIds += standardizedId
                }
            }
            appendDeletesByScope(
                scope = "class:${schoolClass.id}:notebook_column",
                entity = "notebook_column",
                currentIds = currentColumnIds,
            ) { deletedId ->
                buildJsonObject {
                    put("id", JsonPrimitive(deletedId))
                    put("classId", JsonPrimitive(schoolClass.id))
                }
            }

            // notebook cells
            container.notebookCellsRepository.listClassCells(schoolClass.id).forEach { cell ->
                val cellUpdatedAt = cell.trace.updatedAt.toEpochMilliseconds()
                if (cellUpdatedAt > sinceEpochMs) {
                    changes += SyncChange(
                        entity = "notebook_cell",
                        id = "${cell.classId}-${cell.studentId}-${cell.columnId}",
                        updatedAtEpochMs = cellUpdatedAt,
                        deviceId = cell.trace.deviceId ?: localDeviceId,
                        payload = buildJsonObject {
                            put("classId", JsonPrimitive(cell.classId))
                            put("studentId", JsonPrimitive(cell.studentId))
                            put("columnId", JsonPrimitive(cell.columnId))
                            put("textValue", cell.textValue?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                            put("boolValue", cell.boolValue?.let(::JsonPrimitive) ?: JsonPrimitive(false))
                            put("iconValue", cell.iconValue?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                            put("ordinalValue", cell.ordinalValue?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                            put("note", cell.annotation?.note?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                            put("colorHex", cell.annotation?.colorHex?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                            put(
                                "attachmentUris",
                                buildJsonArray {
                                    (cell.annotation?.attachmentUris ?: emptyList()).forEach { add(JsonPrimitive(it)) }
                                },
                            )
                        }.toString(),
                    )
                }
            }

            // notebook instrument templates, items & responses
            container.database.appDatabaseQueries.selectAllInstrumentTemplatesByClass(schoolClass.id).executeAsList().forEach { t ->
                val templateUpdatedAt = t.updated_at_epoch_ms
                if (templateUpdatedAt > sinceEpochMs) {
                    changes += SyncChange(
                        entity = "notebook_instrument_template",
                        id = t.id,
                        updatedAtEpochMs = templateUpdatedAt,
                        deviceId = t.device_id ?: localDeviceId,
                        payload = buildJsonObject {
                            put("id", JsonPrimitive(t.id))
                            put("classId", JsonPrimitive(t.class_id))
                            put("columnId", JsonPrimitive(t.column_id))
                            put("evaluationId", t.evaluation_id?.let(::JsonPrimitive) ?: JsonPrimitive(0))
                            put("title", JsonPrimitive(t.title))
                            put("kind", JsonPrimitive(t.kind))
                            put("inputKind", JsonPrimitive(t.input_kind))
                            put("source", JsonPrimitive(t.source ?: ""))
                            put("createdAtEpochMs", JsonPrimitive(t.created_at_epoch_ms))
                        }.toString(),
                    )
                }
                container.database.appDatabaseQueries.selectInstrumentItemsByTemplate(t.id).executeAsList().forEach { item ->
                    val itemUpdatedAt = item.updated_at_epoch_ms
                    if (itemUpdatedAt > sinceEpochMs) {
                        changes += SyncChange(
                            entity = "notebook_instrument_item",
                            id = item.id,
                            updatedAtEpochMs = itemUpdatedAt,
                            deviceId = item.device_id ?: localDeviceId,
                            payload = buildJsonObject {
                                put("id", JsonPrimitive(item.id))
                                put("templateId", JsonPrimitive(item.template_id))
                                put("itemKey", JsonPrimitive(item.item_key))
                                put("title", JsonPrimitive(item.title))
                                put("itemType", JsonPrimitive(item.item_type))
                                put("optionsCsv", JsonPrimitive(item.options_csv))
                                put("required", JsonPrimitive(item.required != 0L))
                                put("sortOrder", JsonPrimitive(item.sort_order))
                                put("helpText", JsonPrimitive(item.help_text ?: ""))
                            }.toString(),
                        )
                    }
                }
            }

            container.database.appDatabaseQueries.selectAllInstrumentResponsesByClass(schoolClass.id).executeAsList().forEach { r ->
                val responseUpdatedAt = r.updated_at_epoch_ms
                if (responseUpdatedAt > sinceEpochMs) {
                    changes += SyncChange(
                        entity = "notebook_instrument_response",
                        id = "${r.class_id}-${r.student_id}-${r.column_id}-${r.item_id}",
                        updatedAtEpochMs = responseUpdatedAt,
                        deviceId = r.device_id ?: localDeviceId,
                        payload = buildJsonObject {
                            put("classId", JsonPrimitive(r.class_id))
                            put("studentId", JsonPrimitive(r.student_id))
                            put("columnId", JsonPrimitive(r.column_id))
                            put("itemId", JsonPrimitive(r.item_id))
                            put("valueText", JsonPrimitive(r.value_text ?: ""))
                            put("valueBool", r.value_bool?.let { JsonPrimitive(it != 0L) } ?: JsonPrimitive(false))
                            put("valueNumber", JsonPrimitive(r.value_number?.toString() ?: ""))
                        }.toString(),
                    )
                }
            }

            // ── Asistencia ────────────────────────────────────────────────────
            container.attendanceRepository.listAttendance(schoolClass.id).forEach { att ->
                val attUpdatedAt = att.trace.updatedAt.toEpochMilliseconds()
                if (attUpdatedAt > sinceEpochMs) {
                    changes += SyncChange(
                        entity = "attendance",
                        id = "${att.classId}-${att.studentId}-${att.date.toEpochMilliseconds()}",
                        updatedAtEpochMs = attUpdatedAt,
                        deviceId = att.trace.deviceId ?: localDeviceId,
                        payload = buildJsonObject {
                            put("id", JsonPrimitive(att.id))
                            put("classId", JsonPrimitive(att.classId))
                            put("studentId", JsonPrimitive(att.studentId))
                            put("dateEpochMs", JsonPrimitive(att.date.toEpochMilliseconds()))
                            put("status", JsonPrimitive(att.status))
                            put("note", JsonPrimitive(att.note))
                            put("hasIncident", JsonPrimitive(att.hasIncident))
                            put("followUpRequired", JsonPrimitive(att.followUpRequired))
                            att.sessionId?.let { put("sessionId", JsonPrimitive(it)) }
                        }.toString(),
                    )
                }
            }

            // ── Incidencias ───────────────────────────────────────────────────
            container.incidentsRepository.listIncidents(schoolClass.id).forEach { incident ->
                val incUpdatedAt = incident.trace.updatedAt.toEpochMilliseconds()
                if (incUpdatedAt > sinceEpochMs) {
                    changes += SyncChange(
                        entity = "incident",
                        id = incident.id.toString(),
                        updatedAtEpochMs = incUpdatedAt,
                        deviceId = incident.trace.deviceId ?: localDeviceId,
                        payload = buildJsonObject {
                            put("id", JsonPrimitive(incident.id))
                            put("classId", JsonPrimitive(incident.classId))
                            put("studentId", incident.studentId?.let(::JsonPrimitive) ?: JsonPrimitive(0L))
                            put("title", JsonPrimitive(incident.title))
                            put("detail", incident.detail?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                            put("severity", JsonPrimitive(incident.severity))
                            put("dateEpochMs", JsonPrimitive(incident.date.toEpochMilliseconds()))
                        }.toString(),
                    )
                }
            }
        }

        // ── Estudiantes (globales) ────────────────────────────────────────────
        val currentStudentIds = mutableSetOf<String>()
        container.studentsRepository.listStudents().forEach { student ->
            currentStudentIds += student.id.toString()
            val updatedAt = student.trace.updatedAt.toEpochMilliseconds()
            if (updatedAt > sinceEpochMs) {
                changes += SyncChange(
                    entity = "student",
                    id = student.id.toString(),
                    updatedAtEpochMs = updatedAt,
                    deviceId = student.trace.deviceId ?: localDeviceId,
                    payload = buildJsonObject {
                        put("id", JsonPrimitive(student.id))
                        put("firstName", JsonPrimitive(student.firstName))
                        put("lastName", JsonPrimitive(student.lastName))
                        put("email", student.email?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                        put("photoPath", student.photoPath?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                        put("isInjured", JsonPrimitive(student.isInjured))
                        put("sex", JsonPrimitive(student.sex.name))
                        put("sexSource", JsonPrimitive(student.sexSource.name))
                        put("birthDate", student.birthDate?.toString()?.let(::JsonPrimitive) ?: JsonNull)
                    }.toString(),
                )
            }
        }
        appendDeletesByScope(
            scope = "global:student",
            entity = "student",
            currentIds = currentStudentIds,
        ) { deletedId ->
            buildJsonObject {
                put("id", JsonPrimitive(deletedId.toLongOrNull() ?: 0L))
            }
        }

        // ── Rúbricas (bundle con criterios y niveles) ─────────────────────────
        val currentRubricIds = mutableSetOf<String>()
        container.rubricsRepository.listRubrics().forEach { rubric ->
            currentRubricIds += rubric.rubric.id.toString()
            val updatedAt = rubric.rubric.trace.updatedAt.toEpochMilliseconds()
            if (updatedAt > sinceEpochMs) {
                changes += SyncChange(
                    entity = "rubric_bundle",
                    id = rubric.rubric.id.toString(),
                    updatedAtEpochMs = updatedAt,
                    deviceId = rubric.rubric.trace.deviceId ?: localDeviceId,
                    payload = buildJsonObject {
                        put("rubricId", JsonPrimitive(rubric.rubric.id))
                        put("name", JsonPrimitive(rubric.rubric.name))
                        put("description", rubric.rubric.description?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                        put(
                            "criteria",
                            buildJsonArray {
                                rubric.criteria.forEach { criterionWithLevels ->
                                    add(
                                        buildJsonObject {
                                            put("id", JsonPrimitive(criterionWithLevels.criterion.id))
                                            put("description", JsonPrimitive(criterionWithLevels.criterion.description))
                                            put("weight", JsonPrimitive(criterionWithLevels.criterion.weight))
                                            put("order", JsonPrimitive(criterionWithLevels.criterion.order))
                                            put(
                                                "levels",
                                                buildJsonArray {
                                                    criterionWithLevels.levels.forEach { level ->
                                                        add(
                                                            buildJsonObject {
                                                                put("id", JsonPrimitive(level.id))
                                                                put("name", JsonPrimitive(level.name))
                                                                put("points", JsonPrimitive(level.points))
                                                                put("description", level.description?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                                                                put("order", JsonPrimitive(level.order))
                                                            },
                                                        )
                                                    }
                                                },
                                            )
                                        },
                                    )
                                }
                            },
                        )
                    }.toString(),
                )
            }
        }
        appendDeletesByScope(
            scope = "global:rubric_bundle",
            entity = "rubric_bundle",
            currentIds = currentRubricIds,
        ) { deletedId ->
            buildJsonObject {
                put("rubricId", JsonPrimitive(deletedId.toLongOrNull() ?: 0L))
            }
        }

        // ── Evaluaciones de rúbrica (assessments individuales) ────────────────
        // Iteramos las clases → las evaluaciones del tipo rúbrica → los alumnos → los assessments
        classes.forEach { schoolClass ->
            container.evaluationsRepository.listClassEvaluations(schoolClass.id)
                .filter { it.rubricId != null }
                .forEach { evaluation ->
                    container.classesRepository.listStudentsInClass(schoolClass.id).forEach { student ->
                        container.rubricsRepository.listRubricAssessments(student.id, evaluation.id)
                            .forEach { assessment ->
                                val assessmentUpdatedAt = assessment.trace.updatedAt.toEpochMilliseconds()
                                if (assessmentUpdatedAt > sinceEpochMs) {
                                    changes += SyncChange(
                                        entity = "rubric_assessment",
                                        id = "${assessment.studentId}-${assessment.evaluationId}-${assessment.criterionId}",
                                        updatedAtEpochMs = assessmentUpdatedAt,
                                        deviceId = assessment.trace.deviceId ?: localDeviceId,
                                        payload = buildJsonObject {
                                            put("studentId", JsonPrimitive(assessment.studentId))
                                            put("evaluationId", JsonPrimitive(assessment.evaluationId))
                                            put("criterionId", JsonPrimitive(assessment.criterionId))
                                            put("levelId", JsonPrimitive(assessment.levelId))
                                        }.toString(),
                                    )
                                }
                            }
                    }
                }
        }

        // ── Eventos del calendario (globales) ─────────────────────────────────
        container.calendarRepository.listEvents(null).forEach { event ->
            val eventUpdatedAt = event.trace.updatedAt.toEpochMilliseconds()
            if (eventUpdatedAt > sinceEpochMs) {
                changes += SyncChange(
                    entity = "calendar_event",
                    id = event.id.toString(),
                    updatedAtEpochMs = eventUpdatedAt,
                    deviceId = event.trace.deviceId ?: localDeviceId,
                    payload = buildJsonObject {
                        put("id", JsonPrimitive(event.id))
                        put("classId", event.classId?.let(::JsonPrimitive) ?: JsonPrimitive(0L))
                        put("title", JsonPrimitive(event.title))
                        put("description", event.description?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                        put("startEpochMs", JsonPrimitive(event.startAt.toEpochMilliseconds()))
                        put("endEpochMs", JsonPrimitive(event.endAt.toEpochMilliseconds()))
                        put("externalProvider", event.externalProvider?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                        put("externalId", event.externalId?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                    }.toString(),
                )
            }
        }

        // ── Planner: Teaching Units y Sessions ────────────────────────────────
        val teachingUnits = container.plannerRepository.listAllTeachingUnits()
        val teachingUnitScope = "global:teaching_unit"
        val teachingUnitSignatures = teachingUnits.associate { unit ->
            unit.id.toString() to listOf(
                unit.name,
                unit.description,
                unit.colorHex,
                unit.groupId?.toString().orEmpty(),
                unit.schoolClassId?.toString().orEmpty(),
                unit.startDate?.toString().orEmpty(),
                unit.endDate?.toString().orEmpty(),
            ).joinToString("|")
        }
        teachingUnits.forEach { unit ->
            val updatedAt = syntheticUpdatedAt(teachingUnitScope, unit.id.toString(), teachingUnitSignatures.getValue(unit.id.toString()))
            if (sinceEpochMs == 0L || updatedAt > sinceEpochMs) {
                changes += SyncChange(
                    entity = "teaching_unit",
                    id = unit.id.toString(),
                    updatedAtEpochMs = updatedAt.takeIf { it > 0L } ?: Clock.System.now().toEpochMilliseconds(),
                    deviceId = localDeviceId,
                    payload = buildJsonObject {
                        put("id", JsonPrimitive(unit.id))
                        put("name", JsonPrimitive(unit.name))
                        put("description", JsonPrimitive(unit.description))
                        put("colorHex", JsonPrimitive(unit.colorHex))
                        put("groupId", unit.groupId?.let(::JsonPrimitive) ?: JsonPrimitive(0))
                        put("schoolClassId", unit.schoolClassId?.let(::JsonPrimitive) ?: JsonPrimitive(0))
                        put("startDate", unit.startDate?.toString()?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                        put("endDate", unit.endDate?.toString()?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                    }.toString(),
                )
            }
        }
        appendDeletesByScope(
            scope = teachingUnitScope,
            entity = "teaching_unit",
            currentIds = teachingUnits.map { it.id.toString() }.toSet(),
        ) { deletedId ->
            buildJsonObject { put("id", JsonPrimitive(deletedId.toLongOrNull() ?: 0L)) }
        }
        syncSignatureSnapshotByScope[teachingUnitScope] = teachingUnitSignatures

        val plannerSessions = container.plannerRepository.listAllSessions()
        val plannerSessionScope = "global:planning_session"
        val plannerSessionSignatures = plannerSessions.associate { session ->
            session.id.toString() to listOf(
                session.teachingUnitId.toString(),
                session.groupId.toString(),
                session.dayOfWeek.toString(),
                session.period.toString(),
                session.weekNumber.toString(),
                session.year.toString(),
                session.objectives,
                session.activities,
                session.evaluation,
                session.linkedAssessmentIdsCsv,
                session.teacherScheduleSlotId?.toString().orEmpty(),
                session.startTime.orEmpty(),
                session.endTime.orEmpty(),
                session.learningSituationSessionPlanId?.toString().orEmpty(),
                session.status.name,
            ).joinToString("|")
        }
        plannerSessions.forEach { session ->
            val updatedAt = syntheticUpdatedAt(plannerSessionScope, session.id.toString(), plannerSessionSignatures.getValue(session.id.toString()))
            if (sinceEpochMs == 0L || updatedAt > sinceEpochMs) {
                changes += SyncChange(
                    entity = "planning_session",
                    id = session.id.toString(),
                    updatedAtEpochMs = updatedAt.takeIf { it > 0L } ?: Clock.System.now().toEpochMilliseconds(),
                    deviceId = localDeviceId,
                    payload = buildJsonObject {
                        put("id", JsonPrimitive(session.id))
                        put("teachingUnitId", JsonPrimitive(session.teachingUnitId))
                        put("teachingUnitName", JsonPrimitive(session.teachingUnitName))
                        put("teachingUnitColor", JsonPrimitive(session.teachingUnitColor))
                        put("groupId", JsonPrimitive(session.groupId))
                        put("groupName", JsonPrimitive(session.groupName))
                        put("dayOfWeek", JsonPrimitive(session.dayOfWeek))
                        put("period", JsonPrimitive(session.period))
                        put("weekNumber", JsonPrimitive(session.weekNumber))
                        put("year", JsonPrimitive(session.year))
                        put("objectives", JsonPrimitive(session.objectives))
                        put("activities", JsonPrimitive(session.activities))
                        put("evaluation", JsonPrimitive(session.evaluation))
                        put("linkedAssessmentIdsCsv", JsonPrimitive(session.linkedAssessmentIdsCsv))
                        put("teacherScheduleSlotId", session.teacherScheduleSlotId?.let(::JsonPrimitive) ?: JsonNull)
                        put("startTime", session.startTime?.let(::JsonPrimitive) ?: JsonNull)
                        put("endTime", session.endTime?.let(::JsonPrimitive) ?: JsonNull)
                        put("learningSituationSessionPlanId", session.learningSituationSessionPlanId?.let(::JsonPrimitive) ?: JsonNull)
                        put("status", JsonPrimitive(session.status.name))
                    }.toString(),
                )
            }
        }
        appendDeletesByScope(
            scope = plannerSessionScope,
            entity = "planning_session",
            currentIds = plannerSessions.map { it.id.toString() }.toSet(),
        ) { deletedId ->
            buildJsonObject { put("id", JsonPrimitive(deletedId.toLongOrNull() ?: 0L)) }
        }
        syncSignatureSnapshotByScope[plannerSessionScope] = plannerSessionSignatures

        val journals = plannerSessions.mapNotNull { session ->
            container.sessionJournalRepository.getJournalForSession(session.id)
        }
        val journalScope = "global:session_journal"
        val journalSignatures = journals.associate { aggregate ->
            aggregate.journal.planningSessionId.toString() to SessionJournalSyncCodec.signature(aggregate)
        }
        journals.forEach { aggregate ->
            val journalId = aggregate.journal.planningSessionId.toString()
            val updatedAt = syntheticUpdatedAt(journalScope, journalId, journalSignatures.getValue(journalId))
            if (sinceEpochMs == 0L || updatedAt > sinceEpochMs) {
                changes += SyncChange(
                    entity = "session_journal",
                    id = journalId,
                    updatedAtEpochMs = updatedAt.takeIf { it > 0L } ?: Clock.System.now().toEpochMilliseconds(),
                    deviceId = localDeviceId,
                    payload = SessionJournalSyncCodec.encode(aggregate),
                )
            }
        }
        appendDeletesByScope(
            scope = journalScope,
            entity = "session_journal",
            currentIds = journals.map { it.journal.planningSessionId.toString() }.toSet(),
        ) { deletedId ->
            buildJsonObject { put("planningSessionId", JsonPrimitive(deletedId.toLongOrNull() ?: 0L)) }
        }
        syncSignatureSnapshotByScope[journalScope] = journalSignatures

        val teacherSchedules = container.database.appDatabaseQueries.selectAllTeacherSchedules().executeAsList()
        if (teacherSchedules.isEmpty()) {
            liveIdsByEntityThisCollect.getOrPut("teacher_schedule_slot") { mutableSetOf() }
            liveIdsByEntityThisCollect.getOrPut("planner_evaluation_period") { mutableSetOf() }
        }
        val currentTeacherScheduleIds = teacherSchedules.map { it.id.toString() }.toSet()
        teacherSchedules.forEach { schedule ->
            if (schedule.updated_at_epoch_ms > sinceEpochMs) {
                changes += SyncChange(
                    entity = "teacher_schedule",
                    id = schedule.id.toString(),
                    updatedAtEpochMs = schedule.updated_at_epoch_ms,
                    deviceId = schedule.device_id ?: localDeviceId,
                    payload = buildJsonObject {
                        put("id", JsonPrimitive(schedule.id))
                        put("ownerUserId", JsonPrimitive(schedule.owner_user_id))
                        put("academicYearId", JsonPrimitive(schedule.academic_year_id))
                        put("name", JsonPrimitive(schedule.name))
                        put("startDateIso", JsonPrimitive(schedule.start_date))
                        put("endDateIso", JsonPrimitive(schedule.end_date))
                        put("activeWeekdaysCsv", JsonPrimitive(schedule.active_weekdays))
                        put("authorUserId", schedule.author_user_id?.let(::JsonPrimitive) ?: JsonPrimitive(0L))
                        put("createdAtEpochMs", JsonPrimitive(schedule.created_at_epoch_ms))
                        put("updatedAtEpochMs", JsonPrimitive(schedule.updated_at_epoch_ms))
                        put("associatedGroupId", schedule.associated_group_id?.let(::JsonPrimitive) ?: JsonPrimitive(0L))
                    }.toString(),
                )
            }

            val scheduleSlots = container.teacherScheduleRepository.listScheduleSlots(schedule.id)
            val slotScope = "teacher_schedule:${schedule.id}:slot"
            val slotSignatures = scheduleSlots.associate { slot ->
                slot.id.toString() to listOf(
                    slot.teacherScheduleId.toString(),
                    slot.schoolClassId.toString(),
                    slot.subjectLabel,
                    slot.unitLabel.orEmpty(),
                    slot.dayOfWeek.toString(),
                    slot.startTime,
                    slot.endTime,
                    slot.weeklyTemplateId?.toString().orEmpty(),
                ).joinToString("|")
            }
            scheduleSlots.forEach { slot ->
                val updatedAt = syntheticUpdatedAt(slotScope, slot.id.toString(), slotSignatures.getValue(slot.id.toString()))
                if (sinceEpochMs == 0L || updatedAt > sinceEpochMs) {
                    changes += SyncChange(
                        entity = "teacher_schedule_slot",
                        id = slot.id.toString(),
                        updatedAtEpochMs = updatedAt.takeIf { it > 0L } ?: Clock.System.now().toEpochMilliseconds(),
                        deviceId = localDeviceId,
                        payload = buildJsonObject {
                            put("id", JsonPrimitive(slot.id))
                            put("teacherScheduleId", JsonPrimitive(slot.teacherScheduleId))
                            put("schoolClassId", JsonPrimitive(slot.schoolClassId))
                            put("subjectLabel", JsonPrimitive(slot.subjectLabel))
                            put("unitLabel", slot.unitLabel?.let(::JsonPrimitive) ?: JsonPrimitive(""))
                            put("dayOfWeek", JsonPrimitive(slot.dayOfWeek))
                            put("startTime", JsonPrimitive(slot.startTime))
                            put("endTime", JsonPrimitive(slot.endTime))
                            put("weeklyTemplateId", slot.weeklyTemplateId?.let(::JsonPrimitive) ?: JsonPrimitive(0L))
                        }.toString(),
                    )
                }
            }
            appendDeletesByScope(
                scope = slotScope,
                entity = "teacher_schedule_slot",
                currentIds = scheduleSlots.map { it.id.toString() }.toSet(),
            ) { deletedId ->
                buildJsonObject {
                    put("id", JsonPrimitive(deletedId.toLongOrNull() ?: 0L))
                    put("teacherScheduleId", JsonPrimitive(schedule.id))
                }
            }
            syncSignatureSnapshotByScope[slotScope] = slotSignatures

            val periods = container.teacherScheduleRepository.listEvaluationPeriods(schedule.id)
            val periodScope = "teacher_schedule:${schedule.id}:evaluation_period"
            val periodSignatures = periods.associate { period ->
                period.id.toString() to listOf(
                    period.teacherScheduleId.toString(),
                    period.name,
                    period.startDateIso,
                    period.endDateIso,
                    period.sortOrder.toString(),
                ).joinToString("|")
            }
            periods.forEach { period ->
                val updatedAt = syntheticUpdatedAt(periodScope, period.id.toString(), periodSignatures.getValue(period.id.toString()))
                if (sinceEpochMs == 0L || updatedAt > sinceEpochMs) {
                    changes += SyncChange(
                        entity = "planner_evaluation_period",
                        id = period.id.toString(),
                        updatedAtEpochMs = updatedAt.takeIf { it > 0L } ?: Clock.System.now().toEpochMilliseconds(),
                        deviceId = localDeviceId,
                        payload = buildJsonObject {
                            put("id", JsonPrimitive(period.id))
                            put("teacherScheduleId", JsonPrimitive(period.teacherScheduleId))
                            put("name", JsonPrimitive(period.name))
                            put("startDateIso", JsonPrimitive(period.startDateIso))
                            put("endDateIso", JsonPrimitive(period.endDateIso))
                            put("sortOrder", JsonPrimitive(period.sortOrder))
                        }.toString(),
                    )
                }
            }
            appendDeletesByScope(
                scope = periodScope,
                entity = "planner_evaluation_period",
                currentIds = periods.map { it.id.toString() }.toSet(),
            ) { deletedId ->
                buildJsonObject {
                    put("id", JsonPrimitive(deletedId.toLongOrNull() ?: 0L))
                    put("teacherScheduleId", JsonPrimitive(schedule.id))
                }
            }
            syncSignatureSnapshotByScope[periodScope] = periodSignatures
        }
        appendDeletesByScope(
            scope = "global:teacher_schedule",
            entity = "teacher_schedule",
            currentIds = currentTeacherScheduleIds,
        ) { deletedId ->
            buildJsonObject { put("id", JsonPrimitive(deletedId.toLongOrNull() ?: 0L)) }
        }

        // ── Situaciones: metadatos; el DOCX se transfiere por hash fuera de JSON ──
        container.learningSituationsRepository.listSituations().forEach { situation ->
            val updatedAt = situation.trace.updatedAt.toEpochMilliseconds()
            if (sinceEpochMs == 0L || updatedAt > sinceEpochMs) {
                changes += SyncChange(
                    entity = "learning_situation",
                    id = situation.id.toString(),
                    updatedAtEpochMs = updatedAt,
                    deviceId = situation.trace.deviceId ?: localDeviceId,
                    payload = buildJsonObject {
                        put("id", JsonPrimitive(situation.id))
                        put("title", JsonPrimitive(situation.title))
                        put("stageLabel", JsonPrimitive(situation.stageLabel))
                        put("courseLabel", JsonPrimitive(situation.courseLabel))
                        put("subjectLabel", JsonPrimitive(situation.subjectLabel))
                        put("termLabel", JsonPrimitive(situation.termLabel))
                        put("centerLabel", JsonPrimitive(situation.centerLabel))
                        put("sessionCount", JsonPrimitive(situation.sessionCount))
                        put("challenge", JsonPrimitive(situation.challenge))
                        put("finalProduct", JsonPrimitive(situation.finalProduct))
                        put("payloadJson", JsonPrimitive(situation.payloadJson))
                        put("status", JsonPrimitive(situation.status.name))
                    }.toString(),
                )
            }
            container.learningSituationsRepository.listVersions(situation.id).forEach { version ->
                val versionUpdatedAt = version.trace.updatedAt.toEpochMilliseconds()
                if (sinceEpochMs == 0L || versionUpdatedAt > sinceEpochMs) {
                    changes += SyncChange(
                        entity = "learning_situation_version",
                        id = "${situation.id}-${version.versionNumber}",
                        updatedAtEpochMs = versionUpdatedAt,
                        deviceId = version.trace.deviceId ?: localDeviceId,
                        payload = buildJsonObject {
                            put("id", JsonPrimitive(version.id))
                            put("learningSituationId", JsonPrimitive(situation.id))
                            put("versionNumber", JsonPrimitive(version.versionNumber))
                            put("originalFileName", JsonPrimitive(version.originalFileName))
                            put("sha256", JsonPrimitive(version.sha256))
                            put("sizeBytes", JsonPrimitive(version.sizeBytes))
                            put("payloadJson", JsonPrimitive(version.payloadJson))
                            put("warningsJson", JsonPrimitive(version.warningsJson))
                        }.toString(),
                    )
                }
            }
            container.learningSituationsRepository.listSessionSequenceVersions(situation.id).forEach { version ->
                val versionUpdatedAt = version.trace.updatedAt.toEpochMilliseconds()
                if (sinceEpochMs == 0L || versionUpdatedAt > sinceEpochMs) {
                    changes += SyncChange(
                        entity = "learning_situation_sequence_version",
                        id = "${situation.id}-${version.versionNumber}",
                        updatedAtEpochMs = versionUpdatedAt,
                        deviceId = version.trace.deviceId ?: localDeviceId,
                        payload = buildJsonObject {
                            put("id", JsonPrimitive(version.id))
                            put("learningSituationId", JsonPrimitive(situation.id))
                            put("versionNumber", JsonPrimitive(version.versionNumber))
                            put("originalFileName", JsonPrimitive(version.originalFileName))
                            put("sha256", JsonPrimitive(version.sha256))
                            put("sizeBytes", JsonPrimitive(version.sizeBytes))
                            put("payloadJson", JsonPrimitive(version.payloadJson))
                            put("warningsJson", JsonPrimitive(version.warningsJson))
                        }.toString(),
                    )
                }
                container.learningSituationsRepository.listSessionPlans(version.id).forEach { plan ->
                    val planUpdatedAt = plan.trace.updatedAt.toEpochMilliseconds()
                    if (sinceEpochMs == 0L || planUpdatedAt > sinceEpochMs) {
                        changes += SyncChange(
                            entity = "learning_situation_session_plan",
                            id = plan.id.toString(),
                            updatedAtEpochMs = planUpdatedAt,
                            deviceId = plan.trace.deviceId ?: localDeviceId,
                            payload = buildJsonObject {
                                put("id", JsonPrimitive(plan.id))
                                put("learningSituationId", JsonPrimitive(plan.learningSituationId))
                                put("sequenceVersionId", JsonPrimitive(plan.sequenceVersionId))
                                put("sessionNumber", JsonPrimitive(plan.sessionNumber))
                                put("sourceLabel", JsonPrimitive(plan.sourceLabel))
                                put("title", JsonPrimitive(plan.title))
                                put("sessionType", JsonPrimitive(plan.sessionType))
                                put("effectiveMinutes", JsonPrimitive(plan.effectiveMinutes))
                                put("objective", JsonPrimitive(plan.objective))
                                put("criteriaJson", JsonPrimitive(plan.criteriaJson))
                                put("material", JsonPrimitive(plan.material))
                                put("developmentJson", JsonPrimitive(plan.developmentJson))
                                put("adaptationsJson", JsonPrimitive(plan.adaptationsJson))
                            }.toString(),
                        )
                    }
                }
            }
            container.learningSituationsRepository.listClassLinks(situation.id).forEach { link ->
                val linkUpdatedAt = link.trace.updatedAt.toEpochMilliseconds()
                if (sinceEpochMs == 0L || linkUpdatedAt > sinceEpochMs) {
                    changes += SyncChange(
                        entity = "learning_situation_class_link",
                        id = "${situation.id}-${link.classId}",
                        updatedAtEpochMs = linkUpdatedAt,
                        deviceId = link.trace.deviceId ?: localDeviceId,
                        payload = buildJsonObject {
                            put("learningSituationId", JsonPrimitive(situation.id))
                            put("classId", JsonPrimitive(link.classId))
                        }.toString(),
                    )
                }
            }
            container.learningSituationsRepository.listLinkedResources(situation.id).forEach { link ->
                val linkUpdatedAt = link.trace.updatedAt.toEpochMilliseconds()
                if (sinceEpochMs == 0L || linkUpdatedAt > sinceEpochMs) {
                    changes += SyncChange(
                        entity = "learning_situation_link",
                        id = "${situation.id}-${link.kind.name}-${link.resourceId}",
                        updatedAtEpochMs = linkUpdatedAt,
                        deviceId = link.trace.deviceId ?: localDeviceId,
                        payload = buildJsonObject {
                            put("learningSituationId", JsonPrimitive(situation.id))
                            put("kind", JsonPrimitive(link.kind.name))
                            put("resourceId", JsonPrimitive(link.resourceId))
                            link.classId?.let { put("classId", JsonPrimitive(it)) }
                            put("label", JsonPrimitive(link.label))
                        }.toString(),
                    )
                }
            }
        }

        emitOutgoingDeletes(changes, sinceEpochMs)
        return changes
    }

    private fun syntheticUpdatedAt(scope: String, id: String, signature: String): Long {
        val previousSignature = syncSignatureSnapshotByScope[scope]?.get(id)
        val updatedAtById = syncSyntheticUpdatedAtByScope.getOrPut(scope) { mutableMapOf() }
        return when {
            previousSignature == null -> updatedAtById[id] ?: 0L
            previousSignature != signature -> Clock.System.now().toEpochMilliseconds().also { updatedAtById[id] = it }
            else -> updatedAtById[id] ?: 0L
        }
    }

    private suspend fun appendDeletesByScope(
        scope: String,
        entity: String,
        currentIds: Set<String>,
        payloadBuilder: (String) -> JsonObject,
    ) {
        liveIdsByEntityThisCollect.getOrPut(entity) { mutableSetOf() }.addAll(currentIds)
        val previousIds = syncIdSnapshotByScope[scope]
        if (previousIds != null) {
            val now = Clock.System.now().toEpochMilliseconds()
            val tombstones = outgoingDeletesByEntity.getOrPut(entity) { mutableMapOf() }
            previousIds.subtract(currentIds).forEach { deletedId ->
                val change = SyncChange(
                    entity = entity,
                    id = deletedId,
                    updatedAtEpochMs = now,
                    deviceId = localDeviceId,
                    payload = payloadBuilder(deletedId).toString(),
                    op = "delete",
                )
                tombstones[deletedId] = change
                container.syncTombstoneRepository.recordTombstone(
                    entity = entity,
                    entityId = deletedId,
                    deletedAtEpochMs = now,
                    deviceId = localDeviceId,
                )
            }
        }
        syncIdSnapshotByScope[scope] = currentIds
    }

    private suspend fun seedOutgoingDeletesIfNeeded() {
        if (outgoingDeletesSeeded) return
        val stored = container.syncTombstoneRepository.listTombstones()
        outgoingDeletesSeeded = true
        stored.forEach { row ->
            if (row.deviceId != localDeviceId) return@forEach
            val change = SyncChange(
                entity = row.entity,
                id = row.entityId,
                updatedAtEpochMs = row.deletedAtEpochMs,
                deviceId = localDeviceId,
                payload = payloadForPersistedDelete(row.entity, row.entityId),
                op = "delete",
            )
            outgoingDeletesByEntity.getOrPut(row.entity) { mutableMapOf() }[row.entityId] = change
        }
    }

    private fun emitOutgoingDeletes(changes: MutableList<SyncChange>, sinceEpochMs: Long) {
        outgoingDeletesByEntity.forEach { (entity, byId) ->
            val live = liveIdsByEntityThisCollect[entity] ?: return@forEach
            byId.values.forEach { change ->
                if (change.id !in live && change.updatedAtEpochMs > sinceEpochMs) {
                    changes += change
                }
            }
        }
    }

    private fun payloadForPersistedDelete(entity: String, id: String): String {
        return when (entity) {
            "rubric_bundle" -> buildJsonObject {
                put("rubricId", JsonPrimitive(id.toLongOrNull() ?: 0L))
            }.toString()
            "notebook_group_member" -> {
                val parts = id.split("|")
                buildJsonObject {
                    put("classId", JsonPrimitive(parts.getOrNull(0)?.toLongOrNull() ?: 0L))
                    put("tabId", JsonPrimitive(parts.getOrNull(1).orEmpty()))
                    put("groupId", JsonPrimitive(parts.getOrNull(2)?.toLongOrNull() ?: 0L))
                    put("studentId", JsonPrimitive(parts.getOrNull(3)?.toLongOrNull() ?: 0L))
                }.toString()
            }
            "notebook_tab", "notebook_column" -> buildJsonObject {
                put("id", JsonPrimitive(id))
            }.toString()
            else -> {
                val numericId = id.toLongOrNull()
                buildJsonObject {
                    if (numericId != null) put("id", JsonPrimitive(numericId)) else put("id", JsonPrimitive(id))
                }.toString()
            }
        }
    }

    // ---------------------------------------------------------------------------
    // APPLY INCOMING CHANGES (LWW)
    // ---------------------------------------------------------------------------

    override suspend fun applyIncomingChangesLww(changes: List<SyncChange>): SyncAck {
        var applied = 0
        var conflicts = 0
        var ignored = 0
        var failed = 0

        changes.forEach { change ->
            val payload = runCatching { json.parseToJsonElement(change.payload).jsonObject }.getOrNull()
            if (payload == null) { failed++; return@forEach }

            // Si la operación es delete, delegar a handler de borrado
            if (change.op == "delete") {
                val deleted = applyDelete(change)
                if (deleted) {
                    applied++
                    // Deja un tombstone: si otro dispositivo (offline en el momento del
                    // borrado) empuja más tarde un upsert fechado ANTES de este borrado,
                    // no debe resucitar la entidad (ver applyIncomingChangesLww más abajo).
                    container.syncTombstoneRepository.recordTombstone(
                        entity = change.entity,
                        entityId = change.id,
                        deletedAtEpochMs = change.updatedAtEpochMs,
                        deviceId = change.deviceId,
                    )
                } else {
                    ignored++
                }
                return@forEach
            }

            // Un upsert fechado antes (o igual) que el último borrado conocido de esta
            // misma entidad no debe resucitarla: el borrado es más reciente y gana LWW.
            if (container.syncTombstoneRepository.isDeletedAtOrAfter(change.entity, change.id, change.updatedAtEpochMs)) {
                ignored++
                return@forEach
            }

            runCatching {
                when (change.entity) {
                    "academic_year" -> {
                        val id = payload.long("id") ?: return@forEach
                        val name = payload.string("name") ?: return@forEach
                        val existing = container.academicYearsRepository.listAcademicYears().firstOrNull { it.id == id }
                        val startEpochMs = if (payload.containsKey("startEpochMs")) payload.long("startEpochMs") ?: existing?.startAt?.toEpochMilliseconds() ?: return@forEach else existing?.startAt?.toEpochMilliseconds() ?: return@forEach
                        val endEpochMs = if (payload.containsKey("endEpochMs")) payload.long("endEpochMs") ?: existing?.endAt?.toEpochMilliseconds() ?: return@forEach else existing?.endAt?.toEpochMilliseconds() ?: return@forEach
                        val centerId = if (payload.containsKey("centerId")) payload.long("centerId") ?: existing?.centerId ?: 1L else existing?.centerId ?: 1L
                        val status = if (payload.containsKey("status")) payload.string("status") ?: existing?.status?.name ?: "ACTIVE" else existing?.status?.name ?: "ACTIVE"
                        val isActive = if (payload.containsKey("isActive")) payload.bool("isActive") ?: false else existing?.isActive ?: false
                        container.academicYearsRepository.upsertAcademicYear(
                            id = id,
                            centerId = centerId,
                            name = name,
                            startEpochMs = startEpochMs,
                            endEpochMs = endEpochMs,
                            status = status,
                            isActive = isActive,
                            archivedAtEpochMs = if (payload.containsKey("archivedAtEpochMs")) payload.long("archivedAtEpochMs")?.takeIf { it > 0L } else existing?.archivedAt?.toEpochMilliseconds(),
                            updatedAtEpochMs = change.updatedAtEpochMs,
                            deviceId = change.deviceId,
                            syncVersion = 1,
                        )
                        applied++
                    }

                    "class" -> {
                        val id = payload.long("id")
                        val name = payload.string("name") ?: return@forEach
                        val incomingId = id?.takeIf { it > 0L }
                        val existing = incomingId?.let { classId ->
                            container.classesRepository.listClasses().firstOrNull { it.id == classId }
                        }
                        val course = if (payload.containsKey("course")) payload.int("course") ?: existing?.course ?: return@forEach else existing?.course ?: return@forEach
                        container.classesRepository.saveClass(
                            id = incomingId,
                            name = name,
                            course = course,
                            description = if (payload.containsKey("description")) payload.rawString("description") else existing?.description,
                            centerId = if (payload.containsKey("centerId")) payload.long("centerId")?.takeIf { it > 0L } else existing?.centerId,
                            academicYearId = if (payload.containsKey("academicYearId")) payload.long("academicYearId")?.takeIf { it > 0L } else existing?.academicYearId,
                            stageCycleId = if (payload.containsKey("stageCycleId")) payload.long("stageCycleId")?.takeIf { it > 0L } else existing?.stageCycleId,
                            subjectId = if (payload.containsKey("subjectId")) payload.long("subjectId")?.takeIf { it > 0L } else existing?.subjectId,
                            updatedAtEpochMs = change.updatedAtEpochMs,
                            deviceId = change.deviceId,
                            syncVersion = 1,
                        )
                        applied++
                    }

                    "student" -> {
                        val id = payload.long("id")
                        val firstName = payload.string("firstName") ?: return@forEach
                        val lastName = payload.string("lastName") ?: return@forEach
                        val existing = id?.takeIf { it > 0L }?.let { container.studentsRepository.getStudent(it) }
                        // Si el mensaje no trae un campo, se conserva el que ya había.
                        // Un apellido nuevo no puede borrar el correo, la lesión ni la fecha de nacimiento.
                        container.studentsRepository.upsertStudent(
                            id = id?.takeIf { it > 0L },
                            firstName = firstName,
                            lastName = lastName,
                            email = if (payload.containsKey("email")) payload.rawString("email")?.takeIf { it.isNotBlank() } else existing?.email,
                            photoPath = if (payload.containsKey("photoPath")) payload.rawString("photoPath")?.takeIf { it.isNotBlank() } else existing?.photoPath,
                            isInjured = if (payload.containsKey("isInjured")) payload.bool("isInjured") ?: false else existing?.isInjured ?: false,
                            sex = if (payload.containsKey("sex")) {
                                payload.string("sex")?.let { runCatching { StudentSex.valueOf(it) }.getOrNull() } ?: existing?.sex ?: StudentSex.UNSPECIFIED
                            } else {
                                existing?.sex ?: StudentSex.UNSPECIFIED
                            },
                            sexSource = if (payload.containsKey("sexSource")) {
                                payload.string("sexSource")?.let { runCatching { StudentSexSource.valueOf(it) }.getOrNull() } ?: existing?.sexSource ?: StudentSexSource.UNKNOWN
                            } else {
                                existing?.sexSource ?: StudentSexSource.UNKNOWN
                            },
                            birthDate = if (payload.containsKey("birthDate")) {
                                payload.string("birthDate")?.let { runCatching { kotlinx.datetime.LocalDate.parse(it) }.getOrNull() }
                            } else {
                                existing?.birthDate
                            },
                            updatedAtEpochMs = change.updatedAtEpochMs,
                            deviceId = change.deviceId,
                            syncVersion = 1,
                        )
                        applied++
                    }

                    "student_deleted" -> {
                        payload.long("id")?.let {
                            container.studentsRepository.deleteStudent(it)
                            applied++
                        }
                    }

                    "class_roster" -> {
                        val classId = payload.long("classId") ?: return@forEach
                        val remoteIds = payload.longList("studentIds").toSet()
                        val localIds = container.classesRepository.listStudentsInClass(classId).map { it.id }.toSet()
                        remoteIds.subtract(localIds).forEach {
                            // Añadir siempre es seguro: en el peor caso, un snapshot viejo
                            // re-añade a alguien que ya se había quitado en el otro
                            // dispositivo; ese dispositivo lo volverá a quitar en su
                            // próximo snapshot. La mitad peligrosa es la baja (abajo).
                            container.classesRepository.addStudentToClass(classId, it)
                            applied++
                        }
                        localIds.subtract(remoteIds).forEach { studentId ->
                            // Solo dar de baja si este snapshot es al menos tan reciente
                            // como la última alta/baja conocida localmente para ESTE
                            // alumno. Sin esto, un snapshot de roster desactualizado que
                            // llega tarde (p.ej. tras una reconexión) puede borrar a un
                            // alumno recién añadido localmente, aunque el snapshot entero
                            // sea "más nuevo" que la última vez que se sincronizó la clase.
                            val localEnrollmentAt = container.classesRepository.latestEnrollmentUpdatedAt(classId, studentId)
                            if (localEnrollmentAt == null || change.updatedAtEpochMs >= localEnrollmentAt) {
                                container.classesRepository.removeStudentFromClass(classId, studentId)
                                applied++
                            } else {
                                ignored++
                            }
                        }
                    }

                    "evaluation" -> {
                        val id = payload.long("id")
                        val classId = payload.long("classId") ?: return@forEach
                        val code = payload.string("code") ?: return@forEach
                        val name = payload.string("name") ?: return@forEach
                        val type = payload.string("type") ?: return@forEach
                        val incomingId = id?.takeIf { it > 0L }
                        val existing = incomingId?.let { evalId ->
                            container.evaluationsRepository.listClassEvaluations(classId).firstOrNull { it.id == evalId }
                        }
                        container.evaluationsRepository.saveEvaluation(
                            id = incomingId,
                            classId = classId,
                            code = code,
                            name = name,
                            type = type,
                            weight = if (payload.containsKey("weight")) payload.double("weight") ?: existing?.weight ?: 1.0 else existing?.weight ?: 1.0,
                            formula = if (payload.containsKey("formula")) payload.rawString("formula")?.takeIf { it.isNotBlank() } else existing?.formula,
                            rubricId = if (payload.containsKey("rubricId")) payload.long("rubricId")?.takeIf { it > 0L } else existing?.rubricId,
                            description = if (payload.containsKey("description")) payload.rawString("description") else existing?.description,
                            updatedAtEpochMs = change.updatedAtEpochMs,
                            deviceId = change.deviceId,
                            syncVersion = 1,
                        )
                        applied++
                    }

                    "grade" -> {
                        val classId = payload.long("classId") ?: return@forEach
                        val studentId = payload.long("studentId") ?: return@forEach
                        val columnId = payload.string("columnId")
                            ?: payload.long("evaluationId")?.let { "eval_$it" }
                            ?: "eval_0"
                        val evaluationId = payload.long("evaluationId")?.takeIf { it > 0L }
                        val existingGrade = container.database.appDatabaseQueries
                            .selectGradeByStudentClassAndColumn(classId, studentId, columnId)
                            .executeAsOneOrNull()
                        val value = if (payload.containsKey("value")) payload.double("value") else existingGrade?.value_
                        container.gradesRepository.upsertGrade(
                            classId = classId,
                            studentId = studentId,
                            columnId = columnId,
                            evaluationId = evaluationId,
                            value = value,
                            evidence = payload.string("evidence"),
                            evidencePath = payload.string("evidencePath"),
                            rubricSelections = payload.string("rubricSelections"),
                            updatedAtEpochMs = change.updatedAtEpochMs,
                            deviceId = change.deviceId,
                            syncVersion = 1,
                        )
                        applied++
                    }

                    "weekly_slot" -> {
                        val classId = payload.long("schoolClassId") ?: payload.long("classId") ?: return@forEach
                        val dayOfWeek = payload.int("dayOfWeek") ?: return@forEach
                        val startTime = payload.string("startTime") ?: return@forEach
                        val endTime = payload.string("endTime") ?: return@forEach
                        val id = payload.long("id")
                        container.weeklyTemplateRepository.insert(
                            WeeklySlotTemplate(
                                id = id ?: 0L,
                                schoolClassId = classId,
                                dayOfWeek = dayOfWeek,
                                startTime = startTime,
                                endTime = endTime,
                            ),
                        )
                        applied++
                    }

                    "notebook_tab" -> {
                        val classId = payload.long("classId") ?: return@forEach
                        val tabId = payload.string("id") ?: return@forEach
                        val title = payload.string("title") ?: return@forEach
                        val existing = container.notebookConfigRepository.listTabs(classId).firstOrNull { it.id == tabId }
                        val parentTabId = if (payload.containsKey("parentTabId")) payload.string("parentTabId") else existing?.parentTabId
                        val description = if (payload.containsKey("description")) payload.string("description") else existing?.description
                        container.notebookConfigRepository.saveTab(
                            classId = classId,
                            tab = NotebookTab(
                                id = tabId,
                                title = title,
                                description = description,
                                order = if (payload.containsKey("order")) payload.int("order") ?: existing?.order ?: 0 else existing?.order ?: -1,
                                parentTabId = parentTabId,
                                fixedColumnWidth = if (payload.containsKey("fixedColumnWidth")) payload.double("fixedColumnWidth") else existing?.fixedColumnWidth,
                                trace = AuditTrace(
                                    updatedAt = Instant.fromEpochMilliseconds(change.updatedAtEpochMs),
                                    deviceId = change.deviceId,
                                    syncVersion = 1,
                                ),
                            ),
                        )
                        applied++
                    }

                    "notebook_group" -> {
                        val classId = payload.long("classId") ?: payload.long("class_id") ?: return@forEach
                        val groupId = (payload.long("id") ?: payload.long("group_id"))?.takeIf { it > 0L } ?: return@forEach
                        val tabId = payload.string("tabId") ?: payload.string("tab_id") ?: return@forEach
                        val name = payload.string("name") ?: return@forEach
                        val existing = container.notebookRepository.listWorkGroups(classId).firstOrNull { it.id == groupId }
                        container.notebookRepository.saveWorkGroup(
                            classId = classId,
                            workGroup = com.migestor.shared.domain.NotebookWorkGroup(
                                id = groupId,
                                classId = classId,
                                tabId = if (payload.containsKey("tabId") || payload.containsKey("tab_id")) tabId else existing?.tabId ?: tabId,
                                name = name,
                                order = if (payload.containsKey("order")) payload.int("order") ?: existing?.order ?: 0 else existing?.order ?: 0,
                                learningSituationId = if (payload.containsKey("learningSituationId")) payload.long("learningSituationId") else existing?.learningSituationId,
                                trace = com.migestor.shared.domain.AuditTrace(
                                    updatedAt = Instant.fromEpochMilliseconds(change.updatedAtEpochMs),
                                    deviceId = change.deviceId,
                                    syncVersion = 1,
                                ),
                            ),
                        )
                        applied++
                    }

                    "notebook_group_member" -> {
                        val classId = payload.long("classId") ?: payload.long("class_id") ?: return@forEach
                        val tabId = payload.string("tabId") ?: payload.string("tab_id") ?: return@forEach
                        val groupId = payload.long("groupId") ?: payload.long("group_id") ?: return@forEach
                        val studentId = payload.long("studentId") ?: payload.long("student_id") ?: return@forEach
                        container.notebookConfigRepository.assignStudentsToWorkGroup(
                            classId = classId,
                            tabId = tabId,
                            groupId = groupId,
                            studentIds = listOf(studentId),
                        )
                        applied++
                    }

                    "notebook_column" -> {
                        val classId = payload.long("classId") ?: return@forEach
                        val columnId = payload.string("id") ?: return@forEach
                        val title = payload.string("title") ?: return@forEach
                        val existing = container.notebookConfigRepository.listColumns(classId).firstOrNull { it.id == columnId }
                        val type = if (payload.containsKey("type") || payload.containsKey("column_type")) {
                            (payload.string("type") ?: payload.string("column_type"))
                                ?.let { runCatching { NotebookColumnType.valueOf(it) }.getOrNull() }
                                ?: existing?.type
                                ?: NotebookColumnType.NUMERIC
                        } else {
                            existing?.type ?: NotebookColumnType.NUMERIC
                        }
                        val tabIdsCsv = payload.string("tabIdsCsv") ?: payload.string("tab_ids_csv")
                        
                        val categoryKind = if (payload.containsKey("categoryKind")) {
                            payload.string("categoryKind")?.let { runCatching { NotebookColumnCategoryKind.valueOf(it) }.getOrNull() }
                                ?: existing?.categoryKind ?: NotebookColumnCategoryKind.CUSTOM
                        } else existing?.categoryKind ?: NotebookColumnCategoryKind.CUSTOM
                        val instrumentKind = if (payload.containsKey("instrumentKind")) {
                            payload.string("instrumentKind")?.let { runCatching { NotebookInstrumentKind.valueOf(it) }.getOrNull() }
                                ?: existing?.instrumentKind ?: NotebookInstrumentKind.CUSTOM
                        } else existing?.instrumentKind ?: NotebookInstrumentKind.CUSTOM
                        val inputKind = if (payload.containsKey("inputKind")) {
                            payload.string("inputKind")?.let { runCatching { NotebookCellInputKind.valueOf(it) }.getOrNull() }
                                ?: existing?.inputKind ?: NotebookCellInputKind.TEXT
                        } else existing?.inputKind ?: NotebookCellInputKind.TEXT
                        val scaleKind = if (payload.containsKey("scaleKind")) {
                            payload.string("scaleKind")?.let { runCatching { NotebookScaleKind.valueOf(it) }.getOrNull() }
                                ?: existing?.scaleKind ?: NotebookScaleKind.CUSTOM
                        } else existing?.scaleKind ?: NotebookScaleKind.CUSTOM
                        val visibility = if (payload.containsKey("visibility")) {
                            payload.string("visibility")?.let { runCatching { NotebookColumnVisibility.valueOf(it) }.getOrNull() }
                                ?: existing?.visibility ?: NotebookColumnVisibility.VISIBLE
                        } else existing?.visibility ?: NotebookColumnVisibility.VISIBLE

                        val competencyCriteriaIds = if (payload.containsKey("competencyCriteriaIds")) {
                            payload.string("competencyCriteriaIds")
                                ?.split(",")
                                ?.mapNotNull { it.trim().toLongOrNull() }
                                ?: existing?.competencyCriteriaIds
                                ?: emptyList()
                        } else existing?.competencyCriteriaIds ?: emptyList()

                        container.notebookConfigRepository.saveColumn(
                            classId = classId,
                            column = NotebookColumnDefinition(
                                id = columnId,
                                title = title,
                                type = type,
                                categoryKind = categoryKind,
                                instrumentKind = instrumentKind,
                                inputKind = inputKind,
                                evaluationId = if (payload.containsKey("evaluationId")) payload.long("evaluationId")?.takeIf { it > 0L } else existing?.evaluationId,
                                rubricId = if (payload.containsKey("rubricId")) payload.long("rubricId")?.takeIf { it > 0L } else existing?.rubricId,
                                formula = if (payload.containsKey("formula")) payload.rawString("formula") else existing?.formula,
                                weight = if (payload.containsKey("weight")) payload.double("weight") ?: existing?.weight ?: 1.0 else existing?.weight ?: 1.0,
                                dateEpochMs = if (payload.containsKey("dateEpochMs")) payload.long("dateEpochMs")?.takeIf { it > 0L } else existing?.dateEpochMs,
                                unitOrSituation = if (payload.containsKey("unitOrSituation")) payload.string("unitOrSituation") else existing?.unitOrSituation,
                                competencyCriteriaIds = competencyCriteriaIds,
                                scaleKind = scaleKind,
                                tabIds = if (payload.containsKey("tabIdsCsv") || payload.containsKey("tab_ids_csv")) {
                                    tabIdsCsv?.split(",")?.map { it.trim() }?.filter { it.isNotBlank() } ?: existing?.tabIds ?: emptyList()
                                } else existing?.tabIds ?: emptyList(),
                                sharedAcrossTabs = if (payload.containsKey("sharedAcrossTabs") || payload.containsKey("shared_across_tabs")) {
                                    payload.bool("sharedAcrossTabs") ?: payload.bool("shared_across_tabs") ?: existing?.sharedAcrossTabs ?: false
                                } else existing?.sharedAcrossTabs ?: false,
                                colorHex = if (payload.containsKey("colorHex")) payload.string("colorHex") else existing?.colorHex,
                                iconName = if (payload.containsKey("iconName")) payload.string("iconName") else existing?.iconName,
                                order = if (payload.containsKey("order")) payload.int("order") ?: existing?.order ?: -1 else existing?.order ?: -1,
                                widthDp = if (payload.containsKey("widthDp")) payload.double("widthDp") ?: existing?.widthDp ?: 0.0 else existing?.widthDp ?: 0.0,
                                categoryId = if (payload.containsKey("categoryId")) payload.string("categoryId") else existing?.categoryId,
                                countsTowardAverage = if (payload.containsKey("countsTowardAverage")) payload.bool("countsTowardAverage") ?: existing?.countsTowardAverage ?: true else existing?.countsTowardAverage ?: true,
                                isPinned = if (payload.containsKey("isPinned")) payload.bool("isPinned") ?: false else existing?.isPinned ?: false,
                                isHidden = if (payload.containsKey("isHidden")) payload.bool("isHidden") ?: false else existing?.isHidden ?: false,
                                visibility = visibility,
                                isLocked = if (payload.containsKey("isLocked")) payload.bool("isLocked") ?: false else existing?.isLocked ?: false,
                                isTemplate = if (payload.containsKey("isTemplate")) payload.bool("isTemplate") ?: false else existing?.isTemplate ?: false,
                                trace = AuditTrace(
                                    updatedAt = Instant.fromEpochMilliseconds(change.updatedAtEpochMs),
                                    deviceId = change.deviceId,
                                    syncVersion = 1,
                                ),
                            ),
                        )
                        applied++
                    }

                    "notebook_cell" -> {
                        val classId = payload.long("classId") ?: return@forEach
                        val studentId = payload.long("studentId") ?: return@forEach
                        val columnId = payload.string("columnId") ?: return@forEach
                        container.notebookCellsRepository.saveCell(
                            classId = classId,
                            studentId = studentId,
                            columnId = columnId,
                            textValue = payload.string("textValue"),
                            boolValue = payload.bool("boolValue"),
                            iconValue = payload.string("iconValue"),
                            ordinalValue = payload.string("ordinalValue"),
                            note = payload.string("note"),
                            colorHex = payload.string("colorHex"),
                            attachmentUris = payload.array("attachmentUris")
                                .mapNotNull { it.jsonPrimitive.contentOrNull }
                                .filter { it.isNotBlank() },
                            updatedAtEpochMs = change.updatedAtEpochMs,
                            deviceId = change.deviceId,
                            syncVersion = 1,
                        )
                        applied++
                    }

                    "notebook_instrument_template" -> {
                        val id = payload.string("id") ?: return@forEach
                        val classId = payload.long("classId") ?: return@forEach
                        val columnId = payload.string("columnId") ?: return@forEach
                        val title = payload.string("title") ?: return@forEach
                        val existing = container.database.appDatabaseQueries
                            .selectInstrumentTemplateByColumn(columnId)
                            .executeAsOneOrNull()
                            ?.takeIf { it.id == id }
                        val kind = if (payload.containsKey("kind")) payload.string("kind") ?: existing?.kind ?: "observation" else existing?.kind ?: "observation"
                        val inputKind = if (payload.containsKey("inputKind")) payload.string("inputKind") ?: existing?.input_kind ?: "structuredObservation" else existing?.input_kind ?: "structuredObservation"
                        val source = if (payload.containsKey("source")) payload.string("source") else existing?.source
                        val evaluationId = if (payload.containsKey("evaluationId")) payload.long("evaluationId")?.takeIf { it > 0L } else existing?.evaluation_id
                        val createdAt = if (payload.containsKey("createdAtEpochMs")) payload.long("createdAtEpochMs") ?: change.updatedAtEpochMs else existing?.created_at_epoch_ms ?: change.updatedAtEpochMs

                        container.database.appDatabaseQueries.upsertInstrumentTemplate(
                            id = id,
                            class_id = classId,
                            column_id = columnId,
                            evaluation_id = evaluationId,
                            title = title,
                            kind = kind,
                            input_kind = inputKind,
                            source = source,
                            created_at_epoch_ms = createdAt,
                            updated_at_epoch_ms = change.updatedAtEpochMs,
                            device_id = change.deviceId,
                            sync_version = 1,
                        )
                        applied++
                    }

                    "notebook_instrument_item" -> {
                        val id = payload.string("id") ?: return@forEach
                        val templateId = payload.string("templateId") ?: return@forEach
                        val itemKey = payload.string("itemKey") ?: return@forEach
                        val title = payload.string("title") ?: return@forEach
                        val existing = container.database.appDatabaseQueries
                            .selectInstrumentItemsByTemplate(templateId)
                            .executeAsList()
                            .firstOrNull { it.id == id }
                        val itemType = if (payload.containsKey("itemType")) payload.string("itemType") ?: existing?.item_type ?: "scale14" else existing?.item_type ?: "scale14"
                        val optionsCsv = if (payload.containsKey("optionsCsv")) payload.string("optionsCsv").orEmpty() else existing?.options_csv.orEmpty()
                        val required = if (payload.containsKey("required")) payload.bool("required") ?: (existing?.required == 1L) else existing?.required != 0L
                        val sortOrder = if (payload.containsKey("sortOrder")) payload.long("sortOrder") ?: existing?.sort_order ?: 0L else existing?.sort_order ?: 0L
                        val helpText = if (payload.containsKey("helpText")) payload.string("helpText") else existing?.help_text

                        container.database.appDatabaseQueries.upsertInstrumentItem(
                            id = id,
                            template_id = templateId,
                            item_key = itemKey,
                            title = title,
                            item_type = itemType,
                            options_csv = optionsCsv,
                            required = if (required) 1L else 0L,
                            sort_order = sortOrder,
                            help_text = helpText,
                            updated_at_epoch_ms = change.updatedAtEpochMs,
                            device_id = change.deviceId,
                            sync_version = 1,
                        )
                        applied++
                    }

                    "notebook_instrument_response" -> {
                        val classId = payload.long("classId") ?: return@forEach
                        val studentId = payload.long("studentId") ?: return@forEach
                        val columnId = payload.string("columnId") ?: return@forEach
                        val itemId = payload.string("itemId") ?: return@forEach
                        val existing = container.database.appDatabaseQueries
                            .selectInstrumentResponsesForCell(classId, studentId, columnId)
                            .executeAsList()
                            .firstOrNull { it.item_id == itemId }
                        val valueText = if (payload.containsKey("valueText")) payload.rawString("valueText") else existing?.value_text
                        val valueBool = if (payload.containsKey("valueBool")) payload.bool("valueBool")?.let { if (it) 1L else 0L } else existing?.value_bool
                        val valueNumber = if (payload.containsKey("valueNumber")) payload.string("valueNumber")?.toDoubleOrNull() else existing?.value_number

                        container.database.appDatabaseQueries.upsertInstrumentResponse(
                            class_id = classId,
                            student_id = studentId,
                            column_id = columnId,
                            item_id = itemId,
                            value_text = valueText,
                            value_bool = valueBool,
                            value_number = valueNumber,
                            updated_at_epoch_ms = change.updatedAtEpochMs,
                            device_id = change.deviceId,
                            sync_version = 1,
                        )
                        applied++
                    }

                    // ── Nuevas entidades ──────────────────────────────────────

                    "attendance" -> {
                        val studentId = payload.long("studentId") ?: return@forEach
                        val classId = payload.long("classId") ?: return@forEach
                        val dateEpochMs = payload.long("dateEpochMs") ?: return@forEach
                        val status = payload.string("status") ?: return@forEach
                        val existing = container.attendanceRepository.listAttendanceByDate(classId, dateEpochMs)
                            .firstOrNull { it.studentId == studentId }
                        container.attendanceRepository.saveAttendance(
                            id = payload.long("id")?.takeIf { it > 0L } ?: existing?.id,
                            studentId = studentId,
                            classId = classId,
                            dateEpochMs = dateEpochMs,
                            status = status,
                            note = if (payload.containsKey("note")) payload.rawString("note").orEmpty() else existing?.note.orEmpty(),
                            hasIncident = if (payload.containsKey("hasIncident")) payload.bool("hasIncident") ?: false else existing?.hasIncident ?: false,
                            followUpRequired = if (payload.containsKey("followUpRequired")) payload.bool("followUpRequired") ?: false else existing?.followUpRequired ?: false,
                            sessionId = if (payload.containsKey("sessionId")) payload.long("sessionId")?.takeIf { it > 0L } else existing?.sessionId,
                            updatedAtEpochMs = change.updatedAtEpochMs,
                            deviceId = change.deviceId,
                            syncVersion = 1,
                        )
                        applied++
                    }

                    "incident" -> {
                        val classId = payload.long("classId") ?: return@forEach
                        val title = payload.string("title") ?: return@forEach
                        val dateEpochMs = payload.long("dateEpochMs") ?: return@forEach
                        val incomingId = payload.long("id")?.takeIf { it > 0L }
                        val existing = incomingId?.let { id ->
                            container.incidentsRepository.listIncidents(classId).firstOrNull { it.id == id }
                        }
                        container.incidentsRepository.saveIncident(
                            id = incomingId,
                            classId = classId,
                            studentId = if (payload.containsKey("studentId")) payload.long("studentId")?.takeIf { it > 0L } else existing?.studentId,
                            title = title,
                            detail = if (payload.containsKey("detail")) payload.rawString("detail") else existing?.detail,
                            severity = if (payload.containsKey("severity")) payload.string("severity") ?: existing?.severity ?: "low" else existing?.severity ?: "low",
                            dateEpochMs = dateEpochMs,
                            updatedAtEpochMs = change.updatedAtEpochMs,
                            deviceId = change.deviceId,
                            syncVersion = 1,
                        )
                        applied++
                    }

                    "calendar_event" -> {
                        val title = payload.string("title") ?: return@forEach
                        val startEpochMs = payload.long("startEpochMs") ?: return@forEach
                        val endEpochMs = payload.long("endEpochMs") ?: return@forEach
                        val incomingId = payload.long("id")?.takeIf { it > 0L }
                        val existing = incomingId?.let { eventId ->
                            container.calendarRepository.listEvents(null).firstOrNull { it.id == eventId }
                        }
                        container.calendarRepository.saveEvent(
                            id = incomingId,
                            classId = if (payload.containsKey("classId")) payload.long("classId")?.takeIf { it > 0L } else existing?.classId,
                            title = title,
                            description = if (payload.containsKey("description")) payload.rawString("description") else existing?.description,
                            startEpochMs = startEpochMs,
                            endEpochMs = endEpochMs,
                            externalProvider = if (payload.containsKey("externalProvider")) payload.string("externalProvider") else existing?.externalProvider,
                            externalId = if (payload.containsKey("externalId")) payload.string("externalId") else existing?.externalId,
                            updatedAtEpochMs = change.updatedAtEpochMs,
                            deviceId = change.deviceId,
                            syncVersion = 1,
                        )
                        applied++
                    }

                    "rubric_assessment" -> {
                        val studentId = payload.long("studentId") ?: return@forEach
                        val evaluationId = payload.long("evaluationId") ?: return@forEach
                        val criterionId = payload.long("criterionId") ?: return@forEach
                        val levelId = payload.long("levelId") ?: return@forEach
                        container.rubricsRepository.saveRubricAssessment(
                            studentId = studentId,
                            evaluationId = evaluationId,
                            criterionId = criterionId,
                            levelId = levelId,
                            updatedAtEpochMs = change.updatedAtEpochMs,
                            deviceId = change.deviceId,
                            syncVersion = 1,
                        )
                        applied++
                    }

                    "teaching_unit" -> {
                        val name = payload.string("name") ?: return@forEach
                        val incomingId = payload.long("id") ?: 0L
                        val existing = incomingId.takeIf { it > 0L }?.let { unitId ->
                            container.plannerRepository.listAllTeachingUnits().firstOrNull { it.id == unitId }
                        }
                        container.plannerRepository.upsertTeachingUnit(
                            TeachingUnit(
                                id = incomingId,
                                name = name,
                                description = if (payload.containsKey("description")) payload.rawString("description").orEmpty() else existing?.description.orEmpty(),
                                colorHex = if (payload.containsKey("colorHex")) payload.string("colorHex") ?: existing?.colorHex ?: "#4A90D9" else existing?.colorHex ?: "#4A90D9",
                                groupId = if (payload.containsKey("groupId")) payload.long("groupId")?.takeIf { it > 0L } else existing?.groupId,
                                schoolClassId = if (payload.containsKey("schoolClassId")) payload.long("schoolClassId")?.takeIf { it > 0L } else existing?.schoolClassId,
                                startDate = if (payload.containsKey("startDate")) {
                                    payload.string("startDate")?.let { runCatching { kotlinx.datetime.LocalDate.parse(it) }.getOrNull() }
                                } else existing?.startDate,
                                endDate = if (payload.containsKey("endDate")) {
                                    payload.string("endDate")?.let { runCatching { kotlinx.datetime.LocalDate.parse(it) }.getOrNull() }
                                } else existing?.endDate,
                            ),
                        )
                        applied++
                    }

                    "learning_situation" -> {
                        val title = payload.string("title") ?: return@forEach
                        val updatedAt = Instant.fromEpochMilliseconds(change.updatedAtEpochMs)
                        val incomingId = payload.long("id") ?: 0L
                        val existing = incomingId.takeIf { it > 0L }?.let { container.learningSituationsRepository.getSituation(it) }
                        container.learningSituationsRepository.saveSituation(
                            LearningSituation(
                                id = incomingId,
                                title = title,
                                stageLabel = if (payload.containsKey("stageLabel")) payload.string("stageLabel").orEmpty() else existing?.stageLabel.orEmpty(),
                                courseLabel = if (payload.containsKey("courseLabel")) payload.string("courseLabel").orEmpty() else existing?.courseLabel.orEmpty(),
                                subjectLabel = if (payload.containsKey("subjectLabel")) payload.string("subjectLabel").orEmpty() else existing?.subjectLabel.orEmpty(),
                                termLabel = if (payload.containsKey("termLabel")) payload.string("termLabel").orEmpty() else existing?.termLabel.orEmpty(),
                                centerLabel = if (payload.containsKey("centerLabel")) payload.string("centerLabel").orEmpty() else existing?.centerLabel.orEmpty(),
                                sessionCount = if (payload.containsKey("sessionCount")) payload.int("sessionCount") ?: existing?.sessionCount ?: 0 else existing?.sessionCount ?: 0,
                                challenge = if (payload.containsKey("challenge")) payload.string("challenge").orEmpty() else existing?.challenge.orEmpty(),
                                finalProduct = if (payload.containsKey("finalProduct")) payload.string("finalProduct").orEmpty() else existing?.finalProduct.orEmpty(),
                                payloadJson = if (payload.containsKey("payloadJson")) payload.rawString("payloadJson") ?: existing?.payloadJson ?: "{}" else existing?.payloadJson ?: "{}",
                                status = if (payload.containsKey("status")) {
                                    runCatching { LearningSituationStatus.valueOf(payload.string("status") ?: "") }
                                        .getOrDefault(existing?.status ?: LearningSituationStatus.ACTIVE)
                                } else existing?.status ?: LearningSituationStatus.ACTIVE,
                                trace = AuditTrace(
                                    createdAt = updatedAt,
                                    updatedAt = updatedAt,
                                    deviceId = change.deviceId,
                                    syncVersion = 1,
                                ),
                            ),
                        )
                        applied++
                    }

                    "learning_situation_version" -> {
                        val situationId = payload.long("learningSituationId") ?: return@forEach
                        val sha256 = payload.string("sha256") ?: return@forEach
                        val updatedAt = Instant.fromEpochMilliseconds(change.updatedAtEpochMs)
                        val incomingId = payload.long("id")?.takeIf { it > 0L }
                        val existing = container.learningSituationsRepository.listVersions(situationId)
                            .firstOrNull { it.id == incomingId || it.sha256 == sha256 }
                        container.learningSituationsRepository.saveVersion(
                            LearningSituationVersion(
                                id = incomingId ?: existing?.id ?: 0L,
                                learningSituationId = situationId,
                                versionNumber = if (payload.containsKey("versionNumber")) payload.int("versionNumber") ?: existing?.versionNumber ?: 1 else existing?.versionNumber ?: 1,
                                originalFileName = if (payload.containsKey("originalFileName")) payload.string("originalFileName") ?: existing?.originalFileName ?: "$sha256.docx" else existing?.originalFileName ?: "$sha256.docx",
                                sha256 = sha256,
                                localPath = existing?.localPath,
                                sizeBytes = if (payload.containsKey("sizeBytes")) payload.long("sizeBytes") ?: existing?.sizeBytes ?: 0L else existing?.sizeBytes ?: 0L,
                                payloadJson = if (payload.containsKey("payloadJson")) payload.rawString("payloadJson") ?: existing?.payloadJson ?: "{}" else existing?.payloadJson ?: "{}",
                                warningsJson = if (payload.containsKey("warningsJson")) payload.rawString("warningsJson") ?: existing?.warningsJson ?: "[]" else existing?.warningsJson ?: "[]",
                                trace = AuditTrace(
                                    createdAt = updatedAt,
                                    updatedAt = updatedAt,
                                    deviceId = change.deviceId,
                                    syncVersion = 1,
                                ),
                            ),
                        )
                        applied++
                    }

                    "learning_situation_sequence_version" -> {
                        val situationId = payload.long("learningSituationId") ?: return@forEach
                        val sha256 = payload.string("sha256") ?: return@forEach
                        val updatedAt = Instant.fromEpochMilliseconds(change.updatedAtEpochMs)
                        val incomingId = payload.long("id")?.takeIf { it > 0L }
                        val existing = container.learningSituationsRepository.listSessionSequenceVersions(situationId)
                            .firstOrNull { it.id == incomingId || it.sha256 == sha256 }
                        container.learningSituationsRepository.saveSessionSequenceVersion(
                            LearningSituationSessionSequenceVersion(
                                id = incomingId ?: existing?.id ?: 0L,
                                learningSituationId = situationId,
                                versionNumber = if (payload.containsKey("versionNumber")) payload.int("versionNumber") ?: existing?.versionNumber ?: 1 else existing?.versionNumber ?: 1,
                                originalFileName = if (payload.containsKey("originalFileName")) payload.string("originalFileName") ?: existing?.originalFileName ?: "$sha256.docx" else existing?.originalFileName ?: "$sha256.docx",
                                sha256 = sha256,
                                localPath = existing?.localPath,
                                sizeBytes = if (payload.containsKey("sizeBytes")) payload.long("sizeBytes") ?: existing?.sizeBytes ?: 0L else existing?.sizeBytes ?: 0L,
                                payloadJson = if (payload.containsKey("payloadJson")) payload.rawString("payloadJson") ?: existing?.payloadJson ?: "{}" else existing?.payloadJson ?: "{}",
                                warningsJson = if (payload.containsKey("warningsJson")) payload.rawString("warningsJson") ?: existing?.warningsJson ?: "[]" else existing?.warningsJson ?: "[]",
                                trace = AuditTrace(createdAt = updatedAt, updatedAt = updatedAt, deviceId = change.deviceId, syncVersion = 1),
                            ),
                        )
                        applied++
                    }

                    "learning_situation_session_plan" -> {
                        val situationId = payload.long("learningSituationId") ?: return@forEach
                        val versionId = payload.long("sequenceVersionId") ?: return@forEach
                        val title = payload.string("title") ?: return@forEach
                        val updatedAt = Instant.fromEpochMilliseconds(change.updatedAtEpochMs)
                        val incomingId = payload.long("id") ?: 0L
                        val existing = incomingId.takeIf { it > 0L }?.let { container.learningSituationsRepository.getSessionPlan(it) }
                        container.learningSituationsRepository.saveSessionPlan(
                            LearningSituationSessionPlan(
                                id = incomingId,
                                learningSituationId = situationId,
                                sequenceVersionId = versionId,
                                sessionNumber = if (payload.containsKey("sessionNumber")) payload.int("sessionNumber") ?: existing?.sessionNumber ?: 0 else existing?.sessionNumber ?: 0,
                                sourceLabel = if (payload.containsKey("sourceLabel")) payload.string("sourceLabel").orEmpty() else existing?.sourceLabel.orEmpty(),
                                title = title,
                                sessionType = if (payload.containsKey("sessionType")) payload.string("sessionType").orEmpty() else existing?.sessionType.orEmpty(),
                                effectiveMinutes = if (payload.containsKey("effectiveMinutes")) payload.int("effectiveMinutes") ?: existing?.effectiveMinutes ?: 0 else existing?.effectiveMinutes ?: 0,
                                objective = if (payload.containsKey("objective")) payload.string("objective").orEmpty() else existing?.objective.orEmpty(),
                                criteriaJson = if (payload.containsKey("criteriaJson")) payload.rawString("criteriaJson") ?: existing?.criteriaJson ?: "[]" else existing?.criteriaJson ?: "[]",
                                material = if (payload.containsKey("material")) payload.string("material").orEmpty() else existing?.material.orEmpty(),
                                developmentJson = if (payload.containsKey("developmentJson")) payload.rawString("developmentJson") ?: existing?.developmentJson ?: "[]" else existing?.developmentJson ?: "[]",
                                adaptationsJson = if (payload.containsKey("adaptationsJson")) payload.rawString("adaptationsJson") ?: existing?.adaptationsJson ?: "[]" else existing?.adaptationsJson ?: "[]",
                                trace = AuditTrace(createdAt = updatedAt, updatedAt = updatedAt, deviceId = change.deviceId, syncVersion = 1),
                            ),
                        )
                        applied++
                    }

                    "learning_situation_class_link" -> {
                        val situationId = payload.long("learningSituationId") ?: return@forEach
                        val classId = payload.long("classId") ?: return@forEach
                        val existing = container.learningSituationsRepository.listClassLinks(situationId)
                            .map { it.classId }
                        container.learningSituationsRepository.replaceClassLinks(situationId, (existing + classId).distinct())
                        applied++
                    }

                    "learning_situation_link" -> {
                        val situationId = payload.long("learningSituationId") ?: return@forEach
                        val resourceId = payload.string("resourceId") ?: return@forEach
                        val updatedAt = Instant.fromEpochMilliseconds(change.updatedAtEpochMs)
                        val existing = container.learningSituationsRepository.listLinkedResources(situationId)
                            .firstOrNull { it.resourceId == resourceId }
                        container.learningSituationsRepository.saveLinkedResource(
                            LearningSituationLinkedResource(
                                learningSituationId = situationId,
                                kind = if (payload.containsKey("kind")) {
                                    runCatching {
                                        LearningSituationResourceKind.valueOf(payload.string("kind") ?: "")
                                    }.getOrDefault(existing?.kind ?: LearningSituationResourceKind.TEACHING_UNIT)
                                } else {
                                    existing?.kind ?: LearningSituationResourceKind.TEACHING_UNIT
                                },
                                resourceId = resourceId,
                                classId = if (payload.containsKey("classId")) payload.long("classId") else existing?.classId,
                                label = if (payload.containsKey("label")) payload.string("label").orEmpty() else existing?.label.orEmpty(),
                                trace = AuditTrace(
                                    createdAt = updatedAt,
                                    updatedAt = updatedAt,
                                    deviceId = change.deviceId,
                                    syncVersion = 1,
                                ),
                            ),
                        )
                        applied++
                    }

                    "planning_session" -> {
                        val sessionId = payload.long("id") ?: 0L
                        val existing = sessionId.takeIf { it > 0L }?.let { id ->
                            container.plannerRepository.listAllSessions().firstOrNull { it.id == id }
                        }
                        val session = PlanningSession(
                            id = sessionId,
                            teachingUnitId = payload.long("teachingUnitId") ?: existing?.teachingUnitId ?: 0L,
                            teachingUnitName = payload.string("teachingUnitName") ?: existing?.teachingUnitName ?: "Unidad",
                            teachingUnitColor = payload.string("teachingUnitColor") ?: existing?.teachingUnitColor ?: "#4A90D9",
                            groupId = payload.long("groupId") ?: existing?.groupId ?: 0L,
                            groupName = payload.string("groupName") ?: existing?.groupName ?: "",
                            dayOfWeek = payload.int("dayOfWeek") ?: existing?.dayOfWeek ?: 1,
                            period = payload.int("period") ?: existing?.period ?: 1,
                            weekNumber = payload.int("weekNumber") ?: existing?.weekNumber ?: 1,
                            year = payload.int("year") ?: existing?.year ?: 2026,
                            objectives = if (payload.containsKey("objectives")) payload.rawString("objectives").orEmpty() else existing?.objectives.orEmpty(),
                            activities = if (payload.containsKey("activities")) payload.rawString("activities").orEmpty() else existing?.activities.orEmpty(),
                            evaluation = if (payload.containsKey("evaluation")) payload.rawString("evaluation").orEmpty() else existing?.evaluation.orEmpty(),
                            linkedAssessmentIdsCsv = if (payload.containsKey("linkedAssessmentIdsCsv")) {
                                payload.rawString("linkedAssessmentIdsCsv").orEmpty()
                            } else {
                                existing?.linkedAssessmentIdsCsv.orEmpty()
                            },
                            teacherScheduleSlotId = if (payload.containsKey("teacherScheduleSlotId")) {
                                payload.long("teacherScheduleSlotId")?.takeIf { it > 0L }
                            } else {
                                existing?.teacherScheduleSlotId
                            },
                            startTime = if (payload.containsKey("startTime")) payload.rawString("startTime") else existing?.startTime,
                            endTime = if (payload.containsKey("endTime")) payload.rawString("endTime") else existing?.endTime,
                            learningSituationSessionPlanId = if (payload.containsKey("learningSituationSessionPlanId")) {
                                payload.long("learningSituationSessionPlanId")?.takeIf { it > 0L }
                            } else {
                                existing?.learningSituationSessionPlanId
                            },
                            status = SessionStatus.entries.firstOrNull {
                                it.name == payload.string("status")
                            } ?: existing?.status ?: SessionStatus.PLANNED,
                        )
                        container.plannerRepository.upsertSession(session)
                        applied++
                    }

                    "session_journal" -> {
                        val sessionId = SessionJournalSyncCodec.planningSessionId(change.payload)
                        val existing = sessionId?.let { container.sessionJournalRepository.getJournalForSession(it) }
                        val decoded = SessionJournalSyncCodec.decodeKeepingAbsent(change.payload, existing)
                        if (decoded == null) {
                            ignored++
                            return@forEach
                        }
                        container.sessionJournalRepository.saveJournalAggregate(
                            decoded.copy(journal = decoded.journal.copy(id = existing?.journal?.id ?: 0L))
                        )
                        applied++
                    }

                    "teacher_schedule" -> {
                        val updatedAt = Instant.fromEpochMilliseconds(change.updatedAtEpochMs)
                        val incomingId = payload.long("id") ?: 0L
                        val existing = incomingId.takeIf { it > 0L }?.let { id ->
                            container.teacherScheduleRepository.getOrCreatePrimarySchedule().takeIf { it.id == id }
                        }
                        container.teacherScheduleRepository.saveSchedule(
                            TeacherSchedule(
                                id = incomingId,
                                ownerUserId = if (payload.containsKey("ownerUserId")) payload.long("ownerUserId") ?: existing?.ownerUserId ?: 1L else existing?.ownerUserId ?: 1L,
                                academicYearId = if (payload.containsKey("academicYearId")) payload.long("academicYearId") ?: existing?.academicYearId ?: 1L else existing?.academicYearId ?: 1L,
                                name = if (payload.containsKey("name")) payload.string("name") ?: existing?.name ?: "Agenda docente" else existing?.name ?: "Agenda docente",
                                startDateIso = if (payload.containsKey("startDateIso")) payload.string("startDateIso").orEmpty() else existing?.startDateIso.orEmpty(),
                                endDateIso = if (payload.containsKey("endDateIso")) payload.string("endDateIso").orEmpty() else existing?.endDateIso.orEmpty(),
                                activeWeekdaysCsv = if (payload.containsKey("activeWeekdaysCsv")) payload.string("activeWeekdaysCsv") ?: existing?.activeWeekdaysCsv ?: "1,2,3,4,5" else existing?.activeWeekdaysCsv ?: "1,2,3,4,5",
                                trace = AuditTrace(
                                    authorUserId = if (payload.containsKey("authorUserId")) payload.long("authorUserId")?.takeIf { it > 0L } else existing?.trace?.authorUserId,
                                    createdAt = Instant.fromEpochMilliseconds(
                                        if (payload.containsKey("createdAtEpochMs")) payload.long("createdAtEpochMs") ?: change.updatedAtEpochMs else existing?.trace?.createdAt?.toEpochMilliseconds() ?: change.updatedAtEpochMs
                                    ),
                                    updatedAt = updatedAt,
                                    associatedGroupId = if (payload.containsKey("associatedGroupId")) payload.long("associatedGroupId")?.takeIf { it > 0L } else existing?.trace?.associatedGroupId,
                                    deviceId = change.deviceId,
                                    syncVersion = 1,
                                ),
                            ),
                        )
                        applied++
                    }

                    "teacher_schedule_slot" -> {
                        val scheduleId = payload.long("teacherScheduleId") ?: return@forEach
                        val incomingId = payload.long("id") ?: 0L
                        val existing = incomingId.takeIf { it > 0L }?.let { slotId ->
                            container.teacherScheduleRepository.listScheduleSlots(scheduleId).firstOrNull { it.id == slotId }
                        }
                        val schoolClassId = if (payload.containsKey("schoolClassId")) payload.long("schoolClassId") else existing?.schoolClassId
                        val startTime = if (payload.containsKey("startTime")) payload.string("startTime") else existing?.startTime
                        val endTime = if (payload.containsKey("endTime")) payload.string("endTime") else existing?.endTime
                        if (schoolClassId == null || startTime == null || endTime == null) return@forEach
                        container.teacherScheduleRepository.saveScheduleSlot(
                            TeacherScheduleSlot(
                                id = incomingId,
                                teacherScheduleId = scheduleId,
                                schoolClassId = schoolClassId,
                                subjectLabel = if (payload.containsKey("subjectLabel")) payload.string("subjectLabel").orEmpty() else existing?.subjectLabel.orEmpty(),
                                unitLabel = if (payload.containsKey("unitLabel")) payload.string("unitLabel") else existing?.unitLabel,
                                dayOfWeek = if (payload.containsKey("dayOfWeek")) payload.int("dayOfWeek") ?: existing?.dayOfWeek ?: 1 else existing?.dayOfWeek ?: 1,
                                startTime = startTime,
                                endTime = endTime,
                                weeklyTemplateId = if (payload.containsKey("weeklyTemplateId")) payload.long("weeklyTemplateId")?.takeIf { it > 0L } else existing?.weeklyTemplateId,
                            ),
                        )
                        applied++
                    }

                    "planner_evaluation_period" -> {
                        val scheduleId = payload.long("teacherScheduleId") ?: return@forEach
                        val incomingId = payload.long("id") ?: 0L
                        val existing = incomingId.takeIf { it > 0L }?.let { periodId ->
                            container.teacherScheduleRepository.listEvaluationPeriods(scheduleId).firstOrNull { it.id == periodId }
                        }
                        container.teacherScheduleRepository.saveEvaluationPeriod(
                            PlannerEvaluationPeriod(
                                id = incomingId,
                                teacherScheduleId = scheduleId,
                                name = if (payload.containsKey("name")) payload.string("name").orEmpty() else existing?.name.orEmpty(),
                                startDateIso = if (payload.containsKey("startDateIso")) payload.string("startDateIso").orEmpty() else existing?.startDateIso.orEmpty(),
                                endDateIso = if (payload.containsKey("endDateIso")) payload.string("endDateIso").orEmpty() else existing?.endDateIso.orEmpty(),
                                sortOrder = if (payload.containsKey("sortOrder")) payload.int("sortOrder") ?: existing?.sortOrder ?: 0 else existing?.sortOrder ?: 0,
                            ),
                        )
                        applied++
                    }

                    "rubric_bundle" -> {
                        val rubricId = payload.long("rubricId")
                        val name = payload.string("name") ?: return@forEach
                        val existingDetail = rubricId?.takeIf { it > 0L }?.let { container.rubricsRepository.getRubricDetail(it) }
                        val existing = existingDetail?.rubric
                        val savedRubricId = container.rubricsRepository.saveRubric(
                            id = rubricId?.takeIf { it > 0L },
                            name = name,
                            description = if (payload.containsKey("description")) payload.rawString("description") else existing?.description,
                            classId = if (payload.containsKey("classId")) payload.long("classId") else existing?.classId,
                            teachingUnitId = if (payload.containsKey("teachingUnitId")) payload.long("teachingUnitId") else existing?.teachingUnitId,
                            updatedAtEpochMs = change.updatedAtEpochMs,
                            deviceId = change.deviceId,
                            syncVersion = 1,
                        )
                        payload.array("criteria").forEach { criterionElement ->
                            val criterion = criterionElement.jsonObject
                            val criterionId = criterion.long("id")
                            val existingCriterion = existingDetail?.criteria
                                ?.firstOrNull { it.criterion.id == criterionId }
                                ?.criterion
                            val savedCriterionId = container.rubricsRepository.saveCriterion(
                                id = criterionId?.takeIf { it > 0L },
                                rubricId = savedRubricId,
                                description = if (criterion.containsKey("description")) criterion.string("description").orEmpty() else existingCriterion?.description.orEmpty(),
                                weight = if (criterion.containsKey("weight")) criterion.double("weight") ?: existingCriterion?.weight ?: 1.0 else existingCriterion?.weight ?: 1.0,
                                order = if (criterion.containsKey("order")) criterion.int("order") ?: existingCriterion?.order ?: 0 else existingCriterion?.order ?: 0,
                                updatedAtEpochMs = change.updatedAtEpochMs,
                                deviceId = change.deviceId,
                                syncVersion = 1,
                            )
                            if (criterion.containsKey("levels")) criterion.array("levels").forEach { levelElement ->
                                val level = levelElement.jsonObject
                                val existingLevel = existingDetail?.criteria
                                    ?.firstOrNull { it.criterion.id == criterionId }
                                    ?.levels
                                    ?.firstOrNull { it.id == level.long("id") }
                                container.rubricsRepository.saveLevel(
                                    id = level.long("id")?.takeIf { it > 0L },
                                    criterionId = savedCriterionId,
                                    name = if (level.containsKey("name")) level.string("name") ?: existingLevel?.name ?: "Nivel" else existingLevel?.name ?: "Nivel",
                                    points = if (level.containsKey("points")) level.int("points") ?: existingLevel?.points ?: 0 else existingLevel?.points ?: 0,
                                    description = if (level.containsKey("description")) level.string("description") else existingLevel?.description,
                                    order = if (level.containsKey("order")) level.int("order") ?: existingLevel?.order ?: 0 else existingLevel?.order ?: 0,
                                    updatedAtEpochMs = change.updatedAtEpochMs,
                                    deviceId = change.deviceId,
                                    syncVersion = 1,
                                )
                            }
                        }
                        applied++
                    }

                    else -> ignored++
                }
            }.onSuccess {
                // El upsert ganó frente a cualquier borrado previo (más antiguo): si
                // había un tombstone, ya no aplica y lo retiramos para no bloquear
                // futuros upserts legítimos de esta misma entidad.
                container.syncTombstoneRepository.clearTombstone(change.entity, change.id)
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

    // ---------------------------------------------------------------------------
    // DELETE HANDLER
    // ---------------------------------------------------------------------------

    private suspend fun applyDelete(change: SyncChange): Boolean {
        val payload = runCatching { json.parseToJsonElement(change.payload).jsonObject }.getOrNull() ?: return false
        return when (change.entity) {
            "academic_year" -> {
                payload.long("id")?.let {
                    runCatching { container.academicYearsRepository.deleteArchivedAcademicYear(it) }.isSuccess
                } ?: false
            }
            "student_deleted", "student" -> {
                payload.long("id")?.let { container.studentsRepository.deleteStudent(it); true } ?: false
            }
            "evaluation" -> {
                payload.long("id")?.let { container.evaluationsRepository.deleteEvaluation(it); true } ?: false
            }
            "weekly_slot" -> {
                payload.long("id")?.let { container.weeklyTemplateRepository.delete(it); true } ?: false
            }
            "notebook_tab" -> {
                (payload.string("id") ?: change.id).takeIf { it.isNotBlank() }?.let {
                    container.notebookRepository.deleteTab(it)
                    true
                } ?: false
            }
            "notebook_column" -> {
                (payload.string("id") ?: change.id).takeIf { it.isNotBlank() }?.let {
                    container.notebookRepository.deleteColumn(it)
                    true
                } ?: false
            }
            "notebook_instrument_template" -> {
                (payload.string("id") ?: change.id).takeIf { it.isNotBlank() }?.let {
                    container.database.appDatabaseQueries.deleteInstrumentTemplateById(it)
                    true
                } ?: false
            }
            "notebook_instrument_item" -> {
                (payload.string("id") ?: change.id).takeIf { it.isNotBlank() }?.let {
                    container.database.appDatabaseQueries.deleteInstrumentItemById(it)
                    true
                } ?: false
            }
            "notebook_instrument_response" -> {
                val classId = payload.long("classId")
                val studentId = payload.long("studentId")
                val columnId = payload.string("columnId")
                val itemId = payload.string("itemId")
                if (classId != null && studentId != null && columnId != null && itemId != null) {
                    container.database.appDatabaseQueries.deleteInstrumentResponseById(classId, studentId, columnId, itemId)
                    true
                } else false
            }
            "notebook_group" -> {
                payload.long("id")?.let { container.notebookRepository.deleteWorkGroup(it); true } ?: false
            }
            "notebook_group_member" -> {
                val parts = if (change.id.contains("|")) change.id.split("|") else change.id.split("-")
                val classId = payload.long("classId") ?: payload.long("class_id") 
                    ?: (if (parts.size >= 4) parts[parts.size - 4].toLongOrNull() else null)
                    ?: return false
                val tabId = payload.string("tabId") ?: payload.string("tab_id")
                    ?: (if (parts.size >= 3) parts[parts.size - 3] else null)
                    ?: return false
                val studentId = payload.long("studentId") ?: payload.long("student_id")
                    ?: (if (parts.size >= 1) parts.last().toLongOrNull() else null)
                    ?: return false
                container.notebookConfigRepository.clearStudentsFromWorkGroup(
                    classId = classId,
                    tabId = tabId,
                    studentIds = listOf(studentId),
                )
                true
            }
            "rubric_bundle" -> {
                payload.long("rubricId")?.let { container.rubricsRepository.deleteRubric(it); true } ?: false
            }
            "planning_session" -> {
                payload.long("id")?.let { container.plannerRepository.deleteSession(it); true } ?: false
            }
            "session_journal" -> {
                val sessionId = payload.long("planningSessionId") ?: change.id.toLongOrNull()
                if (sessionId != null && sessionId > 0L) {
                    container.sessionJournalRepository.deleteJournalForSession(sessionId)
                    true
                } else {
                    false
                }
            }
            "teaching_unit" -> {
                payload.long("id")?.let { container.plannerRepository.deleteTeachingUnit(it); true } ?: false
            }
            "teacher_schedule_slot" -> {
                payload.long("id")?.let { container.teacherScheduleRepository.deleteScheduleSlot(it); true } ?: false
            }
            "planner_evaluation_period" -> {
                payload.long("id")?.let { container.teacherScheduleRepository.deleteEvaluationPeriod(it); true } ?: false
            }
            else -> false
        }
    }
}

// ---------------------------------------------------------------------------
// JSON Extensions
// ---------------------------------------------------------------------------

private fun JsonObject.string(key: String): String? = this[key]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }

private fun JsonObject.rawString(key: String): String? {
    val element = this[key] ?: return null
    if (element == JsonNull) return null
    return element.jsonPrimitive.contentOrNull
}
private fun JsonObject.long(key: String): Long? = this[key]?.jsonPrimitive?.longOrNull
private fun JsonObject.int(key: String): Int? = this[key]?.jsonPrimitive?.intOrNull
private fun JsonObject.double(key: String): Double? = this[key]?.jsonPrimitive?.doubleOrNull
private fun JsonObject.bool(key: String): Boolean? = this[key]?.jsonPrimitive?.booleanOrNull
private fun JsonObject.array(key: String): List<JsonElement> = this[key]?.jsonArray ?: emptyList()
private fun JsonObject.longList(key: String): List<Long> = array(key).mapNotNull { it.jsonPrimitive.longOrNull }
