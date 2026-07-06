import SwiftUI

struct PlannerFloatingTabBar: View {
    @Binding var activeSection: PlannerWorkspaceSection
    @Namespace private var selectionNamespace

    var body: some View {
        PlannerFloatingTabGlassContainer {
            HStack(spacing: 4) {
                ForEach(PlannerWorkspaceSection.allCases) { section in
                    Button {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                            activeSection = section
                        }
                    } label: {
                        ZStack {
                            if activeSection == section {
                                PlannerFloatingTabSelectionBackground(namespace: selectionNamespace)
                                    .allowsHitTesting(false)
                                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            }

                            VStack(spacing: 2) {
                                Image(systemName: section.systemImage)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(section.rawValue)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(activeSection == section ? Color.primary.opacity(0.88) : Color.secondary)
                            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
                            .padding(.horizontal, 4)
                        }
                        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(section.rawValue)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(height: 40)
        .plannerFloatingTabGlassSurface()
    }
}

private struct PlannerFloatingTabGlassContainer<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: 4) {
                content
            }
        } else {
            content
        }
    }
}

private struct PlannerFloatingTabSelectionBackground: View {
    let namespace: Namespace.ID

    var body: some View {
        let shape = Capsule(style: .continuous)

        shape
            .fill(selectionFallbackFill)
            .plannerFloatingTabNativeSelectionGlass(in: shape, namespace: namespace)
            .overlay {
                shape.stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.025), radius: 3, x: 0, y: 1)
            .matchedGeometryEffect(id: "planner-tab-selection", in: namespace)
    }

    private var selectionFallbackFill: AnyShapeStyle {
        if #available(iOS 26.0, macOS 26.0, *) {
            return AnyShapeStyle(Color.white.opacity(0.008))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }
}

private extension View {
    @ViewBuilder
    func plannerFloatingTabGlassSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .background { shape.fill(Color.white.opacity(0.01)) }
                .glassEffect(.regular.tint(Color.white.opacity(0.018)).interactive(), in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(0.07), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.025), radius: 8, x: 0, y: 4)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(EvaluationDesign.border.opacity(0.45), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 3)
        }
    }

    @ViewBuilder
    func plannerFloatingTabNativeSelectionGlass(
        in shape: Capsule,
        namespace: Namespace.ID
    ) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .glassEffect(.regular.tint(EvaluationDesign.accent.opacity(0.04)).interactive(), in: shape)
                .glassEffectID("planner-tab-selection", in: namespace)
        } else {
            self
        }
    }
}
