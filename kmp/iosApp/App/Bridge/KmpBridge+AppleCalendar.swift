import Foundation
import MiGestorKit

/// Enlace de un evento de la app con su evento en «Colegio». Se guarda en `calendar_events`.
struct AppleCalendarLink {
    let provider: String
    let externalId: String
}

extension KmpBridge {
    // MARK: - Enlaces

    func appleCalendarLink(forEventId id: Int64) async -> AppleCalendarLink? {
        let events = (try? await container.calendarRepository.listEvents(classId: nil)) ?? []
        guard let event = events.first(where: { $0.id == id }),
              event.externalProvider == AppleCalendarMirror.provider,
              let externalId = event.externalId else {
            return nil
        }
        return AppleCalendarLink(provider: AppleCalendarMirror.provider, externalId: externalId)
    }

    func appleCalendarLink(externalId: String) -> AppleCalendarLink {
        AppleCalendarLink(provider: AppleCalendarMirror.provider, externalId: externalId)
    }

    /// Guarda un evento en la base de datos conservando o cambiando su enlace con «Colegio».
    /// No pasa por la cola de sincronización de SyncLAN: cada aparato trae sus propios eventos de «Colegio».
    func saveCalendarRow(
        id: Int64?,
        classId: Int64?,
        title: String,
        description: String?,
        startMs: Int64,
        endMs: Int64,
        link: AppleCalendarLink?,
        updatedMs: Int64
    ) async throws -> Int64 {
        try await container.calendarRepository.saveEvent(
            id: kotlinLong(id),
            classId: kotlinLong(classId),
            title: title,
            description: description,
            startEpochMs: startMs,
            endEpochMs: endMs,
            externalProvider: link?.provider,
            externalId: link?.externalId,
            authorUserId: nil,
            updatedAtEpochMs: updatedMs,
            deviceId: localDeviceId,
            syncVersion: 1
        ).int64Value
    }

    func appleCalendarLocal(_ event: CalendarEvent) -> AppleCalendarLocalEvent {
        AppleCalendarLocalEvent(
            id: event.id,
            title: event.title,
            notes: event.description_,
            startMs: event.startAt.toEpochMilliseconds(),
            endMs: event.endAt.toEpochMilliseconds(),
            updatedMs: event.trace.updatedAt.toEpochMilliseconds(),
            externalId: event.externalProvider == AppleCalendarMirror.provider ? event.externalId : nil
        )
    }

    // MARK: - Activación

    /// Al activar la función: enlaza los eventos que ya existían con su copia en «Colegio»,
    /// o crea la copia si no existe. Devuelve cuántas copias nuevas se han creado.
    func backfillAppleCalendarLinks() async throws -> Int {
        let mirror = AppleCalendarMirror.shared
        try await migrateAppleCalendarLegacyLinks()

        let window = AppleCalendarMirror.schoolYearWindow
        let remote = mirror.remoteEvents(from: window.start, to: window.end)
        let events = try await container.calendarRepository.listEvents(classId: nil)
        var created = 0

        for event in events where event.externalProvider == nil && event.title != AppleCalendarMirror.excludedTitle {
            let local = appleCalendarLocal(event)
            let externalId: String
            if let match = remote.first(where: { $0.title == local.title && Self.isSameDay($0.startMs, local.startMs) }) {
                externalId = match.externalId
            } else {
                let item = AppleCalendarMirror.Item(
                    localId: local.id,
                    title: local.title,
                    notes: local.notes,
                    startMs: local.startMs,
                    endMs: local.endMs
                )
                guard let newExternalId = mirror.createCopy(item) else { continue }
                externalId = newExternalId
                created += 1
            }
            _ = try await saveCalendarRow(
                id: local.id,
                classId: event.classId?.int64Value,
                title: local.title,
                description: local.notes,
                startMs: local.startMs,
                endMs: local.endMs,
                link: appleCalendarLink(externalId: externalId),
                updatedMs: local.updatedMs
            )
        }
        return created
    }

    // MARK: - Sincronización

