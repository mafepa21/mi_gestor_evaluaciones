import SwiftUI

enum AppKeyboardKind {
    case decimalPad
    case numberPad
}

func appSecondarySystemBackgroundColor() -> Color {
#if os(macOS)
    Color(nsColor: .controlBackgroundColor)
#else
    Color(.secondarySystemBackground)
#endif
}

func appTertiarySystemBackgroundColor() -> Color {
#if os(macOS)
    Color(nsColor: .windowBackgroundColor)
#else
    Color(.tertiarySystemBackground)
#endif
}

func appTertiarySystemFillColor() -> Color {
#if os(macOS)
    Color(nsColor: .separatorColor)
#else
    Color(.tertiarySystemFill)
#endif
}

extension View {
    @ViewBuilder
    func appInlineNavigationBarTitleDisplayMode() -> some View {
#if os(macOS)
        self
#else
        self.navigationBarTitleDisplayMode(.inline)
#endif
    }

    @ViewBuilder
    func appKeyboardType(_ kind: AppKeyboardKind) -> some View {
#if os(macOS)
        self
#else
        switch kind {
        case .decimalPad:
            self.keyboardType(.decimalPad)
        case .numberPad:
            self.keyboardType(.numberPad)
        }
#endif
    }

    @ViewBuilder
    func appFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
#if os(macOS)
        self.sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
#else
        self.fullScreenCover(isPresented: isPresented, onDismiss: onDismiss, content: content)
#endif
    }

    @ViewBuilder
    func appNavigationBarHidden(_ hidden: Bool) -> some View {
#if os(macOS)
        self
#else
        self.navigationBarHidden(hidden)
#endif
    }

    @ViewBuilder
    func appHoverLiftEffect() -> some View {
#if os(macOS)
        self
#else
        self.hoverEffect(.lift)
#endif
    }
}

#if os(macOS)
extension ToolbarItemPlacement {
    static var navigationBarLeading: ToolbarItemPlacement { .navigation }
    static var navigationBarTrailing: ToolbarItemPlacement { .primaryAction }
    static var topBarLeading: ToolbarItemPlacement { .navigation }
    static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
}
#endif
