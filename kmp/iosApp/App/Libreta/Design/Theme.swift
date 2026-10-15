import SwiftUI
import UIKit

/// Paleta, medidas y tipografía de la app.
///
/// Todo es cálido y sobrio: una mesa de lino claro, papel crema, tinta azul grisácea
/// para las líneas y un único acento terracota. El papel sigue siendo claro en modo
/// oscuro (con un leve tono crema más apagado) porque es un objeto físico.
enum Theme {

    // MARK: - Utilidades de color

    static func uiColor(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// Color fijo (igual en claro y oscuro).
    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> Color {
        Color(uiColor: uiColor(hex, alpha: alpha))
    }

    /// Color que cambia según el modo claro/oscuro.
    static func adaptive(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        let l = uiColor(light, alpha: lightAlpha)
        let d = uiColor(dark, alpha: darkAlpha)
        return Color(uiColor: UIColor(dynamicProvider: { traits in
            traits.userInterfaceStyle == .dark ? d : l
        }))
    }

    // MARK: - Mesa / biblioteca

    /// Fondo de la biblioteca: lino claro cálido (oscuro: nogal muy apagado).
    static let desk = adaptive(light: 0xEDE6DA, dark: 0x1D1A17)
    /// Brillo suave de luz cenital sobre la mesa.
    static let deskGlow = adaptive(light: 0xFFFFFF, dark: 0xFFF3E0, lightAlpha: 0.45, darkAlpha: 0.05)
    /// Relleno del hueco "Nuevo cuaderno".
    static let newSlotFill = adaptive(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.28, darkAlpha: 0.04)

    // MARK: - Estantería y montones

    /// Frente de la balda: nogal claro y cálido (oscuro: nogal apagado).
    static let shelfWood = adaptive(light: 0xB88A5F, dark: 0x5E4535)
    /// Cara superior de la balda, donde apoyan los lomos (le da la luz).
    static let shelfWoodTop = adaptive(light: 0xD4AD84, dark: 0x735643)
    /// Canto inferior y fondo de la balda, en sombra.
    static let shelfWoodEdge = adaptive(light: 0x8C6240, dark: 0x3D2C21)
    /// Vetas de la madera.
    static let shelfGrain = adaptive(light: 0x5A3A1E, dark: 0x1A120C, lightAlpha: 0.16, darkAlpha: 0.32)
    /// Velo sobre la mesa cuando un montón está desplegado.
    static let scrim = adaptive(light: 0x2B2622, dark: 0x000000, lightAlpha: 0.16, darkAlpha: 0.45)

    // MARK: - Papel

    static let paper = adaptive(light: 0xFBF8F1, dark: 0xE9E3D5)
    /// Canto de las hojas apiladas.
    static let paperEdge = adaptive(light: 0xECE5D6, dark: 0xC9C1AF)
    /// Filo fino que separa hojas apiladas.
    static let paperEdgeLine = adaptive(light: 0xD5CCB9, dark: 0x9C927F)
    /// Líneas del rayado.
    static let ruleInk = color(0x8FA8C2)
    /// Líneas de la cuadrícula.
    static let gridInk = color(0x9BB1C6)
    /// Puntos de la hoja punteada.
    static let dotInk = color(0x8C98A5)
    /// Margen rojo suave del rayado.
    static let marginInk = color(0xD98080)
    /// Acento terracota impreso en las plantillas (fijo: el papel siempre es claro).
    static let paperAccent = color(0xA4532F)
    /// Texto impreso sobre papel (siempre oscuro, el papel siempre es claro).
    static let paperInk = color(0x2B2622)
    static let paperInkSecondary = color(0x8A7F72)

    // MARK: - Texto de interfaz y acento

    static let ink = adaptive(light: 0x2B2622, dark: 0xEFE8DC)
    static let inkSecondary = adaptive(light: 0x7B7064, dark: 0xA89E91)
    /// Único acento: terracota (botones principales, selección).
    static let accent = adaptive(light: 0xA4532F, dark: 0xD9875F)

    // MARK: - Lector

    /// Tapa interior del cuaderno abierto (cartón forrado, marrón tabaco).
    static let backdrop = adaptive(light: 0x5A4536, dark: 0x3A2E25)
    /// Fondo detrás del cuaderno abierto en el lector (la mesa, algo más oscura).
    static let readerBackground = adaptive(light: 0xE4DCCD, dark: 0x151311)

    // MARK: - Controles flotantes y detalles

    /// Velo cálido sobre el material de las barras flotantes (papel en claro, cartón en oscuro).
    static let barTint = adaptive(light: 0xFBF8F1, dark: 0x2A2521, lightAlpha: 0.62, darkAlpha: 0.55)
    /// Filo fino de las barras flotantes.
    static let barStroke = adaptive(light: 0x2B2622, dark: 0xFFFFFF, lightAlpha: 0.10, darkAlpha: 0.10)
    /// Separadores finos (listas, barras).
    static let hairline = adaptive(light: 0x2B2622, dark: 0xEFE8DC, lightAlpha: 0.12, darkAlpha: 0.14)
    /// Cinta de marcapáginas: raso granate.
    static let ribbon = color(0x8E2A2C)

    // MARK: - Sombras

    static let shadow = adaptive(light: 0x33230F, dark: 0x000000, lightAlpha: 0.24, darkAlpha: 0.6)

    // MARK: - Medidas

    /// Proporción ancho/alto de una hoja (≈ A5 algo ensanchado).
    static let pageAspect: CGFloat = 0.72
    /// Proporción ancho/alto de una portada.
    static let coverAspect: CGFloat = 0.72
    static let pageCornerRadius: CGFloat = 4
    static let coverCornerRadius: CGFloat = 7
    static let cardCornerRadius: CGFloat = 12
    static let backdropCornerRadius: CGFloat = 14
    /// Margen de tapa visible alrededor de las hojas en el lector.
    static let backdropInset: CGFloat = 18
    /// Ancho recomendado de portada en la biblioteca (iPad, tamaño regular).
    static let coverWidth: CGFloat = 170
    /// Separación entre portadas en la biblioteca.
    static let shelfSpacing: CGFloat = 40

    // MARK: - Tipografía

    /// Serif (New York) para títulos y todo lo "impreso"; sistema para controles.
    enum Fonts {
        static let largeTitle = Font.system(.largeTitle, design: .serif, weight: .semibold)
        static let title = Font.system(.title2, design: .serif, weight: .semibold)
        static let headline = Font.system(.headline, design: .serif, weight: .semibold)
        static let body = Font.system(.body, design: .default, weight: .regular)
        static let caption = Font.system(.footnote, design: .serif, weight: .regular)
        static let pageNumber = Font.system(.caption, design: .serif, weight: .regular).monospacedDigit()

        static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .serif)
        }
    }
}
