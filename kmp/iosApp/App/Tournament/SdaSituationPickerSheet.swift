import SwiftUI
import MiGestorKit

/// Situación elegida para crear un torneo, con los grupos de trabajo que serán los equipos.
struct SdaNewTournamentTarget: Identifiable, Equatable {
    let choice: SdaSituationChoice
    let teams: [TournamentWorkGroupTeam]

    var id: Int64 { choice.id }

    static func == (lhs: SdaNewTournamentTarget, rhs: SdaNewTournamentTarget) -> Bool {
        lhs.choice == rhs.choice && lhs.teams.map(\.groupId) == rhs.teams.map(\.groupId)
    }
}

/// Primer paso de «＋ Nuevo»: ¿de qué situación salen los equipos? Después sigue la hoja
/// «Nuevo torneo» de siempre. Las situaciones sin dos grupos en el curso salen deshabilitadas.
struct SdaSituationPickerSheet: View {
    let classId: Int64
    let className: String
    let onPick: (SdaNewTournamentTarget) -> Void
    let onOpenSituations: () -> Void

    @EnvironmentObject private var bridge: KmpBridge
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var tapSize: CGFloat = 44

    private enum Phase {
        case loading, failed, ready
    }

    @State private var phase: Phase = .loading
    @State private var choices: [SdaSituationChoice] = []
    @State private var teams: [Int64: [TournamentWorkGroupTeam]] = [:]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Nuevo torneo")
                .appInlineNavigationBarTitleDisplayMode()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { dismiss() }
                    }
                }
        }
        .task { await load() }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            LearningSituationSkeletonBlock(lines: 4)
                .padding(24)
                .frame(maxHeight: .infinity, alignment: .top)
                .accessibilityHidden(true)
        case .failed:
            LearningSituationInlineNotice(
                kind: .error,
                message: "No se pudieron cargar las situaciones.",
                actionTitle: "Reintentar"
            ) {
                Task { await load() }
            }
            .padding(16)
            .frame(maxHeight: .infinity, alignment: .top)
        case .ready:
            if choices.isEmpty {
                WorkspaceEmptyState(
                    title: "Sin situaciones en \(className)",
                    subtitle: "Los equipos salen de los grupos de una situación. Vincula una situación a este curso.",
                    systemImage: "doc.text.magnifyingglass",
                    actionTitle: "Abrir Situaciones"
                ) {
                    dismiss()
                    onOpenSituations()
                }
            } else {
                List {
                    Section {
                        ForEach(choices) { choice in
                            choiceRow(choice)
                        }
                    } header: {
                        Text("¿De qué situación salen los equipos?")
                            .textCase(nil)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    } footer: {
                        Text("Luego sigue la hoja «Nuevo torneo» de siempre.")
                    }
                }
            }
        }
    }

    private func choiceRow(_ choice: SdaSituationChoice) -> some View {
        Button {
            onPick(SdaNewTournamentTarget(choice: choice, teams: teams[choice.id] ?? []))
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Text(choice.title)
                    .foregroundStyle(choice.isAvailable ? Color.primary : Color.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(choice.detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if choice.isAvailable {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: tapSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!choice.isAvailable)
        .accessibilityElement(children: .combine)
        .accessibilityHint(choice.isAvailable ? "Sigue con los datos del torneo." : "Hacen falta al menos dos grupos de trabajo en este curso.")
    }

    private func load() async {
        phase = .loading
        do {
            let result = try await SdaTournamentsHubModel.loadChoices(bridge: bridge, classId: classId)
            choices = result.choices
            teams = result.teams
            phase = .ready
        } catch {
            phase = .failed
        }
    }
}
