import SwiftUI

/// Tokens visuales del módulo Rúbricas al completo (banco/listado, builder,
/// evaluación individual y masiva, vinculación a pestaña) — ver
/// `docs/planes/plan_rediseno_rubricas_2026-07-20.md`. Nace como
/// `RubricEvaluationStyle`, overrides locales solo para las vistas de rúbrica
/// abiertas desde el Cuaderno (`RubricEvaluationView`, `RubricBulkEvaluationSheet`);
/// este PR lo amplía para cubrir el resto del módulo, que hasta ahora no
/// compartía ningún token.
///
/// `EvaluationDesign.swift` sigue bloqueado por las auditorías de UI/layout en
/// curso (`docs/planes/plan_auditoria_ui_2026-07-15.md`,
/// `docs/planes/plan_auditoria_layout_2026-07-15.md`, ramas `fix/auditoria-*`
/// activas): no se edita hasta que esas ramas aterricen. Estos tokens viven
/// aquí mientras tanto; cuando dejen de estar bloqueados, migrar
/// `cardRadius`/`rowRadius` a `EvaluationDesign` en vez de mantener un archivo
/// aparte.
enum RubricsStyle {
    /// `EvaluationDesign.cardRadius` (`heroCardRadius` = 40) es un radio de
    /// portada, excesivo para tarjetas de trabajo densas como los criterios o
    /// el resumen de una rúbrica. Un contenedor raíz de `fullScreenCover` puede
    /// permitirse 20+; el contenido de trabajo, no.
    static let cardRadius: CGFloat = 16

    /// Radio de un elemento anidado **dentro** de una tarjeta `cardRadius`:
    /// nivel de rúbrica (`RubricLevelTile`) y tarjetas de fila anidadas
    /// (`RubricEvaluationView.swift:256`). Es una excepción consciente frente a
    /// `NotebookGridStyle.Radius.card` (12), no un valor huérfano: la familia
    /// de radios de Rúbricas vive un escalón por encima de la del grid
    /// (16/14 frente a 12/6) porque sus tarjetas de trabajo son más espaciosas
    /// que las celdas densas del grid. No se consolida a 12 aquí para no
    /// introducir un cambio visual en un PR de fundación (sin adopción nueva
    /// todavía); si se revisa en el futuro, hacerlo como su propio PR visual.
    static let rowRadius: CGFloat = 14

    /// Radio de las blueprint cards del builder (criterios × niveles, PR 3):
    /// mismo valor que la tarjeta contenedora del grid del Cuaderno — Rúbricas
    /// y Cuaderno son la misma familia de superficies de datos.
    static let blueprintCardRadius = NotebookGridStyle.Radius.card

    /// Radio de los campos de formulario dentro del grid del builder (nombre
    /// de nivel, descripción de criterio, descripción de nivel). Mismo valor
    /// que `NotebookGridStyle.Radius.chip` (8) — hasta ahora sin ningún
    /// consumidor real; el builder es el primero en usarlo, con nombre propio
    /// porque un campo de texto no es un chip.
    static let fieldRadius = NotebookGridStyle.Radius.chip

    /// Borde en reposo de un campo de formulario del builder. Mismo literal
    /// (`Color.primary.opacity(0.08)`) que ya usaban, sin nombre, los 4 campos
    /// de `RubricBuilderGridView` — ahora con un solo sitio del que depender.
    static let fieldBorder = Color.primary.opacity(0.08)

    /// Hover de superficies de rúbrica en macOS. Mismo valor que
    /// `NotebookGridStyle.rowHover` (0.04); token propio para que las vistas de
    /// rúbrica no tengan que nombrar "Notebook". Sustituye al literal
    /// `Color.primary.opacity(0.04)` que `RubricLevelTile` tenía inline.
    static let hover = Color.primary.opacity(0.04)

    /// Hairlines del banco/listado de rúbricas (PR 2): mismos valores que
    /// `NotebookGridStyle`, referenciados en vez de duplicados.
    static let hairline = NotebookGridStyle.gridLine
    static let hairlineStrong = NotebookGridStyle.gridLineStrong

    /// Fill de una fila seleccionada en el banco/listado. Mismo valor que
    /// `NotebookGridStyle.cellSelectionFill` (0.08) — el banco Mac usaba un
    /// 0.10 suelto sin relación con el resto del idioma de selección.
    static let selectionFill = NotebookGridStyle.cellSelectionFill

    /// Tintes de las estadísticas compactas del banco iOS/iPad
    /// (`RubricsWorkspaceView`, fila "Rúbricas/Vinculadas/Criterios/
    /// Situaciones"). No son color semántico de nota (no hay una puntuación
    /// 0-10 detrás de "cuántas rúbricas hay"): son 4 tintes de categoría que
    /// antes venían de tres fuentes sin relación (`EvaluationDesign`,
    /// `IOSAppStyle`, un `.purple` suelto). Mismos colores de siempre —
    /// reexportados aquí para que este archivo sea la única fuente que la
    /// vista tenga que nombrar.
    static let statAccent = EvaluationDesign.accent
    static let statSuccess = EvaluationDesign.success
    static let statWarning = IOSAppStyle.warning
    static let statQuaternary = Color.purple

    /// Color semántico de una puntuación 0-10. Reexporta `NotebookGradeBand`
    /// (mismo corte `<5` suspenso / `5-6,9` aprobado / `≥7` notable+ que ya usa
    /// el grid del Cuaderno) para que el badge de la evaluación individual, el
    /// tinte de nivel de la evaluación masiva y cualquier indicador del banco
    /// de rúbricas compartan una única fuente de verdad en vez de las tres
    /// escalas de color independientes que había antes de este PR.
    static func gradeColor(forScoreOutOfTen score: Double) -> Color {
        NotebookGradeBand(scoreOutOfTen: score).color
    }

