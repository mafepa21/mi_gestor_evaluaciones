import Foundation
import Network
import OSLog

/// Cola de 2 minutos por grupo para publicar «Torneos» en el portal del alumnado (ticket fase 3B, 4.3).
///
/// Reutiliza `WebPortalGradesDebouncer` con espera corta de 2 minutos (agrupa los marcadores de una
/// ronda sin hacer esperar 10 minutos). Apagar un torneo o cambiar «Mostrar nombres de equipo»
/// actualiza/retira al momento (`immediately: true`).
@MainActor
final class WebPortalTournamentsWatcher: ObservableObject {
    static let shared = WebPortalTournamentsWatcher()
    static let log = Logger(subsystem: "com.migestor.entregas-web", category: "portal-torneos")
    static let defaultDelay: TimeInterval = 2 * 60
    static let retryDelay: TimeInterval = 5 * 60
    static let maxRetryDelay: TimeInterval = 60 * 60
    private static let lastPublishedKey = "webPortal.torneos.ultimaPublicacion"

    static func backoff(attempt: Int) -> TimeInterval {
        min(retryDelay * pow(2, Double(min(attempt, 10))), maxRetryDelay)
    }

    @Published private(set) var dueDates: [Int64: Date] = [:]
    @Published private(set) var failedClassIds: Set<Int64> = []
    @Published private(set) var tooLargeClassIds: Set<Int64> = []
    @Published private(set) var lastPublished: [Int64: Date] = [:]

    var summary = WebPortalTournamentsSummary()
    private(set) var publishedState = WebPortalTournamentsPublishedState()

    private(set) var debouncer: WebPortalGradesDebouncer!
    var publish: ((Int64) async -> WebPortalGradesPublishStatus)?
    private(set) var activeClassIds: Set<Int64> = []
    private let stateURL: URL?
    private var inFlight = Set<Int64>()
    private var attempts: [Int64: Int] = [:]
    private var tasks: [Task<Void, Never>] = []
    private var globalObserversInstalled = false
    private var startupDone = false
    private var pathMonitor: NWPathMonitor?
    private var wasOnline: Bool?

    init(
        debouncer: WebPortalGradesDebouncer? = nil,
        stateURL: URL? = WebPortalTournamentSettings.standardURL().map(WebPortalTournamentsPublishedState.url(besides:))
    ) {
        self.stateURL = stateURL
        if let stateURL { publishedState = WebPortalTournamentsPublishedState.load(fileURL: stateURL) }
        let stored = UserDefaults.standard.dictionary(forKey: Self.lastPublishedKey) as? [String: Double] ?? [:]
        for (key, value) in stored { if let id = Int64(key) { lastPublished[id] = Date(timeIntervalSince1970: value) } }
        self.debouncer = debouncer ?? WebPortalGradesDebouncer(
            delay: Self.defaultDelay,
            fire: { [weak self] classId in await self?.fire(classId) }
        )
        self.debouncer.onChange = { [weak self] in
            guard let self else { return }
            self.dueDates = self.debouncer.dueDates
            self.persistPending()
        }
    }

    // MARK: Avisos de cambio

    /// Un torneo del grupo cambió (guardado en Mac): cola de 2 minutos si el grupo tiene torneos activos.
    func noteTournamentChange(classId: Int64) {
        guard activeClassIds.contains(classId) || publishedState.conTorneos.contains(classId) else { return }
        debouncer.schedule(classId: classId)
    }

    /// Llegaron cambios de torneos por Sync LAN (p. ej. marcadores del iPad en Modo directo).
    func noteChangeInAllGroups() {
        for classId in activeClassIds.union(publishedState.conTorneos) {
            debouncer.schedule(classId: classId)
        }
    }

    /// El docente cambió un interruptor. Encender espera 2 min; apagar o cambiar nombres actúa al momento.
    func noteSettingsChange(classId: Int64, immediately: Bool) {
        reloadSettings()
        if immediately { debouncer.fireNow(classId: classId) } else { debouncer.schedule(classId: classId) }
    }

    func reloadSettings() {
        guard let url = WebPortalTournamentSettings.standardURL() else { return }
        activeClassIds = WebPortalTournamentSettings.load(fileURL: url).activeClassIds
    }

    func retryNow(classId: Int64) {
        attempts[classId] = nil
        debouncer.fireNow(classId: classId)
    }

    // MARK: Estado en disco

