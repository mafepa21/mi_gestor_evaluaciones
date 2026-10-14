//
//  PETournamentsWorkspaceView.swift
//  MiGestorKMP
//
//  Sustituto provisional del módulo antiguo de torneos de EF. Los torneos ahora viven en cada
//  Situación de Aprendizaje; aquí solo se listan, en solo lectura, los del curso elegido.
//  La pantalla definitiva se diseñará con maqueta aprobada.
//

import SwiftUI

struct PETournamentsWorkspaceView: View {
    @EnvironmentObject var bridge: KmpBridge
    @Binding var selectedClassId: Int64?

    @State private var tournaments: [TournamentRecord] = []
    @State private var isLoading = false
    @State private var loadError: String?

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
        .task(id: selectedClassId) { await reload() }
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
            List(tournaments) { tournament in
                VStack(alignment: .leading, spacing: 2) {
                    Text(tournament.name)
                        .font(.body.weight(.semibold))
                    Text(summary(of: tournament))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .listStyle(.plain)
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
