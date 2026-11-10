import SwiftUI
import MiGestorKit

/// Copiar y pegar celdas de lista de cotejo/rejilla de observación sin abrir el instrumento.
/// Al copiar, el portapapeles del sistema recibe las notas (para pegarlas en otras apps o en
/// columnas numéricas) y el Cuaderno recuerda de qué alumnos y columna salen las respuestas.
/// Al pegar en otra lista de cotejo se copian las respuestas ítem a ítem y Kotlin recalcula la
/// nota al guardar (`saveStructuredInstrumentEvaluation`).
extension NotebookModuleView {
    /// Filas del rango seleccionado en `column`, en orden visible. Vacío si no hay rango.
    func selectedRangeRows(column: NotebookColumnDefinition, data: NotebookUiStateData) -> [NotebookTableRow] {
        guard let range = selectedCellRange, range.columnId == column.id else { return [] }
        let rows = filteredRows(data: data)
        guard let start = rows.firstIndex(where: { $0.student.id == range.anchorStudentId }),
              let end = rows.firstIndex(where: { $0.student.id == range.endStudentId }) else { return [] }
        return Array(rows[min(start, end)...max(start, end)])
    }

    /// Menú contextual: si la celda está dentro del rango seleccionado, se respeta el rango;
    /// si no, pasa a ser la celda seleccionada.
    func selectCellForClipboard(studentId: Int64, column: NotebookColumnDefinition) {
        if let data = bridge.notebookState as? NotebookUiStateData,
           selectedRangeRows(column: column, data: data).contains(where: { $0.student.id == studentId }) {
            return
        }
        inspectorSelection = NotebookInspectorSelection(studentId: studentId, columnId: column.id)
        selectedCellRange = NotebookCellRange(columnId: column.id, anchorStudentId: studentId, endStudentId: studentId)
    }

    func copyStructuredCells(column: NotebookColumnDefinition, data: NotebookUiStateData) {
        guard let selected = selectedNotebookCell(data: data) else { return }
        var rows = selectedRangeRows(column: column, data: data)
        if rows.isEmpty { rows = [selected.row] }
        let text = rows.map { displayValue(for: $0, column: column) }.joined(separator: "\n")
        setClipboardText(text)
        structuredClipboard = NotebookStructuredClipboard(
            columnId: column.id,
            studentIds: rows.map(\.student.id),
            text: text
        )
        showToast(rows.count == 1 ? "Celda copiada" : "Copiadas \(rows.count) celdas")
    }

    func pasteStructuredCells(into column: NotebookColumnDefinition, rawClipboard: String, data: NotebookUiStateData) {
        guard let clip = structuredClipboard, clip.text == rawClipboard else {
            showToast("Copia antes una celda de lista de cotejo para pegar aquí", style: .warning)
            return
        }
        guard let selected = selectedNotebookCell(data: data) else { return }
        let rows = filteredRows(data: data)
        var targets = selectedRangeRows(column: column, data: data).map(\.student.id)
        if targets.isEmpty { targets = [selected.selection.studentId] }

        // Una celda copiada rellena todo el rango; un bloque se pega desde la primera fila destino
        // hacia abajo, con la misma forma.
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
            var changes: [NotebookCellUndoChange] = []
            var incompatible = 0
            var failed = 0
            for pair in movable {
                do {
                    guard let source = try await bridge.loadStructuredInstrumentEvaluation(
                              classId: classId, studentId: pair.source, columnId: clip.columnId),
                          let target = try await bridge.loadStructuredInstrumentEvaluation(
                              classId: classId, studentId: pair.target, columnId: column.id) else {
                        incompatible += 1
                        continue
                    }
                    guard let merged = Self.copyingResponses(from: source, into: target) else {
                        incompatible += 1
                        continue
                    }
                    try await bridge.saveStructuredInstrumentEvaluation(merged)
                    changes.append(NotebookCellUndoChange(
                        studentId: pair.target,
                        column: column,
                        previousValue: "",
                        previousDisplayLabel: nil,
                        structuredSnapshot: target
                    ))
                    reloadNotebookRow(pair.target)
                } catch {
                    failed += 1
                }
            }
            recordCellUndoBatch(changes)
            if incompatible > 0 || failed > 0 {
                var parts = ["Pegadas \(changes.count) celdas."]
                if incompatible > 0 { parts.append("\(incompatible) con ítems distintos.") }
                if failed > 0 { parts.append("\(failed) no se pudieron guardar.") }
                showToast(parts.joined(separator: " "), style: .warning)
            } else {
                showToast(changes.count == 1 ? "Celda pegada. ⌘Z para deshacer" : "Pegadas \(changes.count) celdas. ⌘Z para deshacer")
            }
        }
    }

    /// Copia las respuestas de `source` en `target`. Misma plantilla: ítem a ítem por posición.
    /// Plantillas distintas: solo los ítems con la misma clave y tipo. `nil` si no coincide nada.
    static func copyingResponses(
        from source: StructuredInstrumentEvaluationModel,
        into target: StructuredInstrumentEvaluationModel
    ) -> StructuredInstrumentEvaluationModel? {
        var result = target
        let sourceByKey = Dictionary(source.items.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var matched = 0
        for index in result.items.indices {
            let item = result.items[index]
            guard let from = sourceByKey[item.key], from.type == item.type else { continue }
            result.items[index].numberValue = from.numberValue
            result.items[index].boolValue = from.boolValue
            result.items[index].textValue = from.textValue
            matched += 1
        }
        return matched > 0 ? result : nil
    }

    func restoreStructuredSnapshots(_ changes: [NotebookCellUndoChange]) {
        Task { @MainActor in
            for change in changes {
                guard let snapshot = change.structuredSnapshot else { continue }
                _ = try? await bridge.saveStructuredInstrumentEvaluation(snapshot)
                // Kotlin no borra la nota si las respuestas quedan vacías: se borra aquí.
                let hasAnswers = snapshot.items.contains { !$0.numberValue.isEmpty || $0.boolValue }
                if !hasAnswers {
                    bridge.saveColumnGrade(studentId: change.studentId, column: change.column, value: "")
                }
                reloadNotebookRow(change.studentId)
            }
        }
    }
}
