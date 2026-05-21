import SwiftUI
import MiGestorKit

struct RubricEvaluationView: View {
    @EnvironmentObject var bridge: KmpBridge

    private var state: RubricEvaluationUiState {
        bridge.rubricEvaluationState
    }

    var body: some View {
        NavigationStack {
            ZStack {
                EvaluationBackdrop()

                if let rubric = state.rubricDetail {
                    GeometryReader { proxy in
                        let isWide = proxy.size.width >= 960
                        let selectedScore = state.totalScore

                        ScrollView {
                            VStack(alignment: .leading, spacing: EvaluationDesign.sectionSpacing) {
                                headerSection(rubric: rubric, score: selectedScore)

                                if isWide {
                                    HStack(alignment: .top, spacing: EvaluationDesign.sectionSpacing) {
                                        criteriaPanel(rubric: rubric)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        summaryPanel(rubric: rubric, score: selectedScore)
                                            .frame(width: 300)
                                    }
                                } else {
                                    VStack(spacing: EvaluationDesign.sectionSpacing) {
                                        criteriaPanel(rubric: rubric)
                                        summaryPanel(rubric: rubric, score: selectedScore)
                                    }
                                }
                            }
                            .padding(EvaluationDesign.screenPadding)
                        }
                    }
                    .appOnChange(of: state.isSaveSuccessful) { saved in
                        guard saved else { return }
                        guard !bridge.isNotebookRubricAutoAdvanceActive else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            closeRubric()
                        }
                    }
                } else if let error = state.error {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(EvaluationDesign.danger)
                        Text("No se pudo abrir la rúbrica")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                        Text(error)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        EvaluationPrimaryButton(label: "Cerrar", systemImage: "xmark") {
                            closeRubric()
                        }
                        .frame(width: 160)
                    }
                    .padding()
                } else {
                    ProgressView("Cargando rúbrica...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func headerSection(rubric: RubricDetail, score: Double) -> some View {
        HStack(alignment: .top, spacing: 16) {
            EvaluationIconButton(systemImage: "chevron.down", tint: .primary) {
                closeRubric()
            }

            EvaluationAvatar(initials: String(state.studentName.prefix(2)))

            VStack(alignment: .leading, spacing: 6) {
                Text("Evaluación individual")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)

                Text(state.studentName)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)

                Text(rubric.rubric.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 12) {
                EvaluationScoreBadge(
                    title: "Nota actual",
                    value: IosFormatting.scoreOutOfTen(from: score)
                )

                EvaluationPrimaryButton(label: "Guardar evaluación", systemImage: "square.and.arrow.down.fill") {
                    bridge.saveRubricEvaluation(
                        manual: true,
                        emitNotebookRefresh: !bridge.isNotebookRubricAutoAdvanceActive,
                        onSuccess: {
                            if !bridge.isNotebookRubricAutoAdvanceActive {
                                bridge.refreshCurrentNotebook()
                                closeRubric()
                            }
                        }
                    )
                }
                .frame(width: 220)
            }
        }
    }

    private func criteriaPanel(rubric: RubricDetail) -> some View {
        EvaluationGlassCard(cornerRadius: 32, fillOpacity: 0.88) {
            VStack(alignment: .leading, spacing: EvaluationDesign.sectionSpacing) {
                HStack(spacing: 12) {
                    EvaluationChip(
                        label: "\(rubric.criteria.count) criterios",
                        systemImage: "checklist",
                        tint: EvaluationDesign.accent
                    )

                    EvaluationChip(
                        label: "Selecciona el nivel",
                        systemImage: "hand.tap.fill",
                        tint: EvaluationDesign.accent
                    )
                }

                VStack(spacing: 16) {
                    ForEach(rubric.criteria, id: \.criterion.id) { criterion in
                        RubricCriterionRow(
                            item: criterion,
                            selectedLevelId: state.selectedLevels[KotlinLong(value: criterion.criterion.id)]?.int64Value,
                            onSelectLevel: { levelId in
                                bridge.rubricEvaluationViewModel.selectLevel(
                                    criterionId: criterion.criterion.id,
                                    levelId: levelId
                                )
                            }
                        )
                    }
                }
            }
        }
    }

    private func summaryPanel(rubric: RubricDetail, score: Double) -> some View {
        EvaluationGlassCard(cornerRadius: 32, fillOpacity: 0.92) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    EvaluationChip(
                        label: "Resumen",
                        systemImage: "sparkles",
                        tint: EvaluationDesign.accent
                    )
                    Spacer()
                    Text(IosFormatting.decimal(from: score))
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(EvaluationDesign.accent)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Progreso")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text("\(state.selectedLevels.count) de \(rubric.criteria.count) criterios resueltos")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    ProgressView(value: Double(state.selectedLevels.count), total: Double(max(rubric.criteria.count, 1)))
                        .tint(EvaluationDesign.accent)
                }

                EvaluationDivider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Siguiente paso")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text("Revisa cada criterio y guarda cuando la rúbrica quede completa.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func closeRubric() {
        bridge.closeRubricEvaluation()
    }
}

struct RubricCriterionRow: View {
    let item: RubricCriterionWithLevels
    let selectedLevelId: Int64?
    let onSelectLevel: (Int64) -> Void
    @State private var hoveredLevelId: Int64?
    @State private var hoverTask: Task<Void, Never>?

