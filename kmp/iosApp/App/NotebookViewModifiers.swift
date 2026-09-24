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

enum NotebookGridKeyCommand: Equatable {
    case move(NotebookNavigationDirection)
    case edit
    case cancel
    case type(String)
}

private struct NotebookKeyboardNavigationModifier: ViewModifier {
    var isActive: FocusState<Bool>.Binding
    let onCommand: (NotebookGridKeyCommand) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            #if os(macOS)
            content
                .focusable()
                .focused(isActive)
                .onKeyPress(phases: [.down, .repeat]) { press in
                    handleMacKeyPress(press)
                }
            #else
            content
                .focusable()
                .focused(isActive)
                .onKeyPress(.return) {
                    onCommand(.edit)
                    return .handled
                }
                .onKeyPress(.tab) {
                    onCommand(.move(.down))
                    return .handled
                }
            #endif
        } else {
            content
        }
    }

    @available(iOS 17.0, macOS 14.0, *)
    private func handleMacKeyPress(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers.contains(.command) || press.modifiers.contains(.control) || press.modifiers.contains(.option) {
            return .ignored
        }
        let isRepeat = press.phase == .repeat
        switch press.key {
        case .upArrow:
            onCommand(.move(.up))
            return .handled
        case .downArrow:
            onCommand(.move(.down))
            return .handled
        case .leftArrow:
            onCommand(.move(.left))
            return .handled
        case .rightArrow:
            onCommand(.move(.right))
            return .handled
        case .tab:
            guard !isRepeat else { return .handled }
            onCommand(.move(press.modifiers.contains(.shift) ? .left : .right))
            return .handled
        case .return:
            guard !isRepeat else { return .handled }
            onCommand(.edit)
            return .handled
        case .escape:
            guard !isRepeat else { return .handled }
            onCommand(.cancel)
            return .handled
        default:
            guard !isRepeat else { return .ignored }
            guard let seed = gradeCharacter(from: press.characters) else { return .ignored }
            onCommand(.type(seed))
            return .handled
        }
    }

    private func gradeCharacter(from characters: String) -> String? {
        guard characters.count == 1, let scalar = characters.unicodeScalars.first else { return nil }
        if CharacterSet.decimalDigits.contains(scalar) || characters == "," || characters == "." {
            return characters
        }
        return nil
    }
}

extension View {
    func notebookNavigationSubtitle(_ subtitle: String) -> some View {
        modifier(NotebookNavigationSubtitleModifier(subtitle: subtitle))
    }

    func notebookKeyboardNavigation(
        isActive: FocusState<Bool>.Binding,
        onCommand: @escaping (NotebookGridKeyCommand) -> Void
    ) -> some View {
        modifier(NotebookKeyboardNavigationModifier(isActive: isActive, onCommand: onCommand))
    }

    @ViewBuilder
    func notebookSearchable(if condition: Bool, text: Binding<String>, prompt: String) -> some View {
        if condition {
            self.searchable(text: text, prompt: prompt)
        } else {
            self
        }
    }
}
