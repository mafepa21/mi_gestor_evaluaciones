import SwiftUI

// MARK: - Tokens del Dashboard
//
// Fuente de verdad: docs/mockups/dashboard/mockup/index.html ("Notas para
// implementación"). Este archivo concentra rejilla, radios, tipografías
// semánticas, superficie de tarjeta y cristal de controles para que el
// Dashboard (iPad ahora, Mac después) hable un solo idioma visual.
//
// Regla de oro: el cristal es cromo (selector, botones, menús, píldora de
// sync, avisos), nunca contenido. Las tarjetas son una superficie limpia,
// sin sombras de color.

enum DashboardStyle {

    /// Rejilla de 8 pt. El 4 solo se usa para microajustes tipográficos.
    enum Spacing {
        static let micro: CGFloat = 4
        static let s1: CGFloat = 8
        static let s2: CGFloat = 16
        static let s3: CGFloat = 24
        static let s4: CGFloat = 32
        static let s5: CGFloat = 40
        static let s6: CGFloat = 48
    }

    enum Radius {
        /// Controles (botones, menús, filas seleccionables).
        static let control: CGFloat = 14
        /// Botón grande de acción principal.
        static let largeControl: CGFloat = 18
        /// Tarjetas de contenido.
        static let card: CGFloat = 20
        /// Hojas: lo pone `.sheet` del sistema; se declara solo por documentación.
        static let sheet: CGFloat = 28
    }

    /// Zona táctil mínima.
    static let minTapSize: CGFloat = 44

    /// Tipografías semánticas (escalan con Dynamic Type). Los tamaños propios
    /// (número de minutos) usan `@ScaledMetric` en la vista.
    enum Typography {
        static let largeTitle = Font.largeTitle.bold()
        static let title = Font.title2.bold()
        static let headline = Font.headline
        static let subheadline = Font.subheadline
        static let footnote = Font.footnote
        static let footnoteStrong = Font.footnote.weight(.semibold)
        static let caption = Font.caption
    }

    /// Urgencia: siempre con icono, nunca solo color.
    enum Tint {
        static let risk = Color.red
        static let alert = Color.orange
        static let pending = Color.blue
        static let success = Color.green
    }

    static var accent: Color { EvaluationDesign.accent }

    static func cardShape() -> RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
    }

    static func controlShape() -> RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
    }

    /// Superficie plana de tarjeta (equivale a `secondarySystemGroupedBackground`).
    static var cardFill: Color {
#if os(iOS)
        Color(.secondarySystemGroupedBackground)
#else
        Color(nsColor: .controlBackgroundColor)
#endif
    }

    /// Superficie de segundo nivel dentro de una tarjeta (filas, fichas).
    static var insetFill: Color {
#if os(iOS)
        Color(.tertiarySystemGroupedBackground)
#else
        Color(nsColor: .windowBackgroundColor)
#endif
    }

    static var pageFill: Color {
#if os(iOS)
        Color(.systemGroupedBackground)
#else
        Color(nsColor: .windowBackgroundColor)
#endif
    }
}

// MARK: - Fondo de pantalla

/// Base agrupada con dos manchas de color muy suaves (el "wallpaper" de la
/// maqueta). En modo oscuro el negro manda; con reducir transparencia o mayor
/// contraste queda liso.
struct DashboardBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            DashboardStyle.pageFill
            if !(reduceTransparency || contrast == .increased) {
                RadialGradient(
                    colors: [DashboardStyle.accent.opacity(colorScheme == .dark ? 0.18 : 0.14), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 520
                )
                RadialGradient(
                    colors: [Color.orange.opacity(colorScheme == .dark ? 0.10 : 0.10), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 420
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Tarjeta de contenido (sin cristal, sin sombras de color)

struct DashboardCardSurface: ViewModifier {
    var padding: CGFloat = DashboardStyle.Spacing.s3
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DashboardStyle.cardFill, in: DashboardStyle.cardShape())
            .overlay {
                if contrast == .increased {
                    DashboardStyle.cardShape().strokeBorder(Color.primary.opacity(0.5), lineWidth: 1)
                }
            }
    }
}

extension View {
    /// Superficie limpia de tarjeta de contenido.
    func dashboardCard(padding: CGFloat = DashboardStyle.Spacing.s3) -> some View {
        modifier(DashboardCardSurface(padding: padding))
    }
}

// MARK: - Cristal solo para controles

/// Cristal líquido con las tres ramas que exige la maqueta: `.glassEffect`
/// en iOS/macOS 26, material fino antes, y fondo sólido con borde visible con
/// "Reducir transparencia" o contraste alto.
struct DashboardGlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    var interactive = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content
                .background(DashboardStyle.cardFill, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.6), lineWidth: 1))
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content.dashboardGlassEffect(in: shape, interactive: interactive)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
        }
    }
}

