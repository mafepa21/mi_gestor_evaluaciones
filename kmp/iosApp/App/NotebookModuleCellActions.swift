import SwiftUI
import MiGestorKit

extension NotebookModuleView {
    func cellFocusId(studentId: Int64, columnId: String) -> String {
        "\(studentId)|\(columnId)"
    }

    func presentFormulaEditor(for column: NotebookColumnDefinition) {
        formulaDraft = column.formula ?? ""
        formulaAIPrompt = ""
        formulaAIMessage = nil
        isFormulaAIGenerating = false
        focusedCellId = nil
        activeChoiceCellId = nil
        formulaEditRequest = NotebookFormulaEditRequest(columnId: column.id)
    }

    func saveFormula(_ column: NotebookColumnDefinition) {
        let trimmed = formulaDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = bridge.notebookState as? NotebookUiStateData else { return }
        let validation = NotebookFormulaEditorValidator.validate(
            formula: trimmed,
            targetColumn: column,
            availableColumns: data.sheet.columns,
            formulaColumns: data.sheet.columns.filter { $0.type == .calculated },
            previewRow: data.sheet.rows.first
        )
        guard validation.isValid else {
            formulaAIMessage = validation.errors.first?.message ?? "Revisa la fórmula antes de guardar."
            return
        }
        saveColumnMutation(
            column,
            formula: trimmed.isEmpty ? nil : trimmed,
            updatesFormula: true
        )
        formulaEditRequest = nil
        showToast(trimmed.isEmpty ? "Fórmula eliminada" : "Fórmula actualizada")
    }

    func generateFormulaWithAI(column: NotebookColumnDefinition, data: NotebookUiStateData) {
        let prompt = formulaAIPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        isFormulaAIGenerating = true
        formulaAIMessage = nil
        let columns = formulaReferenceColumns(for: column, data: data)
        let currentFormula = formulaDraft
        Task {
            do {
                let generation = try await formulaAIOrchestrator.generateWithTrace(
                    .formulaSuggestion(prompt, currentFormula, columns),
                    dataSource: "Cuaderno · fórmula asistida",
                    includedEvidence: columns.map(\.title)
                )
                guard case .formulaSuggestion(let formula) = generation.result else { return }
                await MainActor.run {
                    formulaDraft = formula
                    formulaAIMessage = generation.metadata.audit.usedFallback ? "Propuesta por reglas insertada. Revísala antes de guardar." : "Propuesta insertada. Revísala antes de guardar."
                    isFormulaAIGenerating = false
                }
            } catch {
                await MainActor.run {
                    formulaAIMessage = error.localizedDescription
                    isFormulaAIGenerating = false
                }
            }
        }
    }

    func openRubricIndividual(column: NotebookColumnDefinition, item: NotebookTableRow) {
        guard let rubricId = column.rubricId?.int64Value,
              let evaluationId = column.evaluationId?.int64Value else {
            showToast("Esta columna no tiene rúbrica/evaluación asociada.", style: .warning)
            return
        }
        let classId: Int64
        if let data = bridge.notebookState as? NotebookUiStateData {
            pendingRubricStudentOrder = filteredRows(data: data).map { $0.student.id }
            classId = data.sheet.classId
        } else {
            pendingRubricStudentOrder = [item.student.id]
            classId = bridge.notebookViewModel.currentClassId?.int64Value ?? 0
        }
        pendingRubricColumnId = column.id
        pendingRubricCurrentStudentId = item.student.id
        bridge.startRubricEvaluationCoordinator(
            columnId: column.id,
            rubricId: rubricId,
            classId: classId,
            evaluationId: evaluationId,
            studentIds: pendingRubricStudentOrder,
            currentStudentId: item.student.id
        )
        withAnimation(.spring(response: 0.18, dampingFraction: 0.9)) {
            focusedCellId = nil
            activeChoiceCellId = nil
            inspectorSelection = NotebookInspectorSelection(studentId: item.student.id, columnId: column.id)
        }
        DispatchQueue.main.async {
            bridge.closeBulkRubricEvaluation()
            bridge.openRubricEvaluationFromNotebook(
                studentId: item.student.id,
                columnId: column.id,
                rubricId: rubricId,
                evaluationId: evaluationId
            )
        }
    }

