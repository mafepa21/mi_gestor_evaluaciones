import SwiftUI

/// Colores de tapa disponibles. Tonos de tela de encuadernar: apagados, nunca chillones.
/// `rawValue` se guarda en `Notebook.coverColorRaw` ("blue" por defecto).
enum CoverColor: String, CaseIterable, Identifiable {
    case blue, red, green, yellow, black, brown, purple, teal

    var id: String { rawValue }

    /// Color por defecto de los cuadernos nuevos.
    static let defaultColor: CoverColor = .blue

    /// Convierte el valor guardado en el modelo, con `.blue` como respaldo.
    static func from(_ raw: String) -> CoverColor {
        CoverColor(rawValue: raw) ?? .defaultColor
    }

    var label: String {
        switch self {
        case .blue: "Azul"
        case .red: "Rojo"
        case .green: "Verde"
        case .yellow: "Mostaza"
        case .black: "Negro"
        case .brown: "Marrón"
        case .purple: "Morado"
        case .teal: "Turquesa"
        }
    }

    var hex: UInt32 {
        switch self {
        case .blue: 0x2F4C78
        case .red: 0xA3383A
        case .green: 0x3F6A4A
        case .yellow: 0xD2A23A
        case .black: 0x2A2A2D
        case .brown: 0x7A5335
        case .purple: 0x5D4774
        case .teal: 0x2E6D71
        }
    }

    /// Color principal de la tapa.
    var color: Color { Theme.color(hex) }

    /// Tapas claras necesitan detalles (costuras, iconos) oscuros.
    var isLight: Bool { self == .yellow }

    /// Mezcla hacia negro (`amount` 0…1).
    func shade(_ amount: Double) -> Color { mix(toward: 0, amount) }

    /// Mezcla hacia blanco (`amount` 0…1).
    func tint(_ amount: Double) -> Color { mix(toward: 1, amount) }

    /// Color del hilo de las costuras.
    var stitch: Color {
        isLight ? Color.black.opacity(0.28) : Color.white.opacity(0.32)
    }

    /// Semilla estable para texturas.
    var seed: UInt64 {
        UInt64((CoverColor.allCases.firstIndex(of: self) ?? 0) + 11)
    }

    private func mix(toward target: Double, _ amount: Double) -> Color {
        let a = min(max(amount, 0), 1)
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        return Color(
            red: r + (target - r) * a,
            green: g + (target - g) * a,
            blue: b + (target - b) * a
        )
    }
}

#Preview("Colores de tapa") {
    VStack(alignment: .leading, spacing: 10) {
        ForEach(CoverColor.allCases) { c in
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(c.color)
                    .frame(width: 44, height: 28)
                Text(c.label).font(Theme.Fonts.body)
                Spacer()
                Text(c.rawValue).font(.caption.monospaced()).foregroundStyle(Theme.inkSecondary)
            }
        }
    }
    .padding(24)
    .frame(width: 320)
    .background(Theme.desk)
}
