import SwiftUI

enum PhysicalTestScaleDirection: String, CaseIterable, Identifiable {
    case higherIsBetter
    case lowerIsBetter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .higherIsBetter: return "Mayor marca"
        case .lowerIsBetter: return "Menor marca"
        }
    }

    var subtitle: String {
        switch self {
        case .higherIsBetter: return "Salto, repeticiones, niveles o distancia."
        case .lowerIsBetter: return "Tiempo, velocidad o pruebas cronometradas."
        }
    }
}

struct PhysicalTestScaleRange: Identifiable, Hashable {
    let id = UUID()
    var minValue: Double?
    var maxValue: Double?
    var score: Double
    var label: String

    func contains(_ value: Double) -> Bool {
        let passesMin = minValue.map { value >= $0 } ?? true
        let passesMax = maxValue.map { value <= $0 } ?? true
        return passesMin && passesMax
    }
}

struct PhysicalTestScaleDraft: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var direction: PhysicalTestScaleDirection
    var ranges: [PhysicalTestScaleRange]

    static let defaultJump = PhysicalTestScaleDraft(
        name: "Baremo salto horizontal 0-10",
        direction: .higherIsBetter,
        ranges: [
            .init(minValue: nil, maxValue: 1.19, score: 3, label: "< 1.20 m"),
            .init(minValue: 1.20, maxValue: 1.39, score: 5, label: "1.20-1.39 m"),
            .init(minValue: 1.40, maxValue: 1.59, score: 6, label: "1.40-1.59 m"),
            .init(minValue: 1.60, maxValue: 1.79, score: 8, label: "1.60-1.79 m"),
            .init(minValue: 1.80, maxValue: nil, score: 10, label: ">= 1.80 m")
        ]
    )

    static let defaultSpeed = PhysicalTestScaleDraft(
        name: "Baremo velocidad 0-10",
        direction: .lowerIsBetter,
        ranges: [
            .init(minValue: nil, maxValue: 6.0, score: 10, label: "<= 6.0 s"),
            .init(minValue: 6.1, maxValue: 6.5, score: 8, label: "6.1-6.5 s"),
            .init(minValue: 6.6, maxValue: 7.0, score: 6, label: "6.6-7.0 s"),
            .init(minValue: 7.1, maxValue: 7.5, score: 5, label: "7.1-7.5 s"),
            .init(minValue: 7.6, maxValue: nil, score: 3, label: "> 7.5 s")
        ]
    )

    func score(for rawValue: Double) -> Double? {
        ranges.first(where: { $0.contains(rawValue) })?.score
    }
}

struct PhysicalTestScaleEditor: View {
    @Binding var scale: PhysicalTestScaleDraft
    @State private var previewValue = ""

    private var previewScore: Double? {
        Double(previewValue.replacingOccurrences(of: ",", with: ".")).flatMap { scale.score(for: $0) }
    }

    var body: some View {
        Form {
            Section("Baremo") {
                TextField("Nombre", text: $scale.name)

                Picker("Dirección", selection: $scale.direction) {
                    ForEach(PhysicalTestScaleDirection.allCases) { direction in
                        Text(direction.title).tag(direction)
                    }
                }

                Text(scale.direction.subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Section("Rangos") {
                ForEach($scale.ranges) { $range in
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Etiqueta", text: $range.label)
                        HStack {
                            NumberDraftField(title: "Mín.", value: $range.minValue)
                            NumberDraftField(title: "Máx.", value: $range.maxValue)
                            NumberDraftFieldRequired(title: "Nota", value: $range.score)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Button {
                    scale.ranges.append(.init(minValue: nil, maxValue: nil, score: 5, label: "Nuevo rango"))
                } label: {
                    Label("Añadir rango", systemImage: "plus")
                }
            }

            Section("Preview") {
                TextField("Marca bruta", text: $previewValue)
                    .appKeyboardType(.decimalPad)

                HStack {
                    Text("Nota baremada")
                    Spacer()
                    Text(previewScore.map { PhysicalTestsFormatting.decimal($0) } ?? "-")
                        .font(.headline.monospacedDigit())
                }
            }

            Section {
                Text("TODO(kmp-physical-tests): persistir baremos en KMP/SQLDelight y vincularlos a PhysicalTestResult.rawValue -> score.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Baremo")
    }
}

private struct NumberDraftField: View {
    let title: String
    @Binding var value: Double?

    private var text: Binding<String> {
        Binding(
            get: { value.map { PhysicalTestsFormatting.decimal($0) } ?? "" },
            set: { value = Double($0.replacingOccurrences(of: ",", with: ".")) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField("-", text: text)
                .appKeyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct NumberDraftFieldRequired: View {
    let title: String
    @Binding var value: Double

    private var text: Binding<String> {
        Binding(
            get: { PhysicalTestsFormatting.decimal(value) },
            set: { value = Double($0.replacingOccurrences(of: ",", with: ".")) ?? value }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField("-", text: text)
                .appKeyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
    }
}

enum PhysicalTestsFormatting {
    static func decimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = value.rounded() == value ? 0 : 1
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
