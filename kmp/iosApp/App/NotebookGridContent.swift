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
    let topAccessoryHeight: CGFloat
    let headerHeight: CGFloat
    let rowHeight: CGFloat
    let fixedSegments: [NotebookDisplaySegment]
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
        } scrollHeader: {
            header(scrollableSegments)
        } fixedRow: { index, item in
            rowContent(index, item, fixedSegments)
        } scrollRow: { index, item in
            rowContent(index, item, scrollableSegments)
        }
    }
}
