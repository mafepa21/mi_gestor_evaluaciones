import SwiftUI
import MiGestorKit

struct PlannerWeekMiniatureLayout: View {
    @ObservedObject var weekBoard: PlannerWeekBoardStore
    let vm: PlannerWorkspaceViewModel
    @Binding var selectedCell: PlannerCellKey?
    @Binding var selectedDay: Int?
    let onOpenSession: (PlanningSession) -> Void
    var onOpenDiary: ((PlanningSession) -> Void)? = nil
    var onDropSession: ((Int64, Int, Int) -> Void)? = nil
    /// "Semana" es la pestaña por defecto del Planner: si el profesor no ha
    /// configurado nunca su horario, esta es la primera pantalla que ve. Un
    /// estado vacío accionable aquí evita depender de que descubra la
    /// pestaña "Resumen" para encontrar el configurador.
    var onOpenSettings: (() -> Void)? = nil

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var isDetailPaneVisible = true

    private var isRegularWidth: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        true
        #endif
    }

    var body: some View {
        Group {
            if isRegularWidth {
                regularLayout
            } else {
                compactLayout
            }
        }
    }

    /// iPad apaisado y Mac: grid a la izquierda, detalle como panel lateral
    /// persistente (estilo inspector) para poder ver ambos a la vez.
    private var regularLayout: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Semana")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                detailPaneToggle
            }

            HStack(alignment: .top, spacing: 16) {
                grid
                    .frame(height: gridHeight)
                    .padding(16)
                    .plannerGlassPanel(.content, cornerRadius: 24)
                    .frame(maxWidth: .infinity, alignment: .top)

                if isDetailPaneVisible {
                    ScrollView(.vertical) {
                        detailPane
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(width: 400)
                    .plannerGlassPanel(.content, cornerRadius: 24)
                }
            }
        }
        .padding(.horizontal, EvaluationDesign.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    private var detailPaneToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isDetailPaneVisible.toggle()
            }
        } label: {
            Label(
                isDetailPaneVisible ? "Ocultar detalle" : "Mostrar detalle",
                systemImage: "sidebar.right"
            )
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
        .controlSize(.small)
        .accessibilityHint("Amplía o recupera el inspector lateral del grid semanal")
    }

    /// iPhone y iPad en vertical: grid arriba, detalle debajo en un único scroll.
    private var compactLayout: some View {
        ScrollView(.vertical) {
            VStack(spacing: 16) {
                grid
                    .frame(height: gridHeight)
                    .padding(16)
                    .plannerGlassPanel(.content, cornerRadius: 24)
                    .padding(.horizontal, EvaluationDesign.screenPadding)
                    .padding(.top, 8)

                detailPane
                    .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var grid: some View {
        if vm.effectiveScheduleSlots.isEmpty {
            emptyScheduleState
        } else {
            PlannerWeekMiniatureGrid(
                weekBoard: weekBoard,
                vm: vm,
                selectedCell: $selectedCell,
                selectedDay: $selectedDay,
                onOpenSession: onOpenSession,
                onOpenDiary: onOpenDiary,
                onDropSession: onDropSession
            )
        }
    }

    /// Sin horario configurado, un grid vacío no dice nada útil. Una única
    /// tarea obvia ("Configurar mi horario") en vez de una rejilla en blanco.
    private var emptyScheduleState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(EvaluationDesign.accent)

            VStack(spacing: 6) {
                Text("Aún no has configurado tu horario semanal")
                    .font(.title3.weight(.semibold))
                Text("Define tus franjas lectivas para planificar sesiones y ver la cobertura del curso.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            if let onOpenSettings {
                Button("Configurar mi horario") {
                    onOpenSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(32)
    }

    private var detailPane: some View {
        PlannerWeekDetailPane(
            weekBoard: weekBoard,
            vm: vm,
            selectedCell: $selectedCell,
            selectedDay: $selectedDay,
            onOpenSession: onOpenSession
        )
    }

    private var gridHeight: CGFloat {
        guard !vm.effectiveScheduleSlots.isEmpty else { return 280 }
        let slotsCount = weekBoard.weekRenderModel.visibleSlots.count
        guard slotsCount > 0 else { return 40 }
        let rowHeight: CGFloat = vm.density == .compact ? 44 : 56
        let spacing: CGFloat = 4
        return 40 + CGFloat(slotsCount) * (rowHeight + spacing) + spacing
    }
}

enum PlannerGlassPanelRole {
    case hero
    case content
    case control
}

private struct PlannerGlassPanelModifier: ViewModifier {
    let role: PlannerGlassPanelRole
    let cornerRadius: CGFloat
    let tint: Color?
    let isInteractive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, macOS 26.0, *) {
            content
                .background {
                    shape.fill(nativeFill)
                }
                .glassEffect(nativeGlass.interactive(isInteractive), in: shape)
                .overlay {
                    shape.stroke(nativeBorder, lineWidth: 0.5)
                }
                .overlay(alignment: .top) {
                    shape
                        .stroke(Color.white.opacity(role == .hero ? 0.18 : 0.12), lineWidth: 1)
                        .blur(radius: 0.5)
                        .mask {
                            LinearGradient(
                                colors: [.black, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                }
                .clipShape(shape)
                .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
        } else {
            content
                .background(fallbackFill, in: shape)
                .overlay {
                    shape.stroke(EvaluationDesign.border.opacity(role == .hero ? 0.72 : 0.56), lineWidth: 1)
                }
                .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
        }
    }

    private var nativeFill: Color {
        switch role {
        case .hero:
            return Color.white.opacity(0.035)
        case .content:
            return Color.white.opacity(0.018)
        case .control:
            return Color.white.opacity(0.025)
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var nativeGlass: Glass {
        let base: Glass = .regular
        if let tint {
            return base.tint(tint.opacity(role == .hero ? 0.10 : 0.07))
        }
        switch role {
        case .hero:
            return base.tint(EvaluationDesign.accent.opacity(0.055))
        case .content:
            return base.tint(Color.white.opacity(0.025))
        case .control:
            return base.tint(Color.white.opacity(0.04))
        }
    }

    private var nativeBorder: Color {
        switch role {
        case .hero:
            return Color.white.opacity(0.16)
        case .content:
            return Color.white.opacity(0.10)
        case .control:
            return Color.white.opacity(0.12)
        }
    }

    private var fallbackFill: AnyShapeStyle {
        switch role {
        case .hero:
            return AnyShapeStyle(.thinMaterial)
        case .content, .control:
            return AnyShapeStyle(.ultraThinMaterial)
        }
    }

    private var shadowColor: Color {
        .black.opacity(role == .hero ? 0.10 : 0.06)
    }

    private var shadowRadius: CGFloat {
        role == .hero ? 16 : 10
    }

    private var shadowY: CGFloat {
        role == .hero ? 8 : 5
    }
}

extension View {
    func plannerGlassPanel(
        _ role: PlannerGlassPanelRole = .content,
        cornerRadius: CGFloat = 24,
        tint: Color? = nil,
        isInteractive: Bool = false
    ) -> some View {
        modifier(
            PlannerGlassPanelModifier(
                role: role,
                cornerRadius: cornerRadius,
                tint: tint,
                isInteractive: isInteractive
            )
        )
    }
}

/// Cápsula con icono para el estado de una sesión (planificada/impartida/revisión/etc.),
/// único estilo de badge de estado en todo el Planner.
struct PlannerStatusBadge: View {
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule(style: .continuous))
            .accessibilityElement(children: .combine)
    }
}
