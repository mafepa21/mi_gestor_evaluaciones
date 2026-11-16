import Foundation
import MiGestorKit

/// Una evaluación de la clase que se puntúa con rúbrica: lo que se elige en el modo directo
/// del torneo para evaluar a un equipo.
struct TournamentRubricOption: Identifiable, Hashable, Sendable {
    let evaluationId: Int64
    let rubricId: Int64
    let evaluationName: String
    let rubricName: String
    /// Columna del Cuaderno ligada a la evaluación, si existe: así la nota aparece en ella.
    let columnId: String?
    let tabId: String?

    var id: Int64 { evaluationId }
}

extension KmpBridge {
    /// Evaluaciones con rúbrica de una clase, en orden alfabético. Misma regla que
    /// `launchBulkRubricEvaluationFromUsage` para encontrar la columna del Cuaderno.
    @MainActor
    func tournamentRubricOptions(classId: Int64) async throws -> [TournamentRubricOption] {
        if rubrics.isEmpty {
            try? await refreshRubrics()
        }
        let evaluations = try await container.evaluationsRepository.listClassEvaluations(classId: classId)
        let columns = try await container.notebookConfigRepository.listColumns(classId: classId)
        let rubricNames = Dictionary(
            rubrics.map { ($0.rubric.id, $0.rubric.name) },
            uniquingKeysWith: { first, _ in first }
        )
        return evaluations
            .compactMap { evaluation -> TournamentRubricOption? in
                guard let rubricId = evaluation.rubricId?.int64Value else { return nil }
                let column = columns.first { $0.evaluationId?.int64Value == evaluation.id }
                return TournamentRubricOption(
                    evaluationId: evaluation.id,
                    rubricId: rubricId,
                    evaluationName: evaluation.name,
                    rubricName: rubricNames[rubricId] ?? "Rúbrica",
                    columnId: column?.id,
                    tabId: column?.tabIds.first
                )
            }
            .sorted { $0.evaluationName.localizedCaseInsensitiveCompare($1.evaluationName) == .orderedAscending }
    }

    /// Carga la rúbrica en el ViewModel de evaluación masiva sin abrir su hoja: el modo directo
    /// la muestra solo para un equipo. Cada nivel tocado se guarda solo (guardado automático).
    @MainActor
    func loadTournamentRubric(_ option: TournamentRubricOption, classId: Int64) {
        rubricBulkEvaluationViewModel.load(
            classId: classId,
            evaluationId: option.evaluationId,
            rubricId: option.rubricId,
            columnId: option.columnId,
            tabId: option.tabId
        )
    }

    /// Al cerrar la hoja del equipo: recarga el Cuaderno una vez y sincroniza con el Mac.
    @MainActor
    func finishTournamentRubric(classId: Int64) {
        rubricBulkEvaluationViewModel.onSheetClosed(emitNotebookRefresh: true)
        scheduleNotebookSnapshotSync(forClassId: classId)
    }
}
