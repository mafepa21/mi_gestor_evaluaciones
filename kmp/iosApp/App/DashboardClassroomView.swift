import SwiftUI
import MiGestorKit

/// Vista ultra-enfocada del Modo Clase.
/// Diseñada para uso docente en el aula frente a los alumnos:
/// una única tarjeta dominante, tipografía grande, barra de tiempo transcurrido
/// y dos botones de acción táctiles de 56pt.
struct DashboardClassroomView: View {
    let snapshot: DashboardSnapshot
    let colorScheme: ColorScheme
    let isCompact: Bool
    let onAction: (DashboardNowAction) -> Void
    let onExitClassroomMode: () -> Void

    private var context: DashboardSessionContext? {
        snapshot.currentContext
    }

    private var tint: Color {
        context.map { dashboardContextStatusTint($0.status) } ?? EvaluationDesign.success
    }

    private var groupTitle: String {
        guard let context else { return "Clase en curso" }
        return context.className.isEmpty ? "Clase actual" : context.className
    }

    private var groupSubtitle: String {
        guard let context else { return "Educación Física" }
        let elements = [
            context.subjectLabel,
            context.unitLabel
        ].compactMap { $0 }.filter { !$0.isEmpty }
        return elements.isEmpty ? "Sesión activa" : elements.joined(separator: " · ")
    }

    private var sessionTitle: String {
        context?.sessionTitle ?? context?.unitLabel ?? "Sesión de clase"
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: isCompact ? 8 : 24)

            // Tarjeta Cockpit Principal
            classroomCockpitCard
                .frame(maxWidth: isCompact ? .infinity : 640)

            Spacer(minLength: isCompact ? 8 : 24)

            // Franja inferior contextual discreta
            classroomBottomBar
                .frame(maxWidth: isCompact ? .infinity : 640)
        }
        .padding(.horizontal, isCompact ? 16 : 24)
        .padding(.vertical, isCompact ? 16 : 24)
    }

    // MARK: - Cockpit Card
    private var classroomCockpitCard: some View {
        VStack(spacing: 24) {
            // Cabecera de estado
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(tint)
                        .frame(width: 8, height: 8)

                    Text(context?.status == .active ? "CLASE EN CURSO" : "SESIÓN SELECCIONADA")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .tracking(1.2)
                }

                Text(groupTitle)
                    .font(.system(size: isCompact ? 28 : 36, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(groupSubtitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(sessionTitle)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.top, 4)
                    .multilineTextAlignment(.center)
            }

            // Barra de progreso temporal
            if let start = context?.startTime, let end = context?.endTime {
                DashboardTimeProgressBar(startTime: start, endTime: end, tint: tint)
                    .padding(.horizontal, isCompact ? 8 : 16)
            }

            // Botones de acción principales (56pt de alto para uso táctil inmediato)
            VStack(spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        passListButton
                        observationButton
                    }

                    VStack(spacing: 12) {
                        passListButton
                        observationButton
                    }
                }

                // Menú de acciones secundarias
                classroomSecondaryMenu
            }
            .padding(.top, 4)
        }
        .padding(isCompact ? 16 : 32)
        .background(appCardBackground(for: colorScheme))
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 20, x: 0, y: 8)
    }

    private var passListButton: some View {
        Button {
            onAction(.passList)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                Text("Pasar lista")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(EvaluationDesign.accent)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var observationButton: some View {
        Button {
            onAction(.observation)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "note.text.badge.plus")
                    .font(.system(size: 18, weight: .bold))
                Text("Nueva observación")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered)
        .tint(EvaluationDesign.accent)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var classroomSecondaryMenu: some View {
        Menu {
            Button {
                onAction(.evaluate)
            } label: {
                Label("Evaluar rúbrica", systemImage: "checklist.checked")
            }

            Button {
                onAction(.openNotebook)
            } label: {
                Label("Abrir cuaderno", systemImage: "tablecells")
            }

            if context?.sessionId != nil {
                Button {
                    onAction(.openJournal)
                } label: {
                    Label("Abrir diario de sesión", systemImage: "doc.text")
                }
            }

            Button {
                onAction(.openPlanner)
            } label: {
                Label("Abrir Planner", systemImage: "calendar")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "ellipsis.circle")
                Text("Más acciones")
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Bottom Bar
    private var classroomBottomBar: some View {
        HStack(spacing: 12) {
            // Próxima sesión
            if !snapshot.nextSessionLabel.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Próxima: \(snapshot.nextSessionLabel)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            // Alertas discretas si las hay
            if snapshot.alertsCount > 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(IOSAppStyle.warning)
                        .frame(width: 6, height: 6)
                    Text("\(snapshot.alertsCount) alertas")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(IOSAppStyle.warning)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(IOSAppStyle.warning.opacity(0.12), in: Capsule())
            }

            Spacer()

            // Salir de Modo Clase
            Button(action: onExitClassroomMode) {
                HStack(spacing: 6) {
                    Text("Salir de modo clase")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
