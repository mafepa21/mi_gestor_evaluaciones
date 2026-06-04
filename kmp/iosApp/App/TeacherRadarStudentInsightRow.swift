import SwiftUI

struct TeacherRadarStudentInsightRow: View {
    let insight: TeacherRadarInsightDraft

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.priority.systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(insight.priority.tint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(insight.priority.title.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(insight.priority.tint)
                    Text(insight.title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Text(insight.detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(insight.suggestedAction)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            insight.priority.tint.opacity(0.04)
                .overlay(
                    RoundedRectangle(cornerRadius: EvaluationDesign.pillRadius, style: .continuous)
                        .stroke(insight.priority.tint.opacity(0.12), lineWidth: 1)
                )
        )
        .cornerRadius(EvaluationDesign.pillRadius)
    }
}
