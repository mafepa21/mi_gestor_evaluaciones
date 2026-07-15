import SwiftUI

/// Overrides visuales locales para las vistas de rúbrica que se abren desde el
/// Cuaderno (`RubricEvaluationView`, `RubricBulkEvaluationSheet`).
///
/// `EvaluationDesign.swift` está bloqueado por las auditorías de UI/layout en
/// curso (`docs/planes/plan_auditoria_ui_2026-07-15.md`,
/// `docs/planes/plan_auditoria_layout_2026-07-15.md`): no se edita hasta que
/// esas ramas aterricen. Estos tokens viven aquí mientras tanto; cuando dejen
/// de estar bloqueados, migrar `cardRadius`/`rowRadius` a `EvaluationDesign` en
/// vez de mantener un archivo aparte.
enum RubricEvaluationStyle {
    /// `EvaluationDesign.cardRadius` (`heroCardRadius` = 40) es un radio de
    /// portada, excesivo para tarjetas de trabajo densas como los criterios o
    /// el resumen de una rúbrica. Un contenedor raíz de `fullScreenCover` puede
    /// permitirse 20+; el contenido de trabajo, no.
    static let cardRadius: CGFloat = 16
    static let rowRadius: CGFloat = 14
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
                RoundedRectangle(cornerRadius: RubricEvaluationStyle.rowRadius, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.08) : (isHovered ? Color.primary.opacity(0.04) : EvaluationDesign.surface))
                    .overlay(
                        RoundedRectangle(cornerRadius: RubricEvaluationStyle.rowRadius, style: .continuous)
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
