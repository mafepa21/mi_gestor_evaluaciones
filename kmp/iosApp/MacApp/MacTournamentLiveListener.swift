import Foundation
import SwiftUI

/// Escucha el canal en directo de torneos del helper (`GET /live/events`, solo por loopback) y
/// se lo da a las ventanas de proyección. También decide cuándo se abre la proyección sola.
///
/// - Arranca con `.syncHelperBecameReady` (o al crearse, si el helper ya tiene contraseña) y para
///   con `.syncHelperStopped`. La contraseña local se lee en CADA intento: cambia en cada arranque
///   del helper.
/// - Es independiente de `SyncEventListener`: un 401/404 aquí NO publica `.syncListenerUnauthorized`
///   (el coordinador relanzaría el helper). 404 = helper antiguo sin canal en directo; 401 = otra
///   contraseña. Ambos se reintentan cada 30 s sin avisar.
/// - Los avisos llegan en una sola línea `data:` (`SyncEventLineParser`).
@MainActor
final class MacTournamentLiveListener: ObservableObject {
    /// Último estado válido recibido (puede ser de un torneo o de otro: cada ventana filtra por el suyo).
    @Published private(set) var latestState: TournamentLiveState?
    @Published private(set) var clock = TournamentLiveClock()
    /// `true` si hace más de 12 s que no llega nada. Se recalcula cada segundo.
    @Published private(set) var isStale = false
    /// Torneo cuya proyección hay que abrir ahora. Lo consume la ventana principal.
    @Published private(set) var pendingOpenTournamentId: String?

    /// Reintentos tras un fallo de red (segundos).
    nonisolated static let retrySteps: [TimeInterval] = [0.5, 1, 2, 5]
    /// Reintento cuando el helper no ofrece el canal o rechaza la contraseña.
    nonisolated static let noChannelRetrySeconds: TimeInterval = 30
    /// Cuánto se espera a que aparezca una ventana pedida antes de volver a pedirla.
    private static let awaitingWindowSeconds: TimeInterval = 10

