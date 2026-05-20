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
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(insight.priority.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(insight.priority.tint.opacity(0.14), lineWidth: 1)
        }
    }
}
