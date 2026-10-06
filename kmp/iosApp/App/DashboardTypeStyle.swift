import SwiftUI

// MARK: - Texto que crece (Dynamic Type)

/// Sustituto de `.font(.system(size:))` en el Dashboard: mantiene el tamaño de
/// diseño con la letra estándar y lo escala con el tamaño de texto del sistema
/// (Ajustes > Accesibilidad). Mismo patrón que `.notebookFont` del Cuaderno.
/// En macOS no hay Dynamic Type y el tamaño queda igual.
private struct DashboardScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: DashboardDynamicType.textStyle(for: size))
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

/// Caja cuadrada de un icono que crece al mismo ritmo que el texto de cuerpo,
/// para que el icono no quede pequeño junto a un texto grande.
private struct DashboardScaledIconFrame: ViewModifier {
    @ScaledMetric private var side: CGFloat

    init(side: CGFloat) {
        _side = ScaledMetric(wrappedValue: side, relativeTo: .body)
    }

    func body(content: Content) -> some View {
        content.frame(width: side, height: side)
    }
}

extension View {
    func dashboardFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(DashboardScaledFont(size: size, weight: weight, design: design))
    }

    func dashboardIconFrame(_ side: CGFloat) -> some View {
        modifier(DashboardScaledIconFrame(side: side))
    }
}

enum DashboardDynamicType {
    /// Tope de Dynamic Type del Dashboard: más allá de AX2 las tarjetas y la
    /// fila de cifras dejan de caber en iPhone.
    static let range: ClosedRange<DynamicTypeSize> = .xSmall ... .accessibility2

    /// Estilo de referencia según el tamaño de diseño: un 11 crece como
    /// `.caption2` y un 17 como `.body`.
    static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<12: return .caption2
        case ..<13: return .caption
        case ..<15: return .footnote
        case ..<16: return .subheadline
        case ..<17: return .callout
        case ..<20: return .body
        case ..<22: return .title3
        case ..<28: return .title2
        default: return .title
        }
    }
}
