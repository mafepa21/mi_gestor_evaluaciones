import SwiftUI

/// Reparto de los ítems de un instrumento de autoevaluación/coevaluación en sus dos partes,
/// que se rellenan y se puntúan de forma distinta (ver
/// `LearningSituationAssessmentInstrumentsImportService.swift`, `.selfAssessment`/`.peerAssessment`).
struct StudentRubricSections {
    /// Indicadores de la rúbrica (`rub_<n>`, escala 1-4). Son los que dan la nota.
    let rubricIndices: [Int]
    /// Preguntas abiertas de reflexión (`open_<n>`). No puntúan; las revisa el profesorado.
    let openIndices: [Int]
    /// Cualquier otro ítem que no siga esas dos convenciones. No debería haberlo, pero se
    /// pinta igual para no esconder nunca contenido de la plantilla.
    let otherIndices: [Int]
}

/// Detecta la forma de un instrumento que rellena el alumnado: al menos un indicador con clave
/// `rub_<n>` en escala 1-4. Devuelve `nil` para cualquier otro instrumento estructurado
/// (checklist, quiz, rejilla de observación, formulario suelto).
func studentRubricSections(for items: [StructuredInstrumentEvaluationItem]) -> StudentRubricSections? {
    var rubricIndices: [Int] = []
    var openIndices: [Int] = []
    var otherIndices: [Int] = []
    for (index, item) in items.enumerated() {
        if item.key.hasPrefix("rub_"), item.type == .scale14 {
            rubricIndices.append(index)
        } else if item.key.hasPrefix("open_") {
            openIndices.append(index)
        } else {
            otherIndices.append(index)
        }
    }
    guard !rubricIndices.isEmpty else { return nil }
    return StudentRubricSections(
        rubricIndices: rubricIndices,
        openIndices: openIndices,
        otherIndices: otherIndices
    )
}

/// Contenido de relleno de una autoevaluación/coevaluación: primero la rúbrica, con sus cuatro
/// niveles visibles y elegibles como en una rúbrica de papel, y después las preguntas de
/// reflexión, que no puntúan.
///
/// La nota que se muestra aquí es informativa: la que cuenta para la media del Cuaderno se
/// calcula y persiste en `NotebookInstrumentsRepositorySqlDelight.deriveStudentRubricScore`
/// (Kotlin) al guardar, con la misma fórmula (media de los indicadores respondidos).
struct StudentRubricInstrumentContent: View {
    @Binding var model: StructuredInstrumentEvaluationModel
    let sections: StudentRubricSections
    @State private var expandedLevelKeys: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            rubricSection
            if !sections.openIndices.isEmpty {
                openQuestionsSection
            }
            if !sections.otherIndices.isEmpty {
                otherItemsSection
            }
        }
    }

    private var rubricSection: some View {
        NotebookSurface {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Rúbrica")
                        .font(.headline)
                    Spacer()
                    Text(averageText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(NotebookStyle.successTint)
                }
                Text("Cada indicador puntúa de 1 a 4. La nota del instrumento es la media de los indicadores respondidos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 20) {
                    ForEach(sections.rubricIndices, id: \.self) { index in
                        indicatorBlock(index: index)
                    }
                }
            }
        }
    }

    private func indicatorBlock(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.items[index].title)
                .font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            let levels = rubricLevels(for: model.items[index])
            if levels.isEmpty {
                // Sin descriptores en la plantilla no hay rúbrica que pintar: se deja el
                // selector 1-4 de siempre para no perder la respuesta.
                InstrumentEvaluationScaleControl(selection: numberBinding(index: index))
            } else {
                VStack(spacing: 6) {
                    ForEach(levels) { level in
                        levelRow(level, index: index)
                    }
                }
            }
        }
    }

    private func levelRow(_ level: RubricLevelOption, index: Int) -> some View {
        let isSelected = model.items[index].numberValue == level.value
        let levelKey = "\(index)-\(level.id)"
        let isExpanded = expandedLevelKeys.contains(levelKey)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    // Volver a tocar el nivel elegido lo deselecciona: sin esto no había forma de
                    // dejar un indicador sin responder tras una pulsación accidental.
                    model.items[index].numberValue = isSelected ? "" : level.value
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isSelected ? NotebookStyle.primaryTint : Color.secondary.opacity(0.35))

                        Text(level.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 8)

                        Text(level.value)
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? NotebookStyle.primaryTint : .secondary)
                    }
                }
                .buttonStyle(.plain)

                if !level.descriptor.isEmpty {
                    Button {
                        if isExpanded {
                            expandedLevelKeys.remove(levelKey)
                        } else {
                            expandedLevelKeys.insert(levelKey)
                        }
                    } label: {
                        Image(systemName: isExpanded ? "info.circle.fill" : "info.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isSelected ? NotebookStyle.primaryTint : .secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Descripción de \(level.label)")
                }
            }

            if isExpanded, !level.descriptor.isEmpty {
                Text(level.descriptor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 28)
                    .padding(.top, 8)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: NotebookStyle.innerRadius, style: .continuous)
                .fill(isSelected ? NotebookStyle.primaryTint.opacity(0.12) : NotebookStyle.surfaceMuted)
        )
        .overlay {
            RoundedRectangle(cornerRadius: NotebookStyle.innerRadius, style: .continuous)
                .stroke(isSelected ? NotebookStyle.primaryTint.opacity(0.22) : NotebookStyle.border, lineWidth: 1)
        }
    }

    private var openQuestionsSection: some View {
        NotebookSurface {
            VStack(alignment: .leading, spacing: 16) {
                Text("Preguntas de reflexión")
                    .font(.headline)
                Text("No puntúan: las revisa el profesorado.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(sections.openIndices, id: \.self) { index in
                        StructuredInstrumentItemRow(item: $model.items[index])
                    }
                }
            }
        }
    }

    private var otherItemsSection: some View {
        NotebookSurface {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(sections.otherIndices, id: \.self) { index in
                    StructuredInstrumentItemRow(item: $model.items[index])
                }
            }
        }
    }

    private func numberBinding(index: Int) -> Binding<String> {
        Binding(
            get: { model.items[index].numberValue },
            set: { model.items[index].numberValue = $0 }
        )
    }

    private var averageText: String {
        let values = sections.rubricIndices.compactMap {
            Double(model.items[$0].numberValue.replacingOccurrences(of: ",", with: "."))
        }
        guard !values.isEmpty else { return "—" }
        return String(format: "%.2f / 4", values.reduce(0, +) / Double(values.count))
    }
}

/// Un nivel de la rúbrica tal y como viaja en el `helpText` del ítem:
/// `"1 Todavía no: descriptor · 2 A veces: descriptor · …"` (ver `KmpBridge.assessmentInstrumentItems`).
struct RubricLevelOption: Identifiable {
    let id: Int
    let value: String
    let label: String
    let descriptor: String
}

private func rubricLevels(for item: StructuredInstrumentEvaluationItem) -> [RubricLevelOption] {
    guard let helpText = item.helpText, !helpText.isEmpty else { return [] }
    let parts = helpText.components(separatedBy: " · ").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    guard parts.count >= 2 else { return [] }
    return parts.prefix(4).enumerated().map { index, part in
        let separator = part.range(of: ": ")
        let label = separator.map { String(part[..<$0.lowerBound]) } ?? part
        let descriptor = separator.map { String(part[$0.upperBound...]) } ?? ""
        return RubricLevelOption(
            id: index,
            value: String(index + 1),
            label: label.trimmingCharacters(in: .whitespaces),
            descriptor: descriptor.trimmingCharacters(in: .whitespaces)
        )
    }
}
