import SwiftUI

struct NotebookCompactCommandBar<SecondaryActions: View>: View {
    let isInspectorPresented: Bool
    let canUndo: Bool
    let isAttendanceQuickMode: Bool
    let showsAdvancedActions: Bool
    let onAddColumn: () -> Void
    let onOpenOrganization: () -> Void
    let onToggleInspector: () -> Void
    let onUndo: () -> Void
    let onToggleAttendanceQuickMode: () -> Void
    let onOpenGroupManagement: () -> Void
    let secondaryActions: () -> SecondaryActions

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        #if os(macOS)
        EmptyView()
        #else
        Group {
            if isCompact {
                compactBody
            } else {
                regularBody
            }
        }
        .padding(.horizontal, IOSAppStyle.pagePadding)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NotebookStyle.softBorder)
                .frame(height: 1)
        }
        #endif
    }

    private var compactBody: some View {
        HStack(spacing: 8) {
            Spacer()

            iconButton(systemImage: "plus", label: "Nueva columna", action: onAddColumn, isProminent: true)
            secondaryMenu
        }
    }

    private var regularBody: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            iconButton(systemImage: "plus", label: "Nueva columna", action: onAddColumn, isProminent: true)

            if showsAdvancedActions {
                iconButton(systemImage: "person.2", label: "Gestionar grupos", action: onOpenGroupManagement)
                iconButton(systemImage: "rectangle.3.group", label: "Organizar columnas", action: onOpenOrganization)
                iconButton(
                    systemImage: isInspectorPresented ? "sidebar.right" : "sidebar.squares.right",
                    label: isInspectorPresented ? "Ocultar inspector" : "Mostrar inspector",
                    action: onToggleInspector,
                    isActive: isInspectorPresented
                )
            }

            secondaryMenu
        }
    }

    private var secondaryMenu: some View {
        Menu {
            Button(action: onUndo) {
                Label("Deshacer último cambio", systemImage: "arrow.uturn.backward")
            }
            .disabled(!canUndo)

            if showsAdvancedActions {
                Button(action: onOpenGroupManagement) {
                    Label("Gestionar grupos", systemImage: "person.2")
                }
                Button(action: onToggleAttendanceQuickMode) {
                    Label(
                        isAttendanceQuickMode ? "Salir de asistencia rápida" : "Asistencia rápida",
                        systemImage: "bolt.fill"
                    )
                }
            }

            if isCompact {
                Button(action: onOpenOrganization) {
                    Label("Organizar columnas", systemImage: "rectangle.3.group")
                }
                Button(action: onToggleInspector) {
                    Label(
                        isInspectorPresented ? "Ocultar inspector" : "Mostrar inspector",
                        systemImage: isInspectorPresented ? "sidebar.right" : "sidebar.squares.right"
                    )
                }
            }

            secondaryActions()
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body.weight(.medium))
                .frame(width: 34, height: 34)
                .background(Color.secondary.opacity(0.08), in: Circle())
                .foregroundStyle(.secondary)
        }
        .buttonStyle(NotebookScaleButtonStyle())
        .accessibilityLabel("Más acciones del cuaderno")
    }

    private func iconButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void,
        isProminent: Bool = false,
        isActive: Bool = false
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(isProminent ? .bold : .medium))
                .frame(width: 34, height: 34)
                .background(
                    (isProminent ? IOSAppStyle.info : (isActive ? NotebookStyle.primaryTint : Color.secondary)).opacity(isProminent ? 1 : 0.10),
                    in: Circle()
                )
                .foregroundStyle(isProminent ? .white : (isActive ? NotebookStyle.primaryTint : .secondary))
        }
        .buttonStyle(NotebookScaleButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - NotebookScaleButtonStyle
private struct NotebookScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
