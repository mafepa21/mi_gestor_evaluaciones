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
            }
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
            NotebookEquatableGridRow(signature: rowFingerprintProvider.signature(studentId: item.student.id, segmentKey: fixedSegmentKey)) {
                rowContent(index, item, fixedSegments)
            }
            .equatable()
        } trailingFixedRow: { index, item in
            NotebookEquatableGridRow(signature: rowFingerprintProvider.signature(studentId: item.student.id, segmentKey: trailingFixedSegmentKey)) {
                rowContent(index, item, trailingFixedSegments)
            }
            .equatable()
        } scrollRow: { index, item in
            NotebookEquatableGridRow(signature: rowFingerprintProvider.signature(studentId: item.student.id, segmentKey: scrollableSegmentKey)) {
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
    private let structuralInvalidationKey: String
    private var signatures: [Key: String] = [:]

    init(
        rows: [NotebookTableRow],
        panes: [NotebookRowFingerprintPane],
        rowReloadRevisions: [Int64: Int],
        transientCellIds: Set<String>,
        structuralInvalidationKey: String
    ) {
        self.rowsByStudentId = Dictionary(rows.map { ($0.student.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.panesBySegmentKey = Dictionary(panes.map { ($0.segmentKey, $0) }, uniquingKeysWith: { first, _ in first })
        self.rowReloadRevisions = rowReloadRevisions
        self.transientDigestByStudentId = Self.transientDigestByStudentId(transientCellIds)
        self.structuralInvalidationKey = structuralInvalidationKey
    }

    func signature(studentId: Int64, segmentKey: String) -> String {
        let key = Key(studentId: studentId, segmentKey: segmentKey)
        if let cached = signatures[key] {
            return cached
        }
        guard let item = rowsByStudentId[studentId], let pane = panesBySegmentKey[segmentKey] else {
            return "\(studentId)¬\(segmentKey)"
        }
        let visibleIds = Set(pane.visibleColumnIds)
        let value = Self.signature(
            studentId: studentId,
            average: item.row.weightedAverage.map { "\($0.doubleValue)" } ?? "nil",
            segmentKey: segmentKey,
            visibleColumnIds: pane.visibleColumnIds,
            transientRowDigest: transientDigestByStudentId[studentId] ?? "",
            cellDigestByColumnId: Self.cellDigestByColumnId(item.row.persistedCells, visibleIds: visibleIds),
            gradeDigestByColumnId: Self.gradeDigestByColumnId(item.row.persistedGrades, visibleIds: visibleIds),
            rowReloadRevision: rowReloadRevisions[studentId, default: 0],
            structuralInvalidationKey: structuralInvalidationKey
        )
        signatures[key] = value
        return value
    }

    private static func signature(
        studentId: Int64,
        average: String,
        segmentKey: String,
        visibleColumnIds: [String],
        transientRowDigest: String,
        cellDigestByColumnId: [String: String],
        gradeDigestByColumnId: [String: String],
        rowReloadRevision: Int,
        structuralInvalidationKey: String
    ) -> String {
        guard !visibleColumnIds.isEmpty else {
            return [
                "\(studentId)",
                average,
                segmentKey,
                transientRowDigest,
                "\(rowReloadRevision)",
                structuralInvalidationKey
            ].joined(separator: "¬")
        }

        let visibleCellDigest = visibleColumnIds
            .compactMap { cellDigestByColumnId[$0] }
            .joined(separator: "|")
        let visibleGradeDigest = visibleColumnIds
            .compactMap { gradeDigestByColumnId[$0] }
            .joined(separator: "|")
        return [
            "\(studentId)",
            average,
            segmentKey,
            transientRowDigest,
            visibleCellDigest,
            visibleGradeDigest,
            "\(rowReloadRevision)",
            structuralInvalidationKey
        ].joined(separator: "¬")
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

    private static func cellDigestByColumnId(_ cells: [PersistedNotebookCell], visibleIds: Set<String>) -> [String: String] {
        var digests: [String: String] = [:]
        digests.reserveCapacity(min(cells.count, visibleIds.count))
        for cell in cells where visibleIds.contains(cell.columnId) {
            digests[cell.columnId] = [
                cell.columnId,
                cell.textValue ?? "",
                cell.displayValue ?? "",
                cell.iconValue ?? "",
                cell.annotation?.icon ?? "",
                cell.annotation?.note ?? "",
                "\(cell.annotation?.attachmentUris.count ?? 0)",
                cell.boolValue?.boolValue == true ? "1" : "0"
            ].joined(separator: ":")
        }
        return digests
    }

    private static func gradeDigestByColumnId(_ grades: [Grade], visibleIds: Set<String>) -> [String: String] {
        var digests: [String: String] = [:]
        digests.reserveCapacity(min(grades.count, visibleIds.count))
        for grade in grades where visibleIds.contains(grade.columnId) {
            digests[grade.columnId] = [
                grade.columnId,
                grade.value.map { "\($0.doubleValue)" } ?? "",
                grade.evidencePath ?? "",
                grade.rubricSelections ?? ""
            ].joined(separator: ":")
        }
        return digests
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
