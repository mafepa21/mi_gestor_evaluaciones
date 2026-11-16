import SwiftUI
import MiGestorKit

/// Equipo tocado en el modo directo para evaluarlo con rúbrica.
struct SdaRubricTeamTarget: Identifiable, Equatable {
    let team: TournamentPlanTeam
    var id: String { team.id }
}

/// Hoja compacta del modo directo: evalúa con rúbrica a los alumnos de un equipo.
///
/// Usa el ViewModel de evaluación masiva sin abrir su hoja: cada nivel tocado se guarda solo
/// (guardado automático) en la columna del Cuaderno de la evaluación elegida. La rúbrica
/// elegida (`selectedEvaluationId`) la guarda el modo directo, así el siguiente equipo ya la trae.
struct SdaTournamentRubricSheet: View {
    let bridge: KmpBridge
    let classId: Int64
    let team: TournamentPlanTeam
    @Binding var selectedEvaluationId: Int64?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    /// Solo se redibuja con el estado de la evaluación masiva, no con cualquier cambio del bridge.
    @StateObject private var bridgeWatch = KmpBridgeWatch()
    @State private var options: [TournamentRubricOption] = []
    @State private var optionsPhase: Phase = .loading

    private enum Phase: Equatable { case loading, ready, failed }

    private var watchedBridge: KmpBridge {
        bridgeWatch.bridge(bridge) { [.init($0.bulkRubricEvaluationState)] }
    }

    private var selectedOption: TournamentRubricOption? {
        options.first { $0.evaluationId == selectedEvaluationId }
    }

    private var teamStudentIds: [Int64] { team.studentIDs.compactMap { Int64($0) } }