    private var loopTask: Task<Void, Never>?
    private var staleTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    /// Ventanas abiertas: id de torneo -> `true` si se abrió sola.
    private var openWindows: [String: Bool] = [:]
    /// Ventanas pedidas pero aún no abiertas.
    private var awaitingWindow: [String: Date] = [:]
    /// Cierres que ordenó la política (no cuentan como «cerrada a mano»).
    private var closingByPolicy: Set<String> = []
    /// Sesiones que el docente cerró a mano: no se reabren solas.
    private var closedByHandSessions: [String] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .syncHelperBecameReady, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.start() }
        })
        observers.append(center.addObserver(forName: .syncHelperStopped, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        })
        if MacCommandCenterCoordinator.helperLocalToken != nil { start() }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: Ciclo de vida

    func start() {
        stop()
        loopTask = Task.detached(priority: .utility) { [weak self] in
            await Self.runLoop { state in await self?.receive(state) }
        }
        staleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.refreshStale()
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        staleTask?.cancel()
        staleTask = nil
    }

    // MARK: Estado en directo

    func receive(_ state: TournamentLiveState) {
        if let current = latestState, current.sessionId == state.sessionId, state.seq <= current.seq { return }
        // Otra sesión puede venir de otro iPad: el desfase de relojes anterior ya no vale.
        if latestState?.sessionId != state.sessionId { clock = TournamentLiveClock() }
        clock.observe(state)
        latestState = state
        refreshStale()
        evaluateOpening(for: state)
    }

    /// Lo que pinta la ventana de `tournamentID`; `nil` si aún no ha llegado nada.
    func projection(for tournamentID: String) -> TournamentLiveProjection? {
        guard let latestState else { return nil }
        return TournamentLiveProjection(tournamentID: tournamentID, state: latestState, clock: clock, isStale: isStale)
    }

    private func refreshStale() {
        let stale = latestState.map { TournamentLiveFreshness.isStale($0, nowMs: Self.nowMs()) } ?? false
        if stale != isStale { isStale = stale }
        if stale || latestState?.status == .ended, pendingOpenTournamentId != nil {
            pendingOpenTournamentId = nil
        }
    }

    // MARK: Ventanas

    private func evaluateOpening(for state: TournamentLiveState) {
        let now = Date()
        awaitingWindow = awaitingWindow.filter { now.timeIntervalSince($0.value) < Self.awaitingWindowSeconds }
        let hasWindow = openWindows[state.tournamentId] != nil || awaitingWindow[state.tournamentId] != nil
        guard TournamentLiveProjectionPolicy.shouldOpen(
            state: state,
            isStale: isStale,
            hasWindow: hasWindow,
            closedByHandSessions: Set(closedByHandSessions)
        ) else { return }
        if pendingOpenTournamentId != state.tournamentId {
            pendingOpenTournamentId = state.tournamentId
        }
    }

    /// La ventana principal ya ha pedido abrir la proyección: se espera a que aparezca.
    func consumeOpenRequest() {
        guard let id = pendingOpenTournamentId else { return }
        awaitingWindow[id] = Date()
        pendingOpenTournamentId = nil
    }

    func windowOpened(tournamentID: String) {
        let automatic = awaitingWindow.removeValue(forKey: tournamentID) != nil
        openWindows[tournamentID] = automatic
    }

    func windowClosed(tournamentID: String) {
        openWindows.removeValue(forKey: tournamentID)
        if closingByPolicy.remove(tournamentID) != nil { return }
        // Cerrada por el docente: esa sesión no se vuelve a abrir sola.
        if let state = latestState, state.tournamentId == tournamentID, state.status != .ended,
           !closedByHandSessions.contains(state.sessionId) {
            closedByHandSessions.append(state.sessionId)
            if closedByHandSessions.count > 50 { closedByHandSessions.removeFirst() }
        }
    }

    func wasOpenedAutomatically(tournamentID: String) -> Bool {
        openWindows[tournamentID] ?? false
    }

    /// Avisa de que la siguiente baja de esta ventana la ordena la política, no el docente.
    func willCloseByPolicy(tournamentID: String) {
        closingByPolicy.insert(tournamentID)
    }

    // MARK: Red (fuera del hilo principal)

    private enum StreamEnd {
        /// El canal estuvo abierto y se cortó: reconectar enseguida.
        case closedAfterOpening
        /// Helper antiguo (404), contraseña distinta (401/403) o sin contraseña: sin avisar.
        case noChannel
        case failed
    }

    private nonisolated static func nowMs() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }

    private nonisolated static func runLoop(onState: @escaping @Sendable (TournamentLiveState) async -> Void) async {
        var failures = 0
        while !Task.isCancelled {
            let token = await MainActor.run { MacCommandCenterCoordinator.helperLocalToken }
            guard let token, !token.isEmpty else {
                try? await Task.sleep(nanoseconds: UInt64(noChannelRetrySeconds / 6 * 1_000_000_000))
                continue
            }
            let end = await readStream(token: token, onState: onState)
            let delay: TimeInterval
            switch end {
            case .closedAfterOpening:
                failures = 0
                delay = retrySteps[0]
            case .noChannel:
                delay = noChannelRetrySeconds
            case .failed:
                delay = retrySteps[min(failures, retrySteps.count - 1)]
                failures += 1
            }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    private nonisolated static func readStream(
        token: String,
        onState: @Sendable (TournamentLiveState) async -> Void
    ) async -> StreamEnd {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "127.0.0.1"
        components.port = 8765
        components.path = "/live/events"
        guard let url = components.url else { return .failed }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // El helper manda «sigo vivo» cada 15 s: 35 s sin nada es una conexión muerta.
        request.timeoutInterval = SyncEventListener.idleTimeout

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = SyncEventListener.idleTimeout
        configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
        configuration.waitsForConnectivity = false
        // Siempre es el helper del propio Mac por loopback (certificado propio, sin huella que fijar).
        let session = URLSession(configuration: configuration, delegate: PinnedTLSDelegate(pinnedFingerprint: nil), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var didOpen = false
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed }
            if [401, 403, 404].contains(http.statusCode) { return .noChannel }
            guard (200..<300).contains(http.statusCode) else { return .failed }
            didOpen = true
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard let data = SyncEventLineParser.eventData(from: line)?.data(using: .utf8),
                      let state = TournamentLiveState.decode(data)
                else { continue }
                await onState(state)
            }
            return .closedAfterOpening
        } catch is CancellationError {
            return .failed
        } catch {
            return didOpen ? .closedAfterOpening : .failed
        }
    }
}
