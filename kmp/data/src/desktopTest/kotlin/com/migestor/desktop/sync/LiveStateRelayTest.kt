package com.migestor.desktop.sync

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LiveStateRelayTest {
    private val uuidA = "11111111-2222-3333-4444-555555555555"
    private val uuidB = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

    private fun body(
        session: String = "s1",
        seq: Long = 0,
        extra: String = "",
        scores: String = """{"$uuidA":[3,2]}""",
        v: Int = 1,
        status: String = "running",
    ) = """
        {"v":$v,"sessionId":"$session","tournamentId":"t1","seq":$seq,"sentAtMs":1000,
         "status":"$status","roundNumber":2,
         "timer":{"endAtMs":61000,"totalS":60},"scene":"courts","scores":$scores$extra}
    """.trimIndent()

    private fun accepted(r: LiveAcceptResult): JsonObject {
        assertIs<LiveAcceptResult.Accepted>(r)
        return Json.parseToJsonElement(r.json).jsonObject
    }

    @Test
    fun aceptaYSellaConReceivedAtMs() {
        val relay = LiveStateRelay()
        val obj = accepted(relay.accept(body(), nowMs = 5000))
        assertEquals("5000", obj["receivedAtMs"]!!.jsonPrimitive.content)
        assertEquals("1", obj["v"]!!.jsonPrimitive.content)
        assertEquals("courts", obj["scene"]!!.jsonPrimitive.content)
        assertEquals("2", obj["scores"]!!.jsonObject[uuidA]!!.jsonArray[1].jsonPrimitive.content)
        assertEquals("60", obj["timer"]!!.jsonObject["totalS"]!!.jsonPrimitive.content)
    }

    @Test
    fun rechazaInvalidos() {
        val relay = LiveStateRelay()
        assertEquals(LiveAcceptResult.Invalid, relay.accept("no es json", 0))
        assertEquals(LiveAcceptResult.Invalid, relay.accept("[]", 0))
        assertEquals(LiveAcceptResult.Invalid, relay.accept("""{"v":1}""", 0))
        assertEquals(LiveAcceptResult.Invalid, relay.accept(body(v = 2), 0))
        assertEquals(LiveAcceptResult.Invalid, relay.accept(body(scores = """{"alumno-ana":[1,0]}"""), 0))
        assertEquals(LiveAcceptResult.Invalid, relay.accept(body(scores = """{"$uuidA":[1000,0]}"""), 0))
        assertEquals(LiveAcceptResult.Invalid, relay.accept(body(scores = """{"$uuidA":[1]}"""), 0))
        assertEquals(LiveAcceptResult.Invalid, relay.accept(body(session = ""), 0))
        assertEquals(LiveAcceptResult.Invalid, relay.accept(body(session = "x".repeat(65)), 0))
        assertEquals(LiveAcceptResult.Invalid, relay.accept(body(seq = -1), 0))
        assertNull(relay.latest(0))
    }

    @Test
    fun rechazaMasDe64Marcadores() {
        val relay = LiveStateRelay()
        fun scores(n: Int) = (0 until n).joinToString(",", "{", "}") {
            "\"00000000-0000-0000-0000-${it.toString().padStart(12, '0')}\":[1,1]"
        }
        assertIs<LiveAcceptResult.Accepted>(relay.accept(body(scores = scores(64)), 0))
        assertEquals(LiveAcceptResult.Invalid, LiveStateRelay().accept(body(scores = scores(65)), 0))
    }

    @Test
    fun descartaCamposFueraDeContrato() {
        val relay = LiveStateRelay()
        val r = relay.accept(body(extra = ""","teamNames":{"a":"Ana García"},"names":["Luis"]"""), 0)
        val obj = accepted(r)
        assertFalse(obj.containsKey("names"))
        assertFalse(obj.containsKey("teamNames"))
        assertFalse((r as LiveAcceptResult.Accepted).json.contains("Ana"))
    }

    @Test
    fun estadoDesconocidoPasaAPausedYEscenaAAuto() {
        val relay = LiveStateRelay()
        val raw = body(status = "volando").replace("\"courts\"", "\"otra\"")
        val obj = accepted(relay.accept(raw, 0))
        assertEquals("paused", obj["status"]!!.jsonPrimitive.content)
        assertEquals("auto", obj["scene"]!!.jsonPrimitive.content)
    }

    @Test
    fun seqViejoOIgualEsStale() {
        val relay = LiveStateRelay()
        assertIs<LiveAcceptResult.Accepted>(relay.accept(body(seq = 5), 0))
        assertEquals(LiveAcceptResult.Stale, relay.accept(body(seq = 5), 1))
        assertEquals(LiveAcceptResult.Stale, relay.accept(body(seq = 4), 1))
        assertIs<LiveAcceptResult.Accepted>(relay.accept(body(seq = 6), 2))
    }

    @Test
    fun sesionNuevaSustituyeAunConSeqMenor() {
        val relay = LiveStateRelay()
        relay.accept(body(session = "a", seq = 50), 0)
        val obj = accepted(relay.accept(body(session = "b", seq = 0), 1))
        assertEquals("b", obj["sessionId"]!!.jsonPrimitive.content)
        assertEquals("b", Json.parseToJsonElement(relay.latest(2)!!).jsonObject["sessionId"]!!.jsonPrimitive.content)
    }

    @Test
    fun latestCaducaA30001Ms() {
        val relay = LiveStateRelay()
        relay.accept(body(status = "ended"), nowMs = 10_000)
        assertNotNull(relay.latest(40_000))
        assertNull(relay.latest(40_001))
    }

    @Test
    fun trasCaducarSeAceptaMismoSeq() {
        val relay = LiveStateRelay()
        relay.accept(body(seq = 3), 0)
        assertIs<LiveAcceptResult.Accepted>(relay.accept(body(seq = 3), 31_000))
    }

    @Test
    fun avisoSseEsUnaSolaLinea() {
        val relay = LiveStateRelay()
        val r = relay.accept(body(), 0) as LiveAcceptResult.Accepted
        val frame = relay.sseFrame(r.json)
        assertTrue(frame.startsWith("data: {"))
        assertTrue(frame.endsWith("}\n\n"))
        assertEquals(1, frame.trimEnd('\n').lines().size)
    }
}