    /// Estado de la evaluación masiva solo si ya es el de la rúbrica elegida (no el anterior).
    private var loadedState: BulkRubricEvaluationUiState? {
        guard let option = selectedOption,
              let state = watchedBridge.bulkRubricEvaluationState,
              state.classId == classId,
              state.evaluationId == option.evaluationId,
              state.rubricDetail?.rubric.id == option.rubricId,
              !state.isLoading
        else { return nil }
        return state
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(team.name)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Listo") { dismiss() }
                    }
                }
        }
        .presentationDetents([.large])
        .task { await loadOptions() }
        .onChange(of: selectedEvaluationId) { _, _ in loadSelectedRubric() }
        .onDisappear { bridge.finishTournamentRubric(classId: classId) }
    }

    // MARK: Contenido por estado

    @ViewBuilder
    private var content: some View {
        if teamStudentIds.isEmpty {
            ContentUnavailableView(
                "Equipo sin alumnos",
                systemImage: "person.2.slash",
                description: Text("Asigna alumnos a este equipo en «Integrantes» para poder evaluarlos.")
            )
        } else {
            switch optionsPhase {
            case .loading:
                ProgressView("Cargando rúbricas…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                ContentUnavailableView {
                    Label("No se pudieron cargar las rúbricas", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("Reintentar") { Task { await loadOptions() } }
                }
            case .ready:
                if options.isEmpty {
                    ContentUnavailableView(
                        "Sin rúbricas en esta clase",
                        systemImage: "checklist",
                        description: Text("Crea en el Cuaderno una evaluación con rúbrica y vuelve aquí.")
                    )
                } else if selectedOption == nil {
                    rubricPicker
                } else {
                    evaluationContent
                }
            }
        }
    }

    /// Primera vez en este modo directo: elegir la rúbrica en una lista grande y clara.
    private var rubricPicker: some View {
        List {
            Section {
                ForEach(options) { option in
                    Button {
                        selectedEvaluationId = option.evaluationId
                    } label: {
                        optionLabel(option)
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("¿Con qué rúbrica evalúas?")
            } footer: {
                Text("Se recordará para los demás equipos mientras dure el modo directo.")
            }
        }
    }

    @ViewBuilder
    private var evaluationContent: some View {
        if let state = loadedState, let rubric = state.rubricDetail {
            let members = teamMembers(in: state)
            let assessments = bridge.bulkAssessmentSnapshot(from: state)
            let scores = bridge.bulkScoreSnapshot(from: state)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    rubricMenu
                    if let error = state.error {
                        LearningSituationInlineNotice(
                            kind: .warning,
                            message: "No se guardó algún nivel. Vuelve a tocarlo. (\(error))"
                        )
                    }
                    if members.isEmpty {
                        Text("Los alumnos de este equipo no están en la clase.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(members, id: \.id) { student in
                        studentCard(
                            student,
                            rubric: rubric,
                            selections: assessments[student.id] ?? [:],
                            score: scores[student.id]
                        )
                    }
                    Text("Cada nivel se guarda al tocarlo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
            }
            .background(IOSAppStyle.pageBackground)
        } else if let state = watchedBridge.bulkRubricEvaluationState,
                  !state.isLoading,
                  state.evaluationId == selectedEvaluationId,
                  let error = state.error {
            ContentUnavailableView {
                Label("No se pudo abrir la rúbrica", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Reintentar") { loadSelectedRubric() }
            }
        } else {
            ProgressView("Abriendo rúbrica…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Piezas

    private var rubricMenu: some View {
        Menu {
            Picker("Rúbrica", selection: $selectedEvaluationId) {
                ForEach(options) { option in
                    Text(option.evaluationName).tag(Optional(option.evaluationId))
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedOption?.evaluationName ?? "Rúbrica")
                        .font(.headline)
                        .lineLimit(1)
                    Text("Cambiar rúbrica")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(IOSAppStyle.cardBackground, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rúbrica: \(selectedOption?.evaluationName ?? "sin elegir"). Cambiar rúbrica")
    }

    private func optionLabel(_ option: TournamentRubricOption) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(option.evaluationName).font(.headline)
            if option.rubricName != option.evaluationName {
                Text(option.rubricName).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func studentCard(
        _ student: Student,
        rubric: RubricDetail,
        selections: [Int64: Int64],
        score: Double?
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.displayName(student))
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 8)
                Text(score.map(Self.formatScore) ?? "–")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(score == nil ? Color.secondary : Color.primary)
                    .accessibilityLabel(score.map { "Nota \(Self.formatScore($0))" } ?? "Sin nota")
            }
            ForEach(rubric.criteria, id: \.criterion.id) { item in
                criterionRow(item, studentId: student.id, selectedLevelId: selections[item.criterion.id])
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IOSAppStyle.cardBackground, in: RoundedRectangle(cornerRadius: IOSAppStyle.cardRadius, style: .continuous))
    }

    private func criterionRow(_ item: RubricCriterionWithLevels, studentId: Int64, selectedLevelId: Int64?) -> some View {
        let levels = item.levels.sorted { $0.order < $1.order }
        let maxPoints = Double(levels.map(\.points).max() ?? 0)
        return VStack(alignment: .leading, spacing: 8) {
            // `description_`: en Swift `description` es el texto interno del objeto Kotlin.
            Text(item.criterion.description_)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            // Todas las celdas igual de altas: la de descriptor más largo manda.
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(levels.enumerated()), id: \.element.id) { index, level in
                    levelCell(
                        item,
                        level: level,
                        position: index + 1,
                        maxPoints: maxPoints,
                        isSelected: level.id == selectedLevelId
                    ) {
                        bridge.bulkSelectLevel(studentId: studentId, criterionId: item.criterion.id, levelId: level.id)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Celda de nivel: título corto arriba y su descriptor debajo, con el color del nivel
    /// (mismo criterio que `RubricEvaluationView`).
    private func levelCell(
        _ item: RubricCriterionWithLevels,
        level: RubricLevel,
        position: Int,
        maxPoints: Double,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let points = Double(level.points)
        let color = RubricsStyle.levelColor(points: points, maxPoints: maxPoints)
        let textColor = RubricsStyle.levelTextColor(points: points, maxPoints: maxPoints, scheme: colorScheme)
        let title = RubricsStyle.cleanLevelTitle(level.name)
        let descriptor = (level.description_ ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let shape = RoundedRectangle(cornerRadius: RubricsStyle.rowRadius, style: .continuous)

        return Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("\(position) · \(title)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? textColor : Color.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? textColor : Color.secondary.opacity(0.5))
                }
                if !descriptor.isEmpty {
                    Text(descriptor)
                        .font(.footnote)
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minHeight: 44)
            .background(shape.fill(isSelected ? color.opacity(0.14) : Color.primary.opacity(0.04)))
            .overlay {
                shape.stroke(isSelected ? color : RubricsStyle.hairline, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.criterion.description_): \(title), \(RubricsStyle.pointsText(points))")
        .accessibilityHint(descriptor)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: Datos

    private func teamMembers(in state: BulkRubricEvaluationUiState) -> [Student] {
        let byId = Dictionary(state.students.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return teamStudentIds.compactMap { byId[$0] }
    }

    private func loadOptions() async {
        optionsPhase = .loading
        do {
            options = try await bridge.tournamentRubricOptions(classId: classId)
            optionsPhase = .ready
            if selectedOption == nil, options.count == 1 {
                // `onChange(of: selectedEvaluationId)` la carga.
                selectedEvaluationId = options[0].evaluationId
            } else {
                loadSelectedRubric()
            }
        } catch {
            optionsPhase = .failed
        }
    }

    private func loadSelectedRubric() {
        guard let option = selectedOption else { return }
        bridge.loadTournamentRubric(option, classId: classId)
    }

    /// Nombre y apellidos sin espacios ni comas sueltas al final (algunos apellidos importados las traen).
    private static func displayName(_ student: Student) -> String {
        "\(student.firstName) \(student.lastName)"
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
    }

    private static func formatScore(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
