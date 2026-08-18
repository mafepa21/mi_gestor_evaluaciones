import SwiftUI
import MiGestorKit

/// Read-only audit surface for persisted physical-test scales.
/// It keeps the imported manifest visible without duplicating the editor flow.
struct PhysicalScaleCatalogView: View {
    let scales: [MiGestorKit.PhysicalTestScale]
    let testNames: [String: String]
    var title: String = "Baremos guardados"
    var onSelect: ((MiGestorKit.PhysicalTestScale) -> Void)?

    @State private var expandedScaleIds: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text("Consulta el baremo que se aplicará según el sexo, curso y edad del alumno.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(scales.count) escala\(scales.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if scales.isEmpty {
                Label("Todavía no hay baremos guardados para este contexto.", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(scales.sorted(by: sortScales), id: \.id) { scale in
                            scaleRow(scale)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func scaleRow(_ scale: MiGestorKit.PhysicalTestScale) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedScaleIds.contains(scale.id) },
                set: { expanded in
                    if expanded {
                        expandedScaleIds.insert(scale.id)
                    } else {
                        expandedScaleIds.remove(scale.id)
                    }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(scale.ranges.sorted { $0.sortOrder < $1.sortOrder }, id: \.id) { range in
                    HStack(spacing: 10) {
                        Text(rangeLabel(range, scale: scale))
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(PhysicalTestsFormatting.decimal(range.score))
                            .font(.caption.weight(.black).monospacedDigit())
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if let onSelect {
                    Button {
                        onSelect(scale)
                    } label: {
                        Label("Abrir este baremo en el editor", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
            }
            .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(scale.name)
                            .font(.subheadline.weight(.bold))
                        Text(testNames[scale.testId] ?? scale.testId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(sexLabel(scale.sex))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(sexTint(scale.sex))
                }

                HStack(spacing: 8) {
                    catalogPill(
                        scale.scoringMode == .linear ? "Gradual" : "Por rangos",
                        systemImage: scale.scoringMode == .linear ? "chart.xyaxis.line" : "list.number"
                    )
                    catalogPill(scale.ranges.count == 1 ? "1 punto" : "\(scale.ranges.count) puntos", systemImage: "chart.bar")
                    if scale.scoringMode == .linear, let roundTo = scale.scoreRoundTo?.doubleValue {
                        catalogPill("Paso \(PhysicalTestsFormatting.decimal(roundTo))", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                    Text(scopeLabel(scale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func catalogPill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func rangeLabel(_ range: MiGestorKit.PhysicalTestScaleRange, scale: MiGestorKit.PhysicalTestScale) -> String {
        if scale.scoringMode == .linear {
            let value = "Desde \(range.minValue.map { PhysicalTestsFormatting.decimal($0.doubleValue) } ?? "-")"
            return range.label?.isEmpty == false ? "\(range.label!) · \(value)" : value
        }
        let min = range.minValue.map { PhysicalTestsFormatting.decimal($0.doubleValue) } ?? "-∞"
        let max = range.maxValue.map { PhysicalTestsFormatting.decimal($0.doubleValue) } ?? "+∞"
        return range.label?.isEmpty == false ? range.label! : "\(min) – \(max)"
    }

    private func scopeLabel(_ scale: MiGestorKit.PhysicalTestScale) -> String {
        let course = scale.course.map { "\($0.intValue)º" } ?? "Todos los cursos"
        let age: String
        if scale.ageFrom != nil || scale.ageTo != nil {
            let ageFrom = scale.ageFrom.map { String($0.intValue) } ?? "-"
            let ageTo = scale.ageTo.map { String($0.intValue) } ?? "-"
            age = " · \(ageFrom)–\(ageTo) años"
        } else {
            age = ""
        }
        return course + age
    }

    private func sexLabel(_ sex: String?) -> String {
        switch sex?.uppercased() {
        case "MALE", "M", "H", "HOMBRE", "MASCULINO": return "Hombre"
        case "FEMALE", "F", "MUJER", "FEMENINO": return "Mujer"
        default: return "Neutro"
        }
    }

    private func sexTint(_ sex: String?) -> Color {
        switch sex?.uppercased() {
        case "MALE", "M", "H", "HOMBRE", "MASCULINO": return .blue
        case "FEMALE", "F", "MUJER", "FEMENINO": return .pink
        default: return .secondary
        }
    }

    private func sortScales(_ lhs: MiGestorKit.PhysicalTestScale, _ rhs: MiGestorKit.PhysicalTestScale) -> Bool {
        let lhsTest = testNames[lhs.testId] ?? lhs.testId
        let rhsTest = testNames[rhs.testId] ?? rhs.testId
        if lhsTest != rhsTest { return lhsTest.localizedCaseInsensitiveCompare(rhsTest) == .orderedAscending }
        let lhsSex = sexLabel(lhs.sex)
        let rhsSex = sexLabel(rhs.sex)
        if lhsSex != rhsSex { return lhsSex.localizedCaseInsensitiveCompare(rhsSex) == .orderedAscending }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
