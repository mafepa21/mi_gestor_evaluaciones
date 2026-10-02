import SwiftUI
import MiGestorKit

/// Hoja modal para estructurar sesiones didácticas con Apple Intelligence local.
/// Genera la triple fase pedagógica (calentamiento/activación, desarrollo y vuelta a la calma).
struct PlannerSessionAIAssistantSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let initialTopic: String
    let onApply: (String, String) -> Void // (objetivos, actividades)

    @State private var topic: String
    @State private var stage: String = "Secundaria (ESO)"
    @State private var durationMinutes: Int = 50
    @State private var specificFocus: String = ""
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String? = nil
    @State private var generatedDraft: PlannerSequenceDraft? = nil

    private let availableStages = [
        "Primaria",
        "Secundaria (ESO)",
        "Bachillerato",
        "Ciclos Formativos"
    ]

    private let durationOptions = [45, 50, 60, 90]

    init(initialTopic: String = "", onApply: @escaping (String, String) -> Void) {
        self.initialTopic = initialTopic
        self.onApply = onApply
        _topic = State(initialValue: initialTopic)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    if generatedDraft == nil {
                        inputFormSection
                    } else if let draft = generatedDraft {
                        resultPreviewSection(draft: draft)
                    }
                }
                .padding(20)
            }
            .background(appPageBackground(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Asistente didáctico de sesión")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                if generatedDraft != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Reconfigurar") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                generatedDraft = nil
                            }
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 560)
        #endif
    }

    // MARK: - Formulario

    private var inputFormSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Tarjeta introductoria
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                    Text("Estructuración pedagógica de sesión")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                Text("Apple Intelligence generará la progresión en tres fases (calentamiento/activación, bloque principal y vuelta a la calma/reflexión).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Tema / Unidad
            VStack(alignment: .leading, spacing: 6) {
                Text("Tema, contenido o situación de aprendizaje")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                TextField("Ej: Balonmano: toma de decisiones y desmarques", text: $topic)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(appMutedCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Etapa y Duración
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Etapa")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Picker("Etapa", selection: $stage) {
                        ForEach(availableStages, id: \.self) { s in
                            Text(s).tag(s)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(appMutedCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Duración de la sesión")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Picker("Duración", selection: $durationMinutes) {
                        ForEach(durationOptions, id: \.self) { mins in
                            Text("\(mins) minutos").tag(mins)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(appMutedCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            // Foco específico (opcional)
            VStack(alignment: .leading, spacing: 6) {
                Text("Foco específico o competencia (opcional)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                TextField("Ej: Fomentar el juego limpio y la participación mixta", text: $specificFocus)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(appMutedCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.red)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                }
                .padding(10)
                .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button {
                generateSequence()
            } label: {
                HStack(spacing: 8) {
                    if isGenerating {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.9)
                        Text("Estructurando sesión didáctica…")
                    } else {
                        Image(systemName: "sparkles")
                        Text("Generar estructura de sesión")
                    }
                }
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating ? Color.accentColor.opacity(0.4) : Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
        }
    }

    // MARK: - Previsualización

    private func resultPreviewSection(draft: PlannerSequenceDraft) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Objetivo de sesión")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                Text(draft.sessionFocus)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if !draft.evaluationStrategy.isEmpty {
                    Text("Estrategia evaluativa: \(draft.evaluationStrategy)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Fases/pasos
            ForEach(Array(draft.steps.enumerated()), id: \.offset) { idx, step in
                phaseCard(
                    title: "\(idx + 1). \(step.phase)",
                    minutes: step.estimatedMinutes,
                    description: step.activityDescription,
                    tips: step.organizationTips,
                    materials: step.materialNeeds
                )
            }

            // Botón de aplicación
            Button {
                let objectives = draft.sessionFocus + (draft.evaluationStrategy.isEmpty ? "" : "\nEvaluación: " + draft.evaluationStrategy)
                let activities = draft.steps.map { step in
                    var text = "[\(step.phase.uppercased()) - \(step.estimatedMinutes) MIN]\n\(step.activityDescription)"
                    if !step.organizationTips.isEmpty {
                        text += "\nOrganización: \(step.organizationTips)"
                    }
                    if !step.materialNeeds.isEmpty {
                        text += "\nMaterial: \(step.materialNeeds.joined(separator: ", "))"
                    }
                    return text
                }.joined(separator: "\n\n")

                onApply(objectives, activities)
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Insertar en la sesión")
                }
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func phaseCard(title: String, minutes: Int, description: String, tips: String, materials: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(minutes) min")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineSpacing(3)

            if !tips.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.orange)
                    Text(tips)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !materials.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "cube.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                    Text("Material: \(materials.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appMutedCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Lógica

    private func generateSequence() {
        isGenerating = true
        errorMessage = nil

        let outcomes = specificFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ["Desarrollo motor y juego limpio"]
            : [specificFocus.trimmingCharacters(in: .whitespacesAndNewlines)]

        let input = PlannerSequenceInput(
            unitTitle: topic,
            sessionIndex: 1,
            totalSessions: 1,
            learningOutcomes: outcomes,
            targetAudience: "\(stage) (\(durationMinutes) min)"
        )

        Task { @MainActor in
            do {
                let orchestrator = AppleAIOrchestrator()
                let result = try await orchestrator.generate(.plannerSequence(input))
                withAnimation(.easeInOut(duration: 0.2)) {
                    if case let .plannerSequence(draft) = result {
                        self.generatedDraft = draft
                    }
                    self.isGenerating = false
                }
            } catch {
                withAnimation {
                    self.errorMessage = "Error al estructurar: \(error.localizedDescription)"
                    self.isGenerating = false
                }
            }
        }
    }

    private func appPageBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.10) : Color(white: 0.96)
    }

    private func appMutedCardBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.15) : Color(white: 0.92)
    }
}

private extension View {
    @ViewBuilder
    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
