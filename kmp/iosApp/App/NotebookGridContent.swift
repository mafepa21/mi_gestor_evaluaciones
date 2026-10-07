import SwiftUI
import MiGestorKit

struct NotebookGridContent<
    EmptyContent: View,
    FilterEmptyContent: View,
    SeatingContent: View,
    TopAccessory: View,
    DividerHandle: View,
    HeaderContent: View,
    RowContent: View
>: View {
    let rows: [NotebookTableRow]
    let hasSourceRows: Bool
    let surfaceMode: NotebookSurfaceMode
    let fixedColumnWidth: CGFloat
    let trailingFixedColumnWidth: CGFloat
    let isFixedColumnResizing: Bool
    let topAccessoryHeight: CGFloat
    let headerHeight: CGFloat
    let rowHeight: CGFloat
    let structuralInvalidationKey: String
    let rowReloadRevisions: [Int64: Int]
    let transientCellIds: Set<String>
    /// Resumen barato del contexto que afecta al pintado de una fila (rango, zebra, resaltados, riesgo, lesión...).
    let rowContextDigest: (Int, NotebookTableRow) -> Int
    let scrollProxy: NotebookGridScrollProxy?
    let fixedSegments: [NotebookDisplaySegment]
    let trailingFixedSegments: [NotebookDisplaySegment]
    let scrollableSegments: [NotebookDisplaySegment]
    let emptyContent: () -> EmptyContent
    let filterEmptyContent: () -> FilterEmptyContent
    let seatingContent: ([NotebookTableRow]) -> SeatingContent
    let topAccessory: () -> TopAccessory
    let dividerHandle: () -> DividerHandle
    let header: ([NotebookDisplaySegment]) -> HeaderContent
    let rowContent: (Int, NotebookTableRow, [NotebookDisplaySegment]) -> RowContent

    var body: some View {
        let fixedSegmentKey = Self.segmentKey(for: fixedSegments)

        let trailingFixedSegmentKey = Self.segmentKey(for: trailingFixedSegments)

        let scrollableSegmentKey = Self.segmentKey(for: scrollableSegments)

        let rowFingerprintProvider = NotebookRowFingerprintProvider(
            rows: rows,
            panes: [
                NotebookRowFingerprintPane(segmentKey: fixedSegmentKey, segments: fixedSegments),
                NotebookRowFingerprintPane(segmentKey: trailingFixedSegmentKey, segments: trailingFixedSegments),
                NotebookRowFingerprintPane(segmentKey: scrollableSegmentKey, segments: scrollableSegments)
            ],
            rowReloadRevisions: rowReloadRevisions,
            transientCellIds: transientCellIds,
            rowContextDigest: rowContextDigest,
            structuralInvalidationKey: structuralInvalidationKey
        )

        NotebookGridContainer(
            rows: rows,
            hasSourceRows: hasSourceRows,
            surfaceMode: surfaceMode,
            fixedColumnWidth: fixedColumnWidth,
            trailingFixedColumnWidth: trailingFixedColumnWidth,
            isFixedColumnResizing: isFixedColumnResizing,
            topAccessoryHeight: topAccessoryHeight,
            headerHeight: headerHeight,
            rowHeight: rowHeight,
            groupHeaderInfo: { row in
                (isFirst: row.isFirstInGroup, groupName: row.groupName, count: row.groupMemberCount)
            },
            scrollProxy: scrollProxy
        ) {
            emptyContent()
        } filterEmptyContent: {
            filterEmptyContent()
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
            NotebookEquatableGridRow(signature: rowFingerprintProvider.signature(index: index, item: item, segmentKey: fixedSegmentKey)) {
                rowContent(index, item, fixedSegments)
            }
            .equatable()
        } trailingFixedRow: { index, item in
            NotebookEquatableGridRow(signature: rowFingerprintProvider.signature(index: index, item: item, segmentKey: trailingFixedSegmentKey)) {
                rowContent(index, item, trailingFixedSegments)
            }
            .equatable()
        } scrollRow: { index, item in
            NotebookEquatableGridRow(signature: rowFingerprintProvider.signature(index: index, item: item, segmentKey: scrollableSegmentKey)) {
                rowContent(index, item, scrollableSegments)
            }
            .equatable()
        }
    }

    private static func segmentKey(for segments: [NotebookDisplaySegment]) -> String {
        segments.map(\.id).joined(separator: ",")
    }
}

