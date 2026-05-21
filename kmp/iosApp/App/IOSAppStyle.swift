import SwiftUI

enum IOSAppStyle {
    static let pagePadding: CGFloat = 20
    static let compactPagePadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 18
    static let cardSpacing: CGFloat = 14

    static let cardRadius: CGFloat = 20
    static let innerRadius: CGFloat = 14
    static let controlRadius: CGFloat = 12

    static let pageTitle: Font = .system(size: 28, weight: .black, design: .rounded)
    static let sectionTitle: Font = .headline
    static let cardTitle: Font = .system(size: 16, weight: .bold, design: .rounded)
    static let bodyText: Font = .callout
    static let captionText: Font = .caption.weight(.semibold)

    static var pageBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(.systemGroupedBackground)
        #endif
    }
    static var cardBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(.secondarySystemGroupedBackground)
        #endif
    }
    static let subtleFill = Color.secondary.opacity(0.08)
    static let cardBorder = Color.primary.opacity(0.08)

    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let info = Color.accentColor
}