    private func persistPending() {
        let pending = Array(debouncer.pendingClassIds.union(inFlight).union(failedClassIds)).sorted()
        guard pending != publishedState.pendientes else { return }
        publishedState.pendientes = pending
        savePublishedState()
    }

    private func savePublishedState() {
        if let stateURL { publishedState.save(fileURL: stateURL) }
    }

    func updatePublishedState(withTournaments: Set<Int64>, readClassIds: Set<Int64>, complete: Bool) {
        var current = Set(publishedState.conTorneos).union(withTournaments)
        if complete { current.subtract(readClassIds.subtracting(withTournaments)) }
        let sorted = current.sorted()
        guard sorted != publishedState.conTorneos else { return }
        publishedState.conTorneos = sorted
        savePublishedState()
    }

    func runStartupPassOnce() {
        guard !startupDone, publish != nil else { return }
        startupDone = true
        for classId in Set(publishedState.conTorneos).union(publishedState.pendientes) {
            debouncer.fireNow(classId: classId)
        }
    }

    // MARK: Publicar

    private func fire(_ classId: Int64) async {
        guard let publish else { return }
        inFlight.insert(classId)
        persistPending()
        WebPortalPublishQueue.shared.enqueue { [weak self] in
            let status = await publish(classId)
            guard let self else { return }
            self.inFlight.remove(classId)
            if status.tooLarge { self.tooLargeClassIds.insert(classId) } else { self.tooLargeClassIds.remove(classId) }
            if status.retry {
                self.failedClassIds.insert(classId)
                let attempt = self.attempts[classId, default: 0]
                self.attempts[classId] = attempt + 1
                self.debouncer.schedule(classId: classId, after: Self.backoff(attempt: attempt))
            } else {
                self.failedClassIds.remove(classId)
                self.attempts[classId] = nil
                self.recordPublished(classId: classId)
            }
            self.persistPending()
        }
    }

    private func recordPublished(classId: Int64) {
        lastPublished[classId] = Date()
        let raw = Dictionary(uniqueKeysWithValues: lastPublished.map { (String($0.key), $0.value.timeIntervalSince1970) })
        UserDefaults.standard.set(raw, forKey: Self.lastPublishedKey)
    }

    func networkChanged(online: Bool) {
        defer { wasOnline = online }
        guard online, wasOnline == false else { return }
        for classId in failedClassIds { debouncer.fireNow(classId: classId) }
    }

    func installGlobalObservers() {
        guard !globalObserversInstalled else { return }
        globalObserversInstalled = true

        tasks.append(Task { @MainActor [weak self] in
            for await note in NotificationCenter.default.notifications(named: .lanSyncRemoteChangesApplied) {
                let entities = note.userInfo?[LanSyncRefreshPlan.entitiesUserInfoKey] as? Set<String> ?? []
                if entities.contains("learning_situation_tournament") {
                    self?.noteChangeInAllGroups()
                }
            }
        })

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "com.migestor.portal-torneos.red", qos: .utility))
        pathMonitor = monitor
    }
}

// MARK: - Enganche con el puente

extension KmpBridge {
    /// Cambio en un interruptor de Torneos desde `WebPortalSheet`.
    func schedulePortalTournamentsRepublish(classId: Int64, immediately: Bool = false) {
        let watcher = prepareTournamentsWatcher()
        watcher.noteSettingsChange(classId: classId, immediately: immediately)
    }

    /// Guardado o borrado de un torneo en el Mac.
    func notifyPortalTournamentChanged(classId: Int64?) {
        let watcher = prepareTournamentsWatcher()
        if let classId {
            watcher.noteTournamentChange(classId: classId)
        } else {
            watcher.noteChangeInAllGroups()
        }
    }

    /// Al final de `refreshClasses()` y al arrancar.
    func startPortalTournamentsWatching() {
        let watcher = prepareTournamentsWatcher()
        watcher.runStartupPassOnce()
    }

    private func prepareTournamentsWatcher() -> WebPortalTournamentsWatcher {
        let watcher = WebPortalTournamentsWatcher.shared
        if watcher.publish == nil {
            watcher.publish = { [weak self] classId in
                guard let self else { return WebPortalGradesPublishStatus() }
                return await self.republishPortalBoards(
                    formInstanceIds: [],
                    tournamentClassIds: [classId],
                    onlyDynamicBlocks: true
                )
            }
            watcher.installGlobalObservers()
            watcher.reloadSettings()
        }
        return watcher
    }
}
