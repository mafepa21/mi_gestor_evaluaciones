import SwiftUI
import AppKit

enum MacLiquidGlassSurfaceRole {
    case primaryPanel
    case secondaryPanel
    case readableSurface
}

enum MacLiquidGlassStyle {
    static let hairlineWidth: CGFloat = 0.5

    static let pageBackground = Color(nsColor: .windowBackgroundColor)
    static let readableSurfaceFallback = Color(nsColor: .controlBackgroundColor).opacity(0.92)
    static let primaryPanelFallback = Color(nsColor: .controlBackgroundColor).opacity(0.78)
    static let secondaryPanelFallback = Color(nsColor: .quaternaryLabelColor).opacity(0.08)

    static let hairlineBorder = Color(nsColor: .separatorColor).opacity(0.55)
    static let inactiveBorder = Color(nsColor: .separatorColor).opacity(0.42)

    static func fill(for role: MacLiquidGlassSurfaceRole, isActive: Bool) -> AnyShapeStyle {
        switch role {
        case .primaryPanel:
            return AnyShapeStyle(isActive ? .regularMaterial : .thinMaterial)
        case .secondaryPanel:
            return AnyShapeStyle(isActive ? .thinMaterial : .ultraThinMaterial)
        case .readableSurface:
            return AnyShapeStyle(readableSurfaceFallback)
        }
    }

    static func border(for role: MacLiquidGlassSurfaceRole, isActive: Bool, tint: Color?) -> Color {
        if isActive, let tint {
            return tint.opacity(role == .readableSurface ? 0.35 : 0.42)
        }
        return isActive ? hairlineBorder.opacity(0.85) : inactiveBorder
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

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                shape.fill(MacLiquidGlassStyle.fill(for: role, isActive: isActive))
            }
            .overlay {
                shape.stroke(
                    MacLiquidGlassStyle.border(for: role, isActive: isActive, tint: tint),
                    lineWidth: MacLiquidGlassStyle.hairlineWidth
                )
            }
            .clipShape(shape)
    }
}

extension View {
    func macLiquidGlassPanel(
        _ role: MacLiquidGlassSurfaceRole = .primaryPanel,
        cornerRadius: CGFloat = MacAppStyle.cardRadius,
        isActive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(
            MacLiquidGlassPanelModifier(
                role: role,
                cornerRadius: cornerRadius,
                isActive: isActive,
                tint: tint
            )
        )
    }
}
