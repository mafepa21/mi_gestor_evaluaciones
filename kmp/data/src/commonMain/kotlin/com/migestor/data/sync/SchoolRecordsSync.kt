package com.migestor.data.sync

import com.migestor.data.di.KmpContainer
import com.migestor.shared.domain.Meeting
import com.migestor.shared.domain.MeetingAgreement
import com.migestor.shared.domain.StudentSupportMeasure
import com.migestor.shared.domain.StudentTutoringSession
import com.migestor.shared.sync.SyncAck
import com.migestor.shared.sync.SyncChange
import kotlinx.datetime.Clock
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

/**
 * Sync LAN de las actas y del seguimiento de Inclusión: reuniones, sus acuerdos,
 * medidas de apoyo, tutorías con familias y asignaturas.
 *
 * La app Apple ya encolaba estos cambios, pero ningún lado sabía aplicarlos:
 * `SqlDelightSyncAdapter` los contaba como `ignored`, el iPad soltaba su cola
 * (`failed == 0`) y el dato se perdía en silencio. Esta clase es la única que los
 * lee, los aplica y los borra: la usan el helper del Mac (vía el adapter) y la app
 * Apple (desde `KmpBridge+SyncLAN.swift`), así ambos lados entienden lo mismo.
 *
 * Los payloads son los que ya mandaba la app Apple. Una clave ausente conserva el
 * valor local (p. ej. retirar una medida solo manda `endDateIso` e `isActive`).
 * LWW real: si la fila local es igual o más nueva que el cambio, no se toca.
 */
