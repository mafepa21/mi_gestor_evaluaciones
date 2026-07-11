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
                EvaluationBackdrop()

                if let rubric = state.rubricDetail {
                    GeometryReader { proxy in
                        let isWide = proxy.size.width >= 720
                        let selectedScore = state.totalScore

                        ScrollView {
                            VStack(alignment: .leading, spacing: EvaluationDesign.sectionSpacing) {
                                headerSection(rubric: rubric, score: selectedScore)

                                if isWide {
                                    HStack(alignment: .top, spacing: EvaluationDesign.sectionSpacing) {
                                        criteriaPanel(rubric: rubric)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        summaryPanel(rubric: rubric)
                                            .frame(width: 300)
                                    }
                                } else {
                                    VStack(spacing: EvaluationDesign.sectionSpacing) {
                                        criteriaPanel(rubric: rubric)
                                        summaryPanel(rubric: rubric)
                                    }
                                }

                                saveSection()
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

            EvaluationScoreBadge(
                title: "Nota actual",
                value: IosFormatting.scoreOutOfTen(from: score)
            )
        }
    }

    private func saveSection() -> some View {
        PrimaryActionButton(label: "Guardar evaluación", systemImage: "square.and.arrow.down.fill") {
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
        PremiumCard.glass(cornerRadius: 32, fillOpacity: 0.88) {
            VStack(alignment: .leading, spacing: EvaluationDesign.sectionSpacing) {
                EvaluationChip(
                    label: "\(rubric.criteria.count) criterios",
                    systemImage: "checklist",
                    tint: EvaluationDesign.accent
                )

                VStack(spacing: 16) {
                    ForEach(rubric.criteria, id: \.criterion.id) { criterion in
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
                    }
                }
            }
        }
    }

    private func summaryPanel(rubric: RubricDetail) -> some View {
        PremiumCard.glass(cornerRadius: 32, fillOpacity: 0.92) {
            VStack(alignment: .leading, spacing: 20) {
                EvaluationChip(
                    label: "Resumen",
                    systemImage: "sparkles",
                    tint: EvaluationDesign.accent
                )

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
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @Environment(\.colorScheme) private var colorScheme
    let item: RubricCriterionWithLevels
    let selectedLevelId: Int64?
    @Binding var activePopoverLevel: RubricLevel?
    let onSelectLevel: (Int64) -> Void
    @State private var hoverTask: Task<Void, Never>?
    @State private var levelsRowWidth: CGFloat = 1000

    private let levelTileMinWidth: CGFloat = 150
    private let levelTileSpacing: CGFloat = 8

    private var fitsSingleRow: Bool {
        let count = CGFloat(item.levels.count)
        guard count > 0 else { return true }
        let requiredWidth = count * levelTileMinWidth + (count - 1) * levelTileSpacing
        return levelsRowWidth >= requiredWidth
    }

    var body: some View {
        PremiumCard.glass(cornerRadius: 24, fillOpacity: 0.96) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.criterion.description_)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Elige el nivel que mejor describe el desempeño")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Group {
                    if fitsSingleRow {
                        HStack(spacing: levelTileSpacing) {
                            ForEach(item.levels, id: \.id) { level in
                                levelTile(level)
                            }
                        }
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: levelTileSpacing), GridItem(.flexible(), spacing: levelTileSpacing)],
                            spacing: levelTileSpacing
                        ) {
                            ForEach(item.levels, id: \.id) { level in
                                levelTile(level)
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: LevelsRowWidthKey.self, value: proxy.size.width)
                    }
                )
                .onPreferenceChange(LevelsRowWidthKey.self) { width in
                    levelsRowWidth = width
                }
            }
        }
        .animation(uiFeatureFlags.interactionAnimation, value: selectedLevelId)
        .onDisappear {
            hoverTask?.cancel()
        }
    }

    private func levelTile(_ level: RubricLevel) -> some View {
        let isSelected = selectedLevelId == level.id

        return EvaluationLevelTile(
            title: level.name,
            subtitle: level.description_ ?? "",
            isSelected: isSelected,
            tint: EvaluationDesign.accent
        ) {
            AppleInteractionFeedback.play(.selection)
            onSelectLevel(level.id)
        }
        .frame(minWidth: 150, minHeight: 92)
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
                schedulePopover(for: level)
            } else {
                cancelPopover(for: level)
            }
        }
    }

    private func levelHelpText(_ level: RubricLevel) -> String {
        let description = level.description_?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !description.isEmpty else { return level.name }
        return "\(level.name): \(description)"
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

    private struct LevelsRowWidthKey: PreferenceKey {
        static var defaultValue: CGFloat = 1000
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
}
