package com.migestor.desktop.sync

import kotlinx.serialization.json.Json
import kotlin.math.abs
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Resultado de ofrecer un estado en directo al relé. */
internal sealed interface LiveAcceptResult {
    /** Aceptado: `json` es el estado ya sellado (con `receivedAtMs`), en una sola línea. */
    data class Accepted(val json: String) : LiveAcceptResult

    /** Mismo `sessionId` con un `seq` igual o más viejo: se ignora. */
    data object Stale : LiveAcceptResult

    /** Cuerpo que no cumple el contrato v1. */
    data object Invalid : LiveAcceptResult
}

internal const val LIVE_BODY_LIMIT_BYTES = 16 * 1024
internal const val LIVE_RETENTION_MS = 30_000L
internal const val LIVE_MAX_SCORES = 64
/** Margen admitido entre la hora que manda el iPad y la del Mac (24 h). Fuera de él, inválido. */
internal const val LIVE_CLOCK_WINDOW_MS = 24L * 60 * 60 * 1000
/** Tope de segundos de un reloj de ronda (24 h). */
internal const val LIVE_MAX_SECONDS = 86_400
/** Tope de número de ronda. */
internal const val LIVE_MAX_ROUND = 10_000

/**
 * Guarda en memoria el último estado en directo de un torneo (iPad -> helper -> Mac).
 *
 * Es lógica pura y sin red: el reloj entra por parámetro para poder probarla. Solo
 * reconstruye el JSON con los campos del contrato v1, así que cualquier campo extra
 * (por ejemplo nombres de alumnado) desaparece aquí aunque el iPad lo enviara.
 */
internal class LiveStateRelay {
    private val lock = Any()
    private var lastJson: String? = null
    private var lastSessionId: String? = null
    private var lastSeq: Long = -1
    private var lastReceivedAtMs: Long = 0

    fun accept(body: String, nowMs: Long): LiveAcceptResult {
        val parsed = parse(body, nowMs) ?: return LiveAcceptResult.Invalid
        synchronized(lock) {
            val vigente = lastJson != null && nowMs - lastReceivedAtMs <= LIVE_RETENTION_MS
            if (vigente && lastSessionId == parsed.sessionId && parsed.seq <= lastSeq) {
                return LiveAcceptResult.Stale
            }
            lastJson = parsed.json
            lastSessionId = parsed.sessionId
            lastSeq = parsed.seq
            lastReceivedAtMs = nowMs
            return LiveAcceptResult.Accepted(parsed.json)
        }
    }

    /** Último estado si sigue vigente (30 s desde que llegó, también si es `ended`). */
    fun latest(nowMs: Long): String? = synchronized(lock) {
        val json = lastJson ?: return null
        if (nowMs - lastReceivedAtMs > LIVE_RETENTION_MS) null else json
    }

    /** Aviso SSE: un único `data:` por línea, terminado con línea en blanco. */
    fun sseFrame(json: String): String = "data: $json\n\n"

    private class Parsed(val sessionId: String, val seq: Long, val json: String)

    private fun parse(body: String, nowMs: Long): Parsed? {
        val root = runCatching { Json.parseToJsonElement(body) as? JsonObject }.getOrNull() ?: return null
        if (root.int("v") != 1) return null
        val sessionId = root.string("sessionId")?.takeIf { it.length in 1..64 } ?: return null
        val tournamentId = root.string("tournamentId")?.takeIf { it.length in 1..64 } ?: return null
        val seq = root.long("seq")?.takeIf { it >= 0 } ?: return null
        val sentAtMs = root.long("sentAtMs")?.takeIf { abs(it - nowMs) <= LIVE_CLOCK_WINDOW_MS } ?: return null
        val rawStatus = root.string("status") ?: return null
        val status = if (rawStatus in KNOWN_STATUS) rawStatus else "paused"
        val rawScene = root.string("scene") ?: "auto"
        val scene = if (rawScene in KNOWN_SCENES) rawScene else "auto"

        val roundElement = root["roundNumber"]
        val roundNumber: Int? = if (roundElement == null || roundElement is JsonNull) null
        else root.int("roundNumber")?.takeIf { it in 0..LIVE_MAX_ROUND } ?: return null

        val timerElement = root["timer"]
        var timerJson: JsonObject? = null
        if (timerElement != null && timerElement !is JsonNull) {
            val timer = timerElement as? JsonObject ?: return null
            val totalS = timer.int("totalS")?.takeIf { it in 0..LIVE_MAX_SECONDS } ?: return null
            val endAt = timer["endAtMs"]
            val paused = timer["pausedRemainingS"]
            val endAtMs = if (endAt == null || endAt is JsonNull) null
            else timer.long("endAtMs")?.takeIf { abs(it - nowMs) <= LIVE_CLOCK_WINDOW_MS } ?: return null
            val pausedS = if (paused == null || paused is JsonNull) null
            else timer.int("pausedRemainingS")?.takeIf { it in 0..LIVE_MAX_SECONDS } ?: return null
            timerJson = buildJsonObject {
                if (endAtMs != null) put("endAtMs", endAtMs)
                if (pausedS != null) put("pausedRemainingS", pausedS)
                put("totalS", totalS)
            }
        }

        val scoresElement = root["scores"]
        val scoresJson: JsonObject = when (scoresElement) {
            null, is JsonNull -> JsonObject(emptyMap())
            is JsonObject -> {
                if (scoresElement.size > LIVE_MAX_SCORES) return null
                val limpios = LinkedHashMap<String, JsonElement>()
                for ((key, value) in scoresElement) {
                    if (!UUID_REGEX.matches(key)) return null
                    val pair = value as? JsonArray ?: return null
                    if (pair.size != 2) return null
                    val a = pair[0].asInt()?.takeIf { it in 0..999 } ?: return null
                    val b = pair[1].asInt()?.takeIf { it in 0..999 } ?: return null
                    limpios[key] = JsonArray(listOf(JsonPrimitive(a), JsonPrimitive(b)))
                }
                JsonObject(limpios)
            }
            else -> return null
        }

        val sellado = buildJsonObject {
            put("v", 1)
            put("sessionId", sessionId)
            put("tournamentId", tournamentId)
            put("seq", seq)
            put("sentAtMs", sentAtMs)
            put("receivedAtMs", nowMs)
            put("status", status)
            if (roundNumber != null) put("roundNumber", roundNumber)
            if (timerJson != null) put("timer", timerJson)
            put("scene", scene)
            put("scores", scoresJson)
        }
        return Parsed(sessionId, seq, sellado.toString())
    }

    private fun JsonObject.string(key: String): String? {
        val p = this[key] as? JsonPrimitive ?: return null
        return if (p.isString) p.content else null
    }

    private fun JsonObject.long(key: String): Long? = (this[key] as? JsonPrimitive)?.asLong()

    private fun JsonObject.int(key: String): Int? = (this[key] as? JsonPrimitive)?.asLong()?.let {
        if (it in Int.MIN_VALUE..Int.MAX_VALUE) it.toInt() else null
    }

    private fun JsonPrimitive.asLong(): Long? = if (isString) null else content.toLongOrNull()

    private fun JsonElement.asInt(): Int? = (this as? JsonPrimitive)?.asLong()?.let {
        if (it in Int.MIN_VALUE..Int.MAX_VALUE) it.toInt() else null
    }

    private companion object {
        val KNOWN_STATUS = setOf("running", "paused", "timeUp", "ended")
        val KNOWN_SCENES = setOf("auto", "courts", "standings", "bracket")
        val UUID_REGEX = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
    }
}
