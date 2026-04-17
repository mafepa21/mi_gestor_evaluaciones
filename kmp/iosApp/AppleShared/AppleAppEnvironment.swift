import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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

struct AppleCommandCenterState: Equatable {
    var statusMessage: String = ""
    var pairingPayload: String? = nil
    var pairingHost: String? = nil
    var pairingPin: String? = nil
    var isAvailable: Bool = false

    static let unavailable = AppleCommandCenterState()
}

private struct UiFeatureFlagsKey: EnvironmentKey {
    static let defaultValue = UiFeatureFlags.default
}

private struct AppThemeModeKey: EnvironmentKey {
    static let defaultValue: AppThemeMode = .system
}

private struct AppleCommandCenterStateKey: EnvironmentKey {
    static let defaultValue = AppleCommandCenterState.unavailable
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

    var appleCommandCenterState: AppleCommandCenterState {
        get { self[AppleCommandCenterStateKey.self] }
        set { self[AppleCommandCenterStateKey.self] = newValue }
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
        : appSecondarySystemBackgroundColor()
}

func contrastingTextColor(for background: Color) -> Color {
    let rgba = resolvedPlatformColorComponents(for: background)
    if let red = rgba.red, let green = rgba.green, let blue = rgba.blue {
        let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
        return luminance > 0.56 ? .black : .white
    }

    if let white = rgba.white {
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

private struct ResolvedColorComponents {
    var red: CGFloat?
    var green: CGFloat?
    var blue: CGFloat?
    var white: CGFloat?
}

private func resolvedPlatformColorComponents(for color: Color) -> ResolvedColorComponents {
#if canImport(UIKit)
    let resolved = UIColor(color).resolvedColor(with: UITraitCollection.current)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var white: CGFloat = 0
    var alpha: CGFloat = 1

    if resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
        return ResolvedColorComponents(red: red, green: green, blue: blue, white: nil)
    }

    if resolved.getWhite(&white, alpha: &alpha) {
        return ResolvedColorComponents(red: nil, green: nil, blue: nil, white: white)
    }

    return ResolvedColorComponents()
#elseif canImport(AppKit)
    let resolved = NSColor(color)
    if let rgb = resolved.usingColorSpace(.sRGB) {
        return ResolvedColorComponents(
            red: rgb.redComponent,
            green: rgb.greenComponent,
            blue: rgb.blueComponent,
            white: nil
        )
    }

    if let gray = resolved.usingColorSpace(.genericGray) {
        return ResolvedColorComponents(red: nil, green: nil, blue: nil, white: gray.whiteComponent)
    }

    return ResolvedColorComponents()
#else
    return ResolvedColorComponents()
#endif
}
