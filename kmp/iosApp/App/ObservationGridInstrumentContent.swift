import SwiftUI

/// Un grupo de indicadores que pertenecen a la misma sesión de observación (S3/S7/S9).
struct ObservationSessionGroup: Identifiable {
    let id: String
    let label: String
    let itemIndices: [Int]
}

/// Detecta si una lista de ítems estructurados sigue la forma "sesión · indicador"
/// (ver LearningSituationAssessmentInstrumentsImportService.swift, sessionIndicatorObservationFields)
/// y, si es así, los agrupa por sesión conservando el orden de aparición. Devuelve `nil`
/// para cualquier otra forma de instrumento estructurado (checklist, quiz, formulario suelto).
func observationSessionGroups(for items: [StructuredInstrumentEvaluationItem]) -> [ObservationSessionGroup]? {
    guard !items.isEmpty,
          items.allSatisfy({ $0.type == .scale14 && $0.title.contains(" · ") }) else {
        return nil
    }
    var order: [String] = []
    var indicesByLabel: [String: [Int]] = [:]
    for (index, item) in items.enumerated() {
        let label = sessionLabel(from: item.title)
        if indicesByLabel[label] == nil {
            order.append(label)
            indicesByLabel[label] = []
        }
        indicesByLabel[label]?.append(index)
    }
    guard order.count > 1 else { return nil }
    return order.map { label in
        ObservationSessionGroup(id: label, label: label, itemIndices: indicesByLabel[label] ?? [])
    }
}

private func sessionLabel(from title: String) -> String {
    String(title.split(separator: "·", maxSplits: 1)[0]).trimmingCharacters(in: .whitespaces)
}

private func indicatorLabel(from title: String) -> String {
    guard let separatorRange = title.range(of: "·") else { return title }
    return String(title[separatorRange.upperBound...]).trimmingCharacters(in: .whitespaces)
}

/// Contenido de relleno de una rejilla de observación agrupada por sesión: cada sesión fija
/// (S3/S7/S9) muestra sus indicadores con un selector rápido 1-4, la media de la sesión en
/// vivo, y una cabecera con la nota final del instrumento (media de las sesiones respondidas).
/// El cálculo mostrado aquí es solo informativo: la nota que cuenta para la media del Cuaderno
/// se calcula y persiste en NotebookInstrumentsRepositorySqlDelight.saveResponses (Kotlin) al guardar.
struct ObservationGridInstrumentContent: View {
    @Binding var model: StructuredInstrumentEvaluationModel
    let groups: [ObservationSessionGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            instrumentAverageHeader
            ForEach(groups) { group in
                sessionSection(group)
            }
        }
    }

    // El criterio de evaluación se pinta una sola vez, en la cabecera de la hoja
    // (`StructuredInstrumentEvaluationSheet.formContent`), junto al nombre del alumno. Repetirlo
    // aquí lo mostraba dos veces seguidas en la misma pantalla.
    private var instrumentAverageHeader: some View {
        HStack {
            Text("Nota final del instrumento")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(instrumentAverageText)
                .font(.title3.weight(.bold))
                .foregroundStyle(NotebookStyle.successTint)
        }
        .padding(16)
        .background(NotebookStyle.surfaceMuted, in: RoundedRectangle(cornerRadius: NotebookStyle.innerRadius, style: .continuous))
    }

    private func sessionSection(_ group: ObservationSessionGroup) -> some View {
        NotebookSurface {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(group.label)
                        .font(.headline)
                    Spacer()
                    Text(averageText(for: group.itemIndices))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(NotebookStyle.primaryTint)
                }
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(group.itemIndices, id: \.self) { index in
                        indicatorRow(index: index)
                    }
                }
            }
        }
    }

    private func indicatorRow(index: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                indicatorTitle(index: index)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                scalePicker(index: index)
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 240)
            }

            VStack(alignment: .leading, spacing: 8) {
                indicatorTitle(index: index)
                scalePicker(index: index)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func indicatorTitle(index: Int) -> some View {
        Text(indicatorLabel(from: model.items[index].title))
            .font(.body)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func scalePicker(index: Int) -> some View {
        Picker("Nivel", selection: itemNumberBinding(index: index)) {
            Text("—").tag("")
            ForEach(["1", "2", "3", "4"], id: \.self) { level in
                Text(level).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func itemNumberBinding(index: Int) -> Binding<String> {
        Binding(
            get: { model.items[index].numberValue },
            set: { model.items[index].numberValue = $0 }
        )
    }

    private func sessionAverage(for indices: [Int]) -> Double? {
        let values = indices.compactMap { Double(model.items[$0].numberValue.replacingOccurrences(of: ",", with: ".")) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func averageText(for indices: [Int]) -> String {
        sessionAverage(for: indices).map { String(format: "%.2f", $0) } ?? "—"
    }

    private var instrumentAverageText: String {
        let sessionAverages = groups.compactMap { sessionAverage(for: $0.itemIndices) }
        guard !sessionAverages.isEmpty else { return "—" }
        let overall = sessionAverages.reduce(0, +) / Double(sessionAverages.count)
        return String(format: "%.2f / 4", overall)
    }
}
