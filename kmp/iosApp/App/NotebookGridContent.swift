import SwiftUI

struct NotebookGridContent<
    EmptyContent: View,
    SeatingContent: View,
    TopAccessory: View,
    DividerHandle: View,
    HeaderContent: View,
    RowContent: View
>: View {
    let rows: [NotebookTableRow]
    let surfaceMode: NotebookSurfaceMode
    let fixedColumnWidth: CGFloat
    let trailingFixedColumnWidth: CGFloat
    let topAccessoryHeight: CGFloat
    let headerHeight: CGFloat
    let rowHeight: CGFloat
    let rowInvalidationKey: String
    let fixedSegments: [NotebookDisplaySegment]
    let trailingFixedSegments: [NotebookDisplaySegment]
    let scrollableSegments: [NotebookDisplaySegment]
    let emptyContent: () -> EmptyContent
    let seatingContent: ([NotebookTableRow]) -> SeatingContent
    let topAccessory: () -> TopAccessory
    let dividerHandle: () -> DividerHandle
    let header: ([NotebookDisplaySegment]) -> HeaderContent
    let rowContent: (Int, NotebookTableRow, [NotebookDisplaySegment]) -> RowContent

    var body: some View {
        NotebookGridContainer(
            rows: rows,
            surfaceMode: surfaceMode,
            fixedColumnWidth: fixedColumnWidth,
            trailingFixedColumnWidth: trailingFixedColumnWidth,
            topAccessoryHeight: topAccessoryHeight,
            headerHeight: headerHeight,
            rowHeight: rowHeight
        ) {
            emptyContent()
        } seatingContent: { rows in
            seatingContent(rows)
        } topAccessory: {
            topAccessory()
        } dividerHandle: {
            dividerHandle()
        } fixedHeader: {
            header(fixedSegments)
        } trailingFixedHeader: {
            header(trailingFixedSegments)
        } scrollHeader: {
            header(scrollableSegments)
        } fixedRow: { index, item in
            NotebookEquatableGridRow(signature: rowSignature(index: index, item: item, segments: fixedSegments)) {
                rowContent(index, item, fixedSegments)
            }
        } trailingFixedRow: { index, item in
            NotebookEquatableGridRow(signature: rowSignature(index: index, item: item, segments: trailingFixedSegments)) {
                rowContent(index, item, trailingFixedSegments)
            }
        } scrollRow: { index, item in
            NotebookEquatableGridRow(signature: rowSignature(index: index, item: item, segments: scrollableSegments)) {
                rowContent(index, item, scrollableSegments)
            }
        }
    }

    private func rowSignature(index: Int, item: NotebookTableRow, segments: [NotebookDisplaySegment]) -> String {
        let segmentKey = segments.map(\.id).joined(separator: ",")
        let visibleColumnIds = Set(segments.compactMap { segment -> String? in
            switch segment {
            case .column(let column):
                return column.id
            default:
                return nil
            }
        } + segments.flatMap { segment -> [String] in
            if case .collapsedCategory(_, let columns) = segment {
                return columns.map(\.id)
            }
            return []
        })
        let visibleCellDigest = item.row.persistedCells
            .filter { visibleColumnIds.contains($0.columnId) }
            .sorted { $0.columnId < $1.columnId }
            .map { cell in
                [
                    cell.columnId,
                    cell.textValue ?? "",
                    cell.displayValue ?? "",
                    cell.iconValue ?? "",
                    cell.boolValue?.boolValue == true ? "1" : "0"
                ].joined(separator: ":")
            }
            .joined(separator: "|")
        let visibleGradeDigest = item.row.persistedGrades
            .filter { visibleColumnIds.contains($0.columnId) }
            .sorted { $0.columnId < $1.columnId }
            .map { grade in
                [
                    grade.columnId,
                    grade.value.map { String(format: "%.4f", $0.doubleValue) } ?? "",
                    grade.evidencePath ?? "",
                    grade.rubricSelections ?? ""
                ].joined(separator: ":")
            }
            .joined(separator: "|")
        let average = item.row.weightedAverage.map { String(format: "%.2f", $0.doubleValue) } ?? "nil"
        return [
            "\(item.student.id)",
            average,
            segmentKey,
            visibleCellDigest,
            visibleGradeDigest,
            rowInvalidationKey
        ].joined(separator: "¬")
    }
}

private struct NotebookEquatableGridRow<Content: View>: View, Equatable {
    let signature: String
    let content: () -> Content

    var body: some View {
        content()
    }

    static func == (lhs: NotebookEquatableGridRow<Content>, rhs: NotebookEquatableGridRow<Content>) -> Bool {
        lhs.signature == rhs.signature
    }
}
