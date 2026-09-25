package com.migestor.data.sync

import com.migestor.shared.domain.SessionJournal
import com.migestor.shared.domain.SessionJournalAction
import com.migestor.shared.domain.SessionJournalAggregate
import com.migestor.shared.domain.SessionJournalDecision
import com.migestor.shared.domain.SessionJournalIndividualNote
import com.migestor.shared.domain.SessionJournalLink
import com.migestor.shared.domain.SessionJournalLinkType
import com.migestor.shared.domain.SessionJournalMedia
import com.migestor.shared.domain.SessionJournalMediaType
import com.migestor.shared.domain.SessionJournalStatus
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

/**
 * El diario viaja entero, ligado a la sesión y no a su id local.
 * Las fotos y audios viajan solo como ruta. No se copian los archivos.
 * Un mensaje viejo, sin el campo `status`, no se aplica: antes podía borrar el diario.
 */
object SessionJournalSyncCodec {
    private val json = Json { ignoreUnknownKeys = true }

    fun encode(aggregate: SessionJournalAggregate): String {
        val journal = aggregate.journal
        return buildJsonObject {
            put("planningSessionId", JsonPrimitive(journal.planningSessionId))
            put("teacherName", JsonPrimitive(journal.teacherName))
            put("scheduledSpace", JsonPrimitive(journal.scheduledSpace))
            put("usedSpace", JsonPrimitive(journal.usedSpace))
            put("unitLabel", JsonPrimitive(journal.unitLabel))
            put("objectivePlanned", JsonPrimitive(journal.objectivePlanned))
            put("plannedText", JsonPrimitive(journal.plannedText))
            put("actualText", JsonPrimitive(journal.actualText))
            put("attainmentText", JsonPrimitive(journal.attainmentText))
            put("adaptationsText", JsonPrimitive(journal.adaptationsText))
            put("incidentsText", JsonPrimitive(journal.incidentsText))
            put("groupObservations", JsonPrimitive(journal.groupObservations))
            put("climateScore", JsonPrimitive(journal.climateScore))
            put("participationScore", JsonPrimitive(journal.participationScore))
            put("usefulTimeScore", JsonPrimitive(journal.usefulTimeScore))
            put("perceivedDifficultyScore", JsonPrimitive(journal.perceivedDifficultyScore))
            put("pedagogicalDecision", JsonPrimitive(journal.pedagogicalDecision.name))
            put("pendingTasksText", JsonPrimitive(journal.pendingTasksText))
            put("materialToPrepareText", JsonPrimitive(journal.materialToPrepareText))
            put("studentsToReviewText", JsonPrimitive(journal.studentsToReviewText))
            put("familyCommunicationText", JsonPrimitive(journal.familyCommunicationText))
            put("nextStepText", JsonPrimitive(journal.nextStepText))
            put("weatherText", JsonPrimitive(journal.weatherText))
            put("materialUsedText", JsonPrimitive(journal.materialUsedText))
            put("physicalIncidentsText", JsonPrimitive(journal.physicalIncidentsText))
            put("injuriesText", JsonPrimitive(journal.injuriesText))
            put("unequippedStudentsText", JsonPrimitive(journal.unequippedStudentsText))
            put("intensityScore", JsonPrimitive(journal.intensityScore))
            put("warmupMinutes", JsonPrimitive(journal.warmupMinutes))
            put("mainPartMinutes", JsonPrimitive(journal.mainPartMinutes))
            put("cooldownMinutes", JsonPrimitive(journal.cooldownMinutes))
            put("stationObservationsText", JsonPrimitive(journal.stationObservationsText))
            put("incidentTags", buildJsonArray { journal.incidentTags.forEach { add(JsonPrimitive(it)) } })
            put("status", JsonPrimitive(journal.status.name))
            put("individualNotes", buildJsonArray {
                aggregate.individualNotes.forEach { note ->
                    add(buildJsonObject {
                        put("studentId", note.studentId?.let(::JsonPrimitive) ?: JsonNull)
                        put("studentName", JsonPrimitive(note.studentName))
                        put("note", JsonPrimitive(note.note))
                        put("tag", JsonPrimitive(note.tag))
                    })
                }
            })
            put("actions", buildJsonArray {
                aggregate.actions.forEach { action ->
                    add(buildJsonObject {
                        put("title", JsonPrimitive(action.title))
                        put("detail", JsonPrimitive(action.detail))
                        put("isCompleted", JsonPrimitive(action.isCompleted))
                    })
                }
            })
            put("media", buildJsonArray {
                aggregate.media.forEach { media ->
                    add(buildJsonObject {
                        put("type", JsonPrimitive(media.type.name))
                        put("uri", JsonPrimitive(media.uri))
                        put("transcript", JsonPrimitive(media.transcript))
                        put("caption", JsonPrimitive(media.caption))
                    })
                }
            })
            put("links", buildJsonArray {
                aggregate.links.forEach { link ->
                    add(buildJsonObject {
                        put("type", JsonPrimitive(link.type.name))
                        put("targetId", JsonPrimitive(link.targetId))
                        put("label", JsonPrimitive(link.label))
                    })
                }
            })
        }.toString()
    }

    fun signature(aggregate: SessionJournalAggregate): String = encode(aggregate)

    fun planningSessionId(payload: String): Long? = payloadObject(payload)?.long("planningSessionId")

