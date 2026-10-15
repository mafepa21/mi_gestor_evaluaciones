import SwiftUI

/// Cinta de marcapáginas de raso que cuelga por el borde superior de una hoja.
///
/// Ocupa el tamaño que se le dé (proporción recomendada ≈ 1 : 3, p. ej. 18 × 56).
/// El extremo inferior va cortado en cola de golondrina; el tramo superior se
/// oscurece como si saliera de debajo del canto de la hoja.
struct BookmarkRibbon: View {
    let color: Color

    init(color: Color = Theme.ribbon) {
        self.color = color
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                // Raso: más oscuro en los bordes, brillo en el centro.
                RibbonShape()
                    .fill(LinearGradient(
                        stops: [
                            .init(color: color.opacity(1), location: 0),
                            .init(color: color.mix(white: 0.18), location: 0.45),
                            .init(color: color.mix(white: 0.05), location: 0.6),
                            .init(color: color.mix(black: 0.25), location: 1)
                        ],
                        startPoint: .leading, endPoint: .trailing))

                // Sombra del canto en el arranque de la cinta.
                RibbonShape()
                    .fill(LinearGradient(
                        colors: [Color.black.opacity(0.35), Color.black.opacity(0)],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: min(0.25, 10 / max(geo.size.height, 1)))))

                // Hilos del tejido.
                RibbonShape()
                    .stroke(Color.black.opacity(0.18), lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(0.28), radius: max(0.8, w * 0.06), x: 0.5, y: 1)
        }
        .accessibilityLabel(Text("Marcapáginas"))
    }
}

/// Rectángulo con el extremo inferior en cola de golondrina.
struct RibbonShape: Shape {
    /// Profundidad del corte como fracción del ancho.
    var notch: CGFloat = 0.55

    func path(in rect: CGRect) -> Path {
        let depth = rect.width * notch
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - depth))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private extension Color {
    /// Mezcla lineal (RGB) hacia blanco o negro.
    func mix(white amount: Double) -> Color {
        Color(uiColor: UIColor(self).blended(with: .white, amount: amount))
    }
    func mix(black amount: Double) -> Color {
        Color(uiColor: UIColor(self).blended(with: .black, amount: amount))
    }
}

private extension UIColor {
    func blended(with other: UIColor, amount: Double) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(min(max(amount, 0), 1))
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t, alpha: a1)
    }
}

// MARK: - Selección de objetos

/// Marco de selección de un objeto sobre la hoja: línea discontinua en el acento y
/// cuatro tiradores de papel en las esquinas. `scale` es la escala propia del objeto,
/// para que el trazo se vea igual de fino a cualquier tamaño.
struct SelectionOutline: View {
    let scale: Double

    init(scale: Double) {
        self.scale = scale
    }

    var body: some View {
        let k = 1 / max(scale, 0.3)
        let handle = 11 * k
        RoundedRectangle(cornerRadius: 4 * k)
            .strokeBorder(Theme.accent,
                          style: StrokeStyle(lineWidth: 1.8 * k, dash: [7 * k, 5 * k]))
            .overlay {
                GeometryReader { geo in
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(Theme.paper)
                            .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 1.8 * k))
                            .frame(width: handle, height: handle)
                            .position(x: i % 2 == 0 ? 0 : geo.size.width,
                                      y: i < 2 ? 0 : geo.size.height)
                    }
                }
            }
            .shadow(color: Color.black.opacity(0.12), radius: 1.5 * k)
            .padding(-8 * k)
            .allowsHitTesting(false)
    }
}

/// Contorno muy tenue de los objetos no seleccionados en modo Objetos,
/// para que se vea qué se puede tocar.
struct SelectableHint: View {
    let scale: Double

    init(scale: Double) {
        self.scale = scale
    }

    var body: some View {
        let k = 1 / max(scale, 0.3)
        RoundedRectangle(cornerRadius: 4 * k)
            .strokeBorder(Theme.paperInkSecondary.opacity(0.35),
                          style: StrokeStyle(lineWidth: 1 * k, dash: [3 * k, 4 * k]))
            .padding(-8 * k)
            .allowsHitTesting(false)
    }
}

// MARK: - Previews

#Preview("Marcapáginas y selección") {
    HStack(spacing: 40) {
        PageSheet(side: .single, style: .ruled) { Color.clear }
            .frame(width: 220, height: 220 / Theme.pageAspect)
            .overlay(alignment: .topTrailing) {
                BookmarkRibbon().frame(width: 18, height: 58).padding(.trailing, 24).offset(y: -5)
            }
        Text("Hola")
            .font(Theme.Fonts.serif(34))
            .foregroundStyle(Theme.paperInk)
            .padding(8)
            .overlay { SelectionOutline(scale: 1) }
            .padding(30)
            .background(Theme.paper)
    }
    .padding(40)
    .background(Theme.readerBackground)
}
