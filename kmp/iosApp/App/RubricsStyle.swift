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

    /// Paso (0-3) de un nivel según su ratio de puntos frente al máximo del
    /// criterio: 0 = el más bajo (rojo) … 3 = el más alto (verde). Escala
    /// ordenada de 4 pasos rojo · naranja · menta · verde, **sin azul**, para
    /// que el orden se lea de un vistazo y no se confunda con el acento de la
    /// app. Deliberadamente no es `gradeColor` (3 bandas, pensada para la nota
    /// global 0-10): esta escala tiñe varios niveles del mismo criterio a la
    /// vez. Compartida entre la evaluación individual y la masiva.
    static func levelStep(points: Double, maxPoints: Double) -> Int {
        guard maxPoints > 0 else { return 0 } // sin escala: paso neutro, no verde
        let ratio = points / maxPoints
        switch ratio {
        case 0.8...: return 3
        case 0.6..<0.8: return 2
        case 0.4..<0.6: return 1
        default: return 0
        }
    }

    /// Color de relleno/borde de un paso de la escala (0-3).
    static func stepColor(_ step: Int) -> Color {
        switch step {
        case 3: return EvaluationDesign.success
        case 2: return .mint
        case 1: return .orange
        default: return EvaluationDesign.danger
        }
    }

    /// Color de un nivel según su ratio de puntos (ver `levelStep`).
    static func levelColor(points: Double, maxPoints: Double) -> Color {
        guard maxPoints > 0 else { return .secondary }
        return stepColor(levelStep(points: points, maxPoints: maxPoints))
    }

    /// Color para usar como **texto** sobre fondo claro/tintado. Los tonos de
    /// relleno (menta, naranja, verde) no llegan a contraste 4,5:1 sobre
    /// blanco; en claro se usan variantes oscuras, en oscuro el color base.
    static func stepTextColor(_ step: Int, scheme: ColorScheme) -> Color {
        guard scheme == .light else { return stepColor(step) }
        switch step {
        case 3: return Color(red: 0.05, green: 0.42, blue: 0.20)
        case 2: return Color(red: 0.00, green: 0.42, blue: 0.36)
        case 1: return Color(red: 0.62, green: 0.27, blue: 0.00)
        default: return Color(red: 0.70, green: 0.08, blue: 0.10)
        }
    }

    static func levelTextColor(points: Double, maxPoints: Double, scheme: ColorScheme) -> Color {
        guard maxPoints > 0 else { return .secondary }
        return stepTextColor(levelStep(points: points, maxPoints: maxPoints), scheme: scheme)
    }

    /// Paso de la escala para una nota 0-10 cualitativa (misma paleta que los
    /// niveles): ≥9 verde · ≥6 menta · ≥5 naranja · resto rojo.
    static func scoreStep(forScoreOutOfTen score: Double) -> Int {
        if score >= 9 { return 3 }
        if score >= 6 { return 2 }
        if score >= 5 { return 1 }
        return 0
    }

    /// Texto de puntos con plural correcto ("1 punto", "2 puntos", "1,5 puntos").
    static func pointsText(_ points: Double) -> String {
        let isWhole = points.truncatingRemainder(dividingBy: 1) == 0
        let number = isWhole ? "\(Int(points))" : IosFormatting.scoreOutOfTen(from: points)
        return points == 1 ? "\(number) punto" : "\(number) puntos"
    }

    /// Quita el prefijo numérico de orden ("1 — ", "2 - ") que algunas
    /// rúbricas importadas traen dentro del nombre del nivel: la tarjeta ya
    /// muestra su propia posición.
    static func cleanLevelTitle(_ title: String) -> String {
        let cleaned = title.replacingOccurrences(
            of: #"^\s*\d+\s*[—–-]\s*"#,
            with: "",
            options: .regularExpression
        )
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? title : trimmed
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
    @Environment(\.colorScheme) private var colorScheme
    private var step: Int { RubricsStyle.scoreStep(forScoreOutOfTen: scoreOutOfTen) }
    private var color: Color { RubricsStyle.stepColor(step) }
    private var textColor: Color { RubricsStyle.stepTextColor(step, scheme: colorScheme) }

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
                .foregroundStyle(hasStarted ? textColor : .secondary)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .contentTransition(.numericText(value: scoreOutOfTen))
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeInOut(duration: 0.25), value: progress)
        .animation(.easeInOut(duration: 0.25), value: scoreOutOfTen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nota actual")
        .accessibilityValue(hasStarted ? IosFormatting.scoreOutOfTen(from: scoreOutOfTen) : "Sin empezar")
    }
}

/// Tarjeta de nivel de rúbrica en la evaluación individual. Se coloca en una
/// rejilla adaptativa (`RubricCriterionRow`): todas las tarjetas de una fila
/// miden lo mismo de alto y el título se ve entero. En reposo es neutra; el
/// color (borde 2pt + tinte suave) solo aparece en la elegida. Lleva un número
/// de posición (1…n, el mismo que la tecla rápida) para no depender solo del
/// color. Sin sombra ni `scaleEffect`: el `ScrollView` que la contiene los
/// recortaría.
struct RubricLevelPill: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let points: Double
    let maxPoints: Double
    let isSelected: Bool
    let onSelect: () -> Void
    let description: String?
    /// Posición 1-based del nivel dentro del criterio (símbolo + tecla).
    var position: Int = 1

    private var color: Color { RubricsStyle.levelColor(points: points, maxPoints: maxPoints) }
    private var textColor: Color {
        RubricsStyle.levelTextColor(points: points, maxPoints: maxPoints, scheme: colorScheme)
    }
    private var displayTitle: String { RubricsStyle.cleanLevelTitle(title) }
    private var trimmedDescription: String {
        description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: RubricsStyle.rowRadius, style: .continuous)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text("\(position)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? contrastingTextColor(for: color) : textColor)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(isSelected ? color : color.opacity(0.16)))
                        .accessibilityHidden(true)

                    Spacer(minLength: 0)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? textColor : Color.secondary.opacity(0.6))
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                }

                Text(displayTitle)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(RubricsStyle.pointsText(points))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                if !trimmedDescription.isEmpty {
                    Text(trimmedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minHeight: 44)
            .background(shape.fill(isSelected ? color.opacity(0.14) : Color.primary.opacity(0.04)))
            .overlay {
                shape.stroke(
                    isSelected ? color : RubricsStyle.hairline,
                    lineWidth: isSelected ? 2 : 1
                )
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(displayTitle), \(RubricsStyle.pointsText(points))")
        .accessibilityHint(trimmedDescription.isEmpty ? "Pulsa para seleccionar este nivel" : trimmedDescription)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
