import Foundation
import MiGestorKit

enum PhysicalTestsReload {
    static let failure = "No se pudieron cargar las pruebas físicas. Se mantiene lo que ya ves."
}

enum PhysicalColumnCreateGuard {
    static let linksFailure = "No se pudieron leer las columnas ya creadas. No se ha creado ninguna para no duplicarlas."
}

/// Filtro y tamaño del histórico de pruebas físicas.
/// La UI usa filas lazy para no montar todas las tarjetas de golpe.
enum PhysicalTestsHistoryList {
    enum CompletionFilter: String, CaseIterable {
        case all
        case pending
        case completed
    }

    static func matches(
        definitionId: String?,
        recordedCount: Int,
        resultCount: Int,
        definitionFilter: String?,
        completion: CompletionFilter
    ) -> Bool {
        if let definitionFilter, definitionId != definitionFilter { return false }
        switch completion {
        case .all:
            return true
        case .pending:
            return recordedCount < resultCount
        case .completed:
            return recordedCount >= resultCount && resultCount > 0
        }
    }

    static func filteredProgressCounts(
        rows: [(definitionId: String?, recordedCount: Int, resultCount: Int)],
        definitionFilter: String?,
        completion: CompletionFilter
    ) -> Int {
        rows.filter {
            matches(
                definitionId: $0.definitionId,
                recordedCount: $0.recordedCount,
                resultCount: $0.resultCount,
                definitionFilter: definitionFilter,
                completion: completion
            )
        }.count
    }

    /// Tarjetas del histórico si se construyen todas a la vez.
    static func eagerRowCount(filteredTestCount: Int) -> Int {
        max(0, filteredTestCount)
    }
}
