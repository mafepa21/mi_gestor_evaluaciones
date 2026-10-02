import SwiftUI
import MiGestorKit

/// Franja compacta horizontal para el contexto "Ahora" en Modo Despacho.
/// Permite mantener visible la clase en curso y sus accesos rápidos
/// ocupando una mínima altura vertical para dar protagonismo a los paneles analíticos.
struct DashboardCompactHeroStrip: View {
    let context: DashboardSessionContext?
    let colorScheme: ColorScheme
    let onAction: (DashboardNowAction) -> Void

    private var tint: Color {
        context.map { dashboardContextStatusTint($0.status) } ?? IOSAppStyle.warning
    }

    private var primaryAction: DashboardNowAction {
        guard let context else { return .openPlanner }
        return context.status == .active ? .passList : .openNotebook
    }

    private var primaryTitle: String {
        guard let context else { return "Configurar horario" }
        return context.status == .active ? "Pasar lista" : "Preparar cuaderno"
    }

    private var secondaryActions: [DashboardNowAction] {
        guard let context else { return [] }
        return context.status == .active
            ? [.observation, .evaluate, .openNotebook]
            : [.openPlanner]
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // Variante horizontal (iPad / Mac / iPhone ancho)
            HStack(spacing: 16) {
                indicatorAndText

                Spacer(minLength: 8)

                actionButtons
            }

            // Variante vertical (iPhone estrecho)
            VStack(alignment: .leading, spacing: 8) {
                indicatorAndText

                actionButtons
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(appCardBackground(for: colorScheme))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private var indicatorAndText: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Ahora")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    if let context {
                        Text("· \(dashboardContextStatusLabel(context.status))")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(tint)
                    }
                }

                if let context {
                    Text(summaryLine(for: context))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("No hay franja lectiva en el horario docente")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                onAction(primaryAction)
            } label: {
                Label(primaryTitle, systemImage: primaryAction.systemImage)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .buttonStyle(.borderedProminent)
            .tint(EvaluationDesign.accent)
            .controlSize(.regular)
            .disabled(context != nil && context?.classId == nil && primaryAction != .openPlanner)

            if !secondaryActions.isEmpty {
                Menu {
                    ForEach(secondaryActions) { action in
                        Button {
                            onAction(action)
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .accessibilityLabel("Más acciones")
            }
        }
    }

    private func summaryLine(for context: DashboardSessionContext) -> String {
        var elements: [String] = []
        if !context.className.isEmpty {
            elements.append(context.className)
        }
        if let subject = context.subjectLabel, !subject.isEmpty {
            elements.append(subject)
        }
        if let start = context.startTime, let end = context.endTime {
            elements.append("\(start)–\(end)")
        }
        if let unit = context.unitLabel, !unit.isEmpty {
            elements.append(unit)
        }
        return elements.joined(separator: " · ")
    }
}
