import SwiftUI
import AppKit

@main
struct MiGestorKMPMacApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @AppStorage("theme_mode") private var themeModeRawValue: String = AppThemeMode.system.rawValue
    @StateObject private var session = MacAppSessionController()
    // Ver `MacAppDelegate` más abajo: desactiva la restauración de estado de ventanas de AppKit.
    // No es la causa raíz del crash "Update Constraints in Window pass" (esa era el
    // `.frame(minWidth:minHeight:)` de más abajo, ya sustituido), pero se deja como medida
    // adicional: con state restoration activa, `defaults` sigue acumulando entradas de autosave
    // de ventana atadas a nombres de tipo generados que cambian en cada build.
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate

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
                // Antes había un `.frame(minWidth: 900, minHeight: 600)` aquí. Ese modificador,
                // combinado con la restauración de estado de ventana que Xcode fuerza al lanzar
                // la app (scheme con `ignoresPersistentStateOnLaunch = "NO"`), hacía que AppKit
                // entrara en un bucle de layout al arrancar: NSException "The window has been
                // marked as needing another Update Constraints in Window pass, but it has already
                // had more Update Constraints in Window passes than there are views in the
                // window.", que abortaba el proceso mientras aún se veía "Preparando shell
                // macOS…". Se reprodujo de forma determinista bajo Xcode (Run) y desapareció al
                // quitar el `.frame(minWidth:minHeight:)`. El tamaño mínimo se fija ahora vía
                // AppKit puro (`MacWindowMinSizeSetter` más abajo), que no participa en el pase
                // de Auto Layout de SwiftUI y no reproduce el bucle.
                .background(MacWindowMinSizeSetter(minSize: NSSize(width: 900, height: 600)))
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
        // HStack + Divider en vez de HSplitView: se elimina el NSSplitView (mismo antipatrón
        // de constraints de AppKit corregido en reuniones/alumnado/sync) para descartar el
        // crash de "Update Constraints in Window pass".
        HStack(spacing: 0) {
            MacBackupsView(store: session.backupStore)
                .frame(minWidth: 520, maxWidth: .infinity)

            Divider()

            MacBackupInspectorView(store: session.backupStore)
                .frame(width: 360)
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

/// Desactiva la restauración de estado de ventanas de AppKit (`NSWindowRestoration`).
///
/// No es la causa raíz del crash de arranque bajo Xcode (esa era el `.frame(minWidth:minHeight:)`
/// del `WindowGroup`, ver comentario en `MiGestorKMPMacApp.body` y en `MacWindowMinSizeSetter`),
/// pero el scheme `MiGestorKMPMac` tiene `ignoresPersistentStateOnLaunch = "NO"`, así que Xcode
/// lanza la app pidiéndole a AppKit que restaure la ventana previa. `defaults` acumula, build
/// tras build, entradas de autosave de `NSSplitView`/frame de ventana bajo `com.migestor.mac`
/// atadas a nombres de tipo de Swift generados (que cambian en cada recompilación); desactivar la
/// restauración evita que esa basura se siga acumulando y se reconcilie con el layout actual.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }
}

/// Fija `NSWindow.minSize` directamente en AppKit, sin pasar por el sistema de constraints de
/// SwiftUI. Sustituye a `.frame(minWidth:minHeight:)` en el contenido del `WindowGroup` (ver
/// comentario en `MiGestorKMPMacApp.body`) porque ese modificador es el que disparaba el bucle
/// de "Update Constraints in Window pass" al restaurar el estado de la ventana bajo Xcode.
private struct MacWindowMinSizeSetter: NSViewRepresentable {
    let minSize: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.minSize = minSize
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.minSize = minSize
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
