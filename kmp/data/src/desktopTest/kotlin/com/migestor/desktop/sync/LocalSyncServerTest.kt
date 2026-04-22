package com.migestor.desktop.sync

import com.migestor.shared.sync.SyncChange
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class LocalSyncServerTest {
    @Test
    fun syncEventPayloadIncludesChangesWithOperationMetadata() {
        val payload = LanSyncJsonCodec.encodeSyncEventPayload(
            serverEpochMs = 1234L,
            entities = listOf("notebook_cell"),
            changes = listOf(
                SyncChange(
                    entity = "notebook_cell",
                    id = "1:2:col",
                    updatedAtEpochMs = 1200L,
                    deviceId = "desktop",
                    payload = """{"value":"9"}""",
                    op = "delete",
                    schemaVersion = 2,
                )
            ),
        )

        val root = Json.parseToJsonElement(payload).jsonObject
        val change = root.getValue("changes").jsonArray.single().jsonObject

        assertEquals("1234", root.getValue("serverEpochMs").jsonPrimitive.content)
        assertEquals("notebook_cell", root.getValue("entities").jsonArray.single().jsonPrimitive.content)
        assertEquals("delete", change.getValue("op").jsonPrimitive.content)
        assertEquals("2", change.getValue("schemaVersion").jsonPrimitive.content)
        assertEquals("""{"value":"9"}""", change.getValue("payload").jsonPrimitive.content)
    }

    @Test
    fun sseFilteringDropsChangesFromPairedIosDevice() {
        val changes = listOf(
            SyncChange("grade", "ios-grade", 10L, "ios-1", "{}"),
            SyncChange("grade", "desktop-grade", 11L, "desktop", "{}"),
        )

        val filtered = filterDesktopChangesForSse(changes, pairedDeviceId = "ios-1")

        assertEquals(listOf("desktop-grade"), filtered.map { it.id })
        assertTrue(filtered.none { it.deviceId == "ios-1" })
    }

    @Test
    fun sseFilteringKeepsDesktopChangesWhenNoDeviceIsPaired() {
        val changes = listOf(
            SyncChange("grade", "ios-grade", 10L, "ios-1", "{}"),
            SyncChange("grade", "desktop-grade", 11L, "desktop", "{}"),
        )

        val filtered = filterDesktopChangesForSse(changes, pairedDeviceId = null)

        assertEquals(changes, filtered)
    }
}
