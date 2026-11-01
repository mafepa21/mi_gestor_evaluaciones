import SwiftUI

/// Posición de una hoja dentro del cuaderno abierto.
enum PageSide {
    /// Una sola hoja por pantalla (iPad en vertical). Encuadernada a la izquierda.
    case single
    /// Hoja izquierda de una doble página (lomo a su derecha).
    case left
    /// Hoja derecha de una doble página (lomo a su izquierda).
    case right
}

/// Una hoja de papel: fondo (`PaperBackground`), el contenido encima (el lienzo de
/// dibujo), sombra del lomo en el lado interior y el canto de hojas apiladas en el
/// exterior.
///
/// El tamaño lo decide quien la usa (p. ej. `.aspectRatio(Theme.pageAspect, contentMode: .fit)`).
/// Las decoraciones no reciben toques: todos los gestos llegan al contenido.
struct PageSheet<Content: View>: View {
    let side: PageSide
    let style: PaperStyle
    /// Hojas apiladas + sombra por debajo. El lector las apaga en la hoja que se
    /// curva (se dibujan fijas debajo) para que no "salten" durante el paso de hoja.
    let showsStack: Bool
    let content: Content

    init(side: PageSide, style: PaperStyle, showsStack: Bool = true, @ViewBuilder content: () -> Content) {
        self.side = side
        self.style = style
        self.showsStack = showsStack
        self.content = content()
    }

    var body: some View {
        ZStack {
            PaperBackground(style: style)
            content
            gutter
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .clipShape(sheetShape)
        .overlay(
            sheetShape
                .stroke(Theme.paperEdgeLine.opacity(0.6), lineWidth: 0.5)
                .allowsHitTesting(false)
        )
        .background {
            if showsStack {
                stackedSheets
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: Forma

    private var radius: CGFloat { Theme.pageCornerRadius }

    /// Esquinas redondeadas solo en el lado exterior; el lado del lomo queda recto.
    private var sheetShape: UnevenRoundedRectangle {
        switch side {
        case .single:
            UnevenRoundedRectangle(
                topLeadingRadius: radius * 0.4,
                bottomLeadingRadius: radius * 0.4,
                bottomTrailingRadius: radius,
                topTrailingRadius: radius,
                style: .continuous
            )
        case .left:
            UnevenRoundedRectangle(
                topLeadingRadius: radius,
                bottomLeadingRadius: radius,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        case .right:
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: radius,
                topTrailingRadius: radius,
                style: .continuous
            )
        }
    }

    /// Dirección del lado exterior: -1 izquierda, +1 derecha.
    private var outward: CGFloat { side == .left ? -1 : 1 }

    // MARK: Decoración

    /// Hojas apiladas por debajo, asomando por el borde exterior e inferior.
    private var stackedSheets: some View {
        ZStack {
            ForEach([3, 2, 1], id: \.self) { i in
                sheetShape
                    .fill(Theme.paperEdge)
                    .overlay(sheetShape.stroke(Theme.paperEdgeLine, lineWidth: 0.5))
                    .offset(x: outward * CGFloat(i) * 1.5, y: CGFloat(i) * 0.9)
            }
            sheetShape.fill(Theme.paper)
        }
        .compositingGroup()
        .shadow(color: Theme.shadow, radius: 7, x: outward * 1.5, y: 3)
    }

    /// Sombra del lomo (o de la encuadernación en hoja única).
    @ViewBuilder
    private var gutter: some View {
        switch side {
        case .left:
            LinearGradient(stops: gutterStops, startPoint: .trailing, endPoint: .leading)
        case .right:
            LinearGradient(stops: gutterStops, startPoint: .leading, endPoint: .trailing)
        case .single:
            LinearGradient(stops: bindingStops, startPoint: .leading, endPoint: .trailing)
        }
    }

    /// Curvatura del papel hacia el lomo en la doble página.
    private var gutterStops: [Gradient.Stop] {
        [
            .init(color: Color.black.opacity(0.17), location: 0),
            .init(color: Color.black.opacity(0.08), location: 0.02),
            .init(color: Color.black.opacity(0.03), location: 0.06),
            .init(color: Color.black.opacity(0.0), location: 0.12),
            .init(color: Color.black.opacity(0.0), location: 1)
        ]
    }

    /// Sombra más corta y suave para la hoja única.
    private var bindingStops: [Gradient.Stop] {
        [
            .init(color: Color.black.opacity(0.10), location: 0),
            .init(color: Color.black.opacity(0.03), location: 0.025),
            .init(color: Color.black.opacity(0.0), location: 0.06),
            .init(color: Color.black.opacity(0.0), location: 1)
        ]
    }
}

// MARK: - Previews

#Preview("Doble página") {
    ZStack {
        SpreadBackdrop(color: .brown)
        HStack(spacing: 0) {
            PageSheet(side: .left, style: .ruled) { Color.clear }
                .overlay(alignment: .bottom) {
                    PageNumberLabel(number: 12, alignment: .leading).padding(14)
                }
            PageSheet(side: .right, style: .ruled) { Color.clear }
                .overlay(alignment: .bottom) {
                    PageNumberLabel(number: 13, alignment: .trailing).padding(14)
                }
        }
        .aspectRatio(Theme.pageAspect * 2, contentMode: .fit)
        .padding(Theme.backdropInset)
    }
    .aspectRatio(1.4, contentMode: .fit)
    .padding(30)
    .background(Theme.readerBackground)
}

#Preview("Hoja única") {
    ZStack {
        SpreadBackdrop()
        PageSheet(side: .single, style: .dotted) { Color.clear }
            .aspectRatio(Theme.pageAspect, contentMode: .fit)
            .padding(Theme.backdropInset)
    }
    .aspectRatio(0.76, contentMode: .fit)
    .padding(30)
    .background(Theme.readerBackground)
}
