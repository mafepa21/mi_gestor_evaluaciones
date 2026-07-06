import SwiftUI

struct NotebookGridContainer<
    Row: Identifiable,
    EmptyContent: View,
    SeatingContent: View,
    TopAccessory: View,
    DividerHandle: View,
    FixedHeader: View,
    TrailingFixedHeader: View,
    ScrollHeader: View,
    FixedRow: View,
    TrailingFixedRow: View,
    ScrollRow: View
>: View {
    let rows: [Row]
    let surfaceMode: NotebookSurfaceMode
    let fixedColumnWidth: CGFloat
    let trailingFixedColumnWidth: CGFloat
    let isFixedColumnResizing: Bool
    let topAccessoryHeight: CGFloat
    let headerHeight: CGFloat
    let rowHeight: CGFloat
    let emptyContent: () -> EmptyContent
    let seatingContent: ([Row]) -> SeatingContent
    let topAccessory: () -> TopAccessory
    let dividerHandle: () -> DividerHandle
    let fixedHeader: () -> FixedHeader
    let trailingFixedHeader: () -> TrailingFixedHeader
    let scrollHeader: () -> ScrollHeader
    let fixedRow: (Int, Row) -> FixedRow
    let trailingFixedRow: (Int, Row) -> TrailingFixedRow
    let scrollRow: (Int, Row) -> ScrollRow

    @State private var hoveredRowId: Row.ID? = nil
    @Environment(\.uiFeatureFlags) private var uiFeatureFlags

    var body: some View {
        if rows.isEmpty {
            emptyContent()
        } else if surfaceMode == .seatingPlan {
            seatingContent(rows)
        } else {
            NotebookDataGrid(
                fixedColumnWidth: fixedColumnWidth,
                trailingFixedColumnWidth: trailingFixedColumnWidth,
                isFixedColumnResizing: isFixedColumnResizing,
                topAccessoryHeight: topAccessoryHeight,
                headerHeight: headerHeight
            ) {
                Color.clear
            } dividerHandle: {
                dividerHandle()
            } trailingFixedTopAccessory: {
                Color.clear
            } scrollTopAccessory: {
                topAccessory()
            } fixedHeader: {
                fixedHeader()
            } trailingFixedHeader: {
                trailingFixedHeader()
            } scrollHeader: {
                scrollHeader()
            } fixedRows: {
                rowStack(rows: rows, rowContent: fixedRow)
            } trailingFixedRows: {
                rowStack(rows: rows, rowContent: trailingFixedRow)
            } scrollRows: {
                rowStack(rows: rows, rowContent: scrollRow)
            }
        }
    }

    private func rowStack<Content: View>(
        rows: [Row],
        @ViewBuilder rowContent: @escaping (Int, Row) -> Content
    ) -> some View {
        let rowIndexesById = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })

        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { item in
                let isHovered = hoveredRowId == item.id
                rowContent(rowIndexesById[item.id] ?? 0, item)
                    .frame(height: rowHeight)
                    .background(isHovered ? hoverColor : Color.clear)
                    .contentShape(Rectangle())
                    #if os(macOS)
                    .onHover { hovering in
                        withAnimation(uiFeatureFlags.animation(.easeOut(duration: 0.12))) {
                            hoveredRowId = hovering ? item.id : nil
                        }
                    }
                    #endif
                    .overlay(
                        VStack {
                            Spacer()
                            Rectangle()
                                .fill(NotebookStyle.softBorder.opacity(0.45))
                                .frame(height: 0.5)
                                .padding(.horizontal, 16)
                        }
                    )
            }
        }
        .padding(.bottom, 16)
    }

    private var hoverColor: Color {
        #if os(macOS)
        return Color.primary.opacity(0.035)
        #else
        return Color.primary.opacity(0.02)
        #endif
    }
}
