import SwiftUI
import MiGestorKit
#if canImport(UIKit)
import UIKit
#endif

struct RubricBulkEvaluationSheet: View {
    @ObservedObject var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var horizontalScrollOffset: CGFloat = 0
    @State private var levelHoverTask: Task<Void, Never>?
    @State private var focusedBulkStudentId: Int64?
    @State private var focusedBulkCriterionId: Int64?
    @State private var localInjuryStatuses: [Int64: Bool] = [:]
    @State private var savingInjuryStudentIds: Set<Int64> = []
    @State private var activePopoverLevel: RubricLevel?

    private var state: BulkRubricEvaluationUiState? {
        bridge.bulkRubricEvaluationState
    }

    var body: some View {
        NavigationStack {
            ZStack {
                EvaluationBackdrop()

                if state == nil || state!.isLoading {
                    ProgressView("Cargando evaluación masiva...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                } else if let state, let rubric = state.rubricDetail {
                    GeometryReader { proxy in
                        let isWide = proxy.size.width >= 720
                        let className = className(for: state)
                        let cache = BulkRubricEvaluationCache(
                            state: state,
                            rubric: rubric,
                            assessments: bridge.bulkAssessmentSnapshot(),
                            scores: bridge.bulkScoreSnapshot()
                        )

                        ScrollView {
                            VStack(alignment: .leading, spacing: EvaluationDesign.sectionSpacing) {
                                headerSection(
                                    className: className,
                                    rubric: rubric,
                                    state: state,
                                    cache: cache
                                )

                                let hasInjured = !injuredStudents(for: state).isEmpty

                                if isWide {
                                    HStack(alignment: .top, spacing: EvaluationDesign.sectionSpacing) {
                                        evaluationTable(state: state, rubric: rubric, cache: cache)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        if hasInjured {
                                            injuredSidebar(state: state)
                                                .frame(width: 320)
                                                .transition(.move(edge: .trailing).combined(with: .opacity))
                                        }
                                    }
                                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: hasInjured)
                                } else {
                                    VStack(spacing: EvaluationDesign.sectionSpacing) {
                                        compactEvaluationByCriterion(state: state, rubric: rubric, cache: cache)
                                        if hasInjured {
                                            injuredSidebar(state: state)
                                        }
                                    }
                                }
                            }
                            .padding(EvaluationDesign.screenPadding)
                        }
                        .appOnChange(of: state.isSaveSuccessful) { saved in
                            guard saved else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                bridge.closeBulkRubricEvaluation()
                                dismiss()
                            }
                        }
                        #if os(macOS)
                        .focusable()
                        .onMoveCommand { direction in
                            moveFocusedCell(direction: direction, state: state, rubric: rubric)
                        }
                        #endif
                        .overlay(alignment: .topLeading) {
                            hardwareKeyboardShortcuts(state: state, rubric: rubric)
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(EvaluationDesign.danger)
                        Text("No se pudo abrir la evaluación")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                        if let error = state?.error {
                            Text(error)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        } else {
                            Text("La evaluación seleccionada no existe o no se pudo cargar.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        PrimaryActionButton(label: "Cerrar", systemImage: "xmark") {
                            bridge.closeBulkRubricEvaluation()
                            dismiss()
                        }
                        .frame(width: 160)
                    }
                    .padding()
                }
            }
            .appNavigationBarHidden(true)
            .onAppear {
                // Si existía una evaluación individual previa, la cerramos antes de mostrar la masiva.
                bridge.closeRubricEvaluation()
            }
            .onDisappear {
                levelHoverTask?.cancel()
                activePopoverLevel = nil
            }
            .popover(item: $activePopoverLevel, arrowEdge: .bottom) { level in
                RubricLevelDescriptionPopover(level: level)
                    .padding(4)
                    #if os(iOS)
                    .presentationDetents([.fraction(0.32), .medium])
                    .presentationDragIndicator(.visible)
                    #endif
            }
        }
    }

    private func headerSection(
        className: String,
        rubric: RubricDetail,
        state: BulkRubricEvaluationUiState,
        cache: BulkRubricEvaluationCache
    ) -> some View {
        HStack(alignment: .center, spacing: 24) {
            EvaluationIconButton(systemImage: "chevron.left", tint: .primary.opacity(0.8)) {
                bridge.closeBulkRubricEvaluation()
                dismiss()
            }

            EvaluationSectionTitle(
                eyebrow: "Pulsar para volver",
                title: className,
                subtitle: rubric.rubric.name
            )

            Spacer(minLength: 32)

            HStack(spacing: 16) {
                EvaluationChip(
                    label: "\(cache.totalPendingCriteria) pendientes",
                    systemImage: "clock.badge.exclamationmark",
                    tint: cache.totalPendingCriteria == 0 ? EvaluationDesign.success : EvaluationDesign.accent
                )

                VStack(alignment: .trailing, spacing: 4) {
                    PrimaryActionButton(label: "Guardar Todo", systemImage: "square.and.arrow.down.fill") {
                        bridge.bulkSaveAll()
                    }
                    .frame(width: 180)

                    Text(state.isSaving ? "Guardando cambios..." : "Cambios listos para guardar")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(state.isSaving ? EvaluationDesign.accent : .secondary.opacity(0.6))
                        .padding(.trailing, 8)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func compactEvaluationByCriterion(
        state: BulkRubricEvaluationUiState,
        rubric: RubricDetail,
        cache: BulkRubricEvaluationCache
    ) -> some View {
        PremiumCard.glass(cornerRadius: EvaluationDesign.cardRadius, fillOpacity: 0.92) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    EvaluationChip(label: "\(state.students.count) alumnos", systemImage: "person.3.fill")
                    EvaluationChip(label: "\(rubric.criteria.count) criterios", systemImage: "checklist")
                }

                ForEach(rubric.criteria, id: \.criterion.id) { criterion in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(criterion.criterion.description_)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        ForEach(state.students, id: \.id) { student in
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(student.firstName + " " + student.lastName)
                                        .font(.subheadline.weight(.bold))
                                        .lineLimit(1)
                                    scorePill(for: student.id, width: 72, cache: cache)
                                }
                                .frame(width: 144, alignment: .leading)

                                inlineCriterionCell(
                                    studentId: student.id,
                                    criterion: criterion,
                                    width: 220,
                                    cache: cache
                                )
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                                    .fill(appCardBackground(for: colorScheme))
                            )
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private func evaluationTable(
        state: BulkRubricEvaluationUiState,
        rubric: RubricDetail,
        cache: BulkRubricEvaluationCache
    ) -> some View {
        let criterionWidth: CGFloat = 240
        let scoreWidth: CGFloat = 88
        let actionsWidth: CGFloat = 96
        let studentWidth: CGFloat = 224

        return PremiumCard.glass(cornerRadius: EvaluationDesign.cardRadius, fillOpacity: 0.92) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    EvaluationChip(
                        label: "\(state.students.count) alumnos",
                        systemImage: "person.3.fill"
                    )
                    EvaluationChip(
                        label: "\(rubric.criteria.count) criterios",
                        systemImage: "checklist"
                    )

                    if !state.injuredStudents.isEmpty {
                        EvaluationChip(
                            label: "\(state.injuredStudents.count) lesionados",
                            systemImage: "cross.case.fill",
                            tint: EvaluationDesign.danger,
                            isDestructive: true
                        )
                    }
                }

                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: BulkScrollOffsetKey.self,
                                value: proxy.frame(in: .named("GridScroll")).minX
                            )
                        }
                        .frame(width: 0, height: 0)

                        LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
                            Section {
                                ForEach(state.students, id: \.id) { student in
                                    studentRow(
                                        student: student,
                                        state: state,
                                        rubric: rubric,
                                        cache: cache,
                                        studentWidth: studentWidth,
                                        criterionWidth: criterionWidth,
                                        scoreWidth: scoreWidth,
                                        actionsWidth: actionsWidth,
                                        horizontalOffset: horizontalScrollOffset
                                    )
                                }
                            } header: {
                                headerRow(
                                    rubric: rubric,
                                    studentWidth: studentWidth,
                                    criterionWidth: criterionWidth,
                                    scoreWidth: scoreWidth,
                                    actionsWidth: actionsWidth,
                                    horizontalOffset: horizontalScrollOffset
                                )
                            }
                        }
                        .padding(.horizontal, 4)
                        .frame(minWidth: studentWidth + CGFloat(max(rubric.criteria.count, 1)) * criterionWidth + scoreWidth + actionsWidth + 24)
                    }
                }
                .coordinateSpace(name: "GridScroll")
                .onPreferenceChange(BulkScrollOffsetKey.self) { minX in
                    let newOffset = max(0, -minX)
                    if abs(self.horizontalScrollOffset - newOffset) > 0.5 {
                        self.horizontalScrollOffset = newOffset
                    }
                }
            }
        }
    }

    private func headerRow(
        rubric: RubricDetail,
        studentWidth: CGFloat,
        criterionWidth: CGFloat,
        scoreWidth: CGFloat,
        actionsWidth: CGFloat,
        horizontalOffset: CGFloat
    ) -> some View {
        return HStack(spacing: 0) {
            Text("Estudiante")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: studentWidth, alignment: .leading)
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .padding(.vertical, 8)
                .background(appCardBackground(for: colorScheme).opacity(0.98))
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(EvaluationDesign.border.opacity(horizontalOffset > 0 ? 0.8 : 0))
                        .frame(width: 1)
                }
                .offset(x: horizontalOffset > 0 ? horizontalOffset : 0)
                .zIndex(10)

            HStack(spacing: 16) {
                ForEach(rubric.criteria, id: \.criterion.id) { criterion in
                    Text(criterion.criterion.description_)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(width: criterionWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(criterion.criterion.description_)
                }

                Text("Nota")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: scoreWidth, alignment: .center)

                Text("Acciones")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: actionsWidth, alignment: .center)
            }
            .padding(.trailing, 16)
            .padding(.vertical, 8)
        }
        .background(appCardBackground(for: colorScheme).opacity(0.95))
    }

    private func studentRow(
        student: Student,
        state: BulkRubricEvaluationUiState,
        rubric: RubricDetail,
        cache: BulkRubricEvaluationCache,
        studentWidth: CGFloat,
        criterionWidth: CGFloat,
        scoreWidth: CGFloat,
        actionsWidth: CGFloat,
        horizontalOffset: CGFloat
    ) -> some View {
        let isInjured = isStudentInjured(student, cache: cache)
        let pendingCount = cache.pendingCriteriaCount(for: student.id)

        return HStack(spacing: 0) {
            HStack(spacing: 16) {
                EvaluationAvatar(initials: initials(for: student))

                VStack(alignment: .leading, spacing: 2) {
                    Text(student.firstName + " " + student.lastName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if isInjured {
                        Text("Lesionado")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(EvaluationDesign.danger)
                    } else if pendingCount > 0 {
                        Text("\(pendingCount) pendiente\(pendingCount == 1 ? "" : "s")")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(EvaluationDesign.accent.opacity(0.9))
                    } else {
                        Text("Disponible")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(EvaluationDesign.success.opacity(0.8))
                    }
                }
            }
            .frame(width: studentWidth, alignment: .leading)
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                    .fill(appCardBackground(for: colorScheme))
                    .padding(.trailing, -32)
            )
            .overlay(
                RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                    .stroke(isInjured ? EvaluationDesign.danger.opacity(0.08) : EvaluationDesign.border, lineWidth: 1)
                    .padding(.trailing, -32)
            )
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(EvaluationDesign.border.opacity(horizontalOffset > 0 ? 0.6 : 0))
                    .frame(width: 1)
            }
            .offset(x: horizontalOffset > 0 ? horizontalOffset : 0)
            .zIndex(10)

            HStack(spacing: 16) {
                ForEach(rubric.criteria, id: \.criterion.id) { criterion in
                    inlineCriterionCell(
                        studentId: student.id,
                        criterion: criterion,
                        width: criterionWidth,
                        cache: cache
                    )
                }

                scorePill(for: student.id, width: scoreWidth, cache: cache)

                HStack(spacing: 8) {
                    rowActionButton(
                        title: isInjured ? "Quitar lesión" : "Marcar lesión",
                        systemImage: isInjured ? "heart.slash" : "bandage",
                        tint: isInjured ? EvaluationDesign.danger : EvaluationDesign.success,
                        isEnabled: !savingInjuryStudentIds.contains(student.id)
                    ) {
                        Task { await toggleInjuryStatus(for: student, classId: state.classId, cache: cache) }
                    }

                    rowActionButton(
                        title: "Copiar evaluación",
                        systemImage: "doc.on.doc",
                        tint: EvaluationDesign.accent
                    ) {
                        bridge.bulkCopyAssessment(studentId: student.id)
                    }

                    rowActionButton(
                        title: "Pegar evaluación",
                        systemImage: "doc.on.clipboard",
                        tint: EvaluationDesign.success,
                        isEnabled: state.copiedAssessment != nil
                    ) {
                        bridge.bulkPasteAssessment(studentId: student.id)
                    }
                }
                .frame(width: actionsWidth, alignment: .center)
            }
            .padding(.trailing, 16)
            .padding(.vertical, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                .fill(appCardBackground(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                        .stroke(isInjured ? EvaluationDesign.danger.opacity(0.08) : EvaluationDesign.border, lineWidth: 1)
                )
                .shadow(color: EvaluationDesign.shadow.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }

    private func inlineCriterionCell(
        studentId: Int64,
        criterion: RubricCriterionWithLevels,
        width: CGFloat,
        cache: BulkRubricEvaluationCache
    ) -> some View {
        let selectedLevelId = cache.selectedLevelId(studentId: studentId, criterionId: criterion.criterion.id)
        let selectedLevel = criterion.levels.first { $0.id == selectedLevelId }
        let isFocused = focusedBulkStudentId == studentId && focusedBulkCriterionId == criterion.criterion.id

        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(criterion.levels, id: \.id) { level in
                    let isSelected = selectedLevelId == level.id
                    let tint = levelColor(for: level, in: criterion)
                    
                    Button {
                        focusedBulkStudentId = studentId
                        focusedBulkCriterionId = criterion.criterion.id
                        bridge.bulkSelectLevel(
                            studentId: studentId,
                            criterionId: criterion.criterion.id,
                            levelId: level.id
                        )
                    } label: {
                        HStack(spacing: 4) {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(.white)
                            }
                            
                            Text(levelButtonTitle(level))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .foregroundStyle(isSelected ? .white : .primary.opacity(0.72))
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? tint : appMutedCardBackground(for: colorScheme).opacity(0.85))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isSelected ? tint.opacity(0.3) : EvaluationDesign.border, lineWidth: 1)
                        )
                        .scaleEffect(isSelected ? 1.05 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isSelected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(criterion.criterion.description_), \(level.name)")
                    .help(levelHelpText(level))
                    .onHover { isHovering in
                        if isHovering {
                            scheduleLevelPopover(for: level)
                        } else {
                            cancelLevelPopover(for: level)
                        }
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in
                                activePopoverLevel = level
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                            }
                    )
                }
            }

            if let selectedLevel {
                Text(selectedLevel.name)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(levelColor(for: selectedLevel, in: criterion))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(8)
        .frame(width: width)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            focusedBulkStudentId = studentId
            focusedBulkCriterionId = criterion.criterion.id
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selectedLevel == nil ? Color.clear : levelColor(for: selectedLevel, in: criterion).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isFocused ? EvaluationDesign.accent.opacity(0.65) : Color.clear, lineWidth: 2)
        )
    }

    private func levelButtonTitle(_ level: RubricLevel) -> String {
        let trimmed = level.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 10 {
            return trimmed
        }
        return String(trimmed.prefix(9)) + "…"
    }

    private func levelHelpText(_ level: RubricLevel) -> String {
        let description = level.description_?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !description.isEmpty else { return level.name }
        return "\(level.name): \(description)"
    }

    private func scheduleLevelPopover(for level: RubricLevel) {
        levelHoverTask?.cancel()
        levelHoverTask = Task {
            do {
                try await Task.sleep(nanoseconds: 600_000_000)
                await MainActor.run {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        activePopoverLevel = level
                    }
                }
            } catch {}
        }
    }

    private func cancelLevelPopover(for level: RubricLevel) {
        levelHoverTask?.cancel()
        guard activePopoverLevel?.id == level.id else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            activePopoverLevel = nil
        }
    }

    private func levelColor(for level: RubricLevel?, in criterion: RubricCriterionWithLevels) -> Color {
        guard let level else { return EvaluationDesign.accent }
        let maxPoints = criterion.levels.map(\.points).max() ?? 0
        guard maxPoints > 0 else { return EvaluationDesign.accent }
        let ratio = Double(level.points) / Double(maxPoints)

        switch ratio {
        case 0.8...:
            return EvaluationDesign.success
        case 0.6..<0.8:
            return EvaluationDesign.accent
        case 0.4..<0.6:
            return .orange
        default:
            return EvaluationDesign.danger
        }
    }

    private func scorePill(for studentId: Int64, width: CGFloat, cache: BulkRubricEvaluationCache) -> some View {
        let score = cache.score(for: studentId)
        let scoreText = score.map { String(format: "%.1f", $0) } ?? "—"
        let tint = (score ?? 0) >= 5 ? EvaluationDesign.success : EvaluationDesign.danger

        return Text(scoreText)
            .font(.system(size: 20, weight: .black, design: .rounded))
            .foregroundStyle(score == nil ? .secondary : tint)
            .frame(width: width, alignment: .center)
            .frame(minHeight: 44)
            .background(
                score == nil ? Color.clear : tint.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
    }

    private func rowActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isEnabled ? tint : .secondary.opacity(0.35))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(isEnabled ? tint.opacity(0.12) : Color(.systemFill).opacity(0.25))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .help(title)
    }

    @ViewBuilder
    private func hardwareKeyboardShortcuts(
        state: BulkRubricEvaluationUiState,
        rubric: RubricDetail
    ) -> some View {
        Group {
            Button("Guardar rúbrica masiva") {
                bridge.bulkSaveAll()
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button("Cerrar rúbrica masiva") {
                bridge.closeBulkRubricEvaluation()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            ForEach(1...5, id: \.self) { position in
                Button("Nivel \(position)") {
                    selectFocusedLevel(position: position, state: state, rubric: rubric)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(position)")), modifiers: [])
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0.001)
        .accessibilityHidden(true)
    }

    #if os(macOS)
    private func moveFocusedCell(
        direction: MoveCommandDirection,
        state: BulkRubricEvaluationUiState,
        rubric: RubricDetail
    ) {
        guard !state.students.isEmpty, !rubric.criteria.isEmpty else { return }
        let studentIds = state.students.map(\.id)
        let criterionIds = rubric.criteria.map { $0.criterion.id }
        let currentStudentIndex = focusedBulkStudentId.flatMap { studentIds.firstIndex(of: $0) } ?? 0
        let currentCriterionIndex = focusedBulkCriterionId.flatMap { criterionIds.firstIndex(of: $0) } ?? 0

        let nextStudentIndex: Int
        let nextCriterionIndex: Int
        switch direction {
        case .up:
            nextStudentIndex = max(0, currentStudentIndex - 1)
            nextCriterionIndex = currentCriterionIndex
        case .down:
            nextStudentIndex = min(studentIds.count - 1, currentStudentIndex + 1)
            nextCriterionIndex = currentCriterionIndex
        case .left:
            nextStudentIndex = currentStudentIndex
            nextCriterionIndex = max(0, currentCriterionIndex - 1)
        case .right:
            nextStudentIndex = currentStudentIndex
            nextCriterionIndex = min(criterionIds.count - 1, currentCriterionIndex + 1)
        @unknown default:
            nextStudentIndex = currentStudentIndex
            nextCriterionIndex = currentCriterionIndex
        }

        focusedBulkStudentId = studentIds[nextStudentIndex]
        focusedBulkCriterionId = criterionIds[nextCriterionIndex]
    }
    #endif

    private func selectFocusedLevel(
        position: Int,
        state: BulkRubricEvaluationUiState,
        rubric: RubricDetail
    ) {
        guard !state.students.isEmpty, !rubric.criteria.isEmpty else { return }
        let studentId = focusedBulkStudentId ?? state.students.first?.id
        let criterion = focusedBulkCriterionId.flatMap { criterionId in
            rubric.criteria.first { $0.criterion.id == criterionId }
        } ?? rubric.criteria.first
        guard let studentId,
              let criterion,
              criterion.levels.indices.contains(position - 1) else { return }
        focusedBulkStudentId = studentId
        focusedBulkCriterionId = criterion.criterion.id
        bridge.bulkSelectLevel(
            studentId: studentId,
            criterionId: criterion.criterion.id,
            levelId: criterion.levels[position - 1].id
        )
    }

    private func injuredSidebar(state: BulkRubricEvaluationUiState) -> some View {
        let injuredStudents = injuredStudents(for: state)
        return PremiumCard.glass(cornerRadius: 32, fillOpacity: 0.90) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    EvaluationChip(
                        label: "Lesionados",
                        systemImage: "cross.case.fill",
                        tint: EvaluationDesign.danger,
                        isDestructive: true
                    )
                    Spacer()
                    Text("\(injuredStudents.count)")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(EvaluationDesign.danger)
                }

                if injuredStudents.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.4))
                        Text("No hay alumnos lesionados")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    VStack(spacing: 12) {
                        ForEach(injuredStudents, id: \.id) { student in
                            HStack(spacing: 12) {
                                EvaluationAvatar(initials: initials(for: student), tint: EvaluationDesign.danger)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(student.firstName + " " + student.lastName)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(.primary)
                                    Text("Necesita revisión")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                                Button {
                                    Task {
                                        guard let rubric = state.rubricDetail else { return }
                                        let cache = BulkRubricEvaluationCache(
                                            state: state,
                                            rubric: rubric,
                                            assessments: bridge.bulkAssessmentSnapshot(),
                                            scores: bridge.bulkScoreSnapshot()
                                        )
                                        await toggleInjuryStatus(for: student, classId: state.classId, cache: cache)
                                    }
                                } label: {
                                    Image(systemName: "heart.slash")
                                        .foregroundStyle(EvaluationDesign.danger)
                                }
                                .buttonStyle(.plain)
                                .disabled(savingInjuryStudentIds.contains(student.id))
                            }
                            .padding(16)
                            .background(appCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                                    .stroke(EvaluationDesign.danger.opacity(0.10), lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }

    private func isStudentInjured(_ student: Student, cache: BulkRubricEvaluationCache) -> Bool {
        localInjuryStatuses[student.id] ?? cache.injuredStudentIds.contains(student.id)
    }

    private func injuredStudents(for state: BulkRubricEvaluationUiState) -> [Student] {
        state.students.filter { student in
            localInjuryStatuses[student.id] ?? state.injuredStudents.contains { $0.id == student.id }
        }
    }

    @MainActor
    private func toggleInjuryStatus(
        for student: Student,
        classId: Int64,
        cache: BulkRubricEvaluationCache
    ) async {
        let previousValue = isStudentInjured(student, cache: cache)
        let newValue = !previousValue
        localInjuryStatuses[student.id] = newValue
        savingInjuryStudentIds.insert(student.id)
        defer { savingInjuryStudentIds.remove(student.id) }

        do {
            try await bridge.updateStudentInjuryStatus(
                studentId: student.id,
                isInjured: newValue,
                classId: classId
            )
            bridge.status = newValue ? "Alumno marcado con lesión." : "Lesión retirada."
        } catch {
            localInjuryStatuses[student.id] = previousValue
            bridge.status = "No se pudo actualizar la lesión: \(error.localizedDescription)"
        }
    }

    private func className(for state: BulkRubricEvaluationUiState) -> String {
        bridge.classes.first(where: { $0.id == state.classId })?.name ?? "Clase"
    }

    private func initials(for student: Student) -> String {
        let first = student.firstName.prefix(1)
        let last = student.lastName.prefix(1)
        return String(first + last)
    }
    
    private struct BulkScrollOffsetKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
}

private struct BulkHoveredLevelKey: Hashable {
    let studentId: Int64
    let criterionId: Int64
    let levelId: Int64
}

private struct BulkRubricCellKey: Hashable {
    let studentId: Int64
    let criterionId: Int64
}

private struct BulkRubricEvaluationCache {
    private let selectedLevels: [BulkRubricCellKey: Int64]
    private let scores: [Int64: Double]
    private let criteriaCount: Int
    private let completedCriteriaCountByStudentId: [Int64: Int]
    let injuredStudentIds: Set<Int64>

    var totalPendingCriteria: Int {
        completedCriteriaCountByStudentId.keys.reduce(0) { total, studentId in
            total + pendingCriteriaCount(for: studentId)
        }
    }

    init(
        state: BulkRubricEvaluationUiState,
        rubric: RubricDetail,
        assessments: [Int64: [Int64: Int64]],
        scores: [Int64: Double]
    ) {
        criteriaCount = rubric.criteria.count
        var selectedLevels: [BulkRubricCellKey: Int64] = [:]
        var completedCriteriaCountByStudentId: [Int64: Int] = [:]

        for student in state.students {
            completedCriteriaCountByStudentId[student.id] = 0
        }

        for (studentId, studentMap) in assessments {
            var completedCount = completedCriteriaCountByStudentId[studentId] ?? 0
            for (criterionId, levelId) in studentMap {
                selectedLevels[BulkRubricCellKey(studentId: studentId, criterionId: criterionId)] = levelId
                completedCount += 1
            }
            completedCriteriaCountByStudentId[studentId] = min(completedCount, criteriaCount)
        }

        self.selectedLevels = selectedLevels
        self.scores = scores
        self.completedCriteriaCountByStudentId = completedCriteriaCountByStudentId
        self.injuredStudentIds = Set(state.injuredStudents.map(\.id))
    }

    func selectedLevelId(studentId: Int64, criterionId: Int64) -> Int64? {
        selectedLevels[BulkRubricCellKey(studentId: studentId, criterionId: criterionId)]
    }

    func score(for studentId: Int64) -> Double? {
        scores[studentId]
    }

    func pendingCriteriaCount(for studentId: Int64) -> Int {
        max(0, criteriaCount - (completedCriteriaCountByStudentId[studentId] ?? 0))
    }
}

struct RubricLevelDescriptionPopover: View {
    let level: RubricLevel

    private var trimmedDescription: String {
        level.description_?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(EvaluationDesign.accent)

                Text(level.name)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 12)

                Text("\(Int(level.points)) pts")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(EvaluationDesign.accent)
                    )
            }

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)

            if trimmedDescription.isEmpty {
                Text("Sin descripción adicional para este nivel.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Text(trimmedDescription)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(minWidth: 280, maxWidth: 360)
    }
}
