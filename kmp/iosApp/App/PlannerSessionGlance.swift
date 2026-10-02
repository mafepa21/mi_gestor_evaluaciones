import SwiftUI

struct PlannerSessionGlanceContent: View {
    let data: PlannerSessionGlanceData
    let tint: Color
    let style: PlannerSessionGlanceStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(data.situationTitle)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(style == .expanded ? 2 : 1)

            if !data.badges.isEmpty {
                HStack(spacing: 6) {
                    ForEach(data.badges, id: \.self) { badge in
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(tint.opacity(0.10), in: Capsule())
                    }
                }
            }

            Text(data.sessionTitle)
                .font(style == .expanded ? .title3.weight(.bold) : .headline.weight(.semibold))
                .lineLimit(style == .expanded ? 3 : 2)
                .fixedSize(horizontal: false, vertical: true)

            if let objective = data.objective {
                glanceText(label: "Objetivo", value: objective, lineLimit: style == .expanded ? 4 : 2)
            }

            if let activity = data.activity {
                glanceText(label: style == .expanded ? "Qué toca" : nil, value: activity, lineLimit: style == .expanded ? 4 : 2)
            }

            if style == .expanded, let material = data.material {
                glanceText(label: "Material", value: material, lineLimit: 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func glanceText(label: String?, value: String, lineLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let label {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(style == .expanded ? .subheadline : .subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(lineLimit)
                .lineSpacing(2)
        }
    }
}
