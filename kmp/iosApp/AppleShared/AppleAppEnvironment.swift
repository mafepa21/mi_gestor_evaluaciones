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

enum ApplePairingServiceState: Equatable {
    case stopped
    case starting
    case running(host: String, port: Int, pin: String, sessionId: String, fingerprint: String?)
    case networkError(message: String)
    case connected(host: String, port: Int, pin: String, sessionId: String, fingerprint: String?, deviceName: String?)
    case failed(message: String)

    var showsPairingCode: Bool {
        switch self {
        case .running, .connected:
            return true
        case .stopped, .starting, .networkError, .failed:
            return false
        }
    }

    var pairingHost: String? {
        switch self {
        case let .running(host, _, _, _, _), let .connected(host, _, _, _, _, _):
            return host
        case .stopped, .starting, .networkError, .failed:
            return nil
        }
    }

    var pairingPort: Int? {
        switch self {
        case let .running(_, port, _, _, _), let .connected(_, port, _, _, _, _):
            return port
        case .stopped, .starting, .networkError, .failed:
            return nil
        }
    }

    var pairingPin: String? {
        switch self {
        case let .running(_, _, pin, _, _), let .connected(_, _, pin, _, _, _):
            return pin
        case .stopped, .starting, .networkError, .failed:
            return nil
        }
    }

    var sessionId: String? {
        switch self {
        case let .running(_, _, _, sessionId, _), let .connected(_, _, _, sessionId, _, _):
            return sessionId
        case .stopped, .starting, .networkError, .failed:
            return nil
        }
    }

    var fingerprint: String? {
        switch self {
        case let .running(_, _, _, _, fingerprint), let .connected(_, _, _, _, fingerprint, _):
            return fingerprint
        case .stopped, .starting, .networkError, .failed:
            return nil
        }
    }

    var pairingPayload: String? {
        guard let host = pairingHost,
              let port = pairingPort,
              let pin = pairingPin,
              let sessionId = sessionId,
              !host.isEmpty,
              !pin.isEmpty,
              !sessionId.isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "migestor"
        components.host = "pair"
        var queryItems = [
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "port", value: "\(port)"),
            URLQueryItem(name: "pin", value: pin),
            URLQueryItem(name: "sid", value: sessionId),
        ]
        if let fingerprint, !fingerprint.isEmpty {
            queryItems.append(URLQueryItem(name: "fp", value: fingerprint))
        }
        components.queryItems = queryItems

        return components.url?.absoluteString
            ?? "migestor://pair?host=\(host)&port=\(port)&pin=\(pin)&sid=\(sessionId)"
    }
}

struct AppleCommandCenterState: Equatable {
    var statusMessage: String = ""
    var serviceState: ApplePairingServiceState = .stopped
    var isAvailable: Bool = false

    var pairingPayload: String? { serviceState.pairingPayload }
    var pairingHost: String? { serviceState.pairingHost }
    var pairingPort: Int? { serviceState.pairingPort }
    var pairingPin: String? { serviceState.pairingPin }

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

enum AppSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum AppRadius {
    static let input: CGFloat = 8
    static let card: CGFloat = 12
    static let panel: CGFloat = 20
    static let sheet: CGFloat = 32
}

enum AppTypography {
    static let largeTitle = Font.system(.largeTitle, design: .rounded).weight(.black)
    static let title = Font.system(.title2, design: .rounded).weight(.black)
    static let section = Font.system(.headline, design: .rounded).weight(.bold)
    static let body = Font.system(.subheadline, design: .rounded).weight(.semibold)
    static let caption = Font.system(.caption, design: .rounded).weight(.semibold)
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

struct AppSurfaceCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat = AppRadius.card
    var padding: CGFloat = AppSpacing.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
    }
}

extension View {
    func appSurfaceCard(radius: CGFloat = AppRadius.card, padding: CGFloat = AppSpacing.md) -> some View {
        modifier(AppSurfaceCardModifier(radius: radius, padding: padding))
    }
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
