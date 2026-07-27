import SwiftUI
import MiGestorKit

struct RubricEvaluationView: View {
    @EnvironmentObject var bridge: KmpBridge
    @State private var activePopoverLevel: RubricLevel?

    private var state: RubricEvaluationUiState {
        bridge.rubricEvaluationState
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RubricEvaluationBackdrop()

                if let rubric = state.rubricDetail {
                    let selectedScore = state.totalScore
                    let progress = rubric.criteria.isEmpty ? 0.0 : Double(state.selectedLevels.count) / Double(rubric.criteria.count)

                    ScrollView {
                        VStack(alignment: .leading, spacing: EvaluationDesign.sectionSpacing) {
                            headerSection(rubric: rubric, score: selectedScore, progress: progress)
                            criteriaPanel(rubric: rubric)
                            saveSection(rubric: rubric, score: selectedScore)
                        }
                        .padding(EvaluationDesign.screenPadding)
                        .frame(maxWidth: 640)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
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
                        PrimaryActionButton(label: "Cerrar", systemImage: "xmark") {
                            closeRubric()
                        }
                        .frame(width: 160)
                    }
                    .padding()
                } else if state.studentId == 0 || state.isLoading {
                    ProgressView("Cargando rúbrica...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(EvaluationDesign.danger)
                        Text("No se pudo abrir la rúbrica")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                        Text("La rúbrica seleccionada no existe o no se pudo cargar.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        PrimaryActionButton(label: "Cerrar", systemImage: "xmark") {
                            closeRubric()
                        }
                        .frame(width: 160)
                    }
                    .padding()
                }
            }
            .popover(item: $activePopoverLevel, arrowEdge: .bottom) { level in
                RubricLevelDescriptionPopover(level: level)
                    .padding(4)
            }
            .onDisappear {
                activePopoverLevel = nil
            }
        }
    }

    private func headerSection(rubric: RubricDetail, score: Double, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                Button(action: closeRubric) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cerrar")

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.studentName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(rubric.rubric.name)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                RubricScoreRing(progress: progress, scoreOutOfTen: score)
            }

            let criteriaText = rubricCriteriaSummary(rubric: rubric)
            AssessmentCriteriaDisclosureView(rawText: criteriaText)
        }
    }

    private func rubricCriteriaSummary(rubric: RubricDetail) -> String {
        var parts: [String] = [state.rubricName, rubric.rubric.name, rubric.rubric.description]
        parts.append(contentsOf: rubric.criteria.map { $0.criterion.description_ })
        return parts.joined(separator: " · ")
    }

    private func saveSection(rubric: RubricDetail, score: Double) -> some View {
        let totalCriteria = rubric.criteria.count
        let answeredCriteria = state.selectedLevels.count
        let isComplete = totalCriteria > 0 && answeredCriteria >= totalCriteria

        let labelText = isComplete
            ? "Guardar · \(IosFormatting.scoreOutOfTen(from: score))"
            : "Guardar · \(answeredCriteria) de \(totalCriteria) criterios"

        return PrimaryActionButton(label: labelText, systemImage: "square.and.arrow.down.fill") {
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
        .frame(maxWidth: .infinity)
    }

    private func criteriaPanel(rubric: RubricDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rubric.criteria.enumerated()), id: \.element.criterion.id) { index, criterion in
                if index > 0 {
                    Rectangle()
                        .fill(RubricsStyle.hairline)
                        .frame(height: 1)
                }

                RubricCriterionRow(
                    item: criterion,
                    selectedLevelId: state.selectedLevels[KotlinLong(value: criterion.criterion.id)]?.int64Value,
                    activePopoverLevel: $activePopoverLevel,
                    onSelectLevel: { levelId in
                        bridge.rubricEvaluationViewModel.selectLevel(
                            criterionId: criterion.criterion.id,
                            levelId: levelId
                        )
                    }
                )
                .padding(.vertical, 18)
            }
        }
    }

    private func closeRubric() {
        bridge.closeRubricEvaluation()
    }
}

struct RubricCriterionRow: View {
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    let item: RubricCriterionWithLevels
    let selectedLevelId: Int64?
    @Binding var activePopoverLevel: RubricLevel?
    let onSelectLevel: (Int64) -> Void
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.criterion.description_)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(item.levels, id: \.id) { level in
                        levelPill(level)
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(item.levels, id: \.id) { level in
                        levelPill(level)
                    }
                }
            }
        }
        .animation(uiFeatureFlags.interactionAnimation, value: selectedLevelId)
        .onDisappear {
            hoverTask?.cancel()
        }
    }

    private func levelPill(_ level: RubricLevel) -> some View {
        let maxPoints = item.levels.map(\.points).max() ?? 0

        return RubricLevelPill(
            title: level.name,
            points: Double(level.points),
            maxPoints: Double(maxPoints),
            isSelected: selectedLevelId == level.id,
            onSelect: {
                AppleInteractionFeedback.play(.selection)
                onSelectLevel(level.id)
            },
            onShowDescription: {
                activePopoverLevel = level
            }
        )
        .onHover { isHovering in
            if isHovering {
                schedulePopover(for: level)
            } else {
                cancelPopover(for: level)
            }
        }
    }

    private func schedulePopover(for level: RubricLevel) {
        hoverTask?.cancel()
        hoverTask = Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    withAnimation(uiFeatureFlags.popoverOpenAnimation) {
                        activePopoverLevel = level
                    }
                }
            } catch {}
        }
    }

    private func cancelPopover(for level: RubricLevel) {
        hoverTask?.cancel()
        guard activePopoverLevel?.id == level.id else { return }
        withAnimation(uiFeatureFlags.popoverCloseAnimation) {
            activePopoverLevel = nil
        }
    }
}
