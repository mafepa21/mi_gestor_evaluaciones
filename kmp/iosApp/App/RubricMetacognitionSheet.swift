import SwiftUI
import MiGestorKit

/// Hoja modal para consultar y generar preguntas de metacognición, coevaluación
/// y sugerencias de feedback formativo basadas en los resultados de una rúbrica.
struct RubricMetacognitionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let rubricTitle: String
    let studentName: String
    let scoreSummary: String
    let criteriaNames: [String]

    @State private var isGenerating: Bool = false
    @State private var errorMessage: String? = nil
    @State private var draft: MetacognitionPromptsDraft? = nil
    @State private var showCopiedAlert: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    headerStudentCard

                    if isGenerating {
                        loadingView
                    } else if let draft {
                        promptsContentView(draft: draft)
                    } else if let errorMessage {
                        errorView(errorMessage)
                    }
                }
                .padding(20)
            }
            .background(appPageBackground(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Metacognición y Feedback")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                if draft != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            copyPrompts()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showCopiedAlert ? "checkmark.circle.fill" : "doc.on.doc")
                                Text(showCopiedAlert ? "Copiado" : "Copiar")
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(showCopiedAlert ? Color.green : Color.accentColor)
                        }
                    }
                }
            }
            .task {
                await generatePrompts()
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 580)
        #endif
    }

    // MARK: - Subvistas

    private var headerStudentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(studentName, systemImage: "person.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text(scoreSummary)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }

            Text("Instrumento: \(rubricTitle)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(appMutedCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.1)
            Text("Generando preguntas de reflexión y feedback con IA local…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Text("Adaptando las preguntas al desempeño y criterios de esta rúbrica.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    private func promptsContentView(draft: MetacognitionPromptsDraft) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            // 1. Autoevaluación
            promptSectionCard(
                title: "Autoevaluación del alumno",
                subtitle: "Preguntas para que el alumno reflexione sobre su propio progreso",
                icon: "brain.head.profile",
                color: Color.indigo,
                items: draft.selfEvaluationPrompts
            )

            // 2. Coevaluación
            promptSectionCard(
                title: "Coevaluación entre iguales",
                subtitle: "Guía para valorar constructivamente la ejecución de un compañero",
                icon: "person.2.fill",
                color: Color.teal,
                items: draft.peerEvaluationPrompts
            )

            // 3. Ticket de salida
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "ticket.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.orange)
                    Text("Ticket de salida / Pregunta de cierre")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                }

                Text(draft.exitTicketQuestion)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(14)
            .background(cardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.orange.opacity(0.20), lineWidth: 1))
        }
    }

    private func promptSectionCard(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        items: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(idx + 1).")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(color)
                            .frame(width: 20, alignment: .leading)

                        Text(item)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(8)
                    .background(color.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(14)
        .background(cardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(color.opacity(0.20), lineWidth: 1))
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.red)
            Text(msg)
                .font(.caption)
                .foregroundStyle(Color.red)
            Button("Reintentar") {
                Task { await generatePrompts() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Lógica

    private func generatePrompts() async {
        isGenerating = true
        errorMessage = nil

        let taskInfo = criteriaNames.isEmpty
            ? "\(rubricTitle) (\(studentName))"
            : "\(rubricTitle) - Criterios: \(criteriaNames.prefix(3).joined(separator: ", "))"

        let input = MetacognitionPromptsInput(
            topicOrTask: taskInfo,
            studentLevel: scoreSummary,
            modality: "Autoevaluación y coevaluación en el aula"
        )

        do {
            let orchestrator = AppleAIOrchestrator()
            let result = try await orchestrator.generate(.metacognitionPrompts(input))
            await MainActor.run {
                if case let .metacognitionPrompts(draft) = result {
                    self.draft = draft
                }
                self.isGenerating = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "No se pudieron generar las preguntas: \(error.localizedDescription)"
                self.isGenerating = false
            }
        }
    }

    private func copyPrompts() {
        guard let draft else { return }
        let text = """
        DIANA DE METACOGNICIÓN Y FEEDBACK - \(studentName.uppercased())
        Instrumento: \(rubricTitle) (\(scoreSummary))
        ==================================================

        1. AUTOEVALUACIÓN DEL ALUMNO:
        \(draft.selfEvaluationPrompts.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n"))

        2. COEVALUACIÓN ENTRE IGUALES:
        \(draft.peerEvaluationPrompts.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n"))

        3. TICKET DE SALIDA / PREGUNTA CLAVE DE CIERRE:
        • \(draft.exitTicketQuestion)
        ==================================================
        Generado localmente con Apple Intelligence (\(draft.confidenceNote))
        """

        #if canImport(UIKit)
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif

        showCopiedAlert = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showCopiedAlert = false
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
