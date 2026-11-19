import Foundation
import Network
import OSLog
import MiGestorKit

/// Cola de 10 minutos por grupo para publicar «Mis notas» (ticket fase 2, 4.4).
///
/// Cada aviso de cambio reinicia la espera de su grupo. Cuando pasan 10 minutos sin
/// cambios, el grupo se publica. No hay «Publicar ahora»: así el docente tiene margen
/// para corregir una nota antes de que la vea el alumnado.
///
/// Hilo principal: solo contabilidad (un `Task` que duerme por grupo). El informe, el JSON
/// y el cifrado van en segundo plano (`WebPortalGrades.loadGroup` y `WebPortalPublisher`).

// MARK: - Cola con reloj inyectable

@MainActor
final class WebPortalGradesDebouncer {
    typealias Sleep = @MainActor (TimeInterval) async throws -> Void

    static let defaultDelay: TimeInterval = 10 * 60

    let delay: TimeInterval
    private let sleep: Sleep
    private let now: () -> Date
    private let fire: (Int64) async -> Void
    private var timers: [Int64: (token: UUID, task: Task<Void, Never>)] = [:]
    /// Cuándo toca publicar cada grupo pendiente.
    private(set) var dueDates: [Int64: Date] = [:]
    /// Avisa cuando cambia `dueDates` (para la hoja).
    var onChange: (() -> Void)?

    init(
        delay: TimeInterval = WebPortalGradesDebouncer.defaultDelay,
        sleep: @escaping Sleep = { seconds in try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)) },
        now: @escaping () -> Date = Date.init,
        fire: @escaping (Int64) async -> Void
    ) {
        self.delay = delay
        self.sleep = sleep
        self.now = now
        self.fire = fire
    }

    var pendingClassIds: Set<Int64> { Set(timers.keys) }

    /// Un cambio en el grupo: la espera empieza de nuevo.
    func schedule(classId: Int64, after wait: TimeInterval? = nil) {
        let seconds = wait ?? delay
        timers[classId]?.task.cancel()
        let token = UUID()
        dueDates[classId] = now().addingTimeInterval(seconds)
        let sleeper = sleep
        timers[classId] = (token, Task { @MainActor [weak self] in
            do { try await sleeper(seconds) } catch { return }
            guard let self, !Task.isCancelled, self.timers[classId]?.token == token else { return }
            self.timers[classId] = nil
            self.dueDates[classId] = nil
            self.onChange?()
            await self.fire(classId)
        })
        onChange?()
    }

    func scheduleAll(_ classIds: Set<Int64>) {
        for classId in classIds { schedule(classId: classId) }
    }

    /// Publica ya el grupo (solo para reintentar un fallo, no hay botón para el resto).
    func fireNow(classId: Int64) {
        timers[classId]?.task.cancel()
        timers[classId] = nil
        dueDates[classId] = nil
        onChange?()
        Task { @MainActor [weak self] in await self?.fire(classId) }
    }
}

// MARK: - Vigilante

@MainActor
final class WebPortalGradesWatcher: ObservableObject {
    static let shared = WebPortalGradesWatcher()
    static let log = Logger(subsystem: "com.migestor.entregas-web", category: "portal-notas")
    /// Espera antes de reintentar un fallo que no es de red.
    static let retryDelay: TimeInterval = 5 * 60
    private static let lastPublishedKey = "webPortal.notas.ultimaPublicacion"

    @Published private(set) var dueDates: [Int64: Date] = [:]
    @Published private(set) var failedClassIds: Set<Int64> = []
    @Published private(set) var lastPublished: [Int64: Date] = [:]

    /// Lo último publicado por alumno, para no subir dos veces lo mismo.
    var summary = WebPortalGradesSummary()

    private(set) var debouncer: WebPortalGradesDebouncer!
    /// Publica un grupo. `true` si salió bien (o no había nada que hacer).
    var publish: ((Int64) async -> Bool)?
    /// Grupos con alguna columna encendida (copia de `notas-visibles.json`).
    private(set) var activeClassIds: Set<Int64> = []
    private var watched = Set<Int64>()
    private var tasks: [Task<Void, Never>] = []
    private var globalObserversInstalled = false
    private var pathMonitor: NWPathMonitor?

    init(debouncer: WebPortalGradesDebouncer? = nil) {
        let stored = UserDefaults.standard.dictionary(forKey: Self.lastPublishedKey) as? [String: Double] ?? [:]
        for (key, value) in stored { if let id = Int64(key) { lastPublished[id] = Date(timeIntervalSince1970: value) } }
        self.debouncer = debouncer ?? WebPortalGradesDebouncer(fire: { [weak self] classId in
            await self?.fire(classId)
        })
        self.debouncer.onChange = { [weak self] in
            guard let self else { return }
            self.dueDates = self.debouncer.dueDates
        }
    }

    // MARK: Avisos de cambio

    /// Una nota, un interruptor o la estructura de un grupo cambió.
    func noteChange(classId: Int64) {
        guard activeClassIds.contains(classId) else { return }
        debouncer.schedule(classId: classId)
    }

