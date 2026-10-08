import EventKit
import Foundation

/// Copia a un calendario «Colegio» de Apple los eventos que la app crea, cambia o borra.
/// Solo actúa en el aparato donde se hace el cambio: los eventos que llegan por SyncLAN no se copian,
/// para no duplicarlos. Con la función desactivada, la app no toca el calendario de Apple.
@MainActor
final class AppleCalendarMirror {
    static let shared = AppleCalendarMirror()

    static let enabledKey = "settings.appleCalendarMirrorEnabled"
    static let calendarTitle = "Colegio"

    /// Relación entre el id del evento en la app y el id del evento en Apple. Es local a cada aparato.
    private static let mapKey = "appleCalendarMirror.eventMap"

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

    private let store = EKEventStore()

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

    /// Copia los eventos que todavía no tienen copia. Devuelve cuántos se han copiado.
    /// Si «Colegio» ya tiene un evento igual (mismo título y mismo día), lo enlaza sin duplicarlo.
    @discardableResult
    func mirrorMissing(_ items: [Item]) -> Int {
        guard hasFullAccess, let calendar = try? colegioCalendar() else { return 0 }
        var copied = 0
        for item in items where mapping[String(item.localId)] == nil {
            if relinkExisting(item, in: calendar) { continue }
            if createCopy(of: item) { copied += 1 }
        }
        return copied
    }

    /// Evento nuevo creado en esta app.
    func created(_ item: Item) {
        guard isEnabled, hasFullAccess else { return }
        _ = createCopy(of: item)
    }

    /// Evento editado. Solo actualiza copias que este aparato ya creó.
    /// No crea copias nuevas: así no se duplican eventos que llegaron de otro aparato.
    func updated(_ item: Item) {
        guard isEnabled, hasFullAccess, let event = copiedEvent(for: item.localId) else { return }
        apply(item, to: event)
        try? store.save(event, span: .thisEvent, commit: true)
    }

    /// Evento borrado en esta app.
    func deleted(localId: Int64) {
        guard isEnabled, hasFullAccess, let identifier = mapping[String(localId)] else { return }
        if let event = store.event(withIdentifier: identifier) {
            try? store.remove(event, span: .thisEvent, commit: true)
        }
        removeMapping(for: localId)
    }

    // MARK: - Privado

    private func createCopy(of item: Item) -> Bool {
        guard let calendar = try? colegioCalendar() else { return false }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        apply(item, to: event)
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            print("No se pudo copiar el evento \(item.localId) al calendario Colegio: \(error)")
            return false
        }
        guard let identifier = event.eventIdentifier else { return false }
        setMapping(identifier, for: item.localId)
        return true
    }

    /// Busca en «Colegio» un evento del mismo día y con el mismo título, y lo enlaza en vez de copiarlo otra vez.
    private func relinkExisting(_ item: Item, in calendar: EKCalendar) -> Bool {
        let start = Date(timeIntervalSince1970: Double(item.startMs) / 1000)
        let dayStart = Calendar.current.startOfDay(for: start)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? start
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: [calendar])
        guard let match = store.events(matching: predicate).first(where: { $0.title == item.title }),
              let identifier = match.eventIdentifier else {
            return false
        }
        setMapping(identifier, for: item.localId)
        return true
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

    private func copiedEvent(for localId: Int64) -> EKEvent? {
        guard let identifier = mapping[String(localId)] else { return nil }
        return store.event(withIdentifier: identifier)
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

    private var mapping: [String: String] {
        UserDefaults.standard.dictionary(forKey: Self.mapKey) as? [String: String] ?? [:]
    }

    private func setMapping(_ identifier: String, for localId: Int64) {
        var current = mapping
        current[String(localId)] = identifier
        UserDefaults.standard.set(current, forKey: Self.mapKey)
    }

    private func removeMapping(for localId: Int64) {
        var current = mapping
        current.removeValue(forKey: String(localId))
        UserDefaults.standard.set(current, forKey: Self.mapKey)
    }
}
