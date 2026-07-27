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
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(request.studentName)
                            .font(.title2.weight(.bold))
                        HStack(spacing: 8) {
                            ProgressView(value: progressFraction(for: model.wrappedValue))
                                .tint(NotebookStyle.successTint)
                                .frame(maxWidth: 160)
                            Text(progressText(for: model.wrappedValue))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    let criteriaText = structuredCriteriaSummary(model: model.wrappedValue)
                    AssessmentCriteriaDisclosureView(rawText: criteriaText)
                }

                if let sessionGroups = observationSessionGroups(for: model.wrappedValue.items) {
                    ObservationGridInstrumentContent(model: model, groups: sessionGroups)
                } else {
                    NotebookSurface(padding: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(model.items) { $item in
                                StructuredInstrumentItemRow(item: $item)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private func progressText(for model: StructuredInstrumentEvaluationModel) -> String {
        let total = model.items.count
        let completed = model.items.filter(isCompleted).count
        return completed == total && total > 0 ? "Completo" : "\(completed)/\(total) campos completados"
    }

    private func progressFraction(for model: StructuredInstrumentEvaluationModel) -> Double {
        let total = model.items.count
        guard total > 0 else { return 0 }
        let completed = model.items.filter(isCompleted).count
        return Double(completed) / Double(total)
    }

    private func structuredCriteriaSummary(model: StructuredInstrumentEvaluationModel) -> String {
        var parts: [String] = [request.title]
        parts.append(contentsOf: model.items.map { $0.title })
        return parts.joined(separator: " · ")
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

private struct StructuredInstrumentItemRow: View {
    @Binding var item: StructuredInstrumentEvaluationItem

    var body: some View {
        switch item.type {
        case .check:
            Button {
                item.boolValue.toggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: item.boolValue ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(item.boolValue ? NotebookStyle.successTint : Color.secondary.opacity(0.35))
                    Text(item.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                }
            }
            .buttonStyle(.plain)
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                switch item.type {
                case .choice:
                    Picker("Respuesta", selection: $item.textValue) {
                        Text("Sin respuesta").tag("")
                        ForEach(item.options, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                case .number:
                    TextField("Valor", text: $item.numberValue)
                        .textFieldStyle(.roundedBorder)
                        .appKeyboardType(.decimalPad)
                case .scale14:
                    Picker("Nivel", selection: $item.numberValue) {
                        Text("Sin nivel").tag("")
                        ForEach(["1", "2", "3", "4"], id: \.self) { level in
                            Text(level).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                default:
                    TextField("Respuesta", text: $item.textValue, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }
}
