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
    var testId: String = ""
    var course: Int?
    var ageFrom: Int?
    var ageTo: Int?
    var sex: String = ""
    var batteryId: String = ""
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

    var validationMessages: [String] {
        var messages: [String] = []
        for range in ranges {
            if range.minValue == nil && range.maxValue == nil {
                messages.append("Hay rangos sin mínimo ni máximo.")
            }
            if let min = range.minValue, let max = range.maxValue, min > max {
                messages.append("Hay rangos con mínimo mayor que máximo.")
            }
            if !(0...10).contains(range.score) {
                messages.append("Todas las notas deben estar entre 0 y 10.")
            }
        }
        let sorted = ranges.sorted { ($0.minValue ?? -.infinity) < ($1.minValue ?? -.infinity) }
        for pair in zip(sorted, sorted.dropFirst()) {
            if let leftMax = pair.0.maxValue, let rightMin = pair.1.minValue, rightMin <= leftMax {
                messages.append("Hay rangos solapados.")
                break
            }
        }
        return Array(Set(messages)).sorted()
    }
}

func resolvedPhysicalResult(
    attempts: [Double],
    direction: PhysicalTestScaleDirection,
    resultMode: PhysicalTestResultMode
) -> Double? {
    let validAttempts = attempts.filter { $0.isFinite }
    guard !validAttempts.isEmpty else { return nil }
    switch resultMode {
    case .best:
        return direction == .higherIsBetter ? validAttempts.max() : validAttempts.min()
    case .average:
        return validAttempts.reduce(0, +) / Double(validAttempts.count)
    case .last:
        return validAttempts.last
    }
}

enum PhysicalTestScaleStrategy: String, CaseIterable, Identifiable {
    case recommended = "Baremo recomendado"
    case progress = "Evaluar por progreso"
    case manual = "Baremo manual"

    var id: String { rawValue }

    var title: String { rawValue }

    var subtitle: String {
        switch self {
        case .recommended:
            return "Usa el baremo local disponible como punto de partida y deja la ponderación para el Cuaderno."
        case .progress:
            return "Evalúa la mejora entre mediciones cuando exista histórico persistente de condición física."
        case .manual:
            return "Define rangos de marca y nota para un baremo específico."
        }
    }
}

struct PhysicalTestScaleEditor: View {
    @Binding var scale: PhysicalTestScaleDraft
    @State private var strategy: PhysicalTestScaleStrategy = .recommended
    @State private var previewValue = ""

    private var previewScore: Double? {
        Double(previewValue.replacingOccurrences(of: ",", with: ".")).flatMap { scale.score(for: $0) }
    }

    var body: some View {
        Form {
            Section("Tipo de evaluación") {
                Picker("Baremo", selection: $strategy) {
                    ForEach(PhysicalTestScaleStrategy.allCases) { strategy in
                        Text(strategy.rawValue).tag(strategy)
                    }
                }

                Text(strategy.subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if strategy == .manual {
                Section("Baremo") {
                    TextField("Nombre", text: $scale.name)
                    TextField("Test", text: $scale.testId)

                    HStack {
                        OptionalIntField(title: "Curso", value: $scale.course)
                        OptionalIntField(title: "Edad desde", value: $scale.ageFrom)
                        OptionalIntField(title: "Edad hasta", value: $scale.ageTo)
                    }

                    TextField("Sexo opcional", text: $scale.sex)
                    TextField("Batería opcional", text: $scale.batteryId)

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
                        VStack(alignment: .leading, spacing: 8) {
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
            } else {
                Section(strategy.title) {
                    HStack {
                        Text("Baremo activo")
                        Spacer()
                        Text(scale.name)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    Text("TODO(kmp-physical-tests): persistir selección de baremo recomendado/progreso y resolver el baremo por test cuando exista catálogo KMP.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if !scale.validationMessages.isEmpty {
                Section("Validación") {
                    ForEach(scale.validationMessages, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("Preview") {
                TextField("Marca bruta", text: $previewValue)
                    .appKeyboardType(.decimalPad)

                HStack {
                    Text("Resultado final")
                    Spacer()
                    Text(previewValue.isEmpty ? "-" : previewValue)
                        .font(.headline.monospacedDigit())
                }

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

private struct OptionalIntField: View {
    let title: String
    @Binding var value: Int?

    private var text: Binding<String> {
        Binding(
            get: { value.map(String.init) ?? "" },
            set: { value = Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField("-", text: text)
                .appKeyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
        }
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
