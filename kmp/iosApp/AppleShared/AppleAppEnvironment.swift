import SwiftUI
import MiGestorKit
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

    func withReducedMotion(_ value: Bool) -> UiFeatureFlags {
        UiFeatureFlags(
            newShell: newShell,
            notebookToolbarSimplified: notebookToolbarSimplified,
            accessibilitySurfaceFallback: accessibilitySurfaceFallback,
            reduceMotion: value
        )
    }

    var interactionAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.15)
            : .spring(response: 0.35, dampingFraction: 0.75)
    }

    /// `true` en macOS (interacción por puntero), `false` en iPadOS (táctil).
    /// El puntero exige inmediatez; el tacto tolera curvas algo más largas.
    private var isPointerPlatform: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    /// Fallback común cuando `reduceMotion` está activo: cross-fade breve, sin desplazamientos.
    private var reduceMotionFallback: Animation { .easeInOut(duration: 0.15) }

    // MARK: Rúbricas (celda expandible)

    var rubricOpenAnimation: Animation {
        reduceMotion ? reduceMotionFallback : .spring(response: 0.38, dampingFraction: 0.82)
    }

    var rubricCloseAnimation: Animation {
        reduceMotion ? reduceMotionFallback : .spring(response: 0.30, dampingFraction: 0.90)
    }

    /// Fade-in escalonado del contenido interno de la rúbrica.
    var rubricContentReveal: Animation {
        reduceMotion ? reduceMotionFallback : .easeOut(duration: 0.20)
    }

    // MARK: Menús / popovers custom

    var popoverOpenAnimation: Animation {
        guard !reduceMotion else { return reduceMotionFallback }
        // macOS abre más rápido (0.22) por la expectativa de inmediatez del puntero.
        return .spring(response: isPointerPlatform ? 0.22 : 0.28, dampingFraction: 0.78)
    }

    var popoverCloseAnimation: Animation {
        guard !reduceMotion else { return reduceMotionFallback }
        // macOS: fade puro al perder foco. iPadOS: ease-in con leve scale de salida.
        return isPointerPlatform ? .easeOut(duration: 0.12) : .easeIn(duration: 0.15)
    }

    // MARK: Inspector lateral (panel custom iPadOS; macOS usa `.inspector` nativo)

    var inspectorOpenAnimation: Animation {
        reduceMotion ? reduceMotionFallback : .spring(response: 0.42, dampingFraction: 0.86)
    }

    var inspectorCloseAnimation: Animation {
        reduceMotion ? reduceMotionFallback : .spring(response: 0.35, dampingFraction: 0.92)
    }

    /// Devuelve la curva adecuada según la dirección de la transición del inspector.
    func inspectorAnimation(presented: Bool) -> Animation {
        presented ? inspectorOpenAnimation : inspectorCloseAnimation
    }

    /// Fade-in del contenido del inspector tras completarse el slide (evita text-jitter).
    var inspectorContentReveal: Animation {
        reduceMotion ? reduceMotionFallback : .easeOut(duration: 0.18)
    }

    var inspectorTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
    }

    var bannerTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }
}

@MainActor
enum AppleInteractionFeedback {
    enum Event {
        case selection
        case lightImpact
        case success
        case warning
        case error
    }

    static func play(_ event: Event) {
        #if canImport(UIKit)
        switch event {
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .lightImpact:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        #elseif canImport(AppKit)
        switch event {
        case .selection:
            break
        case .lightImpact, .success:
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        case .warning, .error:
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        #endif
    }
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

extension View {
    /// Resalta al pasar el puntero (Mac/trackpad) o al tocar (Pencil/dedo en iPad).
    @ViewBuilder
    func appInteractiveHighlight() -> some View {
#if os(iOS)
        self.hoverEffect(.highlight)
#else
        self
#endif
    }
}

enum AppleDesignSystem {
    static let pagePadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 24
    static let cardSpacing: CGFloat = 16
    static let cardRadius: CGFloat = 14
    static let controlRadius: CGFloat = 10
    static let chipRadius: CGFloat = 20
    static let inspectorWidth: CGFloat = 360

    static let accent = Color.accentColor
    static let success = Color(red: 0.12, green: 0.65, blue: 0.46)
    static let warning = Color(red: 0.86, green: 0.52, blue: 0.12)
    static let danger = Color(red: 0.90, green: 0.20, blue: 0.22)
    static let border = Color.primary.opacity(0.08)
    static let shadow = Color.black.opacity(0.08)

    static func pageBackground(for colorScheme: ColorScheme) -> Color {
        appPageBackground(for: colorScheme)
    }

    static func cardBackground(for colorScheme: ColorScheme) -> Color {
        appCardBackground(for: colorScheme)
    }

    static func mutedBackground(for colorScheme: ColorScheme) -> Color {
        appMutedCardBackground(for: colorScheme)
    }
}

struct PremiumCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    var padding: CGFloat = AppleDesignSystem.cardSpacing
    var cornerRadius: CGFloat = AppleDesignSystem.cardRadius
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                adaptiveSurfaceBackground(
                    accessibilityFallback: uiFeatureFlags.accessibilitySurfaceFallback,
                    fill: AppleDesignSystem.cardBackground(for: colorScheme).opacity(colorScheme == .dark ? 0.82 : 0.96),
                    cornerRadius: cornerRadius
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(AppleDesignSystem.border, lineWidth: 1)
                }
                .shadow(color: AppleDesignSystem.shadow.opacity(0.65), radius: 16, x: 0, y: 8)
            )
    }
}

struct PremiumToolbarButton: View {
    let title: String
    let systemImage: String
    var isProminent = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Group {
            if isProminent {
                Button(action: action) {
                    Label(title, systemImage: systemImage)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: action) {
                    Label(title, systemImage: systemImage)
                }
                .buttonStyle(.bordered)
            }
        }
        .disabled(isDisabled)
        .accessibilityLabel(title)
    }
}

struct PremiumEmptyState: View {
    let title: String
    let subtitle: String
    var systemImage = "square.stack.3d.up.slash"

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PremiumSectionHeader<Trailing: View>: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?
    @ViewBuilder var trailing: Trailing

    init(
        eyebrow: String? = nil,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                if let eyebrow {
                    Text(eyebrow.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension PremiumSectionHeader where Trailing == EmptyView {
    init(eyebrow: String? = nil, title: String, subtitle: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

struct PremiumInspectorPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppleDesignSystem.cardSpacing) {
                content
            }
            .padding(AppleDesignSystem.pagePadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: AppleDesignSystem.inspectorWidth)
    }
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

// MARK: - Color Hex Initialization
extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleaned.count {
        case 3:
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        default:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        }
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

// MARK: - Identifiable Conformances
extension RubricDetail: @retroactive Identifiable { public var id: Int64 { self.rubric.id } }
extension RubricLevel: @retroactive Identifiable {}
