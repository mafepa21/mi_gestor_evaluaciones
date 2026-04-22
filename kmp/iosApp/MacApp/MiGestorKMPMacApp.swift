import SwiftUI

@main
struct MiGestorKMPMacApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("theme_mode") private var themeModeRawValue: String = AppThemeMode.system.rawValue
    @StateObject private var session = MacAppSessionController()
    @StateObject private var layoutState = WorkspaceLayoutState()

    private var themeMode: AppThemeMode {
        AppThemeMode(rawValue: themeModeRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup("MiGestor") {
            MacRootView(session: session)
                .environmentObject(layoutState)
                .preferredColorScheme(themeMode.colorSchemeOverride)
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhase(newPhase)
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refrescar dashboard") {
                    Task {
                        await session.bridge.refreshDashboard(mode: .office)
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            EmptyView()
        }
    }

    private func handleScenePhase(_ newPhase: ScenePhase) {
        session.handleScenePhase(newPhase)
    }
}
