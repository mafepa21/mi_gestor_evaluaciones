import SwiftUI
import MiGestorKit

/// Hoja «Nuevo torneo»: los equipos son los grupos de trabajo de la SdA.
/// Al crear genera el calendario y guarda el torneo.
struct SdaNewTournamentSheet: View {
    let learningSituationId: Int64
    let teams: [TournamentWorkGroupTeam]
    let suggestedName: String
    let preferredClassId: Int64?
    let onCreated: (TournamentRecord) -> Void

    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var format: TournamentFormat = .roundRobin
    @State private var classId: Int64
    @State private var excludedGroupIds = Set<Int64>()
    @State private var membersPopoverGroupId: Int64?
    @State private var venueCount = 2
    @State private var matchMinutes = 8
    @State private var transitionMinutes = 2
    @State private var requestedGroupCount = 0
    @State private var requestedQualified = 2
    @State private var sessionMinutes: Int?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        learningSituationId: Int64,
        teams: [TournamentWorkGroupTeam],
        suggestedName: String,
        preferredClassId: Int64?,
        onCreated: @escaping (TournamentRecord) -> Void
    ) {
        self.learningSituationId = learningSituationId
        self.teams = teams
        self.suggestedName = suggestedName
        self.preferredClassId = preferredClassId
        self.onCreated = onCreated
        let classIds = Array(Set(teams.map(\.classId))).sorted()
        let initialClass = preferredClassId.flatMap { classIds.contains($0) ? $0 : nil } ?? classIds.first ?? 0
        _name = State(initialValue: suggestedName)
        _classId = State(initialValue: initialClass)
    }

    // MARK: Datos derivados

    private var classIds: [Int64] {
        Array(Set(teams.map(\.classId))).sorted()
    }

    private var classTeams: [TournamentWorkGroupTeam] {
        teams.filter { $0.classId == classId }
    }

    private var selectedTeams: [TournamentWorkGroupTeam] {
        classTeams.filter { !excludedGroupIds.contains($0.groupId) }
    }

    private func className(_ id: Int64) -> String {
        bridge.classes.first(where: { $0.id == id })?.name ?? "Curso"
    }

    private var resolvedGroupCount: Int {
        let count = selectedTeams.count
        guard count >= 2 else { return 0 }
        return GroupStageConfiguration.option(for: requestedGroupCount, teamCount: count)?.groupCount
            ?? GroupStageConfiguration.defaultGroupCount(for: count)
    }

    private var qualifiedRange: ClosedRange<Int> {
        let count = selectedTeams.count
        let minimum = GroupStageConfiguration.minimumQualifiedTeamsPerGroup(groupCount: resolvedGroupCount, teamCount: count)
        let maximum = GroupStageConfiguration.maximumQualifiedTeamsPerGroup(groupCount: resolvedGroupCount, teamCount: count)
        return minimum...max(minimum, maximum)
    }

    private var resolvedQualified: Int {
        min(max(requestedQualified, qualifiedRange.lowerBound), qualifiedRange.upperBound)
    }

    private var estimate: TournamentPlanEstimate? {
        TournamentPlanEstimator.estimate(
            format: format,
            teamCount: selectedTeams.count,
            groupCount: format == .groupStageKnockout ? resolvedGroupCount : 0,
            qualifiedTeamsPerGroup: format == .groupStageKnockout ? resolvedQualified : 2,
            venueCount: venueCount,
            matchDurationMinutes: matchMinutes,
            transitionMinutes: transitionMinutes
        )
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedTeams.count >= 2
            && estimate != nil
            && !isSaving
    }

    // MARK: Cuerpo

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                if classIds.count > 1 { classSection }
                formatSection
                if format == .groupStageKnockout, selectedTeams.count >= 2 { groupStageSection }
                teamsSection
                settingsSection
                summarySection
                if let errorMessage {
                    Section {
                        LearningSituationInlineNotice(kind: .error, message: errorMessage)
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    }
                }
            }
            .navigationTitle("Nuevo torneo")
            .appInlineNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") { Task { await create() } }
                        .disabled(!canCreate)
                }
            }
            .task(id: classId) { await loadSessionMinutes() }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 640)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var nameSection: some View {
        Section("Nombre") {
            TextField("Nombre del torneo", text: $name)
                .frame(minHeight: 44)
        }
    }

    private var classSection: some View {
        Section {
            Picker("Curso", selection: $classId) {
                ForEach(classIds, id: \.self) { id in
                    Text(className(id)).tag(id)
                }
            }
            .frame(minHeight: 44)
            .onChange(of: classId) { _, _ in excludedGroupIds = [] }
        } header: {
            Text("Curso")
        } footer: {
            Text("Cada torneo es de un solo curso. Los equipos son los grupos de ese curso.")
        }
    }

    private var formatSection: some View {
        Section("Formato") {
            ForEach(TournamentFormat.allCases) { option in
                Button {
                    format = option
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: option.symbolName)
                            .foregroundStyle(EvaluationDesign.accent)
                            .frame(minWidth: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.shortTitle)
                                .foregroundStyle(.primary)
                            Text(option.shortSubtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if option == format {
                            Image(systemName: "checkmark")
                                .foregroundStyle(EvaluationDesign.accent)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(option.shortTitle). \(option.shortSubtitle)")
                .accessibilityAddTraits(option == format ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private var groupStageSection: some View {
        Section {
            Picker("Grupos de la liguilla", selection: Binding(
                get: { resolvedGroupCount },
                set: { requestedGroupCount = $0 }
            )) {
                ForEach(GroupStageConfiguration.options(for: selectedTeams.count)) { option in
                    Text(option.title).tag(option.groupCount)
                }
            }
            .frame(minHeight: 44)
            SdaStepperRow(
                title: "Pasan por grupo",
                value: Binding(
                    get: { resolvedQualified },
                    set: { requestedQualified = $0 }
                ),
                range: qualifiedRange,
                unit: "equipos"
            )
        } header: {
            Text("Liguilla")
        } footer: {
            Text("Los mejores de cada grupo pasan al cuadro final.")
        }
    }

    private var teamsSection: some View {
        Section {
            if classTeams.isEmpty {
                Text("Este curso no tiene grupos de trabajo en la situación.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LearningSituationFlowLayout(spacing: 8) {
                    ForEach(classTeams) { team in
                        teamChip(team)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Equipos")
        } footer: {
            #if os(macOS)
            Text("Toca un grupo para dejarlo fuera de este torneo. Pasa el ratón por encima para ver quién está.")
            #else
            Text("Toca un grupo para dejarlo fuera de este torneo. Mantén pulsado para ver quién está.")
            #endif
        }
    }

    private func teamChip(_ team: TournamentWorkGroupTeam) -> some View {
        let isIncluded = !excludedGroupIds.contains(team.groupId)
        return Button {
            if isIncluded { excludedGroupIds.insert(team.groupId) } else { excludedGroupIds.remove(team.groupId) }
        } label: {
            // El estado no depende solo del color: icono + tachado, y texto en color de sistema (contraste).
            HStack(spacing: 6) {
                Image(systemName: isIncluded ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(isIncluded ? EvaluationDesign.accent : Color.secondary)
                    .accessibilityHidden(true)
                Text(team.name)
                    .strikethrough(!isIncluded)
                    .foregroundStyle(isIncluded ? Color.primary : Color.secondary)
            }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(
                    (isIncluded ? EvaluationDesign.accentSoft : Color.secondary.opacity(0.12)),
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .contextMenu {
            Button {
                membersPopoverGroupId = team.groupId
            } label: {
                Label("Ver integrantes", systemImage: "person.2")
            }
        }
        .popover(
            isPresented: Binding(
                get: { membersPopoverGroupId == team.groupId },
                set: { if !$0, membersPopoverGroupId == team.groupId { membersPopoverGroupId = nil } }
            )
        ) {
            membersPopover(team)
        }
        .help(SdaTournamentRoster.summary(of: team.members.map(\.fullName)))
        .accessibilityLabel(team.name)
        .accessibilityValue("\(isIncluded ? "Incluido" : "Fuera del torneo"). \(membersCountText(team))")
        .accessibilityHint(isIncluded ? "Toca para dejarlo fuera." : "Toca para incluirlo.")
        .accessibilityAction(named: "Ver integrantes") {
            membersPopoverGroupId = team.groupId
        }
    }

    private func membersCountText(_ team: TournamentWorkGroupTeam) -> String {
        switch team.members.count {
        case 0: return "Sin alumnos"
        case 1: return "1 alumno"
        default: return "\(team.members.count) alumnos"
        }
    }

    private func membersPopover(_ team: TournamentWorkGroupTeam) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(team.name)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if team.members.isEmpty {
                Text("Sin alumnos. Añádelos en el Cuaderno.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(team.members) { member in
                    Text(member.fullName)
                        .font(.subheadline)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 220, alignment: .leading)
        .presentationCompactAdaptation(.popover)
    }

    private var settingsSection: some View {
        Section("Partidos") {
            SdaStepperRow(title: "Pistas", value: $venueCount, range: 1...12, unit: "pistas")
            SdaStepperRow(title: "Minutos por partido", value: $matchMinutes, range: 1...90, unit: "minutos")
            SdaStepperRow(title: "Cambio entre partidos", value: $transitionMinutes, range: 0...15, unit: "minutos")
        }
    }

    private var summarySection: some View {
        Section("Resumen") {
            VStack(alignment: .leading, spacing: 4) {
                if selectedTeams.count < 2 {
                    Text("Elige al menos dos equipos.")
                        .foregroundStyle(.secondary)
                } else if let estimate {
                    Text("\(sdaPlural(selectedTeams.count, "equipo", "equipos")) · \(sdaPlural(estimate.matchCount, "partido", "partidos")) · \(sdaPlural(estimate.roundCount, "ronda", "rondas")) · **unos \(estimate.durationText)**")
                    fitLine(estimate)
                } else {
                    Text("Con estos ajustes no se puede crear el calendario. Cambia el formato o los equipos.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func fitLine(_ estimate: TournamentPlanEstimate) -> some View {
        if let sessionMinutes {
            if estimate.estimatedDurationMinutes <= sessionMinutes {
                Text("Cabe en una sesión de \(sessionMinutes) min.")
                    .foregroundStyle(IOSAppStyle.success)
            } else {
                Text("No cabe en una sesión de \(sessionMinutes) min. Prueba con más pistas o partidos más cortos.")
                    .foregroundStyle(IOSAppStyle.warning)
            }
        } else {
            Text("Este curso no tiene horario, así que no sé si cabe en una sesión.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Acciones

    private func loadSessionMinutes() async {
        sessionMinutes = nil
        let targetClass = classId
        guard let schedule = (try? await bridge.existingTeacherSchedule()) ?? nil,
              let slots = try? await bridge.plannerTeacherScheduleSlots(scheduleId: schedule.id),
              targetClass == classId
        else { return }
        sessionMinutes = sdaTypicalSessionMinutes(
            startEndTimes: slots
                .filter { $0.schoolClassId == targetClass }
                .map { (start: $0.startTime, end: $0.endTime) }
        )
    }

    private func create() async {
        guard canCreate else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let chosen = selectedTeams
            var plan = TournamentPlan(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                startDate: Date(),
                format: format,
                teams: SdaTournamentTeams.planTeams(from: chosen),
                groupCount: format == .groupStageKnockout ? resolvedGroupCount : 0,
                qualifiedTeamsPerGroup: format == .groupStageKnockout ? resolvedQualified : 2,
                venueCount: venueCount,
                matchDurationMinutes: matchMinutes,
                transitionMinutes: transitionMinutes
            )
            let rounds = try TournamentScheduleGenerator.generate(
                format: plan.format,
                teamNames: plan.teamNames,
                venueCount: plan.venueCount,
                groupCount: plan.format == .groupStageKnockout ? plan.groupCount : nil,
                qualifiedTeamsPerGroup: plan.qualifiedTeamsPerGroup
            )
            plan.persistSchedule(rounds)
            let tabIds = Set(chosen.map(\.tabId))
            let record = try TournamentRecord(
                plan: plan,
                learningSituationId: learningSituationId,
                classId: classId,
                tabId: tabIds.count == 1 ? tabIds.first : nil
            )
            let saved = try await bridge.saveTournament(record)
            onCreated(saved)
            dismiss()
        } catch {
            errorMessage = "No se pudo crear el torneo. Revisa los equipos e inténtalo de nuevo."
        }
    }
}

// MARK: - Resultado de un partido

/// Hoja para anotar o corregir el marcador de un partido.
struct SdaMatchScoreSheet: View {
    let home: String
    let away: String
    let venue: Int
    let requiresWinner: Bool
    let hasResult: Bool
    let onSave: (Int, Int) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var homeScore: Int
    @State private var awayScore: Int

    init(
        home: String,
        away: String,
        venue: Int,
        requiresWinner: Bool,
        initialScore: ScheduleMatchScore?,
        onSave: @escaping (Int, Int) -> Void,
        onClear: @escaping () -> Void
    ) {
        self.home = home
        self.away = away
        self.venue = venue
        self.requiresWinner = requiresWinner
        self.hasResult = initialScore != nil
        self.onSave = onSave
        self.onClear = onClear
        _homeScore = State(initialValue: initialScore?.homeScore ?? 0)
        _awayScore = State(initialValue: initialScore?.awayScore ?? 0)
    }

    private var isInvalidDraw: Bool {
        requiresWinner && homeScore == awayScore
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SdaStepperRow(title: home, value: $homeScore, range: 0...99, unit: "puntos")
                    SdaStepperRow(title: away, value: $awayScore, range: 0...99, unit: "puntos")
                } header: {
                    Text("Pista \(venue)")
                }
                if isInvalidDraw {
                    Section {
                        LearningSituationInlineNotice(
                            kind: .info,
                            message: "En eliminatoria no puede haber empate. Suma un punto a quien gane."
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    }
                }
                if hasResult {
                    Section {
                        Button("Borrar resultado", role: .destructive) {
                            onClear()
                            dismiss()
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
            .navigationTitle("Resultado")
            .appInlineNavigationBarTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(homeScore, awayScore)
                        dismiss()
                    }
                    .disabled(isInvalidDraw)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }
}
