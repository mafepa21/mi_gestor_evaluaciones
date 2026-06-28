import SwiftUI
import MiGestorKit

enum AppleAIGenerationState: Equatable {
    case available
    case preparingModel
    case unavailable
    case rulesFallback
    case recoverableError(String)

    var title: String {
        switch self {
        case .available:
            return "Disponible"
        case .preparingModel:
            return "Preparando modelo"
        case .unavailable:
            return "No disponible"
        case .rulesFallback:
            return "Fallback por reglas"
        case .recoverableError:
            return "Error recuperable"
        }
    }

    var systemImage: String {
        switch self {
        case .available:
            return "checkmark.seal.fill"
        case .preparingModel:
            return "arrow.triangle.2.circlepath"
        case .unavailable:
            return "slash.circle"
        case .rulesFallback:
            return "list.bullet.clipboard"
        case .recoverableError:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .available:
            return NotebookStyle.successTint
        case .preparingModel:
            return NotebookStyle.primaryTint
        case .unavailable:
            return .secondary
        case .rulesFallback:
            return NotebookStyle.warningTint
        case .recoverableError:
            return .orange
        }
    }
}

struct AppleAIGenerationAudit: Equatable {
    var generatedAt: Date = .now
    var dataSource: String
    var includedEvidence: [String]
    var usedRealAI: Bool
    var usedFallback: Bool
    var teacherEdited: Bool = false
    var durationMs: Int64 = 0

    var provenanceLabel: String {
        usedRealAI && !usedFallback ? "Apple Intelligence" : "Reglas locales"
    }
}

struct AppleAIGenerationMetadata: Equatable {
    var state: AppleAIGenerationState
    var availabilityMessage: String
    var audit: AppleAIGenerationAudit
}

struct AppleAIStatusBadge: View {
    let state: AppleAIGenerationState
    let message: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.caption.weight(.bold))
                Text(message)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
            }
        } icon: {
            Image(systemName: state.systemImage)
                .font(.system(size: 14, weight: .bold))
        }
        .foregroundStyle(state.tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(state.tint.opacity(0.10))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(state.tint.opacity(0.16), lineWidth: 1)
        }
    }
}

struct AppleAIAuditSummaryView: View {
    let metadata: AppleAIGenerationMetadata?

    var body: some View {
        if let metadata {
            VStack(alignment: .leading, spacing: 10) {
                Label("Trazabilidad IA", systemImage: "checklist.checked")
                    .font(.headline)
                auditRow("Generado", value: metadata.audit.generatedAt.formatted(date: .abbreviated, time: .shortened))
                auditRow("Fuente", value: metadata.audit.dataSource)
                auditRow("Evidencias", value: evidenceText)
                auditRow("Origen", value: metadata.audit.provenanceLabel)
                auditRow("Editado por docente", value: metadata.audit.teacherEdited ? "Sí" : "No")
            }
            .padding(14)
            .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(NotebookStyle.softBorder, lineWidth: 1)
            }
        }
    }

    private var evidenceText: String {
        let items = metadata?.audit.includedEvidence.prefix(6).joined(separator: " · ") ?? ""
        return items.isEmpty ? "Sin detalle" : items
    }

    private func auditRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }
}

struct AppleAIPreviewSheet: View {
    let title: String
    let subtitle: String
    @Binding var text: String
    let metadata: AppleAIGenerationMetadata?
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title2.weight(.bold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let metadata {
                    AppleAIStatusBadge(state: metadata.state, message: metadata.availabilityMessage)
                    AppleAIAuditSummaryView(metadata: metadata)
                }

                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 280)
                    .padding(12)
                    .scrollContentBackground(.hidden)
                    .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(20)
            .background(EvaluationBackdrop())
            .navigationTitle("Previsualizar")
            .appInlineNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onApply()
                        dismiss()
                    } label: {
                        Label("Aplicar", systemImage: "checkmark.circle.fill")
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 560, minHeight: 560)
#else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#endif
    }
}

struct AppleAIHistoryPanel: View {
    @ObservedObject var bridge: KmpBridge
    @State private var totals: [AIAuditUseCaseTotal] = []
    @State private var failures: [AIAuditEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Historial IA", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)
                .accessibilityLabel("Actualizar historial IA")
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            } else {
                if totals.isEmpty && failures.isEmpty {
                    Text("Sin generaciones IA auditadas todavía.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(totals, id: \.useCase) { total in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(total.useCase)
                                .font(.subheadline.weight(.semibold))
                            Text("Última: \(formattedEpoch(total.lastCreatedAtEpochMs))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(total.successCount)/\(total.totalCount)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(total.successCount == total.totalCount ? NotebookStyle.successTint : NotebookStyle.warningTint)
                    }
                }

                if !failures.isEmpty {
                    Divider()
                    Text("Errores recuperables recientes")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(failures, id: \.id) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(event.service) · \(event.useCase)")
                                .font(.caption.weight(.bold))
                            Text(event.errorMessage ?? event.errorKind ?? "Sin detalle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(formattedEpoch(event.createdAtEpochMs))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .task { await reload() }
    }

    @MainActor
    private func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            totals = try await bridge.aiAuditTotalsByUseCase()
            failures = try await bridge.recentAIAuditFailures(limit: 5)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formattedEpoch(_ epochMs: Int64) -> String {
        guard epochMs > 0 else { return "Sin fecha" }
        return Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000)
            .formatted(date: .abbreviated, time: .shortened)
    }
}

extension AppleAIAvailability {
    var generationState: AppleAIGenerationState {
        switch self {
        case .available:
            return .available
        case .preparing:
            return .preparingModel
        case .disabled, .unavailable:
            return .unavailable
        }
    }
}

extension AIReportDraft {
    var appearsToBeRulesFallback: Bool {
        title.localizedCaseInsensitiveContains("reglas")
    }
}

extension AIChartInsight {
    var appearsToBeRulesFallback: Bool {
        warnings.contains { $0.localizedCaseInsensitiveContains("reglas") || $0.localizedCaseInsensitiveContains("no está disponible") }
    }
}

extension NotebookAICommentDraft {
    var appearsToBeRulesFallback: Bool {
        warnings.contains { $0.localizedCaseInsensitiveContains("reglas") || $0.localizedCaseInsensitiveContains("no está disponible") }
    }
}

extension TeachingAssistantDraft {
    var appearsToBeRulesFallback: Bool {
        confidenceNote?.localizedCaseInsensitiveContains("reglas") == true ||
        warnings.contains { $0.localizedCaseInsensitiveContains("reglas") || $0.localizedCaseInsensitiveContains("no está disponible") }
    }
}

extension PhysicalScaleRecommendationDraft {
    var appearsToBeRulesFallback: Bool {
        explanation.localizedCaseInsensitiveContains("seed deterministas") ||
        editableProposal.localizedCaseInsensitiveContains("Baremo orientativo")
    }
}
