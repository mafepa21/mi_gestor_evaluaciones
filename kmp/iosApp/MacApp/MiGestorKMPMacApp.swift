import SwiftUI
import AppKit

@main
struct MiGestorKMPMacApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("theme_mode") private var themeModeRawValue: String = AppThemeMode.system.rawValue
    @StateObject private var session = MacAppSessionController()

    private var themeMode: AppThemeMode {
        AppThemeMode(rawValue: themeModeRawValue) ?? .system
    }

    init() {
        MacWritingToolsMenuSanitizer.install()
    }

    var body: some Scene {
        WindowGroup("MiGestor") {
            MacApplicationRootView(session: session)
                .environment(\.appThemeMode, themeMode)
                .preferredColorScheme(themeMode.colorSchemeOverride)
                .frame(minWidth: 900, minHeight: 600)
                .appOnChange(of: scenePhase) { _, newPhase in
                    handleScenePhase(newPhase)
                }
        }
        .commands {
            CommandGroup(replacing: .textFormatting) {}

            CommandGroup(replacing: .newItem) {
                Button("Nuevo") {
                    NotificationCenter.default.post(name: .macRootNewItemRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(after: .saveItem) {
                Button("Guardar") {
                    NotificationCenter.default.post(name: .macRootSaveRequested, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("Refrescar") {
                    NotificationCenter.default.post(name: .macRootRefreshRequested, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Crear backup") {
                    NotificationCenter.default.post(name: .macRootBackupRequested, object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Exportar informes") {
                    NotificationCenter.default.post(name: .macRootExportRequested, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Mostrar u ocultar inspector") {
                    NotificationCenter.default.post(name: .macRootToggleInspectorRequested, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                Button("Mostrar u ocultar barra lateral") {
                    NotificationCenter.default.post(name: .macRootToggleSidebarRequested, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])

                Button("Refrescar dashboard") {
                    NotificationCenter.default.post(name: .macRootRefreshRequested, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            MacSettingsScene(session: session)
        }
    }

    private func handleScenePhase(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            session.handleScenePhase(.active)
            NotificationCenter.default.post(name: .appleAppDidBecomeActive, object: nil)
        case .background:
            session.handleScenePhase(.background)
            NotificationCenter.default.post(name: .appleAppDidEnterBackground, object: nil)
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}

private struct MacSettingsScene: View {
    @ObservedObject var session: MacAppSessionController
    @StateObject private var commandCenter = MacCommandCenterCoordinator()
    @StateObject private var backupStore: MacBackupStore

    init(session: MacAppSessionController) {
        self.session = session
        _backupStore = StateObject(wrappedValue: MacBackupStore(bridge: session.bridge))
    }

    var body: some View {
        MacSettingsView(session: session, commandCenter: commandCenter, backupStore: backupStore) {
            session.selectedFeature = .sync
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}

private struct MacApplicationRootView: View {
    @ObservedObject var session: MacAppSessionController
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @AppStorage("mac_reduce_motion") private var prefersReducedMotion = false

    var body: some View {
        MacRootView(session: session)
            .environment(
                \.uiFeatureFlags,
                UiFeatureFlags.default.withReducedMotion(accessibilityReduceMotion || prefersReducedMotion)
            )
    }
}

private enum MacWritingToolsMenuSanitizer {
    private static var observers: [NSObjectProtocol] = []

    static func install() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { _ in
            sanitizeMainMenu()
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSMenu.didAddItemNotification,
            object: nil,
            queue: .main
        ) { _ in
            DispatchQueue.main.async {
                sanitizeMainMenu()
            }
        })
    }

    private static func sanitizeMainMenu() {
        guard let mainMenu = NSApplication.shared.mainMenu else { return }
        removeWritingToolsItems(from: mainMenu)
    }

    private static func removeWritingToolsItems(from menu: NSMenu) {
        for item in menu.items.reversed() {
            if item.action == #selector(NSResponder.showWritingTools(_:)) {
                menu.removeItem(item)
                continue
            }
            if let submenu = item.submenu {
                removeWritingToolsItems(from: submenu)
                if submenu.items.isEmpty && item.title.localizedCaseInsensitiveContains("writing") {
                    menu.removeItem(item)
                }
            }
        }
    }
}
