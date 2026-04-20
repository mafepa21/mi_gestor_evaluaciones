import SwiftUI
import AppKit

enum MacAppStyle {
    static let pagePadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 20
    static let cardSpacing: CGFloat = 12
    static let innerPadding: CGFloat = 16

    static let pageTitle: Font = .title2.weight(.semibold)
    static let sectionTitle: Font = .headline
    static let metricValue: Font = .system(size: 28, weight: .medium, design: .rounded)
    static let metricLabel: Font = .caption.weight(.medium)
    static let bodyText: Font = .callout

    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let pageBackground = Color(nsColor: .windowBackgroundColor)
    static let subtleFill = Color(nsColor: .quaternaryLabelColor).opacity(0.08)

    static let cardBorder = Color(nsColor: .separatorColor).opacity(0.6)
    static let divider = Color(nsColor: .separatorColor)

    static let successTint = Color.green
    static let warningTint = Color.orange
    static let dangerTint = Color.red
    static let infoTint = Color.accentColor

    static let cardRadius: CGFloat = 10
    static let chipRadius: CGFloat = 6
}

struct MacMetricCard: View {
    let label: String
    let value: String
    var tint: Color = MacAppStyle.infoTint
    var systemImage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(label.uppercased())
                    .font(MacAppStyle.metricLabel)
                    .foregroundStyle(.secondary)
                    .tracking(0.4)
            }

            Text(value)
                .font(MacAppStyle.metricValue)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(MacAppStyle.innerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacAppStyle.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous)
                .stroke(MacAppStyle.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacAppStyle.cardRadius, style: .continuous))
    }
}

struct MacSectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionLabel: String = "Ver todo"

    var body: some View {
        HStack {
            Text(title)
                .font(MacAppStyle.sectionTitle)
            Spacer()
            if let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct MacStatusPill: View {
    let label: String
    var isActive: Bool = false
    var tint: Color = MacAppStyle.infoTint

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isActive ? tint : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule(style: .continuous)
                    .fill((isActive ? tint : Color.secondary).opacity(0.12))
            }
    }
}
