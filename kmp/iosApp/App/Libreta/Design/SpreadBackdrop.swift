import SwiftUI

/// Tapa interior del cuaderno abierto: cartón forrado de tela que asoma alrededor
/// de las hojas en el lector. Ocupa todo el espacio que se le dé.
///
/// En apaisado (ancho > alto) dibuja el lomo en el centro; en vertical, la
/// encuadernación a la izquierda. Colócalo detrás de las hojas con un margen de
/// `Theme.backdropInset`.
struct SpreadBackdrop: View {
    /// Si se indica, la tapa toma un tono oscurecido del color del cuaderno.
    let color: CoverColor?

    init(color: CoverColor? = nil) {
        self.color = color
    }

    private var base: Color { color?.shade(0.35) ?? Theme.backdrop }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.backdropCornerRadius, style: .continuous)
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                shape.fill(base)

                WeaveTexture(
                    seed: color?.seed ?? 5,
                    step: 2.5,
                    lightOpacity: 0.05,
                    darkOpacity: 0.08,
                    speckleDensity: 1.0 / 90.0,
                    speckleOpacity: 0.06
                )

                if landscape {
                    // Lomo central.
                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(0.0), location: 0.44),
                            .init(color: Color.black.opacity(0.30), location: 0.5),
                            .init(color: Color.black.opacity(0.0), location: 0.56)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                } else {
                    // Encuadernación a la izquierda.
                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(0.35), location: 0),
                            .init(color: Color.black.opacity(0.0), location: 0.06)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }

                // Costura perimetral.
                shape
                    .inset(by: 6)
                    .stroke(
                        Color.white.opacity(0.16),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [5, 4])
                    )
            }
            .clipShape(shape)
            .overlay(shape.stroke(Color.black.opacity(0.35), lineWidth: 1))
            .overlay(shape.inset(by: 1).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .compositingGroup()
            .shadow(color: Theme.shadow, radius: 12, x: 0, y: 6)
        }
        .accessibilityHidden(true)
    }
}

#Preview("Tapa abierta") {
    VStack(spacing: 30) {
        SpreadBackdrop()
            .frame(width: 520, height: 360)
        SpreadBackdrop(color: .teal)
            .frame(width: 280, height: 380)
    }
    .padding(30)
    .background(Theme.readerBackground)
}
