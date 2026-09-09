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
                RubricEvaluationBackdrop()

                if let rubric = state.rubricDetail {
                    let selectedScore = state.totalScore
                    let progress = rubric.criteria.isEmpty ? 0.0 : Double(state.selectedLevels.count) / Double(rubric.criteria.count)

                    ScrollView {
                        VStack(alignment: .leading, spacing: EvaluationDesign.sectionSpacing) {
                            headerSection(rubric: rubric, score: selectedScore, progress: progress)
                            if !state.criterionStatements.isEmpty
                                || !(state.criterionLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                EvaluationCriterionSection(
                                    statements: state.criterionStatements,
                                    fallbackText: state.criterionLabel
                                )
                            }
                            criteriaPanel(rubric: rubric)
                        }
                        .padding(EvaluationDesign.screenPadding)
                        .frame(maxWidth: 760)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        saveSection(rubric: rubric, score: selectedScore)
                            .frame(maxWidth: 760)
                            .padding(.horizontal, EvaluationDesign.screenPadding)
                            .padding(.bottom, 8)
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
        }
    }

    // MARK: - Student Navigation & Position

    private var studentPosition: (current: Int, total: Int)? {
        guard let context = bridge.rubricEvaluationCoordinator.context,
              !context.studentIds.isEmpty,
              let idx = context.studentIds.firstIndex(of: state.studentId) else {
            return nil
        }
        return (current: idx + 1, total: context.studentIds.count)
    }

    private var canNavigatePrevious: Bool {
        guard let pos = studentPosition else { return false }
        return pos.current > 1
    }

    private var canNavigateNext: Bool {
        guard let pos = studentPosition else { return false }
        return pos.current < pos.total
    }

    private var studentInitials: String {
        let parts = state.studentName
            .split(separator: " ")
            .filter { !$0.isEmpty }
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        } else if let first = parts.first {
            return String(first.prefix(2)).uppercased()
        }
        return "AL"
    }

    private func qualitativeGradeBand(for score: Double) -> (label: String, color: Color) {
        if score >= 9.0 {
            return ("Sobresaliente", EvaluationDesign.success)
        } else if score >= 7.0 {
            return ("Notable", Color.teal)
        } else if score >= 6.0 {
            return ("Bien", Color.blue)
        } else if score >= 5.0 {
            return ("Suficiente", Color.orange)
        } else {
            return ("Insuficiente", EvaluationDesign.danger)
        }
    }

    private func navigateToPreviousStudent() {
        guard let context = bridge.rubricEvaluationCoordinator.context,
              let idx = context.studentIds.firstIndex(of: state.studentId),
              idx > 0 else { return }
        let previousStudentId = context.studentIds[idx - 1]
        saveAndNavigate(to: previousStudentId)
    }

    private func navigateToNextStudent() {
        guard let context = bridge.rubricEvaluationCoordinator.context,
              let idx = context.studentIds.firstIndex(of: state.studentId),
              idx + 1 < context.studentIds.count else { return }
        let nextStudentId = context.studentIds[idx + 1]
        saveAndNavigate(to: nextStudentId)
    }

    private func saveAndNavigate(to targetStudentId: Int64) {
        AppleInteractionFeedback.play(.selection)
        guard let context = bridge.rubricEvaluationCoordinator.context else { return }
        let columnId = context.columnId
        let rubricId = context.rubricId
        let evaluationId = context.evaluationId
        let classId = context.classId
        let studentIds = context.studentIds

        bridge.saveRubricEvaluation(
            manual: true,
            emitNotebookRefresh: true,
            onSuccess: {
                bridge.rubricEvaluationCoordinator.start(
                    columnId: columnId,
                    rubricId: rubricId,
                    classId: classId,
                    evaluationId: evaluationId,
                    studentIds: studentIds,
                    currentStudentId: targetStudentId
                )
                bridge.openRubricEvaluationFromNotebook(
                    studentId: targetStudentId,
                    columnId: columnId,
                    rubricId: rubricId,
                    evaluationId: evaluationId
                )
            }
        )
    }

    private func saveOnly() {
        AppleInteractionFeedback.play(.selection)
        bridge.saveRubricEvaluation(
            manual: true,
            emitNotebookRefresh: true,
            onSuccess: {
                AppleInteractionFeedback.play(.success)
            }
        )
    }

    private func saveAndNextOrFinish() {
        AppleInteractionFeedback.play(.selection)
        if canNavigateNext {
            navigateToNextStudent()
        } else {
            bridge.saveRubricEvaluation(
                manual: true,
                emitNotebookRefresh: true,
                onSuccess: {
                    bridge.refreshCurrentNotebook()
                    closeRubric()
                }
            )
        }
    }

    // MARK: - Header Section

    private func headerSection(rubric: RubricDetail, score: Double, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            InstrumentEvaluationChromeSurface(role: .header) {
                HStack(alignment: .center, spacing: 12) {
                    Button(action: closeRubric) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cerrar")

                    // Avatar con iniciales
                    Circle()
                        .fill(EvaluationDesign.accent.opacity(0.14))
                        .overlay(
                            Text(studentInitials)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(EvaluationDesign.accent)
                        )
                        .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.studentName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text(rubric.rubric.name)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            if let pos = studentPosition {
                                Text("·")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                                Text("\(pos.current) de \(pos.total)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(EvaluationDesign.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(
                                        Capsule().fill(EvaluationDesign.accent.opacity(0.10))
                                    )
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    // Carrusel Stepper (‹ / ›) con shortcuts ⌘← y ⌘→
                    if let _ = studentPosition {
                        HStack(spacing: 4) {
                            Button(action: navigateToPreviousStudent) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(canNavigatePrevious ? Color.primary : Color.secondary.opacity(0.35))
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle().fill(Color.secondary.opacity(canNavigatePrevious ? 0.08 : 0.03))
                                    )
                                    .contentShape(Circle())
                            }
                            .buttonStyle(NotebookScaleButtonStyle())
                            .disabled(!canNavigatePrevious)
                            .keyboardShortcut(.leftArrow, modifiers: [.command])
                            .help("Alumno anterior (⌘←)")
                            .accessibilityLabel("Alumno anterior")

                            Button(action: navigateToNextStudent) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(canNavigateNext ? Color.primary : Color.secondary.opacity(0.35))
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle().fill(Color.secondary.opacity(canNavigateNext ? 0.08 : 0.03))
                                    )
                                    .contentShape(Circle())
                            }
                            .buttonStyle(NotebookScaleButtonStyle())
                            .disabled(!canNavigateNext)
                            .keyboardShortcut(.rightArrow, modifiers: [.command])
                            .help("Siguiente alumno (⌘→)")
                            .accessibilityLabel("Siguiente alumno")
                        }
                    }

                    // Score Ring + Qualitative Band
                    HStack(spacing: 8) {
                        if progress > 0 {
                            let band = qualitativeGradeBand(for: score)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(band.label)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(band.color)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(band.color.opacity(0.12))
                                    )

                                Text("\(Int(progress * 100))% calificado")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        RubricScoreRing(progress: progress, scoreOutOfTen: score)
                    }
                }
            }

            let criteriaText = rubricCriteriaSummary(rubric: rubric)
            InstrumentEvaluationChromeSurface(role: .context, padding: 0) {
                AssessmentCriteriaDisclosureView(rawText: criteriaText, embedded: true)
            }
        }
    }

    private func rubricCriteriaSummary(rubric: RubricDetail) -> String {
        var parts: [String] = [state.rubricName, rubric.rubric.name, rubric.rubric.description]
        parts.append(contentsOf: rubric.criteria.map { $0.criterion.description_ })
        return parts.joined(separator: " · ")
    }

    // MARK: - Save & Action Section

    private func saveSection(rubric: RubricDetail, score: Double) -> some View {
        let totalCriteria = rubric.criteria.count
        let answeredCriteria = state.selectedLevels.count
        let isComplete = totalCriteria > 0 && answeredCriteria >= totalCriteria
        let progress = totalCriteria > 0 ? Double(answeredCriteria) / Double(totalCriteria) : 0.0

        return InstrumentEvaluationChromeSurface(role: .action, padding: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    saveStatus(answeredCriteria: answeredCriteria, totalCriteria: totalCriteria, isComplete: isComplete, progress: progress, score: score)
                    Spacer(minLength: 8)
                    actionButtons(isComplete: isComplete)
                }

                VStack(alignment: .leading, spacing: 12) {
                    saveStatus(answeredCriteria: answeredCriteria, totalCriteria: totalCriteria, isComplete: isComplete, progress: progress, score: score)
                    actionButtons(isComplete: isComplete)
                }
            }
        }
    }

    private func saveStatus(answeredCriteria: Int, totalCriteria: Int, isComplete: Bool, progress: Double, score: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(isComplete ? "Rúbrica completa" : "Nota provisional: \(IosFormatting.scoreOutOfTen(from: score))")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isComplete ? EvaluationDesign.success : .primary)

                if isComplete {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(EvaluationDesign.success)
                }
            }

            HStack(spacing: 8) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 4)
                        Capsule()
                            .fill(isComplete ? EvaluationDesign.success : EvaluationDesign.accent)
                            .frame(width: max(0, min(g.size.width, g.size.width * CGFloat(progress))), height: 4)
                    }
                }
                .frame(width: 80, height: 4)

                Text("\(answeredCriteria) de \(totalCriteria) criterios")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func actionButtons(isComplete: Bool) -> some View {
        HStack(spacing: 10) {
            Button(action: saveOnly) {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                    Text("Guardar")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(NotebookScaleButtonStyle())
            .accessibilityLabel("Guardar evaluación actual")

            Button(action: saveAndNextOrFinish) {
                HStack(spacing: 6) {
                    Image(systemName: canNavigateNext ? "arrow.right.circle.fill" : "checkmark.circle.fill")
                        .font(.subheadline.weight(.bold))

                    Text(canNavigateNext ? "Guardar y siguiente" : "Guardar y finalizar")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isComplete ? EvaluationDesign.success : EvaluationDesign.accent)
                )
                .shadow(
                    color: (isComplete ? EvaluationDesign.success : EvaluationDesign.accent).opacity(0.28),
                    radius: 4,
                    x: 0,
                    y: 2
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(NotebookScaleButtonStyle())
            .keyboardShortcut(.return, modifiers: [.command])
            .help(canNavigateNext ? "Guardar y siguiente alumno (⌘↩)" : "Guardar y cerrar (⌘↩)")
            .accessibilityLabel(canNavigateNext ? "Guardar y siguiente alumno" : "Guardar y finalizar rúbrica")
        }
    }

    // MARK: - Criteria Panel

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
    let onSelectLevel: (Int64) -> Void

    private var selectedLevel: RubricLevel? {
        item.levels.first { $0.id == selectedLevelId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(item.criterion.description_)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)

                if item.criterion.weight > 0 {
                    Text("\(Int(item.criterion.weight))%")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.secondary.opacity(0.12))
                        )
                }

                Spacer(minLength: 8)

                if let selectedLevel {
                    let maxPts = item.levels.map(\.points).max() ?? 0
                    let tint = RubricsStyle.levelColor(points: Double(selectedLevel.points), maxPoints: Double(maxPts))
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2.weight(.bold))
                        Text("\(selectedLevel.name) · \(selectedLevel.points) pts")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(tint.opacity(0.12))
                    )
                    .overlay(
                        Capsule().stroke(tint.opacity(0.28), lineWidth: 1)
                    )
                    .transition(.scale.combined(with: .opacity))
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.dashed")
                            .font(.caption2)
                        Text("Pendiente")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(item.levels, id: \.id) { level in
                        levelPill(level)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
        }
        .animation(uiFeatureFlags.interactionAnimation, value: selectedLevelId)
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
            description: level.description_
        )
    }
}
