import SwiftUI

/// Seccion que muestra el enunciado del o los criterios de evaluacion que se evaluan con un
/// instrumento, colocada justo encima de su contenido (rejilla, rubrica...). El texto viene
/// resuelto por `EvaluationCriteriaReference` (Kotlin, `kmp/shared/.../util/`), que busca el
/// enunciado oficial LOMLOE por el titulo del instrumento; si no lo encuentra, cae a lo que haya en
/// `Evaluation.description`. Compartida entre el instrumento de Rejilla de observacion
/// (`NotebookStructuredInstrumentSupport.swift`) y el de Rubrica (`RubricEvaluationView.swift`).
struct EvaluationCriterionSection: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundStyle(NotebookStyle.primaryTint)
                Text("Criterio de evaluación")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
            }
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(NotebookStyle.surfaceMuted, in: RoundedRectangle(cornerRadius: NotebookStyle.innerRadius, style: .continuous))
    }
}
