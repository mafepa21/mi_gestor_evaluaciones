import Foundation

final class SyncEventListener: @unchecked Sendable {
    /// Silencio máximo del canal antes de darlo por muerto (el helper avisa cada 15 s).
    static let idleTimeout: TimeInterval = 35

    private var eventTask: Task<Void, Never>?
    private var currentConnectionKey: String?
    private let stateLock = NSLock()
    private var _isConnected: Bool = false

    var isConnected: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isConnected
    }

    private func setConnected(_ value: Bool) {
        stateLock.lock()
        _isConnected = value
        stateLock.unlock()
    }

    /// Backoff sequence (nanoseconds): 250ms → 500ms → 1s → 2s → 5s → 10s → 30s.
    /// Starts fast so reconnects after pairing are quick, then slows to avoid spam.
    private let backoffSteps: [UInt64] = [
        250_000_000,
        500_000_000,
        1_000_000_000,
        2_000_000_000,
        5_000_000_000,
        10_000_000_000,
        30_000_000_000
    ]

    private struct OpenedStreamError: Error {
        let underlying: Error
    }

    /// El helper rechazó la contraseña. Reintentar enseguida no lo arregla: se
    /// espera el paso más largo del backoff en vez de llamar cada segundo.
    private struct UnauthorizedError: Error {}

    func start(
        host: String,
        token: String,
        pinnedFingerprint: String?,
        onEvent: @escaping @MainActor (LanSyncEvent?) async -> Void
    ) {
        let connectionKey = "\(host)|\(token)|\(pinnedFingerprint ?? "")"
        if currentConnectionKey == connectionKey, eventTask?.isCancelled == false {
            return
        }

        stop()
        currentConnectionKey = connectionKey
        eventTask = Task.detached(priority: .background) { [weak self] in
            await self?.listen(
                host: host,
                token: token,
                pinnedFingerprint: pinnedFingerprint,
                onEvent: onEvent
            )
        }
    }

    func stop() {
        setConnected(false)
        eventTask?.cancel()
        eventTask = nil
        currentConnectionKey = nil
    }

    private func listen(
        host: String,
        token: String,
        pinnedFingerprint: String?,
        onEvent: @escaping @MainActor (LanSyncEvent?) async -> Void
    ) async {
        var backoffIndex = 0
        while !Task.isCancelled {
            do {
                try await openStream(
                    host: host,
                    token: token,
                    pinnedFingerprint: pinnedFingerprint,
                    onEvent: onEvent
                )
                // Stream opened and closed cleanly (server-side reset). Reconnect fast.
                backoffIndex = 0
            } catch is CancellationError {
                return
            } catch is UnauthorizedError {
                print("[Sync:error] listener sin autorización (\(host)); se reintenta más tarde")
                // En el Mac casi siempre significa que en el puerto responde un
                // helper con otra contraseña (p. ej. uno huérfano de una ejecución
                // anterior): el coordinador lo relanza en vez de reintentar sin fin.
                await MainActor.run {
                    NotificationCenter.default.post(name: .syncListenerUnauthorized, object: nil, userInfo: ["host": host])
                }
                backoffIndex = backoffSteps.count - 1
                try? await Task.sleep(nanoseconds: backoffSteps[backoffIndex])
            } catch is OpenedStreamError {
                // Stream was open but then dropped mid-flight. Reconnect fast.
                backoffIndex = 0
                try? await Task.sleep(nanoseconds: backoffSteps[0])
            } catch {
                // Could not connect. Classify as debug if it is a transient startup error
                // (connection refused, no route to host) so the log stays clean while the
                // helper is still launching. Escalate to error only for unexpected failures.
                if isTransientConnectionError(error) {
                    print("[Sync:debug] endpoint not yet available (\(host)): \(error.localizedDescription)")
                } else {
                    print("[Sync:error] listener error (\(host)): \(error.localizedDescription)")
                }
                let delay = backoffSteps[min(backoffIndex, backoffSteps.count - 1)]
                try? await Task.sleep(nanoseconds: delay)
                if backoffIndex < backoffSteps.count - 1 {
                    backoffIndex += 1
                }
            }
        }
    }

    private func openStream(
        host: String,
        token: String,
        pinnedFingerprint: String?,
        onEvent: @escaping @MainActor (LanSyncEvent?) async -> Void
    ) async throws {
        let url = try buildEventsURL(host: host)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // El helper manda «sigo vivo» cada 15 s: 35 s sin nada es una conexión muerta
        // (Wi-Fi caído, Mac dormido) y se reconecta, en vez de esperar un minuto.
        request.timeoutInterval = Self.idleTimeout

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = Self.idleTimeout
        configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
        configuration.waitsForConnectivity = false

        let session = URLSession(
            configuration: configuration,
            delegate: PinnedTLSDelegate(pinnedFingerprint: pinnedFingerprint),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        var didOpenStream = false
        do {
            let (bytes, response) = try await session.bytes(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
                throw UnauthorizedError()
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            didOpenStream = true
            setConnected(true)
            defer { setConnected(false) }

            // Con el canal cortado se pierden avisos: al (re)conectar se sincroniza
            // ya. Así el Mac recién abierto se iguala con el iPad sin esperar.
            await onEvent(nil)

            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard let data = SyncEventLineParser.eventData(from: line) else { continue }
                if let event = decodeSyncEvent(data) {
                    await onEvent(event)
                } else {
                    await onEvent(nil)
                }
            }
        } catch is CancellationError {
            setConnected(false)
            throw CancellationError()
        } catch {
            setConnected(false)
            if didOpenStream {
                throw OpenedStreamError(underlying: error)
            }
            throw error
        }
    }

    private func decodeSyncEvent(_ data: String) -> LanSyncEvent? {
        guard let payload = data.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LanSyncEvent.self, from: payload)
    }

    private func buildEventsURL(host: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        #if os(macOS)
        components.host = "127.0.0.1"
        #else
        components.host = host
        #endif
        components.port = 8765
        components.path = "/sync/events"

        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }

    /// Returns `true` for errors that are expected while the helper is still starting:
    /// connection refused, host unreachable, DNS failure on a local hostname, or timeout.
    private func isTransientConnectionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        let transientCodes: Set<Int> = [
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorCannotFindHost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorTimedOut
        ]
        return transientCodes.contains(nsError.code)
    }
}

/// Lee el flujo SSE línea a línea.
///
/// `URLSession.AsyncBytes.lines` se salta las líneas vacías, que en SSE marcan el
/// final de cada aviso: esperar esa línea dejaba los avisos sin procesar nunca, y
/// como el canal figuraba conectado, la app solo sincronizaba cada 5 minutos. El
/// helper manda cada aviso en una sola línea `data: {json}`, así que se procesa en
/// cuanto llega. Los comentarios (`: keep-alive`) y demás campos se ignoran.
enum SyncEventLineParser {
    static func eventData(from line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        var data = String(line.dropFirst("data:".count))
        if data.first == " " {
            data.removeFirst()
        }
        return data.isEmpty ? nil : data
    }
}

extension Notification.Name {
    /// El servidor de sync rechazó la contraseña del listener SSE.
    static let syncListenerUnauthorized = Notification.Name("syncListenerUnauthorized")
}
