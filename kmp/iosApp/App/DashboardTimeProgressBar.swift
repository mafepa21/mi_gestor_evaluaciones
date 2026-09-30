import SwiftUI
import MiGestorKit

/// Barra de progreso animada. Pura: recibe la fracción (0...1) ya calculada.
/// Sube de 0 al valor real al aparecer (1 s) y con movimiento reducido salta
/// directa, sin animar.
struct DashboardProgressBar: View {
    let progress: Double
    var tint: Color = DashboardStyle.accent
    let elapsedMinutes: Int
    let totalMinutes: Int
    var label = "Progreso de la sesión"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        Capsule()
            .fill(tint.opacity(0.16))
            .frame(height: DashboardStyle.Spacing.s1)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(tint)
                        .frame(width: geometry.size.width * CGFloat(min(max(shown, 0), 1)))
                }
            }
            .onAppear { update() }
            .appOnChange(of: progress) { _ in update() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue("Han pasado \(elapsedMinutes) de \(totalMinutes) minutos")
    }

    private func update() {
        if reduceMotion {
            shown = progress
        } else {
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 1)) {
                shown = progress
            }
        }
    }
}
