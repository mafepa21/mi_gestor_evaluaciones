import Foundation

// Canal en directo de un torneo (iPad -> helper -> Mac), como lógica pura: sin red ni vistas.
//
// El iPad publica un estado pequeño (ronda, reloj, marcadores provisionales) y el Mac lo pinta en
// la proyección. El estado SOLO lleva ids (de torneo, de partido): ningún nombre de equipo ni de
// alumno sale del iPad. Contrato v1 (lo valida también el helper, `LiveStateRelay.kt`):
//   v, sessionId, tournamentId, seq, sentAtMs, [receivedAtMs lo añade el helper], status,
//   roundNumber?, timer?{endAtMs?, pausedRemainingS?, totalS}, scene, scores{<uuid partido>:[local, visitante]}.
// Nada de esto se guarda nunca en el plan: es provisional hasta que el iPad guarda y la sync llega.

// MARK: - Estado

enum TournamentLiveStatus: String, Codable, Equatable, Sendable {
    case running
    case paused
    case timeUp
    case ended

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // Un valor que esta versión no conoce se trata como «en pausa» (no inventa un reloj).
        self = TournamentLiveStatus(rawValue: raw) ?? .paused
    }
}

/// Escena que el docente fuerza desde el iPad. `auto` deja la rotación normal.
enum TournamentLiveScene: String, Codable, Equatable, Sendable, CaseIterable {
    case auto
    case courts
    case standings
    case bracket

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TournamentLiveScene(rawValue: raw) ?? .auto
    }
}

struct TournamentLiveTimer: Codable, Equatable, Sendable {
    /// Instante de fin (ms, reloj del iPad) si el reloj corre.
    var endAtMs: Int64?
    /// Segundos que quedaban al pausar.
    var pausedRemainingS: Int?
    var totalS: Int
}

struct TournamentLiveState: Codable, Equatable, Sendable {
    static let currentVersion = 1
    /// Más marcadores que estos hacen inválido el estado (lo mismo exige el helper).
    static let maxScores = 64

    var v: Int
    var sessionId: String
    var tournamentId: String
    var seq: Int64
    var sentAtMs: Int64
    /// Lo añade el helper al recibirlo (reloj del Mac). El iPad no lo envía.
    var receivedAtMs: Int64?
    var status: TournamentLiveStatus
    var roundNumber: Int?
    var timer: TournamentLiveTimer?
    var scene: TournamentLiveScene
    /// `[idPartido: [local, visitante]]`.
    var scores: [String: [Int]]

    init(
        v: Int = TournamentLiveState.currentVersion,
        sessionId: String,
        tournamentId: String,
        seq: Int64,
        sentAtMs: Int64,
        receivedAtMs: Int64? = nil,
        status: TournamentLiveStatus,
        roundNumber: Int? = nil,
        timer: TournamentLiveTimer? = nil,
        scene: TournamentLiveScene = .auto,
        scores: [String: [Int]] = [:]
    ) {
        self.v = v
        self.sessionId = sessionId
        self.tournamentId = tournamentId
        self.seq = seq
        self.sentAtMs = sentAtMs
        self.receivedAtMs = receivedAtMs
        self.status = status
        self.roundNumber = roundNumber
        self.timer = timer
        self.scene = scene
        self.scores = scores
    }

    /// Codificación estable (claves ordenadas) para enviar al helper.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) -> TournamentLiveState? {
        guard let state = try? JSONDecoder().decode(TournamentLiveState.self, from: data),
              state.v == currentVersion
        else { return nil }
        return state
    }

    /// Instante (ms, reloj del Mac) en que llegó. Sin él, el de envío.
    var arrivalMs: Int64 { receivedAtMs ?? sentAtMs }
}

// MARK: - Reloj

/// Calcula los segundos que quedan sin depender de que los relojes del iPad y del Mac coincidan.
/// El desfase es el MÍNIMO de `receivedAtMs − sentAtMs` de las últimas 12 muestras: incluye la
/// diferencia entre relojes más la latencia, y el mínimo se queda con la muestra más rápida.
struct TournamentLiveClock: Equatable, Sendable {
    static let maxSamples = 12
    /// Desfase máximo creíble entre relojes (24 h); más allá se ignora la muestra.
    static let maxOffsetMs: Int64 = 24 * 60 * 60 * 1000

    private(set) var offsets: [Int64] = []

    init() {}

    /// Anota el desfase de un estado recién llegado (si trae `receivedAtMs`).
    mutating func observe(_ state: TournamentLiveState) {
        guard let received = state.receivedAtMs else { return }
        // Resta segura: un valor extremo nunca debe cerrar la app del Mac.
        let (offset, overflow) = received.subtractingReportingOverflow(state.sentAtMs)
        guard !overflow, abs(offset) <= Self.maxOffsetMs else { return }
        offsets.append(offset)
        if offsets.count > Self.maxSamples {
            offsets.removeFirst(offsets.count - Self.maxSamples)
        }
    }

    var offsetMs: Int64 { offsets.min() ?? 0 }

