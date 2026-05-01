import SwiftUI
import MiGestorKit

struct NotebookAverageColumnUpdate {
    let column: NotebookColumnDefinition
    let isIncluded: Bool
    let weight: Double
}

private struct NotebookAverageColumnDraft {
    var isIncluded: Bool
    var weightText: String
}

struct NotebookAverageEditorSheet: View {
    let classTitle: String
    let columns: [NotebookColumnDefinition]
    let rows: [NotebookRow]
    let onSave: ([NotebookAverageColumnUpdate]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftsByColumnId: [String: NotebookAverageColumnDraft]

    init(
        classTitle: String,
        columns: [NotebookColumnDefinition],
        rows: [NotebookRow],
        onSave: @escaping ([NotebookAverageColumnUpdate]) -> Void
    ) {
        self.classTitle = classTitle
        self.columns = columns
        self.rows = rows
        self.onSave = onSave
        _draftsByColumnId = State(initialValue: Dictionary(
            uniqueKeysWithValues: columns.map {
                ($0.id, NotebookAverageColumnDraft(
                    isIncluded: Self.initialIncludedState(for: $0),
                    weightText: Self.formatWeight($0.weight > 0 ? $0.weight : Self.defaultWeight(for: $0))
                ))
            }
        ))
    }

    private var configurableColumns: [NotebookColumnDefinition] {
        columns
            .filter { averageEligibility(for: $0) != .notEvaluable }
            .filter { !$0.isArchived }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    private var totalWeight: Double? {
        var total = 0.0
        for column in configurableColumns where draftsByColumnId[column.id]?.isIncluded == true {
            guard let value = parsedWeight(for: column) else { return nil }
            total += value
        }
        return total
    }

    private var selectedColumnCount: Int {
        configurableColumns.filter { draftsByColumnId[$0.id]?.isIncluded == true }.count
    }

    private var canSave: Bool {
        guard selectedColumnCount > 0, let totalWeight else { return false }
        return totalWeight > 0
    }

    private var validationState: AverageValidationState {
        guard selectedColumnCount > 0 else { return .error("Selecciona al menos una columna.") }
        guard let totalWeight else { return .error("Revisa los pesos antes de guardar.") }
        if totalWeight <= 0 { return .error("Los pesos no pueden sumar 0%.") }
        if abs(totalWeight - 100) <= 0.01 { return .ok("Total 100% listo.") }
        return .warning("Total \(Self.formatWeight(totalWeight))%. Puedes guardar o normalizar a 100%.")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        if configurableColumns.isEmpty {
                            emptyState
                        } else {
                            columnsSection
                            previewSection
                        }
                    }
                    .padding(24)
                }

                Divider()

                footer
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
            .background(EvaluationBackdrop())
            .navigationTitle("Editar media")
            .appInlineNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(buildUpdates())
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var header: some View {
        NotebookSurface(cornerRadius: NotebookStyle.cardRadius, fill: NotebookStyle.surfaceMuted, padding: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "percent")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Media de \(classTitle)")
                        .font(.title2.weight(.bold))
                    Text("Elige qué columnas entran, ajusta sus pesos y revisa el resultado por alumno antes de guardar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    private var columnsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Columnas evaluables")
                    .font(.headline)
                Spacer()
                Text("\(selectedColumnCount) seleccionadas")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(configurableColumns, id: \.id) { column in
                    columnRow(column)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "percent")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Sin columnas evaluables")
                .font(.headline)
            Text("Crea columnas numéricas, rúbricas o notas baremadas para configurar la media.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: CGFloat.infinity, minHeight: 260)
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Preview")
                    .font(.headline)
                Spacer()
                Text(previewSubtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            NotebookSurface(cornerRadius: 12, fill: NotebookStyle.surface, padding: 0) {
                VStack(spacing: 0) {
                    ForEach(previewRows.prefix(6), id: \.studentId) { row in
                        HStack(spacing: 12) {
                            Text(row.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                            Text(row.valueText)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(row.value == nil ? .secondary : .primary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        if row.studentId != previewRows.prefix(6).last?.studentId {
                            Divider()
                        }
                    }

                    if previewRows.isEmpty {
                        Text("No hay datos suficientes para previsualizar.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 72)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Label(validationState.message, systemImage: validationState.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(validationState.tint)
                .lineLimit(2)

            Spacer()

            Button("Normalizar a 100%") {
                normalizeWeights()
            }
            .buttonStyle(.bordered)
            .disabled(selectedColumnCount == 0 || totalWeight == nil || abs((totalWeight ?? 0) - 100) <= 0.01)

            Button("Cancelar") { dismiss() }
                .buttonStyle(.bordered)

            Button("Guardar") {
                onSave(buildUpdates())
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
        }
    }

    private func columnRow(_ column: NotebookColumnDefinition) -> some View {
        let draft = draftsByColumnId[column.id] ?? NotebookAverageColumnDraft(isIncluded: false, weightText: "0")
        let isIncluded = draft.isIncluded
        let eligibility = averageEligibility(for: column)

        return NotebookSurface(cornerRadius: 10, fill: NotebookStyle.surface, padding: 14) {
            HStack(spacing: 14) {
                Toggle("", isOn: Binding(
                    get: { draftsByColumnId[column.id]?.isIncluded == true },
                    set: { setIncluded($0, for: column) }
                ))
                .labelsHidden()
                .disabled(eligibility == .notEvaluable)

                VStack(alignment: .leading, spacing: 4) {
                    Text(column.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(eligibility.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(eligibility.tint)
                }

                Spacer(minLength: 10)

                if isIncluded {
                    TextField("0", text: Binding(
                        get: { draftsByColumnId[column.id]?.weightText ?? "0" },
                        set: { setWeightText($0, for: column) }
                    ))
                    .appKeyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)

                    Text("%")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Stepper("", value: weightBinding(for: column), in: 0...100, step: 5)
                        .labelsHidden()
                } else {
                    Text(eligibility.excludedLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 92, alignment: .trailing)
                }
            }
        }
    }

    private var previewRows: [AveragePreviewRow] {
        let includedColumns = configurableColumns.filter { draftsByColumnId[$0.id]?.isIncluded == true }
        guard !includedColumns.isEmpty else { return [] }

        return rows.map { row in
            let average = previewAverage(for: row, columns: includedColumns)
            return AveragePreviewRow(
                studentId: row.student.id,
                name: "\(row.student.firstName) \(row.student.lastName)",
                value: average
            )
        }
    }

    private var previewSubtitle: String {
        if previewRows.contains(where: { $0.value != nil }) {
            return "con datos actuales"
        }
        return "sin notas suficientes"
    }

    private func previewAverage(for row: NotebookRow, columns: [NotebookColumnDefinition]) -> Double? {
        var weightedSum = 0.0
        var total = 0.0
        var hasAnyValue = false

        for column in columns {
            guard let weight = parsedWeight(for: column), weight > 0 else { continue }
            let value = numericValue(for: row, column: column)
            if value != nil { hasAnyValue = true }
            weightedSum += (value ?? 0) * weight
            total += weight
        }

        guard hasAnyValue, total > 0 else { return nil }
        return weightedSum / total
    }

    private func numericValue(for row: NotebookRow, column: NotebookColumnDefinition) -> Double? {
        if let value = row.persistedGrades.first(where: { $0.columnId == column.id })?.value?.doubleValue {
            return value
        }
        if column.type == .check,
           let value = row.persistedCells.first(where: { $0.columnId == column.id })?.boolValue?.boolValue {
            return value ? 10 : 0
        }
        if let evaluationId = column.evaluationId?.int64Value,
           let value = row.cells.first(where: { $0.evaluationId == evaluationId })?.value?.doubleValue {
            return value
        }
        return nil
    }

    private func buildUpdates() -> [NotebookAverageColumnUpdate] {
        let configurableIds = Set(configurableColumns.map(\.id))
        return columns.map { column in
            let isIncluded = configurableIds.contains(column.id) && draftsByColumnId[column.id]?.isIncluded == true
            return NotebookAverageColumnUpdate(
                column: column,
                isIncluded: isIncluded,
                weight: isIncluded ? (parsedWeight(for: column) ?? 0) : 0
            )
        }
    }

    private func setIncluded(_ isIncluded: Bool, for column: NotebookColumnDefinition) {
        var draft = draftsByColumnId[column.id] ?? NotebookAverageColumnDraft(isIncluded: false, weightText: "0")
        draft.isIncluded = isIncluded
        if isIncluded, (parsedWeight(from: draft.weightText) ?? 0) == 0 {
            draft.weightText = Self.formatWeight(Self.defaultWeight(for: column))
        }
        draftsByColumnId[column.id] = draft
    }

    private func setWeightText(_ text: String, for column: NotebookColumnDefinition) {
        var draft = draftsByColumnId[column.id] ?? NotebookAverageColumnDraft(isIncluded: false, weightText: "0")
        draft.weightText = text
        draftsByColumnId[column.id] = draft
    }

    private func weightBinding(for column: NotebookColumnDefinition) -> Binding<Double> {
        Binding(
            get: { parsedWeight(for: column) ?? 0 },
            set: { setWeightText(Self.formatWeight($0), for: column) }
        )
    }

    private func normalizeWeights() {
        let includedColumns = configurableColumns.filter { draftsByColumnId[$0.id]?.isIncluded == true }
        guard !includedColumns.isEmpty else { return }
        let currentTotal = includedColumns.compactMap { parsedWeight(for: $0) }.reduce(0, +)

        if currentTotal > 0 {
            includedColumns.forEach { column in
                let current = parsedWeight(for: column) ?? 0
                setWeightText(Self.formatWeight((current / currentTotal) * 100), for: column)
            }
        } else {
            let equalWeight = 100.0 / Double(includedColumns.count)
            includedColumns.forEach { setWeightText(Self.formatWeight(equalWeight), for: $0) }
        }
    }

    private func parsedWeight(for column: NotebookColumnDefinition) -> Double? {
        parsedWeight(from: draftsByColumnId[column.id]?.weightText ?? "")
    }

    private func parsedWeight(from raw: String) -> Double? {
        let value = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let number = Double(value), number >= 0, number <= 100 else { return nil }
        return number
    }

    private func averageEligibility(for column: NotebookColumnDefinition) -> AverageEligibility {
        switch column.type {
        case .numeric:
            if column.instrumentKind == .physicalTest {
                return Self.isPhysicalRawMeasure(column) ? .excludedByDefault("Marca bruta") : .recommended("Nota baremada")
            }
            return .recommended("Numérica")
        case .rubric:
            return .recommended("Rúbrica")
        case .calculated:
            return .manual("Fórmula numérica")
        case .check:
            return .manual("Lista de control")
        default:
            return .notEvaluable
        }
    }

    private static func initialIncludedState(for column: NotebookColumnDefinition) -> Bool {
        guard column.countsTowardAverage else { return false }
        switch column.type {
        case .numeric, .rubric, .calculated:
            return !isPhysicalRawMeasure(column)
        case .check:
            return true
        default:
            return false
        }
    }

    private static func isPhysicalRawMeasure(_ column: NotebookColumnDefinition) -> Bool {
        guard column.instrumentKind == .physicalTest else { return false }
        switch column.scaleKind {
        case .time, .distance, .repetitions:
            return true
        default:
            return false
        }
    }

    private static func defaultWeight(for column: NotebookColumnDefinition) -> Double {
        switch column.type {
        case .rubric:
            return 20
        case .calculated:
            return 10
        default:
            return 10
        }
    }

    private static func formatWeight(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

private enum AverageValidationState {
    case ok(String)
    case warning(String)
    case error(String)

    var message: String {
        switch self {
        case .ok(let message), .warning(let message), .error(let message):
            return message
        }
    }

    var systemImage: String {
        switch self {
        case .ok:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ok:
            return NotebookStyle.successTint
        case .warning:
            return NotebookStyle.warningTint
        case .error:
            return .red
        }
    }
}

private enum AverageEligibility: Equatable {
    case recommended(String)
    case manual(String)
    case excludedByDefault(String)
    case notEvaluable

    var label: String {
        switch self {
        case .recommended(let label):
            return label
        case .manual(let label):
            return "\(label) · manual"
        case .excludedByDefault(let label):
            return "\(label) · excluida por defecto"
        case .notEvaluable:
            return "No evaluable"
        }
    }

    var excludedLabel: String {
        switch self {
        case .notEvaluable:
            return "No evaluable"
        default:
            return "Excluida"
        }
    }

    var tint: Color {
        switch self {
        case .recommended:
            return NotebookStyle.successTint
        case .manual:
            return Color.accentColor
        case .excludedByDefault:
            return NotebookStyle.warningTint
        case .notEvaluable:
            return .secondary
        }
    }
}

private struct AveragePreviewRow {
    let studentId: Int64
    let name: String
    let value: Double?

    var valueText: String {
        guard let value else { return "-" }
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
