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
    let isFixedColumnResizing: Bool
    let topAccessoryHeight: CGFloat
    let headerHeight: CGFloat
    let rowHeight: CGFloat
    let rowInvalidationKey: String
    let transientCellIds: Set<String>
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
        let fixedSegmentKey = fixedSegments.map(\.id).joined(separator: ",")
        let fixedColumnIds = Self.visibleColumnIds(for: fixedSegments)

        let trailingFixedSegmentKey = trailingFixedSegments.map(\.id).joined(separator: ",")
        let trailingFixedColumnIds = Self.visibleColumnIds(for: trailingFixedSegments)

        let scrollableSegmentKey = scrollableSegments.map(\.id).joined(separator: ",")
        let scrollableColumnIds = Self.visibleColumnIds(for: scrollableSegments)

        NotebookGridContainer(
            rows: rows,
            surfaceMode: surfaceMode,
            fixedColumnWidth: fixedColumnWidth,
            trailingFixedColumnWidth: trailingFixedColumnWidth,
            isFixedColumnResizing: isFixedColumnResizing,
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
            NotebookEquatableGridRow(signature: rowSignature(index: index, item: item, segmentKey: fixedSegmentKey, visibleColumnIds: fixedColumnIds)) {
                rowContent(index, item, fixedSegments)
            }
        } trailingFixedRow: { index, item in
            NotebookEquatableGridRow(signature: rowSignature(index: index, item: item, segmentKey: trailingFixedSegmentKey, visibleColumnIds: trailingFixedColumnIds)) {
                rowContent(index, item, trailingFixedSegments)
            }
        } scrollRow: { index, item in
            NotebookEquatableGridRow(signature: rowSignature(index: index, item: item, segmentKey: scrollableSegmentKey, visibleColumnIds: scrollableColumnIds)) {
                rowContent(index, item, scrollableSegments)
            }
        }
    }

    private static func visibleColumnIds(for segments: [NotebookDisplaySegment]) -> Set<String> {
        Set(segments.compactMap { segment -> String? in
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
    }

    private func rowSignature(index: Int, item: NotebookTableRow, segmentKey: String, visibleColumnIds: Set<String>) -> String {
        guard !visibleColumnIds.isEmpty else {
            return [
                "\(item.student.id)",
                item.row.weightedAverage.map { "\($0.doubleValue)" } ?? "nil",
                segmentKey,
                rowInvalidationKey
            ].joined(separator: "¬")
        }

        let studentPrefix = "\(item.student.id)|"
        let transientCellDigest = transientCellIds
            .compactMap { cellId -> String? in
                guard cellId.hasPrefix(studentPrefix) else { return nil }
                let columnId = String(cellId.dropFirst(studentPrefix.count))
                return visibleColumnIds.contains(columnId) ? columnId : nil
            }
            .sorted()
            .joined(separator: "|")
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
                    grade.value.map { "\($0.doubleValue)" } ?? "",
                    grade.evidencePath ?? "",
                    grade.rubricSelections ?? ""
                ].joined(separator: ":")
            }
            .joined(separator: "|")
        let average = item.row.weightedAverage.map { "\($0.doubleValue)" } ?? "nil"
        return [
            "\(item.student.id)",
            average,
            segmentKey,
            transientCellDigest,
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
