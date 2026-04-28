import SwiftUI

struct PhysicalTestCaptureView: View {
    @ObservedObject var bridge: KmpBridge
    let classId: Int64
    let test: KmpBridge.PhysicalTestSnapshot
    let scale: PhysicalTestScaleDraft?
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex = 0
    @State private var attempts: [String] = ["", "", ""]
    @State private var isSaving = false

    private var currentResult: KmpBridge.PhysicalTestSnapshot.StudentResult? {
        guard test.results.indices.contains(selectedIndex) else { return nil }
        return test.results[selectedIndex]
    }

    private var parsedAttempts: [Double] {
        attempts.compactMap { Double($0.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private var finalValue: Double? {
        parsedAttempts.max() ?? currentResult?.value
    }

    private var scorePreview: Double? {
        finalValue.flatMap { scale?.score(for: $0) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let currentResult {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(test.evaluation.name)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text("\(currentResult.student.firstName) \(currentResult.student.lastName)")
                                .font(.system(size: 42, weight: .black, design: .rounded))
                                .lineLimit(2)
                                .minimumScaleFactor(0.72)
                        }

                        HStack(spacing: 12) {
                            ForEach(0..<attempts.count, id: \.self) { index in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Intento \(index + 1)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    TextField("-", text: $attempts[index])
                                        .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                                        .appKeyboardType(.decimalPad)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(minHeight: 62)
                                }
                            }
                        }

                        HStack(spacing: 12) {
                            CaptureMetric(title: "Resultado", value: finalValue.map { PhysicalTestsFormatting.decimal($0) } ?? "-")
                            CaptureMetric(title: "Nota baremada", value: scorePreview.map { PhysicalTestsFormatting.decimal($0) } ?? "-")
                            CaptureMetric(title: "Alumno", value: "\(selectedIndex + 1)/\(test.results.count)")
                        }

                        Text("TODO(kmp-physical-tests): guardar intentos, rawText, baremo aplicado y score como PhysicalTestResult cuando exista persistencia KMP.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)
                    }
                    .padding(24)
                } else {
                    CaptureEmptyState(
                        title: "Sin alumnado",
                        systemImage: "person.3",
                        subtitle: "Selecciona una clase con alumnado para capturar marcas."
                    )
                }

                Divider()

                HStack(spacing: 12) {
                    Button {
                        move(by: -1)
                    } label: {
                        Label("Anterior", systemImage: "chevron.left")
                    }
                    .disabled(selectedIndex == 0 || isSaving)

                    Spacer()

                    Button {
                        Task { await saveAndAdvance() }
                    } label: {
                        Label(selectedIndex == test.results.count - 1 ? "Guardar" : "Guardar y siguiente", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(currentResult == nil || isSaving)
                }
                .padding(16)
            }
            .navigationTitle("Captura en pista")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .onAppear(perform: loadCurrentValue)
            .onChange(of: selectedIndex) { _ in loadCurrentValue() }
        }
    }

    private func loadCurrentValue() {
        attempts = ["", "", ""]
        if let value = currentResult?.value {
            attempts[0] = PhysicalTestsFormatting.decimal(value)
        }
    }

    private func move(by offset: Int) {
        selectedIndex = min(max(selectedIndex + offset, 0), max(test.results.count - 1, 0))
    }

    @MainActor
    private func saveAndAdvance() async {
        guard let currentResult else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            try await bridge.saveGrade(
                studentId: currentResult.student.id,
                evaluationId: test.evaluation.id,
                value: finalValue,
                classId: classId
            )
            bridge.status = finalValue == nil ? "Marca limpiada correctamente." : "Marca física guardada."
            await onSaved()
            if selectedIndex < test.results.count - 1 {
                move(by: 1)
            } else {
                dismiss()
            }
        } catch {
            bridge.status = "No se pudo guardar la marca: \(error.localizedDescription)"
        }
    }
}

private struct CaptureMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .black, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct CaptureEmptyState: View {
    let title: String
    let systemImage: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .thin))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.weight(.black))
            Text(subtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
