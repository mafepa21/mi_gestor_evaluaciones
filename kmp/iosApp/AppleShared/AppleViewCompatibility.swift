import SwiftUI

enum AppKeyboardKind {
    case decimalPad
    case numberPad
    /// Teclado de direcciones web: sin autocorrección ni mayúscula inicial, con la
    /// barra y el punto a mano. Para campos donde se pega o escribe una URL.
    case url
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

/// Color de marca con variante propia para modo oscuro (en vez de una sola
/// mezcla fija), necesaria para mantener contraste AA de los colores de
/// estado sobre fondos oscuros.
func appAdaptiveBrandColor(
    light: (red: Double, green: Double, blue: Double),
    dark: (red: Double, green: Double, blue: Double)
) -> Color {
#if os(macOS)
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let c = isDark ? dark : light
        return NSColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
    })
#else
    Color(uiColor: UIColor { traits in
        let c = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
    })
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
        case .url:
            // Autocorregir una URL la rompe, y la mayúscula inicial también.
            self.keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
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
    func appFullScreenCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
#if os(macOS)
        self.sheet(item: item, onDismiss: onDismiss, content: content)
#else
        self.fullScreenCover(item: item, onDismiss: onDismiss, content: content)
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

    @ViewBuilder
    func appEditMode(isSelectionMode: Bool) -> some View {
#if os(iOS)
        self.environment(\.editMode, .constant(isSelectionMode ? .inactive : .active))
#else
        self
#endif
    }

    @ViewBuilder
    func appSearchable(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic,
        prompt: String
    ) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            self.searchable(text: text, isPresented: isPresented, placement: placement, prompt: prompt)
        } else {
            self.searchable(text: text, placement: placement, prompt: prompt)
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

// MARK: - Shared Selection Store
/// Centralises class + student selection across iOS shell (IOSRootView) and macOS shell (MacRootView).
@MainActor
final class StudentSelectionStore: ObservableObject {
    @Published var selectedClassId: Int64?
    @Published var selectedStudentId: Int64?
    @Published private(set) var selectionRevision: Int = 0

    var selectedClassBinding: Binding<Int64?> {
        Binding(
            get: { self.selectedClassId },
            set: { self.setClass($0) }
        )
    }

    var selectedStudentBinding: Binding<Int64?> {
        Binding(
            get: { self.selectedStudentId },
            set: { self.setStudent($0) }
        )
    }

    func select(classId: Int64?, studentId: Int64?) {
        guard selectedClassId != classId || selectedStudentId != studentId else { return }
        selectedClassId = classId
        selectedStudentId = studentId
        selectionRevision &+= 1
    }

    func setClass(_ classId: Int64?) {
        guard selectedClassId != classId else { return }
        selectedClassId = classId
        selectionRevision &+= 1
    }

    func setStudent(_ studentId: Int64?) {
        guard selectedStudentId != studentId else { return }
        selectedStudentId = studentId
        selectionRevision &+= 1
    }
}
