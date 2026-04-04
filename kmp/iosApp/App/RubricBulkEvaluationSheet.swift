import SwiftUI
import MiGestorKit

struct RubricBulkEvaluationSheet: View {
    @ObservedObject var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredLevelKey: HoveredLevelKey?
    @State private var popoverDismissalTask: Task<Void, Never>? = nil
    @State private var hoverAnchorPoint: CGPoint?
    @State private var suppressedLevelKey: HoveredLevelKey?
    @State private var horizontalScrollOffset: CGFloat = 0

    private struct HoveredLevelKey: Hashable {
        let studentId: Int64
        let criterionId: Int64
        let levelId: Int64
    }

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
                                        evaluationTable(state: state, rubric: rubric)
                                        if hasInjured {
                                            injuredSidebar(state: state)
                                        }
                                    }
                                }
                            }
                            .padding(EvaluationDesign.screenPadding)
                        }
                        .onChange(of: state.isSaveSuccessful) { saved in
                            guard saved else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                bridge.refreshCurrentNotebook()
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
            .navigationBarHidden(true)
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

                    Text(state.isSaving ? "Guardando cambios..." : "Auto-guardado activo")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(state.isSaving ? EvaluationDesign.accent : .secondary.opacity(0.6))
                        .padding(.trailing, 8)
                }
            }
        }
        .padding(.bottom, 8)
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
                    criterionCell(
                        studentId: student.id,
                        criterion: criterion,
                        criterionWidth: criterionWidth
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

    private func criterionCell(
        studentId: Int64,
        criterion: RubricCriterionWithLevels,
        criterionWidth: CGFloat
    ) -> some View {
        let selectedLevelId = bridge.bulkSelectedLevelId(
            studentId: studentId,
            criterionId: criterion.criterion.id
        )

        return HStack(spacing: 4) {
            ForEach(criterion.levels, id: \.id) { level in
                let isSelected = selectedLevelId == level.id
                let levelKey = HoveredLevelKey(
                    studentId: studentId,
                    criterionId: criterion.criterion.id,
                    levelId: level.id
                )
                let hasDescription = !(level.description_?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty ?? true)
                Button {
                    bridge.bulkSelectLevel(
                        studentId: studentId,
                        criterionId: criterion.criterion.id,
                        levelId: level.id
                    )
                } label: {
                    VStack(spacing: 4) {
                        Text(level.name)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        
                        if level.points > 0 {
                            Text("\(Int(level.points)) pts")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .opacity(0.6)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .padding(.horizontal, 4)
                    .foregroundStyle(isSelected ? .white : .primary.opacity(0.8))
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? EvaluationDesign.accent : Color(.systemFill).opacity(0.3))
                    )
                }
                .buttonStyle(.plain)
                .hoverEffect(.lift)
                .zIndex(hoveredLevelKey == levelKey ? 100 : 0)
                .onHover { isHovering in
                    guard hasDescription else { return }
                    if isHovering {
                        guard suppressedLevelKey != levelKey else { return }
                        activateHover(for: levelKey)
                    } else {
                        clearHover(for: levelKey)
                        if suppressedLevelKey == levelKey {
                            suppressedLevelKey = nil
                        }
                    }
                }
                .modifier(ContinuousHoverIfAvailable { phase in
                    guard hasDescription else { return }
                    switch phase {
                    case .active(let location):
                        guard suppressedLevelKey != levelKey else { return }

                        if hoveredLevelKey != levelKey {
                            hoverAnchorPoint = location
                            activateHover(for: levelKey)
                            return
                        }

                        guard let anchor = hoverAnchorPoint else {
                            hoverAnchorPoint = location
                            return
                        }

                        let deltaX = location.x - anchor.x
                        let deltaY = location.y - anchor.y
                        let moved = (deltaX * deltaX + deltaY * deltaY) > 4 // 2pt
                        if moved {
                            suppressedLevelKey = levelKey
                            clearHover(for: levelKey)
                        }
                    case .ended:
                        clearHover(for: levelKey)
                        if suppressedLevelKey == levelKey {
                            suppressedLevelKey = nil
                        }
                    }
                })
                .overlay(alignment: .center) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .offset(y: -68) // Anclaje sobre la fila anterior
                        .popover(
                            isPresented: Binding(
                                get: { hoveredLevelKey == levelKey && hasDescription },
                                set: { if !$0 { withAnimation { hoveredLevelKey = nil } } }
                            ),
                            arrowEdge: .bottom
                        ) {
                            levelHoverPopover(level: level)
                                .padding(4)
                                .modifier(PresentationCompactAdaptationIfAvailable())
                        }
                }
            }
        }
        .padding(8)
        .frame(width: criterionWidth)
        .background(appMutedCardBackground(for: colorScheme).opacity(0.88), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func scorePill(for studentId: Int64, width: CGFloat) -> some View {
        let score = bridge.bulkScore(studentId: studentId)
        let scoreText = score.map { String(format: "%.1f", $0) } ?? "—"
        let tint = (score ?? 0) >= 5 ? EvaluationDesign.success : EvaluationDesign.danger

        return VStack(alignment: .leading, spacing: 4) {
            Text("Nota")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(scoreText)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(width: width, alignment: .leading)
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

    // We use level.name directly now instead of levelLabel method to show the real valuation.
    @ViewBuilder
    private func levelHoverPopover(level: RubricLevel) -> some View {
        let description = level.description_?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        VStack(alignment: .leading, spacing: 8) {
            Text(level.name)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("\(Int(level.points)) puntos")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(EvaluationDesign.accent)

            if !description.isEmpty {
                Text(description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Este nivel no tiene una descripción detallada definida.")
                    .font(.system(size: 12, weight: .regular))
                    .italic()
                    .foregroundStyle(.secondary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 250, alignment: .leading)
        .padding(12)
    }

    private func className(for state: BulkRubricEvaluationUiState) -> String {
        bridge.classes.first(where: { $0.id == state.classId })?.name ?? "Clase"
    }

    private func initials(for student: Student) -> String {
        let first = student.firstName.prefix(1)
        let last = student.lastName.prefix(1)
        return String(first + last)
    }
    
    private struct PresentationCompactAdaptationIfAvailable: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 16.4, *) {
                content.presentationCompactAdaptation(.popover)
            } else {
                content
            }
        }
    }

    private func activateHover(for levelKey: HoveredLevelKey) {
        popoverDismissalTask?.cancel()
        hoveredLevelKey = levelKey
        popoverDismissalTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000) // Máximo 10 segundos visible por posición.
            if Task.isCancelled { return }
            await MainActor.run {
                if hoveredLevelKey == levelKey {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        hoveredLevelKey = nil
                        hoverAnchorPoint = nil
                    }
                }
            }
        }
    }

    private func clearHover(for levelKey: HoveredLevelKey) {
        guard hoveredLevelKey == levelKey else { return }
        popoverDismissalTask?.cancel()
        popoverDismissalTask = nil
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            hoveredLevelKey = nil
            hoverAnchorPoint = nil
        }
    }

    private struct ContinuousHoverIfAvailable: ViewModifier {
        let onPhase: (HoverPhase) -> Void

        func body(content: Content) -> some View {
            if #available(iOS 17.0, *) {
                content.onContinuousHover(coordinateSpace: .local, perform: onPhase)
            } else {
                content
            }
        }
    }
    private struct BulkScrollOffsetKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
}
