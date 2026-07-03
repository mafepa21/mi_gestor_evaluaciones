import SwiftUI
import MiGestorKit

struct PlannerWeekMiniatureLayout: View {
    @ObservedObject var weekBoard: PlannerWeekBoardStore
    let vm: PlannerWorkspaceViewModel
    @Binding var selectedCell: PlannerCellKey?
    @Binding var selectedDay: Int?
    let onOpenSession: (PlanningSession) -> Void
    var onDropSession: ((Int64, Int, Int) -> Void)? = nil

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 16) {
                PlannerWeekMiniatureGrid(
                    weekBoard: weekBoard,
                    vm: vm,
                    selectedCell: $selectedCell,
                    selectedDay: $selectedDay,
                    onDropSession: onDropSession
                )
                .frame(height: gridHeight)
                .padding(16)
                .plannerGlassPanel(.content, cornerRadius: 24)
                .padding(.horizontal, EvaluationDesign.screenPadding)
                .padding(.top, 8)

                PlannerWeekDetailPane(
                    weekBoard: weekBoard,
                    vm: vm,
                    selectedCell: $selectedCell,
                    selectedDay: $selectedDay,
                    onOpenSession: onOpenSession
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 24)
        }
    }

    private var gridHeight: CGFloat {
        let slotsCount = weekBoard.weekRenderModel.visibleSlots.count
        guard slotsCount > 0 else { return 40 }
        let rowHeight: CGFloat = 36
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
