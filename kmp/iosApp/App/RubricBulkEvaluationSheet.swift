import SwiftUI
import MiGestorKit
#if canImport(UIKit)
import UIKit
#endif

struct RubricBulkEvaluationSheet: View {
    /// Referencia sin suscripción: la hoja solo se redibuja cuando cambia lo que
    /// lee del bridge (`bulkRubricEvaluationState` y `classes`), vía `bridgeWatch`.
    /// Con `@ObservedObject` cualquier cambio de la app (sync, Cuaderno) la repintaba entera.
    let bridge: KmpBridge
    @StateObject private var bridgeWatch = KmpBridgeWatch()
    /// Conversión de niveles y notas hecha una vez por estado, no en cada pintado.
    @StateObject private var snapshotMemo = BulkRubricSnapshotMemo()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @State private var horizontalScrollOffset: CGFloat = 0
    @State private var levelHoverTask: Task<Void, Never>?
    @State private var focusedBulkStudentId: Int64?
    @State private var focusedBulkCriterionId: Int64?
    @State private var localInjuryStatuses: [Int64: Bool] = [:]
    @State private var savingInjuryStudentIds: Set<Int64> = []
    @State private var activePopoverLevel: RubricLevel?
    @State private var activePopoverStudentId: Int64?
    @State private var activePopoverCriterionId: Int64?
    @State private var familyReportStudentId: Int64? = nil
    @State private var selfAssessmentSources: [KmpBridge.SelfAssessmentSourceOption] = []
    @State private var selectedSelfAssessmentColumnId: String = ""
    @State private var showingSelfAssessmentSheet = false
    @State private var isRunningSelfAssessmentAutofill = false
    @State private var autofillProgressCurrent = 0
    @State private var autofillProgressTotal = 0
    @State private var autofillOnlyPending = true
    @State private var aiSuggestionsByCell: [BulkRubricCellKey: RubricSelfAssessmentCriterionSuggestion] = [:]
    @State private var aiProvenanceLabel: String?
    @State private var aiLastSummaryMessage: String?
    @State private var previousLevelsBeforeAutofill: [BulkRubricCellKey: Int64?]? = nil
    @State private var aiOrchestrator = AppleAIOrchestrator()

    private var watchedBridge: KmpBridge {
        bridgeWatch.bridge(bridge) { [.init($0.bulkRubricEvaluationState), .init($0.classes)] }
    }

    private var state: BulkRubricEvaluationUiState? {
        watchedBridge.bulkRubricEvaluationState
    }

