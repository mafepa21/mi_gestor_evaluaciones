import SwiftUI

struct AppleAppRootView: View {
    @StateObject private var bridge = KmpBridge()
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
                await bridge.bootstrap()
                bridge.onAppDidBecomeActive()
                if lifecycleObserver == nil {
                    lifecycleObserver = AppleLifecycleBridgeObserver(bridge: bridge)
                }
            }
#endif
    }
}
