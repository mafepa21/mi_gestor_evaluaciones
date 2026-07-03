import SwiftUI

struct PlannerLiquidGlassControls: View {
    @Binding var density: PlannerDensity
    let canOpenDiary: Bool
    let canCopySelection: Bool
    let canClearSchedulelessWeek: Bool
    let isSelectionModeActive: Bool
    let shareText: String
    let onPreviousWeek: () -> Void
    let onNextWeek: () -> Void
    let onToday: () -> Void
    let onSync: () -> Void
    let onToggleSelection: () -> Void
    let onCopyToNextWeek: () -> Void
    let onMoveOneDay: () -> Void
    let onClearSchedulelessWeek: () -> Void
    let onOpenDiary: () -> Void
    let onNewSession: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Namespace private var glassNamespace

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: glassContainerSpacing) {
                controls
            }
        } else {
            controls
        }
    }

    @ViewBuilder
    private var controls: some View {
        if usesCompactControls {
            compactControls
        } else {
            regularControls
        }
    }

    private var regularControls: some View {
        HStack(spacing: controlSpacing) {
            secondaryButton(systemImage: "chevron.left", label: "Semana anterior", glassID: "planner-week-previous", action: onPreviousWeek)
            secondaryButton(systemImage: "chevron.right", label: "Semana siguiente", glassID: "planner-week-next", action: onNextWeek)
            secondaryButton(systemImage: "calendar", label: "Hoy", glassID: "planner-week-today", action: onToday)
            secondaryMenu
            prominentButton
        }
    }

    private var compactControls: some View {
        HStack(spacing: controlSpacing) {
            secondaryButton(systemImage: "chevron.left", label: "Semana anterior", glassID: "planner-week-previous", action: onPreviousWeek)
            secondaryButton(systemImage: "chevron.right", label: "Semana siguiente", glassID: "planner-week-next", action: onNextWeek)
            secondaryButton(systemImage: "calendar", label: "Hoy", glassID: "planner-week-today", action: onToday)
            secondaryMenu
            prominentButton
        }
        .labelStyle(.iconOnly)
    }

    private var secondaryMenu: some View {
        Menu {
            Button("Sincronizar", systemImage: "arrow.triangle.2.circlepath", action: onSync)
            ShareLink(item: shareText) {
                Label("Compartir planificación", systemImage: "square.and.arrow.up")
            }
            Divider()
            Picker("Densidad", selection: $density) {
                ForEach(PlannerDensity.allCases) { density in
                    Text(density.rawValue).tag(density)
                }
            }
            Divider()
            Button(isSelectionModeActive ? "Salir de selección" : "Seleccionar sesiones", systemImage: "checklist", action: onToggleSelection)
            Button("Copiar a la semana siguiente", systemImage: "doc.on.doc", action: onCopyToNextWeek)
                .disabled(!canCopySelection)
            Button("Mover +1 día", systemImage: "arrow.right", action: onMoveOneDay)
                .disabled(!canCopySelection)
            Divider()
            Button("Abrir sesión en diario", systemImage: "play.rectangle.fill", action: onOpenDiary)
                .disabled(!canOpenDiary)
            Button("Limpiar semana sin franjas", systemImage: "trash", role: .destructive, action: onClearSchedulelessWeek)
                .disabled(!canClearSchedulelessWeek)
        } label: {
            Label("Acciones", systemImage: "ellipsis")
                .frame(minWidth: compactButtonSide, minHeight: compactButtonSide)
        }
        .plannerLiquidGlassControlButtonStyle()
        .plannerLiquidGlassControlIdentity("planner-week-actions", in: glassNamespace)
        .accessibilityLabel("Acciones secundarias")
    }

    private var prominentButton: some View {
        Button(action: onNewSession) {
            Label("Nueva sesión", systemImage: "plus")
                .frame(minWidth: usesCompactControls ? compactButtonSide : 0, minHeight: compactButtonSide)
        }
        .plannerLiquidGlassControlButtonStyle(isProminent: true)
        .plannerLiquidGlassControlIdentity("planner-week-new-session", in: glassNamespace)
        .accessibilityLabel("Nueva sesión")
    }

    private func secondaryButton(systemImage: String, label: String, glassID: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .frame(minWidth: compactButtonSide, minHeight: compactButtonSide)
        }
        .plannerLiquidGlassControlButtonStyle()
        .plannerLiquidGlassControlIdentity(glassID, in: glassNamespace)
        .accessibilityLabel(label)
    }

    private var usesCompactControls: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
        #else
        dynamicTypeSize.isAccessibilitySize
        #endif
    }

    private var compactButtonSide: CGFloat { 40 }
    private var controlSpacing: CGFloat { 16 }
    private var glassContainerSpacing: CGFloat { 16 }
}

private extension View {
    @ViewBuilder
    func plannerLiquidGlassControlButtonStyle(isProminent: Bool = false) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if isProminent {
                self
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.regular)
                    .tint(EvaluationDesign.accent)
            } else {
                self
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.regular)
            }
        } else {
            if isProminent {
                self
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.regular)
            } else {
                self
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.regular)
            }
        }
    }

    @ViewBuilder
    func plannerLiquidGlassControlIdentity(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}
