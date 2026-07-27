import SwiftUI

/// Componente SwiftUI nativo para mostrar los Criterios de Evaluación vinculados a un instrumento
/// (rúbrica, rejilla de observación, checklist), permitiendo ver el código (ej. "CE 2.1") y su
/// descripción literal oficial según la ley (LOMLOE).
struct AssessmentCriteriaDisclosureView: View {
    let criteria: [LomloeCriterionDefinition]
    let initialExpanded: Bool
    
    @State private var isExpanded: Bool

    init(criteria: [LomloeCriterionDefinition], initialExpanded: Bool = false) {
        self.criteria = criteria
        self.initialExpanded = initialExpanded
        _isExpanded = State(initialValue: initialExpanded)
    }

    init(rawText: String?, initialExpanded: Bool = false) {
        let resolved = LomloeCriteriaCatalog.resolveCriteria(from: rawText)
        self.init(criteria: resolved, initialExpanded: initialExpanded)
    }

    var body: some View {
        guard !criteria.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                // Cabecera interactiva con resumen y botón de desplegar
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "book.pages")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor)

                        Text("Criterios de evaluación")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        // Badges compactos por cada código
                        HStack(spacing: 4) {
                            ForEach(criteria) { criterion in
                                Text(criterion.code)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.12))
                                    .foregroundStyle(Color.accentColor)
                                    .clipShape(Capsule())
                            }
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "info.circle")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(isExpanded ? Color.accentColor : Color.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)

                // Detalle expandible con la descripción literal de la ley por cada criterio
                if isExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(criteria) { criterion in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(criterion.code)
                                        .font(.system(size: 12, weight: .black, design: .rounded))
                                        .foregroundStyle(Color.accentColor)
                                    
                                    Text(criterion.title)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.primary)
                                }

                                Text(criterion.officialDescription)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(2)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                                    )
                            )
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        )
    }
}