    /// Tinte de fondo suave (modo heat) para la misma banda de nota.
    static func gradeSoftFill(forScoreOutOfTen score: Double) -> Color {
        NotebookGradeBand(scoreOutOfTen: score).softFill
    }

    /// Color de un nivel según su ratio de puntos frente al máximo del
    /// criterio (4 bandas: ≥0,8 éxito · 0,6-0,8 acento · 0,4-0,6 naranja ·
    /// resto peligro). Deliberadamente **no** es `gradeColor` (3 bandas,
    /// pensada para "nota global 0-10"): esta función tiñe varios niveles del
    /// mismo criterio a la vez para que se distingan entre sí de un vistazo —
    /// un propósito distinto (orden relativo entre opciones) al de una nota
    /// final. Colapsar sus 4 bandas a las 3 de `gradeColor` fusionaría
    /// niveles adyacentes en el mismo color con más frecuencia, perdiendo
    /// justo la distinción que existe para dar. Compartida entre la
    /// evaluación masiva (`RubricBulkEvaluationSheet`) y la individual.
    static func levelColor(points: Double, maxPoints: Double) -> Color {
        guard maxPoints > 0 else { return EvaluationDesign.accent }
        let ratio = points / maxPoints

        switch ratio {
        case 0.8...:
            return EvaluationDesign.success
        case 0.6..<0.8:
            return EvaluationDesign.accent
        case 0.4..<0.6:
            return .orange
        default:
            return EvaluationDesign.danger
        }
    }
}

/// Fondo de las vistas de rúbrica: sustituye a `EvaluationBackdrop`
/// (gradiente + círculo radial decorativo) por una superficie plana con, como
/// mucho, un tinte del 3% arriba. Puntuar una rúbrica es una tarea de
/// concentración; el fondo no debe competir con los criterios.
struct RubricEvaluationBackdrop: View {
    var body: some View {
        ZStack(alignment: .top) {
            #if os(macOS)
            Color(nsColor: .windowBackgroundColor)
            #else
            Color(.systemGroupedBackground)
            #endif

            LinearGradient(
                colors: [EvaluationDesign.accent.opacity(0.03), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 220)
        }
        .ignoresSafeArea()
    }
}

/// Anillo de progreso compacto para la cabecera de la evaluación individual:
/// el arco es la fracción de criterios ya resueltos (`progress`, 0-1); el
/// número central es la nota actual, coloreada por banda. Sustituye a
/// `RubricScoreBadge` — un solo elemento hace el trabajo que antes eran el
/// badge de cabecera *y* el bloque "Progreso" del panel resumen (PR 2 de
/// `docs/planes/plan_rediseno_evaluacion_rubricas_2026-07-20.md`).
///
/// Dibujado a mano (`Circle().trim`) en vez de `Gauge(.accessoryCircularCapacity)`
/// (nativo desde iOS 16/macOS 13, pensado para esto): ese estilo está
/// diseñado para complicaciones/widgets y su aspecto fuera de ese contexto no
/// se puede verificar sin Xcode real en este entorno. El trazo a mano da
/// control total y es el mismo que se validó en el mockup aprobado por el
/// usuario.
///
/// Antes de que haya al menos un criterio resuelto (`progress == 0`), la nota
/// real sería 0.0 y caería en la banda "suspenso" de `gradeColor` — mostrar
/// un cero en rojo en una rúbrica que sencillamente no se ha empezado a
/// puntuar sería engañoso. En ese caso se muestra un guion neutro en vez de
/// la nota.
struct RubricScoreRing: View {
    let progress: Double
    let scoreOutOfTen: Double
    var diameter: CGFloat = 56

    private var hasStarted: Bool { progress > 0 }
    private var color: Color { RubricsStyle.gradeColor(forScoreOutOfTen: scoreOutOfTen) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(RubricsStyle.hairlineStrong, lineWidth: 3)

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text(hasStarted ? IosFormatting.scoreOutOfTen(from: scoreOutOfTen) : "–")
                .font(.system(.footnote, design: .rounded).weight(.bold))
                .foregroundStyle(hasStarted ? color : .secondary)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeInOut(duration: 0.25), value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nota actual")
        .accessibilityValue(hasStarted ? IosFormatting.scoreOutOfTen(from: scoreOutOfTen) : "Sin empezar")
    }
}

/// Píldora compacta de nivel de rúbrica en la evaluación individual.
/// Sustituye a `RubricLevelTile` (PR 3 de
/// `docs/planes/plan_rediseno_evaluacion_rubricas_2026-07-20.md`): solo
/// nombre + puntos en una línea, sin subtítulo de descripción permanente —
/// la descripción se pide aparte (botón "i"), nunca se muestra sin pedirla.
/// Seleccionada = fill con el color **del propio nivel**
/// (`RubricsStyle.levelColor`, por ratio de puntos) en vez de un acento fijo
/// para todos los niveles como hacía `RubricLevelTile`; el color ya es la
/// señal de selección, sin checkmark adicional.
struct RubricLevelPill: View {
    let title: String
    let points: Double
    let maxPoints: Double
    let isSelected: Bool
    let onSelect: () -> Void
    let onShowDescription: () -> Void

    @State private var isHovered = false

    private var color: Color { RubricsStyle.levelColor(points: points, maxPoints: maxPoints) }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text("\(Int(points))")
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .opacity(0.7)
                }
                .foregroundStyle(isSelected ? contrastingTextColor(for: color) : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? color : (isHovered ? RubricsStyle.hover : Color.clear))
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : RubricsStyle.hairlineStrong, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button(action: onShowDescription) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(isSelected ? contrastingTextColor(for: color).opacity(0.7) : .tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Descripción de \(title)")
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
