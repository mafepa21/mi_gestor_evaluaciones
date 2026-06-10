import SwiftUI
import MiGestorKit

struct NotebookAverageExplanationItem: Identifiable {
    let id: String
    let studentName: String
    let explanation: NotebookAverageExplanation?
    
    init(id: String, studentName: String, explanation: NotebookAverageExplanation?) {
        self.id = id
        self.studentName = studentName
        self.explanation = explanation
    }
}

struct NotebookAverageExplanationView: View {
    let studentName: String
    let explanation: NotebookAverageExplanation?

    init(studentName: String, explanation: NotebookAverageExplanation?) {
        self.studentName = studentName
        self.explanation = explanation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let explanation = explanation {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        resultSection(explanation)

                        if !explanation.weightedContributions.isEmpty {
                            sectionHeader(title: "Incluye", icon: "plus.circle.fill", color: NotebookStyle.successTint)
                            ForEach(explanation.weightedContributions, id: \.columnId) { contribution in
                                contributionRow(contribution)
                            }
                        }

                        if !explanation.pendingCells.isEmpty {
                            sectionHeader(title: "Pendiente", icon: "clock.fill", color: NotebookStyle.warningTint)
                            ForEach(explanation.pendingCells, id: \.columnId) { pending in
                                pendingRow(pending)
                            }
                        }

                        if !explanation.excludedColumns.isEmpty {
                            sectionHeader(title: "No incluye", icon: "minus.circle.fill", color: .secondary)
                            ForEach(explanation.excludedColumns, id: \.columnId) { exclusion in
                                exclusionRow(exclusion)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            } else {
                Text("No hay datos de cálculo disponibles.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .padding(.vertical, 16)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Media de \(studentName)")
                .font(.headline)
            if let average = explanation?.average {
                Text("Resultado: \(formattedDecimal(average.doubleValue))")
                    .font(.title2.bold())
                    .foregroundStyle(NotebookStyle.primaryTint)
            } else {
                Text("Resultado: --")
                    .font(.title2.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
    }

    private func resultSection(_ explanation: NotebookAverageExplanation) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Resultado")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(resultDetailText(explanation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(explanation.average.map { formattedDecimal($0.doubleValue) } ?? "--")
                .font(.title3.bold())
                .foregroundStyle(explanation.average == nil ? .secondary : NotebookStyle.primaryTint)
                .monospacedDigit()
        }
        .padding(12)
        .background(NotebookStyle.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func resultDetailText(_ explanation: NotebookAverageExplanation) -> String {
        let included = explanation.includedColumns.count
        let pending = explanation.pendingCells.count
        if included == 0 { return "Sin columnas con datos suficientes." }
        if pending == 0 { return "\(included) columnas incluidas." }
        return "\(included) incluidas · \(pending) pendientes."
    }

    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func contributionRow(_ c: WeightedContribution) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title)
                    .font(.system(size: 13, weight: .medium))
                Text("Peso \(formattedDecimal(c.weight))% · aporta \(formattedDecimal(c.weightedValue))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(formattedDecimal(c.value))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(NotebookStyle.primaryTint)
        }
        .padding(10)
        .background(NotebookStyle.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func pendingRow(_ p: PendingCell) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.title)
                    .font(.system(size: 13, weight: .medium))
                Text("Celda vacía · peso previsto \(formattedDecimal(p.expectedWeight))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            Spacer()
            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(NotebookStyle.warningTint)
        }
        .padding(10)
        .background(NotebookStyle.warningTint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func exclusionRow(_ e: ExcludedColumn) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(exclusionReasonText(e.reason))
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            Spacer()
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.5))
        }
        .padding(10)
        .background(NotebookStyle.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func exclusionReasonText(_ reason: NotebookAverageExclusionReason) -> String {
        switch reason {
        case .empty: return "Pendiente"
        case .columnDoesNotCount: return "No cuenta para media"
        case .rawValueOnly: return "Marca bruta"
        case .lockedOrArchived: return "Bloqueado / Archivado"
        case .nonNumeric: return "Dato no numérico"
        default: return "Excluido"
        }
    }

    private func formattedDecimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}

struct NotebookAverageCompactSummaryView: View {
    let explanation: NotebookAverageExplanation?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(explanation?.average.map { formattedDecimal($0.doubleValue) } ?? "--")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(explanation?.average == nil ? .secondary : NotebookStyle.primaryTint)
                    .monospacedDigit()

                Text(summaryText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)
            }

            if let explanation {
                HStack(spacing: 8) {
                    metricChip(
                        title: "Entran",
                        value: "\(explanation.includedColumns.count)",
                        tint: NotebookStyle.successTint
                    )
                    metricChip(
                        title: "Pendientes",
                        value: "\(explanation.pendingCells.count)",
                        tint: NotebookStyle.warningTint
                    )
                    metricChip(
                        title: "Fuera",
                        value: "\(explanation.excludedColumns.count)",
                        tint: .secondary
                    )
                }

                if let topContribution = explanation.weightedContributions.max(by: { abs($0.weightedValue) < abs($1.weightedValue) }) {
                    Text("Mayor señal: \(topContribution.title) · \(formattedDecimal(topContribution.value)) con peso \(formattedDecimal(topContribution.weight))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryText: String {
        guard let explanation else { return "Sin cálculo disponible" }
        if explanation.average == nil { return "Datos insuficientes" }
        if explanation.pendingCells.isEmpty { return "Media consolidada" }
        return "Media provisional"
    }

    private func metricChip(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func formattedDecimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}

struct NotebookAverageExplanationPresentationModifier: ViewModifier {
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Binding var item: NotebookAverageExplanationItem?

    init(item: Binding<NotebookAverageExplanationItem?>) {
        self._item = item
    }

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .popover(item: $item) { explanationItem in
                popoverContent(for: explanationItem)
            }
        #else
        if horizontalSizeClass == .compact {
            content
                .sheet(item: $item) { explanationItem in
                    sheetContent(for: explanationItem)
                }
        } else {
            content
                .popover(item: $item) { explanationItem in
                    popoverContent(for: explanationItem)
                }
        }
        #endif
    }

    @ViewBuilder
    private func popoverContent(for explanationItem: NotebookAverageExplanationItem) -> some View {
        NotebookAverageExplanationView(
            studentName: explanationItem.studentName,
            explanation: explanationItem.explanation
        )
        .frame(width: 320)
        #if os(macOS)
        .padding()
        #endif
    }

    @ViewBuilder
    private func sheetContent(for explanationItem: NotebookAverageExplanationItem) -> some View {
        NavigationStack {
            NotebookAverageExplanationView(
                studentName: explanationItem.studentName,
                explanation: explanationItem.explanation
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") {
                        item = nil
                    }
                }
            }
        }
        #if !os(macOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }
}

extension View {
    func notebookAverageExplanation(item: Binding<NotebookAverageExplanationItem?>) -> some View {
        self.modifier(NotebookAverageExplanationPresentationModifier(item: item))
    }
}
