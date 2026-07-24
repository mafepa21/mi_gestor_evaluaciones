import SwiftUI

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
            }
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
#endif
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
