package com.migestor.commandcenter

import com.migestor.data.di.KmpContainer
import com.migestor.data.platform.createSharedDesktopDriver
import com.migestor.desktop.sync.CommandCenterSnapshot
import com.migestor.desktop.sync.LocalSyncServer
import com.migestor.desktop.sync.SqlDelightSyncAdapter
import com.migestor.shared.sync.SyncCoordinator

fun main(args: Array<String>) {
    println("[command-center] State: starting")

    val options = CommandCenterOptions.parse(args)

    runCatching {
        val driver = createSharedDesktopDriver(
            dbPath = options.databasePath,
            dbName = options.databaseName,
        )
        val container = KmpContainer(driver)
        val adapter = SqlDelightSyncAdapter(container)
        val server = LocalSyncServer(
            syncCoordinator = SyncCoordinator(adapter),
            stateListener = ::emitSnapshotState,
        )
        server.start()

        Runtime.getRuntime().addShutdownHook(
            Thread {
                runCatching { server.stop() }
            },
        )

        while (true) {
            Thread.sleep(60_000)
        }
    }.onFailure { error ->
        println("[command-center] State: failed|${error.message ?: error::class.simpleName ?: "unknown"}")
        throw error
    }
}

private fun emitSnapshotState(snapshot: CommandCenterSnapshot) {
    if (snapshot.networkErrorMessage != null) {
        println("[command-center] State: network_error|${snapshot.networkErrorMessage}")
        return
    }

    val host = snapshot.host ?: return
    println(
        "[command-center] State: running|host=$host|port=${snapshot.port}|pin=${snapshot.pin}|sid=${snapshot.serverId}|fp=${snapshot.fingerprint}"
    )

    if (snapshot.isPaired) {
        val device = snapshot.pairedDeviceId ?: ""
        println("[command-center] State: connected|device=$device")
    }
}

private data class CommandCenterOptions(
    val databasePath: String?,
    val databaseName: String,
) {
    companion object {
        fun parse(args: Array<String>): CommandCenterOptions {
            var dbPath: String? = null
            var index = 0
            while (index < args.size) {
                when (args[index]) {
                    "--db-path" -> {
                        dbPath = args.getOrNull(index + 1)
                        index += 1
                    }
                }
                index += 1
            }

            val normalizedDbPath = dbPath?.trim()?.takeIf { it.isNotEmpty() }
            val databaseName = normalizedDbPath
                ?.substringAfterLast('/')
                ?.substringAfterLast('\\')
                ?.takeIf { it.isNotBlank() }
                ?: "desktop_mi_gestor_kmp.db"
            return CommandCenterOptions(
                databasePath = normalizedDbPath,
                databaseName = databaseName,
            )
        }
    }
}
