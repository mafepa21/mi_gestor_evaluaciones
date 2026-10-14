import SwiftUI
import MiGestorKit

// Estado de las pantallas de torneos de la Situación de Aprendizaje.
// - `SdaTournamentsListModel`: lo que ve la sección dentro del detalle de la SdA.
// - `SdaTournamentStore`: un torneo abierto; cada cambio se guarda al momento.

/// Fila de la sección: registro más el resumen ya calculado (no se decodifica en cada pintado).
struct SdaTournamentRow: Identifiable, Equatable {
    var record: TournamentRecord
    /// `nil` si el JSON guardado no se puede leer.
    var summary: Summary?
    var groupsChanged: Bool

    struct Summary: Equatable {
        var format: TournamentFormat
        var status: TournamentPlanStatus
        var teamCount: Int
        var venueCount: Int
        var snapshot: [TournamentPlanTeam]
    }

    var id: String { record.id }
}

@MainActor
final class SdaTournamentsListModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case failed
        case ready
    }

    let learningSituationId: Int64
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var teams: [TournamentWorkGroupTeam] = []
    @Published private(set) var rows: [SdaTournamentRow] = []

    init(learningSituationId: Int64) {
        self.learningSituationId = learningSituationId
    }

    /// Lee grupos y torneos. Si ya había datos, los mantiene mientras recarga (sin esqueleto).
    func load(bridge: KmpBridge) async {
        if phase != .ready { phase = .loading }
        do {
            let loadedTeams = try await bridge.workGroupsLinkedToLearningSituation(learningSituationId: learningSituationId)
            let records = try await bridge.tournaments(forLearningSituationId: learningSituationId)
            teams = loadedTeams
            rows = records.map { Self.makeRow($0, teams: loadedTeams) }
            phase = .ready
        } catch {
            if phase != .ready { phase = .failed }
        }
    }

    func record(id: String) -> TournamentRecord? {
        rows.first(where: { $0.id == id })?.record
    }

    func row(id: String) -> SdaTournamentRow? {
        rows.first(where: { $0.id == id })
    }

    func upsert(_ record: TournamentRecord) {
        let row = Self.makeRow(record, teams: teams)
        if let index = rows.firstIndex(where: { $0.id == record.id }) {
            rows[index] = row
        } else {
            rows.append(row)
        }
    }

    func remove(id: String) {
        rows.removeAll { $0.id == id }
    }

    private static func makeRow(_ record: TournamentRecord, teams: [TournamentWorkGroupTeam]) -> SdaTournamentRow {
        guard let plan = try? record.plan() else {
            return SdaTournamentRow(record: record, summary: nil, groupsChanged: false)
        }
        // Solo se compara con los grupos del mismo curso del torneo.
        let classTeams = teams.filter { $0.classId == record.classId }
        let changed = SdaTournamentTeams.hasChanged(snapshot: plan.teams, current: classTeams)
        return SdaTournamentRow(
            record: record,
            summary: SdaTournamentRow.Summary(
                format: plan.format,
                status: plan.status,
                teamCount: plan.teamCount,
                venueCount: plan.venueCount,
                snapshot: plan.teams
            ),
            groupsChanged: changed
        )
    }
}

/// Un torneo abierto. Los cambios se aplican al instante en pantalla y se guardan en segundo
/// plano de uno en uno: si llegan varios seguidos (+/− en directo) se guarda el último estado.
@MainActor
final class SdaTournamentStore: ObservableObject {
    @Published private(set) var plan: TournamentPlan
    @Published private(set) var record: TournamentRecord
    @Published private(set) var saveFailed = false

    private let bridge: KmpBridge
    private var isDirty = false
    private(set) var isDeleted = false
    private var saveTask: Task<Void, Never>?
    /// Se llama tras cada guardado correcto (para refrescar la lista de la SdA).
    var onSaved: ((TournamentRecord) -> Void)?

    init(record: TournamentRecord, plan: TournamentPlan, bridge: KmpBridge) {
        self.record = record
        self.plan = plan
        self.bridge = bridge
    }

    func mutate(_ change: (inout TournamentPlan) -> Void) {
        guard !isDeleted else { return }
        var copy = plan
        change(&copy)
        guard copy != plan else { return }
        plan = copy
        isDirty = true
        startSaving()
    }

    func mutateThrowing(_ change: (inout TournamentPlan) throws -> Void) throws {
        guard !isDeleted else { return }
        var copy = plan
        try change(&copy)
        guard copy != plan else { return }
        plan = copy
        isDirty = true
        startSaving()
    }

    func retrySave() {
        isDirty = true
        startSaving()
    }

    /// Espera a que termine el guardado en curso (al cerrar o antes de borrar).
    func flush() async {
        startSaving()
        await saveTask?.value
    }

    /// Borra el torneo. Antes termina cualquier guardado para que no lo resucite.
    func delete() async throws {
        await flush()
        isDirty = false
        try await bridge.deleteTournament(id: record.id)
        isDeleted = true
        saveFailed = false
    }

    private func startSaving() {
        guard saveTask == nil, isDirty, !isDeleted else { return }
        saveTask = Task { [weak self] in
            await self?.saveLoop()
        }
    }

    private func saveLoop() async {
        while isDirty, !isDeleted {
            isDirty = false
            do {
                let toSave = try record.updating(with: plan)
                let saved = try await bridge.saveTournament(toSave)
                record = saved
                saveFailed = false
                onSaved?(saved)
            } catch {
                isDirty = true
                saveFailed = true
                break
            }
        }
        saveTask = nil
    }
}

/// Destino de una hoja: id estable para `.sheet(item:)`.
struct SdaTournamentTarget: Identifiable, Hashable {
    let id: String
}
