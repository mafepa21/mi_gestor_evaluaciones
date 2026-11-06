import SwiftUI

// Piezas de la modalidad «Liguilla + puestos». La lógica vive en `PlacementTournament.swift`.

// MARK: - Plan: tú decides, la app calcula

/// Secciones de formulario: parejas, minutos y tiempo total, con el resultado del cálculo
/// y, si no cabe, cambios que se aplican con un toque.
struct SdaPlacementPlanSections: View {
    /// Parejas que se pueden cambiar (torneo con inscripción aún sin respuestas).
    /// Si es `nil`, las parejas son las que hay y solo se enseñan.
    var editableTeamCount: Binding<Int>?
    var fixedTeamCount: Int = 0
    @Binding var matchMinutes: Int
    @Binding var totalMinutes: Int
    @Binding var venueCount: Int
    @Binding var transitionMinutes: Int
    @Binding var placementRounds: Int?

    private var teamCount: Int { editableTeamCount?.wrappedValue ?? fixedTeamCount }

    private var input: PlacementPlanInput {
        PlacementPlanInput(
            teamCount: teamCount,
            matchMinutes: matchMinutes,
            transitionMinutes: transitionMinutes,
            totalMinutes: totalMinutes,
            venueCount: venueCount,
            placementRounds: placementRounds
        )
    }

