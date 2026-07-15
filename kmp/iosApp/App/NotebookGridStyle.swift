import SwiftUI

/// Escala de tokens visuales del grid del Cuaderno: superficie de datos densa,
/// jerarquía de cabeceras de columna y estados de foco (hover de fila, columna
/// resaltada, celda seleccionada/en edición).
///
/// Reglas de la escala (ver `docs/planes/plan_rediseno_cuaderno_2026-07-15.md`):
/// - Cada valor de aquí es el resultado final que se pinta: nada de opacidades
///   apiladas sobre otro token (el patrón `NotebookStyle.softBorder.opacity(0.55)`
///   que hacía los bordes reales imposibles de razonar y casi invisibles en dark
///   mode queda sustituido por estos valores absolutos).
/// - Radios concéntricos: si un contenedor de radio `R` tiene padding `P`, el
///   elemento interior usa `R - P` (ver `NotebookGridStyle.Radius`).
/// - Un solo estado de foco por elemento: hover < columna resaltada < selección.
///   Solo la selección usa el color de acento.
enum NotebookGridStyle {
    // MARK: - Líneas y superficies del grid

    /// Hairline de separación entre filas, a ancho completo (sustituye a
    /// `NotebookStyle.softBorder.opacity(0.45)` recortado con padding horizontal).
    static let gridLine = Color.primary.opacity(0.07)

    /// Límite fuerte: borde de columna fija/Media, línea bajo la cabecera,
    /// límites de categoría en el folder lane.
    static let gridLineStrong = Color.primary.opacity(0.14)

    /// Franja de fila par (zebra), plana. Es la única técnica de separación
    /// de filas junto con `gridLine`; no se combina con bordes por celda.
    static let zebra = Color.primary.opacity(0.025)

    // MARK: - Tipografía de datos

    /// Título de cabecera de columna.
    static let columnTitle: Font = .footnote.weight(.semibold)

    /// Metadatos de cabecera (peso, fecha, tipo), en una sola línea.
    static let columnMeta: Font = .caption2

    /// Tipografía de toda celda numérica y de la columna Media.
    #if os(macOS)
    static let cellFont: Font = .callout.monospacedDigit()
    #else
    static let cellFont: Font = .body.monospacedDigit()
    #endif

    // MARK: - Estados de foco (única fuente de verdad para celda/columna/fila)

    /// Hover de fila en macOS. Sin animación: coincide con el comportamiento
    /// nativo de `NSTableView`, que no anima su hover.
    static let rowHover = Color.primary.opacity(0.04)

    /// Wash plano cuando una columna está resaltada (menú de columna abierto,
    /// selección con foco en el inspector). Cubre cabecera + celdas.
    static func columnHighlight(tint: Color = .accentColor) -> Color {
        tint.opacity(0.05)
    }

    /// Anillo de una celda seleccionada o en edición.
    static let cellSelectionRing = Color.accentColor
    static let cellSelectionRingWidth: CGFloat = 2
    /// Relleno plano bajo el anillo de selección.
    static let cellSelectionFill = Color.accentColor.opacity(0.08)

    // MARK: - Estados semánticos (puntos/anillos discretos, nunca fills grandes)

    static let statePending = IOSAppStyle.warning
    static let stateError = IOSAppStyle.danger

    // MARK: - Radios (regla concéntrica: interior = exterior − padding)

    enum Radius {
        /// Celda interactiva (anillo de selección/edición).
        static let cell: CGFloat = 6
        /// Chip (blueprint cards, folder lane).
        static let chip: CGFloat = 8
        /// Tarjeta contenedora.
        static let card: CGFloat = 12
    }
}
