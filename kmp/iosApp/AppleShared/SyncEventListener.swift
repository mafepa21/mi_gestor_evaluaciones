import Foundation

final class SyncEventListener {
    private var eventTask: Task<Void, Never>?
    private var currentConnectionKey: String?

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
        request.timeoutInterval = 60

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
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
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            didOpenStream = true

            var frameLines: [String] = []
            for try await line in bytes.lines {
                try Task.checkCancellation()
                if line.isEmpty {
                    if let event = parseSyncEvent(from: frameLines) {
                        await onEvent(event)
                    } else if frameLines.contains(where: { $0.hasPrefix("data:") }) {
                        await onEvent(nil)
                    }
                    frameLines.removeAll(keepingCapacity: true)
                } else {
                    frameLines.append(line)
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if didOpenStream {
                throw OpenedStreamError(underlying: error)
            }
            throw error
        }
    }

    private func parseSyncEvent(from lines: [String]) -> LanSyncEvent? {
        let dataLines = lines.compactMap { line -> String? in
            guard line.hasPrefix("data:") else { return nil }
            var data = String(line.dropFirst("data:".count))
            if data.first == " " {
                data.removeFirst()
            }
            return data
        }

        guard !dataLines.isEmpty else { return nil }
        let data = dataLines.joined(separator: "\n")
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
