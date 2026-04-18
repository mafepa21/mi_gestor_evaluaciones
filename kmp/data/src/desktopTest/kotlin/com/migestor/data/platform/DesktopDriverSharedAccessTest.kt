package com.migestor.data.platform

import app.cash.sqldelight.db.QueryResult
import kotlin.io.path.createTempDirectory
import kotlin.test.Test
import kotlin.test.assertNotNull

class DesktopDriverSharedAccessTest {
    @Test
    fun sharedDriverCanOpenDatabaseWhileExclusiveDriverOwnsLock() {
        val tempDirectory = createTempDirectory("desktop-driver-shared-test").toFile()
        val dbFile = tempDirectory.resolve("shared-lock-test.db")

        val primaryDriver = createDesktopDriver(dbPath = dbFile.absolutePath)
        try {
            val sharedDriver = createSharedDesktopDriver(dbPath = dbFile.absolutePath)
            try {
                val version = sharedDriver.executeQuery(
                    identifier = null,
                    sql = "PRAGMA user_version",
                    mapper = { cursor ->
                        QueryResult.Value(if (cursor.next().value) cursor.getLong(0) else null)
                    },
                    parameters = 0,
                ).value
                assertNotNull(version)
            } finally {
                sharedDriver.close()
            }
        } finally {
            primaryDriver.close()
            releaseDesktopDatabaseLock()
            dbFile.parentFile?.listFiles()?.forEach { file -> file.delete() }
            dbFile.parentFile?.delete()
        }
    }
}
