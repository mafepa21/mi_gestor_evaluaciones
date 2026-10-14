//
//  PETournamentsWorkspaceView.swift
//  MiGestorKMP
//
//  Sustituto provisional del módulo antiguo de torneos de EF. Los torneos ahora viven en cada
//  Situación de Aprendizaje; aquí se listan los del curso elegido y los migrados (sin SdA) se
//  abren en el mismo detalle de la SdA: anotar resultados, modo directo y borrar.
//  La pantalla definitiva se diseñará con maqueta aprobada.
//

import SwiftUI

struct PETournamentsWorkspaceView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Binding var selectedClassId: Int64?

    @State private var tournaments: [TournamentRecord] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var openTarget: SdaTournamentTarget?
    @State private var closeWarning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Los torneos ahora viven en cada Situación de Aprendizaje")
                    .font(.headline)
                Text("Los torneos antiguos se han copiado aquí y pertenecen solo al curso.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: selectedClassId) {
            closeWarning = nil
            await reload()
        }
        .sheet(item: $openTarget) { target in
            let record = tournaments.first(where: { $0.id == target.id })
            SdaTournamentSheetHost(
                record: record,
                currentTeams: [],
                className: bridge.classes.first(where: { $0.id == record?.classId })?.name ?? "Curso",
                onSaved: { saved in
                    if let index = tournaments.firstIndex(where: { $0.id == saved.id }) {
                        tournaments[index] = saved
                    }
                },
                onDeleted: { tournaments.removeAll { $0.id == target.id } },
                onSaveFailedAtClose: { name in
                    closeWarning = "No se guardaron los últimos cambios de «\(name)». Ábrelo de nuevo y revisa los resultados."
                }
            )
            .environmentObject(bridge)
        }
    }

    @ViewBuilder
    private var content: some View {
        if selectedClassId == nil {
            WorkspaceEmptyState(
                title: "Elige un curso",
                subtitle: "Selecciona un curso para ver sus torneos.",
                systemImage: "trophy"
            )
        } else if let loadError {
            WorkspaceEmptyState(
                title: "No se pudieron cargar los torneos",
                subtitle: loadError,
                systemImage: "exclamationmark.triangle"
            )
        } else if tournaments.isEmpty {
            WorkspaceEmptyState(
                title: isLoading ? "Cargando torneos" : "Este curso no tiene torneos",
                subtitle: "Crea los torneos nuevos desde la Situación de Aprendizaje.",
                systemImage: "trophy"
            )
        } else {
            VStack(spacing: 0) {
                if let closeWarning {
                    LearningSituationInlineNotice(kind: .error, message: closeWarning)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }
                List(tournaments) { tournament in
                    Button {
                        openTarget = SdaTournamentTarget(id: tournament.id)
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tournament.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(summary(of: tournament))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Abre el torneo.")
                }
                .listStyle(.plain)
            }
        }
    }

    private func summary(of tournament: TournamentRecord) -> String {
        let format = TournamentFormat(rawValue: tournament.format)?.title ?? tournament.format
        let status = TournamentPlanStatus(rawValue: tournament.status)?.title ?? tournament.status
        let origin = tournament.learningSituationId == nil ? "Solo del curso" : "De una Situación de Aprendizaje"
        return "\(format) · \(status) · \(origin)"
    }

    private func reload() async {
        guard let classId = selectedClassId else {
            tournaments = []
            loadError = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            tournaments = try await bridge.tournaments(forClassId: classId)
            loadError = nil
        } catch {
            tournaments = []
            loadError = error.localizedDescription
        }
    }
}
