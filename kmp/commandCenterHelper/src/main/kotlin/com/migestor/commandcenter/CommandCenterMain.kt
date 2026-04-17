package com.migestor.commandcenter

import com.migestor.data.di.KmpContainer
import com.migestor.data.platform.createDesktopDriver
import com.migestor.data.platform.releaseDesktopDatabaseLock
import com.migestor.desktop.sync.LocalSyncServer
import com.migestor.desktop.sync.SqlDelightSyncAdapter
import com.migestor.shared.sync.SyncCoordinator

fun main() {
    println("[command-center] Starting macOS command center...")
    val driver = createDesktopDriver("desktop_mi_gestor_kmp.db")
    val container = KmpContainer(driver)
    val adapter = SqlDelightSyncAdapter(container)
    val server = LocalSyncServer(syncCoordinator = SyncCoordinator(adapter))
    server.start()

    println("[command-center] Server ready at ${server.currentHostHint()}:8765")
    println("[command-center] Pairing payload: ${server.currentPairingPayload()}")

    Runtime.getRuntime().addShutdownHook(
        Thread {
            runCatching { server.stop() }
            runCatching { releaseDesktopDatabaseLock() }
        },
    )

    while (true) {
        Thread.sleep(60_000)
    }
}
