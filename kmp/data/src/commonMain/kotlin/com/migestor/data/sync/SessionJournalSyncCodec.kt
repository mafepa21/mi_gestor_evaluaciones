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

    fun decodeKeepingAbsent(payload: String, existing: SessionJournalAggregate?): SessionJournalAggregate? {
        val root = payloadObject(payload) ?: return null
        val decoded = decode(payload) ?: return null
        val previous = existing ?: return decoded
        val kept = previous.journal
        val incoming = decoded.journal
        return decoded.copy(
            journal = incoming.copy(
                teacherName = root.keepString("teacherName", kept.teacherName),
                scheduledSpace = root.keepString("scheduledSpace", kept.scheduledSpace),
                usedSpace = root.keepString("usedSpace", kept.usedSpace),
                unitLabel = root.keepString("unitLabel", kept.unitLabel),
                objectivePlanned = root.keepString("objectivePlanned", kept.objectivePlanned),
                plannedText = root.keepString("plannedText", kept.plannedText),
                actualText = root.keepString("actualText", kept.actualText),
                attainmentText = root.keepString("attainmentText", kept.attainmentText),
                adaptationsText = root.keepString("adaptationsText", kept.adaptationsText),
                incidentsText = root.keepString("incidentsText", kept.incidentsText),
                groupObservations = root.keepString("groupObservations", kept.groupObservations),
                climateScore = root.keepInt("climateScore", kept.climateScore),
                participationScore = root.keepInt("participationScore", kept.participationScore),
                usefulTimeScore = root.keepInt("usefulTimeScore", kept.usefulTimeScore),
                perceivedDifficultyScore = root.keepInt("perceivedDifficultyScore", kept.perceivedDifficultyScore),
                pedagogicalDecision = if (root.containsKey("pedagogicalDecision")) incoming.pedagogicalDecision else kept.pedagogicalDecision,
                pendingTasksText = root.keepString("pendingTasksText", kept.pendingTasksText),
                materialToPrepareText = root.keepString("materialToPrepareText", kept.materialToPrepareText),
                studentsToReviewText = root.keepString("studentsToReviewText", kept.studentsToReviewText),
                familyCommunicationText = root.keepString("familyCommunicationText", kept.familyCommunicationText),
                nextStepText = root.keepString("nextStepText", kept.nextStepText),
                weatherText = root.keepString("weatherText", kept.weatherText),
                materialUsedText = root.keepString("materialUsedText", kept.materialUsedText),
                physicalIncidentsText = root.keepString("physicalIncidentsText", kept.physicalIncidentsText),
                injuriesText = root.keepString("injuriesText", kept.injuriesText),
                unequippedStudentsText = root.keepString("unequippedStudentsText", kept.unequippedStudentsText),
                intensityScore = root.keepInt("intensityScore", kept.intensityScore),
                warmupMinutes = root.keepInt("warmupMinutes", kept.warmupMinutes),
                mainPartMinutes = root.keepInt("mainPartMinutes", kept.mainPartMinutes),
                cooldownMinutes = root.keepInt("cooldownMinutes", kept.cooldownMinutes),
                stationObservationsText = root.keepString("stationObservationsText", kept.stationObservationsText),
                incidentTags = if (root.containsKey("incidentTags")) incoming.incidentTags else kept.incidentTags,
                status = if (root.containsKey("status")) incoming.status else kept.status,
            ),
            individualNotes = if (root.containsKey("individualNotes")) decoded.individualNotes else previous.individualNotes,
            actions = if (root.containsKey("actions")) decoded.actions else previous.actions,
            media = if (root.containsKey("media")) decoded.media else previous.media,
            links = if (root.containsKey("links")) decoded.links else previous.links,
        )
    }

    /**
     * Upsert local: si hay diario previo, las claves ausentes no lo vacían
     * (mismo criterio que [decodeKeepingAbsent] en el adaptador desktop).
     */
    fun forLocalUpsert(
        payload: String,
        localJournalId: Long,
        existing: SessionJournalAggregate? = null,
    ): SessionJournalAggregate? {
        val decoded = decodeKeepingAbsent(payload, existing) ?: return null
        return decoded.copy(journal = decoded.journal.copy(id = localJournalId))
    }

    private fun payloadObject(payload: String): JsonObject? =
        runCatching { json.parseToJsonElement(payload).jsonObject }.getOrNull()

    private fun JsonObject.keepString(key: String, previous: String): String =
        if (containsKey(key)) rawString(key).orEmpty() else previous

    private fun JsonObject.keepInt(key: String, previous: Int): Int =
        if (containsKey(key)) int(key) ?: previous else previous

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
