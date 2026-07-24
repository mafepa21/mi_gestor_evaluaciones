import SwiftUI

/// Estado derivado de sincronización para mostrar en la toolbar del workspace.
///
/// No introduce estado nuevo: se calcula a partir de los valores ya publicados
/// por `DashboardBridgeStore` (`syncStatusMessage`, `syncPendingChanges`,
/// `syncLastRunAt`, `pairedSyncHost`), que a su vez reflejan el `KmpBridge`.
enum SyncStatusBadgeState: Equatable {
    /// No hay ningún host de sync LAN emparejado.
    case inactivo
    /// Hay cambios pendientes de sincronizar.
    case pendiente(count: Int)
    /// El último mensaje de estado indica un fallo de sincronización.
    case error(mensaje: String)
    /// Sincronizado y sin cambios pendientes.
    case sincronizado

    var systemImage: String {
        switch self {
        case .inactivo:
            return "bolt.horizontal.circle"
        case .pendiente:
            return "clock.badge"
        case .error:
            return "exclamationmark.triangle"
        case .sincronizado:
            return "checkmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .inactivo:
            return .secondary
        case .pendiente:
            return IOSAppStyle.warning
        case .error:
            return IOSAppStyle.danger
        case .sincronizado:
            return IOSAppStyle.success
        }
    }

    var shortText: String? {
        switch self {
        case .inactivo:
            return nil
        case .pendiente(let count):
            return "\(count)"
        case .error:
            return nil
        case .sincronizado:
            return nil
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .inactivo:
            return "Sincronización: inactiva, sin equipo emparejado"
        case .pendiente(let count):
            return "Sincronización: \(count) cambio\(count == 1 ? "" : "s") pendiente\(count == 1 ? "" : "s")"
        case .error(let mensaje):
            return "Sincronización: error, \(mensaje)"
        case .sincronizado:
            return "Sincronización: al día"
        }
    }
}

/// Deriva el estado del badge a partir de los campos ya publicados por
/// `DashboardBridgeStore`. Mantiene la lógica separada de la vista para
/// facilitar su verificación por lectura.
func resolvedSyncStatusBadgeState(
    syncStatusMessage: String,
    syncPendingChanges: Int,
    pairedSyncHost: String?
) -> SyncStatusBadgeState {
    guard pairedSyncHost != nil else {
        return .inactivo
    }

    if syncPendingChanges > 0 {
        return .pendiente(count: syncPendingChanges)
    }

    let mensajeNormalizado = syncStatusMessage.lowercased()
    if mensajeNormalizado.contains("fallido") || mensajeNormalizado.contains("error") || mensajeNormalizado.contains("failed") {
        return .error(mensaje: syncStatusMessage)
    }

    return .sincronizado
}

/// Badge no intrusivo para la toolbar del workspace que muestra el estado de
/// sincronización local (LAN). Reutiliza el estado ya publicado por
/// `DashboardBridgeStore`; no crea estado nuevo en el bridge.
struct SyncStatusBadge: View {
    let syncStatusMessage: String
    let syncPendingChanges: Int
    let syncLastRunAt: Date?
    let pairedSyncHost: String?

    private var state: SyncStatusBadgeState {
        resolvedSyncStatusBadgeState(
            syncStatusMessage: syncStatusMessage,
            syncPendingChanges: syncPendingChanges,
            pairedSyncHost: pairedSyncHost
        )
    }

    private var accessibilityHintText: String {
        if let syncLastRunAt {
            return "Última sincronización: \(formattedLastRun(syncLastRunAt))"
        }
        return "Aún no se ha registrado ninguna sincronización"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: state.systemImage)
                .font(.footnote.weight(.semibold))
            if let shortText = state.shortText {
                Text(shortText)
                    .font(.footnote.weight(.semibold))
            }
        }
        .foregroundStyle(state.tint)
        .padding(.horizontal, state.shortText == nil ? 6 : 10)
        .padding(.vertical, 6)
        .background(state.tint.opacity(0.12), in: Capsule())
        .opacity(state == .inactivo ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityHint(accessibilityHintText)
    }

    private func formattedLastRun(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "hoy a las \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
