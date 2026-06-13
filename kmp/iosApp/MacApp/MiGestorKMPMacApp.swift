import SwiftUI
import AppKit

@main
struct MiGestorKMPMacApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
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
            ToolbarCommands()
            AppleAppCommands()

            CommandGroup(replacing: .textFormatting) {}

            CommandGroup(after: .newItem) {
                Button("Refrescar") {
                    AppleAppCommand.post(.appleAppRefreshRequested)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Abrir Backups") {
                    openWindow(id: MacDesktopWindowID.backups.rawValue)
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Crear backup ahora") {
                    AppleAppCommand.post(.appleAppBackupRequested)
                }

                Button("Abrir Sync LAN") {
                    openWindow(id: MacDesktopWindowID.sync.rawValue)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Mostrar u ocultar inspector") {
                    AppleAppCommand.post(.appleAppToggleInspectorRequested)
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                Button("Mostrar u ocultar barra lateral") {
                    AppleAppCommand.post(.appleAppToggleSidebarRequested)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])

                Button("Refrescar dashboard") {
                    AppleAppCommand.post(.appleAppRefreshRequested)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            MacSettingsScene(session: session)
        }

        Window("Informes", id: MacDesktopWindowID.reports.rawValue) {
            MacAuxiliaryWindowRoot(themeMode: themeMode) {
                MacReportsWindowScene(session: session)
            }
            .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1000, height: 760)
        .defaultPosition(.center)

        Window("Backups", id: MacDesktopWindowID.backups.rawValue) {
            MacAuxiliaryWindowRoot(themeMode: themeMode) {
                MacBackupsWindowScene(session: session)
            }
            .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 900, height: 640)
        .defaultPosition(.center)

        Window("Sync LAN", id: MacDesktopWindowID.sync.rawValue) {
            MacAuxiliaryWindowRoot(themeMode: themeMode) {
                MacSyncWindowScene(session: session)
            }
            .frame(minWidth: 780, minHeight: 560)
        }
        .defaultSize(width: 860, height: 620)
        .defaultPosition(.center)
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

enum MacDesktopWindowID: String {
    case reports
    case backups
    case sync
}

private struct MacSettingsScene: View {
    @ObservedObject var session: MacAppSessionController

    var body: some View {
        MacSettingsView(session: session, commandCenter: session.commandCenter, backupStore: session.backupStore) {
            session.selectedFeature = .sync
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}

private struct MacReportsWindowScene: View {
    @ObservedObject var session: MacAppSessionController
    @StateObject private var selection = StudentSelectionStore()

    var body: some View {
        MacReportsView(
            bridge: session.bridge,
            selectedClassId: selection.selectedClassBinding,
            selectedStudentId: selection.selectedStudentBinding
        )
        .controlSize(.regular)
        .task {
            session.start()
        }
    }
}

private struct MacBackupsWindowScene: View {
    @ObservedObject var session: MacAppSessionController

    var body: some View {
        HSplitView {
            MacBackupsView(store: session.backupStore)
                .frame(minWidth: 520)

            MacBackupInspectorView(store: session.backupStore)
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
        }
        .background(MacAppStyle.pageBackground)
        .controlSize(.regular)
        .task {
            session.start()
        }
    }
}

private struct MacSyncWindowScene: View {
    @ObservedObject var session: MacAppSessionController

    var body: some View {
        MacSyncView(bridge: session.bridge, commandCenter: session.commandCenter)
            .controlSize(.regular)
            .task {
                session.start()
            }
    }
}

private struct MacAuxiliaryWindowRoot<Content: View>: View {
    let themeMode: AppThemeMode
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @AppStorage("mac_reduce_motion") private var prefersReducedMotion = false

    init(themeMode: AppThemeMode, @ViewBuilder content: () -> Content) {
        self.themeMode = themeMode
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.appThemeMode, themeMode)
            .preferredColorScheme(themeMode.colorSchemeOverride)
            .environment(
                \.uiFeatureFlags,
                UiFeatureFlags.default.withReducedMotion(accessibilityReduceMotion || prefersReducedMotion)
            )
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
