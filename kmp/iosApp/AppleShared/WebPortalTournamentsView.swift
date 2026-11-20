import SwiftUI

/// Pestaña «Torneos» del portal del alumnado (maqueta fase 3B, estados A1 a A4).
///
/// Solo el Mac cambia los interruptores (como «Notas visibles»): en iPad se ven desactivados
/// con el aviso A4. Encender un torneo se publica solo 2 minutos después; apagarlo o cambiar
/// «Nombres equipo» actualiza/retira al momento.

// MARK: - Modelo

@MainActor
final class WebPortalTournamentsViewModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, loaded }

    enum PendingConfirmation: Identifiable, Equatable {
        case showTournament(WebPortalTournamentRow)
        case showNames(WebPortalTournamentRow)

        var id: String {
            switch self {
            case .showTournament(let row): return "show-\(row.id)"
            case .showNames(let row): return "names-\(row.id)"
            }
        }
    }

    @Published private(set) var overview: WebPortalTournamentOverview?
    @Published private(set) var settings = WebPortalGroupTournamentSettings()
    @Published private(set) var phase: Phase = .idle
    @Published var pendingConfirmation: PendingConfirmation?
    @Published private(set) var saveError: String?

    let settingsURL: URL
    let canEdit: Bool
    private let loadOverview: (Int64) async -> WebPortalTournamentOverview?
    private let changed: (Int64, Bool) -> Void
    private(set) var classId: Int64 = 0

    init(
        settingsURL: URL,
        canEdit: Bool = WebPortalGradesViewModel.platformCanEdit,
        loadOverview: @escaping (Int64) async -> WebPortalTournamentOverview?,
        changed: @escaping (Int64, Bool) -> Void
    ) {
        self.settingsURL = settingsURL
        self.canEdit = canEdit
        self.loadOverview = loadOverview
        self.changed = changed
    }

    func load(classId: Int64) async {
        self.classId = classId
        pendingConfirmation = nil
        saveError = nil
        settings = WebPortalTournamentSettings.load(fileURL: settingsURL)[classId]
        phase = .loading
        let loaded = await loadOverview(classId)
        guard self.classId == classId else { return }
        overview = loaded
        phase = .loaded
    }

    var tournaments: [WebPortalTournamentRow] { overview?.tournaments ?? [] }

    func isVisible(_ row: WebPortalTournamentRow) -> Bool { settings.isVisible(tournamentId: row.id) }
    func showsNames(_ row: WebPortalTournamentRow) -> Bool { settings.showsNames(tournamentId: row.id) }

    /// Apagar es inmediato. Encender por primera vez pide confirmación.
    func requestVisible(_ row: WebPortalTournamentRow, on: Bool) {
        guard canEdit else { return }
        if on, settings.needsConfirmation(tournamentId: row.id) {
            pendingConfirmation = .showTournament(row)
            return
        }
        applyVisible(row.id, on: on)
    }

    /// Activar nombres de equipo por primera vez pide confirmación explícita (A2).
    func requestShowNames(_ row: WebPortalTournamentRow, on: Bool) {
        guard canEdit, isVisible(row) else { return }
        if on, settings.needsNamesConfirmation(tournamentId: row.id) {
            pendingConfirmation = .showNames(row)
            return
        }
        applyShowNames(row.id, on: on)
    }

    func confirmPending() {
        guard let pending = pendingConfirmation else { return }
        pendingConfirmation = nil
        switch pending {
        case .showTournament(let row):
            applyVisible(row.id, on: true, confirm: true)
        case .showNames(let row):
            applyShowNames(row.id, on: true, confirm: true)
        }
    }

    func cancelPending() { pendingConfirmation = nil }

    private func applyVisible(_ tournamentId: String, on: Bool, confirm: Bool = false) {
        apply(immediately: !on) {
            var item = $0.torneos[tournamentId] ?? WebPortalTournamentVisibility()
            item.visible = on
            if !on { item.mostrarNombres = false }
            $0.torneos[tournamentId] = item
            if confirm, !$0.confirmados.contains(tournamentId) { $0.confirmados.append(tournamentId) }
        }
    }

    private func applyShowNames(_ tournamentId: String, on: Bool, confirm: Bool = false) {
        // Cambiar nombres siempre se aplica al momento (p. ej. si el docente corrige un apellido).
        apply(immediately: true) {
            var item = $0.torneos[tournamentId] ?? WebPortalTournamentVisibility(visible: true, mostrarNombres: on)
            item.mostrarNombres = on
            $0.torneos[tournamentId] = item
            if confirm, !$0.nombresConfirmados.contains(tournamentId) { $0.nombresConfirmados.append(tournamentId) }
        }
    }

    private func apply(immediately: Bool, _ change: @escaping (inout WebPortalGroupTournamentSettings) -> Void) {
        let classId = self.classId
        do {
            let saved = try WebPortalTournamentSettings.mutate(fileURL: settingsURL) { change(&$0[classId]) }
            settings = saved[classId]
            saveError = nil
            changed(classId, immediately)
        } catch {
            saveError = "No se pudo guardar el ajuste: \(error.localizedDescription)"
        }
    }
}

