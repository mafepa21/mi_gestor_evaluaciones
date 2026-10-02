import SwiftUI

struct PhysicalTestsImportPreviewSheet: View {
    let draft: PhysicalTestsImportDraft
    let cancel: () -> Void
    let confirm: (PhysicalTestsImportDraft) -> Void

    @State private var editableDraft: PhysicalTestsImportDraft

    init(
        draft: PhysicalTestsImportDraft,
        cancel: @escaping () -> Void,
        confirm: @escaping (PhysicalTestsImportDraft) -> Void
    ) {
        self.draft = draft
        self.cancel = cancel
        self.confirm = confirm
        _editableDraft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Resumen") {
                    LabeledContent("Batería", value: editableDraft.assignmentTemplate.batteryName)
                    LabeledContent("Curso", value: editableDraft.learningSituation.course)
                    LabeledContent("Propósito", value: "Diagnóstico inicial")
                    LabeledContent("Pruebas", value: "\(editableDraft.testDefinitions.count)")
                    Label(
                        editableDraft.scoreIsDisabled
                            ? "Se guardarán solo marcas brutas; no habrá nota ni media."
                            : "La configuración incluye captura de puntuación.",
                        systemImage: editableDraft.scoreIsDisabled ? "checkmark.circle" : "chart.bar"
                    )
                    .foregroundStyle(editableDraft.scoreIsDisabled ? .green : .orange)
                }

                Section("Pruebas") {
                    ForEach($editableDraft.testDefinitions) { $definition in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Nombre", text: $definition.name)
                                .font(.body.weight(.semibold))
                            Text("\(definition.measurementKind) · \(definition.unit) · \(definition.attempts) intentos · \(definition.resultMode)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if !definition.protocolText.isEmpty {
                                Text(definition.protocolText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if !editableDraft.referenceScales.isEmpty {
                    Section("Escalas de referencia") {
                        ForEach(editableDraft.referenceScales) { scale in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(scale.name)
                                    .font(.body.weight(.semibold))
                                let detail = scale.scoring?.mode == "LINEAR"
                                    ? "\(scale.scoring?.points.count ?? 0) puntos · puntuación gradual"
                                    : "\(scale.ranges.count) rangos · puntuación por tramos"
                                Text("\(sexLabel(scale.sex)) · \(detail) · solo referencia diagnóstica")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !editableDraft.calibrationRequiredTestIds.isEmpty {
                    Section("Pendientes de calibración") {
                        ForEach(editableDraft.calibrationRequiredTestIds, id: \.self) { testId in
                            Label(testId, systemImage: "wrench.and.screwdriver")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Text("Estas pruebas se importan como dato bruto hasta validar un baremo específico para su protocolo.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !editableDraft.warnings.isEmpty {
                    Section("Avisos") {
                        ForEach(editableDraft.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Revisar pruebas físicas")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importar") {
                        confirm(editableDraft)
                    }
                    .disabled(editableDraft.testDefinitions.isEmpty || editableDraft.testDefinitions.contains { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 620)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func sexLabel(_ sex: String?) -> String {
        switch sex?.uppercased() {
        case "MALE", "M", "H", "HOMBRE", "MASCULINO": return "Hombre"
        case "FEMALE", "F", "MUJER", "FEMENINO": return "Mujer"
        default: return "Neutro"
        }
    }
}