    /// Caché del estado actual del bridge (para acciones fuera del pintado).
    private func currentCache() -> BulkRubricEvaluationCache? {
        guard let state = bridge.bulkRubricEvaluationState,
              let rubric = state.rubricDetail else { return nil }
        return snapshotMemo.cache(for: state, rubric: rubric, bridge: bridge)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RubricEvaluationBackdrop()

                if state?.isLoading ?? true {
                    ProgressView("Cargando evaluación masiva...")
                        .scaledSystemFont(size: 14, weight: .medium)
                        .foregroundStyle(.secondary)
                } else if let state, let rubric = state.rubricDetail {
                    GeometryReader { proxy in
                        let isWide = proxy.size.width >= 720
                        let className = className(for: state)
                        let cache = snapshotMemo.cache(for: state, rubric: rubric, bridge: bridge)

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
                        .task(id: "\(state.classId)-\(state.evaluationId)-\(state.students.count)") {
                            await refreshSelfAssessmentSources(state: state)
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
                            .scaledSystemFont(size: 28, weight: .bold)
                            .foregroundStyle(EvaluationDesign.danger)
                        Text("No se pudo abrir la evaluación")
                            .scaledSystemFont(size: 18, weight: .black, design: .rounded)
                        if let error = state?.error {
                            Text(error)
                                .scaledSystemFont(size: 13, weight: .medium)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        } else {
                            Text("La evaluación seleccionada no existe o no se pudo cargar.")
                                .scaledSystemFont(size: 13, weight: .medium)
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
                activePopoverStudentId = nil
                activePopoverCriterionId = nil
            }
            .popover(item: $activePopoverLevel, arrowEdge: .bottom) { level in
                let suggestion = activePopoverSuggestion(for: level)
                RubricLevelDescriptionPopover(
                    level: level,
                    aiSuggestion: suggestion,
                    aiProvenanceLabel: aiProvenanceLabel
                )
                .padding(4)
                #if os(iOS)
                .presentationDetents([.fraction(0.38), .medium])
                .presentationDragIndicator(.visible)
                #endif
            }
            .sheet(isPresented: $showingSelfAssessmentSheet) {
                if let state, let rubric = state.rubricDetail {
                    BulkRubricSelfAssessmentAutofillSheet(
                        rubricName: rubric.rubric.name,
                        sources: selfAssessmentSources,
                        selectedSourceColumnId: $selectedSelfAssessmentColumnId,
                        onlyPendingCriteria: $autofillOnlyPending,
                        availability: aiOrchestrator.availability(),
                        onConfirm: {
                            showingSelfAssessmentSheet = false
                            Task {
                                await runBulkSelfAssessmentAutofill(state: state, rubric: rubric)
                            }
                        }
                    )
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { familyReportStudentId != nil },
                    set: { if !$0 { familyReportStudentId = nil } }
                )
            ) {
                if let studentId = familyReportStudentId,
                   let state,
                   let rubric = state.rubricDetail,
                   let student = state.students.first(where: { $0.id == studentId }) {
                    let cache = snapshotMemo.cache(for: state, rubric: rubric, bridge: bridge)
                    let studentLevels = cache.levels(for: student.id)
                    let studentScore = cache.score(for: student.id) ?? 0.0
                    RubricExportFamilyPDFSheet(
                        rubricDetail: rubric,
                        selectedLevelIds: studentLevels,
                        studentName: student.firstName + " " + student.lastName,
                        className: className(for: state),
                        currentScore: studentScore
                    )
                }
            }
        }
    }

    private func headerSection(
        className: String,
        rubric: RubricDetail,
        state: BulkRubricEvaluationUiState,
        cache: BulkRubricEvaluationCache
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            InstrumentEvaluationChromeSurface(role: .header) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 16) {
                        Button {
                            bridge.closeBulkRubricEvaluation()
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .scaledSystemFont(size: 15, weight: .semibold)
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge) // marco fijo: crece hasta donde cabe
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Volver")

                        VStack(alignment: .leading, spacing: 4) {
                            Text(className)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(rubric.rubric.name)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        if !dynamicTypeSize.isAccessibilitySize {
                            headerStatus(state: state, cache: cache)
                        }
                    }
                    // Con letra de accesibilidad el estado no cabe junto al título
                    // ("pendi-entes"): baja a su propia línea.
                    if dynamicTypeSize.isAccessibilitySize {
                        headerStatus(state: state, cache: cache)
                            .padding(.top, 8)
                    }
                }
            }

            let criteriaText = rubricCriteriaSummary(rubric: rubric)
            InstrumentEvaluationChromeSurface(role: .context, padding: 0) {
                AssessmentCriteriaDisclosureView(rawText: criteriaText, embedded: true)
            }

            if isRunningSelfAssessmentAutofill || aiLastSummaryMessage != nil {
                selfAssessmentStatusBanner
            }
        }
    }

    private func headerStatus(state: BulkRubricEvaluationUiState, cache: BulkRubricEvaluationCache) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                selfAssessmentHeaderControl
                pendingAndSaveStatus(state: state, cache: cache)
            }
            VStack(alignment: .trailing, spacing: 8) {
                selfAssessmentHeaderControl
                pendingAndSaveStatus(state: state, cache: cache)
            }
        }
    }

    @ViewBuilder
    private var selfAssessmentHeaderControl: some View {
        let totalRespondents = selfAssessmentSources.reduce(0) { max($0, $1.respondentCount) }
        if !selfAssessmentSources.isEmpty {
            Button {
                showingSelfAssessmentSheet = true
            } label: {
                Label(
                    totalRespondents > 0
                        ? "Autoevaluación (\(totalRespondents))"
                        : "Autoevaluación",
                    systemImage: "sparkles"
                )
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            }
            .instrumentEvaluationGlassButton(isProminent: false)
            .disabled(isRunningSelfAssessmentAutofill)
            .help("Autocompletar niveles revisables a partir de una autoevaluación de la clase")
            .accessibilityLabel("Autocompletar desde autoevaluación")
        }
    }

    private func pendingAndSaveStatus(state: BulkRubricEvaluationUiState, cache: BulkRubricEvaluationCache) -> some View {
        HStack(spacing: 16) {
            Label(
                "\(cache.totalPendingCriteria) pendientes",
                systemImage: "clock.badge.exclamationmark"
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(cache.totalPendingCriteria == 0 ? EvaluationDesign.success : NotebookStyle.warningTint)
            .lineLimit(1)
            .layoutPriority(1)

            InstrumentEvaluationStatus(
                text: state.isSaving ? "Guardando…" : "Cambios guardados",
                tint: state.isSaving ? EvaluationDesign.accent : EvaluationDesign.success
            )
        }
    }

    private var selfAssessmentStatusBanner: some View {
        InstrumentEvaluationChromeSurface(role: .context, padding: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    bannerLeadingContent
                    Spacer(minLength: 8)
                    bannerTrailingActions
                }
                VStack(alignment: .leading, spacing: 8) {
                    bannerLeadingContent
                    bannerTrailingActions
                }
            }
        }
    }

    @ViewBuilder
    private var bannerLeadingContent: some View {
        if isRunningSelfAssessmentAutofill {
            HStack(spacing: 10) {
                ProgressView(
                    value: Double(autofillProgressCurrent),
                    total: Double(max(autofillProgressTotal, 1))
                )
                .tint(EvaluationDesign.accent)
                .frame(maxWidth: 140)

                Text("Analizando autoevaluaciones (\(autofillProgressCurrent)/\(autofillProgressTotal))…")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        } else if let summary = aiLastSummaryMessage {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(EvaluationDesign.accent)

                Text(summary)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)

                if let provenance = aiProvenanceLabel {
                    Text(provenance)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(EvaluationDesign.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(EvaluationDesign.accent.opacity(0.12))
                        )
                }
            }
        }
    }

    @ViewBuilder
    private var bannerTrailingActions: some View {
        if !isRunningSelfAssessmentAutofill {
            HStack(spacing: 12) {
                if previousLevelsBeforeAutofill != nil {
                    Button {
                        revertLastSelfAssessmentAutofill()
                    } label: {
                        Label("Revertir", systemImage: "arrow.uturn.backward")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(EvaluationDesign.danger)
                }

                Button {
                    withAnimation(uiFeatureFlags.interactionAnimation) {
                        aiLastSummaryMessage = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ocultar aviso de autocompletado")
            }
        }
    }

    private func rubricCriteriaSummary(rubric: RubricDetail) -> String {
        var parts: [String] = [rubric.rubric.name, rubric.rubric.description]
        parts.append(contentsOf: rubric.criteria.map { $0.criterion.description_ })
        return parts.joined(separator: " · ")
    }

    private func compactEvaluationByCriterion(
        state: BulkRubricEvaluationUiState,
        rubric: RubricDetail,
        cache: BulkRubricEvaluationCache
    ) -> some View {
        let cellActions = bulkCellActions
        return NotebookSurface(cornerRadius: RubricsStyle.cardRadius, fill: NotebookStyle.surface, padding: 16) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    InstrumentEvaluationMetadataItem(label: "\(state.students.count) alumnos", systemImage: "person.3.fill")
                    InstrumentEvaluationMetadataItem(label: "\(rubric.criteria.count) criterios", systemImage: "checklist")
                }

                ForEach(rubric.criteria, id: \.criterion.id) { criterion in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(criterion.criterion.description_)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        ForEach(state.students, id: \.id) { student in
                            BulkRubricCompactRow(
                                studentId: student.id,
                                studentName: student.firstName + " " + student.lastName,
                                isInjured: isStudentInjured(student, cache: cache),
                                pendingCount: cache.pendingCriteriaCount(for: student.id),
                                score: cache.score(for: student.id),
                                rubric: rubric,
                                criterion: criterion,
                                selectedLevelId: cache.selectedLevelId(studentId: student.id, criterionId: criterion.criterion.id),
                                aiSuggestion: aiSuggestionsByCell[BulkRubricCellKey(studentId: student.id, criterionId: criterion.criterion.id)],
                                isFocused: focusedBulkStudentId == student.id && focusedBulkCriterionId == criterion.criterion.id,
                                cellActions: cellActions,
                                openFamilyReport: { familyReportStudentId = $0 }
                            )
                            .equatable()
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
        let rowActions = bulkRowActions
        // Sugerencias de IA agrupadas por alumno una vez por pintado, no por fila.
        var suggestionsByStudent: [Int64: [Int64: RubricSelfAssessmentCriterionSuggestion]] = [:]
        for (key, suggestion) in aiSuggestionsByCell {
            suggestionsByStudent[key.studentId, default: [:]][key.criterionId] = suggestion
        }
        let canPaste = state.copiedAssessment != nil

        return NotebookSurface(cornerRadius: RubricsStyle.cardRadius, fill: NotebookStyle.surface, padding: 16) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    InstrumentEvaluationMetadataItem(
                        label: "\(state.students.count) alumnos",
                        systemImage: "person.3.fill"
                    )
                    InstrumentEvaluationMetadataItem(
                        label: "\(rubric.criteria.count) criterios",
                        systemImage: "checklist"
                    )

                    if !state.injuredStudents.isEmpty {
                        InstrumentEvaluationMetadataItem(
                            label: "\(state.injuredStudents.count) lesionados",
                            systemImage: "cross.case.fill",
                            tint: EvaluationDesign.danger
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
                                    BulkRubricStudentRow(
                                        studentId: student.id,
                                        studentName: student.firstName + " " + student.lastName,
                                        initials: initials(for: student),
                                        rubric: rubric,
                                        selectedLevels: cache.levels(for: student.id),
                                        score: cache.score(for: student.id),
                                        isInjured: isStudentInjured(student, cache: cache),
                                        pendingCount: cache.pendingCriteriaCount(for: student.id),
                                        aiSuggestions: suggestionsByStudent[student.id] ?? [:],
                                        focusedCriterionId: focusedBulkStudentId == student.id ? focusedBulkCriterionId : nil,
                                        canPaste: canPaste,
                                        isSavingInjury: savingInjuryStudentIds.contains(student.id),
                                        studentWidth: studentWidth,
                                        criterionWidth: criterionWidth,
                                        scoreWidth: scoreWidth,
                                        actionsWidth: actionsWidth,
                                        horizontalOffset: horizontalScrollOffset,
                                        actions: rowActions
                                    )
                                    .equatable()
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
                .scaledSystemFont(size: 11, weight: .black, design: .rounded)
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .padding(.vertical, 8)
                .frame(width: studentWidth, alignment: .leading)
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
                        .scaledSystemFont(size: 11, weight: .bold, design: .rounded)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(width: criterionWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(criterion.criterion.description_)
                }

                Text("Nota")
                    .scaledSystemFont(size: 11, weight: .black, design: .rounded)
                    .foregroundStyle(.secondary)
                    .frame(width: scoreWidth, alignment: .center)

                Text("Acciones")
                    .scaledSystemFont(size: 11, weight: .black, design: .rounded)
                    .foregroundStyle(.secondary)
                    .frame(width: actionsWidth, alignment: .center)
            }
            .padding(.trailing, 16)
            .padding(.vertical, 8)
        }
        .background(appCardBackground(for: colorScheme).opacity(0.95))
    }

    /// Acciones de las celdas. Reciben ids y leen el estado al ejecutarse, así que
    /// una fila que no se redibuja (por `Equatable`) nunca actúa con datos viejos.
    private var bulkCellActions: BulkRubricCellActions {
        BulkRubricCellActions(
            selectLevel: { studentId, criterionId, levelId in
                focusedBulkStudentId = studentId
                focusedBulkCriterionId = criterionId
                bridge.bulkSelectLevel(studentId: studentId, criterionId: criterionId, levelId: levelId)
            },
            focusCell: { studentId, criterionId in
                focusedBulkStudentId = studentId
                focusedBulkCriterionId = criterionId
            },
            hoverLevel: { level, studentId, criterionId, isHovering in
                if isHovering {
                    scheduleLevelPopover(for: level, studentId: studentId, criterionId: criterionId)
                } else {
                    cancelLevelPopover(for: level)
                }
            },
            longPressLevel: { level, studentId, criterionId in
                activePopoverStudentId = studentId
                activePopoverCriterionId = criterionId
                activePopoverLevel = level
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
            }
        )
    }

    private var bulkRowActions: BulkRubricRowActions {
        BulkRubricRowActions(
            cell: bulkCellActions,
            openFamilyReport: { familyReportStudentId = $0 },
            toggleInjury: { toggleInjury(studentId: $0) },
            copyAssessment: { bridge.bulkCopyAssessment(studentId: $0) },
            pasteAssessment: { bridge.bulkPasteAssessment(studentId: $0) }
        )
    }

    /// Lesión desde el menú de la fila: alumno, grupo y caché del estado actual.
    private func toggleInjury(studentId: Int64) {
        guard let state = bridge.bulkRubricEvaluationState,
              let student = state.students.first(where: { $0.id == studentId }),
              let cache = currentCache() else { return }
        Task { await toggleInjuryStatus(for: student, classId: state.classId, cache: cache) }
    }

    private func scheduleLevelPopover(
        for level: RubricLevel,
        studentId: Int64,
        criterionId: Int64
    ) {
        levelHoverTask?.cancel()
        levelHoverTask = Task {
            do {
                try await Task.sleep(nanoseconds: 600_000_000)
                await MainActor.run {
                    withAnimation(uiFeatureFlags.interactionAnimation) {
                        activePopoverStudentId = studentId
                        activePopoverCriterionId = criterionId
                        activePopoverLevel = level
                    }
                }
            } catch {}
        }
    }

    private func cancelLevelPopover(for level: RubricLevel) {
        levelHoverTask?.cancel()
        guard activePopoverLevel?.id == level.id else { return }
        withAnimation(uiFeatureFlags.interactionAnimation) {
            activePopoverLevel = nil
            activePopoverStudentId = nil
            activePopoverCriterionId = nil
        }
    }

    private func activePopoverSuggestion(for level: RubricLevel) -> RubricSelfAssessmentCriterionSuggestion? {
        guard let studentId = activePopoverStudentId,
              let criterionId = activePopoverCriterionId else {
            return nil
        }
        let key = BulkRubricCellKey(studentId: studentId, criterionId: criterionId)
        guard let suggestion = aiSuggestionsByCell[key],
              suggestion.suggestedLevelId == level.id else {
            return nil
        }
        return suggestion
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
                .scaledSystemFont(size: 13, weight: .bold)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge) // marco fijo: crece hasta donde cabe
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
        return NotebookSurface(cornerRadius: RubricsStyle.cardRadius, fill: NotebookStyle.surface, padding: 16) {
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
                        .scaledSystemFont(size: 14, weight: .black, design: .rounded)
                        .foregroundStyle(EvaluationDesign.danger)
                }

                if injuredStudents.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .scaledSystemFont(size: 28, weight: .semibold)
                            .foregroundStyle(.secondary.opacity(0.4))
                        Text("No hay alumnos lesionados")
                            .scaledSystemFont(size: 14, weight: .medium)
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
                                        .scaledSystemFont(size: 15, weight: .bold, design: .rounded)
                                        .foregroundStyle(.primary)
                                    Text("Necesita revisión")
                                        .scaledSystemFont(size: 12, weight: .medium)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                                Button {
                                    Task {
                                        guard let cache = currentCache() else { return }
                                        await toggleInjuryStatus(for: student, classId: state.classId, cache: cache)
                                    }
                                } label: {
                                    Image(systemName: "heart.slash")
                                        .foregroundStyle(EvaluationDesign.danger)
                                }
                                .buttonStyle(.plain)
                                .disabled(savingInjuryStudentIds.contains(student.id))
                                .accessibilityLabel("Quitar de lesionados a \(student.firstName) \(student.lastName)")
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
        watchedBridge.classes.first(where: { $0.id == state.classId })?.name ?? "Clase"
    }

    private func initials(for student: Student) -> String {
        let first = student.firstName.prefix(1)
        let last = student.lastName.prefix(1)
        return String(first + last)
    }

    // MARK: - Autocompletado desde Autoevaluación (Apple Intelligence + Fallback)

    @MainActor
    private func refreshSelfAssessmentSources(state: BulkRubricEvaluationUiState) async {
        guard state.classId > 0 else { return }
        let sources = await bridge.listSelfAssessmentSourceOptions(
            classId: state.classId,
            rubricColumnId: state.columnId,
            rubricTabId: state.tabId,
            students: state.students
        )
        selfAssessmentSources = sources
        if selectedSelfAssessmentColumnId.isEmpty || !sources.contains(where: { $0.columnId == selectedSelfAssessmentColumnId }) {
            selectedSelfAssessmentColumnId = sources.first?.columnId ?? ""
        }
    }

    @MainActor
    private func runBulkSelfAssessmentAutofill(
        state: BulkRubricEvaluationUiState,
        rubric: RubricDetail
    ) async {
        guard let source = selfAssessmentSources.first(where: { $0.columnId == selectedSelfAssessmentColumnId })
                ?? selfAssessmentSources.first else {
            return
        }
        guard !isRunningSelfAssessmentAutofill else { return }

        aiOrchestrator.prewarmIfUseful(for: .studentInsight)
        let currentAssessments = currentCache()?.assessmentsByStudentId ?? [:]

        let criteriaInputs: [RubricSelfAssessmentCriterionInput] = rubric.criteria.enumerated().map { idx, item in
            let levelInputs: [RubricSelfAssessmentCriterionLevelInput] = item.levels.enumerated().map { lIdx, lvl in
                RubricSelfAssessmentCriterionLevelInput(
                    levelId: lvl.id,
                    position: lIdx + 1,
                    name: lvl.name,
                    points: Int(lvl.points),
                    descriptor: lvl.description_ ?? ""
                )
            }
            return RubricSelfAssessmentCriterionInput(
                criterionId: item.criterion.id,
                position: idx + 1,
                title: item.criterion.description_,
                weight: item.criterion.weight,
                levels: levelInputs
            )
        }

        let targetStudents = state.students.filter { student in
            guard source.respondentStudentIds.contains(student.id) else { return false }
            if autofillOnlyPending {
                let studentMap = currentAssessments[student.id] ?? [:]
                return rubric.criteria.contains { studentMap[$0.criterion.id] == nil }
            }
            return true
        }

        guard !targetStudents.isEmpty else {
            withAnimation(uiFeatureFlags.interactionAnimation) {
                aiLastSummaryMessage = "No hay alumnos con autoevaluación pendiente de aplicar en «\(source.columnTitle)»."
                aiProvenanceLabel = nil
            }
            return
        }

        isRunningSelfAssessmentAutofill = true
        autofillProgressCurrent = 0
        autofillProgressTotal = targetStudents.count
        var undoBuffer: [BulkRubricCellKey: Int64?] = [:]
        var appliedStudentsCount = 0
        var appliedCellsCount = 0
        var usedRealAIInBatch = false

        for student in targetStudents {
            let answers = await bridge.loadSelfAssessmentAnswers(
                classId: state.classId,
                studentId: student.id,
                sourceColumnId: source.columnId
            )
            guard !answers.isEmpty else {
                autofillProgressCurrent += 1
                continue
            }

            let mappingInput = RubricSelfAssessmentMappingInput(
                rubricTitle: rubric.rubric.name,
                sourceInstrumentTitle: source.columnTitle,
                studentName: "\(student.firstName) \(student.lastName)",
                criteria: criteriaInputs,
                answers: answers
            )

            do {
                let answeredEvidence = answers.compactMap { ans -> String? in
                    if let scale = ans.scaleValue {
                        return "\(ans.questionTitle): \(scale)/4"
                    }
                    if let text = ans.textResponse?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                        return "\(ans.questionTitle): \(text)"
                    }
                    return nil
                }
                let generation = try await aiOrchestrator.generateWithTrace(
                    capability: .rubricSelfAssessmentMapping,
                    input: .rubricSelfAssessment(mappingInput),
                    dataSource: source.columnTitle,
                    includedEvidence: Array(answeredEvidence.prefix(8))
                )
                if generation.metadata.audit.usedRealAI {
                    usedRealAIInBatch = true
                }
                if case let .rubricSelfAssessmentMapping(draft) = generation.result {
                    var studentChanged = false
                    let existingStudentLevels = currentCache()?.levels(for: student.id) ?? [:]
                    for suggestion in draft.suggestions {
                        let cellKey = BulkRubricCellKey(studentId: student.id, criterionId: suggestion.criterionId)
                        if autofillOnlyPending, existingStudentLevels[suggestion.criterionId] != nil {
                            continue
                        }
                        if undoBuffer[cellKey] == nil {
                            undoBuffer[cellKey] = existingStudentLevels[suggestion.criterionId]
                        }
                        aiSuggestionsByCell[cellKey] = suggestion
                        bridge.bulkSelectLevel(
                            studentId: student.id,
                            criterionId: suggestion.criterionId,
                            levelId: suggestion.suggestedLevelId
                        )
                        appliedCellsCount += 1
                        studentChanged = true
                    }
                    if studentChanged {
                        appliedStudentsCount += 1
                    }
                }
            } catch {
                aiOrchestrator.recordFailure(error)
            }

            autofillProgressCurrent += 1
        }

        isRunningSelfAssessmentAutofill = false
        if appliedCellsCount > 0 {
            previousLevelsBeforeAutofill = undoBuffer
            aiProvenanceLabel = usedRealAIInBatch ? "Apple Intelligence" : "Reglas locales"
            aiLastSummaryMessage = "Completados \(appliedCellsCount) criterios en \(appliedStudentsCount) alumnos desde «\(source.columnTitle)»."
            AppleInteractionFeedback.play(.success)
        } else {
            aiProvenanceLabel = nil
            aiLastSummaryMessage = "No se encontraron criterios pendientes para rellenar desde «\(source.columnTitle)»."
        }
    }

    @MainActor
    private func revertLastSelfAssessmentAutofill() {
        guard let undoBuffer = previousLevelsBeforeAutofill else { return }
        for (cellKey, previousLevelId) in undoBuffer {
            aiSuggestionsByCell.removeValue(forKey: cellKey)
            if let previousLevelId {
                bridge.bulkSelectLevel(
                    studentId: cellKey.studentId,
                    criterionId: cellKey.criterionId,
                    levelId: previousLevelId
                )
            }
        }
        previousLevelsBeforeAutofill = nil
        aiLastSummaryMessage = "Se han revertido las sugerencias aplicadas."
    }
    
    private struct BulkScrollOffsetKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
}

/// Acciones de una celda de criterio. Fuera de la comparación de las filas.
private struct BulkRubricCellActions {
    let selectLevel: (_ studentId: Int64, _ criterionId: Int64, _ levelId: Int64) -> Void
    let focusCell: (_ studentId: Int64, _ criterionId: Int64) -> Void
    let hoverLevel: (_ level: RubricLevel, _ studentId: Int64, _ criterionId: Int64, _ isHovering: Bool) -> Void
    let longPressLevel: (_ level: RubricLevel, _ studentId: Int64, _ criterionId: Int64) -> Void
}

/// Acciones del menú de la fila. Reciben el id del alumno.
private struct BulkRubricRowActions {
    let cell: BulkRubricCellActions
    let openFamilyReport: (_ studentId: Int64) -> Void
    let toggleInjury: (_ studentId: Int64) -> Void
    let copyAssessment: (_ studentId: Int64) -> Void
    let pasteAssessment: (_ studentId: Int64) -> Void
}

/// Misma rúbrica: primero por identidad (barato) y si no, igualdad Kotlin.
private func bulkSameRubric(_ lhs: RubricDetail, _ rhs: RubricDetail) -> Bool {
    lhs === rhs || lhs == rhs
}

/// Envoltorio sobre `RubricsStyle.levelColor(points:maxPoints:)` que
/// resuelve `maxPoints` a partir del criterio — la lógica de bandas (y por
/// qué no es `gradeColor`) vive en `RubricsStyle`, compartida con la
/// evaluación individual.
private func bulkRubricLevelColor(for level: RubricLevel?, in criterion: RubricCriterionWithLevels) -> Color {
    guard let level else { return EvaluationDesign.accent }
    let maxPoints = criterion.levels.map(\.points).max() ?? 0
    return RubricsStyle.levelColor(points: Double(level.points), maxPoints: Double(maxPoints))
}

private func bulkRubricStatusDotColor(isInjured: Bool, pendingCount: Int) -> Color {
    if isInjured {
        return EvaluationDesign.danger
    } else if pendingCount > 0 {
        return Color.gray.opacity(0.5)
    } else {
        return EvaluationDesign.success
    }
}

/// Fila de un alumno en la tabla ancha. Solo se redibuja si cambia algo de lo que
/// pinta (todo está en `==`); las acciones quedan fuera de la comparación.
private struct BulkRubricStudentRow: View, Equatable {
    let studentId: Int64
    let studentName: String
    let initials: String
    let rubric: RubricDetail
    let selectedLevels: [Int64: Int64]
    let score: Double?
    let isInjured: Bool
    let pendingCount: Int
    let aiSuggestions: [Int64: RubricSelfAssessmentCriterionSuggestion]
    let focusedCriterionId: Int64?
    let canPaste: Bool
    let isSavingInjury: Bool
    let studentWidth: CGFloat
    let criterionWidth: CGFloat
    let scoreWidth: CGFloat
    let actionsWidth: CGFloat
    let horizontalOffset: CGFloat
    let actions: BulkRubricRowActions

    @Environment(\.colorScheme) private var colorScheme

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.studentId == rhs.studentId
            && lhs.studentName == rhs.studentName
            && lhs.initials == rhs.initials
            && bulkSameRubric(lhs.rubric, rhs.rubric)
            && lhs.selectedLevels == rhs.selectedLevels
            && lhs.score == rhs.score
            && lhs.isInjured == rhs.isInjured
            && lhs.pendingCount == rhs.pendingCount
            && lhs.aiSuggestions == rhs.aiSuggestions
            && lhs.focusedCriterionId == rhs.focusedCriterionId
            && lhs.canPaste == rhs.canPaste
            && lhs.isSavingInjury == rhs.isSavingInjury
            && lhs.studentWidth == rhs.studentWidth
            && lhs.criterionWidth == rhs.criterionWidth
            && lhs.scoreWidth == rhs.scoreWidth
            && lhs.actionsWidth == rhs.actionsWidth
            && lhs.horizontalOffset == rhs.horizontalOffset
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    EvaluationAvatar(initials: initials)

                    Circle()
                        .fill(bulkRubricStatusDotColor(isInjured: isInjured, pendingCount: pendingCount))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(appCardBackground(for: colorScheme), lineWidth: 1.5))
                }

                Text(studentName)
                    .scaledSystemFont(size: 14, weight: .bold, design: .rounded)
                    .foregroundStyle(.primary)
                    // La columna de nombre tiene ancho fijo: con letra grande
                    // el apellido pasa a la segunda línea en vez de cortarse.
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.vertical, 16)
            .frame(width: studentWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                    .fill(appCardBackground(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                    .stroke(isInjured ? EvaluationDesign.danger.opacity(0.08) : EvaluationDesign.border, lineWidth: 1)
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
                    BulkRubricCriterionCell(
                        studentId: studentId,
                        criterion: criterion,
                        width: criterionWidth,
                        selectedLevelId: selectedLevels[criterion.criterion.id],
                        aiSuggestion: aiSuggestions[criterion.criterion.id],
                        isFocused: focusedCriterionId == criterion.criterion.id,
                        actions: actions.cell
                    )
                }

                BulkRubricScorePill(score: score, width: scoreWidth)

                Menu {
                    Button {
                        actions.openFamilyReport(studentId)
                    } label: {
                        Label("Informe familiar PDF…", systemImage: "doc.text.badge.plus")
                    }

                    Divider()

                    Button {
                        actions.toggleInjury(studentId)
                    } label: {
                        Label(
                            isInjured ? "Quitar lesión" : "Marcar lesión",
                            systemImage: isInjured ? "heart.slash" : "bandage"
                        )
                    }
                    .disabled(isSavingInjury)

                    Button {
                        actions.copyAssessment(studentId)
                    } label: {
                        Label("Copiar evaluación", systemImage: "doc.on.doc")
                    }

                    Button {
                        actions.pasteAssessment(studentId)
                    } label: {
                        Label("Pegar evaluación", systemImage: "doc.on.clipboard")
                    }
                    .disabled(!canPaste)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .scaledSystemFont(size: 18, weight: .medium)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge) // marco fijo: crece hasta donde cabe
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
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
}

/// Fila de un alumno para un criterio en el diseño estrecho (por criterio).
private struct BulkRubricCompactRow: View, Equatable {
    let studentId: Int64
    let studentName: String
    let isInjured: Bool
    let pendingCount: Int
    let score: Double?
    let rubric: RubricDetail
    let criterion: RubricCriterionWithLevels
    let selectedLevelId: Int64?
    let aiSuggestion: RubricSelfAssessmentCriterionSuggestion?
    let isFocused: Bool
    let cellActions: BulkRubricCellActions
    let openFamilyReport: (_ studentId: Int64) -> Void

    @Environment(\.colorScheme) private var colorScheme

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.studentId == rhs.studentId
            && lhs.studentName == rhs.studentName
            && lhs.isInjured == rhs.isInjured
            && lhs.pendingCount == rhs.pendingCount
            && lhs.score == rhs.score
            // El criterio sale de la rúbrica: misma rúbrica y mismo id, mismo criterio.
            && bulkSameRubric(lhs.rubric, rhs.rubric)
            && lhs.criterion.criterion.id == rhs.criterion.criterion.id
            && lhs.selectedLevelId == rhs.selectedLevelId
            && lhs.aiSuggestion == rhs.aiSuggestion
            && lhs.isFocused == rhs.isFocused
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(bulkRubricStatusDotColor(isInjured: isInjured, pendingCount: pendingCount))
                    .frame(width: 8, height: 8)

                Text(studentName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)

                Spacer(minLength: 4)

                BulkRubricScorePill(score: score, width: 44)
                    .contextMenu {
                        Button {
                            openFamilyReport(studentId)
                        } label: {
                            Label("Informe familiar PDF…", systemImage: "doc.text.badge.plus")
                        }
                    }
            }
            .frame(width: 160, alignment: .leading)

            BulkRubricCriterionCell(
                studentId: studentId,
                criterion: criterion,
                width: 220,
                selectedLevelId: selectedLevelId,
                aiSuggestion: aiSuggestion,
                isFocused: isFocused,
                actions: cellActions
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: EvaluationDesign.innerRadius, style: .continuous)
                .fill(appCardBackground(for: colorScheme))
        )
    }
}