    /// Segundos que quedan según el estado, o `nil` si no hay reloj.
    func remainingSeconds(of state: TournamentLiveState, nowMs: Int64) -> Int? {
        guard let timer = state.timer else { return nil }
        if state.status == .timeUp { return 0 }
        if state.status == .running, let end = timer.endAtMs {
            let (shifted, o1) = end.addingReportingOverflow(offsetMs)
            let (diff, o2) = shifted.subtractingReportingOverflow(nowMs)
            guard !o1, !o2 else { return 0 }
            if diff <= 0 { return 0 }
            return Int((min(diff, Self.maxOffsetMs) + 999) / 1000)
        }
        return max(0, timer.pausedRemainingS ?? timer.totalS)
    }
}

// MARK: - Frescura

enum TournamentLiveFreshness {
    /// Sin estado nuevo durante más de esto (el iPad manda un latido cada 5 s) el dato es viejo.
    static let staleAfterMs: Int64 = 12_000

    static func isStale(receivedAtMs: Int64, nowMs: Int64) -> Bool {
        nowMs - receivedAtMs > staleAfterMs
    }

    static func isStale(_ state: TournamentLiveState, nowMs: Int64) -> Bool {
        isStale(receivedAtMs: state.arrivalMs, nowMs: nowMs)
    }
}

// MARK: - Marcadores provisionales

