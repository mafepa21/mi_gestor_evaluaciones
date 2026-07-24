import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AppleAppRootView: View {
    @StateObject private var bridge = KmpBridge()
    @ObservedObject private var backupService = AppleBackupService.shared
    @ObservedObject private var rescueService = AppleDatabaseRescueService.shared
    @State private var lifecycleObserver: AppleLifecycleBridgeObserver?
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @AppStorage("mac_reduce_motion") private var prefersReducedMotion = false
    private let themeMode: AppThemeMode
    private let commandCenterState: AppleCommandCenterState

    init(
        themeMode: AppThemeMode,
        commandCenterState: AppleCommandCenterState = .unavailable
    ) {
        self.themeMode = themeMode
        self.commandCenterState = commandCenterState
    }

    private var uiFeatureFlags: UiFeatureFlags {
        UiFeatureFlags.default.withReducedMotion(accessibilityReduceMotion || prefersReducedMotion)
    }

    var body: some View {
#if os(macOS)
        ContentView()
            .environmentObject(bridge)
            .environment(\.uiFeatureFlags, uiFeatureFlags)
            .environment(\.appThemeMode, themeMode)
            .environment(\.appleCommandCenterState, commandCenterState)
            .preferredColorScheme(themeMode.colorSchemeOverride)
            .task {
                await bridge.bootstrap()
                bridge.onAppDidBecomeActive()
                if lifecycleObserver == nil {
                    lifecycleObserver = AppleLifecycleBridgeObserver(bridge: bridge)
                }
                backupService.scanQuarantinedDatabases()
            }
            .quarantinedDataNotice(backupService: backupService)
#else
        IOSRootView()
            .environmentObject(bridge)
            .environment(\.uiFeatureFlags, uiFeatureFlags)
            .environment(\.appThemeMode, themeMode)
            .environment(\.appleCommandCenterState, commandCenterState)
            .preferredColorScheme(themeMode.colorSchemeOverride)
            .task {
                rescueService.checkForPendingRescue()
                await bridge.bootstrap()
                bridge.onAppDidBecomeActive()
                if lifecycleObserver == nil {
                    lifecycleObserver = AppleLifecycleBridgeObserver(bridge: bridge)
                }
                backupService.scanQuarantinedDatabases()
            }
            .overlay {
                if backupService.needsRestart {
                    RestartRequiredOverlay()
                }
            }
            .alert(
                "No se pudo abrir la base de datos",
                isPresented: $rescueService.isAlertPresented,
                presenting: rescueService.pendingRescue
            ) { marker in
                Button("Reintentar apertura") {
                    rescueService.retryRescuedDatabase()
                }
                Button("Seguir con base vacía", role: .destructive) {
                    rescueService.continueWithEmptyDatabase()
                }
            } message: { marker in
                Text(marker.displayMessage)
            }
            .quarantinedDataNotice(backupService: backupService)
#endif
    }
}

/// Avisa una sola vez de que el arranque apartó una base de datos que no pudo abrir.
///
/// Existe porque la app se abre vacía cuando eso pasa y, sin este aviso, la pérdida es
/// indistinguible de un borrado real: los datos siguen en disco pero nadie lo dice.
private struct QuarantinedDataNotice: ViewModifier {
    @ObservedObject var backupService: AppleBackupService
    @AppStorage("diagnostics.quarantine.acknowledged") private var acknowledgedId: String = ""

    private var pending: AppleQuarantinedDatabase? {
        backupService.quarantinedDatabases
            .first { $0.looksRecoverable && $0.id != acknowledgedId }
    }

    func body(content: Content) -> some View {
        content.alert(
            "Se encontraron datos apartados",
            isPresented: .constant(pending != nil),
            presenting: pending
        ) { item in
            Button("Entendido") { acknowledgedId = item.id }
#if os(macOS)
            Button("Mostrar en Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                acknowledgedId = item.id
            }
#endif
        } message: { item in
            Text(quarantineMessage(for: item))
        }
    }

    private func quarantineMessage(for item: AppleQuarantinedDatabase) -> String {
        let counts = item.summary.map {
            "\($0.classCount) clases y \($0.studentCount) alumnos"
        } ?? "contenido no legible"
        let date = item.quarantinedAt.formatted(date: .abbreviated, time: .shortened)
        return """
        El \(date) la aplicación no pudo abrir su base de datos y arrancó con una vacía. \
        La anterior no se ha borrado: contiene \(counts) y ocupa \(item.sizeText).

        Está en:
        \(item.url.path)

        Puedes recuperarla desde Ajustes › Copias de seguridad, o pedir ayuda antes de \
        seguir trabajando para no sobrescribirla.
        """
    }
}

private extension View {
    func quarantinedDataNotice(backupService: AppleBackupService) -> some View {
        modifier(QuarantinedDataNotice(backupService: backupService))
    }
}

struct RestartRequiredOverlay: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Reinicia la aplicación")
                .font(.title3.weight(.semibold))
            Text("Los datos se han modificado en el dispositivo. Cierra y vuelve a abrir MiGestor para continuar con normalidad.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .ignoresSafeArea()
    }
}
