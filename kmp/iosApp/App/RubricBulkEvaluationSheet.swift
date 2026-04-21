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
        #if os(macOS)
        RubricBulkEvaluationMacView(bridge: bridge)
        #else
        rubricBulkEvaluationIOSBody
        #endif
    }

    private var rubricBulkEvaluationIOSBody: some View {
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
                .appHoverLiftEffect()
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
            HStack(alignment: .top, spacing: 8) {
                Text(level.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Button("Cerrar") {
                    withAnimation {
                        hoveredLevelKey = nil
                        hoverAnchorPoint = nil
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
            }

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

#if os(macOS)
private enum BulkEvaluationMacFilterMode: String, CaseIterable, Identifiable {
    case all
    case pending
    case injured
    case failing
    case incomplete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Todos"
        case .pending: return "Pendientes"
        case .injured: return "Lesionados"
        case .failing: return "Suspensos"
        case .incomplete: return "Incompletos"
        }
    }
}

private struct RubricBulkEvaluationMacView: View {
    @ObservedObject var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var filterMode: BulkEvaluationMacFilterMode = .all
    @State private var selectedStudentId: Int64?
    @State private var selectedCriterionId: Int64?
    @State private var showsInjuredInspector = true

    private var state: BulkRubricEvaluationUiState? { bridge.bulkRubricEvaluationState }

    private var rubric: RubricDetail? { state?.rubricDetail }

    private var filteredStudents: [Student] {
        guard let state else { return [] }
        return state.students.filter(matchesSearch).filter(matchesFilter)
    }

    private var selectedStudent: Student? {
        filteredStudents.first(where: { $0.id == selectedStudentId }) ?? filteredStudents.first
    }

    private var selectedCriterion: RubricCriterionWithLevels? {
        rubric?.criteria.first(where: { $0.criterion.id == selectedCriterionId }) ?? rubric?.criteria.first
    }

    var body: some View {
        Group {
            if let state, let rubric {
                HSplitView {
                    BulkEvaluationMacSynchronizedTable(
                        bridge: bridge,
                        state: state,
                        rubric: rubric,
                        students: filteredStudents,
                        selectedStudentId: Binding(
                            get: { selectedStudent?.id },
                            set: { selectedStudentId = $0 }
                        ),
                        selectedCriterionId: Binding(
                            get: { selectedCriterion?.criterion.id },
                            set: { selectedCriterionId = $0 }
                        )
                    )
                    .frame(minWidth: 760, maxWidth: .infinity, maxHeight: .infinity)

                    BulkEvaluationMacInspector(
                        bridge: bridge,
                        rubric: rubric,
                        student: selectedStudent,
                        criterion: selectedCriterion,
                        isInjured: selectedStudent.map { student in
                            state.injuredStudents.contains(where: { $0.id == student.id })
                        } ?? false,
                        injuredStudents: showsInjuredInspector ? state.injuredStudents : [],
                        missingCriteriaCount: selectedStudent.map { missingCriteriaCount(studentId: $0.id, rubric: rubric) } ?? 0,
                        onClose: close
                    )
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
                .toolbar {
                    BulkEvaluationMacToolbar(
                        bridge: bridge,
                        title: rubric.rubric.name,
                        className: className(for: state),
                        filterMode: $filterMode,
                        searchText: $searchText,
                        showsInjuredInspector: $showsInjuredInspector,
                        onClose: close
                    )
                }
                .onAppear {
                    bridge.closeRubricEvaluation()
                    hydrateSelectionIfNeeded(using: rubric)
                }
                .onChange(of: filterMode) { _ in
                    hydrateSelectionIfNeeded(using: rubric)
                }
                .onChange(of: searchText) { _ in
                    hydrateSelectionIfNeeded(using: rubric)
                }
                .onChange(of: state.students.count) { _ in
                    hydrateSelectionIfNeeded(using: rubric)
                }
                .onChange(of: state.isSaveSuccessful) { saved in
                    guard saved else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        bridge.refreshCurrentNotebook()
                        close()
                    }
                }
            } else if let state, state.isLoading {
                ProgressView("Cargando evaluación masiva...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No se pudo cargar la evaluación",
                    systemImage: "exclamationmark.triangle",
                    description: Text("La matriz de evaluación no está disponible en este momento.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func close() {
        bridge.closeBulkRubricEvaluation()
        dismiss()
    }

    private func hydrateSelectionIfNeeded(using rubric: RubricDetail) {
        if let selectedStudentId,
           filteredStudents.contains(where: { $0.id == selectedStudentId }) == false {
            self.selectedStudentId = filteredStudents.first?.id
        } else if selectedStudentId == nil {
            selectedStudentId = filteredStudents.first?.id
        }

        if let selectedCriterionId,
           rubric.criteria.contains(where: { $0.criterion.id == selectedCriterionId }) == false {
            self.selectedCriterionId = rubric.criteria.first?.criterion.id
        } else if selectedCriterionId == nil {
            selectedCriterionId = rubric.criteria.first?.criterion.id
        }
    }

    private func matchesSearch(student: Student) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let haystack = "\(student.firstName) \(student.lastName)".folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let needle = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return haystack.contains(needle)
    }

    private func matchesFilter(student: Student) -> Bool {
        switch filterMode {
        case .all:
            return true
        case .pending, .incomplete:
            guard let rubric else { return true }
            return missingCriteriaCount(studentId: student.id, rubric: rubric) > 0
        case .injured:
            return student.isInjured
        case .failing:
            guard let score = bridge.bulkScore(studentId: student.id) else { return true }
            return score < 5
        }
    }

    private func missingCriteriaCount(studentId: Int64, rubric: RubricDetail) -> Int {
        rubric.criteria.reduce(into: 0) { partial, criterion in
            if bridge.bulkSelectedLevelId(studentId: studentId, criterionId: criterion.criterion.id) == nil {
                partial += 1
            }
        }
    }

    private func className(for state: BulkRubricEvaluationUiState) -> String {
        bridge.classes.first(where: { $0.id == state.classId })?.name ?? "Clase"
    }
}

private struct BulkEvaluationMacToolbar: ToolbarContent {
    let bridge: KmpBridge
    let title: String
    let className: String
    @Binding var filterMode: BulkEvaluationMacFilterMode
    @Binding var searchText: String
    @Binding var showsInjuredInspector: Bool
    let onClose: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(className)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        ToolbarItem(placement: .principal) {
            Picker("Filtro", selection: $filterMode) {
                ForEach(BulkEvaluationMacFilterMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: $showsInjuredInspector) {
                Image(systemName: "cross.case")
            }
            .toggleStyle(.button)
            .help("Mostrar inspector de lesionados")

            TextField("Buscar alumno", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)

            Button("Guardar") {
                bridge.bulkSaveAll()
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button("Cerrar") {
                onClose()
            }
            .keyboardShortcut(.cancelAction)
        }
    }
}

private struct BulkEvaluationMacSynchronizedTable: View {
    @ObservedObject var bridge: KmpBridge
    let state: BulkRubricEvaluationUiState
    let rubric: RubricDetail
    let students: [Student]
    @Binding var selectedStudentId: Int64?
    @Binding var selectedCriterionId: Int64?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                sidebarHeader
                ScrollView(.vertical, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: rowSpacing) {
                            Color.clear
                                .frame(height: headerHeight)
                            ForEach(students, id: \.id) { student in
                                sidebarRow(student)
                            }
                        }
                        .padding(12)
                        .frame(width: 290, alignment: .topLeading)
                        .background(Color(nsColor: .controlBackgroundColor))

                        Divider()

                        ScrollView(.horizontal, showsIndicators: true) {
                            VStack(spacing: rowSpacing) {
                                gridHeader
                                VStack(spacing: rowSpacing) {
                                    ForEach(students, id: \.id) { student in
                                        gridRow(student)
                                    }
                                }
                            }
                            .padding(12)
                            .frame(
                                minWidth: CGFloat(max(rubric.criteria.count, 1)) * criterionColumnWidth
                                    + scoreColumnWidth
                                    + 24,
                                alignment: .topLeading
                            )
                        }
                        .background(Color(nsColor: .windowBackgroundColor))
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private let criterionColumnWidth: CGFloat = 152
    private let scoreColumnWidth: CGFloat = 96
    private let rowHeight: CGFloat = 56
    private let headerHeight: CGFloat = 72
    private let rowSpacing: CGFloat = 8

    private var sidebarHeader: some View {
        HStack {
            Text("Alumnado")
                .font(.headline)
            Spacer()
            Text("\(students.count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 290, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var gridHeader: some View {
        HStack(spacing: 12) {
            ForEach(rubric.criteria, id: \.criterion.id) { criterion in
                VStack(alignment: .leading, spacing: 4) {
                    Text(criterion.criterion.description_)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text("Peso \(Int((criterion.criterion.weight * 100).rounded()))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: criterionColumnWidth, alignment: .leading)
            }

            Text("Nota")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: scoreColumnWidth)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(height: headerHeight, alignment: .center)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func sidebarRow(_ student: Student) -> some View {
        let isInjured = state.injuredStudents.contains(where: { $0.id == student.id })
        return Button {
            selectedStudentId = student.id
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(isInjured ? Color.red.opacity(0.18) : Color.accentColor.opacity(0.18))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Text(initials(for: student))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(student.firstName) \(student.lastName)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(bridge.bulkScore(studentId: student.id).map { String(format: "%.1f", $0) } ?? "—")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        if missingCriteriaCount(student.id) > 0 {
                            Text("\(missingCriteriaCount(student.id)) pendientes")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Spacer()

                if isInjured {
                    Image(systemName: "bandage")
                        .foregroundStyle(.red)
                }
            }
            .padding(10)
            .frame(height: rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selectedStudentId == student.id ? Color.accentColor.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func gridRow(_ student: Student) -> some View {
        let isSelected = selectedStudentId == student.id

        return HStack(spacing: 12) {
            ForEach(rubric.criteria, id: \.criterion.id) { criterion in
                criterionColumn(student: student, criterion: criterion)
            }

            scorePill(for: student.id)
                .frame(width: scoreColumnWidth)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.28) : Color.black.opacity(0.05), lineWidth: 1)
        )
        .onTapGesture {
            selectedStudentId = student.id
        }
    }

    private func criterionColumn(student: Student, criterion: RubricCriterionWithLevels) -> some View {
        let selectedLevelId = bridge.bulkSelectedLevelId(studentId: student.id, criterionId: criterion.criterion.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(criterion.levels.enumerated()), id: \.element.id) { index, level in
                    let isSelected = selectedLevelId == level.id
                    Button {
                        bridge.bulkSelectLevel(studentId: student.id, criterionId: criterion.criterion.id, levelId: level.id)
                        selectedStudentId = student.id
                        selectedCriterionId = criterion.criterion.id
                    } label: {
                        VStack(spacing: 2) {
                            Text(levelShortLabel(level, index: index))
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .lineLimit(1)
                            Text("\(Int(level.points))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                        }
                        .frame(width: 34, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.08))
                        )
                        .foregroundStyle(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .help(levelTooltip(for: level))
                }
            }
        }
        .frame(width: criterionColumnWidth, alignment: .leading)
        .onTapGesture {
            selectedStudentId = student.id
            selectedCriterionId = criterion.criterion.id
        }
    }

    private func scorePill(for studentId: Int64) -> some View {
        let score = bridge.bulkScore(studentId: studentId)
        let color: Color = (score ?? 0) >= 5 ? .green : .red
        return Text(score.map { String(format: "%.1f", $0) } ?? "—")
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func levelTooltip(for level: RubricLevel) -> String {
        let description = level.description_?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return description.isEmpty ? "\(level.name) · \(Int(level.points)) pts" : "\(level.name): \(description)"
    }

    private func levelShortLabel(_ level: RubricLevel, index: Int) -> String {
        let trimmed = level.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.localizedCaseInsensitiveContains("nivel") {
            return "N\(index + 1)"
        }
        return String(trimmed.prefix(2)).uppercased()
    }

    private func initials(for student: Student) -> String {
        let first = student.firstName.prefix(1)
        let last = student.lastName.prefix(1)
        return String(first + last)
    }

    private func missingCriteriaCount(_ studentId: Int64) -> Int {
        rubric.criteria.reduce(into: 0) { partial, criterion in
            if bridge.bulkSelectedLevelId(studentId: studentId, criterionId: criterion.criterion.id) == nil {
                partial += 1
            }
        }
    }
}

private struct BulkEvaluationMacInspector: View {
    @ObservedObject var bridge: KmpBridge
    let rubric: RubricDetail
    let student: Student?
    let criterion: RubricCriterionWithLevels?
    let isInjured: Bool
    let injuredStudents: [Student]
    let missingCriteriaCount: Int
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Inspector")
                            .font(.headline)
                        if let student {
                            Text("\(student.firstName) \(student.lastName)")
                                .font(.title3.weight(.semibold))
                            Text(isInjured ? "Alumno lesionado" : "Alumno activo")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(isInjured ? .red : .secondary)
                        } else {
                            Text("Selecciona un alumno")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        onClose()
                    } label: {
                        Label("Cerrar", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                }

                if let student {
                    HStack(spacing: 10) {
                        Button("Copiar") {
                            bridge.bulkCopyAssessment(studentId: student.id)
                        }
                        .buttonStyle(.bordered)

                        Button("Pegar") {
                            bridge.bulkPasteAssessment(studentId: student.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(bridge.bulkRubricEvaluationState?.copiedAssessment == nil)
                    }

                    metricBlock(title: "Progreso", value: "\(rubric.criteria.count - missingCriteriaCount)/\(rubric.criteria.count) criterios")
                    metricBlock(title: "Pendientes", value: "\(missingCriteriaCount)")
                    metricBlock(title: "Nota actual", value: bridge.bulkScore(studentId: student.id).map { String(format: "%.1f / 10", $0) } ?? "Sin calcular")
                }

                if let criterion {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Criterio activo")
                            .font(.subheadline.weight(.semibold))
                        Text(criterion.criterion.description_)
                            .font(.body.weight(.medium))
                        Text("Peso \(Int((criterion.criterion.weight * 100).rounded()))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(criterion.levels, id: \.id) { level in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(level.name)
                                            .font(.caption.weight(.bold))
                                        Spacer()
                                        Text("\(Int(level.points)) pts")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.secondary)
                                    }
                                    if let description = level.description_?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                                        Text(description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                )
                            }
                        }
                    }
                }

                if !injuredStudents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Panel de lesionados")
                            .font(.subheadline.weight(.semibold))
                        ForEach(injuredStudents, id: \.id) { student in
                            HStack {
                                Text("\(student.firstName) \(student.lastName)")
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Image(systemName: "bandage")
                                    .foregroundStyle(.red)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.red.opacity(0.08))
                            )
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func metricBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }
}
#endif
