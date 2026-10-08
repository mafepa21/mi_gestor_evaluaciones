import Foundation

/// Evento leído de «Colegio» en Calendario de Apple.
struct AppleCalendarRemoteEvent: Equatable {
    let externalId: String
    let title: String
    let notes: String?
    let startMs: Int64
    let endMs: Int64
    let lastModifiedMs: Int64
}

/// Evento de la app. `externalId` solo tiene valor si el evento está enlazado con «Colegio».
struct AppleCalendarLocalEvent: Equatable {
    let id: Int64
    let title: String
    let notes: String?
    let startMs: Int64
    let endMs: Int64
    let updatedMs: Int64
    let externalId: String?
}

enum AppleCalendarReconcileAction: Equatable {
    /// Crear en la app un evento que existe en «Colegio».
    case importRemote(AppleCalendarRemoteEvent)
    /// El cambio más reciente está en «Colegio»: actualizar el evento de la app.
    case updateLocal(id: Int64, from: AppleCalendarRemoteEvent)
    /// El cambio más reciente está en la app: actualizar el evento de «Colegio».
    case pushLocal(AppleCalendarLocalEvent)
    /// Se borró en «Colegio» dentro del curso: borrar el evento de la app.
    case deleteLocal(id: Int64)
    /// Dos eventos de la app apuntan al mismo evento de «Colegio»: quedarse con el primero.
    case removeDuplicate(id: Int64)
}

/// Decide qué hacer para que la app y «Colegio» coincidan. No toca ni EventKit ni la base de datos.
enum AppleCalendarReconciler {
    static func plan(
        remote: [AppleCalendarRemoteEvent],
        locals: [AppleCalendarLocalEvent],
        windowStartMs: Int64,
        windowEndMs: Int64
    ) -> [AppleCalendarReconcileAction] {
        var actions: [AppleCalendarReconcileAction] = []
        let remoteById = Dictionary(remote.map { ($0.externalId, $0) }, uniquingKeysWith: { first, _ in first })
        var keptLocalByExternalId: [String: AppleCalendarLocalEvent] = [:]

        for local in locals.sorted(by: { $0.id < $1.id }) {
            guard let externalId = local.externalId else { continue }
            if keptLocalByExternalId[externalId] != nil {
                actions.append(.removeDuplicate(id: local.id))
                continue
            }
            keptLocalByExternalId[externalId] = local

            if let remoteEvent = remoteById[externalId] {
                if sameContent(local, remoteEvent) { continue }
                if remoteEvent.lastModifiedMs > local.updatedMs {
                    actions.append(.updateLocal(id: local.id, from: remoteEvent))
                } else {
                    actions.append(.pushLocal(local))
                }
            } else if local.startMs >= windowStartMs && local.startMs <= windowEndMs {
                actions.append(.deleteLocal(id: local.id))
            }
        }

        for remoteEvent in remote where keptLocalByExternalId[remoteEvent.externalId] == nil {
            actions.append(.importRemote(remoteEvent))
        }
        return actions
    }

    static func sameContent(_ local: AppleCalendarLocalEvent, _ remote: AppleCalendarRemoteEvent) -> Bool {
        local.title == remote.title
            && (local.notes ?? "") == (remote.notes ?? "")
            && local.startMs == remote.startMs
            && local.endMs == remote.endMs
    }
}
