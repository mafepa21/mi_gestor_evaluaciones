import SwiftUI

@main
struct MiGestorKMPiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("theme_mode") private var themeModeRawValue: String = AppThemeMode.system.rawValue

    private var themeMode: AppThemeMode {
        AppThemeMode(rawValue: themeModeRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            AppleAppRootView(themeMode: themeMode)
                .onChange(of: scenePhase) { newPhase in
                    handleScenePhase(newPhase)
                }
        }
    }

    private func handleScenePhase(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            NotificationCenter.default.post(name: .appleAppDidBecomeActive, object: nil)
        case .background:
            NotificationCenter.default.post(name: .appleAppDidEnterBackground, object: nil)
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}
