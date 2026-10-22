import SwiftUI

/// Recarga una pantalla cuando llegan por Sync LAN cambios que le afectan.
///
/// Las pantallas que cargan sus datos en `.task` y los guardan en `@State`
/// no se enteraban de lo que llegaba del otro dispositivo hasta salir y
/// volver a entrar.
private struct LanSyncReloadModifier: ViewModifier {
    let screen: LanSyncRefreshPlan.Screen
    let perform: @MainActor () async -> Void

    @State private var reloadTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .lanSyncRemoteChangesApplied)) { notification in
                let entities = notification.userInfo?[LanSyncRefreshPlan.entitiesUserInfoKey] as? Set<String> ?? []
                guard LanSyncRefreshPlan.affects(screen, entities: entities) else { return }
                // Un lote grande llega en varios eventos seguidos: una sola recarga.
                reloadTask?.cancel()
                reloadTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    await perform()
                }
            }
            .onDisappear {
                reloadTask?.cancel()
                reloadTask = nil
            }
    }
}

extension View {
    func reloadOnLanSync(
        _ screen: LanSyncRefreshPlan.Screen,
        perform: @escaping @MainActor () async -> Void
    ) -> some View {
        modifier(LanSyncReloadModifier(screen: screen, perform: perform))
    }
}