    fun decode(payload: String): SessionJournalAggregate? {
        val root = payloadObject(payload) ?: return null
        if (!root.containsKey("status") || !root.containsKey("planningSessionId")) return null
        val planningSessionId = root.long("planningSessionId") ?: return null
        val journal = SessionJournal(
            planningSessionId = planningSessionId,
            teacherName = root.rawString("teacherName").orEmpty(),
            scheduledSpace = root.rawString("scheduledSpace").orEmpty(),
            usedSpace = root.rawString("usedSpace").orEmpty(),
            unitLabel = root.rawString("unitLabel").orEmpty(),
            objectivePlanned = root.rawString("objectivePlanned").orEmpty(),
            plannedText = root.rawString("plannedText").orEmpty(),
            actualText = root.rawString("actualText").orEmpty(),
            attainmentText = root.rawString("attainmentText").orEmpty(),
            adaptationsText = root.rawString("adaptationsText").orEmpty(),
            incidentsText = root.rawString("incidentsText").orEmpty(),
            groupObservations = root.rawString("groupObservations").orEmpty(),
            climateScore = root.int("climateScore") ?: 0,
            participationScore = root.int("participationScore") ?: 0,
            usefulTimeScore = root.int("usefulTimeScore") ?: 0,
            perceivedDifficultyScore = root.int("perceivedDifficultyScore") ?: 0,
            pedagogicalDecision = enumOrDefault(root.rawString("pedagogicalDecision"), SessionJournalDecision.NONE),
            pendingTasksText = root.rawString("pendingTasksText").orEmpty(),
            materialToPrepareText = root.rawString("materialToPrepareText").orEmpty(),
            studentsToReviewText = root.rawString("studentsToReviewText").orEmpty(),
            familyCommunicationText = root.rawString("familyCommunicationText").orEmpty(),
            nextStepText = root.rawString("nextStepText").orEmpty(),
            weatherText = root.rawString("weatherText").orEmpty(),
            materialUsedText = root.rawString("materialUsedText").orEmpty(),
            physicalIncidentsText = root.rawString("physicalIncidentsText").orEmpty(),
            injuriesText = root.rawString("injuriesText").orEmpty(),
            unequippedStudentsText = root.rawString("unequippedStudentsText").orEmpty(),
            intensityScore = root.int("intensityScore") ?: 0,
            warmupMinutes = root.int("warmupMinutes") ?: 0,
            mainPartMinutes = root.int("mainPartMinutes") ?: 0,
            cooldownMinutes = root.int("cooldownMinutes") ?: 0,
            stationObservationsText = root.rawString("stationObservationsText").orEmpty(),
            incidentTags = root.stringList("incidentTags"),
            status = enumOrDefault(root.rawString("status"), SessionJournalStatus.EMPTY),
        )
        return SessionJournalAggregate(
            journal = journal,
            individualNotes = root.array("individualNotes").map { element ->
                val note = element.jsonObject
                SessionJournalIndividualNote(
                    studentId = note.long("studentId")?.takeIf { it > 0L },
                    studentName = note.rawString("studentName").orEmpty(),
                    note = note.rawString("note").orEmpty(),
                    tag = note.rawString("tag").orEmpty(),
                )
            },
            actions = root.array("actions").map { element ->
                val action = element.jsonObject
                SessionJournalAction(
                    title = action.rawString("title").orEmpty(),
                    detail = action.rawString("detail").orEmpty(),
                    isCompleted = action.bool("isCompleted") ?: false,
                )
            },
            media = root.array("media").map { element ->
                val media = element.jsonObject
                SessionJournalMedia(
                    type = enumOrDefault(media.rawString("type"), SessionJournalMediaType.PHOTO),
                    uri = media.rawString("uri").orEmpty(),
                    transcript = media.rawString("transcript").orEmpty(),
                    caption = media.rawString("caption").orEmpty(),
                )
            },
            links = root.array("links").map { element ->
                val link = element.jsonObject
                SessionJournalLink(
                    type = enumOrDefault(link.rawString("type"), SessionJournalLinkType.NOTEBOOK),
                    targetId = link.rawString("targetId").orEmpty(),
                    label = link.rawString("label").orEmpty(),
                )
            },
        )
    }

    fun forLocalUpsert(payload: String, localJournalId: Long): SessionJournalAggregate? {
        val decoded = decode(payload) ?: return null
        return decoded.copy(journal = decoded.journal.copy(id = localJournalId))
    }

    private fun payloadObject(payload: String): JsonObject? =
        runCatching { json.parseToJsonElement(payload).jsonObject }.getOrNull()

    private fun JsonObject.rawString(key: String): String? {
        val element = this[key] ?: return null
        if (element == JsonNull) return null
        return element.jsonPrimitive.contentOrNull
    }

    private fun JsonObject.long(key: String): Long? {
        val element = this[key] ?: return null
        if (element == JsonNull) return null
        return element.jsonPrimitive.longOrNull
    }

    private fun JsonObject.int(key: String): Int? {
        val element = this[key] ?: return null
        if (element == JsonNull) return null
        return element.jsonPrimitive.intOrNull
    }

    private fun JsonObject.bool(key: String): Boolean? {
        val element = this[key] ?: return null
        if (element == JsonNull) return null
        val primitive = element.jsonPrimitive
        primitive.booleanOrNull?.let { return it }
        return when (primitive.contentOrNull) {
            "true", "1" -> true
            "false", "0" -> false
            else -> null
        }
    }

    private fun JsonObject.array(key: String): JsonArray =
        this[key] as? JsonArray ?: JsonArray(emptyList())

    private fun JsonObject.stringList(key: String): List<String> =
        array(key).mapNotNull { it.jsonPrimitive.contentOrNull }

    private inline fun <reified T : Enum<T>> enumOrDefault(raw: String?, fallback: T): T =
        enumValues<T>().firstOrNull { it.name == raw } ?: fallback
}
