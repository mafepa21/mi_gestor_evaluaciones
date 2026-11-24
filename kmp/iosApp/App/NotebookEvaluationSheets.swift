import SwiftUI
import MiGestorKit

// Hojas de la pestaña de evaluación: nueva pestaña con su evaluación, pesos de los
// bloques y organizar pestañas existentes. Solo cambian pestañas (padre y peso),
// nunca notas ni columnas.

/// Dónde va una pestaña nueva o movida.
enum NotebookEvaluationPlacement: Hashable {
    /// Evaluación que ya existe (pestaña raíz).
    case existing(String)
    /// «1.ª/2.ª/3.ª Evaluación» que aún no existe: se crea al guardar.
    case new(String)
    /// Pestaña suelta: no cuenta para ninguna evaluación.
    case loose
}

struct NotebookNewTabRequest: Identifiable {
    let id = UUID()
    let preferredParentTabId: String?
}

struct NotebookEvaluationWeightsRequest: Identifiable {
    let id = UUID()
    let evaluationTabId: String
}

enum NotebookEvaluationNaming {
    static let titles = ["1.ª Evaluación", "2.ª Evaluación", "3.ª Evaluación"]

    /// Opciones del menú: evaluaciones que existen y las tres de siempre que faltan.
    static func options(tabs: [NotebookTab]) -> [(placement: NotebookEvaluationPlacement, title: String)] {
        let roots = tabs.filter { $0.parentTabId == nil }
        let evaluations = roots.filter { root in tabs.contains { $0.parentTabId == root.id } || titles.contains(root.title) }
        var result = evaluations
            .sorted { $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order }
            .map { (NotebookEvaluationPlacement.existing($0.id), $0.title) }
        for title in titles where !evaluations.contains(where: { $0.title == title }) {
            result.append((.new(title), title))
        }
        result.append((.loose, "Ninguna (pestaña suelta)"))
        return result
    }

    /// Propuesta por defecto: la evaluación del trimestre actual.
    static func defaultPlacement(tabs: [NotebookTab], date: Date = Date()) -> NotebookEvaluationPlacement {
        let term = EvaluationClosingTerm.current(at: date)
        let title = titles[[EvaluationClosingTerm.first, .second, .third].firstIndex(of: term) ?? 0]
        let options = options(tabs: tabs)
        return options.first { $0.title == title }?.placement ?? .new(title)
    }
}

// MARK: - Nueva pestaña

struct NotebookNewTabSheet: View {
    let tabs: [NotebookTab]
    let preferredParentTabId: String?
    let defaultTitle: String
    let onCreate: (_ title: String, _ placement: NotebookEvaluationPlacement, _ weight: Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var placement: NotebookEvaluationPlacement = .loose
    @State private var weightText = ""

    private var options: [(placement: NotebookEvaluationPlacement, title: String)] {
        NotebookEvaluationNaming.options(tabs: tabs)
    }

    private var weight: Double? { NotebookWeightText.parse(weightText) }
    private var weightIsValid: Bool { weightText.trimmingCharacters(in: .whitespaces).isEmpty || weight != nil }
    private var canCreate: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && weightIsValid }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre", text: $title)
                    Picker("Evaluación", selection: $placement) {
                        ForEach(options, id: \.placement) { option in
                            Text(option.title).tag(option.placement)
                        }
                    }
                    if placement != .loose {
                        LabeledContent("Peso en la evaluación") {
                            NotebookPercentField(text: $weightText, accessibilityName: "Peso de \(title.isEmpty ? "la pestaña" : title)")
                        }
                    }
                } footer: {
                    Text(placement == .loose
                         ? "Una pestaña suelta (como «Asistencia») no cuenta para ninguna evaluación."
                         : "Sus notas saldrán en el Resumen de la evaluación. Si dejas el peso vacío, pesa lo mismo que los demás bloques.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Nueva pestaña")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") {
                        onCreate(title.trimmingCharacters(in: .whitespacesAndNewlines), placement, placement == .loose ? nil : weight)
                        dismiss()
                    }
                    .disabled(!canCreate)
                }
            }
        }
        .onAppear {
            title = defaultTitle
            if let preferredParentTabId {
                placement = .existing(preferredParentTabId)
            } else {
                placement = NotebookEvaluationNaming.defaultPlacement(tabs: tabs)
            }
        }
    }
}

// MARK: - Pesos

