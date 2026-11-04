import SwiftUI
import MiGestorKit

/// Botón del editor de rúbricas para dar a un criterio dibujos por nivel
/// y/o cronómetro. Abre un popover con el selector de dibujos y los cortes.
struct RubricCriterionPresentationButton: View {
    let visualKey: String?
    let timingConfig: String?
    let levelCount: Int
    let onChange: (_ visualKey: String?, _ timingConfig: String?) -> Void

    @State private var isEditing = false

    private var summary: String {
        var parts: [String] = []
        if RubricVisuals.isKnown(visualKey) { parts.append("Dibujos") }
        if timingConfig != nil { parts.append("Cronómetro") }
        return parts.isEmpty ? "Dibujos o cronómetro" : parts.joined(separator: " · ")
    }

    var body: some View {
        Button {
            isEditing = true
        } label: {
            Label(summary, systemImage: timingConfig != nil ? "stopwatch" : "photo.on.rectangle")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .popover(isPresented: $isEditing) {
            RubricCriterionPresentationEditor(
                visualKey: visualKey,
                timingConfig: timingConfig,
                levelCount: levelCount,
                onChange: onChange
            )
            .frame(minWidth: 320, idealWidth: 360)
            .presentationCompactAdaptation(.sheet)
        }
    }
}

private struct RubricCriterionPresentationEditor: View {
    let levelCount: Int
    let onChange: (_ visualKey: String?, _ timingConfig: String?) -> Void

    @State private var visualKey: String
    @State private var usesTimer: Bool
    @State private var lowerIsBetter: Bool
    @State private var cutTexts: [String]

    init(visualKey: String?, timingConfig: String?, levelCount: Int, onChange: @escaping (String?, String?) -> Void) {
        self.levelCount = levelCount
        self.onChange = onChange
        let timing = RubricTiming.companion.parse(raw: timingConfig)
        let cutCount = max(levelCount - 1, 1)
        let cuts = timing?.cuts.map { RubricCriterionPresentationEditor.text($0.doubleValue) } ?? []
        _visualKey = State(initialValue: RubricVisuals.isKnown(visualKey) ? visualKey ?? "" : "")
        _usesTimer = State(initialValue: timing != nil)
        _lowerIsBetter = State(initialValue: timing?.lowerIsBetter ?? true)
        _cutTexts = State(initialValue: Array((cuts + Array(repeating: "", count: cutCount)).prefix(cutCount)))
    }

    private static func text(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "es_ES")))
    }

    /// Cortes válidos (números y de menor a mayor) en el formato de `RubricTiming`.
    private var timingConfig: String? {
        guard usesTimer else { return nil }
        let values = cutTexts.compactMap { Double($0.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) }
        guard values.count == cutTexts.count, !values.isEmpty, zip(values, values.dropFirst()).allSatisfy({ $0 < $1 }) else { return nil }
        return RubricTiming(lowerIsBetter: lowerIsBetter, cuts: values.map { KotlinDouble(value: $0) }).serialize()
    }

    private var cutsAreInvalid: Bool { usesTimer && timingConfig == nil }

    var body: some View {
        Form {
            Section("Dibujos por nivel") {
                Picker("Dibujos", selection: $visualKey) {
                    Text("Sin dibujos").tag("")
                    ForEach(RubricVisuals.options) { option in
                        Text(option.title).tag(option.key)
                    }
                }
                if let option = RubricVisuals.option(for: visualKey) {
                    Text(option.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !visualKey.isEmpty, levelCount != 4 {
                    Label("Los dibujos son para 4 niveles. Esta rúbrica tiene \(levelCount).", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Toggle("Cronómetro", isOn: $usesTimer)
                if usesTimer {
                    Picker("Mejor", selection: $lowerIsBetter) {
                        Text("Menos tiempo").tag(true)
                        Text("Más tiempo").tag(false)
                    }
                    .pickerStyle(.segmented)
                    ForEach(cutTexts.indices, id: \.self) { index in
                        LabeledContent("Corte \(index + 1) (s)") {
                            TextField("0", text: $cutTexts[index])
                                .multilineTextAlignment(.trailing)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                        }
                    }
                }
            } header: {
                Text("Tiempo")
            } footer: {
                if cutsAreInvalid {
                    Text("Escribe los cortes de menor a mayor, por ejemplo 10, 12 y 15.")
                        .foregroundStyle(.orange)
                } else if usesTimer {
                    Text("Al parar el cronómetro, la app pone el nivel. Puedes cambiarlo a mano.")
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: visualKey) { save() }
        .onChange(of: usesTimer) { save() }
        .onChange(of: lowerIsBetter) { save() }
        .onChange(of: cutTexts) { save() }
    }

    private func save() {
        if cutsAreInvalid { return }
        onChange(visualKey.isEmpty ? nil : visualKey, timingConfig)
    }
}
