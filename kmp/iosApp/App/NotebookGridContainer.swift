import SwiftUI

struct NotebookGridContainer<
    Row: Identifiable,
    EmptyContent: View,
    FilterEmptyContent: View,
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
    let hasSourceRows: Bool
    let surfaceMode: NotebookSurfaceMode
    let fixedColumnWidth: CGFloat
    let trailingFixedColumnWidth: CGFloat
    let isFixedColumnResizing: Bool
    let topAccessoryHeight: CGFloat
    let headerHeight: CGFloat
    let rowHeight: CGFloat
    let emptyContent: () -> EmptyContent
    let filterEmptyContent: () -> FilterEmptyContent
    let seatingContent: ([Row]) -> SeatingContent
    let topAccessory: () -> TopAccessory
    let dividerHandle: () -> DividerHandle
    let fixedHeader: () -> FixedHeader
    let trailingFixedHeader: () -> TrailingFixedHeader
    let scrollHeader: () -> ScrollHeader
    let fixedRow: (Int, Row) -> FixedRow
    let trailingFixedRow: (Int, Row) -> TrailingFixedRow
    let scrollRow: (Int, Row) -> ScrollRow

    let groupHeaderHeight: CGFloat
    let groupHeaderInfo: ((Row) -> (isFirst: Bool, groupName: String, count: Int))?

    init(
        rows: [Row],
        hasSourceRows: Bool,
        surfaceMode: NotebookSurfaceMode,
        fixedColumnWidth: CGFloat,
        trailingFixedColumnWidth: CGFloat,
        isFixedColumnResizing: Bool,
        topAccessoryHeight: CGFloat,
        headerHeight: CGFloat,
        rowHeight: CGFloat,
        groupHeaderHeight: CGFloat = 34,
        groupHeaderInfo: ((Row) -> (isFirst: Bool, groupName: String, count: Int))? = nil,
        @ViewBuilder emptyContent: @escaping () -> EmptyContent,
        @ViewBuilder filterEmptyContent: @escaping () -> FilterEmptyContent,
        @ViewBuilder seatingContent: @escaping ([Row]) -> SeatingContent,
        @ViewBuilder topAccessory: @escaping () -> TopAccessory,
        @ViewBuilder dividerHandle: @escaping () -> DividerHandle,
        @ViewBuilder fixedHeader: @escaping () -> FixedHeader,
        @ViewBuilder trailingFixedHeader: @escaping () -> TrailingFixedHeader,
        @ViewBuilder scrollHeader: @escaping () -> ScrollHeader,
        @ViewBuilder fixedRow: @escaping (Int, Row) -> FixedRow,
        @ViewBuilder trailingFixedRow: @escaping (Int, Row) -> TrailingFixedRow,
        @ViewBuilder scrollRow: @escaping (Int, Row) -> ScrollRow
    ) {
        self.rows = rows
        self.hasSourceRows = hasSourceRows
        self.surfaceMode = surfaceMode
        self.fixedColumnWidth = fixedColumnWidth
        self.trailingFixedColumnWidth = trailingFixedColumnWidth
        self.isFixedColumnResizing = isFixedColumnResizing
        self.topAccessoryHeight = topAccessoryHeight
        self.headerHeight = headerHeight
        self.rowHeight = rowHeight
        self.groupHeaderHeight = groupHeaderHeight
        self.groupHeaderInfo = groupHeaderInfo
        self.emptyContent = emptyContent
        self.filterEmptyContent = filterEmptyContent
        self.seatingContent = seatingContent
        self.topAccessory = topAccessory
        self.dividerHandle = dividerHandle
        self.fixedHeader = fixedHeader
        self.trailingFixedHeader = trailingFixedHeader
        self.scrollHeader = scrollHeader
        self.fixedRow = fixedRow
        self.trailingFixedRow = trailingFixedRow
        self.scrollRow = scrollRow
    }

    @StateObject private var scrollSyncCoordinator = NotebookScrollSyncCoordinator()

    var body: some View {
        if !hasSourceRows {
            emptyContent()
        } else if rows.isEmpty && surfaceMode == .seatingPlan {
            filterEmptyContent()
        } else if surfaceMode == .seatingPlan {
            seatingContent(rows)
        } else {
            NotebookDataGrid(
                scrollSyncCoordinator: scrollSyncCoordinator,
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
                rowStack(rows: rows, pane: .fixed, rowContent: fixedRow)
            } trailingFixedRows: {
                rowStack(rows: rows, pane: .trailingFixed, rowContent: trailingFixedRow)
            } scrollRows: {
                rowStack(rows: rows, pane: .scroll, rowContent: scrollRow)
            }
            .overlay {
                if rows.isEmpty {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: topAccessoryHeight + headerHeight)
                            .allowsHitTesting(false)
                        filterEmptyContent()
                    }
                }
            }
        }
    }

    private enum PaneKind {
        case fixed
        case trailingFixed
        case scroll

        var debugName: String {
            switch self {
            case .fixed: return "fixed"
            case .trailingFixed: return "trailing"
            case .scroll: return "scroll"
            }
        }
    }

    private func rowStack<Content: View>(
        rows: [Row],
        pane: PaneKind,
        @ViewBuilder rowContent: @escaping (Int, Row) -> Content
    ) -> some View {
        NotebookWindowedRowStack(
            viewport: scrollSyncCoordinator,
            rows: rows,
            paneName: pane.debugName,
            rowHeight: rowHeight,
            groupHeaderHeight: groupHeaderHeight,
            groupHeaderInfo: groupHeaderInfo,
            groupHeader: { header in
                groupHeaderView(for: header, pane: pane)
            },
            rowContent: rowContent
        )

    }

    @ViewBuilder
    private func groupHeaderView(for header: (isFirst: Bool, groupName: String, count: Int), pane: PaneKind) -> some View {
        let isUngrouped = header.groupName == "Sin grupo"
        switch pane {
        case .fixed:
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: isUngrouped ? "person.slash" : "person.2.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isUngrouped ? Color.secondary : NotebookStyle.primaryTint)

                    Text(header.groupName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isUngrouped ? Color.secondary : Color.primary)
                        .lineLimit(1)

                    if header.count > 0 {
                        Text("\(header.count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isUngrouped ? Color.secondary : NotebookStyle.primaryTint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule().fill(isUngrouped ? Color.secondary.opacity(0.12) : NotebookStyle.primaryTint.opacity(0.14))
                            )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isUngrouped ? Color.secondary.opacity(0.08) : NotebookStyle.primaryTint.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isUngrouped ? Color.secondary.opacity(0.15) : NotebookStyle.primaryTint.opacity(0.25), lineWidth: 0.5)
                )

                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: groupHeaderHeight)
            .background(appSecondarySystemBackgroundColor().opacity(0.75))
            .overlay(
                VStack {
                    Rectangle()
                        .fill(NotebookGridStyle.gridLine)
                        .frame(height: 0.5)
                    Spacer()
                    Rectangle()
                        .fill(NotebookGridStyle.gridLine)
                        .frame(height: 0.5)
                }
            )

        case .scroll, .trailingFixed:
            HStack {
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .frame(height: groupHeaderHeight)
            .background(appSecondarySystemBackgroundColor().opacity(0.75))
            .overlay(
                VStack {
                    Rectangle()
                        .fill(NotebookGridStyle.gridLine)
                        .frame(height: 0.5)
                    Spacer()
                    Rectangle()
                        .fill(NotebookGridStyle.gridLine)
                        .frame(height: 0.5)
                }
            )
        }
    }
}

