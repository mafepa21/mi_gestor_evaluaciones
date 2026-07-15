import SwiftUI
import MiGestorKit

struct NotebookTabStrip: View {
    let tabs: [NotebookTab]
    let activeTabId: String?
    let onSelect: (String) -> Void
    let onCreateTab: () -> Void
    let onRenameTab: (NotebookTab) -> Void
    let onDeleteTab: (NotebookTab) -> Void

    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 10) {
            if tabs.isEmpty {
                Label("Organiza el cuaderno por temas", systemImage: "rectangle.on.rectangle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Button {
                    onCreateTab()
                } label: {
                    Label("Crear primera pestaña", systemImage: "plus")
                }
                .notebookTabActionButtonStyle(isProminent: true)
            } else {
                NotebookTabGlassContainer {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(tabs, id: \.id) { tab in
                                NotebookTabButton(
                                    tab: tab,
                                    isSelected: tab.id == activeTabId,
                                    namespace: selectionNamespace,
                                    canDelete: tabs.count > 1,
                                    onSelect: { onSelect(tab.id) },
                                    onRename: { onRenameTab(tab) },
                                    onDelete: { onDeleteTab(tab) }
                                )
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                Button {
                    onCreateTab()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .notebookTabActionButtonStyle(isProminent: false, isCircular: true)
                .help("Nueva pestaña")
                .accessibilityLabel("Nueva pestaña")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// Botón de una pestaña individual. Struct propia (no una función-view) para que
/// el hover de macOS tenga estado propio por pestaña sin invalidar las demás.
private struct NotebookTabButton: View {
    let tab: NotebookTab
    let isSelected: Bool
    let namespace: Namespace.ID
    let canDelete: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                if isSelected {
                    NotebookTabSelectionBackground(namespace: namespace)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                Text(tab.title)
                    .font(.footnote.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .background(
                Capsule(style: .continuous)
                    .fill(isHovered && !isSelected ? Color.primary.opacity(0.05) : Color.clear)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { hovering in
            isHovered = hovering
        }
        #endif
        .help("Abrir \(tab.title)")
        .contextMenu {
            Button {
                onRename()
            } label: {
                Label("Renombrar", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Eliminar pestaña", systemImage: "trash")
            }
            .disabled(!canDelete)
        }
        .accessibilityLabel("Pestaña \(tab.title)")
        .accessibilityValue(isSelected ? "Seleccionada" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Liquid Glass (chrome), fallback material para iOS < 26 / macOS < 26

private struct NotebookTabGlassContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: 2) {
                content
            }
            .notebookTabGlassSurface()
        } else {
            content
                .notebookTabGlassSurface()
        }
    }
}

/// Fondo de la selección: capa glass translúcida que hace morphing entre
/// pestañas. Un único `glassEffectID`/`matchedGeometryEffect` constante (no por
/// `tab.id`): solo existe una instancia montada a la vez —la de la pestaña
/// activa—, así que es el mismo patrón de "elemento viajero" que
/// `PlannerFloatingTabBar.PlannerFloatingTabSelectionBackground`, no uno nuevo.
/// Tint neutro (`Color.primary`), nunca el azul de acento del sistema: decisión
/// de producto ya corregida dos veces en el proyecto (ver skill liquid-glass-design).
private struct NotebookTabSelectionBackground: View {
    let namespace: Namespace.ID

    var body: some View {
        let shape = Capsule(style: .continuous)

        shape
            .fill(selectionFallbackFill)
            .notebookTabNativeSelectionGlass(in: shape, namespace: namespace)
            .overlay {
                shape.stroke(NotebookGridStyle.gridLineStrong, lineWidth: 0.5)
            }
            .matchedGeometryEffect(id: "notebook-tab-selection", in: namespace)
    }

    private var selectionFallbackFill: AnyShapeStyle {
        if #available(iOS 26.0, macOS 26.0, *) {
            return AnyShapeStyle(Color.primary.opacity(0.02))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }
}

private extension View {
    /// Superficie glass que envuelve solo el grupo de pestañas (no la barra
    /// entera del cuaderno): flota sobre el fondo del módulo en vez de extender
    /// un `.ultraThinMaterial` a todo el ancho.
    @ViewBuilder
    func notebookTabGlassSurface() -> some View {
        let shape = Capsule(style: .continuous)

        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .background { shape.fill(Color.primary.opacity(0.008)) }
                .glassEffect(.regular.tint(Color.primary.opacity(0.012)).interactive(), in: shape)
                .overlay {
                    shape.stroke(NotebookGridStyle.gridLine, lineWidth: 0.5)
                }
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(NotebookGridStyle.gridLine, lineWidth: 0.5)
                }
        }
    }

    @ViewBuilder
    func notebookTabNativeSelectionGlass(in shape: Capsule, namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .glassEffect(.regular.tint(Color.primary.opacity(0.03)).interactive(), in: shape)
                .glassEffectID("notebook-tab-selection", in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func notebookTabActionButtonStyle(isProminent: Bool, isCircular: Bool = false) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if isProminent {
                self.buttonStyle(.glassProminent)
                    .buttonBorderShape(isCircular ? .circle : .capsule)
                    .controlSize(.small)
            } else {
                self.buttonStyle(.glass)
                    .buttonBorderShape(isCircular ? .circle : .capsule)
                    .controlSize(.small)
            }
        } else if isProminent {
            self.buttonStyle(.borderedProminent)
                .buttonBorderShape(isCircular ? .circle : .capsule)
                .controlSize(.small)
        } else {
            self.buttonStyle(.bordered)
                .buttonBorderShape(isCircular ? .circle : .capsule)
                .controlSize(.small)
        }
    }
}
