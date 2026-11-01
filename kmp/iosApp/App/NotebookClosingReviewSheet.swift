import SwiftUI
import MiGestorKit

/// Adónde lleva un aviso de «Revisar cierre».
enum NotebookClosingTarget: Equatable {
    case cell(studentId: Int64, columnId: String)
    case row(studentId: Int64)
    case hiddenColumns
}

/// Hoja de solo lectura que lista lo que falta en el grupo antes de cerrar la evaluación.
/// No cambia ninguna nota ni la Media. Compartida por iOS, iPad y macOS.
struct NotebookClosingReviewSheet: View {
    let contextText: String
    let loadReport: () async throws -> NotebookClosingReport
    let onSelect: (NotebookClosingTarget) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum Phase {
        case loading
        case loaded(NotebookClosingReport)
        case failed
    }

    @State private var phase: Phase = .loading
    /// El esqueleto solo aparece si la carga tarda más de medio segundo.
    @State private var showsSkeleton = false
    @State private var loadAttempt = 0

    private static let skeletonDelay: UInt64 = 500_000_000

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Revisar cierre")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Cerrar") { dismiss() }
                    }
                }
        }
        .task(id: loadAttempt) { await load() }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    // MARK: - Estados

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            if showsSkeleton {
                skeleton
            } else {
                Color.clear
            }
        case .failed:
            centeredMessage(
                symbol: "exclamationmark.circle.fill",
                tint: .red,
                title: "No se pudo revisar el grupo",
                detail: "Tus notas no han cambiado. Prueba otra vez.",
                showsRetry: true
            )
        case .loaded(let report):
            if !report.hasCountingColumns {
                centeredMessage(
                    symbol: "tablecells",
                    tint: .secondary,
                    title: "Aún no hay notas que revisar",
                    detail: "Este grupo no tiene columnas que cuenten para la Media.",
                    showsRetry: false
                )
            } else if report.issues.isEmpty {
                centeredMessage(
                    symbol: "checkmark.circle.fill",
                    tint: .green,
                    title: "Todo listo para cerrar",
                    detail: "Todas las notas que cuentan están puestas y se leen bien.",
                    showsRetry: false
                )
            } else {
                reportList(report)
            }
        }
    }

    private func load() async {
        phase = .loading
        showsSkeleton = false
        let skeletonTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.skeletonDelay)
            if !Task.isCancelled, case .loading = phase { showsSkeleton = true }
        }
        defer { skeletonTask.cancel() }
        do {
            let report = try await loadReport()
            phase = .loaded(report)
            announce(report)
        } catch {
            if Task.isCancelled { return }
            phase = .failed
            AccessibilityNotification.Announcement("No se pudo revisar el grupo").post()
        }
    }

    private func announce(_ report: NotebookClosingReport) {
        let message: String
        if !report.hasCountingColumns {
            message = "Aún no hay notas que revisar"
        } else if report.issues.isEmpty {
            message = "Todo listo para cerrar"
        } else {
            message = Self.avisosText(Int(report.totalCount))
        }
        AccessibilityNotification.Announcement(message).post()
    }

    // MARK: - Lista

    private func reportList(_ report: NotebookClosingReport) -> some View {
        List {
            Section {
                summary(report)
                    .listRowBackground(Color.orange.opacity(0.15))
            } header: {
                Text(contextText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }

            ForEach(Self.sectionOrder, id: \.title) { spec in
                let issues = report.issuesOf(kind: spec.kind)
                if !issues.isEmpty {
                    Section {
                        ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                            row(for: issue)
                        }
                    } header: {
                        sectionHeader(title: spec.title, count: Int(report.countOf(kind: spec.kind)))
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    private struct SectionSpec {
        let kind: ClosingIssueKind
        let title: String
    }

    private static let sectionOrder: [SectionSpec] = [
        SectionSpec(kind: .emptyGrade, title: "Notas vacías"),
        SectionSpec(kind: .noAverage, title: "Sin Media"),
        SectionSpec(kind: .notUnderstood, title: "Notas que no se entienden"),
        SectionSpec(kind: .criterionWithoutGrade, title: "Criterios sin nota"),
        SectionSpec(kind: .hiddenColumn, title: "Columnas ocultas que cuentan en la Media")
    ]

    private func summary(_ report: NotebookClosingReport) -> some View {
        let total = Int(report.totalCount)
        let empties = Int(report.countOf(kind: .emptyGrade))
        let others = total - empties
        return HStack(alignment: .top, spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.avisosText(total))
                    .font(.headline)
                Text(Self.summaryDetail(empties: empties, others: others))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    Text("\(count)")
                }
            } else {
                HStack {
                    Text(title)
                    Spacer()
                    Text("\(count)")
                        .accessibilityLabel("\(count) en total")
                }
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(nil)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Filas

    private func row(for issue: ClosingIssue) -> some View {
        let model = RowModel(issue: issue)
        return Button {
            handleTap(issue)
            dismiss()
        } label: {
            rowLayout(model)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityHint(model.accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func rowLayout(_ model: RowModel) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                rowTexts(model)
                if let trailing = model.trailing {
                    Text(trailing)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        } else {
            HStack(spacing: 16) {
                rowTexts(model)
                Spacer(minLength: 8)
                if let trailing = model.trailing {
                    Text(trailing)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
    }

    private func rowTexts(_ model: RowModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Text(model.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    private func handleTap(_ issue: ClosingIssue) {
        if issue.kind == .hiddenColumn {
            onSelect(.hiddenColumns)
            return
        }
        guard let student = issue.students.first else { return }
        if let columnId = issue.columnId {
            onSelect(.cell(studentId: student.id, columnId: columnId))
        } else {
            onSelect(.row(studentId: student.id))
        }
    }

    // MARK: - Esqueleto y mensajes

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Revisando el grupo…")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.updatesFrequently)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary)
                .frame(height: 72)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary)
                .frame(width: 120, height: 16)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary)
                .frame(height: 112)
            Spacer(minLength: 0)
        }
        .padding(24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Revisando el grupo")
    }

    private func centeredMessage(
        symbol: String,
        tint: Color,
        title: String,
        detail: String,
        showsRetry: Bool
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
                .padding(.bottom, 8)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if showsRetry {
                Button("Reintentar") { loadAttempt += 1 }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 16)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Textos

    static func avisosText(_ count: Int) -> String {
        count == 1 ? "1 aviso" : "\(count) avisos"
    }

    private static func summaryDetail(empties: Int, others: Int) -> String {
        let emptyText = empties == 1 ? "1 nota vacía" : "\(empties) notas vacías"
        let otherText = others == 1 ? "1 cosa más que revisar" : "\(others) cosas más que revisar"
        switch (empties > 0, others > 0) {
        case (true, true): return "\(emptyText) y \(otherText)"
        case (true, false): return emptyText
        default: return others == 1 ? "1 cosa que revisar" : "\(others) cosas que revisar"
        }
    }

    /// Textos de una fila ya resueltos, para la vista y para VoiceOver.
    private struct RowModel {
        let title: String
        let subtitle: String
        let trailing: String?
        let accessibilityLabel: String
        let accessibilityHint: String

        init(issue: ClosingIssue) {
            let names = issue.students.map(\.name)
            let student = names.first ?? ""
            let columnTitle = issue.title
            if issue.kind == .emptyGrade {
                let count = names.count
                let summary = Self.namesSummary(names)
                title = columnTitle
                subtitle = summary
                trailing = count == 1 ? "1 vacía" : "\(count) vacías"
                accessibilityLabel = "\(columnTitle), \(count == 1 ? "1 nota vacía" : "\(count) notas vacías"): \(names.joined(separator: ", "))"
                accessibilityHint = "Abre la celda"
            } else if issue.kind == .noAverage {
                title = student
                subtitle = "No tiene ninguna nota que cuente"
                trailing = nil
                accessibilityLabel = "\(student), sin Media: no tiene ninguna nota que cuente"
                accessibilityHint = "Abre su fila"
            } else if issue.kind == .notUnderstood {
                let text = issue.text ?? ""
                title = "\(student) · \(columnTitle)"
                subtitle = "Pone «\(text)». No cuenta en la Media."
                trailing = nil
                accessibilityLabel = "\(student), \(columnTitle): pone «\(text)», no cuenta en la Media"
                accessibilityHint = "Abre la celda"
            } else if issue.kind == .criterionWithoutGrade {
                let count = Int(issue.instrumentCount)
                let instruments = count == 1 ? "en su instrumento" : "en sus \(count) instrumentos"
                title = "\(columnTitle) · \(student)"
                subtitle = "Ninguna nota \(instruments)"
                trailing = nil
                accessibilityLabel = "Criterio \(columnTitle), \(student): ninguna nota \(instruments)"
                accessibilityHint = "Abre la celda"
            } else {
                let weight = Self.weightText(issue.weight?.doubleValue)
                title = columnTitle
                subtitle = "Oculta, pero pesa un \(weight) % en la Media."
                trailing = nil
                accessibilityLabel = "\(columnTitle): oculta, pero pesa un \(weight) % en la Media"
                accessibilityHint = "Abre Columnas ocultas"
            }
        }

        /// Hasta tres nombres y «y N más».
        private static func namesSummary(_ names: [String]) -> String {
            let visible = 3
            guard names.count > visible else { return names.joined(separator: ", ") }
            let rest = names.count - visible
            return names.prefix(visible).joined(separator: ", ") + " y \(rest) más"
        }

        private static func weightText(_ weight: Double?) -> String {
            guard let weight else { return "0" }
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "es_ES")
            formatter.maximumFractionDigits = 1
            formatter.minimumFractionDigits = 0
            return formatter.string(from: NSNumber(value: weight)) ?? "\(weight)"
        }
    }
}
