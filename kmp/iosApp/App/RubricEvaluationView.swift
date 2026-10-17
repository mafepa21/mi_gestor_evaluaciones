import SwiftUI
import MiGestorKit

struct RubricEvaluationView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingFamilyReportSheet: Bool = false
    @State private var showingMetacognitionSheet: Bool = false
    /// Criterio que recibe las teclas 1-4 y ↑/↓ (borde de 2pt de acento).
    @State private var activeCriterionId: Int64?
    /// Foto de `selectedLevels` al cargar/guardar: base de `isDirty`.
    @State private var initialLevels: [Int64: Int64]?
    @State private var showingDiscardDialog: Bool = false
    /// `LomloeCriteriaCatalog.resolveCriteria` hecho una vez por rúbrica, no
    /// en cada redibujado.
    @State private var resolvedCriteria: [LomloeCriterionDefinition] = []
    @FocusState private var keysFocused: Bool
    /// Celdas de la tabla sin descriptor (solo número y nivel). Se recuerda entre rúbricas.
    @AppStorage("rubricEvaluation.hidesLevelDescriptions") private var hidesLevelDescriptions = false
    /// Ancho disponible para decidir entre tabla y tarjetas.
    @State private var availableWidth: CGFloat = 0

    private func usesMatrix(_ rubric: RubricDetail) -> Bool {
        RubricMatrixView.fits(rubric.criteria, in: availableWidth)
    }

    /// Ancho máximo del contenido: la tabla aprovecha la ventana; las tarjetas, columna legible.
    private func contentMaxWidth(_ rubric: RubricDetail) -> CGFloat {
        usesMatrix(rubric) ? 1_320 : 760
    }

    private var currentLevels: [Int64: Int64] {
        Self.levelsById(state.selectedLevels)
    }

    /// Convierte el mapa Kotlin (criterio -> nivel) a `[Int64: Int64]`.
    /// Tras `selectLevel`, Kotlin guarda `NSNumber` sueltos y no `KotlinLong`, así que
    /// recorrer el diccionario como `[KotlinLong: KotlinLong]` aborta con un cast fallido.
    /// `NSNumber` vale para ambos casos (`KotlinLong` es subclase suya).
    static func levelsById(_ levels: [KotlinLong: KotlinLong]) -> [Int64: Int64] {
        var result: [Int64: Int64] = [:]
        for (rawKey, rawValue) in (levels as NSDictionary) {
            if let key = rawKey as? NSNumber, let value = rawValue as? NSNumber {
                result[key.int64Value] = value.int64Value
            }
        }
        return result
    }

    /// Hay niveles cambiados respecto a la última carga o guardado.
    private var isDirty: Bool {
        guard let initialLevels else { return false }
        return initialLevels != currentLevels
    }

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

                    ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: EvaluationDesign.sectionSpacing) {
                            headerSection(rubric: rubric, score: selectedScore, progress: progress)
                            if let error = state.error {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(EvaluationDesign.danger)
                                    Text(error)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Spacer(minLength: 0)
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(EvaluationDesign.danger.opacity(0.12))
                                )
                                .accessibilityElement(children: .combine)
                            }
                            criteriaPanel(rubric: rubric)
                        }
                        .padding(EvaluationDesign.screenPadding)
                        .frame(maxWidth: contentMaxWidth(rubric))
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
                    .focusable()
                    .focused($keysFocused)
                    .focusEffectDisabled()
                    .onKeyPress(characters: .decimalDigits) { press in
                        handleDigitKey(press, rubric: rubric)
                    }
                    .onKeyPress(.upArrow) {
                        moveActiveCriterion(by: -1, rubric: rubric)
                    }
                    .onKeyPress(.downArrow) {
                        moveActiveCriterion(by: 1, rubric: rubric)
                    }
                    .appOnChange(of: activeCriterionId) { id in
                        guard let id else { return }
                        withAnimation(uiFeatureFlags.interactionAnimation) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        saveSection(rubric: rubric, score: selectedScore)
                            .frame(maxWidth: contentMaxWidth(rubric))
                            .padding(.horizontal, EvaluationDesign.screenPadding)
                            .padding(.bottom, 8)
                    }
                    .onAppear {
                        refreshResolvedCriteria(rubric: rubric)
                        if initialLevels == nil, !state.isLoading { resetSnapshot(rubric: rubric) }
                        keysFocused = true
                    }
                    .appOnChange(of: state.rubricDetail?.rubric.id) { _ in
                        refreshResolvedCriteria(rubric: rubric)
                    }
                    .appOnChange(of: state.studentId) { _ in
                        resetSnapshot(rubric: rubric)
                    }
                    .appOnChange(of: state.isLoading) { loading in
                        if !loading { resetSnapshot(rubric: rubric) }
                    }
                    .appOnChange(of: state.isSaveSuccessful) { saved in
                        guard saved else { return }
                        initialLevels = currentLevels
                        guard !bridge.isNotebookRubricAutoAdvanceActive else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            closeRubric()
                        }
                    }
                    .sheet(isPresented: $showingFamilyReportSheet) {
                        let selectedIds = Self.levelsById(state.selectedLevels)
                        let resolvedClass = bridge.classes.first(where: { $0.id == (bridge.rubricEvaluationCoordinator.context?.classId ?? -1) })?.name ?? "Educación Física"
                        RubricExportFamilyPDFSheet(
                            rubricDetail: rubric,
                            selectedLevelIds: selectedIds,
                            studentName: state.studentName,
                            className: resolvedClass,
                            currentScore: selectedScore
                        )
                    }
                    .sheet(isPresented: $showingMetacognitionSheet) {
                        let band = qualitativeGradeBand(for: selectedScore)
                        RubricMetacognitionSheet(
                            rubricTitle: rubric.rubric.name,
                            studentName: state.studentName,
                            scoreSummary: "\(IosFormatting.scoreOutOfTen(from: selectedScore))/10 · \(band.label)",
                            criteriaNames: rubric.criteria.map { $0.criterion.description_ }
                        )
                    }
                } else if let error = state.error {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(EvaluationDesign.danger)
                        Text("No se pudo abrir la rúbrica")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                        Text(error)
                            .font(.footnote.weight(.medium))
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
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(EvaluationDesign.danger)
                        Text("No se pudo abrir la rúbrica")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                        Text("La rúbrica seleccionada no existe o no se pudo cargar.")
                            .font(.footnote.weight(.medium))
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
        .interactiveDismissDisabled(isDirty)
        .confirmationDialog(
            "Tienes cambios sin guardar",
            isPresented: $showingDiscardDialog,
            titleVisibility: .visible
        ) {
            Button("Guardar") { saveAndClose() }
            Button("Descartar cambios", role: .destructive) { closeRubric() }
            Button("Seguir evaluando", role: .cancel) {}
        } message: {
            Text("Si sales ahora, se perderán los niveles que has cambiado.")
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

    /// Banda cualitativa con la misma escala de 4 pasos que los niveles
    /// (`RubricsStyle.scoreStep`): rojo · naranja · menta · verde.
    private func qualitativeGradeBand(for score: Double) -> (label: String, step: Int) {
        let step = RubricsStyle.scoreStep(forScoreOutOfTen: score)
        let label: String
        if score >= 9.0 {
            label = "Sobresaliente"
        } else if score >= 7.0 {
            label = "Notable"
        } else if score >= 6.0 {
            label = "Bien"
        } else if score >= 5.0 {
            label = "Suficiente"
        } else {
            label = "Insuficiente"
        }
        return (label, step)
    }

    // MARK: - Teclado, criterio activo y cambios sin guardar

    private func firstUnansweredCriterionId(rubric: RubricDetail) -> Int64? {
        let answered = Set(currentLevels.keys)
        return rubric.criteria.map { $0.criterion.id }.first { !answered.contains($0) }
            ?? rubric.criteria.first?.criterion.id
    }

    private func resetSnapshot(rubric: RubricDetail) {
        initialLevels = currentLevels
        activeCriterionId = firstUnansweredCriterionId(rubric: rubric)
    }

    private func refreshResolvedCriteria(rubric: RubricDetail) {
        resolvedCriteria = LomloeCriteriaCatalog.resolveCriteria(from: rubricCriteriaSummary(rubric: rubric))
    }

    /// Siguiente criterio sin nivel a partir de `id` (dando la vuelta); `nil` si no queda ninguno.
    private func nextUnansweredCriterionId(after id: Int64, answered: Set<Int64>, rubric: RubricDetail) -> Int64? {
        let ids = rubric.criteria.map { $0.criterion.id }
        guard let idx = ids.firstIndex(of: id) else { return nil }
        let rotated = Array(ids[(idx + 1)...]) + Array(ids[..<idx])
        return rotated.first { !answered.contains($0) }
    }

    private func selectLevel(_ levelId: Int64, for criterion: RubricCriterionWithLevels, rubric: RubricDetail) {
        let criterionId = criterion.criterion.id
        bridge.rubricEvaluationViewModel.selectLevel(criterionId: criterionId, levelId: levelId)
        var answered = Set(currentLevels.keys)
        answered.insert(criterionId)
        activeCriterionId = nextUnansweredCriterionId(after: criterionId, answered: answered, rubric: rubric) ?? criterionId
        keysFocused = true
    }

    private func handleDigitKey(_ press: KeyPress, rubric: RubricDetail) -> KeyPress.Result {
        guard press.modifiers.isEmpty,
              let digit = Int(press.characters), digit >= 1,
              let activeId = activeCriterionId,
              let criterion = rubric.criteria.first(where: { $0.criterion.id == activeId }),
              digit <= criterion.levels.count else { return .ignored }
        selectLevel(criterion.levels[digit - 1].id, for: criterion, rubric: rubric)
        return .handled
    }

    private func moveActiveCriterion(by delta: Int, rubric: RubricDetail) -> KeyPress.Result {
        let ids = rubric.criteria.map { $0.criterion.id }
        guard !ids.isEmpty else { return .ignored }
        let current = activeCriterionId.flatMap { ids.firstIndex(of: $0) } ?? 0
        activeCriterionId = ids[min(max(current + delta, 0), ids.count - 1)]
        return .handled
    }

    /// Cierre pedido por la persona usuaria (X, Esc): avisa si hay cambios sin guardar.
    private func requestClose() {
        if isDirty {
            showingDiscardDialog = true
        } else {
            closeRubric()
        }
    }

    private func saveAndClose() {
        bridge.saveRubricEvaluation(
            manual: true,
            emitNotebookRefresh: true,
            onSuccess: {
                bridge.refreshCurrentNotebook()
                closeRubric()
            }
        )
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
        guard !state.isSaving else { return }
        AppleInteractionFeedback.play(.selection)
        guard let context = bridge.rubricEvaluationCoordinator.context else { return }
        let columnId = context.columnId
        let rubricId = context.rubricId
        let evaluationId = context.evaluationId
        let classId = context.classId
        let studentIds = context.studentIds

        let navigate = {
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

        // Sin niveles elegidos no hay nada que guardar: evita crear una nota 0.0 falsa.
        if state.selectedLevels.isEmpty {
            navigate()
            return
        }

        bridge.saveRubricEvaluation(
            manual: true,
            emitNotebookRefresh: true,
            onSuccess: navigate
        )
    }

    private func saveOnly() {
        AppleInteractionFeedback.play(.selection)
        bridge.saveRubricEvaluation(
            manual: true,
            emitNotebookRefresh: true,
            onSuccess: {
                initialLevels = currentLevels
                AppleInteractionFeedback.play(.success)
            }
        )
    }

    private func saveAndNextOrFinish() {
        if canNavigateNext {
            // La vibración la emite saveAndNavigate.
            navigateToNextStudent()
        } else {
            AppleInteractionFeedback.play(.selection)
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
        VStack(alignment: .leading, spacing: 8) {
            InstrumentEvaluationChromeSurface(role: .header) {
                HStack(alignment: .center, spacing: 12) {
                    Button(action: requestClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help("Cerrar (Esc)")
                    .accessibilityLabel("Cerrar")

                    // Avatar con iniciales
                    Circle()
                        .fill(EvaluationDesign.accent.opacity(0.14))
                        .overlay(
                            Text(studentInitials)
                                .font(.system(.footnote, design: .rounded).weight(.bold))
                                .foregroundStyle(EvaluationDesign.accent)
                        )
                        .frame(width: 40, height: 40)
                        .accessibilityHidden(true)

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
                    if studentPosition != nil {
                        HStack(spacing: 4) {
                            Button(action: navigateToPreviousStudent) {
                                Image(systemName: "chevron.left")
                                    .font(.body.weight(.bold))
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
                                    .font(.body.weight(.bold))
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

                    // Un solo anillo de nota + banda cualitativa + menú de extras
                    HStack(spacing: 8) {
                        if progress > 0 {
                            let band = qualitativeGradeBand(for: score)
                            Text(band.label)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(RubricsStyle.stepTextColor(band.step, scheme: colorScheme))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(RubricsStyle.stepColor(band.step).opacity(0.14))
                                )
                        }

                        RubricScoreRing(progress: progress, scoreOutOfTen: score)

                        Menu {
                            Button {
                                showingFamilyReportSheet = true
                            } label: {
                                Label("Informe PDF para familias", systemImage: "doc.text")
                            }
                            Button {
                                showingMetacognitionSheet = true
                            } label: {
                                Label("Metacognición y coevaluación (IA)", systemImage: "brain.head.profile")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityLabel("Más acciones")
                    }
                }
            }

            RubricCriteriaChipsView(
                statements: state.criterionStatements,
                resolved: resolvedCriteria,
                fallbackText: state.criterionLabel
            )
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
        let answeredCriteria = rubric.criteria.filter { state.selectedLevels[KotlinLong(value: $0.criterion.id)] != nil }.count
        let isComplete = totalCriteria > 0 && answeredCriteria >= totalCriteria
        let showsToggle = usesMatrix(rubric)

        return InstrumentEvaluationChromeSurface(role: .action, padding: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    saveStatus(rubric: rubric, answeredCriteria: answeredCriteria, isComplete: isComplete)
                    Spacer(minLength: 8)
                    actionButtons(isComplete: isComplete, showsDescriptionToggle: showsToggle)
                }

                VStack(alignment: .leading, spacing: 8) {
                    saveStatus(rubric: rubric, answeredCriteria: answeredCriteria, isComplete: isComplete)
                    actionButtons(isComplete: isComplete, showsDescriptionToggle: showsToggle)
                }
            }
        }
    }

    /// Progreso por segmentos (uno por criterio, 6pt) + "2 de 3". La nota ya
    /// está en el anillo de la cabecera: aquí no se repite.
    private func saveStatus(rubric: RubricDetail, answeredCriteria: Int, isComplete: Bool) -> some View {
        let tint = isComplete ? EvaluationDesign.success : EvaluationDesign.accent
        return HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(rubric.criteria, id: \.criterion.id) { criterion in
                    let answered = state.selectedLevels[KotlinLong(value: criterion.criterion.id)] != nil
                    Capsule()
                        .fill(answered ? tint : Color.secondary.opacity(0.18))
                        .frame(height: 6)
                }
            }
            .frame(width: min(CGFloat(max(rubric.criteria.count, 1)) * 24, 160))
            .animation(uiFeatureFlags.interactionAnimation, value: answeredCriteria)

            Text("\(answeredCriteria) de \(rubric.criteria.count)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isComplete ? RubricsStyle.stepTextColor(3, scheme: colorScheme) : .secondary)

            if isComplete {
                Image(systemName: "checkmark.seal.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(EvaluationDesign.success)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progreso de la rúbrica")
        .accessibilityValue("\(answeredCriteria) de \(rubric.criteria.count) criterios")
    }

    private func actionButtons(isComplete: Bool, showsDescriptionToggle: Bool) -> some View {
        HStack(spacing: 8) {
            if state.isSaving {
                ProgressView()
                    .controlSize(.small)
            }

            if showsDescriptionToggle {
                Button {
                    hidesLevelDescriptions.toggle()
                } label: {
                    Label(
                        hidesLevelDescriptions ? "Mostrar textos" : "Ocultar textos",
                        systemImage: hidesLevelDescriptions ? "text.alignleft" : "eye.slash"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(hidesLevelDescriptions ? "Mostrar la descripción de cada nivel" : "Ver solo el número y el nombre de cada nivel")
            }

            Button(action: saveOnly) {
                Text("Guardar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(EvaluationDesign.accent)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state.isSaving)
            .accessibilityLabel("Guardar evaluación actual")

            Button(action: saveAndNextOrFinish) {
                HStack(spacing: 8) {
                    Text(canNavigateNext ? "Siguiente" : "Finalizar")
                        .font(.subheadline.weight(.bold))
                    #if os(macOS)
                    Text("⌘↩")
                        .font(.footnote.weight(.semibold))
                        .opacity(0.8)
                    #endif
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isComplete ? EvaluationDesign.success : EvaluationDesign.accent)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(NotebookScaleButtonStyle())
            .disabled(state.isSaving)
            .keyboardShortcut(.return, modifiers: [.command])
            .help(canNavigateNext ? "Guardar y siguiente alumno (⌘↩)" : "Guardar y cerrar (⌘↩)")
            .accessibilityLabel(canNavigateNext ? "Guardar y siguiente alumno" : "Guardar y finalizar rúbrica")
        }
    }

    // MARK: - Criteria Panel

    @ViewBuilder
    private func criteriaPanel(rubric: RubricDetail) -> some View {
        // El peso es relativo (la nota se calcula sobre el total), así que el
        // porcentaje se saca del total y vale igual con pesos 0,4 o 40.
        let totalWeight = rubric.criteria.reduce(0.0) { $0 + max($1.criterion.weight, 0) }
        if usesMatrix(rubric) {
            RubricMatrixView(
                criteria: rubric.criteria,
                totalWeight: totalWeight,
                selectedLevelIds: currentLevels,
                activeCriterionId: activeCriterionId,
                hidesDescriptions: hidesLevelDescriptions,
                onActivate: { id in
                    activeCriterionId = id
                    keysFocused = true
                },
                onSelectLevel: { criterion, levelId in
                    selectLevel(levelId, for: criterion, rubric: rubric)
                }
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rubric.criteria, id: \.criterion.id) { criterion in
                    RubricCriterionRow(
                        item: criterion,
                        totalWeight: totalWeight,
                        selectedLevelId: state.selectedLevels[KotlinLong(value: criterion.criterion.id)]?.int64Value,
                        isActive: activeCriterionId == criterion.criterion.id,
                        onActivate: {
                            activeCriterionId = criterion.criterion.id
                            keysFocused = true
                        },
                        onSelectLevel: { levelId in
                            selectLevel(levelId, for: criterion, rubric: rubric)
                        }
                    )
                    .id(criterion.criterion.id)
                }
            }
        }
    }

    private func closeRubric() {
        bridge.closeRubricEvaluation()
    }
}

/// Línea de chips "CE 2.1 · CE 3.2" desplegable con el enunciado de cada
/// criterio. Sustituye a `AssessmentCriteriaDisclosureView` +
/// `EvaluationCriterionSection`, que mostraban dos veces lo mismo. Prefiere
/// los enunciados oficiales del instrumento (`statements`); si no hay, usa las
/// definiciones LOMLOE resueltas por texto; y como último recurso el texto
/// libre de la evaluación.
private struct RubricCriteriaChipsView: View {
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    let statements: [CriterionStatement]
    let resolved: [LomloeCriterionDefinition]
    let fallbackText: String?
    @State private var isExpanded = false

    private struct Entry: Identifiable {
        let code: String
        let text: String
        var id: String { code }
    }

    private var trimmedFallback: String {
        fallbackText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var entries: [Entry] {
        if !statements.isEmpty {
            return statements.map { Entry(code: "CE \($0.code)", text: $0.statement) }
        }
        return resolved.map { Entry(code: $0.code, text: $0.officialDescription) }
    }

    var body: some View {
        let entries = entries
        if entries.isEmpty && trimmedFallback.isEmpty {
            EmptyView()
        } else {
            InstrumentEvaluationChromeSurface(role: .context, padding: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation(uiFeatureFlags.interactionAnimation) { isExpanded.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            if entries.isEmpty {
                                chip("Criterio")
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(entries) { chip($0.code) }
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Criterios de evaluación")
                    .accessibilityValue(isExpanded ? "Desplegado" : "Plegado")

                    if isExpanded {
                        VStack(alignment: .leading, spacing: 8) {
                            if entries.isEmpty {
                                Text(trimmedFallback)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                ForEach(entries) { entry in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.code)
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.primary)
                                        Text(entry.text)
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .fixedSize()
    }
}

struct RubricCriterionRow: View {
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @Environment(\.colorScheme) private var colorScheme
    let item: RubricCriterionWithLevels
    var totalWeight: Double = 0
    let selectedLevelId: Int64?
    var isActive: Bool = false
    var onActivate: () -> Void = {}
    let onSelectLevel: (Int64) -> Void

    /// Máximo de puntos del criterio, calculado una sola vez.
    private let maxPoints: Double
    @State private var gridWidth: CGFloat = 0
    @State private var selectionTick = 0

    private let gridSpacing: CGFloat = 8
    private let minCardWidth: CGFloat = 152

    init(
        item: RubricCriterionWithLevels,
        totalWeight: Double = 0,
        selectedLevelId: Int64?,
        isActive: Bool = false,
        onActivate: @escaping () -> Void = {},
        onSelectLevel: @escaping (Int64) -> Void
    ) {
        self.item = item
        self.totalWeight = totalWeight
        self.selectedLevelId = selectedLevelId
        self.isActive = isActive
        self.onActivate = onActivate
        self.onSelectLevel = onSelectLevel
        self.maxPoints = Double(item.levels.map(\.points).max() ?? 0)
    }

    private var selectedLevel: RubricLevel? {
        item.levels.first { $0.id == selectedLevelId }
    }

    /// Columnas según el ancho medido, repartidas para que las filas queden
    /// equilibradas (4 niveles en hueco de 3 → 2 + 2, no 3 + 1).
    private var columnCount: Int {
        let count = max(item.levels.count, 1)
        guard gridWidth > 0 else { return count }
        let fit = max(Int((gridWidth + gridSpacing) / (minCardWidth + gridSpacing)), 1)
        guard fit < count else { return count }
        let rows = Int((Double(count) / Double(fit)).rounded(.up))
        return Int((Double(count) / Double(rows)).rounded(.up))
    }

    private var weightPercent: Int? {
        guard item.criterion.weight > 0, totalWeight > 0 else { return nil }
        let value = Int((item.criterion.weight / totalWeight * 100).rounded())
        return value > 0 ? value : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.criterion.description_)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if let weightPercent {
                    Text("\(weightPercent)%")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }

                Spacer(minLength: 8)

                if let selectedLevel {
                    let tint = RubricsStyle.levelColor(points: Double(selectedLevel.points), maxPoints: maxPoints)
                    let textTint = RubricsStyle.levelTextColor(
                        points: Double(selectedLevel.points), maxPoints: maxPoints, scheme: colorScheme
                    )
                    Text("\(RubricsStyle.cleanLevelTitle(selectedLevel.name)) · \(RubricsStyle.pointsText(Double(selectedLevel.points)))")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(textTint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(tint.opacity(0.14)))
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }

            levelsGrid
        }
        .padding(16)
        .overlay {
            RoundedRectangle(cornerRadius: RubricsStyle.cardRadius, style: .continuous)
                .stroke(isActive ? EvaluationDesign.accent : Color.clear, lineWidth: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: RubricsStyle.cardRadius, style: .continuous))
        .onTapGesture(perform: onActivate)
        .animation(uiFeatureFlags.interactionAnimation, value: selectedLevelId)
        .animation(uiFeatureFlags.interactionAnimation, value: isActive)
        .sensoryFeedback(.selection, trigger: selectionTick)
    }

    private var levelsGrid: some View {
        let columns = columnCount
        let levels = item.levels
        return Grid(alignment: .topLeading, horizontalSpacing: gridSpacing, verticalSpacing: gridSpacing) {
            ForEach(Array(stride(from: 0, to: levels.count, by: columns)), id: \.self) { start in
                GridRow {
                    ForEach(start..<min(start + columns, levels.count), id: \.self) { index in
                        levelPill(levels[index], position: index + 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
    }

    private func levelPill(_ level: RubricLevel, position: Int) -> some View {
        RubricLevelPill(
            title: level.name,
            points: Double(level.points),
            maxPoints: maxPoints,
            isSelected: selectedLevelId == level.id,
            onSelect: {
                selectionTick += 1
                onSelectLevel(level.id)
            },
            description: level.description_,
            position: position
        )
    }
}

/// Rúbrica en tabla: criterios en filas y niveles en columnas, con la cabecera
/// de niveles una sola vez. Cabe una rúbrica de 3 × 4 sin scroll en Mac. Solo
/// se usa si todos los criterios tienen el mismo número de niveles
/// (`isEligible`) y hay ancho; si no, `RubricCriterionRow` (tarjetas).
struct RubricMatrixView: View {
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags
    @Environment(\.colorScheme) private var colorScheme
    let criteria: [RubricCriterionWithLevels]
    let totalWeight: Double
    let selectedLevelIds: [Int64: Int64]
    let activeCriterionId: Int64?
    /// Celdas con solo número y nombre de nivel (rúbricas que se conocen de memoria).
    let hidesDescriptions: Bool
    let onActivate: (Int64) -> Void
    let onSelectLevel: (RubricCriterionWithLevels, Int64) -> Void

    @State private var selectionTick = 0

    private let criterionColumnWidth: CGFloat = 200
    private let spacing: CGFloat = 8
    private let rowPadding: CGFloat = 8

    /// Mismo número de niveles (2-6) en todos los criterios.
    static func isEligible(_ criteria: [RubricCriterionWithLevels]) -> Bool {
        guard let count = criteria.first?.levels.count, (2...6).contains(count) else { return false }
        return criteria.allSatisfy { $0.levels.count == count }
    }

    /// Puntos de la columna si todos los criterios coinciden; si no, `nil`.
    private func sharedPoints(at index: Int) -> Double? {
        let values = Set(criteria.map { Double($0.levels[index].points) })
        return values.count == 1 ? values.first : nil
    }

    /// Hay sitio para la tabla si cada columna de nivel tiene al menos 140 pt
    /// (márgenes de pantalla incluidos). En iPad vertical se quedan las tarjetas.
    static func fits(_ criteria: [RubricCriterionWithLevels], in width: CGFloat) -> Bool {
        guard isEligible(criteria), let count = criteria.first?.levels.count else { return false }
        let needed: CGFloat = 200 + 16 + CGFloat(count) * 148 + 48
        return width >= needed
    }

    private var maxSharedPoints: Double {
        Double(criteria.first?.levels.map(\.points).max() ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            headerRow
            ForEach(criteria, id: \.criterion.id) { item in
                criterionRow(item)
                    .id(item.criterion.id)
            }
        }
        .animation(uiFeatureFlags.interactionAnimation, value: selectedLevelIds)
        .animation(uiFeatureFlags.interactionAnimation, value: activeCriterionId)
        .sensoryFeedback(.selection, trigger: selectionTick)
    }

    // MARK: Cabecera de niveles

    private var headerRow: some View {
        RubricMatrixRowLayout(leadingWidth: criterionColumnWidth, spacing: spacing) {
            Color.clear.frame(height: 1)
            if let first = criteria.first {
                ForEach(Array(first.levels.enumerated()), id: \.offset) { index, level in
                    levelHeader(level, position: index + 1, points: sharedPoints(at: index))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
        }
        .padding(.horizontal, rowPadding)
        .accessibilityHidden(true)
    }

    private func levelHeader(_ level: RubricLevel, position: Int, points: Double?) -> some View {
        let color = RubricsStyle.levelColor(points: Double(level.points), maxPoints: maxSharedPoints)
        let textColor = RubricsStyle.levelTextColor(points: Double(level.points), maxPoints: maxSharedPoints, scheme: colorScheme)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(position)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(textColor)
                .frame(width: 24, height: 24)
                .background(Circle().fill(color.opacity(0.16)))
            VStack(alignment: .leading, spacing: 0) {
                Text(RubricsStyle.cleanLevelTitle(level.name))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let points {
                    Text(RubricsStyle.pointsText(points))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Fila de criterio

    private func criterionRow(_ item: RubricCriterionWithLevels) -> some View {
        let isActive = activeCriterionId == item.criterion.id
        let maxPoints = Double(item.levels.map(\.points).max() ?? 0)
        let shape = RoundedRectangle(cornerRadius: RubricsStyle.cardRadius, style: .continuous)
        return RubricMatrixRowLayout(leadingWidth: criterionColumnWidth, spacing: spacing) {
            criterionLabel(item, maxPoints: maxPoints)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture { onActivate(item.criterion.id) }
            ForEach(Array(item.levels.enumerated()), id: \.element.id) { index, level in
                levelCell(item, level: level, position: index + 1, maxPoints: maxPoints)
            }
        }
        .padding(rowPadding)
        .overlay {
            shape.stroke(isActive ? EvaluationDesign.accent : Color.clear, lineWidth: 2)
        }
    }

    private func criterionLabel(_ item: RubricCriterionWithLevels, maxPoints: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.criterion.description_)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let percent = weightPercent(item) {
                Text("\(percent)%")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }
        }
        .padding(.top, 4)
    }

    private func weightPercent(_ item: RubricCriterionWithLevels) -> Int? {
        guard item.criterion.weight > 0, totalWeight > 0 else { return nil }
        let value = Int((item.criterion.weight / totalWeight * 100).rounded())
        return value > 0 ? value : nil
    }

    // MARK: Celda de nivel

    private func levelCell(
        _ item: RubricCriterionWithLevels,
        level: RubricLevel,
        position: Int,
        maxPoints: Double
    ) -> some View {
        let isSelected = selectedLevelIds[item.criterion.id] == level.id
        let points = Double(level.points)
        let color = RubricsStyle.levelColor(points: points, maxPoints: maxPoints)
        let textColor = RubricsStyle.levelTextColor(points: points, maxPoints: maxPoints, scheme: colorScheme)
        let title = RubricsStyle.cleanLevelTitle(level.name)
        let description = (level.description_ ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let showsDescription = !hidesDescriptions && !description.isEmpty
        let shape = RoundedRectangle(cornerRadius: RubricsStyle.rowRadius, style: .continuous)

        return Button {
            selectionTick += 1
            onSelectLevel(item, level.id)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                if showsDescription {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("\(position) · \(title)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? textColor : Color.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? textColor : Color.secondary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: showsDescription ? .topLeading : .leading)
            .frame(minHeight: 44)
            .background(shape.fill(isSelected ? color.opacity(0.14) : Color.primary.opacity(0.04)))
            .overlay {
                shape.stroke(isSelected ? color : RubricsStyle.hairline, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(description.isEmpty ? "\(title) · \(RubricsStyle.pointsText(points))" : description)
        .accessibilityLabel("\(item.criterion.description_): \(title), \(RubricsStyle.pointsText(points))")
        .accessibilityHint(description)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Fila de la tabla de rúbrica: primera columna de ancho fijo y el resto a
/// partes iguales; todas las celdas con la altura de la más alta.
struct RubricMatrixRowLayout: Layout {
    var leadingWidth: CGFloat
    var spacing: CGFloat

    func columnWidths(total: CGFloat, count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [total] }
        let rest = max(total - leadingWidth - spacing * CGFloat(count - 1), 0) / CGFloat(count - 1)
        return [leadingWidth] + Array(repeating: rest, count: count - 1)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? (leadingWidth + CGFloat(max(subviews.count - 1, 0)) * (200 + spacing))
        let widths = columnWidths(total: total, count: subviews.count)
        let height = zip(subviews, widths)
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
            .max() ?? 0
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, columnWidths(total: bounds.width, count: subviews.count)) {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }
}
