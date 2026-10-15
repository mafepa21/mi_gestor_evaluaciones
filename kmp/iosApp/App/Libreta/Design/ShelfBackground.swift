import SwiftUI

/// Fondo de la biblioteca: una mesa forrada de lino claro, con luz cenital suave
/// y un ligero viñeteado. Discreto para que las portadas sean las protagonistas.
/// Ignora el área segura y no recibe toques.
struct ShelfBackground: View {
    init() {}

    var body: some View {
        ZStack {
            Theme.desk

            WeaveTexture(
                seed: 7,
                step: 3,
                lightOpacity: 0.09,
                darkOpacity: 0.035,
                speckleDensity: 1.0 / 140.0,
                speckleOpacity: 0.035
            )

            // Luz cenital.
            GeometryReader { geo in
                RadialGradient(
                    colors: [Theme.deskGlow, Color.clear],
                    center: UnitPoint(x: 0.5, y: 0.0),
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.85
                )
            }

            // Viñeteado muy suave en los bordes.
            LinearGradient(
                colors: [Color.clear, Color.clear, Theme.shadow.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Mesa") {
    ShelfBackground()
}
