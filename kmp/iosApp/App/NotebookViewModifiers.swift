import SwiftUI

private struct NotebookNavigationSubtitleModifier: ViewModifier {
    let subtitle: String

    func body(content: Content) -> some View {
        #if os(macOS)
        if #available(iOS 26.0, macOS 26.0, *) {
            content.navigationSubtitle(subtitle)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct NotebookKeyboardNavigationModifier: ViewModifier {
    let onNext: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            content
                .focusable()
                .onKeyPress(.return) {
                    onNext()
                    return .handled
                }
                .onKeyPress(.tab) {
                    onNext()
                    return .handled
                }
        } else {
            content
        }
    }
}

extension View {
    func notebookNavigationSubtitle(_ subtitle: String) -> some View {
        modifier(NotebookNavigationSubtitleModifier(subtitle: subtitle))
    }

    func notebookKeyboardNavigation(onNext: @escaping () -> Void) -> some View {
        modifier(NotebookKeyboardNavigationModifier(onNext: onNext))
    }
}
