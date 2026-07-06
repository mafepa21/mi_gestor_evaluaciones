import SwiftUI

enum IOSAppStyle {
    static let pagePadding: CGFloat = AppleDesignSystem.compactPagePadding
    static let compactPagePadding: CGFloat = AppleDesignSystem.tightPagePadding
    static let sectionSpacing: CGFloat = 18
    static let cardSpacing: CGFloat = AppleDesignSystem.compactCardSpacing

    static let cardRadius: CGFloat = AppleDesignSystem.regularCardRadius
    static let innerRadius: CGFloat = 14
    static let controlRadius: CGFloat = AppleDesignSystem.regularControlRadius

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
    static let cardBorder = AppleDesignSystem.border
    static let shadow = AppleDesignSystem.shadow

    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let info = Color.accentColor
}