    var body: some View {
        let calculation = PlacementPlanner.calculate(input)
        Section {
            if let editableTeamCount {
                SdaStepperRow(title: "Parejas previstas", value: editableTeamCount, range: 4...60, unit: "parejas")
            } else {
                LabeledContent("Parejas", value: "\(fixedTeamCount)")
                    .frame(minHeight: 44)
            }
            SdaStepperRow(title: "Minutos por partido", value: $matchMinutes, range: 1...90, unit: "minutos")
            SdaStepperRow(title: "Tiempo total", value: $totalMinutes, range: 10...max(600, totalMinutes), unit: "minutos", step: 5)
            DisclosureGroup("Más ajustes") {
                SdaStepperRow(title: "Pistas", value: $venueCount, range: 1...12, unit: "pistas")
                SdaStepperRow(title: "Cambio entre partidos", value: $transitionMinutes, range: 0...15, unit: "minutos")
                if let calculation {
                    SdaStepperRow(
                        title: "Rondas del cuadro",
                        value: Binding(
                            get: { calculation.placementRoundsUsed },
                            set: { placementRounds = $0 >= calculation.placementRoundsAvailable ? nil : $0 }
                        ),
                        range: 1...max(calculation.placementRoundsAvailable, 1),
                        unit: "rondas"
                    )
                }
            }
            .frame(minHeight: 44)
        } header: {
            Text("Tú decides")
        }

        if let calculation {
            resultSection(calculation)
            suggestionsSection(calculation)
        } else {
            Section {
                Text("Hacen falta al menos \(PlacementPlanInput.minimumTeams) parejas.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func resultSection(_ calculation: PlacementPlanCalculation) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(calculation.fits ? "Da tiempo" : "No da tiempo")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(calculation.fits ? IOSAppStyle.success : IOSAppStyle.warning)
                Text(subtitle(calculation))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            LabeledContent("Liguilla", value: leagueText(calculation))
            LabeledContent("Cuadro de puestos", value: placementText(calculation))
            if calculation.restingPerRound > 0 {
                Label(
                    calculation.restingPerRound == 1
                        ? "Descansa 1 pareja en cada tanda de liguilla, por turnos."
                        : "Descansan \(calculation.restingPerRound) parejas en cada tanda de liguilla, por turnos.",
                    systemImage: "pause.circle"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            if calculation.activeVenues < venueCount {
                Label(
                    "Con \(teamCount) parejas se usan \(calculation.activeVenues) de las \(venueCount) pistas.",
                    systemImage: "info.circle"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Resultado")
        }
    }

    @ViewBuilder
    private func suggestionsSection(_ calculation: PlacementPlanCalculation) -> some View {
        let suggestions = PlacementPlanner.suggestions(for: input)
        if !suggestions.isEmpty {
            Section {
                ForEach(suggestions) { suggestion in
                    Button {
                        apply(suggestion.change)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .fontWeight(.semibold)
                            Text(suggestion.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Aplica este cambio.")
                }
            } header: {
                Text("Puedes cambiar")
            }
        }
    }

    private func apply(_ change: PlacementPlanChange) {
        switch change {
        case .totalMinutes(let value): totalMinutes = value
        case .matchMinutes(let value): matchMinutes = value
        case .placementRounds(let value): placementRounds = value
        case .venueCount(let value): venueCount = value
        }
    }

    private func subtitle(_ calculation: PlacementPlanCalculation) -> String {
        let needed = PlacementPlanner.durationText(calculation.neededMinutes)
        let total = PlacementPlanner.durationText(totalMinutes)
        guard calculation.fits else {
            return "Hacen falta al menos \(needed) y tienes \(total)."
        }
        let spare = totalMinutes - calculation.neededMinutes
        return spare > 0 ? "Se usan \(needed) de \(total). Sobran \(spare) min." : "Se usa todo el tiempo: \(total)."
    }

    private func leagueText(_ calculation: PlacementPlanCalculation) -> String {
        guard calculation.fits else {
            return "Mínimo \(sdaPlural(calculation.minimumLeagueRounds, "tanda", "tandas")) para que todas jueguen \(PlacementPlanInput.minimumLeagueMatchesPerTeam) partidos"
        }
        let range = calculation.leagueMatchesPerTeam
        let perTeam = range.lowerBound == range.upperBound ? "\(range.lowerBound)" : "\(range.lowerBound) o \(range.upperBound)"
        return "\(sdaPlural(calculation.leagueRounds, "tanda", "tandas")) · \(sdaPlural(calculation.leagueMatches, "partido", "partidos")) · \(perTeam) por pareja"
    }

    private func placementText(_ calculation: PlacementPlanCalculation) -> String {
        "\(sdaPlural(calculation.placementBatches, "tanda", "tandas")) · \(sdaPlural(calculation.placementMatches, "partido", "partidos")) · \(calculation.placementBatches * calculation.roundMinutes) min"
    }
}

// MARK: - Pasar al cuadro

/// Botón para abrir el cuadro con partidos de liguilla sin jugar. Pide confirmación porque no cuentan.
struct SdaCloseLeagueButton: View {
    @ObservedObject var store: SdaTournamentStore
    @State private var isConfirming = false

    var body: some View {
        let pending = store.plan.pendingLeagueMatchCount
        Button {
            isConfirming = true
        } label: {
            Label("Pasar al cuadro de puestos", systemImage: "arrow.right.circle")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .disabled(store.plan.savedResults.isEmpty)
        .confirmationDialog(
            "¿Pasar al cuadro de puestos?",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("Pasar y descartar \(sdaPlural(pending, "partido", "partidos"))", role: .destructive) {
                store.mutate { $0.closeLeagueEarly() }
            }
            Button("Seguir la liguilla", role: .cancel) {}
        } message: {
            Text("Los partidos sin jugar no contarán. El orden se calcula con los jugados, por porcentaje de victorias.")
        }
    }
}

// MARK: - Clasificación de la liguilla

struct SdaPlacementLeagueTable: View {
    let rows: [PlacementStandingRow]

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 0) {
            GridRow {
                Text("#").gridColumnAlignment(.leading)
                Text("Pareja").gridColumnAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                Text("PJ")
                Text("V")
                Text("E")
                Text("D")
                Text("Dif.")
                Text("%")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                Divider()
                GridRow {
                    Text("\(index + 1)").gridColumnAlignment(.leading)
                    Text(row.teamName)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(row.played)")
                    Text("\(row.wins)")
                    Text("\(row.draws)")
                    Text("\(row.losses)")
                    Text(row.pointDifference > 0 ? "+\(row.pointDifference)" : "\(row.pointDifference)")
                    Text("\(Int((row.winRate * 100).rounded()))").fontWeight(.bold)
                }
                .font(.body.monospacedDigit())
                .frame(minHeight: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "Puesto \(index + 1), \(row.teamName). \(sdaPlural(row.played, "partido", "partidos")), \(sdaPlural(row.wins, "victoria", "victorias")), \(Int((row.winRate * 100).rounded())) por ciento."
                )
            }
        }
    }
}

// MARK: - Tabla final

struct SdaPlacementFinalTable: View {
    let rows: [PlacementFinalRow]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 32, alignment: .top)], alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                VStack(spacing: 0) {
                    Divider()
                    HStack(spacing: 12) {
                        Text("\(row.position)º")
                            .font(.body.weight(.bold).monospacedDigit())
                            .foregroundStyle(row.position <= 3 ? EvaluationDesign.accent : Color.primary)
                            .frame(minWidth: 36, alignment: .leading)
                        Text(row.teamName)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Liguilla \(row.leaguePosition)º")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Puesto \(row.position), \(row.teamName). En la liguilla acabó \(row.leaguePosition).")
            }
        }
    }
}
