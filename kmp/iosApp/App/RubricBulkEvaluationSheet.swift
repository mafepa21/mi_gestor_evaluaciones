import SwiftUI
import MiGestorKit

struct RubricBulkEvaluationSheet: View {
    @ObservedObject var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var horizontalScrollOffset: CGFloat = 0

    private var state: BulkRubricEvaluationUiState? {
        bridge.bulkRubricEvaluationState
    }

    var body: some View {
        NavigationStack {
            ZStack {
                EvaluationBackdrop()

                if let state, state.isLoading {
                    ProgressView("Cargando evaluación masiva...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                } else if let state, let rubric = state.rubricDetail {
                    GeometryReader { proxy in
                        let isWide = proxy.size.width >= 980
                        let className = className(for: state)

                        ScrollView {
                            VStack(alignment: .leading, spacing: EvaluationDesign.sectionSpacing) {
                                headerSection(
                                    className: className,
                                    rubric: rubric,
                                    state: state
                                )

                                let hasInjured = !state.injuredStudents.isEmpty

                                if isWide {
                                    HStack(alignment: .top, spacing: EvaluationDesign.sectionSpacing) {
                                        evaluationTable(state: state, rubric: rubric)
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
                                        compactEvaluationByCriterion(state: state, rubric: rubric)
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
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("No se pudo cargar la evaluación.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .appNavigationBarHidden(true)
            .onAppear {
                // Si existía una evaluación individual previa, la cerramos antes de mostrar la masiva.
                bridge.closeRubricEvaluation()
            }
        }
    }

    private func headerSection(
        className: String,
        rubric: RubricDetail,
        state: BulkRubricEvaluationUiState
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
                VStack(alignment: .trailing, spacing: 4) {
                    EvaluationPrimaryButton(label: "Guardar Todo", systemImage: "square.and.arrow.down.fill") {
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
        rubric: RubricDetail
    ) -> some View {
        EvaluationGlassCard(cornerRadius: EvaluationDesign.cardRadius, fillOpacity: 0.92) {
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
                                    scorePill(for: student.id, width: 72)
                                }
                                .frame(width: 144, alignment: .leading)

                                inlineCriterionCell(
                                    studentId: student.id,
                                    criterion: criterion,
                                    width: 220
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
        rubric: RubricDetail
    ) -> some View {
        let criterionWidth: CGFloat = 180
        let scoreWidth: CGFloat = 88
        let actionsWidth: CGFloat = 92
        let studentWidth: CGFloat = 220

        return EvaluationGlassCard(cornerRadius: EvaluationDesign.cardRadius, fillOpacity: 0.92) {
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
                        .lineLimit(1)
                        .frame(width: criterionWidth, alignment: .leading)
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
        studentWidth: CGFloat,
        criterionWidth: CGFloat,
        scoreWidth: CGFloat,
        actionsWidth: CGFloat,
        horizontalOffset: CGFloat
    ) -> some View {
        let isInjured = state.injuredStudents.contains(where: { $0.id == student.id })

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
                        width: criterionWidth
                    )
                }

                scorePill(for: student.id, width: scoreWidth)

                HStack(spacing: 8) {
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
        width: CGFloat
    ) -> some View {
        let selectedLevelId = bridge.bulkSelectedLevelId(
            studentId: studentId,
            criterionId: criterion.criterion.id
        )
        let selectedLevel = criterion.levels.first { $0.id == selectedLevelId }

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(criterion.levels, id: \.id) { level in
                    let isSelected = selectedLevelId == level.id
                    let tint = levelColor(for: level, in: criterion)
                    Button {
                        bridge.bulkSelectLevel(
                            studentId: studentId,
                            criterionId: criterion.criterion.id,
                            levelId: level.id
                        )
                    } label: {
                        Circle()
                            .fill(isSelected ? tint : appMutedCardBackground(for: colorScheme).opacity(0.92))
                            .frame(width: 32, height: 32)
                            .overlay {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .black))
                                        .foregroundStyle(.white)
                                } else {
                                    Text(levelButtonTitle(level))
                                        .font(.system(size: 10, weight: .black, design: .rounded))
                                        .foregroundStyle(.primary.opacity(0.62))
                                }
                            }
                            .overlay(
                                Circle()
                                    .stroke(isSelected ? tint.opacity(0.35) : EvaluationDesign.border.opacity(0.75), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(criterion.criterion.description_), \(level.name)")
                    .help(levelHelpText(level))
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
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selectedLevel == nil ? Color.clear : levelColor(for: selectedLevel, in: criterion).opacity(0.08))
        )
    }

    private func levelButtonTitle(_ level: RubricLevel) -> String {
        let trimmed = level.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 7 {
            return trimmed
        }
        return String(trimmed.prefix(7))
    }

    private func levelHelpText(_ level: RubricLevel) -> String {
        let description = level.description_?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !description.isEmpty else { return level.name }
        return "\(level.name): \(description)"
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

    private func scorePill(for studentId: Int64, width: CGFloat) -> some View {
        let score = bridge.bulkScore(studentId: studentId)
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

    private func injuredSidebar(state: BulkRubricEvaluationUiState) -> some View {
        EvaluationGlassCard(cornerRadius: 32, fillOpacity: 0.90) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    EvaluationChip(
                        label: "Lesionados",
                        systemImage: "cross.case.fill",
                        tint: EvaluationDesign.danger,
                        isDestructive: true
                    )
                    Spacer()
                    Text("\(state.injuredStudents.count)")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(EvaluationDesign.danger)
                }

                if state.injuredStudents.isEmpty {
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
                        ForEach(state.injuredStudents, id: \.id) { student in
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
                                Image(systemName: "bandage.fill")
                                    .foregroundStyle(EvaluationDesign.danger)
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
