import SwiftUI

enum NotebookToolbarSelectionContext: Equatable {
    case none
    case cells
    case column
}

struct NotebookCompactCommandBar<FilterActions: View, SecondaryActions: View>: View {
    let isInspectorPresented: Bool
    let canUndo: Bool
    let isAttendanceQuickMode: Bool
    let showsAdvancedActions: Bool
    let selectionContext: NotebookToolbarSelectionContext
    let onAddColumn: () -> Void
    let onSearch: () -> Void
    let onCopySelection: () -> Void
    let onPasteSelection: () -> Void
    let onFillSelection: () -> Void
    let onClearSelection: () -> Void
    let onCommentSelection: () -> Void
    let isVoiceDictationActive: Bool
    let onToggleVoiceDictation: () -> Void
    let onEditColumn: () -> Void
    let onHideColumn: () -> Void
    let onDuplicateColumn: () -> Void
    let onReorderColumn: () -> Void
    let onToggleColumnAverage: () -> Void
    let onOpenOrganization: () -> Void
    let onToggleInspector: () -> Void
    let onUndo: () -> Void
    let onToggleAttendanceQuickMode: () -> Void
    let onOpenGroupManagement: () -> Void
    let filters: () -> FilterActions
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    contextualActions
                }
                .padding(.vertical, 1)
            }
            secondaryMenu
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: selectionContext)
    }

    private var regularBody: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            contextualActions

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
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: selectionContext)
    }

    @ViewBuilder
    private var contextualActions: some View {
        switch selectionContext {
        case .none:
            textButton(systemImage: "plus", label: "Columna", action: onAddColumn, isProminent: true)
            textButton(systemImage: "magnifyingglass", label: "Buscar", action: onSearch)
            Menu {
                filters()
            } label: {
                commandLabel(systemImage: "line.3.horizontal.decrease.circle", label: "Filtros")
            }
            .buttonStyle(NotebookScaleButtonStyle())
            .accessibilityLabel("Filtros del cuaderno")
        case .cells:
            textButton(systemImage: "doc.on.doc", label: "Copiar", action: onCopySelection)
            textButton(systemImage: "clipboard", label: "Pegar", action: onPasteSelection)
            textButton(systemImage: "arrow.down.to.line", label: "Rellenar", action: onFillSelection)
            textButton(systemImage: "eraser", label: "Borrar", action: onClearSelection)
            textButton(systemImage: "text.bubble", label: "Comentario", action: onCommentSelection)
            iconButton(
                systemImage: isVoiceDictationActive ? "mic.fill" : "mic",
                label: isVoiceDictationActive ? "Escuchando… toca para parar" : "Dictar nota por voz",
                action: onToggleVoiceDictation,
                isActive: isVoiceDictationActive
            )
        case .column:
            textButton(systemImage: "pencil", label: "Editar", action: onEditColumn)
            textButton(systemImage: "eye.slash", label: "Ocultar", action: onHideColumn)
            textButton(systemImage: "plus.square.on.square", label: "Duplicar", action: onDuplicateColumn)
            textButton(systemImage: "arrow.up.arrow.down", label: "Reordenar", action: onReorderColumn)
            textButton(systemImage: "percent", label: "Media", action: onToggleColumnAverage)
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

    private func textButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void,
        isProminent: Bool = false
    ) -> some View {
        Button(action: action) {
            commandLabel(systemImage: systemImage, label: label, isProminent: isProminent)
        }
        .buttonStyle(NotebookScaleButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }

    private func commandLabel(systemImage: String, label: String, isProminent: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(isProminent ? .white : .primary)
        .frame(height: 34)
        .padding(.horizontal, 12)
        .background(
            Capsule(style: .continuous)
                .fill(isProminent ? IOSAppStyle.info : Color.secondary.opacity(0.08))
        )
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
