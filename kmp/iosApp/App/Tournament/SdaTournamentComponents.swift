import SwiftUI

// Piezas pequeñas compartidas por las pantallas de torneos de la SdA.

// MARK: - Estado

extension TournamentPlanStatus {
    var sdaTint: Color {
        switch self {
        case .draft: return .secondary
        case .scheduled: return EvaluationDesign.accent
        case .live: return IOSAppStyle.success
        case .finished: return .secondary
        }
    }
}

struct SdaStatusBadge: View {
    let status: TournamentPlanStatus

    var body: some View {
        Text(status.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.sdaTint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.sdaTint.opacity(0.14), in: Capsule())
            .accessibilityLabel("Estado: \(status.title)")
    }
}

// MARK: - Contador con menos y más

/// Fila «título + − valor +» con botones de 44 pt. Para VoiceOver es un único control ajustable.
struct SdaStepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var unit: String = ""
    @ScaledMetric(relativeTo: .body) private var tapSize: CGFloat = 44

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                titleText
                controls
            }
            VStack(alignment: .leading, spacing: 8) {
                titleText
                controls
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(unit.isEmpty ? "\(value)" : "\(value) \(unit)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: change(by: 1)
            case .decrement: change(by: -1)
            @unknown default: break
            }
        }
    }

    private var titleText: some View {
        Text(title)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button { change(by: -1) } label: {
                Image(systemName: "minus")
                    .frame(minWidth: tapSize - 16, minHeight: tapSize - 16)
            }
            .disabled(value <= range.lowerBound)
            Text("\(value)")
                .font(.body.weight(.semibold).monospacedDigit())
                .frame(minWidth: 32)
            Button { change(by: 1) } label: {
                Image(systemName: "plus")
                    .frame(minWidth: tapSize - 16, minHeight: tapSize - 16)
            }
            .disabled(value >= range.upperBound)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func change(by delta: Int) {
        value = min(max(value + delta, range.lowerBound), range.upperBound)
    }
}

// MARK: - Partido

/// Partido en calendario y cuadro: pista, equipos y marcador. Toda la fila es un botón.
struct SdaMatchRow: View {
    let venue: Int
    let home: String
    let away: String
    let score: ScheduleMatchScore?
    let isEnabled: Bool
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var tapSize: CGFloat = 44

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pista \(venue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .center, spacing: 8) {
                    Text(home)
                        .fontWeight(score?.winningSide == .home ? .bold : .regular)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(score?.scoreText ?? "vs")
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(score == nil ? .secondary : .primary)
                        .layoutPriority(1)
                        .frame(minWidth: 56)
                    Text(away)
                        .fontWeight(score?.winningSide == .away ? .bold : .regular)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: tapSize, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(isEnabled ? "Toca para registrar o cambiar el resultado." : "Aún no se conocen los dos equipos.")
    }

    private var accessibilityText: String {
        var text = "Pista \(venue). \(home) contra \(away)."
        if let score {
            text += " Resultado: \(score.homeScore) a \(score.awayScore)."
        } else {
            text += " Sin resultado."
        }
        return text
    }
}

// MARK: - Clasificación

struct SdaStandingsTable: View {
    let standings: [Standing]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            wideTable
            compactList
        }
    }

    private var wideTable: some View {
        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 0) {
            GridRow {
                Text("#").gridColumnAlignment(.leading)
                Text("Equipo").gridColumnAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                Text("PJ")
                Text("V")
                Text("E")
                Text("D")
                Text("Pts")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
            ForEach(Array(standings.enumerated()), id: \.element.id) { index, standing in
                Divider()
                GridRow {
                    Text("\(index + 1)").gridColumnAlignment(.leading)
                    Text(standing.teamName)
                        .fontWeight(index == 0 && standing.played > 0 ? .bold : .regular)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(standing.played)")
                    Text("\(standing.wins)")
                    Text("\(standing.draws)")
                    Text("\(standing.losses)")
                    Text("\(standing.points)").fontWeight(.bold)
                }
                .font(.body.monospacedDigit())
                .frame(minHeight: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(standing, position: index + 1))
            }
        }
    }

    private var compactList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(standings.enumerated()), id: \.element.id) { index, standing in
                if index > 0 { Divider() }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(index + 1). \(standing.teamName)")
                        .fontWeight(.semibold)
                    Text("\(standing.points) pts · PJ \(standing.played) · V \(standing.wins) · E \(standing.draws) · D \(standing.losses)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.vertical, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(standing, position: index + 1))
            }
        }
    }

    private func spoken(_ standing: Standing, position: Int) -> String {
        "Puesto \(position), \(standing.teamName). \(standing.points) puntos. "
            + "\(standing.played) jugados, \(standing.wins) ganados, \(standing.draws) empatados, \(standing.losses) perdidos."
    }
}
