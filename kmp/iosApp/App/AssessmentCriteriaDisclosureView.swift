import SwiftUI

struct AssessmentCriteriaDisclosureView: View {
    let rawText: String?
    @State private var isExpanded: Bool = false

    private var criteria: [LomloeCriterionDefinition] {
        LomloeCriteriaCatalog.resolveCriteria(from: rawText)
    }

    var body: some View {
        guard !criteria.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                // Cabecera interactiva con Badges de los Criterios
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "text.book.closed.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.accentColor)

                        Text("Criterios LOMLOE:")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(criteria) { criterion in
                                    Text(criterion.code)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.accentColor.opacity(0.12))
                                        .foregroundStyle(Color.accentColor)
                                        .clipShape(Capsule())
                                }
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

                                if let valencian = criterion.valencianDescription {
                                    Text(valencian)
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundStyle(.secondary.opacity(0.8))
                                        .italic()
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.top, 2)
                                }
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
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        )
    }
}
