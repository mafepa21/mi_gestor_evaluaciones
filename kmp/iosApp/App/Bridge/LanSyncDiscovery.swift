import Foundation

final class LanSyncDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    var onPeersChanged: (([LanDiscoveredPeer]) -> Void)?
    private(set) var lastRestartAt: Date = .distantPast

    func start() {
        browser.delegate = self
        browser.searchForServices(ofType: "_migestor-sync._tcp.", inDomain: "local.")
    }

    /// Vuelve a buscar desde cero. Tras un cambio de Wi-Fi o al volver de segundo plano
    /// el navegador de Bonjour puede quedarse con resultados viejos o sin buscar.
    func restart() {
        lastRestartAt = Date()
        browser.stop()
        services.forEach { $0.stop() }
        services.removeAll()
        start()
    }

    /// iOS rechaza la búsqueda (p. ej. sin permiso de red local todavía): se reintenta.
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        print("[Sync:debug] Bonjour no pudo buscar: \(errorDict)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.restart()
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        if let existingIndex = services.firstIndex(where: { existing in
            existing.name == service.name && existing.type == service.type && existing.domain == service.domain
        }) {
            services[existingIndex] = service
        } else {
            services.append(service)
        }
        service.resolve(withTimeout: 3)
        if !moreComing {
            emitHosts()
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0.name == service.name }
        if !moreComing {
            emitHosts()
        }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        emitHosts()
    }

    private func emitHosts() {
        let peers = services.compactMap { service -> LanDiscoveredPeer? in
            guard let raw = service.hostName else { return nil }
            let host = raw.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let txtData = service.txtRecordData() ?? Data()
            let txt = NetService.dictionary(fromTXTRecord: txtData)
            let sid = txt["sid"].flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let fp = txt["fp"].flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let proto = txt["proto"].flatMap { String(data: $0, encoding: .utf8) } ?? "https"
            return LanDiscoveredPeer(host: host, serverId: sid, fingerprint: fp, scheme: proto)
        }
        let unique = KmpBridge.deduplicateDiscoveredPeers(peers)
        onPeersChanged?(unique.sorted { $0.host < $1.host })
    }
}
