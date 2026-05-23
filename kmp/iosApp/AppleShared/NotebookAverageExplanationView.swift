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

                        if !explanation.included.isEmpty {
                            sectionHeader(title: "Incluye", icon: "plus.circle.fill", color: NotebookStyle.successTint)
                            ForEach(explanation.included, id: \.columnId) { contribution in
                                contributionRow(contribution)
                            }
                        }

                        if !explanation.excluded.isEmpty {
                            sectionHeader(title: "No incluye", icon: "minus.circle.fill", color: .secondary)
                            ForEach(explanation.excluded, id: \.columnId) { exclusion in
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
        let included = explanation.included.count
        let pending = explanation.excluded.filter { $0.reason == .empty }.count
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

    private func contributionRow(_ c: NotebookAverageContribution) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title)
                    .font(.system(size: 13, weight: .medium))
                Text("Peso \(formattedDecimal(c.weight))%")
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

    private func exclusionRow(_ e: NotebookAverageExclusion) -> some View {
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
