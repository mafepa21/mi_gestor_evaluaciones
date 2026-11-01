import Foundation
import Network

/// Vigila la red del dispositivo para Sync LAN.
///
/// Al caerse y volver el Wi-Fi, o al cambiar de red, la conexión con el Mac queda
/// muerta y la IP guardada puede no valer. Sin este aviso la app esperaba a que el
/// listener agotara sus reintentos (hasta 30 s) o a que caducara la conexión.
final class LanNetworkMonitor {
    static let shared = LanNetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.migestor.sync.network-monitor")
    private var isStarted = false
    private var lastSignature: String?
    private var onChange: (@MainActor () -> Void)?

    /// Idempotente: la segunda llamada solo cambia a quién se avisa.
    @MainActor
    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            let signature = LanNetworkChange.signature(
                isSatisfied: path.status == .satisfied,
                interfaces: path.availableInterfaces.map { "\($0.name)" },
                gateways: path.gateways.map { "\($0)" }
            )
            let isSatisfied = path.status == .satisfied
            DispatchQueue.main.async {
                guard let self else { return }
                let previous = self.lastSignature
                self.lastSignature = signature
                guard LanNetworkChange.shouldReconnect(previous: previous, current: signature, isSatisfied: isSatisfied) else { return }
                MainActor.assumeIsolated { self.onChange?() }
            }
        }
        monitor.start(queue: queue)
    }
}

/// Reglas del vigilante de red, separadas para poder probarlas.
enum LanNetworkChange {
    /// Estado + interfaces + puertas de enlace: cambia al caer y volver el Wi-Fi y al
    /// pasar a otra red aunque la interfaz sea la misma.
    static func signature(isSatisfied: Bool, interfaces: [String], gateways: [String]) -> String {
        "\(isSatisfied ? "on" : "off")|\(interfaces.sorted().joined(separator: ","))|\(gateways.sorted().joined(separator: ","))"
    }

    /// Solo se reconecta cuando hay red y es distinta de la anterior. La primera lectura
    /// (al arrancar) no cuenta: el arranque ya sincroniza.
    static func shouldReconnect(previous: String?, current: String, isSatisfied: Bool) -> Bool {
        guard isSatisfied, let previous else { return false }
        return previous != current
    }
}
