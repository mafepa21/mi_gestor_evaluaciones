import Foundation

final class SyncEventListener {
    private var eventTask: Task<Void, Never>?
    private var currentConnectionKey: String?

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
        eventTask = Task { [weak self] in
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
        while !Task.isCancelled {
            do {
                try await openStream(
                    host: host,
                    token: token,
                    pinnedFingerprint: pinnedFingerprint,
                    onEvent: onEvent
                )
            } catch is CancellationError {
                return
            } catch {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
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
        request.timeoutInterval = 20

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
        configuration.waitsForConnectivity = false

        let session = URLSession(
            configuration: configuration,
            delegate: PinnedTLSDelegate(pinnedFingerprint: pinnedFingerprint),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

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
        components.host = host
        components.port = 8765
        components.path = "/sync/events"

        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }
}