    func openNextRubricStudentIfPossible() {
        guard let data = bridge.notebookState as? NotebookUiStateData else {
            resetPendingRubricSequence()
            bridge.closeRubricEvaluation()
            return
        }

        let visibleStudentIds = filteredRows(data: data).map { $0.student.id }
        switch bridge.advanceRubricEvaluationToNextStudent(visibleStudentIds: visibleStudentIds) {
        case .openedNext(let studentId, _):
            pendingRubricCurrentStudentId = studentId
            pendingRubricColumnId = bridge.rubricEvaluationCoordinator.context?.columnId
            pendingRubricStudentOrder = bridge.rubricEvaluationCoordinator.context?.studentIds ?? visibleStudentIds
            if let columnId = pendingRubricColumnId {
                inspectorSelection = NotebookInspectorSelection(studentId: studentId, columnId: columnId)
            }
        case .completed(let summary):
            resetPendingRubricSequence()
            showToast("Rúbrica completada para \(summary.evaluatedCount) alumno\(summary.evaluatedCount == 1 ? "" : "s").")
        case .closed:
            resetPendingRubricSequence()
        }
    }

    func resetPendingRubricSequence() {
        pendingRubricColumnId = nil
        pendingRubricCurrentStudentId = nil
        pendingRubricStudentOrder = []
        bridge.isNotebookRubricAutoAdvanceActive = false
        bridge.rubricEvaluationCoordinator.reset()
    }

    func openRubricBulk(column: NotebookColumnDefinition, data: NotebookUiStateData) {
        guard let evaluationId = column.evaluationId?.int64Value,
              let rubricId = column.rubricId?.int64Value else {
            showToast("Esta columna no tiene una rúbrica asociada", style: .warning)
            return
        }
        focusedCellId = nil
        activeChoiceCellId = nil
        bridge.startBulkRubricEvaluation(
            classId: data.sheet.classId,
            evaluationId: evaluationId,
            rubricId: rubricId,
            columnId: column.id,
            tabId: activeNotebookTabId(data: data)
        )
    }

    func navigateFromFocused(direction: NotebookNavigationDirection, data: NotebookUiStateData) {
        let currentCellId = focusedCellId ?? activeChoiceCellId
        guard let currentCellId else { return }
        let parts = currentCellId.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let studentId = Int64(parts[0]),
              let column = data.sheet.columns.first(where: { $0.id == parts[1] }) else {
            return
        }
        navigateCell(
            from: studentId,
            column: column,
            direction: direction,
            rows: filteredRows(data: data),
            segments: displaySegments(data: data).filter { !isFixedSegment($0) }
        )
    }

    func navigateCell(
        from studentId: Int64,
        column: NotebookColumnDefinition,
        direction: NotebookNavigationDirection,
        rows: [NotebookTableRow],
        segments: [NotebookDisplaySegment]
    ) {
        let navigableColumns = segments.compactMap { segment -> NotebookColumnDefinition? in
            guard case .column(let candidate) = segment else { return nil }
            return candidate
        }

        guard !rows.isEmpty,
              !navigableColumns.isEmpty,
              let currentRowIndex = rows.firstIndex(where: { $0.student.id == studentId }),
              let currentColumnIndex = navigableColumns.firstIndex(where: { $0.id == column.id }) else {
            return
        }

        var nextRowIndex = currentRowIndex
        var nextColumnIndex = currentColumnIndex
        switch direction {
        case .up:
            nextRowIndex = max(currentRowIndex - 1, 0)
        case .down:
            nextRowIndex = min(currentRowIndex + 1, rows.count - 1)
        case .left:
            nextColumnIndex = max(currentColumnIndex - 1, 0)
        case .right:
            nextColumnIndex = min(currentColumnIndex + 1, navigableColumns.count - 1)
        }

        let nextStudentId = rows[nextRowIndex].student.id
        let nextColumn = navigableColumns[nextColumnIndex]
        let nextCellId = cellFocusId(studentId: nextStudentId, columnId: nextColumn.id)

        withAnimation(.spring(response: 0.18, dampingFraction: 0.9)) {
            inspectorSelection = NotebookInspectorSelection(studentId: nextStudentId, columnId: nextColumn.id)
            focusedCellId = nil
            activeChoiceCellId = nil
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.9)) {
                if nextColumn.type == .ordinal || nextColumn.type == .attendance || nextColumn.categoryKind == .attendance {
                    activeChoiceCellId = nextCellId
                } else if nextColumn.type != .calculated && nextColumn.type != .rubric && nextColumn.type != .check {
                    focusedCellId = nextCellId
                }
            }
        }
    }

}