enum TournamentLiveOverlay {
    /// Copia del plan con los marcadores provisionales del estado en directo. No toca el plan
    /// recibido. Solo se aplica si el estado es del mismo torneo, es reciente y (salvo que se
    /// pida `allowEnded`) no es el de cierre. Los ids de partido que el plan no conoce se ignoran.
    static func apply(
        _ state: TournamentLiveState,
        to plan: TournamentPlan,
        tournamentID: String,
        isStale: Bool,
        allowEnded: Bool = false
    ) -> TournamentPlan {
        guard state.tournamentId == tournamentID, !isStale, allowEnded || state.status != .ended else {
            return plan
        }
        var copy = plan
        let initial = plan.slots
        let known = Dictionary(initial.map { ($0.id.uuidString.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        // Por ronda y pista: un cruce de eliminatoria se resuelve con los resultados anteriores.
        let ordered = state.scores.keys
            .compactMap { key in known[key.lowercased()].map { (key, $0) } }
            .sorted { ($0.1.roundNumber, $0.1.venueNumber) < ($1.1.roundNumber, $1.1.venueNumber) }
        for (key, firstSlot) in ordered {
            guard let pair = state.scores[key], pair.count == 2 else { continue }
            let home = min(max(pair[0], 0), 999)
            let away = min(max(pair[1], 0), 999)
            // Se vuelve a buscar el partido: tras un marcador anterior sus equipos pueden haberse resuelto.
            guard let slot = copy.slots.first(where: { $0.id == firstSlot.id }) else { continue }
            if let current = copy.result(for: slot), current.homeScore == home, current.awayScore == away { continue }
            copy.setScore(for: slot, home: home, away: away)
        }
        return copy
    }
}

// MARK: - Lo que lleva la proyección

/// Pistas del iPad para elegir las escenas: se aplican sobre lo que decide `TournamentProjectionModel`.
struct ProjectionLiveHints: Equatable, Sendable {
    /// Número de ronda del iPad. Solo sustituye la ronda de liga deducida; en cuadro se ignora (v1).
    var roundNumber: Int?
    var scene: TournamentLiveScene

    init(roundNumber: Int? = nil, scene: TournamentLiveScene = .auto) {
        self.roundNumber = roundNumber
        self.scene = scene
    }
}

/// Todo lo que la proyección de UN torneo necesita del canal en directo.
struct TournamentLiveProjection: Equatable, Sendable {
    /// Id del torneo de la ventana (el del registro, el mismo que lleva `tournamentId` del estado).
    var tournamentID: String
    var state: TournamentLiveState
    var clock: TournamentLiveClock
    /// `true` si hace más de 12 s que no llega nada (lo calcula el escuchador cada segundo).
    var isStale: Bool

    init(tournamentID: String, state: TournamentLiveState, clock: TournamentLiveClock, isStale: Bool) {
        self.tournamentID = tournamentID
        self.state = state
        self.clock = clock
        self.isStale = isStale
    }

    var isForThisTournament: Bool { state.tournamentId == tournamentID }

    /// Pistas de ronda y escena: valen con el estado viejo (última foto), no con el de cierre.
    var hints: ProjectionLiveHints? {
        guard isForThisTournament, state.status != .ended else { return nil }
        return ProjectionLiveHints(roundNumber: state.roundNumber, scene: state.scene)
    }

    /// Plan con los marcadores provisionales (solo si el estado es reciente y no es el de cierre).
    func plan(overlaying plan: TournamentPlan) -> TournamentPlan {
        TournamentLiveOverlay.apply(state, to: plan, tournamentID: tournamentID, isStale: isStale)
    }

    /// El reloj solo se enseña con el torneo en directo (no con el de cierre).
    var showsClock: Bool {
        isForThisTournament && state.status != .ended && state.timer != nil
    }

    /// El aviso de «sin conexión» solo tiene sentido con una sesión sin cerrar.
    var showsOfflineNotice: Bool {
        isStale && isForThisTournament && state.status != .ended
    }
}

/// Textos que la proyección pinta por el canal en directo. Ninguno lleva nombres.
enum ProjectionLiveTexts {
    static let timeUp = "¡Tiempo!"
    static let paused = "En pausa"

    /// Textos fijos, para que la prueba de nombres los cubra junto al resto de la proyección.
    static let fixedTexts = [timeUp, paused, offlineNotice(atMs: 0, timeZone: TimeZone(secondsFromGMT: 0)!)]

    static func clock(seconds: Int) -> String {
        let value = max(0, seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    /// «Sin conexión con el iPad · datos de las 10:32».
    static func offlineNotice(atMs: Int64, timeZone: TimeZone = .current) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(atMs) / 1000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let text = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        return "Sin conexión con el iPad · datos de las \(text)"
    }
}

// MARK: - Publicar desde el iPad

/// Estado del canal visto desde el iPad (el chip del modo directo).
enum TournamentLiveConnection: Equatable, Sendable {
    /// El iPad no está enlazado con un Mac: no hay chip.
    case notPaired
    /// El helper recibe, pero ninguna ventana de proyección escucha (o no hay helper nuevo).
    case noProjection
    case projecting
}

/// Qué significa la respuesta (o el fallo) de un envío y cuándo conviene el siguiente.
struct TournamentLivePublishOutcome: Equatable, Sendable {
    /// Latido normal del iPad mientras todo va bien.
    static let heartbeatSeconds: TimeInterval = 5
    /// Cada cuánto se reintenta si el helper responde 404 (versión antigua) o 401.
    static let backoffSeconds: TimeInterval = 30

    var connection: TournamentLiveConnection
    var nextSendDelay: TimeInterval

    static func from(statusCode: Int?, listeners: Int?, error: Error?) -> TournamentLivePublishOutcome {
        if error != nil || statusCode == nil {
            return TournamentLivePublishOutcome(connection: .noProjection, nextSendDelay: heartbeatSeconds)
        }
        switch statusCode {
        case 200:
            return TournamentLivePublishOutcome(
                connection: (listeners ?? 0) > 0 ? .projecting : .noProjection,
                nextSendDelay: heartbeatSeconds
            )
        default:
            // 404 (helper sin canal en directo), 401 (contraseña distinta), 400/413/5xx: sin proyección.
            return TournamentLivePublishOutcome(connection: .noProjection, nextSendDelay: backoffSeconds)
        }
    }
}

// MARK: - Abrir y cerrar la ventana del Mac

/// Qué hacer con una ventana de proyección abierta sola cuando cambia el estado en directo.
enum TournamentLiveWindowAction: Equatable, Sendable {
    case keepOpen
    case closeNow
    /// Se queda enseñando el podio y se cierra pasados estos segundos.
    case closeAfter(TimeInterval)
}

enum TournamentLiveProjectionPolicy {
    /// Tiempo que se enseña el podio antes de cerrar una ventana abierta sola.
    static let podiumHoldSeconds: TimeInterval = 60

    /// ¿Abrir la proyección sola? Solo con un estado en directo reciente y sin cerrar, sin ventana
    /// para ese torneo y sin que el docente haya cerrado esa sesión a mano.
    static func shouldOpen(
        state: TournamentLiveState,
        isStale: Bool,
        hasWindow: Bool,
        closedByHandSessions: Set<String>
    ) -> Bool {
        guard !isStale, state.status != .ended, !hasWindow else { return false }
        return !closedByHandSessions.contains(state.sessionId)
    }

    /// Qué hace una ventana con el estado actual. Una ventana abierta a mano nunca se cierra sola.
    /// - `tournamentFinished`: el torneo está en el podio (hay campeón).
    static func windowAction(
        openedAutomatically: Bool,
        windowTournamentID: String,
        state: TournamentLiveState,
        tournamentFinished: Bool
    ) -> TournamentLiveWindowAction {
        guard openedAutomatically else { return .keepOpen }
        // Otro torneo ha tomado el canal (gana la última sesión): esta ventana ya no es la suya.
        guard state.tournamentId == windowTournamentID else { return .closeNow }
        guard state.status == .ended else { return .keepOpen }
        return tournamentFinished ? .closeAfter(podiumHoldSeconds) : .closeNow
    }

    /// Compatibilidad con la lectura corta del contrato: ¿cerrar al momento?
    static func shouldClose(
        openedAutomatically: Bool,
        windowTournamentID: String,
        state: TournamentLiveState,
        tournamentFinished: Bool
    ) -> Bool {
        windowAction(
            openedAutomatically: openedAutomatically,
            windowTournamentID: windowTournamentID,
            state: state,
            tournamentFinished: tournamentFinished
        ) == .closeNow
    }
}
