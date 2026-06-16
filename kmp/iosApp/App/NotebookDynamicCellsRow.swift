import SwiftUI
import MiGestorKit

@MainActor
struct NotebookDynamicCellsRow: View {
    @ObservedObject var bridge: KmpBridge
    let item: NotebookTableRow
    let segments: [NotebookDisplaySegment]
    let inspectorSelection: NotebookInspectorSelection?
    let onSelect: (NotebookInspectorSelection) -> Void
    @FocusState private var focusedCellId: String?
    @State private var activeChoiceCellId: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            ForEach(segments, id: \.id) { segment in
                switch segment {
                case .fixed:
                    EmptyView()
                case .column(let column):
                    NotebookEditableTableCell(
                        displaySnapshot: cellDisplaySnapshot(for: column),
                        actions: notebookCellActions(),
                        item: item,
                        column: column,
                        classId: nil,
                        width: max(column.widthDp, 120),
                        tint: column.colorHex.map { Color(hex: $0) } ?? NotebookStyle.primaryTint,
                        categoryTint: nil,
                        hasColumnColor: column.colorHex?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                        focusedCellId: $focusedCellId,
                        activeChoiceCellId: $activeChoiceCellId,
                        navigationDirection: .down,
                        formulaDisplay: nil,
                        isSelected: inspectorSelection == NotebookInspectorSelection(studentId: item.student.id, columnId: column.id),
                        isAttendanceQuickMode: false,
                        reloadToken: 0,
                        onSelect: {
                            onSelect(NotebookInspectorSelection(studentId: item.student.id, columnId: column.id))
                        },
                        onPrepareUndo: { _, _ in },
                        onOpenFormula: {},
                        onOpenRubricIndividual: {},
                        onOpenRubricBulk: {},
                        onNavigate: { _ in },
                        onCellSaved: {},
                        onAttendanceSaved: {}
                    )
                    .frame(width: max(column.widthDp, 120))
                case .collapsedCategory(let category, let columns):
                    Button {
                        bridge.toggleColumnCategory(id: category.id, collapsed: false)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.name)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("\(columns.filter { !cellValue(for: $0).isEmpty }.count) / \(columns.count)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 150, alignment: .leading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(NotebookStyle.surfaceMuted)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @MainActor
    private func cellDisplaySnapshot(for column: NotebookColumnDefinition) -> NotebookCellDisplaySnapshot {
        let persistedCell = item.row.persistedCells.first(where: { $0.columnId == column.id })
        switch column.type {
        case .numeric:
            return NotebookCellDisplaySnapshot(
                numericText: bridge.numericGradeText(studentId: item.student.id, columnId: column.id)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        case .check:
            return NotebookCellDisplaySnapshot(checkValue: bridge.cellCheck(studentId: item.student.id, columnId: column.id))
        case .calculated:
            return NotebookCellDisplaySnapshot(calculatedText: bridge.numericGradeOnTenText(studentId: item.student.id, columnId: column.id))
        case .rubric:
            return NotebookCellDisplaySnapshot(
                rubricText: bridge.rubricGradeOnTenText(studentId: item.student.id, column: column)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        case .attendance:
            return NotebookCellDisplaySnapshot(text: bridge.cellText(studentId: item.student.id, columnId: column.id))
        default:
            return NotebookCellDisplaySnapshot(text: persistedCell?.textValue ?? persistedCell?.displayValue ?? "")
        }
    }

    @MainActor
    private func notebookCellActions() -> NotebookCellActions {
        NotebookCellActions(
            flushPendingColumnGradeSave: { studentId, columnId in
                bridge.flushPendingColumnGradeSave(studentId: studentId, columnId: columnId)
            },
            saveColumnGrade: { studentId, column, value in
                bridge.saveColumnGrade(studentId: studentId, column: column, value: value)
            },
            saveColumnGradeDebounced: { studentId, column, value in
                bridge.saveColumnGradeDebounced(studentId: studentId, column: column, value: value)
            },
            saveAttendance: { studentId, classId, date, status in
                try? await bridge.saveAttendance(
                    studentId: studentId,
                    classId: classId,
                    on: date,
                    status: status
                )
            }
        )
    }

    private func cellValue(for column: NotebookColumnDefinition) -> String {
        switch column.type {
        case .numeric, .calculated:
            return bridge.numericGradeText(studentId: item.student.id, columnId: column.id)
        case .rubric:
            return bridge.rubricGradeOnTenText(studentId: item.student.id, column: column)
        case .check:
            return bridge.cellCheck(studentId: item.student.id, columnId: column.id) ? "true" : ""
        default:
            return bridge.cellText(studentId: item.student.id, columnId: column.id)
        }
    }
}