private extension View {
    @available(iOS 26.0, macOS 26.0, *)
    @ViewBuilder
    func dashboardGlassEffect<S: InsettableShape>(in shape: S, interactive: Bool) -> some View {
        if interactive {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.glassEffect(.regular, in: shape)
        }
    }
}

extension View {
    /// Fondo de cristal para un control (selector, píldora, aviso, menú).
    func dashboardGlass<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(DashboardGlassBackground(shape: shape, interactive: interactive))
    }

    /// Estilo de botón de cristal: `.glass`/`.glassProminent` en 26 y
    /// `.bordered`/`.borderedProminent` antes. El sistema ya adapta el cristal
    /// a "Reducir transparencia". Zona táctil mínima de 44 pt.
    @ViewBuilder
    func dashboardButtonStyle(prominent: Bool = false, large: Bool = false) -> some View {
        let radius = large ? DashboardStyle.Radius.largeControl : DashboardStyle.Radius.control
        if #available(iOS 26.0, macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
                    .buttonBorderShape(.roundedRectangle(radius: radius))
                    .controlSize(large ? .large : .regular)
                    .tint(DashboardStyle.accent)
                    .frame(minHeight: DashboardStyle.minTapSize)
            } else {
                self.buttonStyle(.glass)
                    .buttonBorderShape(.roundedRectangle(radius: radius))
                    .controlSize(large ? .large : .regular)
                    .frame(minHeight: DashboardStyle.minTapSize)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: radius))
                    .controlSize(large ? .large : .regular)
                    .tint(DashboardStyle.accent)
                    .frame(minHeight: DashboardStyle.minTapSize)
            } else {
                self.buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: radius))
                    .controlSize(large ? .large : .regular)
                    .frame(minHeight: DashboardStyle.minTapSize)
            }
        }
    }
}

/// Agrupa controles de cristal cercanos para que se mezclen bien (iOS/macOS 26).
struct DashboardGlassGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = DashboardStyle.Spacing.s2, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Movimiento

/// Aparición escalonada por bloque: opacidad + 8 pt, 450 ms y 70 ms de retraso
/// por posición. Con "Reducir movimiento" es un fundido simple, sin
/// desplazamiento ni retraso.
struct DashboardReveal: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: (visible || reduceMotion) ? 0 : 8)
            .onAppear {
                guard !visible else { return }
                if reduceMotion {
                    withAnimation(.linear(duration: 0.2)) { visible = true }
                } else {
                    withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.45).delay(Double(index) * 0.07)) {
                        visible = true
                    }
                }
            }
    }
}

extension View {
    func dashboardReveal(_ index: Int) -> some View {
        modifier(DashboardReveal(index: index))
    }

    /// Transición al cambiar de modo: fundido y escala 98,5 % → 100 %; con
    /// movimiento reducido, solo fundido.
    func dashboardModeTransition(reduceMotion: Bool) -> some View {
        transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))
    }
}

// MARK: - Esqueleto

/// Rectángulo de esqueleto de tamaño fijo (nunca flexible: una `LazyVGrid`
/// flexible en el esqueleto ya cerró la app una vez). Oculto a VoiceOver: el
/// contenedor lleva un único "Cargando".
struct DashboardSkeletonShape: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var radius: CGFloat = 6
    var capsule = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        RoundedRectangle(cornerRadius: capsule ? height / 2 : radius, style: .continuous)
            .fill(Color.primary.opacity(0.10))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .opacity(dimmed ? 0.45 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
            .accessibilityHidden(true)
    }
}
