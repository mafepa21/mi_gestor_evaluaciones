package com.migestor.data.platform

import com.migestor.data.db.AppDatabase
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.usePinned
import platform.Foundation.NSTemporaryDirectory
import kotlin.test.Test
import kotlin.test.assertNotNull
import kotlin.test.assertNull

@OptIn(ExperimentalForeignApi::class)
class AdoptionCandidateTest {

    private fun writeFile(name: String, bytes: ByteArray): String {
        val path = NSTemporaryDirectory() + name
        val file = platform.posix.fopen(path, "wb")!!
        if (bytes.isNotEmpty()) {
            bytes.usePinned { platform.posix.fwrite(it.addressOf(0), 1u, bytes.size.toULong(), file) }
        }
        platform.posix.fclose(file)
        return path
    }

    private fun sqliteHeader(userVersion: Long): ByteArray {
        val bytes = ByteArray(4096)
        "SQLite format 3\u0000".encodeToByteArray().copyInto(bytes)
        for (i in 0 until 4) bytes[60 + i] = ((userVersion shr (8 * (3 - i))) and 0xFF).toByte()
        return bytes
    }

    @Test
    fun aceptaUnaBaseDeLaVersionActual() {
        assertNull(adoptionCandidateProblem(writeFile("adopt_ok.db", sqliteHeader(AppDatabase.Schema.version))))
    }

    @Test
    fun rechazaUnArchivoVacio() {
        assertNotNull(adoptionCandidateProblem(writeFile("adopt_vacio.db", ByteArray(0))))
    }

    @Test
    fun rechazaUnaPaginaDeError() {
        val html = "<html><body>500 Internal Server Error</body></html>".padEnd(200).encodeToByteArray()
        assertNotNull(adoptionCandidateProblem(writeFile("adopt_html.db", html)))
    }

    @Test
    fun rechazaUnaBaseDeUnaVersionMasNueva() {
        assertNotNull(adoptionCandidateProblem(writeFile("adopt_nueva.db", sqliteHeader(AppDatabase.Schema.version + 1))))
    }

    @Test
    fun rechazaUnArchivoQueNoExiste() {
        assertNotNull(adoptionCandidateProblem(NSTemporaryDirectory() + "no_existe_adopt.db"))
    }
}
