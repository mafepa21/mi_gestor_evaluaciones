import SwiftUI

struct NotebookGridContainer<
    Row: Identifiable,
    EmptyContent: View,
    SeatingContent: View,
    TopAccessory: View,
    DividerHandle: View,
    FixedHeader: View,
    ScrollHeader: View,
    FixedRow: View,
    ScrollRow: View
>: View {
    let rows: [Row]
    let surfaceMode: NotebookSurfaceMode
    let fixedColumnWidth: CGFloat
    let topAccessoryHeight: CGFloat
    let headerHeight: CGFloat
    let rowHeight: CGFloat
    let emptyContent: () -> EmptyContent
    let seatingContent: ([Row]) -> SeatingContent
    let topAccessory: () -> TopAccessory
    let dividerHandle: () -> DividerHandle
    let fixedHeader: () -> FixedHeader
    let scrollHeader: () -> ScrollHeader
    let fixedRow: (Int, Row) -> FixedRow
    let scrollRow: (Int, Row) -> ScrollRow

    var body: some View {
        if rows.isEmpty {
            emptyContent()
        } else if surfaceMode == .seatingPlan {
            seatingContent(rows)
        } else {
            NotebookDataGrid(
                fixedColumnWidth: fixedColumnWidth,
                topAccessoryHeight: topAccessoryHeight,
                headerHeight: headerHeight
            ) {
                Color.clear
            } dividerHandle: {
                dividerHandle()
            } scrollTopAccessory: {
                topAccessory()
            } fixedHeader: {
                fixedHeader()
            } scrollHeader: {
                scrollHeader()
            } fixedRows: {
                rowStack(rows: rows, rowContent: fixedRow)
            } scrollRows: {
                rowStack(rows: rows, rowContent: scrollRow)
            }
        }
    }

    private func rowStack<Content: View>(
        rows: [Row],
        @ViewBuilder rowContent: @escaping (Int, Row) -> Content
    ) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                rowContent(index, item)
                    .frame(height: rowHeight)
                Divider()
                    .frame(height: 0.5)
                    .overlay(NotebookStyle.softBorder.opacity(0.45))
                    .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 16)
    }
}
