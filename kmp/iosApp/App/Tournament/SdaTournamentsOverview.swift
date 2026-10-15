import Foundation

// Lógica pura de la pantalla «Torneos» (menú lateral): agrupar la lista del curso por Situación
// de Aprendizaje, resumen de cada fila y opciones del selector «¿De qué situación salen los equipos?».
// No depende de la vista ni del puente, así que se prueba sin pantalla.

/// Una fila de la lista de torneos.
struct SdaTournamentListItem: Identifiable, Equatable {
    let id: String
    let name: String
    /// «Liga · 4 equipos · 2 de 6». Si el torneo no se puede leer, un aviso.
    let summary: String
    /// `nil` si el JSON guardado no se puede leer.
    let status: TournamentPlanStatus?
}

/// Un bloque de la lista: una SdA o «Sin situación».
struct SdaTournamentListSection: Identifiable, Equatable {
    static let withoutSituationId = "sin-situacion"
    static let withoutSituationTitle = "Sin situación"

    let id: String
    let title: String
    /// `nil` en el bloque «Sin situación».
    let situationId: Int64?
    var items: [SdaTournamentListItem]
}

/// Opción del selector de situación al crear un torneo.
struct SdaSituationChoice: Identifiable, Equatable {
    let id: Int64
    let title: String
    /// Grupos de trabajo de la situación que son del curso elegido.
    let groupCount: Int

    /// Un torneo necesita al menos dos equipos.
    var isAvailable: Bool { groupCount >= 2 }

    /// «4 grupos», «Sin grupos» o «1 grupo (hacen falta 2)».
    var detailText: String {
        switch groupCount {
        case 0: return "Sin grupos"
        case 1: return "1 grupo (hacen falta 2)"
        default: return "\(groupCount) grupos"
        }
    }
}

enum SdaTournamentsOverview {
    static let unreadableSummary = "No se pudo leer este torneo."

    /// «Liga · 4 equipos · 2 de 6» (el avance solo sale si el calendario tiene partidos).
    static func summary(of plan: TournamentPlan) -> String {
        var parts = [plan.format.shortTitle, sdaPlural(plan.teamCount, "equipo", "equipos")]
        if plan.totalMatchCount > 0 {
            parts.append("\(plan.completedMatchCount) de \(plan.totalMatchCount)")
        }
        return parts.joined(separator: " · ")
    }

    static func item(for record: TournamentRecord) -> SdaTournamentListItem {
        guard let plan = try? record.plan() else {
            return SdaTournamentListItem(id: record.id, name: record.name, summary: unreadableSummary, status: nil)
        }
        return SdaTournamentListItem(
            id: record.id,
            name: record.name,
            summary: summary(of: plan),
            status: plan.status
        )
    }

    /// Agrupa por situación. El orden de los bloques es el de `situations`; los torneos de una
    /// situación que ya no está en esa lista salen justo antes de «Sin situación», que va siempre
    /// al final. Dentro de cada bloque se respeta el orden de `records`.
    static func sections(
        records: [TournamentRecord],
        situations: [(id: Int64, title: String)]
    ) -> [SdaTournamentListSection] {
        var order: [Int64] = []
        var titles: [Int64: String] = [:]
        for situation in situations where titles[situation.id] == nil {
            order.append(situation.id)
            titles[situation.id] = situation.title
        }
        var bySituation: [Int64: [SdaTournamentListItem]] = [:]
        var withoutSituation: [SdaTournamentListItem] = []
        var unknown: [Int64] = []
        for record in records {
            let item = item(for: record)
            if let situationId = record.learningSituationId {
                if titles[situationId] == nil, !unknown.contains(situationId) {
                    unknown.append(situationId)
                }
                bySituation[situationId, default: []].append(item)
            } else {
                withoutSituation.append(item)
            }
        }
        var result: [SdaTournamentListSection] = []
        for situationId in order + unknown {
            guard let items = bySituation[situationId], !items.isEmpty else { continue }
            result.append(
                SdaTournamentListSection(
                    id: "sda-\(situationId)",
                    title: titles[situationId] ?? "Situación",
                    situationId: situationId,
                    items: items
                )
            )
        }
        if !withoutSituation.isEmpty {
            result.append(
                SdaTournamentListSection(
                    id: SdaTournamentListSection.withoutSituationId,
                    title: SdaTournamentListSection.withoutSituationTitle,
                    situationId: nil,
                    items: withoutSituation
                )
            )
        }
        return result
    }

    /// Mete o reemplaza un registro en la lista del curso cargado. Un guardado tardío de otro curso
    /// (se cambió de curso mientras se guardaba) se ignora para no colarlo en la lista nueva.
    static func upserting(
        _ record: TournamentRecord,
        into records: [TournamentRecord],
        loadedClassId: Int64?
    ) -> [TournamentRecord] {
        guard record.classId == loadedClassId else { return records }
        var result = records
        if let index = result.firstIndex(where: { $0.id == record.id }) {
            result[index] = record
        } else {
            result.append(record)
        }
        return result
    }

    /// Opciones del selector: una por situación enlazada al curso, con su número de grupos
    /// en ese curso. Mantiene el orden recibido.
    static func situationChoices(
        situations: [(id: Int64, title: String)],
        groupCountBySituation: [Int64: Int]
    ) -> [SdaSituationChoice] {
        situations.map {
            SdaSituationChoice(id: $0.id, title: $0.title, groupCount: groupCountBySituation[$0.id] ?? 0)
        }
    }
}