// MARK: - Vista

struct WebPortalTournamentsPane: View {
    @ObservedObject var model: WebPortalTournamentsViewModel
    @ObservedObject var watcher: WebPortalTournamentsWatcher
    let classId: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.canEdit {
                // A4
                Label("Los torneos visibles se activan desde el Mac. Los marcadores que anotes aquí en Modo directo suben solos al portal cuando lleguen al Mac por sincronización.", systemImage: "info.circle")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
            if let error = model.saveError {
                banner(error, symbol: "exclamationmark.triangle.fill")
            }
            if watcher.tooLargeClassIds.contains(classId) {
                banner("Demasiado grande: el tablón de algún alumno pasa del límite y no se publica. Oculta algún torneo o nota.", symbol: "exclamationmark.octagon.fill")
            }
            if watcher.failedClassIds.contains(classId) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("No se pudo publicar. Se reintentará solo cuando vuelva la conexión.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Reintentar") { watcher.retryNow(classId: classId) }
                }
                .padding(12)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            if model.phase != .loaded {
                ProgressView().controlSize(.small)
            } else if model.tournaments.isEmpty {
                // A3
                ContentUnavailableView {
                    Label("Este grupo no tiene torneos", systemImage: "trophy")
                } description: {
                    Text("Cuando crees un torneo para este curso en Situaciones de aprendizaje o en Torneos, podrás elegir aquí si el alumnado ve su progreso en el portal.")
                }
            } else {
                tournamentsList
            }
        }
    }

    private func banner(_ text: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.orange)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var tournamentsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Torneos del grupo").frame(maxWidth: .infinity, alignment: .leading)
                Text("Estado").frame(width: 90, alignment: .leading)
                Text("Nombres equipo").frame(width: 120, alignment: .trailing)
                Text("Mostrar").frame(width: 86, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 6)
            ForEach(model.tournaments) { row in
                Divider()
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name).font(.body)
                        Text(row.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    statusBadge(row.status)
                        .frame(width: 90, alignment: .leading)
                    switchView(
                        label: "Mostrar nombres de equipo en \(row.name)",
                        isOn: Binding(get: { model.showsNames(row) }, set: { model.requestShowNames(row, on: $0) }),
                        enabled: model.isVisible(row),
                        onText: "Sí",
                        offText: "Equipo N"
                    )
                    .frame(width: 120, alignment: .trailing)
                    switchView(
                        label: "Mostrar \(row.name) en el portal",
                        isOn: Binding(get: { model.isVisible(row) }, set: { model.requestVisible(row, on: $0) }),
                        enabled: true,
                        onText: "Sí",
                        offText: "No"
                    )
                    .frame(width: 86, alignment: .trailing)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func statusBadge(_ status: TournamentPlanStatus) -> some View {
        let color: Color
        switch status {
        case .live: color = .green
        case .finished: color = .orange
        case .scheduled, .draft: color = .secondary
        }
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(status.title).font(.caption.weight(.medium)).foregroundStyle(color)
        }
    }

    private func switchView(label: String, isOn: Binding<Bool>, enabled: Bool, onText: String, offText: String) -> some View {
        HStack(spacing: 6) {
            Toggle(label, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!model.canEdit || !enabled)
            Text(isOn.wrappedValue ? onText : offText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 24, alignment: .leading)
        }
    }
}

/// Pie de la pestaña Torneos.
struct WebPortalTournamentsFooter: View {
    @ObservedObject var watcher: WebPortalTournamentsWatcher
    let classId: Int64

    var body: some View {
        Group {
            if watcher.failedClassIds.contains(classId) {
                if let last = watcher.lastPublished[classId] {
                    Text("Último publicado: \(last.formatted(.relative(presentation: .named)))")
                } else {
                    Text("Aún no se ha publicado nada")
                }
            } else if let due = watcher.dueDates[classId] {
                Text("Los resultados se publican solos 2 minutos después · próxima publicación hacia las \(due.formatted(date: .omitted, time: .shortened))")
            } else {
                Text("Los resultados se publican solos 2 minutos después · apagar retira al momento")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
