import SwiftUI
import MiGestorKit

struct TeacherRadarDetailView: View {
    @ObservedObject var bridge: KmpBridge
    @Binding var selectedClassId: Int64?
    @Binding var selectedStudentId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void

    @State private var selectedPriority: TeacherRadarInsightDraft.Priority? = nil
    @State private var generatedDraft: TeachingAssistantDraft?
    @State private var isGeneratingDraft = false
    @State private var draftError: String?
    private let contextualAIService = AppleFoundationContextualAIService()

    var body: some View {
        Group {
            if let data = bridge.notebookState as? NotebookUiStateData {
                let snapshot = TeacherRadarBuilder.build(data: data, className: activeClassName(data.sheet.classId))
                radarContent(snapshot)
            } else if bridge.notebookState is NotebookUiStateLoading {
                ProgressView("Preparando Radar…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(EvaluationBackdrop())
            } else {
                NotebookStateCard(
                    systemImage: "scope",
                    title: "Radar sin datos",
                    message: "Selecciona un grupo con cuaderno cargado para generar alertas accionables."
                )
                .background(EvaluationBackdrop())
            }
        }
        .task(id: selectedClassId) {
            await ensureNotebookLoaded()
        }
    }

    private func radarContent(_ snapshot: TeacherRadarSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RADAR DOCENTE")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        Text("Radar de hoy")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                        Text(snapshot.className)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await generateTeacherDraft(snapshot) }
                    } label: {
                        if isGeneratingDraft {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Redactar", systemImage: "apple.intelligence")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(snapshot.insights.isEmpty || isGeneratingDraft)
                }

                TeacherRadarCard(snapshot: snapshot) {}

                if let generatedDraft {
                    draftView(generatedDraft)
                } else if let draftError {
                    Text(draftError)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NotebookStyle.warningTint)
                }

                TeacherRadarGroupSummaryView(summary: snapshot.groupSummary)

                priorityFilters

                VStack(alignment: .leading, spacing: 10) {
                    NotebookSectionLabel(text: "Acciones sugeridas")
                    ForEach(filteredInsights(snapshot.insights)) { insight in
                        Button {
                            if let studentId = insight.studentId {
                                selectedStudentId = studentId
                                onOpenModule(.students, selectedClassId, studentId)
                            } else {
                                onOpenModule(.notebook, selectedClassId, nil)
                            }
                        } label: {
                            TeacherRadarStudentInsightRow(insight: insight)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    NotebookSectionLabel(text: "Ficha de seguimiento")
                    ForEach(snapshot.students) { student in
                        studentFollowUpRow(student)
                    }
                }
            }
            .padding(24)
        }
        .background(EvaluationBackdrop())
    }

    private var priorityFilters: some View {
        HStack(spacing: 8) {
            filterButton("Todas", nil)
            ForEach(TeacherRadarInsightDraft.Priority.allCases, id: \.rawValue) { priority in
                filterButton(priority.title, priority)
            }
        }
    }

    private func filterButton(_ title: String, _ priority: TeacherRadarInsightDraft.Priority?) -> some View {
        Button {
            selectedPriority = priority
        } label: {
            Text(title)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(selectedPriority == priority ? NotebookStyle.primaryTint : .secondary)
    }

    private func studentFollowUpRow(_ student: TeacherRadarStudentSnapshot) -> some View {
        Button {
            selectedStudentId = student.id
            onOpenModule(.students, selectedClassId, student.id)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: student.risk.systemImage)
                    .foregroundStyle(student.risk.tint)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(student.name)
                            .font(.headline)
                        Spacer()
                        Text(student.risk.title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(student.risk.tint)
                    }
                    HStack(spacing: 12) {
                        followUpMetric("Media", averageTrendText(student))
                        followUpMetric("Asistencia", student.attendanceRate.map { "\($0)%" } ?? "Sin dato")
                        followUpMetric("Evidencias", "\(student.evidenceCount)")
                        followUpMetric("Riesgo", student.risk.title)
                    }
                    Text(student.suggestedAction)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(NotebookStyle.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(student.risk.tint.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func followUpMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func draftView(_ draft: TeachingAssistantDraft) -> some View {
        NotebookSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Borrador IA", systemImage: "apple.intelligence")
                        .font(.headline)
                    Spacer()
                    Text(draft.confidenceNote ?? "Basado en datos del Radar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(draft.editableText)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
        }
    }

    private func filteredInsights(_ insights: [TeacherRadarInsightDraft]) -> [TeacherRadarInsightDraft] {
        guard let selectedPriority else { return insights }
        return insights.filter { $0.priority == selectedPriority }
    }

    private func averageTrendText(_ student: TeacherRadarStudentSnapshot) -> String {
        let current = student.average.map { IosFormatting.decimal(from: $0) } ?? "Sin media"
        guard let previous = student.previousAverage else { return current }
        return "\(IosFormatting.decimal(from: previous)) -> \(current)"
    }

    private func activeClassName(_ classId: Int64) -> String {
        bridge.classes.first(where: { $0.id == classId })?.name ?? "Grupo \(classId)"
    }

    private func ensureNotebookLoaded() async {
        await bridge.ensureClassesLoaded()
        if let selectedClassId {
            bridge.selectClass(id: selectedClassId)
        } else if let first = bridge.classes.first {
            await MainActor.run {
                selectedClassId = first.id
                bridge.selectClass(id: first.id)
            }
        }
    }

    private func generateTeacherDraft(_ snapshot: TeacherRadarSnapshot) async {
        isGeneratingDraft = true
        draftError = nil
        defer { isGeneratingDraft = false }
        let evidence = TeachingEvidencePack(
            useCase: .studentRiskRadar,
            title: "Radar Docente",
            subtitle: snapshot.className,
            summary: "Alertas accionables generadas desde cuaderno, rúbricas y evidencias visibles.",
            metrics: [
                KmpBridge.ReportMetric(title: "Prioridad alta", value: "\(snapshot.highPriorityCount)", systemImage: "exclamationmark.triangle.fill"),
                KmpBridge.ReportMetric(title: "Acciones", value: "\(snapshot.actionInsights.count)", systemImage: "checklist"),
                KmpBridge.ReportMetric(title: "Reconocimientos", value: "\(snapshot.positiveCount)", systemImage: "sparkles")
            ],
            factsUsed: snapshot.insights.prefix(6).flatMap { insight in
                [FactItem(text: insight.title)] + insight.evidence.map(FactItem.init)
            },
            warnings: snapshot.insights.filter { $0.priority == .high }.prefix(4).map { WarningItem(text: $0.detail) },
            recommendedActions: snapshot.actionInsights.map { RecommendedActionItem(text: $0.suggestedAction) },
            confidenceNote: "No inventar causas personales; usar solo datos objetivos del Radar.",
            riskLevel: snapshot.highPriorityCount > 0 ? .atencionPrioritaria : .seguimientoNormal,
            sourceDigest: snapshot.insights.map { "\($0.title). \($0.detail)" }.joined(separator: " "),
            hasEnoughData: !snapshot.insights.isEmpty
        )
        do {
            generatedDraft = try await contextualAIService.generateTeachingDraft(
                from: evidence,
                audience: .docente,
                tone: .breve,
                customPrompt: "Resume el grupo, redacta un informe breve de tutoría si procede, propone feedback para alumnado y una intervención docente concreta. No inventes causas personales, diagnósticos ni datos sensibles."
            )
        } catch {
            draftError = error.localizedDescription
        }
    }
}