/// Celda de un criterio (botones de nivel + nombre del nivel elegido). Vive dentro
/// de las filas `Equatable`: todo lo que pinta llega como parámetro.
private struct BulkRubricCriterionCell: View {
    let studentId: Int64
    let criterion: RubricCriterionWithLevels
    let width: CGFloat
    let selectedLevelId: Int64?
    let aiSuggestion: RubricSelfAssessmentCriterionSuggestion?
    let isFocused: Bool
    let actions: BulkRubricCellActions

    var body: some View {
        let criterionId = criterion.criterion.id
        let selectedLevel = criterion.levels.first { $0.id == selectedLevelId }
        let isAISuggestedSelection = aiSuggestion != nil && aiSuggestion?.suggestedLevelId == selectedLevelId

        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Array(criterion.levels.enumerated()), id: \.element.id) { index, level in
                    let isSelected = selectedLevelId == level.id
                    let tint = bulkRubricLevelColor(for: level, in: criterion)

                    Button {
                        actions.selectLevel(studentId, criterionId, level.id)
                    } label: {
                        HStack(spacing: 3) {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .scaledSystemFont(size: 11, weight: .black)
                            }
                            Text("\(index + 1)")
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(isSelected ? contrastingTextColor(for: tint) : .primary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? tint : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(isSelected ? tint : EvaluationDesign.border, lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(criterion.criterion.description_), \(level.name), nivel \(index + 1)")
                    .accessibilityValue(isAISuggestedSelection && isSelected ? "Sugerido desde autoevaluación" : "")
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    .help(Self.levelHelpText(level, suggestion: isSelected ? aiSuggestion : nil))
                    .onHover { isHovering in
                        actions.hoverLevel(level, studentId, criterionId, isHovering)
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in
                                actions.longPressLevel(level, studentId, criterionId)
                            }
                    )
                }
            }

            if let selectedLevel {
                HStack(spacing: 4) {
                    if isAISuggestedSelection {
                        Image(systemName: "sparkles")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(EvaluationDesign.accent)
                            .accessibilityHidden(true)
                    }
                    Text(selectedLevel.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(bulkRubricLevelColor(for: selectedLevel, in: criterion))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(8)
        .frame(width: width)
        .contentShape(RoundedRectangle(cornerRadius: RubricsStyle.rowRadius, style: .continuous))
        .onTapGesture {
            actions.focusCell(studentId, criterionId)
        }
        .background(
            RoundedRectangle(cornerRadius: RubricsStyle.rowRadius, style: .continuous)
                .fill(selectedLevel == nil ? Color.clear : bulkRubricLevelColor(for: selectedLevel, in: criterion).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: RubricsStyle.rowRadius, style: .continuous)
                .stroke(isFocused ? EvaluationDesign.accent.opacity(0.65) : Color.clear, lineWidth: 2)
        )
    }

    private static func levelHelpText(_ level: RubricLevel, suggestion: RubricSelfAssessmentCriterionSuggestion? = nil) -> String {
        let description = level.description_?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = description.isEmpty ? level.name : "\(level.name): \(description)"
        guard let suggestion else { return base }
        return "\(base)\n✨ Autoevaluación: \(suggestion.rationale)"
    }
}

/// Nota compacta con separador decimal localizado (coma en es-ES), coherente
/// con el resto de la app; `String(format: "%.1f")` forzaba siempre el punto.
private struct BulkRubricScorePill: View {
    let score: Double?
    let width: CGFloat

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    var body: some View {
        let scoreText = score.map {
            Self.formatter.string(from: NSNumber(value: $0)) ?? String(format: "%.1f", $0)
        } ?? "—"
        let tint = score.map { RubricsStyle.gradeColor(forScoreOutOfTen: $0) }

        Text(scoreText)
            .scaledSystemFont(size: 20, weight: .black, design: .rounded)
            .foregroundStyle(tint ?? .secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: width, alignment: .center)
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

/// Guarda la última caché y el estado del que salió. Los estados Kotlin son
/// inmutables: mismo objeto, mismo contenido; un estado nuevo la invalida.
@MainActor
private final class BulkRubricSnapshotMemo: ObservableObject {
    private var lastState: BulkRubricEvaluationUiState?
    private var lastCache: BulkRubricEvaluationCache?

    func cache(
        for state: BulkRubricEvaluationUiState,
        rubric: RubricDetail,
        bridge: KmpBridge
    ) -> BulkRubricEvaluationCache {
        if let lastCache, lastState === state {
            return lastCache
        }
        let cache = BulkRubricEvaluationCache(
            state: state,
            rubric: rubric,
            assessments: bridge.bulkAssessmentSnapshot(from: state),
            scores: bridge.bulkScoreSnapshot(from: state)
        )
        lastState = state
        lastCache = cache
        return cache
    }
}

private struct BulkRubricEvaluationCache {
    let assessmentsByStudentId: [Int64: [Int64: Int64]]
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
        var completedCriteriaCountByStudentId: [Int64: Int] = [:]

        for student in state.students {
            completedCriteriaCountByStudentId[student.id] = 0
        }

        for (studentId, studentMap) in assessments {
            var completedCount = completedCriteriaCountByStudentId[studentId] ?? 0
            completedCount += studentMap.count
            completedCriteriaCountByStudentId[studentId] = min(completedCount, criteriaCount)
        }

        self.assessmentsByStudentId = assessments
        self.scores = scores
        self.completedCriteriaCountByStudentId = completedCriteriaCountByStudentId
        self.injuredStudentIds = Set(state.injuredStudents.map(\.id))
    }

    func selectedLevelId(studentId: Int64, criterionId: Int64) -> Int64? {
        assessmentsByStudentId[studentId]?[criterionId]
    }

    func levels(for studentId: Int64) -> [Int64: Int64] {
        assessmentsByStudentId[studentId] ?? [:]
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
    var aiSuggestion: RubricSelfAssessmentCriterionSuggestion? = nil
    var aiProvenanceLabel: String? = nil

    private var trimmedDescription: String {
        level.description_?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .scaledSystemFont(size: 16, weight: .bold)
                    .foregroundStyle(EvaluationDesign.accent)

                Text(level.name)
                    .scaledSystemFont(size: 15, weight: .black, design: .rounded)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 12)

                Text(RubricsStyle.pointsText(Double(level.points)))
                    .scaledSystemFont(size: 12, weight: .black, design: .rounded)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(EvaluationDesign.accent)
                    )
            }

            Rectangle()
                .fill(NotebookGridStyle.gridLine)
                .frame(height: 1)

            if trimmedDescription.isEmpty {
                Text("Sin descripción adicional para este nivel.")
                    .scaledSystemFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(.secondary)
            } else {
                Text(trimmedDescription)
                    .scaledSystemFont(size: 13, weight: .medium)
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let aiSuggestion {
                Rectangle()
                    .fill(NotebookGridStyle.gridLine)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Label("Evidencia de autoevaluación", systemImage: "sparkles")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(EvaluationDesign.accent)

                        Spacer(minLength: 4)

                        if let aiProvenanceLabel {
                            Text(aiProvenanceLabel)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(aiSuggestion.rationale)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !aiSuggestion.evidenceExcerpt.isEmpty {
                        Text(aiSuggestion.evidenceExcerpt)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(EvaluationDesign.accent.opacity(0.08))
                            )
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 280, maxWidth: 380)
    }
}

private struct BulkRubricSelfAssessmentAutofillSheet: View {
    let rubricName: String
    let sources: [KmpBridge.SelfAssessmentSourceOption]
    @Binding var selectedSourceColumnId: String
    @Binding var onlyPendingCriteria: Bool
    let availability: AppleAIAvailability
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var selectedSource: KmpBridge.SelfAssessmentSourceOption? {
        sources.first { $0.columnId == selectedSourceColumnId } ?? sources.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AppleAIStatusBadge(
                        state: availability.generationState,
                        message: availability.isAvailable
                            ? "Apple Intelligence analizará las respuestas y sugerirá el nivel más acorde con cada descriptor."
                            : "Se aplicará emparejamiento determinista local sobre los indicadores y reflexiones."
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Instrumento de origen")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("Elige la autoevaluación o formulario del Cuaderno cuyas respuestas quieres cruzar con «\(rubricName)».")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 8) {
                            ForEach(sources) { source in
                                sourceOptionRow(source)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Modo de aplicación")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Toggle(isOn: $onlyPendingCriteria) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Completar solo criterios pendientes")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("Respeta cualquier nivel que ya hayas puntuado manualmente en la tabla.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: RubricsStyle.rowRadius, style: .continuous)
                                .fill(appCardBackground(for: colorScheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: RubricsStyle.rowRadius, style: .continuous)
                                .stroke(EvaluationDesign.border, lineWidth: 1)
                        )
                    }
                }
                .padding(24)
            }
            .background(RubricEvaluationBackdrop())
            .navigationTitle("Autocompletar rúbrica")
            .appInlineNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onConfirm()
                    } label: {
                        Label("Aplicar sugerencias", systemImage: "sparkles")
                    }
                    .disabled(selectedSource == nil || (selectedSource?.respondentCount ?? 0) == 0)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 460)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func sourceOptionRow(_ source: KmpBridge.SelfAssessmentSourceOption) -> some View {
        let isSelected = (selectedSource?.columnId == source.columnId)
        return Button {
            selectedSourceColumnId = source.columnId
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? EvaluationDesign.accent : .secondary.opacity(0.5))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(source.columnTitle)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if source.isSameContextAsRubric {
                            Text("Misma SA")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(EvaluationDesign.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(EvaluationDesign.accent.opacity(0.12))
                                )
                        }
                    }

                    Text("\(source.respondentCount) con respuestas · \(source.itemCount) preguntas")
                        .font(.caption)
                        .foregroundStyle(source.respondentCount > 0 ? .secondary : EvaluationDesign.danger)
                }

                Spacer(minLength: 8)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: RubricsStyle.rowRadius, style: .continuous)
                    .fill(isSelected ? EvaluationDesign.accent.opacity(0.08) : appCardBackground(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: RubricsStyle.rowRadius, style: .continuous)
                    .stroke(isSelected ? EvaluationDesign.accent : EvaluationDesign.border, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: RubricsStyle.rowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
