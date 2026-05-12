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

    @ViewBuilder
    func appWritingToolsDisabled() -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            self.writingToolsBehavior(.disabled)
        } else {
            self
        }
    }

    @ViewBuilder
    func appOnChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value, perform: action)
        }
    }

    @ViewBuilder
    func appOnChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value, Value) -> Void
    ) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            self.onChange(of: value) { oldValue, newValue in
                action(oldValue, newValue)
            }
        } else {
            self.onChange(of: value) { newValue in
                action(newValue, newValue)
            }
        }
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
