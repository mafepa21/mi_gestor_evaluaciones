import SwiftUI
import MiGestorKit

struct NotebookPhysicalGroupTimerRequest: Identifiable {
    let pair: NotebookPhysicalColumnPair

    var id: String { pair.score.id }
}

extension NotebookModuleView {
    @MainActor
    func physicalTestRowCell(
        pair: NotebookPhysicalColumnPair,
        column: NotebookColumnDefinition,
        item: NotebookTableRow,
        data: NotebookUiStateData,
        rowIndex: Int
    ) -> some View {
        let classId = data.sheet.classId
        let isCellSelected = inspectorSelection == NotebookInspectorSelection(studentId: item.student.id, columnId: column.id)
        return NotebookPhysicalTestCell(
            pair: pair,
            student: item.student,
            markText: displayValue(for: item, column: pair.raw),
            scoreText: displayValue(for: item, column: pair.score),
            width: resolvedColumnWidth(for: column),
            tint: displayTint(for: column),
            isSelected: isCellSelected,
            onSelect: {
                selectedColumnId = nil
                focusedCellId = nil
                activeChoiceCellId = nil
                inspectorSelection = NotebookInspectorSelection(studentId: item.student.id, columnId: column.id)
                selectedCellRange = NotebookCellRange(
                    columnId: column.id,
                    anchorStudentId: item.student.id,
                    endStudentId: item.student.id
                )
            },
            makeRoster: { physicalRoster(for: pair) },
            previewScore: { student, value in
                await bridge.resolvePhysicalNotebookScore(
                    classId: classId,
                    student: student,
                    columnId: pair.raw.id,
                    rawValue: value
                )
            },
            onSave: { student, text in
                await bridge.savePhysicalNotebookMark(student: student, classId: classId, pair: pair, text: text)
            },
            onGroupTimer: pair.kind == .time && !column.isLocked
                ? { physicalGroupTimerRequest = NotebookPhysicalGroupTimerRequest(pair: pair) }
                : nil,
            diagnose: { student, value in
                await bridge.diagnosePhysicalNotebookScore(
                    classId: classId,
                    student: student,
                    columnId: pair.raw.id,
                    rawValue: value
                )
            },
            setSex: { student, sex in
                await bridge.setStudentSexFromNotebook(studentId: student.id, sex: sex)
            }
        )
        .frame(maxHeight: .infinity)
        .background(notebookColumnCellFill(for: column, rowIndex: rowIndex))
        .disabled(column.isLocked)
    }

    /// Alumnado en el orden visible del grid, con su marca actual.
    func physicalRoster(for pair: NotebookPhysicalColumnPair) -> [NotebookPhysicalRosterEntry] {
        gridNavigationContext.rows.map {
            NotebookPhysicalRosterEntry(student: $0.student, markText: displayValue(for: $0, column: pair.raw))
        }
    }

    @MainActor
    func physicalGroupTimerSheet(request: NotebookPhysicalGroupTimerRequest, data: NotebookUiStateData) -> some View {
        let classId = data.sheet.classId
        let pair = request.pair
        return NotebookPhysicalGroupTimerSheet(
            pair: pair,
            groupLabel: activeClassLabel,
            roster: physicalRoster(for: pair),
            previewScore: { student, value in
                await bridge.resolvePhysicalNotebookScore(
                    classId: classId,
                    student: student,
                    columnId: pair.raw.id,
                    rawValue: value
                )
            },
            onSave: { student, text in
                await bridge.savePhysicalNotebookMark(student: student, classId: classId, pair: pair, text: text)
            },
            onFinished: { message in
                showToast(message)
            }
        )
    }

    /// Cambia cuando cambia algo que el arreglo de columnas físicas mira.
    func physicalColumnRepairKey(data: NotebookUiStateData) -> String {
        let relevant = data.sheet.columns.filter {
            $0.instrumentKind == .physicalTest || $0.evaluationId != nil
        }
        var hasher = Hasher()
        hasher.combine(data.sheet.classId)
        for column in relevant {
            hasher.combine(column.id)
            hasher.combine(column.title)
            hasher.combine(column.visibility.name)
            hasher.combine(column.countsTowardAverage)
            hasher.combine(column.weight)
        }
        return "\(data.sheet.classId)|\(hasher.finalize())"
    }

    /// Una prueba física, una columna: oculta la marca y la evaluación duplicada y
    /// corrige pesos invertidos (solo visibilidad y peso). Después rellena las notas
    /// que faltan en marcas ya apuntadas; nunca cambia una nota que ya existe.
    @MainActor
    func repairPhysicalColumnsIfNeeded(data: NotebookUiStateData) async {
        await applyPhysicalColumnRepairPlan(data: data)
        let filled = await fillMissingPhysicalScores(data: data)
        if filled > 0 {
            showToast(filled == 1 ? "Calculada 1 nota de prueba física" : "Calculadas \(filled) notas de pruebas físicas")
        }
    }

    @MainActor
    private func fillMissingPhysicalScores(data: NotebookUiStateData) async -> Int {
        let pairs = NotebookPhysicalColumns.pairs(in: data.sheet.columns).filter { !$0.score.isLocked }
        guard !pairs.isEmpty else { return 0 }
        var filled = 0
        for row in data.sheet.rows {
            let item = NotebookTableRow(student: row.student, row: row, groupName: "")
            for pair in pairs {
                let score = displayValue(for: item, column: pair.score).trimmingCharacters(in: .whitespacesAndNewlines)
                guard score.isEmpty || score == "—",
                      let value = NotebookPhysicalMark.value(from: displayValue(for: item, column: pair.raw), kind: pair.kind),
                      let resolved = await bridge.resolvePhysicalNotebookScore(
                          classId: data.sheet.classId,
                          student: row.student,
                          columnId: pair.raw.id,
                          rawValue: value
                      ) else { continue }
                guard !Task.isCancelled else { return filled }
                bridge.saveColumnGrade(studentId: row.student.id, column: pair.score, value: NotebookPhysicalMark.decimalText(resolved))
                filled += 1
            }
        }
        return filled
    }

    @MainActor
    private func applyPhysicalColumnRepairPlan(data: NotebookUiStateData) async {
        let plan = NotebookPhysicalColumns.repairPlan(for: data.sheet.columns)
        guard !plan.isEmpty else { return }
        let columns = plan.map { repair in
            copyNotebookColumn(
                repair.column,
                isHidden: repair.visibility != .visible,
                visibility: repair.visibility,
                weight: repair.weight,
                countsTowardAverage: repair.countsTowardAverage
            )
        }
        do {
            try await bridge.applyPhysicalColumnRepairs(classId: data.sheet.classId, columns: columns)
        } catch {
            showToast("No se pudieron ordenar las columnas de pruebas físicas.", style: .warning)
        }
    }
}
