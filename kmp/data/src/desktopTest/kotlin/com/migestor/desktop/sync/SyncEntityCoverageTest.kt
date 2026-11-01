package com.migestor.desktop.sync

import com.migestor.data.sync.ModuleRecordsSync
import com.migestor.data.sync.SchoolRecordsSync
import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Cada entidad que la app Apple encola con `enqueueLocalChange(entity: "…")` tiene
 * que saber aplicarse en el Mac (`SqlDelightSyncAdapter`) y en Apple
 * (`KmpBridge+SyncLAN.swift`). Si no, el iPad la da por enviada y se pierde en
 * silencio: pasó con reuniones, acuerdos, medidas de apoyo, tutorías y asignaturas.
 *
 * Lee el código fuente porque el fallo está justo en que nadie mantenía una lista.
 */
class SyncEntityCoverageTest {
    private val kmpRoot: File = generateSequence(File("").absoluteFile) { it.parentFile }
        .first { File(it, "iosApp/App").isDirectory && File(it, "data/src").isDirectory }

    /** Entidades que aún no viajan a propósito. */
    private val pendingEntities = emptySet<String>()

    private fun enqueuedByApple(): Set<String> {
        val pattern = Regex("""enqueueLocalChange\(\s*entity:\s*"([a-z_]+)"""")
        return File(kmpRoot, "iosApp").walkTopDown()
            .filter { it.extension == "swift" }
            .flatMap { file -> pattern.findAll(file.readText()).map { it.groupValues[1] } }
            .toSet()
    }

    private fun appliedByApple(): Set<String> {
        val source = File(kmpRoot, "iosApp/App/Bridge/KmpBridge+SyncLAN.swift").readText()
        val caseLine = Regex("""case\s+("[a-z_]+"(?:\s*,\s*"[a-z_]+")*)\s*:""")
        val literal = Regex(""""([a-z_]+)"""")
        return caseLine.findAll(source)
            .flatMap { match -> literal.findAll(match.groupValues[1]).map { it.groupValues[1] } }
            .toSet() + SchoolRecordsSync.ENTITIES + ModuleRecordsSync.ENTITIES
    }

    private fun appliedByMac(): Set<String> {
        val source = File(kmpRoot, "data/src/commonMain/kotlin/com/migestor/data/sync/SqlDelightSyncAdapter.kt").readText()
        val branch = Regex("""^\s*("[a-z_]+"(?:\s*,\s*"[a-z_]+")*)\s*->""", RegexOption.MULTILINE)
        val literal = Regex(""""([a-z_]+)"""")
        return branch.findAll(source)
            .flatMap { match -> literal.findAll(match.groupValues[1]).map { it.groupValues[1] } }
            .toSet() + SchoolRecordsSync.ENTITIES + ModuleRecordsSync.ENTITIES
    }

    @Test
    fun todoLoQueEncolaLaAppSabeAplicarseEnElMac() {
        val enqueued = enqueuedByApple()
        assertTrue(enqueued.size > 20, "No se encontraron las llamadas a enqueueLocalChange: ¿cambió la ruta?")
        val missing = enqueued - appliedByMac() - pendingEntities
        assertTrue(missing.isEmpty(), "El Mac ignoraría estas entidades: $missing")
    }

    @Test
    fun todoLoQueEncolaLaAppSabeAplicarseEnApple() {
        val missing = enqueuedByApple() - appliedByApple() - pendingEntities
        assertTrue(missing.isEmpty(), "El iPad ignoraría estas entidades: $missing")
    }
}
