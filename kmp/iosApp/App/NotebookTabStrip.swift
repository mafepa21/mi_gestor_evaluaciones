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
        Button {
            // El cambio de pestaña se envuelve en animación para que la pastilla
            // (glassEffectID / matchedGeometryEffect) se deslice de una posición a
            // otra en vez de aparecer/desaparecer.
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                onSelect()
            }
        } label: {
            Text(tab.title)
                .font(.footnote.weight(isSelected ? .semibold : .medium))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .padding(.horizontal, 16)
                .frame(minHeight: 32)
                // La pastilla de selección va SIEMPRE de fondo, nunca como capa
                // hermana en un ZStack: así el cristal no puede componer por encima
                // del texto (era el bug de "el cristal tapa el título").
                .background {
                    if isSelected {
                        NotebookTabSelectionPill(namespace: namespace)
                    } else if isHovered {
                        Capsule(style: .continuous).fill(Color.primary.opacity(0.05))
                    }
                }
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

/// Pastilla de la pestaña activa. Va como **fondo** de la etiqueta (no como capa
/// hermana), así que el texto siempre queda por encima y legible. Una sola
/// instancia montada a la vez —la de la pestaña activa— con un `glassEffectID`
/// (macOS/iOS 26) o `matchedGeometryEffect` (fallback) constante, para que la
/// pastilla se deslice de una pestaña a otra (patrón "elemento viajero", igual
/// que `PlannerFloatingTabBar`). Cristal translúcido con presencia real: sobre
/// fondo claro los tints al 1–3% no se veían; aquí la pastilla tiene material +
/// hairline + brillo superior para leerse en claro y oscuro sin tapar el texto.
private struct NotebookTabSelectionPill: View {
    let namespace: Namespace.ID

    private static let morphID = "notebook-tab-selection"

    var body: some View {
        let shape = Capsule(style: .continuous)

        // Material translúcido (no cristal sobre cristal, que no contrastaba):
        // `.regularMaterial` es una superficie frosted claramente visible en
        // cualquier versión. Sombra + borde + brillo superior la hacen **flotar**
        // sobre la barra; el `matchedGeometryEffect` la desliza entre pestañas.
        shape
            .fill(.regularMaterial)
            .overlay {
                // Brillo superior: relieve de pastilla elevada.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.55), Color.white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
            }
            .overlay { shape.strokeBorder(NotebookGridStyle.gridLineStrong, lineWidth: 0.5) }
            .shadow(color: Color.black.opacity(0.14), radius: 5, x: 0, y: 2)
            .matchedGeometryEffect(id: Self.morphID, in: namespace)
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
                .glassEffect(.regular.interactive(), in: shape)
                .overlay {
                    shape.strokeBorder(NotebookGridStyle.gridLine, lineWidth: 0.5)
                }
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(NotebookGridStyle.gridLine, lineWidth: 0.5)
                }
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
