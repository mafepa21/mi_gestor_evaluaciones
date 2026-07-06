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
                        onOpenStructuredInstrument: {},
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
        let persistedGrade = item.row.persistedGrades.first(where: { $0.columnId == column.id })
        
        switch column.type {
        case .numeric:
            let numericVal: String
            if let value = persistedGrade?.value {
                numericVal = IosFormatting.decimal(from: value.doubleValue)
            } else {
                numericVal = persistedCell?.textValue ?? persistedCell?.displayValue ?? ""
            }
            return NotebookCellDisplaySnapshot(numericText: numericVal.trimmingCharacters(in: .whitespacesAndNewlines))
        case .check:
            let boolVal = persistedCell?.boolValue?.boolValue ?? false
            return NotebookCellDisplaySnapshot(checkValue: boolVal)
        case .calculated:
            let calculatedVal: String
            if let value = persistedGrade?.value {
                calculatedVal = IosFormatting.decimal(from: value.doubleValue)
            } else {
                calculatedVal = persistedCell?.displayValue ?? ""
            }
            return NotebookCellDisplaySnapshot(calculatedText: calculatedVal)
        case .rubric:
            let rubricVal: String
            if let display = persistedCell?.displayValue {
                rubricVal = display
            } else if let value = persistedGrade?.value {
                rubricVal = IosFormatting.decimal(from: value.doubleValue)
            } else {
                rubricVal = ""
            }
            return NotebookCellDisplaySnapshot(rubricText: rubricVal.trimmingCharacters(in: .whitespacesAndNewlines))
        case .attendance:
            let textVal = persistedCell?.textValue ?? persistedCell?.ordinalValue ?? ""
            return NotebookCellDisplaySnapshot(text: textVal)
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
        if column.inputKind.isStructuredInstrument {
            return bridge.structuredCellDisplayText(studentId: item.student.id, columnId: column.id)
        }
        let persistedCell = item.row.persistedCells.first(where: { $0.columnId == column.id })
        let persistedGrade = item.row.persistedGrades.first(where: { $0.columnId == column.id })
        
        switch column.type {
        case .numeric, .calculated:
            if let value = persistedGrade?.value {
                return IosFormatting.decimal(from: value.doubleValue)
            }
            return persistedCell?.textValue ?? persistedCell?.displayValue ?? ""
        case .rubric:
            if let display = persistedCell?.displayValue {
                return display
            }
            if let value = persistedGrade?.value {
                return IosFormatting.decimal(from: value.doubleValue)
            }
            return ""
        case .check:
            let boolVal = persistedCell?.boolValue?.boolValue ?? false
            return boolVal ? "true" : ""
        default:
            return persistedCell?.textValue ?? persistedCell?.displayValue ?? ""
        }
    }
}
