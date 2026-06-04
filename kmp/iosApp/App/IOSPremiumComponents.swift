import SwiftUI

// MARK: - IOSSectionCard
struct IOSSectionCard<Content: View>: View {
    let title: String?
    let systemImage: String?
    let content: Content

    init(title: String? = nil, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IOSAppStyle.cardSpacing) {
            if let title {
                HStack(spacing: 8) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(IOSAppStyle.info)
                    }
                    Text(title)
                        .font(IOSAppStyle.cardTitle)
                        .foregroundStyle(.primary)
                }
            }
            content
        }
        .padding(IOSAppStyle.cardSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IOSAppStyle.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: IOSAppStyle.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IOSAppStyle.cardRadius, style: .continuous)
                .stroke(IOSAppStyle.cardBorder, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
    }
}

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
        .padding(IOSAppStyle.cardSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IOSAppStyle.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: IOSAppStyle.innerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IOSAppStyle.innerRadius, style: .continuous)
                .stroke(IOSAppStyle.cardBorder, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 3)
    }
}

// MARK: - IOSPrimaryActionButton
struct IOSPrimaryActionButton: View {
    let label: String
    let systemImage: String
    var tint: Color = IOSAppStyle.info
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                Text(label)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: IOSAppStyle.controlRadius, style: .continuous)
                    .fill(isEnabled ? tint : tint.opacity(0.5))
                    .shadow(color: (isEnabled ? tint : Color.clear).opacity(0.15), radius: 6, x: 0, y: 3)
            )
        }
        .disabled(!isEnabled)
        .buttonStyle(.plain)
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