private struct NotebookRowFingerprintPane {
    let segmentKey: String
    let visibleColumnIds: [String]

    init(segmentKey: String, segments: [NotebookDisplaySegment]) {
        self.segmentKey = segmentKey
        self.visibleColumnIds = Self.visibleColumnIds(for: segments).sorted()
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
}

private final class NotebookRowFingerprintProvider {
    private struct Key: Hashable {
        let studentId: Int64
        let segmentKey: String
    }

    private let rowsByStudentId: [Int64: NotebookTableRow]
    private let panesBySegmentKey: [String: NotebookRowFingerprintPane]
    private let rowReloadRevisions: [Int64: Int]
    private let transientDigestByStudentId: [Int64: String]
    private let rowContextDigest: (Int, NotebookTableRow) -> Int
    private let structuralInvalidationKey: String
    private var signatures: [Key: Int] = [:]

    init(
        rows: [NotebookTableRow],
        panes: [NotebookRowFingerprintPane],
        rowReloadRevisions: [Int64: Int],
        transientCellIds: Set<String>,
        rowContextDigest: @escaping (Int, NotebookTableRow) -> Int,
        structuralInvalidationKey: String
    ) {
        self.rowContextDigest = rowContextDigest
        self.rowsByStudentId = Dictionary(rows.map { ($0.student.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.panesBySegmentKey = Dictionary(panes.map { ($0.segmentKey, $0) }, uniquingKeysWith: { first, _ in first })
        self.rowReloadRevisions = rowReloadRevisions
        self.transientDigestByStudentId = Self.transientDigestByStudentId(transientCellIds)
        self.structuralInvalidationKey = structuralInvalidationKey
    }

    func signature(index: Int, item: NotebookTableRow, segmentKey: String) -> Int {
        let studentId = item.student.id
        let key = Key(studentId: studentId, segmentKey: segmentKey)
        if let cached = signatures[key] {
            return cached
        }
        guard let item = rowsByStudentId[studentId], let pane = panesBySegmentKey[segmentKey] else {
            var fallback = Hasher()
            fallback.combine(studentId)
            fallback.combine(segmentKey)
            let value = fallback.finalize()
            signatures[key] = value
            return value
        }

        var hasher = Hasher()
        hasher.combine(studentId)
        hasher.combine(item.row.weightedAverage?.doubleValue)
        hasher.combine(segmentKey)
        hasher.combine(transientDigestByStudentId[studentId] ?? "")
        hasher.combine(rowReloadRevisions[studentId, default: 0])
        hasher.combine(rowContextDigest(index, item))
        hasher.combine(structuralInvalidationKey)

        let lookup = item.lookup
        for colId in pane.visibleColumnIds {
            if let cell = lookup.cellsByColumnId[colId] {
                hasher.combine(cell.columnId)
                hasher.combine(cell.textValue)
                hasher.combine(cell.displayValue)
                hasher.combine(cell.iconValue)
                hasher.combine(cell.annotation?.icon)
                hasher.combine(cell.annotation?.note)
                hasher.combine(cell.annotation?.attachmentUris.count ?? 0)
                hasher.combine(cell.ordinalValue)
                hasher.combine(cell.boolValue?.boolValue == true)
            }
            if let grade = lookup.gradesByColumnId[colId] {
                hasher.combine(grade.columnId)
                hasher.combine(grade.value?.doubleValue)
                hasher.combine(grade.evidencePath)
                hasher.combine(grade.rubricSelections)
            }
        }
        let value = hasher.finalize()
        signatures[key] = value
        return value
    }

    private static func transientDigestByStudentId(_ transientCellIds: Set<String>) -> [Int64: String] {
        var grouped: [Int64: [String]] = [:]
        for cellId in transientCellIds {
            guard let separatorIndex = cellId.firstIndex(of: "|"),
                  let studentId = Int64(cellId[..<separatorIndex]) else {
                continue
            }
            grouped[studentId, default: []].append(cellId)
        }
        return grouped.mapValues { $0.sorted().joined(separator: "|") }
    }
}

private struct NotebookEquatableGridRow<Content: View>: View, Equatable {
    let signature: Int
    let content: () -> Content

    var body: some View {
        content()
    }

    static func == (lhs: NotebookEquatableGridRow<Content>, rhs: NotebookEquatableGridRow<Content>) -> Bool {
        lhs.signature == rhs.signature
    }
}
