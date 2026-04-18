import SwiftUI

@main
struct MiGestorKMPMacApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("theme_mode") private var themeModeRawValue: String = AppThemeMode.system.rawValue
    @StateObject private var commandCenter = MacCommandCenterCoordinator()

    private var themeMode: AppThemeMode {
        AppThemeMode(rawValue: themeModeRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup("MiGestor") {
            AppleAppRootView(
                themeMode: themeMode,
                commandCenterState: commandCenter.environmentState
            )
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhase(newPhase)
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refrescar dashboard") {}
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            EmptyView()
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
