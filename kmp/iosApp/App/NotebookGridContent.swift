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
            if case .column(let column) = segment { return column.id }
            return nil
        })
        let cellKey = item.row.persistedCells
            .filter { visibleColumnIds.contains($0.columnId) }
            .map { cell in
                [
                    cell.columnId,
                    cell.textValue ?? "",
                    cell.iconValue ?? "",
                    cell.displayValue ?? ""
                ].joined(separator: ":")
            }
            .joined(separator: "|")
        return [
            "\(index)",
            "\(item.student.id)",
            item.groupName,
            String(describing: item.row.weightedAverage),
            segmentKey,
            cellKey,
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
