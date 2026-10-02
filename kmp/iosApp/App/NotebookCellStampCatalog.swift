import SwiftUI
import MiGestorKit

// MARK: - Categorías pedagógicas de sellos formativos

enum NotebookStampCategory: String, CaseIterable, Identifiable {
    case excellence = "excellence"
    case effort = "effort"
    case attention = "attention"
    case peHealth = "peHealth"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .excellence: return "Excelencia y Logro"
        case .effort: return "Esfuerzo y Actitud"
        case .attention: return "Atención y Refuerzo"
        case .peHealth: return "EF y Bienestar"
        }
    }

    var systemIcon: String {
        switch self {
        case .excellence: return "star.fill"
        case .effort: return "bolt.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .peHealth: return "figure.run"
        }
    }

    var tintColor: Color {
        switch self {
        case .excellence: return Color(red: 0.95, green: 0.72, blue: 0.12)
        case .effort: return Color(red: 0.20, green: 0.65, blue: 0.85)
        case .attention: return Color(red: 0.95, green: 0.45, blue: 0.25)
        case .peHealth: return Color(red: 0.25, green: 0.75, blue: 0.45)
        }
    }
}

// MARK: - Modelo de Sello de Feedback

struct NotebookStampItem: Identifiable, Hashable {
    let id: String
    let symbol: String
    let isSystemImage: Bool
    let title: String
    let category: NotebookStampCategory
    let tintColor: Color
    let meaningDescription: String

    init(
        id: String,
        symbol: String,
        isSystemImage: Bool = true,
        title: String,
        category: NotebookStampCategory,
        tintColor: Color,
        meaningDescription: String
    ) {
        self.id = id
        self.symbol = symbol
        self.isSystemImage = isSystemImage
        self.title = title
        self.category = category
        self.tintColor = tintColor
        self.meaningDescription = meaningDescription
    }
}

// MARK: - Catálogo Integral de Sellos Formativos estilo iDoceo

enum NotebookCellStampCatalog {
    static let allStamps: [NotebookStampItem] = [
        // 1. Excelencia y Reconocimiento
        NotebookStampItem(
            id: "star.fill",
            symbol: "star.fill",
            title: "Sobresaliente",
            category: .excellence,
            tintColor: Color(red: 0.96, green: 0.74, blue: 0.12),
            meaningDescription: "Trabajo excelente o resultado óptimo."
        ),
        NotebookStampItem(
            id: "trophy.fill",
            symbol: "trophy.fill",
            title: "Logro destacado",
            category: .excellence,
            tintColor: Color(red: 0.98, green: 0.62, blue: 0.18),
            meaningDescription: "Máxima puntuación o hito alcanzado."
        ),
        NotebookStampItem(
            id: "target",
            symbol: "target",
            title: "Objetivo cumplido",
            category: .excellence,
            tintColor: Color(red: 0.92, green: 0.28, blue: 0.28),
            meaningDescription: "Criterio de evaluación superado con precisión."
        ),
        NotebookStampItem(
            id: "hand.thumbsup.fill",
            symbol: "hand.thumbsup.fill",
            title: "Buen trabajo",
            category: .excellence,
            tintColor: Color(red: 0.22, green: 0.58, blue: 0.96),
            meaningDescription: "Desempeño correcto y bien ejecutado."
        ),
        NotebookStampItem(
            id: "lightbulb.fill",
            symbol: "lightbulb.fill",
            title: "Idea creativa",
            category: .excellence,
            tintColor: Color(red: 0.98, green: 0.78, blue: 0.18),
            meaningDescription: "Aportación creativa o solución original."
        ),

        // 2. Esfuerzo y Actitud
        NotebookStampItem(
            id: "bolt.fill",
            symbol: "bolt.fill",
            title: "Gran energía",
            category: .effort,
            tintColor: Color(red: 0.95, green: 0.65, blue: 0.15),
            meaningDescription: "Participación activa y entusiasmo."
        ),
        NotebookStampItem(
            id: "chart.line.uptrend.xyaxis",
            symbol: "chart.line.uptrend.xyaxis",
            title: "Progresando",
            category: .effort,
            tintColor: Color(red: 0.22, green: 0.75, blue: 0.45),
            meaningDescription: "Evolución positiva respecto a sesiones anteriores."
        ),
        NotebookStampItem(
            id: "person.2.fill",
            symbol: "person.2.fill",
            title: "Cooperación",
            category: .effort,
            tintColor: Color(red: 0.40, green: 0.45, blue: 0.92),
            meaningDescription: "Excelente trabajo en equipo y ayuda mutua."
        ),
        NotebookStampItem(
            id: "shield.fill",
            symbol: "shield.fill",
            title: "Superación",
            category: .effort,
            tintColor: Color(red: 0.25, green: 0.70, blue: 0.75),
            meaningDescription: "Constancia y superación ante dificultades."
        ),

        // 3. Atención y Refuerzo
        NotebookStampItem(
            id: "exclamationmark.triangle.fill",
            symbol: "exclamationmark.triangle.fill",
            title: "Necesita refuerzo",
            category: .attention,
            tintColor: Color(red: 0.96, green: 0.50, blue: 0.18),
            meaningDescription: "Requiere repasar contenidos o atención individual."
        ),
        NotebookStampItem(
            id: "flag.fill",
            symbol: "flag.fill",
            title: "Prioritario",
            category: .attention,
            tintColor: Color(red: 0.90, green: 0.25, blue: 0.25),
            meaningDescription: "Seguimiento prioritario en tutoría o evaluación."
        ),
        NotebookStampItem(
            id: "hourglass",
            symbol: "hourglass",
            title: "Entrega pendiente",
            category: .attention,
            tintColor: Color(red: 0.65, green: 0.40, blue: 0.85),
            meaningDescription: "Falta entrega o tarea incompleta."
        ),
        NotebookStampItem(
            id: "bubble.left.fill",
            symbol: "bubble.left.fill",
            title: "Nota formativa",
            category: .attention,
            tintColor: Color(red: 0.28, green: 0.60, blue: 0.92),
            meaningDescription: "Contiene observación formativa para el alumno."
        ),
        NotebookStampItem(
            id: "xmark.circle.fill",
            symbol: "xmark.circle.fill",
            title: "No superado",
            category: .attention,
            tintColor: Color(red: 0.88, green: 0.28, blue: 0.28),
            meaningDescription: "No presentado o no supera los criterios mínimos."
        ),

        // 4. Educación Física y Salud
        NotebookStampItem(
            id: "figure.run",
            symbol: "figure.run",
            title: "Ritmo / Marca",
            category: .peHealth,
            tintColor: Color(red: 0.22, green: 0.75, blue: 0.45),
            meaningDescription: "Rendimiento motor o condición física destacada."
        ),
        NotebookStampItem(
            id: "heart.fill",
            symbol: "heart.fill",
            title: "Juego limpio",
            category: .peHealth,
            tintColor: Color(red: 0.95, green: 0.32, blue: 0.55),
            meaningDescription: "Deportividad, respeto a normas y hábitos saludables."
        ),
        NotebookStampItem(
            id: "stopwatch.fill",
            symbol: "stopwatch.fill",
            title: "Cronometrada",
            category: .peHealth,
            tintColor: Color(red: 0.30, green: 0.60, blue: 0.90),
            meaningDescription: "Registro de tiempo o velocidad evaluado."
        )
    ]

