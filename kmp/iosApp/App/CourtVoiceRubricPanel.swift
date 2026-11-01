import SwiftUI

// MARK: - Rúbrica visible durante la sesión de Voz de Pista

/// Muestra el instrumento de «Hoy evalúo» entero: criterios × niveles con sus descriptores.
/// Si hay una alumna seleccionada en la bandeja, marca lo sugerido y lo elegido y deja cambiar el nivel tocando la celda.
struct CourtVoiceRubricPanel: View {
    let instrument: CourtVoiceInstrumentDescriptor
    let studentName: String?
    let proposals: [CourtVoiceCriterionProposal]?
    let onChoose: (_ criterionId: String, _ levelId: String?) -> Void
    var onHide: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(instrument.title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let onHide {
                    Button("Ocultar", action: onHide)
                        .buttonStyle(.borderless)
                }
            }

            if dynamicTypeSize.isAccessibilitySize {
                stacked
            } else {
                ViewThatFits(in: .horizontal) {
                    matrix
                    stacked
                }
            }
        }
        .padding(16)
    }

    private var subtitle: String {
        if let studentName {
            return "\(studentName) · lo sugerido sale de su dictado. Toca una celda para cambiar el nivel."
        }
        return "Toca una alumna de la bandeja para ver y cambiar sus niveles."
    }

    // MARK: Datos

    private func proposal(for criterion: CourtVoiceCriterionDescriptor) -> CourtVoiceCriterionProposal? {
        proposals?.first { $0.criterion.id == criterion.id }
    }

    /// Lista de cotejo: Sí antes que No. Rúbrica: de menor a mayor.
    private func levels(of criterion: CourtVoiceCriterionDescriptor) -> [CourtVoiceCriterionLevel] {
        criterion.kind == .check ? [.checkYes, .checkNo] : criterion.levels
    }

    /// Cabecera común si todos los criterios tienen los mismos niveles.
    private var sharedLevelNames: [String]? {
        let names = instrument.criteria.map { levels(of: $0).map(\.name) }
        guard let first = names.first, names.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private var columnCount: Int {
        instrument.criteria.map { levels(of: $0).count }.max() ?? 0
    }

    // MARK: Tabla (ancho suficiente y texto normal)

    private var matrix: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                Text("Criterio")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(0..<columnCount, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(sharedLevelNames?[index] ?? "Nivel \(index + 1)")
                            .font(.caption.weight(.semibold))
                        if instrument.criteria.first?.kind == .level {
                            Text("\(index + 1)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 110, maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityHidden(true)

            ForEach(instrument.criteria) { criterion in
                let current = proposal(for: criterion)
                let isActive = current?.isMentioned == true || current?.chosenLevelId != nil
                GridRow {
                    Label {
                        Text(criterion.title).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: isActive ? "chevron.right.circle.fill" : "circle")
                            .foregroundStyle(isActive ? EvaluationDesign.accent : Color.secondary.opacity(0.4))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isActive ? EvaluationDesign.accent : Color.primary)
                    .frame(minWidth: 130, maxWidth: 180, alignment: .leading)

                    ForEach(Array(levels(of: criterion).enumerated()), id: \.element.id) { _, level in
                        levelCell(criterion: criterion, level: level, current: current, isActiveRow: isActive)
                    }
                    if levels(of: criterion).count < columnCount {
                        ForEach(levels(of: criterion).count..<columnCount, id: \.self) { _ in Color.clear }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(criterion.title)
                .accessibilityValue(accessibilityValue(for: criterion, current: current))
                .accessibilityAdjustableAction { direction in adjust(criterion: criterion, current: current, direction: direction) }
            }
        }
        .frame(minWidth: 140 + CGFloat(columnCount) * 120)
    }

    private func levelCell(
        criterion: CourtVoiceCriterionDescriptor,
        level: CourtVoiceCriterionLevel,
        current: CourtVoiceCriterionProposal?,
        isActiveRow: Bool
    ) -> some View {
        let isChosen = current?.chosenLevelId == level.id
        let isSuggested = current?.suggestedLevelId == level.id
        return Button {
            onChoose(criterion.id, isChosen && criterion.kind == .level ? nil : level.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                if isSuggested {
                    Label("Sugerido", systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.purple)
                }
                if level.detail != nil || sharedLevelNames == nil {
                    Text(level.detail ?? level.name)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(level.name).font(.footnote.weight(.semibold))
                }
                if isChosen {
                    Label("Elegido", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(EvaluationDesign.accent)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            .padding(8)
            .background(
                cellBackground(isChosen: isChosen, isActiveRow: isActiveRow),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isChosen ? EvaluationDesign.accent : .clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // La fila crece con el descriptor más largo en vez de recortarlo.
        .fixedSize(horizontal: false, vertical: true)
        .disabled(proposals == nil)
    }

    private func cellBackground(isChosen: Bool, isActiveRow: Bool) -> Color {
        if isChosen { return EvaluationDesign.accent.opacity(0.10) }
        if isActiveRow { return EvaluationDesign.accent.opacity(0.06) }
        return Color.secondary.opacity(0.07)
    }

    // MARK: Tarjetas (texto grande o poco ancho)

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(instrument.criteria) { criterion in
                let current = proposal(for: criterion)
                VStack(alignment: .leading, spacing: 8) {
                    Text(criterion.title)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    ForEach(levels(of: criterion)) { level in
                        let isChosen = current?.chosenLevelId == level.id
                        let isSuggested = current?.suggestedLevelId == level.id
                        Button {
                            onChoose(criterion.id, isChosen && criterion.kind == .level ? nil : level.id)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isChosen ? EvaluationDesign.accent : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(level.name).font(.subheadline.weight(.semibold))
                                        if isSuggested {
                                            Label("Sugerido", systemImage: "sparkles")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.purple)
                                        }
                                    }
                                    if let detail = level.detail {
                                        Text(detail).font(.footnote).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(proposals == nil)
                        .accessibilityAddTraits(isChosen ? .isSelected : [])
                        .accessibilityValue(isSuggested ? "Sugerido" : "")
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    // MARK: Accesibilidad

    private func accessibilityValue(for criterion: CourtVoiceCriterionDescriptor, current: CourtVoiceCriterionProposal?) -> String {
        let all = levels(of: criterion)
        var parts: [String] = []
        if let suggested = current?.suggestedLevel { parts.append("Sugerido \(suggested.name)") }
        if let chosen = current?.chosenLevel {
            let position = (all.firstIndex(of: chosen) ?? 0) + 1
            parts.append(criterion.kind == .level ? "Elegido \(chosen.name), \(position) de \(all.count)" : "Elegido \(chosen.name)")
            if let detail = chosen.detail { parts.append(detail) }
        } else {
            parts.append(criterion.kind == .check ? "Sin marcar" : "Sin valorar")
        }
        return parts.joined(separator: ". ")
    }

    private func adjust(criterion: CourtVoiceCriterionDescriptor, current: CourtVoiceCriterionProposal?, direction: AccessibilityAdjustmentDirection) {
        guard proposals != nil else { return }
        let all = levels(of: criterion)
        guard !all.isEmpty else { return }
        let index = current?.chosenLevel.flatMap { all.firstIndex(of: $0) }
        let next: Int
        switch direction {
        case .increment: next = min(all.count - 1, (index ?? -1) + 1)
        case .decrement: next = max(0, (index ?? all.count) - 1)
        @unknown default: return
        }
        onChoose(criterion.id, all[next].id)
    }
}

// MARK: - Piezas de la sesión de evaluación

/// Instrumento de «Hoy evalúo» recordado por clase.
enum CourtVoiceFocusStore {
    private static func key(_ classId: Int64) -> String { "court.voice.focus.instrument.v1.\(classId)" }

    static func columnId(classId: Int64) -> String? {
        UserDefaults.standard.string(forKey: key(classId))
    }

    static func save(columnId: String?, classId: Int64) {
        if let columnId {
            UserDefaults.standard.set(columnId, forKey: key(classId))
        } else {
            UserDefaults.standard.removeObject(forKey: key(classId))
        }
    }
}

#if os(iOS)
/// iPad: la hoja ocupa el tamaño de página para que quepan bandeja y rúbrica.
struct CourtVoicePageSizing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.page)
        } else {
            content
        }
    }
}
#endif

/// Chips que saltan de línea cuando no caben.
struct FlowChips: View {
    let items: [String]

    var body: some View {
        CourtVoiceFlowLayout(spacing: 4) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.10), in: Capsule())
            }
        }
    }
}

private struct CourtVoiceFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