class SchoolRecordsSync(
    private val container: KmpContainer,
    private val localDeviceId: String,
) {
    enum class Outcome { APPLIED, STALE, SKIPPED }

    data class Collected(
        val changes: List<SyncChange>,
        val liveIdsByEntity: Map<String, Set<String>>,
    )

    private val json = Json { ignoreUnknownKeys = true }
    private val queries get() = container.database.appDatabaseQueries

    // Cachés por lote: acuerdos, medidas y tutorías no tienen consulta por id.
    private var agreementsById: Map<Long, MeetingAgreement>? = null
    private var measuresById: Map<Long, StudentSupportMeasure>? = null
    private var tutoringById: Map<Long, StudentTutoringSession>? = null

    // ---------------------------------------------------------------------------
    // COLLECT
    // ---------------------------------------------------------------------------

    @Throws(Exception::class)
    suspend fun collect(sinceEpochMs: Long): Collected {
        val changes = mutableListOf<SyncChange>()
        val live = ENTITIES.associateWith { mutableSetOf<String>() }

        container.subjectsRepository.listSubjects().forEach { subject ->
            live.getValue(SUBJECT) += subject.id.toString()
            changes.addIfNewer(SUBJECT, subject.id, subject.trace.updatedAt.toEpochMilliseconds(), subject.trace.deviceId, sinceEpochMs) {
                put("id", JsonPrimitive(subject.id))
                put("code", JsonPrimitive(subject.code))
                put("name", JsonPrimitive(subject.name))
                put("stageCycleId", subject.stageCycleId?.let(::JsonPrimitive) ?: JsonNull)
            }
        }

        container.meetingRepository.listAll().forEach { meeting ->
            live.getValue(MEETINGS) += meeting.id.toString()
            changes.addIfNewer(MEETINGS, meeting.id, meeting.trace.updatedAt.toEpochMilliseconds(), meeting.trace.deviceId, sinceEpochMs) {
                meetingPayload(meeting)
            }
            meeting.agreements.forEach { agreement ->
                live.getValue(MEETING_AGREEMENTS) += agreement.id.toString()
                changes.addIfNewer(MEETING_AGREEMENTS, agreement.id, agreement.trace.updatedAt.toEpochMilliseconds(), agreement.trace.deviceId, sinceEpochMs) {
                    agreementPayload(agreement)
                }
            }
        }

        container.studentsRepository.listStudents().forEach { student ->
            container.studentSupportMeasureRepository.listByStudent(student.id).forEach { measure ->
                live.getValue(SUPPORT_MEASURES) += measure.id.toString()
                changes.addIfNewer(SUPPORT_MEASURES, measure.id, measure.trace.updatedAt.toEpochMilliseconds(), measure.trace.deviceId, sinceEpochMs) {
                    measurePayload(measure)
                }
            }
            container.studentTutoringSessionRepository.listByStudent(student.id).forEach { session ->
                live.getValue(TUTORING_SESSIONS) += session.id.toString()
                changes.addIfNewer(TUTORING_SESSIONS, session.id, session.trace.updatedAt.toEpochMilliseconds(), session.trace.deviceId, sinceEpochMs) {
                    tutoringPayload(session)
                }
            }
        }

        return Collected(changes, live)
    }

    private inline fun MutableList<SyncChange>.addIfNewer(
        entity: String,
        id: Long,
        updatedAtEpochMs: Long,
        deviceId: String?,
        sinceEpochMs: Long,
        crossinline payload: kotlinx.serialization.json.JsonObjectBuilder.() -> Unit,
    ) {
        if (sinceEpochMs != 0L && updatedAtEpochMs <= sinceEpochMs) return
        this += SyncChange(
            entity = entity,
            id = id.toString(),
            updatedAtEpochMs = updatedAtEpochMs,
            deviceId = deviceId ?: localDeviceId,
            payload = buildJsonObject { payload() }.toString(),
        )
    }

    private fun kotlinx.serialization.json.JsonObjectBuilder.meetingPayload(meeting: Meeting) {
        put("id", JsonPrimitive(meeting.id))
        put("title", JsonPrimitive(meeting.title))
        put("dateIso", JsonPrimitive(meeting.date.toString()))
        put("type", JsonPrimitive(meeting.type.name))
        put("location", JsonPrimitive(meeting.location))
        put("attendees", JsonPrimitive(meeting.attendees))
        put("summary", JsonPrimitive(meeting.summary))
        put("isClosed", JsonPrimitive(meeting.isClosed))
    }

    private fun kotlinx.serialization.json.JsonObjectBuilder.agreementPayload(agreement: MeetingAgreement) {
        put("id", JsonPrimitive(agreement.id))
        put("meetingId", JsonPrimitive(agreement.meetingId))
        put("description", JsonPrimitive(agreement.description))
        put("responsible", JsonPrimitive(agreement.responsible))
        put("dueIso", agreement.due?.let { JsonPrimitive(it.toString()) } ?: JsonNull)
        put("isDone", JsonPrimitive(agreement.isDone))
    }

    private fun kotlinx.serialization.json.JsonObjectBuilder.measurePayload(measure: StudentSupportMeasure) {
        put("id", JsonPrimitive(measure.id))
        put("studentId", JsonPrimitive(measure.studentId))
        put("level", JsonPrimitive(measure.level.name))
        put("measureType", JsonPrimitive(measure.measureType.name))
        put("startDateIso", JsonPrimitive(measure.startDate.toString()))
        put("endDateIso", measure.endDate?.let { JsonPrimitive(it.toString()) } ?: JsonNull)
        put("responsible", measure.responsible?.let(::JsonPrimitive) ?: JsonNull)
        put("intensity", measure.intensity?.let { JsonPrimitive(it.name) } ?: JsonNull)
        put("followUpNotes", JsonPrimitive(measure.followUpNotes))
        put("documentRef", measure.documentRef?.let(::JsonPrimitive) ?: JsonNull)
        put("reviewDueIso", measure.reviewDue?.let { JsonPrimitive(it.toString()) } ?: JsonNull)
        put("isActive", JsonPrimitive(measure.isActive))
    }

    private fun kotlinx.serialization.json.JsonObjectBuilder.tutoringPayload(session: StudentTutoringSession) {
        put("id", JsonPrimitive(session.id))
        put("studentId", JsonPrimitive(session.studentId))
        put("dateIso", JsonPrimitive(session.date.toString()))
        put("channel", JsonPrimitive(session.channel.name))
        put("attendees", JsonPrimitive(session.attendees))
        put("topics", JsonPrimitive(session.topics))
        put("agreements", JsonPrimitive(session.agreements))
        put("reviewDueIso", session.reviewDue?.let { JsonPrimitive(it.toString()) } ?: JsonNull)
        put("isClosed", JsonPrimitive(session.isClosed))
    }

    // ---------------------------------------------------------------------------
    // APPLY
    // ---------------------------------------------------------------------------

    /**
     * Aplica (o borra) los cambios de estas entidades con la misma regla de
     * tombstones que `SqlDelightSyncAdapter.applyIncomingChangesLww`. Los padres van
     * antes que los hijos: un acuerdo no puede llegar antes que su reunión.
     */
    @Throws(Exception::class)
    suspend fun applyAll(changes: List<SyncChange>): SyncAck {
        var applied = 0
        var conflicts = 0
        var ignored = 0
        var failed = 0
        resetCaches()
        sortedForApply(changes.filter { handles(it.entity) }).forEach { change ->
            runCatching {
                if (change.op == "delete") {
                    if (delete(change)) {
                        container.syncTombstoneRepository.recordTombstone(
                            entity = change.entity,
                            entityId = change.id,
                            deletedAtEpochMs = change.updatedAtEpochMs,
                            deviceId = change.deviceId,
                        )
                        applied++
                    } else {
                        ignored++
                    }
                    return@runCatching
                }
                if (container.syncTombstoneRepository.isDeletedAtOrAfter(change.entity, change.id, change.updatedAtEpochMs)) {
                    ignored++
                    return@runCatching
                }
                when (apply(change)) {
                    Outcome.APPLIED -> {
                        applied++
                        container.syncTombstoneRepository.clearTombstone(change.entity, change.id)
                    }
                    Outcome.STALE -> conflicts++
                    Outcome.SKIPPED -> ignored++
                }
            }.onFailure { failed++ }
        }
        resetCaches()
        return SyncAck(
            applied = applied,
            conflictsResolvedByLww = conflicts,
            serverEpochMs = Clock.System.now().toEpochMilliseconds(),
            ignored = ignored,
            failed = failed,
        )
    }

    private fun resetCaches() {
        agreementsById = null
        measuresById = null
        tutoringById = null
    }

    private suspend fun apply(change: SyncChange): Outcome {
        val id = change.id.toLongOrNull() ?: return Outcome.SKIPPED
        val payload = runCatching { json.parseToJsonElement(change.payload).jsonObject }.getOrNull()
            ?: error("payload ilegible: ${change.entity} ${change.id}")
        val updatedAt = change.updatedAtEpochMs
        val deviceId = change.deviceId
        return when (change.entity) {
            SUBJECT -> {
                val existing = container.subjectsRepository.listSubjects().firstOrNull { it.id == id }
                if (existing != null && existing.trace.updatedAt.toEpochMilliseconds() >= updatedAt) return Outcome.STALE
                val code = payload.text("code", existing?.code) ?: return Outcome.SKIPPED
                val name = payload.text("name", existing?.name) ?: return Outcome.SKIPPED
                container.subjectsRepository.saveSubject(
                    id = id,
                    code = code,
                    name = name,
                    stageCycleId = payload.longOrKeep("stageCycleId", existing?.stageCycleId),
                    updatedAtEpochMs = updatedAt,
                    deviceId = deviceId,
                    syncVersion = 1,
                )
                Outcome.APPLIED
            }
            MEETINGS -> {
                val existing = container.meetingRepository.getById(id)
                if (existing != null && existing.trace.updatedAt.toEpochMilliseconds() >= updatedAt) return Outcome.STALE
                val title = payload.text("title", existing?.title) ?: return Outcome.SKIPPED
                val dateIso = payload.text("dateIso", existing?.date?.toString()) ?: return Outcome.SKIPPED
                val type = payload.text("type", existing?.type?.name) ?: "OTRA"
                val location = payload.text("location", existing?.location) ?: ""
                val attendees = payload.text("attendees", existing?.attendees) ?: ""
                val summary = payload.text("summary", existing?.summary) ?: ""
                val isClosed = payload.flag("isClosed", existing?.isClosed ?: false)
                if (existing == null) {
                    queries.insertMeetingWithId(id, title, dateIso, type, location, attendees, summary, isClosed.toLong(), updatedAt, updatedAt, deviceId, 1)
                } else {
                    queries.updateMeeting(title, dateIso, type, location, attendees, summary, isClosed.toLong(), updatedAt, deviceId, id)
                }
                Outcome.APPLIED
            }
            MEETING_AGREEMENTS -> {
                val existing = agreements()[id]
                if (existing != null && existing.trace.updatedAt.toEpochMilliseconds() >= updatedAt) return Outcome.STALE
                val description = payload.text("description", existing?.description) ?: return Outcome.SKIPPED
                val responsible = payload.text("responsible", existing?.responsible) ?: ""
                val dueIso = payload.textOrNull("dueIso", existing?.due?.toString())
                val isDone = payload.flag("isDone", existing?.isDone ?: false)
                if (existing == null) {
                    val meetingId = payload.longOrKeep("meetingId", null) ?: return Outcome.SKIPPED
                    // Sin su reunión el acuerdo quedaría huérfano: se reintentará en el próximo pull.
                    if (container.meetingRepository.getById(meetingId) == null) return Outcome.SKIPPED
                    queries.upsertMeetingAgreementWithId(id, meetingId, description, responsible, dueIso, isDone.toLong(), updatedAt, updatedAt, deviceId, 1)
                } else {
                    queries.updateMeetingAgreement(description, responsible, dueIso, isDone.toLong(), updatedAt, deviceId, id)
                }
                Outcome.APPLIED
            }
            SUPPORT_MEASURES -> {
                val existing = measures()[id]
                if (existing != null && existing.trace.updatedAt.toEpochMilliseconds() >= updatedAt) return Outcome.STALE
                val level = payload.text("level", existing?.level?.name) ?: return Outcome.SKIPPED
                val measureType = payload.text("measureType", existing?.measureType?.name) ?: return Outcome.SKIPPED
                val startDateIso = payload.text("startDateIso", existing?.startDate?.toString()) ?: return Outcome.SKIPPED
                val responsible = payload.textOrNull("responsible", existing?.responsible)?.takeIf { it.isNotBlank() }
                val intensity = payload.textOrNull("intensity", existing?.intensity?.name)
                val followUpNotes = payload.text("followUpNotes", existing?.followUpNotes) ?: ""
                val documentRef = payload.textOrNull("documentRef", existing?.documentRef)?.takeIf { it.isNotBlank() }
                val reviewDueIso = payload.textOrNull("reviewDueIso", existing?.reviewDue?.toString())
                val endDateIso = payload.textOrNull("endDateIso", existing?.endDate?.toString())
                val isActive = payload.flag("isActive", existing?.isActive ?: true)
                if (existing == null) {
                    val studentId = payload.longOrKeep("studentId", null) ?: return Outcome.SKIPPED
                    queries.upsertSupportMeasure(
                        id, studentId, level, measureType, startDateIso, endDateIso, responsible, intensity,
                        followUpNotes, documentRef, reviewDueIso, isActive.toLong(), updatedAt, updatedAt, deviceId, 1,
                    )
                } else {
                    // update en el sitio para no reescribir created_at; la retirada va aparte.
                    queries.updateSupportMeasure(
                        level, measureType, startDateIso, responsible, intensity, followUpNotes, documentRef,
                        reviewDueIso, updatedAt, deviceId, id,
                    )
                    if (!isActive && existing.isActive) {
                        queries.retireSupportMeasure(endDateIso ?: startDateIso, updatedAt, deviceId, id)
                    }
                }
                Outcome.APPLIED
            }
            TUTORING_SESSIONS -> {
                val existing = tutoring()[id]
                if (existing != null && existing.trace.updatedAt.toEpochMilliseconds() >= updatedAt) return Outcome.STALE
                val dateIso = payload.text("dateIso", existing?.date?.toString()) ?: return Outcome.SKIPPED
                val channel = payload.text("channel", existing?.channel?.name) ?: "IN_PERSON"
                val attendees = payload.text("attendees", existing?.attendees) ?: ""
                val topics = payload.text("topics", existing?.topics) ?: ""
                val agreements = payload.text("agreements", existing?.agreements) ?: ""
                val reviewDueIso = payload.textOrNull("reviewDueIso", existing?.reviewDue?.toString())
                val isClosed = payload.flag("isClosed", existing?.isClosed ?: false)
                if (existing == null) {
                    val studentId = payload.longOrKeep("studentId", null) ?: return Outcome.SKIPPED
                    queries.upsertTutoringSessionWithId(
                        id, studentId, dateIso, channel, attendees, topics, agreements, reviewDueIso,
                        isClosed.toLong(), updatedAt, updatedAt, deviceId, 1,
                    )
                } else {
                    queries.updateTutoringSession(
                        dateIso, channel, attendees, topics, agreements, reviewDueIso, isClosed.toLong(),
                        updatedAt, deviceId, id,
                    )
                }
                Outcome.APPLIED
            }
            else -> Outcome.SKIPPED
        }
    }

    private suspend fun delete(change: SyncChange): Boolean {
        val id = change.id.toLongOrNull() ?: return false
        when (change.entity) {
            SUBJECT -> container.subjectsRepository.deleteSubject(id)
            MEETINGS -> container.meetingRepository.deleteMeeting(id)
            MEETING_AGREEMENTS -> container.meetingRepository.deleteAgreement(id)
            SUPPORT_MEASURES -> container.studentSupportMeasureRepository.delete(id)
            TUTORING_SESSIONS -> container.studentTutoringSessionRepository.delete(id)
            else -> return false
        }
        return true
    }

    private suspend fun agreements(): Map<Long, MeetingAgreement> =
        agreementsById ?: container.meetingRepository.listAll()
            .flatMap { it.agreements }
            .associateBy { it.id }
            .also { agreementsById = it }

    private suspend fun measures(): Map<Long, StudentSupportMeasure> =
        measuresById ?: container.studentsRepository.listStudents()
            .flatMap { container.studentSupportMeasureRepository.listByStudent(it.id) }
            .associateBy { it.id }
            .also { measuresById = it }

    private suspend fun tutoring(): Map<Long, StudentTutoringSession> =
        tutoringById ?: container.studentsRepository.listStudents()
            .flatMap { container.studentTutoringSessionRepository.listByStudent(it.id) }
            .associateBy { it.id }
            .also { tutoringById = it }

    companion object {
        const val SUBJECT = "subject"
        const val MEETINGS = "meetings"
        const val MEETING_AGREEMENTS = "meeting_agreements"
        const val SUPPORT_MEASURES = "student_support_measures"
        const val TUTORING_SESSIONS = "student_tutoring_sessions"

        /** En orden de aplicación: padres antes que hijos. */
        val ENTITIES: List<String> = listOf(SUBJECT, MEETINGS, MEETING_AGREEMENTS, SUPPORT_MEASURES, TUTORING_SESSIONS)

        fun handles(entity: String): Boolean = entity in ENTITIES

        /** Upserts por orden de padres a hijos; los borrados al final, de hijos a padres. */
        fun sortedForApply(changes: List<SyncChange>): List<SyncChange> {
            val (deletes, upserts) = changes.partition { it.op == "delete" }
            return upserts.sortedBy { ENTITIES.indexOf(it.entity) } +
                deletes.sortedByDescending { ENTITIES.indexOf(it.entity) }
        }
    }
}

private fun Boolean.toLong(): Long = if (this) 1L else 0L

/** Texto que puede ser vacío. Clave ausente → `keep`; `null` en el JSON → `keep`. */
private fun JsonObject.text(key: String, keep: String?): String? {
    if (!containsKey(key)) return keep
    val element = this[key]
    if (element == null || element is JsonNull) return keep
    return element.jsonPrimitive.contentOrNull ?: keep
}

/** Texto opcional. Clave ausente → `keep`; `null` en el JSON → `null` (se borra). */
private fun JsonObject.textOrNull(key: String, keep: String?): String? {
    if (!containsKey(key)) return keep
    val element = this[key]
    if (element == null || element is JsonNull) return null
    return element.jsonPrimitive.contentOrNull?.takeIf { it.isNotEmpty() }
}

private fun JsonObject.longOrKeep(key: String, keep: Long?): Long? {
    if (!containsKey(key)) return keep
    val element = this[key]
    if (element == null || element is JsonNull) return null
    return element.jsonPrimitive.longOrNull ?: keep
}

private fun JsonObject.flag(key: String, keep: Boolean): Boolean =
    this[key]?.takeIf { it !is JsonNull }?.jsonPrimitive?.booleanOrNull ?: keep