    /// Pesos, columnas, ocultas o un cambio externo en la base: afecta a todos los grupos vigilados.
    func noteChangeInAllGroups() {
        for classId in activeClassIds { debouncer.schedule(classId: classId) }
    }

    /// El docente cambió un interruptor: la cola del grupo empieza de nuevo aunque ahora
    /// no quede ninguna columna encendida (hay que retirar lo que ya se vio).
    func noteSettingsChange(classId: Int64) {
        reloadSettings()
        debouncer.schedule(classId: classId)
    }

    func reloadSettings() {
        guard let url = WebPortalGradeSettings.standardURL() else { return }
        activeClassIds = WebPortalGradeSettings.load(fileURL: url).activeClassIds
    }

    /// Para la hoja: «Reintentar» tras un fallo.
    func retryNow(classId: Int64) {
        debouncer.fireNow(classId: classId)
    }

    // MARK: Publicar

    private func fire(_ classId: Int64) async {
        guard let publish else { return }
        WebPortalPublishQueue.shared.enqueue { [weak self] in
            let ok = await publish(classId)
            guard let self else { return }
            if ok {
                self.failedClassIds.remove(classId)
                self.recordPublished(classId: classId)
            } else {
                self.failedClassIds.insert(classId)
                // Sin red lo reintenta `NWPathMonitor`; con otro fallo, pasado un rato.
                self.debouncer.schedule(classId: classId, after: Self.retryDelay)
            }
        }
    }

    private func recordPublished(classId: Int64) {
        lastPublished[classId] = Date()
        let raw = Dictionary(uniqueKeysWithValues: lastPublished.map { (String($0.key), $0.value.timeIntervalSince1970) })
        UserDefaults.standard.set(raw, forKey: Self.lastPublishedKey)
    }

    // MARK: Vigilancia de la base

    /// Un vigilante por grupo, que nunca se para (los flujos de Kotlin no se cancelan):
    /// si el grupo está apagado, `noteChange` no hace nada. Idempotente.
    func watch(classId: Int64, flows: [any Flow]) {
        guard watched.insert(classId).inserted else { return }
        for flow in flows {
            tasks.append(Task { @MainActor [weak self] in
                var first = true
                for await _ in flow.asAsyncSequence(type: Any.self) {
                    // La primera emisión es el estado actual, no un cambio.
                    if first { first = false; continue }
                    self?.noteChange(classId: classId)
                }
            })
        }
    }

    /// Avisos que no son de un grupo: Sync LAN aplicado, estructura del Cuaderno y red.
    func installGlobalObservers() {
        guard !globalObserversInstalled else { return }
        globalObserversInstalled = true

        tasks.append(Task { @MainActor [weak self] in
            for await note in NotificationCenter.default.notifications(named: .lanSyncRemoteChangesApplied) {
                let entities = note.userInfo?[LanSyncRefreshPlan.entitiesUserInfoKey] as? Set<String> ?? []
                if !entities.isDisjoint(with: LanSyncRefreshPlan.steps(entities: entities).notebookEntities) {
                    self?.noteChangeInAllGroups()
                }
            }
        })
        tasks.append(Task { @MainActor [weak self] in
            for await _ in NotebookRefreshBus.shared.refreshSignal.asAsyncSequence(type: Any.self) {
                self?.noteChangeInAllGroups()
            }
        })

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                guard let self else { return }
                for classId in self.failedClassIds { self.debouncer.fireNow(classId: classId) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.migestor.portal-notas.red", qos: .utility))
        pathMonitor = monitor
    }
}

// MARK: - Enganche con el puente

extension KmpBridge {
    /// Única entrada del portal de notas (diseño, sección 1): un cambio en el grupo, o un
    /// interruptor, lo pone en la cola de 10 minutos. No bloquea ni lanza.
    func schedulePortalGradesRepublish(classId: Int64) {
        let watcher = prepareGradesWatcher()
        watcher.noteSettingsChange(classId: classId)
        watchPortalGrades(classId: classId)
    }

    /// Al final de `refreshClasses()` y al arrancar: vigila los grupos con alguna columna encendida.
    func startPortalGradesWatching() {
        let watcher = prepareGradesWatcher()
        for classId in watcher.activeClassIds { watchPortalGrades(classId: classId) }
    }

    private func prepareGradesWatcher() -> WebPortalGradesWatcher {
        let watcher = WebPortalGradesWatcher.shared
        if watcher.publish == nil {
            watcher.publish = { [weak self] classId in
                guard let self else { return true }
                return await self.republishPortalBoards(formInstanceIds: [], gradeClassIds: [classId])
            }
            watcher.installGlobalObservers()
            watcher.reloadSettings()
        }
        return watcher
    }

    private func watchPortalGrades(classId: Int64) {
        WebPortalGradesWatcher.shared.watch(classId: classId, flows: [
            container.gradesRepository.observeGradesForClass(classId: classId),
            container.notebookCellsRepository.observeClassCells(classId: classId),
        ])
    }
}
