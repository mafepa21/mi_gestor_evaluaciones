import SwiftUI
import MiGestorKit

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
                        bridge: bridge,
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
