import SwiftUI

/// Textura de tela/lino dibujada con Canvas: trama fina + motas irregulares.
/// Determinista (misma semilla → mismo dibujo) y sin imágenes externas.
/// Uso interno de Design (portadas, mesa, tapa del lector).
struct WeaveTexture: View {
    var seed: UInt64 = 1
    /// Separación de la trama en puntos.
    var step: CGFloat = 2.5
    /// Opacidad de los hilos claros (horizontales).
    var lightOpacity: Double = 0.05
    /// Opacidad de los hilos oscuros (verticales).
    var darkOpacity: Double = 0.05
    /// Motas por punto cuadrado.
    var speckleDensity: CGFloat = 1.0 / 90.0
    var speckleOpacity: Double = 0.06

    var body: some View {
        Canvas { ctx, size in
            guard size.width > 0, size.height > 0, step > 0.5 else { return }

            var horizontal = Path()
            var y: CGFloat = 0
            while y <= size.height {
                horizontal.move(to: CGPoint(x: 0, y: y))
                horizontal.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            var vertical = Path()
            var x: CGFloat = 0
            while x <= size.width {
                vertical.move(to: CGPoint(x: x, y: 0))
                vertical.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            ctx.stroke(horizontal, with: .color(Color.white.opacity(lightOpacity)), lineWidth: 0.5)
            ctx.stroke(vertical, with: .color(Color.black.opacity(darkOpacity)), lineWidth: 0.5)

            // Motas y pequeñas irregularidades del hilo ("slubs").
            var rng = TextureRandom(seed: seed)
            let raw = size.width * size.height * speckleDensity
            let count = max(0, min(6000, Int(raw)))
            var lightDots = Path()
            var darkDots = Path()
            for i in 0..<count {
                let px = CGFloat.random(in: 0..<size.width, using: &rng)
                let py = CGFloat.random(in: 0..<size.height, using: &rng)
                let w = CGFloat.random(in: 0.6...3.5, using: &rng)
                let rect = CGRect(x: px, y: py, width: w, height: 0.7)
                if i % 2 == 0 {
                    lightDots.addRect(rect)
                } else {
                    darkDots.addRect(rect)
                }
            }
            ctx.fill(lightDots, with: .color(Color.white.opacity(speckleOpacity)))
            ctx.fill(darkDots, with: .color(Color.black.opacity(speckleOpacity)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Generador pseudoaleatorio determinista (SplitMix64).
fileprivate struct TextureRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z: UInt64 = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

#Preview("Textura") {
    WeaveTexture(seed: 3)
        .background(CoverColor.blue.color)
        .frame(width: 300, height: 200)
}