    /// Sincroniza en segundo plano si la función está activada. Se llama al volver a la app
    /// y cada vez que Calendario de Apple avisa de un cambio.
    func reconcileAppleCalendarIfEnabled() {
        let mirror = AppleCalendarMirror.shared
        guard mirror.isEnabled, mirror.hasFullAccess else { return }
        mirror.onStoreChanged = { [weak self] in
            self?.reconcileAppleCalendarIfEnabled()
        }
        guard !mirror.reconcileInFlight else { return }
        mirror.reconcileInFlight = true

        Task { @MainActor [weak self] in
            defer { AppleCalendarMirror.shared.reconcileInFlight = false }
            guard let self else { return }
            do {
                try await self.migrateAppleCalendarLegacyLinks()
                try await self.importAndReconcileAppleCalendar()
            } catch {
                print("No se pudo sincronizar con Colegio: \(error)")
            }
        }
    }

    /// Pasa a la base de datos los enlaces que guardaba la versión anterior en UserDefaults.
    /// Las copias antiguas de «Día no lectivo» se borran: esa marca ya no se copia a «Colegio».
    private func migrateAppleCalendarLegacyLinks() async throws {
        let mirror = AppleCalendarMirror.shared
        guard !mirror.legacyLocalIds.isEmpty else { return }
        let events = try await container.calendarRepository.listEvents(classId: nil)

        for event in events where event.externalProvider == nil {
            guard let legacyExternalId = mirror.legacyExternalId(localId: event.id) else { continue }
            if event.title == AppleCalendarMirror.excludedTitle {
                mirror.deleteCopy(externalId: legacyExternalId)
            } else {
                let local = appleCalendarLocal(event)
                _ = try await saveCalendarRow(
                    id: local.id,
                    classId: event.classId?.int64Value,
                    title: local.title,
                    description: local.notes,
                    startMs: local.startMs,
                    endMs: local.endMs,
                    link: appleCalendarLink(externalId: legacyExternalId),
                    updatedMs: local.updatedMs
                )
            }
            mirror.removeLegacyMapping(localId: event.id)
        }
    }

    private func importAndReconcileAppleCalendar() async throws {
        let window = AppleCalendarMirror.schoolYearWindow
        let remote = AppleCalendarMirror.shared.remoteEvents(from: window.start, to: window.end)
        let events = try await container.calendarRepository.listEvents(classId: nil)
        let actions = AppleCalendarReconciler.plan(
            remote: remote,
            locals: events.map { appleCalendarLocal($0) },
            windowStartMs: Int64(window.start.timeIntervalSince1970 * 1000),
            windowEndMs: Int64(window.end.timeIntervalSince1970 * 1000)
        )
        for action in actions {
            try await apply(action)
        }
    }

    private func apply(_ action: AppleCalendarReconcileAction) async throws {
        switch action {
        case .importRemote(let remote):
            _ = try await saveCalendarRow(
                id: nil,
                classId: nil,
                title: remote.title,
                description: remote.notes,
                startMs: remote.startMs,
                endMs: remote.endMs,
                link: appleCalendarLink(externalId: remote.externalId),
                updatedMs: remote.lastModifiedMs
            )
        case .updateLocal(let id, let remote):
            _ = try await saveCalendarRow(
                id: id,
                classId: nil,
                title: remote.title,
                description: remote.notes,
                startMs: remote.startMs,
                endMs: remote.endMs,
                link: appleCalendarLink(externalId: remote.externalId),
                updatedMs: remote.lastModifiedMs
            )
        case .pushLocal(let local):
            guard let externalId = local.externalId else { return }
            AppleCalendarMirror.shared.updateCopy(
                externalId: externalId,
                item: AppleCalendarMirror.Item(
                    localId: local.id,
                    title: local.title,
                    notes: local.notes,
                    startMs: local.startMs,
                    endMs: local.endMs
                )
            )
        case .deleteLocal(let id), .removeDuplicate(let id):
            try await container.calendarRepository.deleteEvent(id: id)
        }
    }

    private static func isSameDay(_ firstMs: Int64, _ secondMs: Int64) -> Bool {
        let first = Date(timeIntervalSince1970: Double(firstMs) / 1000)
        let second = Date(timeIntervalSince1970: Double(secondMs) / 1000)
        return Calendar.current.isDate(first, inSameDayAs: second)
    }
}
