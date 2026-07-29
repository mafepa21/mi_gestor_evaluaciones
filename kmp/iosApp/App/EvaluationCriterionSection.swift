import SwiftUI
import MiGestorKit

/// Sección que muestra el o los criterios de evaluación que se evalúan con un instrumento,
/// colocada justo encima de su contenido (rejilla, rúbrica...). Cada criterio se pinta como una
/// etiqueta con su código curricular ("2.1") delante del enunciado; si hay más de uno, todos se
/// listan, separados por un divisor. El texto viene resuelto por `EvaluationCriteriaReference`
/// (Kotlin, `kmp/shared/.../util/`), que busca el enunciado oficial LOMLOE por el título del
/// instrumento. Si el instrumento no está en ese catálogo (otra materia/curso), `statements` llega
/// vacío y se enseña `fallbackText` (lo que haya en `Evaluation.description`) sin etiqueta de
/// código, porque en ese caso no se conoce con certeza. Compartida entre el instrumento de Rejilla
/// de observación (`NotebookStructuredInstrumentSupport.swift`) y el de Rúbrica
/// (`RubricEvaluationView.swift`).
struct EvaluationCriterionSection: View {
    let statements: [CriterionStatement]
    let fallbackText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundStyle(NotebookStyle.primaryTint)
                Text(statements.count > 1 ? "Criterios de evaluación" : "Criterio de evaluación")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
            }

            if statements.isEmpty {
                if let fallbackText, !fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(fallbackText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(statements.enumerated()), id: \.offset) { index, item in
                        if index > 0 {
                            Divider().opacity(0.5)
                        }
                        criterionRow(item)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(NotebookStyle.surfaceMuted, in: RoundedRectangle(cornerRadius: NotebookStyle.innerRadius, style: .continuous))
    }

    private func criterionRow(_ item: CriterionStatement) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(item.code)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(NotebookStyle.primaryTint, in: Capsule())
                .fixedSize()
            Text(item.statement)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
