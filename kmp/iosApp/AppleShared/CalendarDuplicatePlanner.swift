import Foundation

/// Un evento de calendario visto desde la regla de repetidos.
struct CalendarDuplicateCandidate: Equatable {
    let id: Int64
    let title: String
    let startMs: Int64
    let endMs: Int64
    let classId: Int64?
    let isLinked: Bool
}

/// Un periodo de evaluación visto desde la regla de repetidos.
struct EvaluationPeriodDuplicateCandidate: Equatable {
    let id: Int64
    let name: String
    let startDateIso: String
    let endDateIso: String
    let scheduleId: Int64
}

/// Decide qué elementos repetidos borrar. De cada grupo repetido siempre se conserva uno.
enum CalendarDuplicatePlanner {
    /// Dos eventos con el mismo título, inicio y fin son el mismo evento, aunque uno no tenga grupo.
    /// Se conserva primero el que tiene grupo, luego el enlazado con «Colegio», y por último el más antiguo.
    static func eventIdsToRemove(_ events: [CalendarDuplicateCandidate]) -> [Int64] {
        let groups = Dictionary(grouping: events) { "\($0.title)|\($0.startMs)|\($0.endMs)" }
        var ids: [Int64] = []
        for group in groups.values where group.count > 1 {
            let sorted = group.sorted { lhs, rhs in
                if (lhs.classId != nil) != (rhs.classId != nil) { return lhs.classId != nil }
                if lhs.isLinked != rhs.isLinked { return lhs.isLinked }
                return lhs.id < rhs.id
            }
            ids.append(contentsOf: sorted.dropFirst().map(\.id))
        }
        return ids.sorted()
    }

    /// Periodos con el mismo nombre, las mismas fechas y el mismo horario. Se conserva el más antiguo.
    static func periodIdsToRemove(_ periods: [EvaluationPeriodDuplicateCandidate]) -> [Int64] {
        let groups = Dictionary(grouping: periods) {
            "\($0.scheduleId)|\($0.name)|\($0.startDateIso)|\($0.endDateIso)"
        }
        var ids: [Int64] = []
        for group in groups.values where group.count > 1 {
            ids.append(contentsOf: group.sorted { $0.id < $1.id }.dropFirst().map(\.id))
        }
        return ids.sorted()
    }
}
