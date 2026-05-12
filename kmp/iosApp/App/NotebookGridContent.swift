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
        let cellCount = item.row.persistedCells.count
        let average = item.row.weightedAverage.map { String(format: "%.2f", $0.doubleValue) } ?? "nil"
        return [
            "\(item.student.id)",
            average,
            "\(cellCount)",
            segmentKey,
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
