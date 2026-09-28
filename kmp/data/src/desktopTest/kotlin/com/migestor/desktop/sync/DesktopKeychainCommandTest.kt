package com.migestor.desktop.sync

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DesktopKeychainCommandTest {
    @Test
    fun elSecretoNoViajaEnTextoPlanoConOpcionW() {
        val secret = "token-que-no-debe-verse"
        val args = DesktopKeychainCommand.addArgs(
            account = "paired-token",
            serviceName = "com.migestor.sync.desktop",
            value = secret
        )

        val hexSecret = secret.toByteArray(Charsets.UTF_8).joinToString("") { "%02x".format(it) }
        assertTrue(args.contains("-X"))
        assertEquals(hexSecret, args.getOrNull(args.indexOf("-X") + 1))
        assertFalse(args.contains(secret))
        assertFalse(args.contains("-w"))
    }
}
