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
    /// Solo se redibuja con el estado de la evaluación masiva, no con cualquier cambio del bridge.
    @StateObject private var bridgeWatch = KmpBridgeWatch()
    @State private var options: [TournamentRubricOption] = []
    @State private var optionsPhase: Phase = .loading
    @ScaledMetric(relativeTo: .body) private var levelHeight: CGFloat = 44

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
                    if !options.isEmpty {
                        ToolbarItem(placement: .navigation) { rubricMenu }
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
            Label(selectedOption?.evaluationName ?? "Rúbrica", systemImage: "checklist")
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        }
        .accessibilityLabel("Cambiar rúbrica")
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
                Text("\(student.firstName) \(student.lastName)")
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
        return VStack(alignment: .leading, spacing: 8) {
            Text(item.criterion.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(levels, id: \.id) { level in
                    levelButton(level, isSelected: level.id == selectedLevelId) {
                        bridge.bulkSelectLevel(studentId: studentId, criterionId: item.criterion.id, levelId: level.id)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.criterion.description)
    }

    @ViewBuilder
    private func levelButton(_ level: RubricLevel, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let label = Text(level.name)
            .font(.callout.weight(isSelected ? .semibold : .regular))
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: levelHeight)
        if isSelected {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent)
                .accessibilityAddTraits(.isSelected)
        } else {
            Button(action: action) { label }
                .buttonStyle(.bordered)
                .tint(.secondary)
        }
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

    private static func formatScore(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
