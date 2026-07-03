import SwiftUI
import MiGestorKit

extension NotebookModuleView {
    func openInspectorForSelection(_ data: NotebookUiStateData) {
        if inspectorSelection != nil { return }
        if let firstColumn = managedColumns(data: data).first,
           let firstRow = filteredRows(data: data).first {
            inspectorSelection = NotebookInspectorSelection(studentId: firstRow.student.id, columnId: firstColumn.id)
            focusMode = .reviewing
        }
    }

    func openInspectorForStudent(_ studentId: Int64, data: NotebookUiStateData) {
        if let existingSelection = inspectorSelection,
           existingSelection.studentId == studentId,
           !existingSelection.columnId.isEmpty {
            inspectorSelection = existingSelection
        } else if let firstColumn = managedColumns(data: data).first {
            inspectorSelection = NotebookInspectorSelection(studentId: studentId, columnId: firstColumn.id)
        }
        isInspectorPresented = true
        focusMode = .reviewing
    }

    func evaluationTitle(for column: NotebookColumnDefinition) -> String {
        guard let evaluationId = column.evaluationId?.int64Value else { return "Sin evaluación asociada" }
        if let schoolClass = currentClass,
           let evaluation = bridge.evaluationsInClass.first(where: { $0.id == evaluationId }),
           !bridge.evaluationsInClass.isEmpty {
            return "\(evaluation.name) · \(schoolClass.name)"
        }
        return "Evaluación #\(evaluationId)"
    }

    func rubricTitle(for column: NotebookColumnDefinition) -> String {
        guard let rubricId = column.rubricId?.int64Value else { return "Sin rúbrica asociada" }
        return bridge.rubrics.first(where: { $0.rubric.id == rubricId })?.rubric.name ?? "Rúbrica #\(rubricId)"
    }

    func clearNotebookFilters() {
        searchText = ""
        selectedGroupId = nil
        groupByWorkGroupMode = "none"
    }

    func filteredRows(data: NotebookUiStateData) -> [NotebookTableRow] {
        gridLayoutModel.visibleRows(
            data: data,
            activeTabId: activeNotebookTabId(data: data),
            groupByWorkGroupMode: groupByWorkGroupMode,
            searchText: searchText,
            selectedGroupId: selectedGroupId,
            renderCacheKey: notebookRenderCacheKey(data: data)
        )
    }

    func notebookRenderCacheKey(data: NotebookUiStateData) -> NotebookRenderCacheKey {
        NotebookRenderCacheKey(
            classId: data.sheet.classId,
            activeTabId: activeNotebookTabId(data: data),
            searchText: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
            hiddenColumnsRevision: notebookHiddenColumnsRevision(data: data),
            structuralRevision: structuralGridRevision
        )
    }

    func notebookHiddenColumnsRevision(data: NotebookUiStateData) -> Int {
        data.sheet.columns
            .map { "\($0.id):\($0.visibility):\($0.isHidden):\($0.isArchived)" }
            .sorted()
            .reduce(17) { partial, part in
                partial &* 31 &+ part.hashValue
            }
    }

    func cellAlignment(for segment: NotebookDisplaySegment) -> Alignment {
        switch segment {
        case .fixed(let fixed):
            return fixed == .photo ? .center : .leading
        case .collapsedCategory:
            return .leading
        case .column:
            return .center
        }
    }

    @MainActor
    func notebookRowView(
        item: NotebookTableRow,
        data: NotebookUiStateData,
        segments: [NotebookDisplaySegment],
        rowIndex: Int,
        allRows: [NotebookTableRow],
        navigableSegments: [NotebookDisplaySegment]
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if segments.isEmpty {
                emptyNotebookCellPlaceholder(width: 180)
            } else {
                ForEach(segments, id: \.id) { segment in
                    rowCell(
                        for: segment,
                        item: item,
                        data: data,
                        rowIndex: rowIndex,
                        allRows: allRows,
                        navigableSegments: navigableSegments
                    )
                    .frame(width: segmentWidth(segment), height: notebookGridRowHeight, alignment: cellAlignment(for: segment))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: notebookGridRowHeight, alignment: .center)
        .padding(.horizontal, 16)
        .background(
            (rowIndex.isMultiple(of: 2) ? NotebookStyle.surfaceSoft.opacity(0.38) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            inspectorSelection?.studentId == item.student.id ? NotebookStyle.primaryTint.opacity(0.18) : .clear,
                            lineWidth: 1
                        )
                )
        )
    }

