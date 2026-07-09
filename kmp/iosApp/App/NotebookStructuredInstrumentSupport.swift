import SwiftUI
import MiGestorKit

extension NotebookCellInputKind {
    var isStructuredInstrument: Bool {
        switch self {
        case .structuredChecklist, .structuredObservation, .structuredForm, .structuredQuiz:
            return true
        default:
            return false
        }
    }
}

struct StructuredInstrumentEvaluationRequest: Identifiable {
    let id: String
    let classId: Int64
    let studentId: Int64
    let studentName: String
    let columnId: String
    let title: String
}

struct StructuredInstrumentEvaluationSheet: View {
    @ObservedObject var bridge: KmpBridge
    let request: StructuredInstrumentEvaluationRequest
    let onSaved: () -> Void
    let onClose: () -> Void

    @State private var model: StructuredInstrumentEvaluationModel?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    NotebookContentUnavailableView("No se pudo abrir el instrumento", systemImage: "exclamationmark.triangle", description: errorMessage)
                } else if model != nil {
                    let binding = Binding<StructuredInstrumentEvaluationModel>(
                        get: { model! },
                        set: { model = $0 }
                    )
                    formContent(binding)
                } else {
                    NotebookContentUnavailableView("Sin plantilla", systemImage: "doc.badge.gearshape", description: "Esta columna todavía no tiene plantilla estructurada.")
                }
            }
            .navigationTitle(request.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar", action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Label("Guardar", systemImage: "checkmark.circle.fill")
                        }
                    }
                    .disabled(isSaving || model == nil)
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 620, minHeight: 560)
#else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#endif
        .task { await load() }
    }

    private func formContent(_ model: Binding<StructuredInstrumentEvaluationModel>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(request.studentName)
                        .font(.title2.weight(.bold))
                    Text(progressText(for: model.wrappedValue))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let description = model.wrappedValue.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Guía e Información del Instrumento", systemImage: "info.circle.fill")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(NotebookStyle.primaryTint)
                        Text(description)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(NotebookStyle.primaryTint.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(NotebookStyle.primaryTint.opacity(0.18), lineWidth: 1)
                    )
                }

                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(groupedItems(model.wrappedValue.items).enumerated()), id: \.offset) { _, group in
                        VStack(alignment: .leading, spacing: 10) {
                            if let header = group.header {
                                HStack {
                                    Text(header)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(NotebookStyle.primaryTint)
                                    Spacer()
                                    if let average = groupAverage(group.items) {
                                        Text("Media: \(average, specifier: "%.1f")")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            VStack(spacing: 16) {
                                ForEach(group.items) { item in
                                    StructuredInstrumentItemEditor(item: itemBinding(for: item, in: model))
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    // Agrupa items por el prefijo de titulo antes del separador " · " (convencion
    // usada por instrumentos con estructura fila x indicador, ej. la rejilla de
    // observacion "S3 - inicio · Tecnica"). Los items sin ese separador quedan sin
    // agrupar, igual que antes de este cambio.
    private func groupedItems(_ items: [StructuredInstrumentEvaluationItem]) -> [(header: String?, items: [StructuredInstrumentEvaluationItem])] {
        var order: [String] = []
        var buckets: [String: [StructuredInstrumentEvaluationItem]] = [:]
        var ungrouped: [StructuredInstrumentEvaluationItem] = []
        for item in items {
            guard let separatorRange = item.title.range(of: " · ") else {
                ungrouped.append(item)
                continue
            }
            let header = String(item.title[..<separatorRange.lowerBound])
            if buckets[header] == nil { order.append(header) }
            buckets[header, default: []].append(item)
        }
        var result = order.map { (header: Optional($0), items: buckets[$0] ?? []) }
        if !ungrouped.isEmpty { result.append((header: nil, items: ungrouped)) }
        return result
    }

    private func groupAverage(_ items: [StructuredInstrumentEvaluationItem]) -> Double? {
        let values = items.compactMap { Double($0.numberValue.replacingOccurrences(of: ",", with: ".")) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func itemBinding(for item: StructuredInstrumentEvaluationItem, in model: Binding<StructuredInstrumentEvaluationModel>) -> Binding<StructuredInstrumentEvaluationItem> {
        Binding(
            get: { model.wrappedValue.items.first(where: { $0.id == item.id }) ?? item },
            set: { newValue in
                guard let index = model.wrappedValue.items.firstIndex(where: { $0.id == item.id }) else { return }
                model.wrappedValue.items[index] = newValue
            }
        )
    }

    private func progressText(for model: StructuredInstrumentEvaluationModel) -> String {
        let total = model.items.count
        let completed = model.items.filter(isCompleted).count
        return completed == total && total > 0 ? "Evaluación completa" : "\(completed)/\(total) ítems respondidos"
    }

    private func isCompleted(_ item: StructuredInstrumentEvaluationItem) -> Bool {
        switch item.type {
        case .check:
            return item.boolValue
        case .text, .choice:
            return !item.textValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .number, .scale14:
            return Double(item.numberValue.replacingOccurrences(of: ",", with: ".")) != nil
        default:
            return false
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            model = try await bridge.loadStructuredInstrumentEvaluation(
                classId: request.classId,
                studentId: request.studentId,
                columnId: request.columnId
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func save() async {
        guard let model else { return }
        isSaving = true
        errorMessage = nil
        do {
            _ = try await bridge.saveStructuredInstrumentEvaluation(model)
            onSaved()
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

private struct StructuredInstrumentItemEditor: View {
    @Binding var item: StructuredInstrumentEvaluationItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title)
                .font(.headline)
                .foregroundStyle(.primary)

            switch item.type {
            case .check:
                Button {
                    item.boolValue.toggle()
                } label: {
                    HStack {
                        Image(systemName: item.boolValue ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20))
                            .foregroundStyle(item.boolValue ? NotebookStyle.primaryTint : .secondary)
                        Text(item.boolValue ? "Completado" : "Marcar como completado")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(item.boolValue ? .primary : .secondary)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            case .choice:
                if !item.options.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(item.options, id: \.self) { option in
                            let isSelected = item.textValue == option
                            Button {
                                item.textValue = option
                            } label: {
                                HStack {
                                    Text(option)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(isSelected ? NotebookStyle.primaryTint : .primary)
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(NotebookStyle.primaryTint)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(.secondary.opacity(0.5))
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isSelected ? NotebookStyle.primaryTint.opacity(0.08) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(isSelected ? NotebookStyle.primaryTint : NotebookStyle.softBorder, lineWidth: 1.5)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                } else {
                    TextField("Escribe respuesta...", text: $item.textValue)
                        .textFieldStyle(.roundedBorder)
                }
            case .number:
                TextField("Valor numérico", text: $item.numberValue)
                    .textFieldStyle(.roundedBorder)
            case .scale14:
                HStack(spacing: 8) {
                    ForEach(["1", "2", "3", "4"], id: \.self) { level in
                        let isSelected = item.numberValue == level
                        let color = levelColor(for: level)
                        Button {
                            item.numberValue = level
                        } label: {
                            VStack(spacing: 4) {
                                Text(level)
                                    .font(.title3.bold())
                                Text(levelTitle(for: level))
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? color.opacity(0.12) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(isSelected ? color : NotebookStyle.softBorder, lineWidth: isSelected ? 2 : 1)
                            )
                            .foregroundStyle(isSelected ? color : .secondary)
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            default:
                TextField("Respuesta de texto", text: $item.textValue, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(16)
        .background(NotebookStyle.surfaceSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(NotebookStyle.softBorder.opacity(0.35), lineWidth: 1)
        )
    }

    private func levelColor(for level: String) -> Color {
        switch level {
        case "1": return .red
        case "2": return .orange
        case "3": return .blue
        case "4": return .green
        default: return .secondary
        }
    }

    private func levelTitle(for level: String) -> String {
        switch level {
        case "1": return "Insuf"
        case "2": return "Sufi"
        case "3": return "Notab"
        case "4": return "Sobre"
        default: return ""
        }
    }
}
