package com.migestor.desktop.sync

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class BonjourAdvertiserTest {
    private class FakeProcess : Process() {
        var alive = true
        override fun getOutputStream(): OutputStream = ByteArrayOutputStream()
        override fun getInputStream(): InputStream = ByteArrayInputStream(ByteArray(0))
        override fun getErrorStream(): InputStream = ByteArrayInputStream(ByteArray(0))
        override fun waitFor(): Int = 0
        override fun exitValue(): Int = 0
        override fun destroy() { alive = false }
        override fun isAlive(): Boolean = alive
    }

    private val address = InetAddress.getLoopbackAddress()
    private val txt = mapOf("sid" to "mac-1", "proto" to "https", "fp" to "abc", "paired" to "1")

    @Test
    fun registraConElBonjourDelSistemaConElTxtCompleto() {
        val command = NativeDnsSdAdvertiser.commandFor("MiGestorDesktop-mac-1", 8765, txt)
        assertEquals(
            listOf("/usr/bin/dns-sd", "-R", "MiGestorDesktop-mac-1", "_migestor-sync._tcp", "local", "8765",
                "fp=abc", "paired=1", "proto=https", "sid=mac-1"),
            command,
        )
    }

    @Test
    fun noRelanzaSiNadaCambiaPeroSiSiCambiaElTxt() {
        val launched = mutableListOf<FakeProcess>()
        val killed = mutableListOf<String>()
        val advertiser = NativeDnsSdAdvertiser(
            launcher = { FakeProcess().also(launched::add) },
            staleKiller = { killed += it },
        )
        advertiser.publish(address, "MiGestorDesktop-mac-1", 8765, txt)
        advertiser.publish(address, "MiGestorDesktop-mac-1", 8765, txt)
        assertEquals(1, launched.size)
        // Antes de registrar se retira el anuncio que haya dejado un helper anterior.
        assertEquals(listOf("MiGestorDesktop-mac-1"), killed)

        advertiser.publish(address, "MiGestorDesktop-mac-1", 8765, txt + ("paired" to "0"))
        assertEquals(2, launched.size)
        assertTrue(!launched[0].alive)
    }

    @Test
    fun siElAnuncioSeCaeSeVuelveAPublicar() {
        val launched = mutableListOf<FakeProcess>()
        val advertiser = NativeDnsSdAdvertiser(launcher = { FakeProcess().also(launched::add) }, staleKiller = {})
        advertiser.ensurePublished()
        assertEquals(0, launched.size)

        advertiser.publish(address, "MiGestorDesktop-mac-1", 8765, txt)
        launched.single().alive = false
        advertiser.ensurePublished()
        assertEquals(2, launched.size)
        assertTrue(launched[1].alive)

        advertiser.close()
        advertiser.ensurePublished()
        assertEquals(2, launched.size)
    }
}
