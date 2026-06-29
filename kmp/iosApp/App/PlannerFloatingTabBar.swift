import SwiftUI

struct PlannerFloatingTabBar: View {
    @Binding var activeSection: PlannerWorkspaceSection
    @Namespace private var selectionNamespace

    var body: some View {
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
                            Capsule(style: .continuous)
                                .fill(.thinMaterial)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                                .matchedGeometryEffect(id: "planner-tab-selection", in: selectionNamespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.rawValue)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(EvaluationDesign.border.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}