    func emptyNotebookCellPlaceholder(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(NotebookStyle.surfaceSoft.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(NotebookStyle.softBorder.opacity(0.65), lineWidth: 0.8)
            )
            .frame(width: width, height: 44)
            .frame(height: notebookGridRowHeight, alignment: .center)
    }

    func groupedRows(data: NotebookUiStateData) -> [NotebookWorkGroup] {
        let activeTabId = activeNotebookTabId(data: data)
        return data.sheet.workGroups
            .filter { activeTabId == nil || $0.tabId == activeTabId }
            .sorted { $0.order < $1.order }
    }

    func groupId(for studentId: Int64, in data: NotebookUiStateData) -> Int64? {
        let activeTabId = activeNotebookTabId(data: data)
        return data.sheet.workGroupMembers
            .first(where: { $0.studentId == studentId && (activeTabId == nil || $0.tabId == activeTabId) })?
            .groupId
    }

    func groupName(for groupId: Int64, in data: NotebookUiStateData) -> String? {
        let activeTabId = activeNotebookTabId(data: data)
        return data.sheet.workGroups
            .first(where: { $0.id == groupId && (activeTabId == nil || $0.tabId == activeTabId) })?
            .name
    }

    func memberCount(_ groupId: Int64, in data: NotebookUiStateData) -> Int {
        let activeTabId = activeNotebookTabId(data: data)
        return data.sheet.workGroupMembers
            .filter { $0.groupId == groupId && (activeTabId == nil || $0.tabId == activeTabId) }
            .count
    }

    func columns(in category: NotebookColumnCategory, data: NotebookUiStateData, includeHidden: Bool = false) -> [NotebookColumnDefinition] {
        gridLayoutModel.columns(
            in: category,
            data: data,
            activeTabId: activeNotebookTabId(data: data),
            viewPreset: viewPreset,
            includeHidden: includeHidden
        )
    }

    func managedColumns(data: NotebookUiStateData) -> [NotebookColumnDefinition] {
        gridLayoutModel.managedColumns(
            data: data,
            activeTabId: activeNotebookTabId(data: data),
            viewPreset: viewPreset
        )
    }

    func relevantCategories(data: NotebookUiStateData) -> [NotebookColumnCategory] {
        gridLayoutModel.relevantCategories(
            data: data,
            activeTabId: activeNotebookTabId(data: data),
            viewPreset: viewPreset
        )
    }

    func visibleCategories(data: NotebookUiStateData) -> [NotebookColumnCategory] {
        gridLayoutModel.visibleCategories(
            data: data,
            activeTabId: activeNotebookTabId(data: data)
        )
    }

    func displaySegments(data: NotebookUiStateData) -> [NotebookDisplaySegment] {
        gridLayoutModel.displaySegments(
            data: data,
            activeTabId: activeNotebookTabId(data: data),
            viewPreset: viewPreset
        )
    }

    func notebookSourceColumns(data: NotebookUiStateData) -> [NotebookColumnDefinition] {
        managedColumns(data: data)
    }

    func visibleNotebookSourceColumns(data: NotebookUiStateData) -> [NotebookColumnDefinition] {
        let renderModel = gridLayoutModel.renderModelCached(
            key: notebookRenderCacheKey(data: data),
            data: data,
            viewPreset: viewPreset,
            isCompact: isCompact
        )
        let segments = renderModel.fixedSegments + renderModel.scrollableSegments + renderModel.trailingFixedSegments
        return segments.compactMap { segment in
            guard case .column(let column) = segment else { return nil }
            return column
        }
    }

    func notebookEvidenceSourceColumns(_ columns: [NotebookColumnDefinition]) -> [NotebookColumnDefinition] {
        columns.filter { !isNotebookIndividualSummaryColumn($0) }
    }

    func selectedNotebookAIStudentIds(in data: NotebookUiStateData) -> [Int64] {
        if let selectedStudentId {
            return [selectedStudentId]
        }
        if let inspectorSelection {
            return [inspectorSelection.studentId]
        }
        return filteredRows(data: data).map(\.student.id)
    }

}