private struct NotebookWindowedRow<Row: Identifiable>: Identifiable {
    let index: Int
    let row: Row
    var id: Row.ID { row.id }
}

private struct NotebookWindowedRowStack<
    Row: Identifiable,
    Header: View,
    Content: View
>: View {
    @ObservedObject var viewport: NotebookScrollSyncCoordinator
    let rows: [Row]
    let paneName: String
    let rowHeight: CGFloat
    let groupHeaderHeight: CGFloat
    let groupHeaderInfo: ((Row) -> (isFirst: Bool, groupName: String, count: Int))?
    let groupHeader: ((isFirst: Bool, groupName: String, count: Int)) -> Header
    let rowContent: (Int, Row) -> Content

    var body: some View {
        let metrics = currentMetrics
        let range = NotebookRowWindowMath.clamped(viewport.visibleRange, count: rows.count)
        let topInset = metrics.prefixY.indices.contains(range.lowerBound) ? metrics.prefixY[range.lowerBound] : 0
        let visibleRows = range.map { NotebookWindowedRow(index: $0, row: rows[$0]) }

        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: metrics.totalHeight)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(visibleRows) { entry in
                    rowSlot(entry)
                }
            }
            .padding(.top, topInset)
        }
        .frame(height: metrics.totalHeight, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .onAppear {
            viewport.install(metrics: metrics)
        }
        .appOnChange(of: metrics) { newMetrics in
            viewport.install(metrics: newMetrics)
        }
    }

    private var currentMetrics: NotebookRowWindowMath.Metrics {
        NotebookRowWindowMath.metrics(slotHeights: rows.map { slotHeight(for: $0) })
    }

    private func slotHeight(for item: Row) -> CGFloat {
        rowHeight + (showsGroupHeader(for: item) ? groupHeaderHeight : 0)
    }

    private func showsGroupHeader(for item: Row) -> Bool {
        guard let groupHeaderInfo else { return false }
        return groupHeaderInfo(item).isFirst
    }

    private func headerInfo(for item: Row) -> (isFirst: Bool, groupName: String, count: Int)? {
        guard let groupHeaderInfo else { return nil }
        return groupHeaderInfo(item)
    }

    @ViewBuilder
    private func rowSlot(_ entry: NotebookWindowedRow<Row>) -> some View {
        let header = headerInfo(for: entry.row)
        let showsHeader = header?.isFirst == true

        VStack(alignment: .leading, spacing: 0) {
            if showsHeader, let header {
                groupHeader(header)
            }
            NotebookGridHoverRow(rowHeight: rowHeight) {
                rowContent(entry.index, entry.row)
            }
        }
        .onAppear {
            NotebookRowVirtualizationDebug.appear(pane: paneName, totalRows: rows.count)
        }
        .onDisappear {
            NotebookRowVirtualizationDebug.disappear(pane: paneName, totalRows: rows.count)
        }
    }
}

private struct NotebookGridHoverRow<Content: View>: View {
    let rowHeight: CGFloat
    let content: Content

    @State private var isHovered = false

    init(rowHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.rowHeight = rowHeight
        self.content = content()
    }

    var body: some View {
        content
            .frame(height: rowHeight)
            .background(isHovered ? hoverColor : Color.clear)
            .contentShape(Rectangle())
            #if os(macOS)
            .onHover { hovering in
                // Sin animación: coincide con el comportamiento nativo de
                // NSTableView, que no anima su hover.
                isHovered = hovering
            }
            #endif
            .overlay(
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(NotebookGridStyle.gridLine)
                        .frame(height: 0.5)
                }
            )
    }

    private var hoverColor: Color {
        #if os(macOS)
        return NotebookGridStyle.rowHover
        #else
        return Color.primary.opacity(0.02)
        #endif
    }
}
