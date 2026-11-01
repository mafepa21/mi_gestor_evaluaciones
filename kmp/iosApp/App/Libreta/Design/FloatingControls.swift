import SwiftUI

// MARK: - Superficie flotante

extension View {
    /// Fondo de los controles que flotan sobre el cuaderno: material translúcido con un
    /// velo cálido, filo fino y sombra suave. Se retira para no competir con el papel.
    func floatingSurface<S: InsettableShape>(_ shape: S) -> some View {
        background {
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(Theme.barTint))
                .overlay(shape.strokeBorder(Theme.barStroke, lineWidth: 0.5))
                .shadow(color: Theme.shadow.opacity(0.55), radius: 10, x: 0, y: 4)
        }
    }

    /// Aspecto de un icono de barra (útil para etiquetas de `Menu` o `PhotosPicker`,
    /// que no siempre respetan un `ButtonStyle`).
    func toolbarIconChrome(isActive: Bool = false) -> some View {
        modifier(ToolbarIconChrome(isActive: isActive, isPressed: false))
    }
}

/// Barra flotante en forma de cápsula. Pensada para `ToolbarIconButtonStyle`.
///
///     FloatingBar {
///         Button { … } label: { Image(systemName: "magnifyingglass") }
///         FloatingBarDivider()
///         …
///     }
///     .buttonStyle(ToolbarIconButtonStyle())
struct FloatingBar<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 2, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        HStack(spacing: spacing) { content }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .foregroundStyle(Theme.ink)
            .tint(Theme.accent)
            .floatingSurface(Capsule(style: .continuous))
    }
}

/// Separador vertical fino entre grupos de una `FloatingBar`.
struct FloatingBarDivider: View {
    init() {}
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1, height: 22)
            .padding(.horizontal, 6)
            .accessibilityHidden(true)
    }
}

// MARK: - Estilos de botón

/// Icono de barra: 40 pt, trazo del sistema, tinta cálida. `isActive` lo marca con
/// el acento (modo encendido, hoja marcada…).
struct ToolbarIconButtonStyle: ButtonStyle {
    var isActive: Bool

    init(isActive: Bool = false) {
        self.isActive = isActive
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(ToolbarIconChrome(isActive: isActive, isPressed: configuration.isPressed))
    }
}

struct ToolbarIconChrome: ViewModifier {
    var isActive: Bool
    var isPressed: Bool
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .labelStyle(.iconOnly)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(isActive ? Theme.accent : Theme.ink)
            .frame(width: 40, height: 40)
            .background {
                Circle().fill(isActive ? Theme.accent.opacity(0.14)
                                       : (isPressed ? Theme.ink.opacity(0.08) : Color.clear))
            }
            .contentShape(Circle())
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(isPressed ? 0.92 : 1)
            .animation(.spring(duration: 0.2), value: isPressed)
    }
}

/// Botón con icono y texto dentro de una barra flotante ("Imagen", "Texto"…).
struct ToolbarLabelButtonStyle: ButtonStyle {
    init() {}

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background {
                Capsule(style: .continuous)
                    .fill(configuration.isPressed ? Theme.ink.opacity(0.08) : Color.clear)
            }
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Acción principal dentro de una barra ("Listo"): texto en acento sobre un velo del acento.
struct ToolbarPrimaryButtonStyle: ButtonStyle {
    init() {}

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.22 : 0.13),
                        in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
            .padding(.horizontal, 2)
    }
}

/// Botón circular suelto (pasar hoja cuando el dedo dibuja).
struct FloatingCircleButtonStyle: ButtonStyle {
    init() {}

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(Theme.ink)
            .frame(width: 50, height: 50)
            .floatingSurface(Circle())
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Pulsación de una portada u objeto "físico": se hunde un poco.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat

    init(scale: CGFloat = 0.97) {
        self.scale = scale
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

// MARK: - Muestra de color

/// Círculo de color seleccionable (tapas, color del texto).
struct ColorSwatch: View {
    let color: Color
    let isSelected: Bool
    var diameter: CGFloat

    init(color: Color, isSelected: Bool, diameter: CGFloat = 28) {
        self.color = color
        self.isSelected = isSelected
        self.diameter = diameter
    }

    var body: some View {
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5))
            .frame(width: diameter, height: diameter)
            .padding(3)
            .overlay(
                Circle().strokeBorder(Theme.accent, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            )
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Estado vacío

/// Estado vacío sobrio: icono fino, título serif y una línea de ayuda.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String?

    init(_ title: String, systemImage: String, message: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.inkSecondary.opacity(0.8))
                .padding(.bottom, 4)
            Text(title)
                .font(Theme.Fonts.title)
                .foregroundStyle(Theme.ink)
            if let message {
                Text(message)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Controles flotantes") {
    ZStack {
        SpreadBackdrop(color: .green)
        VStack(spacing: 30) {
            HStack {
                FloatingBar {
                    Button {} label: { Image(systemName: "chevron.left") }
                    Text("Diario de viaje").font(Theme.Fonts.headline).padding(.trailing, 12)
                }
                Spacer()
                FloatingBar {
                    Button {} label: { Image(systemName: "magnifyingglass") }
                    Button {} label: { Image(systemName: "square.grid.2x2") }
                    Button {} label: { Image(systemName: "bookmark.fill") }
                        .buttonStyle(ToolbarIconButtonStyle(isActive: true))
                    FloatingBarDivider()
                    Button {} label: { Image(systemName: "ellipsis") }
                }
            }
            .buttonStyle(ToolbarIconButtonStyle())
            FloatingBar {
                Button {} label: { Label("Imagen", systemImage: "photo") }
                Button {} label: { Label("Texto", systemImage: "textformat") }
                FloatingBarDivider()
                Button("Listo") {}.buttonStyle(ToolbarPrimaryButtonStyle())
            }
            .buttonStyle(ToolbarLabelButtonStyle())
            Button {} label: { Image(systemName: "chevron.right") }
                .buttonStyle(FloatingCircleButtonStyle())
        }
        .padding(30)
    }
    .frame(width: 700, height: 400)
}

#Preview("Estado vacío") {
    EmptyStateView("Sin marcapáginas", systemImage: "bookmark",
                   message: "Marca una hoja con el icono del marcapáginas.")
        .background(Theme.desk)
}
