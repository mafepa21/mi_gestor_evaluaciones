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

/// Tarjeta de nivel de una rúbrica. Sustituye a `EvaluationLevelTile`
/// (definida en `EvaluationDesign.swift`, bloqueado) solo en las vistas de
/// rúbrica del Cuaderno: en reposo es una superficie plana sin borde; al
/// seleccionar, un anillo de 2pt en el tinte del nivel + fill plano — mismo
/// idioma de selección que las celdas del grid y las blueprint cards de
/// "Nueva columna" — en vez de rellenar toda la tarjeta con el color y texto
/// blanco encima.
struct RubricLevelTile: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    var tint: Color = EvaluationDesign.accent
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    if isSelected {
                        selectionCheckmark
                    }
                }

                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: RubricsStyle.rowRadius, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.08) : (isHovered ? RubricsStyle.hover : EvaluationDesign.surface))
                    .overlay(
                        RoundedRectangle(cornerRadius: RubricsStyle.rowRadius, style: .continuous)
                            .stroke(isSelected ? tint : Color.clear, lineWidth: isSelected ? 2 : 0)
                    )
            )
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { hovering in
            isHovered = hovering
        }
        #endif
    }

    @ViewBuilder
    private var selectionCheckmark: some View {
        if #available(iOS 18.0, macOS 14.0, *) {
            Image(systemName: "checkmark.circle.fill")
                .symbolEffect(.bounce, value: isSelected)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
        }
    }
}