    private var selectedLevel: RubricLevel? {
        item.levels.first { $0.id == selectedLevelId }
    }

    private var selectedLevelDescription: String {
        selectedLevel?.description_?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var body: some View {
        EvaluationGlassCard(cornerRadius: 24, fillOpacity: 0.96) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.criterion.description_)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Elige el nivel que mejor describe el desempeño")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(item.levels, id: \.id) { level in
                            let isSelected = selectedLevelId == level.id

                            EvaluationLevelTile(
                                title: level.name,
                                subtitle: level.description_ ?? "",
                                isSelected: isSelected,
                                tint: EvaluationDesign.accent
                            ) {
                                onSelectLevel(level.id)
                            }
                            .frame(width: 160)
                            .overlay(alignment: .bottomTrailing) {
                                Text("\(Int(level.points)) pts")
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .foregroundStyle(isSelected ? .white : EvaluationDesign.accent)
                                    .padding(.trailing, 12)
                                    .padding(.bottom, 10)
                            }
                            .help(levelHelpText(level))
                            .onHover { isHovering in
                                if isHovering {
                                    schedulePopover(for: level.id)
                                } else {
                                    cancelPopover(for: level.id)
                                }
                            }
                            .popover(
                                isPresented: Binding(
                                    get: { hoveredLevelId == level.id },
                                    set: { if !$0 { cancelPopover(for: level.id) } }
                                ),
                                arrowEdge: .bottom
                            ) {
                                RubricLevelDescriptionPopover(level: level)
                                    .padding(4)
                            }
                        }
                    }
                }

                if !selectedLevelDescription.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(EvaluationDesign.accent.opacity(0.72))
                            .padding(.top, 2)

                        Text(selectedLevelDescription)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(EvaluationDesign.accent.opacity(0.08))
                    )
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        )
                    )
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: selectedLevelId)
        .onDisappear {
            hoverTask?.cancel()
            hoveredLevelId = nil
        }
    }

    private func levelHelpText(_ level: RubricLevel) -> String {
        let description = level.description_?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !description.isEmpty else { return level.name }
        return "\(level.name): \(description)"
    }

    private func schedulePopover(for levelId: Int64) {
        hoverTask?.cancel()
        hoverTask = Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        hoveredLevelId = levelId
                    }
                }
            } catch {}
        }
    }

    private func cancelPopover(for levelId: Int64) {
        hoverTask?.cancel()
        guard hoveredLevelId == levelId else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            hoveredLevelId = nil
        }
    }
}
