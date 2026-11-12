import SwiftUI
import MiGestorKit

/// Copiar y pegar celdas de rúbrica sin abrir la rúbrica. Copiar reutiliza
/// `copyStructuredCells` (texto + alumnos de origen). Pegar copia el nivel de cada criterio
/// y guarda la nota que devuelve Kotlin, igual que la evaluación individual.
extension NotebookModuleView {
    func pasteRubricCells(into column: NotebookColumnDefinition, rawClipboard: String, data: NotebookUiStateData) {
        guard let clip = structuredClipboard, clip.text == rawClipboard,
              let sourceColumn = data.sheet.columns.first(where: { $0.id == clip.columnId }),
              sourceColumn.type == .rubric else {
            showToast("Copia antes una celda de rúbrica para pegar aquí", style: .warning)
            return
        }
        guard let targetEvaluationId = column.evaluationId?.int64Value,
              let sourceEvaluationId = sourceColumn.evaluationId?.int64Value else {
            showToast("Esta columna no tiene rúbrica asociada", style: .warning)
            return
        }
        guard column.rubricId?.int64Value == sourceColumn.rubricId?.int64Value else {
            showToast("Solo se puede pegar entre columnas con la misma rúbrica", style: .warning)
            return
        }
        guard let selected = selectedNotebookCell(data: data) else { return }
        let rows = filteredRows(data: data)
        var targets = selectedRangeRows(column: column, data: data).map(\.student.id)
        if targets.isEmpty { targets = [selected.selection.studentId] }

        // Una celda copiada rellena todo el rango; un bloque se pega con la misma forma.
        let pairs: [(source: Int64, target: Int64)]
        if clip.studentIds.count == 1 {
            pairs = targets.map { (clip.studentIds[0], $0) }
        } else {
            guard let start = rows.firstIndex(where: { $0.student.id == targets[0] }) else { return }
            let targetIds = rows[start...].prefix(clip.studentIds.count).map(\.student.id)
            pairs = Array(zip(clip.studentIds, targetIds))
        }
        let movable = pairs.filter { !($0.source == $0.target && clip.columnId == column.id) }
        guard !movable.isEmpty else {
            showToast("Sin cambios: es la misma celda")
            return
        }

        let classId = data.sheet.classId
        Task { @MainActor in
            let repo = bridge.container.rubricsRepository
            var changes: [NotebookCellUndoChange] = []
            var empty = 0
            var failed = 0
            for pair in movable {
                do {
                    let source = try await repo.listRubricAssessments(studentId: pair.source, evaluationId: sourceEvaluationId)
                    guard !source.isEmpty else {
                        empty += 1
                        continue
                    }
                    let previous = try await repo.listRubricAssessments(studentId: pair.target, evaluationId: targetEvaluationId)
                    let levels = Dictionary(source.map { ($0.criterionId, $0.levelId) }, uniquingKeysWith: { _, last in last })
                    try await saveRubricLevels(levels, studentId: pair.target, classId: classId, column: column, evaluationId: targetEvaluationId)
                    changes.append(NotebookCellUndoChange(
                        studentId: pair.target,
                        column: column,
                        previousValue: "",
                        previousDisplayLabel: nil,
                        rubricSnapshot: Dictionary(previous.map { ($0.criterionId, $0.levelId) }, uniquingKeysWith: { _, last in last })
                    ))
                    reloadNotebookRow(pair.target)
                } catch {
                    failed += 1
                }
            }
            recordCellUndoBatch(changes)
            if empty > 0 || failed > 0 {
                var parts = ["Pegadas \(changes.count) celdas."]
                if empty > 0 { parts.append("\(empty) de origen sin evaluar.") }
                if failed > 0 { parts.append("\(failed) no se pudieron guardar.") }
                showToast(parts.joined(separator: " "), style: .warning)
            } else {
                showToast(changes.count == 1 ? "Celda pegada. ⌘Z para deshacer" : "Pegadas \(changes.count) celdas. ⌘Z para deshacer")
            }
        }
    }

    /// Guarda los niveles y la nota resultante en la celda, como la evaluación individual.
    @MainActor
    func saveRubricLevels(
        _ levels: [Int64: Int64],
        studentId: Int64,
        classId: Int64,
        column: NotebookColumnDefinition,
        evaluationId: Int64
    ) async throws {
        let repo = bridge.container.rubricsRepository
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        var score: Double?
        for (criterionId, levelId) in levels.sorted(by: { $0.key < $1.key }) {
            let result = try await repo.saveRubricAssessment(
                studentId: studentId,
                evaluationId: evaluationId,
                criterionId: criterionId,
                levelId: levelId,
                updatedAtEpochMs: nowMs,
                deviceId: bridge.localDeviceId,
                syncVersion: 1
            )
            score = result?.doubleValue ?? score
        }
        guard let score else { return }
        let saved = try await repo.listRubricAssessments(studentId: studentId, evaluationId: evaluationId)
        let selections = saved.map { "\($0.criterionId):\($0.levelId)" }.sorted().joined(separator: ",")
        try await bridge.container.notebookRepository.upsertGrade(
            classId: classId,
            studentId: studentId,
            columnId: column.id,
            evaluationId: KotlinLong(value: evaluationId),
            numericValue: score,
            rubricSelections: selections.isEmpty ? nil : selections,
            evidence: nil,
            createdAtEpochMs: nowMs,
            updatedAtEpochMs: nowMs,
            deviceId: bridge.localDeviceId,
            syncVersion: 1
        )
    }

    func restoreRubricSnapshots(_ changes: [NotebookCellUndoChange]) {
        guard let classId = (bridge.notebookState as? NotebookUiStateData)?.sheet.classId else { return }
        Task { @MainActor in
            for change in changes {
                guard let snapshot = change.rubricSnapshot,
                      let evaluationId = change.column.evaluationId?.int64Value else { continue }
                if snapshot.isEmpty {
                    // No hay borrado de niveles sueltos: se vacía la nota de la celda.
                    bridge.saveColumnGrade(studentId: change.studentId, column: change.column, value: "")
                } else {
                    try? await saveRubricLevels(snapshot, studentId: change.studentId, classId: classId, column: change.column, evaluationId: evaluationId)
                }
                reloadNotebookRow(change.studentId)
            }
        }
    }
}
