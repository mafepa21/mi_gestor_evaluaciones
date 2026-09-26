import SwiftUI
import MiGestorKit

/// Modal de generación de rúbricas analíticas LOMLOE con Apple Intelligence local.
/// Sigue los principios de Jobs Design Philosophy: jerarquía clara, rejilla de 8pt y cero fricción.
struct AIRubricGeneratorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let initialTopic: String
    let onApply: (AIRubricDraft) -> Void

    @State private var topic: String
    @State private var stage: String = "Secundaria (ESO)"
    @State private var criteriaPrompt: String = ""
    @State private var numberOfLevels: Int = 4
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String? = nil
    @State private var generatedDraft: AIRubricDraft? = nil

    private let availableStages = [
        "Primaria",
        "Secundaria (ESO)",
        "Bachillerato",
        "Ciclos Formativos"
    ]

    init(initialTopic: String = "", onApply: @escaping (AIRubricDraft) -> Void) {
        self.initialTopic = initialTopic
        self.onApply = onApply
        _topic = State(initialValue: initialTopic)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 24) {
                    if generatedDraft == nil {
                        inputFormSection
                    } else if let draft = generatedDraft {
                        resultPreviewSection(draft: draft)
                    }
                }
                .padding(24)
            }
            .background(appPageBackground(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Crear rúbrica LOMLOE")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                if generatedDraft != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Volver a configurar") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                generatedDraft = nil
                            }
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 600)
        #endif
    }

    // MARK: - Formulario de Entrada

    private var inputFormSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Tarjeta de contexto
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                    Text("Generador curricular con IA local")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                Text("Define la situación de aprendizaje o contenido. Apple Intelligence graduará automáticamente los descriptores según la taxonomía LOMLOE.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Campo Situación de Aprendizaje / Tema
            VStack(alignment: .leading, spacing: 8) {
                Text("Situación de Aprendizaje o Tema")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                TextField("Ej: Deportes de raqueta: iniciación al bádminton", text: $topic)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(appMutedCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Etapa educativa y número de niveles
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Etapa educativa")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Picker("Etapa", selection: $stage) {
                        ForEach(availableStages, id: \.self) { stageOption in
                            Text(stageOption).tag(stageOption)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(appMutedCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Niveles de logro")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Picker("Niveles", selection: $numberOfLevels) {
                        Text("3 niveles").tag(3)
                        Text("4 niveles (LOMLOE)").tag(4)
                        Text("5 niveles").tag(5)
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(appMutedCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            // Criterios específicos o foco pedagógico (opcional)
            VStack(alignment: .leading, spacing: 8) {
                Text("Criterios de evaluación o aspectos clave (opcional)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $criteriaPrompt)
                    .frame(height: 80)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(appMutedCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if criteriaPrompt.isEmpty {
                            Text("Ej: Técnica básica de golpeo, colocación en pista y respeto de las reglas.")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                                .padding(12)
                                .allowsHitTesting(false)
                        }
                    }
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

            // Botón de generación
            Button {
                generateRubric()
            } label: {
                HStack(spacing: 8) {
                    if isGenerating {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.9)
                        Text("Graduando criterios LOMLOE en dispositivo…")
                    } else {
                        Image(systemName: "sparkles")
                        Text("Generar rúbrica graduada")
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

    // MARK: - Previsualización del Resultado

    private func resultPreviewSection(draft: AIRubricDraft) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Cabecera del borrador
            VStack(alignment: .leading, spacing: 6) {
                Text("Propuesta generada")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                Text(draft.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                if let course = draft.targetCourse, !course.isEmpty {
                    Text(course)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Lista de Criterios
            VStack(alignment: .leading, spacing: 16) {
                Text("Criterios y descriptores graduados (\(draft.criteria.count))")
                    .font(.headline)
                    .foregroundStyle(.primary)

                ForEach(Array(draft.criteria.enumerated()), id: \.offset) { idx, criterion in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Criterio \(idx + 1)")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                                .foregroundStyle(Color.accentColor)

                            Text(criterion.criterionTitle)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)

                            Spacer()
                            Text("Ponderación: \(Int(criterion.weight))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Niveles en cuadrícula compacta
                        VStack(spacing: 8) {
                            ForEach(criterion.levels, id: \.levelIndex) { level in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(level.levelName)
                                        .font(.caption.weight(.bold))
                                        .frame(width: 80, alignment: .leading)
                                        .foregroundStyle(levelColor(for: level.levelIndex, total: criterion.levels.count))

                                    Text(level.descriptor)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(8)
                                .background(appMutedCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                    .padding(16)
                    .background(cardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                }
            }

            // Botón de aplicación
            Button {
                onApply(draft)
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Aplicar al editor de rúbrica")
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

    // MARK: - Lógica

    private func generateRubric() {
        isGenerating = true
        errorMessage = nil

        let taskDescription = criteriaPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Criterios curriculares LOMLOE y evaluación formativa en \(topic)"
            : criteriaPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        let input = RubricDraftInput(
            title: topic,
            criteriaOrTask: taskDescription,
            courseOrCycle: stage,
            levelCount: numberOfLevels
        )

        Task { @MainActor in
            do {
                let orchestrator = AppleAIOrchestrator()
                let result = try await orchestrator.generate(.rubricDraft(input))
                withAnimation(.easeInOut(duration: 0.2)) {
                    if case let .rubricDraft(draft) = result {
                        self.generatedDraft = draft
                    }
                    self.isGenerating = false
                }
            } catch {
                withAnimation {
                    self.errorMessage = "No se pudo generar la rúbrica: \(error.localizedDescription)"
                    self.isGenerating = false
                }
            }
        }
    }

    private func levelColor(for index: Int, total: Int) -> Color {
        guard total > 1 else { return Color.accentColor }
        let ratio = Double(index) / Double(total - 1)
        if ratio <= 0.33 {
            return Color.orange
        } else if ratio <= 0.66 {
            return Color.blue
        } else {
            return Color.green
        }
    }

    private func appPageBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.10) : Color(white: 0.96)
    }

    private func appMutedCardBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.15) : Color(white: 0.92)
    }

    private func cardBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.13) : Color.white
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
