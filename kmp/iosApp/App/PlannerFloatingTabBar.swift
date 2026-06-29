import SwiftUI

struct PlannerFloatingTabBar: View {
    @Binding var activeSection: PlannerWorkspaceSection
    @Namespace private var selectionNamespace

    var body: some View {
        PlannerFloatingTabGlassContainer {
            HStack(spacing: 0) {
                ForEach(PlannerWorkspaceSection.allCases) { section in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            activeSection = section
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: section.systemImage)
                                .font(.system(size: 16, weight: .semibold))
                            Text(section.rawValue)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(activeSection == section ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .padding(.horizontal, 8)
                        .background {
                            if activeSection == section {
                                PlannerFloatingTabSelectionBackground(namespace: selectionNamespace)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(section.rawValue)
                }
            }
        }
        .padding(8)
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
            GlassEffectContainer(spacing: 8) {
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
                shape.stroke(Color.white.opacity(0.22), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
            .matchedGeometryEffect(id: "planner-tab-selection", in: namespace)
    }

    private var selectionFallbackFill: AnyShapeStyle {
        if #available(iOS 26.0, macOS 26.0, *) {
            return AnyShapeStyle(Color.white.opacity(0.08))
        }
        return AnyShapeStyle(.thinMaterial)
    }
}

private extension View {
    @ViewBuilder
    func plannerFloatingTabGlassSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .background { shape.fill(Color.white.opacity(0.035)) }
                .glassEffect(.regular.interactive(), in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 5)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(EvaluationDesign.border.opacity(0.7), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        }
    }

    @ViewBuilder
    func plannerFloatingTabNativeSelectionGlass(
        in shape: Capsule,
        namespace: Namespace.ID
    ) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .glassEffect(.regular.tint(EvaluationDesign.accent.opacity(0.14)).interactive(), in: shape)
                .glassEffectID("planner-tab-selection", in: namespace)
        } else {
            self
        }
    }
}
