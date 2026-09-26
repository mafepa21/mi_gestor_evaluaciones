import SwiftUI
import Combine
import MiGestorKit

/// Barra visual de tiempo transcurrido para la sesión lectiva en curso en el Dashboard.
/// Calcula de forma reactiva el porcentaje completado a partir de la franja horaria.
struct DashboardTimeProgressBar: View {
    let startTime: String?
    let endTime: String?
    var tint: Color = EvaluationDesign.accent

    @State private var now = Date()
    private static let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var startMinutes: Int? {
        guard let startTime else { return nil }
        return parseMinutes(from: startTime)
    }

    private var endMinutes: Int? {
        guard let endTime else { return nil }
        return parseMinutes(from: endTime)
    }

    private var currentMinutes: Int {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        return hour * 60 + minute
    }

    /// Porcentaje completado entre 0.0 y 1.0
    private var progress: Double {
        guard let start = startMinutes, let end = endMinutes, end > start else {
            return 0.0
        }
        if currentMinutes <= start { return 0.0 }
        if currentMinutes >= end { return 1.0 }
        return Double(currentMinutes - start) / Double(end - start)
    }

    private var percentageLabel: String {
        let pct = Int((progress * 100).rounded())
        return "\(max(0, min(100, pct)))%"
    }

    private var timeRangeLabel: String {
        guard let start = startTime, let end = endTime else {
            return "En horario"
        }
        return "\(start) – \(end)"
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(timeRangeLabel)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                Text(percentageLabel)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tint.opacity(0.14))
                        .frame(height: 8)

                    Capsule()
                        .fill(tint)
                        .frame(width: max(8, geometry.size.width * CGFloat(progress)), height: 8)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
                }
            }
            .frame(height: 8)
        }
        .onReceive(Self.timer) { newTime in
            now = newTime
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Progreso de la sesión: \(percentageLabel), horario \(timeRangeLabel)")
    }

    private func parseMinutes(from value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let minute = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return hour * 60 + minute
    }
}
