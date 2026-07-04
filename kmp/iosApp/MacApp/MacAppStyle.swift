import SwiftUI
import AppKit

enum MacAppStyle {
    static let pagePadding: CGFloat = AppleDesignSystem.pagePadding
    static let sectionSpacing: CGFloat = AppleDesignSystem.sectionSpacing
    static let cardSpacing: CGFloat = AppleDesignSystem.cardSpacing
    static let innerPadding: CGFloat = AppleDesignSystem.cardSpacing

    static let pageTitle: Font = .title3.weight(.semibold)
    static let sectionTitle: Font = .headline
    static let metricValue: Font = .system(size: 22, weight: .medium, design: .rounded)
    static let metricLabel: Font = .caption.weight(.medium)
    static let bodyText: Font = .callout

    static let cardBackground = MacLiquidGlassStyle.readableSurfaceFallback
    static let pageBackground = MacLiquidGlassStyle.pageBackground
    static let subtleFill = MacLiquidGlassStyle.secondaryPanelFallback

    static let cardBorder = MacLiquidGlassStyle.hairlineBorder
    static let divider = MacLiquidGlassStyle.hairlineBorder

    static let successTint = AppleDesignSystem.success
    static let warningTint = AppleDesignSystem.warning
    static let dangerTint = AppleDesignSystem.danger
    static let infoTint = AppleDesignSystem.accent

    static let cardRadius: CGFloat = AppleDesignSystem.cardRadius
    static let chipRadius: CGFloat = AppleDesignSystem.controlRadius

    static let smallStateAnimation: Animation = .spring(response: 0.35, dampingFraction: 0.75)
    static let smallStateTransition: AnyTransition = .opacity.combined(with: .scale(scale: 0.98))
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
                .contentTransition(.numericText())
        }
        .padding(MacAppStyle.innerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macLiquidGlassPanel(.primaryPanel, isActive: true, tint: tint, isInteractive: true)
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
                    .fill(MacLiquidGlassStyle.statusFill(isActive: isActive, tint: tint))
            }
    }
}

struct MacPopupActionBar: View {
    let title: String?
    var subtitle: String? = nil
    var saveTitle: String? = nil
    var saveSystemImage: String = "square.and.arrow.down"
    var canSave: Bool = true
    let onClose: () -> Void
    var onSave: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let title {
                        Text(title)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 12)

            Button {
                onClose()
            } label: {
                Label("Cerrar", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)

            if let saveTitle, let onSave {
                Button {
                    onSave()
                } label: {
                    Label(saveTitle, systemImage: saveSystemImage)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut("s", modifiers: [.command])
            }
        }
        .padding(.horizontal, MacAppStyle.innerPadding)
        .padding(.vertical, 12)
        .macLiquidGlassPanel(.chrome, cornerRadius: 0, isActive: true)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MacLiquidGlassStyle.hairlineBorder)
                .frame(height: MacLiquidGlassStyle.hairlineWidth)
        }
    }
}
