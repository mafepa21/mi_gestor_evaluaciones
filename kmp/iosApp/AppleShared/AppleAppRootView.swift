import SwiftUI

struct AppleAppRootView: View {
    @StateObject private var bridge = KmpBridge()
    @State private var lifecycleObserver: AppleLifecycleBridgeObserver?
    private let uiFeatureFlags = UiFeatureFlags.default
    private let themeMode: AppThemeMode
    private let commandCenterState: AppleCommandCenterState

    init(
        themeMode: AppThemeMode,
        commandCenterState: AppleCommandCenterState = .unavailable
    ) {
        self.themeMode = themeMode
        self.commandCenterState = commandCenterState
    }

    var body: some View {
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
    }
}
