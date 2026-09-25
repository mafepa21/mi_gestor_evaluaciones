package com.migestor.desktop.sync

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class DesktopKeychainCommandTest {
    @Test
    fun elSecretoNoViajaEnLosArgumentosDelLlavero() {
        val secret = "token-que-no-debe-verse"
        val args = DesktopKeychainCommand.addArgs(account = "paired-token", serviceName = "com.migestor.sync.desktop")

        assertEquals("-w", args.last())
        assertFalse(args.contains(secret))
        assertFalse(args.any { it == "-w" && args.getOrNull(args.indexOf("-w") + 1) == secret })
    }
}
