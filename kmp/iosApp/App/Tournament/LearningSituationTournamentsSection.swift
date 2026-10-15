import SwiftUI
import MiGestorKit

/// Sección «Torneos» del detalle de la Situación de Aprendizaje: lista breve y «＋ Nuevo».
/// Los equipos son los grupos de trabajo vinculados a la situación. Tocar una fila abre el torneo
/// en la pantalla «Torneos» del menú lateral, donde se juega, se imprime y se borra.
struct LearningSituationTournamentsSection: View {
    let situationId: Int64
    /// Curso al que lleva «Crear grupos» (el primero vinculado o el seleccionado).
    let groupsClassId: Int64?
    let onOpenModule: (AppWorkspaceModule, Int64?, Int64?) -> Void

    @EnvironmentObject private var bridge: KmpBridge
    @StateObject private var model: SdaTournamentsListModel
    @State private var isCreating = false
    @State private var refreshTarget: SdaTournamentTarget?
    @State private var deleteTarget: SdaTournamentTarget?
    @ObservedObject private var navigation = SdaTournamentNavigationStore.shared
    @State private var errorMessage: String?
    @ScaledMetric(relativeTo: .body) private var tapSize: CGFloat = 44

    init(
        situationId: Int64,
        groupsClassId: Int64?,
        onOpenModule: @escaping (AppWorkspaceModule, Int64?, Int64?) -> Void
    ) {
        self.situationId = situationId
        self.groupsClassId = groupsClassId
        self.onOpenModule = onOpenModule
        _model = StateObject(wrappedValue: SdaTournamentsListModel(learningSituationId: situationId))
    }

    /// Un torneo es de un solo curso: hace falta algún curso con al menos dos grupos.
    /// Contar todos los grupos juntos engañaba cuando estaban repartidos en cursos distintos.
    private var hasPlayableClass: Bool {
        Dictionary(grouping: model.teams, by: \.classId).values.contains { $0.count >= 2 }
    }

    // MARK: Cuerpo