struct NotebookEvaluationWeightsSheet: View {
    let evaluationTitle: String
    let blocks: [NotebookTab]
    let onSave: ([String: Double]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var texts: [String: String] = [:]

    private var values: [String: Double] {
        texts.compactMapValues(NotebookWeightText.parse)
    }

    private var allValid: Bool { blocks.allSatisfy { values[$0.id] != nil } }
    private var total: Double { blocks.reduce(0) { $0 + (values[$1.id] ?? 0) } }
    private var totalText: String { NotebookEvaluation.shared.formatPercent(value: total) }
    private var isHundred: Bool { abs(total - 100) < 0.05 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(blocks, id: \.id) { block in
                        LabeledContent(block.title) {
                            NotebookPercentField(
                                text: Binding(get: { texts[block.id] ?? "" }, set: { texts[block.id] = $0 }),
                                accessibilityName: "Peso de \(block.title)"
                            )
                        }
                    }
                    LabeledContent {
                        Label {
                            Text(totalText)
                        } icon: {
                            Image(systemName: isHundred ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(isHundred ? .green : .orange)
                        }
                    } label: {
                        Text("Total").bold()
                    }
                    .accessibilityElement(children: .combine)
                } header: {
                    Text("Peso de cada bloque")
                } footer: {
                    Text(isHundred
                         ? "El peso de cada nota dentro de su bloque se cambia en la columna, como siempre."
                         : "El total no es 100: se reparte en proporción. Ejemplo: 60 y 60 cuentan como 50 % y 50 %.")
                }

                Section {
                    Button("Repartir a partes iguales") {
                        let share = (100.0 / Double(max(blocks.count, 1)) * 10).rounded() / 10
                        for block in blocks { texts[block.id] = NotebookWeightText.format(share) }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Pesos · \(evaluationTitle)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        // Se guardan siempre los pesos de todos los bloques: sin mezclas con «vacío».
                        onSave(values)
                        if !isHundred {
                            AccessibilityNotification.Announcement("El total no es 100. Se reparte en proporción.").post()
                        }
                        dismiss()
                    }
                    .disabled(!allValid)
                }
            }
        }
        .onAppear {
            let percents = NotebookEvaluation.shared.weightPercents(blocks: blocks)
            for block in blocks {
                let value = block.weight?.doubleValue ?? percents[block.id]?.doubleValue ?? 0
                texts[block.id] = NotebookWeightText.format(value)
            }
        }
    }
}

// MARK: - Organizar pestañas

struct NotebookOrganizeTabsSheet: View {
    let tabs: [NotebookTab]
    let onSave: (_ placements: [String: NotebookEvaluationPlacement]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var placements: [String: NotebookEvaluationPlacement] = [:]

    /// Pestañas que se pueden mover: las sueltas y los bloques (no las evaluaciones con hijas).
    private var movableTabs: [NotebookTab] {
        tabs.filter { tab in
            !(tab.parentTabId == nil && tabs.contains { $0.parentTabId == tab.id })
                && !(tab.parentTabId == nil && NotebookEvaluationNaming.titles.contains(tab.title))
        }
        .sorted { ($0.parentTabId ?? "", $0.order, $0.id) < ($1.parentTabId ?? "", $1.order, $1.id) }
    }

    private var options: [(placement: NotebookEvaluationPlacement, title: String)] {
        NotebookEvaluationNaming.options(tabs: tabs)
    }

    private func currentPlacement(_ tab: NotebookTab) -> NotebookEvaluationPlacement {
        tab.parentTabId.map { .existing($0) } ?? .loose
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if movableTabs.isEmpty {
                        Text("No hay pestañas para organizar.").foregroundStyle(.secondary)
                    }
                    ForEach(movableTabs, id: \.id) { tab in
                        Picker(selection: Binding(
                            get: { placements[tab.id] ?? currentPlacement(tab) },
                            set: { placements[tab.id] = $0 }
                        )) {
                            ForEach(options, id: \.placement) { option in
                                Text(option.title).tag(option.placement)
                            }
                        } label: {
                            Text(tab.title)
                        }
                        .accessibilityLabel("Evaluación de \(tab.title)")
                    }
                } header: {
                    Text("Pestañas")
                } footer: {
                    Text("Meter una pestaña en una evaluación no mueve ni borra ninguna nota: sus notas salen también en el Resumen.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Organizar pestañas")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let changed = placements.filter { id, placement in
                            guard let tab = tabs.first(where: { $0.id == id }) else { return false }
                            return placement != currentPlacement(tab)
                        }
                        onSave(changed)
                        dismiss()
                    }
                    .disabled(placements.isEmpty)
                }
            }
        }
    }
}

// MARK: - Campo de porcentaje

struct NotebookPercentField: View {
    @Binding var text: String
    let accessibilityName: String

    var body: some View {
        HStack(spacing: 4) {
            TextField("Igual", text: $text)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .frame(minWidth: 56, maxWidth: 80)
                .accessibilityLabel("\(accessibilityName), por ciento")
            Text("%").foregroundStyle(.secondary).accessibilityHidden(true)
        }
    }
}

enum NotebookWeightText {
    /// «60», «33,3», «33.3» → número de 0 a 100. Vacío o fuera de rango → `nil`.
    static func parse(_ text: String) -> Double? {
        let clean = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(clean), value >= 0, value <= 100 else { return nil }
        return value
    }

    static func format(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded).replacingOccurrences(of: ".", with: ",")
    }
}
