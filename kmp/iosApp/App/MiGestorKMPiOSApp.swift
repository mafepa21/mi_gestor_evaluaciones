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
                .appOnChange(of: scenePhase) { newPhase in
                    handleScenePhase(newPhase)
                }
        }
        .commands {
            AppleAppCommands()
        }
        .backgroundTask(.appRefresh(LanSyncBackgroundRefresh.identifier)) {
            await LanSyncBackgroundRefresh.run()
        }
    }

    private func handleScenePhase(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            NotificationCenter.default.post(name: .appleAppDidBecomeActive, object: nil)
            AppleBackupService.shared.handleScenePhaseForAutomaticBackup(isActive: true)
        case .background:
            NotificationCenter.default.post(name: .appleAppDidEnterBackground, object: nil)
            AppleBackupService.shared.handleScenePhaseForAutomaticBackup(isActive: false)
            LanSyncBackgroundRefresh.schedule()
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}
