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

/// Barra de tiempo transcurrido de la sesión en curso, con su horario y el
/// porcentaje. Se refresca con `TimelineView` cada 30 s: no hay temporizador
/// estático ni estado que se quede obsoleto.
struct DashboardTimeProgressBar: View {
    let startTime: String?
    let endTime: String?
    var tint: Color = DashboardStyle.accent

    var body: some View {
        if let clock = DashboardSessionClock(start: startTime, end: endTime) {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                let state = clock.state(at: timeline.date)
                VStack(spacing: DashboardStyle.Spacing.s1) {
                    HStack {
                        Text("\(startTime ?? "") – \(endTime ?? "")")
                            .font(DashboardStyle.Typography.footnoteStrong)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Spacer()
                        Text("\(Int((state.progress * 100).rounded())) %")
                            .font(DashboardStyle.Typography.footnoteStrong)
                            .foregroundStyle(tint)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: state.progress))
                    }
                    .accessibilityHidden(true)

                    DashboardProgressBar(
                        progress: state.progress,
                        tint: tint,
                        elapsedMinutes: state.elapsed,
                        totalMinutes: state.total
                    )
                }
            }
        }
    }
}
