import SwiftUI
import MiGestorKit

struct NotebookGridContent<
    EmptyContent: View,
    FilteredEmptyContent: View,
    SeatingContent: View,
    TopAccessory: View,
    DividerHandle: View,
    HeaderContent: View,
    RowContent: View
>: View {
    let rows: [NotebookTableRow]
    let hasUnfilteredRows: Bool
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
    let filteredEmptyContent: () -> FilteredEmptyContent
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
            hasUnfilteredRows: hasUnfilteredRows,
            surfaceMode: surfaceMode,
            fixedColumnWidth: fixedColumnWidth,
            trailingFixedColumnWidth: trailingFixedColumnWidth,
            isFixedColumnResizing: isFixedColumnResizing,
            topAccessoryHeight: topAccessoryHeight,
            headerHeight: headerHeight,
            rowHeight: rowHeight
        ) {
            emptyContent()
        } filteredEmptyContent: {
            filteredEmptyContent()
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

private struct NotebookRowFingerprintProvider {
    private struct Key: Hashable {
        let studentId: Int64
        let segmentKey: String
    }

    private let signatures: [Key: String]

    init(
        rows: [NotebookTableRow],
        panes: [NotebookRowFingerprintPane],
        rowReloadRevisions: [Int64: Int],
        transientCellIds: Set<String>,
        structuralInvalidationKey: String
    ) {
        var signatures: [Key: String] = [:]
        signatures.reserveCapacity(rows.count * panes.count)

        let transientDigestByStudentId = Self.transientDigestByStudentId(transientCellIds)

        for item in rows {
            let studentId = item.student.id
            let rowReloadRevision = rowReloadRevisions[studentId, default: 0]
            let transientRowDigest = transientDigestByStudentId[studentId] ?? ""
            let average = item.row.weightedAverage.map { "\($0.doubleValue)" } ?? "nil"
            let cellDigestByColumnId = Self.cellDigestByColumnId(item.row.persistedCells)
            let gradeDigestByColumnId = Self.gradeDigestByColumnId(item.row.persistedGrades)

            for pane in panes {
                signatures[Key(studentId: studentId, segmentKey: pane.segmentKey)] = Self.signature(
                    studentId: studentId,
                    average: average,
                    segmentKey: pane.segmentKey,
                    visibleColumnIds: pane.visibleColumnIds,
                    transientRowDigest: transientRowDigest,
                    cellDigestByColumnId: cellDigestByColumnId,
                    gradeDigestByColumnId: gradeDigestByColumnId,
                    rowReloadRevision: rowReloadRevision,
                    structuralInvalidationKey: structuralInvalidationKey
                )
            }
        }

        self.signatures = signatures
    }

    func signature(studentId: Int64, segmentKey: String) -> String {
        signatures[Key(studentId: studentId, segmentKey: segmentKey)] ?? "\(studentId)¬\(segmentKey)"
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

    private static func cellDigestByColumnId(_ cells: [PersistedNotebookCell]) -> [String: String] {
        var digests: [String: String] = [:]
        digests.reserveCapacity(cells.count)
        for cell in cells {
            digests[cell.columnId] = [
                cell.columnId,
                cell.textValue ?? "",
                cell.displayValue ?? "",
                cell.iconValue ?? "",
                cell.boolValue?.boolValue == true ? "1" : "0"
            ].joined(separator: ":")
        }
        return digests
    }

    private static func gradeDigestByColumnId(_ grades: [Grade]) -> [String: String] {
        var digests: [String: String] = [:]
        digests.reserveCapacity(grades.count)
        for grade in grades {
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
