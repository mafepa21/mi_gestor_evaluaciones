import SwiftUI
import UIKit

enum AppThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case darkPremium

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Según el sistema"
        case .light: return "Claro"
        case .darkPremium: return "Oscuro premium"
        }
    }

    var colorSchemeOverride: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .darkPremium: return .dark
        }
    }
}

struct UiFeatureFlags {
    let newShell: Bool
    let notebookToolbarSimplified: Bool
    let accessibilitySurfaceFallback: Bool
    let reduceMotion: Bool

    static let `default` = UiFeatureFlags(
        newShell: true,
        notebookToolbarSimplified: true,
        accessibilitySurfaceFallback: false,
        reduceMotion: false
    )
}

private struct UiFeatureFlagsKey: EnvironmentKey {
    static let defaultValue = UiFeatureFlags.default
}

private struct AppThemeModeKey: EnvironmentKey {
    static let defaultValue: AppThemeMode = .system
}

extension EnvironmentValues {
    var uiFeatureFlags: UiFeatureFlags {
        get { self[UiFeatureFlagsKey.self] }
        set { self[UiFeatureFlagsKey.self] = newValue }
    }

    var appThemeMode: AppThemeMode {
        get { self[AppThemeModeKey.self] }
        set { self[AppThemeModeKey.self] = newValue }
    }
}

func appPageBackground(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
        ? Color(red: 0.05, green: 0.08, blue: 0.14)
        : Color(white: 0.98)
}

func appCardBackground(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
        ? Color(red: 0.10, green: 0.14, blue: 0.22)
        : Color.white
}

func appMutedCardBackground(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
        ? Color(red: 0.13, green: 0.18, blue: 0.27)
        : Color(.secondarySystemBackground)
}

func contrastingTextColor(for background: Color) -> Color {
    let resolved = UIColor(background).resolvedColor(with: UITraitCollection.current)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var white: CGFloat = 0
    var alpha: CGFloat = 1

    if resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
        let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
        return luminance > 0.56 ? .black : .white
    }

    if resolved.getWhite(&white, alpha: &alpha) {
        return white > 0.56 ? .black : .white
    }

    return .primary
}

func contrastingTextColor(for hexColor: String) -> Color {
    contrastingTextColor(for: Color(hex: hexColor))
}

@ViewBuilder
func adaptiveSurfaceBackground(
    accessibilityFallback: Bool,
    fill: Color,
    cornerRadius: CGFloat
) -> some View {
    if accessibilityFallback {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
    } else {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
    }
}

@main
struct MiGestorKMPiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var bridge = KmpBridge()
    private let uiFeatureFlags = UiFeatureFlags.default
    @AppStorage("theme_mode") private var themeModeRawValue: String = AppThemeMode.system.rawValue

    private var themeMode: AppThemeMode {
        AppThemeMode(rawValue: themeModeRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bridge)
                .environment(\.uiFeatureFlags, uiFeatureFlags)
                .environment(\.appThemeMode, themeMode)
                .preferredColorScheme(themeMode.colorSchemeOverride)
                .task {
                    await bridge.bootstrap()
                    bridge.onAppDidBecomeActive()
                }
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .active:
                        bridge.onAppDidBecomeActive()
                    case .background:
                        bridge.onAppDidEnterBackground()
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }
}