    var body: some View {
        LearningSituationCard(title: nil) {
            header
            switch model.phase {
            case .loading:
                LearningSituationSkeletonBlock(lines: 3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Cargando torneos")
            case .failed:
                LearningSituationInlineNotice(
                    kind: .error,
                    message: "No se pudieron cargar los torneos.",
                    actionTitle: "Reintentar"
                ) {
                    Task { await model.load(bridge: bridge) }
                }
            case .ready:
                readyContent
            }
            if let warning = navigation.saveWarning {
                LearningSituationInlineNotice(
                    kind: .error,
                    message: warning,
                    actionTitle: "Entendido"
                ) {
                    navigation.dismissSaveWarning()
                }
            }
            if let errorMessage {
                LearningSituationInlineNotice(kind: .error, message: errorMessage)
            }
        }
        .task { await model.load(bridge: bridge) }
        .sheet(isPresented: $isCreating) {
            SdaNewTournamentSheet(
                learningSituationId: situationId,
                teams: model.teams,
                suggestedName: "Torneo \(model.rows.count + 1)",
                preferredClassId: groupsClassId
            ) { created in
                model.upsert(created)
            }
            .environmentObject(bridge)
        }
        .confirmationDialog(
            "¿Borrar «\(deleteTarget.flatMap { model.record(id: $0.id)?.name } ?? "este torneo")»?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Borrar", role: .destructive) {
                if let target = deleteTarget { Task { await delete(target) } }
                deleteTarget = nil
            }
            Button("Cancelar", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Se borran el calendario y los resultados en todos tus dispositivos.")
        }
        .confirmationDialog(
            "¿Actualizar los equipos?",
            isPresented: Binding(
                get: { refreshTarget != nil },
                set: { if !$0 { refreshTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Actualizar y borrar resultados", role: .destructive) {
                if let target = refreshTarget { Task { await refresh(target) } }
                refreshTarget = nil
            }
            Button("Cancelar", role: .cancel) { refreshTarget = nil }
        } message: {
            Text("Se borran el calendario y los resultados, y se crea un calendario nuevo con los grupos de hoy.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Torneos")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if model.phase == .ready, !model.rows.isEmpty, hasPlayableClass {
                Button {
                    isCreating = true
                } label: {
                    Label("Nuevo", systemImage: "plus")
                        .frame(minHeight: tapSize)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Nuevo torneo")
            }
        }
        .frame(minHeight: tapSize - 8)
    }

    // MARK: Estados con datos

    @ViewBuilder
    private var readyContent: some View {
        if model.rows.isEmpty {
            if !hasPlayableClass {
                emptyWithoutGroups
            } else {
                emptyWithGroups
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider() }
                    rowView(row)
                        .padding(.vertical, 4)
                }
            }
        }
    }

    private var emptyWithoutGroups: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.3")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(model.teams.isEmpty ? "Primero, crea los grupos" : "Hace falta otro grupo")
                .font(.headline)
            Text(model.teams.isEmpty
                ? "Los equipos del torneo salen de los grupos de trabajo de esta situación."
                : model.teams.count >= 2
                    ? "Tus grupos están en cursos distintos y un torneo es de un solo curso. Crea otro grupo en el mismo curso que alguno de ellos."
                    : "Con un solo grupo no hay torneo. Crea al menos dos grupos de trabajo en esta situación.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                onOpenModule(.notebook, groupsClassId, nil)
            } label: {
                Text("Crear grupos")
                    .frame(minHeight: tapSize)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint("Abre el Cuaderno para crear los grupos de trabajo.")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var emptyWithGroups: some View {
        VStack(spacing: 8) {
            Image(systemName: "trophy")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Sin torneos todavía")
                .font(.headline)
            Text("Tienes \(sdaPlural(model.teams.count, "grupo listo", "grupos listos")) para jugar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                isCreating = true
            } label: {
                Text("Crear torneo")
                    .frame(minHeight: tapSize)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: Fila

    private func rowView(_ row: SdaTournamentRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                open(row)
            } label: {
                HStack(spacing: 8) {
                    Text(row.record.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let summary = row.summary {
                        SdaStatusBadge(status: summary.status)
                    } else {
                        Text("No se pudo leer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: tapSize, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Abre el torneo en la pantalla Torneos.")
            .contextMenu {
                Button(role: .destructive) {
                    deleteTarget = SdaTournamentTarget(id: row.id)
                } label: {
                    Label("Borrar…", systemImage: "trash")
                }
            }

            if row.groupsChanged {
                LearningSituationInlineNotice(
                    kind: .warning,
                    message: "Los grupos han cambiado desde que creaste este torneo.",
                    actionTitle: "Actualizar equipos"
                ) {
                    refreshTarget = SdaTournamentTarget(id: row.id)
                }
            }
        }
    }

    // MARK: Acciones

    private func delete(_ target: SdaTournamentTarget) async {
        errorMessage = nil
        do {
            try await bridge.deleteTournament(id: target.id)
            model.remove(id: target.id)
        } catch {
            errorMessage = "No se pudo borrar el torneo. Inténtalo de nuevo."
        }
    }

    /// Deja el torneo pedido y cambia al módulo Torneos, en el curso del torneo.
    private func open(_ row: SdaTournamentRow) {
        SdaTournamentNavigationStore.shared.request(tournamentId: row.id, classId: row.record.classId)
        onOpenModule(.peTournaments, row.record.classId, nil)
    }

    private func refresh(_ target: SdaTournamentTarget) async {
        errorMessage = nil
        guard let row = model.row(id: target.id), var plan = try? row.record.plan() else {
            errorMessage = "No se pudo leer el torneo."
            return
        }
        do {
            try plan.updateTeams(from: model.teams.filter { $0.classId == row.record.classId })
            let saved = try await bridge.saveTournament(try row.record.updating(with: plan))
            model.upsert(saved)
        } catch {
            errorMessage = "No se pudieron actualizar los equipos de «\(row.record.name)». Hacen falta al menos dos grupos."
        }
    }
}
