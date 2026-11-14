import Foundation

/// Lo que el iPad quiere que el Mac vea ahora. Solo ids y números: nunca nombres.
struct TournamentLivePayload: Equatable, Sendable {
    var tournamentId: String
    var status: TournamentLiveStatus
    var roundNumber: Int?
    var timer: TournamentLiveTimer?
    var scene: TournamentLiveScene
    var scores: [String: [Int]]
}

/// Publica el estado del modo competición del iPad en el helper del Mac (`POST /live/state`).
///
/// - Nunca hay más de un envío en vuelo: si llega algo nuevo mientras tanto, al terminar se manda lo último.
/// - `seq` crece en cada envío; un latido cada 5 s mantiene vivo el estado en la proyección.
/// - Usa el enlace de la sync (host, contraseña y huella) sin tocar el bridge ni la base de datos.
/// - Una `URLSession` por sesión, con la huella fijada y 3 s de tiempo máximo por envío.
/// - Que no haya proyección no es un error: solo cambia `connection` (un chip gris).
@MainActor
final class TournamentLivePublisher: ObservableObject {
    /// Empieza en `.notPaired` (sin chip) hasta la primera respuesta del helper: así el chip no
    /// parpadea con «sin proyección» antes de saber nada.
    @Published private(set) var connection: TournamentLiveConnection = .notPaired

    /// Identifica esta vez que se entra al modo directo. Una sesión nueva sustituye a la anterior.
    let sessionId = UUID().uuidString

    private let bridge: KmpBridge?
    private var latest: TournamentLivePayload?
    private var seq: Int64 = 0
    private var inFlight = false
    private var hasNewerThanSent = false
    private var isSuspended = false
    private var isFinished = false
    private var endRequested = false
    private var heartbeat: Task<Void, Never>?
    /// Hasta cuándo no se manda nada (helper sin canal en directo o contraseña distinta).
    private var retryNotBefore: Date = .distantPast
    private var session: URLSession?
    private var sessionFingerprint: String?

    init(bridge: KmpBridge?) {
        self.bridge = bridge
    }

    // MARK: Entrada

    /// Anota el estado actual y lo envía en cuanto se pueda.
    func publish(_ payload: TournamentLivePayload) {
        guard !isFinished else { return }
        latest = payload
        hasNewerThanSent = true
        sendIfPossible(force: false)
    }

    /// El iPad pasa a segundo plano: se para el latido (iOS no deja trabajar a la app).
    func suspend() {
        isSuspended = true
        heartbeat?.cancel()
        heartbeat = nil
    }

    /// Vuelve a primer plano: se reanuda el latido y se envía lo último.
    func resume() {
        guard !isFinished else { return }
        isSuspended = false
        retryNotBefore = .distantPast
        hasNewerThanSent = true
        sendIfPossible(force: true)
    }

    /// Cierra la sesión: manda `ended` una sola vez y no vuelve a enviar nada.
    func end() {
        guard !isFinished, !endRequested else { return }
        endRequested = true
        heartbeat?.cancel()
        heartbeat = nil
        guard latest != nil else {
            finish()
            return
        }
        if inFlight { return } // al terminar el envío en curso se manda `ended`
        sendEnd()
    }

    // MARK: Envío

    private struct Target {
        let url: URL
        let token: String
        let fingerprint: String?
    }

    /// Enlazado pero sin huella del Mac: hay que volver a enlazar para proyectar.
    private var isPairedWithoutFingerprint: Bool {
        guard let bridge, let token = bridge.syncToken, !token.isEmpty,
              let host = bridge.pairedSyncHost, !host.isEmpty else { return false }
        return bridge.pairedServerFingerprint?.isEmpty ?? true
    }

    private func target() -> Target? {
        guard let bridge,
              let rawHost = bridge.pairedSyncHost,
              let token = bridge.syncToken, !token.isEmpty
        else { return nil }
        let host = LanSyncClient.normalizeHost(rawHost)
        guard !host.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.port = 8765
        components.path = "/live/state"
        guard let url = components.url else { return nil }
        // Sin huella del Mac no hay TLS anclado: no se manda el token (se trata como no enlazado).
        guard let fingerprint = bridge.pairedServerFingerprint, !fingerprint.isEmpty else { return nil }
        return Target(url: url, token: token, fingerprint: fingerprint)
    }

