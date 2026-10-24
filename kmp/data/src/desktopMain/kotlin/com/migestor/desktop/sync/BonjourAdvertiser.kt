package com.migestor.desktop.sync

import java.io.File
import java.net.InetAddress
import java.util.concurrent.TimeUnit
import javax.jmdns.JmDNS
import javax.jmdns.ServiceInfo

/**
 * Anuncio Bonjour del helper (`_migestor-sync._tcp`), con el que el iPad encuentra
 * al Mac aunque cambie de IP.
 */
internal interface BonjourAdvertiser {
    /** Publica o actualiza el servicio. `address` solo lo usa JmDNS (una interfaz). */
    fun publish(address: InetAddress, instanceName: String, port: Int, txt: Map<String, String>)

    /** Vuelve a publicar si el anuncio se cayó. Se llama en cada vuelta del monitor de red. */
    fun ensurePublished()

    fun close()

    companion object {
        fun create(): BonjourAdvertiser =
            if (NativeDnsSdAdvertiser.isAvailable()) NativeDnsSdAdvertiser() else JmDnsAdvertiser()
    }
}

/**
 * macOS: registra el servicio con `dns-sd -R`, es decir, con el mDNSResponder del
 * sistema. Este lo anuncia en todas las interfaces y lo vuelve a anunciar solo al
 * cambiar de Wi-Fi o al despertar el Mac. Con JmDNS el anuncio quedaba atado a la
 * interfaz y la IP del arranque: si el Wi-Fi se caía y volvía con la misma IP, el
 * iPad dejaba de ver al Mac.
 */
internal class NativeDnsSdAdvertiser(
    private val launcher: (List<String>) -> Process = ::launch,
    private val staleKiller: (String) -> Unit = ::killStaleRegistrations,
) : BonjourAdvertiser {
    private var process: Process? = null
    private var publishedCommand: List<String>? = null

    @Synchronized
    override fun publish(address: InetAddress, instanceName: String, port: Int, txt: Map<String, String>) {
        val command = commandFor(instanceName, port, txt)
        if (command == publishedCommand && process?.isAlive == true) return
        close()
        // Un helper terminado a la fuerza deja su `dns-sd` vivo y el nombre ocupado.
        staleKiller(instanceName)
        process = launcher(command)
        publishedCommand = command
    }

    @Synchronized
    override fun ensurePublished() {
        val command = publishedCommand ?: return
        if (process?.isAlive == true) return
        process = launcher(command)
    }

    @Synchronized
    override fun close() {
        process?.let { running ->
            running.destroy()
            if (!running.waitFor(1, TimeUnit.SECONDS)) running.destroyForcibly()
        }
        process = null
        publishedCommand = null
    }

    companion object {
        const val DNS_SD = "/usr/bin/dns-sd"
        const val SERVICE_TYPE = "_migestor-sync._tcp"

        fun isAvailable(): Boolean =
            System.getProperty("os.name").orEmpty().lowercase().contains("mac") && File(DNS_SD).canExecute()

        fun commandFor(instanceName: String, port: Int, txt: Map<String, String>): List<String> =
            listOf(DNS_SD, "-R", instanceName, SERVICE_TYPE, "local", port.toString()) +
                txt.toSortedMap().map { (key, value) -> "$key=$value" }

        private fun launch(command: List<String>): Process =
            ProcessBuilder(command)
                .redirectErrorStream(true)
                .redirectOutput(ProcessBuilder.Redirect.DISCARD)
                .start()

        private fun killStaleRegistrations(instanceName: String) {
            runCatching {
                ProcessBuilder("/usr/bin/pkill", "-f", "dns-sd -R $instanceName ")
                    .redirectErrorStream(true)
                    .redirectOutput(ProcessBuilder.Redirect.DISCARD)
                    .start()
                    .waitFor(2, TimeUnit.SECONDS)
            }
        }
    }
}

/** Resto de sistemas (y respaldo): JmDNS ligado a la interfaz LAN actual. */
internal class JmDnsAdvertiser : BonjourAdvertiser {
    private var jmDns: JmDNS? = null
    private var serviceInfo: ServiceInfo? = null
    private var boundAddress: InetAddress? = null

    @Synchronized
    override fun publish(address: InetAddress, instanceName: String, port: Int, txt: Map<String, String>) {
        if (address != boundAddress) {
            close()
            jmDns = JmDNS.create(address)
            boundAddress = address
        } else {
            serviceInfo?.let { jmDns?.unregisterService(it) }
        }
        serviceInfo = ServiceInfo.create("$NativeServiceType.local.", instanceName, port, 0, 0, txt)
        serviceInfo?.let { jmDns?.registerService(it) }
    }

    override fun ensurePublished() = Unit

    @Synchronized
    override fun close() {
        serviceInfo?.let { runCatching { jmDns?.unregisterService(it) } }
        serviceInfo = null
        runCatching { jmDns?.close() }
        jmDns = null
        boundAddress = null
    }

    private companion object {
        const val NativeServiceType = NativeDnsSdAdvertiser.SERVICE_TYPE
    }
}
