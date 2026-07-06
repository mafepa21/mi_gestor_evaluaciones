import SwiftUI

// MARK: - IOSCommandBar
struct IOSCommandBar<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            content
        }
        .padding(.horizontal, IOSAppStyle.compactPagePadding)
        .padding(.vertical, 10)
        .background(IOSAppStyle.cardBackground.opacity(0.85))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: IOSAppStyle.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IOSAppStyle.controlRadius, style: .continuous)
                .stroke(IOSAppStyle.cardBorder, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
}

// MARK: - IOSSearchField
struct IOSSearchField: View {
    @Binding var text: String
    var placeholder: String = "Buscar…"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .font(IOSAppStyle.bodyText)
                .textFieldStyle(.plain)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 38)
        .background(IOSAppStyle.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: IOSAppStyle.controlRadius, style: .continuous))
    }
}

// MARK: - IOSStatusPill
struct IOSStatusPill: View {
    let label: String
    var isActive: Bool = true
    var tint: Color = IOSAppStyle.info

    var body: some View {
        Text(label)
            .font(IOSAppStyle.captionText)
            .foregroundStyle(isActive ? tint : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? tint.opacity(0.12) : IOSAppStyle.subtleFill)
            )
            .overlay {
                if isActive {
                    Capsule(style: .continuous)
                        .stroke(tint.opacity(0.2), lineWidth: 1)
                }
            }
    }
}

// MARK: - IOSMetricCard
struct IOSMetricCard: View {
    let title: String
    let value: String
    var systemImage: String? = nil
    var tint: Color = IOSAppStyle.info

    var body: some View {
        PremiumCard.metric {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    Text(title.uppercased())
                        .font(IOSAppStyle.captionText)
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                        .lineLimit(1)
                }

                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

// MARK: - IOSEmptyState
struct IOSEmptyState: View {
    let title: String
    let subtitle: String
    var systemImage: String = "doc.text.magnifyingglass"

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary.opacity(0.7))

            Text(title)
                .font(IOSAppStyle.cardTitle)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(IOSAppStyle.bodyText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - IOSSheetHeader
struct IOSSheetHeader: View {
    let title: String
    var subtitle: String? = nil
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(IOSAppStyle.cardTitle)
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(IOSAppStyle.captionText)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, IOSAppStyle.pagePadding)
        .padding(.vertical, 14)
        .background(IOSAppStyle.cardBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(IOSAppStyle.cardBorder)
                .frame(height: 1)
        }
    }
}
