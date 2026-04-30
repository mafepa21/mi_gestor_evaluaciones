import SwiftUI
import MiGestorKit

struct PhysicalTestCaptureView: View {
    @ObservedObject var bridge: KmpBridge
    let classId: Int64
    let test: KmpBridge.PhysicalTestSnapshot
    let assignmentId: String
    let batteryId: String
    let testDefinitionId: String
    let course: Int?
    let age: Int?
    let rawColumnId: String?
    let scoreColumnId: String?
    let attemptsCount: Int
    let direction: PhysicalTestScaleDirection
    let resultMode: PhysicalTestResultMode
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex = 0
    @State private var attempts: [String] = []
    @State private var isSaving = false
    @State private var scaleWarning: String?

    private var currentResult: KmpBridge.PhysicalTestSnapshot.StudentResult? {
        guard test.results.indices.contains(selectedIndex) else { return nil }
        return test.results[selectedIndex]
    }

    private var parsedAttempts: [Double] {
        attempts.compactMap { Double($0.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private var finalValue: Double? {
        resolvedPhysicalResult(
            attempts: parsedAttempts,
            direction: direction,
            resultMode: resultMode
        ) ?? currentResult?.value
    }

    private var scorePreview: Double? {
        nil
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

                        Text(scaleWarning ?? "Si no hay baremo aplicable, se guardará solo la marca bruta.")
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
        attempts = Array(repeating: "", count: max(attemptsCount, 1))
        scaleWarning = nil
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
            let normalizedAttempts = attempts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let rawValue = finalValue
            let effectiveAge = ageOnCurrentDate(for: currentResult.student) ?? age
            let effectiveSex = sexForScale(currentResult.student)
            let resolvedScale = try await bridge.resolvePhysicalScale(
                testId: testDefinitionId,
                course: course,
                age: effectiveAge,
                sex: effectiveSex,
                batteryId: batteryId
            )
            let score = rawValue.flatMap { value in
                resolvedScale?.ranges.first(where: { range in
                    let minOk = range.minValue.map { value >= $0.doubleValue } ?? true
                    let maxOk = range.maxValue.map { value <= $0.doubleValue } ?? true
                    return minOk && maxOk
                })?.score
            }
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let resultId = "pe_result_\(assignmentId)_\(testDefinitionId)_\(currentResult.student.id)"
            let result = MiGestorKit.PhysicalTestResult(
                id: resultId,
                assignmentId: assignmentId,
                testId: testDefinitionId,
                classId: classId,
                studentId: currentResult.student.id,
                rawValue: rawValue.map { KotlinDouble(value: $0) },
                rawText: normalizedAttempts.filter { !$0.isEmpty }.joined(separator: " · "),
                score: score.map { KotlinDouble(value: $0) },
                scaleId: resolvedScale?.id,
                observedAtEpochMs: nowMs,
                rawColumnId: rawColumnId,
                scoreColumnId: scoreColumnId,
                trace: auditTrace()
            )
            let persistedAttempts = normalizedAttempts.enumerated().map { index, rawText in
                MiGestorKit.PhysicalTestAttempt(
                    id: "\(resultId)_attempt_\(index + 1)",
                    resultId: resultId,
                    attemptNumber: Int32(index + 1),
                    rawValue: Double(rawText.replacingOccurrences(of: ",", with: ".")).map { KotlinDouble(value: $0) },
                    rawText: rawText
                )
            }
            try await bridge.savePhysicalResult(result, attempts: persistedAttempts)
            if let rawValue, let rawColumnId {
                try await bridge.saveNotebookPhysicalValue(classId: classId, studentId: currentResult.student.id, columnId: rawColumnId, value: rawValue)
            }
            if let score, let scoreColumnId {
                try await bridge.saveNotebookPhysicalValue(classId: classId, studentId: currentResult.student.id, columnId: scoreColumnId, value: score)
            }
            if rawValue != nil && resolvedScale == nil {
                scaleWarning = "Sin baremo aplicable: se ha guardado solo la marca."
                bridge.status = scaleWarning ?? "Marca física guardada."
            } else {
                scaleWarning = nil
                bridge.status = score == nil ? "Marca física guardada." : "Marca y nota física guardadas."
            }
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

    private func auditTrace() -> AuditTrace {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let now = Instant.companion.fromEpochMilliseconds(epochMilliseconds: nowMs)
        return AuditTrace(authorUserId: nil, createdAt: now, updatedAt: now, associatedGroupId: KotlinLong(value: classId), deviceId: nil, syncVersion: 0)
    }

    private func sexForScale(_ student: Student) -> String? {
        switch student.sex {
        case .male: return "MALE"
        case .female: return "FEMALE"
        default: return nil
        }
    }

    private func ageOnCurrentDate(for student: Student) -> Int? {
        guard let birthDate = student.birthDate else { return nil }
        let now = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        guard let year = now.year, let month = now.month, let day = now.day else { return nil }
        var age = year - Int(birthDate.year)
        if month < Int(birthDate.monthNumber) ||
            (month == Int(birthDate.monthNumber) && day < Int(birthDate.dayOfMonth)) {
            age -= 1
        }
        return age >= 0 ? age : nil
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
