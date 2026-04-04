import SwiftUI

enum EvaluationDesign {
    static let screenPadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 32
    static let cardSpacing: CGFloat = 16
    static let cardRadius: CGFloat = 40
    static let innerRadius: CGFloat = 16
    static let pillRadius: CGFloat = 12
    static let accent = Color(red: 0.09, green: 0.32, blue: 0.92)
    static let accentSoft = Color(red: 0.09, green: 0.32, blue: 0.92).opacity(0.12)
    static let success = Color(red: 0.12, green: 0.65, blue: 0.46)
    static let danger = Color(red: 0.90, green: 0.20, blue: 0.22)
    static let surface = Color(.secondarySystemBackground)
    static let surfaceMuted = Color(.secondarySystemBackground)
    static let surfaceSoft = Color(.tertiarySystemBackground)
    static let border = Color.black.opacity(0.06)
    static let shadow = Color.black.opacity(0.08)
    static let plannerCoursePalette: [String] = [
        "#2563EB",
        "#0F766E",
        "#DC2626",
        "#7C3AED",
        "#EA580C",
        "#0891B2",
        "#65A30D",
        "#BE185D",
        "#4F46E5",
        "#B45309"
    ]
}

enum AppDateTimeSupport {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "es_ES_POSIX")
        return calendar
    }()

    static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func date(fromISO isoDate: String, fallback: Date = .now) -> Date {
        isoDateFormatter.date(from: isoDate) ?? fallback
    }

    static func isoDateString(from date: Date) -> String {
        isoDateFormatter.string(from: date)
    }

    static func time(from string: String, fallback: Date = .now) -> Date {
        guard let parsed = timeFormatter.date(from: string.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return fallback
        }
        let components = calendar.dateComponents([.hour, .minute], from: parsed)
        return calendar.date(bySettingHour: components.hour ?? 8, minute: components.minute ?? 0, second: 0, of: fallback) ?? fallback
    }

    static func timeString(from date: Date) -> String {
        timeFormatter.string(from: date)
    }
}

struct EvaluationBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.08, blue: 0.14),
                        Color(red: 0.08, green: 0.11, blue: 0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.98, blue: 1.0),
                        Color(red: 0.99, green: 0.98, blue: 0.99)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [EvaluationDesign.accent.opacity(0.12), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 260
                    )
                )
                .frame(width: 460, height: 460)
                .offset(x: -180, y: -220)
                .blur(radius: 40)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.45, green: 0.70, blue: 1.0).opacity(0.10), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 220
                    )
                )
                .frame(width: 380, height: 380)
                .offset(x: 180, y: 260)
                .blur(radius: 50)
        }
        .ignoresSafeArea()
    }
}

struct EvaluationGlassCard<Content: View>: View {
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let fillOpacity: Double
    let content: Content

    init(cornerRadius: CGFloat = EvaluationDesign.cardRadius, fillOpacity: Double = 0.82, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.fillOpacity = fillOpacity
        self.content = content()
    }

    var body: some View {
        content
            .padding(EvaluationDesign.screenPadding)
            .background(
                adaptiveSurfaceBackground(
                    accessibilityFallback: uiFeatureFlags.accessibilitySurfaceFallback,
                    fill: colorScheme == .dark
                        ? appCardBackground(for: .dark).opacity(fillOpacity)
                        : appCardBackground(for: .light).opacity(fillOpacity),
                    cornerRadius: cornerRadius
                )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(EvaluationDesign.border, lineWidth: 1)
                    )
                    .shadow(color: EvaluationDesign.shadow.opacity(0.20), radius: 18, x: 0, y: 8)
            )
    }
}

struct EvaluationChip: View {
    let label: String
    var systemImage: String? = nil
    var active: Bool = false
    var tint: Color = EvaluationDesign.accent
    var isDestructive: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
            }

            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(active ? contrastingTextColor(for: isDestructive ? EvaluationDesign.danger : tint) : (isDestructive ? EvaluationDesign.danger : tint))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(active ? tint : (isDestructive ? EvaluationDesign.danger.opacity(0.10) : tint.opacity(0.10)))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(active ? tint : tint.opacity(0.10), lineWidth: 1)
                )
        )
    }
}

struct EvaluationIconButton: View {
    let systemImage: String
    let tint: Color
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.10), in: Circle())
                .overlay(Circle().stroke(tint.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? systemImage)
    }
}

struct EvaluationPrimaryButton: View {
    let label: String
    let systemImage: String
    var tint: Color = EvaluationDesign.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                Text(label)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundStyle(contrastingTextColor(for: tint))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint)
                    .shadow(color: tint.opacity(0.18), radius: 12, x: 0, y: 6)
            )
        }
        .buttonStyle(.plain)
    }
}

struct EvaluationScoreBadge: View {
    let title: String
    let value: String
    var tint: Color = EvaluationDesign.success

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct EvaluationAvatar: View {
    let initials: String
    var tint: Color = EvaluationDesign.accent

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.12))
            Text(initials.uppercased())
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(width: 48, height: 48)
    }
}

struct EvaluationSectionTitle: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct EvaluationLevelTile: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    var tint: Color = EvaluationDesign.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : .primary)

                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                    .lineLimit(3)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                    .fill(isSelected ? tint : EvaluationDesign.surfaceSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                            .stroke(isSelected ? tint : EvaluationDesign.border, lineWidth: 1)
                    )
            )
            .shadow(color: isSelected ? tint.opacity(0.22) : EvaluationDesign.shadow.opacity(0.08), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

struct EvaluationDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.06))
            .frame(height: 1)
    }
}
