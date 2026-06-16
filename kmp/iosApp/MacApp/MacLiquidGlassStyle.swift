import SwiftUI
import AppKit

enum MacLiquidGlassSurfaceRole {
    case chrome
    case primaryPanel
    case secondaryPanel
    case readableSurface
    case floatingBanner
    case inspector
}

enum MacLiquidGlassStyle {
    static let hairlineWidth: CGFloat = 0.5

    static let pageBackground = Color(nsColor: .windowBackgroundColor)
    static let readableSurfaceFallback = Color(nsColor: .controlBackgroundColor).opacity(0.92)
    static let primaryPanelFallback = Color(nsColor: .controlBackgroundColor).opacity(0.78)
    static let secondaryPanelFallback = Color(nsColor: .quaternaryLabelColor).opacity(0.08)

    static let hairlineBorder = Color(nsColor: .separatorColor).opacity(0.55)
    static let inactiveBorder = Color(nsColor: .separatorColor).opacity(0.42)
    static let innerHighlight = Color.white.opacity(0.18)
    static let inactiveHighlight = Color.white.opacity(0.08)

    static func fill(for role: MacLiquidGlassSurfaceRole, isActive: Bool) -> AnyShapeStyle {
        switch role {
        case .chrome:
            return AnyShapeStyle(isActive ? .thinMaterial : .ultraThinMaterial)
        case .primaryPanel:
            return AnyShapeStyle(isActive ? .regularMaterial : .thinMaterial)
        case .secondaryPanel:
            return AnyShapeStyle(isActive ? .thinMaterial : .ultraThinMaterial)
        case .readableSurface:
            return AnyShapeStyle(readableSurfaceFallback)
        case .floatingBanner:
            return AnyShapeStyle(.regularMaterial)
        case .inspector:
            return AnyShapeStyle(isActive ? .thinMaterial : .ultraThinMaterial)
        }
    }

    static func border(for role: MacLiquidGlassSurfaceRole, isActive: Bool, tint: Color?) -> Color {
        if isActive, let tint {
            return tint.opacity(role == .readableSurface ? 0.35 : 0.42)
        }
        return isActive ? hairlineBorder.opacity(0.85) : inactiveBorder
    }

    static func highlight(for role: MacLiquidGlassSurfaceRole, isActive: Bool) -> Color {
        switch role {
        case .readableSurface:
            return Color.clear
        case .floatingBanner, .primaryPanel, .chrome:
            return isActive ? innerHighlight : inactiveHighlight
        case .secondaryPanel, .inspector:
            return isActive ? innerHighlight.opacity(0.82) : inactiveHighlight
        }
    }

    static func shadow(for role: MacLiquidGlassSurfaceRole, isActive: Bool) -> (color: Color, radius: CGFloat, y: CGFloat) {
        switch role {
        case .chrome, .readableSurface:
            return (.clear, 0, 0)
        case .secondaryPanel, .inspector:
            return (.black.opacity(isActive ? 0.08 : 0.04), isActive ? 8 : 4, isActive ? 4 : 2)
        case .primaryPanel:
            return (.black.opacity(isActive ? 0.10 : 0.06), isActive ? 14 : 8, isActive ? 7 : 4)
        case .floatingBanner:
            return (.black.opacity(0.12), 16, 8)
        }
    }

    static func glass(for role: MacLiquidGlassSurfaceRole, isActive: Bool, tint: Color?) -> Glass {
        let base: Glass
        switch role {
        case .readableSurface:
            base = .identity
        case .floatingBanner, .primaryPanel:
            base = .regular
        case .chrome, .secondaryPanel, .inspector:
            base = isActive ? .regular : .clear
        }

        if let tint, role != .readableSurface {
            return base.tint(tint.opacity(role == .floatingBanner ? 0.16 : 0.10))
        }
        return base
    }

    static func statusFill(isActive: Bool, tint: Color) -> Color {
        (isActive ? tint : Color.secondary).opacity(isActive ? 0.14 : 0.08)
    }
}

private struct MacLiquidGlassPanelModifier: ViewModifier {
    let role: MacLiquidGlassSurfaceRole
    let cornerRadius: CGFloat
    let isActive: Bool
    let tint: Color?
    let isInteractive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let shadow = MacLiquidGlassStyle.shadow(for: role, isActive: isActive)
        let glass = MacLiquidGlassStyle
            .glass(for: role, isActive: isActive, tint: tint)
            .interactive(isInteractive)

        content
            .background {
                shape.fill(MacLiquidGlassStyle.fill(for: role, isActive: isActive))
            }
            .glassEffect(glass, in: shape)
            .overlay {
                shape.stroke(
                    MacLiquidGlassStyle.border(for: role, isActive: isActive, tint: tint),
                    lineWidth: MacLiquidGlassStyle.hairlineWidth
                )
            }
            .overlay(alignment: .top) {
                shape
                    .stroke(MacLiquidGlassStyle.highlight(for: role, isActive: isActive), lineWidth: 1)
                    .blur(radius: 0.5)
                    .mask {
                        LinearGradient(
                            colors: [.black, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            }
            .clipShape(shape)
            .shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
    }
}

extension View {
    func macLiquidGlassPanel(
        _ role: MacLiquidGlassSurfaceRole = .primaryPanel,
        cornerRadius: CGFloat = MacAppStyle.cardRadius,
        isActive: Bool = false,
        tint: Color? = nil,
        isInteractive: Bool = false
    ) -> some View {
        modifier(
            MacLiquidGlassPanelModifier(
                role: role,
                cornerRadius: cornerRadius,
                isActive: isActive,
                tint: tint,
                isInteractive: isInteractive
            )
        )
    }

    func macLiquidGlassGroup(spacing: CGFloat? = nil) -> some View {
        GlassEffectContainer(spacing: spacing) {
            self
        }
    }
}
