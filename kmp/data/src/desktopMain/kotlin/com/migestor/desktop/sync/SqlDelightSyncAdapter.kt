package com.migestor.desktop.sync

import com.migestor.data.di.KmpContainer
import com.migestor.shared.domain.AuditTrace
import com.migestor.shared.domain.NotebookColumnDefinition
import com.migestor.shared.domain.NotebookColumnType
import com.migestor.shared.domain.NotebookTab
import com.migestor.shared.domain.PlanningSession
import com.migestor.shared.domain.SessionStatus
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
    private val rosterSnapshotByClass = mutableMapOf<Long, Set<Long>>()
    private val weeklySlotSnapshotByClass = mutableMapOf<Long, Map<Long, String>>()

    // ---------------------------------------------------------------------------
    // COLLECT LOCAL CHANGES
    // ---------------------------------------------------------------------------

    override suspend fun collectLocalChanges(sinceEpochMs: Long): List<SyncChange> {
        val changes = mutableListOf<SyncChange>()
        val classes = container.classesRepository.listClasses()

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
            val currentWeeklySlotSignatures = weeklySlots.associate { slot ->
                slot.id to "${slot.schoolClassId}|${slot.dayOfWeek}|${slot.startTime}|${slot.endTime}"
            }
            val previousWeeklySlotSignatures = weeklySlotSnapshotByClass[schoolClass.id]
            weeklySlots.forEach { slot ->
                val signature = currentWeeklySlotSignatures[slot.id]
                val previousSignature = previousWeeklySlotSignatures?.get(slot.id)
                val shouldSendWeeklySlot = sinceEpochMs == 0L || previousSignature == null || previousSignature != signature
                if (shouldSendWeeklySlot) {
                    changes += SyncChange(
                        entity = "weekly_slot",
                        id = slot.id.toString(),
                        updatedAtEpochMs = Clock.System.now().toEpochMilliseconds(),
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
                changes = changes,
                scope = "class:${schoolClass.id}:weekly_slot",
                entity = "weekly_slot",
                currentIds = currentWeeklySlotIds,
            ) { deletedId ->
                buildJsonObject {
                    put("id", JsonPrimitive(deletedId.toLongOrNull() ?: 0L))
                    put("schoolClassId", JsonPrimitive(schoolClass.id))
                }
            }
            weeklySlotSnapshotByClass[schoolClass.id] = currentWeeklySlotSignatures

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
                changes = changes,
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
                        }.toString(),
                    )
                }
            }
            appendDeletesByScope(
                changes = changes,
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
                changes = changes,
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
                        }.toString(),
                    )
                }
                if (columnUpdatedAt <= sinceEpochMs) {
                    val standardizedId = column.evaluationId?.let { "eval_$it" } ?: column.id
                    currentColumnIds += standardizedId
                }
            }
            appendDeletesByScope(
                changes = changes,
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
                    }.toString(),
                )
            }
        }
        appendDeletesByScope(
            changes = changes,
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
            changes = changes,
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
        container.plannerRepository.listAllTeachingUnits().forEach { unit ->
            // Teaching units no tienen campo updatedAt aún, enviamos siempre si sinceEpochMs==0
            if (sinceEpochMs == 0L) {
                changes += SyncChange(
                    entity = "teaching_unit",
                    id = unit.id.toString(),
                    updatedAtEpochMs = Clock.System.now().toEpochMilliseconds(),
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

        container.plannerRepository.listAllSessions().forEach { session ->
            if (sinceEpochMs == 0L) {
                changes += SyncChange(
                    entity = "planning_session",
                    id = session.id.toString(),
                    updatedAtEpochMs = Clock.System.now().toEpochMilliseconds(),
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
                        put("status", JsonPrimitive(session.status.name))
                    }.toString(),
                )
            }
        }

        return changes
    }

    private fun appendDeletesByScope(
        changes: MutableList<SyncChange>,
        scope: String,
        entity: String,
        currentIds: Set<String>,
        payloadBuilder: (String) -> JsonObject,
    ) {
        val previousIds = syncIdSnapshotByScope[scope]
        if (previousIds != null) {
            val now = Clock.System.now().toEpochMilliseconds()
            previousIds.subtract(currentIds).forEach { deletedId ->
                changes += SyncChange(
                    entity = entity,
                    id = deletedId,
                    updatedAtEpochMs = now,
                    deviceId = localDeviceId,
                    payload = payloadBuilder(deletedId).toString(),
                    op = "delete",
                )
            }
        }
        syncIdSnapshotByScope[scope] = currentIds
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
                if (deleted) applied++ else ignored++
                return@forEach
            }

            runCatching {
                when (change.entity) {
                    "class" -> {
                        val id = payload.long("id")
                        val name = payload.string("name") ?: return@forEach
                        val course = payload.int("course") ?: return@forEach
                        container.classesRepository.saveClass(
                            id = id?.takeIf { it > 0L },
                            name = name,
                            course = course,
                            description = payload.string("description"),
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
                        container.studentsRepository.saveStudent(
                            id = id?.takeIf { it > 0L },
                            firstName = firstName,
                            lastName = lastName,
                            email = payload.string("email"),
                            photoPath = payload.string("photoPath"),
                            isInjured = payload.bool("isInjured") ?: false,
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
                            container.classesRepository.addStudentToClass(classId, it)
                            applied++
                        }
                        localIds.subtract(remoteIds).forEach {
                            container.classesRepository.removeStudentFromClass(classId, it)
                            applied++
                        }
                    }

                    "evaluation" -> {
                        val id = payload.long("id")
                        val classId = payload.long("classId") ?: return@forEach
                        val code = payload.string("code") ?: return@forEach
                        val name = payload.string("name") ?: return@forEach
                        val type = payload.string("type") ?: return@forEach
                        val weight = payload.double("weight") ?: 1.0
                        container.evaluationsRepository.saveEvaluation(
                            id = id?.takeIf { it > 0L },
                            classId = classId,
                            code = code,
                            name = name,
                            type = type,
                            weight = weight,
                            formula = payload.string("formula"),
                            rubricId = payload.long("rubricId")?.takeIf { it > 0L },
                            description = payload.string("description"),
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
                        container.gradesRepository.upsertGrade(
                            classId = classId,
                            studentId = studentId,
                            columnId = columnId,
                            evaluationId = evaluationId,
                            value = payload.double("value"),
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
                        val parentTabId = payload.string("parentTabId")
                        val description = payload.string("description")
                        container.notebookConfigRepository.saveTab(
                            classId = classId,
                            tab = NotebookTab(
                                id = tabId,
                                title = title,
                                description = description,
                                order = payload.int("order") ?: 0,
                                parentTabId = parentTabId,
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
                        container.notebookRepository.saveWorkGroup(
                            classId = classId,
                            workGroup = com.migestor.shared.domain.NotebookWorkGroup(
                                id = groupId,
                                classId = classId,
                                tabId = tabId,
                                name = name,
                                order = payload.int("order") ?: 0,
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
                        val type = (payload.string("type") ?: payload.string("column_type"))
                            ?.let { runCatching { NotebookColumnType.valueOf(it) }.getOrNull() }
                            ?: NotebookColumnType.NUMERIC
                        val tabIdsCsv = payload.string("tabIdsCsv") ?: payload.string("tab_ids_csv")
                        container.notebookConfigRepository.saveColumn(
                            classId = classId,
                            column = NotebookColumnDefinition(
                                id = columnId,
                                title = title,
                                type = type,
                                evaluationId = payload.long("evaluationId")?.takeIf { it > 0L },
                                rubricId = payload.long("rubricId")?.takeIf { it > 0L },
                                formula = payload.string("formula"),
                                weight = payload.double("weight") ?: 1.0,
                                tabIds = tabIdsCsv
                                    ?.split(",")
                                    ?.map { it.trim() }
                                    ?.filter { it.isNotBlank() }
                                    ?: emptyList(),
                                sharedAcrossTabs = payload.bool("sharedAcrossTabs") ?: payload.bool("shared_across_tabs") ?: false,
                                colorHex = payload.string("colorHex"),
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

                    // ── Nuevas entidades ──────────────────────────────────────

                    "attendance" -> {
                        val studentId = payload.long("studentId") ?: return@forEach
                        val classId = payload.long("classId") ?: return@forEach
                        val dateEpochMs = payload.long("dateEpochMs") ?: return@forEach
                        val status = payload.string("status") ?: return@forEach
                        container.attendanceRepository.saveAttendance(
                            id = payload.long("id")?.takeIf { it > 0L },
                            studentId = studentId,
                            classId = classId,
                            dateEpochMs = dateEpochMs,
                            status = status,
                            note = payload.string("note") ?: "",
                            hasIncident = payload.bool("hasIncident") ?: false,
                            followUpRequired = payload.bool("followUpRequired") ?: false,
                            sessionId = payload.long("sessionId")?.takeIf { it > 0L },
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
                        container.incidentsRepository.saveIncident(
                            id = payload.long("id")?.takeIf { it > 0L },
                            classId = classId,
                            studentId = payload.long("studentId")?.takeIf { it > 0L },
                            title = title,
                            detail = payload.string("detail"),
                            severity = payload.string("severity") ?: "low",
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
                        container.calendarRepository.saveEvent(
                            id = payload.long("id")?.takeIf { it > 0L },
                            classId = payload.long("classId")?.takeIf { it > 0L },
                            title = title,
                            description = payload.string("description"),
                            startEpochMs = startEpochMs,
                            endEpochMs = endEpochMs,
                            externalProvider = payload.string("externalProvider"),
                            externalId = payload.string("externalId"),
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
                        container.plannerRepository.upsertTeachingUnit(
                            TeachingUnit(
                                id = payload.long("id") ?: 0L,
                                name = name,
                                description = payload.string("description") ?: "",
                                colorHex = payload.string("colorHex") ?: "#4A90D9",
                                groupId = payload.long("groupId")?.takeIf { it > 0L },
                                schoolClassId = payload.long("schoolClassId")?.takeIf { it > 0L },
                                startDate = payload.string("startDate")
                                    ?.takeIf { it.isNotBlank() }
                                    ?.let { runCatching { kotlinx.datetime.LocalDate.parse(it) }.getOrNull() },
                                endDate = payload.string("endDate")
                                    ?.takeIf { it.isNotBlank() }
                                    ?.let { runCatching { kotlinx.datetime.LocalDate.parse(it) }.getOrNull() },
                            ),
                        )
                        applied++
                    }

                    "planning_session" -> {
                        val session = PlanningSession(
                            id = payload.long("id") ?: 0L,
                            teachingUnitId = payload.long("teachingUnitId") ?: 0L,
                            teachingUnitName = payload.string("teachingUnitName") ?: "Unidad",
                            teachingUnitColor = payload.string("teachingUnitColor") ?: "#4A90D9",
                            groupId = payload.long("groupId") ?: 0L,
                            groupName = payload.string("groupName") ?: "",
                            dayOfWeek = payload.int("dayOfWeek") ?: 1,
                            period = payload.int("period") ?: 1,
                            weekNumber = payload.int("weekNumber") ?: 1,
                            year = payload.int("year") ?: 2026,
                            objectives = payload.string("objectives") ?: "",
                            activities = payload.string("activities") ?: "",
                            evaluation = payload.string("evaluation") ?: "",
                            linkedAssessmentIdsCsv = payload.string("linkedAssessmentIdsCsv") ?: "",
                            status = SessionStatus.entries.firstOrNull {
                                it.name == payload.string("status")
                            } ?: SessionStatus.PLANNED,
                        )
                        container.plannerRepository.upsertSession(session)
                        applied++
                    }

                    "rubric_bundle" -> {
                        val rubricId = payload.long("rubricId")
                        val name = payload.string("name") ?: return@forEach
                        val savedRubricId = container.rubricsRepository.saveRubric(
                            id = rubricId?.takeIf { it > 0L },
                            name = name,
                            description = payload.string("description"),
                            classId = payload.long("classId"),
                            teachingUnitId = payload.long("teachingUnitId"),
                            updatedAtEpochMs = change.updatedAtEpochMs,
                            deviceId = change.deviceId,
                            syncVersion = 1,
                        )
                        payload.array("criteria").forEach { criterionElement ->
                            val criterion = criterionElement.jsonObject
                            val criterionId = criterion.long("id")
                            val savedCriterionId = container.rubricsRepository.saveCriterion(
                                id = criterionId?.takeIf { it > 0L },
                                rubricId = savedRubricId,
                                description = criterion.string("description") ?: "",
                                weight = criterion.double("weight") ?: 1.0,
                                order = criterion.int("order") ?: 0,
                                updatedAtEpochMs = change.updatedAtEpochMs,
                                deviceId = change.deviceId,
                                syncVersion = 1,
                            )
                            criterion.array("levels").forEach { levelElement ->
                                val level = levelElement.jsonObject
                                container.rubricsRepository.saveLevel(
                                    id = level.long("id")?.takeIf { it > 0L },
                                    criterionId = savedCriterionId,
                                    name = level.string("name") ?: "Nivel",
                                    points = level.int("points") ?: 0,
                                    description = level.string("description"),
                                    order = level.int("order") ?: 0,
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
            "teaching_unit" -> {
                payload.long("id")?.let { container.plannerRepository.deleteTeachingUnit(it); true } ?: false
            }
            else -> false
        }
    }
}

// ---------------------------------------------------------------------------
// JSON Extensions
// ---------------------------------------------------------------------------

private fun JsonObject.string(key: String): String? = this[key]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }
private fun JsonObject.long(key: String): Long? = this[key]?.jsonPrimitive?.longOrNull
private fun JsonObject.int(key: String): Int? = this[key]?.jsonPrimitive?.intOrNull
private fun JsonObject.double(key: String): Double? = this[key]?.jsonPrimitive?.doubleOrNull
private fun JsonObject.bool(key: String): Boolean? = this[key]?.jsonPrimitive?.booleanOrNull
private fun JsonObject.array(key: String): List<JsonElement> = this[key]?.jsonArray ?: emptyList()
private fun JsonObject.longList(key: String): List<Long> = array(key).mapNotNull { it.jsonPrimitive.longOrNull }
