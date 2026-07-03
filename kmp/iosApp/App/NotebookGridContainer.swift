import SwiftUI

enum NotebookRowVirtualizationDebug {
    static var enabled = false

    private static var materializedRowIds: [String: Set<AnyHashable>] = [:]
    private static var totalRowCounts: [String: Int] = [:]
    private static var lastLogAt: [String: Date] = [:]

    static func rowAppeared<ID: Hashable>(pane: String, id: ID, totalRows: Int) {
        guard enabled else { return }
        materializedRowIds[pane, default: []].insert(AnyHashable(id))
        totalRowCounts[pane] = totalRows
        logIfDue(pane: pane)
    }

    static func rowDisappeared<ID: Hashable>(pane: String, id: ID) {
        guard enabled else { return }
        materializedRowIds[pane]?.remove(AnyHashable(id))
    }

    private static func logIfDue(pane: String) {
        let now = Date()
        if let last = lastLogAt[pane], now.timeIntervalSince(last) < 0.5 {
            return
        }
        lastLogAt[pane] = now
        let materialized = materializedRowIds[pane]?.count ?? 0
        let total = totalRowCounts[pane] ?? 0
        print("NotebookPerf virtualization pane=\(pane) materialized=\(materialized) totalRows=\(total)")
    }
}

@MainActor
final class NotebookRowHoverModel: ObservableObject {
    @Published var hoveredRowId: AnyHashable?
}

struct NotebookGridContainer<
    Row: Identifiable,
    EmptyContent: View,
    FilteredEmptyContent: View,
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
    let hasUnfilteredRows: Bool
    let surfaceMode: NotebookSurfaceMode
    let fixedColumnWidth: CGFloat
    let trailingFixedColumnWidth: CGFloat
    let isFixedColumnResizing: Bool
    let topAccessoryHeight: CGFloat
    let headerHeight: CGFloat
    let rowHeight: CGFloat
    let emptyContent: () -> EmptyContent
    let filteredEmptyContent: () -> FilteredEmptyContent
    let seatingContent: ([Row]) -> SeatingContent
    let topAccessory: () -> TopAccessory
    let dividerHandle: () -> DividerHandle
    let fixedHeader: () -> FixedHeader
    let trailingFixedHeader: () -> TrailingFixedHeader
    let scrollHeader: () -> ScrollHeader
    let fixedRow: (Int, Row) -> FixedRow
    let trailingFixedRow: (Int, Row) -> TrailingFixedRow
    let scrollRow: (Int, Row) -> ScrollRow

    @StateObject private var hoverModel = NotebookRowHoverModel()

    var body: some View {
        if rows.isEmpty && !hasUnfilteredRows {
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
                rowStack(pane: "fixed", rows: rows, rowContent: fixedRow)
            } trailingFixedRows: {
                rowStack(pane: "trailing", rows: rows, rowContent: trailingFixedRow)
            } scrollRows: {
                if rows.isEmpty {
                    filteredEmptyContent()
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    rowStack(pane: "scroll", rows: rows, rowContent: scrollRow)
                }
            }
        }
    }

    private func rowStack<Content: View>(
        pane: String,
        rows: [Row],
        @ViewBuilder rowContent: @escaping (Int, Row) -> Content
    ) -> some View {
        let rowIndexesById = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })
        let totalRows = rows.count

        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { item in
                NotebookHoverableRow(rowId: AnyHashable(item.id), rowHeight: rowHeight, hoverModel: hoverModel) {
                    rowContent(rowIndexesById[item.id] ?? 0, item)
                }
                .onAppear {
                    NotebookRowVirtualizationDebug.rowAppeared(pane: pane, id: item.id, totalRows: totalRows)
                }
                .onDisappear {
                    NotebookRowVirtualizationDebug.rowDisappeared(pane: pane, id: item.id)
                }
            }
        }
        .padding(.bottom, 16)
    }
}

/// Fila hoja del grid: es la única unidad que se invalida al pasar el ratón,
/// en vez del `NotebookGridContainer` ancestro (que renderiza los 3 paneles).
private struct NotebookHoverableRow<Content: View>: View {
    let rowId: AnyHashable
    let rowHeight: CGFloat
    @ObservedObject var hoverModel: NotebookRowHoverModel
    @ViewBuilder let content: () -> Content

    private var isHovered: Bool {
        hoverModel.hoveredRowId == rowId
    }

    var body: some View {
        content()
            .frame(height: rowHeight)
            .background(isHovered ? hoverColor : Color.clear)
            .contentShape(Rectangle())
            #if os(macOS)
            .onHover { hovering in
                hoverModel.hoveredRowId = hovering ? rowId : nil
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
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var hoverColor: Color {
        #if os(macOS)
        return Color.primary.opacity(0.035)
        #else
        return Color.primary.opacity(0.02)
        #endif
    }
}
