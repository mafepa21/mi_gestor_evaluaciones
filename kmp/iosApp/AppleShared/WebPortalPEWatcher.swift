import Foundation
import Network
import OSLog

/// Cola de 10 minutos por grupo para publicar «EF y seguimiento» (pruebas físicas y asistencia)
/// en el portal del alumnado (fase 3C). Apagar retira al momento (`immediately: true`).
@MainActor
final class WebPortalPEWatcher: ObservableObject {
    static let shared = WebPortalPEWatcher()
    static let log = Logger(subsystem: "com.migestor.entregas-web", category: "portal-ef")
    static let defaultDelay: TimeInterval = 10 * 60
    static let retryDelay: TimeInterval = 5 * 60
    static let maxRetryDelay: TimeInterval = 60 * 60
    private static let lastPublishedKey = "webPortal.ef.ultimaPublicacion"

    static func backoff(attempt: Int) -> TimeInterval {
        min(retryDelay * pow(2, Double(min(attempt, 10))), maxRetryDelay)
    }

    @Published private(set) var dueDates: [Int64: Date] = [:]
    @Published private(set) var failedClassIds: Set<Int64> = []
    @Published private(set) var tooLargeClassIds: Set<Int64> = []
    @Published private(set) var lastPublished: [Int64: Date] = [:]

    var summary = WebPortalPESummary()
    private(set) var publishedState = WebPortalPEPublishedState()

    private(set) var debouncer: WebPortalGradesDebouncer!
    var publish: ((Int64) async -> WebPortalGradesPublishStatus)?
    private(set) var activeClassIds: Set<Int64> = []
    private let stateURL: URL?
    private var inFlight = Set<Int64>()
    private var attempts: [Int64: Int] = [:]
    private var startupDone = false

    init(
        debouncer: WebPortalGradesDebouncer? = nil,
        stateURL: URL? = WebPortalPESettings.standardURL().map(WebPortalPEPublishedState.url(besides:))
    ) {
        self.stateURL = stateURL
        if let stateURL { publishedState = WebPortalPEPublishedState.load(fileURL: stateURL) }
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

    func noteSettingsChange(classId: Int64, immediately: Bool) {
        reloadSettings()
        if immediately { debouncer.fireNow(classId: classId) } else { debouncer.schedule(classId: classId) }
    }

    func noteDataChange(classId: Int64) {
        reloadSettings()
        guard activeClassIds.contains(classId) || publishedState.conEF.contains(classId) else { return }
        debouncer.schedule(classId: classId)
    }

    func reloadSettings() {
        guard let url = WebPortalPESettings.standardURL() else { return }
        activeClassIds = WebPortalPESettings.load(fileURL: url).activeClassIds
    }

    func retryNow(classId: Int64) {
        attempts[classId] = nil
        debouncer.fireNow(classId: classId)
    }

    private func persistPending() {
        let pending = Array(debouncer.pendingClassIds.union(inFlight).union(failedClassIds)).sorted()
        guard pending != publishedState.pendientes else { return }
        publishedState.pendientes = pending
        savePublishedState()
    }

    private func savePublishedState() {
        if let stateURL { publishedState.save(fileURL: stateURL) }
    }

    func updatePublishedState(withPE: Set<Int64>, readClassIds: Set<Int64>, complete: Bool) {
        var current = Set(publishedState.conEF).union(withPE)
        if complete { current.subtract(readClassIds.subtracting(withPE)) }
        let sorted = current.sorted()
        guard sorted != publishedState.conEF else { return }
        publishedState.conEF = sorted
        savePublishedState()
    }

    func runStartupPassOnce() {
        guard !startupDone, publish != nil else { return }
        startupDone = true
        for classId in Set(publishedState.conEF).union(publishedState.pendientes) {
            debouncer.fireNow(classId: classId)
        }
    }

    private func fire(_ classId: Int64) async {
        guard let publish else { return }
        inFlight.insert(classId)
        persistPending()
        WebPortalPublishQueue.shared.enqueue { [weak self] in
            let status = await publish(classId)
            self?.finish(classId: classId, status: status)
        }
    }

    private func finish(classId: Int64, status: WebPortalGradesPublishStatus) {
        inFlight.remove(classId)
        if status.tooLarge { tooLargeClassIds.insert(classId) } else { tooLargeClassIds.remove(classId) }
        if status.retry {
            failedClassIds.insert(classId)
            let next = (attempts[classId] ?? 0) + 1
            attempts[classId] = next
            debouncer.schedule(classId: classId, after: Self.backoff(attempt: next))
        } else {
            failedClassIds.remove(classId)
            attempts[classId] = nil
            lastPublished[classId] = Date()
            let stored = Dictionary(uniqueKeysWithValues: lastPublished.map { (String($0.key), $0.value.timeIntervalSince1970) })
            UserDefaults.standard.set(stored, forKey: Self.lastPublishedKey)
        }
        persistPending()
    }
}
