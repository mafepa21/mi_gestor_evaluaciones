import Foundation
import os

/// Registro de lentitud. Solo apunta lo que supera un límite, para que el registro
/// no se llene. Se ve en la consola de Xcode y en la app Consola de macOS filtrando
/// por subsistema `com.migestor.app` y categoría `rendimiento`
/// (guía: `docs/REGISTRO_RENDIMIENTO.md`). Las marcas de `os_signpost` aparecen en
/// Instruments (plantilla "Logging" o "Time Profiler").
enum PerfLog {
    static let logger = Logger(subsystem: "com.migestor.app", category: "rendimiento")
    static let signposter = OSSignposter(logger: logger)

    /// Por debajo de esto no se apunta nada.
    static let defaultThresholdMs: Double = 150

    @discardableResult
    static func measure<T>(
        _ name: StaticString,
        detail: @autoclosure () -> String = "",
        thresholdMs: Double = defaultThresholdMs,
        _ work: () async throws -> T
    ) async rethrows -> T {
        let state = signposter.beginInterval(name)
        let start = DispatchTime.now()
        defer {
            signposter.endInterval(name, state)
            report(name, start: start, detail: detail(), thresholdMs: thresholdMs)
        }
        return try await work()
    }

    @discardableResult
    static func measureSync<T>(
        _ name: StaticString,
        detail: @autoclosure () -> String = "",
        thresholdMs: Double = defaultThresholdMs,
        _ work: () throws -> T
    ) rethrows -> T {
        let state = signposter.beginInterval(name)
        let start = DispatchTime.now()
        defer {
            signposter.endInterval(name, state)
            report(name, start: start, detail: detail(), thresholdMs: thresholdMs)
        }
        return try work()
    }

    static func elapsedMs(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    /// Para medir dentro de una función con varios `return`:
    /// `let start = DispatchTime.now(); defer { PerfLog.finish("nombre", start: start) }`.
    static func finish(_ name: StaticString, start: DispatchTime, detail: String = "", thresholdMs: Double = defaultThresholdMs) {
        report(name, start: start, detail: detail, thresholdMs: thresholdMs)
    }

    // MARK: Operaciones que empiezan en un sitio y terminan en otro

    @MainActor private static var pendingStarts: [String: DispatchTime] = [:]

    /// Empieza a medir algo que termina en otro punto del código (p. ej. el Cuaderno
    /// pide un grupo y los datos llegan después por su flujo de estado).
    @MainActor
    static func begin(_ key: String) {
        pendingStarts[key] = DispatchTime.now()
    }

    @MainActor
    static func end(_ key: String) {
        guard let start = pendingStarts.removeValue(forKey: key) else { return }
        let ms = elapsedMs(since: start)
        guard ms >= defaultThresholdMs else { return }
        logger.notice("Lento: \(key, privacy: .public) \(Int(ms), privacy: .public) ms")
    }

    private static func report(_ name: StaticString, start: DispatchTime, detail: String, thresholdMs: Double) {
        let ms = elapsedMs(since: start)
        guard ms >= thresholdMs else { return }
        let label = "\(name)"
        logger.notice("Lento: \(label, privacy: .public) \(Int(ms), privacy: .public) ms \(detail, privacy: .public)")
    }

    // MARK: Cambio de pantalla

    /// Mide desde que se elige una pantalla hasta que termina la vuelta del bucle
    /// principal en la que SwiftUI la monta (aproximación al primer pintado).
    @MainActor
    static func markScreenSwitch(to screen: String) {
        let start = DispatchTime.now()
        let state = signposter.beginInterval("Cambio de pantalla")
        DispatchQueue.main.async {
            signposter.endInterval("Cambio de pantalla", state)
            let ms = elapsedMs(since: start)
            guard ms >= defaultThresholdMs else { return }
            logger.notice("Lento: cambio de pantalla a \(screen, privacy: .public) \(Int(ms), privacy: .public) ms")
        }
    }
}

/// Vigila si el hilo de la pantalla deja de responder. Solo en versiones de prueba:
/// un hilo aparte le pide cada 100 ms que responda; si tarda más de 250 ms, apunta
/// cuánto estuvo congelado.
enum MainThreadHangWatchdog {
    private static var started = false
    static let thresholdMs: Double = 250

    @MainActor
    static func startIfDebug() {
        #if DEBUG
        guard !started else { return }
        started = true
        let thread = Thread {
            while true {
                let start = DispatchTime.now()
                let answered = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { answered.signal() }
                if answered.wait(timeout: .now() + .milliseconds(Int(thresholdMs))) == .timedOut {
                    answered.wait()
                    let ms = PerfLog.elapsedMs(since: start)
                    PerfLog.logger.error("Pantalla congelada \(Int(ms), privacy: .public) ms")
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        thread.name = "MainThreadHangWatchdog"
        thread.qualityOfService = .utility
        thread.start()
        #endif
    }
}
