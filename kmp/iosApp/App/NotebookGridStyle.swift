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

    /// Tipografía de toda celda numérica y de la columna Media. Diseño
    /// redondeado + semibold ("números con carácter" del rediseño radical): la
    /// nota es la protagonista de la celda, no un dato menudo alineado a la
    /// derecha. `.system(_:design:)` conserva el escalado de Dynamic Type.
    #if os(macOS)
    static let cellFont: Font = .system(.callout, design: .rounded).weight(.semibold).monospacedDigit()
    #else
    static let cellFont: Font = .system(.body, design: .rounded).weight(.semibold).monospacedDigit()
    #endif

    // MARK: - Estados de foco (única fuente de verdad para celda/columna/fila)

    /// Hover de fila en macOS. Sin animación: coincide con el comportamiento
    /// nativo de `NSTableView`, que no anima su hover.
    static let rowHover = Color.primary.opacity(0.04)

    /// Wash de columna resaltada (menú de columna abierto, foco de inspector).
    /// **Neutro, no de acento**: el azul inundando toda la columna sobre un fondo
    /// claro leía como un bloque plano poco premium. La identidad de acento vive
    /// en la barra bajo la cabecera (ver `headerChip`), no en un flood de color.
    static let columnActiveWash = Color.primary.opacity(0.04)

    /// Anillo de una celda seleccionada o en edición.
    static let cellSelectionRing = Color.accentColor
    static let cellSelectionRingWidth: CGFloat = 2

    /// Fill plano de acento para selección de **tarjetas** (blueprint cards,
    /// niveles de rúbrica), donde no hay wash de columna que tapar. En las celdas
    /// del grid se usa `cellSelectionSurface` en su lugar (elevación, no tinte).
    static let cellSelectionFill = Color.accentColor.opacity(0.08)

    /// Relleno de la celda seleccionada: superficie **opaca** que tapa cualquier
    /// wash de columna por debajo, para que la celda se eleve limpia (como una
    /// tecla pulsada) en vez de teñirse de azul. La elevación real la dan el
    /// anillo + la sombra `cellSelectionShadow`.
    static var cellSelectionSurface: Color { appSecondarySystemBackgroundColor() }
    static let cellSelectionShadow = Color.accentColor.opacity(0.22)

    // MARK: - Superficie del grid

    /// Sombra suave del grid como tarjeta elevada sobre el lienzo del módulo.
    static let gridSurfaceShadow = Color.black.opacity(0.06)

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

    // MARK: - Color semántico de nota (rediseño radical del grid)

    /// <5 suspenso · 5–6,9 aprobado · ≥7 notable+. Mismo corte de "aprobado" que
    /// ya usa el resto de la app (ver `averageState`); no es un umbral nuevo.
    static let gradeLow = appAdaptiveBrandColor(light: (0.86, 0.20, 0.18), dark: (1.0, 0.38, 0.36))
    static let gradeMid = appAdaptiveBrandColor(light: (0.79, 0.53, 0.0), dark: (0.94, 0.67, 0.19))
    static let gradeHigh = appAdaptiveBrandColor(light: (0.12, 0.60, 0.32), dark: (0.28, 0.80, 0.50))

    /// Clave de `@AppStorage` compartida por varias vistas (`NotebookModuleView`,
    /// `NotebookStatefulEditableTableCell`): color semántico de nota + heat de
    /// celda, con un único ajuste on/off desde el menú de acciones del cuaderno.
    /// Cada vista declara su propio `@AppStorage` con esta misma clave en vez de
    /// enhebrar un booleano por los inits — patrón estándar de SwiftUI para un
    /// ajuste que cruza muchos tipos de celda sin acoplarlos entre sí.
    static let semanticGradeColorDefaultsKey = "notebook.semanticGradeColorEnabled"

    // MARK: - Identidad de alumno (rediseño radical del grid)

    private static let studentAccentPalette: [Color] = [
        appAdaptiveBrandColor(light: (0.11, 0.42, 0.90), dark: (0.36, 0.62, 1.0)),
        appAdaptiveBrandColor(light: (0.62, 0.24, 0.85), dark: (0.75, 0.48, 0.98)),
        appAdaptiveBrandColor(light: (0.86, 0.30, 0.55), dark: (0.98, 0.52, 0.70)),
        appAdaptiveBrandColor(light: (0.80, 0.42, 0.0), dark: (0.98, 0.62, 0.28)),
        appAdaptiveBrandColor(light: (0.0, 0.55, 0.55), dark: (0.30, 0.78, 0.78)),
        appAdaptiveBrandColor(light: (0.35, 0.55, 0.10), dark: (0.55, 0.78, 0.30)),
    ]

    /// Color determinista por alumno (mismo id → mismo color siempre), para que
    /// el monograma de la columna Nombre distinga alumnos de un vistazo, como
    /// Contactos — no es un color aleatorio en cada render.
    static func studentAccent(for studentId: Int64) -> Color {
        let index = Int(abs(studentId) % Int64(studentAccentPalette.count))
        return studentAccentPalette[index]
    }
}

/// Banda de una nota 0–10 para el color semántico y el modo heat del grid.
enum NotebookGradeBand {
    case low, mid, high

    init(scoreOutOfTen score: Double) {
        if score < 5 {
            self = .low
        } else if score < 7 {
            self = .mid
        } else {
            self = .high
        }
    }

    var color: Color {
        switch self {
        case .low: return NotebookGridStyle.gradeLow
        case .mid: return NotebookGridStyle.gradeMid
        case .high: return NotebookGridStyle.gradeHigh
        }
    }

    /// Tinte de fondo suave para el modo heat (mismo toggle que el color del
    /// número, nunca un fill fuerte: color con contención, no un bloque relleno).
    var softFill: Color { color.opacity(0.12) }
}

/// Lienzo del Cuaderno: fondo neutro y calmado sobre el que el grid (superficie
/// más clara) se lee como una tarjeta elevada. Sustituye a `EvaluationBackdrop`
/// (gradiente + halos de acento), que hacía que las celdas parecieran flotar
/// sobre un fondo "webby" en vez de sobre una superficie de datos sólida.
struct NotebookCanvasBackground: View {
    var body: some View {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemGroupedBackground)
        #endif
    }
}