    /// Sellos rápidos para menús contextuales y atajos de 1 toque
    static let quickStamps: [NotebookStampItem] = [
        allStamps.first(where: { $0.id == "star.fill" })!,
        allStamps.first(where: { $0.id == "hand.thumbsup.fill" })!,
        allStamps.first(where: { $0.id == "bolt.fill" })!,
        allStamps.first(where: { $0.id == "exclamationmark.triangle.fill" })!,
        allStamps.first(where: { $0.id == "flag.fill" })!,
        allStamps.first(where: { $0.id == "figure.run" })!
    ]

    /// Busca un sello en el catálogo por su identificador o símbolo persistido
    static func item(for identifier: String?) -> NotebookStampItem? {
        guard let id = identifier?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            return nil
        }
        return allStamps.first { $0.id == id || $0.symbol == id }
    }

    /// Filtra sellos por categoría
    static func stamps(for category: NotebookStampCategory) -> [NotebookStampItem] {
        allStamps.filter { $0.category == category }
    }
}

// MARK: - Badge de Sello en Celda

struct NotebookCellStampBadge: View {
    let iconValue: String?
    let note: String?
    let attachmentCount: Int
    let fallbackTint: Color
    let studentName: String?

    var body: some View {
        let stamp = NotebookCellStampCatalog.item(for: iconValue)
        let resolvedTint = stamp?.tintColor ?? fallbackTint

        HStack(spacing: 3) {
            if let stamp {
                Image(systemName: stamp.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(resolvedTint)
            } else if let iconValue, !iconValue.isEmpty {
                if iconValue.contains(".") || iconValue.count > 2 {
                    Image(systemName: iconValue)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(resolvedTint)
                } else {
                    Text(iconValue)
                        .font(.system(size: 11))
                }
            }

            if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(resolvedTint.opacity(0.85))
            }

            if attachmentCount > 0 {
                Text("\(attachmentCount)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(resolvedTint)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(resolvedTint.opacity(0.16))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(resolvedTint.opacity(0.32), lineWidth: 0.8)
        )
        .shadow(color: resolvedTint.opacity(0.18), radius: 2, x: 0, y: 1)
        .help(tooltipText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var tooltipText: String {
        var parts: [String] = []
        if let studentName, !studentName.isEmpty {
            parts.append(studentName)
        }
        if let stamp = NotebookCellStampCatalog.item(for: iconValue) {
            parts.append("Sello: \(stamp.title) (\(stamp.meaningDescription))")
        } else if let iconValue, !iconValue.isEmpty {
            parts.append("Icono: \(iconValue)")
        }
        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Nota: \(note)")
        }
        if attachmentCount > 0 {
            parts.append("Adjuntos: \(attachmentCount)")
        }
        return parts.joined(separator: "\n")
    }

    private var accessibilityDescription: String {
        var desc = ""
        if let stamp = NotebookCellStampCatalog.item(for: iconValue) {
            desc += "Sello formativo \(stamp.title). "
        } else if let iconValue, !iconValue.isEmpty {
            desc += "Icono \(iconValue). "
        }
        if let note, !note.isEmpty {
            desc += "Con nota formativa. "
        }
        if attachmentCount > 0 {
            desc += "\(attachmentCount) adjuntos."
        }
        return desc
    }
}
