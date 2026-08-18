import SwiftUI
import MiGestorKit

struct EvaluationHubView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void
    let onCreateEvaluation: () -> Void
    @State var evaluations: [Evaluation] = []
    @State var selectedEvaluationId: Int64?
    @State var searchText = ""
    @State var selectedTypeFilter = "Todas"

    var availableTypes: [String] {
        ["Todas"] + Array(Set(evaluations.map(\.type))).sorted()
    }

    var filteredEvaluations: [Evaluation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return evaluations.filter { evaluation in
            let matchesType = selectedTypeFilter == "Todas" || evaluation.type == selectedTypeFilter
            let matchesText = query.isEmpty
                || evaluation.name.localizedCaseInsensitiveContains(query)
                || evaluation.code.localizedCaseInsensitiveContains(query)
                || (evaluation.description_?.localizedCaseInsensitiveContains(query) ?? false)
            return matchesType && matchesText
        }
        .sorted { lhs, rhs in
            if lhs.weight == rhs.weight {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.weight > rhs.weight
        }
    }

    var selectedEvaluation: Evaluation? {
        filteredEvaluations.first(where: { $0.id == selectedEvaluationId }) ?? evaluations.first(where: { $0.id == selectedEvaluationId })
    }

    var selectedPresentation: EvaluationInspectorModel? {
        guard let selectedEvaluation else { return nil }
        return evaluationPresentation(
            evaluation: selectedEvaluation,
            rubrics: bridge.rubrics,
            rubricClassLinks: bridge.rubricClassLinks
        )
    }

    var rubricName: String {
        guard let rubricId = selectedEvaluation?.rubricId?.int64Value else { return "Sin asignar" }
        return bridge.rubrics.first(where: { $0.rubric.id == rubricId })?.rubric.name ?? "Rúbrica #\(rubricId)"
    }

    var linkedClassCountText: String {
        guard let rubricId = selectedEvaluation?.rubricId?.int64Value else { return "0" }
        return "\(bridge.rubricClassLinks[rubricId]?.count ?? 0)"
    }

    var evaluationMetrics: (total: Int, linkedRubrics: Int, averageWeight: Double) {
        let total = filteredEvaluations.count
        let linkedRubrics = filteredEvaluations.filter { $0.rubricId != nil }.count
        let averageWeight = filteredEvaluations.isEmpty ? 0 : filteredEvaluations.map(\.weight).reduce(0, +) / Double(filteredEvaluations.count)
        return (total, linkedRubrics, averageWeight)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                evaluationListPane
                    .frame(minWidth: 336, idealWidth: 360, maxWidth: 384)

                Color.clear.frame(width: 8)

                evaluationDetailPane
            }

            VStack(spacing: 0) {
                evaluationListPane
                    .frame(maxHeight: 420)
                evaluationDetailPane
            }
        }
        .background(appPageBackground(for: colorScheme))
        .task { await reload() }
        .appOnChange(of: selectedClassId) { _ in
            Task { await reload() }
        }
    }

    private var evaluationListPane: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Buscar evaluación o código…", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Picker("Tipo", selection: $selectedTypeFilter) {
                    ForEach(availableTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    WorkspaceCompactStat(title: "Total", value: "\(evaluationMetrics.total)", tint: .blue)
                    WorkspaceCompactStat(title: "Rúbricas", value: "\(evaluationMetrics.linkedRubrics)", tint: .green)
                    WorkspaceCompactStat(title: "Peso medio", value: String(format: "%.1f", evaluationMetrics.averageWeight), tint: .orange)
                    WorkspaceCompactStat(title: "Tipos", value: "\(max(availableTypes.count - 1, 0))", tint: EvaluationDesign.accent)
                }
            }
            .padding(24)

            List {
                Section("Evaluaciones") {
                    ForEach(filteredEvaluations, id: \.id) { evaluation in
                        Button {
                            selectedEvaluationId = evaluation.id
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(evaluation.name)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text("\(evaluation.type) · Peso \(String(format: "%.1f", evaluation.weight))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
        }
        .background(appMutedCardBackground(for: colorScheme))
    }

    private var evaluationDetailPane: some View {
        Group {
            if selectedEvaluation != nil, let presentation = selectedPresentation {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        WorkspaceInspectorHero(title: presentation.title, subtitle: presentation.subtitle)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                            WorkspaceMetricCard(title: "Peso", value: presentation.weightText, systemImage: "scalemass")
                            WorkspaceMetricCard(title: "Código", value: presentation.code, systemImage: "number")
                            WorkspaceMetricCard(title: "Rúbrica", value: presentation.rubricName, systemImage: "checklist")
                            WorkspaceMetricCard(
                                title: "Clases con rúbrica",
                                value: presentation.linkedClassCountText,
                                systemImage: "rectangle.3.group"
                            )
                        }

                        HStack(spacing: 12) {
                            Button("Abrir cuaderno") {
                                onOpenModule(.notebook, selectedClassId, nil)
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Ir a rúbricas") {
                                onOpenModule(.rubrics, selectedClassId, nil)
                            }
                            .buttonStyle(.bordered)
                        }

                        WorkspaceDetailBlock(title: "Resumen del instrumento", content: presentation.summary)

                        VStack(alignment: .leading, spacing: 16) {
                            Text("Contexto evaluativo")
                                .font(.headline)
                            WorkspaceFlowLayout(spacing: 10) {
                                WorkspaceTag(text: selectedClassId == nil ? "Clase global" : "Clase activa", systemImage: "rectangle.3.group")
                                ForEach(Array(presentation.readinessTags.enumerated()), id: \.offset) { _, tag in
                                    WorkspaceTag(text: tag, systemImage: "tag.fill")
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            Text("Acciones rápidas")
                                .font(.headline)
                            WorkspaceActionRow(title: "Abrir cuaderno del grupo", systemImage: "book.closed.fill") {
                                onOpenModule(.notebook, selectedClassId, nil)
                            }
                            WorkspaceActionRow(title: "Ir a banco de rúbricas", systemImage: "checklist") {
                                onOpenModule(.rubrics, selectedClassId, nil)
                            }
                        }
                    }
                    .padding(24)
                }
            } else {
                VStack(spacing: 24) {
                    WorkspaceEmptyState(
                        title: "Selecciona una evaluación",
                        subtitle: "Revisa instrumentos, peso, rúbrica asociada y acceso directo a cuaderno o banco de rúbricas."
                    )
                    HStack(spacing: 12) {
                        Button("Crear evaluación") {
                            onCreateEvaluation()
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Abrir cuaderno") {
                            onOpenModule(.notebook, selectedClassId, nil)
                        }
                        .buttonStyle(.bordered)
                        Button("Abrir rúbricas") {
                            onOpenModule(.rubrics, selectedClassId, nil)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appPageBackground(for: colorScheme))
    }

    @MainActor
    func reload() async {
        guard let selectedClassId else {
            evaluations = []
            selectedEvaluationId = nil
            return
        }
        evaluations = (try? await bridge.evaluations(for: selectedClassId)) ?? []
        if selectedEvaluationId == nil {
            selectedEvaluationId = evaluations.first?.id
        } else if !evaluations.contains(where: { $0.id == selectedEvaluationId }) {
            selectedEvaluationId = evaluations.first?.id
        }
    }
}
