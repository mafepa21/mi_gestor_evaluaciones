import SwiftUI

// MARK: - Texto que crece (Dynamic Type)

/// Sustituto de `.font(.system(size:))`: mantiene el tamaño de diseño y lo
/// escala con el tamaño de texto del sistema (Ajustes > Accesibilidad). El
/// estilo de referencia se deduce del tamaño, así un 11 crece como `.caption2`
/// y un 17 como `.body`. En macOS no hay Dynamic Type y el tamaño queda igual.
///
/// En el Cuaderno se usa a través de `.notebookFont`; fuera, con
/// `.scaledSystemFont`. Mínimo de diseño: 11 pt.
struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: Self.textStyle(for: size))
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }

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

extension View {
    /// Letra del sistema con tamaño propio que crece con Dynamic Type.
    func scaledSystemFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design))
    }
}
