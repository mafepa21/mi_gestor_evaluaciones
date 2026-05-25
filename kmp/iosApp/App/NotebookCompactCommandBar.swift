import SwiftUI
import MiGestorKit

struct NotebookCompactCommandBar<SecondaryActions: View>: View {
    @ObservedObject var bridge: KmpBridge
    @Binding var searchText: String
    let classTitle: String
    let subtitle: String?
    let selectedClassId: Int64?
    let classes: [SchoolClass]
    let focusMode: NotebookFocusMode
    let isInspectorPresented: Bool
    let canUndo: Bool
    let isAttendanceQuickMode: Bool
    let showsAdvancedActions: Bool
    let onSelectClass: (Int64) -> Void
    let onAddColumn: () -> Void
    let onOpenOrganization: () -> Void
    let onToggleInspector: () -> Void
    let onUndo: () -> Void
    let onToggleAttendanceQuickMode: () -> Void
    let secondaryActions: () -> SecondaryActions
    @State private var isClassPickerPresented = false

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
        .background(.bar)
        #endif
    }

    private var compactBody: some View {
        HStack(spacing: 8) {
            classPicker
                .frame(maxWidth: 132)

            IOSSearchField(text: $searchText, placeholder: "Buscar")
                .frame(maxWidth: .infinity)

            iconButton(systemImage: "plus", label: "Nueva columna", action: onAddColumn, isProminent: true)
            secondaryMenu
        }
    }

    private var regularBody: some View {
        HStack(spacing: 10) {
            classPicker
                .frame(maxWidth: 230)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            IOSSearchField(text: $searchText, placeholder: "Buscar alumno")
                .frame(minWidth: 210, maxWidth: 300)

            Spacer(minLength: 0)

            iconButton(systemImage: "plus", label: "Nueva columna", action: onAddColumn, isProminent: true)

            if showsAdvancedActions {
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

    private var classPicker: some View {
        Button {
            isClassPickerPresented = true
        } label: {
            HStack(spacing: 7) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(classTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isCompact, let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NotebookStyle.surfaceSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(NotebookStyle.softBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Seleccionar clase")
        .popover(isPresented: $isClassPickerPresented, arrowEdge: .top) {
            NotebookClassPickerPopover(
                classes: classes,
                selectedClassId: selectedClassId,
                onSelectClass: { onSelectClass($0) },
                onClose: { isClassPickerPresented = false }
            )
        }
    }

    private var secondaryMenu: some View {
        Menu {
            Button(action: onUndo) {
                Label("Deshacer último cambio", systemImage: "arrow.uturn.backward")
            }
            .disabled(!canUndo)

            if showsAdvancedActions {
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
        .buttonStyle(.plain)
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
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
