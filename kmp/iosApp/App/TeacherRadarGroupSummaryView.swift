import SwiftUI

struct TeacherRadarGroupSummaryView: View {
    let summary: TeacherRadarGroupSummary

    var body: some View {
        NotebookSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        NotebookSectionLabel(text: "Grupo")
                        Text(summary.className)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                    }
                    Spacer()
                    Image(systemName: "rectangle.3.group.fill")
                        .foregroundStyle(NotebookStyle.primaryTint)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    metric("Rúbricas", "\(summary.rubricCompletionRate)%", "checklist")
                    metric("Sin criterio", "\(summary.missingRubricStudentCount)", "square.and.pencil")
                    metric("Caída", "\(summary.fallingPerformanceCount)", "chart.line.downtrend.xyaxis")
                    metric("Lesionados", "\(summary.injuredCount)", "cross.case.fill")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Acción recomendada")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(summary.suggestedAction)
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(NotebookStyle.primaryTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(NotebookStyle.surfaceMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
