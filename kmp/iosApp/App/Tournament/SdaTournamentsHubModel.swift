import SwiftUI
import MiGestorKit

/// Estado de la pantalla «Torneos»: torneos del curso elegido, títulos de sus situaciones y los
/// grupos actuales de cada situación (para avisar de grupos cambiados y actualizar equipos).
@MainActor
final class SdaTournamentsHubModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case failed
        case ready
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var records: [TournamentRecord] = []
    @Published private(set) var situations: [(id: Int64, title: String)] = []
    @Published private(set) var teamsBySituation: [Int64: [TournamentWorkGroupTeam]] = [:]
    /// Curso al que corresponden `records` (evita aplicar una petición con datos de otro curso).
    @Published private(set) var loadedClassId: Int64?

    var sections: [SdaTournamentListSection] {
        SdaTournamentsOverview.sections(records: records, situations: situations)
    }

    func record(id: String?) -> TournamentRecord? {
        guard let id else { return nil }
        return records.first(where: { $0.id == id })
    }

    /// Lee torneos, situaciones y grupos. Con datos ya cargados del mismo curso los mantiene
    /// mientras recarga (sin esqueleto).
    func load(bridge: KmpBridge, classId: Int64?) async {
        guard let classId else {
            records = []
            loadedClassId = nil
            phase = .ready
            return
        }
        if loadedClassId != classId {
            records = []
            teamsBySituation = [:]
            phase = .loading
        } else if phase != .ready {
            phase = .loading
        }
        do {
            let loadedRecords = try await bridge.tournaments(forClassId: classId)
            let allSituations = try await bridge.learningSituations()
            var teams: [Int64: [TournamentWorkGroupTeam]] = [:]
            for situationId in Set(loadedRecords.compactMap(\.learningSituationId)) {
                teams[situationId] = (try? await bridge.workGroupsLinkedToLearningSituation(learningSituationId: situationId)) ?? []
            }
            guard !Task.isCancelled else { return }
            records = loadedRecords
            situations = allSituations.map { (id: $0.id, title: $0.title) }
            teamsBySituation = teams
            loadedClassId = classId
            phase = .ready
        } catch {
            guard !Task.isCancelled else { return }
            if loadedClassId != classId || phase != .ready { phase = .failed }
        }
    }

    func upsert(_ record: TournamentRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
    }

    func remove(id: String) {
        records.removeAll { $0.id == id }
    }

    /// Situaciones del curso (con vínculo al curso, sin archivar) con su número de grupos.
    /// Devuelve también los grupos de cada situación para la hoja «Nuevo torneo».
    static func loadChoices(
        bridge: KmpBridge,
        classId: Int64
    ) async throws -> (choices: [SdaSituationChoice], teams: [Int64: [TournamentWorkGroupTeam]]) {
        let links = try await bridge.learningSituationClassLinksAll()
        let linkedIds = Set(links.filter { $0.classId == classId }.map(\.learningSituationId))
        let situations = try await bridge.learningSituations()
            .filter { linkedIds.contains($0.id) && $0.status != .archived }
        var teams: [Int64: [TournamentWorkGroupTeam]] = [:]
        var counts: [Int64: Int] = [:]
        for situation in situations {
            let situationTeams = try await bridge.workGroupsLinkedToLearningSituation(learningSituationId: situation.id)
            teams[situation.id] = situationTeams
            counts[situation.id] = situationTeams.filter { $0.classId == classId }.count
        }
        let choices = SdaTournamentsOverview.situationChoices(
            situations: situations.map { (id: $0.id, title: $0.title) },
            groupCountBySituation: counts
        )
        return (choices, teams)
    }
}
