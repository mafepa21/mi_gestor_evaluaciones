import EventKit
import Foundation

/// Conecta la app con el calendario «Colegio» de la cuenta de Calendario de Apple, en los dos sentidos.
/// Este servicio solo habla con EventKit. Qué cambiar y cuándo lo decide `AppleCalendarReconciler`
/// y el puente (`KmpBridge+AppleCalendar`).
@MainActor
final class AppleCalendarMirror {
    static let shared = AppleCalendarMirror()

    static let enabledKey = "settings.appleCalendarMirrorEnabled"
    static let calendarTitle = "Colegio"
    /// Valor de `external_provider` en `calendar_events` para los eventos enlazados con «Colegio».
    static let provider = "apple_calendar"
    /// Eventos que el planificador crea y borra como marca interna. No se copian a «Colegio».
    static let excludedTitle = "Día no lectivo"

    /// Enlace de la versión anterior (id local → eventIdentifier). Solo sirve para migrarlo.
    private static let legacyMapKey = "appleCalendarMirror.eventMap"

    struct Item {
        let localId: Int64
        let title: String
        let notes: String?
        let startMs: Int64
        let endMs: Int64
    }

    enum MirrorError: LocalizedError {
        case noCalendarSource

        var errorDescription: String? {
            "No encuentro una cuenta de Calendario donde crear «Colegio»."
        }
    }

    /// Se llama cuando cambia algo en Calendario de Apple (también por cambios hechos fuera de la app).
    var onStoreChanged: (() -> Void)?
    /// Evita dos sincronizaciones a la vez.
    var reconcileInFlight = false

    private let store = EKEventStore()
    private var storeObserver: NSObjectProtocol?

    private init() {
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onStoreChanged?()
            }
        }
    }

    /// Curso 2026-2027, de 1 de septiembre de 2026 a 30 de junio de 2027, en hora local.
    static var schoolYearWindow: (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)) ?? .distantPast
        let lastDay = calendar.date(from: DateComponents(year: 2027, month: 6, day: 30)) ?? .distantPast
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: lastDay) ?? lastDay
        return (start, end)
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestAccess() async -> Bool {
        if hasFullAccess { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Crea el calendario «Colegio» si todavía no existe.
    func prepareCalendar() throws {
        _ = try colegioCalendar()
    }

    // MARK: - Lectura

    /// Eventos de «Colegio» que caen en el intervalo. Eventos sin identificador externo se ignoran.
    func remoteEvents(from start: Date, to end: Date) -> [AppleCalendarRemoteEvent] {
        guard hasFullAccess, let calendar = existingColegioCalendar() else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        return store.events(matching: predicate).compactMap { event in
            guard let externalId = event.calendarItemExternalIdentifier, !externalId.isEmpty else { return nil }
            let lastModified = event.lastModifiedDate ?? event.startDate ?? Date()
            return AppleCalendarRemoteEvent(
                externalId: externalId,
                title: event.title ?? "",
                notes: event.notes,
                startMs: Self.milliseconds(event.startDate),
                endMs: Self.milliseconds(event.endDate),
                lastModifiedMs: Self.milliseconds(lastModified)
            )
        }
    }

    // MARK: - Escritura

    /// Crea un evento en «Colegio» y devuelve su identificador externo.
    func createCopy(_ item: Item) -> String? {
        guard hasFullAccess, let calendar = try? colegioCalendar() else { return nil }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        apply(item, to: event)
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            print("No se pudo crear el evento en Colegio: \(error)")
            return nil
        }
        return event.calendarItemExternalIdentifier
    }

    @discardableResult
    func updateCopy(externalId: String, item: Item) -> Bool {
        guard hasFullAccess, let event = eventWithExternalId(externalId) else { return false }
        apply(item, to: event)
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return true
        } catch {
            print("No se pudo actualizar el evento en Colegio: \(error)")
            return false
        }
    }

    func deleteCopy(externalId: String) {
        guard hasFullAccess, let event = eventWithExternalId(externalId) else { return }
        do {
            try store.remove(event, span: .thisEvent, commit: true)
        } catch {
            print("No se pudo borrar el evento de Colegio: \(error)")
        }
    }

    func eventWithExternalId(_ externalId: String) -> EKEvent? {
        store.calendarItems(withExternalIdentifier: externalId).compactMap { $0 as? EKEvent }.first
    }

    // MARK: - Migración del enlace antiguo (UserDefaults)

    /// Identificador externo del evento de «Colegio» que la versión anterior enlazó con este id local.
    func legacyExternalId(localId: Int64) -> String? {
        guard hasFullAccess,
              let identifier = legacyMapping[String(localId)],
              let event = store.event(withIdentifier: identifier) else { return nil }
        return event.calendarItemExternalIdentifier
    }

    var legacyLocalIds: [Int64] {
        legacyMapping.keys.compactMap { Int64($0) }
    }

    func removeLegacyMapping(localId: Int64) {
        var current = legacyMapping
        current.removeValue(forKey: String(localId))
        UserDefaults.standard.set(current, forKey: Self.legacyMapKey)
    }

    // MARK: - Privado

    private var legacyMapping: [String: String] {
        UserDefaults.standard.dictionary(forKey: Self.legacyMapKey) as? [String: String] ?? [:]
    }

    private func apply(_ item: Item, to event: EKEvent) {
        let start = Date(timeIntervalSince1970: Double(item.startMs) / 1000)
        let end = Date(timeIntervalSince1970: Double(item.endMs) / 1000)
        event.title = item.title
        event.notes = item.notes
        // Los hitos se guardan a las 00:00 locales: se copian como evento de día completo.
        event.isAllDay = Calendar.current.startOfDay(for: start) == start
        event.startDate = start
        event.endDate = max(end, start)
    }

    private func existingColegioCalendar() -> EKCalendar? {
        store.calendars(for: .event).first { $0.title == Self.calendarTitle }
    }

    /// Busca «Colegio» antes de crearlo: así, iPad y Mac comparten el mismo calendario y no se duplica.
    private func colegioCalendar() throws -> EKCalendar {
        if let existing = store.calendars(for: .event).first(where: {
            $0.title == Self.calendarTitle && $0.allowsContentModifications
        }) {
            return existing
        }
        guard let source = preferredSource() else { throw MirrorError.noCalendarSource }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = Self.calendarTitle
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    private func preferredSource() -> EKSource? {
        store.sources.first { $0.sourceType == .calDAV && $0.title == "iCloud" }
            ?? store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .local }
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }
}