    private func sendIfPossible(force: Bool) {
        guard !isFinished, !endRequested, !isSuspended else { return }
        guard let latest else { return }
        guard !inFlight else { return } // lo último se manda al terminar el envío en curso
        guard force || Date() >= retryNotBefore else { return }
        guard let target = target() else {
            connection = isPairedWithoutFingerprint ? .needsRepair : .notPaired
            scheduleHeartbeat(after: TournamentLivePublishOutcome.heartbeatSeconds)
            return
        }
        post(latest, status: latest.status, to: target)
    }

    private func sendEnd() {
        guard var payload = latest, let target = target() else {
            finish()
            return
        }
        payload.status = .ended
        post(payload, status: .ended, to: target)
    }

    private func post(_ payload: TournamentLivePayload, status: TournamentLiveStatus, to target: Target) {
        inFlight = true
        hasNewerThanSent = false
        seq += 1
        let state = TournamentLiveState(
            sessionId: sessionId,
            tournamentId: payload.tournamentId,
            seq: seq,
            sentAtMs: Self.nowMs(),
            status: status,
            roundNumber: payload.roundNumber,
            timer: payload.timer,
            scene: payload.scene,
            scores: payload.scores
        )
        guard let body = try? state.encoded() else {
            inFlight = false
            return
        }
        let urlSession = makeSession(fingerprint: target.fingerprint)
        let isEnding = status == .ended
        Task { [weak self] in
            let response = await Self.send(body: body, to: target.url, token: target.token, using: urlSession)
            self?.didFinishSending(response, wasEnding: isEnding)
        }
    }

    private func didFinishSending(_ response: SendResponse, wasEnding: Bool) {
        inFlight = false
        if wasEnding {
            finish()
            return
        }
        let outcome = TournamentLivePublishOutcome.from(
            statusCode: response.statusCode,
            listeners: response.listeners,
            error: response.error
        )
        connection = outcome.connection
        if outcome.nextSendDelay >= TournamentLivePublishOutcome.backoffSeconds {
            retryNotBefore = Date().addingTimeInterval(outcome.nextSendDelay)
        } else {
            retryNotBefore = .distantPast
        }
        if endRequested {
            sendEnd()
            return
        }
        if hasNewerThanSent, Date() >= retryNotBefore {
            sendIfPossible(force: false)
        } else {
            scheduleHeartbeat(after: outcome.nextSendDelay)
        }
    }

    private func scheduleHeartbeat(after delay: TimeInterval) {
        heartbeat?.cancel()
        guard !isFinished, !endRequested, !isSuspended else { return }
        heartbeat = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.heartbeatFired()
        }
    }

    private func heartbeatFired() {
        // El latido manda el último estado aunque no haya cambiado nada: mantiene vivo el dato.
        hasNewerThanSent = true
        sendIfPossible(force: true)
    }

    private func finish() {
        isFinished = true
        heartbeat?.cancel()
        heartbeat = nil
        session?.finishTasksAndInvalidate()
        session = nil
    }

    private func makeSession(fingerprint: String?) -> URLSession {
        if let session, sessionFingerprint == fingerprint { return session }
        session?.finishTasksAndInvalidate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 3
        configuration.waitsForConnectivity = false
        let created = URLSession(
            configuration: configuration,
            delegate: PinnedTLSDelegate(pinnedFingerprint: fingerprint),
            delegateQueue: nil
        )
        session = created
        sessionFingerprint = fingerprint
        return created
    }

    // MARK: Red (fuera del hilo principal)

    private struct SendResponse: Sendable {
        var statusCode: Int?
        var listeners: Int?
        var error: Error?
    }

    private nonisolated static func send(body: Data, to url: URL, token: String, using session: URLSession) async -> SendResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 3
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return SendResponse(statusCode: nil, listeners: nil, error: URLError(.badServerResponse))
            }
            let listeners = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["listeners"] as? Int
            return SendResponse(statusCode: http.statusCode, listeners: listeners, error: nil)
        } catch {
            return SendResponse(statusCode: nil, listeners: nil, error: error)
        }
    }

    private nonisolated static func nowMs() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }
}
