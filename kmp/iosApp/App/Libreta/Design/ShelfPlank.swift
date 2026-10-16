import SwiftUI

/// Balda de madera vista de frente: una cara superior en leve perspectiva (donde apoyan
/// los lomos) y un frente con vetas. Proyecta una sombra suave sobre la mesa.
/// Ocupa el ancho propuesto y `ShelfPlank.height` de alto.
struct ShelfPlank: View {
    /// Profundidad visible de la cara superior.
    static let topDepth: CGFloat = 12
    /// Alto del frente.
    static let frontHeight: CGFloat = 18
    static var height: CGFloat { topDepth + frontHeight }

    var seed: UInt64
    /// Resalta la balda (p. ej. al arrastrar un cuaderno encima).
    var isHighlighted: Bool

    init(seed: UInt64 = 1, isHighlighted: Bool = false) {
        self.seed = seed
        self.isHighlighted = isHighlighted
    }

    var body: some View {
        VStack(spacing: 0) {
            // Cara superior: más oscura al fondo (sombra de los lomos), clara en el borde.
            ShelfTopShape(inset: 7)
                .fill(LinearGradient(colors: [Theme.shelfWoodEdge, Theme.shelfWoodTop],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: Self.topDepth)

            ZStack {
                LinearGradient(colors: [Theme.shelfWood, Theme.shelfWoodEdge],
                               startPoint: .top, endPoint: .bottom)
                WoodGrain(seed: seed)
                // Bisel: filo de luz en la arista.
                VStack(spacing: 0) {
                    Rectangle().fill(Color.white.opacity(0.22)).frame(height: 1)
                    Spacer(minLength: 0)
                    Rectangle().fill(Color.black.opacity(0.18)).frame(height: 1)
                }
            }
            .frame(height: Self.frontHeight)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 3,
                                              style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 2)
                .opacity(isHighlighted ? 1 : 0)
        }
        .compositingGroup()
        .shadow(color: Theme.shadow, radius: 9, x: 0, y: 8)
        .shadow(color: Theme.shadow, radius: 1, x: 0, y: 1)
        .accessibilityHidden(true)
    }
}

/// Trapecio: el borde de atrás (arriba) es algo más estrecho que el de delante.
private struct ShelfTopShape: Shape {
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Vetas finas y onduladas, deterministas (misma semilla, mismo dibujo).
private struct WoodGrain: View {
    var seed: UInt64

    var body: some View {
        Canvas { ctx, size in
            guard size.width > 0, size.height > 0 else { return }
            var rng = StableRandom(seed: seed)
            var path = Path()
            let lines = max(3, Int(size.height / 2.5))
            for _ in 0..<lines {
                let y0 = rng.unit() * size.height
                let amplitude = 0.3 + rng.unit() * 1.3
                let wavelength = 70 + rng.unit() * 180
                let phase = rng.unit() * .pi * 2
                var x: CGFloat = 0
                path.move(to: CGPoint(x: 0, y: y0 + amplitude * sin(phase)))
                while x < size.width {
                    x += 8
                    path.addLine(to: CGPoint(x: x, y: y0 + amplitude * sin(phase + x / wavelength * 2 * .pi)))
                }
            }
            ctx.stroke(path, with: .color(Theme.shelfGrain), lineWidth: 0.6)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Balda") {
    VStack(spacing: 60) {
        ShelfPlank(seed: 3)
        ShelfPlank(seed: 8, isHighlighted: true)
    }
    .padding(40)
    .background(ShelfBackground())
}
