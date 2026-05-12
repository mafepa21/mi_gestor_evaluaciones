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
            MacRootView(session: session)
                .environment(\.appThemeMode, themeMode)
                .preferredColorScheme(themeMode.colorSchemeOverride)
                .frame(minWidth: 900, minHeight: 600)
                .appOnChange(of: scenePhase) { _, newPhase in
                    handleScenePhase(newPhase)
                }
        }
        .commands {
            CommandGroup(replacing: .textFormatting) {}

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
            sanitizeMainMenu()
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
